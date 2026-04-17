-- ABYSSAL STATION
-- Agent 22 (Wave 3) | Top-down sonar horror adventure
-- Merged: Agent 13 (sonar), Agent 19 (escalating horror), Agent 18 (crafting/narrative)
-- 160x120 | 2-bit (4 shades) | mode(2) | single-file
-- D-Pad: Move | A: Ping/Interact | B: Inventory | START: Pause

----------------------------------------------------------------
-- CONSTANTS
----------------------------------------------------------------
local W, H = 160, 120
local TILE = 8
local COLS, ROWS = 20, 15
local SONAR_CD = 18
local SONAR_MAX = 70
local SONAR_SPD = 2.8
local MOVE_DELAY = 5

-- 2-bit palette
local BLK, DRK, LIT, WHT = 0, 1, 2, 3

-- Tile types
local T_EMPTY = 0
local T_WALL  = 1
local T_DOOR  = 2
local T_ITEM  = 3
local T_EXIT  = 4
local T_DOC   = 5

-- Sound channels
local CH_SONAR = 0
local CH_OBJ   = 1
local CH_AMB   = 2
local CH_FOOT  = 3

-- Demo
local IDLE_MAX = 150
local DEMO_LEN = 500

----------------------------------------------------------------
-- SAFE AUDIO
----------------------------------------------------------------
local function snd_tone(ch, a, b, dur) if tone then tone(ch, a, b, dur) end end
local function snd_wave(ch, w) if wave then wave(ch, w) end end
local function snd_noise(ch, dur) if noise then noise(ch, dur) end end
local function snd_note(ch, n, dur) if note then note(ch, n, dur) end end

----------------------------------------------------------------
-- SOUND EFFECTS
----------------------------------------------------------------
local foot_alt = false
local function sfx_step()
  foot_alt = not foot_alt
  snd_wave(CH_FOOT, "triangle")
  snd_tone(CH_FOOT, foot_alt and 80 or 70, foot_alt and 60 or 50, 0.03)
end
local function sfx_bump() snd_noise(CH_FOOT, 0.04) end
local function sfx_ping()
  snd_wave(CH_SONAR, "sine")
  snd_tone(CH_SONAR, 1200, 400, 0.15)
end
local function sfx_key()
  snd_wave(CH_OBJ, "sine"); snd_tone(CH_OBJ, 800, 1600, 0.1)
  snd_wave(CH_SONAR, "sine"); snd_tone(CH_SONAR, 1000, 2000, 0.1)
end
local function sfx_door()
  snd_wave(CH_OBJ, "triangle"); snd_tone(CH_OBJ, 200, 400, 0.2)
end
local function sfx_craft()
  snd_note(0, "E5", 0.08); snd_note(1, "G5", 0.08); snd_note(0, "C6", 0.12)
end
local function sfx_pickup()
  snd_note(0, "C5", 0.06); snd_note(0, "E5", 0.06)
end
local function sfx_read() snd_note(0, "D4", 0.06); snd_note(1, "F4", 0.04) end
local function sfx_locked() snd_noise(0, 0.08); snd_note(1, "C2", 0.08) end
local function sfx_entity_step(d)
  if d > 15 then return end
  local t = math.max(0, math.min(1, 1 - d / 15))
  snd_wave(CH_FOOT, "square")
  snd_tone(CH_FOOT, 200 - t * 100, 160 - t * 80, 0.01 + t * 0.03)
end
local function sfx_growl()
  snd_wave(CH_AMB, "sawtooth"); snd_tone(CH_AMB, 45, 35, 0.12)
end
local function sfx_jumpscare()
  snd_noise(CH_SONAR, 0.2); snd_wave(CH_OBJ, "sawtooth")
  snd_tone(CH_OBJ, 80, 40, 0.3); snd_noise(CH_FOOT, 0.15)
  snd_wave(CH_AMB, "square"); snd_tone(CH_AMB, 100, 50, 0.25)
end
local function sfx_heartbeat(r)
  snd_wave(CH_AMB, "sine")
  local b = 50 + r * 20
  snd_tone(CH_AMB, b, b * 0.7, 0.06)
end
local function sfx_drip()
  snd_wave(CH_OBJ, "sine")
  snd_tone(CH_OBJ, 1200 + math.random(800), 600, 0.02)
end
local function sfx_creak()
  snd_wave(CH_AMB, "sawtooth")
  local f = ({55,62,48,70})[math.random(4)]
  snd_tone(CH_AMB, f, f * 0.8, 0.1)
end
local function sfx_drone()
  snd_wave(CH_AMB, "triangle"); snd_tone(CH_AMB, 45, 48, 0.5)
end
local function sfx_alert()
  snd_wave(CH_OBJ, "square"); snd_tone(CH_OBJ, 120, 80, 0.08)
end
local function sfx_victory()
  snd_wave(0, "sine"); snd_tone(0, 400, 800, 0.2)
  snd_wave(1, "sine"); snd_tone(1, 600, 1200, 0.2)
end
local function sfx_scare(v)
  snd_noise(0, 0.15 + v * 0.1); snd_note(1, "C2", 0.2 + v * 0.1)
end

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
local function lerp(a, b, t) return a + (b - a) * t end

----------------------------------------------------------------
-- ITEMS & CRAFTING (from Agent 18)
----------------------------------------------------------------
local ITEMS = {
  matches   = {name="Matches",    desc="Three matches.",          icon="M"},
  lens      = {name="Glass Lens", desc="Cracked magnifying lens.",icon="O"},
  lantern   = {name="Lantern",    desc="Makeshift light source.", icon="*"},
  wire      = {name="Wire",       desc="Thin copper wire.",       icon="W"},
  metal_rod = {name="Metal Rod",  desc="Short iron rod.",         icon="I"},
  lockpick  = {name="Lockpick",   desc="Bent wire pick.",         icon="P"},
  tape      = {name="Tape",       desc="Electrical tape.",        icon="T"},
  fuse_dead = {name="Dead Fuse",  desc="Blown 30-amp fuse.",      icon="F"},
  fuse_good = {name="Fixed Fuse", desc="Taped fuse. Works!",      icon="f"},
  key_brass = {name="Brass Key",  desc="Heavy brass key.",        icon="K"},
  key_lab   = {name="Lab Key",    desc="Scratched lab keycard.",  icon="L"},
  key_exit  = {name="Exit Key",   desc="Glows faintly blue.",     icon="X"},
  crowbar   = {name="Crowbar",    desc="Heavy. Pries open.",      icon="C"},
  journal1  = {name="Journal p.1",desc="Day 1: sublevel 4.",      icon="J"},
  journal2  = {name="Journal p.2",desc="Day 15: the sounds.",     icon="J"},
  journal3  = {name="Journal p.3",desc="Day 31: I am Subject 17.",icon="J"},
  evidence  = {name="Evidence",   desc="Subject 17 file.",        icon="E"},
}

local RECIPES = {
  {a="matches",   b="lens",      result="lantern"},
  {a="wire",      b="metal_rod", result="lockpick"},
  {a="tape",      b="fuse_dead", result="fuse_good"},
}

-- Documents
local DOCUMENTS = {
  journal1 = "Day 1. Transferred to sublevel 4. The station is deeper than they told us. No natural light. The walls sweat.",
  journal2 = "Day 15. I hear it moving in the vents at night. Others say it's pipes. I know better. It responds to sound.",
  journal3 = "Day 31. They never rescued us. We ARE the experiment. I found my own file. Subject 17. The thing in the dark... it was one of us.",
  memo = "MEMO: Sublevel 4 lockdown. All sonar equipment silenced. Entity exhibits acoustic hunting behavior. Do NOT make noise.",
  evidence = "PROJECT ABYSS - Subject 17 transformation complete. Entity retains hunting instinct. Responds to sonar frequencies. Containment: FAILED.",
}

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local scene = "title"   -- title, play, inv, doc, dead, win, demo, pause
local S = nil
local tick = 0
local idle_timer = 0

-- Player (tile coords)
local px, py = 2, 7
local move_timer = 0
local has_lantern = false

-- Inventory
local inv = {}
local inv_sel = 1
local combine_mode = false
local combine_first = nil

-- Sonar
local sonar_timer = 0
local sonar_radius = 0
local sonar_active = false
local ring_particles = {}
local tile_reveal = {}  -- [y][x] = remaining reveal frames

-- Entity (tile coords, float)
local ex, ey = 17, 3
local e_speed = 0.025
local e_active = false
local e_chase = false
local e_alert_x, e_alert_y = -1, -1
local e_target_x, e_target_y = 15, 7
local e_patrol_timer = 0
local e_step_timer = 0
local e_accum_x, e_accum_y = 0, 0
local player_alive = true

-- Horror state (from Agent 19)
local heartbeat_rate = 0
local heartbeat_timer = 0
local amb_drip = 50
local amb_creak = 100
local amb_drone = 0
local scare_timer = 120
local scare_flash = 0
local shake_timer = 0
local shake_x, shake_y = 0, 0
local entity_eyes = {}
local darkness_tendrils = {}
local static_amount = 0

-- Messages / documents
local msg_text = ""
local msg_timer = 0
local doc_text = nil
local doc_lines = {}
local doc_scroll = 0

-- Hint
local hint_text = ""
local hint_timer = 0

-- Room
local cur_room = 1
local room_map = {}
local room_items = {}   -- {x,y,id} items on the floor
local room_docs = {}    -- {x,y,doc_key}
local death_timer = 0
local victory_timer = 0

-- Demo
local demo_mode = false
local demo_timer = 0
local demo_actions = {}
local demo_step = 1

-- Title
local title_pulse = 0

----------------------------------------------------------------
-- INVENTORY HELPERS
----------------------------------------------------------------
local function has_item(name)
  for i, v in ipairs(inv) do if v == name then return true, i end end
  return false
end

local function add_item(name)
  if not has_item(name) and #inv < 8 then
    inv[#inv + 1] = name
    sfx_pickup()
    msg_text = "Got: " .. ITEMS[name].name
    msg_timer = 60
    if name == "lantern" then has_lantern = true end
    return true
  end
  return false
end

local function remove_item(name)
  local found, idx = has_item(name)
  if found then table.remove(inv, idx) end
end

local function try_combine(a, b)
  for _, r in ipairs(RECIPES) do
    if (a == r.a and b == r.b) or (a == r.b and b == r.a) then
      remove_item(a); remove_item(b)
      add_item(r.result)
      sfx_craft()
      return ITEMS[r.result].name
    end
  end
  return nil
end

-- Word wrap
local function word_wrap(str, mx)
  local lines = {}
  for para in str:gmatch("[^\n]+") do
    local ln = ""
    for w in para:gmatch("%S+") do
      if #ln + #w + 1 > mx then lines[#lines+1] = ln; ln = w
      else ln = #ln > 0 and (ln .. " " .. w) or w end
    end
    if #ln > 0 then lines[#lines+1] = ln end
  end
  if #lines == 0 then lines[1] = "" end
  return lines
end

local function show_doc(key)
  local txt = DOCUMENTS[key]
  if not txt then return end
  doc_text = txt
  doc_lines = word_wrap(txt, 28)
  doc_scroll = 0
  scene = "doc"
  sfx_read()
end

local function show_msg(txt, dur)
  msg_text = txt; msg_timer = dur or 90
end

----------------------------------------------------------------
-- ROOM DEFINITIONS (6 rooms)
----------------------------------------------------------------
local function make_grid()
  local m = {}
  for y = 0, ROWS-1 do
    m[y] = {}
    for x = 0, COLS-1 do
      m[y][x] = (y == 0 or y == ROWS-1 or x == 0 or x == COLS-1) and T_WALL or T_EMPTY
    end
  end
  return m
end

local function build_room(num)
  local m = make_grid()
  local items = {}
  local docs = {}

  if num == 1 then
    -- Cell block: starting area
    for y = 1, 8 do m[y][10] = T_WALL end
    for x = 10, 14 do m[8][x] = T_WALL end
    m[4][4] = T_WALL; m[4][7] = T_WALL
    m[10][5] = T_WALL; m[10][15] = T_WALL
    m[8][12] = T_DOOR  -- needs brass key
    m[13][18] = T_EXIT
    items[#items+1] = {x=3, y=2, id="matches"}
    items[#items+1] = {x=15, y=3, id="key_brass"}
    docs[#docs+1]   = {x=8, y=12, key="journal1"}

  elseif num == 2 then
    -- Laboratory corridor
    for y = 0, 10 do m[y][5] = T_WALL end
    for y = 4, 14 do m[y][10] = T_WALL end
    for y = 0, 8 do m[y][15] = T_WALL end
    for x = 5, 10 do m[4][x] = T_WALL end
    for x = 10, 15 do m[10][x] = T_WALL end
    m[6][6] = T_EMPTY; m[6][7] = T_EMPTY
    m[10][13] = T_DOOR  -- needs lockpick
    m[13][17] = T_EXIT
    items[#items+1] = {x=18, y=2, id="lens"}
    items[#items+1] = {x=2, y=12, id="wire"}
    docs[#docs+1]   = {x=8, y=7, key="memo"}

  elseif num == 3 then
    -- Generator room
    for x = 3, 17 do m[7][x] = T_WALL end
    for y = 2, 12 do m[y][10] = T_WALL end
    m[7][6] = T_EMPTY; m[7][14] = T_EMPTY
    m[5][10] = T_EMPTY; m[10][10] = T_EMPTY
    m[3][4] = T_WALL; m[11][4] = T_WALL
    m[3][16] = T_WALL; m[11][16] = T_WALL
    m[7][10] = T_DOOR  -- needs fuse_good
    m[13][10] = T_EXIT
    items[#items+1] = {x=17, y=3, id="metal_rod"}
    items[#items+1] = {x=4, y=11, id="tape"}
    docs[#docs+1]   = {x=16, y=11, key="journal2"}

  elseif num == 4 then
    -- Archive
    for y = 3, 11 do m[y][7] = T_WALL end
    for y = 3, 11 do m[y][13] = T_WALL end
    for x = 7, 13 do m[3][x] = T_WALL end
    for x = 7, 13 do m[11][x] = T_WALL end
    m[3][10] = T_EMPTY; m[11][10] = T_EMPTY
    m[7][7] = T_EMPTY; m[7][13] = T_EMPTY
    m[7][7] = T_DOOR  -- needs lab key
    m[1][18] = T_EXIT
    items[#items+1] = {x=3, y=1, id="fuse_dead"}
    items[#items+1] = {x=10, y=7, id="key_lab"}
    docs[#docs+1]   = {x=10, y=5, key="evidence"}

  elseif num == 5 then
    -- Containment wing
    for x = 2, 8 do m[4][x] = T_WALL end
    for x = 12, 18 do m[4][x] = T_WALL end
    for x = 2, 8 do m[10][x] = T_WALL end
    for x = 12, 18 do m[10][x] = T_WALL end
    m[4][5] = T_EMPTY; m[10][5] = T_EMPTY
    m[4][15] = T_EMPTY; m[10][15] = T_EMPTY
    for y = 4, 10 do m[y][9] = T_WALL; m[y][11] = T_WALL end
    m[7][9] = T_EMPTY; m[7][11] = T_EMPTY
    m[7][9] = T_DOOR  -- needs crowbar
    m[13][1] = T_EXIT
    items[#items+1] = {x=15, y=7, id="crowbar"}
    items[#items+1] = {x=3, y=7, id="key_exit"}
    docs[#docs+1]   = {x=10, y=1, key="journal3"}

  elseif num == 6 then
    -- Final escape
    for y = 2, 12 do m[y][5] = T_WALL end
    for y = 2, 12 do m[y][15] = T_WALL end
    m[7][5] = T_EMPTY; m[7][15] = T_EMPTY
    for x = 5, 15 do m[7][x] = T_WALL end
    m[7][10] = T_EMPTY
    m[2][10] = T_WALL; m[12][10] = T_WALL
    m[3][3] = T_WALL; m[3][17] = T_WALL
    m[11][3] = T_WALL; m[11][17] = T_WALL
    m[7][10] = T_DOOR  -- needs exit key
    m[1][10] = T_EXIT  -- freedom
    items[#items+1] = {x=10, y=12, id="evidence"}
  end

  return m, items, docs
end

-- What key/item is needed for each room's door?
local DOOR_NEEDS = {
  [1] = "key_brass",
  [2] = "lockpick",
  [3] = "fuse_good",
  [4] = "key_lab",
  [5] = "crowbar",
  [6] = "key_exit",
}

-- Player start positions per room
local STARTS = {
  [1] = {x=2, y=7},
  [2] = {x=2, y=12},
  [3] = {x=2, y=4},
  [4] = {x=2, y=7},
  [5] = {x=2, y=2},
  [6] = {x=2, y=12},
}

-- Entity start positions per room
local E_STARTS = {
  [1] = {x=17, y=3},
  [2] = {x=17, y=2},
  [3] = {x=17, y=11},
  [4] = {x=17, y=12},
  [5] = {x=17, y=12},
  [6] = {x=17, y=2},
}

----------------------------------------------------------------
-- TILE HELPERS
----------------------------------------------------------------
local function get_tile(tx, ty)
  if ty < 0 or ty >= ROWS or tx < 0 or tx >= COLS then return T_WALL end
  return room_map[ty][tx]
end

local function walkable(tx, ty)
  local t = get_tile(tx, ty)
  return t == T_EMPTY or t == T_ITEM or t == T_DOC or t == T_EXIT
end

local function init_reveal()
  tile_reveal = {}
  for y = 0, ROWS-1 do
    tile_reveal[y] = {}
    for x = 0, COLS-1 do tile_reveal[y][x] = 0 end
  end
end

----------------------------------------------------------------
-- LOAD ROOM
----------------------------------------------------------------
local function load_room(num)
  cur_room = num
  local m, it, dc = build_room(num)
  room_map = m
  room_items = it
  room_docs = dc

  -- Mark item/doc tiles
  for _, item in ipairs(room_items) do
    room_map[item.y][item.x] = T_ITEM
  end
  for _, doc in ipairs(room_docs) do
    room_map[doc.y][doc.x] = T_DOC
  end

  -- Player
  local sp = STARTS[num] or {x=2, y=7}
  px, py = sp.x, sp.y
  player_alive = true
  move_timer = 0

  -- Sonar reset
  sonar_active = false; sonar_radius = 0; sonar_timer = 0
  ring_particles = {}
  init_reveal()

  -- Entity
  local ep = E_STARTS[num] or {x=17, y=3}
  ex, ey = ep.x, ep.y
  e_active = true
  e_chase = false
  e_alert_x, e_alert_y = -1, -1
  e_speed = 0.02 + num * 0.006
  e_patrol_timer = 0; e_step_timer = 0
  e_accum_x, e_accum_y = 0, 0
  e_target_x, e_target_y = ep.x, ep.y

  -- Horror reset
  scare_timer = 120; scare_flash = 0; shake_timer = 0
  entity_eyes = {}; darkness_tendrils = {}
  heartbeat_rate = 0; heartbeat_timer = 0
  static_amount = 0; death_timer = 0
  hint_text = ""; hint_timer = 0
  msg_text = ""; msg_timer = 0
  doc_text = nil
end

----------------------------------------------------------------
-- ENTITY AI (from Agent 13)
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
    if tick % 60 == 0 then
      e_target_x = clamp(math.floor(ex) + math.random(-4, 4), 1, COLS-2)
      e_target_y = clamp(math.floor(ey) + math.random(-4, 4), 1, ROWS-2)
    end
  else
    e_chase = false
    if tick % 90 == 0 then
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
    e_accum_x = e_accum_x + (dx / td) * speed
    e_accum_y = e_accum_y + (dy / td) * speed

    if math.abs(e_accum_x) >= 1 then
      local sx = e_accum_x > 0 and 1 or -1
      e_accum_x = e_accum_x - sx
      if entity_can_move(math.floor(ex + sx), math.floor(ey)) then
        ex = ex + sx
      end
    end
    if math.abs(e_accum_y) >= 1 then
      local sy = e_accum_y > 0 and 1 or -1
      e_accum_y = e_accum_y - sy
      if entity_can_move(math.floor(ex), math.floor(ey + sy)) then
        ey = ey + sy
      end
    end
  end

  -- Entity footsteps
  e_step_timer = e_step_timer + 1
  if e_step_timer >= (e_chase and 12 or 20) then
    e_step_timer = 0; sfx_entity_step(d)
  end

  -- Growl
  if e_chase and d < 6 and tick % 40 == 0 then sfx_growl() end

  -- Caught player?
  if d < 1.5 then
    sfx_jumpscare()
    scare_flash = 12; shake_timer = 15
    player_alive = false; death_timer = 0
  end

  -- Near-scare
  if d < 3 and math.random(100) < 4 and scare_flash <= 0 then
    scare_flash = 3; shake_timer = 4
    snd_noise(CH_SONAR, 0.06)
  end
end

----------------------------------------------------------------
-- SONAR SYSTEM (from Agent 13)
----------------------------------------------------------------
local function do_ping()
  if sonar_timer > 0 then return end
  sonar_active = true; sonar_radius = 0; sonar_timer = SONAR_CD
  sfx_ping(); ring_particles = {}

  -- Alert entity
  if e_active and player_alive then
    e_alert_x, e_alert_y = px, py
    e_chase = true
    sfx_alert()
    hint_text = "...IT HEARD YOU"
    hint_timer = 40
  end
end

local function update_sonar()
  if sonar_timer > 0 then sonar_timer = sonar_timer - 1 end
  if not sonar_active then return end

  sonar_radius = sonar_radius + SONAR_SPD

  -- Reveal tiles as ring passes
  if tick % 2 == 0 then
    local angles = 24
    for i = 0, angles - 1 do
      local a = (i / angles) * math.pi * 2
      local rx = px * TILE + 4 + math.cos(a) * sonar_radius
      local ry = py * TILE + 4 + math.sin(a) * sonar_radius
      if rx >= 0 and rx < W and ry >= 0 and ry < H then
        local tx = math.floor(rx / TILE)
        local ty = math.floor(ry / TILE)
        if tx >= 0 and tx < COLS and ty >= 0 and ty < ROWS then
          local t = room_map[ty][tx]
          tile_reveal[ty][tx] = t == T_WALL and 25 or 12
        end
        -- Ring particle
        local life = (get_tile(math.floor(rx/TILE), math.floor(ry/TILE)) == T_WALL) and 10 or 4
        ring_particles[#ring_particles+1] = {x=rx, y=ry, life=life, col=DRK}
      end
    end
  end

  -- Reveal items/docs with bright flash
  for _, item in ipairs(room_items) do
    local id = dist(px, py, item.x, item.y)
    if sonar_radius >= id * TILE and sonar_radius < id * TILE + SONAR_SPD * 2 then
      tile_reveal[item.y][item.x] = 25
      ring_particles[#ring_particles+1] = {x=item.x*TILE+4, y=item.y*TILE+4, life=20, col=WHT}
      -- Sound cue
      local dur = math.max(0.02, 0.1 - id * 0.005)
      snd_wave(CH_OBJ, "sine"); snd_tone(CH_OBJ, 800 + (18-id)*60, 1000, dur)
    end
  end
  for _, doc in ipairs(room_docs) do
    local dd = dist(px, py, doc.x, doc.y)
    if sonar_radius >= dd * TILE and sonar_radius < dd * TILE + SONAR_SPD * 2 then
      tile_reveal[doc.y][doc.x] = 25
      ring_particles[#ring_particles+1] = {x=doc.x*TILE+4, y=doc.y*TILE+4, life=20, col=LIT}
    end
  end

  -- Reveal entity
  if e_active then
    local ed = dist(px, py, ex, ey)
    if sonar_radius >= ed * TILE and sonar_radius < ed * TILE + SONAR_SPD * 2 then
      ring_particles[#ring_particles+1] = {x=ex*TILE+4, y=ey*TILE+4, life=15, col=WHT}
      tile_reveal[math.floor(ey)][math.floor(ex)] = 18
      snd_wave(CH_OBJ, "sawtooth"); snd_tone(CH_OBJ, 150, 60, 0.1)
    end
  end

  -- Reveal door
  for y = 0, ROWS-1 do
    for x = 0, COLS-1 do
      if room_map[y][x] == T_DOOR then
        local dd = dist(px, py, x, y)
        if sonar_radius >= dd * TILE and sonar_radius < dd * TILE + SONAR_SPD * 2 then
          tile_reveal[y][x] = 30
          ring_particles[#ring_particles+1] = {x=x*TILE+4, y=y*TILE+4, life=20, col=LIT}
        end
      end
      if room_map[y][x] == T_EXIT then
        local dd = dist(px, py, x, y)
        if sonar_radius >= dd * TILE and sonar_radius < dd * TILE + SONAR_SPD * 2 then
          tile_reveal[y][x] = 30
          ring_particles[#ring_particles+1] = {x=x*TILE+4, y=y*TILE+4, life=25, col=WHT}
        end
      end
    end
  end

  if sonar_radius > SONAR_MAX then sonar_active = false end

  -- Update particles
  local alive = {}
  for _, p in ipairs(ring_particles) do
    p.life = p.life - 1
    if p.life > 0 then alive[#alive+1] = p end
  end
  ring_particles = alive
end

-- Decay tile reveals
local function update_reveal()
  for y = 0, ROWS-1 do
    for x = 0, COLS-1 do
      if tile_reveal[y][x] > 0 then
        tile_reveal[y][x] = tile_reveal[y][x] - 1
      end
    end
  end
  -- Lantern: keep tiles near player revealed
  if has_lantern then
    for dy = -2, 2 do
      for dx = -2, 2 do
        local tx, ty = px + dx, py + dy
        if tx >= 0 and tx < COLS and ty >= 0 and ty < ROWS then
          if dist(px, py, tx, ty) <= 2.5 then
            tile_reveal[ty][tx] = math.max(tile_reveal[ty][tx], 3)
          end
        end
      end
    end
  end
  -- Always reveal player tile
  if py >= 0 and py < ROWS and px >= 0 and px < COLS then
    tile_reveal[py][px] = math.max(tile_reveal[py][px], 3)
  end
end

----------------------------------------------------------------
-- ESCALATING HORROR (from Agent 19)
----------------------------------------------------------------
local function spawn_eyes()
  if #entity_eyes >= 6 then return end
  local side = math.random(1, 4)
  local x, y
  if side == 1 then x = math.random(10, W-10); y = math.random(2, 10)
  elseif side == 2 then x = math.random(10, W-10); y = math.random(H-12, H-4)
  elseif side == 3 then x = math.random(2, 14); y = math.random(10, H-10)
  else x = math.random(W-16, W-4); y = math.random(10, H-10)
  end
  entity_eyes[#entity_eyes+1] = {x=x, y=y, life=math.random(30,90), blink=math.random(0,100)}
end

local function update_horror()
  if not player_alive then return end

  local d = dist(px, py, ex, ey)
  local urgency = clamp(1 - d / 15, 0, 1)

  -- Ambient drips
  amb_drip = amb_drip - 1
  if amb_drip <= 0 then amb_drip = 50 + math.random(80); sfx_drip() end

  -- Creaks
  amb_creak = amb_creak - 1
  if amb_creak <= 0 then
    amb_creak = 60 + math.random(math.floor(lerp(120, 30, urgency)))
    sfx_creak()
  end

  -- Drone
  amb_drone = amb_drone + 1
  if amb_drone >= 90 then amb_drone = 0; sfx_drone() end

  -- Heartbeat
  heartbeat_rate = lerp(heartbeat_rate, urgency, 0.05)
  if heartbeat_rate > 0.08 then
    heartbeat_timer = heartbeat_timer - 1
    if heartbeat_timer <= 0 then
      heartbeat_timer = math.floor(lerp(30, 6, heartbeat_rate))
      sfx_heartbeat(heartbeat_rate)
    end
  end

  -- Entity eyes
  if math.random(100) < math.floor(urgency * 12) then spawn_eyes() end
  local i = 1
  while i <= #entity_eyes do
    local e = entity_eyes[i]
    e.life = e.life - 1; e.blink = e.blink + 1
    if e.life <= 0 then
      entity_eyes[i] = entity_eyes[#entity_eyes]
      entity_eyes[#entity_eyes] = nil
    else i = i + 1 end
  end

  -- Scare events
  scare_timer = scare_timer - 1
  if scare_timer <= 0 then
    scare_timer = math.floor(lerp(300, 60, urgency)) + math.random(60)
    if urgency > 0.3 and math.random(100) < math.floor(urgency * 40) then
      sfx_scare(urgency)
      scare_flash = math.floor(urgency * 4) + 2
      shake_timer = math.floor(urgency * 6) + 4
    end
  end

  -- Static
  static_amount = 0
  if urgency > 0.5 then
    static_amount = (urgency - 0.5) * 0.6
    if urgency > 0.85 then static_amount = static_amount + math.random() * 0.2 end
  end

  -- Darkness tendrils
  if urgency < 0.2 then darkness_tendrils = {} else
    local mx = math.floor(urgency * 20)
    while #darkness_tendrils < mx do
      local side = math.random(1,4)
      local t = {}
      if side == 1 then t.x=math.random(0,W-1); t.y=0; t.dx=(math.random()-0.5)*0.5; t.dy=0.3+math.random()*0.5
      elseif side == 2 then t.x=math.random(0,W-1); t.y=H-1; t.dx=(math.random()-0.5)*0.5; t.dy=-(0.3+math.random()*0.5)
      elseif side == 3 then t.x=0; t.y=math.random(0,H-1); t.dx=0.3+math.random()*0.5; t.dy=(math.random()-0.5)*0.5
      else t.x=W-1; t.y=math.random(0,H-1); t.dx=-(0.3+math.random()*0.5); t.dy=(math.random()-0.5)*0.5
      end
      t.len = math.floor(urgency*25) + math.random(5,15); t.life = t.len
      darkness_tendrils[#darkness_tendrils+1] = t
    end
    local j = 1
    while j <= #darkness_tendrils do
      local t = darkness_tendrils[j]
      t.x = t.x + t.dx; t.y = t.y + t.dy; t.life = t.life - 1
      if t.life <= 0 then
        darkness_tendrils[j] = darkness_tendrils[#darkness_tendrils]
        darkness_tendrils[#darkness_tendrils] = nil
      else j = j + 1 end
    end
  end
end

----------------------------------------------------------------
-- PLAYER INPUT
----------------------------------------------------------------
local function update_player()
  if not player_alive then return end

  move_timer = math.max(0, move_timer - 1)

  local dx, dy = 0, 0
  if btn("left") then dx = -1
  elseif btn("right") then dx = 1
  elseif btn("up") then dy = -1
  elseif btn("down") then dy = 1 end

  if (dx ~= 0 or dy ~= 0) and move_timer == 0 then
    move_timer = MOVE_DELAY
    local nx, ny = px + dx, py + dy

    if walkable(nx, ny) then
      px, py = nx, ny; sfx_step()
      idle_timer = 0

      -- Pick up items
      for i = #room_items, 1, -1 do
        local it = room_items[i]
        if it.x == px and it.y == py then
          add_item(it.id)
          room_map[it.y][it.x] = T_EMPTY
          table.remove(room_items, i)
        end
      end

      -- Read documents
      for i = #room_docs, 1, -1 do
        local dc = room_docs[i]
        if dc.x == px and dc.y == py then
          show_doc(dc.key)
          room_map[dc.y][dc.x] = T_EMPTY
          table.remove(room_docs, i)
        end
      end

    elseif get_tile(nx, ny) == T_DOOR then
      -- Try to open door
      local need = DOOR_NEEDS[cur_room]
      if need and has_item(need) then
        remove_item(need)
        room_map[ny][nx] = T_EMPTY
        sfx_door()
        show_msg("Door opened!", 45)
      else
        sfx_locked()
        local item_name = need and ITEMS[need] and ITEMS[need].name or "something"
        show_msg("Locked. Need: " .. item_name, 60)
      end

    elseif get_tile(nx, ny) == T_EXIT then
      -- Go to next room
      if cur_room >= 6 then
        scene = "win"; victory_timer = 0
        sfx_victory()
      else
        load_room(cur_room + 1)
        show_msg("Room " .. cur_room, 45)
      end

    else
      sfx_bump()
    end
  end

  -- A button: sonar ping
  if btnp("a") then do_ping() end

  -- B button: inventory
  if btnp("b") then
    if #inv > 0 then
      scene = "inv"; inv_sel = 1; combine_mode = false; combine_first = nil
    else
      show_msg("Inventory empty", 40)
    end
  end

  -- START: pause
  if btnp("start") then scene = "pause" end
end

----------------------------------------------------------------
-- DRAWING
----------------------------------------------------------------
local function draw_tile(s, tx, ty, reveal)
  local sx, sy = tx * TILE, ty * TILE
  local t = room_map[ty][tx]

  if reveal <= 0 then return end  -- dark

  local bright = reveal > 8
  local dim = reveal <= 8

  if t == T_WALL then
    rectf(s, sx, sy, TILE, TILE, bright and LIT or DRK)
    -- Wall detail
    if bright then
      rect(s, sx, sy, TILE, TILE, WHT)
    end
  elseif t == T_DOOR then
    rectf(s, sx, sy, TILE, TILE, BLK)
    rect(s, sx, sy, TILE, TILE, bright and WHT or LIT)
    -- Door handle
    pix(s, sx + 5, sy + 4, bright and WHT or LIT)
  elseif t == T_ITEM then
    -- Sparkle for items
    local fc = bright and WHT or LIT
    pix(s, sx+3, sy+3, fc); pix(s, sx+4, sy+4, fc)
    pix(s, sx+4, sy+3, fc); pix(s, sx+3, sy+4, fc)
    if bright then
      pix(s, sx+2, sy+3, DRK); pix(s, sx+5, sy+4, DRK)
    end
  elseif t == T_DOC then
    -- Paper icon
    local fc = bright and LIT or DRK
    rectf(s, sx+2, sy+1, 4, 6, fc)
    if bright then
      pix(s, sx+3, sy+3, WHT); pix(s, sx+4, sy+3, WHT)
      pix(s, sx+3, sy+5, WHT)
    end
  elseif t == T_EXIT then
    -- Pulsing exit marker
    local pulse = math.sin(tick * 0.1) > 0
    rectf(s, sx+1, sy+1, 6, 6, pulse and LIT or DRK)
    if bright then
      rect(s, sx, sy, TILE, TILE, WHT)
      text(s, ">", sx+2, sy+1, WHT)
    end
  else
    -- Empty floor: subtle checker when bright
    if bright then
      local checker = (tx + ty) % 2
      if checker == 1 then pix(s, sx+3, sy+3, DRK) end
    end
  end
end

local function draw_player(s)
  local sx, sy = px * TILE, py * TILE
  -- Simple character
  rectf(s, sx+2, sy+1, 4, 6, WHT)
  -- Eyes
  pix(s, sx+3, sy+2, BLK); pix(s, sx+4, sy+2, BLK)
  -- Feet
  pix(s, sx+2, sy+7, LIT); pix(s, sx+5, sy+7, LIT)
end

local function draw_entity(s)
  if not e_active then return end
  local erx = math.floor(ex)
  local ery = math.floor(ey)
  -- Only visible if tile is revealed
  if ery >= 0 and ery < ROWS and erx >= 0 and erx < COLS then
    if tile_reveal[ery][erx] > 0 then
      local sx, sy = erx * TILE, ery * TILE
      -- Menacing figure
      rectf(s, sx+1, sy+0, 6, 7, WHT)
      -- Hollow eyes
      pix(s, sx+2, sy+2, BLK); pix(s, sx+5, sy+2, BLK)
      -- Jagged mouth
      pix(s, sx+2, sy+4, BLK); pix(s, sx+4, sy+4, BLK)
      pix(s, sx+3, sy+5, BLK); pix(s, sx+5, sy+5, BLK)
    end
  end
end

local function draw_sonar_ring(s)
  if not sonar_active then return end
  local cx = px * TILE + 4
  local cy = py * TILE + 4
  local r = math.floor(sonar_radius)
  -- Draw ring
  local pts = 32
  for i = 0, pts - 1 do
    local a = (i / pts) * math.pi * 2
    local rx = math.floor(cx + math.cos(a) * r)
    local ry = math.floor(cy + math.sin(a) * r)
    if rx >= 0 and rx < W and ry >= 0 and ry < H then
      pix(s, rx, ry, DRK)
    end
  end
end

local function draw_particles(s)
  for _, p in ipairs(ring_particles) do
    local rx = math.floor(p.x)
    local ry = math.floor(p.y)
    if rx >= 0 and rx < W and ry >= 0 and ry < H then
      pix(s, rx, ry, p.col)
    end
  end
end

local function draw_eyes(s)
  for _, e in ipairs(entity_eyes) do
    if (e.blink % 40) >= 3 then
      local c = e.life < 10 and DRK or LIT
      pix(s, e.x, e.y, c); pix(s, e.x+3, e.y, c)
    end
  end
end

local function draw_tendrils(s)
  for _, t in ipairs(darkness_tendrils) do
    local tx = math.floor(t.x)
    local ty = math.floor(t.y)
    if tx >= 0 and tx < W and ty >= 0 and ty < H then
      pix(s, tx, ty, BLK)
      if t.life > t.len * 0.7 then
        if tx+1 < W then pix(s, tx+1, ty, BLK) end
        if ty+1 < H then pix(s, tx, ty+1, BLK) end
      end
    end
  end
end

local function draw_static(s)
  if static_amount < 0.05 then return end
  local num = math.floor(static_amount * 60)
  for i = 1, num do
    pix(s, math.random(0, W-1), math.random(0, H-1), math.random(0, 1))
  end
end

local function draw_vignette(s, intensity)
  local border = math.floor(intensity * 20)
  if border < 1 then return end
  for y = 0, border - 1 do
    local c = y < border/2 and BLK or DRK
    line(s, 0, y, W-1, y, c)
    line(s, 0, H-1-y, W-1, H-1-y, c)
  end
  for x = 0, border - 1 do
    local c = x < border/2 and BLK or DRK
    line(s, x, border, x, H-1-border, c)
    line(s, W-1-x, border, W-1-x, H-1-border, c)
  end
end

local function draw_hud(s)
  -- Room number
  text(s, "R" .. cur_room, 1, 1, DRK)
  -- Sonar cooldown bar
  if sonar_timer > 0 then
    local bw = math.floor((sonar_timer / SONAR_CD) * 16)
    rectf(s, 1, H-4, bw, 3, DRK)
  end
  -- Inventory count
  if #inv > 0 then
    text(s, "[B]x" .. #inv, W-28, 1, DRK)
  end
  -- Message
  if msg_timer > 0 then
    msg_timer = msg_timer - 1
    local tw = #msg_text * 4 + 4
    rectf(s, W/2 - tw/2, H - 14, tw, 9, BLK)
    text(s, msg_text, W/2, H - 13, WHT, 8)  -- ALIGN_HCENTER = 8
  end
  -- Hint (warning)
  if hint_timer > 0 then
    hint_timer = hint_timer - 1
    text(s, hint_text, W/2, 10, (tick % 4 < 2) and WHT or LIT, 8)
  end
end

----------------------------------------------------------------
-- SCENE: PLAY
----------------------------------------------------------------
local function play_update()
  update_player()
  update_sonar()
  update_reveal()
  update_entity()
  update_horror()
end

local function play_draw()
  S = screen()
  cls(S, BLK)

  -- Apply shake
  if shake_timer > 0 then
    shake_timer = shake_timer - 1
    shake_x = math.random(-2, 2)
    shake_y = math.random(-2, 2)
  else
    shake_x, shake_y = 0, 0
  end

  -- Draw revealed tiles
  for y = 0, ROWS-1 do
    for x = 0, COLS-1 do
      draw_tile(S, x, y, tile_reveal[y][x])
    end
  end

  draw_sonar_ring(S)
  draw_particles(S)
  draw_player(S)
  draw_entity(S)

  -- Horror overlays
  local d = dist(px, py, ex, ey)
  local urg = clamp(1 - d / 15, 0, 1)
  draw_vignette(S, urg)
  draw_eyes(S)
  draw_tendrils(S)
  draw_static(S)

  -- Scare flash
  if scare_flash > 0 then
    scare_flash = scare_flash - 1
    if scare_flash > 6 then cls(S, WHT)
    elseif scare_flash > 3 then cls(S, LIT) end
  end

  draw_hud(S)
end

----------------------------------------------------------------
-- SCENE: INVENTORY (from Agent 18)
----------------------------------------------------------------
local function inv_update()
  if btnp("up") then inv_sel = math.max(1, inv_sel - 1) end
  if btnp("down") then inv_sel = math.min(#inv, inv_sel + 1) end

  if btnp("a") then
    if combine_mode then
      -- Try combining
      local result = try_combine(combine_first, inv[inv_sel])
      if result then
        show_msg("Crafted: " .. result, 60)
        combine_mode = false; combine_first = nil
        if #inv == 0 then scene = "play" end
      else
        show_msg("Can't combine.", 40)
        combine_mode = false; combine_first = nil
      end
    else
      -- Select for combine
      combine_mode = true
      combine_first = inv[inv_sel]
      show_msg("Combine with?", 40)
    end
  end

  if btnp("b") then
    scene = "play"
    combine_mode = false; combine_first = nil
  end
end

local function inv_draw()
  S = screen()
  cls(S, BLK)
  text(S, "INVENTORY", W/2, 2, WHT, 8)
  line(S, 10, 10, W-10, 10, DRK)

  for i, id in ipairs(inv) do
    local it = ITEMS[id]
    local y = 14 + (i-1) * 10
    local sel = (i == inv_sel)
    if sel then rectf(S, 8, y-1, W-16, 10, DRK) end
    local prefix = sel and "> " or "  "
    if combine_mode and id == combine_first then prefix = "* " end
    text(S, prefix .. (it and it.icon or "?") .. " " .. (it and it.name or id), 10, y, sel and WHT or LIT)
  end

  -- Description at bottom
  if inv[inv_sel] and ITEMS[inv[inv_sel]] then
    local desc = ITEMS[inv[inv_sel]].desc
    text(S, desc, W/2, H-16, DRK, 8)
  end

  text(S, "[A]Combine [B]Close", W/2, H-6, DRK, 8)

  if msg_timer > 0 then
    msg_timer = msg_timer - 1
    text(S, msg_text, W/2, H-26, WHT, 8)
  end
end

----------------------------------------------------------------
-- SCENE: DOCUMENT
----------------------------------------------------------------
local function doc_update()
  if btnp("up") then doc_scroll = math.max(0, doc_scroll - 1) end
  if btnp("down") then doc_scroll = math.min(math.max(0, #doc_lines - 8), doc_scroll + 1) end
  if btnp("a") or btnp("b") then
    doc_text = nil; doc_lines = {}
    scene = "play"
  end
end

local function doc_draw()
  S = screen()
  cls(S, BLK)
  rectf(S, 6, 4, W-12, H-8, DRK)
  rect(S, 6, 4, W-12, H-8, LIT)

  text(S, "DOCUMENT", W/2, 7, WHT, 8)
  line(S, 12, 15, W-12, 15, LIT)

  local max_vis = 8
  for i = 1, max_vis do
    local idx = doc_scroll + i
    if doc_lines[idx] then
      text(S, doc_lines[idx], 12, 18 + (i-1)*10, LIT)
    end
  end

  if doc_scroll > 0 then text(S, "^", W-14, 18, WHT) end
  if doc_scroll + max_vis < #doc_lines then text(S, "v", W-14, H-18, WHT) end
  text(S, "[A/B] Close", W/2, H-8, DRK, 8)
end

----------------------------------------------------------------
-- SCENE: DEATH
----------------------------------------------------------------
local function dead_update()
  death_timer = death_timer + 1
  if death_timer > 90 and (btnp("a") or btnp("start")) then
    load_room(cur_room)
    scene = "play"
  end
end

local function dead_draw()
  S = screen()
  cls(S, BLK)

  -- Entity face (from Agent 19)
  local cx, cy = W/2, H/2
  if death_timer < 30 then
    -- Flash
    cls(S, (death_timer % 4 < 2) and WHT or BLK)
  else
    circ(S, cx, cy, 25, WHT)
    circ(S, cx-9, cy-5, 6, WHT); circ(S, cx+9, cy-5, 6, WHT)
    circ(S, cx-9, cy-5, 3, BLK); circ(S, cx+9, cy-5, 3, BLK)
    pix(S, cx-9, cy-5, WHT); pix(S, cx+9, cy-5, WHT)
    for i = -12, 12 do
      local my = cy + 10 + math.floor(math.sin(i * 0.8) * 3)
      if cx+i >= 0 and cx+i < W and my >= 0 and my < H then
        pix(S, cx+i, my, WHT)
      end
    end
    if death_timer > 60 then
      text(S, "YOU WERE FOUND", W/2, cy+25, (tick%6<3) and WHT or LIT, 8)
    end
    if death_timer > 90 then
      text(S, "[A] Retry", W/2, cy+35, DRK, 8)
    end
  end

  draw_static(S)
end

----------------------------------------------------------------
-- SCENE: WIN
----------------------------------------------------------------
local function win_update()
  victory_timer = victory_timer + 1
  if victory_timer > 120 and (btnp("a") or btnp("start")) then
    scene = "title"
  end
end

local function win_draw()
  S = screen()
  cls(S, BLK)
  local reveal = math.min(victory_timer, 60)
  if reveal > 10 then text(S, "YOU ESCAPED", W/2, 30, WHT, 8) end
  if reveal > 30 then text(S, "ABYSSAL STATION", W/2, 45, LIT, 8) end
  if reveal > 45 then
    text(S, "The surface light", W/2, 62, DRK, 8)
    text(S, "burns your eyes.", W/2, 72, DRK, 8)
    text(S, "You are free.", W/2, 82, LIT, 8)
  end
  if victory_timer > 120 then
    text(S, "[A] Title", W/2, 100, DRK, 8)
  end
end

----------------------------------------------------------------
-- SCENE: PAUSE
----------------------------------------------------------------
local function pause_update()
  if btnp("start") or btnp("b") then scene = "play" end
end

local function pause_draw()
  S = screen()
  cls(S, BLK)
  text(S, "PAUSED", W/2, 40, WHT, 8)
  text(S, "Room " .. cur_room .. "/6", W/2, 55, LIT, 8)
  text(S, "Items: " .. #inv, W/2, 65, DRK, 8)
  text(S, "[START] Resume", W/2, 85, DRK, 8)
end

----------------------------------------------------------------
-- SCENE: TITLE
----------------------------------------------------------------
local function title_update()
  title_pulse = title_pulse + 1
  idle_timer = idle_timer + 1

  if btnp("start") or btnp("a") then
    -- New game
    inv = {}; has_lantern = false
    load_room(1)
    scene = "play"
    idle_timer = 0
    show_msg("Room 1 - Find a way out", 60)
    return
  end

  if idle_timer > IDLE_MAX then
    -- Enter demo
    demo_mode = true; demo_timer = 0; demo_step = 1
    inv = {}; has_lantern = false
    load_room(1)
    scene = "demo"
    -- Pre-build demo actions
    demo_actions = {
      {act="wait", dur=30},
      {act="ping", dur=1},
      {act="move", dir="right", dur=40},
      {act="ping", dur=1},
      {act="move", dir="up", dur=25},
      {act="move", dir="right", dur=30},
      {act="ping", dur=1},
      {act="move", dir="down", dur=40},
      {act="ping", dur=1},
      {act="move", dir="left", dur=20},
      {act="ping", dur=1},
      {act="move", dir="right", dur=50},
      {act="ping", dur=1},
      {act="wait", dur=30},
    }
  end
end

local function title_draw()
  S = screen()
  cls(S, BLK)

  -- Atmospheric flicker
  if math.random() < 0.03 then cls(S, DRK) end

  -- Title
  local flick = math.random(100)
  local tc = WHT
  if flick < 5 then tc = DRK elseif flick < 10 then tc = LIT end

  text(S, "ABYSSAL", W/2, 25, tc, 8)
  text(S, "STATION", W/2, 36, tc, 8)

  -- Subtitle
  if title_pulse > 30 then
    text(S, "sonar horror adventure", W/2, 52, DRK, 8)
  end

  -- Blink prompt
  if (title_pulse % 40) < 25 then
    text(S, "[A/START] Begin", W/2, 80, LIT, 8)
  end

  -- Sonar ring animation on title
  if title_pulse % 60 < 30 then
    local r = (title_pulse % 60) * 2
    circ(S, W/2, 30, r, DRK)
  end

  -- Credits
  text(S, "Agents 13+19+18", W/2, H-8, DRK, 8)
end

----------------------------------------------------------------
-- SCENE: DEMO
----------------------------------------------------------------
local function demo_update()
  -- Exit demo on any press
  if btnp("a") or btnp("b") or btnp("start") then
    scene = "title"; idle_timer = 0; demo_mode = false
    return
  end

  demo_timer = demo_timer + 1
  if demo_timer > DEMO_LEN then
    scene = "title"; idle_timer = 0; demo_mode = false
    return
  end

  -- Execute demo actions
  if demo_step <= #demo_actions then
    local act = demo_actions[demo_step]
    act.dur = act.dur - 1

    if act.act == "ping" then
      do_ping()
      demo_step = demo_step + 1
    elseif act.act == "move" then
      move_timer = math.max(0, move_timer - 1)
      if move_timer == 0 then
        move_timer = MOVE_DELAY
        local dx, dy = 0, 0
        if act.dir == "right" then dx = 1
        elseif act.dir == "left" then dx = -1
        elseif act.dir == "up" then dy = -1
        elseif act.dir == "down" then dy = 1 end
        local nx, ny = px + dx, py + dy
        if walkable(nx, ny) then px, py = nx, ny; sfx_step() end
      end
      if act.dur <= 0 then demo_step = demo_step + 1 end
    elseif act.act == "wait" then
      if act.dur <= 0 then demo_step = demo_step + 1 end
    end
  end

  update_sonar(); update_reveal(); update_entity(); update_horror()
end

local function demo_draw()
  play_draw()
  -- Demo overlay
  text(S, "DEMO", 2, H-8, DRK)
  if (tick % 60) < 40 then
    text(S, "Press any button", W/2, 1, DRK, 8)
  end
end

----------------------------------------------------------------
-- MAIN LOOP
----------------------------------------------------------------
function _init()
  mode(2)
  scene = "title"
  title_pulse = 0
  idle_timer = 0
  tick = 0
end

function _update()
  tick = tick + 1

  if scene == "title" then title_update()
  elseif scene == "play" then play_update()
  elseif scene == "inv" then inv_update()
  elseif scene == "doc" then doc_update()
  elseif scene == "dead" then
    if not player_alive then dead_update() end
  elseif scene == "win" then win_update()
  elseif scene == "pause" then pause_update()
  elseif scene == "demo" then demo_update()
  end

  -- Transition to death scene
  if scene == "play" and not player_alive then
    scene = "dead"; death_timer = 0
  end
end

function _draw()
  if scene == "title" then title_draw()
  elseif scene == "play" then play_draw()
  elseif scene == "inv" then inv_draw()
  elseif scene == "doc" then doc_draw()
  elseif scene == "dead" then dead_draw()
  elseif scene == "win" then win_draw()
  elseif scene == "pause" then pause_draw()
  elseif scene == "demo" then demo_draw()
  end
end
