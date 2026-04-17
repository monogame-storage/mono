# Game Production Coordination Brief

## Scope
- Game / build stage: concept -> vertical-slice
- Engine / platform context: Mono fantasy console (160x120, 2-bit 4 grayscale, Lua 5.4, 30fps)
- Team shape: solo AI agent (Agent #06)
- Next public beat: contest tournament submission
- Confidence: high

## Primary mode
concept-to-milestone

## Game Concept: THE DARK ROOM - TIME PRESSURE
You wake in pitch darkness. A countdown timer ticks. Something is coming.
Solve puzzles across 3 rooms to escape before time runs out. Tension escalates:
sounds grow louder, the screen pulses, darkness closes in around the edges.
Speed-solving under pressure with atmospheric dread.

## What matters most now
- Countdown timer creates genuine tension: visible, audible, always pressing
- Escalating atmosphere: screen pulse intensity and vignette darkness increase as time runs low
- 3 rooms with distinct speed-puzzles: pattern lock, wire sequence, code cipher
- 2-bit grayscale palette (0-3) used for maximum contrast and mood
- Sound design: ticking clock, warning tones, success/fail stings
- Demo mode: auto-plays through puzzles on title idle

## Recommended next artifact
milestone-brief

## Priority decisions
| Decision | Why now | Owner | Risk if delayed |
|----------|---------|-------|-----------------|
| Timer duration tuning | Core tension driver | Agent 06 | Too easy or impossible |
| Puzzle complexity | Must be solvable under pressure | Agent 06 | Frustrating gameplay |
| Escalation curve | Atmosphere depends on pacing | Agent 06 | Flat tension |
| Room transition flow | Affects momentum | Agent 06 | Jarring experience |

## Immediate next steps
1. Implement countdown timer with visual/audio escalation
2. Build 3 puzzle rooms: pattern lock, wire sequence, code cipher
3. Add atmospheric effects: vignette, screen pulse, sound escalation
4. Polish with title screen, demo mode, game over states

## What not to do yet
- Complex narrative or dialogue trees
- Inventory system beyond puzzle state
- Save/load system
- More than 3 rooms
