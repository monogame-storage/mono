#!/bin/bash
# PostToolUse hook: detect API drift between the three Mono runners.
#
# After the engine-bindings.js refactor most Lua globals are registered
# in a single shared file, so this hook narrowed its job to the remaining
# env-specific surface (drawing / audio / images / motion). Triggered by
# edits to any of the runner files.

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_response.filePath // ""')

case "$FILE" in
  */runtime/engine.js|*/runtime/engine-bindings.js|*/runtime/engine-draw.js|*/dev/headless/mono-runner.js|*/dev/test-worker.js) ;;
  *) exit 0 ;;
esac

REPO=$(echo "$FILE" | sed -e 's|/runtime/engine\.js||' \
                          -e 's|/runtime/engine-bindings\.js||' \
                          -e 's|/runtime/engine-draw\.js||' \
                          -e 's|/dev/headless/mono-runner\.js||' \
                          -e 's|/dev/test-worker\.js||')

ENGINE="$REPO/runtime/engine.js"
BINDINGS="$REPO/runtime/engine-bindings.js"
TEST="$REPO/dev/headless/mono-runner.js"
WORKER="$REPO/dev/test-worker.js"

[ -f "$ENGINE" ] && [ -f "$BINDINGS" ] && [ -f "$TEST" ] && [ -f "$WORKER" ] || exit 0

# Collect lua.global.set("name"…) entries from each file.
api_names() {
  grep -oE 'lua\.global\.set\("[^"]+"' "$1" 2>/dev/null | sed 's/lua\.global\.set("//;s/"$//' | sort -u
}

ENGINE_APIS=$(api_names "$ENGINE")
BINDINGS_APIS=$(api_names "$BINDINGS")
TEST_APIS=$(api_names "$TEST")
WORKER_APIS=$(api_names "$WORKER")

# An API is "provided" to a runner if it shows up either directly in that
# runner's file or in the shared bindings module (which every runner calls).
provided_by_test()   { printf '%s\n%s\n' "$TEST_APIS"   "$BINDINGS_APIS" | sort -u; }
provided_by_worker() { printf '%s\n%s\n' "$WORKER_APIS" "$BINDINGS_APIS" | sort -u; }

TEST_PROVIDED=$(provided_by_test)
WORKER_PROVIDED=$(provided_by_worker)

MISSING=""
note_missing() {
  local api="$1" runner="$2"
  MISSING="$MISSING  - $api (in engine.js, missing from $runner)\n"
}

for api in $ENGINE_APIS; do
  # Skip helpers not meant for game code.
  case "$api" in _*|SCREEN_W|SCREEN_H|COLORS) continue ;; esac
  echo "$TEST_PROVIDED"   | grep -qx "$api" || note_missing "$api" "mono-runner.js"
  echo "$WORKER_PROVIDED" | grep -qx "$api" || note_missing "$api" "test-worker.js"
done

if [ -n "$MISSING" ]; then
  MSG=$(printf "⚠️ API sync gap detected:\\n%bAdd the missing stub or move it into runtime/engine-bindings.js." "$MISSING")
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"$MSG\"}}"
fi
exit 0
