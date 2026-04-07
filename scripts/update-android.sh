#!/bin/bash
# Replace Android template files in a test project (development tool)
# Overwrites template files in-place, preserving cart/, .git, .gitignore, README.md.
# Intended for template development iteration, not end-user project updates.
#
# Usage:
#   ./scripts/update-android.sh <target-dir> [options]
#
# Options:
#   --replace-mono-engine   Also delete and recreate cart/.mono/ with latest engine
#   --dry-run               Show what would be done without making changes
#
# Examples:
#   ./scripts/update-android.sh ~/mono/android/pong
#   ./scripts/update-android.sh ~/mono/android/pong --replace-mono-engine

set -e

MONO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE_DIR="$MONO_ROOT/android"

# --- Parse arguments ---
TARGET_DIR=""
REPLACE_ENGINE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --replace-mono-engine) REPLACE_ENGINE=true; shift ;;
    --dry-run)             DRY_RUN=true; shift ;;
    -*)                    echo "Unknown option: $1"; exit 1 ;;
    *)
      if [ -z "$TARGET_DIR" ]; then
        TARGET_DIR="$1"; shift
      else
        echo "Unexpected argument: $1"; exit 1
      fi
      ;;
  esac
done

if [ -z "$TARGET_DIR" ]; then
  echo "Usage: $0 <target-dir> [--replace-mono-engine] [--dry-run]"
  echo ""
  echo "  target-dir              Existing Android project directory (required)"
  echo "  --replace-mono-engine   Delete and recreate cart/.mono/ with latest engine"
  echo "  --dry-run               Show what would be done without making changes"
  exit 1
fi

if [ ! -d "$TARGET_DIR" ]; then
  echo "Error: $TARGET_DIR does not exist"
  exit 1
fi

if [ ! -d "$TARGET_DIR/app" ]; then
  echo "Error: $TARGET_DIR/app not found — is this a Mono Android project?"
  exit 1
fi

# --- Helpers ---
run() {
  if $DRY_RUN; then
    echo "  [dry-run] $*"
  else
    "$@"
  fi
}

log() {
  echo "  $1"
}

echo "Replacing template in: $TARGET_DIR"
echo ""

# --- 1. Preserve user customizations ---
APP_NAME=""
APP_ID=""
PROJ_NAME=""
if [ -f "$TARGET_DIR/app/src/main/res/values/strings.xml" ]; then
  APP_NAME=$(grep -o '>.*<' "$TARGET_DIR/app/src/main/res/values/strings.xml" | head -1 | tr -d '><')
fi
if [ -f "$TARGET_DIR/app/build.gradle.kts" ]; then
  APP_ID=$(grep 'applicationId' "$TARGET_DIR/app/build.gradle.kts" | head -1 | sed 's/.*"\(.*\)".*/\1/')
fi
if [ -f "$TARGET_DIR/settings.gradle.kts" ]; then
  PROJ_NAME=$(grep 'rootProject.name' "$TARGET_DIR/settings.gradle.kts" | head -1 | sed 's/.*"\(.*\)".*/\1/')
fi

log "Preserved: name=\"$APP_NAME\" id=\"$APP_ID\" project=\"$PROJ_NAME\""

# --- 2. Copy template files (overwrite) ---
echo ""
echo "Copying latest template..."
for item in "$TEMPLATE_DIR"/*; do
  name="$(basename "$item")"
  case "$name" in
    .gitignore|README.md) ;; # only create if missing (below)
    *)
      if [ -d "$item" ]; then
        run rm -rf "$TARGET_DIR/$name"
        run cp -R "$item" "$TARGET_DIR/$name"
      else
        run cp "$item" "$TARGET_DIR/"
      fi
      log "COPY $name"
      ;;
  esac
done
# Make scripts executable
for f in "$TARGET_DIR"/gradlew "$TARGET_DIR"/*.sh; do
  [ -f "$f" ] && run chmod +x "$f"
done
# Only create .gitignore and README.md if missing (preserve user edits)
if [ ! -f "$TARGET_DIR/.gitignore" ]; then
  run cp "$TEMPLATE_DIR/.gitignore" "$TARGET_DIR/"
  log ".gitignore created (was missing)"
fi
if [ ! -f "$TARGET_DIR/README.md" ]; then
  run cp "$TEMPLATE_DIR/README.md" "$TARGET_DIR/"
  log "README.md created (was missing)"
fi

# --- 3. Restore user customizations ---
echo ""
echo "Restoring customizations..."
if [ -n "$PROJ_NAME" ] && ! $DRY_RUN; then
  sed -i '' "s/rootProject.name = \"mono-android\"/rootProject.name = \"$PROJ_NAME\"/" "$TARGET_DIR/settings.gradle.kts"
  log "Project name → $PROJ_NAME"
fi
if [ -n "$APP_ID" ] && ! $DRY_RUN; then
  sed -i '' "s/applicationId = \"com.mono.game\"/applicationId = \"$APP_ID\"/" "$TARGET_DIR/app/build.gradle.kts"
  log "Application ID → $APP_ID"
fi
if [ -n "$APP_NAME" ] && ! $DRY_RUN; then
  sed -i '' "s/>Mono Game</>$APP_NAME</" "$TARGET_DIR/app/src/main/res/values/strings.xml"
  log "App name → $APP_NAME"
fi

# --- 4. Optionally replace cart/.mono/ engine ---
if $REPLACE_ENGINE; then
  echo ""
  echo "Replacing cart/.mono/ engine..."
  run rm -rf "$TARGET_DIR/cart/.mono"
  run mkdir -p "$TARGET_DIR/cart/.mono"

  run mkdir -p "$TARGET_DIR/cart/.mono/shaders"

  if ! $DRY_RUN; then
    cp "$MONO_ROOT/runtime/engine.js" "$TARGET_DIR/cart/.mono/engine.js"
    cp "$MONO_ROOT/runtime/console-gamepad.js" "$TARGET_DIR/cart/.mono/console-gamepad.js"
    cp "$MONO_ROOT/runtime/shader.js" "$TARGET_DIR/cart/.mono/shader.js"
    for sf in tint.js lcd.js lcd3d.js crt.js scanlines.js invert_lcd.js; do
      cp "$MONO_ROOT/runtime/shaders/$sf" "$TARGET_DIR/cart/.mono/shaders/$sf"
    done

    VERSION=$(grep -o 'const MONO_VERSION = "[^"]*"' "$MONO_ROOT/editor/index.html" | head -1 | cut -d'"' -f2)
    echo "$VERSION" > "$TARGET_DIR/cart/.mono/VERSION"
    log "Engine updated to v$VERSION"
  else
    log "[dry-run] Would copy engine.js, console-gamepad.js, VERSION"
  fi
fi

# --- Done ---
echo ""
echo "Done! Template replaced: $TARGET_DIR"
if $REPLACE_ENGINE; then
  VERSION=$(grep -o 'const MONO_VERSION = "[^"]*"' "$MONO_ROOT/editor/index.html" | head -1 | cut -d'"' -f2)
  echo "  Engine: v$VERSION"
fi
echo ""
echo "Next: cd $TARGET_DIR && ./run-debug.sh"
