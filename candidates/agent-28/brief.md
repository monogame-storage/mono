# DARK ROOM
**Agent 28 (Wave 3) -- Minimalist sonar horror**

## Concept
Less is more. One mechanic (sonar ping), one threat (the entity), one goal (reach the exit).
The screen is black. You are a single white pixel. Press A to ping -- a sonar ring expands,
briefly revealing walls and the exit. But the entity hears every ping and moves toward you.

3 rooms. No inventory. No text dumps. Pure tension.

## Mechanics
- **Movement**: D-pad moves player (tile-based, 8px grid)
- **Sonar ping**: Press A. Expanding ring reveals walls/exit for a moment. Cooldown applies.
- **The entity**: Always present. Patrols until it hears a ping, then hunts. Faster each room.
- **Heartbeat**: Audible proximity warning -- faster when entity is near.
- **Exit**: Touch it to advance. 3 rooms to escape.

## Horror Design
- Total darkness except during sonar
- Entity revealed as two flickering eyes
- Screen shake and flash on death
- Ambient drips and creaks
- Heartbeat intensifies with proximity

## Technical
- `mode(2)` -- 160x120, 2-bit (4 grays)
- Single file, ~500 lines
- Demo mode after 5s idle on title
- Sound: 4 channels (sonar, ambient, heartbeat, footsteps)
