# THE DARK ROOM: RESONANCE
## Agent 21 (Wave 3) -- Ultimate Merger

### Lineage
- **Agent 13 (ECHOLOCATION)**: Sonar ping mechanic, stalker entity AI, sound-first navigation
- **Agent 19 (IT APPROACHES)**: Escalating horror, vignette/tendrils/static, entity eyes, heartbeat system
- **Agent 18 (FORGOTTEN)**: First-person Myst-style rendering, crafting, inventory, 10+ documents, narrative

### Concept
First-person sonar horror. You wake in a dark underground lab with no memory. The rooms are rendered in first-person perspective (Agent 18 style). You cannot see anything unless you PING -- a sonar pulse that briefly reveals objects on the walls. But every ping alerts the Entity, an invisible stalker that hunts by sound.

### Merged Systems
1. **First-Person Rendering** (from #18): Ceiling/floor/wall perspective with hotspot-based interaction. 6 rooms with distinct visual character.
2. **Sonar Ping** (from #13): Press A to send a sonar pulse. Objects on the current wall glow briefly. But the Entity hears it and moves toward you. A cooldown prevents spam.
3. **Escalating Horror** (from #19): Entity proximity drives heartbeat, vignette, darkness tendrils, screen static, entity eyes watching from shadows, and jump scares. The longer you take, the worse it gets.
4. **Crafting & Inventory** (from #18): 8-slot inventory, 4 crafting recipes (matches+lens=lantern, wire+rod=lockpick, tape+fuse=fixed fuse, note halves=full note).
5. **Narrative via Documents** (from #18): 10 discoverable documents telling the story of Subject 17 and Project LETHE.
6. **Multiple Endings**: Escape with evidence (good), escape without evidence (ambiguous), caught by entity (death).

### Controls
- D-Pad L/R: Turn/move cursor | U/D: Move cursor vertically
- A: Sonar Ping (reveals wall objects, alerts entity) / Interact (when cursor on object)
- B: Inventory toggle
- START: Craft mode (in inventory) / Pause (in game)
- SELECT: Hold/use selected item

### Rooms
1. CELL -- Starting room, matches on floor, journal page
2. CORRIDOR -- Hub connecting all rooms, keycard behind pipes
3. STORAGE -- Supplies: wire, metal rod, fuse, tape, journal page 2
4. LAB -- Fuse box, terminal, examination chair, locked desk
5. OFFICE -- Painting, filing cabinet, safe (code 7439), exit door
6. EXIT HALL -- Blast door with keypad, final escape

### Technical
- `mode(2)`, 160x120, 2-bit (4 grayscale)
- Surface-first rendering via `screen()`
- Single-file `main.lua`
- Demo mode after 5 seconds idle
- Full sound design: sonar pings, heartbeat, ambient drips/creaks, entity growls, jump scares
