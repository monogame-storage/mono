# Production Coordination Brief: TILT PINBALL

## Production Intake
- **Game Type**: Arcade Pinball
- **Stage**: Concept-to-Milestone
- **Constraint**: Mono fantasy console (160x120, 1-bit, Lua, motion sensor)
- **Scope**: Single-file pinball with motion tilt control and classic mechanics

## Concept
TILT PINBALL is a classic pinball machine rendered in 1-bit on the Mono fantasy console. The ball bounces off bumpers, ramps, and targets while the player controls flippers with A/B buttons. Tilting the phone (or using arrow keys) nudges the table, subtly affecting ball trajectory. But tilt too hard and the machine calls "TILT!" -- disabling flippers for 3 seconds as a penalty. Features bumpers, score targets, drain guard, and multi-ball.

## Motion API
- `motion_x()`: Table tilt left/right (affects ball X velocity)
- `motion_y()`: Table nudge forward/back (affects ball Y velocity)
- `motion_enabled()`: Check if device has motion sensor
- Hard tilt detection: When absolute motion exceeds threshold, trigger TILT penalty
- Fallback: Left/Right arrows for tilt, A button for left flipper, B for right flipper

## Primary Mode: Concept-to-Milestone

### Milestone 1: Core Pinball Physics
- Ball with gravity, velocity, and collision
- Two flippers (left/right) activated by A/B buttons
- Ball-flipper collision with proper deflection
- Walls and playfield boundary collision
- Ball launcher (plunger) mechanic

### Milestone 2: Table Features
- Circular bumpers that bounce ball and award points
- Score targets (hit zones for bonus points)
- Drain at bottom, ball lost when it falls through
- 3 balls per game
- Score display and ball count HUD

### Milestone 3: Motion & Tilt
- Motion tilt affects ball physics (subtle nudge)
- TILT detection when motion exceeds threshold
- TILT penalty: flippers disabled for 3 seconds, warning flash
- Keyboard fallback for non-motion devices

### Milestone 4: Polish
- Demo/attract mode with auto-play
- Sound effects (bumper hits, flipper activation, drain, tilt warning)
- Multi-ball bonus (extra ball from target combos)
- Score multiplier system
- Title screen and game over flow
- 1-bit visual style with dithering for depth

## Priority Decisions Table

| Decision | Priority | Rationale |
|----------|----------|-----------|
| Ball physics + gravity | P0 | Core pinball feel requires believable physics |
| Flipper controls (A/B) | P0 | Primary player interaction |
| Wall/bumper collision | P0 | Table must feel physical |
| Motion tilt nudge | P0 | Contest theme - motion control |
| TILT penalty mechanic | P0 | Signature risk/reward mechanic |
| Score system + HUD | P1 | Feedback and progression |
| Ball launcher/plunger | P1 | Authentic pinball start |
| Sound effects | P1 | Satisfying feedback on hits |
| Demo/attract mode | P1 | Required by contest rules |
| Multi-ball | P2 | Exciting bonus moment |
| Score multiplier | P2 | Depth for skilled players |
| Dithered visuals | P2 | 1-bit aesthetic polish |

## Risk Assessment
- **Physics complexity**: Simplified circle-vs-line/circle collisions; no full rigid body needed
- **1-bit rendering**: High contrast works well for pinball (bright ball on dark table)
- **Motion sensitivity**: Tunable threshold prevents accidental TILT
- **160x120 resolution**: Vertical pinball table fits well in portrait-ish aspect

## What NOT To Do
- No multiple tables (one well-designed table is enough)
- No complex ramp 3D effects
- No network features
- No save/load (session-only high score)
