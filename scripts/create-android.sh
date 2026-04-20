#!/bin/bash
# Mono Android project generator / updater
#
# New directory  → creates project from template
# Existing dir   → updates template files, preserving cart/, .git, .gitignore, README.md
#
# Usage:
#   ./scripts/create-android.sh <target-dir> [options]
#
# Options:
#   --project-name "Name"   Display name (default: derived from directory name)
#   --package com.ssk.pong  Full package name (default: com.mono.<dir-name>)
#   --replace-engine   Replace cart/.mono/ with latest engine (update mode only)
#   --dry-run               Show what would be done without making changes
#
# Examples:
#   ./scripts/create-android.sh ~/projects/mono-pong
#   ./scripts/create-android.sh ~/projects/mono-pong --project-name "Mono Pong" --package com.ssk.pong
#   ./scripts/create-android.sh ~/mono/android/pong --replace-engine

set -e

MONO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE_DIR="$MONO_ROOT/android"

# --- Parse arguments ---
TARGET_DIR=""
PROJECT_NAME=""
PACKAGE=""
ICON=""
REPLACE_ENGINE=false
KEEP_ANDROID=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-name)        PROJECT_NAME="$2"; shift 2 ;;
    --package)             PACKAGE="$2"; shift 2 ;;
    --icon)                ICON="$2"; shift 2 ;;
    --replace-engine) REPLACE_ENGINE=true; shift ;;
    --keep-android)   KEEP_ANDROID=true; shift ;;
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
  echo "Usage: $0 <target-dir> [options]"
  echo ""
  echo "  target-dir              Project directory (created if new, updated if exists)"
  echo "  --project-name \"Name\"   Display name (default: derived from dir name)"
  echo "  --package com.ssk.pong  Full package name (default: com.mono.<dir-name>)"
  echo "  --icon icon.png         App icon (PNG, 512x512 recommended)"
  echo "  --replace-engine        Replace cart/.mono/ ONLY (skips template refresh)"
  echo "  --keep-android          Keep app/ as-is (only update non-app template files)"
  echo "  --dry-run               Show what would be done without making changes"
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

copy_engine_files() {
  local mono_dir="$1"
  cp "$MONO_ROOT/runtime/engine.js" "$mono_dir/engine.js"
  cp "$MONO_ROOT/runtime/console-gamepad.js" "$mono_dir/console-gamepad.js"
  cp "$MONO_ROOT/runtime/shader.js" "$mono_dir/shader.js"
  # Copy template files (excluding main.lua which goes to cart/)
  for f in "$MONO_ROOT/editor/templates/mono/"*; do
    local name=$(basename "$f")
    case "$name" in
      main.lua) ;;
      *) cp -R "$f" "$mono_dir/" ;;
    esac
  done
  for sf in tint.js lcd.js lcd3d.js crt.js scanlines.js invert_lcd.js; do
    cp "$MONO_ROOT/runtime/shaders/$sf" "$mono_dir/shaders/$sf"
  done
  local version=$(grep -o 'const MONO_VERSION = "[^"]*"' "$MONO_ROOT/editor/index.html" | head -1 | cut -d'"' -f2)
  echo "$version" > "$mono_dir/VERSION"
  # Write engine major.minor for cart.json compatibility checks
  echo "$version" | cut -d. -f1,2 > "$mono_dir/ENGINE"
  # Substitute template placeholders in CONTEXT.md ({{VERSION}}, {{BASE_URL}})
  if [ -f "$mono_dir/CONTEXT.md" ]; then
    local base_url="https://github.com/monogame-storage/mono/blob/main"
    sed -i '' -e "s|{{VERSION}}|$version|g" -e "s|{{BASE_URL}}|$base_url|g" "$mono_dir/CONTEXT.md"
  fi
}

generate_icons() {
  local src="$1" dst="$2"
  if ! command -v magick &>/dev/null; then
    echo "  Warning: ImageMagick not found, skipping icon generation"
    return
  fi
  if $DRY_RUN; then
    log "[dry-run] Would generate icons from $(basename "$src")"
    return
  fi
  magick "$src" -resize 48x48   "$dst/mipmap-mdpi/ic_launcher.png"
  magick "$src" -resize 72x72   "$dst/mipmap-hdpi/ic_launcher.png"
  magick "$src" -resize 96x96   "$dst/mipmap-xhdpi/ic_launcher.png"
  magick "$src" -resize 144x144 "$dst/mipmap-xxhdpi/ic_launcher.png"
  magick "$src" -resize 192x192 "$dst/mipmap-xxxhdpi/ic_launcher.png"
  log "Icon generated from $(basename "$src")"
}

# --- Detect mode ---
if [ -d "$TARGET_DIR" ] && [ -d "$TARGET_DIR/app" ]; then
  MODE="update"
else
  MODE="create"
fi

DIR_NAME="$(basename "$TARGET_DIR")"

# ======================================================================
#  UPDATE MODE — existing project
# ======================================================================
if [ "$MODE" = "update" ]; then
  echo "Updating Mono Android project: $TARGET_DIR"
  echo ""

  # Engine-only mode: refresh cart/.mono/ + app/templates/, skip everything
  # else (no app/, no gradle, no customization preserve/restore).
  if $REPLACE_ENGINE; then
    echo "Replacing cart/.mono/ engine (engine-only)..."
    run rm -rf "$TARGET_DIR/cart/.mono"
    run mkdir -p "$TARGET_DIR/cart/.mono/shaders"
    if ! $DRY_RUN; then
      copy_engine_files "$TARGET_DIR/cart/.mono"
      log "Engine updated to v$(cat "$TARGET_DIR/cart/.mono/VERSION")"
    else
      log "[dry-run] Would replace engine files"
    fi

    # Refresh app/templates/ (index.html etc.) — engine updates often pair
    # with HTML/CSS changes that must stay in sync.
    if [ -d "$TEMPLATE_DIR/app/templates" ]; then
      run rm -rf "$TARGET_DIR/app/templates"
      run cp -R "$TEMPLATE_DIR/app/templates" "$TARGET_DIR/app/templates"
      log "Refreshed app/templates/"
    fi

    echo ""
    echo "Done! Engine updated: $TARGET_DIR"
    exit 0
  fi

  # Preserve user customizations
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

  # Copy template files (overwrite)
  echo ""
  echo "Copying latest template..."
  for item in "$TEMPLATE_DIR"/*; do
    name="$(basename "$item")"
    case "$name" in
      .gitignore|README.md|cart) ;; # preserve user data
      app|settings.gradle.kts)
        if $KEEP_ANDROID; then
          log "KEEP $name (--keep-android)"
        else
          run rm -rf "$TARGET_DIR/$name"
          run cp -R "$item" "$TARGET_DIR/$name"
          log "COPY $name"
        fi
        ;;
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
  for f in "$TARGET_DIR"/gradlew "$TARGET_DIR"/*.sh; do
    [ -f "$f" ] && run chmod +x "$f"
  done
  if [ ! -f "$TARGET_DIR/.gitignore" ]; then
    run cp "$TEMPLATE_DIR/.gitignore" "$TARGET_DIR/"
    log ".gitignore created (was missing)"
  fi
  if [ ! -f "$TARGET_DIR/README.md" ]; then
    run cp "$TEMPLATE_DIR/README.md" "$TARGET_DIR/"
    log "README.md created (was missing)"
  fi

  # Restore customizations
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

  # Custom icon
  if [ -n "$ICON" ] && ! $DRY_RUN; then
    generate_icons "$ICON" "$TARGET_DIR/app/src/main/res"
  fi

  echo ""
  echo "Done! Updated: $TARGET_DIR"
  echo ""
  echo "Next: cd $TARGET_DIR && ./run.sh"
  exit 0
fi

# ======================================================================
#  CREATE MODE — new project
# ======================================================================

if [ -z "$PROJECT_NAME" ]; then
  PROJECT_NAME="$(echo "$DIR_NAME" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')"
fi

if [ -z "$PACKAGE" ]; then
  APP_SUFFIX="$(echo "$DIR_NAME" | tr '-' '.' | tr '[:upper:]' '[:lower:]')"
  PACKAGE="com.mono.${APP_SUFFIX}"
fi

APP_ID="$PACKAGE"

echo "Creating Mono Android project: $PROJECT_NAME"

# 1. Copy template
run mkdir -p "$TARGET_DIR"
if ! $DRY_RUN; then
  for item in "$TEMPLATE_DIR"/*; do
    name="$(basename "$item")"
    if [ -d "$item" ]; then
      cp -R "$item" "$TARGET_DIR/$name"
    else
      cp "$item" "$TARGET_DIR/"
    fi
  done
  cp "$TEMPLATE_DIR/.gitignore" "$TARGET_DIR/"
  for f in "$TARGET_DIR"/gradlew "$TARGET_DIR"/*.sh; do
    [ -f "$f" ] && chmod +x "$f"
  done
fi

# 2. Generate local.properties with SDK path
if ! $DRY_RUN; then
  if [ -n "$ANDROID_HOME" ]; then
    echo "sdk.dir=$ANDROID_HOME" > "$TARGET_DIR/local.properties"
  elif [ -d "$HOME/Library/Android/sdk" ]; then
    echo "sdk.dir=$HOME/Library/Android/sdk" > "$TARGET_DIR/local.properties"
  elif [ -d "$HOME/Android/Sdk" ]; then
    echo "sdk.dir=$HOME/Android/Sdk" > "$TARGET_DIR/local.properties"
  fi
fi

# 3. Set up cart/.mono/ with engine + shader files
run mkdir -p "$TARGET_DIR/cart/.mono/shaders"
if ! $DRY_RUN; then
  copy_engine_files "$TARGET_DIR/cart/.mono"
fi

# 4. Create starter scene files + default shader.json
if ! $DRY_RUN; then
  title_esc=$(printf '%s' "$PROJECT_NAME" | sed -e 's/[\\&|]/\\&/g')
  for f in main.lua title.lua game.lua gameover.lua; do
    sed "s|%TITLE%|$title_esc|g" "$MONO_ROOT/templates/game/$f" > "$TARGET_DIR/cart/$f"
  done
  cat > "$TARGET_DIR/cart/shader.json" << 'SHADER_EOF'
{
  "chain": ["tint", "lcd"],
  "params": {
    "tint": { "tint": [1.0, 0.75, 0.3] },
    "lcd": { "thickness": 0.20, "pixel_size": 1.0, "bg_color": [0, 0, 0], "bg_color2": [0.19, 0.19, 0.19], "bg_dir": 0.0 },
    "lcd3d": { "thickness": 0.20, "pixel_size": 1.0, "depth": 1.0, "bg_color": [0, 0, 0], "bg_color2": [0.19, 0.19, 0.19], "bg_dir": 0.0 },
    "crt": { "curvature": 0.02, "vignette": 0.1 },
    "scanlines": { "opacity": 0.2 },
    "invert_lcd": { "gap": 0.20, "bg_color": [0.72, 0.74, 0.42], "dot_color": [0, 0, 0], "vignette": 1.0 }
  }
}
SHADER_EOF
fi

# 5. Customize project
if ! $DRY_RUN; then
  sed -i '' "s/rootProject.name = \"mono-android\"/rootProject.name = \"$DIR_NAME\"/" "$TARGET_DIR/settings.gradle.kts"
  sed -i '' "s/applicationId = \"com.mono.game\"/applicationId = \"$APP_ID\"/" "$TARGET_DIR/app/build.gradle.kts"
  sed -i '' "s/>Mono Game</>$PROJECT_NAME</" "$TARGET_DIR/app/src/main/res/values/strings.xml"
  if [ -n "$ICON" ]; then
    generate_icons "$ICON" "$TARGET_DIR/app/src/main/res"
  fi
fi

VERSION=$(grep -o 'const MONO_VERSION = "[^"]*"' "$MONO_ROOT/editor/index.html" | head -1 | cut -d'"' -f2)
echo ""
echo "Done! Project created at: $TARGET_DIR"
echo ""
echo "  App name:  $PROJECT_NAME"
echo "  Package:   $APP_ID"
echo "  Engine:    v$VERSION"
echo ""
echo "Next steps:"
echo "  cd $TARGET_DIR"
echo "  # Edit cart/main.lua or deploy from Mono editor"
echo "  ./run.sh"
