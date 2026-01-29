#!/system/bin/sh
# Device Info Fix Module - post-fs-data script
# This runs early in boot to ensure overlay idmap is refreshed

MODDIR=${0%/*}

LOG_FILE="$MODDIR/service.log"
# Export for sub-scripts
export MODDIR LOG_FILE

# Load common functions (needed for logging in post-fs-data)
if [ -f "$MODDIR/scripts/common.sh" ]; then
    . "$MODDIR/scripts/common.sh"
else
    # Minimal fallback
    log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"; }
fi

log "=============================================="
log "post-fs-data script started (Early Boot)"

# =============================================================================
# Feature: Battery Capacity Override (Bind-Mount)
# =============================================================================
# MUST happen here to precede System Server
if [ -f "$MODDIR/scripts/battery.sh" ]; then
    . "$MODDIR/scripts/battery.sh"
    apply_battery_override
fi

# =============================================================================
# Feature: Volume Curve Optimization (Bind-Mount)
# =============================================================================
# MUST happen here to precede Audio Service
if [ -f "$MODDIR/scripts/volume.sh" ]; then
    . "$MODDIR/scripts/volume.sh"
    apply_volume_optimization
fi

log "post-fs-data script completed"
