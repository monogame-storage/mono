# Agent 31 - THE DARK ROOM: LETHE (Sonar Edition)

## Concept
Agent-29's psychological horror narrative game ("LETHE") enhanced with agent-27's sonar ping system. The darkness-first design means objects in rooms are invisible until revealed by sonar pings. Each ping emits an expanding ring that temporarily reveals hotspot objects (fade after ~90 frames). Pinging alerts a stalker entity that hunts you through the facility.

## Sonar Integration
- Press A (when not in dialogue/inventory/safe mode) to emit sonar ping
- Expanding visual ring reveals wall objects temporarily with fade
- Cooldown bar shown in HUD (40 frame cooldown)
- Pinging alerts entity; entity pursues player across rooms
- Objects are hidden in darkness until pinged (darkness-first)
- Entity presence shown via heartbeat and ambient sounds

## Preserved from Agent-29
- All 7 rooms, all hotspots, all items, all recipes
- Full narrative typewriter system, document reader
- All story bits, all 3 endings, safe puzzle
- Room transition system, inventory, crafting
- Demo mode touring rooms

## Entity System (from Agent-27 inspiration)
- Stalker entity patrols rooms, alerted by sonar pings
- Heartbeat intensifies when entity is near
- Entity can enter current room via doors
- Getting caught triggers scare flash and death/respawn

## Controls
- D-Pad: Move cursor / Turn
- A: Interact (on hotspot) / Sonar Ping (no hotspot hit)
- B: Inventory
- START: Pause / Craft mode
- SELECT: Hold item

## Technical
- mode(2), 160x120, 2-bit (4 shades 0-3)
- Single file, safe audio wrappers, demo mode with sounds
