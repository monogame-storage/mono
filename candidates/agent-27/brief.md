# THE DARK ROOM: ECHOLOCATION
## Agent 27 (Wave 3) -- The Definitive Version

### Concept
You wake in pitch darkness. You cannot see. Your only tool: sonar -- a pulse that
reveals the world around you for brief moments. But every ping betrays your position
to the entity that stalks these halls. Navigate 6 rooms, find items, craft tools,
uncover the truth of Subject 17, and escape -- or be consumed by the dark.

### Mechanics Combined
- **Sonar Navigation** (Agent 13): Ping reveals walls/objects as expanding ring particles; alerts the stalker entity
- **Stalker Entity + Horror Escalation** (Agent 19): Heartbeat system, proximity-based tension, screen shake, scare flashes
- **Crafting System** (Agent 12/18): Find components, combine in inventory (matches+lens=lantern, wire+nail=lockpick, torn notes=code)
- **Typewriter Narrative** (Agent 11): Story text types character-by-character on first room entry and journal discovery
- **First-Person Room Views** (Agent 18): Detailed hotspot-based interaction with drawn scenes per wall direction
- **Multiple Endings**: Based on evidence collected and journals read

### Room Layout (6 rooms)
1. **The Cell** -- Starting room. Find matches, lens. Craft lantern to see door.
2. **The Corridor** -- Hub. Keycard behind pipe. Doors to Lab, Archives, Storage.
3. **The Archives** -- Bookshelves, blue key, journal pages. Entity patrols here.
4. **The Storage** -- Wire, nail, dead fuse. Craft lockpick and fuse repair.
5. **The Lab** -- Terminal, fuse box, examination chair. Uncover Subject 17 truth.
6. **The Exit** -- Keypad door. Enter code from assembled notes. Multiple endings.

### Controls
- D-Pad: Turn (L/R) to face walls, Move forward/back
- A: Interact / Sonar Ping / Advance text
- B: Open inventory / Craft (select two items)
- START: Start game
- SELECT: Pause

### Technical
- 160x120, mode(2), 2-bit (4 grayscale: 0=black, 1=dark, 2=light, 3=white)
- Single file, demo mode on idle, full sound design
- Surface-first rendering with cls/pix/rectf/line/text/circ
