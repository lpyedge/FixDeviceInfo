#!/system/bin/sh
# Device Info Fix Module - Service Script
# Main entry point that orchestrates all feature modules
#
# Features:
# - Battery capacity override (bind-mount)
# - Volume curve optimization (bind-mount)
# - Brightness floor guard (sysfs)
# - Device name override (settings)

MODDIR=${0%/*}
LOG_FILE="$MODDIR/service.log"

# Export for sub-scripts
export MODDIR LOG_FILE

# =============================================================================
# Load common functions
# =============================================================================
if [ -f "$MODDIR/scripts/common.sh" ]; then
    . "$MODDIR/scripts/common.sh"
else
    # Fallback minimal log function if common.sh is missing
    log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"; }
    log "Warning: scripts/common.sh not found, using minimal logging"
fi

log "=============================================="
log "Service script started"
log "Module path: $MODDIR"

# =============================================================================
# Feature: Battery Capacity Override
# =============================================================================
if [ -f "$MODDIR/scripts/battery.sh" ]; then
    . "$MODDIR/scripts/battery.sh"
    apply_battery_override
else
    log "Warning: scripts/battery.sh not found, skip battery override"
fi

# =============================================================================
# Feature: Volume Curve Optimization
# =============================================================================
if [ -f "$MODDIR/scripts/volume.sh" ]; then
    . "$MODDIR/scripts/volume.sh"
    apply_volume_optimization
else
    log "Warning: scripts/volume.sh not found, skip volume optimization"
fi

# =============================================================================
# Feature: Brightness Floor Guard
# =============================================================================
if [ -f "$MODDIR/scripts/brightness.sh" ]; then
    . "$MODDIR/scripts/brightness.sh"
    apply_brightness_floor
else
    log "Warning: scripts/brightness.sh not found, skip brightness floor"
fi

log "Service script completed"

# =============================================================================
# Feature: Device Name Override (runs in background)
# This needs to wait for settings service, so run async
# =============================================================================
if [ -f "$MODDIR/scripts/device_name.sh" ]; then
    (
        # Keep this self-contained: if common.sh is missing, device_name.sh will log minimally.
        [ -f "$MODDIR/scripts/common.sh" ] && . "$MODDIR/scripts/common.sh"
        . "$MODDIR/scripts/device_name.sh"

        apply_device_name
        # Watch for module disable at runtime and rollback persistent settings.
        watch_disable_and_rollback
    ) &
else
    log "Warning: scripts/device_name.sh not found, skip device_name override"
fi

exit 0
