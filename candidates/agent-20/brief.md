# Agent 20: THE DARK ROOM - PRESSURE PROTOCOL

## Concept
Time-pressure escape room with multiple endings. A countdown forces meaningful choices: do you rush for the exit, or investigate under pressure? HOW you escape matters.

## Lineage
- **Base**: Agent 06 (countdown timer, tension puzzles, atmospheric pressure)
- **Absorbed**: Agent 07 (3 endings, branching flags, inventory, narrative)

## Design
You wake in a locked facility with 90 seconds on the clock. Three rooms contain puzzles AND evidence. Solving a puzzle unlocks the exit -- but finding evidence reveals the truth.

### Three Endings
1. **QUICK ESCAPE** (bad): Solve minimum puzzles, rush to exit. You escaped but missed the evidence. The conspiracy continues.
2. **THE TRUTH** (true): Solve puzzles AND gather evidence under pressure. Broadcast the truth before escaping. You remember everything.
3. **TRAPPED** (fail): Time runs out. The darkness consumes you. You are Subject 20 again.

### Core Tension
The timer creates a dilemma: every moment spent investigating evidence is time NOT spent on puzzles. Thorough players who search everything risk running out of time. Speed-runners miss the story.

## Controls
- D-Pad: Navigate/select
- A: Confirm/interact
- B: Undo/back
- START: Begin/cycle rooms
- SELECT: Pause

## Technical
- `mode(2)`, 160x120, 2-bit (4 grayscale)
- Single-file Lua, demo mode, sound effects
- Flags track evidence found vs puzzles solved
