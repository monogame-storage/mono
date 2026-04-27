#!/bin/bash
# pre-commit: block commit if docs/API.md is stale relative to engine JSDoc / partials.
# Install: cp scripts/pre-commit.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit

set -e

# Only run if any relevant path is staged.
STAGED=$(git diff --cached --name-only)
TRIGGER=0
for f in $STAGED; do
  case "$f" in
    runtime/engine.js|runtime/engine-bindings.js|docs/api-header.md|docs/api-footer.md)
      TRIGGER=1
      break
      ;;
  esac
done
[ "$TRIGGER" = "1" ] || exit 0

REPO_ROOT=$(git rev-parse --show-toplevel)
[ -f "$REPO_ROOT/scripts/gen-api-docs.js" ] || exit 0
DIFF=$(cd "$REPO_ROOT" && node scripts/gen-api-docs.js --check 2>&1) || {
  echo "✖ docs/API.md is out of date." >&2
  echo "$DIFF" >&2
  echo "" >&2
  echo "  Run \`npm run docs:api\` and stage docs/API.md, then retry." >&2
  exit 1
}
exit 0
