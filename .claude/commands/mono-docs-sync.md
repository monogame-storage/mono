---
description: Verify that docs/DEV.md stays in sync with runtime/engine.js — catches ghost APIs and undocumented ones
---

Run the doc sync checker:

```bash
node ./.claude/scripts/mono-docs-sync.js
```

## What it reports

1. **Undocumented APIs** — registered in `runtime/engine.js` via `lua.global.set` but not mentioned in a `docs/DEV.md` code block.
2. **Ghost APIs** — mentioned in `docs/DEV.md` but no longer registered in `runtime/engine.js` (renamed, removed, or typo).

Both lists are exit-code failures so CI can block drift.

## How it works

- Parses every `lua.global.set("NAME"` call from engine.js.
- Maps `_`-prefixed internal helpers to their public wrapper name (`_btn` → `btn`, etc.) so the report matches user-facing docs.
- Scans `docs/DEV.md` for `name(...)` patterns inside fenced code blocks (lua/ts/js), skipping comments and Lua keywords/stdlib calls.
- Filters lifecycle callbacks like `_init`, `play_draw`, `title_update` (user-defined, not engine APIs).

## When to use

- After any change to `runtime/engine.js` API surface
- After editing `docs/DEV.md`
- As a pre-merge check alongside `/mono-verify`

## Limitations

Only catches function-form APIs (`name(...)`). Global constants like `SCREEN_W`, `COLORS`, or `ALIGN_CENTER` are not auto-detected — they still need manual doc review.
