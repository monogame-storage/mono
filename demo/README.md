# demo/ — guide for adding a demo

Checklist to add a new demo without breaking the portal or the coverage report. Follow this or use `/mono-new-demo <name> [category]` which does most of it for you.

## Games vs API showcases

There are two kinds of things under `demo/`:

- **Games** — playable, with a player goal, title screen, gameplay loop, end states. New games must follow the [Mono Game Standard](../docs/GAME-STANDARD.md) (START begins, SELECT pauses) — use `/mono-new-game` to scaffold.
- **API showcases** — single-file tech demos that exercise engine APIs or visualize a feature (`engine-test`, `shader-test`, `synth`, `clock`). No title, no gameplay loop, no standard compliance required. Use `/mono-new-demo` to scaffold.

This file covers the shared conventions (entry file, portal registration, coverage attract mode). For game-specific rules (START/SELECT behavior, scene structure for games), see `docs/GAME-STANDARD.md`.

Existing games (`pong`, `bounce`, `dodge`, `invaders`, `bubble`, `tiltmaze`, `starfighter`, `paint`) are grandfathered — they predate the standard and are not required to conform.

## Required conventions

### 1. Entry file is `main.lua`

```
demo/<name>/
├── main.lua      ← entry point, loaded by play.html AND mono-runner.js --scan
├── (optional)    ← other .lua scene files, assets, etc.
```

Every demo uses `main.lua` as the entry file — no exceptions. `play.html` loads `/demo/<name>/main.lua` and `mono-runner.js --scan` recursively walks `demo/` looking for `main.lua` files. There is no separate "test file" vs "play file"; the same file drives both.

### 2. Register in `play.html`

Add an entry to the `GAMES` dictionary near the top of `/play.html`:

```js
var GAMES = {
  ...
  mydemo: { path: "/demo/mydemo/main.lua", colors: 4 }
};
```

- `path`: absolute path from the repo root (always starts with `/demo/`)
- `colors`: 1 (B/W), 2 (4-gray), or 4 (16-gray)

### 3. Add a link in `demo/index.html`

```html
<a href="/play.html?game=mydemo">mydemo <span class="tag">category</span></a>
```

Without this link the demo exists but nobody finds it.

### 4. Multi-scene demos

If your demo uses `go("scene")` to load additional `.lua` files, place them as siblings of `main.lua`:

```
demo/tiltmaze/
├── main.lua      ← calls go("title") in _start
├── title.lua
├── level1.lua
├── level2.lua
└── clear.lua
```

Each scene file defines its own `<name>_init / _update / _draw` functions. See `tiltmaze/` for a working example.

## Strongly recommended

### Attract mode (for scan-mode coverage)

`/mono-verify` and `mono-runner.js --scan` run every demo for ~60-120 frames with **no input at all**. If your demo's interesting APIs (audio, camera effects, screen transitions) only trigger on user input, they will stay at 0 coverage in the report.

Fix: make the demo demonstrate its features without waiting for the player. Two patterns:

**A. Auto-play loop at fixed frame counts**

```lua
function _update()
  if frame() == 5  then note(0, "C4", 0.15) end
  if frame() == 15 then tone(1, 400, 1800, 0.2) end
  if frame() == 25 then noise(1, 0.15, "high", 1200) end
  -- ... normal gameplay below
end
```

Used by `demo/synth/main.lua`.

**B. Fallback CPU when no input detected**

```lua
local has_input = btn("up") or btn("down") or touch()
if not has_input then
  -- simple tracking AI so the ball actually hits paddles
  if ball.y > paddle.y then paddle.y = paddle.y + 1 end
  if ball.y < paddle.y then paddle.y = paddle.y - 1 end
end
```

Used by `demo/pong/main.lua`.

### Run `/mono-verify` before committing

Confirms your demo boots, doesn't crash under fuzz, and is deterministic. Also updates the aggregated coverage report so you see immediately if your demo adds new APIs to the "used" bucket.

```bash
/mono-verify
```

### Lint with `/mono-lint`

```bash
node .claude/scripts/mono-lint.js demo/mydemo/main.lua
```

Catches the `/docs/AI-PITFALLS.md` patterns (forward refs, `rnd()` in draw, removed APIs, etc.).

## Common mistakes (ask me how I know)

| Mistake | Symptom | Fix |
|---|---|---|
| Used a filename other than `main.lua` | Demo doesn't appear in portal or scan | Rename to `main.lua` |
| Forgot `play.html` entry | 404 when visiting `/play.html?game=xxx` | Add to `GAMES` dict |
| Forgot `demo/index.html` link | Works by URL, not discoverable | Add `<a>` |
| Interesting APIs only fire on input | Coverage 0% for those APIs | Add attract mode |
| Wrong drawing surface | Blank screen | `cls(scr, 0)` — first arg must be `scr`, not a color |
| Overwrote existing demo folder | Two conflicting files | Check `ls demo/` before creating |

## Existing demos

| Demo | Category | What it shows |
|---|---|---|
| bounce | physics | ball + wall bouncing |
| dodge | action | arcade dodge |
| pong | sport | 2-player pong with AI fallback |
| invaders | shooter | Space Invaders |
| bubble | touch | touch bubbles |
| starfighter | sprite | full sprite API — loadImage, spr, sspr, drawImage, drawImageRegion |
| paint | touch | full touch API + swipe + gpix |
| tiltmaze | scene | scene system, analog tilt, canvas prerender + blit |
| synth | audio | wave/note/tone/noise/sfx_stop + waveform visualization |
| engine-test | api | comprehensive engine API coverage across 6 modes |
| shader-test | visuals | custom HTML UI for shader chain (has its own `index.html`) |

All demos have `main.lua` as the entry file. `shader-test` additionally has a custom `index.html` because it exposes a shader control panel; it is opened via `/demo/shader-test/` directly rather than through `play.html`.
