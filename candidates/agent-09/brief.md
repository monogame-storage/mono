# THE DARK ROOM - Agent 09 Brief

## BMAD-GDS Production Coordination Brief

**Title:** THE DARK ROOM
**Genre:** First-Person Mystery Adventure
**Platform:** Mono Fantasy Console (160x120, 2-bit / 4 grayscale, 30fps)
**Agent:** 09
**Stage:** concept -> vertical-slice

### Concept
A first-person point-and-click adventure in the style of Myst meets retro. You wake up in a dark room seen from your own eyes. Turn left/right to face different walls. Each wall can have objects, doors, and clues. Examine objects, collect items, solve puzzles, escape.

### Core Mechanics
- **First-person view:** You see one wall at a time. Left/right arrows rotate your facing direction (N/E/S/W).
- **Cursor interaction:** D-pad moves a cursor over the current wall view. A button examines/interacts with hotspots.
- **Inventory:** B button toggles inventory bar. Select items and use them on hotspots.
- **Room transitions:** Doors on walls lead to other rooms. Walk through by interacting with an open/unlocked door.
- **Lighting:** Rooms start very dark (shade 0-1). Finding light sources brightens the view.
- **Puzzles:** Key-lock, combination safe, hidden switches, item combinations.

### Room Layout (4 rooms, 4 walls each = 16 viewable faces)
1. **Bedroom** - Wake here. Bed, nightstand with drawer (key inside), locked door (north wall), window (boarded).
2. **Hallway** - Connects bedroom to study and kitchen. Painting with clue, coat hook, locked cabinet.
3. **Study** - Desk with journal, bookshelf with false book (lever), safe with 3-digit combination.
4. **Kitchen** - Counter, fridge with note, back door (final exit, needs master key from safe).

### Inventory Items
- Matchbox (from nightstand) -> lights candle
- Small key (nightstand drawer) -> opens hallway cabinet
- Candle (hallway cabinet) -> brightens rooms when lit
- Journal page (study desk) -> safe combination hint: "the year we arrived backwards"
- Master key (inside safe) -> opens kitchen back door

### Puzzle Flow
1. Open nightstand drawer -> get matchbox + small key
2. Go to hallway, use small key on cabinet -> get candle
3. Use matchbox on candle -> rooms brighten (visibility upgrade)
4. Go to study, read journal -> learn safe hint
5. Check painting in hallway for year "1947" -> code is 749(1 reversed = 7491, use last 3 = 491... but safe is 3 digits so "749")
6. Open safe with code 749 -> get master key
7. Go to kitchen, use master key on back door -> escape / win

### Win Condition
Escape through the kitchen back door.

### Demo Mode
After 10 seconds idle on title, auto-play demo: camera pans through rooms, cursor moves to objects, simulates exploration. Any button press returns to title.

### Sound Design
- Footstep/turn sounds on navigation
- Door creak on room transitions
- Item pickup chime
- Ambient low drone for tension
- Puzzle solve fanfare
- Atmospheric drip sounds

### Priority Decisions
| Decision | Why now | Owner | Risk if delayed |
|----------|---------|-------|-----------------|
| First-person rendering approach | Core visual identity | Agent 09 | Everything depends on it |
| Wall hotspot system | Interaction model | Agent 09 | No gameplay without it |
| Room/wall data structure | Content pipeline | Agent 09 | Late restructuring |
| Puzzle chain design | Progression logic | Agent 09 | Dead ends or softlocks |

### Risk Assessment
- **Visual clarity at 160x120 with only 4 shades:** Mitigate with strong silhouettes and dithering patterns.
- **Complexity in single file:** Keep data tables compact, reuse drawing routines.
- **Softlock potential:** Ensure all items are accessible without prerequisites that could be missed.

### What Not To Do Yet
- Multiple endings or branching narrative
- Complex animation systems
- Save/load beyond session state
