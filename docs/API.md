# Mono API Reference v1.0 "Mono"

## Lifecycle

A game is composed of three callback functions:

```typescript
function init(): void    // called once when the game starts
function update(): void  // per-frame logic (30fps)
function draw(): void    // per-frame rendering
```

## Graphics

### circ(cx, cy, r, color: Color): void
Draw a circle outline.

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

### circf

### cls

### date

### drawImage

### drawImageRegion

### frame

### go

### gpix

### gyro_alpha

### gyro_beta

### gyro_gamma

### imageHeight

### imageWidth

### line

### loadImage

### mode

### motion_enabled

### motion_x

### motion_y

### motion_z

### noise

### note

### pix

### print

### rect

### rectf

### scene_name

### screen

### sfx_stop

### spr

### sspr

### swipe

### text

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
