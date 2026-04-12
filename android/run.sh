#!/bin/bash
# Build APK and install+launch on connected device/emulator
# Usage: ./run.sh [--release] [--clean] [--FLAG[=VALUE] ...]
#
#   --release       Build signed release APK (requires app/key.properties)
#   --clean         Clean before build
#   --UPPER_FLAG    Pass "UPPER_FLAG=true" as intent extra to the app
#   --KEY=VALUE     Pass "KEY=VALUE" as intent extra to the app
#
# Examples:
#   ./run.sh                              # debug build, no flags
#   ./run.sh --release --clean            # clean release build
#   ./run.sh --DEMO_MODE --NO_ADS         # debug + app flags
#   ./run.sh --release --LEVEL=5          # release + app flag with value
set -e

cd "$(dirname "$0")"

RELEASE=false
CLEAN=""
LAUNCH_FLAGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release) RELEASE=true; shift ;;
    --clean)   CLEAN="clean"; shift ;;
    --[A-Z]*)
      # Uppercase flags are passed through as intent extras.
      # --FLAG       → --es FLAG true
      # --FLAG=val   → --es FLAG val
      KEY="${1#--}"
      if [[ "$KEY" == *=* ]]; then
        LAUNCH_FLAGS+=(--es "${KEY%%=*}" "${KEY#*=}")
      else
        LAUNCH_FLAGS+=(--es "$KEY" "true")
      fi
      shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
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
if [ ${#LAUNCH_FLAGS[@]} -gt 0 ]; then
  echo "  Flags: ${LAUNCH_FLAGS[*]}"
fi
adb shell am start -n "$APP_ID/$NAMESPACE.MainActivity" "${LAUNCH_FLAGS[@]}"
