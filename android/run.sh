#!/bin/bash
# Build APK and install+launch on connected device/emulator
# Usage: ./run.sh [--release] [--clean]
#   --release  Build signed release APK (requires app/key.properties)
#   --clean    Clean before build
set -e

cd "$(dirname "$0")"

RELEASE=false
CLEAN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release) RELEASE=true; shift ;;
    --clean)   CLEAN="clean"; shift ;;
    *)         echo "Unknown option: $1"; exit 1 ;;
  esac
done

APP_ID=$(grep 'applicationId' app/build.gradle.kts | head -1 | sed 's/.*"\(.*\)".*/\1/')
NAMESPACE=$(grep 'namespace' app/build.gradle.kts | head -1 | sed 's/.*"\(.*\)".*/\1/')

if $RELEASE; then
  VARIANT="release"
  TASK="assembleRelease"
  APK="app/build/outputs/apk/release/app-release.apk"
else
  VARIANT="debug"
  TASK="assembleDebug"
  APK="app/build/outputs/apk/debug/app-debug.apk"
fi

echo "Building $VARIANT APK..."
./gradlew $CLEAN $TASK -q

echo "Installing..."
if ! adb install -r "$APK" 2>&1 | tee /tmp/mono-adb-install.log; then
  if grep -q 'INSTALL_FAILED_UPDATE_INCOMPATIBLE\|signatures do not match' /tmp/mono-adb-install.log; then
    echo "Signature mismatch — uninstalling previous build and retrying..."
    adb uninstall "$APP_ID" || true
    adb install "$APK"
  else
    exit 1
  fi
fi

echo "Launching $APP_ID..."
adb shell am start -n "$APP_ID/$NAMESPACE.MainActivity"
