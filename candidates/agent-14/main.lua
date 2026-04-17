-- ECHO LABYRINTH: Procedural Sonar Navigator
-- Agent 14 -- agent-08 (sonar navigation) + agent-10 (procedural generation)
-- Every playthrough is unique. Navigate by sound alone. Share seeds.
-- 160x120 | 2-bit | mode(2)

----------------------------------------------------------------
-- CONSTANTS
----------------------------------------------------------------
local W, H = 160, 120
local TILE = 8
local COLS, ROWS = 20, 15
local SONAR_COOLDOWN = 15
local SONAR_MAX_RADIUS = 60
local SONAR_SPEED = 2.5
local MOVE_DELAY = 4
local NUM_ROOMS = 5

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
-- SEEDED PRNG (xorshift32 from agent-10)
----------------------------------------------------------------
local seed_val = 0
local rng_state = 1

local function rng_seed(s)
  seed_val = s
  rng_state = (s == 0) and 1 or s
end

local function rng()
  local x = rng_state
  x = x ~ (x << 13)
  x = x ~ (x >> 17)
  x = x ~ (x << 5)
  x = x & 0xFFFFFFFF
  if x == 0 then x = 1 end
  rng_state = x
  return x
end

local function rng_int(lo, hi)
  return lo + (rng() % (hi - lo + 1))
end

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local scene = "title"
local s = nil
local frm = 0
local title_pulse = 0
local paused = false

-- Player
local px, py = 2, 7
local move_timer = 0
local has_key = false
local sonar_timer = 0
local sonar_radius = 0
local sonar_active = false
local ping_objects = {}

-- Rooms
local current_room = 1
local room_map = {}
local room_objects = {}
local room_seeds = {} -- per-room seed for regeneration

-- Particles
local ring_particles = {}

-- Demo mode
local demo_mode = false
local demo_timer = 0
local demo_step = 1
local demo_auto_timer = 0
local demo_ping_cd = 0

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

-- Title
local title_idle_timer = 0

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

local function dist_to_freq(d, base_low, base_high)
  local max_d = 20
  local t = math.max(0, math.min(1, 1 - d / max_d))
  return base_low + (base_high - base_low) * t * t
end

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
    local f = dist_to_freq(d, 600, 2000)
    wave(CH_OBJECT, "sine")
    tone(CH_OBJECT, f, f * 1.2, dur)
  elseif obj_type == T_DOOR then
    if has_key then
      local f = dist_to_freq(d, 150, 500)
      wave(CH_OBJECT, "triangle")
      tone(CH_OBJECT, f, f * 1.1, dur)
    else
      local f = dist_to_freq(d, 100, 300)
      wave(CH_OBJECT, "square")
      tone(CH_OBJECT, f, f * 0.9, dur)
    end
  elseif obj_type == T_EXIT then
    local f = dist_to_freq(d, 300, 1000)
    wave(CH_OBJECT, "sine")
    tone(CH_OBJECT, f, f * 1.5, dur)
    wave(CH_AMBIENT, "triangle")
    tone(CH_AMBIENT, f * 0.75, f * 1.1, dur)
  elseif obj_type == T_DANGER then
    local f = dist_to_freq(d, 80, 250)
    wave(CH_OBJECT, "sawtooth")
    tone(CH_OBJECT, f, f * 0.5, dur)
  elseif obj_type == T_HINT then
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
-- PROCEDURAL ROOM GENERATION
----------------------------------------------------------------
local function generate_room(room_num)
  -- Seed the RNG for this specific room
  rng_seed(seed_val * 1000 + room_num * 137)

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

  -- Difficulty increases with room number
  local complexity = room_num

  -- Generate internal wall segments
  local num_walls = 2 + complexity
  for i = 1, num_walls do
    local vertical = rng_int(0, 1) == 0
    if vertical then
      local wx = rng_int(3, COLS - 4)
      local wy_start = rng_int(1, ROWS - 5)
      local wy_len = rng_int(3, math.min(8, ROWS - wy_start - 1))
      for wy = wy_start, math.min(wy_start + wy_len, ROWS - 2) do
        m[wy][wx] = T_WALL
      end
      -- Always leave a gap for passage
      local gap_y = rng_int(wy_start, math.min(wy_start + wy_len, ROWS - 2))
      m[gap_y][wx] = T_EMPTY
    else
      local wy = rng_int(3, ROWS - 4)
      local wx_start = rng_int(1, COLS - 5)
      local wx_len = rng_int(3, math.min(10, COLS - wx_start - 1))
      for wx = wx_start, math.min(wx_start + wx_len, COLS - 2) do
        m[wy][wx] = T_WALL
      end
      -- Leave a gap
      local gap_x = rng_int(wx_start, math.min(wx_start + wx_len, COLS - 2))
      m[wy][gap_x] = T_EMPTY
    end
  end

  -- Place key in an open tile on the far side
  local key_placed = false
  for attempt = 1, 50 do
    local kx = rng_int(COLS / 2, COLS - 2)
    local ky = rng_int(1, ROWS - 2)
    if m[ky][kx] == T_EMPTY then
      m[ky][kx] = T_KEY
      key_placed = true
      break
    end
  end
  if not key_placed then
    -- Fallback: place somewhere
    for y = 1, ROWS - 2 do
      for x = COLS - 3, COLS / 2, -1 do
        if m[y][x] == T_EMPTY then
          m[y][x] = T_KEY
          key_placed = true
          break
        end
      end
      if key_placed then break end
    end
  end

  -- Place door blocking path to exit area
  local door_placed = false
  for attempt = 1, 50 do
    local dx = rng_int(COLS / 3, COLS - 3)
    local dy = rng_int(2, ROWS - 3)
    if m[dy][dx] == T_EMPTY then
      -- Check if adjacent to a wall (doorway feel)
      local adj_wall = false
      if get_tile(dx-1, dy) == T_WALL or get_tile(dx+1, dy) == T_WALL
         or get_tile(dx, dy-1) == T_WALL or get_tile(dx, dy+1) == T_WALL then
        adj_wall = true
      end
      -- For the generated map, use the local map
      local function local_tile(tx, ty)
        if ty < 0 or ty >= ROWS or tx < 0 or tx >= COLS then return T_WALL end
        return m[ty][tx]
      end
      if local_tile(dx-1, dy) == T_WALL or local_tile(dx+1, dy) == T_WALL
         or local_tile(dx, dy-1) == T_WALL or local_tile(dx, dy+1) == T_WALL then
        m[dy][dx] = T_DOOR
        door_placed = true
        break
      end
    end
  end
  if not door_placed then
    -- Fallback: place door at a wall gap
    for y = 2, ROWS - 3 do
      for x = COLS / 3, COLS - 3 do
        if m[y][x] == T_EMPTY then
          local function local_tile(tx, ty)
            if ty < 0 or ty >= ROWS or tx < 0 or tx >= COLS then return T_WALL end
            return m[ty][tx]
          end
          if local_tile(x-1, y) == T_WALL or local_tile(x+1, y) == T_WALL then
            m[y][x] = T_DOOR
            door_placed = true
            break
          end
        end
      end
      if door_placed then break end
    end
  end

  -- Place exit on the far edge area
  local exit_placed = false
  for attempt = 1, 50 do
    local ex = rng_int(COLS - 4, COLS - 2)
    local ey = rng_int(1, ROWS - 2)
    if m[ey][ex] == T_EMPTY then
      m[ey][ex] = T_EXIT
      exit_placed = true
      break
    end
  end
  if not exit_placed then
    m[ROWS - 2][COLS - 2] = T_EXIT
  end

  -- Place danger tiles (more in later rooms)
  local num_dangers = complexity
  for i = 1, num_dangers do
    for attempt = 1, 30 do
      local dx = rng_int(2, COLS - 3)
      local dy = rng_int(2, ROWS - 3)
      if m[dy][dx] == T_EMPTY then
        m[dy][dx] = T_DANGER
        break
      end
    end
  end

  -- Place hint tile near start
  for attempt = 1, 30 do
    local hx = rng_int(1, COLS / 3)
    local hy = rng_int(1, ROWS - 2)
    if m[hy][hx] == T_EMPTY then
      m[hy][hx] = T_HINT
      break
    end
  end

  -- Find a valid starting position near left side
  local start_x, start_y = 2, 7
  for attempt = 1, 50 do
    local sx = rng_int(1, 4)
    local sy = rng_int(1, ROWS - 2)
    if m[sy][sx] == T_EMPTY then
      start_x, start_y = sx, sy
      break
    end
  end

  return m, start_x, start_y
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

  local start_x, start_y
  room_map, start_x, start_y = generate_room(num)
  px, py = start_x, start_y
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

  ping_objects = {}
  for _, obj in ipairs(room_objects) do
    local d = dist(px, py, obj.x, obj.y)
    if d < 18 then
      table.insert(ping_objects, {x=obj.x, y=obj.y, type=obj.type, dist=d, pinged=false})
    end
  end
  table.sort(ping_objects, function(a, b) return a.dist < b.dist end)
end

local function update_sonar()
  if sonar_timer > 0 then
    sonar_timer = sonar_timer - 1
  end
  if not sonar_active then return end

  sonar_radius = sonar_radius + SONAR_SPEED

  if frm % 2 == 0 then
    local angle_count = 16
    for i = 0, angle_count - 1 do
      local a = (i / angle_count) * math.pi * 2
      local rx = px * TILE + 4 + math.cos(a) * sonar_radius
      local ry = py * TILE + 4 + math.sin(a) * sonar_radius
      if rx >= 0 and rx < W and ry >= 0 and ry < H then
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

  for _, obj in ipairs(ping_objects) do
    if not obj.pinged and sonar_radius >= obj.dist * TILE then
      obj.pinged = true
      sfx_object_ping(obj.type, obj.dist)
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
-- PROXIMITY SOUND
----------------------------------------------------------------
local function update_proximity_sounds()
  if frm % 20 ~= 0 then return end
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
local function update_demo()
  demo_timer = demo_timer + 1
  demo_auto_timer = demo_auto_timer + 1

  -- Auto sonar ping periodically
  demo_ping_cd = demo_ping_cd - 1
  if demo_ping_cd <= 0 then
    do_sonar_ping()
    demo_ping_cd = 40
  end

  if demo_auto_timer < 8 then return end
  demo_auto_timer = 0

  -- Try random movement, preferring unexplored directions
  local dirs = {{1,0},{-1,0},{0,1},{0,-1}}
  -- Pick a direction based on frame
  local di = (rng_int(1, 4))
  local dx, dy = dirs[di][1], dirs[di][2]
  local nx = px + dx
  local ny = py + dy
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
    if current_room < NUM_ROOMS then
      current_room = current_room + 1
      load_room(current_room)
    else
      -- Loop demo
      current_room = 1
      load_room(1)
    end
    px, py = nx, ny
  elseif tile == T_EMPTY or tile == T_HINT or tile == T_DANGER then
    px, py = nx, ny
    sfx_footstep()
  end

  -- Reset demo after a while
  if demo_timer > 600 then
    demo_timer = 0
    current_room = 1
    load_room(1)
  end
end

----------------------------------------------------------------
-- TITLE SCENE
----------------------------------------------------------------
local function title_update()
  title_pulse = title_pulse + 1
  title_idle_timer = title_idle_timer + 1

  if title_pulse % 60 == 0 then
    sfx_title_ping()
  end

  -- Enter demo after idle
  if title_idle_timer > 180 and not demo_mode then
    demo_mode = true
    -- Generate a new seed for demo
    seed_val = (title_pulse * 31337 + 12345) & 0xFFFF
    if seed_val == 0 then seed_val = 1 end
    current_room = 1
    load_room(1)
    demo_timer = 0
    demo_auto_timer = 0
    demo_ping_cd = 20
    title_idle_timer = 0
  end

  if demo_mode then
    update_demo()
    update_sonar()
  end

  if btnp("start") or btnp("a") then
    demo_mode = false
    scene = "game"
    -- Generate fresh seed if we haven't set one
    if seed_val == 0 then
      seed_val = (frm * 31337 + 7919) & 0xFFFF
      if seed_val == 0 then seed_val = 1 end
    end
    current_room = 1
    load_room(1)
    hint_text = "PRESS A TO PING"
    hint_timer = 90
  end
end

local function title_draw()
  s = screen()
  cls(s, C_BLACK)

  local pulse = math.sin(title_pulse * 0.05) * 0.5 + 0.5
  local tcol = pulse > 0.5 and C_LIGHT or C_DARK

  text(s, "ECHO LABYRINTH", W/2, 20, C_WHITE, ALIGN_CENTER)
  text(s, "PROCEDURAL SONAR", W/2, 33, tcol, ALIGN_CENTER)

  -- Seed display
  text(s, "SEED:" .. seed_val, W/2, 46, C_DARK, ALIGN_CENTER)

  -- Sonar ring animation on title
  local ring_r = (title_pulse % 60) * 1.5
  if ring_r < 80 then
    local cx, cy = W/2, 78
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
    pix(s, cx, 78, C_WHITE)
  end

  if demo_mode then
    local dpx = px * TILE + 4
    local dpy = py * TILE + 4
    pix(s, dpx, dpy, C_WHITE)
    for _, p in ipairs(ring_particles) do
      if p.x >= 0 and p.x < W and p.y >= 0 and p.y < H then
        pix(s, math.floor(p.x), math.floor(p.y), p.col)
      end
    end
    text(s, "- DEMO -", W/2, 4, C_DARK, ALIGN_CENTER)
  end

  if title_pulse % 40 < 25 then
    text(s, "PRESS START", W/2, 108, C_LIGHT, ALIGN_CENTER)
  end
end

----------------------------------------------------------------
-- GAME SCENE
----------------------------------------------------------------
local HINT_MSGS = {
  "FIND THE KEY",
  "BEWARE DANGER",
  "LISTEN CLOSELY",
  "WALLS ECHO BACK",
  "PING TO SEE",
}

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
      wave(CH_OBJECT, "square")
      tone(CH_OBJECT, 100, 80, 0.1)
    end
    return
  end

  if tile == T_EXIT then
    sfx_exit_enter()
    if current_room < NUM_ROOMS then
      current_room = current_room + 1
      load_room(current_room)
      hint_text = "ROOM " .. current_room .. "/" .. NUM_ROOMS
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
    return
  end

  if tile == T_HINT then
    room_map[ny][nx] = T_EMPTY
    room_objects = find_objects()
    hint_text = HINT_MSGS[(current_room % #HINT_MSGS) + 1]
    hint_timer = 60
    wave(CH_OBJECT, "sine")
    tone(CH_OBJECT, 1000, 1200, 0.1)
    wave(CH_SONAR, "sine")
    tone(CH_SONAR, 1500, 1800, 0.1)
    px, py = nx, ny
    return
  end

  -- Empty tile
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

  frm = frm + 1

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

  if hint_timer > 0 then
    hint_timer = hint_timer - 1
  end
end

local function game_draw()
  s = screen()
  cls(s, C_BLACK)

  -- Player dot
  local draw_px = px * TILE + 4
  local draw_py = py * TILE + 4
  pix(s, draw_px, draw_py, C_WHITE)
  if frm % 30 < 20 then
    pix(s, draw_px - 1, draw_py, C_DARK)
    pix(s, draw_px + 1, draw_py, C_DARK)
    pix(s, draw_px, draw_py - 1, C_DARK)
    pix(s, draw_px, draw_py + 1, C_DARK)
  end

  -- Sonar ring particles
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

  -- Key indicator
  if has_key then
    text(s, "K", W - 8, 2, C_WHITE)
  end

  -- Room/seed info
  text(s, current_room .. "/" .. NUM_ROOMS, 4, 2, C_DARK)
  text(s, "S:" .. seed_val, W - 4, 10, C_DARK, ALIGN_RIGHT)

  -- Sonar cooldown bar
  if sonar_timer > 0 then
    local bar_w = math.floor((sonar_timer / SONAR_COOLDOWN) * 16)
    rectf(s, W/2 - 8, H - 5, bar_w, 2, C_DARK)
  else
    if frm % 40 < 30 then
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
    rectf(s, W/2 - 30, H/2 - 12, 60, 24, C_BLACK)
    text(s, "PAUSED", W/2, H/2 - 8, C_WHITE, ALIGN_CENTER)
    text(s, "SEED:" .. seed_val, W/2, H/2 + 2, C_DARK, ALIGN_CENTER)
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
    -- New random seed for next game
    seed_val = (seed_val * 7919 + victory_timer) & 0xFFFF
    if seed_val == 0 then seed_val = 1 end
  end
end

local function victory_draw()
  s = screen()
  cls(s, C_BLACK)

  local r = math.min(victory_timer * 0.8, 50)
  local cx, cy = W/2, H/2
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
    text(s, "LIGHT", W/2, H/2 - 16, C_WHITE, ALIGN_CENTER)
  end
  if victory_timer > 50 then
    text(s, "YOU ESCAPED", W/2, H/2 - 4, C_LIGHT, ALIGN_CENTER)
    text(s, "ECHO LABYRINTH", W/2, H/2 + 8, C_LIGHT, ALIGN_CENTER)
  end
  if victory_timer > 70 then
    text(s, "SEED:" .. seed_val, W/2, H/2 + 22, C_DARK, ALIGN_CENTER)
    text(s, NUM_ROOMS .. " ROOMS", W/2, H/2 + 32, C_DARK, ALIGN_CENTER)
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
  frm = 0
  -- Generate initial random seed
  seed_val = 42
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
