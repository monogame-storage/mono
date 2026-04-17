# ABYSSAL PING
## Agent 25 (Wave 3) -- Sonar + Procedural + Horror Merge

### Sources
- Agent 13: Sonar-based navigation, stalker entity that hunts by sound
- Agent 14: Seed-based procedural room generation, xorshift32 PRNG
- Agent 19: Escalating horror (entity eyes, darkness tendrils, static, heartbeat, jump scares)

### Concept
You are blind in an infinite procedural abyss. Your only tool is sonar -- but every ping alerts the entity that hunts you. Each room is procedurally generated from a shared seed. Horror escalates the deeper you go: more walls, faster entity, darkness tendrils closing in, eyes watching from the void. Survive as many rooms as possible. Permadeath. Share seeds.

### Mechanics
- **Sonar navigation**: Press A to emit a sonar ping that reveals walls, keys, doors, exits as sound echoes. Each object type has a distinct audio signature.
- **Entity AI**: A stalker patrols each room. It hears your pings and moves toward the sound source. Closer = faster heartbeat, growls, heavy footsteps. If it catches you: jump scare, permadeath.
- **Procedural generation**: xorshift32 PRNG seeded per-room. Wall complexity, danger count, and entity speed increase with depth. Every seed produces a unique infinite sequence of rooms.
- **Escalating horror**: Deeper rooms trigger more entity eyes at screen edges, darkness tendrils creeping inward, screen static, and increasingly frantic heartbeat. Vignette tightens.
- **Scoring**: High score = rooms escaped. Seed displayed for competitive replay.
- **Key/Door/Exit loop**: Find key, unlock door, reach exit. Repeat forever -- if you survive.

### Controls
- D-Pad: Move
- A: Sonar ping (cooldown; alerts entity)
- Start: Begin game
- Select: Pause (shows seed)

### Technical
- `mode(2)`, 160x120, 2-bit (4 grayscale)
- Surface-first rendering
- Single file: `main.lua`
- Demo mode after 5s idle on title
- 4 sound channels: sonar, object, ambient, footstep
