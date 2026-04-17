# THE DARK ROOM: LETHE -- UX/UI Polish
## Agent 38 | Wave 4 | UX/UI Domain

### Base
Built on Agent 29's story-first psychological horror. All gameplay, story, puzzles, and audio preserved intact.

### UX/UI Changes

#### Inventory Overhaul
- Grid-style layout with 5x2 icon cells instead of plain text list
- Each item rendered as a bordered icon tile with its single-char icon centered
- Selected item gets highlight border and description shown below the grid
- Combine mode visually marks first item with a pulsing outline
- Held item shown with clear "USING:" label in HUD
- Button prompts at bottom: A=Inspect, SEL=Hold, START=Craft

#### Minimap
- 5x3 room grid in top-right corner (18x12px) showing discovered rooms
- Current room highlighted with a blinking dot
- Rooms fill in as visited (discovery tracking via room_narrated flags)
- Fades out after 3 seconds of no room change, reappears on transition
- Drawn at alpha using dither so it does not obscure gameplay

#### Subtle HUD
- Bottom bar reduced to 8px height, drawn with dither transparency
- Room name left-aligned, direction as small compass icon (arrow glyph)
- Held-item icon shown inline only when an item is active
- HUD auto-fades: full opacity during interaction, dims after 2s idle
- Story progress dots replaced with a thin progress bar (1px tall)

#### Touch / Tap Support
- Hotspot interaction: cursor snaps to tapped hotspot center on A press
- Typewriter text: tap (A) skips to end; second tap dismisses
- Inventory: swipe-like quick open via double-tap B
- All overlays respond to A for primary action, B for dismiss

#### Contextual Button Prompts
- Dynamic prompt bar at screen bottom shows what A and B do right now
- During exploration: "A:Look  B:Items"
- Near a hotspot (cursor overlap): "A:Examine [name]  B:Items"
- Inventory open: "A:Inspect  B:Close"
- Craft mode: "A:Select  B:Cancel"
- Safe puzzle: "^v:Digit  <>:Slot  A:Try  B:Exit"
- Typewriter playing: "A:Skip"
- Typewriter done: "A:Continue"
- Prompts use DARK color so they fade into the background

#### Loading / Transition Polish
- Room transitions use a radial-wipe pattern (scanlines converge to center then expand)
- Transition takes 20 frames instead of 15 for smoother feel
- Brief black hold (4 frames) between wipe-out and wipe-in
- New room name flashes centered on screen during the hold frame
- Title-to-play transition fades through black over 10 frames

#### Layout Audit (160x120 compliance)
- All text clamped to screen bounds; word_wrap reduced to 26 chars for overlays
- Inventory grid positioned at (8,14) with 68x50 footprint -- no overflow
- Minimap at (140,2) sized 18x12 -- fits within right margin
- Message popups max width capped at 152px, centered with 4px margin
- Typewriter overlay has 8px margin all sides; scroll area fits 8 lines of 26 chars
- Document overlay margin increased to 10px each side
- Ending text wrap set to 30 chars, 11 visible lines with safe margins
- Safe digit display repositioned inside safe draw area to avoid overflow
- Pause menu centered with fixed 80x36 box
- All HUD elements verified to stay within 160x120 pixel boundary

### Architecture
- Same mode(2), 160x120, 2-bit, 4 shades
- Same controls: D-Pad, A, B, START, SELECT
- Single file, no external assets
- All original story content, puzzles, and endings preserved verbatim
