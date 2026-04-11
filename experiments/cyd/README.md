# CYD Mono runtime

Native-code Mono runtime running on an **ESP32-2432S028R** (Cheap
Yellow Display, dual-USB variant). Phase-3 snapshot: `demo/bubble`
runs unchanged via a minimal Mono engine API port, driven by native
Lua 5.4.7.

For the story of how this configuration was found (panel discovery,
SPI clock probing, benchmark numbers), see **EXPERIMENTS.md**.

## Status

| Area | State |
|---|---|
| Display pipeline | Working — 1:1 centered, 80 MHz SPI |
| Lua VM | Working — Lua 5.4.7 native, ~65 KB for bubble |
| Mono engine API subset | Working — enough for `demo/bubble` |
| Touch input | Working — Y axis flipped manually in `sampleTouch()` |
| Sound | Stubs only |
| Image loading / sprite sheets | Not ported |
| Multi-surface canvas | Not ported |

## Hardware

- **Board:** ESP32-2432S028R (2.8" CYD), dual-USB revision
- **MCU:** ESP32-D0WD-V3, dual-core, 240 MHz, 320 KB RAM, 4 MB flash
- **Display:** ST7789 (not ILI9341 — dual-USB 2024+ batches ship ST7789)
- **Touch:** XPT2046 resistive on dedicated VSPI bus
- **Connection:** CH340 USB-serial (VID 1A86:7523) — both USB ports
  enumerate on the same CH340

## Configuration

### Display (LovyanGFX Panel_ST7789)
| Setting | Value | Notes |
|---|---|---|
| SPI bus | HSPI | |
| Pins | SCK=14 MOSI=13 MISO=12 DC=2 CS=15 RST=−1 BL=21 | |
| Clock | **80 MHz** | only valid rung above 40; no 55 MHz on ESP32 HSPI |
| Rotation | **3** (landscape, flipped) | |
| `invert` | `true` + **explicit `invertDisplay(true)` after `init()`** | compile-time flag alone is not honored by `Panel_ST7789` |
| `rgb_order` | `false` | CYD ST7789 is wired RGB |
| Native panel size | 240×320 (portrait); logical 320×240 after rotation | |

### Canvas
| Setting | Value |
|---|---|
| Size | 160×144 (current Mono standard) |
| Blit | 1:1 centered via `pushSprite(&tft, 80, 48)` |
| Color depth | 16-bit (RGB565) |
| Palette | 16-level grayscale, `v = round(i/15 × 255)` — matches `buildPalette(4)` in `runtime/engine.js` |

### Touch (LovyanGFX Touch_XPT2046)
| Setting | Value |
|---|---|
| SPI bus | VSPI (independent of display) |
| Pins | SCK=25 MOSI=32 MISO=39 CS=33 IRQ=36 |
| Clock | 1 MHz |
| Calibration | `x_min=300 x_max=3900 y_min=200 y_max=3900` (defaults) |
| Y-axis fix | `ty = (height − 1) − ty` applied in `sampleTouch()` |

On this CYD unit, after `setRotation(3)` the XPT2046 returns **correct
X** but **inverted Y** relative to the display. Trying to express this
via swapped `y_min`/`y_max` does **not** work — LovyanGFX defensively
normalizes the bounds internally so `min < max` always, silently
undoing the swap. The flip is applied in C in `sampleTouch()` instead.

Verified with a 5-point guided calibration (TL, TR, BR, BL, center)
that recorded target vs. raw vs. 180°-flipped values. See
`EXPERIMENTS.md` for the numbers. If touch misbehaves on a new unit,
the `calibOneTarget()` routine is available in git history (commit
with the Phase 3 bubble port).

Screen→canvas conversion: `(cx, cy) = (tx − 80, ty − 48)`, clipped
to `[0..160) × [0..144)`.

### Lua
| Setting | Value |
|---|---|
| Engine | Lua 5.4.7 (stock sources in `lib/lua/`) |
| Build flags | `-DLUA_USE_C89 -DLUA_32BITS` |
| VM memory | ~49 KB base, ~65 KB with `bubble` loaded |
| Prelude | Mirrors `runtime/engine.js` shim (wraps `_touch_*`, `_cam_get_*`, `_btn*`) |

### Ported engine API

| Category | Functions |
|---|---|
| Drawing | `cls`, `pix`, `rect`, `rectf`, `circ`, `circf`, `line`, `text` |
| Camera | `cam`, `cam_reset`, `cam_shake`, `cam_get` |
| Input | `touch`, `touch_start`, `touch_end`, `touch_count`, `touch_pos` |
| Meta | `screen` (returns 0), `mode` (no-op), `frame`, `time`, `print` |
| Stubs | `btn`, `btnp` (no physical buttons), `note`, `tone`, `noise`, `wave`, `sfx_stop` |
| Globals | `SCREEN_W`, `SCREEN_H`, `COLORS`, `ALIGN_LEFT/HCENTER/RIGHT/VCENTER/CENTER` |

The 4×7 Mono font is faithfully ported from `runtime/engine.js` into
`src/mono_font.h`. Camera offsets are applied C-side before drawing.

## Build tree

```
experiments/cyd/
├── platformio.ini           Arduino framework, LovyanGFX, Lua flags
├── README.md                this file — current environment spec
├── EXPERIMENTS.md           how we got here (phase journal)
├── lib/
│   └── lua/                 Lua 5.4.7 stock sources + library.json
└── src/
    ├── main.cpp             LGFX_CYD, engine API bindings, main loop
    ├── mono_font.h          generated — 4×7 Mono font table
    └── bubble_game.h        generated — bubble main.lua embedded as a C string
```

`mono_font.h` and `bubble_game.h` are generated, not hand-edited. If
either source changes, regenerate:

```sh
# Font table (only needed if runtime/engine.js FONT data changes)
python3 -c "...see EXPERIMENTS.md for the generator snippet..."

# Bubble script
python3 -c "
with open('/Users/ssk/work/mono/demo/bubble/main.lua') as f: src = f.read()
with open('src/bubble_game.h','w') as f:
    f.write('#pragma once\nstatic const char* BUBBLE_LUA = R\"MLUA(\n'
            + src.rstrip() + '\n)MLUA\";\n')
"
```

## Build / flash / monitor

```sh
cd experiments/cyd
~/.platformio/penv/bin/pio run                                  # build
~/.platformio/penv/bin/pio run -t upload \
    --upload-port /dev/cu.usbserial-10                          # flash
~/.platformio/penv/bin/pio device monitor -p /dev/cu.usbserial-10  # serial
```

If `pio device monitor` fails with `termios Operation not supported`,
use a direct pyserial reader:

```sh
~/.platformio/penv/bin/python3 -c "
import serial,sys
s=serial.Serial('/dev/cu.usbserial-10',115200)
while True:
    l=s.readline()
    if l: sys.stdout.write(l.decode('utf-8','replace')); sys.stdout.flush()
"
```

Upload speed is capped at **460800** — 921600 causes CRC errors on
this CH340 dongle.

## Tuning knobs (in `platformio.ini`)

| Define | Valid values | Notes |
|---|---|---|
| `CYD_SPI_FREQ` | 40000000 / 80000000 | ESP32 HSPI has no valid steps between these |
| `MONO_W` / `MONO_H` | 160 / 144 | match main Mono engine resolution |
| `PANEL_DRIVER` (in `main.cpp`) | 1=ILI9341, **2=ST7789** (default), 3=ILI9342 | change only for hardware variants |

## Observed performance (80 MHz SPI, 1:1 blit)

- **bubble title screen:** ~114 fps, frame time 8.6–10.4 ms
- **256 moving rects in Lua:** ~56 fps, frame time 17.5–18.8 ms
- **30 fps budget math:** ~9 ms fixed overhead (flush + HUD + touch),
  → ~24 ms/frame free for Lua game logic + draw
  → ~600 sprite fillRect calls per frame possible at Lua speed

## Open items

- **Audio.** All sound functions are no-ops. If any demo depends on
  sound for timing (bubble doesn't), those would silently desync.
- **Image loading.** No `loadImage` / `spr` / `sspr`. Games that ship
  sprite sheets won't run without these.
- **Per-unit touch calibration.** The Y-axis flip is applied
  unconditionally. If a new CYD unit needs a different transform
  (other axis, different calibration bounds), rerun the guided
  `calibOneTarget` / `calibrateTouch` routine preserved in git
  history and apply the correct flip in `sampleTouch()`.

## Why this configuration (short version)

- **ST7789 not ILI9341** — dual-USB CYDs (2024+) ship this panel even
  though listings still say ILI9341. Wrong driver = mirrored text +
  partial screen + wrong colors.
- **80 MHz SPI, not 40 or 55** — ESP32 HSPI clock is APB/N with
  integer N only. 55 MHz silently clamps to 40. 80 MHz = ~2× blit
  throughput; passes 6-min stress soak with 0 drops.
- **1:1 blit, not 2x upscale** — Mono is already 160×144 natively.
  Upscaling to 320×240 triples the blit cost for no visual gain
  (the screen just has black borders either way).
- **Native Lua 5.4, not Wasmoon** — Wasmoon on ESP32 via WAMR/wasm3
  would be 2–5× slower, 600+ KB bigger, and use extra linear memory.
  Native Lua builds cleanly from `lib/lua/src` at 49 KB VM memory.
- **Y-flip in C, not calibration swap** — LovyanGFX normalizes
  `y_min < y_max` defensively, so inverting the config bounds is a
  silent no-op. The manual flip in `sampleTouch()` is the only thing
  that actually changes the mapping.
