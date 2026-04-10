#!/usr/bin/env bash
# mono-new-demo: scaffold a new demo in demo/<name>/
#
# Usage:
#   mono-new-demo.sh <name> [category]
#
# Categories hint which APIs the template should exercise:
#   graphics (default) — basic shapes
#   audio             — note, tone, noise, wave, sfx_stop
#   sprite            — loadImage, spr, sspr, drawImage
#   touch             — touch, swipe, touch_pos
#   scene             — go, scene_name
#   canvas            — canvas, blit, canvas_del

set -euo pipefail

NAME="${1:-}"
CATEGORY="${2:-graphics}"

if [ -z "$NAME" ]; then
  echo "usage: mono-new-demo.sh <name> [category]" >&2
  echo "categories: graphics, audio, sprite, touch, scene, canvas" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEMO_DIR="$REPO_ROOT/demo/$NAME"

if [ -e "$DEMO_DIR" ]; then
  echo "error: $DEMO_DIR already exists" >&2
  exit 1
fi

mkdir -p "$DEMO_DIR"

# Base template — common to all categories
cat > "$DEMO_DIR/main.lua" <<LUA
-- $NAME demo
-- Category: $CATEGORY
local scr = screen()

function _init()
  mode(4)
end

function _start()
LUA

# Category-specific additions in _start
case "$CATEGORY" in
  audio)
    cat >> "$DEMO_DIR/main.lua" <<'LUA'
  wave(0, "square")
  wave(1, "sine")
LUA
    ;;
  sprite)
    cat >> "$DEMO_DIR/main.lua" <<'LUA'
  -- sprites = loadImage("sprites.png")
  -- sprites_w = imageWidth(sprites)
  -- sprites_h = imageHeight(sprites)
LUA
    ;;
esac

cat >> "$DEMO_DIR/main.lua" <<'LUA'
end

function _update()
LUA

case "$CATEGORY" in
  touch)
    cat >> "$DEMO_DIR/main.lua" <<'LUA'
  if touch() then
    local x, y = touch_pos()
    -- handle touch at (x, y)
  end
  local dir = swipe()
  if dir then
    -- handle swipe
  end
LUA
    ;;
  audio)
    cat >> "$DEMO_DIR/main.lua" <<'LUA'
  if btnp("a") then note(0, "C5", 0.2) end
  if btnp("b") then tone(1, 400, 2000, 0.2) end
  if btnp("start") then sfx_stop() end
LUA
    ;;
esac

cat >> "$DEMO_DIR/main.lua" <<LUA
end

function _draw()
  cls(scr, 0)
  text(scr, "$NAME", 2, 2, 15)
  text(scr, "CATEGORY $CATEGORY", 2, 12, 11)
end
LUA

# Target APIs for this category
case "$CATEGORY" in
  graphics) TARGET_APIS="- cls, rectf, circ, text (basic graphics)" ;;
  audio)    TARGET_APIS="- note, tone, noise, wave, sfx_stop" ;;
  sprite)   TARGET_APIS="- loadImage, spr, sspr, drawImage, imageWidth, imageHeight" ;;
  touch)    TARGET_APIS="- touch, touch_start, touch_end, touch_pos, touch_posf, touch_count, swipe" ;;
  scene)    TARGET_APIS="- go, scene_name" ;;
  canvas)   TARGET_APIS="- canvas, canvas_w, canvas_h, canvas_del, blit" ;;
  *)        TARGET_APIS="- (custom)" ;;
esac

# README with intent and target APIs
cat > "$DEMO_DIR/README.md" <<MD
# $NAME

Category: **$CATEGORY**

## Intent

Describe what this demo proves or teaches in 1-2 sentences.

## Target APIs

$TARGET_APIS

## Controls

Document player input here.

## Verify

\`\`\`bash
cd demo/$NAME
node ../../editor/templates/mono/mono-test.js main.lua --frames 120 --coverage
\`\`\`
MD

# Smoke test
cd "$DEMO_DIR"
if node "$REPO_ROOT/editor/templates/mono/mono-test.js" main.lua --frames 10 --colors 4 --quiet >/dev/null 2>&1; then
  echo "✓ demo/$NAME scaffolded and passes smoke test"
  echo "  files:"
  echo "    $DEMO_DIR/main.lua"
  echo "    $DEMO_DIR/README.md"
  echo "  next:"
  echo "    edit main.lua to implement your demo"
  echo "    run /mono-verify to confirm it fits the pipeline"
else
  echo "✗ demo/$NAME scaffolded but smoke test failed — check main.lua" >&2
  exit 1
fi
