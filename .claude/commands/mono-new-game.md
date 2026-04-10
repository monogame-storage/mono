---
description: Scaffold a new standard-compliant Mono game in demo/<name>/ — title + game + optional end-state
---

Create a new game scaffold under `demo/` following the [Mono Game Standard](../../docs/GAME-STANDARD.md):

```bash
./.claude/scripts/mono-new-game.sh <name>
```

## What it creates

```
demo/<name>/
├── main.lua       ← entry, go("title")
├── title.lua      ← title screen with blinking "PRESS START", reads btnp("start")
├── game.lua       ← main gameplay loop (inherits engine-default SELECT pause)
├── gameover.lua   ← end state, any input → title
├── .standard      ← marker file for /mono-lint (opt-in standard enforcement)
└── README.md      ← intent, controls, verification command
```

Immediately runs a 10-frame smoke test so scaffolding errors surface right away.

## What makes it standard-compliant

- **START begins the game** — `title.lua` calls `go("game")` on `btnp("start")`
- **SELECT pauses** — `game.lua` inherits engine default (no override needed)
- **Touch = START on title** — `title.lua` also reacts to `touch_start()`
- **Blinking "PRESS START"** — single line, on/off blink on the title screen
- **Scene transitions use `btnp()`** — never `btn()` (hold)

## When to use

- Starting a brand-new game that should follow the standard across Mono's catalog
- Anything meant for the Play Store release or a first-party shipped game

## Alternative

For single-file API showcases (`engine-test`, `shader-test` style), use `/mono-new-demo` instead. It doesn't add the title/game/gameover scene skeleton.
