# Production Brief: KNOCKOUT! - Mono Boxing Game

## Scope
A fast-paced arcade boxing game for the Mono fantasy console (160x120, 16-shade grayscale). Players fight through a 3-round boxing match against an AI opponent with escalating difficulty across a tournament bracket. Features fluid punch/dodge mechanics, stamina management, health bars, knockdowns, TKO/KO finishes, crowd atmosphere, and screen shake on power hits.

## Primary Mode: Concept-to-Milestone

### Milestone 1: Core Boxing (MVP)
- Two boxers on screen with idle/punch/block animations
- Movement (left/right/forward/back), jabs (A), power punches (B)
- Health bars, stamina bar, round timer
- Basic AI that punches and blocks
- Knockdown and 10-count system

### Milestone 2: Full Match Structure
- 3-round matches with scoring (10-point must system)
- Win by KO, TKO (3 knockdowns), or decision
- Between-round screen with stats
- Title screen, pause, game over flows

### Milestone 3: Polish & Tournament
- Tournament mode (4 opponents, increasing difficulty)
- Crowd sound effects (cheering on hits, roaring on knockdowns)
- Screen shake on power hits and knockdowns
- Combo system (jab-jab-hook, jab-cross-uppercut)
- Instant replay on KO finishes
- Multiple AI difficulty patterns per opponent

## Priority Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Sport | Boxing | Two characters, no scrolling, perfect for 160x120 |
| View | Side view | Classic fighting game perspective, clear visuals |
| Input | D-pad move, A=jab/hook, B=power/uppercut | Simple but deep with timing |
| AI | State machine with tells | Fair, learnable, escalating difficulty |
| Scoring | 10-point must + KO | Authentic boxing rules |
| Animation | Frame-based procedural drawing | No sprites needed, smooth at any frame |
| Audio | Note-based SFX + crowd noise | Atmospheric within engine limits |

## Next Steps
1. Implement boxer drawing and animation system
2. Build input handling and movement
3. Add punch collision and damage
4. Implement AI opponent behavior
5. Build match flow (rounds, scoring, KO)
6. Add tournament progression
7. Polish with sound, screen shake, replays

## What NOT To Do Yet
- No multiplayer/two-player mode (single-player focus first)
- No character customization or cosmetics
- No complex combo trees beyond 3-hit chains
- No persistent save/career mode
- No online features
