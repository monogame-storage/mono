#!/bin/bash
# PostToolUse hook: warn if docs/API.md is out of date relative to engine JSDoc.
# Triggered by edits to runtime/engine.js or runtime/engine-bindings.js.

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_response.filePath // ""')

case "$FILE" in
  */runtime/engine.js|*/runtime/engine-bindings.js) ;;
  *) exit 0 ;;
esac

REPO=$(echo "$FILE" | sed -e 's|/runtime/engine\.js||' -e 's|/runtime/engine-bindings\.js||')
[ -f "$REPO/scripts/gen-api-docs.js" ] || exit 0

DIFF=$(cd "$REPO" && node scripts/gen-api-docs.js --check 2>&1)
STATUS=$?
if [ $STATUS -ne 0 ]; then
  MSG=$(printf "⚠️ docs/API.md is out of date — run \`npm run docs:api\`.\\n\\n%s" "$DIFF")
  # Escape for JSON.
  MSG_JSON=$(printf "%s" "$MSG" | jq -Rs .)
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":$MSG_JSON}}"
fi
exit 0
