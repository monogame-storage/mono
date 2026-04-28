#!/bin/bash
# PostToolUse hook: auto-bump VERSION patch on deployed file edits

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')

case "$FILE" in
  */runtime/engine.js) REPO=$(echo "$FILE" | sed 's|/runtime/engine.js||') ;;
  */dev/headless/mono-runner.js) REPO=$(echo "$FILE" | sed 's|/dev/headless/mono-runner.js||') ;;
  */dev/templates/mono/CONTEXT.md) REPO=$(echo "$FILE" | sed 's|/dev/templates/mono/CONTEXT.md||') ;;
  *) exit 0 ;;
esac

VERSION_FILE="$REPO/VERSION"
if [ ! -f "$VERSION_FILE" ]; then
  exit 0
fi

CURRENT=$(tr -d '[:space:]' < "$VERSION_FILE")
if [ -z "$CURRENT" ]; then
  exit 0
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"
PATCH=$((PATCH + 1))
NEW="$MAJOR.$MINOR.$PATCH"

echo "$NEW" > "$VERSION_FILE"

TRIGGER=$(basename "$FILE")
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"$TRIGGER edited → version bumped $CURRENT → $NEW\"}}"
