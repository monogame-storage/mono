# Castle Defense - bmad-gds Brief

## Concept
A defense game inspired by chess castling. The player positions rook-walls to protect the king from waves of enemy attackers. When defenses are overwhelmed on one side, the player can "castle" - swapping king and rook positions to retreat to the other side of the board.

## Chess Connection
- **Castling mechanic**: King swaps with rook to escape danger (the core defensive move)
- **Rook walls**: Rooks act as defensive walls, sliding in straight lines (rank/file movement)
- **King safety**: King must never be in check (if enemies reach king, game over)
- **Board layout**: Grid-based fortress with castle-like architecture

## Gameplay Loop
1. Place rook-walls on the grid to form fortress walls
2. Enemy waves approach from edges
3. Rooks block and damage enemies they touch
4. When one side is overwhelmed, trigger CASTLE to swap king to the other side
5. Earn points to place more rooks, survive as long as possible

## Controls
- D-pad: Move cursor
- A/btn0: Place rook / Select rook to move
- B/btn1: Castle (swap king to opposite side)
- START: Start game / Pause
- Touch: Tap to place, drag to move rooks

## Visual Style
1-bit black and white. Chess piece silhouettes. Rooks as crenellated wall segments. King with crown. Enemies as dark chess pieces (pawns, knights, bishops). Particle effects for impacts.

## Sound Design
- Placement: solid stone-drop tone
- Castle swap: dramatic swoosh
- Enemy hit: crunch
- Wave start: horn blast
- King in danger: rapid warning beeps

## States
- DEMO: Attract mode with 7-segment clock, auto-play demonstration
- PLAY: Active gameplay with waves
- PAUSE: Pause menu
- GAMEOVER: Final score display

## Scoring
- Points per enemy defeated
- Bonus for surviving waves
- Multiplier for efficient rook placement
