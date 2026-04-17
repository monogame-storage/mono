# Production Coordination Brief: SHAKE DICE

## Production Intake
- **Game Type**: Board Game (Dice Rolling)
- **Stage**: Concept-to-Milestone
- **Constraint**: Mono fantasy console (160x120, 16 grayscale, Lua)
- **Scope**: Single-file shake-to-roll board game with motion controls

## Concept
SHAKE DICE is a board game where players physically shake their device to roll dice. The accelerometer detects shake intensity, driving dice momentum and animation. Players race around a 20-square board, landing on event squares that grant bonuses, penalties, or special actions. Supports 2-player hot-seat or solo vs AI. First to the finish wins.

## Primary Mode: Concept-to-Milestone

### Milestone 1: Core Shake-to-Roll
- Motion API shake detection via accelerometer magnitude delta
- Dice momentum system: harder shake = longer tumble animation
- Animated bouncing dice with dot-face rendering
- Fallback: press A to roll when motion unavailable

### Milestone 2: Board Game Loop
- 20-square linear board with start and finish
- Player tokens that animate along the path
- Event squares: bonus roll, lose turn, gain/lose points, warp
- Turn management for 2-player hot-seat and AI opponent

### Milestone 3: Polish
- Dice tumble sound via tone sweeps
- Landing thud and event jingles
- Board zoom/scroll to follow active player
- Title screen, HUD, win/lose screen
- AI opponent with simple random play
- Demo/attract mode with auto-shake

## Priority Decisions Table

| Decision | Priority | Rationale |
|----------|----------|-----------|
| Shake detection + dice roll | P0 | Core mechanic; must feel physical and responsive |
| Dice animation with faces | P0 | Visual payoff of the shake interaction |
| Board with player movement | P0 | Fundamental gameplay loop |
| Event squares | P1 | Creates variety and strategy |
| 2-player hot-seat | P1 | Social play is the point of a board game |
| AI opponent | P1 | Solo play option |
| Sound effects | P2 | Feedback and atmosphere |
| Title screen and flow | P2 | Polish and presentation |
| Attract/demo mode | P2 | Idle state |

## Risk Assessment
- **Motion API availability**: Mitigated by btnp("a") fallback for non-motion devices
- **Shake sensitivity tuning**: Use magnitude threshold with dead zone; tune for feel
- **Board readability at 160x120**: Use compact square grid with clear token contrast
- **Single file constraint**: Organized with section comments

## Next Steps
1. Implement shake detection and dice roll mechanic
2. Build board layout and player movement
3. Add event squares and turn logic
4. Polish with sound, menus, and AI
