#!/system/bin/sh
# Device Info Fix Module - Uninstall Script
# This script is executed when the module is removed from Magisk Manager

MODDIR=${0%/*}

ui_print() {
  echo "$1"
}

ui_print "***********************************"
ui_print " Uninstalling Device Info Fix"
ui_print "***********************************"
ui_print ""
ui_print "- Removing overlay files..."
ui_print "- Magisk will restore original system properties"
ui_print ""

# Undo bind-mount if the module patched power_profile at runtime.
# Note: disabling a module requires reboot to fully restore mounts.
TARGET_FILE="$MODDIR/power_profile_target"
TARGET_PP=""
if [ -f "$TARGET_FILE" ]; then
  TARGET_PP=$(cat "$TARGET_FILE" 2>/dev/null | tr -d '\r\n')
fi

# Fallback for common ODM layout
[ -z "$TARGET_PP" ] && TARGET_PP="/odm/etc/power_profile/power_profile.xml"

if command -v su >/dev/null 2>&1; then
  su -c "umount '$TARGET_PP' 2>/dev/null" >/dev/null 2>&1 || true
else
  umount "$TARGET_PP" 2>/dev/null || true
fi

# ==========================================================================
# Undo volume curve bind-mount
# ==========================================================================
VOLUME_TARGET_FILE="$MODDIR/volume_target"
VOLUME_TARGET=""
if [ -f "$VOLUME_TARGET_FILE" ]; then
  VOLUME_TARGET=$(cat "$VOLUME_TARGET_FILE" 2>/dev/null | tr -d '\r\n')
fi

if [ -n "$VOLUME_TARGET" ]; then
  ui_print "- Restoring original volume configuration..."
  if command -v su >/dev/null 2>&1; then
    su -c "umount '$VOLUME_TARGET' 2>/dev/null" >/dev/null 2>&1 || true
  else
    umount "$VOLUME_TARGET" 2>/dev/null || true
  fi
fi

# ==========================================================================
# Restore device_name to system default
# Delete the custom setting so system uses the default value from build.prop
# ==========================================================================
ui_print "- Restoring device name to default..."

# ==========================================================================
# Stop auto brightness fixer daemon (best effort)
# ==========================================================================
PID_FILE="$MODDIR/.auto_brightness_fix.pid"
if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE" 2>/dev/null | tr -d '\r\n')
  if echo "$PID" | grep -Eq '^[0-9]+$'; then
    if command -v su >/dev/null 2>&1; then
      su -c "kill $PID 2>/dev/null" >/dev/null 2>&1 || true
    else
      kill "$PID" 2>/dev/null || true
    fi
  fi
  rm -f "$PID_FILE" 2>/dev/null || true
fi

# Try to delete device_name setting (let system use default)
if command -v settings >/dev/null 2>&1; then
  settings delete global device_name >/dev/null 2>&1 || true
  settings delete secure bluetooth_name >/dev/null 2>&1 || true
  ui_print "  ✓ Device name will be restored on next reboot"
fi

ui_print ""
ui_print "✓ Module uninstalled successfully"
ui_print ""
ui_print "NOTE: Please reboot to apply changes"
ui_print ""

# Magisk automatically removes:
# - All files in $MODPATH (including overlays)
# - All property overrides from system.prop
# No additional cleanup needed

exit 0
