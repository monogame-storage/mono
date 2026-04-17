-- THE DARK ROOM: Sonic Abyss
-- Agent 30 (Wave 3) — Sound Design Focus
-- Audio alone tells the story. 2 channels, maximum dread.
-- CH0 = ambience/heartbeat/drone | CH1 = events/sonar/footsteps

----------------------------------------------------------------
-- CONSTANTS
----------------------------------------------------------------
local W, H = 160, 120
local TILE = 8
local COLS, ROWS = 20, 15
local SONAR_COOLDOWN = 25
local SONAR_MAX_RADIUS = 70
local SONAR_SPEED = 2.2
local MOVE_DELAY = 4

-- Colors (2-bit)
local C_BLACK = 0
local C_DARK  = 1
local C_LIGHT = 2
local C_WHITE = 3

-- Tile types
local T_EMPTY = 0
local T_WALL  = 1
local T_KEY   = 2
local T_DOOR  = 3
local T_EXIT  = 4

-- 2 audio channels: ambience and events
local CH_AMB = 0   -- ambience, heartbeat, drone, creaks
local CH_EVT = 1   -- sonar, footsteps, object pings, scares

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local scene = "title"
local s = nil
local frame = 0
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
local foot_alt = false

-- Entity (the stalker)
local ex, ey = 15, 3
local e_speed = 0.03
local e_active = false
local e_chase = false
local e_alert_x, e_alert_y = -1, -1
local e_target_x, e_target_y = 15, 3
local e_patrol_timer = 0
local e_step_timer = 0
local e_move_accum_x = 0
local e_move_accum_y = 0

-- Scare / death
local scare_flash = 0
local shake_timer = 0
local shake_x, shake_y = 0, 0
local death_timer = 0

-- Rooms
local current_room = 1
local room_map = {}
local room_objects = {}

-- Sonar particles
local ring_particles = {}

-- Demo
local demo_mode = false
local demo_timer = 0
local demo_path = {}
local demo_step = 1

-- Ambient sound scheduling
local amb_drip_timer = 40
local amb_creak_timer = 80
local amb_drone_timer = 0
local amb_thud_timer = 120
local amb_wind_timer = 200

-- Heartbeat
local heartbeat_timer = 0
local heartbeat_rate = 0
local heartbeat_phase = 0  -- 0=lub, 1=dub, 2=rest

-- Silence system: suppress ambient near entity
local silence_factor = 1.0

-- Hint
local hint_text = ""
local hint_timer = 0

-- Victory
local victory_timer = 0

-- Musical note frequencies (for sonar chord)
local NOTE_C4  = 262
local NOTE_E4  = 330
local NOTE_G4  = 392
local NOTE_C5  = 523
local NOTE_Eb4 = 311  -- minor third for dread

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

local function dist_to_freq(d, lo, hi)
  local max_d = 20
  local t = math.max(0, math.min(1, 1 - d / max_d))
  return lo + (hi - lo) * t * t
end

local function dist_to_dur(d)
  local max_d = 20
  local t = math.max(0, math.min(1, 1 - d / max_d))
  return 0.02 + t * 0.10
end

----------------------------------------------------------------
-- SOUND DESIGN — The Heart of Agent 30
----------------------------------------------------------------

-- === FOOTSTEPS ===
-- Alternating pitch, slight randomness for organic feel
local function sfx_footstep()
  foot_alt = not foot_alt
  wave(CH_EVT, "triangle")
  if foot_alt then
    tone(CH_EVT, 85 + math.random(10), 55, 0.025)
  else
    tone(CH_EVT, 72 + math.random(8), 48, 0.025)
  end
end

-- Wall bump: short noise, feels tactile
local function sfx_wall_bump()
  noise(CH_EVT, 0.035)
end

-- === SONAR PING ===
-- Musical: descending minor chord (root -> fifth) creating dread
local function sfx_sonar_ping()
  -- Start with high sine, sweep down through a minor interval
  wave(CH_EVT, "sine")
  tone(CH_EVT, NOTE_C5, NOTE_Eb4, 0.18)
  -- Simultaneous drone on ambience channel: the fifth, quieter
  wave(CH_AMB, "triangle")
  tone(CH_AMB, NOTE_G4, NOTE_C4 * 0.8, 0.22)
end

-- === OBJECT SIGNATURES ===
-- Each object type has a completely unique waveform + frequency profile

local function sfx_object_ping(obj_type, d)
  local dur = dist_to_dur(d)
  if dur < 0.02 then return end

  if obj_type == T_KEY then
    -- Key: bright ascending sine arpeggio (hope)
    local f = dist_to_freq(d, 800, 2200)
    wave(CH_EVT, "sine")
    tone(CH_EVT, f, f * 1.5, dur)
  elseif obj_type == T_DOOR then
    if has_key then
      -- Unlockable: warm triangle, gentle rise
      local f = dist_to_freq(d, 200, 600)
      wave(CH_EVT, "triangle")
      tone(CH_EVT, f, f * 1.2, dur)
    else
      -- Locked: buzzy square, descending (rejection)
      local f = dist_to_freq(d, 120, 350)
      wave(CH_EVT, "square")
      tone(CH_EVT, f, f * 0.7, dur)
    end
  elseif obj_type == T_EXIT then
    -- Exit: harmonic sweep across both channels (resolution)
    local f = dist_to_freq(d, 400, 1200)
    wave(CH_EVT, "sine")
    tone(CH_EVT, f, f * 1.6, dur)
    wave(CH_AMB, "triangle")
    tone(CH_AMB, f * 0.75, f * 1.2, dur * 0.8)
  end
end

-- === KEY PICKUP ===
-- Triumphant ascending chord
local function sfx_key_pickup()
  wave(CH_EVT, "sine")
  tone(CH_EVT, NOTE_C4, NOTE_C5 * 1.5, 0.15)
  wave(CH_AMB, "triangle")
  tone(CH_AMB, NOTE_E4, NOTE_G4 * 2, 0.12)
end

-- === DOOR OPEN ===
-- Heavy mechanical: low square + triangle sweep
local function sfx_door_open()
  wave(CH_EVT, "square")
  tone(CH_EVT, 120, 300, 0.2)
  wave(CH_AMB, "triangle")
  tone(CH_AMB, 80, 200, 0.25)
end

-- === EXIT ENTER ===
-- Release: bright ascending on both channels
local function sfx_exit_enter()
  wave(CH_EVT, "sine")
  tone(CH_EVT, 400, 1400, 0.3)
  wave(CH_AMB, "sine")
  tone(CH_AMB, 500, 1200, 0.3)
end

-- === HEARTBEAT SYSTEM ===
-- Musical heartbeat: lub-DUB pattern with pitch tied to danger
-- Uses sine wave for warmth, frequency drops with intensity (more bass = more dread)
local function sfx_heartbeat_lub(intensity)
  wave(CH_AMB, "sine")
  local base = lerp(65, 45, intensity)  -- deeper when more scared
  tone(CH_AMB, base, base * 0.65, 0.05)
end

local function sfx_heartbeat_dub(intensity)
  wave(CH_AMB, "sine")
  local base = lerp(55, 38, intensity)  -- dub is lower
  tone(CH_AMB, base * 1.1, base * 0.5, 0.04)
end

-- === AMBIENT SOUNDSCAPE ===

-- Water drip: high sine plink with random pitch
local function sfx_drip()
  if silence_factor < 0.3 then return end  -- silenced near entity
  wave(CH_EVT, "sine")
  local pitch = 1400 + math.random(1000)
  tone(CH_EVT, pitch, pitch * 0.4, 0.015)
end

-- Creak: low sawtooth wobble (wood stress)
local function sfx_creak()
  if silence_factor < 0.3 then return end
  wave(CH_AMB, "sawtooth")
  local creaks = {48, 55, 62, 70, 42}
  local f = creaks[math.random(#creaks)]
  tone(CH_AMB, f, f * 0.75 + math.random(5), 0.08)
end

-- Distant thud: muffled triangle pulse
local function sfx_thud()
  if silence_factor < 0.3 then return end
  wave(CH_AMB, "triangle")
  tone(CH_AMB, 40 + math.random(15), 30, 0.06)
end

-- Wind: filtered noise burst
local function sfx_wind()
  if silence_factor < 0.3 then return end
  noise(CH_AMB, 0.08)
end

-- Base drone: ever-present low hum
local function sfx_drone()
  if silence_factor < 0.2 then return end
  wave(CH_AMB, "triangle")
  -- Slowly oscillating pitch for unease
  local pitch = 42 + math.sin(frame * 0.01) * 5
  tone(CH_AMB, pitch, pitch + 3, 0.4)
end

-- === ENTITY SOUNDS ===

-- Entity footstep: heavier, lower, square wave (mechanical dread)
local function sfx_entity_step(d)
  if d > 14 then return end
  local vol_t = clamp(1 - d / 14, 0, 1)
  local freq = lerp(180, 70, vol_t)
  local dur = lerp(0.01, 0.05, vol_t)
  wave(CH_EVT, "square")
  tone(CH_EVT, freq, freq * 0.7, dur)
end

-- Entity growl: detuned sawtooth rumble (unique signature)
local function sfx_entity_growl(d)
  if d > 8 then return end
  local intensity = clamp(1 - d / 8, 0, 1)
  wave(CH_AMB, "sawtooth")
  local f = lerp(50, 35, intensity)
  tone(CH_AMB, f, f * 0.6, lerp(0.06, 0.15, intensity))
end

-- Entity alert response: when it hears your ping
local function sfx_alert_response()
  -- Ominous low answer on ambience channel
  wave(CH_AMB, "square")
  tone(CH_AMB, 90, 55, 0.1)
end

-- Jumpscare: blast both channels simultaneously
local function sfx_jumpscare()
  noise(CH_EVT, 0.25)
  wave(CH_AMB, "sawtooth")
  tone(CH_AMB, 100, 30, 0.3)
end

-- === VICTORY ===
local function sfx_victory()
  wave(CH_EVT, "sine")
  tone(CH_EVT, NOTE_C4, NOTE_C5, 0.2)
  wave(CH_AMB, "triangle")
  tone(CH_AMB, NOTE_E4, NOTE_G4 * 2, 0.25)
end

-- === TITLE ===
local function sfx_title_ping()
  wave(CH_EVT, "sine")
  tone(CH_EVT, 700, 500, 0.1)
end

----------------------------------------------------------------
-- ROOM DATA
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
  for y = 1, 8 do m[y][10] = T_WALL end
  for x = 10, 14 do m[8][x] = T_WALL end
  m[4][4] = T_WALL
  m[4][7] = T_WALL
  m[10][5] = T_WALL
  m[10][15] = T_WALL
  m[3][15] = T_KEY
  m[8][12] = T_DOOR
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
  for y = 0, 10 do m[y][5] = T_WALL end
  for y = 4, 14 do m[y][10] = T_WALL end
  for y = 0, 8 do m[y][15] = T_WALL end
  for x = 5, 10 do m[4][x] = T_WALL end
  for x = 10, 15 do m[10][x] = T_WALL end
  m[2][18] = T_KEY
  m[10][13] = T_DOOR
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
  for x = 3, 17 do m[7][x] = T_WALL end
  for y = 2, 12 do m[y][10] = T_WALL end
  m[7][6] = T_EMPTY
  m[7][14] = T_EMPTY
  m[5][10] = T_EMPTY
  m[10][10] = T_EMPTY
  m[3][4] = T_WALL; m[11][4] = T_WALL
  m[3][16] = T_WALL; m[11][16] = T_WALL
  m[3][17] = T_KEY
  m[7][10] = T_DOOR
  m[13][10] = T_EXIT
  return m
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
  scare_flash = 0
  shake_timer = 0
  death_timer = 0
  heartbeat_rate = 0
  heartbeat_timer = 0
  heartbeat_phase = 0
  silence_factor = 1.0

  -- Reset ambient timers with room-specific randomization
  amb_drip_timer = 30 + math.random(40)
  amb_creak_timer = 60 + math.random(80)
  amb_thud_timer = 90 + math.random(60)
  amb_wind_timer = 150 + math.random(100)
  amb_drone_timer = 0

  if num == 1 then
    room_map = build_room_1()
    px, py = 2, 7
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
  e_speed = 0.02 + num * 0.008
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

  -- Update silence factor: closer entity = more silence in ambient
  local target_silence = clamp(d / 10, 0, 1)
  silence_factor = lerp(silence_factor, target_silence, 0.03)

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
    if frame % 60 == 0 then
      e_target_x = clamp(ex + math.random(-4, 4), 1, COLS-2)
      e_target_y = clamp(ey + math.random(-4, 4), 1, ROWS-2)
    end
  else
    e_chase = false
    if frame % 90 == 0 then
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

  -- Entity footstep sounds (heavier, spaced based on chase state)
  e_step_timer = e_step_timer + 1
  local step_interval = e_chase and 10 or 18
  if e_step_timer >= step_interval then
    e_step_timer = 0
    sfx_entity_step(d)
  end

  -- Growl when close and chasing
  if e_chase and d < 7 and frame % 35 == 0 then
    sfx_entity_growl(d)
  end

  -- CHECK IF CAUGHT
  if d < 1.5 then
    sfx_jumpscare()
    scare_flash = 14
    shake_timer = 18
    player_alive = false
    death_timer = 0
    hint_text = ""
    hint_timer = 0
  end

  -- Random close scare
  if d < 3 and math.random(100) < 3 and scare_flash <= 0 then
    scare_flash = 3
    shake_timer = 4
    noise(CH_EVT, 0.05)
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
    sfx_alert_response()
    hint_text = "...IT HEARD YOU"
    hint_timer = 45
  end
end

local function update_sonar()
  if sonar_timer > 0 then
    sonar_timer = sonar_timer - 1
  end

  if not sonar_active then return end

  sonar_radius = sonar_radius + SONAR_SPEED

  -- Ring particles
  if frame % 2 == 0 then
    local angle_count = 20
    for i = 0, angle_count - 1 do
      local a = (i / angle_count) * math.pi * 2
      local rx = px * TILE + 4 + math.cos(a) * sonar_radius
      local ry = py * TILE + 4 + math.sin(a) * sonar_radius
      if rx >= 0 and rx < W and ry >= 0 and ry < H then
        local tx = math.floor(rx / TILE)
        local ty = math.floor(ry / TILE)
        local tile = get_tile(tx, ty)
        if tile == T_WALL then
          -- Walls persist longer (echo)
          table.insert(ring_particles, {x=rx, y=ry, life=12, col=C_DARK})
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
        life = 22,
        col = C_WHITE
      })
    end
  end

  -- Reveal entity with sonar (terrifying moment)
  if e_active and player_alive then
    local ed = dist(px, py, ex, ey)
    if sonar_radius >= ed * TILE and sonar_radius < ed * TILE + SONAR_SPEED * 2 then
      table.insert(ring_particles, {
        x = ex * TILE + 4,
        y = ey * TILE + 4,
        life = 18,
        col = C_WHITE
      })
      -- Unique entity reveal: detuned sawtooth stab
      wave(CH_EVT, "sawtooth")
      tone(CH_EVT, 160, 55, 0.12)
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
-- AMBIENT SOUNDSCAPE ENGINE
-- Layered: drips, creaks, thuds, wind, drone
-- All respect silence_factor (fades near entity)
----------------------------------------------------------------

local function update_ambient_sounds()
  -- Water drips (random high plinks)
  amb_drip_timer = amb_drip_timer - 1
  if amb_drip_timer <= 0 then
    amb_drip_timer = 35 + math.random(70)
    sfx_drip()
  end

  -- Creaks (wood/metal stress)
  amb_creak_timer = amb_creak_timer - 1
  if amb_creak_timer <= 0 then
    amb_creak_timer = 80 + math.random(140)
    sfx_creak()
  end

  -- Distant thuds
  amb_thud_timer = amb_thud_timer - 1
  if amb_thud_timer <= 0 then
    amb_thud_timer = 100 + math.random(120)
    sfx_thud()
  end

  -- Wind gusts
  amb_wind_timer = amb_wind_timer - 1
  if amb_wind_timer <= 0 then
    amb_wind_timer = 180 + math.random(200)
    sfx_wind()
  end

  -- Drone: continuous low hum, every ~90 frames
  amb_drone_timer = amb_drone_timer + 1
  if amb_drone_timer >= 80 then
    amb_drone_timer = 0
    sfx_drone()
  end
end

----------------------------------------------------------------
-- HEARTBEAT ENGINE
-- Musical lub-DUB pattern with tempo/pitch tied to entity distance
-- Silence between beats creates rhythmic tension
----------------------------------------------------------------

local function update_heartbeat()
  if not e_active or not player_alive then
    heartbeat_rate = math.max(heartbeat_rate - 0.01, 0)
    if heartbeat_rate < 0.05 then return end
  end

  -- Calculate danger from entity proximity
  local d = dist(px, py, ex, ey)
  local target_rate = clamp(1 - (d / 14), 0, 1)
  heartbeat_rate = lerp(heartbeat_rate, target_rate, 0.04)

  if heartbeat_rate < 0.08 then
    heartbeat_timer = 0
    heartbeat_phase = 0
    return
  end

  heartbeat_timer = heartbeat_timer + 1

  -- Interval between beats: 28 frames (calm) to 5 frames (panic)
  local beat_interval = math.floor(lerp(28, 5, heartbeat_rate))
  -- Dub comes 3-4 frames after lub
  local dub_delay = math.max(2, math.floor(beat_interval * 0.15))

  if heartbeat_phase == 0 and heartbeat_timer >= beat_interval then
    heartbeat_timer = 0
    heartbeat_phase = 1
    sfx_heartbeat_lub(heartbeat_rate)
  elseif heartbeat_phase == 1 and heartbeat_timer >= dub_delay then
    heartbeat_timer = 0
    heartbeat_phase = 0
    sfx_heartbeat_dub(heartbeat_rate)
  end
end

----------------------------------------------------------------
-- PROXIMITY HINTS (nearby objects hum gently)
----------------------------------------------------------------

local function update_proximity_sounds()
  if frame % 22 ~= 0 then return end

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

local function title_update()
  title_pulse = title_pulse + 1
  title_idle_timer = title_idle_timer + 1

  -- Ambient ping on title every 60 frames
  if title_pulse % 60 == 0 then
    sfx_title_ping()
  end

  -- Subtle drone on title
  if title_pulse % 90 == 0 then
    wave(CH_AMB, "triangle")
    tone(CH_AMB, 50, 45, 0.4)
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
    update_ambient_sounds()
    update_heartbeat()
  end

  if btnp("start") or btnp("a") then
    demo_mode = false
    scene = "game"
    current_room = 1
    load_room(1)
    hint_text = "PRESS A TO PING"
    hint_timer = 90
    -- Opening drone
    wave(CH_AMB, "triangle")
    tone(CH_AMB, 45, 50, 0.5)
  end
end

local function title_draw()
  s = screen()
  cls(s, C_BLACK)

  local pulse = math.sin(title_pulse * 0.05) * 0.5 + 0.5
  local tcol = pulse > 0.5 and C_LIGHT or C_DARK

  text(s, "THE DARK ROOM", W/2, 22, C_WHITE, ALIGN_CENTER)
  text(s, "SONIC ABYSS", W/2, 35, tcol, ALIGN_CENTER)

  -- Sonar ring visual
  local ring_r = (title_pulse % 60) * 1.5
  if ring_r < 80 then
    local cx, cy = W/2, 72
    local segs = 28
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
    pix(s, cx, 72, C_WHITE)
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
    hint_timer = 45
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
      hint_timer = 45
    else
      sfx_wall_bump()
      hint_text = "LOCKED"
      hint_timer = 30
      wave(CH_EVT, "square")
      tone(CH_EVT, 100, 70, 0.08)
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

  -- Empty tile
  px, py = nx, ny
  sfx_footstep()
end

local function game_update()
  if paused then
    if btnp("select") then paused = false end
    return
  end

  if btnp("select") then
    paused = true
    return
  end

  frame = frame + 1

  -- Movement
  if move_timer > 0 then move_timer = move_timer - 1 end

  if player_alive then
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
  else
    -- Dead: wait then restart
    death_timer = death_timer + 1
    if death_timer > 60 then
      load_room(current_room)
      hint_text = "TRY AGAIN"
      hint_timer = 60
    end
  end

  update_sonar()
  update_entity()
  update_proximity_sounds()
  update_ambient_sounds()
  update_heartbeat()

  -- Shake decay
  if shake_timer > 0 then
    shake_timer = shake_timer - 1
    shake_x = math.random(-2, 2)
    shake_y = math.random(-2, 2)
  else
    shake_x, shake_y = 0, 0
  end

  -- Scare flash decay
  if scare_flash > 0 then
    scare_flash = scare_flash - 1
  end

  -- Hint decay
  if hint_timer > 0 then hint_timer = hint_timer - 1 end
end

local function game_draw()
  s = screen()
  cls(s, C_BLACK)

  local ox = shake_x
  local oy = shake_y

  -- Player dot (always visible)
  local draw_px = px * TILE + 4 + ox
  local draw_py = py * TILE + 4 + oy
  if player_alive then
    pix(s, draw_px, draw_py, C_WHITE)
    -- Breathing cross (pulses with heartbeat rate)
    local blink_speed = heartbeat_rate > 0.3 and 15 or 30
    if frame % blink_speed < (blink_speed * 0.7) then
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
      if p.life < 5 then c = C_DARK end
      if p.life < 2 then c = C_BLACK end
      if c > 0 then
        pix(s, rx, ry, c)
      end
    end
  end

  -- Active sonar ring outline
  if sonar_active then
    local segs = 36
    for i = 0, segs - 1 do
      local a = (i / segs) * math.pi * 2
      local rx = draw_px + math.cos(a) * sonar_radius
      local ry = draw_py + math.sin(a) * sonar_radius
      if rx >= 0 and rx < W and ry >= 0 and ry < H then
        pix(s, math.floor(rx), math.floor(ry), C_DARK)
      end
    end
  end

  -- Scare flash overlay
  if scare_flash > 0 then
    local fc = scare_flash > 8 and C_WHITE or C_LIGHT
    -- Flash: horizontal lines for screen-tear effect
    for y = 0, H - 1, 3 do
      for x = 0, W - 1, 2 do
        pix(s, x, y, fc)
      end
    end
  end

  -- Key indicator
  if has_key then
    text(s, "K", W - 8, 2, C_WHITE)
  end

  -- Room number
  text(s, current_room .. "/3", 4, 2, C_DARK)

  -- Sonar cooldown bar
  if sonar_timer > 0 then
    local bar_w = math.floor((sonar_timer / SONAR_COOLDOWN) * 16)
    rectf(s, W/2 - 8, H - 5, bar_w, 2, C_DARK)
  else
    if frame % 40 < 30 then
      pix(s, W/2, H - 4, C_LIGHT)
    end
  end

  -- Heartbeat indicator (visual pulse tied to heartbeat_rate)
  if heartbeat_rate > 0.1 then
    local pulse_size = math.floor(heartbeat_rate * 3)
    local bx = 4
    local by = H - 8
    for i = 0, pulse_size do
      pix(s, bx + i, by, C_DARK)
    end
  end

  -- Hint text
  if hint_timer > 0 then
    local hcol = hint_timer > 15 and C_LIGHT or C_DARK
    text(s, hint_text, W/2, H - 14, hcol, ALIGN_CENTER)
  end

  -- Death overlay
  if not player_alive and death_timer < 60 then
    if death_timer > 20 then
      text(s, "CAUGHT", W/2, H/2 - 4, C_WHITE, ALIGN_CENTER)
    end
  end

  -- Pause
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

  -- Gentle ambient during victory (relief)
  if victory_timer % 45 == 0 then
    wave(CH_AMB, "sine")
    tone(CH_AMB, NOTE_C4, NOTE_E4, 0.3)
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

  -- Expanding light rings
  local r = math.min(victory_timer * 0.8, 50)
  local cx, cy = W/2, H/2
  for ring = math.floor(r), 0, -4 do
    local col = C_DARK
    if ring < r * 0.3 then col = C_WHITE
    elseif ring < r * 0.6 then col = C_LIGHT
    end
    local segs = 28
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
  wave(CH_AMB, "triangle")
  wave(CH_EVT, "sine")
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
