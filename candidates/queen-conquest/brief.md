# Queen Conquest

## Concept
A strategy/territory game using the chess queen's power on an 8x8 grid. Command your queen to conquer territory by claiming all squares in her line of sight (all 8 directions). Enemy bishops and rooks try to block and reclaim your territory. Maximize territory control while avoiding capture.

## Controls
- **D-Pad**: Move cursor on the grid
- **A Button**: Move queen to cursor position (must be a valid queen move)
- **B Button**: Skip turn (costs 1 point)
- **Start**: Start game / Pause
- **Touch**: Tap a square to move queen there

## Gameplay
- Player controls a white queen on an 8x8 board
- Moving the queen claims all squares along her path and line of sight
- Enemy pieces (bishops, rooks) spawn every few turns and reclaim territory
- Enemy pieces move toward the player's territory each turn
- If an enemy lands on the queen's square, she is captured (game over)
- If queen captures an enemy by moving to its square, bonus points
- Score = number of squares controlled; multiplied by consecutive captures
- Game ends on capture or when board is fully contested

## Scenes
1. **Title**: "QUEEN CONQUEST" with animated queen icon, press START
2. **Game**: 8x8 grid with queen, enemies, territory overlay, score/turn HUD
3. **Game Over**: Final score, territory percentage, high score

## Demo/Attract Mode
- Activates after idle on title screen
- AI queen plays automatically, making strategic moves
- Clock display shows current time
- Any button press returns to title

## Visual Style
- 1-bit black and white only
- Board: alternating filled/empty squares (classic chess pattern)
- Player territory: filled white squares with dot pattern
- Enemy territory: black squares with cross marks
- Queen: crown-like symbol (5x5 pixel art)
- Enemies: simplified bishop (diagonal lines) and rook (cross shape)

## Audio
- Move: short click note
- Capture territory: ascending arpeggio
- Enemy spawns: low warning tone
- Capture enemy: triumphant chord
- Game over: descending notes
