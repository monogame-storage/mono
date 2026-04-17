-- THE DARK ROOM: ECHOLOCATION
-- Agent 27 (Wave 3) — The Definitive Version
-- Sonar navigation + stalker entity + crafting + typewriter narrative + multiple endings
-- 160x120 | 2-bit (0-3) | mode(2) | 30fps
-- D-Pad: Turn/Move | A: Interact/Ping/Advance | B: Inventory | START: Start | SELECT: Pause

----------------------------------------------------------------
-- CONSTANTS
----------------------------------------------------------------
local W, H = 160, 120
local BLACK, DARK, LIGHT, WHITE = 0, 1, 2, 3
local TILE = 8
local MAP_W, MAP_H = 20, 15
local DIR_N, DIR_E, DIR_S, DIR_W = 1, 2, 3, 4
local DIR_NAMES = {"NORTH", "EAST", "SOUTH", "WEST"}
local IDLE_TIMEOUT = 180
local DEMO_DURATION = 600

----------------------------------------------------------------
-- SAFE AUDIO WRAPPERS
----------------------------------------------------------------
local function sfx_note(ch, n, dur)
  if note then note(ch, n, dur) end
end
local function sfx_noise(ch, dur)
  if noise then noise(ch, dur) end
end
local function sfx_wave(ch, w)
  if wave then wave(ch, w) end
end
local function sfx_tone(ch, f1, f2, dur)
  if tone then tone(ch, f1, f2, dur) end
end

----------------------------------------------------------------
-- SOUND EFFECTS
----------------------------------------------------------------
local function snd_ping()
  sfx_wave(0, "sine")
  sfx_tone(0, 1200, 400, 0.15)
end

local function snd_step()
  sfx_wave(3, "triangle")
  sfx_tone(3, 80, 60, 0.03)
end

local function snd_bump()
  sfx_noise(3, 0.04)
end

local function snd_pickup()
  sfx_note(0, "C5", 0.06)
  sfx_note(1, "E5", 0.06)
end

local function snd_craft()
  sfx_note(0, "E5", 0.08)
  sfx_note(1, "G5", 0.08)
  sfx_note(0, "C6", 0.12)
end

local function snd_door()
  sfx_note(0, "C2", 0.15)
  sfx_note(1, "E2", 0.1)
end

local function snd_locked()
  sfx_noise(0, 0.08)
  sfx_note(1, "C2", 0.08)
end

local function snd_unlock()
  sfx_note(0, "C5", 0.08)
  sfx_note(1, "E5", 0.06)
end

local function snd_read()
  sfx_note(0, "D4", 0.06)
  sfx_note(1, "F4", 0.04)
end

local function snd_entity_step(d)
  if d > 15 then return end
  local vol_t = math.max(0, math.min(1, 1 - d / 15))
  local freq = 200 - vol_t * 100
  sfx_wave(2, "square")
  sfx_tone(2, freq, freq * 0.8, 0.02 + vol_t * 0.02)
end

local function snd_entity_growl()
  sfx_wave(2, "sawtooth")
  sfx_tone(2, 45, 35, 0.12)
end

local function snd_jumpscare()
  sfx_noise(0, 0.2)
  sfx_wave(1, "sawtooth")
  sfx_tone(1, 80, 40, 0.3)
  sfx_noise(3, 0.15)
  sfx_wave(2, "square")
  sfx_tone(2, 100, 50, 0.25)
end

local function snd_heartbeat(intensity)
  sfx_wave(2, "sine")
  local base = 50 + intensity * 20
  sfx_tone(2, base, base * 0.7, 0.06)
end

local function snd_drip()
  sfx_wave(1, "sine")
  local pitch = 1200 + math.random(800)
  sfx_tone(1, pitch, pitch * 0.5, 0.02)
end

local function snd_creak()
  local creaks = {55, 62, 48, 70}
  sfx_wave(2, "sawtooth")
  local f = creaks[math.random(#creaks)]
  sfx_tone(2, f, f * 0.8, 0.1)
end

local function snd_alert()
  sfx_wave(1, "square")
  sfx_tone(1, 120, 80, 0.08)
end

local function snd_sonar_obj(otype, d)
  local max_d = 18
  local t = math.max(0, math.min(1, 1 - d / max_d))
  local dur = 0.02 + t * 0.08
  if dur < 0.02 then return end
  if otype == "item" then
    local f = 600 + t * t * 1400
    sfx_wave(1, "sine")
    sfx_tone(1, f, f * 1.2, dur)
  elseif otype == "door" then
    local f = 150 + t * t * 350
    sfx_wave(1, "triangle")
    sfx_tone(1, f, f * 1.1, dur)
  elseif otype == "exit" then
    local f = 300 + t * t * 700
    sfx_wave(1, "sine")
    sfx_tone(1, f, f * 1.5, dur)
  end
end

local function snd_victory()
  sfx_wave(0, "sine")
  sfx_tone(0, 400, 800, 0.2)
  sfx_wave(1, "sine")
  sfx_tone(1, 600, 1200, 0.2)
  sfx_wave(2, "triangle")
  sfx_tone(2, 300, 600, 0.2)
end

local function snd_title_ping()
  sfx_wave(0, "sine")
  sfx_tone(0, 800, 600, 0.1)
end

----------------------------------------------------------------
-- UTILITY
----------------------------------------------------------------
local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function dist(x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  return math.sqrt(dx * dx + dy * dy)
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function word_wrap(str, max)
  local lines = {}
  for para in str:gmatch("[^\n]+") do
    local ln = ""
    for w in para:gmatch("%S+") do
      if #ln + #w + 1 > max then
        lines[#lines + 1] = ln
        ln = w
      else
        if #ln > 0 then ln = ln .. " " end
        ln = ln .. w
      end
    end
    if #ln > 0 then lines[#lines + 1] = ln end
  end
  if #lines == 0 then lines[1] = "" end
  return lines
end

----------------------------------------------------------------
-- ITEM DATABASE
----------------------------------------------------------------
local ITEMS = {
  matches   = {name="Matches",     desc="Three matches remain.",       icon="M"},
  lens      = {name="Glass Lens",  desc="Cracked magnifying lens.",    icon="O"},
  lantern   = {name="Lantern",     desc="Makeshift light. It works!",  icon="*"},
  wire      = {name="Wire",        desc="Thin copper wire.",           icon="W"},
  nail      = {name="Rusty Nail",  desc="Bent rusty nail.",            icon="N"},
  lockpick  = {name="Lockpick",    desc="Wire + nail pick.",           icon="P"},
  tape      = {name="Tape",        desc="Roll of electrical tape.",    icon="T"},
  fuse_dead = {name="Dead Fuse",   desc="Blown 30-amp fuse.",         icon="F"},
  fuse_good = {name="Fixed Fuse",  desc="Taped fuse. Might work.",    icon="f"},
  keycard   = {name="Keycard",     desc="Dr. Wren - Level 4.",        icon="K"},
  note_l    = {name="Note(left)",  desc="Torn paper: '74..'",         icon="1"},
  note_r    = {name="Note(right)", desc="Torn paper: '..39'",         icon="2"},
  full_note = {name="Full Note",   desc="Code: 7439",                 icon="!"},
  crowbar   = {name="Crowbar",     desc="Heavy. Pries things open.",   icon="C"},
  journal1  = {name="Journal p.1", desc="Day 1: moved to sublevel.",  icon="J"},
  journal2  = {name="Journal p.2", desc="Day 15: hiding pages.",      icon="J"},
  journal3  = {name="Journal p.3", desc="Day 31: I am Subject 17.",   icon="J"},
  evidence  = {name="Evidence",    desc="Subject 17 file. Proof.",     icon="E"},
}

local RECIPES = {
  {a="matches",   b="lens",      result="lantern"},
  {a="wire",      b="nail",      result="lockpick"},
  {a="tape",      b="fuse_dead", result="fuse_good"},
  {a="note_l",    b="note_r",    result="full_note"},
}

----------------------------------------------------------------
-- FORWARD DECLARATIONS
----------------------------------------------------------------
local init_game, init_rooms, reset_entity
local S -- screen surface

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local state = "title"
local fcount = 0
local idle_timer = 0
local demo_mode = false
local demo_timer = 0
local demo_dir = 0
local demo_dir_timer = 0
local paused = false

-- Player
local px, py = 80, 60  -- pixel position
local pdir = DIR_N
local p_alive = true
local has_light = false

-- Sonar
local sonar_active = false
local sonar_radius = 0
local sonar_cooldown = 0
local sonar_particles = {}
local SONAR_SPEED = 2.5
local SONAR_MAX = 80
local SONAR_CD = 30

-- Entity
local ex, ey = 80, 60
local e_room = 3
local e_speed = 0.4
local e_active = false
local e_chase = false
local e_patrol_x, e_patrol_y = 80, 60
local e_timer = 0
local e_alert = false  -- entity alerted by sonar
local e_alert_x, e_alert_y = 0, 0

-- Scare / horror
local scare_flash = 0
local shake_timer = 0
local shake_amt = 0
local heartbeat_rate = 0
local heartbeat_timer = 0
local amb_drip_timer = 30
local amb_creak_timer = 60

-- Inventory
local inv = {}
local inv_open = false
local inv_cursor = 1
local combine_first = nil

-- Rooms
local rooms = {}
local current_room = 1
local room_transition = 0
local room_visited = {}

-- Narrative (typewriter)
local narr_lines = {}
local narr_active = false
local narr_tw_pos = 0
local narr_tw_spd = 2
local narr_done = false

-- Messages
local msg_text = ""
local msg_timer = 0

-- Particles
local particles = {}

-- Flags
local flags = {}

-- Title
local title_pulse = 0
local title_timer = 0
local title_flicker = 0

-- Ending
local ending_type = ""
local ending_timer = 0

----------------------------------------------------------------
-- INVENTORY MANAGEMENT
----------------------------------------------------------------
local function has_item(id)
  for _, v in ipairs(inv) do
    if v == id then return true end
  end
  return false
end

local function add_item(id)
  if #inv < 8 and not has_item(id) then
    inv[#inv + 1] = id
    snd_pickup()
    return true
  end
  return false
end

local function remove_item(id)
  for i, v in ipairs(inv) do
    if v == id then
      table.remove(inv, i)
      return true
    end
  end
  return false
end

local function try_combine(id_a, id_b)
  for _, r in ipairs(RECIPES) do
    if (id_a == r.a and id_b == r.b) or (id_a == r.b and id_b == r.a) then
      remove_item(id_a)
      remove_item(id_b)
      add_item(r.result)
      if r.result == "lantern" then has_light = true end
      snd_craft()
      return ITEMS[r.result].name
    end
  end
  return nil
end

local function show_msg(txt, dur)
  msg_text = txt or ""
  msg_timer = dur or 60
end

----------------------------------------------------------------
-- NARRATIVE SYSTEM (typewriter)
----------------------------------------------------------------
local function show_narrative(str)
  narr_lines = word_wrap(str, 24)
  narr_active = true
  narr_tw_pos = 0
  narr_done = false
  snd_read()
end

local function dismiss_narrative()
  narr_active = false
  narr_lines = {}
end

----------------------------------------------------------------
-- ROOM DESCRIPTIONS (shown on first entry)
----------------------------------------------------------------
local room_descriptions = {
  [1] = "Pitch black. Cold concrete. Your head throbs. The air smells of rust and something worse. Tally marks cover the walls. Hundreds of them.",
  [2] = "A corridor stretches into darkness. Emergency lights flicker red. Institutional green tile, cracked and stained. A sign: SUBLEVEL 4 - RESTRICTED.",
  [3] = "Shelves loom like the ribs of some vast creature. Books and files scatter the floor. Formaldehyde. Something moved in the corner.",
  [4] = "Rusted equipment. Stacked boxes. Syringes. Restraints. Unlabeled vials. This is where they kept the tools of forgetting.",
  [5] = "A vast chamber. Examination chair with leather restraints worn smooth. Electrodes dangle from a headpiece. You have sat here before. You feel it in your bones.",
  [6] = "The final door. A keypad glows faintly beside it. Beyond: the sound of wind. Freedom -- if you know the code.",
}

local journal_entries = {
  journal1 = {
    title = "JOURNAL - DAY 1",
    body = "They moved me to sublevel 4 after I found the files. Dr. Wren says it is for my safety. The door locked behind me. I heard him whisper. I do not believe him.",
  },
  journal2 = {
    title = "JOURNAL - DAY 15",
    body = "The others do not remember their names. Eyes hollow like dolls. I hide my journal in the walls. If they erase me, perhaps I will find these pages. Perhaps I will remember.",
  },
  journal3 = {
    title = "JOURNAL - DAY 31",
    body = "I know now. I am not a researcher. I am Subject 17. They gave me false memories. The real Dr. Wren died months ago. Whatever wears his face is not him. I must escape.",
  },
}

----------------------------------------------------------------
-- ROOM DEFINITIONS
----------------------------------------------------------------
local function make_room(id, name)
  local r = {
    id = id, name = name,
    tiles = {}, doors = {}, items = {},
    explored = false,
  }
  for y = 0, MAP_H - 1 do
    r.tiles[y] = {}
    for x = 0, MAP_W - 1 do
      r.tiles[y][x] = 1
    end
  end
  return r
end

local function carve(r, x1, y1, x2, y2)
  for y = y1, y2 do
    for x = x1, x2 do
      if r.tiles[y] then r.tiles[y][x] = 0 end
    end
  end
end

local function add_door(r, tx, ty, target, ttx, tty, locked, key_id)
  r.doors[#r.doors + 1] = {
    tx = tx, ty = ty,
    target_room = target, target_x = ttx, target_y = tty,
    locked = locked or false, key_id = key_id or nil,
  }
end

local function add_room_item(r, tx, ty, itype, iid)
  r.items[#r.items + 1] = {
    tx = tx, ty = ty, type = itype, id = iid or "", collected = false,
  }
end

init_rooms = function()
  rooms = {}

  -- Room 1: The Cell (start)
  local r1 = make_room(1, "The Cell")
  carve(r1, 2, 2, 17, 12)
  r1.tiles[5][5] = 1; r1.tiles[5][14] = 1
  r1.tiles[9][5] = 1; r1.tiles[9][14] = 1
  r1.tiles[7][10] = 1; r1.tiles[8][10] = 1
  add_door(r1, 17, 7, 2, 2, 7, false)
  add_room_item(r1, 4, 4, "craft", "matches")
  add_room_item(r1, 14, 10, "craft", "lens")
  add_room_item(r1, 10, 3, "craft", "journal1")
  rooms[1] = r1

  -- Room 2: The Corridor (hub)
  local r2 = make_room(2, "The Corridor")
  carve(r2, 1, 4, 18, 10)
  carve(r2, 8, 2, 12, 4)
  carve(r2, 6, 10, 14, 12)
  add_door(r2, 1, 7, 1, 16, 7, false)
  add_door(r2, 10, 2, 5, 10, 12, true, "keycard")  -- to Lab
  add_door(r2, 18, 7, 3, 2, 7, false)               -- to Archives
  add_door(r2, 10, 12, 4, 10, 2, false)              -- to Storage
  add_room_item(r2, 3, 6, "craft", "keycard")
  add_room_item(r2, 16, 9, "craft", "wire")
  rooms[2] = r2

  -- Room 3: The Archives
  local r3 = make_room(3, "The Archives")
  carve(r3, 1, 1, 18, 13)
  for x = 4, 16, 4 do
    for y = 3, 5 do r3.tiles[y][x] = 1 end
    for y = 8, 10 do r3.tiles[y][x] = 1 end
  end
  add_door(r3, 1, 7, 2, 17, 7, false)
  add_door(r3, 18, 7, 6, 2, 7, true, "lockpick")  -- to Exit (needs lockpick)
  add_room_item(r3, 6, 2, "craft", "journal2")
  add_room_item(r3, 14, 12, "craft", "note_l")
  add_room_item(r3, 17, 6, "craft", "crowbar")
  rooms[3] = r3

  -- Room 4: Storage
  local r4 = make_room(4, "Storage")
  carve(r4, 2, 1, 17, 13)
  r4.tiles[4][6] = 1; r4.tiles[5][6] = 1
  r4.tiles[4][12] = 1; r4.tiles[5][12] = 1
  r4.tiles[8][9] = 1; r4.tiles[9][9] = 1
  r4.tiles[8][10] = 1; r4.tiles[9][10] = 1
  add_door(r4, 10, 1, 2, 10, 11, false)
  add_room_item(r4, 15, 11, "craft", "nail")
  add_room_item(r4, 4, 3, "craft", "tape")
  add_room_item(r4, 16, 4, "craft", "fuse_dead")
  add_room_item(r4, 8, 12, "craft", "note_r")
  add_room_item(r4, 3, 8, "craft", "journal3")
  rooms[4] = r4

  -- Room 5: The Lab
  local r5 = make_room(5, "The Lab")
  carve(r5, 2, 2, 17, 12)
  r5.tiles[6][8] = 1; r5.tiles[6][9] = 1
  r5.tiles[7][8] = 1; r5.tiles[7][9] = 1
  r5.tiles[4][13] = 1; r5.tiles[5][13] = 1
  add_door(r5, 10, 12, 2, 10, 3, false)
  add_room_item(r5, 15, 3, "craft", "evidence")
  rooms[5] = r5

  -- Room 6: The Exit
  local r6 = make_room(6, "The Exit")
  carve(r6, 3, 3, 16, 11)
  r6.tiles[7][9] = 1; r6.tiles[7][10] = 1
  add_door(r6, 2, 7, 3, 17, 7, false)
  add_room_item(r6, 10, 4, "exit")
  rooms[6] = r6
end

----------------------------------------------------------------
-- COLLISION
----------------------------------------------------------------
local function solid_at(rm, px_x, px_y)
  local tx = math.floor(px_x / TILE)
  local ty = math.floor(px_y / TILE)
  if tx < 0 or tx >= MAP_W or ty < 0 or ty >= MAP_H then return true end
  local r = rooms[rm]
  if not r then return true end
  return r.tiles[ty][tx] == 1
end

local function can_move(rm, cx, cy, dx, dy, rad)
  rad = rad or 3
  local nx, ny = cx + dx, cy + dy
  if solid_at(rm, nx - rad, ny - rad) then return false end
  if solid_at(rm, nx + rad, ny - rad) then return false end
  if solid_at(rm, nx - rad, ny + rad) then return false end
  if solid_at(rm, nx + rad, ny + rad) then return false end
  return true
end

----------------------------------------------------------------
-- SONAR SYSTEM
----------------------------------------------------------------
local sonar_objects = {}

local function do_sonar_ping()
  if sonar_cooldown > 0 then return end
  sonar_active = true
  sonar_radius = 0
  sonar_cooldown = SONAR_CD
  sonar_particles = {}
  snd_ping()

  -- Find sonar targets in current room
  sonar_objects = {}
  local r = rooms[current_room]
  if not r then return end

  -- Items
  for _, item in ipairs(r.items) do
    if not item.collected then
      local ix = item.tx * TILE + 4
      local iy = item.ty * TILE + 4
      local d = dist(px, py, ix, iy)
      if d < SONAR_MAX then
        sonar_objects[#sonar_objects + 1] = {x=ix, y=iy, d=d, otype="item", pinged=false}
      end
    end
  end

  -- Doors
  for _, door in ipairs(r.doors) do
    local dx = door.tx * TILE + 4
    local dy = door.ty * TILE + 4
    local d = dist(px, py, dx, dy)
    if d < SONAR_MAX then
      sonar_objects[#sonar_objects + 1] = {x=dx, y=dy, d=d, otype="door", pinged=false}
    end
  end

  table.sort(sonar_objects, function(a, b) return a.d < b.d end)

  -- Alert the entity!
  if e_active and p_alive then
    e_alert = true
    e_alert_x = px
    e_alert_y = py
    snd_alert()
    show_msg("...IT HEARD YOU", 40)
  end
end

local function update_sonar()
  if sonar_cooldown > 0 then sonar_cooldown = sonar_cooldown - 1 end
  if not sonar_active then return end

  sonar_radius = sonar_radius + SONAR_SPEED

  -- Create ring particles
  if fcount % 2 == 0 then
    local segs = 20
    for i = 0, segs - 1 do
      local a = (i / segs) * math.pi * 2
      local rx = px + math.cos(a) * sonar_radius
      local ry = py + math.sin(a) * sonar_radius
      if rx >= 0 and rx < W and ry >= 0 and ry < H then
        local tx = math.floor(rx / TILE)
        local ty = math.floor(ry / TILE)
        local r = rooms[current_room]
        local is_wall = r and r.tiles[ty] and r.tiles[ty][tx] == 1
        sonar_particles[#sonar_particles + 1] = {
          x = rx, y = ry,
          life = is_wall and 12 or 4,
          col = is_wall and LIGHT or DARK,
        }
      end
    end
  end

  -- Ping objects as wave reaches them
  for _, obj in ipairs(sonar_objects) do
    if not obj.pinged and sonar_radius >= obj.d then
      obj.pinged = true
      snd_sonar_obj(obj.otype, obj.d)
      sonar_particles[#sonar_particles + 1] = {
        x = obj.x, y = obj.y,
        life = 20,
        col = WHITE,
      }
    end
  end

  -- Reveal entity with sonar (terrifying moment)
  if e_active and e_room == current_room then
    local ed = dist(px, py, ex, ey)
    if sonar_radius >= ed and sonar_radius < ed + SONAR_SPEED * 2 then
      sonar_particles[#sonar_particles + 1] = {
        x = ex, y = ey, life = 18, col = WHITE,
      }
      sfx_wave(1, "sawtooth")
      sfx_tone(1, 150, 60, 0.1)
    end
  end

  if sonar_radius > SONAR_MAX then
    sonar_active = false
  end

  -- Update particles
  local alive = {}
  for _, p in ipairs(sonar_particles) do
    p.life = p.life - 1
    if p.life > 0 then alive[#alive + 1] = p end
  end
  sonar_particles = alive
end

----------------------------------------------------------------
-- ENTITY AI
----------------------------------------------------------------
reset_entity = function()
  e_room = 3
  ex = 10 * TILE + 4
  ey = 7 * TILE + 4
  e_active = true
  e_chase = false
  e_timer = 0
  e_speed = 0.4
  e_patrol_x = ex
  e_patrol_y = ey
  e_alert = false
end

local function entity_ai()
  if not e_active or not p_alive then return end

  local same_room = (e_room == current_room)

  if same_room then
    e_chase = true
    e_speed = lerp(e_speed, 0.7, 0.01)

    local dx = px - ex
    local dy = py - ey
    local d = dist(px, py, ex, ey)

    -- If alerted by sonar, rush toward ping origin
    if e_alert then
      dx = e_alert_x - ex
      dy = e_alert_y - ey
      local ad = dist(ex, ey, e_alert_x, e_alert_y)
      if ad < 10 then
        e_alert = false  -- reached ping origin, now hunt normally
      end
      d = ad
    end

    if d > 2 then
      local mx = (dx / d) * e_speed
      local my = (dy / d) * e_speed
      if can_move(e_room, ex, ey, mx, 0, 3) then ex = ex + mx end
      if can_move(e_room, ex, ey, 0, my, 3) then ey = ey + my end
    end

    -- Check catch
    local pd = dist(px, py, ex, ey)
    if pd < 8 then
      snd_jumpscare()
      scare_flash = 12
      shake_timer = 15
      shake_amt = 4
      p_alive = false
      return
    end

    -- Random scare when close
    if pd < 30 and math.random(100) < 3 then
      scare_flash = 4
      shake_timer = 6
      shake_amt = 2
      sfx_noise(0, 0.1)
    end
  else
    -- Not in same room: patrol and occasionally enter player's room
    e_chase = false
    e_speed = 0.4
    e_timer = e_timer + 1

    -- If alerted by sonar, navigate toward player's room
    if e_alert then
      local r = rooms[e_room]
      if r then
        -- Try to find door to player's room
        for _, door in ipairs(r.doors) do
          if door.target_room == current_room then
            e_patrol_x = door.tx * TILE + 4
            e_patrol_y = door.ty * TILE + 4
            local dd = dist(ex, ey, e_patrol_x, e_patrol_y)
            if dd < 8 then
              e_room = door.target_room
              ex = door.target_x * TILE + 4
              ey = door.target_y * TILE + 4
              sfx_note(2, "G2", 0.1)
              show_msg("...it enters...", 60)
              return
            end
            break
          end
        end
      end
    end

    if e_timer % 60 == 0 then
      local r = rooms[e_room]
      if r and #r.doors > 0 then
        local door = r.doors[math.random(#r.doors)]
        e_patrol_x = door.tx * TILE + 4
        e_patrol_y = door.ty * TILE + 4

        if math.random(100) < 30 then
          if door.target_room == current_room or math.random(100) < 20 then
            e_room = door.target_room
            ex = door.target_x * TILE + 4
            ey = door.target_y * TILE + 4
            if door.target_room == current_room then
              sfx_note(2, "G2", 0.1)
              show_msg("...a door creaks...", 60)
            end
          end
        end
      end
    end

    local dx = e_patrol_x - ex
    local dy = e_patrol_y - ey
    local d = math.sqrt(dx * dx + dy * dy)
    if d > 2 then
      local mx = (dx / d) * e_speed
      local my = (dy / d) * e_speed
      if can_move(e_room, ex, ey, mx, 0, 3) then ex = ex + mx end
      if can_move(e_room, ex, ey, 0, my, 3) then ey = ey + my end
    end
  end
end

----------------------------------------------------------------
-- SCARE / AMBIENT
----------------------------------------------------------------
local function trigger_scare(intensity)
  scare_flash = 4 + intensity * 2
  shake_timer = 8 + intensity * 4
  shake_amt = 2 + intensity * 2
  sfx_noise(0, 0.15 + intensity * 0.1)
  sfx_note(1, "C2", 0.2 + intensity * 0.1)
  sfx_note(2, "F#2", 0.15)
end

local function update_ambient()
  amb_drip_timer = amb_drip_timer - 1
  if amb_drip_timer <= 0 then
    amb_drip_timer = 40 + math.random(80)
    snd_drip()
  end

  amb_creak_timer = amb_creak_timer - 1
  if amb_creak_timer <= 0 then
    amb_creak_timer = 90 + math.random(120)
    snd_creak()
  end

  -- Heartbeat based on entity distance
  if e_active and e_room == current_room and p_alive then
    local d = dist(px, py, ex, ey)
    local target = clamp(1 - (d / 100), 0, 1)
    heartbeat_rate = lerp(heartbeat_rate, target, 0.05)
  else
    heartbeat_rate = math.max(heartbeat_rate - 0.01, 0)
  end

  if heartbeat_rate > 0.08 then
    heartbeat_timer = heartbeat_timer + 1
    local interval = math.floor(lerp(30, 6, heartbeat_rate))
    if heartbeat_timer >= interval then
      heartbeat_timer = 0
      snd_heartbeat(heartbeat_rate)
    end
  else
    heartbeat_timer = 0
  end

  -- Entity footsteps (audible through doors too)
  if e_active then
    local audible = (e_room == current_room)
    if not audible then
      local r = rooms[current_room]
      if r then
        for _, door in ipairs(r.doors) do
          if door.target_room == e_room then audible = true; break end
        end
      end
    end
    if audible then
      e_timer = e_timer + 1
      local step_interval = e_chase and 7 or 14
      if e_timer % step_interval == 0 then
        local d = dist(px, py, ex, ey)
        snd_entity_step(d / TILE)
        if e_chase and d < 40 and fcount % 40 == 0 then
          snd_entity_growl()
        end
      end
    end
  end
end

----------------------------------------------------------------
-- INTERACTION
----------------------------------------------------------------
local function check_interact()
  local r = rooms[current_room]
  if not r then return end

  -- Check doors
  for _, door in ipairs(r.doors) do
    local dx = door.tx * TILE + 4 - px
    local dy = door.ty * TILE + 4 - py
    if math.abs(dx) < 12 and math.abs(dy) < 12 then
      if door.locked then
        if door.key_id and has_item(door.key_id) then
          remove_item(door.key_id)
          door.locked = false
          snd_unlock()
          show_msg("Unlocked!", 45)
        elseif has_item("lockpick") then
          remove_item("lockpick")
          door.locked = false
          snd_unlock()
          show_msg("Picked the lock!", 45)
        else
          snd_locked()
          local need = door.key_id or "?"
          show_msg("Locked. Need: " .. (ITEMS[need] and ITEMS[need].name or need), 60)
        end
      else
        -- Transition
        current_room = door.target_room
        px = door.target_x * TILE + 4
        py = door.target_y * TILE + 4
        rooms[current_room].explored = true
        room_transition = 15
        show_msg(rooms[current_room].name, 45)
        snd_door()
        scare_flash = 0
        sonar_active = false
        sonar_particles = {}

        -- Show narrative on first visit
        if not room_visited[current_room] then
          room_visited[current_room] = true
          local desc = room_descriptions[current_room]
          if desc then show_narrative(desc) end
        end
        return
      end
    end
  end

  -- Check items
  for _, item in ipairs(r.items) do
    if not item.collected then
      local dx = item.tx * TILE + 4 - px
      local dy = item.ty * TILE + 4 - py
      if math.abs(dx) < 12 and math.abs(dy) < 12 then
        if item.type == "exit" then
          -- Check for ending conditions
          if has_item("full_note") or flags.code_known then
            -- Determine ending quality
            local journals = 0
            if has_item("journal1") then journals = journals + 1 end
            if has_item("journal2") then journals = journals + 1 end
            if has_item("journal3") then journals = journals + 1 end
            local has_ev = has_item("evidence")

            if journals >= 3 and has_ev then
              ending_type = "true"  -- best ending
            elseif has_ev then
              ending_type = "good"
            else
              ending_type = "escape"
            end
            state = "ending"
            ending_timer = 0
            snd_victory()
          else
            show_msg("A keypad. Need the code.", 60)
            snd_locked()
          end
          return
        elseif item.type == "craft" then
          item.collected = true
          if add_item(item.id) then
            show_msg("Got: " .. ITEMS[item.id].name, 60)
            -- Show journal narratives
            local entry = journal_entries[item.id]
            if entry then
              show_narrative(entry.title .. "\n" .. entry.body)
            end
            -- Crafting lantern gives light
            if item.id == "lantern" then has_light = true end
            -- Getting full_note sets flag
            if item.id == "full_note" then flags.code_known = true end
          else
            show_msg("Inventory full!", 45)
            item.collected = false
          end
        end
      end
    end
  end
end

----------------------------------------------------------------
-- PARTICLES
----------------------------------------------------------------
local function add_particle(x, y, c)
  if #particles > 40 then return end
  particles[#particles + 1] = {
    x = x, y = y,
    vx = (math.random() - 0.5) * 1.5,
    vy = (math.random() - 0.5) * 1.5,
    life = 10 + math.random(15),
    c = c or DARK,
  }
end

local function update_particles()
  local i = 1
  while i <= #particles do
    local p = particles[i]
    p.x = p.x + p.vx
    p.y = p.y + p.vy
    p.life = p.life - 1
    if p.life <= 0 then
      particles[i] = particles[#particles]
      particles[#particles] = nil
    else
      i = i + 1
    end
  end
end

----------------------------------------------------------------
-- DRAWING HELPERS
----------------------------------------------------------------
local function dither_rect(rx, ry, rw, rh, c1, c2, pat)
  for dy = 0, rh - 1 do
    for dx = 0, rw - 1 do
      local x, y = rx + dx, ry + dy
      if x >= 0 and x < W and y >= 0 and y < H then
        if pat <= 0 then
          pix(S, x, y, c1)
        elseif pat >= 4 then
          pix(S, x, y, c2)
        elseif pat == 2 then
          pix(S, x, y, (x + y) % 2 == 0 and c2 or c1)
        elseif pat == 1 then
          pix(S, x, y, (x % 2 + y % 2 * 2) == 0 and c2 or c1)
        else
          pix(S, x, y, (x % 2 + y % 2 * 2) == 0 and c1 or c2)
        end
      end
    end
  end
end

local function draw_vignette()
  -- Darkness vignette at edges (heavier without light)
  local depth = has_light and 12 or 20
  for i = 0, depth - 1 do
    local a = i / depth
    if (math.floor(a * 4) + fcount) % 2 == 0 or a < 0.5 then
      -- Top
      for x = 0, W - 1 do
        if math.random() < (1 - a) * 0.5 then
          pix(S, x, i, BLACK)
        end
      end
      -- Bottom
      for x = 0, W - 1 do
        if math.random() < (1 - a) * 0.5 then
          pix(S, x, H - 1 - i, BLACK)
        end
      end
    end
    -- Left/Right
    for y = 0, H - 1 do
      if math.random() < (1 - a) * 0.3 then
        pix(S, i, y, BLACK)
      end
      if math.random() < (1 - a) * 0.3 then
        pix(S, W - 1 - i, y, BLACK)
      end
    end
  end
end

local function draw_horror_overlay()
  -- Scare flash
  if scare_flash > 0 then
    scare_flash = scare_flash - 1
    if scare_flash > 6 then
      cls(S, WHITE)
      return
    end
  end

  -- Static based on heartbeat
  if heartbeat_rate > 0.3 then
    local count = math.floor(heartbeat_rate * 80)
    for _ = 1, count do
      local sx = math.random(0, W - 1)
      local sy = math.random(0, H - 1)
      pix(S, sx, sy, math.random(0, 1))
    end
  end

  -- Entity eyes in darkness (when nearby but unseen)
  if e_active and e_room == current_room and p_alive then
    local d = dist(px, py, ex, ey)
    if d < 60 and d > 20 then
      local blink = math.floor(fcount / 30) % 5
      if blink < 3 then
        -- Eyes position relative to player
        local angle = math.atan2(ey - py, ex - px)
        local draw_d = math.min(d, 50)
        local eye_x = W / 2 + math.cos(angle) * (draw_d * 0.8)
        local eye_y = H / 2 + math.sin(angle) * (draw_d * 0.5)
        local ex1 = math.floor(eye_x - 2)
        local ex2 = math.floor(eye_x + 2)
        local ey1 = math.floor(eye_y)
        if ex1 >= 0 and ex2 < W and ey1 >= 0 and ey1 < H then
          pix(S, ex1, ey1, LIGHT)
          pix(S, ex2, ey1, LIGHT)
        end
      end
    end
  end
end

----------------------------------------------------------------
-- DRAW: TOP-DOWN MAP (sonar reveal)
----------------------------------------------------------------
local function draw_map()
  local r = rooms[current_room]
  if not r then return end

  -- In pure darkness, only sonar particles visible
  -- With lantern, dim map visible
  if has_light then
    -- Draw dim map
    for ty = 0, MAP_H - 1 do
      for tx = 0, MAP_W - 1 do
        local sx = tx * TILE
        local sy = ty * TILE
        if r.tiles[ty][tx] == 1 then
          -- Wall: dither pattern
          if (tx + ty) % 2 == 0 then
            rectf(S, sx, sy, TILE, TILE, DARK)
          else
            rectf(S, sx, sy, TILE, TILE, BLACK)
            pix(S, sx + 2, sy + 2, DARK)
            pix(S, sx + 5, sy + 5, DARK)
          end
        end
        -- Items
        for _, item in ipairs(r.items) do
          if not item.collected and item.tx == tx and item.ty == ty then
            local ix = sx + 3
            local iy = sy + 2
            if ITEMS[item.id] then
              text(S, ITEMS[item.id].icon, ix, iy, LIGHT)
            elseif item.type == "exit" then
              text(S, "X", ix, iy, WHITE)
            end
          end
        end
      end
    end

    -- Doors
    for _, door in ipairs(r.doors) do
      local dx = door.tx * TILE + 2
      local dy = door.ty * TILE + 2
      local c = door.locked and LIGHT or WHITE
      rectf(S, dx, dy, 4, 4, c)
      if door.locked then
        pix(S, dx + 1, dy + 1, WHITE)
      end
    end
  end

  -- Sonar particles (always visible)
  for _, p in ipairs(sonar_particles) do
    local sx = math.floor(p.x)
    local sy = math.floor(p.y)
    if sx >= 0 and sx < W and sy >= 0 and sy < H then
      local c = p.col
      if p.life < 4 then c = math.max(c - 1, 0) end
      if c > 0 then pix(S, sx, sy, c) end
    end
  end

  -- Player
  local pc = WHITE
  if fcount % 20 < 3 then pc = LIGHT end  -- subtle blink
  pix(S, math.floor(px), math.floor(py), pc)
  -- Direction indicator
  local ddx = ({0, 1, 0, -1})[pdir]
  local ddy = ({-1, 0, 1, 0})[pdir]
  local fx = math.floor(px + ddx * 2)
  local fy = math.floor(py + ddy * 2)
  if fx >= 0 and fx < W and fy >= 0 and fy < H then
    pix(S, fx, fy, LIGHT)
  end

  -- Entity (visible only if in same room and revealed by sonar or very close)
  if e_active and e_room == current_room then
    local d = dist(px, py, ex, ey)
    local show_entity = false
    -- Always show if very close
    if d < 15 then show_entity = true end
    -- Show briefly after sonar reveals it
    for _, p in ipairs(sonar_particles) do
      if dist(p.x, p.y, ex, ey) < 6 and p.col == WHITE then
        show_entity = true
        break
      end
    end
    if show_entity then
      local esx = math.floor(ex)
      local esy = math.floor(ey)
      if esx >= 0 and esx < W and esy >= 0 and esy < H then
        local ec = (fcount % 4 < 2) and WHITE or LIGHT
        pix(S, esx, esy, ec)
        pix(S, esx - 1, esy, DARK)
        pix(S, esx + 1, esy, DARK)
      end
    end
  end

  -- Dust particles
  for _, p in ipairs(particles) do
    local sx = math.floor(p.x)
    local sy = math.floor(p.y)
    if sx >= 0 and sx < W and sy >= 0 and sy < H then
      pix(S, sx, sy, p.c)
    end
  end
end

----------------------------------------------------------------
-- DRAW: HUD
----------------------------------------------------------------
local function draw_hud()
  -- Room name
  local r = rooms[current_room]
  if r then
    text(S, r.name, 2, 2, DARK)
  end

  -- Direction
  text(S, DIR_NAMES[pdir], W - 2, 2, DARK, ALIGN_RIGHT)

  -- Sonar cooldown indicator
  if sonar_cooldown > 0 then
    local bar_w = math.floor((sonar_cooldown / SONAR_CD) * 20)
    rectf(S, W / 2 - 10, H - 4, bar_w, 2, DARK)
  else
    if fcount % 60 < 40 then
      text(S, "[A]:PING", W / 2, H - 8, DARK, ALIGN_HCENTER)
    end
  end

  -- Heartbeat visual
  if heartbeat_rate > 0.2 then
    local hb_x = W - 12
    local hb_y = H - 12
    local pulse = math.sin(fcount * heartbeat_rate * 0.3)
    local r_size = math.floor(2 + pulse * heartbeat_rate * 3)
    if r_size > 0 then
      circ(S, hb_x, hb_y, r_size, heartbeat_rate > 0.6 and WHITE or LIGHT)
    end
  end

  -- Inventory quick view
  if #inv > 0 then
    local iy = H - 18
    text(S, "INV:", 2, iy, DARK)
    for i, id in ipairs(inv) do
      local item = ITEMS[id]
      if item then
        text(S, item.icon, 20 + (i - 1) * 8, iy, LIGHT)
      end
    end
  end

  -- Message
  if msg_timer > 0 then
    msg_timer = msg_timer - 1
    local mc = msg_timer > 15 and LIGHT or DARK
    text(S, msg_text, W / 2, H - 28, mc, ALIGN_HCENTER)
  end
end

----------------------------------------------------------------
-- DRAW: NARRATIVE OVERLAY (typewriter)
----------------------------------------------------------------
local function draw_narrative()
  if not narr_active then return end

  -- Dark overlay
  dither_rect(8, 8, W - 16, H - 16, BLACK, DARK, 1)
  rect(S, 8, 8, W - 16, H - 16, LIGHT)

  -- Typewriter text
  narr_tw_pos = narr_tw_pos + narr_tw_spd
  local total_chars = 0
  for _, ln in ipairs(narr_lines) do total_chars = total_chars + #ln end

  if narr_tw_pos >= total_chars then
    narr_done = true
    narr_tw_pos = total_chars
  end

  -- Click sound for typewriter
  if not narr_done and fcount % 3 == 0 then
    sfx_note(3, "A5", 0.01)
  end

  local chars_drawn = 0
  local ly = 14
  for _, ln in ipairs(narr_lines) do
    local show = ""
    for c = 1, #ln do
      chars_drawn = chars_drawn + 1
      if chars_drawn <= narr_tw_pos then
        show = show .. ln:sub(c, c)
      end
    end
    if #show > 0 then
      text(S, show, 14, ly, WHITE)
    end
    ly = ly + 10
    if ly > H - 20 then break end
  end

  -- Prompt
  if narr_done then
    if fcount % 40 < 25 then
      text(S, "[A] continue", W / 2, H - 16, LIGHT, ALIGN_HCENTER)
    end
  end
end

----------------------------------------------------------------
-- DRAW: INVENTORY SCREEN
----------------------------------------------------------------
local function draw_inventory()
  cls(S, BLACK)
  text(S, "INVENTORY", W / 2, 4, WHITE, ALIGN_HCENTER)
  line(S, 10, 12, W - 10, 12, DARK)

  if #inv == 0 then
    text(S, "Empty...", W / 2, 50, DARK, ALIGN_HCENTER)
  else
    for i, id in ipairs(inv) do
      local item = ITEMS[id]
      if not item then goto continue end
      local iy = 16 + (i - 1) * 12
      local sel = (i == inv_cursor)
      local c = sel and WHITE or LIGHT

      -- Selection indicator
      if sel then
        rectf(S, 6, iy - 1, W - 12, 11, DARK)
        text(S, ">", 8, iy, WHITE)
      end

      -- Combine highlight
      if combine_first == i then
        text(S, "+", 8, iy, WHITE)
      end

      text(S, item.icon .. " " .. item.name, 16, iy, c)
      ::continue::
    end
  end

  -- Instructions
  local iy = H - 20
  line(S, 10, iy - 4, W - 10, iy - 4, DARK)
  if combine_first then
    text(S, "A:Combine  B:Cancel", W / 2, iy, LIGHT, ALIGN_HCENTER)
  else
    text(S, "A:Select  B:Close", W / 2, iy, LIGHT, ALIGN_HCENTER)
  end
  text(S, "Select 2 items to craft", W / 2, iy + 10, DARK, ALIGN_HCENTER)
end

----------------------------------------------------------------
-- GAME INIT
----------------------------------------------------------------
init_game = function()
  init_rooms()
  px = 10 * TILE + 4
  py = 7 * TILE + 4
  pdir = DIR_N
  p_alive = true
  has_light = false
  current_room = 1
  rooms[1].explored = true

  inv = {}
  inv_cursor = 1
  combine_first = nil
  inv_open = false

  sonar_active = false
  sonar_radius = 0
  sonar_cooldown = 0
  sonar_particles = {}
  sonar_objects = {}

  particles = {}
  scare_flash = 0
  shake_timer = 0
  shake_amt = 0
  heartbeat_rate = 0
  heartbeat_timer = 0
  msg_text = ""
  msg_timer = 0
  fcount = 0

  room_visited = {}
  room_visited[1] = true
  narr_active = false
  narr_lines = {}

  flags = {}
  ending_type = ""
  ending_timer = 0

  reset_entity()

  -- Show opening narrative
  show_narrative(room_descriptions[1])
end

----------------------------------------------------------------
-- TITLE STATE
----------------------------------------------------------------
local function update_title()
  title_pulse = title_pulse + 1
  title_timer = title_timer + 1

  if title_pulse % 60 == 0 then
    snd_title_ping()
  end

  -- Flicker
  if title_flicker > 0 then
    title_flicker = title_flicker - 1
  elseif math.random(200) < 3 then
    title_flicker = 5
  end

  -- Demo mode after idle
  idle_timer = idle_timer + 1
  if idle_timer > IDLE_TIMEOUT and not demo_mode then
    demo_mode = true
    init_game()
    demo_timer = 0
    state = "demo"
    return
  end

  if btnp("start") or btnp("a") then
    state = "game"
    init_game()
    idle_timer = 0
    demo_mode = false
  end
end

local function draw_title()
  cls(S, BLACK)

  -- Flickering title
  local tc = WHITE
  local flick = math.random(100)
  if flick < 6 then tc = DARK
  elseif flick < 12 then tc = LIGHT end
  if title_flicker > 0 and title_flicker > 3 then tc = BLACK end

  if tc > BLACK then
    text(S, "THE DARK ROOM", W / 2, 16, tc, ALIGN_HCENTER)
  end

  -- Subtitle: ECHOLOCATION
  if title_timer > 30 then
    text(S, "ECHOLOCATION", W / 2, 28, DARK, ALIGN_HCENTER)
  end

  -- Creepy taglines
  if title_timer > 50 then
    text(S, "you are blind.", W / 2, 44, DARK, ALIGN_HCENTER)
  end
  if title_timer > 80 then
    text(S, "something breathes nearby.", W / 2, 54, DARK, ALIGN_HCENTER)
  end
  if title_timer > 110 then
    text(S, "every ping reveals.", W / 2, 64, DARK, ALIGN_HCENTER)
  end
  if title_timer > 140 then
    text(S, "every ping betrays.", W / 2, 74, LIGHT, ALIGN_HCENTER)
  end

  -- Sonar ring animation
  local ring_r = (title_pulse % 60) * 1.5
  if ring_r < 80 then
    local cx, cy = W / 2, 92
    local segs = 24
    for i = 0, segs - 1 do
      local a = (i / segs) * math.pi * 2
      local rx = cx + math.cos(a) * ring_r
      local ry = cy + math.sin(a) * ring_r * 0.4
      local sx = math.floor(rx)
      local sy = math.floor(ry)
      if sx >= 0 and sx < W and sy >= 0 and sy < H then
        pix(S, sx, sy, ring_r < 40 and DARK or BLACK)
      end
    end
    pix(S, cx, 92, WHITE)
  end

  -- Entity eyes
  if title_timer > 100 then
    local blink = math.floor(title_pulse / 20) % 5
    if blink < 2 then
      local eye_x = W / 2 + math.sin(title_pulse * 0.02) * 30
      local eye_y = 92 + math.cos(title_pulse * 0.015) * 6
      pix(S, math.floor(eye_x) - 1, math.floor(eye_y), LIGHT)
      pix(S, math.floor(eye_x) + 1, math.floor(eye_y), LIGHT)
    end
  end

  -- Blink prompt
  if title_pulse % 40 < 25 then
    text(S, "PRESS START", W / 2, 108, LIGHT, ALIGN_HCENTER)
  end
end

----------------------------------------------------------------
-- DEMO STATE
----------------------------------------------------------------
local function update_demo()
  demo_timer = demo_timer + 1
  fcount = fcount + 1

  -- Auto-explore
  demo_dir_timer = demo_dir_timer + 1
  if demo_dir_timer > 15 then
    demo_dir_timer = 0
    demo_dir = math.random(1, 4)

    -- Occasionally ping
    if math.random(5) == 1 then
      do_sonar_ping()
    end
  end

  -- Move in demo direction
  local ddx = ({0, 1, 0, -1})[demo_dir] or 0
  local ddy = ({-1, 0, 1, 0})[demo_dir] or 0
  if can_move(current_room, px, py, ddx * 1.2, 0, 3) then px = px + ddx * 1.2 end
  if can_move(current_room, px, py, 0, ddy * 1.2, 3) then py = py + ddy * 1.2 end

  update_sonar()
  update_ambient()
  update_particles()
  entity_ai()

  -- Add dust
  if fcount % 10 == 0 then
    add_particle(math.random(0, W - 1), math.random(0, H - 1), DARK)
  end

  -- End demo
  if demo_timer > DEMO_DURATION or btnp("start") or btnp("a") then
    state = "title"
    demo_mode = false
    idle_timer = 0
    title_pulse = 0
    title_timer = 0
  end
end

local function draw_demo()
  cls(S, BLACK)
  draw_map()
  draw_vignette()
  draw_horror_overlay()
  text(S, "- DEMO -", W / 2, 2, DARK, ALIGN_HCENTER)
  text(S, "PRESS START", W / 2, H - 8, DARK, ALIGN_HCENTER)
end

----------------------------------------------------------------
-- GAME STATE: UPDATE
----------------------------------------------------------------
local function update_game()
  -- Handle narrative overlay
  if narr_active then
    if btnp("a") then
      if narr_done then
        dismiss_narrative()
      else
        narr_tw_pos = 9999  -- skip to end
      end
    end
    return
  end

  -- Handle inventory
  if inv_open then
    idle_timer = 0
    if btnp("up") then
      inv_cursor = math.max(1, inv_cursor - 1)
      sfx_note(0, "A4", 0.02)
    end
    if btnp("down") then
      inv_cursor = math.min(#inv, inv_cursor + 1)
      sfx_note(0, "A4", 0.02)
    end
    if btnp("a") then
      if #inv > 0 then
        if combine_first == nil then
          combine_first = inv_cursor
          sfx_note(0, "E4", 0.03)
        else
          if combine_first ~= inv_cursor then
            local id_a = inv[combine_first]
            local id_b = inv[inv_cursor]
            local result = try_combine(id_a, id_b)
            if result then
              show_msg("Crafted: " .. result, 60)
            else
              show_msg("Can't combine those.", 45)
              sfx_noise(0, 0.04)
            end
          end
          combine_first = nil
          inv_cursor = math.min(inv_cursor, #inv)
        end
      end
    end
    if btnp("b") then
      inv_open = false
      combine_first = nil
    end
    return
  end

  -- Pause
  if paused then
    if btnp("select") or btnp("start") then paused = false end
    return
  end

  if btnp("select") then
    paused = true
    return
  end

  idle_timer = idle_timer + 1
  fcount = fcount + 1

  -- Death state
  if not p_alive then
    if scare_flash > 0 then scare_flash = scare_flash - 1 end
    if shake_timer > 0 then shake_timer = shake_timer - 1 end
    ending_timer = ending_timer + 1
    if ending_timer > 60 and (btnp("start") or btnp("a")) then
      -- Respawn in same room
      local r = rooms[current_room]
      if r and #r.doors > 0 then
        local door = r.doors[1]
        px = door.target_x * TILE + 4
        py = door.target_y * TILE + 4
        current_room = door.target_room
      else
        px = 10 * TILE + 4
        py = 7 * TILE + 4
        current_room = 1
      end
      p_alive = true
      scare_flash = 0
      shake_timer = 0
      heartbeat_rate = 0
      ending_timer = 0
      reset_entity()
      show_msg("You wake again... still trapped.", 90)
    end
    return
  end

  -- Open inventory
  if btnp("b") then
    inv_open = true
    inv_cursor = math.min(inv_cursor, math.max(1, #inv))
    combine_first = nil
    return
  end

  -- Sonar ping
  if btnp("a") then
    -- First try interact, then sonar
    check_interact()
    if state ~= "game" then return end  -- state might change
    if sonar_cooldown <= 0 then
      do_sonar_ping()
    end
    idle_timer = 0
  end

  -- Movement
  local spd = 1.2
  local moved = false
  if btn("up") then
    local ddx = ({0, 1, 0, -1})[pdir]
    local ddy = ({-1, 0, 1, 0})[pdir]
    if can_move(current_room, px, py, ddx * spd, ddy * spd, 3) then
      px = px + ddx * spd
      py = py + ddy * spd
      moved = true
    else
      snd_bump()
    end
    idle_timer = 0
  end
  if btn("down") then
    local ddx = ({0, -1, 0, 1})[pdir]
    local ddy = ({1, 0, -1, 0})[pdir]
    if can_move(current_room, px, py, ddx * spd * 0.7, ddy * spd * 0.7, 3) then
      px = px + ddx * spd * 0.7
      py = py + ddy * spd * 0.7
      moved = true
    else
      snd_bump()
    end
    idle_timer = 0
  end
  if btnp("left") then
    pdir = pdir - 1
    if pdir < 1 then pdir = 4 end
    sfx_note(0, "C2", 0.03)
    idle_timer = 0
  end
  if btnp("right") then
    pdir = pdir + 1
    if pdir > 4 then pdir = 1 end
    sfx_note(0, "C2", 0.03)
    idle_timer = 0
  end

  -- Footstep sound
  if moved and fcount % 8 == 0 then
    snd_step()
  end

  -- Room transition fade
  if room_transition > 0 then
    room_transition = room_transition - 1
  end

  -- Update systems
  update_sonar()
  update_ambient()
  update_particles()
  entity_ai()

  -- Shake decay
  if shake_timer > 0 then shake_timer = shake_timer - 1 end

  -- Dust particles
  if fcount % 12 == 0 then
    add_particle(math.random(0, W - 1), math.random(0, H - 1), DARK)
  end

  -- Auto demo if idle too long
  if idle_timer > IDLE_TIMEOUT * 3 then
    state = "title"
    idle_timer = 0
    title_pulse = 0
    title_timer = 0
  end
end

----------------------------------------------------------------
-- GAME STATE: DRAW
----------------------------------------------------------------
local function draw_game()
  cls(S, BLACK)

  -- Shake offset
  local sx, sy = 0, 0
  if shake_timer > 0 then
    sx = math.random(-shake_amt, shake_amt)
    sy = math.random(-shake_amt, shake_amt)
  end

  -- Room transition flash
  if room_transition > 10 then
    cls(S, BLACK)
    return
  end

  -- Offset for shake (simplified: redraw at offset)
  -- We just draw normally and apply shake to vignette

  draw_map()
  draw_vignette()
  draw_horror_overlay()
  draw_hud()
  draw_narrative()

  -- Death overlay
  if not p_alive then
    dither_rect(0, 0, W, H, BLACK, DARK, 1)
    if ending_timer > 20 then
      text(S, "IT FOUND YOU", W / 2, H / 2 - 10, WHITE, ALIGN_HCENTER)
    end
    if ending_timer > 50 then
      text(S, "darkness consumes...", W / 2, H / 2 + 4, DARK, ALIGN_HCENTER)
    end
    if ending_timer > 60 then
      if fcount % 40 < 25 then
        text(S, "[A] try again", W / 2, H / 2 + 20, LIGHT, ALIGN_HCENTER)
      end
    end
  end

  -- Inventory screen (drawn over everything)
  if inv_open then
    draw_inventory()
  end

  -- Pause overlay
  if paused then
    dither_rect(20, 40, W - 40, 40, BLACK, DARK, 2)
    rect(S, 20, 40, W - 40, 40, LIGHT)
    text(S, "PAUSED", W / 2, 50, WHITE, ALIGN_HCENTER)
    text(S, "SELECT to resume", W / 2, 64, LIGHT, ALIGN_HCENTER)
  end
end

----------------------------------------------------------------
-- ENDING STATE
----------------------------------------------------------------
local function update_ending()
  ending_timer = ending_timer + 1
  if ending_timer > 180 and (btnp("start") or btnp("a")) then
    state = "title"
    idle_timer = 0
    title_pulse = 0
    title_timer = 0
  end
end

local function draw_ending()
  cls(S, BLACK)

  local y = 16

  if ending_type == "true" then
    -- Best ending: full truth revealed
    text(S, "FREEDOM", W / 2, y, WHITE, ALIGN_HCENTER)
    y = y + 16
    if ending_timer > 30 then
      text(S, "You remember everything.", W / 2, y, LIGHT, ALIGN_HCENTER)
      y = y + 12
    end
    if ending_timer > 60 then
      text(S, "Subject 17. The experiments.", W / 2, y, LIGHT, ALIGN_HCENTER)
      y = y + 12
    end
    if ending_timer > 90 then
      text(S, "Dr. Wren's lies.", W / 2, y, LIGHT, ALIGN_HCENTER)
      y = y + 12
    end
    if ending_timer > 120 then
      text(S, "The evidence will end this.", W / 2, y, WHITE, ALIGN_HCENTER)
      y = y + 16
    end
    if ending_timer > 150 then
      text(S, "You step into the light.", W / 2, y, WHITE, ALIGN_HCENTER)
      y = y + 12
    end
    if ending_timer > 170 then
      text(S, "TRUE ENDING", W / 2, y + 8, WHITE, ALIGN_HCENTER)
    end

  elseif ending_type == "good" then
    text(S, "ESCAPE", W / 2, y, WHITE, ALIGN_HCENTER)
    y = y + 16
    if ending_timer > 30 then
      text(S, "You have the evidence.", W / 2, y, LIGHT, ALIGN_HCENTER)
      y = y + 12
    end
    if ending_timer > 60 then
      text(S, "But the memories are", W / 2, y, LIGHT, ALIGN_HCENTER)
      y = y + 10
      text(S, "fragments. Incomplete.", W / 2, y, LIGHT, ALIGN_HCENTER)
      y = y + 12
    end
    if ending_timer > 90 then
      text(S, "Who were you, really?", W / 2, y, DARK, ALIGN_HCENTER)
      y = y + 16
    end
    if ending_timer > 120 then
      text(S, "GOOD ENDING", W / 2, y, LIGHT, ALIGN_HCENTER)
    end

  else
    -- Basic escape
    text(S, "ESCAPE", W / 2, y, LIGHT, ALIGN_HCENTER)
    y = y + 16
    if ending_timer > 30 then
      text(S, "You stumble into daylight.", W / 2, y, DARK, ALIGN_HCENTER)
      y = y + 12
    end
    if ending_timer > 60 then
      text(S, "Free. But you remember", W / 2, y, DARK, ALIGN_HCENTER)
      y = y + 10
      text(S, "nothing. Not even your name.", W / 2, y, DARK, ALIGN_HCENTER)
      y = y + 12
    end
    if ending_timer > 90 then
      text(S, "The darkness follows.", W / 2, y, DARK, ALIGN_HCENTER)
      y = y + 16
    end
    if ending_timer > 120 then
      text(S, "ENDING", W / 2, y, DARK, ALIGN_HCENTER)
    end
  end

  if ending_timer > 180 then
    if fcount % 40 < 25 then
      text(S, "PRESS START", W / 2, H - 12, LIGHT, ALIGN_HCENTER)
    end
    fcount = fcount + 1
  end
end

----------------------------------------------------------------
-- MAIN LOOP
----------------------------------------------------------------
function _init()
  mode(2)
  state = "title"
  title_pulse = 0
  title_timer = 0
  title_flicker = 0
  idle_timer = 0
  demo_mode = false
end

function _update()
  if state == "title" then
    update_title()
  elseif state == "demo" then
    update_demo()
  elseif state == "game" then
    update_game()
  elseif state == "ending" then
    update_ending()
  end
end

function _draw()
  S = screen()

  if state == "title" then
    draw_title()
  elseif state == "demo" then
    draw_demo()
  elseif state == "game" then
    draw_game()
  elseif state == "ending" then
    draw_ending()
  end
end
