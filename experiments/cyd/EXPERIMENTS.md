# CYD probe — experiment journal

Chronological log of how the working configuration in `README.md` was
found. Keep this as a reference for future debugging — it records
what we tried, what failed, and why we landed where we did.

## Phase 1 — raw blit feasibility (80 MHz the hard way)

**Question:** can a CYD sustain 30 fps with a 160×120 framebuffer
upscaled 2× onto the 320×240 display, leaving enough budget for a
Lua VM?

### First build — wrong panel assumption

Set up PlatformIO + Arduino framework + LovyanGFX 1.1.16, configured
`Panel_ILI9341` per CYD listings, targeted 40 MHz SPI. Built cleanly
on the first try; upload at 921600 baud failed with a head-of-packet
CRC error — dropped upload speed to 460800 and it flashed fine.

First bench run (rotating A/B/C/D modes, 3 s each):

```
Mode A (FLUSH only)      31.67 fps  dt 31.55–32.07 ms
Mode B (CLEAR + FLUSH)   30.84 fps  dt 32.41–33.12 ms
Mode C (CLEAR + 64)      30.57 fps  dt 32.69–33.04 ms
Mode D (CLEAR + 256)     29.90 fps  dt 33.37–33.71 ms
```

Clean SPI-bound numbers matching the 320×240 RGB565 theoretical
(~30.7 ms at 40 MHz). CPU essentially idle — the 256-rect case only
added 1.8 ms over raw flush.

**Problem:** Mode D was already below 30 fps with no Lua on top.
Needed a faster SPI clock.

### The "55 MHz" trap

Tried `CYD_SPI_FREQ=55000000` → numbers came back **identical** to
40 MHz. Investigation: ESP32 HSPI derives its clock from APB (80 MHz)
using integer dividers only. Valid frequencies:

```
80 / 1 = 80 MHz
80 / 2 = 40 MHz
80 / 3 = 26.67 MHz
80 / 4 = 20 MHz
…
```

55 MHz has no integer divisor. LovyanGFX silently rounds down to the
nearest valid rung (40). Skipped straight to 80 MHz.

### 80 MHz result

```
Mode A (FLUSH only)      61.67 fps  dt 16.21 ms
Mode B (CLEAR + FLUSH)   58.39 fps  dt 17.12 ms
Mode C (CLEAR + 64)      57.42 fps  dt 17.40 ms
Mode D (CLEAR + 256)     55.30 fps  dt 18.07 ms
```

Exactly ~2× the 40 MHz numbers — matches theory. Frame budget at
30 fps is 33.3 ms; worst case uses 18 ms; **~15 ms free for Lua**.
Phase 1 passes decisively.

### 6-minute Mode D soak

Replaced auto-cycle with touch-driven hold-on-mode so stability and
thermals could be observed. 6-minute soak on Mode D:

| Metric | Value |
|---|---|
| Samples | 265 / 267 s (1/sec) |
| Frames | 13,464 (50.43 fps mean) |
| `now` fps range | 50.30–50.50 (±0.1) |
| Cumulative drift | −0.1 fps (noise) |
| `dt_min` | locked at 19.60 ms |
| `dt_max` | locked at 20.50 ms |
| Spikes >21 ms | 0 |
| Drops <50 fps | 0 |

ESP32 was mildly warm to touch — well below thermal throttling.

## The panel detective story

Mid-Phase-1, before the SPI clock investigation above, a geometry
problem surfaced.

### Symptom: "leftover" space

With rotation 1, the 2× blit only filled the left ~2/3 of the screen
with the bottom cut off. Flipping to rotation 3 just mirrored the
leftover region to the opposite corner. Adding a `drawRect` border
using `TFT_RED` showed up as **blue**.

Two symptoms at once:
1. Drawing area was smaller than 320×240
2. Colors were shifted (red → blue)

### Rotation diagnostic

Built a boot sequence that cycled `setRotation(0..3)`, drawing a
thick border + four corner markers + rotation label in a distinct
color per rotation. Operator reported: **none** of the four fill the
physical screen, and **the text is mirrored**.

Mirrored text = MADCTL interpretation mismatch = wrong panel driver.
CYD dual-USB 2024+ batches ship **ST7789**, not ILI9341, despite the
listings. Added a `PANEL_DRIVER` build-time selector and switched to
`Panel_ST7789`.

### Color diagnostic

With ST7789 + `invert=true, rgb_order=false`: text was correct but
colors were still off. Tried `rgb_order=true`: operator reported
`RED → YELLOW`, `GREEN → PURPLE`. That's the RGB-complement-inverted
pattern, suggesting both flags were active when only one should be.

Built a second diagnostic that showed a fixed R/G/B/W/K color bar and
toggled `invertDisplay()` at runtime (Phase A vs Phase B). Operator
report:

- **Phase A (invert=ON):** blue, green, red, white, black — pure
  R↔B swap, W/K correct
- **Phase B (invert=OFF):** yellow, purple, cyan, black, white —
  Phase A with bit complement

Reading: polarity is correct with `invert=true`, so the remaining
R↔B swap has to come from `rgb_order`. Flipped `PANEL_RGB` back to
`false` and colors aligned.

### LovyanGFX ST7789 init quirk

Compile-time `invert=true` in `Panel_ST7789::config` **does not**
take effect during `init()`. Only a runtime `tft.invertDisplay(true)`
call after init asserts INVON. Discovered this because the rotation
diagnostic (which ran right after `init()`) had wrong colors even
though the config said `invert=true`. Permanent fix: call
`tft.invertDisplay(PANEL_INVERT)` explicitly in `setup()`.

## Phase 2 — Lua embedding

**Question:** can native Lua 5.4 sustain the same 256-rect workload
at 30 fps, and how does it compare to Wasmoon?

### Embedding

Downloaded Lua 5.4.7 stock sources, stripped `lua.c` and `luac.c`
(the standalone interpreter / compiler mains), dropped the rest into
`lib/lua/src/` with a `library.json` carrying `-DLUA_USE_C89
-DLUA_32BITS`. PlatformIO auto-discovered the library; linked on
first try. Flash 27% → 44% (+220 KB); RAM 8% (barely moved).

Changed canvas from 160×120 @ 2× to **160×144 @ 1:1** to match Mono's
current resolution standard. The 1:1 blit costs ~4.6 ms instead of
~16 ms, freeing even more budget for Lua.

### Synthetic workload

Ported the 256-rect step-and-draw loop to Lua:

```lua
local rand = math.random
local rects = {}
for i = 1, 256 do
  rects[i] = { rand(0, W-9), rand(0, H-9),
               (rand()-0.5)*4, (rand()-0.5)*4,
               rand(0, 15)*17 }
end

function step(n)
  for i = 1, n do
    local r = rects[i]
    local x, y = r[1]+r[3], r[2]+r[4]
    if x < 0 or x > Wm then r[3] = -r[3] end
    if y < 0 or y > Hm then r[4] = -r[4] end
    r[1] = x; r[2] = y
    fill(x, y, r[5])          -- C binding
  end
end
```

C side exposes a single `fill(x, y, gray)` binding that draws a fixed
8×8 fillRect. Each frame: `fillSprite(black)` → Lua `step(256)` →
`pushSprite(tft, 80, 48)`.

### Numbers

First run:

```
Lua 5.4.7 init-mem=49 KB
Mode D (256 rects, Lua) fps=56.5  dt 17.5–18.8 ms  (9 s sustained)
```

- Lua VM footprint: **49 KB**
- Per-rect Lua cost: ~39 μs
  (5-slot table access + 4 float ops + 1 C call)
- 30 fps budget math: flush+overhead 9 ms → **24 ms/frame free for
  game logic + draw** → ~600 sprite draws/frame at Lua speed

### Wasmoon decision

Wasmoon on ESP32 would require a WASM runtime (WAMR or wasm3):

- +100–200 KB flash for the runtime itself
- +500 KB for the Wasmoon WASM binary
- 2–5× slower via double interpretation (Lua bytecode → WASM →
  runtime interpreter)
- A separate linear-memory pool outside the ESP32 heap

Native Lua beats it on every axis. Decision: **ESP32 gets native Lua,
browser build keeps wasmoon**. Game code is the same either way — the
only thing that differs between platforms is the host binding layer,
which is platform-specific regardless.

## Phase 3 — bubble via engine API port

**Question:** does a real Mono game (`demo/bubble/main.lua`) run
unchanged on CYD?

### Inventory

Grepped `lua.global.set` in `runtime/engine.js` and walked bubble's
code to list every API it touches. Total surface area: ~25 bindings
plus a few globals and a ~10-line Lua prelude.

### Port checklist

- **Drawing primitives** — LovyanGFX Sprite has all of them native
  (`drawPixel`, `drawRect`, `fillRect`, `drawCircle`, `fillCircle`,
  `drawLine`). Each binding reads args via `lua_tonumber`, subtracts
  camera offset, looks up palette, calls the Sprite method.

- **Mono 4×7 font** — `runtime/engine.js` stores glyphs as 28-char
  "0"/"1" strings. Generated a `uint32_t MONO_FONT[128]` table via a
  Python one-liner, packed each glyph as 28 bits (`bit(i) = pixel at
  (i%4, i/4)`). `monoDrawText` implements the same alignment math as
  the JS version (`textW = len * 5 - 1`, HCENTER halves, etc.) and
  forces uppercase.

- **16-level palette** — matches `buildPalette(4)`:
  ```
  v = round((i / 15) * 255)
  g_palette[i] = color565(v, v, v)
  ```

- **Camera** — `cam(x, y)` writes globals, drawing bindings subtract
  them before plotting. `cam_shake(frames)` sets a counter; loop()
  offsets the `pushSprite` position by `±3` random pixels while the
  counter is non-zero.

- **Touch** — sampled once per frame at the top of `loop()` via
  `tft.getTouch()`. Screen→canvas conversion subtracts `(g_dstX,
  g_dstY)` and clips. Rising/falling edges computed against the
  previous frame. Exposed through `_touch_*` bindings; the prelude
  wraps them into `touch_pos(i) → x, y`.

- **Prelude** — copied verbatim from `runtime/engine.js` (the shim
  that turns `_btn/_btnp/_cam_get_x/_y/_touch_*` into nicer Lua APIs).
  Kept for zero-modification compatibility.

- **Embedding bubble.lua** — Python script reads `demo/bubble/main.lua`
  and wraps it into `src/bubble_game.h` as `static const char*
  BUBBLE_LUA = R"MLUA(...)MLUA";`. No file-system, no LittleFS — the
  script lives in flash as a string literal.

- **Sound** — `note`, `tone`, `noise`, `wave`, `sfx_stop` are all
  `l_noop`. Bubble's audio calls are silent but harmless.

### First run

```
=== CYD Mono Phase 3 — bubble ===
Panel:  ST7789  SPI=80000000 Hz
Canvas: 160x144 centered at (80,48)
Lua init OK. mem=64 KB
Entering main loop.
[bubble] fps=114.0  dt= 8.6..10.4ms  frm=114  lua=65KB
[bubble] fps=115.0  dt= 8.6..10.3ms  frm=229  lua=65KB
...
```

- Title screen renders on first boot
- 4×7 Mono font readable
- 5 title bubbles with pixel-art mobs inside
- ~114 fps with ~9 ms frame time (≈4× the 30 fps budget)
- Lua memory 65 KB (16 KB more than the synthetic bench, reasonable
  for the bubble state tables)

### Touch calibration — the long way around

First boot with the ported touch binding: bubble responded to taps,
but taps at the top of the screen registered at the bottom and vice
versa. Pure Y-axis flip. Reported as "아래 위가 뒤집혔어".

**Attempt 1:** Swap `y_min` and `y_max` in `Touch_XPT2046::config`
from `200/3900` to `3900/200`. Assumption: LovyanGFX maps raw ADC
linearly between min and max, so inverting the bounds should produce
an inverted mapping. Flashed; user reported **both X and Y were now
flipped**.

**Attempt 2:** Figured X must also have been flipped from the start
and only became noticeable after Y was fixed. Swapped X bounds too
(`300/3900` → `3900/300`). User reported **only X was flipped now**.
That contradicted Attempt 1 — the math didn't work out consistently.

**Attempt 3:** Reverted X to defaults, kept Y swapped. Added a
diagnostic log of every touch rising edge on the physical screen.
Asked the user to tap the four corners. Got one log entry — the
others were silently dropped because the original rising-edge test
was gated on "touch inside canvas box", which the corners were not.

**Attempt 4:** Widened the log to fire on any screen-level rising
edge. User tapped four corners + center. Results:

```
target(0, 0)   got screen(296, 219)   → both axes still flipped
target(319, 0) got screen(  6, 220)
target(319,239)got screen( 14,  14)
target(0, 239) got screen(293,  19)
target(160,120)got screen(151, 134)   → center is near-invariant
```

**Key insight:** every swap attempt had been silently reverted by
LovyanGFX. `Panel_Common::setCalibrateAffine` (and friends) normalize
`min < max` defensively so code assumptions downstream hold. My
"invert by swapping bounds" trick had **zero effect** — the touch
was running the raw-mapped configuration the whole time, and what I
thought were "different states after each swap" were all actually the
same state with user-dependent reporting precision.

**Attempt 5:** Abandoned the config-side approach. Applied the axis
flip manually in `sampleTouch()` by computing
`tx = (width-1)-tx; ty = (height-1)-ty` (180°). User reported only
X was now flipped — meaning the original raw reading was actually
**Y-only flipped**, and my 180° transform was introducing an unwanted
X inversion.

**Attempt 6 — guided calibration:** Added a temporary
`calibrateTouch()` routine called at the top of `setup()` before
anything else. Draws a red crosshair at each of 5 target screen
positions in turn, waits for a touch, and logs both the raw
`getTouch` reading and the 180°-flipped value next to the target:

```
CAL TOP-LEFT   target( 20, 20)  raw( 23,212)  flip(296, 27)
CAL TOP-RIGHT  target(300, 20)  raw(300,216)  flip( 19, 23)
CAL BOT-RIGHT  target(300,220)  raw(300, 23)  flip( 19,216)
CAL BOT-LEFT   target( 20,220)  raw( 29, 26)  flip(290,213)
CAL CENTER     target(160,120)  raw(169,122)  flip(150,117)
```

Reading across `raw(...)`: X matches target in every row. Y is
consistently inverted (`target_y ≈ 240 − raw_y`). That's the true
picture: **X is correct, Y-only flip is needed**.

**Final fix:** In `sampleTouch()`, only invert Y:

```cpp
if (touched) {
  ty = (tft.height() - 1) - ty;
}
```

The `calibrateTouch()` routine was removed after verification (still
in git history) — it's worth re-adding and rerunning if a new CYD
unit misbehaves.

### Lessons from the touch chase

1. **Don't trust calibration-bound swaps for axis inversion.**
   LovyanGFX normalizes `min < max` internally; the swap is a no-op.
   Apply the flip in C after `getTouch()` returns.
2. **Build a diagnostic view before the third guess.** Attempts 1–5
   were all blind swaps. Attempt 6 (the guided crosshair UI with
   per-target logging) took 15 minutes to write and produced the
   answer in a single run. Should have been Attempt 2.
3. **Center points don't help calibrate rotations.** A 180° rotation
   around the canvas center maps the center to itself, so CENTER
   looked "nearly correct" in every broken configuration and gave no
   signal. Always test corners, not centers.
4. **Users report symptoms, not axes.** "Both flipped" and "X flipped"
   coming from the same underlying config is a tell that the model
   disagrees with reality — switch to hard data immediately.

## Lessons to carry forward

1. **CYD panel variant is not discoverable from listings.** Always
   run a rotation + color diagnostic on a new unit before trusting
   documentation.
2. **`Panel_ST7789`'s `invert` config flag is not honored in init.**
   Always assert `invertDisplay()` explicitly after init.
3. **ESP32 HSPI clock is quantized to APB/N.** Assume 40 or 80,
   nothing in between. Test with Serial output of the actual clock,
   not the requested value.
4. **1:1 blit beats 2× upscale by a lot on SPI.** If the source
   resolution matches the canvas, never upscale — eat the letterbox
   borders and save the bandwidth.
5. **Native Lua 5.4 is dramatically better than Wasmoon on MCUs.**
   Wasmoon only makes sense where WASM sandboxing is the point.
6. **Mono's engine API is small enough to C-port in one sitting.**
   ~25 functions + 1 font table + 1 palette + ~10 lines of prelude
   was enough to run `bubble` unchanged.
