#!/system/bin/sh
# ==============================================================================
# Module: Auto-Brightness Clamp Fixer (Generic)
# Description: Detects and resets auto-brightness when clamped to 0 in dark environments
# Version: 3.0 (Universal)
# Platforms: OPLUS (ColorOS/OxygenOS), Xiaomi (HyperOS/MIUI), Samsung (OneUI), AOSP
# Usage: Can be triggered by Tasker/MacroDroid or run as daemon
# ==============================================================================

LOG_TAG="FixDeviceInfo_LuxFix"

COOLDOWN_SECONDS=120
DEBOUNCE_HITS=3
RATE_WINDOW_SECONDS=3600
RATE_MAX_TRIGGERS=3
SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
LAST_RUN_FILE=""
HITS_FILE=""
RATE_FILE=""
if [ -n "$SCRIPT_DIR" ]; then
    LAST_RUN_FILE="$SCRIPT_DIR/.fixdeviceinfo_luxfix_last_run"
    HITS_FILE="$SCRIPT_DIR/.fixdeviceinfo_luxfix_hits"
    RATE_FILE="$SCRIPT_DIR/.fixdeviceinfo_luxfix_rate"
fi

has_settings_cmd() {
    command -v settings >/dev/null 2>&1
}

is_int() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

get_backlight_dir() {
    local bl
    local base

    for bl in /sys/class/backlight/panel0-backlight /sys/class/backlight/panel1-backlight; do
        [ -d "$bl" ] || continue
        [ -f "$bl/brightness" ] || continue
        echo "$bl"
        return 0
    done

    for bl in /sys/class/backlight/*; do
        [ -d "$bl" ] || continue
        [ -f "$bl/brightness" ] || continue
        base="${bl##*/}"
        case "$base" in
            *panel*|*display*|*backlight*)
                echo "$bl"
                return 0
                ;;
        esac
    done

    for bl in /sys/class/backlight/*; do
        [ -d "$bl" ] || continue
        [ -f "$bl/brightness" ] || continue
        echo "$bl"
        return 0
    done

    return 1
}

# =============================================================================
# Configuration
# =============================================================================

# Determine threshold dynamically based on max_brightness
get_critical_threshold() {
    local bl_dir
    if ! bl_dir=$(get_backlight_dir); then
        echo 2
        return 0
    fi

    local max_brightness
    max_brightness=$(cat "$bl_dir/max_brightness" 2>/dev/null || echo 255)

    if ! is_int "$max_brightness"; then
        max_brightness=255
    fi
    
    # Set threshold to 1% of max (255→2, 4095→40)
    local threshold=$((max_brightness / 100))
    [ "$threshold" -lt 2 ] && threshold=2
    
    echo "$threshold"
}

CRITICAL_THRESHOLD=$(get_critical_threshold)

# =============================================================================
# Utility Functions
# =============================================================================

log_msg() {
    if [ -w /dev/kmsg ]; then
        echo "$LOG_TAG: $1" > /dev/kmsg
        return 0
    fi

    if command -v log >/dev/null 2>&1; then
        log -t "$LOG_TAG" "$1" 2>/dev/null || true
    fi
}

# Check if screen is on (0=on, 1=off)
is_screen_on() {
    local bl_dir
    bl_dir=$(get_backlight_dir) || return 1

    local bl_power
    bl_power=$(cat "$bl_dir/bl_power" 2>/dev/null)

    if [ -z "$bl_power" ]; then
        local v
        v=$(get_panel_brightness 2>/dev/null)
        if is_int "$v" && [ "$v" -gt 0 ]; then
            return 0
        fi
        return 1
    fi
    
    # bl_power: 0=on, 4=off (FB_BLANK_POWERDOWN)
    if [ "$bl_power" = "0" ]; then
        return 0
    fi

    if is_int "$bl_power" && [ "$bl_power" -ne 4 ]; then
        return 0
    fi

    return 1
}

# Check auto-brightness status (0=enabled, 1=disabled)
is_auto_brightness_enabled() {
    has_settings_cmd || return 1
    local mode
    mode=$(settings get system screen_brightness_mode 2>/dev/null)
    
    if [ "$mode" = "1" ]; then
        return 0
    else
        return 1
    fi
}

# Get framework brightness setting
get_setting_brightness() {
    has_settings_cmd || return 1
    settings get system screen_brightness 2>/dev/null
}

# Get physical backlight value
get_panel_brightness() {
    local bl_dir
    bl_dir=$(get_backlight_dir) || return 1

    if [ -r "$bl_dir/actual_brightness" ]; then
        cat "$bl_dir/actual_brightness" 2>/dev/null
        return 0
    fi

    cat "$bl_dir/brightness" 2>/dev/null
}

# =============================================================================
# Core Fix Logic
# =============================================================================

perform_soft_restart() {
    log_msg "Triggering Auto-Brightness Soft Restart..."

    has_settings_cmd || return 0

    local restore_needed=0
    trap 'if [ "$restore_needed" = "1" ]; then settings put system screen_brightness_mode 1 >/dev/null 2>&1 || true; fi' EXIT INT TERM HUP
    
    # 1. Switch to manual mode
    settings put system screen_brightness_mode 0 >/dev/null 2>&1 || true
    restore_needed=1
    
    # 2. Wait for state machine teardown (100ms)
    sleep 0.1 2>/dev/null || sleep 1
    
    # 3. Restore auto mode
    settings put system screen_brightness_mode 1 >/dev/null 2>&1 || true
    restore_needed=0
    trap - EXIT INT TERM HUP
    
    log_msg "Soft Restart Completed. Clamp should be cleared."
}

rate_limit_allows_trigger() {
    [ -n "$RATE_FILE" ] || return 0

    local now_ts
    now_ts=$(date +%s)
    is_int "$now_ts" || return 0

    local window_start=0
    local count=0
    if [ -f "$RATE_FILE" ]; then
        window_start=$(sed -n '1p' "$RATE_FILE" 2>/dev/null | tr -d '\r\n')
        count=$(sed -n '2p' "$RATE_FILE" 2>/dev/null | tr -d '\r\n')
        is_int "$window_start" || window_start=0
        is_int "$count" || count=0
    fi

    if [ "$window_start" -le 0 ] || [ $((now_ts - window_start)) -ge "$RATE_WINDOW_SECONDS" ]; then
        window_start=$now_ts
        count=0
    fi

    [ "$count" -lt "$RATE_MAX_TRIGGERS" ]
}

rate_limit_record_trigger() {
    [ -n "$RATE_FILE" ] || return 0

    local now_ts
    now_ts=$(date +%s)
    is_int "$now_ts" || return 0

    local window_start=0
    local count=0
    if [ -f "$RATE_FILE" ]; then
        window_start=$(sed -n '1p' "$RATE_FILE" 2>/dev/null | tr -d '\r\n')
        count=$(sed -n '2p' "$RATE_FILE" 2>/dev/null | tr -d '\r\n')
        is_int "$window_start" || window_start=0
        is_int "$count" || count=0
    fi

    if [ "$window_start" -le 0 ] || [ $((now_ts - window_start)) -ge "$RATE_WINDOW_SECONDS" ]; then
        window_start=$now_ts
        count=0
    fi

    count=$((count + 1))
    {
        echo "$window_start"
        echo "$count"
    } > "$RATE_FILE" 2>/dev/null || true
}

debounce_get_hits() {
    [ -n "$HITS_FILE" ] || { echo 0; return 0; }
    if [ -f "$HITS_FILE" ]; then
        local hits
        hits=$(cat "$HITS_FILE" 2>/dev/null | tr -d '\r\n')
        is_int "$hits" || hits=0
        echo "$hits"
        return 0
    fi
    echo 0
}

debounce_set_hits() {
    [ -n "$HITS_FILE" ] || return 0
    echo "$1" > "$HITS_FILE" 2>/dev/null || true
}

# =============================================================================
# Main Logic
# =============================================================================

main() {
    if [ -n "$LAST_RUN_FILE" ] && [ -f "$LAST_RUN_FILE" ]; then
        local last_ts
        last_ts=$(cat "$LAST_RUN_FILE" 2>/dev/null)
        if is_int "$last_ts"; then
            local now_ts
            now_ts=$(date +%s)
            if is_int "$now_ts" && [ $((now_ts - last_ts)) -lt "$COOLDOWN_SECONDS" ]; then
                return
            fi
        fi
    fi

    # Safety check: Only run when screen is on
    if ! is_screen_on; then
        return
    fi
    
    # Only run when auto-brightness is enabled
    if ! is_auto_brightness_enabled; then
        return
    fi
    
    # Get current physical brightness
    local current_physical
    current_physical=$(get_panel_brightness)
    
    # Fail-safe: If read fails, assume safe state
    if [ -z "$current_physical" ]; then
        return
    fi

    if ! is_int "$current_physical"; then
        return
    fi
    
    # Check if clamp is triggered
    if [ "$current_physical" -lt "$CRITICAL_THRESHOLD" ]; then
        # Get framework brightness for confirmation
        local setting_brightness
        setting_brightness=$(get_setting_brightness)
        
        # If framework thinks brightness should be > 10 but physical is clamped,
        # this is the 0-lux clamp bug common in many vendor ROMs
        if is_int "$setting_brightness" && [ "$setting_brightness" -gt 10 ]; then
            local hits
            hits=$(debounce_get_hits)
            hits=$((hits + 1))
            debounce_set_hits "$hits"

            [ "$hits" -ge "$DEBOUNCE_HITS" ] || return
            debounce_set_hits 0

            rate_limit_allows_trigger || return

            log_msg "DETECTED CLAMP BUG: Physical=$current_physical (< $CRITICAL_THRESHOLD), Framework=$setting_brightness"
            perform_soft_restart
            rate_limit_record_trigger
            if [ -n "$LAST_RUN_FILE" ]; then
                date +%s > "$LAST_RUN_FILE" 2>/dev/null || true
            fi
        else
            # Framework also thinks it's dark - this is normal auto-dimming
            debounce_set_hits 0
        fi
    else
        debounce_set_hits 0
    fi
}

# Execute main logic
main
