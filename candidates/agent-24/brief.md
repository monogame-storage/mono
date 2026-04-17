# ECHO CHAMBERS
## Agent 24 (Wave 3) — Sonar + Puzzles + Multiple Endings

### Lineage
- Agent 13: sonar navigation, entity AI, horror atmosphere
- Agent 15: puzzle mechanics (pattern, combo, wires, tiles), multi-ending system
- Agent 18: crafting/narrative, documents, inventory, rich world-building

### Concept
Five sealed chambers in an underground research facility. Each room is pitch black.
You navigate by sonar — pinging reveals walls and puzzle elements as brief flashes.
But each ping alerts the Entity, a presence that hunts by sound.

Each chamber contains a unique puzzle that must be solved in darkness:
1. **COMBINATION** — Dial a 4-digit code (hints from sonar echoes)
2. **PATTERN** — Memorize and reproduce a grid pattern
3. **WIRE** — Match numbered wire pairs on a grid
4. **SEQUENCE** — Repeat a tone sequence (audio memory)
5. **CIPHER** — Decode a substitution cipher from document clues

### Mechanics
- **Sonar**: Press A to ping. Expanding ring reveals walls (dim) and objects (bright). Cooldown between pings.
- **Entity**: Drawn to ping sounds. Patrols when calm, chases when alerted. Catches you = death or ending.
- **Puzzles**: Press B near a puzzle terminal to engage. Each room has one. Solved puzzles stay solved.
- **Documents**: Found via sonar. Provide puzzle hints and lore. Read with B.
- **Ping danger**: Each ping in a room increases entity aggression. Too many pings = entity spawns/accelerates.

### Endings (3)
- **TRUE FREEDOM** (all 5 puzzles solved): Full escape. You remember everything. The facility is exposed.
- **PARTIAL ESCAPE** (some puzzles solved, reach exit): You escape but memories are fragmented. The truth stays buried.
- **CONSUMED** (entity catches you in final room): Trapped forever. You become part of the facility.

### Controls
- D-Pad: Move (tile-based)
- A: Sonar ping / Confirm in puzzle
- B: Interact with terminal / Submit puzzle answer
- START: Pause
- SELECT: View solved count

### Technical
- `mode(2)`, 160x120, 2-bit (4 shades: black, dark, light, white)
- Surface-first rendering
- Single file, demo mode on idle, sound effects on all channels
