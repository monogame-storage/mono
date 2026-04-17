# Agent 26 — THE DARK ROOM: WITNESS

## Wave 3 Merge
- **Agent 17**: First-person horror (entity on walls, heartbeat, ambient)
- **Agent 18**: First-person crafting + narrative (item combining, documents)
- **Agent 15**: Puzzles determine ending (multiple endings, puzzle mechanics)

## Vision
First-person horror adventure in an underground research facility. You are Subject 26, a test subject in Project LETHE — a memory erasure program. You wake in a cell with no memories. Explore sublevel 4, craft survival tools, read documents that reveal the conspiracy, and survive the Entity that stalks you through the walls.

Three endings determined by what you discover, solve, and survive:
1. **ESCAPE** — Find the key and leave. Free but ignorant, memories lost forever.
2. **CONSUMED** — The Entity catches you. You become part of the walls.
3. **THE TRUTH** — Gather all evidence, power the transmitter, broadcast proof. You remember everything.

## Mechanics
- **First-person Myst-style**: 4 walls per room, turn L/R, cursor interaction
- **Entity AI**: Stalks between rooms, appears as eyes on walls. Stare too long = scare. 5 encounters = death ending.
- **Crafting**: Combine matches+lens=lantern, wire+rod=lockpick, tape+fuse=fixed fuse, torn notes=code
- **Documents**: Journal pages, memos reveal the conspiracy, needed for truth ending
- **Horror atmosphere**: Heartbeat rate, candle flicker, screen shake, ambient drips/creaks
- **Puzzles**: Safe combination (code from clues), keypad (code from notes)

## Technical
- `mode(2)`, 160x120, 2-bit (4 shades: BLACK/DARK/LIGHT/WHITE)
- Surface-first rendering
- Single-file Lua
- Demo mode after 10 seconds idle
- Safe audio wrapping (pcall on note/noise)

## Rooms
1. **Cell** — Start room. Matches on floor, journal page on cot, door to corridor.
2. **Corridor** — Hub. Notice board, doors to lab/office, pipe with keycard.
3. **Office** — Desk with torn note, filing cabinet (lockpick), safe (combination), evidence file.
4. **Lab** — Terminal, fuse box, master key behind powered terminal.
5. **Roof Access** — Transmitter antenna. Broadcast evidence for truth ending.

## Controls
- D-Pad: Move cursor / Turn at edges
- A: Interact
- B: Inventory / Deselect item
- START: Pause
