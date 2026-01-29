#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Device Info Fix - Local Build Script
# Build and package the Magisk module with overlay APKs
# =============================================================================

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
BUILD_DIR="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"

# Check ANDROID_HOME
ANDROID_HOME=${ANDROID_HOME:?"ANDROID_HOME is required"}
BUILD_TOOL_PATH=$(ls -d "$ANDROID_HOME"/build-tools/* 2>/dev/null | sort -V | tail -1)
AAPT2="$BUILD_TOOL_PATH/aapt2"
APKSIGNER="$BUILD_TOOL_PATH/apksigner"
ANDROID_JAR="$ANDROID_HOME/platforms/android-33/android.jar"

# Parameters (from environment variables)
BATTERY_CAPACITY=${BATTERY_CAPACITY:-}
CPU_NAME=${CPU_NAME:-}
DEVICE_ID=${DEVICE_ID:-}
MODEL_NAME=${MODEL_NAME:-}
BRAND=${BRAND:-}
MANUFACTURER=${MANUFACTURER:-}
LCD_DENSITY=${LCD_DENSITY:-}
PRODUCT_NAME=${PRODUCT_NAME:-}
BUILD_PRODUCT=${BUILD_PRODUCT:-}
OPTIMIZE_VOLUME=${OPTIMIZE_VOLUME:-}
BRIGHTNESS_FLOOR=${BRIGHTNESS_FLOOR:-}

# =============================================================================
# Utility Functions
# =============================================================================

# Trim whitespace (consistent with CI)
trim() {
  local value="$1"
  value="${value#${value%%[![:space:]]*}}"
  value="${value%${value##*[![:space:]]}}"
  printf "%s" "$value"
}

# Escape special characters for sed replacement
# We use # as delimiter, so we need to escape: &, \, #, and newlines
sed_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/[&#]/\\&/g' -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g'
}

# Escape special characters for XML content (handles <, >, &, ', ")
xml_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e "s/'/\&apos;/g" -e 's/"/\&quot;/g'
}

# Sanitize value for system.prop: remove newlines, =, and leading/trailing whitespace
# This ensures no property injection is possible
sanitize_prop_value() {
  printf '%s' "$1" | tr -d '\r\n=' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Sanitize for filename (alphanumeric, dot, dash, underscore only)
sanitize_filename() {
  printf '%s' "$1" | sed 's/[^A-Za-z0-9._-]/-/g'
}

# =============================================================================
# Trim all inputs
# =============================================================================
BATTERY_CAPACITY=$(trim "$BATTERY_CAPACITY")
CPU_NAME=$(trim "$CPU_NAME")
DEVICE_ID=$(trim "$DEVICE_ID")
MODEL_NAME=$(trim "$MODEL_NAME")
BRAND=$(trim "$BRAND")
MANUFACTURER=$(trim "$MANUFACTURER")
LCD_DENSITY=$(trim "$LCD_DENSITY")
PRODUCT_NAME=$(trim "$PRODUCT_NAME")
BUILD_PRODUCT=$(trim "$BUILD_PRODUCT")
OPTIMIZE_VOLUME=$(trim "$OPTIMIZE_VOLUME")
BRIGHTNESS_FLOOR=$(trim "$BRIGHTNESS_FLOOR")

# =============================================================================
# STEP 1: Clean up FIRST (before keystore handling)
# =============================================================================
echo "🧹 Cleaning stale build artifacts..."
rm -rf "$BUILD_DIR" "$DIST_DIR"
rm -f "$ROOT_DIR"/DeviceInfoFix*-Module.zip
mkdir -p "$BUILD_DIR" "$DIST_DIR"

# =============================================================================
# STEP 2: Keystore handling (AFTER cleanup)
# =============================================================================
KS_FILE="$BUILD_DIR/release.jks"

if [ -n "${SIGNING_KEY_B64:-}" ]; then
  echo "Decoding SIGNING_KEY_B64 into build/release.jks"
  echo "$SIGNING_KEY_B64" | base64 -d > "$KS_FILE"
elif [ -f "$ROOT_DIR/release.jks" ]; then
  echo "Using existing release.jks from repo root"
  cp "$ROOT_DIR/release.jks" "$KS_FILE"
else
  echo "❌ release.jks not found. Provide SIGNING_KEY_B64 or place keystore at $ROOT_DIR/release.jks" >&2
  exit 1
fi

# Verify keystore exists after handling
if [ ! -f "$KS_FILE" ]; then
  echo "❌ Keystore file not found at $KS_FILE after setup" >&2
  exit 1
fi

KS_ALIAS=${ALIAS:-${KEY_ALIAS:-my-alias}}
KS_PASS=${KEY_STORE_PASSWORD:-${KS_PASS:-}}
KEY_PASS=${KEY_PASSWORD:-$KS_PASS}

# Validate keystore password is provided
if [ -z "$KS_PASS" ]; then
  echo "❌ KEY_STORE_PASSWORD (or KS_PASS) is required" >&2
  exit 1
fi

# =============================================================================
# STEP 3: Validate parameters (strict, consistent with README)
# =============================================================================
validate_params() {
  local has_error=0
  
  # Battery capacity: must be integer 1000-20000
  if [ -n "$BATTERY_CAPACITY" ]; then
    if ! [[ "$BATTERY_CAPACITY" =~ ^[0-9]+$ ]]; then
      echo "❌ Error: BATTERY_CAPACITY must be a positive integer" >&2
      has_error=1
    elif [ "$BATTERY_CAPACITY" -lt 1000 ] || [ "$BATTERY_CAPACITY" -gt 20000 ]; then
      echo "❌ Error: BATTERY_CAPACITY must be between 1000-20000 mAh" >&2
      has_error=1
    fi
  fi
  
  # LCD density: must be integer 120-640 (as documented in README)
  if [ -n "$LCD_DENSITY" ]; then
    if ! [[ "$LCD_DENSITY" =~ ^[0-9]+$ ]]; then
      echo "❌ Error: LCD_DENSITY must be a positive integer" >&2
      has_error=1
    elif [ "$LCD_DENSITY" -lt 120 ] || [ "$LCD_DENSITY" -gt 640 ]; then
      echo "❌ Error: LCD_DENSITY must be between 120-640 DPI" >&2
      has_error=1
    fi
  fi
  
  # Device ID: alphanumeric, dash, underscore only
  if [ -n "$DEVICE_ID" ]; then
    if ! [[ "$DEVICE_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
      echo "❌ Error: DEVICE_ID should only contain letters, numbers, hyphens and underscores" >&2
      has_error=1
    fi
  fi
  
  # Product name: alphanumeric, dash, underscore only (as documented in README)
  if [ -n "$PRODUCT_NAME" ]; then
    if ! [[ "$PRODUCT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
      echo "❌ Error: PRODUCT_NAME should only contain letters, numbers, hyphens and underscores" >&2
      has_error=1
    fi
  fi
  
  # Build product: alphanumeric, dash, underscore only (as documented in README)
  if [ -n "$BUILD_PRODUCT" ]; then
    if ! [[ "$BUILD_PRODUCT" =~ ^[a-zA-Z0-9_-]+$ ]]; then
      echo "❌ Error: BUILD_PRODUCT should only contain letters, numbers, hyphens and underscores" >&2
      has_error=1
    fi
  fi
  
  # MODEL_NAME: reject dangerous characters (consistent with CI validation)
  if [ -n "$MODEL_NAME" ]; then
    if [[ "$MODEL_NAME" =~ [=] ]] || [[ "$MODEL_NAME" == *$'\n'* ]] || [[ "$MODEL_NAME" == *$'\r'* ]]; then
      echo "❌ Error: MODEL_NAME cannot contain '=' or newlines" >&2
      has_error=1
    fi
    # Reject shell special characters (same as CI)
    if [[ "$MODEL_NAME" == *'`'* || "$MODEL_NAME" == *'$'* || "$MODEL_NAME" == *'\\'* ]]; then
      echo "❌ Error: MODEL_NAME contains potentially dangerous characters (\`, \$, \\)" >&2
      has_error=1
    fi
  fi
  
  # BRAND: reject dangerous characters (consistent with CI validation)
  if [ -n "$BRAND" ]; then
    if [[ "$BRAND" =~ [=] ]] || [[ "$BRAND" == *$'\n'* ]] || [[ "$BRAND" == *$'\r'* ]]; then
      echo "❌ Error: BRAND cannot contain '=' or newlines" >&2
      has_error=1
    fi
    if [[ "$BRAND" == *'`'* || "$BRAND" == *'$'* || "$BRAND" == *'\\'* ]]; then
      echo "❌ Error: BRAND contains potentially dangerous characters (\`, \$, \\)" >&2
      has_error=1
    fi
  fi
  
  # MANUFACTURER: reject dangerous characters (consistent with CI validation)
  if [ -n "$MANUFACTURER" ]; then
    if [[ "$MANUFACTURER" =~ [=] ]] || [[ "$MANUFACTURER" == *$'\n'* ]] || [[ "$MANUFACTURER" == *$'\r'* ]]; then
      echo "❌ Error: MANUFACTURER cannot contain '=' or newlines" >&2
      has_error=1
    fi
    if [[ "$MANUFACTURER" == *'`'* || "$MANUFACTURER" == *'$'* || "$MANUFACTURER" == *'\\'* ]]; then
      echo "❌ Error: MANUFACTURER contains potentially dangerous characters (\`, \$, \\)" >&2
      has_error=1
    fi
  fi
  
  # CPU_NAME: reject dangerous characters (consistent with CI validation)
  if [ -n "$CPU_NAME" ]; then
    if [[ "$CPU_NAME" == *'`'* || "$CPU_NAME" == *'$'* || "$CPU_NAME" == *'\\'* ]]; then
      echo "❌ Error: CPU_NAME contains potentially dangerous characters (\`, \$, \\)" >&2
      has_error=1
    fi
    # Warn if contains characters that need XML escaping (we handle them, but warn user)
    if [[ "$CPU_NAME" =~ [\'\"<>\&] ]]; then
      echo "⚠️  Warning: CPU_NAME contains special characters that will be XML-escaped"
    fi
  fi
  
  if [ $has_error -eq 1 ]; then
    exit 1
  fi
  
  echo "✅ All input parameters validated"
}

validate_params

# =============================================================================
# Build Battery Overlay APK (if configured)
# =============================================================================
if [ -n "$BATTERY_CAPACITY" ]; then
  echo "🔋 Building battery overlay APK (${BATTERY_CAPACITY} mAh)..."
  
  mkdir -p "$BUILD_DIR/battery/res/xml"
  
  # BATTERY_CAPACITY is validated as integer, safe to use directly
  sed "s|{{BATTERY_CAPACITY}}|${BATTERY_CAPACITY}|g" \
    "$ROOT_DIR/overlay-src/battery/res/xml/power_profile.xml.in" \
    > "$BUILD_DIR/battery/res/xml/power_profile.xml"
  
  cp "$ROOT_DIR/overlay-src/battery/AndroidManifest.xml" "$BUILD_DIR/battery/"
  
  # Compile and link
  "$AAPT2" compile --dir "$BUILD_DIR/battery/res" -o "$BUILD_DIR/battery/resources.zip"
  "$AAPT2" link -o "$BUILD_DIR/battery/unsigned.apk" \
    --auto-add-overlay \
    -I "$ANDROID_JAR" \
    --manifest "$BUILD_DIR/battery/AndroidManifest.xml" \
    "$BUILD_DIR/battery/resources.zip"
  
  # Sign APK
  "$APKSIGNER" sign --ks "$KS_FILE" \
    --ks-key-alias "$KS_ALIAS" \
    --ks-pass pass:"$KS_PASS" \
    --key-pass pass:"$KEY_PASS" \
    --out "$BUILD_DIR/battery-overlay.apk" \
    "$BUILD_DIR/battery/unsigned.apk"
  
  echo "  ✓ battery-overlay.apk built"
else
  echo "ℹ️  BATTERY_CAPACITY not set: skip battery overlay"
fi

# =============================================================================
# Build CPU Overlay APK (if configured)
# =============================================================================
if [ -n "$CPU_NAME" ]; then
  echo "🖥️ Building CPU overlay APK (${CPU_NAME})..."
  
  mkdir -p "$BUILD_DIR/cpu/res/values"
  
  # XML-escape CPU_NAME to handle &, <, >, ', " safely
  CPU_NAME_ESCAPED=$(xml_escape "$CPU_NAME")
  # Then escape for sed replacement
  CPU_NAME_SED=$(sed_escape "$CPU_NAME_ESCAPED")
  
  sed "s|{{CPU_NAME}}|${CPU_NAME_SED}|g" \
    "$ROOT_DIR/overlay-src/cpu/res/values/strings.xml.in" \
    > "$BUILD_DIR/cpu/res/values/strings.xml"
  
  cp "$ROOT_DIR/overlay-src/cpu/AndroidManifest.xml" "$BUILD_DIR/cpu/"
  
  # Compile and link
  "$AAPT2" compile --dir "$BUILD_DIR/cpu/res" -o "$BUILD_DIR/cpu/resources.zip"
  "$AAPT2" link -o "$BUILD_DIR/cpu/unsigned.apk" \
    --auto-add-overlay \
    -I "$ANDROID_JAR" \
    --manifest "$BUILD_DIR/cpu/AndroidManifest.xml" \
    "$BUILD_DIR/cpu/resources.zip"
  
  # Sign APK
  "$APKSIGNER" sign --ks "$KS_FILE" \
    --ks-key-alias "$KS_ALIAS" \
    --ks-pass pass:"$KS_PASS" \
    --key-pass pass:"$KEY_PASS" \
    --out "$BUILD_DIR/cpu-overlay.apk" \
    "$BUILD_DIR/cpu/unsigned.apk"
  
  echo "  ✓ cpu-overlay.apk built"
else
  echo "ℹ️  CPU_NAME not set: skip CPU overlay"
fi

# =============================================================================
# Generate system.prop (if any property is configured)
# =============================================================================
generate_system_prop() {
  local prop_file="$BUILD_DIR/system.prop"
  local has_props=0
  
  # Helper to write a sanitized property
  write_prop() {
    local key="$1"
    local value="$2"
    if [ -n "$value" ]; then
      # Sanitize value: remove newlines and = to prevent injection
      local safe_value
      safe_value=$(sanitize_prop_value "$value")
      echo "${key}=${safe_value}" >> "$prop_file"
      has_props=1
    fi
  }
  
  # Start fresh
  : > "$prop_file"
  
  # Device ID (already validated as alphanumeric)
  if [ -n "$DEVICE_ID" ]; then
    write_prop "ro.product.device.display" "$DEVICE_ID"
    write_prop "ro.vendor.product.device.display" "$DEVICE_ID"
  fi
  
  # Model name (sanitized)
  if [ -n "$MODEL_NAME" ]; then
    local safe_model
    safe_model=$(sanitize_prop_value "$MODEL_NAME")
    write_prop "ro.product.model" "$safe_model"
    write_prop "ro.product.system.model" "$safe_model"
    write_prop "ro.product.vendor.model" "$safe_model"
    write_prop "ro.product.odm.model" "$safe_model"
    write_prop "ro.product.marketname" "$safe_model"
    write_prop "ro.product.odm.marketname" "$safe_model"
    write_prop "ro.product.vendor.marketname" "$safe_model"
    write_prop "ro.vendor.oplus.market.name" "$safe_model"
    write_prop "ro.oppo.market.name" "$safe_model"
    write_prop "ro.oppo.market.enname" "$safe_model"
    write_prop "ro.vendor.oplus.market.enname" "$safe_model"
    write_prop "ro.vendor.vivo.market.name" "$safe_model"
    write_prop "ro.vivo.market.name" "$safe_model"
    write_prop "ro.config.marketing_name" "$safe_model"
    write_prop "ro.vendor.product.ztename" "$safe_model"
    write_prop "ro.vendor.asus.product.mkt_name" "$safe_model"
    write_prop "ro.lge.petname" "$safe_model"
    write_prop "ro.boot.vendor.lge.petname" "$safe_model"
  fi
  
  # Brand (sanitized)
  if [ -n "$BRAND" ]; then
    local safe_brand
    safe_brand=$(sanitize_prop_value "$BRAND")
    write_prop "ro.product.brand" "$safe_brand"
    write_prop "ro.product.system.brand" "$safe_brand"
    write_prop "ro.product.vendor.brand" "$safe_brand"
  fi
  
  # Manufacturer (sanitized)
  if [ -n "$MANUFACTURER" ]; then
    local safe_manufacturer
    safe_manufacturer=$(sanitize_prop_value "$MANUFACTURER")
    write_prop "ro.product.manufacturer" "$safe_manufacturer"
    write_prop "ro.product.system.manufacturer" "$safe_manufacturer"
    write_prop "ro.product.vendor.manufacturer" "$safe_manufacturer"
  fi
  
  # LCD density (already validated as integer)
  if [ -n "$LCD_DENSITY" ]; then
    write_prop "ro.sf.lcd_density" "$LCD_DENSITY"
  fi
  
  # Product name (already validated as alphanumeric)
  if [ -n "$PRODUCT_NAME" ]; then
    write_prop "ro.product.name" "$PRODUCT_NAME"
    write_prop "ro.product.system.name" "$PRODUCT_NAME"
    write_prop "ro.product.vendor.name" "$PRODUCT_NAME"
  fi
  
  # Build product (already validated as alphanumeric)
  if [ -n "$BUILD_PRODUCT" ]; then
    write_prop "ro.build.product" "$BUILD_PRODUCT"
  fi
  
  if [ $has_props -eq 1 ]; then
    echo "  ✓ system.prop generated"
    return 0
  else
    rm -f "$prop_file"
    return 1
  fi
}

if [ -n "$DEVICE_ID" ] || [ -n "$MODEL_NAME" ] || [ -n "$BRAND" ] || [ -n "$MANUFACTURER" ] || [ -n "$LCD_DENSITY" ] || [ -n "$PRODUCT_NAME" ] || [ -n "$BUILD_PRODUCT" ]; then
  echo "🔧 Generating system.prop..."
  generate_system_prop || echo "ℹ️  No system properties to override"
else
  echo "ℹ️  No system properties to override"
fi

# =============================================================================
# Package Magisk Module
# =============================================================================
echo "📦 Packaging Magisk module..."

BUILD_SUFFIX=""
[ -n "$BATTERY_CAPACITY" ] && BUILD_SUFFIX="${BUILD_SUFFIX}-cap${BATTERY_CAPACITY}mAh"
[ -n "$CPU_NAME" ] && BUILD_SUFFIX="${BUILD_SUFFIX}-cpu$(sanitize_filename "$CPU_NAME" | cut -c1-20)"
[ -n "$DEVICE_ID" ] && BUILD_SUFFIX="${BUILD_SUFFIX}-dev$(sanitize_filename "$DEVICE_ID")"
[ -n "$MODEL_NAME" ] && BUILD_SUFFIX="${BUILD_SUFFIX}-model$(sanitize_filename "$MODEL_NAME")"
[ -n "$BRAND" ] && BUILD_SUFFIX="${BUILD_SUFFIX}-brand$(sanitize_filename "$BRAND")"
[ -n "$LCD_DENSITY" ] && BUILD_SUFFIX="${BUILD_SUFFIX}-dpi${LCD_DENSITY}"
[ -n "$PRODUCT_NAME" ] && BUILD_SUFFIX="${BUILD_SUFFIX}-prod$(sanitize_filename "$PRODUCT_NAME")"
[ -n "$BUILD_PRODUCT" ] && BUILD_SUFFIX="${BUILD_SUFFIX}-build$(sanitize_filename "$BUILD_PRODUCT")"

# Include runtime feature flags in output filename for traceability
[ "$OPTIMIZE_VOLUME" = "true" ] && BUILD_SUFFIX="${BUILD_SUFFIX}-vol"
[ "$BRIGHTNESS_FLOOR" = "true" ] && BUILD_SUFFIX="${BUILD_SUFFIX}-bright"

OUTPUT_ZIP="$ROOT_DIR/DeviceInfoFix${BUILD_SUFFIX}-Module.zip"
echo "  → Output: $(basename "$OUTPUT_ZIP")"

# =============================================================================
# CRITICAL: Overlay APKs MUST be under system/product/overlay
# This is the only reliable path for RRO on most ROMs.
# Previous attempts using vendor/overlay often failed to enable overlay.
# =============================================================================
mkdir -p "$DIST_DIR/system/product/overlay"

# Install overlay APKs
if [ -f "$BUILD_DIR/battery-overlay.apk" ]; then
  cp "$BUILD_DIR/battery-overlay.apk" "$DIST_DIR/system/product/overlay/"
  echo "  ✓ battery-overlay.apk → system/product/overlay/"
fi

if [ -f "$BUILD_DIR/cpu-overlay.apk" ]; then
  cp "$BUILD_DIR/cpu-overlay.apk" "$DIST_DIR/system/product/overlay/"
  echo "  ✓ cpu-overlay.apk → system/product/overlay/"
fi

# Battery capacity config for bind-mount patch (preferred method)
if [ -n "$BATTERY_CAPACITY" ]; then
  echo "$BATTERY_CAPACITY" > "$DIST_DIR/battery_capacity.conf"
  echo "  ✓ battery_capacity.conf included"
fi

# Model name config for device_name override (Bluetooth/Hotspot name)
if [ -n "$MODEL_NAME" ]; then
  # Sanitize for safety (same as system.prop)
  safe_model=$(sanitize_prop_value "$MODEL_NAME")
  echo "$safe_model" > "$DIST_DIR/model_name.conf"
  echo "  ✓ model_name.conf included (for device_name override)"
fi

# Volume optimization config for bind-mount volume curve linearization
if [ "$OPTIMIZE_VOLUME" = "true" ]; then
  echo "true" > "$DIST_DIR/optimize_volume.conf"
  cp "$ROOT_DIR/module/volume_curve_patch.xml" "$DIST_DIR/"
  echo "  ✓ optimize_volume.conf included (volume curve linearization)"
fi

# Brightness floor guard config (prevent screen blackout in dark environments)
if [ "$BRIGHTNESS_FLOOR" = "true" ]; then
  echo "true" > "$DIST_DIR/brightness_floor.conf"
  echo "  ✓ brightness_floor.conf included (brightness floor guard)"
fi

# Copy module files
cp "$ROOT_DIR/module/module.prop" "$DIST_DIR/"
[ -f "$ROOT_DIR/module/service.sh" ] && cp "$ROOT_DIR/module/service.sh" "$DIST_DIR/"
[ -f "$ROOT_DIR/module/post-fs-data.sh" ] && cp "$ROOT_DIR/module/post-fs-data.sh" "$DIST_DIR/"
[ -f "$ROOT_DIR/module/uninstall.sh" ] && cp "$ROOT_DIR/module/uninstall.sh" "$DIST_DIR/"

# Copy scripts directory
if [ -d "$ROOT_DIR/module/scripts" ]; then
  mkdir -p "$DIST_DIR/scripts"
  cp "$ROOT_DIR/module/scripts/"*.sh "$DIST_DIR/scripts/"
  chmod 0755 "$DIST_DIR/scripts/"*.sh 2>/dev/null || true
  echo "  ✓ Feature scripts included"
fi

# Copy system.prop if generated
if [ -f "$BUILD_DIR/system.prop" ]; then
  cp "$BUILD_DIR/system.prop" "$DIST_DIR/"
  echo "  ✓ system.prop included"
fi

# Setup Magisk installer
mkdir -p "$DIST_DIR/META-INF/com/google/android"
cp "$ROOT_DIR/module/META-INF/com/google/android/update-binary" "$DIST_DIR/META-INF/com/google/android/"
echo '#MAGISK' > "$DIST_DIR/META-INF/com/google/android/updater-script"
chmod 0755 "$DIST_DIR/META-INF/com/google/android/update-binary" 2>/dev/null || true
[ -f "$DIST_DIR/service.sh" ] && chmod 0755 "$DIST_DIR/service.sh" 2>/dev/null || true
[ -f "$DIST_DIR/post-fs-data.sh" ] && chmod 0755 "$DIST_DIR/post-fs-data.sh" 2>/dev/null || true
[ -f "$DIST_DIR/uninstall.sh" ] && chmod 0755 "$DIST_DIR/uninstall.sh" 2>/dev/null || true

# Create ZIP
( cd "$DIST_DIR" && zip -r "$OUTPUT_ZIP" . )

# Clean up keystore from build directory (security)
rm -f "$KS_FILE"

echo ""
echo "✅ Build complete: $OUTPUT_ZIP"
echo ""
echo "Install with: adb push \"$OUTPUT_ZIP\" /sdcard/ && adb shell su -c 'magisk --install-module /sdcard/$(basename "$OUTPUT_ZIP")'"
