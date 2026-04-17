-- ECHOLOCATION
-- Agent 13 — Sound-driven horror: sonar navigation + stalker entity
-- Base: Agent 08 (sonar) | Absorbed: Agent 04 (horror/entity)
-- You are blind. Something hunts you. Every ping reveals... and betrays.

----------------------------------------------------------------
-- CONSTANTS
----------------------------------------------------------------
local W, H = 160, 120
local TILE = 8
local COLS, ROWS = 20, 15
local SONAR_COOLDOWN = 20
local SONAR_MAX_RADIUS = 65
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
local frame_count = 0
local title_pulse = 0
local paused = false

-- Player
local px, py = 2, 7  -- tile coords
local move_timer = 0
local has_key = false
local sonar_timer = 0
local sonar_radius = 0
local sonar_active = false
local ping_objects = {}
local player_moving = false
local player_alive = true

-- Entity (the stalker)
local ex, ey = 15, 3    -- tile coords
local e_speed = 0.03    -- tiles per frame
local e_active = false
local e_chase = false
local e_alert_x, e_alert_y = -1, -1  -- where entity heard last ping
local e_patrol_timer = 0
local e_target_x, e_target_y = 15, 3
local e_step_timer = 0
local e_move_accum_x = 0
local e_move_accum_y = 0

-- Scare system
local scare_timer = 0
local scare_flash = 0
local shake_timer = 0
local shake_x, shake_y = 0, 0

-- Rooms
local current_room = 1
local room_map = {}
local room_objects = {}

-- Sonar ring particles
local ring_particles = {}

-- Demo mode
local demo_mode = false
local demo_timer = 0
local demo_path = {}
local demo_step = 1

-- Ambient / heartbeat
local ambient_timer = 0
local heartbeat_timer = 0
local heartbeat_rate = 0  -- 0=calm, 1=max panic
local amb_drip_timer = 0
local amb_creak_timer = 0

-- Hint text
local hint_text = ""
local hint_timer = 0

-- Victory / death
local victory_timer = 0
local death_timer = 0

-- Footstep alternator
local foot_alt = false

----------------------------------------------------------------
-- ROOM DATA
-- 20x15 grids: 0=empty, 1=wall, 2=key, 3=door, 4=exit
----------------------------------------------------------------

local function build_room_1()
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
  -- Internal walls creating corridors (hide-and-seek layout)
  for y = 1, 8 do m[y][10] = T_WALL end
  for x = 10, 14 do m[8][x] = T_WALL end
  -- Pillars for cover
  m[4][4] = T_WALL
  m[4][7] = T_WALL
  m[10][5] = T_WALL
  m[10][15] = T_WALL
  -- Key on right side (behind wall)
  m[3][15] = T_KEY
  -- Door at bottom passage
  m[8][12] = T_DOOR
  -- Exit bottom right
  m[13][18] = T_EXIT
  return m
end

local function build_room_2()
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
  -- Maze-like corridors
  for y = 0, 10 do m[y][5] = T_WALL end
  for y = 4, 14 do m[y][10] = T_WALL end
  for y = 0, 8 do m[y][15] = T_WALL end
  for x = 5, 10 do m[4][x] = T_WALL end
  for x = 10, 15 do m[10][x] = T_WALL end
  -- Hiding spots (alcoves)
  m[6][6] = T_EMPTY; m[6][7] = T_EMPTY
  m[12][12] = T_EMPTY; m[12][13] = T_EMPTY
  -- Key hidden behind maze
  m[2][18] = T_KEY
  -- Door
  m[10][13] = T_DOOR
  -- Exit
  m[13][17] = T_EXIT
  return m
end

local function build_room_3()
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
  -- Cross pattern with many hiding spots
  for x = 3, 17 do m[7][x] = T_WALL end
  for y = 2, 12 do m[y][10] = T_WALL end
  -- Openings
  m[7][6] = T_EMPTY
  m[7][14] = T_EMPTY
  m[5][10] = T_EMPTY
  m[10][10] = T_EMPTY
  -- Scattered pillars
  m[3][4] = T_WALL; m[11][4] = T_WALL
  m[3][16] = T_WALL; m[11][16] = T_WALL
  -- Key top right
  m[3][17] = T_KEY
  -- Door center
  m[7][10] = T_DOOR
  -- Exit bottom center
  m[13][10] = T_EXIT
  return m
end

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------

local function dist(x1, y1, x2, y2)
  local dx = x1 - x2
  local dy = y1 - y2
  return math.sqrt(dx*dx + dy*dy)
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
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
  end
end

-- HORROR SOUNDS

local function sfx_heartbeat(intensity)
  -- Deeper, more urgent heartbeat when closer
  wave(CH_AMBIENT, "sine")
  local base = lerp(50, 70, intensity)
  tone(CH_AMBIENT, base, base * 0.7, 0.06)
end

local function sfx_heartbeat_double(intensity)
  -- Double thump for high panic
  wave(CH_AMBIENT, "sine")
  local base = lerp(55, 75, intensity)
  tone(CH_AMBIENT, base, base * 0.6, 0.04)
end

local function sfx_entity_step(d)
  -- Entity footstep: heavier than player, pitch varies with distance
  -- Closer = louder/lower
  if d > 15 then return end
  local vol_t = clamp(1 - d / 15, 0, 1)
  local freq = lerp(200, 100, vol_t)
  local dur = lerp(0.01, 0.04, vol_t)
  wave(CH_FOOTSTEP, "square")
  tone(CH_FOOTSTEP, freq, freq * 0.8, dur)
end

local function sfx_entity_growl()
  -- Low rumble when entity is near and hunting
  wave(CH_AMBIENT, "sawtooth")
  tone(CH_AMBIENT, 45, 35, 0.12)
end

local function sfx_jumpscare()
  -- Full horror: blast all channels
  noise(CH_SONAR, 0.2)
  wave(CH_OBJECT, "sawtooth")
  tone(CH_OBJECT, 80, 40, 0.3)
  noise(CH_FOOTSTEP, 0.15)
  wave(CH_AMBIENT, "square")
  tone(CH_AMBIENT, 100, 50, 0.25)
end

local function sfx_ambient_drip()
  wave(CH_OBJECT, "sine")
  local pitch = 1200 + math.random(800)
  tone(CH_OBJECT, pitch, pitch * 0.5, 0.02)
end

local function sfx_ambient_creak()
  wave(CH_AMBIENT, "sawtooth")
  local creaks = {55, 62, 48, 70}
  local f = creaks[math.random(#creaks)]
  tone(CH_AMBIENT, f, f * 0.8, 0.1)
end

local function sfx_ambient_drone()
  wave(CH_AMBIENT, "triangle")
  tone(CH_AMBIENT, 45, 48, 0.5)
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

local function sfx_alert_ping()
  -- When entity hears your sonar: ominous response
  wave(CH_OBJECT, "square")
  tone(CH_OBJECT, 120, 80, 0.08)
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
  player_alive = true
  scare_timer = 0
  scare_flash = 0
  shake_timer = 0
  death_timer = 0

  if num == 1 then
    room_map = build_room_1()
    px, py = 2, 7
    -- Entity starts far away
    ex, ey = 17, 3
    e_target_x, e_target_y = 15, 7
  elseif num == 2 then
    room_map = build_room_2()
    px, py = 2, 12
    ex, ey = 17, 2
    e_target_x, e_target_y = 12, 6
  elseif num == 3 then
    room_map = build_room_3()
    px, py = 2, 4
    ex, ey = 17, 11
    e_target_x, e_target_y = 10, 10
  end

  e_active = true
  e_chase = false
  e_alert_x, e_alert_y = -1, -1
  e_speed = 0.02 + num * 0.008  -- gets faster each room
  e_patrol_timer = 0
  e_step_timer = 0
  e_move_accum_x = 0
  e_move_accum_y = 0
  room_objects = find_objects()
end

----------------------------------------------------------------
-- ENTITY AI
----------------------------------------------------------------

local function entity_can_move(tx, ty)
  if ty < 0 or ty >= ROWS or tx < 0 or tx >= COLS then return false end
  local t = room_map[ty][tx]
  return t ~= T_WALL and t ~= T_DOOR
end

local function update_entity()
  if not e_active or not player_alive then return end

  local d = dist(px, py, ex, ey)

  -- Determine behavior
  if e_alert_x >= 0 then
    -- Entity heard a ping! Move toward the sound source
    e_chase = true
    e_target_x = e_alert_x
    e_target_y = e_alert_y

    -- If entity reached the alert location, start hunting nearby
    if dist(ex, ey, e_alert_x, e_alert_y) < 2 then
      e_alert_x, e_alert_y = -1, -1
      -- Linger and search for a while
      e_patrol_timer = 120
    end
  elseif d < 4 then
    -- Very close: chase directly
    e_chase = true
    e_target_x = px
    e_target_y = py
  elseif e_patrol_timer > 0 then
    -- Searching area after losing player
    e_patrol_timer = e_patrol_timer - 1
    if frame_count % 60 == 0 then
      -- Wander randomly nearby
      e_target_x = clamp(ex + math.random(-4, 4), 1, COLS-2)
      e_target_y = clamp(ey + math.random(-4, 4), 1, ROWS-2)
    end
  else
    -- Patrol: wander toward random spots
    e_chase = false
    if frame_count % 90 == 0 then
      e_target_x = math.random(2, COLS-3)
      e_target_y = math.random(2, ROWS-3)
    end
  end

  -- Move toward target
  local speed = e_chase and (e_speed * 1.8) or e_speed
  local dx = e_target_x - ex
  local dy = e_target_y - ey
  local td = dist(ex, ey, e_target_x, e_target_y)

  if td > 0.5 then
    local mx = (dx / td) * speed
    local my = (dy / td) * speed

    e_move_accum_x = e_move_accum_x + mx
    e_move_accum_y = e_move_accum_y + my

    -- Move in whole tile increments when accumulated enough
    local step_x = 0
    local step_y = 0
    if math.abs(e_move_accum_x) >= 1 then
      step_x = e_move_accum_x > 0 and 1 or -1
      e_move_accum_x = e_move_accum_x - step_x
    end
    if math.abs(e_move_accum_y) >= 1 then
      step_y = e_move_accum_y > 0 and 1 or -1
      e_move_accum_y = e_move_accum_y - step_y
    end

    if step_x ~= 0 and entity_can_move(math.floor(ex + step_x), math.floor(ey)) then
      ex = ex + step_x
    end
    if step_y ~= 0 and entity_can_move(math.floor(ex), math.floor(ey + step_y)) then
      ey = ey + step_y
    end
  end

  -- Entity footstep sounds
  e_step_timer = e_step_timer + 1
  local step_interval = e_chase and 12 or 20
  if e_step_timer >= step_interval then
    e_step_timer = 0
    sfx_entity_step(d)
  end

  -- Growl when close and chasing
  if e_chase and d < 6 and frame_count % 40 == 0 then
    sfx_entity_growl()
  end

  -- CHECK IF CAUGHT PLAYER
  if d < 1.5 then
    -- JUMPSCARE!
    sfx_jumpscare()
    scare_flash = 12
    shake_timer = 15
    player_alive = false
    death_timer = 0
    hint_text = ""
    hint_timer = 0
  end

  -- Random scare when very close
  if d < 3 and math.random(100) < 4 and scare_flash <= 0 then
    scare_flash = 3
    shake_timer = 4
    noise(CH_SONAR, 0.06)
  end
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
  table.sort(ping_objects, function(a, b) return a.dist < b.dist end)

  -- ALERT THE ENTITY! The ping is audible to it.
  if e_active and player_alive then
    e_alert_x = px
    e_alert_y = py
    e_chase = true
    -- Delayed response sound
    sfx_alert_ping()
    -- Show warning
    hint_text = "...IT HEARD YOU"
    hint_timer = 40
  end
end

local function update_sonar()
  if sonar_timer > 0 then
    sonar_timer = sonar_timer - 1
  end

  if not sonar_active then return end

  sonar_radius = sonar_radius + SONAR_SPEED

  -- Create ring particles at current radius
  if frame_count % 2 == 0 then
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
          table.insert(ring_particles, {x=rx, y=ry, life=10, col=C_DARK})
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
      table.insert(ring_particles, {
        x = obj.x * TILE + 4,
        y = obj.y * TILE + 4,
        life = 20,
        col = C_WHITE
      })
    end
  end

  -- Reveal entity position with sonar! (terrifying)
  if e_active then
    local ed = dist(px, py, ex, ey)
    if sonar_radius >= ed * TILE and sonar_radius < ed * TILE + SONAR_SPEED * 2 then
      -- Entity shows up as brief flash
      table.insert(ring_particles, {
        x = ex * TILE + 4,
        y = ey * TILE + 4,
        life = 15,
        col = C_WHITE
      })
      -- Scary reveal sound
      wave(CH_OBJECT, "sawtooth")
      tone(CH_OBJECT, 150, 60, 0.1)
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
-- AMBIENT HORROR SOUNDS
----------------------------------------------------------------

local function update_ambient()
  -- Dripping water
  amb_drip_timer = amb_drip_timer - 1
  if amb_drip_timer <= 0 then
    amb_drip_timer = 50 + math.random(80)
    sfx_ambient_drip()
  end

  -- Random creak
  amb_creak_timer = amb_creak_timer - 1
  if amb_creak_timer <= 0 then
    amb_creak_timer = 100 + math.random(150)
    sfx_ambient_creak()
  end

  -- Ambient drone
  ambient_timer = ambient_timer + 1
  if ambient_timer >= 90 then
    ambient_timer = 0
    sfx_ambient_drone()
  end

  -- HEARTBEAT: based on entity proximity
  if e_active and player_alive then
    local d = dist(px, py, ex, ey)
    local target_rate = clamp(1 - (d / 15), 0, 1)
    -- Smooth transition
    heartbeat_rate = lerp(heartbeat_rate, target_rate, 0.05)
  else
    heartbeat_rate = math.max(heartbeat_rate - 0.01, 0)
  end

  if heartbeat_rate > 0.08 then
    heartbeat_timer = heartbeat_timer + 1
    -- Interval: 30 frames (calm) down to 6 frames (panic)
    local interval = math.floor(lerp(30, 6, heartbeat_rate))
    if heartbeat_timer >= interval then
      heartbeat_timer = 0
      sfx_heartbeat(heartbeat_rate)
      -- Double beat at high panic
      if heartbeat_rate > 0.5 then
        sfx_heartbeat_double(heartbeat_rate)
      end
    end
  else
    heartbeat_timer = 0
  end
end

----------------------------------------------------------------
-- PROXIMITY SOUND (continuous ambient object hinting)
----------------------------------------------------------------

local function update_proximity_sounds()
  if frame_count % 25 ~= 0 then return end

  local nearest = nil
  local nearest_dist = 999

  for _, obj in ipairs(room_objects) do
    local d = dist(px, py, obj.x, obj.y)
    if d < nearest_dist then
      nearest_dist = d
      nearest = obj
    end
  end

  if nearest and nearest_dist < 12 then
    sfx_object_ping(nearest.type, nearest_dist)
  end
end

----------------------------------------------------------------
-- DEMO MODE
----------------------------------------------------------------

local function build_demo_path()
  demo_path = {
    {dx=1, dy=0}, {dx=1, dy=0}, {dx=1, dy=0}, {dx=1, dy=0},
    {dx=1, dy=0}, {dx=1, dy=0}, {dx=1, dy=0},
    {dx=0, dy=-1}, {dx=0, dy=-1}, {dx=0, dy=-1}, {dx=0, dy=-1},
    {dx=1, dy=0}, {dx=1, dy=0}, {dx=1, dy=0}, {dx=1, dy=0},
    {dx=0, dy=0, ping=true},
    {dx=1, dy=0}, {dx=1, dy=0},
    {dx=0, dy=1}, {dx=0, dy=1}, {dx=0, dy=1}, {dx=0, dy=1}, {dx=0, dy=1},
    {dx=-1, dy=0}, {dx=-1, dy=0}, {dx=-1, dy=0},
    {dx=0, dy=0, ping=true},
    {dx=0, dy=1}, {dx=0, dy=1},
    {dx=0, dy=1}, {dx=0, dy=1}, {dx=0, dy=1},
    {dx=1, dy=0}, {dx=1, dy=0}, {dx=1, dy=0}, {dx=1, dy=0}, {dx=1, dy=0}, {dx=1, dy=0},
    {dx=0, dy=1}, {dx=0, dy=1},
  }
  demo_step = 1
  demo_timer = 0
end

local function update_demo()
  demo_timer = demo_timer + 1
  if demo_timer < 8 then return end
  demo_timer = 0

  if demo_step > #demo_path then
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
    elseif tile == T_EMPTY then
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
local title_flicker = 0
local title_timer_count = 0

local function title_update()
  title_pulse = title_pulse + 1
  title_idle_timer = title_idle_timer + 1
  title_timer_count = title_timer_count + 1

  -- Ominous ping every 60 frames
  if title_pulse % 60 == 0 then
    sfx_title_ping()
  end

  -- Random title flicker (horror)
  if title_flicker > 0 then
    title_flicker = title_flicker - 1
  elseif math.random(200) < 3 then
    title_flicker = 5
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
    update_entity()
  end

  if btnp("start") or btnp("a") then
    demo_mode = false
    scene = "game"
    current_room = 1
    load_room(1)
    hint_text = "PING TO SEE... BUT IT LISTENS"
    hint_timer = 120
  end
end

local function title_draw()
  s = screen()
  cls(s, C_BLACK)

  -- Flickering title (horror style)
  local title_c = C_WHITE
  local flick = math.random(100)
  if flick < 6 then title_c = C_DARK
  elseif flick < 12 then title_c = C_LIGHT end

  if title_flicker > 0 and title_flicker > 3 then
    title_c = C_BLACK
  end

  if title_c > C_BLACK then
    text(s, "ECHOLOCATION", W/2, 20, title_c, ALIGN_CENTER)
  end

  -- Creepy subtitle reveal
  if title_timer_count > 30 then
    text(s, "you are blind.", W/2, 40, C_DARK, ALIGN_CENTER)
  end
  if title_timer_count > 60 then
    text(s, "something breathes nearby.", W/2, 50, C_DARK, ALIGN_CENTER)
  end
  if title_timer_count > 90 then
    text(s, "every sound reveals... and betrays.", W/2, 60, C_DARK, ALIGN_CENTER)
  end

  -- Sonar ring visual on title
  local ring_r = (title_pulse % 60) * 1.5
  if ring_r < 80 then
    local cx, cy = W/2, 85
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
    pix(s, cx, 85, C_WHITE)
  end

  -- Entity eyes blinking in the dark (horror touch)
  if title_timer_count > 100 then
    local blink = math.floor(title_pulse / 20) % 5
    if blink < 2 then
      local eye_x = W/2 + math.sin(title_pulse * 0.02) * 30
      local eye_y = 85 + math.cos(title_pulse * 0.015) * 8
      pix(s, math.floor(eye_x) - 1, math.floor(eye_y), C_LIGHT)
      pix(s, math.floor(eye_x) + 1, math.floor(eye_y), C_LIGHT)
    end
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

  -- Blink prompt
  if title_pulse % 40 < 25 then
    text(s, "PRESS START", W/2, 110, C_LIGHT, ALIGN_CENTER)
  end
end

----------------------------------------------------------------
-- GAME SCENE
----------------------------------------------------------------

local function try_move(dx, dy)
  if not player_alive then return end

  local nx = px + dx
  local ny = py + dy
  local tile = get_tile(nx, ny)

  if tile == T_WALL then
    sfx_wall_bump()
    hint_text = "WALL"
    hint_timer = 15
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
    if current_room < 3 then
      current_room = current_room + 1
      load_room(current_room)
      hint_text = "ROOM " .. current_room .. " - IT FOLLOWS"
      hint_timer = 60
    else
      scene = "victory"
      victory_timer = 0
      sfx_victory()
    end
    return
  end

  -- Empty tile - move
  px, py = nx, ny
  sfx_footstep()
  player_moving = true
end

local function game_update()
  if not player_alive then
    death_timer = death_timer + 1
    -- Scare effects decay
    if scare_flash > 0 then scare_flash = scare_flash - 1 end
    if shake_timer > 0 then shake_timer = shake_timer - 1 end
    if death_timer > 90 and (btnp("start") or btnp("a")) then
      load_room(current_room)
      hint_text = "TRY AGAIN... QUIETLY"
      hint_timer = 60
    end
    return
  end

  if paused then
    if btnp("select") then paused = false end
    return
  end

  if btnp("select") then
    paused = true
    return
  end

  frame_count = frame_count + 1
  player_moving = false

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

  -- Sonar ping on A (THE GAMBLE)
  if btnp("a") then
    do_sonar_ping()
  end

  update_sonar()
  update_entity()
  update_proximity_sounds()
  update_ambient()

  -- Scare effects decay
  if scare_flash > 0 then scare_flash = scare_flash - 1 end
  if shake_timer > 0 then
    shake_timer = shake_timer - 1
    shake_x = math.random(-3, 3)
    shake_y = math.random(-2, 2)
  else
    shake_x = 0
    shake_y = 0
  end

  -- Hint decay
  if hint_timer > 0 then
    hint_timer = hint_timer - 1
  end
end

local function game_draw()
  s = screen()
  cls(s, C_BLACK)

  -- Jump scare flash
  if scare_flash > 0 then
    cls(s, scare_flash > 6 and C_WHITE or C_LIGHT)
    if not player_alive and scare_flash > 4 then
      -- Flash entity face (two big eyes)
      local cx, cy = W/2, H/2
      -- Left eye
      rectf(s, cx - 20, cy - 10, 12, 8, C_BLACK)
      pix(s, cx - 15, cy - 7, C_WHITE)
      pix(s, cx - 14, cy - 7, C_WHITE)
      -- Right eye
      rectf(s, cx + 8, cy - 10, 12, 8, C_BLACK)
      pix(s, cx + 13, cy - 7, C_WHITE)
      pix(s, cx + 14, cy - 7, C_WHITE)
      -- Mouth
      line(s, cx - 15, cy + 5, cx + 15, cy + 5, C_BLACK)
      return
    end
    if scare_flash > 3 then return end
  end

  -- Player dot (always visible)
  local draw_px = px * TILE + 4 + shake_x
  local draw_py = py * TILE + 4 + shake_y

  if player_alive then
    pix(s, draw_px, draw_py, C_WHITE)
    -- Breathing pulse (cross)
    local breathe = math.sin(frame_count * 0.08)
    if breathe > 0 then
      pix(s, draw_px - 1, draw_py, C_DARK)
      pix(s, draw_px + 1, draw_py, C_DARK)
      pix(s, draw_px, draw_py - 1, C_DARK)
      pix(s, draw_px, draw_py + 1, C_DARK)
    end
  end

  -- Sonar ring particles
  for _, p in ipairs(ring_particles) do
    local rx = math.floor(p.x) + shake_x
    local ry = math.floor(p.y) + shake_y
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

  -- Entity: show as pair of eyes when close enough (even without sonar)
  if e_active and player_alive then
    local ed = dist(px, py, ex, ey)
    if ed < 5 then
      local epx = math.floor(ex * TILE + 4) + shake_x
      local epy = math.floor(ey * TILE + 4) + shake_y
      local blink = math.floor(frame_count / 8) % 5
      if blink < 3 then
        local brightness = ed < 3 and C_WHITE or C_LIGHT
        pix(s, epx - 1, epy, brightness)
        pix(s, epx + 1, epy, brightness)
      end
    end
  end

  -- Key indicator (top right)
  if has_key then
    text(s, "K", W - 8, 2, C_WHITE)
  end

  -- Room number
  text(s, current_room .. "/3", 4, 2, C_DARK)

  -- Heartbeat indicator (visual pulse around edges when panicked)
  if heartbeat_rate > 0.3 then
    local pulse = math.sin(frame_count * 0.3) * heartbeat_rate
    if pulse > 0.3 then
      local c = heartbeat_rate > 0.7 and C_LIGHT or C_DARK
      -- Vignette pulse on edges
      for i = 0, W-1, 4 do
        pix(s, i, 0, c)
        pix(s, i, H-1, c)
      end
      for i = 0, H-1, 4 do
        pix(s, 0, i, c)
        pix(s, W-1, i, c)
      end
    end
  end

  -- Sonar cooldown bar
  if sonar_timer > 0 then
    local bar_w = math.floor((sonar_timer / SONAR_COOLDOWN) * 16)
    rectf(s, W/2 - 8, H - 5, bar_w, 2, C_DARK)
  else
    if frame_count % 40 < 30 then
      pix(s, W/2, H - 4, C_LIGHT)
    end
  end

  -- Hint text
  if hint_timer > 0 then
    local hcol = hint_timer > 15 and C_LIGHT or C_DARK
    text(s, hint_text, W/2, H - 14, hcol, ALIGN_CENTER)
  end

  -- Death overlay
  if not player_alive and scare_flash <= 0 then
    text(s, "IT GOT YOU", W/2, H/2 - 8, C_WHITE, ALIGN_CENTER)
    if death_timer > 30 then
      text(s, "ROOM " .. current_room, W/2, H/2 + 4, C_DARK, ALIGN_CENTER)
    end
    if death_timer > 60 then
      if frame_count % 40 < 25 then
        text(s, "PRESS START", W/2, H/2 + 16, C_LIGHT, ALIGN_CENTER)
      end
    end
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
    title_timer_count = 0
    demo_mode = false
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
    text(s, "SILENCE", W/2, H/2 - 12, C_WHITE, ALIGN_CENTER)
  end
  if victory_timer > 50 then
    text(s, "YOU ESCAPED", W/2, H/2, C_LIGHT, ALIGN_CENTER)
    text(s, "THE DARKNESS", W/2, H/2 + 12, C_LIGHT, ALIGN_CENTER)
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
  title_timer_count = 0
  demo_mode = false
  frame_count = 0
  amb_drip_timer = 30
  amb_creak_timer = 60
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
