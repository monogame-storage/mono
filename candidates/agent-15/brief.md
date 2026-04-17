# Agent 15: THE DARK ROOM - FRACTURED MEMORIES (Puzzle Edition)

## Lineage
- **Base**: Agent 07 (Multi-ending mystery adventure with 7 rooms, 3 endings, flags/inventory)
- **Absorbed**: Agent 03 (Interactive puzzle mechanics: combination lock, sliding tiles, wire connect, pattern match, sequence memory)

## Concept
A mystery adventure where you wake with no memories in a dark facility. Instead of simply examining objects and picking up items, each room contains a real interactive puzzle that must be solved to progress. The puzzles you solve (and how) determine which of the three endings you reach.

## Room / Puzzle Mapping
| Room | Puzzle | Reward |
|------|--------|--------|
| Dark Room | **Pattern Match** - Memorize and reproduce a light pattern on the wall | Flashlight + Key |
| Hallway | Navigation hub (no puzzle, connects rooms) | Access to other rooms |
| Laboratory | **Combination Lock** - Crack a 4-digit code using sum/parity hints from equipment | Evidence + Fuse |
| Office | **Wire Connect** - Match numbered wire pairs on a circuit board | ID Badge + File access |
| Basement | **Sliding Tiles** - Arrange 1-8 tiles to restore power grid | Power restored |
| Rooftop | **Sequence Memory** - Simon-style antenna frequency replay | Memo (broadcast freq) |
| Vault | **Combination Lock v2** - Final code from clues gathered across rooms | Triggers ending |

## Three Endings
1. **Escape** (solve Dark Room + Basement puzzles, use key at front door)
2. **Trapped** (trigger lockdown in Basement without solving the tiles)
3. **The Truth** (solve all 5 puzzles, access vault terminal to broadcast evidence)

## Technical
- `mode(2)`, 160x120, 2-bit palette (black/dark gray/light gray/white)
- Surface-first drawing via `screen()`
- Single-file `main.lua`
- Demo mode activates after 10s idle, shows puzzle gameplay
- Sound via `note()` and `noise()` with safe wrappers
- D-Pad navigation, A to confirm/interact, B to cancel/submit
