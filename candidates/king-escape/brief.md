# KING ESCAPE

## Concept
You ARE the king. Move one square at a time across the board while enemy chess pieces hunt you down with their real movement patterns. Survive wave after wave of escalating threats.

## Genre
Action / Survival

## Chess Connection
- Player is the King piece: moves exactly one square in any direction
- Enemy pieces use authentic chess movement: knights jump L-shapes, bishops slide diagonals, rooks charge straight lines, queens combine both
- Capturing: move onto an enemy piece when it is NOT attacking your square to eliminate it
- Waves grow in count and piece variety, mirroring chess's escalating tension

## Controls
- D-Pad / Arrow keys: move king one square (turn-based movement)
- Touch: swipe in a direction to move
- START: begin game / restart
- SELECT: pause

## Mechanics
- 10x8 chess board (fits 160x120 at 14px cells with HUD)
- Turn-based: king moves, then all enemies move
- Enemy AI: each piece type calculates valid chess moves and picks the one closest to the king
- Safe captures: if an enemy is on a square it does NOT attack, moving onto it captures it (+score)
- Danger squares flash to warn the player
- Waves: Wave 1 = 2 pawns. Each wave adds more/harder pieces (knights, bishops, rooks, queen)
- Power-ups appear on random empty squares: shield (survive one hit), freeze (enemies skip a turn)
- Score: +10 per wave survived, +25 per piece captured, bonus for speed

## Visual Style
- 1-bit black and white
- Clean chess board with alternating pixel patterns
- Recognizable piece silhouettes drawn with primitives (no sprites)
- Danger squares indicated by dithered pattern
- Screen flash and shake on hit

## Sound Design
- Move: short click note
- Capture: satisfying ascending tone
- Hit/death: noise burst + descending tone
- Wave clear: triumphant chord
- Danger warning: subtle tick

## Demo Mode
- AI king wanders avoiding danger squares
- 7-segment clock displayed in corner
- Runs until START pressed

## Target Feel
Claustrophobic chess tension. Every move matters. The board feels alive with threat lines.
