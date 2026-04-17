-- THE DARK ROOM: Sound Navigator
-- Agent 08 — Navigate by sound alone
-- You are blind. Sound is your eyes.

----------------------------------------------------------------
-- CONSTANTS
----------------------------------------------------------------
local W, H = 160, 120
local TILE = 8
local COLS, ROWS = 20, 15  -- 160/8, 120/8
local SONAR_COOLDOWN = 15
local SONAR_MAX_RADIUS = 60
local SONAR_SPEED = 2.5
local MOVE_DELAY = 4

-- Colors (2-bit: 0=black, 1=dark, 2=light, 3=white)
local C_BLACK = 0
local C_DARK = 1
local C_LIGHT = 2
local C_WHITE = 3

-- Tile types
local T_EMPTY = 0
local T_WALL = 1
local T_KEY = 2
local T_DOOR = 3
local T_EXIT = 4
local T_DANGER = 5
local T_HINT = 6

-- Sound channels
local CH_SONAR = 0
local CH_OBJECT = 1
local CH_AMBIENT = 2
local CH_FOOTSTEP = 3

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local scene = "title"
local s = nil
local frame = 0
local title_pulse = 0
local paused = false

-- Player
local px, py = 2, 7  -- tile coords
local move_timer = 0
local has_key = false
local sonar_timer = 0
local sonar_radius = 0
local sonar_active = false
local ping_objects = {}  -- objects revealed by last ping

-- Rooms
local current_room = 1
local room_map = {}
local room_objects = {}

-- Particles (sonar ring dots)
local ring_particles = {}

-- Demo mode
local demo_mode = false
local demo_timer = 0
local demo_path = {}
local demo_step = 1
local demo_ping_timer = 0

-- Ambient
local ambient_timer = 0
local heartbeat_timer = 0

-- Hint text
local hint_text = ""
local hint_timer = 0

-- Victory
local victory_timer = 0

-- Footstep alternator
local foot_alt = false

----------------------------------------------------------------
-- ROOM DATA
-- 20x15 grids: 0=empty, 1=wall, 2=key, 3=door, 4=exit, 5=danger, 6=hint
----------------------------------------------------------------

local function build_room_1()
  -- Simple: find key, open door
  local m = {}
  for y = 0, ROWS-1 do
    m[y] = {}
    for x = 0, COLS-1 do
      if y == 0 or y == ROWS-1 or x == 0 or x == COLS-1 then
        m[y][x] = T_WALL
      else
        m[y][x] = T_EMPTY
      end
    end
  end
  -- Internal walls
  for y = 1, 8 do m[y][10] = T_WALL end
  for x = 10, 14 do m[8][x] = T_WALL end
  -- Key on right side
  m[3][15] = T_KEY
  -- Door at bottom passage
  m[8][12] = T_DOOR
  -- Exit bottom right
  m[13][18] = T_EXIT
  -- Hint near start
  m[7][2] = T_HINT
  return m
end

local function build_room_2()
  -- Maze-like with danger zones
  local m = {}
  for y = 0, ROWS-1 do
    m[y] = {}
    for x = 0, COLS-1 do
      if y == 0 or y == ROWS-1 or x == 0 or x == COLS-1 then
        m[y][x] = T_WALL
      else
        m[y][x] = T_EMPTY
      end
    end
  end
  -- Vertical walls
  for y = 0, 10 do m[y][5] = T_WALL end
  for y = 4, 14 do m[y][10] = T_WALL end
  for y = 0, 8 do m[y][15] = T_WALL end
  -- Horizontal walls
  for x = 5, 10 do m[4][x] = T_WALL end
  for x = 10, 15 do m[10][x] = T_WALL end
  -- Key hidden behind maze
  m[2][18] = T_KEY
  -- Door
  m[10][13] = T_DOOR
  -- Danger zones (make ticking sound)
  m[6][7] = T_DANGER
  m[6][8] = T_DANGER
  m[8][12] = T_DANGER
  -- Exit
  m[13][17] = T_EXIT
  -- Hint
  m[2][2] = T_HINT
  return m
end

local function build_room_3()
  -- Final room: complex layout
  local m = {}
  for y = 0, ROWS-1 do
    m[y] = {}
    for x = 0, COLS-1 do
      if y == 0 or y == ROWS-1 or x == 0 or x == COLS-1 then
        m[y][x] = T_WALL
      else
        m[y][x] = T_EMPTY
      end
    end
  end
  -- Cross pattern walls
  for x = 3, 17 do m[7][x] = T_WALL end
  for y = 2, 12 do m[y][10] = T_WALL end
  -- Openings
  m[7][6] = T_EMPTY
  m[7][14] = T_EMPTY
  m[5][10] = T_EMPTY
  m[10][10] = T_EMPTY
  -- Key top right
  m[3][16] = T_KEY
  -- Door center
  m[7][10] = T_DOOR
  -- Danger scattered
  m[4][4] = T_DANGER
  m[11][8] = T_DANGER
  m[3][13] = T_DANGER
  m[11][15] = T_DANGER
  -- Exit bottom center
  m[13][10] = T_EXIT
  -- Hint
  m[4][2] = T_HINT
  return m
end

----------------------------------------------------------------
-- HELPER FUNCTIONS
----------------------------------------------------------------

local function dist(x1, y1, x2, y2)
  local dx = x1 - x2
  local dy = y1 - y2
  return math.sqrt(dx*dx + dy*dy)
end

local function get_tile(tx, ty)
  if ty < 0 or ty >= ROWS or tx < 0 or tx >= COLS then return T_WALL end
  return room_map[ty][tx]
end

local function find_objects()
  local objs = {}
  for y = 0, ROWS-1 do
    for x = 0, COLS-1 do
      local t = room_map[y][x]
      if t >= T_KEY then
        table.insert(objs, {x=x, y=y, type=t})
      end
    end
  end
  return objs
end

-- Map distance to frequency (closer = higher pitch)
local function dist_to_freq(d, base_low, base_high)
  local max_d = 20
  local t = math.max(0, math.min(1, 1 - d / max_d))
  return base_low + (base_high - base_low) * t * t
end

-- Map distance to duration (closer = longer)
local function dist_to_dur(d)
  local max_d = 20
  local t = math.max(0, math.min(1, 1 - d / max_d))
  return 0.02 + t * 0.08
end

----------------------------------------------------------------
-- SOUND DESIGN
----------------------------------------------------------------

local function sfx_footstep()
  foot_alt = not foot_alt
  wave(CH_FOOTSTEP, "triangle")
  if foot_alt then
    tone(CH_FOOTSTEP, 80, 60, 0.03)
  else
    tone(CH_FOOTSTEP, 70, 50, 0.03)
  end
end

local function sfx_wall_bump()
  noise(CH_FOOTSTEP, 0.04)
end

local function sfx_sonar_ping()
  wave(CH_SONAR, "sine")
  tone(CH_SONAR, 1200, 400, 0.15)
end

local function sfx_key_pickup()
  wave(CH_OBJECT, "sine")
  tone(CH_OBJECT, 800, 1600, 0.1)
  wave(CH_SONAR, "sine")
  tone(CH_SONAR, 1000, 2000, 0.1)
end

local function sfx_door_open()
  wave(CH_OBJECT, "triangle")
  tone(CH_OBJECT, 200, 400, 0.2)
  wave(CH_SONAR, "square")
  tone(CH_SONAR, 150, 300, 0.2)
end

local function sfx_exit_enter()
  wave(CH_SONAR, "sine")
  tone(CH_SONAR, 400, 1200, 0.3)
  wave(CH_OBJECT, "sine")
  tone(CH_OBJECT, 600, 1400, 0.3)
  wave(CH_AMBIENT, "triangle")
  tone(CH_AMBIENT, 300, 900, 0.3)
end

local function sfx_danger_hit()
  noise(CH_FOOTSTEP, 0.1)
  wave(CH_OBJECT, "sawtooth")
  tone(CH_OBJECT, 300, 80, 0.15)
end

local function sfx_object_ping(obj_type, d)
  local dur = dist_to_dur(d)
  if dur < 0.02 then return end

  if obj_type == T_KEY then
    -- Key: bright sine chirp
    local f = dist_to_freq(d, 600, 2000)
    wave(CH_OBJECT, "sine")
    tone(CH_OBJECT, f, f * 1.2, dur)
  elseif obj_type == T_DOOR then
    if has_key then
      -- Unlockable door: inviting triangle
      local f = dist_to_freq(d, 150, 500)
      wave(CH_OBJECT, "triangle")
      tone(CH_OBJECT, f, f * 1.1, dur)
    else
      -- Locked door: low buzzy square
      local f = dist_to_freq(d, 100, 300)
      wave(CH_OBJECT, "square")
      tone(CH_OBJECT, f, f * 0.9, dur)
    end
  elseif obj_type == T_EXIT then
    -- Exit: harmonic chord sweep
    local f = dist_to_freq(d, 300, 1000)
    wave(CH_OBJECT, "sine")
    tone(CH_OBJECT, f, f * 1.5, dur)
    wave(CH_AMBIENT, "triangle")
    tone(CH_AMBIENT, f * 0.75, f * 1.1, dur)
  elseif obj_type == T_DANGER then
    -- Danger: harsh sawtooth stab
    local f = dist_to_freq(d, 80, 250)
    wave(CH_OBJECT, "sawtooth")
    tone(CH_OBJECT, f, f * 0.5, dur)
  elseif obj_type == T_HINT then
    -- Hint: gentle chime
    local f = dist_to_freq(d, 500, 1500)
    wave(CH_OBJECT, "sine")
    tone(CH_OBJECT, f, f, dur)
  end
end

local function sfx_ambient_drone()
  wave(CH_AMBIENT, "triangle")
  tone(CH_AMBIENT, 55, 58, 0.5)
end

local function sfx_heartbeat()
  wave(CH_AMBIENT, "sine")
  tone(CH_AMBIENT, 60, 40, 0.06)
end

local function sfx_victory()
  wave(0, "sine")
  tone(0, 400, 800, 0.2)
  wave(1, "sine")
  tone(1, 600, 1200, 0.2)
  wave(2, "triangle")
  tone(2, 300, 600, 0.2)
end

local function sfx_title_ping()
  wave(CH_SONAR, "sine")
  tone(CH_SONAR, 800, 600, 0.1)
end

----------------------------------------------------------------
-- ROOM MANAGEMENT
----------------------------------------------------------------

local function load_room(num)
  has_key = false
  sonar_active = false
  sonar_radius = 0
  ping_objects = {}
  ring_particles = {}
  hint_text = ""
  hint_timer = 0

  if num == 1 then
    room_map = build_room_1()
    px, py = 2, 7
  elseif num == 2 then
    room_map = build_room_2()
    px, py = 2, 12
  elseif num == 3 then
    room_map = build_room_3()
    px, py = 2, 4
  end

  room_objects = find_objects()
end

----------------------------------------------------------------
-- SONAR SYSTEM
----------------------------------------------------------------

local function do_sonar_ping()
  if sonar_timer > 0 then return end
  sonar_active = true
  sonar_radius = 0
  sonar_timer = SONAR_COOLDOWN
  sfx_sonar_ping()
  ring_particles = {}

  -- Find objects within range and queue them
  ping_objects = {}
  for _, obj in ipairs(room_objects) do
    local d = dist(px, py, obj.x, obj.y)
    if d < 18 then
      table.insert(ping_objects, {x=obj.x, y=obj.y, type=obj.type, dist=d, pinged=false})
    end
  end
  -- Sort by distance (closest pinged first when wave reaches)
  table.sort(ping_objects, function(a, b) return a.dist < b.dist end)
end

local function update_sonar()
  if sonar_timer > 0 then
    sonar_timer = sonar_timer - 1
  end

  if not sonar_active then return end

  sonar_radius = sonar_radius + SONAR_SPEED

  -- Create ring particles at current radius
  if frame % 2 == 0 then
    local angle_count = 16
    for i = 0, angle_count - 1 do
      local a = (i / angle_count) * math.pi * 2
      local rx = px * TILE + 4 + math.cos(a) * sonar_radius
      local ry = py * TILE + 4 + math.sin(a) * sonar_radius
      -- Check if on screen
      if rx >= 0 and rx < W and ry >= 0 and ry < H then
        -- Check if hitting a wall
        local tx = math.floor(rx / TILE)
        local ty = math.floor(ry / TILE)
        local tile = get_tile(tx, ty)
        if tile == T_WALL then
          table.insert(ring_particles, {x=rx, y=ry, life=8, col=C_DARK})
        else
          table.insert(ring_particles, {x=rx, y=ry, life=4, col=C_DARK})
        end
      end
    end
  end

  -- Ping objects as wave reaches them
  for _, obj in ipairs(ping_objects) do
    if not obj.pinged and sonar_radius >= obj.dist * TILE then
      obj.pinged = true
      sfx_object_ping(obj.type, obj.dist)
      -- Bright particle at object location
      table.insert(ring_particles, {
        x = obj.x * TILE + 4,
        y = obj.y * TILE + 4,
        life = 20,
        col = C_WHITE
      })
    end
  end

  if sonar_radius > SONAR_MAX_RADIUS then
    sonar_active = false
  end

  -- Update particles
  local alive = {}
  for _, p in ipairs(ring_particles) do
    p.life = p.life - 1
    if p.life > 0 then
      table.insert(alive, p)
    end
  end
  ring_particles = alive
end

----------------------------------------------------------------
-- PROXIMITY SOUND (continuous ambient object hinting)
----------------------------------------------------------------

local function update_proximity_sounds()
  -- Every ~20 frames, play the nearest interesting object sound
  if frame % 20 ~= 0 then return end

  local nearest = nil
  local nearest_dist = 999

  for _, obj in ipairs(room_objects) do
    local d = dist(px, py, obj.x, obj.y)
    if d < nearest_dist then
      nearest_dist = d
      nearest = obj
    end
  end

  if nearest and nearest_dist < 15 then
    sfx_object_ping(nearest.type, nearest_dist)
  end
end

----------------------------------------------------------------
-- DEMO MODE
----------------------------------------------------------------

local function build_demo_path()
  -- Pre-scripted path for room 1 demo
  demo_path = {
    {dx=1, dy=0}, {dx=1, dy=0}, {dx=1, dy=0}, {dx=1, dy=0},
    {dx=1, dy=0}, {dx=1, dy=0}, {dx=1, dy=0},
    {dx=0, dy=-1}, {dx=0, dy=-1}, {dx=0, dy=-1}, {dx=0, dy=-1},
    {dx=1, dy=0}, {dx=1, dy=0}, {dx=1, dy=0}, {dx=1, dy=0},
    -- ping
    {dx=0, dy=0, ping=true},
    {dx=1, dy=0}, {dx=1, dy=0},
    -- get key at 15,3
    {dx=0, dy=1}, {dx=0, dy=1}, {dx=0, dy=1}, {dx=0, dy=1}, {dx=0, dy=1},
    -- back to door area
    {dx=-1, dy=0}, {dx=-1, dy=0}, {dx=-1, dy=0},
    {dx=0, dy=0, ping=true},
    {dx=0, dy=1}, {dx=0, dy=1},
    -- through door at 12,8
    {dx=0, dy=1}, {dx=0, dy=1}, {dx=0, dy=1},
    {dx=1, dy=0}, {dx=1, dy=0}, {dx=1, dy=0}, {dx=1, dy=0}, {dx=1, dy=0}, {dx=1, dy=0},
    {dx=0, dy=1}, {dx=0, dy=1},
    -- reach exit
  }
  demo_step = 1
  demo_timer = 0
  demo_ping_timer = 0
end

local function update_demo()
  demo_timer = demo_timer + 1
  if demo_timer < 8 then return end
  demo_timer = 0

  if demo_step > #demo_path then
    -- Demo over, loop
    load_room(1)
    build_demo_path()
    return
  end

  local step = demo_path[demo_step]
  if step.ping then
    do_sonar_ping()
  else
    local nx = px + step.dx
    local ny = py + step.dy
    local tile = get_tile(nx, ny)
    if tile == T_WALL then
      sfx_wall_bump()
    elseif tile == T_KEY then
      has_key = true
      room_map[ny][nx] = T_EMPTY
      room_objects = find_objects()
      sfx_key_pickup()
      px, py = nx, ny
    elseif tile == T_DOOR then
      if has_key then
        room_map[ny][nx] = T_EMPTY
        room_objects = find_objects()
        sfx_door_open()
        has_key = false
      end
    elseif tile == T_EXIT then
      sfx_exit_enter()
      px, py = nx, ny
    elseif tile == T_EMPTY or tile == T_HINT or tile == T_DANGER then
      px, py = nx, ny
      sfx_footstep()
    end
  end
  demo_step = demo_step + 1
end

----------------------------------------------------------------
-- TITLE SCENE
----------------------------------------------------------------

local title_idle_timer = 0

local function title_update()
  title_pulse = title_pulse + 1
  title_idle_timer = title_idle_timer + 1

  -- Ambient ping every 60 frames on title
  if title_pulse % 60 == 0 then
    sfx_title_ping()
  end

  -- Enter demo after 5 seconds idle
  if title_idle_timer > 150 and not demo_mode then
    demo_mode = true
    current_room = 1
    load_room(1)
    build_demo_path()
    title_idle_timer = 0
  end

  if demo_mode then
    update_demo()
    update_sonar()
  end

  if btnp("start") or btnp("a") then
    demo_mode = false
    scene = "game"
    current_room = 1
    load_room(1)
    hint_text = "PRESS A TO PING"
    hint_timer = 90
  end
end

local function title_draw()
  s = screen()
  cls(s, C_BLACK)

  -- Pulsing title
  local pulse = math.sin(title_pulse * 0.05) * 0.5 + 0.5
  local tcol = pulse > 0.5 and C_LIGHT or C_DARK

  text(s, "THE DARK ROOM", W/2, 25, C_WHITE, ALIGN_CENTER)
  text(s, "SOUND NAVIGATOR", W/2, 38, tcol, ALIGN_CENTER)

  -- Sonar ring visual on title
  local ring_r = (title_pulse % 60) * 1.5
  if ring_r < 80 then
    local cx, cy = W/2, 75
    local segs = 24
    for i = 0, segs - 1 do
      local a = (i / segs) * math.pi * 2
      local rx = cx + math.cos(a) * ring_r
      local ry = cy + math.sin(a) * ring_r * 0.5
      if rx >= 0 and rx < W and ry >= 0 and ry < H then
        local c = ring_r < 40 and C_DARK or C_BLACK
        if c > 0 then
          pix(s, math.floor(rx), math.floor(ry), c)
        end
      end
    end
    -- Center dot
    pix(s, cx, 75, C_WHITE)
  end

  if demo_mode then
    -- Draw demo with sonar view
    -- Player dot
    local dpx = px * TILE + 4
    local dpy = py * TILE + 4
    pix(s, dpx, dpy, C_WHITE)
    -- Ring particles
    for _, p in ipairs(ring_particles) do
      if p.x >= 0 and p.x < W and p.y >= 0 and p.y < H then
        pix(s, math.floor(p.x), math.floor(p.y), p.col)
      end
    end
    -- Demo label
    text(s, "- DEMO -", W/2, 4, C_DARK, ALIGN_CENTER)
  end

  -- Blink prompt
  if title_pulse % 40 < 25 then
    text(s, "PRESS START", W/2, 108, C_LIGHT, ALIGN_CENTER)
  end
end

----------------------------------------------------------------
-- GAME SCENE
----------------------------------------------------------------

local function try_move(dx, dy)
  local nx = px + dx
  local ny = py + dy
  local tile = get_tile(nx, ny)

  if tile == T_WALL then
    sfx_wall_bump()
    hint_text = "WALL"
    hint_timer = 20
    return
  end

  if tile == T_KEY then
    has_key = true
    room_map[ny][nx] = T_EMPTY
    room_objects = find_objects()
    sfx_key_pickup()
    hint_text = "KEY FOUND"
    hint_timer = 40
    px, py = nx, ny
    return
  end

  if tile == T_DOOR then
    if has_key then
      room_map[ny][nx] = T_EMPTY
      room_objects = find_objects()
      sfx_door_open()
      has_key = false
      hint_text = "DOOR OPENED"
      hint_timer = 40
    else
      sfx_wall_bump()
      hint_text = "LOCKED"
      hint_timer = 30
      -- Play door locked sound
      wave(CH_OBJECT, "square")
      tone(CH_OBJECT, 100, 80, 0.1)
    end
    return
  end

  if tile == T_EXIT then
    sfx_exit_enter()
    if current_room < 3 then
      current_room = current_room + 1
      load_room(current_room)
      hint_text = "ROOM " .. current_room
      hint_timer = 60
    else
      scene = "victory"
      victory_timer = 0
      sfx_victory()
    end
    return
  end

  if tile == T_DANGER then
    sfx_danger_hit()
    hint_text = "DANGER!"
    hint_timer = 30
    -- Push player back
    return
  end

  if tile == T_HINT then
    room_map[ny][nx] = T_EMPTY
    room_objects = find_objects()
    if current_room == 1 then
      hint_text = "FIND THE KEY"
    elseif current_room == 2 then
      hint_text = "BEWARE DANGER"
    else
      hint_text = "LISTEN CLOSELY"
    end
    hint_timer = 60
    -- Chime
    wave(CH_OBJECT, "sine")
    tone(CH_OBJECT, 1000, 1200, 0.1)
    wave(CH_SONAR, "sine")
    tone(CH_SONAR, 1500, 1800, 0.1)
    px, py = nx, ny
    return
  end

  -- Empty tile - move
  px, py = nx, ny
  sfx_footstep()
end

local function game_update()
  if paused then
    if btnp("select") then
      paused = false
    end
    return
  end

  if btnp("select") then
    paused = true
    return
  end

  frame = frame + 1

  -- Movement with repeat delay
  if move_timer > 0 then
    move_timer = move_timer - 1
  end

  if move_timer <= 0 then
    if btn("left") then try_move(-1, 0); move_timer = MOVE_DELAY
    elseif btn("right") then try_move(1, 0); move_timer = MOVE_DELAY
    elseif btn("up") then try_move(0, -1); move_timer = MOVE_DELAY
    elseif btn("down") then try_move(0, 1); move_timer = MOVE_DELAY
    end
  end

  -- Sonar ping on A
  if btnp("a") then
    do_sonar_ping()
  end

  update_sonar()
  update_proximity_sounds()

  -- Ambient drone
  ambient_timer = ambient_timer + 1
  if ambient_timer >= 90 then
    ambient_timer = 0
    sfx_ambient_drone()
  end

  -- Heartbeat near danger
  local near_danger = false
  for _, obj in ipairs(room_objects) do
    if obj.type == T_DANGER then
      local d = dist(px, py, obj.x, obj.y)
      if d < 5 then
        near_danger = true
        break
      end
    end
  end
  if near_danger then
    heartbeat_timer = heartbeat_timer + 1
    if heartbeat_timer % 15 == 0 then
      sfx_heartbeat()
    end
  else
    heartbeat_timer = 0
  end

  -- Hint decay
  if hint_timer > 0 then
    hint_timer = hint_timer - 1
  end
end

local function game_draw()
  s = screen()
  cls(s, C_BLACK)

  -- Player dot (always visible - your position)
  local draw_px = px * TILE + 4
  local draw_py = py * TILE + 4
  pix(s, draw_px, draw_py, C_WHITE)
  -- Small cross around player
  if frame % 30 < 20 then
    pix(s, draw_px - 1, draw_py, C_DARK)
    pix(s, draw_px + 1, draw_py, C_DARK)
    pix(s, draw_px, draw_py - 1, C_DARK)
    pix(s, draw_px, draw_py + 1, C_DARK)
  end

  -- Sonar ring particles (the main visual feedback)
  for _, p in ipairs(ring_particles) do
    local rx = math.floor(p.x)
    local ry = math.floor(p.y)
    if rx >= 0 and rx < W and ry >= 0 and ry < H then
      local c = p.col
      if p.life < 4 then c = C_DARK end
      if p.life < 2 then c = C_BLACK end
      if c > 0 then
        pix(s, rx, ry, c)
      end
    end
  end

  -- Active sonar ring outline
  if sonar_active then
    local segs = 32
    for i = 0, segs - 1 do
      local a = (i / segs) * math.pi * 2
      local rx = draw_px + math.cos(a) * sonar_radius
      local ry = draw_py + math.sin(a) * sonar_radius
      if rx >= 0 and rx < W and ry >= 0 and ry < H then
        pix(s, math.floor(rx), math.floor(ry), C_DARK)
      end
    end
  end

  -- Key indicator (top right)
  if has_key then
    rectf(s, W - 10, 2, 7, 5, C_LIGHT)
    pix(s, W - 7, 4, C_BLACK)
    text(s, "K", W - 8, 2, C_WHITE)
  end

  -- Room number
  text(s, current_room .. "/3", 4, 2, C_DARK)

  -- Sonar cooldown bar
  if sonar_timer > 0 then
    local bar_w = math.floor((sonar_timer / SONAR_COOLDOWN) * 16)
    rectf(s, W/2 - 8, H - 5, bar_w, 2, C_DARK)
  else
    -- Ready indicator
    if frame % 40 < 30 then
      pix(s, W/2, H - 4, C_LIGHT)
    end
  end

  -- Hint text
  if hint_timer > 0 then
    local hcol = hint_timer > 15 and C_LIGHT or C_DARK
    text(s, hint_text, W/2, H - 14, hcol, ALIGN_CENTER)
  end

  -- Pause overlay
  if paused then
    rectf(s, W/2 - 25, H/2 - 8, 50, 16, C_BLACK)
    text(s, "PAUSED", W/2, H/2 - 4, C_WHITE, ALIGN_CENTER)
  end
end

----------------------------------------------------------------
-- VICTORY SCENE
----------------------------------------------------------------

local function victory_update()
  victory_timer = victory_timer + 1

  if victory_timer % 30 == 0 and victory_timer < 120 then
    sfx_victory()
  end

  if victory_timer > 60 and (btnp("start") or btnp("a")) then
    scene = "title"
    title_pulse = 0
    title_idle_timer = 0
    demo_mode = false
  end
end

local function victory_draw()
  s = screen()
  cls(s, C_BLACK)

  -- Expanding light
  local r = math.min(victory_timer * 0.8, 50)
  local cx, cy = W/2, H/2
  -- Concentric rings of increasing brightness
  for ring = math.floor(r), 0, -4 do
    local col = C_DARK
    if ring < r * 0.3 then col = C_WHITE
    elseif ring < r * 0.6 then col = C_LIGHT
    end
    local segs = 24
    for i = 0, segs - 1 do
      local a = (i / segs) * math.pi * 2
      local rx = cx + math.cos(a) * ring
      local ry = cy + math.sin(a) * ring
      if rx >= 0 and rx < W and ry >= 0 and ry < H then
        pix(s, math.floor(rx), math.floor(ry), col)
      end
    end
  end

  if victory_timer > 30 then
    text(s, "LIGHT", W/2, H/2 - 12, C_WHITE, ALIGN_CENTER)
  end
  if victory_timer > 50 then
    text(s, "YOU ESCAPED", W/2, H/2, C_LIGHT, ALIGN_CENTER)
    text(s, "THE DARK ROOM", W/2, H/2 + 12, C_LIGHT, ALIGN_CENTER)
  end
  if victory_timer > 90 and (victory_timer % 40 < 25) then
    text(s, "PRESS START", W/2, H - 12, C_DARK, ALIGN_CENTER)
  end
end

----------------------------------------------------------------
-- ENGINE CALLBACKS
----------------------------------------------------------------

function _init()
  mode(2)
end

function _start()
  scene = "title"
  title_pulse = 0
  title_idle_timer = 0
  demo_mode = false
  frame = 0
  -- Set default wave types
  wave(CH_SONAR, "sine")
  wave(CH_OBJECT, "sine")
  wave(CH_AMBIENT, "triangle")
  wave(CH_FOOTSTEP, "triangle")
end

function _update()
  if scene == "title" then
    title_update()
  elseif scene == "game" then
    game_update()
  elseif scene == "victory" then
    victory_update()
  end
end

function _draw()
  if scene == "title" then
    title_draw()
  elseif scene == "game" then
    game_draw()
  elseif scene == "victory" then
    victory_draw()
  end
end
