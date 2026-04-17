-- GRAVITON - Main Game Scene
-- Core mechanic: blocks fall under gravity. Player can rotate gravity direction
-- and move/drop pieces. Fill complete lines to clear them. Gravity rotation
-- creates unique strategic depth.

-- Grid constants
local GRID_W = 8
local GRID_H = 10
local CELL = 8          -- pixel size of each cell
local GRID_PX_X = 36    -- grid top-left pixel X
local GRID_PX_Y = 10    -- grid top-left pixel Y

-- Gravity directions: 1=down, 2=left, 3=up, 4=right
local GRAV_DOWN = 1
local GRAV_LEFT = 2
local GRAV_UP = 3
local GRAV_RIGHT = 4

local GRAV_NAMES = {"DOWN", "LEFT", "UP", "RIGHT"}
local GRAV_ARROWS = {"v", "<", "^", ">"}

-- Piece shapes (relative offsets from pivot)
-- Each shape is a list of {dx, dy} offsets
local SHAPES = {
  -- L-shape
  { {0,0}, {1,0}, {2,0}, {2,1} },
  -- J-shape
  { {0,0}, {1,0}, {2,0}, {0,1} },
  -- T-shape
  { {0,0}, {1,0}, {2,0}, {1,1} },
  -- S-shape
  { {1,0}, {2,0}, {0,1}, {1,1} },
  -- Z-shape
  { {0,0}, {1,0}, {1,1}, {2,1} },
  -- O-shape (2x2)
  { {0,0}, {1,0}, {0,1}, {1,1} },
  -- I-shape
  { {0,0}, {1,0}, {2,0}, {3,0} },
}

-- Color palette for block types (grayscale shades, brighter = heavier/more points)
local BLOCK_COLORS = {6, 8, 10, 12, 14, 9, 11}

-- Game state (score, level, lines_cleared are global for gameover screen)
local grid = {}          -- grid[y][x] = 0 (empty) or color value
local gravity = GRAV_DOWN
local piece = nil         -- current falling piece
local next_piece = nil    -- preview piece
score = 0
level = 1
lines_cleared = 0
local combo = 0
local game_over = false
local fall_timer = 0
local fall_speed = 20     -- frames between gravity steps (decreases with level)
local lock_timer = 0
local lock_delay = 12     -- frames before locking after landing
local clear_flash = 0     -- animation timer for line clears
local clearing_lines = {} -- lines being cleared
local gravity_rotate_cooldown = 0
local shake_timer = 0
local score_popups = {}   -- {x, y, text, timer}
local das_timer = 0       -- delayed auto-shift
local das_dir = nil
local DAS_DELAY = 8
local DAS_REPEAT = 3
local paused = false

-- Touch control state
local touch_cooldown = 0
local TOUCH_COOLDOWN_FRAMES = 4

-- Gravity rotation visual
local grav_anim_timer = 0
local grav_anim_from = GRAV_DOWN

function game_init()
  -- Initialize grid
  grid = {}
  for y = 1, GRID_H do
    grid[y] = {}
    for x = 1, GRID_W do
      grid[y][x] = 0
    end
  end

  gravity = GRAV_DOWN
  score = 0       -- global
  level = 1       -- global
  lines_cleared = 0  -- global
  combo = 0
  game_over = false
  fall_timer = 0
  fall_speed = 20
  lock_timer = 0
  clear_flash = 0
  clearing_lines = {}
  gravity_rotate_cooldown = 0
  shake_timer = 0
  score_popups = {}
  das_timer = 0
  das_dir = nil
  grav_anim_timer = 0
  paused = false
  touch_cooldown = 0

  -- Spawn first pieces
  next_piece = generate_piece()
  spawn_piece()
end

function generate_piece()
  local shape_idx = math.random(1, #SHAPES)
  local shape = SHAPES[shape_idx]
  local color = BLOCK_COLORS[shape_idx]
  -- Deep copy shape
  local blocks = {}
  for i, b in ipairs(shape) do
    blocks[i] = {b[1], b[2]}
  end
  return { blocks = blocks, color = color, x = 0, y = 0, shape_idx = shape_idx }
end

function spawn_piece()
  piece = next_piece
  next_piece = generate_piece()

  -- Position piece at spawn edge based on gravity
  position_piece_at_spawn(piece)

  -- Check if spawn position is valid
  if not is_valid_position(piece) then
    game_over = true
    -- Update high score
    if score > high_score then
      high_score = score
    end
    noise(0, 0.5)
  else
    -- Spawn sound
    note(0, "E4", 0.05)
  end
end

function position_piece_at_spawn(p)
  -- Find piece bounds
  local minx, maxx, miny, maxy = 99, -99, 99, -99
  for _, b in ipairs(p.blocks) do
    if b[1] < minx then minx = b[1] end
    if b[1] > maxx then maxx = b[1] end
    if b[2] < miny then miny = b[2] end
    if b[2] > maxy then maxy = b[2] end
  end
  local pw = maxx - minx + 1
  local ph = maxy - miny + 1

  if gravity == GRAV_DOWN then
    p.x = math.floor((GRID_W - pw) / 2) + 1
    p.y = 1 - miny
  elseif gravity == GRAV_UP then
    p.x = math.floor((GRID_W - pw) / 2) + 1
    p.y = GRID_H - maxy
  elseif gravity == GRAV_LEFT then
    p.x = GRID_W - maxx
    p.y = math.floor((GRID_H - ph) / 2) + 1
  elseif gravity == GRAV_RIGHT then
    p.x = 1 - minx
    p.y = math.floor((GRID_H - ph) / 2) + 1
  end
end

function is_valid_position(p, ox, oy)
  ox = ox or 0
  oy = oy or 0
  for _, b in ipairs(p.blocks) do
    local gx = p.x + b[1] + ox
    local gy = p.y + b[2] + oy
    if gx < 1 or gx > GRID_W or gy < 1 or gy > GRID_H then
      return false
    end
    if grid[gy][gx] ~= 0 then
      return false
    end
  end
  return true
end

function get_gravity_delta()
  if gravity == GRAV_DOWN then return 0, 1
  elseif gravity == GRAV_UP then return 0, -1
  elseif gravity == GRAV_LEFT then return -1, 0
  elseif gravity == GRAV_RIGHT then return 1, 0
  end
end

function get_move_axes()
  -- Returns the lateral movement directions based on gravity
  -- Returns: left_dx, left_dy, right_dx, right_dy
  if gravity == GRAV_DOWN or gravity == GRAV_UP then
    return -1, 0, 1, 0  -- left/right movement
  else
    return 0, -1, 0, 1  -- up/down movement
  end
end

function lock_piece()
  if not piece then return end
  for _, b in ipairs(piece.blocks) do
    local gx = piece.x + b[1]
    local gy = piece.y + b[2]
    if gy >= 1 and gy <= GRID_H and gx >= 1 and gx <= GRID_W then
      grid[gy][gx] = piece.color
    end
  end
  -- Lock sound
  note(0, "C3", 0.05)
  note(1, "G3", 0.05)

  piece = nil
  lock_timer = 0

  -- Check for line clears
  check_lines()
end

function check_lines()
  clearing_lines = {}

  if gravity == GRAV_DOWN or gravity == GRAV_UP then
    -- Check horizontal rows
    for y = 1, GRID_H do
      local full = true
      for x = 1, GRID_W do
        if grid[y][x] == 0 then full = false; break end
      end
      if full then
        table.insert(clearing_lines, {type = "row", idx = y})
      end
    end
  else
    -- Check vertical columns
    for x = 1, GRID_W do
      local full = true
      for y = 1, GRID_H do
        if grid[y][x] == 0 then full = false; break end
      end
      if full then
        table.insert(clearing_lines, {type = "col", idx = x})
      end
    end
  end

  if #clearing_lines > 0 then
    clear_flash = 15  -- start flash animation
    combo = combo + 1

    -- Score: more lines = exponentially more points, combos multiply
    local line_count = #clearing_lines
    local base = line_count * line_count * 100
    local combo_mult = math.min(combo, 8)
    local level_mult = level
    local pts = base * combo_mult * level_mult

    score = score + pts
    lines_cleared = lines_cleared + line_count

    -- Level up every 8 lines
    local new_level = math.floor(lines_cleared / 8) + 1
    if new_level > level then
      level = new_level
      fall_speed = math.max(4, 20 - (level - 1) * 2)
      -- Level up fanfare
      note(0, "C5", 0.1)
      note(1, "E5", 0.1)
    end

    -- Score popup
    local popup_x, popup_y
    if clearing_lines[1].type == "row" then
      popup_x = GRID_PX_X + GRID_W * CELL / 2
      popup_y = GRID_PX_Y + (clearing_lines[1].idx - 1) * CELL
    else
      popup_x = GRID_PX_X + (clearing_lines[1].idx - 1) * CELL
      popup_y = GRID_PX_Y + GRID_H * CELL / 2
    end
    table.insert(score_popups, {x = popup_x, y = popup_y, text = "+" .. pts, timer = 30})

    -- Sound effects
    if line_count >= 4 then
      note(0, "C5", 0.15)
      note(1, "G5", 0.15)
      cam_shake(4)
    elseif line_count >= 2 then
      note(0, "E5", 0.1)
      cam_shake(2)
    else
      note(0, "G4", 0.08)
    end

    shake_timer = 5
  else
    combo = 0
    -- No clears, spawn next piece
    spawn_piece()
  end
end

function do_clear_lines()
  -- Actually remove the cleared lines and shift blocks
  for _, cl in ipairs(clearing_lines) do
    if cl.type == "row" then
      -- Clear row, shift based on gravity
      for x = 1, GRID_W do
        grid[cl.idx][x] = 0
      end
    else
      -- Clear column
      for y = 1, GRID_H do
        grid[y][cl.idx] = 0
      end
    end
  end

  -- Apply gravity to remaining blocks
  apply_gravity_to_grid()

  clearing_lines = {}
  spawn_piece()
end

function apply_gravity_to_grid()
  local gdx, gdy = get_gravity_delta()

  if gravity == GRAV_DOWN then
    -- Shift blocks down to fill gaps
    for x = 1, GRID_W do
      local write = GRID_H
      for y = GRID_H, 1, -1 do
        if grid[y][x] ~= 0 then
          if write ~= y then
            grid[write][x] = grid[y][x]
            grid[y][x] = 0
          end
          write = write - 1
        end
      end
    end
  elseif gravity == GRAV_UP then
    for x = 1, GRID_W do
      local write = 1
      for y = 1, GRID_H do
        if grid[y][x] ~= 0 then
          if write ~= y then
            grid[write][x] = grid[y][x]
            grid[y][x] = 0
          end
          write = write + 1
        end
      end
    end
  elseif gravity == GRAV_LEFT then
    for y = 1, GRID_H do
      local write = 1
      for x = 1, GRID_W do
        if grid[y][x] ~= 0 then
          if write ~= x then
            grid[y][write] = grid[y][x]
            grid[y][x] = 0
          end
          write = write + 1
        end
      end
    end
  elseif gravity == GRAV_RIGHT then
    for y = 1, GRID_H do
      local write = GRID_W
      for x = GRID_W, 1, -1 do
        if grid[y][x] ~= 0 then
          if write ~= x then
            grid[y][write] = grid[y][x]
            grid[y][x] = 0
          end
          write = write - 1
        end
      end
    end
  end
end

function rotate_gravity(dir)
  -- dir: 1 = clockwise, -1 = counter-clockwise
  grav_anim_from = gravity
  grav_anim_timer = 10

  local old_grav = gravity
  gravity = ((gravity - 1 + dir) % 4) + 1

  -- Sound for gravity rotation
  if dir == 1 then
    tone(0, 300, 500, 0.1)
  else
    tone(0, 500, 300, 0.1)
  end

  -- Apply gravity to all existing grid blocks
  apply_gravity_to_grid()

  -- Reposition current piece if possible
  if piece then
    -- Try to keep piece valid, if not revert
    if not is_valid_position(piece) then
      -- Try nudging piece
      local nudged = false
      for nudge = 1, 3 do
        local gdx, gdy = get_gravity_delta()
        -- Try opposite of gravity (push away from wall)
        if is_valid_position(piece, -gdx * nudge, -gdy * nudge) then
          piece.x = piece.x - gdx * nudge
          piece.y = piece.y - gdy * nudge
          nudged = true
          break
        end
      end
      if not nudged then
        -- Revert gravity
        gravity = old_grav
        apply_gravity_to_grid()
        noise(0, 0.05)  -- feedback for failed rotation
      end
    end
  end

  gravity_rotate_cooldown = 8
end

function hard_drop()
  if not piece then return end
  local gdx, gdy = get_gravity_delta()
  local dropped = 0
  while is_valid_position(piece, gdx, gdy) do
    piece.x = piece.x + gdx
    piece.y = piece.y + gdy
    dropped = dropped + 1
  end
  -- Bonus score for hard drop
  score = score + dropped * 2
  lock_piece()
  -- Drop sound
  tone(1, 200, 80, 0.08)
  shake_timer = 3
end

function game_update()
  if game_over then
    if btnp("start") or touch_start() then
      go("gameover")
    end
    return
  end

  -- Pause toggle
  if btnp("select") then
    paused = not paused
    if paused then
      note(0, "E3", 0.05)
    else
      note(0, "E4", 0.05)
    end
  end
  if paused then return end

  -- Handle line clear animation
  if clear_flash > 0 then
    clear_flash = clear_flash - 1
    if clear_flash <= 0 then
      do_clear_lines()
    end
    return
  end

  if gravity_rotate_cooldown > 0 then
    gravity_rotate_cooldown = gravity_rotate_cooldown - 1
  end

  if grav_anim_timer > 0 then
    grav_anim_timer = grav_anim_timer - 1
  end

  if shake_timer > 0 then
    shake_timer = shake_timer - 1
  end

  -- Update score popups
  for i = #score_popups, 1, -1 do
    local p = score_popups[i]
    p.timer = p.timer - 1
    p.y = p.y - 0.5
    if p.timer <= 0 then
      table.remove(score_popups, i)
    end
  end

  if not piece then return end

  -- Touch cooldown timer
  if touch_cooldown > 0 then
    touch_cooldown = touch_cooldown - 1
  end

  -- Touch input: swipes and taps
  local swipe_dir = swipe()
  if swipe_dir then
    touch_cooldown = TOUCH_COOLDOWN_FRAMES
    if swipe_dir == "left" then
      -- Swipe left = move piece left
      if gravity == GRAV_DOWN or gravity == GRAV_UP then
        if is_valid_position(piece, -1, 0) then
          piece.x = piece.x - 1
          lock_timer = 0
          note(1, "A4", 0.02)
        end
      else
        if is_valid_position(piece, 0, -1) then
          piece.y = piece.y - 1
          lock_timer = 0
          note(1, "A4", 0.02)
        end
      end
    elseif swipe_dir == "right" then
      -- Swipe right = move piece right
      if gravity == GRAV_DOWN or gravity == GRAV_UP then
        if is_valid_position(piece, 1, 0) then
          piece.x = piece.x + 1
          lock_timer = 0
          note(1, "A4", 0.02)
        end
      else
        if is_valid_position(piece, 0, 1) then
          piece.y = piece.y + 1
          lock_timer = 0
          note(1, "A4", 0.02)
        end
      end
    elseif swipe_dir == "up" then
      -- Swipe up = hard drop
      hard_drop()
      return
    elseif swipe_dir == "down" then
      -- Swipe down = soft drop (move one step toward gravity)
      local gdx, gdy = get_gravity_delta()
      if is_valid_position(piece, gdx, gdy) then
        piece.x = piece.x + gdx
        piece.y = piece.y + gdy
        score = score + 1
        lock_timer = 0
      end
    end
  end

  -- Touch tap: detect tap (touch_start without a swipe)
  if touch_start() and not swipe_dir and touch_cooldown <= 0 then
    local tx, ty = touch_pos()
    if tx and ty then
      -- Screen is 160 wide: left third, center third, right third
      if tx < 53 then
        -- Tap left side = move piece left
        if gravity == GRAV_DOWN or gravity == GRAV_UP then
          if is_valid_position(piece, -1, 0) then
            piece.x = piece.x - 1
            lock_timer = 0
            note(1, "A4", 0.02)
          end
        else
          if is_valid_position(piece, 0, -1) then
            piece.y = piece.y - 1
            lock_timer = 0
            note(1, "A4", 0.02)
          end
        end
      elseif tx > 107 then
        -- Tap right side = move piece right
        if gravity == GRAV_DOWN or gravity == GRAV_UP then
          if is_valid_position(piece, 1, 0) then
            piece.x = piece.x + 1
            lock_timer = 0
            note(1, "A4", 0.02)
          end
        else
          if is_valid_position(piece, 0, 1) then
            piece.y = piece.y + 1
            lock_timer = 0
            note(1, "A4", 0.02)
          end
        end
      else
        -- Tap center = rotate gravity (A button equivalent)
        if gravity_rotate_cooldown <= 0 then
          rotate_gravity(1)
        end
      end
      touch_cooldown = TOUCH_COOLDOWN_FRAMES
    end
  end

  -- Input: rotate gravity with A button
  if btnp("a") and gravity_rotate_cooldown <= 0 then
    rotate_gravity(1)  -- clockwise
  end

  -- Input: movement (lateral to gravity direction)
  local ldx, ldy, rdx, rdy = get_move_axes()

  -- DAS (Delayed Auto-Shift) system
  local move_left = btnp("left") or btnp("up")
  local move_right = btnp("right") or btnp("down")

  -- Map d-pad to movement based on gravity
  local mx, my = 0, 0
  if gravity == GRAV_DOWN or gravity == GRAV_UP then
    if btnp("left") then mx = -1 end
    if btnp("right") then mx = 1 end
    -- DAS
    if btn("left") then
      if das_dir == "left" then
        das_timer = das_timer + 1
        if das_timer > DAS_DELAY and das_timer % DAS_REPEAT == 0 then mx = -1 end
      else
        das_dir = "left"
        das_timer = 0
      end
    elseif btn("right") then
      if das_dir == "right" then
        das_timer = das_timer + 1
        if das_timer > DAS_DELAY and das_timer % DAS_REPEAT == 0 then mx = 1 end
      else
        das_dir = "right"
        das_timer = 0
      end
    else
      das_dir = nil
      das_timer = 0
    end
  else
    if btnp("up") then my = -1 end
    if btnp("down") then my = 1 end
    -- DAS
    if btn("up") then
      if das_dir == "up" then
        das_timer = das_timer + 1
        if das_timer > DAS_DELAY and das_timer % DAS_REPEAT == 0 then my = -1 end
      else
        das_dir = "up"
        das_timer = 0
      end
    elseif btn("down") then
      if das_dir == "down" then
        das_timer = das_timer + 1
        if das_timer > DAS_DELAY and das_timer % DAS_REPEAT == 0 then my = 1 end
      else
        das_dir = "down"
        das_timer = 0
      end
    else
      das_dir = nil
      das_timer = 0
    end
  end

  -- Apply lateral movement
  if mx ~= 0 or my ~= 0 then
    if is_valid_position(piece, mx, my) then
      piece.x = piece.x + mx
      piece.y = piece.y + my
      lock_timer = 0  -- reset lock delay on movement
      note(1, "A4", 0.02)
    end
  end

  -- Hard drop with B
  if btnp("b") then
    hard_drop()
    return
  end

  -- Soft drop: pressing toward gravity speeds up fall
  local gdx, gdy = get_gravity_delta()
  local soft_drop = false
  if gravity == GRAV_DOWN and btn("down") then soft_drop = true end
  if gravity == GRAV_UP and btn("up") then soft_drop = true end
  if gravity == GRAV_LEFT and btn("left") then soft_drop = true end
  if gravity == GRAV_RIGHT and btn("right") then soft_drop = true end

  -- Gravity fall
  local effective_speed = soft_drop and math.max(2, math.floor(fall_speed / 4)) or fall_speed
  fall_timer = fall_timer + 1

  if fall_timer >= effective_speed then
    fall_timer = 0
    if is_valid_position(piece, gdx, gdy) then
      piece.x = piece.x + gdx
      piece.y = piece.y + gdy
      if soft_drop then score = score + 1 end
      lock_timer = 0
    end
  end

  -- Check lock on every frame if piece can't move in gravity direction
  if piece and not is_valid_position(piece, gdx, gdy) then
    lock_timer = lock_timer + 1
    if lock_timer >= lock_delay then
      lock_piece()
    end
  end
end

function game_draw()
  local s = screen()
  cls(s, 0)

  -- Camera shake
  if shake_timer > 0 then
    cam_shake(2)
  end

  -- Draw grid background
  rectf(s, GRID_PX_X - 1, GRID_PX_Y - 1, GRID_W * CELL + 2, GRID_H * CELL + 2, 2)
  rectf(s, GRID_PX_X, GRID_PX_Y, GRID_W * CELL, GRID_H * CELL, 1)

  -- Draw grid lines
  for x = 0, GRID_W do
    local px = GRID_PX_X + x * CELL
    line(s, px, GRID_PX_Y, px, GRID_PX_Y + GRID_H * CELL, 2)
  end
  for y = 0, GRID_H do
    local py = GRID_PX_Y + y * CELL
    line(s, GRID_PX_X, py, GRID_PX_X + GRID_W * CELL, py, 2)
  end

  -- Draw placed blocks
  for y = 1, GRID_H do
    for x = 1, GRID_W do
      if grid[y][x] ~= 0 then
        draw_block(s, GRID_PX_X + (x-1) * CELL, GRID_PX_Y + (y-1) * CELL, grid[y][x])
      end
    end
  end

  -- Draw ghost piece (preview of where piece will land)
  if piece and not game_over then
    local gdx, gdy = get_gravity_delta()
    local ghost_ox, ghost_oy = 0, 0
    while is_valid_position(piece, ghost_ox + gdx, ghost_oy + gdy) do
      ghost_ox = ghost_ox + gdx
      ghost_oy = ghost_oy + gdy
    end
    for _, b in ipairs(piece.blocks) do
      local gx = piece.x + b[1] + ghost_ox
      local gy = piece.y + b[2] + ghost_oy
      local px = GRID_PX_X + (gx - 1) * CELL
      local py = GRID_PX_Y + (gy - 1) * CELL
      rect(s, px + 1, py + 1, CELL - 2, CELL - 2, 4)
    end
  end

  -- Draw current piece
  if piece and not game_over then
    for _, b in ipairs(piece.blocks) do
      local gx = piece.x + b[1]
      local gy = piece.y + b[2]
      if gx >= 1 and gx <= GRID_W and gy >= 1 and gy <= GRID_H then
        draw_block(s, GRID_PX_X + (gx-1) * CELL, GRID_PX_Y + (gy-1) * CELL, piece.color)
      end
    end
  end

  -- Line clear flash
  if clear_flash > 0 then
    local flash_c = (math.floor(clear_flash / 2) % 2 == 0) and 15 or 0
    for _, cl in ipairs(clearing_lines) do
      if cl.type == "row" then
        rectf(s, GRID_PX_X, GRID_PX_Y + (cl.idx - 1) * CELL, GRID_W * CELL, CELL, flash_c)
      else
        rectf(s, GRID_PX_X + (cl.idx - 1) * CELL, GRID_PX_Y, CELL, GRID_H * CELL, flash_c)
      end
    end
  end

  -- Draw gravity indicator
  draw_gravity_indicator(s)

  -- Draw UI panel (right side)
  draw_ui(s)

  -- Draw score popups
  for _, p in ipairs(score_popups) do
    local alpha = math.min(15, math.floor(p.timer / 2) + 8)
    text(s, p.text, math.floor(p.x), math.floor(p.y), alpha, ALIGN_HCENTER)
  end

  -- Game over overlay
  if game_over then
    rectf(s, 20, 40, 120, 40, 0)
    rect(s, 20, 40, 120, 40, 15)
    text(s, "GAME OVER", 80, 48, 15, ALIGN_HCENTER)
    text(s, "SCORE: " .. score, 80, 58, 12, ALIGN_HCENTER)
    if math.floor(frame() / 15) % 2 == 0 then
      text(s, "PRESS START", 80, 70, 10, ALIGN_HCENTER)
    end
  end

  -- Pause overlay
  if paused then
    rectf(s, 40, 45, 80, 30, 0)
    rect(s, 40, 45, 80, 30, 12)
    text(s, "PAUSED", 80, 52, 15, ALIGN_HCENTER)
    text(s, "SELECT TO RESUME", 80, 63, 8, ALIGN_HCENTER)
  end
end

function draw_block(s, px, py, c)
  -- Draw a single block with 3D-ish shading
  rectf(s, px, py, CELL, CELL, c)
  -- Highlight top-left edge
  line(s, px, py, px + CELL - 1, py, math.min(15, c + 2))
  line(s, px, py, px, py + CELL - 1, math.min(15, c + 1))
  -- Shadow bottom-right edge
  line(s, px + CELL - 1, py, px + CELL - 1, py + CELL - 1, math.max(0, c - 2))
  line(s, px, py + CELL - 1, px + CELL - 1, py + CELL - 1, math.max(0, c - 3))
  -- Inner dot
  pix(s, px + 3, py + 3, math.min(15, c + 3))
end

function draw_gravity_indicator(s)
  -- Draw gravity arrow indicator at top-left
  local gx, gy = 14, 14
  local r = 10

  -- Background circle
  circf(s, gx, gy, r, 2)
  circ(s, gx, gy, r, 6)

  -- Arrow pointing in gravity direction
  local gdx, gdy = get_gravity_delta()
  local ax = gx + gdx * 6
  local ay = gy + gdy * 6

  -- Arrow line
  line(s, gx, gy, ax, ay, 15)

  -- Arrowhead
  if gravity == GRAV_DOWN then
    line(s, ax - 2, ay - 2, ax, ay, 15)
    line(s, ax + 2, ay - 2, ax, ay, 15)
  elseif gravity == GRAV_UP then
    line(s, ax - 2, ay + 2, ax, ay, 15)
    line(s, ax + 2, ay + 2, ax, ay, 15)
  elseif gravity == GRAV_LEFT then
    line(s, ax + 2, ay - 2, ax, ay, 15)
    line(s, ax + 2, ay + 2, ax, ay, 15)
  elseif gravity == GRAV_RIGHT then
    line(s, ax - 2, ay - 2, ax, ay, 15)
    line(s, ax - 2, ay + 2, ax, ay, 15)
  end

  -- Label
  text(s, "G", gx, gy + r + 4, 8, ALIGN_HCENTER)

  -- Animation flash on rotation
  if grav_anim_timer > 0 then
    local flash_r = r + (10 - grav_anim_timer) * 2
    circ(s, gx, gy, flash_r, math.max(1, grav_anim_timer))
  end
end

function draw_ui(s)
  local ux = GRID_PX_X + GRID_W * CELL + 6
  local uy = GRID_PX_Y

  -- Score
  text(s, "SCORE", ux, uy, 8)
  text(s, tostring(score), ux, uy + 8, 15)

  -- Level
  text(s, "LEVEL", ux, uy + 20, 8)
  text(s, tostring(level), ux, uy + 28, 12)

  -- Lines
  text(s, "LINES", ux, uy + 40, 8)
  text(s, tostring(lines_cleared), ux, uy + 48, 12)

  -- Combo
  if combo > 1 then
    text(s, "COMBO", ux, uy + 60, 8)
    text(s, "x" .. combo, ux, uy + 68, 14)
  end

  -- Next piece preview
  text(s, "NEXT", ux + 8, uy + 75, 8)
  if next_piece then
    local nx = ux + 6
    local ny = uy + 84
    rectf(s, nx - 1, ny - 1, 26, 18, 1)
    rect(s, nx - 1, ny - 1, 26, 18, 4)
    for _, b in ipairs(next_piece.blocks) do
      draw_block(s, nx + b[1] * 5, ny + b[2] * 5, next_piece.color)
    end
  end

  -- Gravity direction text
  text(s, "GRAV", 4, 30, 6)
  text(s, GRAV_ARROWS[gravity], 14, 38, 15, ALIGN_HCENTER)
end
