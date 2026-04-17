# Production Coordination Brief: DUSKHOLD

## Production Intake
- **Game Type**: Roguelike (turn-based dungeon crawler)
- **Stage**: Concept-to-Milestone
- **Constraint**: Mono fantasy console (160x120, 16 grayscale, Lua)
- **Agent**: Zeta
- **Target**: Contest submission — single polished deliverable

## Concept
DUSKHOLD is a turn-based roguelike where the player descends through procedurally generated dungeon floors, battling enemies, collecting items, and surviving as long as possible. The grayscale palette reinforces a dark, oppressive atmosphere — bright tiles are safe, dark tiles are dangerous. Fog of war hides unexplored areas. Permadeath gives each run stakes.

## Scope
| Feature | Priority | Status |
|---------|----------|--------|
| Procedural dungeon generation (rooms + corridors) | P0 | Planned |
| Turn-based grid movement | P0 | Planned |
| FOV / fog of war (unexplored/explored/visible) | P0 | Planned |
| Player stats (HP, ATK, DEF, floor) | P0 | Planned |
| Melee combat with hit feedback | P0 | Planned |
| 4+ enemy types with distinct AI | P0 | Planned |
| Items: health potions, weapons, armor | P0 | Planned |
| Stairs to next floor (increasing difficulty) | P0 | Planned |
| Permadeath + death screen with run stats | P0 | Planned |
| Title screen + pause menu | P0 | Planned |
| Minimap overlay | P1 | Planned |
| Sound effects (steps, hits, pickups, death) | P1 | Planned |
| Camera shake on hits | P1 | Planned |
| Damage number popups | P1 | Planned |
| Score / kill tracking | P2 | Planned |

## Primary Mode: Concept-to-Milestone

### Milestone 1: Playable Core (Target: Single session)
- Dungeon generation, movement, FOV, enemies, combat, items, stairs, death screen
- All features in single main.lua for contest compliance

## Priority Decisions
| Decision | Choice | Rationale |
|----------|--------|-----------|
| File structure | Single main.lua | Simplicity, contest format |
| Dungeon algorithm | BSP / room placement | Reliable, varied layouts |
| FOV algorithm | Raycasting (simple) | Good balance of accuracy and performance |
| Tile size | 6x6 pixels | Fits ~26x20 view in 160x120 |
| Enemy AI | State-based (idle/chase/patrol) | Distinct behaviors per type |
| Item system | Pickup on walk-over | Simple, intuitive |
| Difficulty scaling | More enemies + stronger per floor | Standard roguelike curve |

## Risk Assessment
| Risk | Mitigation |
|------|------------|
| Performance with large maps | Limit map to 40x30, only draw visible area |
| Too easy / too hard | Tune HP/ATK/DEF values, playtest mentally |
| Dungeon gen produces bad layouts | Fallback: ensure connectivity with flood fill |
| Feature creep | Strict P0-first approach |

## What NOT To Do Yet
- No save/load system
- No inventory management UI (auto-equip best gear)
- No boss enemies (keep scope tight)
- No multiple dungeon tilesets
- No animation system beyond simple flashes

## Next Steps
1. Implement complete game in main.lua
2. Verify all GAME-STANDARD requirements met
3. Polish: sound, camera shake, damage popups
