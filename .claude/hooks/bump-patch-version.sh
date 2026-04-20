#!/bin/bash
# PostToolUse hook: auto-bump MONO_VERSION patch on deployed file edits

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')

case "$FILE" in
  */runtime/engine.js) REPO=$(echo "$FILE" | sed 's|/runtime/engine.js||') ;;
  */editor/templates/mono/mono-test.js) REPO=$(echo "$FILE" | sed 's|/editor/templates/mono/mono-test.js||') ;;
  */editor/templates/mono/CONTEXT.md) REPO=$(echo "$FILE" | sed 's|/editor/templates/mono/CONTEXT.md||') ;;
  *) exit 0 ;;
esac
EDITOR="$REPO/editor/index.html"

if [ ! -f "$EDITOR" ]; then
  exit 0
fi

CURRENT=$(grep -oE 'MONO_VERSION = "[^"]+"' "$EDITOR" | sed 's/MONO_VERSION = "//;s/"//')
if [ -z "$CURRENT" ]; then
  exit 0
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"
PATCH=$((PATCH + 1))
NEW="$MAJOR.$MINOR.$PATCH"

sed -i '' "s/MONO_VERSION = \"$CURRENT\"/MONO_VERSION = \"$NEW\"/" "$EDITOR"

# Keep the plain-text VERSION file at the repo root in sync so bash
# scripts and static JS fetchers can read it without parsing HTML.
if [ -f "$REPO/VERSION" ]; then
  echo "$NEW" > "$REPO/VERSION"
fi

TRIGGER=$(basename "$FILE")
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"$TRIGGER edited → version bumped $CURRENT → $NEW\"}}"
