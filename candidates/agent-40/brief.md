# THE DARK ROOM: LETHE -- Agent 40 (Final Agent)

## Merge Sources
- Agent-29: Champion narrative (7 rooms, bitmask story, 3 endings, typewriter, crafting)
- Agent-33: Entity AI (patrol, noise, chase, heartbeat, eyes, jump scare)

## Features
- 7 rooms: Cell, Corridor, Storage, Lab, Office, Exit Hall, Garden
- Entity AI: patrol, noise attraction, chase, heartbeat, eyes, jump scare, death
- Musical heartbeat: lub-DUB with pitch variation based on entity proximity
- Sonar ping: A button when not interacting reveals objects, alerts entity
- Crafting: lantern (matches+lens), lockpick (wire+rod), fuse (tape+fuse), full note (note halves)
- 3 endings: Ignorance, Half-Remembered, Full Revelation (based on story bits discovered)
- Demo mode with 7-segment clock
- Typewriter narrative system
- Touch support basics (cursor follows touch)
- Bitmask story tracking (8 discoveries)

## Controls
- D-Pad: Move cursor / Turn at edges
- A: Interact / Sonar ping (when no hotspot)
- B: Inventory
- START: Pause / Craft mode in inventory
- SELECT: Equip item from inventory

## Technical
- mode(2), 2-bit (0-3), 160x120, surface-first, single-file
- Safe audio wrappers for note/noise/tone/wave
