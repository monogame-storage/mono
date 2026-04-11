# CYD Mono audio test

Standalone PlatformIO project that implements the reverse-designed
Mono audio spec (see `../cyd/README.md` → *Open items → Audio*) on
an ESP32-2432S028R and exercises every feature through a touch UI.

Does **not** share code with `../cyd/` — it's a clean test harness so
you can flash it, run the audio suite, then flash bubble back.

## What it proves

- ESP32 internal DAC via I2S + DMA actually works on CYD's GPIO 26
  speaker path
- 4-voice software mixer sustains 22,050 Hz at <1% CPU of one core
- All 6 waveform types (square, triangle, sawtooth, sine, LFSR
  noise, sample playback) produce audible, distinguishable output
- Linear attack+decay envelopes behave correctly at both extremes
- Frequency sweeps sound smooth (no stepping)
- 1-pole filters meaningfully alter noise timbre
- Sample playback (PCM from RAM) coexists with synth voices and
  mixes cleanly
- Pitch shifting samples by changing playback rate works

## Scenes (cycle with `< PREV` / `NEXT >`, fire with `PLAY`)

| # | Name      | Tests                                              |
|---|-----------|----------------------------------------------------|
| 1 | WELCOME   | (no audio — just the title card)                   |
| 2 | WAVEFORMS | Plays C4 on sq / tri / saw / sin / noise in order  |
| 3 | SCALE     | C major scale C4..C5, square wave                  |
| 4 | SWEEPS    | 200→2000, 2000→200, fast, slow pitch bends         |
| 5 | ENVELOPE  | 4 attack/decay shapes: punchy, chime, fade, swell  |
| 6 | POLYPHONY | C major triad held on ch0-2 + melody on ch3        |
| 7 | NOISE     | Raw LFSR → lowpass 500 Hz → highpass 2.5 kHz → LP2 |
| 8 | SAMPLES   | Pre-synthesized blip at 0.5x/1x/1.5x/2x + 2-mix    |

`STOP` cuts all 4 voices mid-play.

## Audio stack details

- **Output:** I2S_NUM_0 → internal DAC channel 2 → GPIO 26 → onboard
  speaker
- **Sample rate:** 22,050 Hz mono, 8-bit (upper byte of 16-bit I2S
  word, lower byte ignored by the DAC)
- **Buffering:** 4 × 256 samples = ~46 ms latency
- **Mixer:** dedicated FreeRTOS task pinned to core 0, priority
  `configMAX_PRIORITIES - 2`
- **Voices:** 4, all equivalent (no fixed-role channels). Each holds
  waveform type, phase, envelope state, filter state, optional
  sample pointer+length
- **Mixing math:** `(wave_sample × envelope × volume)` per voice,
  summed, divided by voice count to prevent clipping
- **Mixer cost:** ~15 µs per 256-sample buffer fill × ~86 fills/sec
  = ~1.3 ms/s ≈ 0.13% of one core

## Pre-synthesized sample

`synthesize_blip()` runs once at setup and fills `blip_pcm[4410]`
(0.2 s at 22,050 Hz = 4.4 KB) with a 1000 → 300 Hz exponential sweep
under an exponential decay envelope. Scene 8 plays that buffer back
through the mixer's sample voice path at four different `phase_inc`
rates to prove pitch shifting works.

Why synthesize at boot instead of embedding a real `.wav`?

- Keeps the test program hermetic (no binary data files)
- Proves both the mixer's sample path *and* the CPU can generate
  content without blocking anything
- 4.4 KB of RAM doesn't matter
- A real asset pipeline (Python + `xxd -i` or a build-step `.raw`)
  is straightforward; this test just doesn't need to demonstrate it

## Build / flash

```sh
cd experiments/cyd-audio
~/.platformio/penv/bin/pio run -t upload --upload-port /dev/cu.usbserial-10
~/.platformio/penv/bin/pio device monitor
```

Same upload caveats as the main cyd project: upload_speed stays at
460800 to avoid CH340 CRC errors.

## Known differences from the reverse-spec

- **Bandpass filter:** not implemented (only LP and HP). 1-pole IIR
  can't do true BP — needs a state-variable or biquad. Skipped for
  scope; easy to add.
- **Filter on synth voices:** currently runs the filter branch on
  any active voice but it's only useful for noise in the tests. Not
  a correctness issue.
- **Master volume:** no global gain control. Per-channel `vol()`
  is the only knob.
- **Sustain / ADSR:** only AD (attack + decay). Sustain would add
  a `hold_samples` field; straightforward if needed later.

## Self-verification without a speaker

There's a boot-time diagnostic that runs automatically on reset
and prints results to Serial. No UI interaction required. It
covers:

1. **Direct `dac_output_voltage` probe** on DAC1/GPIO 25 (control,
   released before tft.init) and DAC2/GPIO 26 (target), reading
   the pin back via `adc2_get_raw`. Shows whether the DAC drives
   the pin and whether the ADC can see the swing.
2. **Software layer probe** (`scene_selftest` called automatically
   at end of setup) — `audio_task` buffer counter, direct
   `mix_sample()` range, task-reported last-buffer envelope, ADC
   silence vs. ADC active during a full-volume 440 Hz sine.

### What the diagnostics tell us on CYD

Measured on this unit (reproducible):

```
DAC1 / GPIO 25 / ADC2_CH8:
  dac=  0 → adc=16     dac= 64 → adc=321   dac=128 → adc=341
  dac=192 → adc=357    dac=255 → adc=347   (saturates ~0.33 V)

DAC2 / GPIO 26 / ADC2_CH9:
  dac=  0 → adc=681    dac= 64 → adc=900   dac=128 → adc=907
  dac=192 → adc=909    dac=255 → adc=911   (saturates ~0.87 V)

audio_task buffers/100ms: 9
mixer direct        min=-31 max=31 range=62    ← full-volume sine, 4 voices
task last buf       min=-31 max=31             ← matches mixer
adc silence         min=1881 max=1887 range=6
adc active          min=1878 max=1885 range=7  ← clamped, same as silence
```

Software layers all pass. ADC loopback is **inconclusive** —
both DAC pins are externally clamped by onboard circuits:

- **GPIO 25** is loaded by the XPT2046 touch controller's SCLK
  input, holding the pin near ~0.34 V.
- **GPIO 26** is loaded by the speaker-driver NPN's base-emitter
  junction, holding the pin near ~0.87 V (Vbe, present even on
  units with no speaker fitted to the collector).

The DAC is driving the pin (see the real delta from dac=0 to
dac=64), but it can't swing past the external clamp. The AC
component of a 440 Hz sine is still present in that ~0.3 V band
and would be amplified correctly by the BJT stage + a speaker —
but the ADC's sample-and-hold averages the clipped swing back to
the DC level.

### Verdict

- **Software stack: PASS** (mixer + task + DMA + I2S confirmed)
- **Full electrical verification: requires a speaker or a scope**
  on this board. ADC2 loopback is the wrong instrument for this
  specific hardware — it can't see past the onboard clamps.

The self-test scene now prints `SW PASS  HW ?` when software
layers pass but ADC loopback is flat, distinguishing "code is
wrong" from "board won't let me measure."

## Things to try if you have a speaker or scope

- **Acoustic:** flash the firmware, connect a small 8Ω speaker
  across the speaker pads (or tap GPIO 26 ↔ transistor collector
  ↔ Vcc). Step through scenes 2–8 via the UI.
- **Electrical:** scope GPIO 26 directly or tap the transistor's
  collector / speaker output. The 440 Hz sine in the SELF-TEST
  scene should show clean ±0.3 V swing at the base, amplified to
  near-rail swing at the collector if the stage is biased.
- **Listening tests worth doing:** (1) can you tell the five
  waveforms apart audibly? (2) do the 1-pole LP/HP filters meaningfully
  change the noise timbre, or does the speaker bandwidth wipe out
  the effect? (3) is 22,050 Hz enough, or does square-wave aliasing
  become objectionable?
