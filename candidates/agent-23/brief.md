# CONTAINMENT BREACH
## Agent 23 (Wave 3) -- Sonar + Time Pressure + Crafting

### Concept
A flooding underground research facility. 120-second countdown. You navigate dark rooms using sonar pings, craft tools from scavenged components, and collect evidence before escaping. An entity patrols the corridors -- your sonar reveals the way but also betrays your position. Collect evidence files for the true ending, or just escape with your life.

### Lineage
- **Agent 13** (Echolocation): Sonar navigation, entity stalker AI, ring particles, sound-based horror
- **Agent 19** (It Approaches): Countdown timer, urgency system, escalating horror overlays, vignette/tendrils/static
- **Agent 18** (The Dark Room): Crafting system, inventory, item combining, narrative items, evidence collection

### Mechanics
1. **Sonar** -- Press A to ping. Expanding ring reveals walls, items, doors, entity. Entity hears your ping and investigates.
2. **120s Countdown** -- Water is rising. Urgency increases visual/audio horror. Timer penalty on entity catch (respawn costs 10s).
3. **Crafting** -- Find components (wire+battery=flashlight, pipe+valve=lever, card+tape=keycard). Press B for inventory, combine items.
4. **Evidence** -- 3 hidden evidence files across rooms. Collect all 3 + escape = true ending. Just escape = survival ending.
5. **Entity** -- Patrols rooms. Attracted to sonar pings. Faster each room. Caught = jumpscare + time penalty + respawn.
6. **3 Rooms** -- Each requires a crafted tool to unlock the exit. Room 3 exit requires master keycard.

### Controls
- D-Pad: Move (tile-based)
- A: Sonar ping
- B: Toggle inventory / combine mode
- START: Begin game / pause
- SELECT: Pause

### Technical
- `mode(2)` -- 2-bit, 4 grayscale shades (0=black, 1=dark, 2=light, 3=white)
- 160x120 resolution, 20x15 tile grid (8px tiles)
- 4 sound channels: sonar, objects, ambient, footsteps
- Demo mode after 5s idle on title screen
- Single-file Lua
