# Production Coordination Brief: NITRO DASH

## Production Intake
- **Game Type**: Racing (Pseudo-3D)
- **Stage**: Concept-to-Milestone
- **Constraint**: Mono fantasy console (160x120, 16 grayscale, Lua)
- **Scope**: Single-file racing game with OutRun-style road rendering

## Concept
NITRO DASH is a pseudo-3D racing game inspired by classic arcade racers like OutRun and Road Rash. The player races down a winding road at high speed, dodging traffic and obstacles while competing against the clock. Segment-based road rendering creates a convincing sense of depth and speed on a 160x120 grayscale display.

## Primary Mode: Concept-to-Milestone

### Milestone 1: Core Racing Loop
- Pseudo-3D road rendering with curves and hills
- Player car with acceleration, braking, steering
- Road stripe animation for speed sensation
- Parallax background scrolling

### Milestone 2: Game Systems
- AI opponent cars to dodge and overtake
- Obstacle variety (cars, rocks, oil slicks)
- Checkpoint/timer system with lap tracking
- Nitro boost mechanic (limited uses per race)

### Milestone 3: Polish
- Engine sound via tone sweeps
- Crash/collision with screen shake
- Best time leaderboard (session)
- Title screen, HUD, game over flow
- Multiple track segments (curves, straights, hills)

## Priority Decisions Table

| Decision | Priority | Rationale |
|----------|----------|-----------|
| Pseudo-3D road rendering | P0 | Core visual identity; must feel like a real racer |
| Speed sensation (stripes, parallax) | P0 | Racing MUST feel fast |
| Player controls (accel/brake/steer) | P0 | Fundamental gameplay |
| AI traffic / obstacles | P1 | Creates challenge and tension |
| Checkpoint timer system | P1 | Gives structure and replayability |
| Nitro boost mechanic | P1 | Signature mechanic, risk/reward |
| Sound effects (engine, crash) | P2 | Atmosphere and feedback |
| Multiple track variety | P2 | Replay value |
| Best time tracking | P2 | Progression hook |
| Screen shake on crash | P2 | Juice and feel |

## Risk Assessment
- **Road rendering complexity**: Mitigated by using proven segment-projection math
- **Performance on 160x120**: Low resolution actually helps; fewer pixels to draw
- **Grayscale limitation**: Use contrast and dithering patterns to differentiate road, grass, sky
- **Single file constraint**: Keep code organized with clear section comments

## Next Steps
1. Implement road segment projection and rendering
2. Add player car with physics
3. Layer in traffic, obstacles, and timer
4. Polish with sound, effects, and menus

## What NOT To Do Yet
- No multiplayer or split-screen
- No track editor
- No save/load to disk (session-only leaderboard)
- No complex particle systems beyond simple effects
