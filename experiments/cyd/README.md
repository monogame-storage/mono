# CYD Mono Blit Probe

**Purpose:** a single, narrow experiment — *can an ESP32-2432S028R (CYD)
push a 160×120 framebuffer to its 320×240 ILI9341 at 30 fps with enough
CPU headroom left over to run game logic?*

This is Phase 1 of a potential ESP32 port of Mono. It does **not** embed
a Lua VM, does **not** implement any engine API, and does **not** touch
the rest of the repo. It exists only to answer the hardware-ceiling
question so we can decide whether to keep going.

## What it measures

Four modes cycle every 3 seconds:

| Mode | Description | Tells us |
| --- | --- | --- |
| A | `FLUSH` only — re-push a static frame | Raw 2× blit ceiling (SPI + LovyanGFX overhead) |
| B | `CLEAR + FLUSH` | Cost of clearing the 160×120 sprite per frame |
| C | `CLEAR + 64 rects + FLUSH` | Realistic small game loop |
| D | `CLEAR + 256 rects + FLUSH` | Stress case — lots of fillRect work |

For each mode the probe prints `fps`, `dt_min`, `dt_max`, and frame count
over Serial, and shows the current mode + fps on-screen.

## 30 fps budget

Frame budget is `33,333 µs`. Mode A is the hardware ceiling; the others
tell us how much of that budget remains for drawing + (eventually) Lua.

A rough back-of-envelope at 40 MHz SPI:

```
Bits per frame (2x = 320x240 RGB565) = 320 * 240 * 16 = 1,228,800 bits
Theoretical flush                    = 1,228,800 / 40,000,000 ≈ 30.7 ms
```

…which leaves almost nothing. That's why this probe matters — if
LovyanGFX + DMA can't beat the naive math, or if 55/80 MHz SPI works on
this specific board, we need to know *now*.

## Build & flash

PlatformIO is already installed at `~/.platformio/penv/bin/pio`.

```bash
cd experiments/cyd
~/.platformio/penv/bin/pio run                     # build only
~/.platformio/penv/bin/pio run -t upload           # flash
~/.platformio/penv/bin/pio device monitor          # read results
```

Plug the CYD into a USB port (either of the dual-USB jacks works — the
single CH340 enumerates on both). If `upload` can't find the port,
list candidates with `pio device list`.

## Tweaking the SPI clock

Flip `CYD_SPI_FREQ` in `platformio.ini`:

- `40000000` — safe default, works on every CYD I've seen
- `55000000` — often works, 35 % faster flush
- `80000000` — sometimes works, can produce glitches; try it

Rebuild + reflash after each change and compare Mode A numbers.

## What a "pass" looks like

- **Mode A ≥ 45 fps** — raw blit has real headroom, Lua port is viable
- **Mode A 30–45 fps** — tight; doable but Lua will feel the squeeze
- **Mode A < 30 fps** — hardware can't keep up even bare; stop here,
  either drop to 15 fps or rethink the pipeline (dirty rects, partial
  updates, or a different controller)

Mode C is the more honest "can a typical game hit 30 fps" signal.

## Not in scope

- Lua VM selection / benchmarking (Phase 2)
- Engine API port (Phase 3)
- Touch input, audio, filesystem, WiFi
- Any modification to `runtime/`, `demo/`, or anything outside
  `experiments/cyd/`
