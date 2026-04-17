# GYRO RACER

Steer a racing car by tilting your phone left and right. Lean forward to accelerate, back to brake. Race through a winding pseudo-3D track in time trial mode.

## Controls
- **Tilt left/right**: Steer (via `motion_x()`, fallback: d-pad left/right / `axis_x()`)
- **Tilt forward/back**: Accelerate / brake (via `motion_y()`, fallback: up/down buttons)

## Gameplay
- Pseudo-3D road with curves, rendered as perspective-projected segments
- Winding track with alternating curves creating a challenging course
- Going off-road slows you down significantly
- Speed-sensitive steering: faster speeds require more careful inputs
- Time trial: complete laps as fast as possible
- HUD shows speed bar, lap time, best time, and lap counter

## Modes
- **Demo mode**: AI drives the car automatically when no input is detected
- **Race mode**: Player controls via tilt or d-pad

## Visual Style
- 1-bit (black and white) with `mode(1)`
- Pseudo-3D road with dithered grass, striped road markings
- Player car drawn at bottom center with tilt animation
- Sky with horizon line and simple scenery

## Sound
- Engine drone pitch scales with speed (`tone()`)
- Tire screech on hard turns (`noise()`)
- Lap completion chime (`note()`)
