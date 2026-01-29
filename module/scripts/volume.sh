#!/system/bin/sh
# Device Info Fix Module - Volume Curve Optimization
# Bind-mount patched audio config for linear volume curve

# Source common functions (MODDIR and LOG_FILE must be set by caller)
. "$MODDIR/scripts/common.sh"

# =============================================================================
# Configuration
# =============================================================================
VOLUME_CONF_FILE="$MODDIR/optimize_volume.conf"
VOLUME_PATCH_FILE="$MODDIR/volume_curve_patch.xml"
VOLUME_TARGET_FILE="$MODDIR/volume_target"

# =============================================================================
# Functions
# =============================================================================

find_volume_config() {
    for path in \
        /vendor/etc/audio_policy_volumes.xml \
        /vendor/etc/default_volume_tables.xml \
        /odm/etc/audio_policy_volumes.xml \
        /odm/etc/default_volume_tables.xml \
        /system/etc/audio_policy_volumes.xml \
        /system/etc/default_volume_tables.xml; do
        if [ -f "$path" ]; then
            # Check if this file contains the volume curve we want to patch
            if grep -q 'DEFAULT_DEVICE_CATEGORY_SPEAKER_VOLUME_CURVE' "$path" 2>/dev/null; then
                echo "$path"
                return 0
            fi
        fi
    done
    return 1
}

# =============================================================================
# Main Function (Run in post-fs-data)
# =============================================================================
# CRITICAL: This must run in post-fs-data (before Zygote starts)
# AudioPolicyService reads these files during system server startup.
apply_volume_optimization() {
    if [ ! -f "$VOLUME_CONF_FILE" ]; then
        log "Volume optimization not enabled, skip"
        return 0
    fi
    
    if [ ! -f "$VOLUME_PATCH_FILE" ]; then
        log "Warning: volume_curve_patch.xml not found, skip volume optimization"
        return 1
    fi
    
    log "Applying volume curve optimization..."
    
    # Try to use cached path first
    local volume_src=""
    if [ -f "$VOLUME_TARGET_FILE" ]; then
        volume_src=$(cat "$VOLUME_TARGET_FILE" 2>/dev/null | tr -d '\r\n')
        if [ -n "$volume_src" ] && [ -f "$volume_src" ]; then
            log "Using cached volume config path: $volume_src"
        else
            volume_src=""
        fi
    fi
    
    # Find volume config if not cached
    if [ -z "$volume_src" ]; then
        volume_src=$(find_volume_config || true)
    fi
    
    if [ -z "$volume_src" ]; then
        log "No suitable volume config file found, skip optimization"
        return 1
    fi
    
    log "Found volume config: $volume_src"
    echo "$volume_src" > "$VOLUME_TARGET_FILE" 2>/dev/null || true
    
    # Create patched copy
    local volume_workdir="$MODDIR/volume_config"
    mkdir -p "$volume_workdir" 2>/dev/null || true
    local volume_out="$volume_workdir/$(basename "$volume_src")"
    
    # Read the patch content
    local patch_content
    patch_content=$(cat "$VOLUME_PATCH_FILE" 2>/dev/null)
    
    if [ -z "$patch_content" ]; then
        log "Warning: volume patch file is empty"
        return 1
    fi
    
    # Create patched file by replacing the DEFAULT_DEVICE_CATEGORY_SPEAKER_VOLUME_CURVE section
    # FIXED: awk regex to allow flexible whitespace (0 or more) in the reference tag
    awk -v patch="$patch_content" '
    BEGIN { in_section = 0; printed = 0 }
    /<reference[[:space:]]*name="DEFAULT_DEVICE_CATEGORY_SPEAKER_VOLUME_CURVE">/ {
        in_section = 1
        print patch
        printed = 1
        next
    }
    in_section && /<\/reference>/ {
        in_section = 0
        next
    }
    !in_section { print }
    ' "$volume_src" > "$volume_out" 2>/dev/null
    
    # Verify patch was actually applied (check for our signature value)
    if ! grep -q 'point>1,-6000<' "$volume_out" 2>/dev/null; then
        log "Warning: Volume curve patch was NOT applied - source file format may differ"
        log "Skipping bind-mount to avoid mounting unchanged file"
        rm -f "$volume_out" 2>/dev/null || true
        return 1
    fi
    
    # Verify output file is not empty and has reasonable size
    if [ ! -s "$volume_out" ]; then
        log "Warning: Patched volume file is empty, aborting"
        rm -f "$volume_out" 2>/dev/null || true
        return 1
    fi
    
    chmod 0644 "$volume_out" 2>/dev/null || true
    
    preserve_selinux_context "$volume_src" "$volume_out"
    
    umount "$volume_src" 2>/dev/null || true
    if mount --bind "$volume_out" "$volume_src" 2>/dev/null; then
        log "Bind-mounted patched volume config to $volume_src"
    else
        log "Warning: Bind-mount failed for volume config $volume_src"
        return 1
    fi
    
    log "Volume curve optimization completed"
}

# Run if executed directly
if [ "${0##*/}" = "volume.sh" ]; then
    apply_volume_optimization
fi
