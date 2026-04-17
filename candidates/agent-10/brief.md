# Production Coordination Brief: THE DARK ROOM (Procedural)

## Production Intake
- **Game Type**: Mystery Adventure / Procedural Generation
- **Stage**: Concept-to-Milestone (v1.0 deliverable)
- **Engine**: Mono Fantasy Console (160x120, 2-bit 4 grayscale, Lua)
- **Constraint**: Single `main.lua` file, no external assets, `mode(2)`

## Concept
**THE DARK ROOM** -- A procedurally generated mystery adventure. You wake in darkness. Every playthrough generates a unique layout of rooms, items, puzzles, and a final solution from a seed. Explore interconnected rooms, collect clues and items, solve lock-and-key puzzles, piece together what happened. The seed is displayed so players can share and replay the same mystery. High replay value through true procedural generation of all game content.

## Scope
| Feature | Priority | Status |
|---------|----------|--------|
| Seed-based PRNG for full procedural generation | P0 | Planned |
| Room graph generation (6-10 rooms per seed) | P0 | Planned |
| Procedural item/clue placement | P0 | Planned |
| Lock-and-key puzzle chain generation | P0 | Planned |
| First-person room exploration (text + visual) | P0 | Planned |
| Inventory system (collect, use, combine) | P0 | Planned |
| Atmospheric sound (note/noise) | P0 | Planned |
| Title screen with seed entry | P0 | Planned |
| Demo/attract mode with auto-play | P0 | Planned |
| Win condition: escape the dark room | P0 | Planned |
| Room transition animations | P1 | Planned |
| Environmental storytelling via clue fragments | P1 | Planned |
| Multiple puzzle archetypes (lock/code/combine) | P1 | Planned |
| Tension system (ambient dread escalation) | P2 | Stretch |

## Primary Mode: Concept-to-Milestone

### Milestone 1: Core Loop (v1.0)
- Seed-based procedural room graph with 6-10 rooms
- Items and puzzles generated per seed
- Navigate rooms, examine objects, collect items
- Solve puzzles to unlock new areas
- Find the exit to win
- Title screen with seed display and entry
- Demo mode after idle timeout
- Atmospheric audio throughout

## Priority Decisions
| Decision | Choice | Rationale |
|----------|--------|-----------|
| Generation scope | Full (rooms, items, puzzles, solution) | Maximizes replay value |
| Visual style | First-person room view with 2-bit atmosphere | Fits dark room theme perfectly in limited palette |
| Navigation | Cardinal directions between rooms | Simple, intuitive, works with d-pad |
| Puzzle types | Lock-key, codes, item combinations | Varied but procedurally generatable |
| Seed display | On title + HUD | Enables sharing and replay |

## Risk Assessment
| Risk | Mitigation |
|------|-----------|
| Unsolvable generated puzzles | Validate solution path during generation |
| Repetitive feel across seeds | Large pool of room types, item names, clue text |
| 2-bit palette limiting atmosphere | Leverage darkness as aesthetic; flickering, dithering |
| Complexity in single file | Clean section organization, compact data tables |

## Next Steps
1. Implement seed-based PRNG
2. Build room graph generator with validation
3. Create item/puzzle placement system
4. Wire up exploration UI and inventory
5. Add atmospheric audio and transitions
6. Implement demo mode

## What NOT To Do Yet
- No save/load system
- No combat mechanics
- No NPC dialogue trees
- No multi-floor dungeons
