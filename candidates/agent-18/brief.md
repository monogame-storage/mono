# Agent 18 — THE DARK ROOM: Forgotten

First-person Myst-style adventure with crafting and narrative documents.

## Concept
You wake in an underground research facility with no memory. Explore rooms in first-person view, find components, craft tools from them, and use crafted items on wall objects to progress. The story of Project LETHE unfolds through journal pages and memos scattered across six rooms.

## Sources
- **Agent-09**: First-person wall rendering, cursor interaction, directional navigation, dither shading
- **Agent-05**: Crafting recipe system (combine two items to create a new one), grid inventory
- **Agent-01**: Narrative depth, journal pages, document-driven storytelling, multi-room puzzle chains

## Rooms (6)
1. **Cell** — Start here in darkness. Find matches and a lens.
2. **Corridor** — Central hub connecting all areas. Find keycard behind pipes.
3. **Storage** — Components: wire, metal rod, fuse. Craft a lockpick or crowbar.
4. **Lab** — Insert fuse to restore power. Use terminal for exit code. Find journal pages.
5. **Office** — Dr. Wren's office. Filing cabinet with evidence. Safe with master key.
6. **Exit Hall** — Blast door with keypad. Enter code to escape.

## Crafting Recipes
- Matches + Lens = Lantern (provides light)
- Wire + Metal Rod = Lockpick (opens cabinet)
- Tape + Fuse = Patched Fuse (restores lab power)
- Note Left + Note Right = Full Note (reveals safe code)

## Puzzle Chain
Wake -> find matches+lens -> craft lantern -> explore with light -> find keycard -> access lab/office -> craft patched fuse -> power lab terminal -> get exit code -> find evidence -> escape

## Technical
- `mode(2)`, 2-bit (4 shades), 160x120
- First-person 3D wall view with dithered shading
- Crosshair cursor for wall object interaction
- Demo mode after 10s idle on title
- Sound effects for all interactions
- Single-file Lua
