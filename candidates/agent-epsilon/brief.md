# Production Coordination Brief: MONO BEAT

## Production Intake
- **Game Type**: Rhythm / Music
- **Stage**: Concept-to-Milestone (v1.0 deliverable)
- **Engine**: Mono Fantasy Console (160x120, 16 grayscale, Lua)
- **Constraint**: Single `main.lua` file, no external assets, all music generated via `note()`/`tone()`

## Concept
**MONO BEAT** -- a DDR/Guitar Hero-style rhythm game where notes scroll down 4 lanes toward a hit zone. Players press d-pad directions to match falling notes in time with pre-composed songs. Features timing judgments, combo system, score multipliers, multiple songs, and reactive visuals.

## Scope
| Feature | Priority | Status |
|---------|----------|--------|
| 4-lane note highway (left/down/up/right) | P0 | Planned |
| Timing judgment (Perfect/Great/Good/Miss) | P0 | Planned |
| Pre-composed songs with note()/tone() playback | P0 | Planned |
| Combo counter + score multiplier | P0 | Planned |
| Title screen + song select | P0 | Planned |
| Results screen with letter grade (S/A/B/C/D) | P0 | Planned |
| Visual feedback (lane flash, beat pulse) | P1 | Planned |
| 3 songs with varying difficulty | P1 | Planned |
| Particle effects on hits | P1 | Planned |
| Brightness gradient (notes brighten near hit zone) | P1 | Planned |
| Pause menu (SELECT) | P0 | Planned |
| Beat-reactive background visualization | P2 | Stretch |

## Primary Mode: Concept-to-Milestone

### Milestone 1: Core Loop (v1.0)
- Scrolling note highway with 4 lanes
- Input detection with timing windows
- Judgment display + combo counter
- At least 3 playable songs
- Title -> Song Select -> Play -> Results flow
- Audio plays via note()/tone() synced with chart

## Priority Decisions
| Decision | Choice | Rationale |
|----------|--------|-----------|
| Lane count | 4 (d-pad) | Maps perfectly to available inputs |
| Note scroll direction | Top-to-bottom | Most intuitive for small screen |
| Timing windows | 3 tiers + miss | Balances accessibility and depth |
| Song data format | Inline Lua tables | No file I/O needed, fast iteration |
| Audio approach | note()/tone() on hit + background melody | Layer player hits with song playback |

## Risk Assessment
| Risk | Mitigation |
|------|-----------|
| Audio timing drift | Use frame-based timing, sync to time() |
| Small screen readability | Large clear lane markers, high contrast |
| Limited input (4 dirs + A/B) | A/B used for menu, d-pad for gameplay |
| Performance with many notes | Cap active notes, efficient rendering |

## Next Steps
1. Implement core note highway rendering
2. Build timing judgment system
3. Compose 3 songs as chart data
4. Wire up audio playback
5. Add scoring, combos, results

## What NOT To Do Yet
- No online leaderboards
- No custom song editor
- No difficulty modifiers beyond per-song charts
- No multiplayer mode
