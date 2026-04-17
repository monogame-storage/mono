-- ABYSSAL PING
-- Agent 25 (Wave 3) — Infinite procedural horror with sonar
-- Merged: Agent 13 (sonar+stalker) + Agent 14 (procedural rooms) + Agent 19 (escalating horror)
-- Navigate by sound. Entity hunts by sound. Horror escalates with depth.
-- 160x120 | 2-bit | mode(2)

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

-- Demo / idle
local IDLE_TIMEOUT = 150
local DEMO_DURATION = 600

----------------------------------------------------------------
-- SEEDED PRNG (xorshift32)
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
-- UTILITY
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
local player_alive = true

-- Entity (stalker)
local ex, ey = 15, 3
local e_speed = 0.03
local e_active = false
local e_chase = false
local e_alert_x, e_alert_y = -1, -1
local e_patrol_timer = 0
local e_target_x, e_target_y = 15, 3
local e_step_timer = 0
local e_move_accum_x = 0
local e_move_accum_y = 0

-- Rooms
local current_room = 1
local room_map = {}
local room_objects = {}
local best_room = 0

-- Sonar ring particles
local ring_particles = {}

-- Horror state
local scare_flash = 0
local shake_timer = 0
local shake_x, shake_y = 0, 0
local entity_eyes = {}
local darkness_tendrils = {}
local static_amount = 0
local heartbeat_rate = 0
local heartbeat_timer = 0
local amb_drip_timer = 40
local amb_creak_timer = 60

-- Demo mode
local demo_mode = false
local demo_timer = 0
local demo_auto_timer = 0
local demo_ping_cd = 0
local title_idle_timer = 0

-- Ambient
local ambient_timer = 0

-- Hint text
local hint_text = ""
local hint_timer = 0

-- Death
local death_timer = 0

-- Footstep alternator
local foot_alt = false

----------------------------------------------------------------
-- MAP ACCESS
----------------------------------------------------------------
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

-- Horror sounds
local function sfx_heartbeat_sound(intensity)
  wave(CH_AMBIENT, "sine")
  local base = lerp(50, 70, intensity)
  tone(CH_AMBIENT, base, base * 0.7, 0.06)
end

local function sfx_entity_step(d)
  if d > 15 then return end
  local vol_t = clamp(1 - d / 15, 0, 1)
  local freq = lerp(200, 100, vol_t)
  local dur = lerp(0.01, 0.04, vol_t)
  wave(CH_FOOTSTEP, "square")
  tone(CH_FOOTSTEP, freq, freq * 0.8, dur)
end

local function sfx_entity_growl()
  wave(CH_AMBIENT, "sawtooth")
  tone(CH_AMBIENT, 45, 35, 0.12)
end

local function sfx_jumpscare()
  noise(CH_SONAR, 0.2)
  wave(CH_OBJECT, "sawtooth")
  tone(CH_OBJECT, 80, 40, 0.3)
  noise(CH_FOOTSTEP, 0.15)
  wave(CH_AMBIENT, "square")
  tone(CH_AMBIENT, 100, 50, 0.25)
end

local function sfx_alert_ping()
  wave(CH_OBJECT, "square")
  tone(CH_OBJECT, 120, 80, 0.08)
end

local function sfx_ambient_drip()
  wave(CH_OBJECT, "sine")
  local pitch = 1200 + rng_int(0, 800)
  tone(CH_OBJECT, pitch, pitch * 0.5, 0.02)
end

local function sfx_ambient_creak()
  wave(CH_AMBIENT, "sawtooth")
  local creaks = {55, 62, 48, 70}
  local f = creaks[rng_int(1, 4)]
  tone(CH_AMBIENT, f, f * 0.8, 0.1)
end

local function sfx_ambient_drone()
  wave(CH_AMBIENT, "triangle")
  tone(CH_AMBIENT, 45, 48, 0.5)
end

local function sfx_title_ping()
  wave(CH_SONAR, "sine")
  tone(CH_SONAR, 800, 600, 0.1)
end

----------------------------------------------------------------
-- HORROR SYSTEMS (from agent-19)
----------------------------------------------------------------

-- Entity eyes at screen edges
local function spawn_entity_eyes(depth)
  if #entity_eyes >= 6 then return end
  local side = rng_int(1, 4)
  local eyex, eyey
  if side == 1 then
    eyex = rng_int(10, W - 10); eyey = rng_int(2, 12)
  elseif side == 2 then
    eyex = rng_int(10, W - 10); eyey = rng_int(H - 14, H - 4)
  elseif side == 3 then
    eyex = rng_int(2, 16); eyey = rng_int(10, H - 10)
  else
    eyex = rng_int(W - 18, W - 4); eyey = rng_int(10, H - 10)
  end
  entity_eyes[#entity_eyes + 1] = {
    x = eyex, y = eyey,
    life = rng_int(30, 90),
    blink = rng_int(0, 100),
  }
end

local function update_entity_eyes()
  local i = 1
  while i <= #entity_eyes do
    local e = entity_eyes[i]
    e.life = e.life - 1
    e.blink = e.blink + 1
    if e.life <= 0 then
      entity_eyes[i] = entity_eyes[#entity_eyes]
      entity_eyes[#entity_eyes] = nil
    else
      i = i + 1
    end
  end
end

local function draw_entity_eyes(scr)
  for _, e in ipairs(entity_eyes) do
    local blinking = (e.blink % 40) < 3
    if not blinking then
      local c = (e.life < 10) and C_DARK or C_LIGHT
      pix(scr, e.x, e.y, c)
      pix(scr, e.x + 3, e.y, c)
    end
  end
end

-- Darkness tendrils creeping from edges
local function update_tendrils(urgency)
  if urgency < 0.1 then
    darkness_tendrils = {}
    return
  end
  local max_tendrils = math.floor(urgency * 20)
  while #darkness_tendrils < max_tendrils do
    local side = rng_int(1, 4)
    local t = {}
    if side == 1 then
      t.x = rng_int(0, W - 1); t.y = 0
      t.dx = (rng_int(0, 100) / 100 - 0.5) * 0.5; t.dy = 0.3 + rng_int(0, 50) / 100
    elseif side == 2 then
      t.x = rng_int(0, W - 1); t.y = H - 1
      t.dx = (rng_int(0, 100) / 100 - 0.5) * 0.5; t.dy = -(0.3 + rng_int(0, 50) / 100)
    elseif side == 3 then
      t.x = 0; t.y = rng_int(0, H - 1)
      t.dx = 0.3 + rng_int(0, 50) / 100; t.dy = (rng_int(0, 100) / 100 - 0.5) * 0.5
    else
      t.x = W - 1; t.y = rng_int(0, H - 1)
      t.dx = -(0.3 + rng_int(0, 50) / 100); t.dy = (rng_int(0, 100) / 100 - 0.5) * 0.5
    end
    t.len = math.floor(urgency * 25) + rng_int(5, 15)
    t.life = t.len
    darkness_tendrils[#darkness_tendrils + 1] = t
  end
  local i = 1
  while i <= #darkness_tendrils do
    local t = darkness_tendrils[i]
    t.x = t.x + t.dx
    t.y = t.y + t.dy
    t.life = t.life - 1
    if t.life <= 0 then
      darkness_tendrils[i] = darkness_tendrils[#darkness_tendrils]
      darkness_tendrils[#darkness_tendrils] = nil
    else
      i = i + 1
    end
  end
end

local function draw_tendrils(scr)
  for _, t in ipairs(darkness_tendrils) do
    local tx = math.floor(t.x)
    local ty = math.floor(t.y)
    if tx >= 0 and tx < W and ty >= 0 and ty < H then
      pix(scr, tx, ty, C_BLACK)
      if t.life > t.len * 0.7 then
        if tx + 1 < W then pix(scr, tx + 1, ty, C_BLACK) end
        if ty + 1 < H then pix(scr, tx, ty + 1, C_BLACK) end
      end
    end
  end
end

-- Vignette darkening edges
local function draw_vignette(scr, intensity)
  local border = math.floor(intensity * 25)
  if border < 1 then return end
  for y = 0, border - 1 do
    local c = (y < border / 2) and C_BLACK or C_DARK
    line(scr, 0, y, W - 1, y, c)
    line(scr, 0, H - 1 - y, W - 1, H - 1 - y, c)
  end
  for x = 0, border - 1 do
    local c = (x < border / 2) and C_BLACK or C_DARK
    line(scr, x, border, x, H - 1 - border, c)
    line(scr, W - 1 - x, border, W - 1 - x, H - 1 - border, c)
  end
end

-- Screen static
local function draw_static(scr, amount)
  if amount < 0.05 then return end
  local num = math.floor(amount * 50)
  for i = 1, num do
    local sx = rng_int(0, W - 1)
    local sy = rng_int(0, H - 1)
    pix(scr, sx, sy, rng_int(0, 1))
  end
end

-- Entity face flash (jump scare on death)
local function draw_entity_face(scr)
  local cx, cy = W / 2, H / 2
  circ(scr, cx, cy, 25, C_WHITE)
  circ(scr, cx, cy, 24, C_DARK)
  circ(scr, cx - 9, cy - 5, 6, C_WHITE)
  circ(scr, cx + 9, cy - 5, 6, C_WHITE)
  circ(scr, cx - 9, cy - 5, 3, C_BLACK)
  circ(scr, cx + 9, cy - 5, 3, C_BLACK)
  pix(scr, cx - 9, cy - 5, C_WHITE)
  pix(scr, cx + 9, cy - 5, C_WHITE)
  for i = -12, 12 do
    local my = cy + 10 + math.floor(math.sin(i * 0.8) * 3)
    if cx + i >= 0 and cx + i < W and my >= 0 and my < H then
      pix(scr, cx + i, my, C_WHITE)
    end
  end
end

----------------------------------------------------------------
-- PROCEDURAL ROOM GENERATION (from agent-14, enhanced)
----------------------------------------------------------------
local function generate_room(room_num)
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

  -- Difficulty scales with depth
  local complexity = math.min(room_num, 12)

  -- Internal wall segments
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
      local gap_y = rng_int(wy_start, math.min(wy_start + wy_len, ROWS - 2))
      m[gap_y][wx] = T_EMPTY
    else
      local wy = rng_int(3, ROWS - 4)
      local wx_start = rng_int(1, COLS - 5)
      local wx_len = rng_int(3, math.min(10, COLS - wx_start - 1))
      for wx = wx_start, math.min(wx_start + wx_len, COLS - 2) do
        m[wy][wx] = T_WALL
      end
      local gap_x = rng_int(wx_start, math.min(wx_start + wx_len, COLS - 2))
      m[wy][gap_x] = T_EMPTY
    end
  end

  -- Pillars in deeper rooms for cover
  if room_num >= 3 then
    local num_pillars = math.min(room_num - 2, 6)
    for i = 1, num_pillars do
      local ppx = rng_int(3, COLS - 4)
      local ppy = rng_int(3, ROWS - 4)
      if m[ppy][ppx] == T_EMPTY then
        m[ppy][ppx] = T_WALL
      end
    end
  end

  -- Place key on far side
  local key_placed = false
  for attempt = 1, 50 do
    local kx = rng_int(math.floor(COLS / 2), COLS - 2)
    local ky = rng_int(1, ROWS - 2)
    if m[ky][kx] == T_EMPTY then
      m[ky][kx] = T_KEY
      key_placed = true
      break
    end
  end
  if not key_placed then
    for y = 1, ROWS - 2 do
      for x = COLS - 3, math.floor(COLS / 2), -1 do
        if m[y][x] == T_EMPTY then
          m[y][x] = T_KEY
          key_placed = true
          break
        end
      end
      if key_placed then break end
    end
  end

  -- Place door near a wall
  local door_placed = false
  local function local_tile(tx, ty)
    if ty < 0 or ty >= ROWS or tx < 0 or tx >= COLS then return T_WALL end
    return m[ty][tx]
  end
  for attempt = 1, 50 do
    local dx = rng_int(math.floor(COLS / 3), COLS - 3)
    local dy = rng_int(2, ROWS - 3)
    if m[dy][dx] == T_EMPTY then
      if local_tile(dx-1, dy) == T_WALL or local_tile(dx+1, dy) == T_WALL
         or local_tile(dx, dy-1) == T_WALL or local_tile(dx, dy+1) == T_WALL then
        m[dy][dx] = T_DOOR
        door_placed = true
        break
      end
    end
  end
  if not door_placed then
    for y = 2, ROWS - 3 do
      for x = math.floor(COLS / 3), COLS - 3 do
        if m[y][x] == T_EMPTY then
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

  -- Place exit on far edge
  local exit_placed = false
  for attempt = 1, 50 do
    local exx = rng_int(COLS - 4, COLS - 2)
    local exy = rng_int(1, ROWS - 2)
    if m[exy][exx] == T_EMPTY then
      m[exy][exx] = T_EXIT
      exit_placed = true
      break
    end
  end
  if not exit_placed then
    m[ROWS - 2][COLS - 2] = T_EXIT
  end

  -- Entity start position: far from player, deeper = closer start
  local ent_x, ent_y = COLS - 3, rng_int(2, ROWS - 3)
  local ent_attempts = 0
  while m[ent_y][ent_x] ~= T_EMPTY and ent_attempts < 30 do
    ent_x = rng_int(math.floor(COLS * 0.6), COLS - 2)
    ent_y = rng_int(1, ROWS - 2)
    ent_attempts = ent_attempts + 1
  end

  -- Player start position near left
  local start_x, start_y = 2, 7
  for attempt = 1, 50 do
    local sx = rng_int(1, 4)
    local sy = rng_int(1, ROWS - 2)
    if m[sy][sx] == T_EMPTY then
      start_x, start_y = sx, sy
      break
    end
  end

  return m, start_x, start_y, ent_x, ent_y
end

----------------------------------------------------------------
-- ROOM MANAGEMENT
----------------------------------------------------------------
local function load_room(num)
  has_key = false
  sonar_active = false
  sonar_radius = 0
  sonar_timer = 0
  ping_objects = {}
  ring_particles = {}
  hint_text = ""
  hint_timer = 0
  player_alive = true
  scare_flash = 0
  shake_timer = 0
  death_timer = 0
  entity_eyes = {}
  darkness_tendrils = {}
  static_amount = 0

  local start_x, start_y, ent_x, ent_y
  room_map, start_x, start_y, ent_x, ent_y = generate_room(num)
  px, py = start_x, start_y

  -- Entity setup: gets faster and starts closer with depth
  ex, ey = ent_x, ent_y
  e_active = true
  e_chase = false
  e_alert_x, e_alert_y = -1, -1
  e_speed = 0.02 + math.min(num, 15) * 0.006
  e_patrol_timer = 0
  e_step_timer = 0
  e_move_accum_x = 0
  e_move_accum_y = 0
  e_target_x, e_target_y = rng_int(2, COLS - 3), rng_int(2, ROWS - 3)

  room_objects = find_objects()
end

----------------------------------------------------------------
-- HORROR URGENCY (depth-based escalation)
----------------------------------------------------------------
local function get_urgency()
  -- Escalates with room depth: room 1 = 0, room 10+ = near max
  local base = clamp((current_room - 1) / 10, 0, 0.8)
  -- Also spikes when entity is close
  local d = dist(px, py, ex, ey)
  local proximity = clamp(1 - d / 12, 0, 0.4)
  return clamp(base + proximity, 0, 1)
end

----------------------------------------------------------------
-- AMBIENT HORROR UPDATE
----------------------------------------------------------------
local function update_horror()
  local urgency = get_urgency()

  -- Drips
  amb_drip_timer = amb_drip_timer - 1
  if amb_drip_timer <= 0 then
    amb_drip_timer = 40 + rng_int(0, 80)
    sfx_ambient_drip()
  end

  -- Creaks (more frequent deeper)
  amb_creak_timer = amb_creak_timer - 1
  if amb_creak_timer <= 0 then
    amb_creak_timer = math.floor(lerp(120, 30, urgency)) + rng_int(0, 60)
    sfx_ambient_creak()
  end

  -- Heartbeat
  heartbeat_rate = urgency
  if heartbeat_rate > 0.15 then
    heartbeat_timer = heartbeat_timer - 1
    local interval = math.floor(lerp(30, 8, heartbeat_rate))
    if heartbeat_timer <= 0 then
      heartbeat_timer = interval
      sfx_heartbeat_sound(heartbeat_rate)
    end
  end

  -- Eyes watching from darkness
  update_entity_eyes()
  if urgency > 0.2 and rng_int(1, 100) < math.floor(urgency * 10) then
    spawn_entity_eyes(current_room)
  end

  -- Tendrils
  update_tendrils(urgency)

  -- Static
  static_amount = 0
  if urgency > 0.5 then
    static_amount = (urgency - 0.5) * 0.5
  end

  -- Scare flash countdown
  if scare_flash > 0 then scare_flash = scare_flash - 1 end
  if shake_timer > 0 then
    shake_timer = shake_timer - 1
    shake_x = rng_int(-2, 2)
    shake_y = rng_int(-2, 2)
  else
    shake_x, shake_y = 0, 0
  end

  -- Ambient drone
  ambient_timer = ambient_timer + 1
  if ambient_timer >= 90 then
    ambient_timer = 0
    sfx_ambient_drone()
  end
end

----------------------------------------------------------------
-- ENTITY AI (from agent-13)
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
    e_chase = true
    e_target_x = e_alert_x
    e_target_y = e_alert_y
    if dist(ex, ey, e_alert_x, e_alert_y) < 2 then
      e_alert_x, e_alert_y = -1, -1
      e_patrol_timer = 120
    end
  elseif d < 4 then
    e_chase = true
    e_target_x = px
    e_target_y = py
  elseif e_patrol_timer > 0 then
    e_patrol_timer = e_patrol_timer - 1
    if frm % 60 == 0 then
      e_target_x = clamp(math.floor(ex) + rng_int(-4, 4), 1, COLS-2)
      e_target_y = clamp(math.floor(ey) + rng_int(-4, 4), 1, ROWS-2)
    end
  else
    e_chase = false
    if frm % 90 == 0 then
      e_target_x = rng_int(2, COLS-3)
      e_target_y = rng_int(2, ROWS-3)
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

    local step_x, step_y = 0, 0
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
  if e_chase and d < 6 and frm % 40 == 0 then
    sfx_entity_growl()
  end

  -- CHECK IF CAUGHT PLAYER
  if d < 1.5 then
    sfx_jumpscare()
    scare_flash = 15
    shake_timer = 20
    player_alive = false
    death_timer = 0
    hint_text = ""
    hint_timer = 0
  end

  -- Random scare when very close
  if d < 3 and rng_int(1, 100) < 4 and scare_flash <= 0 then
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

  ping_objects = {}
  for _, obj in ipairs(room_objects) do
    local d = dist(px, py, obj.x, obj.y)
    if d < 18 then
      table.insert(ping_objects, {x=obj.x, y=obj.y, type=obj.type, dist=d, pinged=false})
    end
  end
  table.sort(ping_objects, function(a, b) return a.dist < b.dist end)

  -- ALERT THE ENTITY
  if e_active and player_alive then
    e_alert_x = px
    e_alert_y = py
    e_chase = true
    sfx_alert_ping()
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
          table.insert(ring_particles, {x=rx, y=ry, life=10, col=C_DARK})
        else
          table.insert(ring_particles, {x=rx, y=ry, life=4, col=C_DARK})
        end
      end
    end
  end

  -- Ping objects as ring reaches them
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

  -- Also reveal entity position briefly if sonar reaches it
  local ed = dist(px, py, ex, ey)
  if sonar_radius >= ed * TILE and sonar_radius < ed * TILE + SONAR_SPEED * 2 then
    table.insert(ring_particles, {
      x = ex * TILE + 4,
      y = ey * TILE + 4,
      life = 12,
      col = C_WHITE
    })
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
-- PROXIMITY SOUNDS
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
-- PLAYER MOVEMENT
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
      wave(CH_OBJECT, "square")
      tone(CH_OBJECT, 100, 80, 0.1)
    end
    return
  end

  if tile == T_EXIT then
    sfx_exit_enter()
    current_room = current_room + 1
    if current_room > best_room then
      best_room = current_room
    end
    load_room(current_room)
    hint_text = "ROOM " .. current_room .. " - DEEPER..."
    hint_timer = 60
    return
  end

  -- Empty tile
  px, py = nx, ny
  sfx_footstep()
end

----------------------------------------------------------------
-- DEMO MODE
----------------------------------------------------------------
local function update_demo()
  demo_timer = demo_timer + 1
  demo_auto_timer = demo_auto_timer + 1

  demo_ping_cd = demo_ping_cd - 1
  if demo_ping_cd <= 0 then
    do_sonar_ping()
    demo_ping_cd = 45
  end

  if demo_auto_timer < 8 then return end
  demo_auto_timer = 0

  local dirs = {{1,0},{-1,0},{0,1},{0,-1}}
  local di = rng_int(1, 4)
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
    current_room = current_room + 1
    load_room(current_room)
  elseif tile == T_EMPTY then
    px, py = nx, ny
    sfx_footstep()
  end

  -- Reset demo periodically
  if demo_timer > DEMO_DURATION then
    demo_timer = 0
    current_room = 1
    load_room(1)
  end
end

----------------------------------------------------------------
-- TITLE SCENE
----------------------------------------------------------------
local title_reveal = 0

local function title_update()
  title_pulse = title_pulse + 1
  title_reveal = title_reveal + 1
  title_idle_timer = title_idle_timer + 1

  if title_pulse % 60 == 0 then
    sfx_title_ping()
  end

  -- Enter demo after idle
  if title_idle_timer > IDLE_TIMEOUT and not demo_mode then
    demo_mode = true
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
    update_entity()
    update_horror()
  end

  if btnp("start") or btnp("a") then
    demo_mode = false
    scene = "game"
    seed_val = (frm * 31337 + 7919) & 0xFFFF
    if seed_val == 0 then seed_val = 1 end
    current_room = 1
    best_room = 0
    load_room(1)
    hint_text = "PRESS A TO PING"
    hint_timer = 90
  end
end

local function title_draw()
  s = screen()
  cls(s, C_BLACK)

  -- Atmospheric flicker
  if rng_int(1, 100) < 3 then
    cls(s, C_DARK)
  end

  local flick = rng_int(1, 100)
  local tc = C_WHITE
  if flick < 5 then tc = C_DARK
  elseif flick < 10 then tc = C_LIGHT end

  text(s, "ABYSSAL PING", W/2, 16, tc, ALIGN_CENTER)

  line(s, 30, 26, 130, 26, C_DARK)

  -- Staged horror reveal
  if title_reveal > 20 then
    text(s, "you are blind.", W/2, 33, C_DARK, ALIGN_CENTER)
  end
  if title_reveal > 50 then
    text(s, "something hunts by sound.", W/2, 43, C_DARK, ALIGN_CENTER)
  end
  if title_reveal > 80 then
    text(s, "every ping reveals...", W/2, 53, C_LIGHT, ALIGN_CENTER)
  end
  if title_reveal > 110 then
    text(s, "...and betrays.", W/2, 63, C_LIGHT, ALIGN_CENTER)
  end

  -- Sonar ring animation
  local ring_r = (title_pulse % 60) * 1.5
  if ring_r < 80 then
    local cx, cy = W/2, 82
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
    pix(s, cx, 82, C_WHITE)
  end

  -- Demo overlay
  if demo_mode then
    local dpx = px * TILE + 4
    local dpy = py * TILE + 4
    pix(s, dpx, dpy, C_WHITE)
    for _, p in ipairs(ring_particles) do
      if p.x >= 0 and p.x < W and p.y >= 0 and p.y < H then
        pix(s, math.floor(p.x), math.floor(p.y), p.col)
      end
    end
    draw_entity_eyes(s)
    text(s, "- DEMO -", W/2, 4, C_DARK, ALIGN_CENTER)
  end

  -- Ambient eyes in title darkness
  if title_reveal > 60 and rng_int(1, 100) < 5 then
    local exx = rng_int(10, W - 10)
    local eyy = rng_int(90, H - 8)
    pix(s, exx, eyy, C_DARK)
    pix(s, exx + 3, eyy, C_DARK)
  end

  if title_reveal > 130 and title_pulse % 40 < 25 then
    text(s, "PRESS START", W/2, 100, C_WHITE, ALIGN_CENTER)
  end

  text(s, "A:Ping  D-PAD:Move", W/2, 112, C_DARK, ALIGN_CENTER)
end

----------------------------------------------------------------
-- GAME SCENE
----------------------------------------------------------------
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

  if not player_alive then
    death_timer = death_timer + 1
    if death_timer > 60 and (btnp("start") or btnp("a")) then
      scene = "death"
    end
    return
  end

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
  update_entity()
  update_horror()

  if hint_timer > 0 then
    hint_timer = hint_timer - 1
  end
end

local function game_draw()
  s = screen()
  cls(s, C_BLACK)

  local ox, oy = shake_x, shake_y

  -- Player dot
  local draw_px = px * TILE + 4 + ox
  local draw_py = py * TILE + 4 + oy
  if player_alive then
    pix(s, draw_px, draw_py, C_WHITE)
    if frm % 30 < 20 then
      pix(s, draw_px - 1, draw_py, C_DARK)
      pix(s, draw_px + 1, draw_py, C_DARK)
      pix(s, draw_px, draw_py - 1, C_DARK)
      pix(s, draw_px, draw_py + 1, C_DARK)
    end
  end

  -- Sonar ring particles
  for _, p in ipairs(ring_particles) do
    local rx = math.floor(p.x) + ox
    local ry = math.floor(p.y) + oy
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

  -- Entity eyes from horror system
  draw_entity_eyes(s)

  -- Darkness tendrils
  draw_tendrils(s)

  -- Vignette (depth-based)
  local urgency = get_urgency()
  draw_vignette(s, urgency)

  -- Static
  draw_static(s, static_amount)

  -- Scare flash
  if scare_flash > 0 then
    cls(s, C_WHITE)
    if not player_alive and death_timer < 15 then
      draw_entity_face(s)
    end
  end

  -- Key indicator
  if has_key then
    text(s, "K", W - 8, 2, C_WHITE)
  end

  -- Room / seed info
  text(s, "R:" .. current_room, 4, 2, C_DARK)
  text(s, "S:" .. seed_val, W - 4, 2, C_DARK, ALIGN_RIGHT)

  -- Sonar cooldown indicator
  if sonar_timer > 0 then
    local bar_w = math.floor((sonar_timer / SONAR_COOLDOWN) * 16)
    rectf(s, W/2 - 8, H - 5, bar_w, 2, C_DARK)
  else
    if frm % 40 < 30 and player_alive then
      pix(s, W/2, H - 4, C_LIGHT)
    end
  end

  -- Hint text
  if hint_timer > 0 then
    local hcol = hint_timer > 15 and C_LIGHT or C_DARK
    text(s, hint_text, W/2, H - 14, hcol, ALIGN_CENTER)
  end

  -- Death message
  if not player_alive and death_timer > 20 then
    text(s, "CONSUMED BY THE ABYSS", W/2, H/2 - 4, C_LIGHT, ALIGN_CENTER)
    if death_timer > 40 then
      text(s, "DEPTH: " .. (current_room - 1), W/2, H/2 + 8, C_DARK, ALIGN_CENTER)
    end
    if death_timer > 60 and frm % 40 < 25 then
      text(s, "PRESS START", W/2, H/2 + 20, C_DARK, ALIGN_CENTER)
    end
  end

  -- Pause overlay
  if paused then
    rectf(s, W/2 - 36, H/2 - 16, 72, 32, C_BLACK)
    text(s, "PAUSED", W/2, H/2 - 12, C_WHITE, ALIGN_CENTER)
    text(s, "SEED:" .. seed_val, W/2, H/2 - 2, C_DARK, ALIGN_CENTER)
    text(s, "DEPTH:" .. current_room, W/2, H/2 + 8, C_DARK, ALIGN_CENTER)
  end
end

----------------------------------------------------------------
-- DEATH SCENE
----------------------------------------------------------------
local death_scene_timer = 0

local function death_update()
  death_scene_timer = death_scene_timer + 1

  if death_scene_timer > 30 and (btnp("start") or btnp("a")) then
    scene = "title"
    title_pulse = 0
    title_idle_timer = 0
    title_reveal = 0
    demo_mode = false
    seed_val = (seed_val * 7919 + frm) & 0xFFFF
    if seed_val == 0 then seed_val = 1 end
    death_scene_timer = 0
  end
end

local function death_draw()
  s = screen()
  cls(s, C_BLACK)

  -- Flicker
  if rng_int(1, 100) < 5 then
    cls(s, C_DARK)
  end

  if death_scene_timer > 5 then
    text(s, "YOU WERE FOUND", W/2, 20, C_WHITE, ALIGN_CENTER)
  end
  if death_scene_timer > 20 then
    line(s, 40, 30, 120, 30, C_DARK)
  end
  if death_scene_timer > 30 then
    text(s, "ROOMS SURVIVED", W/2, 40, C_DARK, ALIGN_CENTER)
    local depth = current_room - 1
    text(s, "" .. depth, W/2, 54, C_WHITE, ALIGN_CENTER)
  end
  if death_scene_timer > 45 then
    text(s, "SEED:" .. seed_val, W/2, 70, C_DARK, ALIGN_CENTER)
  end
  if death_scene_timer > 55 then
    text(s, "SHARE SEED TO CHALLENGE", W/2, 84, C_DARK, ALIGN_CENTER)
  end
  if death_scene_timer > 30 and death_scene_timer % 40 < 25 then
    text(s, "PRESS START", W/2, 100, C_LIGHT, ALIGN_CENTER)
  end

  -- Ambient eyes
  draw_entity_eyes(s)
  update_entity_eyes()
  if rng_int(1, 100) < 8 then
    spawn_entity_eyes(5)
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
  title_reveal = 0
  demo_mode = false
  frm = 0
  seed_val = 42
  best_room = 0
  death_scene_timer = 0
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
  elseif scene == "death" then
    death_update()
  end
end

function _draw()
  if scene == "title" then
    title_draw()
  elseif scene == "game" then
    game_draw()
  elseif scene == "death" then
    death_draw()
  end
end
