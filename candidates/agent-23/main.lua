-- CONTAINMENT BREACH
-- Agent 23 (Wave 3) -- Sonar + Time Pressure + Crafting
-- Navigate a flooding facility with sonar. Craft tools. Collect evidence. Escape.
-- 160x120 | 2-bit (4 grayscale) | mode(2) | 30fps

----------------------------------------------------------------
-- CONSTANTS
----------------------------------------------------------------
local W, H = 160, 120
local TILE = 8
local COLS, ROWS = 20, 15
local SONAR_COOLDOWN = 22
local SONAR_MAX_RADIUS = 70
local SONAR_SPEED = 2.5
local MOVE_DELAY = 4

-- Colors (2-bit)
local BLACK, DARK, LIGHT, WHITE = 0, 1, 2, 3

-- Tile types
local T_EMPTY = 0
local T_WALL = 1
local T_ITEM = 2
local T_DOOR = 3
local T_EXIT = 4
local T_EVIDENCE = 5

-- Sound channels
local CH_SONAR = 0
local CH_OBJECT = 1
local CH_AMBIENT = 2
local CH_FOOT = 3

-- Timing
local TOTAL_TIME = 120 * 30   -- 120 seconds at 30fps
local WARN_TIME = 40 * 30
local CRIT_TIME = 15 * 30
local IDLE_TIMEOUT = 150
local DEMO_DURATION = 450

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local scene = "title"
local frame_count = 0
local paused = false

-- Player
local px, py = 2, 7
local move_timer = 0
local player_alive = true
local sonar_timer = 0
local sonar_radius = 0
local sonar_active = false
local ping_objects = {}
local ring_particles = {}
local foot_alt = false

-- Entity
local ex, ey = 17, 3
local e_speed = 0.025
local e_active = false
local e_chase = false
local e_alert_x, e_alert_y = -1, -1
local e_patrol_timer = 0
local e_target_x, e_target_y = 15, 7
local e_step_timer = 0
local e_move_accum_x, e_move_accum_y = 0, 0

-- Timer
local timer = TOTAL_TIME
local pulse_phase = 0

-- Scare / shake
local scare_flash = 0
local shake_timer = 0
local shake_x, shake_y = 0, 0

-- Horror atmosphere
local heartbeat_rate = 0
local heartbeat_timer = 0
local amb_drip_timer = 40
local amb_creak_timer = 80
local entity_eyes = {}
local darkness_tendrils = {}
local static_amount = 0

-- Room
local current_room = 1
local room_map = {}
local room_items = {}   -- {x, y, item_id} items on the floor

-- Inventory
local inv = {}
local inv_open = false
local inv_sel = 1
local combine_mode = false
local combine_first = nil

-- Hint / message
local hint_text = ""
local hint_timer = 0

-- Evidence
local evidence_count = 0

-- Victory / death
local victory_timer = 0
local death_timer = 0
local ending_type = "survival"

-- Demo
local demo_mode = false
local demo_timer = 0
local demo_path = {}
local demo_step = 1

-- Title
local title_pulse = 0
local title_idle_timer = 0
local title_timer_count = 0
local title_flicker = 0

----------------------------------------------------------------
-- ITEM / CRAFTING DATABASE
----------------------------------------------------------------
local ITEMS = {
  wire      = {name="Wire",       icon="W", desc="Copper wire."},
  battery   = {name="Battery",    icon="B", desc="Small cell battery."},
  flashlight= {name="Flashlight", icon="*", desc="Makeshift light source."},
  pipe      = {name="Pipe",       icon="I", desc="Short metal pipe."},
  valve     = {name="Valve",      icon="V", desc="Rusty valve handle."},
  lever     = {name="Lever",      icon="L", desc="Pry lever. Opens sealed doors."},
  card      = {name="Card Blank", icon="C", desc="Blank access card."},
  tape      = {name="Tape",       icon="T", desc="Magnetic tape strip."},
  keycard   = {name="Keycard",    icon="K", desc="Encoded access card."},
  evidence1 = {name="File: ALPHA",icon="E", desc="Subject transfer log."},
  evidence2 = {name="File: BETA", icon="E", desc="Experiment results."},
  evidence3 = {name="File: GAMMA",icon="E", desc="Cover-up memo."},
}

local RECIPES = {
  {a="wire",   b="battery", result="flashlight"},
  {a="pipe",   b="valve",   result="lever"},
  {a="card",   b="tape",    result="keycard"},
}

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------
local function dist(x1, y1, x2, y2)
  local dx, dy = x1 - x2, y1 - y2
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

local function has_item(name)
  for i, v in ipairs(inv) do
    if v == name then return true, i end
  end
  return false
end

local function add_item(name)
  if not has_item(name) and #inv < 8 then
    inv[#inv+1] = name
    return true
  end
  return false
end

local function remove_item(name)
  local found, idx = has_item(name)
  if found then table.remove(inv, idx) end
end

local function try_combine(id_a, id_b)
  for _, r in ipairs(RECIPES) do
    if (id_a == r.a and id_b == r.b) or (id_a == r.b and id_b == r.a) then
      remove_item(id_a)
      remove_item(id_b)
      add_item(r.result)
      return ITEMS[r.result].name
    end
  end
  return nil
end

local function find_floor_items()
  local objs = {}
  for y = 0, ROWS-1 do
    for x = 0, COLS-1 do
      local t = room_map[y][x]
      if t == T_ITEM or t == T_DOOR or t == T_EXIT or t == T_EVIDENCE then
        objs[#objs+1] = {x=x, y=y, type=t}
      end
    end
  end
  return objs
end

local function show_hint(txt, dur)
  hint_text = txt
  hint_timer = dur or 60
end

local function text_center(s, str, y, c)
  text(s, str, W/2, y, c, ALIGN_CENTER)
end

----------------------------------------------------------------
-- SOUND EFFECTS
----------------------------------------------------------------
local function sfx_sonar_ping()
  wave(CH_SONAR, "sine")
  tone(CH_SONAR, 1200, 400, 0.15)
end

local function sfx_footstep()
  foot_alt = not foot_alt
  wave(CH_FOOT, "triangle")
  tone(CH_FOOT, foot_alt and 80 or 70, foot_alt and 60 or 50, 0.03)
end

local function sfx_wall_bump()
  noise(CH_FOOT, 0.04)
end

local function sfx_pickup()
  wave(CH_OBJECT, "sine")
  tone(CH_OBJECT, 800, 1600, 0.1)
  wave(CH_SONAR, "sine")
  tone(CH_SONAR, 1000, 2000, 0.1)
end

local function sfx_craft()
  wave(CH_OBJECT, "sine")
  tone(CH_OBJECT, 660, 1320, 0.08)
  wave(CH_SONAR, "sine")
  tone(CH_SONAR, 880, 1760, 0.12)
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

local function sfx_evidence()
  wave(CH_OBJECT, "sine")
  tone(CH_OBJECT, 500, 1000, 0.1)
  wave(CH_SONAR, "triangle")
  tone(CH_SONAR, 700, 1400, 0.15)
end

local function sfx_object_ping(obj_type, d)
  local max_d = 20
  local t = clamp(1 - d / max_d, 0, 1)
  local dur = 0.02 + t * 0.08
  if dur < 0.02 then return end
  local base = 400 + t * t * 1200

  if obj_type == T_ITEM or obj_type == T_EVIDENCE then
    wave(CH_OBJECT, "sine")
    tone(CH_OBJECT, base, base * 1.2, dur)
  elseif obj_type == T_DOOR then
    wave(CH_OBJECT, "square")
    tone(CH_OBJECT, base * 0.4, base * 0.35, dur)
  elseif obj_type == T_EXIT then
    wave(CH_OBJECT, "sine")
    tone(CH_OBJECT, base * 0.8, base * 1.5, dur)
    wave(CH_AMBIENT, "triangle")
    tone(CH_AMBIENT, base * 0.6, base * 1.1, dur)
  end
end

local function sfx_heartbeat(intensity)
  wave(CH_AMBIENT, "sine")
  local base = lerp(50, 70, intensity)
  tone(CH_AMBIENT, base, base * 0.7, 0.06)
end

local function sfx_entity_step(d)
  if d > 15 then return end
  local vol_t = clamp(1 - d / 15, 0, 1)
  local freq = lerp(200, 100, vol_t)
  wave(CH_FOOT, "square")
  tone(CH_FOOT, freq, freq * 0.8, lerp(0.01, 0.04, vol_t))
end

local function sfx_entity_growl()
  wave(CH_AMBIENT, "sawtooth")
  tone(CH_AMBIENT, 45, 35, 0.12)
end

local function sfx_jumpscare()
  noise(CH_SONAR, 0.2)
  wave(CH_OBJECT, "sawtooth")
  tone(CH_OBJECT, 80, 40, 0.3)
  noise(CH_FOOT, 0.15)
  wave(CH_AMBIENT, "square")
  tone(CH_AMBIENT, 100, 50, 0.25)
end

local function sfx_ambient_drip()
  wave(CH_OBJECT, "sine")
  tone(CH_OBJECT, 1200 + math.random(800), 600, 0.02)
end

local function sfx_ambient_creak()
  wave(CH_AMBIENT, "sawtooth")
  local f = ({55,62,48,70})[math.random(4)]
  tone(CH_AMBIENT, f, f * 0.8, 0.1)
end

local function sfx_tick()
  wave(CH_AMBIENT, "triangle")
  tone(CH_AMBIENT, 200, 180, 0.02)
end

local function sfx_warn()
  noise(CH_SONAR, 0.03)
  wave(CH_OBJECT, "sine")
  tone(CH_OBJECT, 440, 380, 0.05)
end

local function sfx_crit()
  wave(CH_SONAR, "sine")
  tone(CH_SONAR, 660, 880, 0.08)
  wave(CH_OBJECT, "sine")
  tone(CH_OBJECT, 880, 660, 0.08)
end

local function sfx_victory()
  wave(0, "sine"); tone(0, 400, 800, 0.2)
  wave(1, "sine"); tone(1, 600, 1200, 0.2)
  wave(2, "triangle"); tone(2, 300, 600, 0.2)
end

local function sfx_alert_ping()
  wave(CH_OBJECT, "square")
  tone(CH_OBJECT, 120, 80, 0.08)
end

local function sfx_title_ping()
  wave(CH_SONAR, "sine")
  tone(CH_SONAR, 800, 600, 0.1)
end

local function sfx_inv_open()
  wave(CH_OBJECT, "sine")
  tone(CH_OBJECT, 300, 600, 0.04)
end

local function sfx_inv_select()
  wave(CH_OBJECT, "sine")
  tone(CH_OBJECT, 500, 520, 0.03)
end

----------------------------------------------------------------
-- ROOM DATA
-- Each room has specific items on the floor and a required tool
-- Room 1: wire + battery -> flashlight (opens sealed hatch)
-- Room 2: pipe + valve -> lever (pries open blast door)
-- Room 3: card + tape -> keycard (unlocks exit terminal)
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
  -- Internal walls: L-shaped corridor
  for y = 1, 8 do m[y][10] = T_WALL end
  for x = 10, 14 do m[8][x] = T_WALL end
  -- Pillars
  m[4][4] = T_WALL; m[4][7] = T_WALL
  m[10][5] = T_WALL; m[10][15] = T_WALL
  -- Items
  m[3][3] = T_ITEM    -- wire
  m[6][16] = T_ITEM   -- battery
  m[2][17] = T_EVIDENCE -- evidence 1
  -- Door (needs flashlight to navigate past dark section)
  m[8][12] = T_DOOR
  -- Exit
  m[13][18] = T_EXIT
  return m, {
    {x=3, y=3, id="wire"},
    {x=16, y=6, id="battery"},
    {x=17, y=2, id="evidence1"},
  }
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
  -- Maze corridors
  for y = 0, 10 do m[y][5] = T_WALL end
  for y = 4, 14 do m[y][10] = T_WALL end
  for y = 0, 8 do m[y][15] = T_WALL end
  for x = 5, 10 do m[4][x] = T_WALL end
  for x = 10, 15 do m[10][x] = T_WALL end
  -- Items
  m[2][3] = T_ITEM     -- pipe
  m[12][17] = T_ITEM   -- valve
  m[6][18] = T_EVIDENCE -- evidence 2
  -- Door (needs lever to pry open)
  m[10][13] = T_DOOR
  -- Exit
  m[13][17] = T_EXIT
  return m, {
    {x=3, y=2, id="pipe"},
    {x=17, y=12, id="valve"},
    {x=18, y=6, id="evidence2"},
  }
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
  -- Cross pattern
  for x = 3, 17 do m[7][x] = T_WALL end
  for y = 2, 12 do m[y][10] = T_WALL end
  -- Openings
  m[7][6] = T_EMPTY; m[7][14] = T_EMPTY
  m[5][10] = T_EMPTY; m[10][10] = T_EMPTY
  -- Pillars
  m[3][4] = T_WALL; m[11][4] = T_WALL
  m[3][16] = T_WALL; m[11][16] = T_WALL
  -- Items
  m[3][2] = T_ITEM     -- card
  m[11][17] = T_ITEM   -- tape
  m[2][16] = T_EVIDENCE -- evidence 3
  -- Door (needs keycard)
  m[7][10] = T_DOOR
  -- Exit
  m[13][10] = T_EXIT
  return m, {
    {x=2, y=3, id="card"},
    {x=17, y=11, id="tape"},
    {x=16, y=2, id="evidence3"},
  }
end

-- Required tool for each room's door
local ROOM_TOOLS = {"flashlight", "lever", "keycard"}

----------------------------------------------------------------
-- ROOM MANAGEMENT
----------------------------------------------------------------
local function load_room(num)
  sonar_active = false
  sonar_radius = 0
  sonar_timer = 0
  ping_objects = {}
  ring_particles = {}
  player_alive = true
  scare_flash = 0
  shake_timer = 0
  death_timer = 0

  local items
  if num == 1 then
    room_map, items = build_room_1()
    px, py = 2, 7
    ex, ey = 17, 3
    e_target_x, e_target_y = 15, 7
  elseif num == 2 then
    room_map, items = build_room_2()
    px, py = 2, 12
    ex, ey = 17, 2
    e_target_x, e_target_y = 12, 6
  elseif num == 3 then
    room_map, items = build_room_3()
    px, py = 2, 4
    ex, ey = 17, 11
    e_target_x, e_target_y = 10, 10
  end

  -- Place floor items (only those not already in inventory)
  room_items = {}
  for _, it in ipairs(items) do
    if not has_item(it.id) then
      room_items[#room_items+1] = {x=it.x, y=it.y, id=it.id}
    else
      -- Remove from map if already collected
      room_map[it.y][it.x] = T_EMPTY
    end
  end

  e_active = true
  e_chase = false
  e_alert_x, e_alert_y = -1, -1
  e_speed = 0.02 + num * 0.008
  e_patrol_timer = 0
  e_step_timer = 0
  e_move_accum_x, e_move_accum_y = 0, 0
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
    e_chase = true
    e_target_x, e_target_y = e_alert_x, e_alert_y
    if dist(ex, ey, e_alert_x, e_alert_y) < 2 then
      e_alert_x, e_alert_y = -1, -1
      e_patrol_timer = 120
    end
  elseif d < 4 then
    e_chase = true
    e_target_x, e_target_y = px, py
  elseif e_patrol_timer > 0 then
    e_patrol_timer = e_patrol_timer - 1
    if frame_count % 60 == 0 then
      e_target_x = clamp(ex + math.random(-4, 4), 1, COLS-2)
      e_target_y = clamp(ey + math.random(-4, 4), 1, ROWS-2)
    end
  else
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
    e_move_accum_x = e_move_accum_x + (dx / td) * speed
    e_move_accum_y = e_move_accum_y + (dy / td) * speed

    local sx, sy = 0, 0
    if math.abs(e_move_accum_x) >= 1 then
      sx = e_move_accum_x > 0 and 1 or -1
      e_move_accum_x = e_move_accum_x - sx
    end
    if math.abs(e_move_accum_y) >= 1 then
      sy = e_move_accum_y > 0 and 1 or -1
      e_move_accum_y = e_move_accum_y - sy
    end
    if sx ~= 0 and entity_can_move(math.floor(ex + sx), math.floor(ey)) then
      ex = ex + sx
    end
    if sy ~= 0 and entity_can_move(math.floor(ex), math.floor(ey + sy)) then
      ey = ey + sy
    end
  end

  -- Entity footstep sounds
  e_step_timer = e_step_timer + 1
  if e_step_timer >= (e_chase and 12 or 20) then
    e_step_timer = 0
    sfx_entity_step(d)
  end

  -- Growl when close
  if e_chase and d < 6 and frame_count % 40 == 0 then
    sfx_entity_growl()
  end

  -- CAUGHT: jumpscare + time penalty
  if d < 1.5 then
    sfx_jumpscare()
    scare_flash = 12
    shake_timer = 15
    player_alive = false
    death_timer = 0
    timer = timer - 10 * 30  -- lose 10 seconds
    if timer < 0 then timer = 0 end
  end

  -- Random micro-scare when very close
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

  -- Queue objects in range
  ping_objects = {}
  local objs = find_floor_items()
  for _, obj in ipairs(objs) do
    local d = dist(px, py, obj.x, obj.y)
    if d < 18 then
      ping_objects[#ping_objects+1] = {x=obj.x, y=obj.y, type=obj.type, dist=d, pinged=false}
    end
  end
  table.sort(ping_objects, function(a, b) return a.dist < b.dist end)

  -- Alert entity
  if e_active and player_alive then
    e_alert_x, e_alert_y = px, py
    e_chase = true
    sfx_alert_ping()
    show_hint("...IT HEARD YOU", 40)
  end
end

local function update_sonar()
  if sonar_timer > 0 then sonar_timer = sonar_timer - 1 end
  if not sonar_active then return end

  sonar_radius = sonar_radius + SONAR_SPEED

  -- Ring particles at current radius
  if frame_count % 2 == 0 then
    local segs = 16
    for i = 0, segs - 1 do
      local a = (i / segs) * math.pi * 2
      local rx = px * TILE + 4 + math.cos(a) * sonar_radius
      local ry = py * TILE + 4 + math.sin(a) * sonar_radius
      if rx >= 0 and rx < W and ry >= 0 and ry < H then
        local tx = math.floor(rx / TILE)
        local ty = math.floor(ry / TILE)
        local tile = get_tile(tx, ty)
        if tile == T_WALL then
          ring_particles[#ring_particles+1] = {x=rx, y=ry, life=12, col=DARK}
        else
          ring_particles[#ring_particles+1] = {x=rx, y=ry, life=4, col=DARK}
        end
      end
    end
  end

  -- Ping objects as wave reaches them
  for _, obj in ipairs(ping_objects) do
    if not obj.pinged and sonar_radius >= obj.dist * TILE then
      obj.pinged = true
      sfx_object_ping(obj.type, obj.dist)
      local c = WHITE
      if obj.type == T_EVIDENCE then c = LIGHT end
      ring_particles[#ring_particles+1] = {
        x = obj.x * TILE + 4, y = obj.y * TILE + 4,
        life = 20, col = c
      }
    end
  end

  -- Reveal entity
  if e_active then
    local ed = dist(px, py, ex, ey)
    if sonar_radius >= ed * TILE and sonar_radius < ed * TILE + SONAR_SPEED * 2 then
      ring_particles[#ring_particles+1] = {
        x = ex * TILE + 4, y = ey * TILE + 4,
        life = 15, col = WHITE
      }
      wave(CH_OBJECT, "sawtooth")
      tone(CH_OBJECT, 150, 60, 0.1)
    end
  end

  if sonar_radius > SONAR_MAX_RADIUS then
    sonar_active = false
  end

  -- Update particle lifetimes
  local alive = {}
  for _, p in ipairs(ring_particles) do
    p.life = p.life - 1
    if p.life > 0 then alive[#alive+1] = p end
  end
  ring_particles = alive
end

----------------------------------------------------------------
-- AMBIENT HORROR
----------------------------------------------------------------
local function spawn_entity_eyes()
  if #entity_eyes >= 6 then return end
  local side = math.random(1, 4)
  local ox, oy
  if side == 1 then
    ox = math.random(10, W-10); oy = math.random(2, 12)
  elseif side == 2 then
    ox = math.random(10, W-10); oy = math.random(H-14, H-4)
  elseif side == 3 then
    ox = math.random(2, 16); oy = math.random(10, H-10)
  else
    ox = math.random(W-18, W-4); oy = math.random(10, H-10)
  end
  entity_eyes[#entity_eyes+1] = {x=ox, y=oy, life=math.random(30,90), blink=math.random(0,100)}
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

local function update_tendrils(urgency)
  if urgency < 0.2 then
    darkness_tendrils = {}
    return
  end
  local max_t = math.floor(urgency * 20)
  while #darkness_tendrils < max_t do
    local side = math.random(1, 4)
    local t = {}
    if side == 1 then
      t.x = math.random(0, W-1); t.y = 0
      t.dx = (math.random()-0.5)*0.5; t.dy = 0.3 + math.random()*0.5
    elseif side == 2 then
      t.x = math.random(0, W-1); t.y = H-1
      t.dx = (math.random()-0.5)*0.5; t.dy = -(0.3 + math.random()*0.5)
    elseif side == 3 then
      t.x = 0; t.y = math.random(0, H-1)
      t.dx = 0.3 + math.random()*0.5; t.dy = (math.random()-0.5)*0.5
    else
      t.x = W-1; t.y = math.random(0, H-1)
      t.dx = -(0.3 + math.random()*0.5); t.dy = (math.random()-0.5)*0.5
    end
    t.len = math.floor(urgency * 25) + math.random(5, 15)
    t.life = t.len
    darkness_tendrils[#darkness_tendrils+1] = t
  end
  local i = 1
  while i <= #darkness_tendrils do
    local t = darkness_tendrils[i]
    t.x = t.x + t.dx; t.y = t.y + t.dy
    t.life = t.life - 1
    if t.life <= 0 then
      darkness_tendrils[i] = darkness_tendrils[#darkness_tendrils]
      darkness_tendrils[#darkness_tendrils] = nil
    else
      i = i + 1
    end
  end
end

local function update_ambient()
  local urgency = 1.0 - (timer / TOTAL_TIME)

  -- Drip
  amb_drip_timer = amb_drip_timer - 1
  if amb_drip_timer <= 0 then
    amb_drip_timer = 40 + math.random(80)
    sfx_ambient_drip()
  end

  -- Creak
  amb_creak_timer = amb_creak_timer - 1
  if amb_creak_timer <= 0 then
    amb_creak_timer = 60 + math.random(math.floor(lerp(120, 30, urgency)))
    sfx_ambient_creak()
  end

  -- Heartbeat
  if e_active and player_alive then
    local d = dist(px, py, ex, ey)
    local target = clamp(1 - d/15, 0, 1)
    -- Also factor in time urgency
    target = math.max(target, urgency * 0.6)
    heartbeat_rate = lerp(heartbeat_rate, target, 0.05)
  else
    heartbeat_rate = math.max(heartbeat_rate - 0.01, 0)
  end

  if heartbeat_rate > 0.08 then
    heartbeat_timer = heartbeat_timer + 1
    local interval = math.floor(lerp(30, 6, heartbeat_rate))
    if heartbeat_timer >= interval then
      heartbeat_timer = 0
      sfx_heartbeat(heartbeat_rate)
    end
  end

  -- Entity eyes spawn
  if math.random(100) < math.floor(urgency * 10) then
    spawn_entity_eyes()
  end
  update_entity_eyes()
  update_tendrils(urgency)

  -- Static
  static_amount = 0
  if urgency > 0.5 then
    static_amount = (urgency - 0.5) * 0.6
    if urgency > 0.85 then static_amount = static_amount + math.random() * 0.2 end
  end

  -- Time-based tick sounds
  if timer > WARN_TIME then
    if timer % 30 == 0 then sfx_tick() end
  elseif timer > CRIT_TIME then
    if timer % 15 == 0 then sfx_warn() end
  else
    if timer % 8 == 0 then sfx_crit() end
  end
end

----------------------------------------------------------------
-- HORROR DRAW HELPERS
----------------------------------------------------------------
local function draw_vignette(s, intensity)
  local border = math.floor(intensity * 25)
  if border < 1 then return end
  for y = 0, border-1 do
    local c = y < border/2 and BLACK or DARK
    line(s, 0, y, W-1, y, c)
    line(s, 0, H-1-y, W-1, H-1-y, c)
  end
  for x = 0, border-1 do
    local c = x < border/2 and BLACK or DARK
    line(s, x, border, x, H-1-border, c)
    line(s, W-1-x, border, W-1-x, H-1-border, c)
  end
end

local function draw_entity_eyes_overlay(s)
  for _, e in ipairs(entity_eyes) do
    if (e.blink % 40) >= 3 then
      local c = e.life < 10 and DARK or LIGHT
      pix(s, e.x, e.y, c)
      pix(s, e.x + 3, e.y, c)
    end
  end
end

local function draw_tendrils(s)
  for _, t in ipairs(darkness_tendrils) do
    local tx = math.floor(t.x)
    local ty = math.floor(t.y)
    if tx >= 0 and tx < W and ty >= 0 and ty < H then
      pix(s, tx, ty, BLACK)
      if t.life > t.len * 0.7 then
        if tx+1 < W then pix(s, tx+1, ty, BLACK) end
        if ty+1 < H then pix(s, tx, ty+1, BLACK) end
      end
    end
  end
end

local function draw_static(s, amount)
  if amount < 0.05 then return end
  local num = math.floor(amount * 60)
  for i = 1, num do
    pix(s, math.random(0, W-1), math.random(0, H-1), math.random(0, 1))
  end
end

local function draw_entity_face(s)
  local cx, cy = W/2, H/2
  circ(s, cx, cy, 25, WHITE)
  circ(s, cx, cy, 24, DARK)
  circ(s, cx-9, cy-5, 6, WHITE)
  circ(s, cx+9, cy-5, 6, WHITE)
  circ(s, cx-9, cy-5, 3, BLACK)
  circ(s, cx+9, cy-5, 3, BLACK)
  pix(s, cx-9, cy-5, WHITE)
  pix(s, cx+9, cy-5, WHITE)
  for i = -12, 12 do
    local my = cy + 10 + math.floor(math.sin(i * 0.8) * 3)
    if cx+i >= 0 and cx+i < W and my >= 0 and my < H then
      pix(s, cx+i, my, WHITE)
    end
  end
end

local function draw_water_line(s, urgency)
  -- Rising water at bottom of screen
  local water_h = math.floor(urgency * 20)
  if water_h < 1 then return end
  for y = H - water_h, H - 1 do
    local wave_off = math.sin((y + frame_count * 0.1) * 0.5) * 2
    for x = 0, W - 1 do
      local wx = x + math.floor(wave_off)
      if (wx + y) % 3 == 0 then
        pix(s, x, y, DARK)
      else
        pix(s, x, y, BLACK)
      end
    end
  end
end

----------------------------------------------------------------
-- INVENTORY UI
----------------------------------------------------------------
local function draw_inventory(s)
  -- Dark overlay
  rectf(s, 10, 8, 140, 104, BLACK)
  rect(s, 10, 8, 140, 104, LIGHT)

  text(s, "INVENTORY", W/2, 12, WHITE, ALIGN_CENTER)

  if #inv == 0 then
    text(s, "Empty", W/2, 50, DARK, ALIGN_CENTER)
  else
    for i, id in ipairs(inv) do
      local it = ITEMS[id]
      local y = 22 + (i-1) * 10
      local c = LIGHT
      if i == inv_sel then
        c = WHITE
        rectf(s, 14, y-1, 132, 9, DARK)
      end
      if combine_mode and combine_first == id then
        text(s, ">" .. it.icon .. " " .. it.name .. " [COMBINE]", 18, y, WHITE)
      else
        text(s, it.icon .. " " .. it.name, 18, y, c)
      end
    end
  end

  -- Instructions at bottom
  if combine_mode then
    text(s, "Select 2nd item to combine", W/2, 92, LIGHT, ALIGN_CENTER)
  else
    text(s, "A:Combine  B:Close", W/2, 92, DARK, ALIGN_CENTER)
  end

  -- Evidence counter
  text(s, "Evidence: " .. evidence_count .. "/3", W/2, 100, DARK, ALIGN_CENTER)
end

local function update_inventory()
  if btnp("b") then
    if combine_mode then
      combine_mode = false
      combine_first = nil
    else
      inv_open = false
      combine_mode = false
      combine_first = nil
    end
    return
  end

  if #inv == 0 then return end

  if btnp("up") then
    inv_sel = inv_sel - 1
    if inv_sel < 1 then inv_sel = #inv end
    sfx_inv_select()
  elseif btnp("down") then
    inv_sel = inv_sel + 1
    if inv_sel > #inv then inv_sel = 1 end
    sfx_inv_select()
  end

  if btnp("a") then
    local sel_id = inv[inv_sel]
    if not sel_id then return end

    if combine_mode then
      if sel_id ~= combine_first then
        local result = try_combine(combine_first, sel_id)
        if result then
          sfx_craft()
          show_hint("Crafted: " .. result, 60)
          combine_mode = false
          combine_first = nil
          inv_sel = clamp(inv_sel, 1, math.max(1, #inv))
        else
          show_hint("Can't combine those.", 40)
          combine_mode = false
          combine_first = nil
        end
      end
    else
      combine_mode = true
      combine_first = sel_id
    end
  end
end

----------------------------------------------------------------
-- PLAYER MOVEMENT
----------------------------------------------------------------
local function try_move(dx, dy)
  if not player_alive then return end
  local nx, ny = px + dx, py + dy
  local tile = get_tile(nx, ny)

  if tile == T_WALL then
    sfx_wall_bump()
    show_hint("WALL", 15)
    return
  end

  if tile == T_ITEM or tile == T_EVIDENCE then
    -- Find item at this location
    for i, it in ipairs(room_items) do
      if it.x == nx and it.y == ny then
        if add_item(it.id) then
          sfx_pickup()
          show_hint("Got: " .. ITEMS[it.id].name, 50)
          if tile == T_EVIDENCE then
            evidence_count = evidence_count + 1
            sfx_evidence()
            show_hint("EVIDENCE " .. evidence_count .. "/3", 60)
          end
          room_map[ny][nx] = T_EMPTY
          table.remove(room_items, i)
        else
          show_hint("Inventory full!", 40)
        end
        break
      end
    end
    px, py = nx, ny
    sfx_footstep()
    return
  end

  if tile == T_DOOR then
    local tool = ROOM_TOOLS[current_room]
    if has_item(tool) then
      remove_item(tool)
      room_map[ny][nx] = T_EMPTY
      sfx_door_open()
      show_hint("Used " .. ITEMS[tool].name .. "!", 50)
    else
      sfx_wall_bump()
      show_hint("Need: " .. ITEMS[tool].name, 50)
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
      show_hint("SECTOR " .. current_room .. " - WATER RISING", 60)
    else
      -- VICTORY
      scene = "victory"
      victory_timer = 0
      if evidence_count >= 3 then
        ending_type = "true"
      else
        ending_type = "survival"
      end
      sfx_victory()
    end
    return
  end

  -- Empty tile
  px, py = nx, ny
  sfx_footstep()
end

----------------------------------------------------------------
-- GAME UPDATE
----------------------------------------------------------------
local function game_update()
  if not player_alive then
    death_timer = death_timer + 1
    if scare_flash > 0 then scare_flash = scare_flash - 1 end
    if shake_timer > 0 then shake_timer = shake_timer - 1 end
    if timer <= 0 then
      -- Total time out during death -> game over
      if death_timer > 60 and (btnp("start") or btnp("a")) then
        scene = "gameover"
        victory_timer = 0
      end
      return
    end
    if death_timer > 60 and (btnp("start") or btnp("a")) then
      load_room(current_room)
      show_hint("TRY AGAIN... QUIETLY", 60)
    end
    return
  end

  if paused then
    if btnp("select") or btnp("start") then paused = false end
    return
  end
  if btnp("select") then paused = true; return end

  -- Inventory mode
  if inv_open then
    update_inventory()
    return
  end

  if btnp("b") then
    inv_open = true
    inv_sel = 1
    combine_mode = false
    combine_first = nil
    sfx_inv_open()
    return
  end

  frame_count = frame_count + 1

  -- Countdown
  timer = timer - 1
  pulse_phase = pulse_phase + 1

  if timer <= 0 then
    timer = 0
    scene = "gameover"
    victory_timer = 0
    sfx_jumpscare()
    return
  end

  -- Movement
  if move_timer > 0 then move_timer = move_timer - 1 end
  if move_timer <= 0 then
    if btn("left") then try_move(-1, 0); move_timer = MOVE_DELAY
    elseif btn("right") then try_move(1, 0); move_timer = MOVE_DELAY
    elseif btn("up") then try_move(0, -1); move_timer = MOVE_DELAY
    elseif btn("down") then try_move(0, 1); move_timer = MOVE_DELAY
    end
  end

  -- Sonar on A
  if btnp("a") then do_sonar_ping() end

  update_sonar()
  update_entity()
  update_ambient()

  -- Scare effects decay
  if scare_flash > 0 then scare_flash = scare_flash - 1 end
  if shake_timer > 0 then
    shake_timer = shake_timer - 1
    shake_x = math.random(-3, 3)
    shake_y = math.random(-2, 2)
  else
    shake_x, shake_y = 0, 0
  end

  -- Hint decay
  if hint_timer > 0 then hint_timer = hint_timer - 1 end
end

----------------------------------------------------------------
-- GAME DRAW
----------------------------------------------------------------
local function draw_timer_bar(s)
  local secs = math.ceil(timer / 30)
  local mins = math.floor(secs / 60)
  secs = secs % 60
  local ts = string.format("%d:%02d", mins, secs)

  local c = WHITE
  if timer < CRIT_TIME then
    c = math.floor(pulse_phase / 4) % 2 == 0 and WHITE or DARK
  elseif timer < WARN_TIME then
    c = LIGHT
  end
  text(s, ts, W/2, 2, c, ALIGN_CENTER)
end

local function game_draw()
  local s = screen()
  local urgency = 1.0 - (timer / TOTAL_TIME)

  -- Jump scare flash
  if scare_flash > 0 then
    cls(s, scare_flash > 6 and WHITE or LIGHT)
    if not player_alive and scare_flash > 4 then
      draw_entity_face(s)
      return
    end
    if scare_flash > 3 then return end
  end

  cls(s, BLACK)

  -- Player dot
  local dpx = px * TILE + 4 + shake_x
  local dpy = py * TILE + 4 + shake_y

  if player_alive then
    pix(s, dpx, dpy, WHITE)
    -- Breathing pulse
    local breathe = math.sin(frame_count * 0.08)
    if breathe > 0 then
      pix(s, dpx-1, dpy, DARK)
      pix(s, dpx+1, dpy, DARK)
      pix(s, dpx, dpy-1, DARK)
      pix(s, dpx, dpy+1, DARK)
    end
  end

  -- Sonar ring particles
  for _, p in ipairs(ring_particles) do
    local rx = math.floor(p.x) + shake_x
    local ry = math.floor(p.y) + shake_y
    if rx >= 0 and rx < W and ry >= 0 and ry < H then
      local c = p.col
      if p.life < 4 then c = DARK end
      if p.life < 2 then c = BLACK end
      if c > 0 then pix(s, rx, ry, c) end
    end
  end

  -- Active sonar ring
  if sonar_active then
    local segs = 32
    for i = 0, segs-1 do
      local a = (i / segs) * math.pi * 2
      local rx = dpx + math.cos(a) * sonar_radius
      local ry = dpy + math.sin(a) * sonar_radius
      if rx >= 0 and rx < W and ry >= 0 and ry < H then
        pix(s, math.floor(rx), math.floor(ry), DARK)
      end
    end
  end

  -- Entity eyes (visible when close)
  if e_active and player_alive then
    local ed = dist(px, py, ex, ey)
    if ed < 5 then
      local epx = math.floor(ex * TILE + 4) + shake_x
      local epy = math.floor(ey * TILE + 4) + shake_y
      local blink = math.floor(frame_count / 8) % 5
      if blink < 3 then
        local brightness = ed < 3 and WHITE or LIGHT
        pix(s, epx-1, epy, brightness)
        pix(s, epx+1, epy, brightness)
      end
    end
  end

  -- HUD: timer
  draw_timer_bar(s)

  -- Room number + evidence
  text(s, current_room .. "/3", 4, 2, DARK)
  if evidence_count > 0 then
    text(s, "E:" .. evidence_count, W - 20, 2, LIGHT)
  end

  -- Inventory hint icons (small bar)
  if #inv > 0 then
    for i, id in ipairs(inv) do
      local it = ITEMS[id]
      text(s, it.icon, 4 + (i-1) * 6, H - 8, DARK)
    end
  end

  -- Heartbeat visual pulse
  if heartbeat_rate > 0.3 then
    local pulse = math.sin(frame_count * 0.3) * heartbeat_rate
    if pulse > 0.3 then
      local c = heartbeat_rate > 0.7 and LIGHT or DARK
      for i = 0, W-1, 4 do pix(s, i, 0, c); pix(s, i, H-1, c) end
      for i = 0, H-1, 4 do pix(s, 0, i, c); pix(s, W-1, i, c) end
    end
  end

  -- Sonar cooldown indicator
  if sonar_timer > 0 then
    local bar_w = math.floor((sonar_timer / SONAR_COOLDOWN) * 16)
    rectf(s, W/2 - 8, H - 5, bar_w, 2, DARK)
  else
    if frame_count % 40 < 30 then pix(s, W/2, H - 4, LIGHT) end
  end

  -- Hint text
  if hint_timer > 0 then
    local hc = hint_timer > 15 and LIGHT or DARK
    text(s, hint_text, W/2, H - 16, hc, ALIGN_CENTER)
  end

  -- Horror overlays
  draw_vignette(s, urgency)
  draw_entity_eyes_overlay(s)
  draw_tendrils(s)
  draw_static(s, static_amount)
  draw_water_line(s, urgency)

  -- Critical scanlines
  if timer < CRIT_TIME then
    for i = 1, 5 do
      local y = math.random(0, H-1)
      line(s, 0, y, W-1, y, DARK)
    end
  end

  -- Inventory overlay
  if inv_open then
    draw_inventory(s)
  end

  -- Death overlay
  if not player_alive and scare_flash <= 0 then
    text(s, "IT GOT YOU", W/2, H/2 - 12, WHITE, ALIGN_CENTER)
    if timer <= 0 then
      text(s, "TIME'S UP", W/2, H/2, LIGHT, ALIGN_CENTER)
    else
      local pen = "(-10s)"
      text(s, pen, W/2, H/2, DARK, ALIGN_CENTER)
    end
    if death_timer > 30 then
      text(s, "SECTOR " .. current_room, W/2, H/2 + 12, DARK, ALIGN_CENTER)
    end
    if death_timer > 60 then
      if frame_count % 40 < 25 then
        text(s, "PRESS START", W/2, H/2 + 24, LIGHT, ALIGN_CENTER)
      end
    end
  end

  -- Pause overlay
  if paused then
    rectf(s, W/2 - 35, H/2 - 14, 70, 28, BLACK)
    rect(s, W/2 - 35, H/2 - 14, 70, 28, DARK)
    text(s, "PAUSED", W/2, H/2 - 8, WHITE, ALIGN_CENTER)
    text(s, "...water still rises...", W/2, H/2 + 2, DARK, ALIGN_CENTER)
  end
end

----------------------------------------------------------------
-- TITLE SCREEN
----------------------------------------------------------------
local function title_update()
  title_pulse = title_pulse + 1
  title_idle_timer = title_idle_timer + 1
  title_timer_count = title_timer_count + 1

  if title_pulse % 60 == 0 then sfx_title_ping() end

  if title_flicker > 0 then
    title_flicker = title_flicker - 1
  elseif math.random(200) < 3 then
    title_flicker = 5
  end

  -- Demo mode after idle
  if title_idle_timer > IDLE_TIMEOUT and not demo_mode then
    demo_mode = true
    current_room = 1
    timer = TOTAL_TIME
    inv = {}
    evidence_count = 0
    load_room(1)
    demo_path = {
      {dx=1,dy=0},{dx=1,dy=0},{dx=1,dy=0},{dx=1,dy=0},
      {dx=1,dy=0},{dx=1,dy=0},{dx=1,dy=0},
      {dx=0,dy=-1},{dx=0,dy=-1},{dx=0,dy=-1},{dx=0,dy=-1},
      {dx=0,dy=0,ping=true},
      {dx=1,dy=0},{dx=1,dy=0},{dx=1,dy=0},{dx=1,dy=0},
      {dx=0,dy=0,ping=true},
      {dx=0,dy=1},{dx=0,dy=1},{dx=0,dy=1},{dx=0,dy=1},{dx=0,dy=1},
      {dx=-1,dy=0},{dx=-1,dy=0},{dx=-1,dy=0},
      {dx=0,dy=0,ping=true},
      {dx=0,dy=1},{dx=0,dy=1},{dx=0,dy=1},{dx=0,dy=1},
      {dx=1,dy=0},{dx=1,dy=0},{dx=1,dy=0},{dx=1,dy=0},{dx=1,dy=0},
    }
    demo_step = 1
    demo_timer = 0
  end

  if demo_mode then
    demo_timer = demo_timer + 1
    if demo_timer % 8 == 0 then
      if demo_step <= #demo_path then
        local step = demo_path[demo_step]
        if step.ping then
          do_sonar_ping()
        else
          local nx = px + step.dx
          local ny = py + step.dy
          local tile = get_tile(nx, ny)
          if tile == T_EMPTY then
            px, py = nx, ny
            sfx_footstep()
          elseif tile == T_ITEM or tile == T_EVIDENCE then
            px, py = nx, ny
            sfx_pickup()
          end
        end
        demo_step = demo_step + 1
      else
        -- Restart demo
        load_room(1)
        demo_step = 1
      end
    end
    update_sonar()
    update_entity()

    -- Exit demo on input timeout or button
    if demo_timer > DEMO_DURATION then
      demo_mode = false
      title_idle_timer = 0
    end
  end

  if btnp("start") or btnp("a") then
    demo_mode = false
    scene = "game"
    current_room = 1
    timer = TOTAL_TIME
    inv = {}
    evidence_count = 0
    frame_count = 0
    heartbeat_rate = 0
    heartbeat_timer = 0
    entity_eyes = {}
    darkness_tendrils = {}
    static_amount = 0
    amb_drip_timer = 40
    amb_creak_timer = 80
    scare_flash = 0
    shake_timer = 0
    ending_type = "survival"
    load_room(1)
    show_hint("PING TO SEE. CRAFT TO ESCAPE.", 120)
  end
end

local function title_draw()
  local s = screen()
  cls(s, BLACK)

  -- Flicker
  local tc = WHITE
  local flick = math.random(100)
  if flick < 6 then tc = DARK
  elseif flick < 12 then tc = LIGHT end
  if title_flicker > 0 and title_flicker > 3 then tc = BLACK end

  if tc > BLACK then
    text(s, "CONTAINMENT BREACH", W/2, 14, tc, ALIGN_CENTER)
  end

  -- Decorative line
  line(s, 25, 24, 135, 24, DARK)

  -- Staged reveal
  if title_timer_count > 20 then
    text(s, "the facility is flooding.", W/2, 32, DARK, ALIGN_CENTER)
  end
  if title_timer_count > 50 then
    text(s, "something patrols the dark.", W/2, 42, DARK, ALIGN_CENTER)
  end
  if title_timer_count > 80 then
    text(s, "you have 120 seconds.", W/2, 52, LIGHT, ALIGN_CENTER)
  end
  if title_timer_count > 110 then
    text(s, "craft. collect. escape.", W/2, 62, DARK, ALIGN_CENTER)
  end

  -- Sonar ring on title
  local ring_r = (title_pulse % 60) * 1.5
  if ring_r < 80 then
    local cx, cy = W/2, 82
    local segs = 24
    for i = 0, segs-1 do
      local a = (i / segs) * math.pi * 2
      local rx = cx + math.cos(a) * ring_r
      local ry = cy + math.sin(a) * ring_r * 0.5
      if rx >= 0 and rx < W and ry >= 0 and ry < H then
        local c = ring_r < 40 and DARK or BLACK
        if c > 0 then pix(s, math.floor(rx), math.floor(ry), c) end
      end
    end
    pix(s, cx, 82, WHITE)
  end

  -- Wandering entity eyes
  if title_timer_count > 100 then
    local blink = math.floor(title_pulse / 20) % 5
    if blink < 2 then
      local eye_x = W/2 + math.sin(title_pulse * 0.02) * 30
      local eye_y = 82 + math.cos(title_pulse * 0.015) * 8
      pix(s, math.floor(eye_x)-1, math.floor(eye_y), LIGHT)
      pix(s, math.floor(eye_x)+1, math.floor(eye_y), LIGHT)
    end
  end

  -- Demo overlay
  if demo_mode then
    local dpx = px * TILE + 4
    local dpy = py * TILE + 4
    pix(s, dpx, dpy, WHITE)
    for _, p in ipairs(ring_particles) do
      if p.x >= 0 and p.x < W and p.y >= 0 and p.y < H then
        pix(s, math.floor(p.x), math.floor(p.y), p.col)
      end
    end
    text(s, "- DEMO -", W/2, 4, DARK, ALIGN_CENTER)
  end

  -- Blink prompt
  if title_pulse % 40 < 25 then
    text(s, "PRESS START", W/2, 108, LIGHT, ALIGN_CENTER)
  end
end

----------------------------------------------------------------
-- VICTORY SCREEN
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
  local s = screen()
  cls(s, BLACK)

  -- Expanding sonar rings (escape light)
  local r = math.min(victory_timer * 0.8, 50)
  local cx, cy = W/2, H/2
  for ring = math.floor(r), 0, -4 do
    local col = DARK
    if ring < r * 0.3 then col = WHITE
    elseif ring < r * 0.6 then col = LIGHT end
    local segs = 24
    for i = 0, segs-1 do
      local a = (i / segs) * math.pi * 2
      local rx = cx + math.cos(a) * ring
      local ry = cy + math.sin(a) * ring
      if rx >= 0 and rx < W and ry >= 0 and ry < H then
        pix(s, math.floor(rx), math.floor(ry), col)
      end
    end
  end

  if victory_timer > 20 then
    if ending_type == "true" then
      text(s, "TRUTH REVEALED", W/2, H/2 - 16, WHITE, ALIGN_CENTER)
    else
      text(s, "ESCAPED", W/2, H/2 - 16, WHITE, ALIGN_CENTER)
    end
  end

  if victory_timer > 40 then
    local secs_left = math.ceil(timer / 30)
    text(s, "Time: " .. secs_left .. "s remaining", W/2, H/2 - 4, LIGHT, ALIGN_CENTER)
    text(s, "Evidence: " .. evidence_count .. "/3", W/2, H/2 + 6, LIGHT, ALIGN_CENTER)
  end

  if victory_timer > 60 then
    if ending_type == "true" then
      text(s, "The world will know", W/2, H/2 + 20, DARK, ALIGN_CENTER)
      text(s, "what they did here.", W/2, H/2 + 30, DARK, ALIGN_CENTER)
    else
      text(s, "You survived.", W/2, H/2 + 20, DARK, ALIGN_CENTER)
      text(s, "But the truth remains buried.", W/2, H/2 + 30, DARK, ALIGN_CENTER)
    end
  end

  if victory_timer > 80 then
    -- Rating
    local secs_left = math.ceil(timer / 30)
    local rating = "BARELY ALIVE"
    if ending_type == "true" and secs_left > 30 then rating = "WHISTLEBLOWER"
    elseif ending_type == "true" then rating = "TRUTH SEEKER"
    elseif secs_left > 60 then rating = "SWIFT ESCAPE"
    elseif secs_left > 30 then rating = "CLOSE CALL"
    end
    text(s, rating, W/2, H/2 + 44, WHITE, ALIGN_CENTER)
  end

  if victory_timer > 90 and victory_timer % 40 < 25 then
    text(s, "PRESS START", W/2, H - 8, DARK, ALIGN_CENTER)
  end
end

----------------------------------------------------------------
-- GAME OVER SCREEN
----------------------------------------------------------------
local function gameover_update()
  victory_timer = victory_timer + 1

  if victory_timer == 10 then
    noise(0, 0.4); wave(1, "sine"); tone(1, 55, 40, 0.5)
  end
  if victory_timer == 30 then
    noise(1, 0.3); wave(2, "sine"); tone(2, 44, 35, 0.5)
  end

  if victory_timer > 90 and (btnp("start") or btnp("a")) then
    scene = "title"
    title_pulse = 0
    title_idle_timer = 0
    title_timer_count = 0
    demo_mode = false
  end
end

local function gameover_draw()
  local s = screen()
  cls(s, BLACK)

  if victory_timer < 20 then
    -- Static burst + face
    for i = 1, 100 do
      pix(s, math.random(0, W-1), math.random(0, H-1), math.random(0, WHITE))
    end
    if victory_timer > 8 then draw_entity_face(s) end
    return
  end

  if victory_timer < 40 then
    draw_vignette(s, (victory_timer - 20) / 20)
    text(s, "DROWNED", W/2, H/2, DARK, ALIGN_CENTER)
    return
  end

  -- Glitch
  if math.random() < 0.1 then
    line(s, 0, math.random(0, H-1), W-1, math.random(0, H-1), DARK)
  end

  text(s, "CONTAINMENT FAILED", W/2, 24, WHITE, ALIGN_CENTER)
  text(s, "The water took everything.", W/2, 40, LIGHT, ALIGN_CENTER)

  text(s, "Sector reached: " .. current_room .. "/3", W/2, 60, LIGHT, ALIGN_CENTER)
  text(s, "Evidence found: " .. evidence_count .. "/3", W/2, 70, DARK, ALIGN_CENTER)

  local survived = math.floor((TOTAL_TIME - timer) / 30)
  text(s, "Survived: " .. survived .. "s", W/2, 80, DARK, ALIGN_CENTER)

  if victory_timer > 90 and victory_timer % 40 < 25 then
    text(s, "PRESS START", W/2, 100, DARK, ALIGN_CENTER)
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
  wave(CH_FOOT, "triangle")
end

function _update()
  if scene == "title" then
    title_update()
  elseif scene == "game" then
    game_update()
  elseif scene == "victory" then
    victory_update()
  elseif scene == "gameover" then
    gameover_update()
  end
end

function _draw()
  if scene == "title" then
    title_draw()
  elseif scene == "game" then
    game_draw()
  elseif scene == "victory" then
    victory_draw()
  elseif scene == "gameover" then
    gameover_draw()
  end
end
