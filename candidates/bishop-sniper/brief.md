# BISHOP SNIPER - Game Brief

## Game Identity
- **Title:** BISHOP SNIPER
- **Genre:** Arcade / Shooter
- **Chess Piece:** Bishop
- **Core Mechanic:** Diagonal-only shooting on a chess grid

## Concept
You are a bishop on an 8x8 chessboard. You can ONLY fire shots along the four diagonals from your position. Enemy pieces march inward from the edges of the board. Position yourself strategically and time your diagonal shots to eliminate them before they reach you. Missed shots ricochet off the board edge for a second chance. Chain kills along the same diagonal for combo multipliers. Stark 1-bit black and white creates dramatic sniper contrast.

## Gameplay Loop
1. Bishop sits on the chessboard; enemies spawn at board edges
2. Player moves bishop to any valid square (diagonals only, like real chess)
3. Player aims and fires along one of four diagonal lines
4. Shot travels diagonally until it hits an enemy or reaches the board edge
5. Edge hits cause a single ricochet (shot bounces and continues on reflected diagonal)
6. Killing multiple enemies on the same diagonal shot triggers combo multiplier
7. Enemies that reach the bishop cost a life; 3 lives total
8. Waves escalate with faster, tougher enemies (pawns, knights, rooks)
9. Game over when all lives lost

## Visual Design (1-bit)
- 8x8 chessboard with alternating black/white squares filling the play area
- Bishop rendered as a stylized pointed piece silhouette (white on black square, black on white square)
- Enemies: distinct silhouettes for each piece type (pawn=round, knight=L-shape, rook=tower)
- Shot trail: dashed diagonal line with a bright head pixel
- Ricochet: flash effect at bounce point
- Kill: explosion burst of pixels radiating outward
- Combo text: "x2!" "x3!" floats up from kill location
- HUD bar at top: score (left), lives (center icons), wave number (right)
- Crosshair/aim indicator: blinking dots along active diagonal

## Controls
- D-pad: move bishop diagonally (up+left, up+right, down+left, down+right)
- A button: fire shot in aimed direction
- B button: cycle aim direction (4 diagonals)
- START: begin game / pause
- Touch: tap a diagonal direction from bishop to aim+fire

## Difficulty Progression
| Wave | Enemies | Speed | Types | Special |
|------|---------|-------|-------|---------|
| 1-2  | 3-4     | Slow  | Pawns only | Tutorial feel |
| 3-4  | 5-6     | Medium | Pawns + Knights | Knights move in L-patterns |
| 5-6  | 7-8     | Fast  | All types | Rooks are tanky (2 hits) |
| 7+   | 8+      | Very fast | All + faster spawns | Relentless pressure |

## Sound Design
- Shot fire: sharp click/snap tone
- Hit/kill: satisfying crunch noise burst
- Ricochet: metallic ping note
- Combo: ascending tone sequence (higher per combo level)
- Enemy approach warning: low pulse when enemy is 2 squares away
- Life lost: descending buzz
- Wave complete: triumphant chord
- Game over: slow descending tones

## Demo Mode (Attract)
- AI bishop auto-moves and fires at approaching enemies
- 7-segment HH:MM clock displayed in top-right corner
- Game runs infinitely with no game-over; enemies respawn endlessly
- Any button press or touch exits to title screen

## Scoring
- Base kill: 10 points per enemy
- Combo multiplier: x2 for 2 kills on same shot, x3 for 3, etc.
- Ricochet kill bonus: +25 extra per kill after a bounce
- Wave clear bonus: 50 x wave_number
- No-damage wave bonus: 100 extra if no lives lost in a wave
- Speed bonus: faster kills within a wave earn more
