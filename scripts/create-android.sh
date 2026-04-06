#!/bin/bash
# Mono Android project generator
# Usage: ./scripts/create-android.sh <target-dir> [options]
#
# Example:
#   ./scripts/create-android.sh ~/projects/mono-pong
#   ./scripts/create-android.sh ~/projects/mono-pong --project-name "Mono Pong" --org com.ssk

set -e

MONO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE_DIR="$MONO_ROOT/android"

# --- Parse arguments ---
TARGET_DIR=""
PROJECT_NAME=""
ORG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-name) PROJECT_NAME="$2"; shift 2 ;;
    --org)          ORG="$2"; shift 2 ;;
    -*)             echo "Unknown option: $1"; exit 1 ;;
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
  echo "Usage: $0 <target-dir> [--project-name \"My Game\"] [--org com.example]"
  echo ""
  echo "  target-dir      Project directory to create (required)"
  echo "  --project-name  Display name (default: derived from directory name)"
  echo "  --org           Organization package (default: com.mono)"
  exit 1
fi

# Derive defaults from target directory name
DIR_NAME="$(basename "$TARGET_DIR")"

if [ -z "$PROJECT_NAME" ]; then
  # mono-pong → Mono Pong
  PROJECT_NAME="$(echo "$DIR_NAME" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')"
fi

if [ -z "$ORG" ]; then
  ORG="com.mono"
fi

# com.ssk + mono-pong → com.ssk.mono.pong
APP_SUFFIX="$(echo "$DIR_NAME" | tr '-' '.' | tr '[:upper:]' '[:lower:]')"
APP_ID="${ORG}.${APP_SUFFIX}"

if [ -d "$TARGET_DIR" ]; then
  echo "Error: $TARGET_DIR already exists"
  exit 1
fi

echo "Creating Mono Android project: $PROJECT_NAME"

# 1. Copy template
mkdir -p "$TARGET_DIR"
cp -R "$TEMPLATE_DIR/app" "$TARGET_DIR/app"
cp -R "$TEMPLATE_DIR/gradle" "$TARGET_DIR/gradle"
cp "$TEMPLATE_DIR/build.gradle.kts" "$TARGET_DIR/"
cp "$TEMPLATE_DIR/settings.gradle.kts" "$TARGET_DIR/"
cp "$TEMPLATE_DIR/gradlew" "$TARGET_DIR/"
cp "$TEMPLATE_DIR/gradlew.bat" "$TARGET_DIR/"
chmod +x "$TARGET_DIR/gradlew"
cp "$TEMPLATE_DIR/.gitignore" "$TARGET_DIR/"
cp "$TEMPLATE_DIR/README.md" "$TARGET_DIR/"

# 2. Generate local.properties with SDK path
if [ -n "$ANDROID_HOME" ]; then
  echo "sdk.dir=$ANDROID_HOME" > "$TARGET_DIR/local.properties"
elif [ -d "$HOME/Library/Android/sdk" ]; then
  echo "sdk.dir=$HOME/Library/Android/sdk" > "$TARGET_DIR/local.properties"
elif [ -d "$HOME/Android/Sdk" ]; then
  echo "sdk.dir=$HOME/Android/Sdk" > "$TARGET_DIR/local.properties"
fi

# 3. Set up cart/.mono/ with engine files
mkdir -p "$TARGET_DIR/cart/.mono"
cp "$MONO_ROOT/runtime/engine.js" "$TARGET_DIR/cart/.mono/engine.js"
cp "$MONO_ROOT/runtime/console-gamepad.js" "$TARGET_DIR/cart/.mono/console-gamepad.js"

VERSION=$(grep -o 'const MONO_VERSION = "[^"]*"' "$MONO_ROOT/editor/index.html" | head -1 | cut -d'"' -f2)
echo "$VERSION" > "$TARGET_DIR/cart/.mono/VERSION"

# 4. Create minimal main.lua
cat > "$TARGET_DIR/cart/main.lua" << 'LUA'
local scr = screen()

function _update()
end

function _draw()
  cls(scr, 0)
  text(scr, "HELLO MONO", 44, 66, 1)
end
LUA

# 5. Customize project
sed -i '' "s/rootProject.name = \"mono-android\"/rootProject.name = \"$DIR_NAME\"/" "$TARGET_DIR/settings.gradle.kts"
sed -i '' "s/applicationId = \"com.mono.game\"/applicationId = \"$APP_ID\"/" "$TARGET_DIR/app/build.gradle.kts"
sed -i '' "s/>Mono Game</>$PROJECT_NAME</" "$TARGET_DIR/app/src/main/res/values/strings.xml"

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
echo "  ./gradlew assembleDebug"
