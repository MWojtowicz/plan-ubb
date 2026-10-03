#!/bin/zsh
# Builds the release APK for publishing (e.g. on GitHub Releases), signed with the Plan UBB release key.
#
#   ./build-release.sh        # → build/release/plan-ubb-<version>.apk
#
# The first run creates the key: ~/.android/planubb-release.jks, with a random password kept in the
# macOS Keychain (item "planubb-release-keystore"). Back up both. Every update must be signed with
# the same key, or Android refuses to install it over the old version.
set -euo pipefail

cd "${0:A:h}"

KEYSTORE="${KEYSTORE:-$HOME/.android/planubb-release.jks}"
KEY_ALIAS="planubb"
KEYCHAIN_ITEM="planubb-release-keystore"

if [[ -z "${JAVA_HOME:-}" ]] && ! /usr/libexec/java_home >/dev/null 2>&1; then
  export JAVA_HOME="$HOME/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  [[ -d "$JAVA_HOME" ]] || export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi
KEYTOOL="${JAVA_HOME:+$JAVA_HOME/bin/}keytool"

SDK_DIR="${ANDROID_HOME:-$(sed -n 's/^sdk\.dir=//p' local.properties 2>/dev/null)}"
SDK_DIR="${SDK_DIR:-$HOME/Library/Android/sdk}"
APKSIGNER="$(ls -d "$SDK_DIR"/build-tools/*/apksigner | sort -V | tail -1)"

if [[ ! -f "$KEYSTORE" ]]; then
  if security find-generic-password -s "$KEYCHAIN_ITEM" >/dev/null 2>&1; then
    echo "The Keychain has a password for the release key, but $KEYSTORE is missing." >&2
    echo "Restore the keystore from your backup (or set KEYSTORE=<path>); a new key couldn't update installed copies." >&2
    exit 1
  fi
  echo "==> Creating the release key at $KEYSTORE"
  password="$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)"
  security add-generic-password -s "$KEYCHAIN_ITEM" -a "$KEY_ALIAS" -l "Plan UBB release keystore" -w "$password"
  mkdir -p "${KEYSTORE:h}"
  "$KEYTOOL" -genkeypair -keystore "$KEYSTORE" -storetype PKCS12 -storepass "$password" -keypass "$password" \
    -alias "$KEY_ALIAS" -keyalg RSA -keysize 4096 -validity 18250 \
    -dname "CN=Plan UBB, O=$(git config user.name || echo Plan UBB)"
  chmod 600 "$KEYSTORE"
  echo "    Back up $KEYSTORE and the Keychain item \"$KEYCHAIN_ITEM\"."
fi
password="$(security find-generic-password -s "$KEYCHAIN_ITEM" -w)"

echo "==> Running the unit tests"
./gradlew --quiet :app:testDebugUnitTest

echo "==> Building and signing the release APK"
# Same mechanism Android Studio uses for "Generate Signed APK"; build.gradle.kts stays untouched.
./gradlew --quiet :app:assembleRelease \
  -Pandroid.injected.signing.store.file="$KEYSTORE" \
  -Pandroid.injected.signing.store.password="$password" \
  -Pandroid.injected.signing.key.alias="$KEY_ALIAS" \
  -Pandroid.injected.signing.key.password="$password"

version="$(sed -n 's/.*versionName = "\(.*\)"/\1/p' app/build.gradle.kts)"
mkdir -p build/release
APK="build/release/plan-ubb-$version.apk"
cp app/build/outputs/apk/release/app-release.apk "$APK"

echo "==> Checking the signature"
"$APKSIGNER" verify --print-certs "$APK" 2>/dev/null | grep -E "certificate (DN|SHA-256)"
echo "Release APK: ${APK:A} ($(du -h "$APK" | cut -f1 | tr -d ' '))"
