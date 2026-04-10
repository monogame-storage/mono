# demo/ — guide for adding a demo

Checklist to add a new demo without breaking the portal or the coverage report. Follow this or use `/mono-new-demo <name> [category]` which does most of it for you.

## Required conventions

### 1. Entry file is `main.lua` — not `game.lua`

```
demo/<name>/
├── main.lua      ← entry point, loaded by play.html
├── (optional)    ← other .lua scene files, assets, etc.
```

`play.html` loads the file at `/demo/<name>/main.lua`. Do NOT name it `game.lua` — that filename is used by `mono-test.js` internally when running standalone tests, but it will not show up in the browser portal.

> Historical note: earlier demos under `editor/templates/mono/` used `game.lua`. Those are templates for the editor, not browser demos. Everything under `demo/` must use `main.lua`.

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

`/mono-verify` and `mono-test.js --scan` run every demo for ~60-120 frames with **no input at all**. If your demo's interesting APIs (audio, camera effects, screen transitions) only trigger on user input, they will stay at 0 coverage in the report.

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
| Used `game.lua` instead of `main.lua` | Demo doesn't appear in portal | Rename to `main.lua` |
| Forgot `play.html` entry | 404 when visiting `/play.html?game=xxx` | Add to `GAMES` dict |
| Forgot `demo/index.html` link | Works by URL, not discoverable | Add `<a>` |
| Interesting APIs only fire on input | Coverage 0% for those APIs | Add attract mode |
| Wrong drawing surface | Blank screen | `cls(scr, 0)` — first arg must be `scr`, not a color |
| Overwrote existing demo folder | Two conflicting files | Check `ls demo/` before creating |

## Existing demos

| Demo | Entry | Category | What it shows |
|---|---|---|---|
| bounce | main.lua | physics | ball + wall bouncing |
| dodge | main.lua | action | arcade dodge |
| pong | main.lua | sport | 2-player pong with AI fallback |
| invaders | main.lua | shooter | Space Invaders |
| bubble | main.lua | touch | touch bubbles |
| starfighter | main.lua | sprite | full sprite API — loadImage, spr, sspr, drawImage, drawImageRegion |
| paint | main.lua | touch | full touch API + swipe + gpix |
| tiltmaze | main.lua | scene | scene system, analog tilt, canvas prerender + blit |
| synth | main.lua | audio | wave/note/tone/noise/sfx_stop + waveform visualization |
| engine-test | game.lua | internal | used only by mono-test.js, not play.html |
| shader-test | main + index.html | visuals | custom HTML UI for shader chain |
