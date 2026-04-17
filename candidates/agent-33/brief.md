# Agent 33 (Wave 4) -- LETHE: Entity AI

## Base
Agent 29's THE DARK ROOM: LETHE (first-person point-and-click psychological horror).

## What changed
Added a stalker entity that patrols rooms and hunts the player, transforming
the game from pure psychological horror into psychological + survival horror.

### Entity behavior
- Starts in room 3 (Storage) after a grace period of ~8 seconds.
- Patrols between rooms using doors; picks random patrol targets every few seconds.
- Biased toward the player's room (30% chance to enter).
- Attracted by player interactions (door use, item pickup, turning).
  Each action adds "noise" that draws the entity closer.
- Heartbeat system: rate scales inversely with distance when entity is in the
  same room. Beat interval ranges from 30 frames (far) down to 6 frames (close).
  Visual pulse indicator drawn in the HUD corner.
- Entity eyes visible in darkness: two glowing dots appear on the current
  first-person view when the entity is in the same room. They blink, shift,
  and become brighter as it gets closer.
- Jump scare on catch: full-screen white flash, camera shake, harsh noise burst.
  Transitions to a "CAUGHT" death screen with typewriter text and restart option.
- Entity is completely frozen during narrative text display (typewriter or
  document overlays). This is the grace period -- the player is safe while reading.
- Entity speed escalates slightly over time and when chasing.
- Distant footstep sounds when entity is in an adjacent room.
- Door creak message when entity enters the player's room.

### Audio additions
- `snd_entity_step()`: low thudding when entity moves nearby.
- `snd_entity_growl()`: guttural tone when entity is very close.
- `snd_jumpscare()`: layered noise burst for the catch moment.
- Heartbeat now driven by entity proximity, not just story revelations.

### Integration points for other agents
- If Agent 31 adds sonar pings, the entity's `noise` accumulator can hook into
  ping events for a large attraction spike.
- The `entity_noise(amount)` function is the public API for attracting the entity.

## Reference
Agent 27's entity AI system (patrol, chase, sonar-alert, heartbeat, eyes).
Adapted from top-down tile movement to first-person room-based movement.
