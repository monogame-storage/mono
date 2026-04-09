---
description: Lint a Mono Lua game file for AI-PITFALLS patterns — forward refs, removed APIs, unsafe draw calls, etc.
---

Run the Mono lint helper against the given file(s):

```bash
node ./.claude/scripts/mono-lint.js <file.lua> [file2.lua ...]
```

If no file is given, default to linting every `demo/**/*.lua`:

```bash
node ./.claude/scripts/mono-lint.js $(find demo -name "*.lua")
```

## What it catches

Rules are derived from `docs/AI-PITFALLS.md`. Each rule is a regex heuristic, not a full Lua parser, so false positives are possible but rare.

| Rule | Severity | Catches |
|---|---|---|
| `local-forward-ref` | error | `local function` called before its definition |
| `rnd-nonexistent` | error | `rnd(...)` calls (Mono only has `math.random`) |
| `removed-api` | error | `vrow()`, `vdump()` — test-runner internals |
| `draw-random` | warn | `math.random()` inside a `_draw()` body (flickers) |
| `text-after-cam` | warn | `text()` drawn while `cam()` is non-zero (misaligned HUD) |
| `surface-missing` | warn | drawing functions with a literal as first arg instead of `scr` |
| `diagonal-unnormalized` | info | reads both axes but no `0.7071` diagonal normalization |

## When to use

- Before committing new demos or games
- When reviewing AI-generated Lua code
- As part of the CI gate alongside `/mono-verify`

Exit code is 1 if any error or warning is found (info is informational only).
