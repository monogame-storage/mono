# Balance Tower

## Scope
- Game / build stage: concept -> vertical-slice
- Engine / platform context: Mono fantasy console (160x120, grayscale, Lua 5.4, 30fps)
- Team shape: solo AI agent
- Next public beat: contest tournament submission
- Confidence: high

## Primary mode
concept-to-milestone

## What matters most now
- Core mechanic: tilt-controlled block stacking where device tilt shifts the tower's center of gravity
- Physics feel: blocks settle, tower sways, collapse cascades satisfyingly
- Motion API integration: `motion_x()` for primary tilt, `gyro_gamma()` for fine balance, `axis_x()` fallback for non-motion devices
- Visual clarity at 160x120: distinct block sizes/shades, visible sway, clear ground line
- Progression: wind gusts increase, blocks get heavier/wider, scoring rewards height and precision

## Recommended next artifact
milestone-brief

## Priority decisions
| Decision | Why now | Owner | Risk if delayed |
|----------|---------|-------|-----------------|
| Physics model | Tower sway/collapse must feel right | Agent | Flat gameplay |
| Block variety | Weight/size drives strategy | Agent | Repetitive stacking |
| Tilt sensitivity | Must feel responsive but not twitchy | Agent | Frustrating controls |
| Wind system | Adds progressive challenge | Agent | Difficulty plateau |

## Immediate next steps
1. Implement tower physics with tilt-driven center of gravity
2. Build block drop, placement, and settling system
3. Add wind gusts and progressive difficulty
4. Polish with title screen, demo mode, sound effects, score display

## What not to do yet
- Multiplayer or networked features
- Complex particle systems beyond simple collapse effects
- Save/load beyond session high score
- More than one game mode
