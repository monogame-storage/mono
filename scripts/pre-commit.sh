#!/bin/bash
# pre-commit: block commit if docs/API.md is stale relative to engine JSDoc / partials.
# Install: cp scripts/pre-commit.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit

set -e

STAGED=$(git diff --cached --name-only)
TRIGGER_INPUT=0
while IFS= read -r f; do
  case "$f" in
    runtime/engine.js|runtime/engine-bindings.js|docs/api-header.md|docs/api-footer.md) TRIGGER_INPUT=1 ;;
  esac
done <<< "$STAGED"

[ "$TRIGGER_INPUT" = "1" ] || exit 0

REPO_ROOT=$(git rev-parse --show-toplevel)
[ -f "$REPO_ROOT/scripts/gen-api-docs.js" ] || exit 0

# Drift check: compare the working-tree docs/API.md against what would be
# generated from the current engine source. If they match, the staged
# engine change has no effect on the public API (e.g. comment-only edit),
# and the commit is allowed regardless of whether API.md is staged.
DIFF=$(cd "$REPO_ROOT" && node scripts/gen-api-docs.js --check 2>&1) && exit 0

# Drift exists — block the commit. We fail even when a stale docs/API.md
# happens to be staged, because that means the user staged outdated docs.
echo "✖ docs/API.md is out of date." >&2
echo "$DIFF" >&2
echo "" >&2
echo "  Run \`npm run docs:api\` and stage docs/API.md, then retry." >&2
exit 1
