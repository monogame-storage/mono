#!/usr/bin/env bash
# mono-new-game: scaffold a new standard-compliant Mono game in demo/<name>/
#
# Creates title + game + gameover scene files with the default SELECT pause
# behavior inherited from the engine, plus a blinking PRESS START on the
# title screen. See docs/GAME-STANDARD.md for the full standard.

set -euo pipefail

NAME="${1:-}"

if [ -z "$NAME" ]; then
  echo "usage: mono-new-game.sh <name>" >&2
  echo "" >&2
  echo "Creates demo/<name>/ with main.lua + title.lua + game.lua + gameover.lua" >&2
  echo "following the Mono Game Standard (see docs/GAME-STANDARD.md)." >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEMO_DIR="$REPO_ROOT/demo/$NAME"

if [ -e "$DEMO_DIR" ]; then
  echo "error: $DEMO_DIR already exists" >&2
  exit 1
fi

mkdir -p "$DEMO_DIR"

# --- main.lua — entry, boots into title ---
cat > "$DEMO_DIR/main.lua" <<'LUA'
-- Entry file: boot into the title scene.
function _init()
  mode(4)
end

function _start()
  go("title")
end
LUA

# --- title.lua — title screen with blinking PRESS START ---
cat > "$DEMO_DIR/title.lua" <<LUA
-- Title scene: blinking PRESS START, reacts to START or touch.
local scr = screen()

function title_init()
end

function title_update()
  -- START (or touch) begins the game
  if btnp("start") or touch_start() then
    go("game")
  end
end

function title_draw()
  cls(scr, 0)
  text(scr, "$NAME", 0, 40, 15, ALIGN_HCENTER)

  -- Blinking PRESS START — classic arcade pattern
  if math.floor(frame() / 15) % 2 == 0 then
    text(scr, "PRESS START", 0, 90, 11, ALIGN_HCENTER)
  end
end
LUA

# --- game.lua — main gameplay loop ---
cat > "$DEMO_DIR/game.lua" <<'LUA'
-- Gameplay scene.
-- SELECT is handled by the engine (pause toggle) — no need to implement it.
-- If you want SELECT for inventory / menu / etc., call use_pause(false)
-- in game_init and handle btnp("select") yourself.
local scr = screen()

local player_x, player_y

function game_init()
  player_x = SCREEN_W / 2
  player_y = SCREEN_H / 2
end

function game_update()
  -- Simple movement with the d-pad
  if btn("left")  then player_x = player_x - 1 end
  if btn("right") then player_x = player_x + 1 end
  if btn("up")    then player_y = player_y - 1 end
  if btn("down")  then player_y = player_y + 1 end

  -- Example: A triggers "hit" → go to gameover
  if btnp("a") then
    go("gameover")
  end
end

function game_draw()
  cls(scr, 0)
  text(scr, "PLAYING", 2, 2, 11)
  rectf(scr, math.floor(player_x) - 2, math.floor(player_y) - 2, 5, 5, 15)
end
LUA

# --- gameover.lua — any input returns to title ---
cat > "$DEMO_DIR/gameover.lua" <<'LUA'
-- Game over scene. Any input returns to the title.
local scr = screen()

local function any_input_pressed()
  return btnp("start") or btnp("select") or btnp("a") or btnp("b")
      or btnp("up") or btnp("down") or btnp("left") or btnp("right")
      or touch_start()
end

function gameover_init()
end

function gameover_update()
  if any_input_pressed() then
    go("title")
  end
end

function gameover_draw()
  cls(scr, 0)
  text(scr, "GAME OVER", 0, 55, 15, ALIGN_HCENTER)
  text(scr, "ANY KEY",   0, 75, 8,  ALIGN_HCENTER)
end
LUA

# --- .standard marker for /mono-lint ---
touch "$DEMO_DIR/.standard"

# --- README.md ---
cat > "$DEMO_DIR/README.md" <<MD
# $NAME

Standard-compliant Mono game.

## Scenes

- \`title\` — press START (or tap) to begin
- \`game\` — main gameplay. SELECT pauses (engine default)
- \`gameover\` — any input returns to title

## Controls

| Button | Action |
|--------|--------|
| D-pad  | move |
| A      | (triggers gameover in this scaffold — customize) |
| START  | begin game (from title) |
| SELECT | pause / resume (engine-managed) |

## Verify

\`\`\`bash
cd demo/$NAME
node ../../editor/templates/mono/mono-test.js main.lua --frames 120
\`\`\`

Or run \`/mono-verify\` to check this game along with every other demo.

## Standard compliance

This game was scaffolded by \`/mono-new-game\` and follows the
[Mono Game Standard](../../docs/GAME-STANDARD.md). The \`.standard\` marker
file opts into lint enforcement for standard compliance.
MD

# --- Smoke test ---
cd "$DEMO_DIR"
if node "$REPO_ROOT/editor/templates/mono/mono-test.js" main.lua --frames 10 --colors 4 --quiet >/dev/null 2>&1; then
  echo "✓ demo/$NAME scaffolded and passes smoke test"
  echo "  files:"
  echo "    $DEMO_DIR/main.lua"
  echo "    $DEMO_DIR/title.lua"
  echo "    $DEMO_DIR/game.lua"
  echo "    $DEMO_DIR/gameover.lua"
  echo "    $DEMO_DIR/.standard"
  echo "    $DEMO_DIR/README.md"
  echo "  next:"
  echo "    edit game.lua to implement your gameplay"
  echo "    register in play.html GAMES dict + demo/index.html link"
  echo "    run /mono-verify to confirm it fits the pipeline"
else
  echo "✗ demo/$NAME scaffolded but smoke test failed — check the .lua files" >&2
  exit 1
fi
