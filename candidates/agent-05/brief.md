# Production Coordination Brief: THE DARK ROOM -- Inventory & Crafting

## Production Intake
- **Game Type**: Mystery Adventure (Inventory/Crafting Focus)
- **Stage**: Concept-to-Milestone (v1.0 deliverable)
- **Engine**: Mono Fantasy Console (160x120, 2-bit / 4 grayscale, Lua)
- **Constraint**: Single `main.lua`, mode(2), 2-bit palette (0-3), surface-first rendering

## Concept
Wake in a pitch-black room. Grope in the dark for objects. Combine them in your inventory to solve puzzles and escape. A key needs a handle. A flashlight needs batteries. Torn note fragments reveal a chilling message. The inventory IS the gameplay -- every puzzle is about finding, combining, and using items on the environment.

## Scope
| Feature | Priority | Status |
|---------|----------|--------|
| Room exploration with object hotspots | P0 | Planned |
| Item pickup with feedback sounds | P0 | Planned |
| Inventory UI (open/close, scroll, select) | P0 | Planned |
| Item combining (drag A onto B) | P0 | Planned |
| Use item on environment (key on door, etc.) | P0 | Planned |
| 3 rooms (cell, hallway, exit) | P0 | Planned |
| Flashlight + batteries = light mechanic | P0 | Planned |
| Note fragments -> full message | P0 | Planned |
| Key + handle = working key | P0 | Planned |
| Title screen + demo mode | P0 | Planned |
| Atmospheric sound (drips, creaks) | P1 | Planned |
| Pause menu (SELECT) | P0 | Planned |
| Win/escape ending | P0 | Planned |
| Contextual interaction prompts | P1 | Planned |

## Priority Decisions
| Decision | Choice | Rationale |
|----------|--------|-----------|
| Palette | 2-bit (0-3) | Contest constraint; maximizes dark atmosphere |
| Inventory access | X button toggle | Instant access, clean overlay |
| Combining method | Select A then B | Simple two-step, no drag needed on d-pad |
| Room transitions | Fade to black | Fits dark theme, hides loading |
| Item limit | 8 slots | Fits screen, forces resource thinking |

## Risk Assessment
| Risk | Mitigation |
|------|-----------|
| 2-bit readability | High contrast borders, clear icons, text labels |
| Inventory UI too small | Dedicate full screen overlay, large slots |
| Combining too obscure | Show "combine" prompt when valid pair selected |
| Player gets stuck | Environmental text hints, contextual prompts |

## Milestone 1: Core Loop (v1.0)
- Pick up items from rooms
- Open inventory, select items, combine them
- Use items on environment to progress
- 3 rooms with item-gated progression
- Flashlight reveals hidden objects
- Note fragments form escape message
- Full title -> play -> win flow

## What NOT To Do Yet
- No save/load system
- No branching story paths
- No enemy encounters
- No timed puzzles
