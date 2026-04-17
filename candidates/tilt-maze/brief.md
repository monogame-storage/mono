# TILT MAZE - bmad-gds Brief

## Game Identity
- **Title:** TILT MAZE
- **Genre:** Arcade / Puzzle
- **Core Mechanic:** Motion-controlled ball rolling through procedural mazes

## Concept
Tilt your device to roll a ball through increasingly complex mazes. The ball has momentum and friction, so precise tilting is key. Reach the exit before time runs out. Each level generates a new maze with more walls, longer paths, and tighter corridors. Fallback d-pad controls for devices without motion sensors.

## Gameplay Loop
1. Maze appears with ball at the start (top-left region) and exit marker (bottom-right region)
2. Player tilts device (or uses d-pad) to roll the ball
3. Ball accelerates based on tilt angle, decelerates via friction
4. Walls block movement with a bounce effect
5. Timer counts down -- bonus points for speed
6. Reaching the exit completes the level; next maze is larger/harder
7. Game over if timer expires

## Visual Design (1-bit)
- Maze walls: white lines on black background
- Ball: filled white circle (3px radius)
- Exit: blinking white square/target marker
- Start position: small arrow indicator
- HUD: level number, timer, score at top
- Trail: faint dotted breadcrumb trail behind ball

## Controls
- **Primary:** `motion_x()` / `motion_y()` -- device tilt (-1 to 1)
- **Fallback:** `axis_x()` / `axis_y()` -- d-pad/gamepad analog
- START: begin game / pause
- Touch: tap to start from title

## Maze Generation
Recursive backtracker (depth-first) algorithm:
| Level | Grid Size | Time | Description |
|-------|-----------|------|-------------|
| 1 | 7x5 | 30s | Tutorial -- open corridors |
| 2 | 9x7 | 35s | Getting tighter |
| 3 | 11x8 | 40s | Medium complexity |
| 4 | 13x9 | 45s | Challenging |
| 5+ | 15x10 | 50s | Maximum density |

## Ball Physics
- Acceleration: tilt_value * 120 pixels/sec^2
- Max speed: 60 pixels/sec
- Friction: velocity *= 0.92 per frame
- Wall bounce: velocity component reversed and damped by 0.5
- Small dead-zone (0.05) to prevent drift on flat surfaces

## Sound Design
- Rolling hum: continuous low tone modulated by speed
- Wall bounce: short percussive noise burst
- Timer warning: rapid beeps when <5s
- Level complete: ascending arpeggio
- Game over: descending tones
- Exit proximity: pitch rises as ball nears exit

## Demo Mode
- AI navigates the maze using wall-following (right-hand rule)
- Infinite play -- generates new maze when solved
- 7-segment HH:MM clock displayed in top-right corner
- Any button/touch exits to title

## Scoring
- Base points per level: 100
- Time bonus: remaining seconds x 10
- Speed bonus: complete in under half the time limit for 200 extra
- Level multiplier: level number x base score
- Minimal bounces bonus: fewer than 5 wall hits = 50 extra
