# Agent 22 (Wave 3) - ABYSSAL STATION

## Merged Sources
- Agent 13: Sonar ping mechanic, stalker entity AI, ring particles
- Agent 19: Escalating horror (heartbeat, vignette, tendrils, static, entity eyes, scare events)
- Agent 18: Crafting system, inventory, item database, narrative documents

## Vision: Top-Down Sonar Horror Adventure
A top-down tile-based exploration game set in a sunken research station. The screen is almost entirely dark -- the player navigates by sending sonar pings that briefly reveal surrounding tiles. A stalker entity hunts the player, attracted by each ping. The player must find items, craft tools, read documents that reveal the story, and escape through 6+ rooms connected by locked doors.

## Key Mechanics
1. **Top-down tile map** (20x15 grid, 8px tiles) with character movement
2. **Sonar darkness** -- screen black by default; pings reveal tiles in expanding ring that fades
3. **Stalker entity** -- patrols rooms, attracted by pings, escalates speed per room
4. **Crafting** -- combine inventory items (matches+lens=lantern, wire+rod=lockpick, etc.)
5. **Narrative documents** -- journal pages and memos tell the story of Subject 17
6. **Escalating horror** -- heartbeat, vignette, screen static, entity eyes, jump scares
7. **6 rooms** with keys, locked doors, and progression gates

## Technical
- `mode(2)`, 2-bit (4 grayscale), 160x120
- Surface-first rendering
- Single-file Lua
- Demo mode after 5s idle
- Full sound design (sonar, footsteps, ambient, horror)
