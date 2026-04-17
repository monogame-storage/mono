# Shake Fighter - Production Brief

## Scope
- Game / build stage: concept -> vertical-slice
- Engine / platform context: Mono fantasy console (160x120, grayscale, Lua 5.4, 30fps)
- Team shape: solo AI agent
- Next public beat: contest tournament submission
- Confidence: high

## Primary mode
concept-to-milestone

## What matters most now
- Motion-controlled fighting: punch by thrusting phone forward, block by holding still, dodge by tilting
- Satisfying punch detection with three attack types: jab, power punch, uppercut
- Responsive AI opponent that reads player patterns and fights back convincingly
- Stamina system that prevents button/shake mashing and rewards tactical play
- Best-of-3 round structure with KO and TKO conditions
- Clean fallback to d-pad/buttons for non-motion devices

## Core mechanic
- PUNCH: motion_z spike > 0.3 = jab, > 0.6 = power punch
- UPPERCUT: motion_y spike > 0.5 (upward motion)
- BLOCK: all motion axes < 0.15 (phone held still)
- DODGE: motion_x tilt left/right > 0.4
- Fallback: A = punch, B = block, d-pad left/right = dodge

## Recommended next artifact
milestone-brief

## Priority decisions
| Decision | Why now | Owner | Risk if delayed |
|----------|---------|-------|-----------------|
| Motion threshold tuning | Core feel depends on it | Agent | Unresponsive or too sensitive controls |
| AI difficulty curve | Must feel fair but challenging | Agent | Frustrating or boring gameplay |
| Stamina cost balance | Prevents spam, rewards timing | Agent | Degenerate strategies |
| Visual readability | Fighters must read clearly at 160x120 | Agent | Confused players |

## Immediate next steps
1. Implement motion detection with threshold-based punch/block/dodge classification
2. Build fighter state machines (idle, punch, block, dodge, hit, knockdown)
3. Create AI opponent with pattern recognition and varied attack selection
4. Add round system, health bars, stamina, KO/TKO logic
5. Polish with title screen, attract mode, sound effects, screen shake

## What not to do yet
- Character selection or multiple fighters
- Online multiplayer
- Complex combo system beyond basic attack types
- Persistent save data beyond session
