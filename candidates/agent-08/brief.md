# Production Coordination Brief: THE DARK ROOM — Sound Navigator

## Production Intake
- **Game Type**: Mystery/exploration (audio-primary navigation)
- **Stage**: Concept-to-Milestone
- **Constraint**: Mono fantasy console (160x120, 2-bit 4 grayscale, 30fps, single main.lua)
- **Agent**: 08
- **Target**: Contest 4 submission — THE DARK ROOM theme

## Concept
You wake up blind in a pitch-black room. The screen is almost entirely black. Your only guide is SOUND. Different objects emit distinct tones — a door hums low, a key chimes high, walls crackle with noise. Frequency rises as you approach objects (louder = closer). Navigate by ear through multiple rooms, find keys, unlock doors, escape. Minimal visuals: a faint player dot, subtle pulse rings to represent sound waves emanating from you. The 2-bit palette (black, dark gray, light gray, white) reinforces total darkness — only the barest hint of light exists.

## Scope
| Feature | Priority | Status |
|---------|----------|--------|
| Audio-based proximity system (freq/pitch = distance) | P0 | Planned |
| Player movement (d-pad) with footstep sounds | P0 | Planned |
| Sonar ping mechanic (press A to emit pulse) | P0 | Planned |
| Multiple object types with unique sound signatures | P0 | Planned |
| Key + locked door puzzle mechanic | P0 | Planned |
| 3 rooms with increasing complexity | P0 | Planned |
| Minimal visual: player dot + sonar rings | P0 | Planned |
| Title screen + victory screen | P0 | Planned |
| Pause (SELECT) | P0 | Planned |
| Demo/attract mode with auto-play | P1 | Planned |
| Wall collision with noise feedback | P1 | Planned |
| Ambient drone background | P1 | Planned |
| Heartbeat sound that intensifies near danger | P2 | Planned |

## Primary Mode: Concept-to-Milestone

### Milestone 1: Playable Core
- Room layout, movement, sonar ping, sound proximity, key+door, 3 rooms
- All in single main.lua, mode(2)

## Priority Decisions
| Decision | Choice | Rationale |
|----------|--------|-----------|
| Visual style | Near-black, sonar rings only | Reinforces blindness theme |
| Audio engine | tone()/wave()/noise() per channel | Use all 4 channels for layered sound |
| Proximity model | Inverse distance -> frequency mapping | Intuitive: higher pitch = closer |
| Room design | Hand-crafted tile grids | Reliable, tuned for audio puzzles |
| Object sounds | Key=sine high, Door=triangle low, Wall=noise, Exit=chord | Distinct signatures |

## Risk Assessment
| Risk | Mitigation |
|------|------------|
| Sound-only may confuse players | Sonar ring visual + text hints at start |
| Limited audio channels (4) | Prioritize nearest/most important object |
| Too hard to navigate blind | Subtle visual breadcrumbs on sonar ping |
| Monotonous gameplay | Each room introduces new object type |

## GAME-STANDARD Compliance
- START begins game from title
- SELECT pauses during gameplay
- mode(2) called in _init()
- Single file, no go() calls
