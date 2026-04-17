# Agent 19: IT APPROACHES

## Concept
Time-pressure escape room fused with survival horror. A malevolent entity stalks
you through three puzzle rooms. The 90-second countdown IS the entity approaching --
as time drains, darkness encroaches, the entity manifests visually, and tension
escalates through sound and screen effects. Solve all three puzzles before it
catches you.

## Lineage
- **Base**: agent-06 (time-pressure puzzle rooms, 90s countdown, escalating tension)
- **Absorbed**: agent-04 (entity AI, darkness/flashlight, scare system, ambient horror)

## Fusion
The countdown is no longer abstract -- it represents the entity drawing closer.
Visual darkness closes in proportional to elapsed time. The entity appears as
glowing eyes in the shadows, triggering jump scares at random intervals. Ambient
horror sounds (drips, creaks, heartbeat) layer over the ticking clock. Wrong
puzzle answers don't just cost time -- they attract the entity, causing immediate
scare events.

## Controls
- D-Pad: Puzzle input (direction-dependent per puzzle)
- A: Confirm / Submit
- B: Undo / Back
- START: Begin game / Next room
- SELECT: Pause

## Technical
- `mode(2)`, 160x120, 2-bit (4 grayscale), 30fps
- Single-file, demo mode, sound effects
- Three puzzle types: Pattern Lock, Wire Connect, Code Cipher
