# Mono — Claude Code Project Instructions

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
- Record the bug pattern in `docs/AI-PITFALLS.md`
- Format: Symptom, Cause, Fix with code examples
- This document is referenced in future prompts to prevent the same mistake

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
