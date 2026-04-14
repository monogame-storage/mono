#!/bin/bash
# Refresh the Android template (app/, gradle/, scripts, etc.) to the latest.
# Preserves cart/ (game files), .git, .gitignore, README.md.
# After refresh, re-runs the googleplay pipeline if GOOGLEPLAY_TEMPLATE_ROOT is set.
#
# Usage: ./update-android.sh
#
# Requires: MONO_ROOT, optionally GOOGLEPLAY_TEMPLATE_ROOT
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$MONO_ROOT" ]; then
  echo "Error: MONO_ROOT environment variable is not set." >&2
  exit 1
fi

CREATE_ANDROID="$MONO_ROOT/scripts/create-android.sh"
if [ ! -f "$CREATE_ANDROID" ]; then
  echo "Error: $CREATE_ANDROID not found." >&2
  exit 1
fi

# Refresh android template (wipes app/, re-copies gradle/scripts)
"$CREATE_ANDROID" "$PROJECT_DIR"

# Re-apply googleplay setup if config exists and template root is set
CONFIG="$(find "$PROJECT_DIR/.." -maxdepth 1 -name "$(basename "$PROJECT_DIR").properties" 2>/dev/null | head -1)"
if [ -n "$GOOGLEPLAY_TEMPLATE_ROOT" ] && [ -n "$CONFIG" ]; then
  echo ""
  echo "Re-applying googleplay setup from $CONFIG ..."
  "$GOOGLEPLAY_TEMPLATE_ROOT/create-playstore-app.sh" "$PROJECT_DIR" --config "$CONFIG" --replace-android
fi
