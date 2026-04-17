# Agent 39 | Wave 4 | TECHNICAL ROBUSTNESS

## Domain: Bulletproofing LETHE

Base: Agent 29 (Wave 3) - "THE DARK ROOM: LETHE" psychological horror adventure.

## Changes Made

### API Safety Guards
- Wrapped all engine API calls (`note`, `noise`, `tone`, `wave`, `btn`, `btnp`, `frame`, `screen`, `mode`, `cls`, `text`, `rect`, `rectf`, `line`, `circ`, `pix`) in safe wrappers with nil checks
- All drawing functions receive surface parameter first, verified before use
- `frame()` guarded with fallback to 0; memoized per-frame to avoid redundant calls

### Color Correctness (mode 2, 0-3 only)
- All color values are constants BLACK(0), DARK(1), LIGHT(2), WHITE(3)
- Added `safe_color()` clamp to guarantee 0-3 range on all draw calls
- Audited every `pix`, `rectf`, `rect`, `line`, `circ`, `text` call for valid colors

### Text Overflow Prevention (160x120)
- Message bar: clamped width to screen width, truncated text if exceeds ~38 chars
- Inventory overlay: capped visible items to 8, added scroll if more
- Typewriter overlay: enforced word_wrap max at 28 chars (fits 148px panel)
- Document overlay: enforced word_wrap max at 30 chars (fits 144px panel)
- Ending text: word_wrap at 32 chars with scroll
- All text coordinates verified within 0..159 x 0..119

### Demo Mode Stability
- Clamped `cur_x`/`cur_y` to integers after sin/cos drift
- Demo step wraps with modulo, never exceeds sequence length
- Demo runs indefinitely without accumulating floating point error
- All button checks guarded for demo exit

### Edge Case Handling
- Empty inventory: inv_sel stays at 1, all inventory actions check `#inv > 0`
- Max items (10): `add_item` already caps; added overflow message
- Rapid button pressing: all state transitions are idempotent; no double-fire on transitions
- `inv_sel` re-clamped after combine removes items
- `held_item` validated against current inventory before use
- `combine_first` cleared on inventory close
- Safe puzzle digits always 0-9 via modulo
- `get_ending()` always returns 1-3; ending_texts indexed safely
- `trans_target_dir` defaults to DIR_N if nil
- Room narratives handle nil rooms gracefully

### Performance Optimizations
- `dither_rectf`: solid fills (pat<=0, pat>=4) use single `rectf` instead of per-pixel
- Checkerboard ceiling/floor: replaced per-pixel with row-based rectf bands
- Side wall fills: use rectf for horizontal spans instead of per-pixel pix calls
- Memoized `frame()` result per update cycle to avoid redundant engine calls

### Code Structure
- All safe wrappers at top of file, before any game logic
- Constants section clearly separated
- No global pollution; all state is local
- Consistent guard pattern: `if api then api(...) end`
