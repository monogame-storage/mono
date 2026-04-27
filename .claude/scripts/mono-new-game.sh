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

# --- Copy canonical files from templates/game/ with title + engine substitution ---
# Escape backslashes and sed delimiters in the name so the substitution is safe.
TITLE_ESC=$(printf '%s' "$NAME" | sed -e 's/[\\&|]/\\&/g')
ENGINE=$(cat "$REPO_ROOT/VERSION")
for f in cart.json main.lua title.lua game.lua gameover.lua; do
  sed -e "s|%TITLE%|$TITLE_ESC|g" -e "s|%ENGINE%|$ENGINE|g" \
      "$REPO_ROOT/templates/game/$f" > "$DEMO_DIR/$f"
done

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
node ../../headless/mono-runner.js main.lua --frames 120
\`\`\`

Or run \`/mono-verify\` to check this game along with every other demo.

## Standard compliance

This game was scaffolded by \`/mono-new-game\` and follows the
[Mono Game Standard](../../docs/GAME-STANDARD.md). The \`.standard\` marker
file opts into lint enforcement for standard compliance.
MD

# --- Smoke test ---
cd "$DEMO_DIR"
if node "$REPO_ROOT/headless/mono-runner.js" main.lua --frames 10 --colors 4 --quiet >/dev/null 2>&1; then
  echo "✓ demo/$NAME scaffolded and passes smoke test"
  echo "  files:"
  echo "    $DEMO_DIR/cart.json"
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
