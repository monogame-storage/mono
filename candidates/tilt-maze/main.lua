-- TILT MAZE
-- Tilt your device to roll a ball through procedural mazes!
-- A motion-controlled arcade puzzle for Mono (1-bit).

------------------------------------------------------------
-- CONSTANTS
------------------------------------------------------------
local W = 160
local H = 120

-- Physics
local ACCEL = 120        -- pixels/sec^2 per unit tilt
local MAX_SPEED = 60     -- pixels/sec max velocity
local FRICTION = 0.92    -- velocity multiplier per frame
local BOUNCE = 0.5       -- velocity damping on wall hit
local DEADZONE = 0.05    -- tilt dead-zone
local DT = 1/30          -- fixed timestep (30fps)

-- Ball
local BALL_R = 2         -- ball radius in pixels

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

-- Level definitions: {grid_cols, grid_rows, time_limit}
local LEVELS = {
  {7,  5,  30},
  {9,  7,  35},
  {11, 8,  40},
  {13, 9,  45},
  {15, 10, 50},
}

------------------------------------------------------------
-- STATE
------------------------------------------------------------
-- Maze
local maze = {}        -- maze[r][c] = {n=bool, s=bool, e=bool, w=bool} (wall flags)
local maze_cols = 7
local maze_rows = 5
local cell_w = 0
local cell_h = 0
local maze_ox = 0      -- maze offset x (pixels)
local maze_oy = 0      -- maze offset y (pixels)
local maze_pw = 0      -- maze pixel width
local maze_ph = 0      -- maze pixel height

-- Ball
local ball_x = 0
local ball_y = 0
local vel_x = 0
local vel_y = 0
local trail = {}       -- breadcrumb trail {{x,y}, ...}
local trail_timer = 0
local bounce_count = 0

-- Exit
local exit_x = 0
local exit_y = 0
local exit_r = 0       -- exit cell row
local exit_c = 0       -- exit cell col

-- Game state
local score = 0
local hi_score = 0
local level = 1
local timer_left = 30
local timer_warn = false
local game_over = false
local level_complete = false
local level_complete_timer = 0
local paused = false

local anim_frame = 0
local flash_timer = 0
local shake = 0
local has_motion = false

-- Demo / attract mode
local demo_mode = false
local demo_dir = 0       -- 0=N,1=E,2=S,3=W for wall-following
local demo_target_x = 0
local demo_target_y = 0
local demo_timer = 0
local demo_solving = false

-- Title
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
  if bit_check(segs, 1)  then rectf(s, ox+t, oy, sw, t, col) end
  if bit_check(segs, 2)  then rectf(s, ox+t+sw, oy+t, t, sh, col) end
  if bit_check(segs, 4)  then rectf(s, ox+t+sw, oy+t+sh+t, t, sh, col) end
  if bit_check(segs, 8)  then rectf(s, ox+t, oy+t+sh+t+sh, sw, t, col) end
  if bit_check(segs, 16) then rectf(s, ox, oy+t+sh+t, t, sh, col) end
  if bit_check(segs, 32) then rectf(s, ox, oy+t, t, sh, col) end
  if bit_check(segs, 64) then rectf(s, ox+t, oy+t+sh, sw, t, col) end
end

local function draw_clock(s, cx, cy, col)
  if not date then return end
  local d = date()
  local hh = d.hour
  local mm = d.min
  local dw = 6
  draw_seg7(s, math.floor(hh/10), cx, cy, col)
  draw_seg7(s, hh%10, cx+dw, cy, col)
  -- colon blink
  local blink = math.floor(anim_frame / 15) % 2
  if blink == 0 then
    pix(s, cx+dw*2+1, cy+3, col)
    pix(s, cx+dw*2+1, cy+6, col)
  end
  draw_seg7(s, math.floor(mm/10), cx+dw*2+3, cy, col)
  draw_seg7(s, mm%10, cx+dw*2+3+dw, cy, col)
end

local function format_time(t)
  local sec = math.max(0, math.ceil(t))
  return string.format("%d", sec)
end

------------------------------------------------------------
-- SOUND EFFECTS
------------------------------------------------------------
local function sfx_bounce()
  if noise then noise(4, 0.6) end
end

local function sfx_complete()
  if note then note(0, "C4", 0.5) end
  if note then note(1, "E4", 0.5) end
  if note then note(2, "G4", 0.5) end
  if note then note(3, "C5", 0.7) end
end

local function sfx_gameover()
  if note then note(0, "E4", 0.5) end
  if note then note(1, "C4", 0.5) end
  if note then note(2, "A3", 0.5) end
end

local function sfx_tick()
  if noise then noise(1, 0.3) end
end

local function sfx_start()
  if note then note(0, "C5", 0.5) end
  if note then note(1, "E5", 0.5) end
end

local function sfx_roll()
  local spd = math.sqrt(vel_x*vel_x + vel_y*vel_y)
  if spd > 5 then
    local freq = 80 + spd * 2
    if tone then tone(0, freq, freq + 20, 0.1) end
  end
end

------------------------------------------------------------
-- MAZE GENERATION (Recursive Backtracker / DFS)
------------------------------------------------------------
local function generate_maze(cols, rows)
  local grid = {}
  for r = 1, rows do
    grid[r] = {}
    for c = 1, cols do
      grid[r][c] = {n=true, s=true, e=true, w=true, visited=false}
    end
  end

  local stack = {}
  local cr, cc = 1, 1
  grid[cr][cc].visited = true
  local visited_count = 1
  local total = cols * rows

  -- Direction offsets: {dr, dc, wall_from, wall_to}
  local dirs = {
    {-1, 0, "n", "s"},  -- north
    { 1, 0, "s", "n"},  -- south
    { 0, 1, "e", "w"},  -- east
    { 0,-1, "w", "e"},  -- west
  }

  while visited_count < total do
    -- Find unvisited neighbors
    local neighbors = {}
    for _, d in ipairs(dirs) do
      local nr, nc = cr + d[1], cc + d[2]
      if nr >= 1 and nr <= rows and nc >= 1 and nc <= cols and not grid[nr][nc].visited then
        neighbors[#neighbors+1] = {nr, nc, d[3], d[4]}
      end
    end

    if #neighbors > 0 then
      -- Pick random neighbor
      local chosen = neighbors[math.random(1, #neighbors)]
      local nr, nc = chosen[1], chosen[2]
      -- Remove walls
      grid[cr][cc][chosen[3]] = false
      grid[nr][nc][chosen[4]] = false
      -- Push current to stack and move
      stack[#stack+1] = {cr, cc}
      cr, cc = nr, nc
      grid[cr][cc].visited = true
      visited_count = visited_count + 1
    else
      -- Backtrack
      local prev = stack[#stack]
      stack[#stack] = nil
      cr, cc = prev[1], prev[2]
    end
  end

  return grid
end

------------------------------------------------------------
-- MAZE LAYOUT
------------------------------------------------------------
local function setup_maze(lv)
  local def = LEVELS[math.min(lv, #LEVELS)]
  maze_cols = def[1]
  maze_rows = def[2]
  timer_left = def[3]
  timer_warn = false

  -- Calculate cell size to fit in screen with HUD margin
  local avail_w = W - 8
  local avail_h = H - 16  -- top HUD
  cell_w = math.floor(avail_w / maze_cols)
  cell_h = math.floor(avail_h / maze_rows)
  -- Keep square-ish cells
  local csz = math.min(cell_w, cell_h)
  cell_w = csz
  cell_h = csz

  maze_pw = maze_cols * cell_w
  maze_ph = maze_rows * cell_h
  maze_ox = math.floor((W - maze_pw) / 2)
  maze_oy = math.floor((H - maze_ph) / 2) + 5

  maze = generate_maze(maze_cols, maze_rows)

  -- Ball at center of cell (1,1)
  ball_x = maze_ox + math.floor(cell_w / 2)
  ball_y = maze_oy + math.floor(cell_h / 2)
  vel_x = 0
  vel_y = 0
  trail = {}
  trail_timer = 0
  bounce_count = 0

  -- Exit at bottom-right cell
  exit_r = maze_rows
  exit_c = maze_cols
  exit_x = maze_ox + (exit_c - 1) * cell_w + math.floor(cell_w / 2)
  exit_y = maze_oy + (exit_r - 1) * cell_h + math.floor(cell_h / 2)
end

------------------------------------------------------------
-- CELL / COLLISION HELPERS
------------------------------------------------------------
local function pixel_to_cell(px, py)
  local c = math.floor((px - maze_ox) / cell_w) + 1
  local r = math.floor((py - maze_oy) / cell_h) + 1
  return clamp(r, 1, maze_rows), clamp(c, 1, maze_cols)
end

local function cell_left(c)   return maze_ox + (c-1) * cell_w end
local function cell_right(c)  return maze_ox + c * cell_w end
local function cell_top(r)    return maze_oy + (r-1) * cell_h end
local function cell_bottom(r) return maze_oy + r * cell_h end

local function ball_collide()
  -- Get current cell
  local r, c = pixel_to_cell(ball_x, ball_y)
  local cell = maze[r] and maze[r][c]
  if not cell then return end

  local br = BALL_R
  local bounced = false

  -- Check north wall
  if cell.n and ball_y - br < cell_top(r) then
    ball_y = cell_top(r) + br
    vel_y = -vel_y * BOUNCE
    bounced = true
  end
  -- Check south wall
  if cell.s and ball_y + br > cell_bottom(r) then
    ball_y = cell_bottom(r) - br
    vel_y = -vel_y * BOUNCE
    bounced = true
  end
  -- Check west wall
  if cell.w and ball_x - br < cell_left(c) then
    ball_x = cell_left(c) + br
    vel_x = -vel_x * BOUNCE
    bounced = true
  end
  -- Check east wall
  if cell.e and ball_x + br > cell_right(c) then
    ball_x = cell_right(c) - br
    vel_x = -vel_x * BOUNCE
    bounced = true
  end

  -- Also check maze outer bounds
  if ball_x - br < maze_ox then
    ball_x = maze_ox + br
    vel_x = -vel_x * BOUNCE
    bounced = true
  end
  if ball_x + br > maze_ox + maze_pw then
    ball_x = maze_ox + maze_pw - br
    vel_x = -vel_x * BOUNCE
    bounced = true
  end
  if ball_y - br < maze_oy then
    ball_y = maze_oy + br
    vel_y = -vel_y * BOUNCE
    bounced = true
  end
  if ball_y + br > maze_oy + maze_ph then
    ball_y = maze_oy + maze_ph - br
    vel_y = -vel_y * BOUNCE
    bounced = true
  end

  if bounced then
    bounce_count = bounce_count + 1
    sfx_bounce()
  end
end

-- Check if ball reached exit
local function check_exit()
  local dx = ball_x - exit_x
  local dy = ball_y - exit_y
  local dist = math.sqrt(dx*dx + dy*dy)
  return dist < cell_w * 0.4
end

------------------------------------------------------------
-- DEMO AI (wall-following, right-hand rule)
------------------------------------------------------------
local function demo_pick_target()
  -- Simple pathfinding: move toward exit using BFS
  local sr, sc = pixel_to_cell(ball_x, ball_y)
  local er, ec = exit_r, exit_c

  -- BFS to find path
  local visited = {}
  for r = 1, maze_rows do
    visited[r] = {}
  end
  local queue = {{sr, sc, nil}}
  visited[sr][sc] = true
  local parent = {}  -- parent[r*1000+c] = {pr, pc}

  local dirs = {
    {-1, 0, "n"},  -- north
    { 1, 0, "s"},  -- south
    { 0, 1, "e"},  -- east
    { 0,-1, "w"},  -- west
  }

  local found = false
  local qi = 1
  while qi <= #queue do
    local cur = queue[qi]
    qi = qi + 1
    local cr, cc = cur[1], cur[2]

    if cr == er and cc == ec then
      found = true
      break
    end

    for _, d in ipairs(dirs) do
      local nr, nc = cr + d[1], cc + d[2]
      if nr >= 1 and nr <= maze_rows and nc >= 1 and nc <= maze_cols then
        if not visited[nr] then visited[nr] = {} end
        if not visited[nr][nc] and not maze[cr][cc][d[3]] then
          visited[nr][nc] = true
          parent[nr*1000+nc] = {cr, cc}
          queue[#queue+1] = {nr, nc}
        end
      end
    end
  end

  -- Reconstruct path and get next step
  if found then
    local path = {}
    local cr, cc = er, ec
    while cr ~= sr or cc ~= sc do
      path[#path+1] = {cr, cc}
      local p = parent[cr*1000+cc]
      if not p then break end
      cr, cc = p[1], p[2]
    end
    -- Path is reversed, take the last element (first step)
    if #path > 0 then
      local next_cell = path[#path]
      demo_target_x = maze_ox + (next_cell[2] - 1) * cell_w + math.floor(cell_w / 2)
      demo_target_y = maze_oy + (next_cell[1] - 1) * cell_h + math.floor(cell_h / 2)
      return
    end
  end

  -- Fallback: aim at exit
  demo_target_x = exit_x
  demo_target_y = exit_y
end

------------------------------------------------------------
-- DRAWING: MAZE
------------------------------------------------------------
local function draw_maze(s)
  for r = 1, maze_rows do
    for c = 1, maze_cols do
      local cell = maze[r][c]
      local x = maze_ox + (c-1) * cell_w
      local y = maze_oy + (r-1) * cell_h

      -- Draw walls
      if cell.n then
        line(s, x, y, x + cell_w, y, 1)
      end
      if cell.s then
        line(s, x, y + cell_h, x + cell_w, y + cell_h, 1)
      end
      if cell.w then
        line(s, x, y, x, y + cell_h, 1)
      end
      if cell.e then
        line(s, x + cell_w, y, x + cell_w, y + cell_h, 1)
      end
    end
  end
end

local function draw_exit(s)
  -- Blinking exit marker
  local blink = math.floor(anim_frame / 8) % 2
  local esz = math.max(2, math.floor(cell_w / 3))

  if blink == 0 then
    -- Filled square
    rectf(s, exit_x - esz, exit_y - esz, esz*2+1, esz*2+1, 1)
  else
    -- Outline square
    rect(s, exit_x - esz, exit_y - esz, esz*2+1, esz*2+1, 1)
  end
end

local function draw_trail(s)
  for i = 1, #trail do
    local t = trail[i]
    pix(s, t[1], t[2], 1)
  end
end

local function draw_ball(s)
  circf(s, ball_x, ball_y, BALL_R, 1)
end

local function draw_hud(s, show_demo)
  -- Top bar
  if show_demo then
    text(s, "DEMO", 2, 1, 1)
    draw_clock(s, W - 30, 1, 1)
  else
    text(s, "LV" .. level, 2, 1, 1)
    text(s, format_time(timer_left), W/2, 1, 1, ALIGN_CENTER)
    text(s, "" .. score, W - 4, 1, 1)
  end
end

------------------------------------------------------------
-- TITLE SCENE
------------------------------------------------------------
function title_init()
  title_anim = 0
end

function title_update()
  title_anim = title_anim + 1
  anim_frame = anim_frame + 1
  has_motion = motion_enabled and motion_enabled() == 1

  if btnp("start") or btnp("a") then
    sfx_start()
    score = 0
    level = 1
    setup_maze(level)
    game_over = false
    level_complete = false
    go("game")
    return
  end

  if touch_start and touch_start() then
    sfx_start()
    score = 0
    level = 1
    setup_maze(level)
    game_over = false
    level_complete = false
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

  -- Title
  text(s, "TILT MAZE", W/2, 12, 1, ALIGN_CENTER)

  -- Animated ball rolling back and forth
  local bx = W/2 + math.floor(math.sin(title_anim * 0.05) * 30)
  local by = 30
  circf(s, bx, by, 3, 1)

  -- Small maze decoration
  local mx, my = W/2 - 20, 38
  rect(s, mx, my, 40, 30, 1)
  -- Internal walls
  line(s, mx+10, my, mx+10, my+20, 1)
  line(s, mx+20, my+10, mx+20, my+30, 1)
  line(s, mx+30, my, mx+30, my+20, 1)
  line(s, mx, my+15, mx+10, my+15, 1)
  line(s, mx+20, my+15, mx+30, my+15, 1)

  -- Arrow showing tilt
  local ax = W/2
  local ay = 78
  local tilt_off = math.floor(math.sin(title_anim * 0.08) * 6)
  line(s, ax - 10, ay, ax + 10, ay, 1)
  line(s, ax + tilt_off, ay - 4, ax + tilt_off, ay + 4, 1)
  circf(s, ax + tilt_off, ay, 2, 1)

  -- Instructions
  if has_motion then
    text(s, "TILT TO ROLL", W/2, 88, 1, ALIGN_CENTER)
  else
    text(s, "D-PAD TO ROLL", W/2, 88, 1, ALIGN_CENTER)
  end

  local blink = math.floor(title_anim * 0.06) % 2
  if blink == 0 then
    text(s, "PRESS START", W/2, 100, 1, ALIGN_CENTER)
  end

  -- High score
  if hi_score > 0 then
    text(s, "HI:" .. hi_score, W/2, 112, 1, ALIGN_CENTER)
  end
end

------------------------------------------------------------
-- DEMO SCENE
------------------------------------------------------------
function demo_init()
  demo_mode = true
  local lv = math.random(1, 3)
  setup_maze(lv)
  demo_solving = true
  demo_timer = 0
  demo_pick_target()
end

function demo_update()
  anim_frame = anim_frame + 1
  demo_timer = demo_timer + 1

  -- Any input exits demo
  if btnp("start") or btnp("a") or btnp("b") or (touch_start and touch_start()) then
    demo_mode = false
    go("title")
    return
  end

  -- AI: steer ball toward target
  local dx = demo_target_x - ball_x
  local dy = demo_target_y - ball_y
  local dist = math.sqrt(dx*dx + dy*dy)

  if dist > 2 then
    local tx = clamp(dx / dist, -1, 1) * 0.7
    local ty = clamp(dy / dist, -1, 1) * 0.7
    vel_x = vel_x + tx * ACCEL * DT
    vel_y = vel_y + ty * ACCEL * DT
  else
    -- Reached target, pick next
    demo_pick_target()
  end

  -- Apply friction
  vel_x = vel_x * FRICTION
  vel_y = vel_y * FRICTION

  -- Clamp speed
  local spd = math.sqrt(vel_x*vel_x + vel_y*vel_y)
  if spd > MAX_SPEED then
    vel_x = vel_x / spd * MAX_SPEED
    vel_y = vel_y / spd * MAX_SPEED
  end

  -- Move ball
  ball_x = ball_x + vel_x * DT
  ball_y = ball_y + vel_y * DT

  -- Collide
  ball_collide()

  -- Trail
  trail_timer = trail_timer + 1
  if trail_timer >= 4 then
    trail_timer = 0
    trail[#trail+1] = {math.floor(ball_x), math.floor(ball_y)}
    if #trail > 80 then table.remove(trail, 1) end
  end

  -- Check exit
  if check_exit() then
    -- Restart demo with new maze
    demo_init()
  end
end

function demo_draw()
  local s = screen()
  cls(s, 0)

  draw_trail(s)
  draw_maze(s)
  draw_exit(s)
  draw_ball(s)

  -- HUD
  text(s, "DEMO", 2, 1, 1)
  draw_clock(s, W - 30, 1, 1)
end

------------------------------------------------------------
-- GAME SCENE
------------------------------------------------------------
function game_init()
  game_over = false
  level_complete = false
  paused = false
end

function game_update()
  anim_frame = anim_frame + 1

  -- Pause
  if btnp("start") and not game_over and not level_complete then
    paused = not paused
    return
  end
  if paused then return end

  -- Level complete animation
  if level_complete then
    level_complete_timer = level_complete_timer - 1
    if level_complete_timer <= 0 then
      level = level + 1
      setup_maze(level)
      level_complete = false
    end
    return
  end

  -- Game over: wait for restart
  if game_over then
    if btnp("a") or btnp("start") or (touch_start and touch_start()) then
      go("title")
    end
    return
  end

  -- Timer
  timer_left = timer_left - DT
  if timer_left <= 5 and not timer_warn then
    timer_warn = true
  end
  if timer_warn and math.floor(timer_left * 2) ~= math.floor((timer_left + DT) * 2) then
    sfx_tick()
  end
  if timer_left <= 0 then
    timer_left = 0
    game_over = true
    if score > hi_score then hi_score = score end
    sfx_gameover()
    cam_shake(6)
    return
  end

  -- Input: motion primary, axis fallback
  local tx, ty = 0, 0
  has_motion = motion_enabled and motion_enabled() == 1

  if has_motion then
    tx = motion_x()
    ty = motion_y()
  end

  -- Always layer axis on top (for d-pad fallback or combined input)
  local ax_x = axis_x()
  local ax_y = axis_y()
  if math.abs(ax_x) > 0.1 then tx = ax_x end
  if math.abs(ax_y) > 0.1 then ty = ax_y end

  -- Dead-zone
  if math.abs(tx) < DEADZONE then tx = 0 end
  if math.abs(ty) < DEADZONE then ty = 0 end

  -- Apply acceleration
  vel_x = vel_x + tx * ACCEL * DT
  vel_y = vel_y + ty * ACCEL * DT

  -- Friction
  vel_x = vel_x * FRICTION
  vel_y = vel_y * FRICTION

  -- Clamp speed
  local spd = math.sqrt(vel_x*vel_x + vel_y*vel_y)
  if spd > MAX_SPEED then
    vel_x = vel_x / spd * MAX_SPEED
    vel_y = vel_y / spd * MAX_SPEED
  end

  -- Move ball
  ball_x = ball_x + vel_x * DT
  ball_y = ball_y + vel_y * DT

  -- Collide with walls
  ball_collide()

  -- Roll sound (every few frames)
  if anim_frame % 6 == 0 then
    sfx_roll()
  end

  -- Trail
  trail_timer = trail_timer + 1
  if trail_timer >= 3 then
    trail_timer = 0
    trail[#trail+1] = {math.floor(ball_x), math.floor(ball_y)}
    if #trail > 100 then table.remove(trail, 1) end
  end

  -- Check exit
  if check_exit() then
    -- Score
    local time_bonus = math.floor(timer_left) * 10
    local lvl_base = level * 100
    local speed_bonus = 0
    local def = LEVELS[math.min(level, #LEVELS)]
    if timer_left > def[3] / 2 then speed_bonus = 200 end
    local bounce_bonus = 0
    if bounce_count < 5 then bounce_bonus = 50 end

    local level_score = lvl_base + time_bonus + speed_bonus + bounce_bonus
    score = score + level_score

    if score > hi_score then hi_score = score end

    level_complete = true
    level_complete_timer = 60  -- 2 seconds
    flash_timer = 30
    sfx_complete()
    cam_shake(3)
  end

  -- Shake decay
  if shake > 0 then shake = shake - 1 end
end

function game_draw()
  local s = screen()
  cls(s, 0)

  -- Level complete flash
  if level_complete then
    if math.floor(flash_timer) % 4 < 2 then
      cls(s, 1)
      draw_maze(s)
      -- Invert ball
      circf(s, ball_x, ball_y, BALL_R, 0)
    else
      draw_trail(s)
      draw_maze(s)
      draw_exit(s)
      draw_ball(s)
    end
    flash_timer = flash_timer - 1

    text(s, "LEVEL CLEAR!", W/2, H/2 - 10, 1, ALIGN_CENTER)
    local def = LEVELS[math.min(level, #LEVELS)]
    local tb = math.floor(timer_left) * 10
    text(s, "TIME +" .. tb, W/2, H/2 + 2, 1, ALIGN_CENTER)

    -- HUD
    text(s, "LV" .. level, 2, 1, 1)
    text(s, "" .. score, W - 4, 1, 1)
    return
  end

  -- Game over
  if game_over then
    draw_trail(s)
    draw_maze(s)
    draw_ball(s)

    -- Dark overlay effect (checkerboard)
    for py = 0, H-1, 2 do
      for px = 0, W-1, 2 do
        pix(s, px, py, 0)
      end
    end

    text(s, "TIME UP!", W/2, H/2 - 14, 1, ALIGN_CENTER)
    text(s, "SCORE:" .. score, W/2, H/2 - 2, 1, ALIGN_CENTER)
    if score >= hi_score and score > 0 then
      text(s, "NEW BEST!", W/2, H/2 + 10, 1, ALIGN_CENTER)
    end
    local blink = math.floor(anim_frame * 0.06) % 2
    if blink == 0 then
      text(s, "PRESS START", W/2, H/2 + 24, 1, ALIGN_CENTER)
    end
    return
  end

  -- Pause
  if paused then
    draw_maze(s)
    draw_ball(s)
    text(s, "PAUSED", W/2, H/2, 1, ALIGN_CENTER)
    return
  end

  -- Normal gameplay
  draw_trail(s)
  draw_maze(s)
  draw_exit(s)
  draw_ball(s)

  -- HUD
  text(s, "LV" .. level, 2, 1, 1)

  -- Timer (flash if warning)
  if timer_warn then
    local tw_blink = math.floor(anim_frame / 4) % 2
    if tw_blink == 0 then
      text(s, format_time(timer_left), W/2, 1, 1, ALIGN_CENTER)
    end
  else
    text(s, format_time(timer_left), W/2, 1, 1, ALIGN_CENTER)
  end

  text(s, "" .. score, W - 4, 1, 1)

  -- Tilt indicator (small crosshair showing current tilt direction)
  if has_motion then
    local ix = W - 12
    local iy = H - 12
    rect(s, ix - 5, iy - 5, 11, 11, 1)
    local mx = motion_x()
    local my = motion_y()
    local dx = math.floor(mx * 4)
    local dy = math.floor(my * 4)
    pix(s, ix + dx, iy + dy, 1)
  end
end

------------------------------------------------------------
-- MONO FRAMEWORK HOOKS
------------------------------------------------------------
function _init()
  mode(1)
  if date then
    local d = date()
    math.randomseed(d.ms + d.sec * 1000)
  else
    math.randomseed(os.time and os.time() or 0)
  end
  anim_frame = 0
  score = 0
  hi_score = 0
  level = 1
  has_motion = false
end

function _start()
  go("title")
end
