# Agent 34 - LETHE Visual Polish (Wave 4)

## Domain: VISUALS

## Base: agent-29/main.lua

## Changes

### Dithering patterns for depth (room-specific)
- Cell: diagonal hatch dither (claustrophobic, scratchy)
- Corridor: horizontal scanline dither (institutional fluorescent)
- Storage: noise/stipple dither (cluttered, chaotic)
- Lab: ordered Bayer 4x4 dither (clinical precision)
- Office: crosshatch dither (bureaucratic)
- Exit Hall: vertical stripe dither (imposing, gate-like)
- Garden: organic wave dither (natural, flowing)

### Particle effects
- Dust motes: 12 persistent particles drifting slowly, fading in/out
- Flickering lights: randomized brightness pulses on lit rooms
- Drip particles: visible water drops in corridor/storage
- Heartbeat screen pulse: subtle brightness flash on heartbeat events
- Garden fireflies: slow-moving bright dots in garden room

### Screen transitions
- Iris-close wipe centered on player cursor (closing circle to black)
- Iris-open on arrival in new room
- Fade-to-white for ending transition

### Typewriter cursor blink
- Proper block cursor with 3-phase blink (solid, half, off)
- Cursor leaves brief afterimage trail
- Slight screen shake on dramatic text reveals

### Vignette darkening
- Circular falloff darkening at all screen edges
- Stronger vignette when no light (trapped feeling)
- Lighter vignette with lantern (relief)
- Vignette pulses subtly with heartbeat

### Room-specific visual character
- Cell: tight vignette, scratch-pattern walls, oppressive dark
- Corridor: emergency light pools (red-tinted zones), tile pattern floor
- Storage: dense shelf shadows, cluttered floor noise pixels
- Lab: clean grid lines on walls, sterile even lighting, electrode sparks
- Office: paper texture on desk, portrait shadow flicker
- Exit Hall: dramatic spotlight on blast door, rubble scatter pixels
- Garden: moonlight beam, organic vine patterns on walls, star twinkle

### Preserved
- ALL narrative text, story bits, puzzle logic, items, recipes, hotspots
- ALL sound effects and ambient audio
- ALL input handling and game states
- ALL room connectivity and progression
