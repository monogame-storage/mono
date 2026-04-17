-- KNIGHT HOP
-- Visit every square on the board using the knight's L-shaped move.
-- A Chess Wars puzzle game for Mono (1-bit).

------------------------------------------------------------
-- CONSTANTS
------------------------------------------------------------
local W = 160
local H = 120

-- Knight L-shaped move offsets
local MOVES = {
  {-2,-1},{-2,1},{-1,-2},{-1,2},
  {1,-2},{1,2},{2,-1},{2,1}
}

-- Level definitions: {board_size, time_limit}
local LEVELS = {
  {5, 60}, {5, 45}, {6, 60}, {6, 50},
  {7, 70}, {7, 55}, {8, 80}, {8, 65},
}

-- 7-segment digit map: a=1 b=2 c=4 d=8 e=16 f=32 g=64
local SEG7 = {
  [0] = 1+2+4+8+16+32,
  [1] = 2+4,
  [2] = 1+2+8+16+64,
  [3] = 1+2+4+8+64,
  [4] = 2+4+32+64,
  [5] = 1+4+8+32+64,
  [6] = 1+4+8+16+32+64,
  [7] = 1+2+4,
  [8] = 1+2+4+8+16+32+64,
  [9] = 1+2+4+8+32+64,
}

------------------------------------------------------------
-- STATE
------------------------------------------------------------
local board = {}
local board_size = 5
local cell_px = 12
local board_ox, board_oy = 0, 0

local knight_r, knight_c = 1, 1
local cursor_r, cursor_c = 1, 1
local valid_moves = {}
local danger_map = {}  -- danger_map[r][c] = true if move leads to dead-end (0 onward moves)

local visited_count = 0
local total_cells = 25
local timer_left = 60
local timer_warn = false
local score = 0
local hi_score = 0
local level = 1
local combo = 0
local combo_timer = 0
local last_hop_time = 0
local game_over = false
local game_won = false
local paused = false
local level_complete = false
local level_complete_timer = 0
local trapped = false

local anim_frame = 0
local hop_anim = 0
local hop_from_r, hop_from_c = 0, 0
local flash_timer = 0
local shake = 0

-- Demo / attract mode
local demo_mode = false
local demo_path = {}
local demo_step = 0
local demo_timer = 0
local demo_delay = 12

-- Title screen
local title_anim = 0

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function bit_check(val, bit)
  return math.floor(val / bit) % 2 == 1
end

local function draw_seg7(s, digit, ox, oy, col)
  local segs = SEG7[digit] or 0
  local t = 1
  local sw = 3
  local sh = 3
  if bit_check(segs, 1) then rectf(s, ox+t, oy, sw, t, col) end
  if bit_check(segs, 2) then rectf(s, ox+t+sw, oy+t, t, sh, col) end
  if bit_check(segs, 4) then rectf(s, ox+t+sw, oy+t+sh+t, t, sh, col) end
  if bit_check(segs, 8) then rectf(s, ox+t, oy+t+sh+t+sh, sw, t, col) end
  if bit_check(segs, 16) then rectf(s, ox, oy+t+sh+t, t, sh, col) end
  if bit_check(segs, 32) then rectf(s, ox, oy+t, t, sh, col) end
  if bit_check(segs, 64) then rectf(s, ox+t, oy+t+sh, sw, t, col) end
end

local function draw_clock(s, cx, cy, col)
  local d = date()
  local hh = d.hour
  local mm = d.min
  local dw = 6
  draw_seg7(s, math.floor(hh/10), cx, cy, col)
  draw_seg7(s, hh%10, cx+dw, cy, col)
  -- colon
  local blink = math.floor(time()*2) % 2
  if blink == 0 then
    pix(s, cx+dw*2+1, cy+3, col)
    pix(s, cx+dw*2+1, cy+6, col)
  end
  draw_seg7(s, math.floor(mm/10), cx+dw*2+3, cy, col)
  draw_seg7(s, mm%10, cx+dw*2+3+dw, cy, col)
end

------------------------------------------------------------
-- BOARD LOGIC
------------------------------------------------------------
local function init_board(sz)
  board_size = sz
  total_cells = sz * sz
  cell_px = math.floor(math.min(96 / sz, 14))
  local bw = sz * cell_px
  local bh = sz * cell_px
  board_ox = math.floor((W - bw) / 2)
  board_oy = math.floor((H - bh) / 2) + 6

  board = {}
  for r = 1, sz do
    board[r] = {}
    for c = 1, sz do
      board[r][c] = 0  -- 0=unvisited, 1=visited
    end
  end
end

local function on_board(r, c)
  return r >= 1 and r <= board_size and c >= 1 and c <= board_size
end

local function get_valid_moves(r, c)
  local moves = {}
  for _, m in ipairs(MOVES) do
    local nr, nc = r + m[1], c + m[2]
    if on_board(nr, nc) and board[nr][nc] == 0 then
      moves[#moves+1] = {nr, nc}
    end
  end
  return moves
end

-- Compute danger map: for each valid move, check how many onward moves exist
-- A move is "dangerous" (dead-end) if landing there yields 0 further moves
-- A move is "risky" if landing there yields only 1 further move
local function compute_danger_map(moves, brd, sz)
  local dmap = {}
  for r = 1, sz do
    dmap[r] = {}
    for c = 1, sz do
      dmap[r][c] = 0  -- 0=safe, 1=risky(1 exit), 2=dead-end(0 exits)
    end
  end
  for _, m in ipairs(moves) do
    local mr, mc = m[1], m[2]
    -- Simulate landing on this square
    local old = brd[mr][mc]
    brd[mr][mc] = 1
    local onward = 0
    for _, mv in ipairs(MOVES) do
      local nr, nc = mr + mv[1], mc + mv[2]
      if nr >= 1 and nr <= sz and nc >= 1 and nc <= sz and brd[nr][nc] == 0 then
        onward = onward + 1
      end
    end
    brd[mr][mc] = old
    if onward == 0 then
      dmap[mr][mc] = 2  -- dead-end
    elseif onward == 1 then
      dmap[mr][mc] = 1  -- risky
    end
  end
  return dmap
end

-- Warnsdorff heuristic for demo AI
local function warnsdorff_degree(r, c, brd, sz)
  local count = 0
  for _, m in ipairs(MOVES) do
    local nr, nc = r + m[1], c + m[2]
    if nr >= 1 and nr <= sz and nc >= 1 and nc <= sz and brd[nr][nc] == 0 then
      count = count + 1
    end
  end
  return count
end

local function generate_tour(sz)
  local brd = {}
  for r = 1, sz do
    brd[r] = {}
    for c = 1, sz do
      brd[r][c] = 0
    end
  end

  -- Try multiple starting positions
  local best_path = {}
  local starts = {}
  for attempt = 1, 10 do
    local sr = math.random(1, sz)
    local sc = math.random(1, sz)
    starts[#starts+1] = {sr, sc}
  end
  -- Also try corners and edges which often work well
  starts[#starts+1] = {1, 1}
  starts[#starts+1] = {1, 2}
  starts[#starts+1] = {2, 1}

  for _, start in ipairs(starts) do
    -- Reset board
    for r = 1, sz do
      for c = 1, sz do
        brd[r][c] = 0
      end
    end

    local path = {{start[1], start[2]}}
    brd[start[1]][start[2]] = 1
    local cr, cc = start[1], start[2]

    for step = 2, sz * sz do
      local best_move = nil
      local best_deg = 9
      local candidates = {}

      for _, m in ipairs(MOVES) do
        local nr, nc = cr + m[1], cc + m[2]
        if nr >= 1 and nr <= sz and nc >= 1 and nc <= sz and brd[nr][nc] == 0 then
          local deg = warnsdorff_degree(nr, nc, brd, sz)
          if deg < best_deg then
            best_deg = deg
            candidates = {{nr, nc}}
          elseif deg == best_deg then
            candidates[#candidates+1] = {nr, nc}
          end
        end
      end

      if #candidates == 0 then break end
      best_move = candidates[math.random(1, #candidates)]
      cr, cc = best_move[1], best_move[2]
      brd[cr][cc] = 1
      path[#path+1] = {cr, cc}
    end

    if #path > #best_path then
      best_path = path
    end
    if #path >= sz * sz then break end
  end

  return best_path
end

local function cell_screen_pos(r, c)
  local x = board_ox + (c - 1) * cell_px
  local y = board_oy + (r - 1) * cell_px
  return x, y
end

local function screen_to_cell(sx, sy)
  local c = math.floor((sx - board_ox) / cell_px) + 1
  local r = math.floor((sy - board_oy) / cell_px) + 1
  if on_board(r, c) then return r, c end
  return nil, nil
end

------------------------------------------------------------
-- DRAWING: KNIGHT PIECE
------------------------------------------------------------
local function draw_knight(s, px, py, sz, col)
  -- Stylized knight head in a small pixel grid
  -- Scale based on cell size
  local sc = math.max(1, math.floor(sz / 10))
  local cx = px + math.floor(sz / 2)
  local cy = py + math.floor(sz / 2)

  if sz >= 10 then
    -- Detailed knight shape
    -- Base
    rectf(s, cx-3*sc, cy+2*sc, 6*sc, sc, col)
    -- Body
    rectf(s, cx-2*sc, cy-1*sc, 4*sc, 3*sc, col)
    -- Neck
    rectf(s, cx-sc, cy-3*sc, 2*sc, 2*sc, col)
    -- Head (forward facing)
    rectf(s, cx, cy-4*sc, 2*sc, sc, col)
    -- Ear
    pix(s, cx-sc, cy-4*sc, col)
    -- Eye (inverse color)
    pix(s, cx+sc, cy-3*sc, 1 - col)
  else
    -- Tiny knight for small cells
    rectf(s, cx-2, cy-2, 4, 5, col)
    rectf(s, cx-1, cy-4, 2, 2, col)
    pix(s, cx, cy-3, 1 - col)
  end
end

------------------------------------------------------------
-- SOUND EFFECTS
------------------------------------------------------------
local function sfx_hop()
  note(0, "E5", 0.06)
  note(1, "G5", 0.08)
end

local function sfx_invalid()
  note(0, "C3", 0.1)
  noise(1, 0.05)
end

local function sfx_combo(c)
  local notes_list = {"C5", "E5", "G5", "C6"}
  local n = notes_list[clamp(c, 1, 4)]
  note(0, n, 0.08)
end

local function sfx_timer_warn()
  note(0, "A5", 0.03)
end

local function sfx_level_complete()
  note(0, "C5", 0.1)
  note(1, "E5", 0.1)
  -- Delayed notes simulated by longer initial
  tone(0, 660, 784, 0.15)
  tone(1, 523, 1047, 0.2)
end

local function sfx_game_over()
  tone(0, 440, 220, 0.2)
  tone(1, 330, 165, 0.3)
end

local function sfx_trapped()
  noise(0, 0.15)
  tone(1, 300, 100, 0.2)
end

local function sfx_select()
  note(0, "C5", 0.04)
end

------------------------------------------------------------
-- GAME LOGIC
------------------------------------------------------------
local function start_level(lv)
  level = lv
  local ldef = LEVELS[math.min(lv, #LEVELS)]
  local sz = ldef[1]
  local tl = ldef[2]
  -- For levels beyond table, increase board but cap at 8
  if lv > #LEVELS then
    sz = 8
    tl = math.max(50, 80 - (lv - #LEVELS) * 3)
  end

  init_board(sz)
  timer_left = tl
  timer_warn = false
  visited_count = 0
  combo = 0
  combo_timer = 0
  last_hop_time = 0
  game_over = false
  game_won = false
  level_complete = false
  level_complete_timer = 0
  trapped = false
  hop_anim = 0
  flash_timer = 0
  shake = 0

  -- Pick a good starting position (corner-ish for better tours)
  knight_r = math.random(1, math.ceil(sz/2))
  knight_c = math.random(1, math.ceil(sz/2))
  board[knight_r][knight_c] = 1
  visited_count = 1

  valid_moves = get_valid_moves(knight_r, knight_c)
  danger_map = compute_danger_map(valid_moves, board, board_size)
  -- Free cursor starts at knight position
  cursor_r = knight_r
  cursor_c = knight_c
end

local function do_hop(r, c)
  -- Validate move
  local is_valid = false
  for _, m in ipairs(valid_moves) do
    if m[1] == r and m[2] == c then
      is_valid = true
      break
    end
  end
  if not is_valid then
    sfx_invalid()
    shake = 3
    return false
  end

  -- Perform hop
  hop_from_r, hop_from_c = knight_r, knight_c
  hop_anim = 8

  knight_r, knight_c = r, c
  board[r][c] = 1
  visited_count = visited_count + 1

  -- Combo system
  local now = time()
  if now - last_hop_time < 2.0 and last_hop_time > 0 then
    combo = combo + 1
    sfx_combo(combo)
  else
    combo = 1
    sfx_hop()
  end
  last_hop_time = now
  combo_timer = 30

  -- Score
  local base = 10
  local mult = clamp(combo, 1, 4)
  score = score + base * mult

  -- Check level complete
  if visited_count >= total_cells then
    level_complete = true
    level_complete_timer = 90
    -- Time bonus
    local time_bonus = math.floor(timer_left) * 5
    score = score + time_bonus + 500  -- perfect clear bonus
    sfx_level_complete()
    flash_timer = 20
    return true
  end

  -- Update valid moves and danger map
  valid_moves = get_valid_moves(knight_r, knight_c)
  if #valid_moves == 0 then
    trapped = true
    game_over = true
    sfx_trapped()
    cam_shake(5)
    return true
  end

  danger_map = compute_danger_map(valid_moves, board, board_size)
  cursor_r = knight_r
  cursor_c = knight_c
  return true
end

------------------------------------------------------------
-- SCENES
------------------------------------------------------------

-- === TITLE SCENE ===
function title_init()
  title_anim = 0
end

function title_update()
  title_anim = title_anim + 1
  anim_frame = anim_frame + 1

  if btnp("start") then
    sfx_select()
    score = 0
    start_level(1)
    go("game")
    return
  end

  -- Enter demo after idle
  if title_anim > 180 then
    go("demo")
    return
  end
end

function title_draw()
  local s = screen()
  cls(s, 0)

  -- Title text
  text(s, "KNIGHT HOP", W/2, 15, 1, ALIGN_CENTER)

  -- Animated knight bouncing
  local bounce = math.floor(math.sin(title_anim * 0.08) * 4)
  draw_knight(s, W/2 - 8, 30 + bounce, 16, 1)

  -- Chessboard decoration
  local bsz = 4
  for r = 0, 3 do
    for c = 0, 7 do
      if (r + c) % 2 == 0 then
        rectf(s, W/2 - 16 + c*bsz, 52 + r*bsz, bsz, bsz, 1)
      end
    end
  end

  -- L-shape illustration
  local lx, ly = W/2 + 25, 32
  rect(s, lx, ly, 9, 15, 1)
  rectf(s, lx+1, ly+1, 3, 5, 1)
  line(s, lx+4, ly+5, lx+7, ly+5, 1)
  rectf(s, lx+5, ly+1, 3, 4, 1)

  -- Instructions
  local blink = math.floor(title_anim * 0.06) % 2
  if blink == 0 then
    text(s, "PRESS START", W/2, 78, 1, ALIGN_CENTER)
  end

  text(s, "VISIT EVERY SQUARE", W/2, 90, 1, ALIGN_CENTER)
  text(s, "USING L-SHAPED HOPS", W/2, 98, 1, ALIGN_CENTER)

  -- High score
  if hi_score > 0 then
    text(s, "HI:" .. hi_score, W/2, 110, 1, ALIGN_CENTER)
  end
end

-- === DEMO SCENE ===
function demo_init()
  local sz = 5 + math.random(0, 1)
  init_board(sz)
  demo_path = generate_tour(sz)
  demo_step = 1
  demo_timer = 0

  if #demo_path > 0 then
    knight_r = demo_path[1][1]
    knight_c = demo_path[1][2]
    board[knight_r][knight_c] = 1
    visited_count = 1
  end

  valid_moves = get_valid_moves(knight_r, knight_c)
end

function demo_update()
  anim_frame = anim_frame + 1
  demo_timer = demo_timer + 1

  -- Any button exits demo
  if btnp("start") or btnp("a") or btnp("b") or btnp("select") then
    go("title")
    return
  end

  -- Touch exits demo
  if touch_start() then
    go("title")
    return
  end

  -- Auto-play
  if demo_timer >= demo_delay then
    demo_timer = 0
    demo_step = demo_step + 1

    if demo_step <= #demo_path then
      local nr, nc = demo_path[demo_step][1], demo_path[demo_step][2]
      hop_from_r, hop_from_c = knight_r, knight_c
      hop_anim = 6
      knight_r, knight_c = nr, nc
      board[nr][nc] = 1
      visited_count = visited_count + 1
      valid_moves = get_valid_moves(knight_r, knight_c)
      sfx_hop()
    else
      -- Tour done or stuck, restart demo
      demo_init()
    end
  end
end

function demo_draw()
  local s = screen()
  cls(s, 0)

  draw_board(s)

  -- DEMO label
  local blink = math.floor(anim_frame * 0.05) % 2
  if blink == 0 then
    text(s, "DEMO", W/2, 2, 1, ALIGN_CENTER)
  end

  -- 7-segment clock
  draw_clock(s, W - 30, 2, 1)

  -- "Press START" at bottom
  text(s, "PRESS START", W/2, H - 10, 1, ALIGN_CENTER)
end

-- === GAME SCENE ===
function game_init()
  paused = false
end

function game_update()
  anim_frame = anim_frame + 1

  if hop_anim > 0 then hop_anim = hop_anim - 1 end
  if flash_timer > 0 then flash_timer = flash_timer - 1 end
  if shake > 0 then shake = shake - 1 end
  if combo_timer > 0 then combo_timer = combo_timer - 1 end

  -- Pause
  if btnp("start") then
    if game_over or level_complete then
      -- Handled below
    else
      paused = not paused
      sfx_select()
      return
    end
  end

  if paused then return end

  -- Level complete transition
  if level_complete then
    level_complete_timer = level_complete_timer - 1
    if level_complete_timer <= 0 or btnp("a") then
      start_level(level + 1)
    end
    return
  end

  -- Game over
  if game_over then
    if btnp("a") or btnp("start") then
      if score > hi_score then hi_score = score end
      go("title")
    end
    return
  end

  -- Timer
  timer_left = timer_left - (1/30)
  if timer_left <= 10 and not timer_warn then
    timer_warn = true
  end
  if timer_warn and math.floor(timer_left * 2) % 2 == 0 and timer_left > 0 then
    if math.floor(anim_frame) % 15 == 0 then
      sfx_timer_warn()
    end
  end
  if timer_left <= 0 then
    timer_left = 0
    game_over = true
    sfx_game_over()
    cam_shake(4)
    return
  end

  -- Input: FREE CURSOR movement on d-pad, A confirms hop
  local moved = false

  if btnp("right") then
    cursor_c = clamp(cursor_c + 1, 1, board_size)
    moved = true
  elseif btnp("left") then
    cursor_c = clamp(cursor_c - 1, 1, board_size)
    moved = true
  elseif btnp("up") then
    cursor_r = clamp(cursor_r - 1, 1, board_size)
    moved = true
  elseif btnp("down") then
    cursor_r = clamp(cursor_r + 1, 1, board_size)
    moved = true
  end

  if moved then
    sfx_select()
  end

  -- Confirm hop with A: only if cursor is on a valid L-shaped destination
  if btnp("a") then
    local is_valid = false
    for _, m in ipairs(valid_moves) do
      if m[1] == cursor_r and m[2] == cursor_c then
        is_valid = true
        break
      end
    end
    if is_valid then
      do_hop(cursor_r, cursor_c)
    else
      sfx_invalid()
      shake = 3
    end
  end

  -- Touch input
  if touch_start() then
    local tx, ty = touch_pos()
    local tr, tc = screen_to_cell(tx, ty)
    if tr and tc then
      -- Check if it's a valid move
      local found = false
      for _, m in ipairs(valid_moves) do
        if m[1] == tr and m[2] == tc then
          cursor_r = tr
          cursor_c = tc
          do_hop(tr, tc)
          found = true
          break
        end
      end
      if not found then
        -- Move cursor to tapped cell even if not valid
        if on_board(tr, tc) then
          cursor_r = tr
          cursor_c = tc
        end
      end
    end
  end
end

------------------------------------------------------------
-- DRAWING
------------------------------------------------------------
function draw_board(s)
  -- Draw the chessboard
  for r = 1, board_size do
    for c = 1, board_size do
      local x, y = cell_screen_pos(r, c)
      local light = (r + c) % 2 == 0

      if board[r][c] == 1 then
        -- Visited square
        if light then
          rectf(s, x, y, cell_px, cell_px, 1)
          -- X mark
          line(s, x+2, y+2, x+cell_px-3, y+cell_px-3, 0)
          line(s, x+cell_px-3, y+2, x+2, y+cell_px-3, 0)
        else
          rectf(s, x, y, cell_px, cell_px, 0)
          line(s, x+2, y+2, x+cell_px-3, y+cell_px-3, 1)
          line(s, x+cell_px-3, y+2, x+2, y+cell_px-3, 1)
        end
      else
        -- Unvisited square
        if light then
          rectf(s, x, y, cell_px, cell_px, 1)
        else
          rectf(s, x, y, cell_px, cell_px, 0)
          rect(s, x, y, cell_px, cell_px, 1)
        end
      end
    end
  end

  -- Draw valid move indicators with DANGER MAP overlay
  if not game_over and not level_complete then
    local blink = math.floor(anim_frame * 0.15) % 2
    local fast_blink = math.floor(anim_frame * 0.3) % 2
    for _, m in ipairs(valid_moves) do
      local mr, mc = m[1], m[2]
      local x, y = cell_screen_pos(mr, mc)
      local cx = x + math.floor(cell_px / 2)
      local cy = y + math.floor(cell_px / 2)
      local sq_light = (mr + mc) % 2 == 0
      local dot_col = sq_light and 0 or 1
      local danger = danger_map[mr] and danger_map[mr][mc] or 0

      if danger == 2 then
        -- DEAD-END: fast blink inverted fill to warn player
        if fast_blink == 0 then
          -- Invert the whole cell
          rectf(s, x, y, cell_px, cell_px, dot_col)
          -- Draw skull-like X pattern
          line(s, x+1, y+1, x+cell_px-2, y+cell_px-2, 1 - dot_col)
          line(s, x+cell_px-2, y+1, x+1, y+cell_px-2, 1 - dot_col)
        else
          -- Normal dot on blink-off frame
          circf(s, cx, cy, 2, dot_col)
        end
      elseif danger == 1 then
        -- RISKY (1 exit): dashed border to signal caution
        if blink == 0 then
          circf(s, cx, cy, 2, dot_col)
        else
          circ(s, cx, cy, 2, dot_col)
        end
        -- Draw corner warning ticks
        pix(s, x+1, y+1, dot_col)
        pix(s, x+cell_px-2, y+1, dot_col)
        pix(s, x+1, y+cell_px-2, dot_col)
        pix(s, x+cell_px-2, y+cell_px-2, dot_col)
      else
        -- SAFE: normal indicator
        if blink == 0 then
          circf(s, cx, cy, 2, dot_col)
        else
          circ(s, cx, cy, 2, dot_col)
        end
      end
    end
  end

  -- Draw FREE CURSOR highlight (visible on any board square)
  if not game_over and not level_complete then
    local cx, cy = cell_screen_pos(cursor_r, cursor_c)
    local pulse = math.floor(anim_frame * 0.2) % 2
    local sz = cell_px

    -- Check if cursor is on a valid move target
    local on_valid = false
    for _, m in ipairs(valid_moves) do
      if m[1] == cursor_r and m[2] == cursor_c then
        on_valid = true
        break
      end
    end

    local cl = 1
    -- Bracket corners always visible
    -- Top-left
    line(s, cx-1, cy-1, cx+3, cy-1, cl)
    line(s, cx-1, cy-1, cx-1, cy+3, cl)
    -- Top-right
    line(s, cx+sz-4, cy-1, cx+sz, cy-1, cl)
    line(s, cx+sz, cy-1, cx+sz, cy+3, cl)
    -- Bottom-left
    line(s, cx-1, cy+sz, cx+3, cy+sz, cl)
    line(s, cx-1, cy+sz-4, cx-1, cy+sz, cl)
    -- Bottom-right
    line(s, cx+sz-4, cy+sz, cx+sz, cy+sz, cl)
    line(s, cx+sz, cy+sz-4, cx+sz, cy+sz, cl)

    if on_valid then
      -- Full pulsing border when on a valid target
      if pulse == 0 then
        rect(s, cx-1, cy-1, cell_px+2, cell_px+2, cl)
      end
    else
      -- Dimmer indicator: just the corners, no pulse rectangle
      -- (corners already drawn above)
    end
  end

  -- Draw knight
  local kx, ky = cell_screen_pos(knight_r, knight_c)
  if hop_anim > 0 then
    -- Animate hop: interpolate from old to new
    local fx, fy = cell_screen_pos(hop_from_r, hop_from_c)
    local t = 1.0 - (hop_anim / 8)
    local ax = fx + (kx - fx) * t
    local ay = fy + (ky - fy) * t - math.sin(t * 3.14159) * 12  -- Arc
    draw_knight(s, ax, ay, cell_px, 1)
  else
    draw_knight(s, kx, ky, cell_px, 1)
  end
end

function draw_hud(s)
  -- Top bar
  rectf(s, 0, 0, W, 9, 0)

  -- Level
  text(s, "LV" .. level, 2, 1, 1)

  -- Moves remaining
  local remaining = total_cells - visited_count
  text(s, remaining .. " LEFT", W/2, 1, 1, ALIGN_CENTER)

  -- Timer (right-aligned manually: 2 chars * 5px = 10px)
  local tstr = string.format("%02d", math.max(0, math.ceil(timer_left)))
  local timer_x = W - 12
  if timer_warn and math.floor(anim_frame * 0.15) % 2 == 0 then
    -- Flash: hide text every other blink
  else
    text(s, tstr, timer_x, 1, 1)
  end

  -- Bottom bar
  rectf(s, 0, H - 9, W, 9, 0)

  -- Score
  text(s, "SC:" .. score, 2, H - 8, 1)

  -- Combo
  if combo > 1 and combo_timer > 0 then
    local cstr = "x" .. combo
    text(s, cstr, W/2, H - 8, 1, ALIGN_CENTER)
  end

  -- Progress bar
  local bar_w = 40
  local bar_x = W - bar_w - 2
  local bar_y = H - 7
  rect(s, bar_x, bar_y, bar_w, 5, 1)
  local fill = math.floor((visited_count / total_cells) * (bar_w - 2))
  if fill > 0 then
    rectf(s, bar_x + 1, bar_y + 1, fill, 3, 1)
  end
end

function game_draw()
  local s = screen()
  cls(s, 0)

  -- Apply shake
  if shake > 0 then
    cam_shake(shake)
  end

  draw_board(s)
  draw_hud(s)

  -- Flash effect on level complete
  if flash_timer > 0 and flash_timer % 4 < 2 then
    rectf(s, 0, 0, W, H, 1)
  end

  -- Pause overlay
  if paused then
    rectf(s, W/2 - 30, H/2 - 10, 60, 20, 0)
    rect(s, W/2 - 30, H/2 - 10, 60, 20, 1)
    text(s, "PAUSED", W/2, H/2 - 4, 1, ALIGN_CENTER)
  end

  -- Level complete overlay
  if level_complete then
    rectf(s, W/2 - 50, H/2 - 20, 100, 40, 0)
    rect(s, W/2 - 50, H/2 - 20, 100, 40, 1)
    text(s, "COMPLETE!", W/2, H/2 - 14, 1, ALIGN_CENTER)
    local time_bonus = math.floor(timer_left) * 5
    text(s, "TIME +" .. time_bonus, W/2, H/2 - 4, 1, ALIGN_CENTER)
    text(s, "PERFECT +500", W/2, H/2 + 4, 1, ALIGN_CENTER)
    if level_complete_timer < 60 then
      text(s, "PRESS A", W/2, H/2 + 16, 1, ALIGN_CENTER)
    end
  end

  -- Game over overlay
  if game_over then
    rectf(s, W/2 - 45, H/2 - 22, 90, 44, 0)
    rect(s, W/2 - 45, H/2 - 22, 90, 44, 1)
    if trapped then
      text(s, "TRAPPED!", W/2, H/2 - 16, 1, ALIGN_CENTER)
      text(s, "NO MOVES LEFT", W/2, H/2 - 6, 1, ALIGN_CENTER)
    else
      text(s, "TIME UP!", W/2, H/2 - 16, 1, ALIGN_CENTER)
    end
    text(s, "SCORE:" .. score, W/2, H/2 + 4, 1, ALIGN_CENTER)
    if score > hi_score then
      text(s, "NEW HIGH!", W/2, H/2 + 12, 1, ALIGN_CENTER)
    end
    text(s, "PRESS START", W/2, H/2 + 22, 1, ALIGN_CENTER)
  end
end

------------------------------------------------------------
-- MONO FRAMEWORK HOOKS
------------------------------------------------------------
function _init()
  mode(1)
  local d = date(); math.randomseed(d.ms + d.sec * 1000)
  anim_frame = 0
  score = 0
  hi_score = 0
  level = 1
end

function _start()
  go("title")
end
