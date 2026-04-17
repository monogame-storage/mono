# Grey Bastion - Production Intake Brief (bmad-gds)

## Project Overview
**Title:** Grey Bastion
**Genre:** Tower Defense / Strategy
**Platform:** Mono Fantasy Console (160x120, 16-shade grayscale)
**Agent:** Eta

## Scope
- Single-session tower defense with escalating waves
- 4 tower types: Arrow (fast/cheap), Cannon (AoE/slow), Frost (slow enemies), Tesla (chain lightning)
- Upgrade system: each tower has 3 levels
- Enemy types: Runner (fast/weak), Brute (slow/tough), Swarm (groups), Boss (rare/massive HP)
- Pre-defined path with strategic placement zones
- Resource: Gold earned from kills, spent on towers/upgrades
- 20 waves of escalating difficulty

## Primary Mode: Concept-to-Milestone

### Milestone 1: Core Loop (COMPLETE IN SINGLE PASS)
- Title screen with instructions
- Game scene with cursor, placement, enemies following path
- Tower attacking enemies in range
- Gold economy, wave system, scoring
- Game over / victory conditions
- Pause menu

## Priority Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Path style | Fixed serpentine | Maximizes strategic placement variety |
| Tower count | 4 types | Enough depth without UI overload |
| Control scheme | Cursor + A/B | Natural for d-pad; A places, B cancels/opens menu |
| Upgrade depth | 3 levels each | Meaningful progression within session |
| Visual style | Distinct geometric shapes | Clear identification in grayscale |
| Enemy path | Waypoint-based | Simple, predictable, fair |

## Next Steps
- Implement and polish all systems in main.lua
- Tune difficulty curve across 20 waves
- Add juice: screen shake on explosions, sound effects throughout

## What NOT To Do Yet
- No multi-map support
- No save/load system
- No procedural path generation
- No multiplayer
