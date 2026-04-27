# Mono API Reference v1.0 "Mono"

## Constraints

| Property | Value |
|----------|-------|
| Resolution | 160 × 120 pixels |
| Color palette | Up to 16 grayscale, configurable via `mode()` |
| Sprite size | 16 × 16 pixels |
| Frame rate | 30 FPS |
| Input | 8 buttons: up, down, left, right, a, b, start, select |
| Audio | 2 channels, square / sawtooth / triangle / sine + noise |
| Language | Lua 5.4 via Wasmoon |

## Color Modes

`mode(bits)` sets color depth — call inside `_init()` before any drawing.

| bits | Colors | Palette |
|------|--------|---------|
| 1 | 2 | `#000000`, `#ffffff` |
| 2 | 4 | `#000000`, `#555555`, `#aaaaaa`, `#ffffff` |
| 4 | 16 | 0 `#000000` to 15 `#ffffff`, evenly spaced |

Default is 1-bit (2 colors) if `mode()` is never called.

## Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `SCREEN_W` | 160 | Screen width in pixels |
| `SCREEN_H` | 120 | Screen height in pixels |
| `COLORS` | 2 / 4 / 16 | Number of colors in current mode |
| `ALIGN_LEFT` | 0 | Text align: left (default) |
| `ALIGN_HCENTER` | 1 | Text align: horizontal center |
| `ALIGN_RIGHT` | 2 | Text align: right edge |
| `ALIGN_VCENTER` | 4 | Text align: vertical center |
| `ALIGN_CENTER` | 5 | `ALIGN_HCENTER + ALIGN_VCENTER` |

## Lifecycle

The engine calls two global functions before scenes start (both optional):

```lua
function _init()    -- system config: call mode() here
function _start()   -- game setup: define sprites, set state, often calls go("title")
```

Order: `_init()` → engine internals exposed → `_start()` → game loop begins. Each frame: input → `<scene>_update()` → `<scene>_draw()`.

## Surfaces

All drawing functions take a **surface id** as their first parameter. `screen()` returns the screen surface (always 0). Off-screen canvases are created with `canvas(w, h)` for render-to-texture (zoom, minimaps, masks, etc.).

```lua
local scr = screen()
cls(scr, 0)
rectf(scr, 10, 10, 50, 50, 3)
text(scr, "HI", 10, 10, 1)
```

The screen surface auto-flushes at the end of each frame — no manual `flush()` needed.

## Scenes

Two conventions, auto-detected per scene file:

**Convention A — global functions:**
```lua
function title_init()    -- called once when entering scene
function title_update()  -- called every frame
function title_draw()    -- called every frame
```

**Convention B — table-returning module (recommended):**
```lua
-- scenes/play.lua
local scene = {}
function scene.init() end
function scene.update() end
function scene.draw() end
return scene
```

`go("title")` loads `title.lua` and starts that scene. Folder paths supported: `go("scenes/play")` loads `scenes/play.lua` (basename `play` is used for global function names). `scene_name()` returns the current scene name.

`require()` is for non-scene modules (config, utilities) — standard Lua semantics, dot notation for subfolders (`require("lib.utils")` → `lib/utils.lua`).

## Controls

8-button keys: `"up"`, `"down"`, `"left"`, `"right"`, `"a"`, `"b"`, `"start"`, `"select"`.

| Button | Primary | Alt (WASD) | Alt (P;'L) |
|--------|---------|------------|------------|
| up     | ↑       | W          | P          |
| down   | ↓       | S          | ;          |
| left   | ←       | A          | L          |
| right  | →       | D          | '          |
| a      | Z       |            |            |
| b      | X       |            |            |
| start  | Enter   |            |            |
| select | Space   |            |            |

`btnr()` is safer than `btnp()` for scene transitions — a press spanning a transition won't re-trigger.

Mouse clicks are treated as a single touch. On mobile, all touch points are available via `touch_count()` and `touch_pos(i)` / `touch_posf(i)` (1-based index).

## Debug

Press number keys during gameplay to toggle overlays:

| Key | Overlay | Color | Shows |
|-----|---------|-------|-------|
| 1 | HITBOX | green | Collision shapes |
| 2 | SPRITE | magenta | Sprite bounding boxes |
| 3 | FILL | cyan / orange | rectf / circf areas |

## Pause

**Select** (Space) toggles pause during the `play` scene. While paused, `<scene>_update()` is skipped; `<scene>_draw()` still runs. A blinking "PAUSE" overlay is drawn automatically.
