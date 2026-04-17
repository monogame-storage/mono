## Agent 36 (Wave 4) -- LETHE: PUZZLES

**Domain:** Interactive puzzles integrated into key rooms of the LETHE narrative.

**Base:** Agent 29 (story-first psychological horror, first-person room explorer)
**Reference:** Agent 24 (best-in-class puzzle mechanics: combination, pattern memory, wire matching, sequence)

### Changes from base (Agent 29)

Three optional interactive puzzles have been woven into the existing room structure. Each puzzle is activated by interacting with specific objects, feels like a natural part of the environment, and rewards the player with story evidence or items they could otherwise obtain through exploration alone. Skipping puzzles is always possible -- the game remains completable without solving any of them -- but solving them yields earlier access to key information and bonus narrative fragments that deepen the horror.

#### 1. Safe Combination Puzzle (Office, Room 5)
- **Trigger:** Interacting with the safe when you have light.
- **Mechanic:** 4-digit tumbler interface (D-Pad to select digit/change value, A to try, B to exit). Inspired by Agent 24's combination vault but adapted to feel like cracking an old office safe.
- **Narrative integration:** The code (7439) is scattered across torn notes and the lab terminal. If the player already found the full code through exploration, the safe auto-opens. If not, they can deduce it from partial clues (note_l = "74..", note_r = "..39") or brute-force it.
- **Reward:** Master key (unlocks the secret Garden room with Wren's final recording). A story snippet about Wren's hidden safe also plays on solve.

#### 2. Pattern Memory Puzzle (Lab Terminal, Room 4)
- **Trigger:** Using the lab terminal after power is restored.
- **Mechanic:** 4x4 grid is shown briefly; player must reproduce it from memory. Based on Agent 24's pattern chamber but re-themed as a LETHE memory authentication test -- the system requires you to prove your memory still works before granting access.
- **Narrative integration:** The terminal is literally a memory-testing device in a facility that erases memories. Solving it feels like an act of defiance. Failure triggers a "MEMORY INSUFFICIENT" message with a brief screen glitch.
- **Reward:** Reveals the full terminal readout (Subject 17 file, exit code, Wren's death) as a single story beat. Also sets the terminal_used flag, granting the STORY_TERMINAL bit.

#### 3. Wire Connection Puzzle (Fuse Box, Room 4)
- **Trigger:** Using the fixed fuse on the fuse box in the lab.
- **Mechanic:** 4x4 grid with 4 numbered wire pairs. Player navigates with D-Pad, selects endpoints with A to connect matching numbers. Drawn from Agent 24's wire lab but presented as reconnecting severed power lines inside the fuse panel.
- **Narrative integration:** The facility's power was deliberately cut -- someone (or something) didn't want the terminal accessed. Reconnecting wires is physical, tactile, and grounded in the story.
- **Reward:** Restores lab power (lab_powered flag), enabling the terminal. On solve, a brief narrative flash: the fluorescent lights stutter on and you see the room clearly for the first time.

### Design principles
- **Optional but rewarding:** Every puzzle can be bypassed. The safe code can be found on documents. Power can theoretically be restored without the wire puzzle. But puzzles give faster access and richer narrative.
- **Narrative-first:** Each puzzle is introduced with a short typewriter narrative explaining what you're doing and why. Failure messages are in-character ("MEMORY INSUFFICIENT", "WRONG COMBINATION", "SHORT CIRCUIT").
- **Consistent controls:** All puzzles use D-Pad + A/B, matching the base game's control scheme. B always exits.
- **Horror atmosphere maintained:** Puzzles use the same 2-bit palette, ambient sounds continue during puzzles, and failure triggers screen flicker/heartbeat effects.
