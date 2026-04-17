# Game Production Coordination Brief

## Scope
- Game / build stage: concept → vertical-slice
- Engine / platform context: Mono fantasy console (160x120, 1-bit, Lua 5.4, 30fps)
- Team shape: solo AI agent
- Next public beat: contest tournament submission
- Confidence: high

## Primary mode
concept-to-milestone

## What matters most now
- Core mechanic: pawn races upward toward the 8th rank while dodging enemy pieces scrolling downward
- Promotion system: reaching rank 8 promotes pawn (knight→bishop→rook→queen), each granting new abilities (wider dodge, shield, slow-time, magnet score)
- En passant mechanic: diagonal dodge move with brief invincibility, triggered by swipe or button
- Escalating difficulty: scroll speed increases, enemy density ramps, piece types get more dangerous
- 1-bit visual clarity: chess piece silhouettes must be instantly readable at 160x120 in pure black/white

## Recommended next artifact
milestone-brief

## Priority decisions
| Decision | Why now | Owner | Risk if delayed |
|----------|---------|-------|-----------------|
| Pawn movement feel | Core loop depends on responsive lateral dodging | Agent | Sluggish controls kill fun |
| Enemy spawn patterns | Defines difficulty curve and fairness | Agent | Unfair deaths frustrate players |
| Promotion pacing | Too fast = trivial, too slow = boring | Agent | Flat progression |
| En passant timing window | Must feel like a skill move, not random | Agent | Mechanic feels pointless |

## Immediate next steps
1. Implement pawn lane movement with smooth left/right dodging on a chess-board scrolling field
2. Build enemy piece spawner with increasing variety (pawns→knights→bishops→rooks→queen)
3. Add promotion system at rank-8 boundary with visual feedback and ability unlock
4. Polish with title screen, demo mode, 7-segment clock, sound effects, game over, and touch support

## What not to do yet
- Multiplayer or networked features
- Save/load beyond session high score
- Complex particle systems that exceed frame budget
- More than 4 promotion tiers (keep scope tight)
