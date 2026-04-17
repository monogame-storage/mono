# Agent 13: ECHOLOCATION

## Concept
A horror game where you navigate in total darkness using only sonar pings. An entity stalks you -- you can hear its footsteps, its breathing. Your heartbeat accelerates as it gets closer. Your sonar ping reveals walls and objects... but it also ALERTS the entity to your position. Every ping is a gamble: navigate or hide?

## Lineage
- **Base**: Agent 08 (Sound Navigator) -- sonar mechanics, minimal visuals, sound-first design
- **Absorbed**: Agent 04 (The Dark Room) -- stalker entity AI, jump scares, heartbeat system, horror atmosphere

## Mechanics
- **Sonar ping** (A button): sends expanding ring that reveals walls/objects via sound. But the entity HEARS it and moves toward the ping origin.
- **Heartbeat**: accelerates based on entity proximity. Your only warning.
- **Entity footsteps**: audible directional sound -- heavier when closer, faster when chasing.
- **Jump scare**: screen flash + noise burst when the entity catches you. Death.
- **Keys & doors**: find keys by sonar, unlock doors to progress through 3 rooms to the exit.
- **Stealth**: stop moving to reduce detection. The entity patrols but charges when it hears a ping or you step too close.

## Controls
- D-Pad: Move
- A: Sonar ping (alerts entity!)
- START: Begin / Restart
- SELECT: Pause

## Technical
- `mode(2)`, 2-bit palette (4 shades)
- Single-file `main.lua`
- Demo mode activates after 5 seconds idle on title
- All feedback through sound: `tone()`, `noise()`, `wave()`
