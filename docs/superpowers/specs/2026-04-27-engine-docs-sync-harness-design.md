# Engine ↔ Docs Sync Harness — Design

**Date:** 2026-04-27
**Branch:** `feature/essential-inputs`
**Status:** Approved (brainstorming)

## Problem

When engine code (`runtime/engine.js`, `runtime/engine-bindings.js`) is edited — adding new APIs, renaming, removing — the public API documentation in `docs/API.md` drifts. There is no automatic detection or correction. The existing `.claude/hooks/check-api-sync.sh` only checks runner-to-runner consistency (engine.js ↔ mono-test.js ↔ test-worker.js), not engine ↔ docs.

Today, `docs/API.md` documents ~24 functions while the engine registers many more (`cam`, `cam_reset`, `canvas`, `drawImage`, `gyro_*`, `motion_*`, `axis_x/y`, `touch_*`, `swipe`, `noise`, `mode`, `go`, `scene_name`, etc.). This gap grows every commit.

## Goals

- A single source of truth — the engine code — drives the public API surface.
- Generated `docs/API.md` is always in sync with whatever the engine registers.
- Drift is caught early (PostToolUse warning) and blocked at commit time (pre-commit gate).
- Doc generation is opt-in via JSDoc — APIs without JSDoc are visible but minimal, supporting incremental migration.
- No formal test suite for the generator. Git diff is the verification.

## Non-Goals

- Type-checking or validating JSDoc signatures. The `@lua` line is rendered verbatim.
- Generating `docs/DEV.md` (the long-form developer guide). Out of scope for this harness.
- CI integration. Local pre-commit gate is the enforcement boundary for now.
- Backward compatibility with the current `docs/API.md` content beyond a one-time migration.

## Source of Truth

**Engine code is the source of truth.** Specifically: `lua.global.set("name", ...)` registrations across `runtime/engine.js` and `runtime/engine-bindings.js`. JSDoc blocks immediately preceding each registration carry signature, group, and description metadata.

## Architecture

```
runtime/engine.js              ← @lua JSDoc above each lua.global.set(...)
runtime/engine-bindings.js     ← same
        │
        ▼  parsed by
scripts/gen-api-docs.js        ← Node script (parser + renderer)
        │
        ▼  composed as
docs/api-header.md  +  [generated body]  +  docs/api-footer.md
        │
        ▼  written to
docs/API.md                    ← generated artifact, committed
```

Three entry points:

1. **`npm run docs:api`** — explicit regeneration, run by hand.
2. **PostToolUse hook** — runs `--check` (dry-run) after edits to `engine.js` / `engine-bindings.js`. Warns if drift detected. Never writes.
3. **pre-commit hook** — runs `--check` if any of `runtime/engine.js`, `runtime/engine-bindings.js`, `docs/api-header.md`, `docs/api-footer.md` is staged. Blocks commit on drift.

## JSDoc Convention

The only place authors hand-write API metadata. Three tags total:

| Tag | Required | Role |
|---|---|---|
| `@lua` | yes | One-line signature, rendered verbatim |
| `@group` | no | Section header (e.g. `Graphics`, `Input`). Defaults to `Misc` |
| `@desc` | no | Free-form prose paragraph: definition, intent, caveats, usage hints |

Example:

```js
/**
 * @lua circ(cx, cy, r, color: Color): void
 * @group Graphics
 * @desc Draw a circle outline.
 */
lua.global.set("circ", (cx, cy, r, color) => { ... });

/**
 * @lua btnr(key: Key): boolean
 * @group Input
 * @desc True on the frame the button is released. Use instead of btnp() for scene transitions and confirmations — acting on release feels more forgiving.
 */
lua.global.set("btnr", ...);
```

`@desc` is a single paragraph. Multiple sentences allowed. Markdown line breaks within `@desc` collapse to spaces in output.

A registration without a JSDoc block still appears in the output, but only its name is rendered (no signature, no description). It lands in the `Misc` section. This supports incremental migration from the current undocumented state.

## Scope Rules

A `lua.global.set("name", ...)` registration is **excluded** from the generated body if:

- The name starts with `_` (internal helpers, e.g. `_btn`, `_touch_pos_x`, `_cam_get_x`).
- The name is `SCREEN_W`, `SCREEN_H`, or `COLORS` (built-in constants).
- The registration has no JSDoc and the name is all-uppercase (constant-style, e.g. `ALIGN_LEFT`, `ALIGN_CENTER`).

A registration is **included** if it doesn't match any exclusion rule. Constants documented with JSDoc (`@desc Sprite alignment flag`) are included like any other API.

## Output Format

The generated body is concatenated between `docs/api-header.md` and `docs/api-footer.md` to produce `docs/API.md`.

**Body structure:**

- Top-level `##` headings group APIs by `@group` value.
- Within each group, APIs are sorted alphabetically by name.
- Each API renders as `### <signature>` (the `@lua` line) followed by `@desc` text on the next line (if present).
- The `Misc` group renders last and contains:
  - APIs that have no `@group` tag.
  - APIs with no JSDoc at all (rendered as `### <name>` only, no signature, no description).

**Example output (English):**

```markdown
## Graphics

### cls(color?: Color): void

### circ(cx, cy, r, color: Color): void
Draw a circle outline.

## Input

### btn(key: Key): boolean

### btnr(key: Key): boolean
True on the frame the button is released. Use instead of btnp() for scene transitions and confirmations — acting on release feels more forgiving.

## Misc

### mode
### noise
```

No `<!-- AUTO-GENERATED -->` comments. No "Parameters" / "Example" / "Usage" / "Note" labels. No "(undocumented)" markers. The output is consumed primarily by AI assistants generating Mono game code; redundant human-facing decoration is removed.

All generated content is in English. `api-header.md` and `api-footer.md` are also in English.

## Header / Footer Files

Two hand-edited markdown files frame the generated body:

- **`docs/api-header.md`** — title, lifecycle intro, anything that should appear before the API listing. Migrated from the current `docs/API.md` introduction.
- **`docs/api-footer.md`** — closing notes (e.g. the current "추후 추가 검토 중" memo, translated to English). Migrated from the current `docs/API.md` footer.

Composition order:

```
[contents of api-header.md]
\n
[generated body]
\n
[contents of api-footer.md]
```

`docs/API.md` is never hand-edited after the migration. Authors edit either the engine JSDoc, `api-header.md`, or `api-footer.md` — never the generated artifact.

## Generator Script

**File:** `scripts/gen-api-docs.js` (Node, no new dependencies).

**Modes:**

- No args → parse, render, write `docs/API.md`. Exit 0.
- `--check` → parse, render in-memory, diff against current `docs/API.md`. Exit 0 if identical, exit 1 with diff on stderr if not.

**Parsing approach:**

- Read `runtime/engine.js` and `runtime/engine-bindings.js` as text.
- Regex-find each `lua.global.set("name", ...)` and look backward for an immediately preceding `/** ... */` block.
- Within each block, extract `@lua`, `@group`, `@desc` lines. Multi-line `@desc` collapses whitespace to a single space.
- Apply scope rules. Build the in-memory model.
- Render to markdown.

**Failure modes:**

- Missing `docs/api-header.md` or `docs/api-footer.md` → script errors and exits non-zero. (Natural file-read error, no special handling.)
- Zero functions parsed → script errors and exits non-zero. (Almost certainly indicates a parser regression.)

## Hook Wiring

**`.claude/hooks/check-api-docs.sh` (new, PostToolUse):**

- Triggered on edits to `runtime/engine.js` or `runtime/engine-bindings.js`.
- Runs `node scripts/gen-api-docs.js --check`.
- On exit 1, returns `additionalContext` to Claude with: `"docs/API.md is out of date — run \`npm run docs:api\`"` plus a short diff snippet.
- Never blocks; warning only.

**`.git/hooks/pre-commit` (new):**

- If any of `runtime/engine.js`, `runtime/engine-bindings.js`, `docs/api-header.md`, `docs/api-footer.md` is staged, runs `node scripts/gen-api-docs.js --check`.
- On exit 1, blocks the commit with the message: `"docs/API.md is out of date. Run \`npm run docs:api\` and stage docs/API.md."`

**Relationship to existing `check-api-sync.sh`:**

- That hook continues to enforce runner-to-runner consistency (engine.js ↔ mono-test.js ↔ test-worker.js).
- The new hook enforces engine-to-docs consistency.
- Both run independently in PostToolUse with no overlap.

## `package.json` Additions

```json
{
  "scripts": {
    "docs:api": "node scripts/gen-api-docs.js",
    "docs:api:check": "node scripts/gen-api-docs.js --check"
  }
}
```

## One-Time Migration

Before the harness can run cleanly:

1. Move the introductory section of the current `docs/API.md` (title + "라이프사이클") into `docs/api-header.md`, translated to English.
2. Move the closing memo ("추후 추가 검토 중") into `docs/api-footer.md`, translated to English.
3. Audit `runtime/engine.js` and `runtime/engine-bindings.js`, adding `@lua` / `@group` / `@desc` JSDoc to APIs that already exist in `docs/API.md`. APIs not currently documented can be left without JSDoc — they will land in `Misc` and can be migrated incrementally.
4. Run `npm run docs:api` to produce the new `docs/API.md`.
5. Commit: header file, footer file, engine JSDoc additions, generator script, hooks, new `API.md`.

## Verification

No formal tests for the generator. After any change to `scripts/gen-api-docs.js`, run `npm run docs:api` and inspect `git diff docs/API.md`. If the diff is wrong, `git checkout docs/API.md` and fix the generator. The pre-commit gate prevents bad output from reaching shared history.

## Out of Scope (Future Work)

- Auto-generating `docs/DEV.md`. The long-form guide stays hand-written for now.
- Type validation of `@lua` signatures.
- CI enforcement (the pre-commit gate is local).
- Cross-checking generated APIs against actual call sites in demo games.
