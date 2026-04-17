# THE DARK ROOM - Production Intake Brief (bmad-gds)

## Project Overview
**Title:** The Dark Room
**Genre:** Horror / Survival
**Platform:** Mono Fantasy Console (160x120, 2-bit 4-shade grayscale)
**Agent:** 04

## Concept
First-person horror where you wake in a pitch-black room with only a dying flashlight. Darkness is the core mechanic: limited cone of visibility, ambient sounds from unseen threats, flickering light creating tension. Navigate through rooms, find keys and batteries, avoid the entity that stalks you. The 2-bit palette (black, dark grey, light grey, white) creates oppressive, claustrophobic atmosphere. Jump scares via screen flash and camera shake when the entity gets close.

## Scope
- Flashlight cone with flickering, battery drain
- 5 interconnected rooms with locked doors
- Inventory: keys, batteries, notes
- Stalking entity with footstep audio cues
- Jump scare system (screen flash + cam_shake + noise burst)
- Ambient sound design: drips, creaks, breathing
- Demo/attract mode with AI wandering

## Primary Mode: Concept-to-Milestone

### Milestone 1: Core Loop (COMPLETE IN SINGLE PASS)
- Title screen with flickering text
- Top-down exploration with flashlight cone
- Room transitions with locked doors
- Battery drain and pickup system
- Entity AI that follows player through rooms
- Footstep sounds that intensify as entity nears
- Jump scare triggers on entity contact
- Game over screen
- Pause menu (SELECT)
- Demo mode on title idle

## Priority Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Perspective | Top-down | Simplest to render flashlight cone |
| Light mechanic | Cone + flicker | Creates tension with limited vision |
| Enemy count | 1 stalker | Single threat maximizes dread |
| Room count | 5 rooms | Enough for exploration without scope creep |
| Controls | D-pad move, A interact, B flashlight | Simple, intuitive |
| Scare method | Flash + shake + noise | Multi-sensory impact |
| Palette use | 0=darkness, 1=shadow, 2=dim, 3=lit | Darkness dominates |

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Not scary enough | Layer audio cues, randomize entity behavior |
| Too dark to play | Flashlight cone always visible, UI elements bright |
| Entity too hard/easy | Tunable speed, sight range, patrol patterns |
| Battery too punishing | Generous battery pickups, light never fully dies |

## What NOT To Do Yet
- No save/load system
- No multiple enemy types
- No procedural room generation
- No cutscenes
