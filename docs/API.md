# Mono API Reference v1.0 "Mono"

## Lifecycle

A game is composed of three callback functions:

```typescript
function init(): void    // called once when the game starts
function update(): void  // per-frame logic (30fps)
function draw(): void    // per-frame rendering
```

## Globals

### frame: number
Current frame number, starts at 0 and increments by 1 each frame.

## Graphics

### circ(cx, cy, r, color: Color): void
Draw a circle outline.

### circf(cx: number, cy: number, r: number, color: Color): void
Draw a filled circle.

### cls(color?: Color): void
Clear the screen with the given color. Default 0 (BLACK).

### line(x0: number, y0: number, x1: number, y1: number, color: Color): void
Draw a line between two points.

### pix(x: number, y: number, color: Color): void
Set a single pixel.

### rect(x: number, y: number, w: number, h: number, color: Color): void
Draw a rectangle outline.

### rectf(x: number, y: number, w: number, h: number, color: Color): void
Draw a filled rectangle.

### text(str: string, x: number, y: number, color: Color): void
Draw text with the built-in 4×7 pixel font (uppercase, digits, basic punctuation).

## Input

### btn(key: Key): boolean
Returns true while the given button is held. Key ∈ "up","down","left","right","a","b","start","select".

### btnp(key: Key): boolean
Returns true on the frame the button was newly pressed (was not down on the previous frame).

### btnr(key: Key): boolean
Returns true on the frame the button was released. Use instead of btnp() for scene transitions and confirmations — acting on release feels more forgiving.

## Sound

### note(channel: 0 | 1, note: string, duration: number): void
Play a note on the given channel. note is "C4" / "A#3" / etc. duration in seconds.

### sfx_stop(channel?: 0 | 1): void
Stop a channel. With no argument, stops all channels.

## Sprite

### spr(id: number, x: number, y: number, flipX?: boolean, flipY?: boolean): void
Draw a registered sprite at the given screen position. flipX/flipY mirror.

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

### print

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
