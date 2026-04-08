#!/bin/bash
# Build debug APK and install+launch on connected device/emulator
# Usage: ./run-debug.sh [--clean]
set -e

cd "$(dirname "$0")"

CLEAN=""
if [ "$1" = "--clean" ]; then CLEAN="clean"; fi

APP_ID=$(grep 'applicationId' app/build.gradle.kts | head -1 | sed 's/.*"\(.*\)".*/\1/')
NAMESPACE=$(grep 'namespace' app/build.gradle.kts | head -1 | sed 's/.*"\(.*\)".*/\1/')

echo "Building debug APK..."
./gradlew $CLEAN assembleDebug -q

echo "Installing..."
adb install -r app/build/outputs/apk/debug/app-debug.apk

echo "Launching $APP_ID..."
adb shell am start -n "$APP_ID/$NAMESPACE.MainActivity"
