# THE DARK ROOM: LETHE
## Agent 29 | Wave 3 | Story-First Psychological Horror

### Concept
A first-person mystery where every room reveals another layer of a terrible truth. You are Subject 17 -- a patient in an underground facility who has been memory-wiped 31 times. The horror is not a monster; it is what you discover about yourself.

### Architecture
- **Mode**: `mode(2)` -- 2-bit, 4 grayscale shades (0-3)
- **Resolution**: 160x120, 30fps
- **Controls**: D-Pad (turn/cursor), A (interact), B (inventory), START (pause)
- **Single-file**: All code in main.lua, no external files

### Story Structure
Seven rooms, each a chapter in the narrative. Documents, journals, and environmental clues reveal the story of Project LETHE -- a memory-erasure program.

### Key Features
- **Typewriter text** with per-character reveal and sound
- **3 distinct endings**: Ignorance (escape without reading), Partial Truth (some journals), Full Revelation (all evidence + code)
- **Crafting system** (matches+lens=lantern, wire+rod=lockpick, tape+fuse=repaired fuse, torn notes=full code)
- **Safe puzzle** with 4-digit code from torn notes
- **Demo mode** after 300 frames idle on title
- **Ambient sound**: drips, creaks, heartbeat near discovery
- **First-person room rendering** with perspective walls and interactive hotspots
- **Document reader** with word wrap and scrolling
- **Narrative weight**: Documents are the game -- every interaction tells part of the story

### Room Map
1. **The Cell** - Wake here. Matches, lens, Journal Day 1, wall scratches ("THEY ERASE YOU")
2. **The Corridor** - Hub. Pipes (keycard), notice board (LETHE memo), doors to all wings
3. **Storage** - Wire, rod, fuse, tape, Journal Day 15 (LETHE compound vials)
4. **The Lab** - Fuse box, terminal (exit code), examination chair, Journal Day 31
5. **The Office** - Painting (torn note), filing cabinet (Subject 17 file), safe (master key), desk (memos)
6. **Exit Hall** - Blast door with keypad, final choice
7. **The Garden** - Optional room behind safe: Dr. Wren's final recording

### Endings
1. **IGNORANCE IS MERCY** - Escape without reading journals. "Free. But you remember nothing."
2. **HALF-REMEMBERED** - Escape with some journals. "Fragments of truth. Enough to haunt."
3. **FULL REVELATION** - All journals + evidence + terminal. "You are Subject 17. You remember everything. They will answer for this."
