# Mono — Claude Code Project Instructions

## Project Stage: ALPHA (Engine Development)

Current focus: engine development + first-party game for Play Store release.

### Stage Rules
- NO backward compatibility — break anything freely
- NO deprecation warnings or migration guides
- NO defensive coding for external consumers
- API changes are expected and encouraged
- Optimize for speed of iteration, not stability

### Stage Roadmap
```
ALPHA   (now)  Engine development     — no external users, break freely
BETA           Online editor          — API stabilization begins
GAMMA          Publishing system      — backward compatibility starts
PUBLIC         User pages & community — stability required
```

## Project
Mono is a constraint-driven fantasy game console (160x144, 16 grayscale colors, 16x16 sprites, Lua 5.4 via Wasmoon).

## Key Files
- `runtime/engine.js` — Single-file game engine (Wasmoon + canvas + ECS + audio)
- `demo/engine-test/game.lua` — Engine test suite (8 modes: shooter, camera, sprites, input, sound, tilemap, RPG, brawler)
- `demo/pacman/game.lua` — Pac-Man Lua port
- `docs/DEV.md` — Developer guide (API reference)
- `docs/AI-PITFALLS.md` — Common AI mistakes when generating Mono code

## Rules

### When AI makes a mistake
- First, fix the root cause — if the API is confusing, rename it; if a return type is ambiguous, change it
- Only document in `docs/AI-PITFALLS.md` when the root cause cannot be fixed (e.g. Lua language limitations, Wasmoon quirks)
- We are in ALPHA — prefer changing the engine over teaching AI to work around bad design

### Lua specifics (Wasmoon)
- Lua 5.4, NOT Luau — no type annotations
- `local function` must be defined BEFORE it's called (no forward references)
- JS functions returning to Lua: never return `null`, use `false` instead
- `pollCollision()` returns `false` when empty, not `nil`
- `goto`/`::label::` for continue pattern (Lua 5.4 has no `continue`)

### Engine conventions
- Camera affects `rectf`/`circ`/`spr` but NOT `text()` — use `cam(0,0)` for HUD
- `rnd()` NEVER in draw functions — generate once in init, store in table
- Debug overlays: 1=hitbox, 2=sprite, 3=fill, 4=pad
- `spawn()` uses Lua-side wrapper that decomposes to `_spawnRaw` flat args
- Diagonal movement must be normalized (0.7071 factor)

### Git
- Commit messages: imperative, concise, with Co-Authored-By
- Don't amend — always new commits
- Push to `ssk-play/mono` on GitHub
- PR that addresses a GitHub issue: always include `Closes #N` in PR body so merging auto-closes the issue
