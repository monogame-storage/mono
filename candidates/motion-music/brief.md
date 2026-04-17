# Production Coordination Brief: MOTION MUSIC

## Production Intake
- **Game Type**: Musical Instrument / Creative Tool
- **Stage**: Concept-to-Milestone (v1.0 deliverable)
- **Engine**: Mono Fantasy Console (160x120, 1-bit, Lua)
- **Constraint**: Single `main.lua`, no external assets, all sound via `note()`/`tone()`/`noise()`/`wave()`

## Concept
**MOTION MUSIC** -- your phone becomes a musical instrument. Tilt left/right to sweep pitch (low to high). Tilt forward/back to control volume/intensity via note duration and waveform richness. Shake hard to trigger drum hits (noise bursts). Gyro rotation (alpha/yaw) selects waveform: square, sine, triangle, sawtooth. Visual feedback includes real-time waveform display, current note name, particle effects that pulse with the sound, and a 4-track looper for layering recordings.

## Scope
| Feature | Priority | Status |
|---------|----------|--------|
| Tilt-to-pitch mapping (left=low, right=high) | P0 | Planned |
| Forward/back tilt controls intensity | P0 | Planned |
| Shake detection triggers drum hits | P0 | Planned |
| Gyro rotation selects waveform (4 types) | P0 | Planned |
| Visual waveform display | P0 | Planned |
| Current note name display | P0 | Planned |
| Particle effects reactive to sound | P1 | Planned |
| Record mode (capture a sequence) | P1 | Planned |
| Loop playback of recordings | P1 | Planned |
| 4-track layering | P1 | Planned |
| Demo mode (auto-play when idle) | P0 | Planned |
| Keyboard fallback (arrows + A/B) | P0 | Planned |

## Primary Mode: Concept-to-Milestone

### Milestone 1: Core Instrument (v1.0)
- Tilt controls pitch across 2+ octave range
- Forward/back tilt modulates intensity
- Shake triggers noise/drum hits
- Gyro selects waveform type
- Real-time visual feedback (waveform, note name, particles)
- 4-track looper: record, playback, layer
- Demo mode with auto-composition

## Priority Decisions
| Decision | Choice | Rationale |
|----------|--------|-----------|
| Pitch mapping | Chromatic scale C3-C5 | 2 octaves gives expressive range |
| Tilt axis | motion_x for pitch | Natural left-right tilt on phone |
| Shake detection | magnitude threshold on accel | Works reliably across devices |
| Waveform select | gyro_alpha (yaw) | Rotating phone is intuitive |
| Recording format | {frame, note, wave, dur} | Lightweight, easy to replay |
| Visual style | 1-bit with dithered waveforms | Matches mode(1) constraint |

## Audio Architecture
- Channel 0: Live instrument (player-controlled)
- Channel 1: Loop playback / layered track
- Waveform set per-note via `wave(ch, type)`
- `note(ch, "C4", dur)` for pitched notes
- `noise(ch, dur)` for percussion/shake hits
- `tone(ch, hz1, hz2, dur)` for pitch sweeps

## Risk Assessment
| Risk | Mitigation |
|------|-----------|
| Motion API unavailable (desktop) | Arrow key fallback with on-screen indicators |
| Latency in motion-to-sound | Minimal processing, direct mapping each frame |
| Audio channel conflicts | Dedicated channels per function |
| Recording overflow | Cap at 300 frames (~10s at 30fps) per track |

## Demo Mode
- Auto-plays a pre-composed melody using simulated motion
- Cycles through waveforms and pitch patterns
- Shows "TILT TO PLAY" overlay, exits on any input

## Next Steps
1. Implement motion-to-pitch mapping
2. Add waveform visualization
3. Build shake detector
4. Create recording/looping system
5. Add particle effects
6. Compose demo sequence

## What NOT To Do Yet
- No MIDI export
- No preset scales/key locking
- No network sharing of recordings
- No multi-device jam sessions
