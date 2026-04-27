# Engine ↔ Docs Sync Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a generator + hook harness that makes `runtime/engine.js` + `runtime/engine-bindings.js` JSDoc the single source of truth for `docs/API.md`, with PostToolUse drift warning and pre-commit drift gate.

**Architecture:** A small Node script (`scripts/gen-api-docs.js`) parses `lua.global.set("name", ...)` registrations and their preceding `/** ... */` JSDoc blocks, applies scope rules, and renders a markdown body sandwiched between hand-edited `docs/api-header.md` and `docs/api-footer.md`. PostToolUse runs `--check` mode to warn on drift; a `.git/hooks/pre-commit` runs the same check to block drift on commit.

**Tech Stack:** Node (no new npm dependencies), shell hooks, plain markdown.

**Spec:** `docs/superpowers/specs/2026-04-27-engine-docs-sync-harness-design.md`

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `docs/api-header.md` | create | Hand-edited intro (title + lifecycle). Composed before generated body. |
| `docs/api-footer.md` | create | Hand-edited closing memo. Composed after generated body. |
| `scripts/gen-api-docs.js` | create | Node script: parse → render → write (or `--check` diff). |
| `runtime/engine.js` | modify | Add `@lua` / `@group` / `@desc` JSDoc to publicly documented APIs. |
| `runtime/engine-bindings.js` | modify | Same as above. |
| `docs/API.md` | overwrite | Generated artifact. Replaces current hand-written version. |
| `package.json` | modify | Add `docs:api` and `docs:api:check` scripts. |
| `.claude/hooks/check-api-docs.sh` | create | PostToolUse drift warning. |
| `.claude/settings.json` | create | Register PostToolUse hook for the new script. |
| `.git/hooks/pre-commit` | create | Drift gate — blocks commit if `API.md` is stale. |

---

## Task 1: Create `docs/api-header.md`

**Files:**
- Create: `docs/api-header.md`

- [ ] **Step 1: Write the header file**

Translate the title and lifecycle section from the current `docs/API.md` into English. Use this content:

```markdown
# Mono API Reference v1.0 "Mono"

## Lifecycle

A game is composed of three callback functions:

```typescript
function init(): void    // called once when the game starts
function update(): void  // per-frame logic (30fps)
function draw(): void    // per-frame rendering
```
```

- [ ] **Step 2: Verify file exists and contents look right**

Run: `cat docs/api-header.md`
Expected: prints the markdown above.

- [ ] **Step 3: Commit**

```bash
git add docs/api-header.md
git commit -m "docs(api): add hand-edited header partial for API.md"
```

---

## Task 2: Create `docs/api-footer.md`

**Files:**
- Create: `docs/api-footer.md`

- [ ] **Step 1: Write the footer file**

Translate the "추후 추가 검토 중" section from the current `docs/API.md` into English:

```markdown
## Under Consideration

- `cam(x, y)` — camera offset (for scrolling games)
- `overlap(x1,y1,w1,h1, x2,y2,w2,h2)` — AABB collision helper
- Transparency handling (color 0 transparent? separate transparent index?)
- `save(key, value)` / `load(key)` — local data storage
```

- [ ] **Step 2: Verify**

Run: `cat docs/api-footer.md`
Expected: prints the markdown above.

- [ ] **Step 3: Commit**

```bash
git add docs/api-footer.md
git commit -m "docs(api): add hand-edited footer partial for API.md"
```

---

## Task 3: Generator skeleton — read partials and write `API.md`

Build the smallest possible generator that reads header/footer and writes `API.md` with an empty body. This proves file IO and the composition order before adding parsing logic.

**Files:**
- Create: `scripts/gen-api-docs.js`

- [ ] **Step 1: Write the skeleton**

```javascript
#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const HEADER = path.join(ROOT, "docs", "api-header.md");
const FOOTER = path.join(ROOT, "docs", "api-footer.md");
const OUT    = path.join(ROOT, "docs", "API.md");

function readText(p) {
  return fs.readFileSync(p, "utf8").replace(/\s+$/, "") + "\n";
}

function compose(body) {
  const header = readText(HEADER);
  const footer = readText(FOOTER);
  return `${header}\n${body}\n${footer}`;
}

function main() {
  const body = "<!-- generated body goes here -->";
  const out = compose(body);
  fs.writeFileSync(OUT, out);
  console.log(`wrote ${path.relative(ROOT, OUT)}`);
}

main();
```

- [ ] **Step 2: Make executable and run**

```bash
chmod +x scripts/gen-api-docs.js
node scripts/gen-api-docs.js
```

Expected stdout: `wrote docs/API.md`

- [ ] **Step 3: Inspect output**

Run: `cat docs/API.md`
Expected: header content, blank line, `<!-- generated body goes here -->`, blank line, footer content.

- [ ] **Step 4: Commit (skeleton only, do NOT commit `docs/API.md` yet — it still has placeholder)**

```bash
git add scripts/gen-api-docs.js
git commit -m "feat(docs): generator skeleton for API.md composition"
```

---

## Task 4: Parse `lua.global.set` registrations and preceding JSDoc blocks

Add the parser. For each registration, extract the API name and the immediately preceding `/** ... */` block (if any). Don't apply scope rules or render yet — just collect a flat list and dump it to stderr to verify.

**Files:**
- Modify: `scripts/gen-api-docs.js`

- [ ] **Step 1: Add parser and a debug dump**

Replace the contents of `scripts/gen-api-docs.js` with:

```javascript
#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const HEADER  = path.join(ROOT, "docs", "api-header.md");
const FOOTER  = path.join(ROOT, "docs", "api-footer.md");
const OUT     = path.join(ROOT, "docs", "API.md");
const SOURCES = [
  path.join(ROOT, "runtime", "engine.js"),
  path.join(ROOT, "runtime", "engine-bindings.js"),
];

function readText(p) {
  return fs.readFileSync(p, "utf8").replace(/\s+$/, "") + "\n";
}

// Parse one source file → array of { name, jsdoc | null }
function parseFile(src) {
  const text = fs.readFileSync(src, "utf8");
  const out = [];
  // Match `lua.global.set("name", ...)`. We capture the name and the byte offset.
  const reg = /lua\.global\.set\(\s*"([^"]+)"/g;
  let m;
  while ((m = reg.exec(text)) !== null) {
    const name = m[1];
    const at = m.index;
    // Walk backward from `at` to find the immediately preceding `/** ... */` block.
    // It's "preceding" if only whitespace separates it from the registration line.
    const prefix = text.slice(0, at);
    const closeIdx = prefix.lastIndexOf("*/");
    let jsdoc = null;
    if (closeIdx !== -1) {
      const between = prefix.slice(closeIdx + 2);
      if (/^\s*$/.test(between)) {
        const openIdx = prefix.lastIndexOf("/**", closeIdx);
        if (openIdx !== -1) {
          jsdoc = prefix.slice(openIdx, closeIdx + 2);
        }
      }
    }
    out.push({ name, jsdoc });
  }
  return out;
}

function parseAll() {
  const all = [];
  for (const src of SOURCES) all.push(...parseFile(src));
  return all;
}

function compose(body) {
  const header = readText(HEADER);
  const footer = readText(FOOTER);
  return `${header}\n${body}\n${footer}`;
}

function main() {
  const apis = parseAll();
  // Debug dump for now.
  console.error(`parsed ${apis.length} registrations`);
  for (const a of apis) {
    console.error(`  ${a.name}${a.jsdoc ? "  [jsdoc]" : ""}`);
  }
  const body = "<!-- generated body goes here -->";
  fs.writeFileSync(OUT, compose(body));
}

main();
```

- [ ] **Step 2: Run and inspect stderr**

```bash
node scripts/gen-api-docs.js 2>&1 | head -30
```

Expected: lines like `parsed N registrations` then a list of names, with `[jsdoc]` next to those that have a preceding block. At this stage no name should have `[jsdoc]` because we haven't added any blocks yet.

- [ ] **Step 3: Commit**

```bash
git add scripts/gen-api-docs.js
git commit -m "feat(docs): parse lua.global.set sites and preceding JSDoc"
```

---

## Task 5: Extract `@lua` / `@group` / `@desc` from JSDoc text

Turn raw JSDoc text into structured `{ sig, group, desc }` per API. Empty/missing tags become `null`.

**Files:**
- Modify: `scripts/gen-api-docs.js`

- [ ] **Step 1: Add a `extractTags` helper and use it**

In `scripts/gen-api-docs.js`, add this function above `parseFile`:

```javascript
function extractTags(jsdoc) {
  if (!jsdoc) return { sig: null, group: null, desc: null };
  // Strip /** */ and leading * on each line, then collapse to a single tag-stream.
  const inner = jsdoc
    .replace(/^\/\*\*/, "")
    .replace(/\*\/$/, "")
    .split(/\r?\n/)
    .map(line => line.replace(/^\s*\*\s?/, ""))
    .join("\n");
  // Tokenize tags. A tag starts at "@<word>" at line start and runs until the next "@<word>" at line start or EOF.
  const tags = {};
  const re = /^@(\w+)[ \t]*([^\n]*(?:\n(?!@)[^\n]*)*)/gm;
  let m;
  while ((m = re.exec(inner)) !== null) {
    const name = m[1];
    const value = m[2].replace(/\s+/g, " ").trim();
    if (!(name in tags)) tags[name] = value;
  }
  return {
    sig:   tags.lua   || null,
    group: tags.group || null,
    desc:  tags.desc  || null,
  };
}
```

Then in `parseFile`, attach the structured tags to each entry. Replace the `out.push(...)` line with:

```javascript
    out.push({ name, ...extractTags(jsdoc) });
```

And remove the `jsdoc` raw field from output.

Update the debug dump in `main()`:

```javascript
  for (const a of apis) {
    console.error(`  ${a.name.padEnd(18)} group=${a.group || "-"}  sig=${a.sig || "-"}`);
  }
```

- [ ] **Step 2: Add a temporary JSDoc to one registration to verify the parser works**

Open `runtime/engine.js`. Find the line `lua.global.set("circ", ...)`. Add a JSDoc block immediately above it:

```javascript
/**
 * @lua circ(cx, cy, r, color: Color): void
 * @group Graphics
 * @desc Draw a circle outline.
 */
lua.global.set("circ", (id, cx, cy, r, c) => { ... });
```

(Leave the existing implementation line as-is; only insert the block.)

- [ ] **Step 3: Run and inspect**

```bash
node scripts/gen-api-docs.js 2>&1 | grep -E "circ|parsed"
```

Expected: a line like `circ               group=Graphics  sig=circ(cx, cy, r, color: Color): void`.

- [ ] **Step 4: Commit**

```bash
git add scripts/gen-api-docs.js runtime/engine.js
git commit -m "feat(docs): extract @lua/@group/@desc from JSDoc blocks"
```

---

## Task 6: Apply scope rules

Drop registrations that should not appear in the docs.

**Files:**
- Modify: `scripts/gen-api-docs.js`

- [ ] **Step 1: Add `isPublic` and filter**

Add this function to `scripts/gen-api-docs.js`:

```javascript
function isPublic(api) {
  const n = api.name;
  if (n.startsWith("_")) return false;
  if (n === "SCREEN_W" || n === "SCREEN_H" || n === "COLORS") return false;
  // All-uppercase constant-style names without JSDoc are excluded.
  if (!api.sig && /^[A-Z][A-Z0-9_]+$/.test(n)) return false;
  return true;
}
```

In `main()`, filter the parsed list:

```javascript
  const apis = parseAll().filter(isPublic);
```

- [ ] **Step 2: Run and verify exclusions**

```bash
node scripts/gen-api-docs.js 2>&1 | grep -E "_btn|SCREEN_W|ALIGN_LEFT" || echo "excluded ✓"
```

Expected: `excluded ✓` (none of those names appear in the output).

- [ ] **Step 3: Commit**

```bash
git add scripts/gen-api-docs.js
git commit -m "feat(docs): apply scope rules (skip _*, SCREEN_*, COLORS, bare CONSTS)"
```

---

## Task 7: Render the body — groups, sort, Misc

Group APIs by `@group`, sort alphabetically within each group, render markdown. APIs without JSDoc go to a `Misc` section as bare names.

**Files:**
- Modify: `scripts/gen-api-docs.js`

- [ ] **Step 1: Replace the placeholder body with a real renderer**

Add this function to `scripts/gen-api-docs.js`:

```javascript
function renderBody(apis) {
  // Bucket by @group. APIs with no JSDoc go to "Misc" too, but rendered as bare names.
  const groups = new Map();
  const ensure = (g) => {
    if (!groups.has(g)) groups.set(g, []);
    return groups.get(g);
  };
  for (const api of apis) {
    const g = api.group || "Misc";
    ensure(g).push(api);
  }
  // Always show Misc last; everything else alphabetical.
  const groupNames = [...groups.keys()].filter(g => g !== "Misc").sort();
  if (groups.has("Misc")) groupNames.push("Misc");

  const lines = [];
  for (const g of groupNames) {
    lines.push(`## ${g}`);
    lines.push("");
    const list = groups.get(g).slice().sort((a, b) => a.name.localeCompare(b.name));
    for (const api of list) {
      if (api.sig) {
        lines.push(`### ${api.sig}`);
        if (api.desc) lines.push(api.desc);
      } else {
        lines.push(`### ${api.name}`);
      }
      lines.push("");
    }
  }
  // Trim trailing blank line.
  while (lines.length && lines[lines.length - 1] === "") lines.pop();
  return lines.join("\n");
}
```

In `main()`, replace the placeholder body with the rendered body and remove the debug dump:

```javascript
function main() {
  const apis = parseAll().filter(isPublic);
  const body = renderBody(apis);
  fs.writeFileSync(OUT, compose(body));
  console.log(`wrote ${path.relative(ROOT, OUT)} (${apis.length} APIs)`);
}
```

- [ ] **Step 2: Run and inspect**

```bash
node scripts/gen-api-docs.js
cat docs/API.md
```

Expected: `# Mono API Reference v1.0 "Mono"` header, then a `## Graphics` section with our `circ` entry, then a `## Misc` section listing every other registered API by name only, then the footer.

- [ ] **Step 3: Commit script change only (NOT the new API.md yet — Task 9 owns that)**

```bash
git add scripts/gen-api-docs.js
git commit -m "feat(docs): render grouped API body with Misc fallback"
```

---

## Task 8: Add `--check` mode

Dry-run that diffs the would-be output against the current `docs/API.md`. Exit 0 if identical, exit 1 with a diff snippet if not.

**Files:**
- Modify: `scripts/gen-api-docs.js`

- [ ] **Step 1: Add `--check` support**

Replace `main()` in `scripts/gen-api-docs.js` with:

```javascript
function shortDiff(expected, actual) {
  const e = expected.split("\n");
  const a = actual.split("\n");
  const lines = [];
  const maxLen = Math.max(e.length, a.length);
  for (let i = 0; i < maxLen && lines.length < 20; i++) {
    if (e[i] !== a[i]) {
      if (e[i] !== undefined) lines.push(`-${i + 1}: ${e[i]}`);
      if (a[i] !== undefined) lines.push(`+${i + 1}: ${a[i]}`);
    }
  }
  return lines.join("\n");
}

function main() {
  const check = process.argv.includes("--check");
  const apis = parseAll().filter(isPublic);
  const body = renderBody(apis);
  const expected = compose(body);

  if (check) {
    const actual = fs.existsSync(OUT) ? fs.readFileSync(OUT, "utf8") : "";
    if (actual === expected) {
      process.exit(0);
    }
    process.stderr.write("docs/API.md is out of date.\n");
    process.stderr.write(shortDiff(expected, actual) + "\n");
    process.exit(1);
  }

  fs.writeFileSync(OUT, expected);
  console.log(`wrote ${path.relative(ROOT, OUT)} (${apis.length} APIs)`);
}
```

Note the diff convention: `-N` is the *expected* line (what generation would produce), `+N` is the *actual* line currently in `API.md`. Mismatches mean the file is stale.

- [ ] **Step 2: Verify `--check` fails on current state**

The current `docs/API.md` is the old hand-written one and definitely doesn't match. Run:

```bash
node scripts/gen-api-docs.js --check; echo "exit=$?"
```

Expected: prints `docs/API.md is out of date.` and a diff snippet, then `exit=1`.

- [ ] **Step 3: Commit**

```bash
git add scripts/gen-api-docs.js
git commit -m "feat(docs): add --check mode to detect API.md drift"
```

---

## Task 9: Generate first `API.md` and commit

Now that the generator works, commit the actual generated artifact. This replaces the old hand-written `API.md`.

**Files:**
- Overwrite: `docs/API.md`

- [ ] **Step 1: Generate**

```bash
node scripts/gen-api-docs.js
```

Expected stdout: `wrote docs/API.md (N APIs)` for some N.

- [ ] **Step 2: Inspect**

Run: `cat docs/API.md`
Expected: English header, a `## Graphics` section with `circ`, a `## Misc` section listing every other registration. The old Korean content is gone.

- [ ] **Step 3: Verify `--check` now passes**

```bash
node scripts/gen-api-docs.js --check; echo "exit=$?"
```

Expected: `exit=0`, no output.

- [ ] **Step 4: Commit**

```bash
git add docs/API.md
git commit -m "docs(api): regenerate API.md from engine JSDoc (first pass)"
```

---

## Task 10: Add `package.json` scripts

**Files:**
- Modify: `package.json`

- [ ] **Step 1: Read current `package.json`**

Run: `cat package.json`

The `"scripts"` field is currently `{}`.

- [ ] **Step 2: Add the two scripts**

Edit `package.json`. Replace `"scripts": {},` with:

```json
  "scripts": {
    "docs:api": "node scripts/gen-api-docs.js",
    "docs:api:check": "node scripts/gen-api-docs.js --check"
  },
```

- [ ] **Step 3: Verify both scripts work**

```bash
npm run docs:api
npm run docs:api:check
```

Expected: first prints `wrote docs/API.md (N APIs)`, second exits 0 silently.

- [ ] **Step 4: Commit**

```bash
git add package.json
git commit -m "chore(scripts): add docs:api and docs:api:check"
```

---

## Task 11: Create PostToolUse hook

After edits to `runtime/engine.js` or `runtime/engine-bindings.js`, run `--check` and emit a Claude-visible warning if drift is detected. Never blocks.

**Files:**
- Create: `.claude/hooks/check-api-docs.sh`

- [ ] **Step 1: Write the hook**

```bash
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
```

- [ ] **Step 2: Make executable**

```bash
chmod +x .claude/hooks/check-api-docs.sh
```

- [ ] **Step 3: Manual smoke test — drift case**

The current `docs/API.md` is in sync (we generated it in Task 9). To force drift, temporarily revert one JSDoc and run the hook by hand:

```bash
# Mock a tool result for the hook
echo '{"tool_input":{"file_path":"'"$PWD"'/runtime/engine.js"}}' | bash .claude/hooks/check-api-docs.sh
```

Expected (because `API.md` is in sync): no output, exit 0.

Now temporarily edit `runtime/engine.js` — change the `@desc` of `circ` to "drifted". Save. Run the same command:

```bash
echo '{"tool_input":{"file_path":"'"$PWD"'/runtime/engine.js"}}' | bash .claude/hooks/check-api-docs.sh
```

Expected: a JSON line containing `"⚠️ docs/API.md is out of date"` and a diff snippet.

Revert the temporary edit:

```bash
git checkout runtime/engine.js
```

- [ ] **Step 4: Commit**

```bash
git add .claude/hooks/check-api-docs.sh
git commit -m "chore(hooks): PostToolUse — warn on docs/API.md drift"
```

---

## Task 12: Register the hook in `.claude/settings.json`

The hook script exists but isn't wired up. Create `.claude/settings.json` (or extend it if it appears later) to register the PostToolUse handler for `Edit` and `Write` tools.

**Files:**
- Create: `.claude/settings.json`

- [ ] **Step 1: Confirm settings.json doesn't already exist**

Run: `ls .claude/settings.json 2>/dev/null || echo "absent"`
Expected: `absent`

If it does exist, switch to editing it instead of creating it — adding the new hook entry to the existing `hooks.PostToolUse` array.

- [ ] **Step 2: Write the settings file**

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/check-api-docs.sh"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add .claude/settings.json
git commit -m "chore(hooks): register PostToolUse for check-api-docs.sh"
```

---

## Task 13: Create the pre-commit gate

Block commits when staged engine or partials would change `API.md`.

**Files:**
- Create: `.git/hooks/pre-commit` (note: not tracked by git — must be installed manually or via a setup script)

- [ ] **Step 1: Write the hook**

```bash
#!/bin/bash
# pre-commit: block commit if docs/API.md is stale relative to engine JSDoc / partials.

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
DIFF=$(cd "$REPO_ROOT" && node scripts/gen-api-docs.js --check 2>&1) || {
  echo "✖ docs/API.md is out of date." >&2
  echo "$DIFF" >&2
  echo "" >&2
  echo "  Run \`npm run docs:api\` and stage docs/API.md, then retry." >&2
  exit 1
}
exit 0
```

- [ ] **Step 2: Install and make executable**

```bash
chmod +x .git/hooks/pre-commit
```

- [ ] **Step 3: Smoke test — clean state passes**

The current state is in sync. Stage a no-op change and try to commit:

```bash
touch /tmp/sync-check && git add /tmp/sync-check 2>/dev/null || true
# (a no-op for the gate; we're just exercising the hook)
git commit --allow-empty -m "test: pre-commit gate runs (no-op)" --dry-run 2>&1 | head
```

Or simpler — just confirm the script alone exits 0 when called:

```bash
bash .git/hooks/pre-commit; echo "exit=$?"
```

Expected: `exit=0`.

- [ ] **Step 4: Smoke test — drift blocks**

Edit `runtime/engine.js`, change the `@desc` of `circ` to "drifted", stage it:

```bash
# (manually edit runtime/engine.js as described)
git add runtime/engine.js
bash .git/hooks/pre-commit; echo "exit=$?"
```

Expected: prints `✖ docs/API.md is out of date.` and a diff snippet, `exit=1`.

Revert and unstage:

```bash
git checkout runtime/engine.js
git reset HEAD runtime/engine.js
```

- [ ] **Step 5: Document hook installation**

Because `.git/hooks/` is not tracked, add a one-line install hint in the existing `CLAUDE.md` (under a "Hooks" subsection if it doesn't already exist) so future contributors install it. Append to `CLAUDE.md`:

```markdown

### Pre-commit hook

`.git/hooks/pre-commit` blocks commits when `docs/API.md` is out of date. Install:

```bash
cp scripts/pre-commit.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
```
```

Then move the hook body into `scripts/pre-commit.sh` (so it's tracked) and copy it to `.git/hooks/pre-commit`:

```bash
cp .git/hooks/pre-commit scripts/pre-commit.sh
```

- [ ] **Step 6: Commit the tracked copy and the doc**

```bash
git add scripts/pre-commit.sh CLAUDE.md
git commit -m "chore(hooks): pre-commit gate blocks API.md drift"
```

---

## Task 14: Backfill JSDoc for existing documented APIs

The old `docs/API.md` documented ~24 APIs. Annotate each one in `engine.js` / `engine-bindings.js` so they render with signatures and descriptions instead of falling into `Misc`.

For each API in the list below, add a JSDoc block immediately above its `lua.global.set("name", ...)` call.

**Files:**
- Modify: `runtime/engine.js`
- Modify: `runtime/engine-bindings.js`

- [ ] **Step 1: Annotate Graphics group (`runtime/engine.js`)**

Add JSDoc for each of: `cls`, `pix`, `line`, `rect`, `rectf`, `circf`, `text`. (`circ` was annotated in Task 5.)

```javascript
/**
 * @lua cls(color?: Color): void
 * @group Graphics
 * @desc Clear the screen with the given color. Default 0 (BLACK).
 */
lua.global.set("cls", (id, c) => { ... });

/**
 * @lua pix(x: number, y: number, color: Color): void
 * @group Graphics
 * @desc Set a single pixel.
 */
lua.global.set("pix", ...);

/**
 * @lua line(x0: number, y0: number, x1: number, y1: number, color: Color): void
 * @group Graphics
 * @desc Draw a line between two points.
 */
lua.global.set("line", ...);

/**
 * @lua rect(x: number, y: number, w: number, h: number, color: Color): void
 * @group Graphics
 * @desc Draw a rectangle outline.
 */
lua.global.set("rect", ...);

/**
 * @lua rectf(x: number, y: number, w: number, h: number, color: Color): void
 * @group Graphics
 * @desc Draw a filled rectangle.
 */
lua.global.set("rectf", ...);

/**
 * @lua circf(cx: number, cy: number, r: number, color: Color): void
 * @group Graphics
 * @desc Draw a filled circle.
 */
lua.global.set("circf", ...);

/**
 * @lua text(str: string, x: number, y: number, color: Color): void
 * @group Graphics
 * @desc Draw text with the built-in 4×7 pixel font (uppercase, digits, basic punctuation).
 */
lua.global.set("text", ...);
```

- [ ] **Step 2: Annotate Sprite, Map, Sound, Util groups (`runtime/engine.js`)**

Add JSDoc for: `sprite`, `spr`, `mget`, `mset`, `map`, `note`, `sfx_stop` (called `stop` in old API), `frame`. (Note: signature should match what game code actually calls, ignoring the surface-id internal arg.)

```javascript
/**
 * @lua sprite(id: number, data: string): void
 * @group Sprite
 * @desc Register a 16×16 sprite. data is a 64-char string of "0".."3".
 */
lua.global.set("sprite", ...);

/**
 * @lua spr(id: number, x: number, y: number, flipX?: boolean, flipY?: boolean): void
 * @group Sprite
 * @desc Draw a registered sprite at the given screen position. flipX/flipY mirror.
 */
lua.global.set("spr", ...);

/**
 * @lua mget(cx: number, cy: number): number
 * @group Map
 * @desc Read the sprite ID at tilemap cell (cx, cy).
 */
lua.global.set("mget", ...);

/**
 * @lua mset(cx: number, cy: number, id: number): void
 * @group Map
 * @desc Set the sprite ID at tilemap cell (cx, cy).
 */
lua.global.set("mset", ...);

/**
 * @lua map(mx: number, my: number, mw: number, mh: number, sx: number, sy: number): void
 * @group Map
 * @desc Render an mw×mh region of the tilemap, starting at cell (mx, my), to screen position (sx, sy).
 */
lua.global.set("map", ...);

/**
 * @lua note(channel: 0 | 1, note: string, duration: number): void
 * @group Sound
 * @desc Play a note on the given channel. note is "C4" / "A#3" / etc. duration in seconds.
 */
lua.global.set("note", ...);

/**
 * @lua sfx_stop(channel?: 0 | 1): void
 * @group Sound
 * @desc Stop a channel. With no argument, stops all channels.
 */
lua.global.set("sfx_stop", ...);

/**
 * @lua frame: number
 * @group Globals
 * @desc Current frame number, starts at 0 and increments by 1 each frame.
 */
lua.global.set("frame", ...);
```

(If the registered name in the engine is different from what's documented — e.g. `sfx_stop` vs `stop` — annotate with the actual registered name. The doc reflects engine reality, not the old hand-written API.md.)

- [ ] **Step 3: Annotate Util math group (`runtime/engine.js`)**

For each of `rnd`, `flr`, `abs`, `min`, `max`, `sin`, `cos`, find the registration and add JSDoc:

```javascript
/**
 * @lua rnd(max: number): number
 * @group Util
 * @desc Random float in [0, max).
 */
lua.global.set("rnd", ...);

/**
 * @lua flr(n: number): number
 * @group Util
 * @desc Floor of n (Math.floor).
 */
lua.global.set("flr", ...);

// ... and so on for abs, min, max, sin, cos with brief one-line descs.
```

- [ ] **Step 4: Annotate Input group (`runtime/engine-bindings.js`)**

`btn` and `btnp` (and `btnr` if registered as a public API) live as Lua-side wrappers in the `lua.doString(...)` block of `engine-bindings.js`, not as direct `lua.global.set` calls. They will not be picked up by the parser.

Decision: add `lua.global.set("btn", ...)` etc are not directly registered — the user-facing names are defined in Lua via `doString`. The harness as designed only sees registrations.

To document `btn` / `btnp` / `btnr`, add a JSDoc-only "shadow" registration block in `engine-bindings.js` that just sets a no-op marker, OR adjust the parser to also recognize Lua-defined wrappers from the `doString` block.

The simplest fix: alongside the `lua.doString(...)` call, add empty `lua.global.set("btn", function() {})` style registrations that get immediately overwritten by the Lua wrappers — purely so the parser sees them and renders the JSDoc. (They cost ~one no-op call at boot and survive in the engine namespace just long enough to be replaced.)

Above the existing `await lua.doString(...)` block (around line 132 of `runtime/engine-bindings.js`), add:

```javascript
    /**
     * @lua btn(key: Key): boolean
     * @group Input
     * @desc Returns true while the given button is held. Key ∈ "up","down","left","right","a","b","start","select".
     */
    lua.global.set("btn", () => false);

    /**
     * @lua btnp(key: Key): boolean
     * @group Input
     * @desc Returns true on the frame the button was newly pressed (was not down on the previous frame).
     */
    lua.global.set("btnp", () => false);

    /**
     * @lua btnr(key: Key): boolean
     * @group Input
     * @desc Returns true on the frame the button was released. Use instead of btnp() for scene transitions and confirmations — acting on release feels more forgiving.
     */
    lua.global.set("btnr", () => false);
```

These are immediately replaced by the `function btn(k) ... end` definitions in the subsequent `lua.doString(...)`, so they have no runtime effect.

- [ ] **Step 5: Regenerate and inspect**

```bash
npm run docs:api
cat docs/API.md
```

Expected: `## Graphics`, `## Sprite`, `## Map`, `## Input`, `## Sound`, `## Util`, `## Globals` sections all populated with the annotated APIs (signatures + descriptions). `## Misc` still lists everything else (`cam`, `cam_reset`, `drawImage`, `gyro_*`, `motion_*`, etc.) as bare names.

- [ ] **Step 6: Verify `--check` passes**

```bash
npm run docs:api:check; echo "exit=$?"
```

Expected: `exit=0`.

- [ ] **Step 7: Commit**

```bash
git add runtime/engine.js runtime/engine-bindings.js docs/API.md
git commit -m "docs(api): backfill JSDoc for previously documented APIs"
```

---

## Task 15: End-to-end smoke test

Confirm the full feedback loop works.

- [ ] **Step 1: Edit `circ` JSDoc**

Open `runtime/engine.js` and change the `@desc` of `circ` from "Draw a circle outline." to "Draw a circle outline (1-pixel stroke)."

- [ ] **Step 2: Verify PostToolUse hook would warn**

```bash
echo '{"tool_input":{"file_path":"'"$PWD"'/runtime/engine.js"}}' | bash .claude/hooks/check-api-docs.sh
```

Expected: a JSON line with `"⚠️ docs/API.md is out of date"` and a diff snippet showing the changed `@desc`.

- [ ] **Step 3: Verify pre-commit blocks**

```bash
git add runtime/engine.js
bash .git/hooks/pre-commit; echo "exit=$?"
```

Expected: `exit=1`, with the same drift message.

- [ ] **Step 4: Regenerate and confirm pre-commit now passes**

```bash
npm run docs:api
git add docs/API.md
bash .git/hooks/pre-commit; echo "exit=$?"
```

Expected: `exit=0`.

- [ ] **Step 5: Commit the smoke-test edit**

```bash
git commit -m "docs(api): refine circ description"
```

This commit exercises the full path: edit → regenerate → stage both → gate passes → commit.

---

## Self-Review Checklist

Run through this after the plan is written.

- **Spec coverage:**
  - Engine-first SoT → Tasks 4, 5, 14 (parser reads engine JSDoc).
  - Generate-only mode → Task 7 (renderer); no manual edits to `API.md` (Task 9 commits the generated artifact).
  - JSDoc convention (`@lua`, `@group`, `@desc`) → Task 5 (extractor) and Task 14 (backfill).
  - Scope rules (`_*`, `SCREEN_*`, `COLORS`, all-uppercase no-JSDoc) → Task 6.
  - Header/footer composition → Tasks 1, 2, 3.
  - Output format (English, `### sig` + desc, Misc fallback) → Task 7.
  - PostToolUse warn → Tasks 11, 12.
  - pre-commit gate → Task 13.
  - `npm run docs:api` / `:check` → Task 10.
  - One-time migration → Tasks 1, 2, 9, 14.
  - No formal tests → none in the plan.
- **Placeholder scan:** no TBD/TODO; every code step contains the actual code. Task 14 step 3 uses "and so on" for trivially-similar Util math entries; the pattern is shown in full for two examples and the remaining names are listed explicitly.
- **Type/name consistency:** `gen-api-docs.js`, `parseAll`, `parseFile`, `extractTags`, `isPublic`, `renderBody`, `compose`, `shortDiff`, `main`, `apis`, `body`, `expected`, `actual` — all referenced consistently across tasks. Tag names `@lua` / `@group` / `@desc` match between extractor (Task 5) and backfill (Task 14).
