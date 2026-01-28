#!/usr/bin/env bash
set -euo pipefail

# Build and package the battery overlay into a Magisk-flashable zip.
# Requirements: ANDROID_HOME with build-tools + platforms; android-33; aapt2; apksigner.

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
BUILD_DIR="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"
OUTPUT_ZIP="$ROOT_DIR/DeviceInfoFixModule.zip"

ANDROID_HOME=${ANDROID_HOME:?"ANDROID_HOME is required"}
BUILD_TOOL_PATH=$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -1)
AAPT2="$BUILD_TOOL_PATH/aapt2"
APKSIGNER="$BUILD_TOOL_PATH/apksigner"
ANDROID_JAR="$ANDROID_HOME/platforms/android-33/android.jar"

BATTERY_CAPACITY=${BATTERY_CAPACITY:-}
DEVICE_ID=${DEVICE_ID:-}
MODEL_NAME=${MODEL_NAME:-}
BRAND=${BRAND:-}
MANUFACTURER=${MANUFACTURER:-}
LCD_DENSITY=${LCD_DENSITY:-}
PRODUCT_NAME=${PRODUCT_NAME:-}
BUILD_PRODUCT=${BUILD_PRODUCT:-}

# Keystore handling - use build directory to avoid leaving credentials in repo root
KS_FILE="$BUILD_DIR/release.jks"
if [ -n "${SIGNING_KEY_B64:-}" ]; then
  echo "Decoding SIGNING_KEY_B64 into build/release.jks"
  echo "$SIGNING_KEY_B64" | base64 -d > "$KS_FILE"
elif [ -f "$ROOT_DIR/release.jks" ]; then
  echo "Using existing release.jks from repo root"
  cp "$ROOT_DIR/release.jks" "$KS_FILE"
else
  echo "release.jks not found. Provide SIGNING_KEY_B64 or place the keystore at $ROOT_DIR/release.jks" >&2
  echo "WARNING: Avoid committing keystore to repository. Use environment variable or secure storage." >&2
  exit 1
fi

KS_ALIAS=${ALIAS:-${KEY_ALIAS:-my-alias}}
KS_PASS=${KEY_STORE_PASSWORD:-${KS_PASS:-}}
KEY_PASS=${KEY_PASSWORD:-$KS_PASS}

# Validate input parameters
validate_params() {
  local has_error=0
  
  if [ -n "$BATTERY_CAPACITY" ]; then
    if ! [[ "$BATTERY_CAPACITY" =~ ^[0-9]+$ ]]; then
      echo "❌ Error: BATTERY_CAPACITY must be a positive integer" >&2
      has_error=1
    elif [ "$BATTERY_CAPACITY" -lt 1000 ] || [ "$BATTERY_CAPACITY" -gt 20000 ]; then
      echo "⚠️  Warning: BATTERY_CAPACITY $BATTERY_CAPACITY seems unusual (expected 1000-20000 mAh)"
    fi
  fi
  
  if [ -n "$LCD_DENSITY" ]; then
    if ! [[ "$LCD_DENSITY" =~ ^[0-9]+$ ]]; then
      echo "❌ Error: LCD_DENSITY must be a positive integer" >&2
      has_error=1
    elif [ "$LCD_DENSITY" -lt 120 ] || [ "$LCD_DENSITY" -gt 640 ]; then
      echo "⚠️  Warning: LCD_DENSITY $LCD_DENSITY seems unusual (expected 120-640)"
    fi
  fi
  
  if [ -n "$DEVICE_ID" ]; then
    if ! [[ "$DEVICE_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
      echo "❌ Error: DEVICE_ID should only contain letters, numbers, hyphens and underscores" >&2
      has_error=1
    fi
  fi
  
  # Validate string parameters to prevent injection attacks
  validate_string() {
    local name=$1
    local value=$2
    
    # Prevent prop injection via line breaks / separators.
    if [[ "$value" == *$'\n'* || "$value" == *$'\r'* || "$value" == *"="* ]]; then
      echo "❌ Error: $name contains invalid characters (newline, carriage return, or equals sign)" >&2
      has_error=1
      return 1
    fi
    
    # Avoid confusing/unsafe shell metacharacters in logs and generated files.
    if [[ "$value" == *'`'* || "$value" == *'$'* || "$value" == *'\\'* ]]; then
      echo "❌ Error: $name contains potentially dangerous characters" >&2
      has_error=1
      return 1
    fi
  }
  
  [ -n "$MODEL_NAME" ] && validate_string "MODEL_NAME" "$MODEL_NAME"
  [ -n "$BRAND" ] && validate_string "BRAND" "$BRAND"
  [ -n "$MANUFACTURER" ] && validate_string "MANUFACTURER" "$MANUFACTURER"
  [ -n "$PRODUCT_NAME" ] && validate_string "PRODUCT_NAME" "$PRODUCT_NAME"
  [ -n "$BUILD_PRODUCT" ] && validate_string "BUILD_PRODUCT" "$BUILD_PRODUCT"
  
  if [ $has_error -eq 1 ]; then
    exit 1
  fi
  
  echo "✅ All input parameters validated successfully"
}

validate_params

# Clean up stale files to prevent dirty state
echo "🧹 Cleaning up stale build artifacts..."
rm -f "$ROOT_DIR/module/system.prop"
rm -rf "$BUILD_DIR" "$DIST_DIR"
rm -f "$OUTPUT_ZIP"
mkdir -p "$BUILD_DIR"

# Stage resources to avoid mutating tracked files
BUILD_RES_DIR="$BUILD_DIR/res"
mkdir -p "$BUILD_RES_DIR"
cp -a "$ROOT_DIR/app/src/main/res/." "$BUILD_RES_DIR/"

# Optionally override capacity in build directory (not source)
if [ -n "$BATTERY_CAPACITY" ]; then
  echo "📊 Setting battery capacity to $BATTERY_CAPACITY mAh"
  cat > "$BUILD_RES_DIR/xml/power_profile.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<power_profile xmlns:android="http://schemas.android.com/apk/res/android">
    <item name="battery.capacity">${BATTERY_CAPACITY}</item>
</power_profile>
EOF
fi

# Generate system.prop in build directory (not source)
BUILD_SYSTEM_PROP="$BUILD_DIR/system.prop"
if [ -n "$DEVICE_ID" ] || [ -n "$MODEL_NAME" ] || [ -n "$BRAND" ] || [ -n "$MANUFACTURER" ] || [ -n "$LCD_DENSITY" ] || [ -n "$PRODUCT_NAME" ] || [ -n "$BUILD_PRODUCT" ]; then
  echo "🔧 Generating system.prop with custom properties:"
  {
    if [ -n "$DEVICE_ID" ]; then
      echo "ro.product.device=${DEVICE_ID}"
      echo "ro.product.system.device=${DEVICE_ID}"
      echo "ro.product.vendor.device=${DEVICE_ID}"
      echo "  ✓ Device ID: ${DEVICE_ID}" >&2
    fi
    
    if [ -n "$MODEL_NAME" ]; then
      echo "ro.product.model=${MODEL_NAME}"
      echo "ro.product.system.model=${MODEL_NAME}"
      echo "ro.product.vendor.model=${MODEL_NAME}"
      echo "  ✓ Model: ${MODEL_NAME}" >&2
    fi
    
    if [ -n "$BRAND" ]; then
      echo "ro.product.brand=${BRAND}"
      echo "ro.product.system.brand=${BRAND}"
      echo "ro.product.vendor.brand=${BRAND}"
      echo "  ✓ Brand: ${BRAND}" >&2
    fi
    
    if [ -n "$MANUFACTURER" ]; then
      echo "ro.product.manufacturer=${MANUFACTURER}"
      echo "ro.product.system.manufacturer=${MANUFACTURER}"
      echo "ro.product.vendor.manufacturer=${MANUFACTURER}"
      echo "  ✓ Manufacturer: ${MANUFACTURER}" >&2
    fi
    
    if [ -n "$LCD_DENSITY" ]; then
      echo "ro.sf.lcd_density=${LCD_DENSITY}"
      echo "  ✓ LCD Density: ${LCD_DENSITY} DPI" >&2
    fi
    
    if [ -n "$PRODUCT_NAME" ]; then
      echo "ro.product.name=${PRODUCT_NAME}"
      echo "ro.product.system.name=${PRODUCT_NAME}"
      echo "ro.product.vendor.name=${PRODUCT_NAME}"
      echo "  ✓ Product Name: ${PRODUCT_NAME}" >&2
    fi
    
    if [ -n "$BUILD_PRODUCT" ]; then
      echo "ro.build.product=${BUILD_PRODUCT}"
      echo "  ✓ Build Product: ${BUILD_PRODUCT}" >&2
    fi
  } > "$BUILD_SYSTEM_PROP"
else
  echo "ℹ️  No system properties to override, system.prop will not be included"
  BUILD_SYSTEM_PROP=""
fi

# 1) Compile resources
"$AAPT2" compile --dir "$BUILD_RES_DIR" -o "$BUILD_DIR/resources.zip"

# 2) Link to unsigned APK
"$AAPT2" link -o "$BUILD_DIR/unsigned.apk" \
  -I "$ANDROID_JAR" \
  --manifest "$ROOT_DIR/app/src/main/AndroidManifest.xml" \
  "$BUILD_DIR/resources.zip"

# 3) Sign APK
"$APKSIGNER" sign --ks "$KS_FILE" \
  --ks-key-alias "$KS_ALIAS" \
  --ks-pass pass:"$KS_PASS" \
  --key-pass pass:"$KEY_PASS" \
  --out "$BUILD_DIR/battery-overlay.apk" \
  "$BUILD_DIR/unsigned.apk"

# 4) Package Magisk module
echo "📦 Packaging Magisk module..."

# Install overlay to both vendor and product for better compatibility
mkdir -p "$DIST_DIR/system/vendor/overlay" "$DIST_DIR/system/product/overlay" "$DIST_DIR/META-INF/com/google/android"
cp "$BUILD_DIR/battery-overlay.apk" "$DIST_DIR/system/vendor/overlay/"
cp "$BUILD_DIR/battery-overlay.apk" "$DIST_DIR/system/product/overlay/"
cp "$ROOT_DIR/module/module.prop" "$DIST_DIR/"

# Copy service.sh if exists
[ -f "$ROOT_DIR/module/service.sh" ] && cp "$ROOT_DIR/module/service.sh" "$DIST_DIR/"

# Copy lifecycle scripts
[ -f "$ROOT_DIR/module/uninstall.sh" ] && cp "$ROOT_DIR/module/uninstall.sh" "$DIST_DIR/"

# Copy system.prop ONLY if it was generated in this build
if [ -n "$BUILD_SYSTEM_PROP" ] && [ -f "$BUILD_SYSTEM_PROP" ]; then
  cp "$BUILD_SYSTEM_PROP" "$DIST_DIR/system.prop"
  echo "  ✓ system.prop included"
else
  echo "  ℹ️  No system.prop (no property overrides)"
fi

# Use the standard Magisk installer template
cp "$ROOT_DIR/module/META-INF/com/google/android/update-binary" "$DIST_DIR/META-INF/com/google/android/"
echo '#MAGISK' > "$DIST_DIR/META-INF/com/google/android/updater-script"
chmod 0755 "$DIST_DIR/META-INF/com/google/android/update-binary" 2>/dev/null || true
[ -f "$DIST_DIR/service.sh" ] && chmod 0755 "$DIST_DIR/service.sh" 2>/dev/null || true
[ -f "$DIST_DIR/uninstall.sh" ] && chmod 0755 "$DIST_DIR/uninstall.sh" 2>/dev/null || true

( cd "$DIST_DIR" && zip -r "$OUTPUT_ZIP" . )

# Clean up temporary keystore for security
rm -f "$KS_FILE"

echo "Build complete: $OUTPUT_ZIP"
