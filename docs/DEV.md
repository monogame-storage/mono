# Mono Engine Developer Guide

Complete API reference for the Mono game engine. Everything you need to build games without reading engine source code.

---

## 1. Quick Start

### Minimal HTML Boilerplate

Create a project folder with this structure:

```
my-game/
  index.html
  game.lua
```

**index.html:**

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>My Game</title>
<link rel="stylesheet" href="../../runtime/mono.css">
</head>
<body>
<div id="frame">
  <canvas id="screen"></canvas>
</div>
<script src="../../runtime/engine.js"></script>
<script>Mono.boot("screen", { game: "game.lua" }).catch(e => console.error("Boot failed:", e));</script>
</body></html>
```

Adjust the paths to `engine.js` and `mono.css` relative to your project folder.

### Minimal game.lua (Hello World)

```lua
local scr = screen()

function _init()
  mode(1)  -- 1=2 colors, 2=4 colors, 4=16 colors
end

function _start()
  go("title")
end

function title_init()
end

function title_update()
  if btnp("start") then
    go("play")
  end
end

function title_draw()
  cls(scr, 0)
  text(scr, "HELLO MONO", SCREEN_W/2, SCREEN_H/2 - 10, 1, ALIGN_CENTER)
  text(scr, "PRESS START", SCREEN_W/2, SCREEN_H/2 + 10, 1, ALIGN_CENTER)
end

function play_init()
end

function play_update()
end

function play_draw()
  cls(scr, 0)
  text(scr, "PLAYING!", SCREEN_W/2, SCREEN_H/2, 1, ALIGN_CENTER)
end
```

### How to Run Locally

Serve the project folder over HTTP. Lua files are fetched via `fetch()`, so `file://` will not work.

```bash
# Python 3
cd my-game && python3 -m http.server 8000

# Node.js (npx)
npx serve my-game
```

Open `http://localhost:8000` in a browser.

---

## 2. Constraints

| Property        | Value                                           |
|-----------------|-------------------------------------------------|
| Resolution      | 160 x 144 pixels                                |
| Color palette   | Up to 16 grayscale (4-bit), configurable via `mode()` |
| Sprite size     | 16 x 16 pixels (default)                        |
| Frame rate      | 30 FPS                                          |
| Input           | 8 buttons: up, down, left, right, a, b, start, select |
| Audio           | 2 channels, square wave                         |
| Language        | Lua 5.4 via Wasmoon                             |

### Graphics Mode

```lua
mode(bits)   -- set color depth: 1 = 2 colors, 2 = 4 colors, 4 = 16 colors
```

| bits | Colors | Palette                                       |
|------|--------|-----------------------------------------------|
| 1    | 2      | `#000000`, `#ffffff`                          |
| 2    | 4      | `#000000`, `#555555`, `#aaaaaa`, `#ffffff`    |
| 4    | 16     | 0 `#000000` to 15 `#ffffff`, evenly spaced    |

Call `mode()` inside `_init()` before any drawing. It rebuilds the palette and updates the `COLORS` global.

Default is 1-bit (2 colors) if `mode()` is never called.

### Global Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `SCREEN_W` | 160 | Screen width in pixels |
| `SCREEN_H` | 144 | Screen height in pixels |
| `COLORS` | 2/4/16 | Number of colors in current mode |
| `ALIGN_LEFT` | 0 | Text align: left (default) |
| `ALIGN_HCENTER` | 1 | Text align: horizontal center |
| `ALIGN_RIGHT` | 2 | Text align: right edge |
| `ALIGN_VCENTER` | 4 | Text align: vertical center |
| `ALIGN_CENTER` | 5 | Text align: both horizontal + vertical center |

---

## 3. Game Structure

### Lifecycle: `_init` → `_start` → loop

Before any scene runs, the engine calls two global functions (if defined):

```lua
function _init()
  -- System configuration phase.
  -- Call mode() here to set color depth.
  mode(4)  -- 16 grayscale
end

function _start()
  -- Game initialization phase.
  -- Define sprites, set up initial state, etc.
  -- The palette and COLORS global are ready here.
end
```

**Order:**
1. `_init()` — configure hardware (mode, etc.). Called before internals are exposed.
2. Engine exposes `_internal` for plugins (shader, etc.)
3. `_start()` — game setup (sprites, variables, scene prep)
4. Game loop begins (`_update` → `_draw` each frame)

Both are optional. If your game uses scenes, `_start()` is a good place to call `go("title")`.

### Scenes

Scene names are arbitrary strings. Use any name you want:

```lua
go("title")           -- loads title.lua
go("scenes/play")     -- loads scenes/play.lua (folder structure supported)
```

### Convention A: Global Functions (simple)

```lua
-- title.lua
function title_init()    -- called once when entering the scene
end

function title_update()  -- called every frame (game logic)
end

function title_draw()    -- called every frame (rendering)
end
```

With folder paths like `go("scenes/play")`, the engine uses the basename (`play`) to find `play_init`, `play_update`, `play_draw`.

### Convention B: State Pattern (recommended)

Scene files return a table with `init`, `update`, `draw` methods:

```lua
-- scenes/play.lua
local scene = {}

function scene.init()
  -- called once when entering
end

function scene.update()
  -- called every frame
end

function scene.draw()
  -- called every frame
end

return scene
```

The state pattern avoids global function name collisions and enables clean folder organization:
```
main.lua
scenes/
  title.lua
  play.lua
  clear.lua
  gameover.lua
```

Both conventions are auto-detected. If a scene file returns a table, the state pattern is used; otherwise the engine looks for global `<basename>_init/update/draw` functions.

### Game Loop Order

Each frame runs in this order:

1. **Input** -- button states updated
2. **Update** -- `<scene>_update()` called
3. **Draw** -- `<scene>_draw()` called

### Frame Counter

```lua
local f = frame()  -- returns the current frame number (starts at 0, increments each tick)
```

---

## 4. Canvas Surface

All drawing targets a **surface**. The screen is surface 0; you can create additional off-screen canvases for render-to-texture effects, zoom, minimaps, etc.

The screen surface is **auto-flushed** at the end of each frame — no manual `flush()` or `present()` call is needed. Just draw to the screen in `_draw()` and the engine handles the rest.

### Surface Functions

```lua
screen()              -- returns the screen surface id (always 0)
canvas(w, h)          -- create a virtual canvas, returns surface id (max 1024x1024)
canvas_w(id)          -- returns width of surface
canvas_h(id)          -- returns height of surface
canvas_del(id)        -- free a canvas (cannot delete screen)

blit(src, dst, dx, dy [, dw, dh [, sx, sy, sw, sh]])
  -- copy/scale between surfaces
  -- src, dst: surface ids
  -- dx, dy: destination position
  -- dw, dh: destination size (optional; defaults to source size)
  -- sx, sy, sw, sh: source sub-region (optional; defaults to full source)
  -- Uses nearest-neighbor scaling. Color 255 = transparent.
```

### Basic Usage

```lua
local scr = screen()
cls(scr, 0)
rectf(scr, 10, 10, 50, 50, 3)
text(scr, "HI", 10, 10, 1)
```

### Zoom / Render-to-Texture Example

Draw the world at double resolution, then scale down to the screen:

```lua
local world = canvas(320, 288)
local scr = screen()

function _draw()
  cls(world, 0)
  cam(px - 160, py - 144)
  rectf(world, 10, 10, 50, 50, 3)
  spr(world, player_img, px, py)

  cls(scr, 0)
  cam(0, 0)
  blit(world, scr, 0, 0, 160, 144)
  text(scr, "HP: 100", 2, 2, 15)
end
```

---

## 5. Graphics API

All drawing functions take a **surface id** as their first parameter. Use `screen()` to get the default screen surface. Color values are integers from 0 to `COLORS - 1` (e.g., 0-1 in 1-bit mode, 0-15 in 4-bit mode).

### Screen

```lua
cls(surface, color)               -- clear entire surface to color (default 0)
```

### Pixels

```lua
pix(surface, x, y, color)         -- set a single pixel (affected by camera)
gpix(surface, x, y)               -- get pixel color at coordinate (returns color index, or -1 if out of bounds)
```

### Lines and Shapes

```lua
line(surface, x1, y1, x2, y2, color)    -- draw line between two points
rect(surface, x, y, w, h, color)        -- draw rectangle outline
rectf(surface, x, y, w, h, color)       -- draw filled rectangle
circ(surface, x, y, r, color)           -- draw circle outline (x,y = center)
circf(surface, x, y, r, color)          -- draw filled circle (x,y = center)
```

All shape functions are affected by camera offset.

### Sprites (Image-based)

```lua
spr(surface, id, x, y)                     -- draw sprite/image at (x, y), camera-affected
sspr(surface, id, sx, sy, sw, sh, dx, dy)  -- draw sub-region of sprite/image
```

Sprites are loaded via `loadImage()`. See section 6 for details.

### Text

```lua
text(surface, str, x, y, color [, align])
```

- 4x7 pixel bitmap font, 5px character pitch (4px glyph + 1px gap)
- Uppercase only (auto-converted)
- Supports: A-Z, 0-9, space, `.` `,` `!` `?` `-` `+` `:` `/` `*` `#` `(` `)` `=` `'` `"` `<` `>` `_`
- `align` (optional, bit flags — default `ALIGN_LEFT`):
  - `ALIGN_LEFT` (0) — default
  - `ALIGN_HCENTER` (1) — x is the horizontal center
  - `ALIGN_RIGHT` (2) — x is the right edge
  - `ALIGN_VCENTER` (4) — y is the vertical center
  - `ALIGN_CENTER` (5) — `ALIGN_HCENTER + ALIGN_VCENTER`
  - Combine with `+`: `ALIGN_RIGHT + ALIGN_VCENTER`
- **NOT affected by camera** -- always draws at screen coordinates

---

## 6. Images

Load external images (PNG, JPG, WebP, BMP, GIF, SVG) and draw them. Images are auto-quantized to the current grayscale palette. Transparent pixels (alpha < 128) are skipped.

```lua
local id = loadImage("bg.png")     -- load image, returns integer ID
                                    -- call in _start(), loaded before game loop begins

spr(surface, id, x, y)             -- draw full image at (x, y), camera-affected
sspr(surface, id, sx, sy, sw, sh, dx, dy)  -- draw sub-region of image

imageWidth(id)                      -- returns image width in pixels
imageHeight(id)                     -- returns image height in pixels
```

- `loadImage` returns an ID synchronously; the actual fetch happens async and completes before the game loop starts
- Path is relative to the game folder (e.g., `"world01.png"`) or absolute (`"/assets/bg.png"`)
- All browser-supported image formats work (PNG, JPG, WebP, BMP, GIF, SVG)
- Images are quantized using luminance: `0.299R + 0.587G + 0.114B` → nearest palette gray

---

## 7. Camera

```lua
cam(x, y)          -- set camera position; all camera-affected drawing shifts by (-x, -y)
cam_reset()         -- reset camera to (0, 0) and clear shake
cam_shake(amount)   -- start screen shake; decays by 0.9x per frame, stops below 0.5

local cx, cy = cam_get()   -- returns current camera x, y as two values
```

**What is affected by camera:** `pix`, `line`, `rect`, `rectf`, `circ`, `circf`, `spr`, `sspr`

**What is NOT affected by camera:** `text`

Typical usage (follow a player):

```lua
function play_update()
  -- move player...
  cam(playerX - SCREEN_W/2, playerY - SCREEN_H/2)
end

function play_draw()
  local scr = screen()
  cls(scr, 0)
  -- world drawing (camera-affected)
  rectf(scr, playerX, playerY, 16, 16, 3)

  -- HUD (reset camera first)
  cam(0, 0)
  text(scr, "HP: 100", 2, 2, 15)
end
```

---

## 8. Audio

### Sound Effects

```lua
note(channel, noteStr, duration)
```

- `channel`: 0 or 1 (two square-wave channels)
- `noteStr`: note name + octave, e.g. `"C4"`, `"A#5"`, `"F#3"`
- `duration`: seconds (e.g. `0.1`)

Supported note names: C, C#, D, D#, E, F, F#, G, G#, A, A#, B (octaves 0-8).

```lua
sfx_stop(channel)    -- stop a specific channel
sfx_stop()           -- stop all channels
```

---

## 9. Input

### Button State

```lua
btn(key)     -- returns true while the button is held down
btnp(key)    -- returns true only on the first frame the button is pressed
```

### Valid Keys

`"up"`, `"down"`, `"left"`, `"right"`, `"a"`, `"b"`, `"start"`, `"select"`

### Analog Stick

```lua
axis_x()     -- returns analog X axis value (-1.0 to 1.0)
axis_y()     -- returns analog Y axis value (-1.0 to 1.0)
```

### Keyboard Mapping

| Button   | Primary Keys             | Alt Keys (WASD) | Alt Keys (P;'L) |
|----------|--------------------------|------------------|------------------|
| up       | Arrow Up                 | W                | P                |
| down     | Arrow Down               | S                | ;                |
| left     | Arrow Left               | A                | L                |
| right    | Arrow Right              | D                | '                |
| a        | Z                        |                  |                  |
| b        | X                        |                  |                  |
| start    | Enter                    |                  |                  |
| select   | Space                    |                  |                  |

Korean keyboard layout (ㅈㄴㅁㅇ / ㅋㅌ) is also mapped for convenience.

---

## 10. Scene Management

```lua
go("play")              -- transition to scene (loads play.lua if not yet loaded)
go("scenes/play")       -- folder paths supported (loads scenes/play.lua)
scene_name()            -- returns current scene name as string (e.g. "title", "scenes/play")
```

When `go()` is called:
1. The scene file (`<name>.lua`) is loaded if not already loaded
2. If the file returns a table (state pattern), `table.init()` is called
3. Otherwise, `<basename>_init()` is called (global function convention)

Scene files are loaded once and cached. Subsequent `go()` calls to the same scene skip loading and just call `init()` again.

### require() — Module Loading

Use standard Lua `require()` for non-scene files (config, utilities, libraries):

```lua
local config = require("config")       -- loads config.lua
local utils = require("lib.utils")     -- loads lib/utils.lua
```

- `require()` is for **data/utility modules** — config tables, helper functions, constants
- `go()` is for **scene transitions** — triggers lifecycle (init/update/draw)
- Modules are loaded once and cached in `package.loaded` (standard Lua behavior)
- Use dot notation for subfolders: `require("lib.utils")` → `lib/utils.lua`

---

## 11. Debug

### Debug Overlays

Press number keys during gameplay to toggle overlays:

| Key | Overlay            | Color   | Shows                              |
|-----|--------------------|---------|------------------------------------|
| 1   | HITBOX             | Green   | Collision shapes (circles/rects)   |
| 2   | SPRITE             | Magenta | Sprite bounding boxes              |
| 3   | FILL               | Cyan/Orange | rectf/circf fill areas          |

### Console Logging

```lua
print(...)    -- logs to browser console with "[Lua]" prefix
```

### Video Debug

```lua
vrow(y)       -- returns hex string of one scanline's color values
vdump()       -- returns hex string of entire screen (used by mono-test.js)
```

---

## 12. Pause

- Press **Select** (Space) during the `play` scene to toggle pause
- While paused, `<scene>_update()` is skipped; draw still runs
- A blinking "PAUSE" overlay is drawn automatically
- The engine handles this entirely -- no code needed

---

## 13. Portal Integration

The engine communicates with a parent iframe via `postMessage` for demo recording/playback:

| Parent sends          | Engine does               |
|-----------------------|---------------------------|
| `{ type: "mono", cmd: "rec" }` | Start recording inputs |
| `{ type: "mono", cmd: "stop" }` | Stop recording/playback |
| `{ type: "mono", cmd: "save" }` | Save recording to localStorage |
| `{ type: "mono", cmd: "play" }` | Play back saved recording |

The engine notifies the parent of state changes:
```
{ type: "mono", event: "state", state: "recording" | "playback" | "idle" }
```

Demo data is saved to `localStorage` under the key `mono_demo_<gameId>` where `gameId` is derived from the URL path.

---

## 14. Examples

### Minimal Platformer

```lua
local scr = screen()
local px, py = 72, 120
local vy = 0
local GRAVITY = 0.4
local GROUND = 120
local jumping = false

function _init()
  mode(4)
end

function play_init()
  px, py = 72, GROUND
  vy = 0
end

function play_update()
  if btn("left") then px = px - 2 end
  if btn("right") then px = px + 2 end

  if btnp("a") and not jumping then
    vy = -7
    jumping = true
  end

  vy = vy + GRAVITY
  py = py + vy

  if py >= GROUND then
    py = GROUND
    vy = 0
    jumping = false
  end
end

function play_draw()
  cls(scr, 0)
  rectf(scr, 0, 136, 160, 8, 1)
  rectf(scr, px, py, 16, 16, 3)
end
```
