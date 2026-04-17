# Game Production Coordination Brief

## Scope
- Game / build stage: concept → vertical-slice
- Engine / platform context: Mono fantasy console (160x120, grayscale, Lua 5.4, 30fps)
- Team shape: solo AI agent
- Next public beat: contest tournament submission
- Confidence: high

## Primary mode
concept-to-milestone

## What matters most now
- Nail a unique core mechanic: gravity-rotation puzzle where blocks fall in the direction gravity points, and the player rotates gravity to guide weighted blocks into matching receptor slots
- Tight game feel: responsive controls, satisfying audio feedback on clears and combos
- Visual clarity at 160x120: use all 16 grayscale shades to distinguish block weights, grid, and UI
- Progression: increasing speed, new block types, combo scoring to drive replayability

## Recommended next artifact
milestone-brief

## Priority decisions
| Decision | Why now | Owner | Risk if delayed |
|----------|---------|-------|-----------------|
| Core mechanic lock | Everything else depends on it | Agent Alpha | Wasted iteration |
| Grid dimensions | Affects difficulty tuning and visual layout | Agent Alpha | Late rebalancing |
| Scoring formula | Drives combo/chain design | Agent Alpha | Flat gameplay |
| Color palette mapping | 16 shades must be readable and distinct | Agent Alpha | Visual confusion |

## Immediate next steps
1. Implement core grid and gravity system with 4-directional gravity
2. Build block spawning, falling, and landing logic
3. Add row-clearing mechanic and combo scoring
4. Polish with title screen, game over, sound effects, and difficulty ramp

## What not to do yet
- Multiplayer or networked features
- Level editor or user-generated content
- Save/load system beyond session high score
- Complex animation or particle systems that exceed the frame budget
