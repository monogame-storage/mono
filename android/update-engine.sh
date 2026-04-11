#!/bin/bash
# Update cart/.mono/ engine files to the latest from the Mono repo.
# Everything else (app/, gradle/, run.sh, etc.) is left untouched.
#
# Usage: ./update-engine.sh
#
# Requires: MONO_ROOT environment variable pointing to the mono repo root.
set -e

# Resolve project dir = where this script lives
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$MONO_ROOT" ]; then
  echo "Error: MONO_ROOT environment variable is not set." >&2
  echo "  Add this to ~/.zshrc (or equivalent):" >&2
  echo "    export MONO_ROOT=\"\$HOME/work/mono\"" >&2
  exit 1
fi

CREATE_ANDROID="$MONO_ROOT/scripts/create-android.sh"
if [ ! -f "$CREATE_ANDROID" ]; then
  echo "Error: $CREATE_ANDROID not found." >&2
  echo "  MONO_ROOT=$MONO_ROOT" >&2
  exit 1
fi

exec "$CREATE_ANDROID" "$PROJECT_DIR" --replace-engine
