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

enable_overlay_fallback() {
    local overlay_package="com.fixdeviceinfo.battery.overlay"
    if cmd overlay list 2>/dev/null | grep -q "$overlay_package"; then
        cmd overlay enable --user 0 "$overlay_package" 2>/dev/null && log "Enabled overlay for user 0"
        cmd overlay enable "$overlay_package" 2>/dev/null && log "Enabled overlay (all users)"
        return 0
    fi
    return 1
}

# =============================================================================
# Main Function
# =============================================================================
apply_battery_override() {
    # Read battery capacity from config
    local cap=""
    if [ -f "$BATTERY_CONF_FILE" ]; then
        cap=$(cat "$BATTERY_CONF_FILE" 2>/dev/null | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi

    if ! is_int "$cap"; then
        # Safety principle: if user did not configure battery capacity, do not touch/enable any battery override.
        log "No valid battery_capacity.conf, skip all battery overrides"
        return 0
    fi

    # Wait a bit for early boot mounts to settle
    sleep 5

    local src
    src=$(find_power_profile || true)
    if [ -z "$src" ]; then
        log "power_profile.xml not found in known locations"
        enable_overlay_fallback || true
        return 0
    fi

    log "Found power_profile: $src"
    echo "$src" > "$BATTERY_TARGET_FILE" 2>/dev/null || true

    local workdir="$MODDIR/power_profile"
    mkdir -p "$workdir" 2>/dev/null || true
    local out="$workdir/power_profile.xml"

    # Create patched copy (preserve full OEM file, only replace battery.capacity)
    # Support both integer (5000) and decimal (5000.0) formats in source file
    if grep -q 'name="battery\.capacity"' "$src"; then
        sed -E "s#(<item[[:space:]]+name=\"battery\.capacity\">)[0-9]+(\.[0-9]+)?(</item>)#\1${cap}\3#" "$src" > "$out" 2>/dev/null
        # Verify the replacement actually happened
        if ! grep -q "battery\.capacity\">${cap}<" "$out" 2>/dev/null; then
            log "Warning: battery.capacity replacement may not have worked, check $out"
        fi
    else
        cp "$src" "$out" 2>/dev/null
        # Try to insert before closing tag; support both <device> and <power_profile> root nodes
        if grep -q '</device>' "$out" 2>/dev/null; then
            sed -i "s#</device>#  <item name=\"battery.capacity\">${cap}</item>\n</device>#" "$out" 2>/dev/null || true
        elif grep -q '</power_profile>' "$out" 2>/dev/null; then
            sed -i "s#</power_profile>#  <item name=\"battery.capacity\">${cap}</item>\n</power_profile>#" "$out" 2>/dev/null || true
        else
            # Unknown root node - log warning and skip patching to avoid breaking XML
            log "Warning: Unknown XML root node in $src, cannot safely insert battery.capacity"
            log "Fallback to RRO overlay for battery capacity"
            rm -f "$out" 2>/dev/null || true
            enable_overlay_fallback || true
            return 0
        fi
    fi

    chmod 0644 "$out" 2>/dev/null || true

    # Preserve SELinux context
    preserve_selinux_context "$src" "$out"

    # Bind-mount patched file over the discovered path
    umount "$src" 2>/dev/null || true
    if mount --bind "$out" "$src" 2>/dev/null; then
        log "Bind-mounted patched power_profile to $src (capacity=$cap)"
    else
        log "Bind-mount failed for $src"
        enable_overlay_fallback || true
    fi

    log "Battery override completed"
}

# Run if executed directly (for testing)
if [ "${0##*/}" = "battery.sh" ]; then
    apply_battery_override
fi
