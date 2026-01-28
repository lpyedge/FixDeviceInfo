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
ui_print "✓ Module uninstalled successfully"
ui_print ""
ui_print "NOTE: Please reboot to apply changes"
ui_print ""

# Magisk automatically removes:
# - All files in $MODPATH (including overlays)
# - All property overrides from system.prop
# No additional cleanup needed

exit 0
