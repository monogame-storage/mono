# KNIGHT HOP - bmad-gds Brief

## Game Identity
- **Title:** KNIGHT HOP
- **Genre:** Puzzle / Arcade
- **Chess Piece:** Knight
- **Core Mechanic:** L-shaped movement (2+1 squares)

## Concept
The player controls a knight on a chessboard and must visit every square exactly once (Knight's Tour). Each level increases board size from 5x5 up to 8x8. A countdown timer creates urgency. Bonus points for speed and combo chains (consecutive valid moves without hesitation).

## Gameplay Loop
1. Board appears with knight on a starting square
2. Valid L-shaped destinations are highlighted
3. Player moves cursor to a valid square and confirms with A button (or tap)
4. Visited squares are marked; move counter tracks progress
5. Timer counts down -- bonus points awarded for time remaining
6. Level complete when all squares visited; next level has larger board
7. Game over if timer expires or no valid moves remain (trapped)

## Visual Design (1-bit)
- Checkerboard pattern with alternating black/white squares
- Knight represented as a stylized chess knight icon
- Valid moves shown as blinking dots
- Visited squares shown with an X mark
- Current cursor position shown with animated bracket corners
- HUD: level number, moves remaining, timer, score

## Controls
- D-pad: move cursor between valid destinations
- A button: confirm move / hop to selected square
- START: begin game / pause
- Touch: tap valid destination to hop

## Difficulty Progression
| Level | Board | Time | Description |
|-------|-------|------|-------------|
| 1 | 5x5 | 60s | Tutorial size |
| 2 | 5x5 | 45s | Faster |
| 3 | 6x6 | 60s | Bigger board |
| 4 | 6x6 | 50s | Faster |
| 5 | 7x7 | 70s | Challenge |
| 6 | 7x7 | 55s | Speed run |
| 7+ | 8x8 | 80s | Full board |

## Sound Design
- Hop sound: short rising tone on each valid move
- Invalid move: low buzz
- Combo sound: ascending notes for chains
- Timer warning: rapid beeps when <10s
- Level complete: triumphant arpeggio
- Game over: descending tones

## Demo Mode
- AI performs a knight's tour using Warnsdorff's heuristic
- 7-segment HH:MM clock displayed in corner
- Any button press exits to title

## Scoring
- Base points per hop: 10
- Time bonus: remaining seconds x 5
- Combo multiplier: consecutive quick hops (under 2s each) build x2, x3, x4
- Perfect clear (all squares): 500 bonus
- No-hesitation bonus: complete level without pausing > 3s on any move
