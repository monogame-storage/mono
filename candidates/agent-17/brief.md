# THE DARK ROOM: HAUNTED - Agent 17 Brief

## BMAD-GDS Production Coordination Brief

**Title:** THE DARK ROOM: HAUNTED
**Genre:** First-Person Horror Adventure
**Platform:** Mono Fantasy Console (160x120, 2-bit / 4 grayscale, 30fps)
**Agent:** 17 (hybrid of Agent 09 + Agent 04)
**Stage:** concept -> vertical-slice

### Concept
A first-person point-and-click horror adventure merging Myst-style wall exploration with survival horror. You wake in a dark room seen from your own eyes. Each wall can have objects, doors, clues -- and something watching you. Limited candle light creates claustrophobic visibility. A stalking entity can appear on any wall as glowing eyes in the darkness. Your heartbeat accelerates when danger is near. Examine objects, solve puzzles, survive, escape.

### Sources
- **Agent 09 (Base):** First-person wall rendering, cursor-based interaction, hotspot system, inventory, puzzle chain (nightstand -> key -> cabinet -> candle -> journal -> safe -> master key -> escape)
- **Agent 04 (Absorbed):** Entity AI, heartbeat proximity system, scare triggers (screen flash + shake + noise burst), ambient horror audio (drips, creaks, entity footsteps), death/game-over state, vignette darkness

### Core Mechanics
- **First-person view:** See one wall at a time. Left/right at edges rotate facing (N/E/S/W).
- **Cursor interaction:** D-pad moves cursor. A button examines/interacts with hotspots.
- **Inventory:** B toggles inventory. Select and use items on hotspots.
- **Limited visibility:** Rooms start pitch dark. Candle light brightens view but with flickering. Without light, only silhouettes visible.
- **The Entity:** A stalking presence that moves between rooms. Appears as glowing eyes on walls. Heartbeat sound intensifies as it gets closer. If it reaches your room and you face it, jump scare triggers.
- **Scare system:** Screen flash, camera shake, harsh noise burst on entity contact or close encounters.
- **Ambient horror:** Dripping water, random creaks, distant footsteps, breathing sounds.

### Room Layout (4 rooms)
1. **Bedroom** - Wake here. Bed, nightstand (key + matchbox), locked door, boarded window.
2. **Hallway** - Connects rooms. Painting with clue "1947", locked cabinet, door to kitchen.
3. **Study** - Desk with journal, bookshelf, safe with 3-digit combo, door back to hallway.
4. **Kitchen** - Counter, fridge with note, EXIT door (needs master key).

### Horror Layer
- Entity starts in room 3, patrols between rooms
- When entity is in your room, it can appear on the wall you face as glowing eyes
- Heartbeat rate increases with proximity (audio cue)
- Random scare events: eyes flicker, whisper sounds, screen shake
- If entity "catches" you (appears on your wall too many times), game over with jump scare
- Candle flickers more when entity is near

### Puzzle Flow
1. Open nightstand -> matchbox + small key
2. Hallway cabinet + small key -> candle
3. Matchbox + candle -> light (visibility upgrade)
4. Study journal -> safe hint ("the year we arrived, reversed")
5. Hallway painting -> "1947" -> code 749
6. Safe 749 -> master key
7. Kitchen back door + master key -> escape

### Demo Mode
After 10 seconds idle on title, auto-play demo: camera pans through rooms with light on, cursor drifts, entity eyes occasionally visible. Any button returns to title.

### Sound Design
- Heartbeat (rate tied to entity distance)
- Footstep/turn sounds on navigation
- Entity footsteps (distant, unsettling)
- Door creak on transitions
- Item pickup chime
- Ambient drips and creaks
- Scare noise burst (flash + shake)
- Puzzle solve fanfare

### Win/Lose Conditions
- **Win:** Escape through kitchen back door with master key
- **Lose:** Entity catches you (too many close encounters)

### Priority Decisions
| Decision | Why now | Owner | Risk if delayed |
|----------|---------|-------|-----------------|
| First-person + horror merge | Core identity | Agent 17 | Must feel both atmospheric and scary |
| Entity wall appearance system | Unique horror mechanic | Agent 17 | No tension without it |
| Heartbeat audio proximity | Primary fear cue | Agent 17 | Game feels flat |
| Scare trigger balance | Player experience | Agent 17 | Too annoying or too mild |

### Risk Assessment
- **Visual clarity at 160x120:** Strong silhouettes, dither patterns, glowing entity eyes stand out
- **Horror in 4 shades:** Darkness itself is the weapon; less is more
- **Entity too aggressive:** Tunable encounter rate, grace period after scares
- **Softlock:** All items accessible without entity-blocked paths
