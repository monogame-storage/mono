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
INSTALL_LOG=/tmp/mono-adb-install.log

# adb install exit code is unreliable on some devices; check output for "Failure".
try_install() {
  adb install "$@" 2>&1 | tee "$INSTALL_LOG"
  ! grep -qi '^Failure' "$INSTALL_LOG"
}

if ! try_install -r "$APK"; then
  if grep -qE 'INSTALL_FAILED_UPDATE_INCOMPATIBLE|INSTALL_FAILED_VERSION_DOWNGRADE|INSTALL_FAILED_ALREADY_EXISTS|signatures do not match' "$INSTALL_LOG"; then
    echo "Install blocked (signing or version conflict) — uninstalling previous build and retrying..."
    adb uninstall "$APP_ID" || true
    try_install "$APK" || { echo "Install failed after uninstall."; exit 1; }
  else
    echo "Install failed — see output above."
    exit 1
  fi
fi

echo "Launching $APP_ID..."
adb shell am start -n "$APP_ID/$NAMESPACE.MainActivity"
