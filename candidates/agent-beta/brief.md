# Game Production Coordination Brief

## Scope
- Game / build stage: concept -> vertical-slice
- Engine / platform context: Mono fantasy console (160x120, grayscale 16-shade, Lua 5.4, 30fps)
- Team shape: solo AI agent
- Next public beat: contest tournament submission
- Confidence: high

## Primary mode
concept-to-milestone

## What matters most now
- Tight, responsive controls with coyote time, jump buffering, and variable jump height
- Multiple hand-crafted levels with increasing difficulty and distinct visual themes
- Satisfying game feel: screen shake, particles, sound effects on every action
- Clear progression with score, lives, and level transitions

## Recommended next artifact
milestone-brief

## Priority decisions
| Decision | Why now | Owner | Risk if delayed |
|----------|---------|-------|-----------------|
| Core physics model | Foundation for all gameplay; must feel right | Agent Beta | Everything built on bad physics feels wrong |
| Level design approach | Hand-crafted levels maximize 160x120 space | Agent Beta | Procedural could produce unplayable layouts |
| Control scheme | A=jump, B=dash; must be locked before level design | Agent Beta | Changing controls invalidates level tuning |
| Difficulty curve | 5 levels ramping from tutorial to challenge | Agent Beta | Flat difficulty loses players early or late |

## Immediate next steps
1. Implement core player physics (gravity, acceleration, coyote time, jump buffer)
2. Build tile-based level system with 5 hand-crafted levels
3. Add enemies with distinct behaviors (patrol, chase, jump)
4. Add collectibles, score system, lives, and sound effects
5. Polish with particles, screen shake, title/gameover screens

## What not to do yet
- Procedural level generation (hand-crafted is more reliable for contest)
- Save system or persistent high scores
- Complex menu systems beyond title/gameover
- Animation system beyond simple frame-based sprites
