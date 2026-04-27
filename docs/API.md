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

The engine calls three global functions before the game loop starts (all optional):

```lua
function _init()    -- system config: call mode() here
function _start()   -- game setup: define sprites, queue loadImage() calls, set state
function _ready()   -- runs after every loadImage() resolves; safe to query imageWidth/imageHeight; common place to call go()
```

Order: `_init()` → engine internals exposed → `_start()` → image loads finish → `_ready()` → game loop begins. Each frame: input → `<scene>_update()` (or global `_update()` when no scene is active) → `<scene>_draw()` (or `_draw()`).

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

**Select** (Space) toggles pause in every scene by default. While paused, `<scene>_update()` is skipped; `<scene>_draw()` still runs. A blinking "PAUSE" overlay is drawn automatically. Call `use_pause(false)` to opt out — the engine stops auto-pausing and the game owns SELECT (useful for menu / title scenes that bind it).

## Camera

### cam_get(): number, number
Returns the current camera offset (x, y) set by cam().

## Globals

### frame(): number
Current frame number, starts at 0 and increments by 1 each frame.

## Graphics

### circ(surface: number, cx: number, cy: number, r: number, color: Color): void
Draw a circle outline (1-pixel stroke).

### circf(surface: number, cx: number, cy: number, r: number, color: Color): void
Draw a filled circle.

### cls(surface: number, color?: Color): void
Clear the surface with the given color. Default 0 (BLACK).

### line(surface: number, x0: number, y0: number, x1: number, y1: number, color: Color): void
Draw a line between two points.

### pix(surface: number, x: number, y: number, color: Color): void
Set a single pixel.

### rect(surface: number, x: number, y: number, w: number, h: number, color: Color): void
Draw a rectangle outline.

### rectf(surface: number, x: number, y: number, w: number, h: number, color: Color): void
Draw a filled rectangle.

### text(surface: number, str: string, x: number, y: number, color: Color, align?: number): void
Draw text with the built-in 4×7 pixel font (uppercase, digits, basic punctuation). Optional align is a bit flag (combine ALIGN_HCENTER, ALIGN_RIGHT, ALIGN_VCENTER, ALIGN_CENTER). Not affected by camera.

## Input

### btn(key: Key): boolean
Returns true while the given button is held. Key ∈ "up","down","left","right","a","b","start","select".

### btnp(key: Key): boolean
Returns true on the frame the button was newly pressed (was not down on the previous frame).

### btnr(key: Key): boolean
Returns true on the frame the button was released. Use instead of btnp() for scene transitions and confirmations — acting on release feels more forgiving.

### touch(): boolean
Returns true while at least one finger is on the screen.

### touch_end(): boolean
Returns true on the frame a touch was released.

### touch_pos(i?: number): number, number | false
Integer pixel coordinates (x, y) of touch i (1-based, default 1). Returns false if no such touch.

### touch_posf(i?: number): number, number | false
Sub-pixel float coordinates (x, y) of touch i (1-based, default 1). Returns false if no such touch.

### touch_start(): boolean
Returns true on the frame a touch began.

## Sound

### note(channel: 0 | 1, note: string, duration: number): void
Play a note on the given channel. note is "C4" / "A#3" / etc. duration in seconds.

### sfx_stop(channel?: 0 | 1): void
Stop a channel. With no argument, stops all channels.

## Sprite

### spr(surface: number, id: number, x: number, y: number): void
Draw a registered sprite or loaded image at (x, y). Camera-affected.

## Util

### print(...): void
Logs values to the host console (prefixed with [Lua]). Useful during development. On platforms without a visible console (e.g. mobile builds) this is a no-op for end users.

## Misc

### axis_x

### axis_y

### blit

### cam

### cam_reset

### cam_shake

### canvas

### canvas_del

### canvas_h

### canvas_w

### date

### drawImage

### drawImageRegion

### go

### gpix

### gyro_alpha

### gyro_beta

### gyro_gamma

### imageHeight

### imageWidth

### loadImage

### mode

### motion_enabled

### motion_x

### motion_y

### motion_z

### noise

### scene_name

### screen

### sspr

### swipe

### time

### tone

### touch_count

### use_pause

### wave

## Under Consideration

- `cam(x, y)` — camera offset (for scrolling games)
- `overlap(x1,y1,w1,h1, x2,y2,w2,h2)` — AABB collision helper
- Transparency handling (color 0 transparent? separate transparent index?)
- `save(key, value)` / `load(key)` — local data storage
