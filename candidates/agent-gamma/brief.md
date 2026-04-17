# Game Production Coordination Brief

## Scope
- Game / build stage: concept -> vertical-slice
- Engine / platform context: Mono fantasy console (160x120, grayscale 16-color mode 4, Lua 5.4, 30fps)
- Team shape: solo AI agent
- Next public beat: contest tournament submission

## Primary mode
concept-to-milestone

## Game Concept: VOID STORM
A vertical scrolling shoot-em-up (shmup) featuring intense bullet-hell gameplay. The player pilots a fighter through waves of increasingly dangerous enemies, collecting power-ups to upgrade weapons and shields, culminating in multi-phase boss encounters every 5 waves. The grayscale palette is used to create depth through brightness layering: dark backgrounds, medium enemies, bright bullets and explosions.

## What matters most now
- Tight, responsive player controls with diagonal normalization
- Distinct enemy types with readable attack patterns (sine-wave fliers, chargers, turrets, spreaders)
- Progressive wave system that ramps difficulty smoothly
- Boss fights with multi-phase patterns and visible health bars
- Power-up system: weapon upgrades (spread, rapid, laser), shield, bomb
- Satisfying juice: screen shake, flash on hit, particle explosions, audio feedback
- Clean collision detection and fair hitboxes
- High score persistence across sessions

## Priority decisions
| Decision | Why now | Owner | Risk if delayed |
|----------|---------|-------|-----------------|
| Vertical scroll vs fixed screen | Defines level design approach | Agent Gamma | Architecture rework |
| Enemy pattern language | Must be extensible for 10+ waves | Agent Gamma | Monotonous gameplay |
| Power-up balance | Affects difficulty curve | Agent Gamma | Too easy/hard |
| Boss phase design | Centerpiece of experience | Agent Gamma | Underwhelming climax |
| Grayscale depth mapping | Visual clarity depends on it | Agent Gamma | Unreadable screen |

## Immediate next steps
1. Implement core player movement and shooting mechanics
2. Build wave spawning system with 5 enemy types
3. Add power-up drops and weapon upgrade system
4. Create boss encounters at wave 5 and 10
5. Layer particle effects, screen shake, and audio
6. Implement title screen, pause, game over, high score
7. Balance difficulty curve through playtesting

## What not to do yet
- Multiple playable ships / ship selection
- Story or narrative elements
- Leaderboard / online features
- Sprite-based art (use primitives only per engine constraints)
- Complex scrolling backgrounds (keep performant)
