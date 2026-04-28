# Mono Game Project (engine v{{VERSION}})

This is a [Mono](https://github.com/monogame-storage/mono) fantasy console game.

## Constraints
- Resolution: 160x120
- Colors: 16 grayscale (4-bit), configurable via `mode()`
- Sprites: 16x16
- Language: Lua 5.4 (via Wasmoon)
- Frame rate: 30 FPS
- Input: 8 buttons (up, down, left, right, a, b, start, select)

## Canvas Surface (Pygame-style)
All drawing functions take a **surface id** as their first argument.

```lua
local scr = screen()       -- screen surface (always 0)
local c = canvas(320, 288) -- virtual canvas (max 1024x1024)

-- All drawing: first arg is surface
cls(scr, 0)
pix(scr, x, y, col)
rectf(scr, x, y, w, h, col)
text(scr, "HI", 10, 10, 1)
spr(scr, id, x, y)

-- Copy/scale between surfaces
blit(src, dst, dx, dy)                         -- 1:1
blit(src, dst, dx, dy, dw, dh)                 -- scale
blit(src, dst, dx, dy, dw, dh, sx, sy, sw, sh) -- region + scale

canvas_w(c)    -- width
canvas_h(c)    -- height
canvas_del(c)  -- free
```

### Zoom example
```lua
local world = canvas(320, 240)
local scr = screen()

function _draw()
  cls(world, 0)
  cam(px - 160, py - 120)
  spr(world, player_img, px, py)

  cls(scr, 0)
  cam(0, 0)
  blit(world, scr, 0, 0, 160, 120)  -- 2x downscale
  text(scr, "HP: 100", 2, 2, 15)    -- HUD on screen
end
```

## Entry Point
- **`main.lua`** is the required entry file. The editor runs this file on Start.

## Lifecycle
```
_init()    -- system config: call mode() here
_start()   -- game init: sprites, loadImage(), variables
_ready()   -- called after all images loaded (optional)
_update()  -- called every frame (game logic)
_draw()    -- called every frame (rendering)
```

## Scenes (State Pattern)
Use `go()` to transition between scenes. Scene files return a table:
```lua
-- scenes/play.lua
local scene = {}
function scene.init() end
function scene.update() end
function scene.draw() end
return scene
```
```lua
-- main.lua
function _ready() go("scenes/title") end
```
- `go("scenes/play")` — loads `scenes/play.lua`, calls `scene.init()`
- `scene_name()` — returns current scene name (e.g. `"scenes/play"`)
- `frame()` — current frame number (starts at 0)
- `cam_get()` — returns camera x, y (`local cx, cy = cam_get()`)
- `require("config")` — load non-scene modules (config.lua, lib/utils.lua)
- Folder structure is free: `scenes/`, `src/`, or flat — any path works
- `require()` for data/utilities, `go()` for scene transitions
- Use `btnr()` (release) for scene transitions — `btnp()` can double-trigger across scenes

## Globals
- `COLORS` — number of palette colors (e.g. 16 in mode 4). Use `COLORS - 1` for max color index.

## Documentation
- API Reference: {{BASE_URL}}/docs/API.md
- Common AI Mistakes: {{BASE_URL}}/docs/AI-PITFALLS.md
- Headless Testing: {{BASE_URL}}/docs/LLM-VERIFICATION.md
- Source: https://github.com/monogame-storage/mono

## Audio (2 channels)
```lua
-- Musical notes (channel 0-1, note string, duration in seconds)
note(0, "C4", 0.2)         -- play middle C
note(1, "A#5", 0.1)        -- play A#5 on channel 1

-- Frequency sweep (channel, startHz, endHz, duration)
tone(0, 400, 200, 0.3)     -- descending tone
tone(1, 200, 2000, 0.4)    -- ascending whistle

-- Noise (channel, duration, [filter, cutoff])
noise(0, 0.1)              -- white noise burst
noise(0, 0.3, "low", 400)  -- rumble

-- Waveform: "square" (default), "sawtooth", "triangle", "sine"
wave(0, "sine")
note(0, "C4", 0.5)         -- sine wave C4

-- Stop
sfx_stop(0)                -- stop channel
sfx_stop()                 -- stop all
```
Note names: C, C#, D, D#, E, F, F#, G, G#, A, A#, B (octaves 0-8).
**There is no `sfx()` function** — use `note()`, `tone()`, or `noise()`.

## Key Rules
- Lua 5.4, NOT Luau — no type annotations
- `local function` must be defined BEFORE it's called
- Never return `null` from JS — use `false`
- `pollCollision()` returns `false` when empty, not `nil`
- Never use `rnd()` in `_draw()` — generate once in init, store in table
- Camera affects shapes/sprites but NOT `text()`
- Diagonal movement must be normalized (0.7071 factor)
- **All drawing functions require a surface id as first argument** — use `local scr = screen()` at file scope

## Status
This engine is under active development. Not all APIs listed in the docs may be implemented yet,
and some game patterns may require APIs that don't exist yet.

If you find a bug or need a feature that isn't available, file a GitHub issue.
**Always check for duplicates first:**

```bash
# 1. Search existing issues before creating
gh issue list --repo monogame-storage/mono --search "keyword" --state all

# 2. If a similar issue exists, comment on it instead
gh issue comment <number> --body "Additional context: ..."

# 3. Only create a new issue if no match found
gh issue create --repo monogame-storage/mono \
  --label "bug" \
  --title "frame() not available in mono-runner.js" \
  --body "API.md documents frame() but mono-runner.js doesn't register it."

gh issue create --repo monogame-storage/mono \
  --label "proposal" \
  --title "go() with auto file loading" \
  --body "What: go('play') loads play.lua automatically.
Why: scene-per-file structure for maintainability.
Workaround: manual state variable for scene management."
```

Use labels: `bug`, `proposal`. The developer will review and prioritize.

## Headless Verification (mono-runner.js)
LLM can run and verify Lua code without a browser using `mono-runner.js`.

**Setup**: `.mono/mono-runner.js` and shell wrappers (`mono-run`, `mono-run.cmd`) are auto-deployed when you open a folder in the editor.
Dependencies: `npm install wasmoon@1.16.0 pngjs@7`

**Prefer vdump over PNG** — vdump is text (hex 0-f per pixel), directly readable and verifiable. PNG is for human visual checks only.

**Usage**:
```bash
# Run a game file and dump the VRAM (160×120 hex, 0-f per pixel)
./mono-run main.lua --frames 5 --vdump

# Test inline code (no file needed)
./mono-run --source 'cls(0) rectf(10,10,20,20,1) print(gpix(15,15))' --vdump --console

# Pixel-level assertion
./mono-run --source 'cls(0) pix(80,72,1) print(gpix(80,72))' --console --quiet
# → prints "1" if correct

# Verify specific region (e.g. check top-left 10x5 area)
./mono-run main.lua --frames 5 --vdump --region 0,0,10,5

# Save and compare snapshots (regression test)
./mono-run main.lua --frames 5 --snapshot expected.txt
./mono-run main.lua --frames 5 --diff expected.txt
```

**Workflow**: Edit code → run mono-runner.js → check vdump → fix → repeat (1-2s per cycle).

**Fast-forward testing**: Run thousands of frames in ~1 second to verify game outcomes:
```bash
# Stop when game prints "WINNER"
./mono-run main.lua --frames 10000 --until "WINNER" --quiet --console

# Run 10 games, report win rate stats
./mono-run main.lua --frames 10000 --until "WINNER" --quiet --runs 10

# Reproducible test with fixed seed
./mono-run main.lua --frames 1000 --seed 42 --console --quiet

# Auto-play with VRAM bot (reads screen, controls P2)
./mono-run main.lua --frames 10000 --until "WINNER" --bot --quiet
# Custom bot script
./mono-run main.lua --frames 10000 --until "WINNER" --bot bot.lua --quiet
```
