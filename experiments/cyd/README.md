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

- **bubble title screen:** ~116 fps render, 30.0 Hz logic tick,
  8.5 ms avg work per frame
- **256 moving rects in Lua:** ~56 fps, frame time 17.5–18.8 ms
  (Phase 2 synthetic bench; logic tick decoupling added later)
- **30 fps budget math:** ~9 ms fixed overhead (flush + touch + HUD),
  → ~24 ms/frame free for Lua game logic + draw
  → ~600 sprite fillRect calls per frame possible at Lua speed

### Logic tick vs render rate

Mono's engine.js hardcodes `FPS = 30`. Every demo uses frame-counted
timing (e.g. bubble's `spawn_rate = 28` meaning "every 28 _update
calls"), so _update must run at exactly 30 Hz to keep game speed
correct. Render is decoupled and runs free — on CYD the loop blits
the canvas ~116 times per second even though the game state only
changes 30 times per second. The extra blits are wasted work but
(a) they cost <10 ms each, well under the 33 ms budget, and
(b) they keep the render path exercised so the stats line shows
real hardware headroom.

Implementation: `loop()` gates `_update` (and touch sampling) on a
33,333 µs deadline; `_draw` + `pushSprite` run every iteration.

## Open items

### Audio (stubbed; feasible — and worth reverse-specifying)

`note`, `tone`, `noise`, `wave`, `sfx_stop` are registered as
`l_noop` — they accept and ignore arguments. bubble doesn't call
any of them, so the stubs are fine for the current demo. Other
demos that need audio:

- `demo/synth` — audio is the point of the demo
- `demo/starfighter`, `demo/pong` — SFX only

CYD hardware: **GPIO 26 → NPN transistor → onboard speaker.**
GPIO 26 is also ESP32 DAC channel 2, so both PWM and analog
output paths are available on the same pin. The speaker is a
small magnetic unit with a usable frequency response roughly
**400–6000 Hz** — below and above that the physical transducer
rolls off hard.

#### DAC channel mapping (ESP-IDF naming is counterintuitive)

| Macro                       | DAC  | GPIO   | CYD use        |
|---                          |---   |---     |---             |
| `I2S_DAC_CHANNEL_RIGHT_EN`  | DAC1 | **25** | XPT2046 SCLK   |
| `I2S_DAC_CHANNEL_LEFT_EN`   | DAC2 | **26** | speaker path   |

Use `LEFT_EN` + `I2S_CHANNEL_FMT_ONLY_LEFT` for audio on GPIO 26.
`RIGHT_EN` routes the I2S DMA through DAC1, which takes the pad
over from the touch controller — breaks touch and audio at the
same time, one setting two symptoms.

#### Pin clamping — ADC2 loopback is bounded

Measured with `dac_output_voltage()` + `adc2_get_raw()` on both
DAC channels (`experiments/cyd-audio` boot diagnostic):

| Pin            | DAC=0    | Saturates at  | Loopback swing |
|---             |---       |---            |---             |
| GPIO 25 (DAC1) | ~0.02 V  | ~0.34 V       | ~0.32 V        |
| GPIO 26 (DAC2) | ~0.65 V  | ~0.87 V       | ~0.22 V        |

Both pins are loaded by onboard circuits:

- **GPIO 25** — XPT2046 touch controller's SCLK input impedance
- **GPIO 26** — speaker-driver NPN's base-emitter junction (the
  transistor is fitted even on units with no speaker soldered
  to the collector)

The DAC *is* driving the pin (`dac=0` → `dac=64` produces a real
ADC delta), it just can't push past the external load to Vcc.
ADC2 loopback only sees the clamped-and-averaged swing, so it's
not a valid acoustic test on CYD. Full verification needs a
speaker (acoustic) or scope (electrical) on the transistor's
output stage, where the AC component of the DAC signal gets
amplified normally.

#### Capability envelope

With I2S + internal DAC + a per-sample software mixer (the
pragmatic path for anything beyond beeps), the CYD can
comfortably deliver:

| Axis | Realistic value | Limit |
|---|---|---|
| Sample rate | **22,050 Hz** mono | speaker Nyquist is ~12 kHz anyway |
| Bit depth | **8-bit unsigned** | ESP32 internal DAC is 8-bit |
| Voices | **4** polyphonic | CPU cost <1% of one core at 4 voices |
| Waveforms | square, triangle, sawtooth, sine, LFSR noise | 256-entry tables, ~1 KB |
| Envelope | linear attack + decay (AD, no sustain) | per-sample cost trivial |
| Pitch | fixed or exponential sweep | same precision as current `tone()` |
| Filter | optional per-voice 1-pole IIR (low/high/band) | 3 mul per sample |
| Stereo | no — speaker is mono | physical |
| Reverb/FX | no | not attempted |

CPU: 4 voices × 15 cycles/sample × 22,050 Hz ≈ **1.3 Mcycles/s
= 0.55% of one 240 MHz core**. Headroom is effectively infinite.

#### Reverse-spec proposal (adopt CYD envelope as the Mono standard)

The current Mono audio spec in `runtime/engine.js` is defined
**by Web Audio API accidents** — 2 channels, hardcoded 20 ms
fade-out, `BiquadFilter` on noise, arbitrary oscillator types
from the browser. That's not a spec, it's "whatever Web Audio
does with its own defaults". It ports poorly because it inherits
the host's capability ceiling instead of declaring one.

Flipping it around: **use the CYD's realistic envelope as the
Mono audio standard**. Any game that works on CYD automatically
works in the browser (the browser's ceiling is strictly higher);
the reverse is not true. This is the same pattern Mono already
uses for video (160×144, 16-color grayscale, 16×16 sprites —
those aren't browser limits, they're chosen constraints that
define the fantasy console).

Proposed spec:

```
MONO SOUND v2

Channels:    4  (ch = 0..3, all equivalent)
Sample rate: 22,050 Hz mono
Bit depth:   8-bit unsigned
Waveforms:   square, triangle, sawtooth, sine, noise
Envelope:    per-voice attack + decay (seconds, linear)
Pitch:       fixed or exponential sweep (start → end)
Filter:      optional per-voice 1-pole low / high / band
Volume:      per-channel 0..1
```

Lua surface (backward-compatible with existing demos that already
use `note/tone/noise/wave/sfx_stop`):

```lua
wave(ch, "square" | "triangle" | "saw" | "sine" | "noise")
adsr(ch, attack_sec, decay_sec)
vol(ch, 0..1)
note(ch, "C4", dur)
tone(ch, f_start, f_end, dur)
noise(ch, dur, "low"|"high"|"band", cutoff_hz)
sfx_stop(ch)     -- nil ch stops all
```

Differences from current Mono audio:

| Property | Current | Reverse-spec v2 |
|---|---|---|
| Channels | 2 | **4** (Game Boy–level polyphony) |
| Sample rate | browser default (44.1/48 kHz) | **22,050 Hz** fixed |
| Bit depth | 32-bit float (Web Audio) | **8-bit** |
| Envelope | hardcoded 20 ms tail | **configurable AD** |
| Noise filter | Biquad (Web Audio) | 1-pole IIR |

Net effect: **richer musically** (4 voices, configurable
envelope) while **narrower technically** (8-bit, 22 kHz, no
stereo) — which is exactly the fantasy-console trade. The
browser runtime would need to be constrained down to match;
that's a small engine change.

Implementation paths, in order of effort:

1. **LEDC PWM square wave** (~200 lines). `ledcWriteTone()` +
   a timer ISR for sweeps and envelopes. Only square wave.
   Good enough for `pong` and `starfighter` but doesn't cover
   the reverse-spec (no triangle / sine / LFSR / filter). Only
   worth doing as a throwaway first step.
2. **I2S + internal DAC + software mixer** (~300 lines).
   Implements the full reverse-spec above. Needed for
   `demo/synth` to be authentic and for Mono v2 audio to land
   on CYD as the reference platform.

### Image loading (absent; should be startup pre-bake)

`loadImage`, `spr`, `sspr` are not implemented. Most demos that
aren't pure primitives need them — `demo/invaders`, `demo/tiltmaze`,
etc.

**Design decision: pre-bake at game startup, not at firmware
build time and not per-frame.** Build-time bake locks the firmware
to a single game and blocks the "one CYD, many games" direction
Mono is heading. Per-frame decode is pointless (the engine's
internal image format is already palette bytes). Startup pre-bake
is the middle ground: assets ship as files on LittleFS or SD, the
firmware is game-agnostic, and decode cost is paid once at boot.

Recommended architecture:

```
ESP32 boot
  → mount LittleFS (internal) or SD (CYD onboard slot)
  → scan /games/<name>/
      ├─ main.lua       → doString into Lua VM
      ├─ manifest.json  → metadata, asset list
      └─ sprites/*.png  → PNGdec → palette bytes → images[id]
  → call _init()
  → main loop
```

Format notes:

- **PNG:** works, LovyanGFX has it built in, `PNGdec` (bitbank2)
  standalone is ~5 KB working memory. Fine for startup decode.
- **WebP:** skip. libwebp is 300–500 KB flash + 150–250 KB RAM,
  no production-quality small ESP32 port exists, and WebP's
  advantages (photo compression) don't help 16-color palette
  art. PNG compresses palette art as well or better.
- **QOI:** viable alternative (~150 lines C header-only, perfect
  for palette data), but PNG + author-side tooling is more
  ergonomic.
- **Pre-baked palette bytes directly:** also fine as a format for
  built-in demos, using the same embed-as-C-string pattern we
  used for `bubble_game.h`.

RAM budget check (current usage):

```
  25 KB  Arduino base
  46 KB  canvas 160x144 RGB565
  65 KB  Lua VM + bubble state
-------
 136 KB  used
 184 KB  free (320 KB total)
```

At ~1 byte per pixel (palette index), 184 KB holds ~180,000 pixels
= ~700 sprites of 16×16, or a 320×240 background plus ~400
sprites. Enough for any Mono game we care about. PSRAM-equipped
CYD variants add 4–8 MB if headroom is ever tight.

### Per-unit touch calibration

The Y-axis flip is applied unconditionally. If a new CYD unit
needs a different transform (other axis, different calibration
bounds), rerun the guided `calibOneTarget` / `calibrateTouch`
routine preserved in git history and apply the correct flip in
`sampleTouch()`.

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
