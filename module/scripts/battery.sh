#!/system/bin/sh
# Device Info Fix Module - Battery Capacity Override
# Dynamically locate power_profile.xml and bind-mount a patched copy

# Source common functions (MODDIR and LOG_FILE must be set by caller)
. "$MODDIR/scripts/common.sh"

# =============================================================================
# Configuration
# =============================================================================
BATTERY_CONF_FILE="$MODDIR/battery_capacity.conf"
BATTERY_TARGET_FILE="$MODDIR/power_profile_target"

# =============================================================================
# Functions
# =============================================================================

find_power_profile() {
    # Fast path: reuse previously discovered location
    if [ -f "$BATTERY_TARGET_FILE" ]; then
        local cached
        cached=$(cat "$BATTERY_TARGET_FILE" 2>/dev/null | tr -d '\r\n')
        if [ -n "$cached" ] && [ -f "$cached" ]; then
            log "Using cached power_profile path: $cached"
            echo "$cached"
            return 0
        fi
    fi
    
    # Slow path: search likely partitions; stop at first hit.
    for root in \
        /odm/etc/power_profile \
        /odm/etc \
        /odm \
        /vendor/etc \
        /vendor \
        /product/etc \
        /product \
        /system/etc \
        /system \
        /system_ext/etc \
        /system_ext; do
        [ -d "$root" ] || continue
        p=$(find "$root" -name power_profile.xml 2>/dev/null | head -n 1)
        if [ -n "$p" ] && [ -f "$p" ]; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

# =============================================================================
# Main Function: Bind-Mount (Run in post-fs-data)
# =============================================================================
# CRITICAL: This must run in post-fs-data (before Zygote starts)
# The PowerManagerService reads power_profile.xml during system server startup.
# If we mount later (e.g. at service.sh), the system will have already cached
# the original values, and our changes will be ignored until a userspace reboot.
apply_battery_override() {
    # Read battery capacity from config
    local cap=""
    if [ -f "$BATTERY_CONF_FILE" ]; then
        cap=$(cat "$BATTERY_CONF_FILE" 2>/dev/null | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi

    if ! is_int "$cap"; then
        log "No valid battery_capacity.conf, skip bind-mount"
        return 0
    fi

    # No sleep needed in post-fs-data; we want to race AHEAD of the system
    
    local src
    src=$(find_power_profile || true)
    if [ -z "$src" ]; then
        log "power_profile.xml not found, cannot bind-mount"
        return 0
    fi

    log "Found power_profile: $src"
    echo "$src" > "$BATTERY_TARGET_FILE" 2>/dev/null || true

    local workdir="$MODDIR/power_profile"
    mkdir -p "$workdir" 2>/dev/null || true
    local out="$workdir/power_profile.xml"

    # Create patched copy
    # FIXED: Regex now handles whitespace around tags and content (e.g. <item > 4500 </item>)
    if grep -q 'name="battery\.capacity"' "$src"; then
        sed -E "s#(<item[[:space:]]+name=\"battery\.capacity\">)[[:space:]]*[0-9]+(\.[0-9]+)?[[:space:]]*(</item>)#\1${cap}\3#" "$src" > "$out" 2>/dev/null
        
        # Verify
        if ! grep -q "battery\.capacity\">${cap}<" "$out" 2>/dev/null; then
             log "Warning: battery.capacity replacement may not have worked, check $out"
        fi
    else
        cp "$src" "$out" 2>/dev/null
        # Try to insert before closing tag
        if grep -q '</device>' "$out" 2>/dev/null; then
            sed -i "s#</device>#  <item name=\"battery.capacity\">${cap}</item>\n</device>#" "$out" 2>/dev/null || true
        elif grep -q '</power_profile>' "$out" 2>/dev/null; then
            sed -i "s#</power_profile>#  <item name=\"battery.capacity\">${cap}</item>\n</power_profile>#" "$out" 2>/dev/null || true
        else
            log "Warning: Unknown XML root node in $src, cannot safely insert battery.capacity"
            rm -f "$out" 2>/dev/null || true
            return 0
        fi
    fi

    chmod 0644 "$out" 2>/dev/null || true
    preserve_selinux_context "$src" "$out"

    umount "$src" 2>/dev/null || true
    if mount --bind "$out" "$src" 2>/dev/null; then
        log "Bind-mounted patched power_profile (capacity=$cap). This MUST happen before system server starts."
    else
        log "Bind-mount failed for $src"
    fi
}

# =============================================================================
# Fallback/Supplemental: Enable Overlay (Run in service.sh)
# =============================================================================
# CRITICAL: This must run in service.sh (after system is ready)
# The 'cmd' command requires the ActivityManager/OverlayManager services to be running.
enable_battery_overlay() {
    # Only enable if user actually configured it
    if [ ! -f "$BATTERY_CONF_FILE" ]; then 
        return 0
    fi

    local overlay_package="com.fixdeviceinfo.battery.overlay"
    if cmd overlay list 2>/dev/null | grep -q "$overlay_package"; then
        cmd overlay enable --user 0 "$overlay_package" 2>/dev/null && log "Enabled battery overlay for user 0"
        cmd overlay enable "$overlay_package" 2>/dev/null && log "Enabled battery overlay (system-wide)"
    fi
}

# Run if executed directly
if [ "${0##*/}" = "battery.sh" ]; then
    apply_battery_override
fi
