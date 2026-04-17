# Agent 32 (Wave 4) -- LETHE Sound Design Polish

## Base
Agent 29's THE DARK ROOM: LETHE -- first-person psychological horror with 7 rooms, inventory/crafting, typewriter narratives, and 3 endings.

## Reference
Agent 30's Sonic Abyss -- best-in-class sound design using 2 channels with musical sonar, object signatures, heartbeat system, silence-as-weapon, and 5-layer ambient soundscape.

## Changes (Sound Design Only)
All narrative, puzzles, rooms, hotspots, inventory, crafting, endings, and visual rendering are unchanged.

### 1. Musical Sonar Ping (minor chord with echo/decay)
- Replaced simple `snd_turn()` with a descending minor chord sweep (C5 -> Eb4 on sine, G4 -> C4 on triangle) when turning, giving spatial awareness a musical quality.

### 2. Unique Audio Signatures Per Object Type
- **Pickup items (keys, journal, evidence):** bright ascending sine arpeggio (hope).
- **Doors (locked):** buzzy square wave, descending pitch (rejection).
- **Doors (open):** warm triangle sweep upward (invitation).
- **Terminals/machines:** dual-channel harmonic sweep (technology).
- **Crafting:** triumphant ascending chord on both channels.
- **Solve/unlock:** full resolution chord (C4->C5 sine + E4->G4*2 triangle).

### 3. Musical Heartbeat (lub-DUB with pitch variation)
- Replaced flat heartbeat with a lub-DUB system using sine waves.
- Lub: higher pitch, short attack. DUB: lower pitch, longer decay.
- Pitch drops with increasing danger intensity (deeper = more dread).
- Tempo increases as story revelations accumulate (more knowledge = more anxiety).
- Phase system: lub -> dub -> rest, with variable intervals.

### 4. Silence as Weapon (ambient fades near danger)
- Added `silence_factor` (0.0 to 1.0) that modulates all ambient sounds.
- During heartbeat-active moments (story revelations), silence_factor drops, suppressing ambient layers.
- Creates eerie quiet during intense narrative moments, then ambient layers creep back in.

### 5. Five-Layer Ambient Soundscape
- **Layer 1 - Drips:** High sine plinks with random pitch (1400-2400 Hz), suppressed near danger.
- **Layer 2 - Creaks:** Low sawtooth wobble with random selection from 5 pitches, organic feel.
- **Layer 3 - Thuds:** Muffled triangle pulses (40-55 Hz), distant and structural.
- **Layer 4 - Wind:** Filtered noise bursts, long intervals.
- **Layer 5 - Drone:** Ever-present low triangle hum with sinusoidal pitch oscillation for unease.

### 6. Enhanced Existing Sounds
- Footsteps: alternating pitch with randomness for organic feel.
- Typewriter: randomized pitch for each tick.
- Wall interaction sounds use waveform selection (sine/triangle/square) for variety.
- All sounds respect the 2-channel constraint (CH0=ambience, CH1=events).
