#!/bin/bash
# PostToolUse hook: check lua.global.set API sync between engine.js and mono-test.js
# Triggered when runtime/engine.js or editor/templates/mono/mono-test.js is edited

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_response.filePath // ""')

# Only check if the edited file is engine.js or mono-test.js
case "$FILE" in
  */runtime/engine.js|*/editor/templates/mono/mono-test.js) ;;
  *) exit 0 ;;
esac

REPO=$(echo "$FILE" | sed 's|/runtime/engine.js||;s|/editor/templates/mono/mono-test.js||')
ENGINE="$REPO/runtime/engine.js"
TEST="$REPO/editor/templates/mono/mono-test.js"

if [ ! -f "$ENGINE" ] || [ ! -f "$TEST" ]; then
  exit 0
fi

# Extract lua.global.set("name" calls from both files (macOS compatible)
ENGINE_APIS=$(grep -oE 'lua\.global\.set\("[^"]+"' "$ENGINE" | sed 's/lua\.global\.set("//;s/"//' | sort -u)
TEST_APIS=$(grep -oE 'lua\.global\.set\("[^"]+"' "$TEST" | sed 's/lua\.global\.set("//;s/"//' | sort -u)

# APIs that should be in both (game-facing APIs only, exclude internal helpers)
GAME_APIS="btn btnp cls text rectf recirc circ circf line spr cam rnd frame go scene_name print palt"

MISSING=""
for api in $GAME_APIS; do
  IN_ENGINE=$(echo "$ENGINE_APIS" | grep -x "$api" || true)
  IN_TEST=$(echo "$TEST_APIS" | grep -x "$api" || true)
  if [ -n "$IN_ENGINE" ] && [ -z "$IN_TEST" ]; then
    MISSING="$MISSING  - $api (in engine.js but NOT in mono-test.js)\n"
  fi
done

if [ -n "$MISSING" ]; then
  MSG=$(printf "⚠️ API sync gap detected:\\n%bCheck editor/templates/mono/mono-test.js" "$MISSING")
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"$MSG\"}}"
else
  exit 0
fi
