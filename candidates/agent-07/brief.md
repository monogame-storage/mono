# The Dark Room: Fractured Memories - Production Intake Brief (bmad-gds)

## Project Overview
**Title:** The Dark Room: Fractured Memories
**Genre:** Mystery Adventure / Interactive Fiction (Multiple Endings)
**Platform:** Mono Fantasy Console (160x120, 2-bit / 4 grayscale)
**Agent:** 07

## Scope
- First-person text-and-visual mystery adventure
- Wake up in a dark room with no memory; explore, find clues, make choices
- 7 rooms: Dark Room, Hallway, Lab, Office, Basement, Roof, Vault
- Inventory system: collect and use key items to unlock paths
- Branching narrative tracked by flags/variables
- 3 distinct endings:
  - **ESCAPE (Good):** Find the key and exit through the front door
  - **TRAPPED FOREVER (Bad):** Trigger the lockdown sequence, sealed inside
  - **UNCOVER THE CONSPIRACY (True):** Collect all evidence, access the vault, expose the truth
- Atmospheric sound: ambient drones, footsteps, discovery chimes, tension stings
- Demo/attract mode with auto-play sequence

## Primary Mode: Concept-to-Milestone

### Milestone 1: Core Loop (COMPLETE IN SINGLE PASS)
- Title screen with flickering atmosphere
- Room rendering with 2-bit grayscale pixel art
- Text-based interaction: examine, take, use, move
- Inventory bar (up to 6 items)
- Flag system tracking: has_key, has_badge, has_evidence, saw_files, lockdown_triggered, vault_open
- 3 endings with unique ending screens
- START begins game, SELECT pauses
- Sound effects throughout
- Demo mode after idle on title

## Priority Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Visual style | Pixel-art rooms + text overlay | Maximizes atmosphere in 2-bit palette |
| Interaction | Cursor-based menu per room | Clean UX on d-pad; up/down select, A confirms |
| Branching | Flag-based state machine | Simple, reliable, supports 3+ endings |
| Inventory | 6-slot bar at bottom | Visible context without cluttering 120px height |
| Endings | 3 tiers (good/bad/true) | Replay value; true ending requires thorough exploration |
| Sound | note() drones + noise() stings | Builds tension with minimal API |
| Room count | 7 rooms | Enough depth for meaningful exploration without scope creep |

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| 2-bit palette limits readability | High-contrast design; white text on black; dithering for mid-tones |
| Screen space for text + visuals | Split layout: top 70px art, bottom 50px text/menu |
| Branching complexity | All flags are booleans; endings checked in priority order |
| Single-file size | Rooms stored as compact data tables; shared draw routines |

## Next Steps
- Polish room transitions with fade effects
- Tune pacing: ensure true ending requires visiting all rooms
- Add atmospheric ambient sound loop on each room
