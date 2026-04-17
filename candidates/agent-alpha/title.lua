-- Title Screen for GRAVITON

local blink_timer = 0
local star_particles = {}
local logo_y = 0
local intro_done = false
local intro_timer = 0
local idle_timer = 0
local IDLE_THRESHOLD = 90  -- ~3 seconds at 30fps

-- Demo/Attract mode state
local demo_active = false
local demo_timer = 0
-- Demo runs indefinitely until a button is pressed
local demo_grid = {}
local demo_piece = nil
local demo_gravity = 1  -- 1=down
local demo_move_timer = 0
local demo_fall_timer = 0
local DEMO_GRID_W = 8
local DEMO_GRID_H = 10
local DEMO_CELL = 4  -- smaller cells for mini preview
local DEMO_PX_X = 44
local DEMO_PX_Y = 30

local DEMO_SHAPES = {
  { {0,0}, {1,0}, {2,0}, {2,1} },
  { {0,0}, {1,0}, {2,0}, {0,1} },
  { {0,0}, {1,0}, {2,0}, {1,1} },
  { {1,0}, {2,0}, {0,1}, {1,1} },
  { {0,0}, {1,0}, {1,1}, {2,1} },
  { {0,0}, {1,0}, {0,1}, {1,1} },
  { {0,0}, {1,0}, {2,0}, {3,0} },
}
local DEMO_COLORS = {6, 8, 10, 12, 14, 9, 11}

function title_init()
  blink_timer = 0
  intro_timer = 0
  intro_done = false
  logo_y = -30
  idle_timer = 0
  demo_active = false
  demo_timer = 0

  -- Create floating particles for background ambiance
  star_particles = {}
  math.randomseed(42) -- deterministic for consistent look
  for i = 1, 40 do
    star_particles[i] = {
      x = math.random(0, 159),
      y = math.random(0, 119),
      speed = math.random(5, 15) / 10,
      brightness = math.random(2, 8),
      phase = math.random(0, 100) / 10
    }
  end
  math.randomseed(math.floor(time() * 1000))
end

-- Demo helper: initialize demo grid
local function demo_init_grid()
  demo_grid = {}
  for y = 1, DEMO_GRID_H do
    demo_grid[y] = {}
    for x = 1, DEMO_GRID_W do
      demo_grid[y][x] = 0
    end
  end
  demo_gravity = 1
  demo_fall_timer = 0
  demo_move_timer = 0
  demo_piece = nil
end

-- Demo helper: spawn a piece
local function demo_spawn_piece()
  local idx = math.random(1, #DEMO_SHAPES)
  local shape = DEMO_SHAPES[idx]
  local color = DEMO_COLORS[idx]
  local blocks = {}
  for i, b in ipairs(shape) do
    blocks[i] = {b[1], b[2]}
  end
  demo_piece = {
    blocks = blocks,
    color = color,
    x = math.floor((DEMO_GRID_W - 3) / 2) + 1,
    y = 1
  }
  -- Check if spawn blocked
  for _, b in ipairs(demo_piece.blocks) do
    local gx = demo_piece.x + b[1]
    local gy = demo_piece.y + b[2]
    if gx >= 1 and gx <= DEMO_GRID_W and gy >= 1 and gy <= DEMO_GRID_H then
      if demo_grid[gy][gx] ~= 0 then
        -- Grid full, reset
        demo_init_grid()
        demo_spawn_piece()
        return
      end
    end
  end
end

-- Demo helper: check valid position
local function demo_is_valid(p, ox, oy)
  if not p then return false end
  for _, b in ipairs(p.blocks) do
    local gx = p.x + b[1] + ox
    local gy = p.y + b[2] + oy
    if gx < 1 or gx > DEMO_GRID_W or gy < 1 or gy > DEMO_GRID_H then
      return false
    end
    if demo_grid[gy] and demo_grid[gy][gx] ~= 0 then
      return false
    end
  end
  return true
end

-- Demo helper: lock piece into grid
local function demo_lock_piece()
  if not demo_piece then return end
  for _, b in ipairs(demo_piece.blocks) do
    local gx = demo_piece.x + b[1]
    local gy = demo_piece.y + b[2]
    if gy >= 1 and gy <= DEMO_GRID_H and gx >= 1 and gx <= DEMO_GRID_W then
      demo_grid[gy][gx] = demo_piece.color
    end
  end
  -- Check for full rows and clear them
  for y = DEMO_GRID_H, 1, -1 do
    local full = true
    for x = 1, DEMO_GRID_W do
      if demo_grid[y][x] == 0 then full = false; break end
    end
    if full then
      -- Shift rows down
      for yy = y, 2, -1 do
        for x = 1, DEMO_GRID_W do
          demo_grid[yy][x] = demo_grid[yy-1][x]
        end
      end
      for x = 1, DEMO_GRID_W do
        demo_grid[1][x] = 0
      end
      note(0, "G4", 0.06)
    end
  end
  demo_piece = nil
end

-- Demo helper: simple AI move
local function demo_ai_move()
  if not demo_piece then return end
  -- Randomly move left or right, or occasionally rotate gravity
  local r = math.random(1, 10)
  if r <= 3 and demo_is_valid(demo_piece, -1, 0) then
    demo_piece.x = demo_piece.x - 1
  elseif r <= 6 and demo_is_valid(demo_piece, 1, 0) then
    demo_piece.x = demo_piece.x + 1
  elseif r == 7 then
    -- Occasionally rotate gravity direction for visual interest
    demo_gravity = (demo_gravity % 4) + 1
    tone(0, 300, 500, 0.06)
  end
end

-- Demo update
local function demo_update()
  demo_timer = demo_timer + 1

  -- Spawn piece if needed
  if not demo_piece then
    demo_spawn_piece()
  end

  -- AI moves every 10 frames
  demo_move_timer = demo_move_timer + 1
  if demo_move_timer >= 10 then
    demo_move_timer = 0
    demo_ai_move()
  end

  -- Gravity fall every 8 frames
  demo_fall_timer = demo_fall_timer + 1
  if demo_fall_timer >= 8 then
    demo_fall_timer = 0
    if demo_piece then
      local gdx, gdy = 0, 0
      if demo_gravity == 1 then gdy = 1
      elseif demo_gravity == 2 then gdx = -1
      elseif demo_gravity == 3 then gdy = -1
      elseif demo_gravity == 4 then gdx = 1
      end
      if demo_is_valid(demo_piece, gdx, gdy) then
        demo_piece.x = demo_piece.x + gdx
        demo_piece.y = demo_piece.y + gdy
      else
        demo_lock_piece()
      end
    end
  end
end

-- 7-segment clock display
-- Segment layout for a digit ~7px wide x 11px tall, thickness 2px:
--  _a_
-- |   |
-- f   b
-- |_g_|
-- |   |
-- e   c
-- |_d_|
local SEG_PATTERNS = {
  -- 0-9, each entry: {a,b,c,d,e,f,g}
  {1,1,1,1,1,1,0}, -- 0
  {0,1,1,0,0,0,0}, -- 1
  {1,1,0,1,1,0,1}, -- 2
  {1,1,1,1,0,0,1}, -- 3
  {0,1,1,0,0,1,1}, -- 4
  {1,0,1,1,0,1,1}, -- 5
  {1,0,1,1,1,1,1}, -- 6
  {1,1,1,0,0,0,0}, -- 7
  {1,1,1,1,1,1,1}, -- 8
  {1,1,1,1,0,1,1}, -- 9
}

local function draw_seg_digit(s, x, y, digit, color)
  local pat = SEG_PATTERNS[digit + 1]
  if not pat then return end
  -- Segment rectangles: {x_off, y_off, w, h}
  -- a: top horizontal
  if pat[1] == 1 then rectf(s, x+1, y, 5, 2, color) end
  -- b: top-right vertical
  if pat[2] == 1 then rectf(s, x+5, y+1, 2, 4, color) end
  -- c: bottom-right vertical
  if pat[3] == 1 then rectf(s, x+5, y+6, 2, 4, color) end
  -- d: bottom horizontal
  if pat[4] == 1 then rectf(s, x+1, y+9, 5, 2, color) end
  -- e: bottom-left vertical
  if pat[5] == 1 then rectf(s, x, y+6, 2, 4, color) end
  -- f: top-left vertical
  if pat[6] == 1 then rectf(s, x, y+1, 2, 4, color) end
  -- g: middle horizontal
  if pat[7] == 1 then rectf(s, x+1, y+4, 5, 2, color) end
end

local function draw_clock(s)
  local d = date()
  local h = d.hour
  local m = d.min
  local color = 4  -- dim gray
  local cx = 160 - 42  -- top-right area
  local cy = 2

  -- Draw HH:MM
  draw_seg_digit(s, cx, cy, math.floor(h / 10), color)
  draw_seg_digit(s, cx + 9, cy, h % 10, color)

  -- Blinking colon (two dots): on for 30 frames, off for 30 frames
  if math.floor(frame() / 30) % 2 == 0 then
    rectf(s, cx + 17, cy + 3, 2, 2, color)
    rectf(s, cx + 17, cy + 7, 2, 2, color)
  end

  draw_seg_digit(s, cx + 21, cy, math.floor(m / 10), color)
  draw_seg_digit(s, cx + 30, cy, m % 10, color)
end

-- Demo draw (mini playfield)
local function demo_draw(s)
  -- Dim background
  rectf(s, 0, 0, 160, 120, 0)

  -- Draw mini grid background
  rectf(s, DEMO_PX_X - 1, DEMO_PX_Y - 1,
    DEMO_GRID_W * DEMO_CELL + 2, DEMO_GRID_H * DEMO_CELL + 2, 2)
  rectf(s, DEMO_PX_X, DEMO_PX_Y,
    DEMO_GRID_W * DEMO_CELL, DEMO_GRID_H * DEMO_CELL, 1)

  -- Draw placed blocks
  for y = 1, DEMO_GRID_H do
    for x = 1, DEMO_GRID_W do
      if demo_grid[y][x] ~= 0 then
        rectf(s, DEMO_PX_X + (x-1)*DEMO_CELL, DEMO_PX_Y + (y-1)*DEMO_CELL,
          DEMO_CELL, DEMO_CELL, demo_grid[y][x])
      end
    end
  end

  -- Draw current piece
  if demo_piece then
    for _, b in ipairs(demo_piece.blocks) do
      local gx = demo_piece.x + b[1]
      local gy = demo_piece.y + b[2]
      if gx >= 1 and gx <= DEMO_GRID_W and gy >= 1 and gy <= DEMO_GRID_H then
        rectf(s, DEMO_PX_X + (gx-1)*DEMO_CELL, DEMO_PX_Y + (gy-1)*DEMO_CELL,
          DEMO_CELL, DEMO_CELL, demo_piece.color)
      end
    end
  end

  -- Gravity arrow label
  local grav_arrows = {"v", "<", "^", ">"}
  text(s, "GRAV:" .. grav_arrows[demo_gravity],
    DEMO_PX_X + DEMO_GRID_W * DEMO_CELL + 4, DEMO_PX_Y + 2, 8)

  -- "DEMO" label
  text(s, "DEMO", 80, DEMO_PX_Y - 8, 6, ALIGN_HCENTER)

  -- Blinking PRESS START overlay
  if math.floor(frame() / 20) % 2 == 0 then
    text(s, "PRESS START", 80, DEMO_PX_Y + DEMO_GRID_H * DEMO_CELL + 8, 15, ALIGN_HCENTER)
  end

  -- Title stays visible at top
  draw_title_logo(s, 4)

  -- 7-segment clock overlay (demo mode only)
  draw_clock(s)
end

function title_update()
  intro_timer = intro_timer + 1

  -- Check for any button press or touch to exit demo, or START to begin game
  if intro_done and demo_active then
    if btnp("start") or btnp("a") or btnp("b") or btnp("select")
      or btnp("left") or btnp("right") or btnp("up") or btnp("down")
      or touch_start() then
      demo_active = false
      idle_timer = 0
      demo_timer = 0
      note(0, "C5", 0.1)
      return
    end
  elseif intro_done and (btnp("start") or touch_start()) then
    note(0, "C5", 0.1)
    note(1, "E5", 0.1)
    go("game")
    return
  end

  -- Slide logo in
  if not intro_done then
    logo_y = logo_y + 2
    if logo_y >= 18 then
      logo_y = 18
      intro_done = true
    end
  end

  blink_timer = blink_timer + 1

  -- Update particles - slow drift downward (like gravity)
  for _, p in ipairs(star_particles) do
    p.y = p.y + p.speed * 0.3
    if p.y > 120 then
      p.y = -2
      p.x = math.random(0, 159)
    end
    -- Pulse brightness
    p.brightness = 3 + math.floor(math.sin(time() * 2 + p.phase) * 2.5)
  end

  -- Track idle time for attract mode
  if intro_done and not demo_active then
    idle_timer = idle_timer + 1
    -- Check for any input to reset idle timer
    if btn("left") or btn("right") or btn("up") or btn("down")
      or btn("a") or btn("b") or btn("select") or touch() then
      idle_timer = 0
    end
    if idle_timer >= IDLE_THRESHOLD then
      -- Activate demo mode
      demo_active = true
      demo_timer = 0
      demo_init_grid()
      idle_timer = 0
    end
  end

  -- Update demo if active
  if demo_active then
    demo_update()
  end
end

function title_draw()
  local s = screen()
  cls(s, 0)

  -- Draw particles
  for _, p in ipairs(star_particles) do
    pix(s, math.floor(p.x), math.floor(p.y), p.brightness)
  end

  if demo_active then
    -- Draw demo mode
    demo_draw(s)
    return
  end

  -- Draw decorative border
  rect(s, 2, 2, 156, 116, 3)
  rect(s, 4, 4, 152, 112, 2)

  -- Title: GRAVITON
  draw_title_logo(s, logo_y)

  if intro_done then
    -- Subtitle
    text(s, "GRAVITY PUZZLE", 80, logo_y + 22, 8, ALIGN_HCENTER)

    -- Blinking start prompt
    if math.floor(blink_timer / 15) % 2 == 0 then
      text(s, "PRESS START", 80, 78, 15, ALIGN_HCENTER)
    end

    -- Instructions hint
    text(s, "D-PAD:MOVE  A:ROTATE GRAVITY", 80, 95, 6, ALIGN_HCENTER)
    text(s, "B:HARD DROP", 80, 103, 6, ALIGN_HCENTER)

    -- High score
    if high_score > 0 then
      text(s, "HI-SCORE: " .. high_score, 80, 110, 10, ALIGN_HCENTER)
    end
  end
end

function draw_title_logo(s, y)
  -- "GRAVITON" in large block letters
  local letters = {
    -- G
    {rects = {{0,0,5,1},{0,0,1,5},{0,4,5,1},{4,2,1,3},{2,2,3,1}}},
    -- R
    {rects = {{0,0,1,5},{0,0,4,1},{4,0,1,2},{0,2,4,1},{2,2,1,1},{3,3,1,1},{4,4,1,1}}},
    -- A
    {rects = {{0,1,1,4},{4,1,1,4},{0,0,5,1},{0,2,5,1}}},
    -- V
    {rects = {{0,0,1,3},{4,0,1,3},{1,3,1,1},{3,3,1,1},{2,4,1,1}}},
    -- I
    {rects = {{0,0,5,1},{0,4,5,1},{2,0,1,5}}},
    -- T
    {rects = {{0,0,5,1},{2,0,1,5}}},
    -- O
    {rects = {{0,0,5,1},{0,4,5,1},{0,0,1,5},{4,0,1,5}}},
    -- N
    {rects = {{0,0,1,5},{4,0,1,5},{1,1,1,1},{2,2,1,1},{3,3,1,1}}},
  }

  local total_w = #letters * 7 - 2
  local start_x = math.floor((160 - total_w * 2) / 2)

  for i, letter in ipairs(letters) do
    local lx = start_x + (i - 1) * 14
    -- Shadow
    for _, r in ipairs(letter.rects) do
      rectf(s, lx + r[1]*2 + 1, y + r[2]*2 + 1, r[3]*2, r[4]*2, 4)
    end
    -- Main letter
    local c = 10 + math.floor(math.sin(time() * 1.5 + i * 0.5) * 2.5)
    for _, r in ipairs(letter.rects) do
      rectf(s, lx + r[1]*2, y + r[2]*2, r[3]*2, r[4]*2, c)
    end
  end
end
