#!/bin/bash
# PostToolUse hook: bump patch version when engine.js or mono-test.js is edited

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')

# Only trigger for engine.js or mono-test.js edits
case "$FILE" in
  */runtime/engine.js) REPO=$(echo "$FILE" | sed 's|/runtime/engine.js||') ;;
  */editor/templates/mono/mono-test.js) REPO=$(echo "$FILE" | sed 's|/editor/templates/mono/mono-test.js||') ;;
  *) exit 0 ;;
esac
EDITOR="$REPO/editor/index.html"

if [ ! -f "$EDITOR" ]; then
  exit 0
fi

# Extract current version
CURRENT=$(grep -oE 'MONO_VERSION = "[^"]+"' "$EDITOR" | sed 's/MONO_VERSION = "//;s/"//')
if [ -z "$CURRENT" ]; then
  exit 0
fi

# Parse semver and bump patch
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"
PATCH=$((PATCH + 1))
NEW="$MAJOR.$MINOR.$PATCH"

# Replace in editor/index.html
sed -i '' "s/MONO_VERSION = \"$CURRENT\"/MONO_VERSION = \"$NEW\"/" "$EDITOR"

echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"Engine version bumped: $CURRENT → $NEW\"}}"
