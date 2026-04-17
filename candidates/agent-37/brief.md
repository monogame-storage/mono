# Agent 37 (Wave 4) -- LETHE: REPLAY VALUE

## Domain
Replay value systems layered onto the LETHE psychological horror base (agent-29).

## What changed
- **Ending tracker**: Persistent save data records which of the three endings the player has seen. Title screen shows completion marks. Unlocking all three endings reveals a secret fourth ending.
- **New Game+ mode**: After first completion, subsequent playthroughs feature a stalker entity (inspired by agent-25's entity system). The entity manifests as footsteps, flickering lights, and brief sightings. Heartbeat intensifies near it. Adds tension without changing puzzle structure.
- **Time attack mode**: Unlocked after first completion. A countdown timer (inspired by agent-23) ticks during gameplay. Displayed in HUD. Reaching the exit before time expires earns a rank (S/A/B/C). Pausing stops the timer.
- **Procedural item placement**: Seeded PRNG (xorshift32, from agent-25) shuffles pickup locations for items within their respective rooms each playthrough. The seed is derived from a run counter, so every run is different but deterministic.
- **Statistics screen**: Accessible from pause menu. Tracks: total play time, items found, story bits discovered, endings seen, runs completed, fastest time attack. Persisted in save data.

## Architecture
- `save_data` table holds all persistent state (endings seen, stats, NG+ flag, run count).
- `store()`/`fetch()` calls used for persistence (engine-provided key-value store).
- Procedural placement uses a shuffled slot system per room -- items rotate among predefined valid positions.
- The NG+ entity uses a simple patrol/alert AI with proximity-based audio cues.
- Time attack is a separate mode selection on the title screen, only visible after first clear.

## Controls (unchanged from base)
- D-Pad: Move cursor / Turn
- A: Interact
- B: Inventory
- START: Pause
- SELECT: Hold item from inventory
