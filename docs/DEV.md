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
function _init()
  mode(4)  -- 16 grayscale
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
  cls(0)
  text("HELLO MONO", 120, 100, 3)
  text("PRESS START", 115, 130, 2)
end

function play_init()
end

function play_update()
end

function play_draw()
  cls(0)
  text("PLAYING!", 130, 116, 3)
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
| Language        | Lua 5.4 via Wasmoon                             |
| Audio           | 2 channels, square wave                         |

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
2. **Update** -- `<scene>_update()` called, then ECS physics/collision/lifetime processed
3. **Draw** -- camera shake applied, `<scene>_draw()` called, then ECS entities rendered

### Frame Counter

```lua
local f = frame()  -- returns the current frame number (starts at 0, increments each tick)
```

---

## 4. Graphics API

All drawing functions use integer color values from 0 to `COLORS - 1` (e.g., 0-1 in 1-bit mode, 0-15 in 4-bit mode).

### Screen

```lua
cls(color)               -- clear entire screen to color (default 0)
```

### Pixels

```lua
pix(x, y, color)         -- set a single pixel (affected by camera)
gpix(x, y)               -- get pixel color at screen coordinate (returns 0-3, or -1 if out of bounds)
```

### Lines and Shapes

```lua
line(x1, y1, x2, y2, color)    -- draw line between two points
rect(x, y, w, h, color)        -- draw rectangle outline
rectf(x, y, w, h, color)       -- draw filled rectangle
circ(x, y, r, color)           -- draw circle outline (x,y = center)
circf(x, y, r, color)          -- draw filled circle (x,y = center)
```

All shape functions are affected by camera offset.

### Sprites

```lua
spr(id, x, y)                      -- draw sprite (all pixels, including color 0)
spr(id, x, y, flipX, flipY)        -- draw sprite with optional flip (boolean)

sprT(id, x, y)                     -- draw sprite, skip color 0 pixels (transparent)
sprT(id, x, y, flipX, flipY)       -- transparent sprite with flip

sprRot(id, cx, cy, angle)          -- draw sprite rotated around center (radians)
sprScale(id, cx, cy, scale)        -- draw sprite scaled from center, color 0 = transparent
sprScale(id, cx, cy, scale, flipX, flipY)  -- scaled with flip
```

**Unified draw function (LOVE2D-style):**

```lua
draw(id, x, y, rotation, scaleX, scaleY, originX, originY)
```

- `rotation`: radians (default 0)
- `scaleX`, `scaleY`: scale factors (default 1)
- `originX`, `originY`: origin offset in sprite-local pixels (default 0,0 = top-left; use 8,8 for center of a 16x16 sprite)
- Color 0 pixels are transparent

All sprite drawing functions are affected by camera.

### Text

```lua
text(str, x, y, color)
```

- 4x7 pixel bitmap font, 5px character pitch (4px glyph + 1px gap)
- Uppercase only (auto-converted)
- Supports: A-Z, 0-9, space, `.` `,` `!` `?` `-` `+` `:` `/` `*` `#` `(` `)` `=` `'` `"` `<` `>` `_`
- **NOT affected by camera** -- always draws at screen coordinates

---

## 5. Sprites

### defSprite

```lua
defSprite(id, data)
```

- `id`: integer sprite ID (you choose)
- `data`: a 256-character string where each character is `"0"`, `"1"`, `"2"`, or `"3"` representing the color of each pixel, row by row, left to right, top to bottom

```lua
defSprite(1,
  "0000000330000000" ..
  "0000003333000000" ..
  "0000333333330000" ..
  "0003333333333000" ..
  "0033333223333300" ..
  "0333333223333330" ..
  "3333332002333333" ..
  "0333320000233330" ..
  "0033320000233300" ..
  "0003320000233000" ..
  "0000320000230000" ..
  "0000020000200000" ..
  "0000002002000000" ..
  "0000000220000000" ..
  "0000000000000000" ..
  "0000000000000000"
)
```

`defSprite` also accepts multiline visual format strings (with newlines).

### defVisual (Lua helper)

A convenience pattern used in demos. Define it in your game:

```lua
local _sprNames = {}
local _sprNext = 1

local function defVisual(name, art)
  local data = ""
  for line in art:gmatch("[^\n]+") do
    local trimmed = line:match("^%s*(.-)%s*$")
    if #trimmed == 16 then
      for i = 1, 16 do
        local ch = trimmed:sub(i, i)
        if ch == "." or ch == "0" then data = data .. "0"
        else data = data .. ch end
      end
    end
  end
  if #data == 256 then
    defSprite(_sprNext, data)
    _sprNames[name] = _sprNext
    _sprNext = _sprNext + 1
  end
end

-- Override sprite_id to use local names
local _orig_sprite_id = sprite_id
sprite_id = function(name)
  return _sprNames[name] or 0
end
```

### Visual Sprite Format

Use `.` for color 0 (background/transparent) and `1`, `2`, `3` for the other colors:

```lua
defVisual("ship", [[
.......33.......
......3333......
.....333333.....
....33333333....
...3333333333...
..333332233333..
.33333322333333.
3333332..2333333
.33332....23333.
..3332....2333..
...332....233...
....32....23....
.....2....2.....
......2..2......
.......22.......
................
]])
```

### sprite_id

```lua
local id = sprite_id("ship")   -- returns the numeric ID registered for "ship", or 0
```

This works with names registered via the declarative `game` table or your own `defVisual` helper.

---

## 6. Camera

```lua
cam(x, y)          -- set camera position; all camera-affected drawing shifts by (-x, -y)
cam_reset()         -- reset camera to (0, 0) and clear shake

local cx, cy = cam_get()   -- returns current camera x, y as two values

cam_shake(amount)   -- start screen shake; decays by 0.9x per frame, stops below 0.5
```

**What is affected by camera:** `pix`, `line`, `rect`, `rectf`, `circ`, `circf`, `spr`, `sprT`, `sprRot`, `sprScale`, `draw`, `map`

**What is NOT affected by camera:** `text`

Typical usage (follow a player):

```lua
function play_update()
  -- move player...
  local cx = playerX - 160  -- center horizontally
  local cy = playerY - 120  -- center vertically
  cam(cx, cy)
end
```

---

## 7. Images

Load external images (PNG, JPG, WebP, BMP, GIF, SVG) and draw them. Images are auto-quantized to the current grayscale palette. Transparent pixels (alpha < 128) are skipped.

```lua
local id = loadImage("bg.png")     -- load image, returns integer ID
                                    -- call in _start(), loaded before game loop begins

drawImage(id, x, y)                -- draw full image at (x, y), camera-affected
drawImageRegion(id, sx, sy, sw, sh, dx, dy)  -- draw sub-region of image
                                    -- sx,sy,sw,sh = source rect
                                    -- dx,dy = screen destination, camera-affected
```

- `loadImage` returns an ID synchronously; the actual fetch happens async and completes before the game loop starts
- Path is relative to the game folder (e.g., `"world01.png"`) or absolute (`"/assets/bg.png"`)
- All browser-supported image formats work (PNG, JPG, WebP, BMP, GIF, SVG)
- Images are quantized using luminance: `0.299R + 0.587G + 0.114B` → nearest palette gray

Example (Gals Panic style reveal):

```lua
local bg

function _start()
  bg = loadImage("world01.png")
end

function _draw()
  cls(0)
  -- reveal a 40x40 region of the background at screen position (10, 10)
  drawImageRegion(bg, 10, 10, 40, 40, 10, 10)
end
```

---

## 8. Input

### Button State

```lua
btn(key)     -- returns true while the button is held down
btnp(key)    -- returns true only on the first frame the button is pressed
```

### Valid Keys

`"up"`, `"down"`, `"left"`, `"right"`, `"a"`, `"b"`, `"start"`, `"select"`

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

## 9. Audio

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

### Background Music

```lua
bgm(tracks, bpm, loop)
```

- `tracks`: a Lua table of 1 or 2 strings (one per channel)
- `bpm`: beats per minute (default 120)
- `loop`: boolean (default true)

Track format: space-separated tokens where each token is:
- A note name like `"C4"`, `"A#5"` -- plays the note
- `"-"` -- sustain (hold previous note)
- `"."` -- silence (note off)
- `"|"` -- ignored (visual bar separator)

```lua
bgm({
  "E4 . G4 . A4 . G4 . E4 . D4 . E4 .",
  "C3 - - - E3 - - - A2 - - - E3 - - -",
}, 180, true)
```

```lua
bgm_stop()           -- stop background music
bgm_vol(vol)         -- set BGM volume (0.0 to 1.0)
```

---

## 10. Tilemap

### Set and Get Tiles

```lua
mset(cx, cy, spriteId)   -- set tile at cell (cx, cy) to a sprite ID
mget(cx, cy)              -- get sprite ID at cell (cx, cy), returns 0 if empty
```

Cell coordinates are in tile units (not pixels).

### Draw Tilemap Region

```lua
map(mx, my, mw, mh, sx, sy)
```

- `mx`, `my`: starting cell coordinates in the tilemap
- `mw`, `mh`: number of cells to draw (width, height)
- `sx`, `sy`: screen pixel position for the top-left corner

Draws using `spr()` (not `sprT`), so color 0 pixels are drawn. Affected by camera.

```lua
-- Fill a 20x15 tilemap
for y = 0, 14 do
  for x = 0, 19 do
    mset(x, y, floorTileId)
  end
end

-- Draw the visible portion
map(0, 0, 20, 15, 0, 0)
```

---

## 11. ECS (Entity Component System)

### Spawning Entities

```lua
local e = spawn({
  group = "bullet",                -- string tag for grouping
  pos = { x = 100, y = 50 },      -- position
  vel = { x = 0, y = -5 },        -- velocity (auto-applied each frame)
  sprite = spriteId,               -- sprite to draw (uses sprT, so color 0 = transparent)
  hitbox = { r = 5 },             -- circle hitbox (radius)
  -- OR --
  hitbox = { w = 12, h = 14, ox = -6, oy = -7 },  -- rect hitbox (ox/oy = offset from pos)
  gravity = 0.1,                   -- added to vel.y each frame
  lifetime = 30,                   -- auto-kill after N frames
  offscreen = true,                -- auto-kill when far off screen
  anchor_x = 0.5,                 -- sprite anchor (0=left, 0.5=center, 1=right)
  anchor_y = 0.5,                 -- sprite anchor (0=top, 0.5=center, 1=bottom)
  flipX = true,                   -- flip sprite horizontally
  flipY = false,                  -- flip sprite vertically
  z = 10,                         -- z-order (higher = drawn on top)
})
```

`spawn` returns the entity table. The entity has an `_id` field you can use for `kill()` and `tween()`.

Custom properties are passed through and accessible in `each()` callbacks:

```lua
spawn({
  group = "enemy",
  pos = { x = 100, y = 0 },
  sprite = enemyId,
  hp = 3,            -- custom property
  scoreValue = 100,  -- custom property
})
```

### Entity Lifecycle

```lua
kill(entity)           -- remove a specific entity (pass the entity table or its _id)
killAll("bullets")     -- remove all entities in group
killAll()              -- remove ALL entities
```

### Iterating Entities

```lua
each("enemy", function(e)
  -- e.pos.x, e.pos.y, e.vel.x, e.vel.y, e.sprite, etc.
  e.pos.x = e.pos.x + 1
end)

local n = ecount("enemy")   -- count alive entities in group
ecount()                     -- count all alive entities
```

### Collisions (Poll Mode)

Register a collision pair with a string tag. When two entities collide, **both are auto-killed** and the collision is queued:

```lua
onCollide("bullet", "enemy", "bullet_enemy")

-- In update:
while true do
  local hit = pollCollision()
  if not hit then break end
  if hit.tag == "bullet_enemy" then
    -- hit.ax, hit.ay = position of entity from groupA
    -- hit.bx, hit.by = position of entity from groupB
    -- hit.aId, hit.bId = entity IDs
    spawnExplosion(hit.bx, hit.by)
    score = score + 100
  end
end
```

### Collisions (Callback Mode)

Register with a function instead of a string. Entities are **NOT auto-killed** -- you decide what happens:

```lua
onCollide("pacman", "ghost", function(pac, ghost)
  -- pac and ghost are entity tables
  -- handle collision manually
  kill(ghost)
end)
```

### Clear Collisions

```lua
clearCollisions()   -- remove all collision handlers and queued events
```

Note: `clearCollisions()` is automatically called when changing scenes via `go()`.

### ECS Update Order

Each frame, the engine runs (in order):
1. Remove dead entities
2. Kill offscreen entities (if `offscreen = true`)
3. Apply velocity: `pos += vel`
4. Apply gravity: `vel.y += gravity`
5. Decrement lifetime; kill if <= 0
6. Advance animations
7. Detect collisions

---

## 12. Tween

```lua
tween(entityId, property, toValue, frames, easing)
```

- `entityId`: the `_id` field of a spawned entity
- `property`: dot-separated path like `"pos.x"`, `"pos.y"`
- `toValue`: target value
- `frames`: duration in frames
- `easing`: `"linear"` (default), `"in"`, `"out"`, `"inout"`

```lua
local e = spawn({ group = "ui", pos = { x = -50, y = 120 }, sprite = logoId })
tween(e._id, "pos.x", 160, 30, "out")  -- slide in from left over 1 second
```

```lua
tween_clear()   -- remove all active tweens
```

Easing functions:
- `"linear"` -- constant speed
- `"in"` -- quadratic ease in (slow start)
- `"out"` -- quadratic ease out (slow end)
- `"inout"` -- quadratic ease in-out

---

## 13. Scene Management

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

```
my-game/
  main.lua
  config.lua              -- require("config")
  lib/
    utils.lua             -- require("lib.utils")
  scenes/
    title.lua             -- go("scenes/title")
    play.lua              -- go("scenes/play")
```

---

## 14. Math and Utility

```lua
rnd(n)      -- random float from 0 (inclusive) to n (exclusive)
flr(x)      -- floor (same as math.floor)
abs(x)      -- absolute value

seed(n)     -- set the PRNG seed (deterministic for replays)

overlap(x1, y1, w1, h1, x2, y2, w2, h2)   -- AABB overlap check, returns boolean
```

`rnd()` uses a Lehmer PRNG (Park-Miller). For integer random: `flr(rnd(6))` gives 0-5.

---

## 15. Debug Overlays

Press number keys during gameplay to toggle overlays:

| Key | Overlay            | Color   | Shows                              |
|-----|--------------------|---------|------------------------------------|
| 1   | HITBOX             | Green   | Collision shapes (circles/rects)   |
| 2   | SPRITE             | Magenta | Sprite bounding boxes              |
| 3   | FILL               | Cyan/Orange | rectf/circf fill areas          |

### Manual Debug Shapes

```lua
dbg(x, y, w, h)    -- register a debug rectangle (only visible when overlay 1 is on)
dbgC(x, y, r)      -- register a debug circle
```

These are automatically registered by the ECS for entities with hitboxes. Call them manually for custom collision areas.

---

## 16. Pause

- Press **Select** (Space) during the `play` scene to toggle pause
- While paused, `<scene>_update()` is skipped; draw still runs
- A blinking "PAUSE" overlay is drawn automatically
- The engine handles this entirely -- no code needed

---

## 17. Portal Integration

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

## 18. Memory (RAM)

The engine provides 4096 bytes of RAM accessible from Lua:

```lua
poke(addr, value)       -- write byte (0-255) at address (0-4095)
peek(addr)              -- read byte at address

poke16(addr, value)     -- write 16-bit value (little-endian)
peek16(addr)            -- read 16-bit value
```

---

## 19. Examples

### Minimal Shooter

```lua
-- Sprites
defSprite(1,
  "0000000330000000" ..
  "0000003333000000" ..
  "0000333333330000" ..
  "0003333333333000" ..
  "0033333223333300" ..
  "0333333223333330" ..
  "3333332002333333" ..
  "0333320000233330" ..
  "0033320000233300" ..
  "0003320000233000" ..
  "0000320000230000" ..
  "0000020000200000" ..
  "0000002002000000" ..
  "0000000220000000" ..
  "0000000000000000" ..
  "0000000000000000"
)

defSprite(2,
  "0000000000000000" ..
  "0000000000000000" ..
  "0000000000000000" ..
  "0000000000000000" ..
  "0000000000000000" ..
  "0000000330000000" ..
  "0000003333000000" ..
  "0000033333300000" ..
  "0000003333000000" ..
  "0000000330000000" ..
  "0000000000000000" ..
  "0000000000000000" ..
  "0000000000000000" ..
  "0000000000000000" ..
  "0000000000000000" ..
  "0000000000000000"
)

local px, py = 152, 200
local score = 0

function title_init() end

function title_update()
  if btnp("start") then go("play") end
end

function title_draw()
  cls(0)
  text("SPACE SHOOTER", 110, 80, 3)
  text("PRESS START", 118, 140, 2)
end

function play_init()
  px, py = 152, 200
  score = 0
  killAll()
  onCollide("bullet", "enemy", "hit")
end

function play_update()
  -- Move ship
  if btn("left") and px > 0 then px = px - 3 end
  if btn("right") and px < 304 then px = px + 3 end

  -- Shoot
  if btnp("a") and ecount("bullet") < 5 then
    spawn({
      group = "bullet",
      pos = { x = px + 8, y = py - 4 },
      vel = { x = 0, y = -6 },
      sprite = 2,
      hitbox = { r = 3 },
      offscreen = true,
      anchor_x = 0.5, anchor_y = 0.5,
    })
    note(0, "A5", 0.03)
  end

  -- Spawn enemies
  if frame() % 40 == 0 then
    spawn({
      group = "enemy",
      pos = { x = flr(rnd(288)) + 16, y = -16 },
      vel = { x = 0, y = 1.5 },
      sprite = 1,
      hitbox = { r = 6 },
      offscreen = true,
      anchor_x = 0.5, anchor_y = 0.5,
    })
  end

  -- Process collisions
  while true do
    local hit = pollCollision()
    if not hit then break end
    score = score + 100
    note(0, "E5", 0.08)
  end
end

function play_draw()
  cls(0)
  sprT(1, flr(px), flr(py))
  text("SCORE:" .. score, 4, 4, 3)
end
```

### Minimal Platformer Concept

```lua
local px, py = 100, 200
local vy = 0
local GRAVITY = 0.4
local GROUND = 200
local jumping = false

function play_init()
  px, py = 100, GROUND
  vy = 0
end

function play_update()
  -- Horizontal movement
  if btn("left") then px = px - 2 end
  if btn("right") then px = px + 2 end

  -- Jump
  if btnp("a") and not jumping then
    vy = -7
    jumping = true
    note(0, "C5", 0.05)
  end

  -- Gravity
  vy = vy + GRAVITY
  py = py + vy

  -- Ground collision
  if py >= GROUND then
    py = GROUND
    vy = 0
    jumping = false
  end
end

function play_draw()
  cls(0)

  -- Ground
  rectf(0, 216, 320, 24, 1)

  -- Player (simple rectangle)
  rectf(flr(px), flr(py), 16, 16, 3)
end
```

### Using Visual Sprites

```lua
local _sprNames = {}
local _sprNext = 1

local function defVisual(name, art)
  local data = ""
  for line in art:gmatch("[^\n]+") do
    local trimmed = line:match("^%s*(.-)%s*$")
    if #trimmed == 16 then
      for i = 1, 16 do
        local ch = trimmed:sub(i, i)
        if ch == "." or ch == "0" then data = data .. "0"
        else data = data .. ch end
      end
    end
  end
  if #data == 256 then
    defSprite(_sprNext, data)
    _sprNames[name] = _sprNext
    _sprNext = _sprNext + 1
  end
end

sprite_id = function(name)
  return _sprNames[name] or 0
end

defVisual("hero", [[
......1111......
.....111111.....
....11311311....
....11111111....
.....111111.....
......3333......
.....333333.....
....33333333....
...3333333333...
....33333333....
.....333333.....
......3333......
.....33..33.....
....33....33....
...33......33...
..33........33..
]])

function play_draw()
  cls(0)
  sprT(sprite_id("hero"), 152, 112)
end
```

### BGM Example

```lua
function play_init()
  bgm({
    "C4 . E4 . G4 . E4 . C4 . E4 . G4 . C5 .",
    "C3 - - - G2 - - - A2 - - - E2 - - -",
  }, 140, true)
end
```

Track tokens: note names play notes, `"-"` sustains, `"."` silences, `"|"` is ignored (visual aid).
