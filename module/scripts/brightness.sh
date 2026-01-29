#!/system/bin/sh
# Device Info Fix Module - Brightness Floor Guard
# Prevents auto-brightness from dimming screen to 0 in dark environments

# Source common functions (MODDIR and LOG_FILE must be set by caller)
. "$MODDIR/scripts/common.sh"

# =============================================================================
# Configuration
# =============================================================================
BRIGHTNESS_CONF_FILE="$MODDIR/brightness_floor.conf"

# =============================================================================
# Vendor-specific implementations
# =============================================================================

# OPLUS / realme / OnePlus (ColorOS / OxygenOS)
oplus_dimlayer_guard() {
    local applied=0
    
    # Disable dim layer completely
    write_if_exists /sys/kernel/oplus_display/dimlayer_bl_en 0 && applied=1
    
    # Set alpha floor (200 = readable at night without being too bright)
    write_if_exists /sys/kernel/oplus_display/dim_alpha 200 && applied=1
    write_if_exists /sys/kernel/oplus_display/dim_dc_alpha 200 && applied=1
    
    # Shell convention: 0=success, 1=failure
    [ "$applied" -eq 1 ] && return 0 || return 1
}

# Xiaomi / Redmi / HyperOS (and older MIUI)
xiaomi_dim_guard() {
    local applied=0
    
    write_if_exists /sys/class/backlight/panel0-backlight/dim_alpha 200 && applied=1
    write_if_exists /sys/class/backlight/panel0-backlight/dc_alpha 200 && applied=1
    
    # Some devices use lcd_enhance path
    write_if_exists /sys/kernel/lcd_enhance/dim_alpha 200 && applied=1
    
    # Shell convention: 0=success, 1=failure
    [ "$applied" -eq 1 ] && return 0 || return 1
}

# Samsung (OneUI) - prevent brightness going to 0
samsung_guard() {
    local applied=0
    
    # Samsung doesn't have dimlayer, directly set minimum brightness
    write_if_exists /sys/class/backlight/panel0-backlight/brightness 5 && applied=1
    write_if_exists /sys/class/backlight/panel1-backlight/brightness 5 && applied=1
    
    # Shell convention: 0=success, 1=failure
    [ "$applied" -eq 1 ] && return 0 || return 1
}

# Pixel / AOSP / LineageOS / Generic (fallback)
aosp_min_backlight_guard() {
    local applied=0
    local bl
    
    for bl in /sys/class/backlight/*/brightness; do
        [ -w "$bl" ] || continue
        echo 5 > "$bl" 2>/dev/null
        applied=1
    done
    
    # Shell convention: 0=success, 1=failure
    [ "$applied" -eq 1 ] && return 0 || return 1
}

# =============================================================================
# Main Function
# =============================================================================
apply_brightness_floor() {
    if [ ! -f "$BRIGHTNESS_CONF_FILE" ]; then
        log "Brightness floor not enabled, skip"
        return 0
    fi
    
    log "Applying brightness floor guard..."
    
    # Try each vendor-specific method in order, stop at first success
    if oplus_dimlayer_guard; then
        log "Brightness floor applied via OPLUS method"
        return 0
    fi
    
    if xiaomi_dim_guard; then
        log "Brightness floor applied via Xiaomi method"
        return 0
    fi
    
    if samsung_guard; then
        log "Brightness floor applied via Samsung method"
        return 0
    fi
    
    if aosp_min_backlight_guard; then
        log "Brightness floor applied via AOSP fallback method"
        return 0
    fi
    
    log "Warning: No brightness sysfs nodes found or writable"
    return 1
}

# Run if executed directly (for testing)
if [ "${0##*/}" = "brightness.sh" ]; then
    apply_brightness_floor
fi
