# The Dark Room: Fractured Memories - Production Intake Brief (bmad-gds)

## Project Overview
**Title:** The Dark Room: Fractured Memories (Visual Exploration Edition)
**Genre:** Top-Down Mystery Adventure / Multiple Endings
**Platform:** Mono Fantasy Console (160x120, 2-bit / 4 grayscale)
**Agent:** 16
**Lineage:** agent-07 (multi-ending narrative) + agent-02 (visual map, fog of war)

## Concept
Replaces agent-07's text-menu room navigation with agent-02's top-down tile map exploration. You physically walk through 7 rooms, interact with objects by pressing A nearby, and uncover a branching narrative with 3 endings. Fog of war reveals tiles as you explore, making discovery feel earned.

## Scope
- Top-down 8x8 tile map with player character movement (D-Pad)
- 7 rooms: Dark Room, Hallway, Lab, Office, Basement, Rooftop, Vault
- Fog of war: tiles reveal as you walk near them; dark rooms have limited light radius
- Flashlight pickup expands visibility in dark rooms
- Interaction zones (Z tiles) trigger narrative events from agent-07's branching story
- Inventory system: up to 6 items, browsable with B button
- 3 distinct endings:
  - **ESCAPE (Good):** Find the brass key, reach the front door
  - **TRAPPED (Bad):** Activate the basement lockdown
  - **THE TRUTH (True):** Collect all evidence, access vault terminal, broadcast the conspiracy
- Door locks gated by items (fuse, badge, evidence) and flags (has_light, saw_files)
- Sound effects: footsteps, pickups, door sounds, ambient drones, danger stings
- Demo mode: auto-walks in the hallway after idle on title screen
- Pause screen with START button

## Architecture
- Rooms defined as 20x13 ASCII grids (# wall, . floor, D door, F furniture, Z zone, I item)
- Collision: 5-point hitbox check against tile grid
- Fog of war: per-room revealed[] table tracks which tiles the player has seen
- Narrative actions: zone interactions call do_narrative_action() which mirrors agent-07's full branching logic
- All state in local variables; single _update/_draw loop

## Priority Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Navigation | Top-down movement replaces text menus | More immersive; player physically explores |
| Fog of war | Per-tile reveal tracking | Rewards exploration; builds tension in dark rooms |
| Interaction | A button near Z/I/F tiles | Natural spatial interaction instead of menu selection |
| Narrative | Zone tiles trigger agent-07 story events | Preserves all 3 endings and branching depth |
| Dark rooms | Light radius + flashlight upgrade | Atmospheric; flashlight feels like a real discovery |
| HUD | Bottom bar (room name, item count, hints) | Leaves map area uncluttered |

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| Player may miss interaction zones | Z tiles have subtle sparkle hint |
| Dark room too frustrating | Starting visibility of 3 tiles is enough to find flashlight |
| Door requirements unclear | Locked door message hints at what's needed |
| Fog of war performance | Only checks 20x13 grid per frame; lightweight |

## Controls
- D-Pad: Move character
- A: Interact with nearby objects/zones
- B: Open/close inventory
- START: Pause/resume, start game from title
