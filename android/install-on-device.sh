#!/bin/zsh
# Builds Plan UBB, signs it with the local debug key and installs it on a USB-connected Android phone.
#
#   ./install-on-device.sh            # release build, first phone on USB
#   BUILD_TYPE=debug ./install-on-device.sh
#   DEVICE_ID=<serial> ./install-on-device.sh
#
# The phone needs Developer options → USB debugging turned on, and this Mac allowed.
set -euo pipefail

cd "${0:A:h}"

BUILD_TYPE="${BUILD_TYPE:-release}"
APP_ID="it.mwojtowicz.planubb"
DEBUG_KEYSTORE="$HOME/.android/debug.keystore"

if [[ -z "${JAVA_HOME:-}" ]] && ! /usr/libexec/java_home >/dev/null 2>&1; then
  export JAVA_HOME="$HOME/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  [[ -d "$JAVA_HOME" ]] || export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi

SDK_DIR="${ANDROID_HOME:-$(sed -n 's/^sdk\.dir=//p' local.properties 2>/dev/null)}"
SDK_DIR="${SDK_DIR:-$HOME/Library/Android/sdk}"
ADB="$SDK_DIR/platform-tools/adb"
[[ -x "$ADB" ]] || ADB="$(command -v adb)" || { echo "adb not found. Install the Android SDK platform-tools." >&2; exit 1; }

if [[ -z "${DEVICE_ID:-}" ]]; then
  # Lines look like: <serial>  device usb:1-1 product:… model:… — wireless debugging has no usb: field.
  devices="$("$ADB" devices -l | tail -n +2)"
  DEVICE_ID="$(awk '$2 == "device" && / usb:/ { print $1; exit }' <<< "$devices")"
  if [[ -z "$DEVICE_ID" ]]; then
    if grep -q unauthorized <<< "$devices"; then
      echo "The phone hasn't allowed this Mac yet. Unlock it and accept the USB debugging prompt." >&2
    else
      echo "No phone connected over USB. Plug it in and turn on Developer options → USB debugging." >&2
    fi
    exit 1
  fi
fi
echo "==> Device: $DEVICE_ID ($("$ADB" -s "$DEVICE_ID" shell getprop ro.product.model | tr -d '\r')), build: $BUILD_TYPE"

task="assemble${(C)BUILD_TYPE}"
signing=()
if [[ "$BUILD_TYPE" == release ]]; then
  if [[ ! -f "$DEBUG_KEYSTORE" ]]; then
    echo "==> Creating debug keystore"
    mkdir -p "${DEBUG_KEYSTORE:h}"
    "${JAVA_HOME:+$JAVA_HOME/bin/}keytool" -genkeypair -keystore "$DEBUG_KEYSTORE" -storepass android \
      -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 \
      -dname "CN=Android Debug,O=Android,C=US" >/dev/null
  fi
  # Same mechanism Android Studio uses for "Generate Signed APK"; build.gradle.kts stays untouched.
  signing=(
    -Pandroid.injected.signing.store.file="$DEBUG_KEYSTORE"
    -Pandroid.injected.signing.store.password=android
    -Pandroid.injected.signing.key.alias=androiddebugkey
    -Pandroid.injected.signing.key.password=android
  )
fi

echo "==> Building and signing"
./gradlew --quiet ":app:$task" "${signing[@]}"

APK="app/build/outputs/apk/$BUILD_TYPE/app-$BUILD_TYPE.apk"

echo "==> Installing $APK"
if ! "$ADB" -s "$DEVICE_ID" install -r "$APK"; then
  echo "Install failed. If it's a signature mismatch, an older copy was signed with a different key:" >&2
  echo "  $ADB -s $DEVICE_ID uninstall $APP_ID   (this deletes the app's data)" >&2
  exit 1
fi

echo "==> Launching"
"$ADB" -s "$DEVICE_ID" shell am start -n "$APP_ID/.ui.MainActivity" >/dev/null
echo "Launched $APP_ID."
