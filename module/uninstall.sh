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

ui_print "✓ Module uninstalled successfully"
ui_print ""
ui_print "NOTE: Please reboot to apply changes"
ui_print ""

# Magisk automatically removes:
# - All files in $MODPATH (including overlays)
# - All property overrides from system.prop
# No additional cleanup needed

exit 0
