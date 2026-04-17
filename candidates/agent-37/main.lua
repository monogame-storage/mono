-- THE DARK ROOM: LETHE (REPLAY VALUE)
-- Agent 37 | Wave 4 | Replay systems on agent-29 base
-- Tracks endings, New Game+, time attack, procedural items, statistics
-- 160x120 | 2-bit (4 shades: 0-3) | mode(2)
-- D-Pad: Move cursor/Turn | A: Interact | B: Inventory | START: Pause

----------------------------------------------
-- CONSTANTS
----------------------------------------------
local W, H = 160, 120
local BLACK, DARK, LIGHT, WHITE = 0, 1, 2, 3
local DIR_N, DIR_E, DIR_S, DIR_W = 1, 2, 3, 4
local DIR_NAMES = {"NORTH", "EAST", "SOUTH", "WEST"}
local DEMO_IDLE = 300

----------------------------------------------
-- SEEDED PRNG (xorshift32, from agent-25)
----------------------------------------------
local rng_state = 1

local function rng_seed(s)
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

----------------------------------------------
-- SAFE AUDIO
----------------------------------------------
local function sfx_note(ch, n, dur)
  if note then note(ch, n, dur) end
end
local function sfx_noise(ch, dur)
  if noise then noise(ch, dur) end
end

----------------------------------------------
-- SOUND EFFECTS
----------------------------------------------
local function snd_turn() sfx_note(0, "C2", 0.05) end
local function snd_step() sfx_note(0, "G2", 0.04) sfx_noise(1, 0.03) end
local function snd_pickup()
  sfx_note(0, "C5", 0.06) sfx_note(0, "E5", 0.06) sfx_note(0, "G5", 0.06)
end
local function snd_door() sfx_note(0, "C2", 0.15) sfx_note(1, "E2", 0.1) end
local function snd_locked() sfx_noise(0, 0.08) sfx_note(1, "C2", 0.08) end
local function snd_solve()
  sfx_note(0, "C5", 0.1) sfx_note(0, "E5", 0.1)
  sfx_note(0, "G5", 0.1) sfx_note(0, "C6", 0.2)
end
local function snd_craft()
  sfx_note(0, "E5", 0.08) sfx_note(1, "G5", 0.08) sfx_note(0, "C6", 0.12)
end
local function snd_click() sfx_note(0, "A4", 0.03) end
local function snd_typewriter() sfx_note(1, "D6", 0.01) end
local function snd_read() sfx_note(0, "D4", 0.06) sfx_note(1, "F4", 0.04) end
local function snd_heartbeat()
  sfx_note(0, "C3", 0.06) sfx_note(0, "C3", 0.04)
end
local function snd_drip()
  sfx_note(3, "E6", 0.02)
end
local function snd_creak()
  local creaks = {"A2", "B2", "G2", "D2"}
  sfx_note(2, creaks[math.random(#creaks)], 0.12)
end
local function snd_entity_step()
  sfx_noise(2, 0.03)
  sfx_note(2, "D2", 0.06)
end
local function snd_entity_breathe()
  sfx_note(3, "A1", 0.12)
end

----------------------------------------------
-- PERSISTENT SAVE DATA
----------------------------------------------
local save_data = {
  endings_seen = {false, false, false, false},  -- endings 1-3 + secret 4th
  ng_plus = false,
  run_count = 0,
  total_time_frames = 0,
  total_items_found = 0,
  total_story_bits = 0,
  total_completions = 0,
  best_time_attack = 0,  -- 0 = never completed
}

local function save_persistent()
  if store then
    -- Pack endings as bits
    local eb = 0
    for i = 1, 4 do
      if save_data.endings_seen[i] then eb = eb + (2 ^ (i - 1)) end
    end
    store("lethe_eb", eb)
    store("lethe_ng", save_data.ng_plus and 1 or 0)
    store("lethe_rc", save_data.run_count)
    store("lethe_tt", save_data.total_time_frames)
    store("lethe_ti", save_data.total_items_found)
    store("lethe_ts", save_data.total_story_bits)
    store("lethe_tc", save_data.total_completions)
    store("lethe_bt", save_data.best_time_attack)
  end
end

local function load_persistent()
  if fetch then
    local eb = fetch("lethe_eb") or 0
    for i = 1, 4 do
      save_data.endings_seen[i] = (eb % (2 ^ i)) >= (2 ^ (i - 1))
    end
    save_data.ng_plus = (fetch("lethe_ng") or 0) > 0
    save_data.run_count = fetch("lethe_rc") or 0
    save_data.total_time_frames = fetch("lethe_tt") or 0
    save_data.total_items_found = fetch("lethe_ti") or 0
    save_data.total_story_bits = fetch("lethe_ts") or 0
    save_data.total_completions = fetch("lethe_tc") or 0
    save_data.best_time_attack = fetch("lethe_bt") or 0
  end
end

----------------------------------------------
-- GLOBAL STATE
----------------------------------------------
local state = "title"
local idle_timer = 0
local msg_text = ""
local msg_timer = 0
local has_light = false

-- Run stats (per-run)
local run_time = 0         -- frames elapsed this run
local run_items = 0        -- items picked up this run
local run_seed = 1         -- seed for procedural placement

-- Time attack
local time_attack = false
local ta_limit = 30 * 60 * 3  -- 3 minutes at 30fps
local ta_remaining = 0

-- Typewriter narrative system
local tw_text = nil
local tw_lines = {}
local tw_pos = 0
local tw_total = 0
local tw_speed = 1
local tw_done = false
local tw_scroll = 0
local tw_sound_cd = 0

-- Document reader
local doc_text = nil
local doc_lines = {}
local doc_scroll = 0

-- Player
local cur_room = 1
local cur_dir = DIR_N
local cur_x, cur_y = 80, 60

-- Inventory
local inv = {}
local inv_open = false
local inv_sel = 1
local held_item = nil
local combine_mode = false
local combine_first = nil

-- Transition
local trans_timer = 0
local trans_target_room = nil
local trans_target_dir = nil

-- Ambient timers
local amb_drip_timer = 60
local amb_creak_timer = 120
local heartbeat_timer = 0
local heartbeat_active = false

-- Story tracking
local story_bits = 0
local STORY_JOURNAL1  = 1
local STORY_JOURNAL2  = 2
local STORY_JOURNAL3  = 4
local STORY_MEMO      = 8
local STORY_EVIDENCE  = 16
local STORY_TERMINAL  = 32
local STORY_CHAIR     = 64
local STORY_GARDEN    = 128

local function story_known(bit) return (story_bits % (bit * 2)) >= bit end
local function story_learn(bit)
  if not story_known(bit) then
    story_bits = story_bits + bit
    heartbeat_active = true
    heartbeat_timer = 90
  end
end

----------------------------------------------
-- NG+ ENTITY (stalker in subsequent playthroughs)
----------------------------------------------
local entity = {
  active = false,
  room = 3,           -- starts in storage
  dir = DIR_N,
  move_timer = 0,
  move_interval = 180, -- frames between moves
  alert = false,
  alert_timer = 0,
  visible_timer = 0,  -- brief sighting flashes
  breathe_timer = 0,
  step_timer = 0,
}

local function entity_reset()
  entity.active = save_data.ng_plus
  entity.room = 3
  entity.dir = DIR_N
  entity.move_timer = 0
  entity.move_interval = 180
  entity.alert = false
  entity.alert_timer = 0
  entity.visible_timer = 0
  entity.breathe_timer = 0
  entity.step_timer = 0
end

-- Room adjacency for entity movement
local room_adj = {
  [1] = {2},
  [2] = {1, 3, 4, 5},
  [3] = {2},
  [4] = {2},
  [5] = {2, 6},
  [6] = {5, 7},
  [7] = {6},
}

local function entity_update()
  if not entity.active then return end

  -- Move towards player periodically
  entity.move_timer = entity.move_timer + 1
  if entity.move_timer >= entity.move_interval then
    entity.move_timer = 0
    -- Move towards player's room through adjacency
    local adj = room_adj[entity.room]
    if adj then
      local best = nil
      local best_dist = 999
      for _, r in ipairs(adj) do
        local d = math.abs(r - cur_room)
        if d < best_dist then
          best_dist = d
          best = r
        end
      end
      -- Sometimes move randomly instead
      if math.random(3) == 1 then
        best = adj[math.random(#adj)]
      end
      if best then
        entity.room = best
        entity.dir = math.random(4)
      end
    end
    -- Speed up over time
    entity.move_interval = math.max(90, entity.move_interval - 1)
  end

  -- Audio cues when in same room
  if entity.room == cur_room then
    entity.step_timer = entity.step_timer + 1
    if entity.step_timer >= 45 then
      entity.step_timer = 0
      snd_entity_step()
    end
    entity.breathe_timer = entity.breathe_timer + 1
    if entity.breathe_timer >= 90 then
      entity.breathe_timer = 0
      snd_entity_breathe()
    end
    -- Increase heartbeat
    if not heartbeat_active then
      heartbeat_active = true
      heartbeat_timer = 60
    end
    -- Brief visual sighting chance
    if entity.dir == cur_dir and math.random(300) == 1 then
      entity.visible_timer = 12
    end
  else
    entity.step_timer = 0
    entity.breathe_timer = 0
  end

  -- Adjacent room: faint sounds
  local adj = room_adj[cur_room]
  if adj then
    for _, r in ipairs(adj) do
      if r == entity.room and math.random(120) == 1 then
        snd_entity_step()
      end
    end
  end

  if entity.visible_timer > 0 then
    entity.visible_timer = entity.visible_timer - 1
  end
end

----------------------------------------------
-- PROCEDURAL ITEM PLACEMENT
----------------------------------------------
-- Each room has item slots with valid position offsets
-- Items are shuffled among slots each run based on seed

local item_slot_offsets = {
  -- Room 1 (cell): matches, lens, journal1
  [1] = {
    {dx=4, dy=8},   -- floor left
    {dx=24, dy=10},  -- floor right
    {dx=30, dy=3},   -- on cot
  },
  -- Room 3 (storage): wire, metal_rod, fuse_dead, tape, journal2
  [3] = {
    {dx=14, dy=2},  -- shelf left top
    {dx=12, dy=14}, -- shelf right mid
    {dx=4, dy=6},   -- box area 1
    {dx=4, dy=6},   -- box area 2
    {dx=38, dy=16}, -- chem shelf
  },
  -- Room 5 (office): note_l, note_r, evidence
  [5] = {
    {dx=6, dy=4},    -- behind painting
    {dx=4, dy=2},    -- on desk
    {dx=1, dy=1},    -- in cabinet
  },
  -- Room 6 (exit hall): crowbar
  [6] = {
    {dx=6, dy=2},
  },
}

-- Shuffled slot indices per room, computed at run start
local shuffled_slots = {}

local function shuffle_item_slots()
  shuffled_slots = {}
  rng_seed(run_seed)
  for room, slots in pairs(item_slot_offsets) do
    local indices = {}
    for i = 1, #slots do indices[i] = i end
    -- Fisher-Yates shuffle
    for i = #indices, 2, -1 do
      local j = rng_int(1, i)
      indices[i], indices[j] = indices[j], indices[i]
    end
    shuffled_slots[room] = indices
  end
end

-- Get the shuffled offset for a given room's nth item
local function get_item_offset(room, slot_idx)
  local slots = item_slot_offsets[room]
  local shuf = shuffled_slots[room]
  if not slots or not shuf then return {dx=0, dy=0} end
  local mapped = shuf[((slot_idx - 1) % #slots) + 1] or 1
  return slots[mapped] or {dx=0, dy=0}
end

----------------------------------------------
-- ITEM DATABASE
----------------------------------------------
local ITEMS = {
  matches   = {name="Matches",     desc="Three matches. Won't last long.",  icon="M"},
  lens      = {name="Glass Lens",  desc="Cracked magnifying lens.",         icon="O"},
  lantern   = {name="Lantern",     desc="Makeshift light. Barely enough.",  icon="*"},
  wire      = {name="Wire",        desc="Thin copper wire.",                icon="W"},
  metal_rod = {name="Metal Rod",   desc="Short iron rod.",                  icon="I"},
  lockpick  = {name="Lockpick",    desc="Bent wire pick.",                  icon="P"},
  tape      = {name="Tape",        desc="Roll of electrical tape.",         icon="T"},
  fuse_dead = {name="Dead Fuse",   desc="Blown 30-amp fuse.",              icon="F"},
  fuse_good = {name="Fixed Fuse",  desc="Taped fuse. Might work.",         icon="f"},
  keycard   = {name="Keycard",     desc="Dr. Wren - Level 4 Access.",      icon="K"},
  note_l    = {name="Note(left)",  desc="Torn paper: '74..'",              icon="1"},
  note_r    = {name="Note(right)", desc="Torn paper: '..39'",              icon="2"},
  full_note = {name="Full Note",   desc="Code: 7439",                      icon="N"},
  crowbar   = {name="Crowbar",     desc="Heavy. Pries things open.",       icon="C"},
  evidence  = {name="Evidence",    desc="Subject 17 file. Proof of everything.", icon="E"},
  journal1  = {name="Journal p.1", desc="Day 1: They moved me here.",      icon="J"},
  journal2  = {name="Journal p.2", desc="Day 15: They erase us.",          icon="J"},
  journal3  = {name="Journal p.3", desc="Day 31: I am Subject 17.",        icon="J"},
  master_key= {name="Master Key",  desc="Heavy brass key. Final door.",    icon="Q"},
}

local RECIPES = {
  {a="matches",   b="lens",      result="lantern"},
  {a="wire",      b="metal_rod", result="lockpick"},
  {a="tape",      b="fuse_dead", result="fuse_good"},
  {a="note_l",    b="note_r",    result="full_note"},
}

----------------------------------------------
-- PUZZLE FLAGS
----------------------------------------------
local flags = {}

local function reset_flags()
  flags = {
    cell_searched = false,
    keycard_found = false,
    lab_powered = false,
    terminal_used = false,
    desk_pried = false,
    evidence_found = false,
    safe_open = false,
    safe_mode = false,
    safe_digits = {0,0,0,0},
    safe_sel = 1,
    escaped = false,
    garden_visited = false,
    room_narrated = {},
  }
end

----------------------------------------------
-- UTILITY
----------------------------------------------
local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function show_msg(txt, dur)
  msg_text = txt
  msg_timer = dur or 90
end

local function has_item(name)
  for i, v in ipairs(inv) do
    if v == name then return true, i end
  end
  return false
end

local function add_item(name)
  if not has_item(name) and #inv < 10 then
    inv[#inv+1] = name
    snd_pickup()
    show_msg("Got: " .. ITEMS[name].name, 60)
    run_items = run_items + 1
    return true
  end
  return false
end

local function remove_item(name)
  local found, idx = has_item(name)
  if found then
    table.remove(inv, idx)
    if held_item == name then held_item = nil end
  end
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

----------------------------------------------
-- WORD WRAP
----------------------------------------------
local function word_wrap(str, max)
  local lines = {}
  for para in str:gmatch("[^\n]+") do
    local ln = ""
    for w in para:gmatch("%S+") do
      if #ln + #w + 1 > max then
        lines[#lines+1] = ln
        ln = w
      else
        ln = #ln > 0 and (ln .. " " .. w) or w
      end
    end
    if #ln > 0 then lines[#lines+1] = ln end
  end
  if #lines == 0 then lines[1] = "" end
  return lines
end

----------------------------------------------
-- TYPEWRITER NARRATIVE
----------------------------------------------
local function show_typewriter(txt, speed)
  tw_text = txt
  tw_lines = word_wrap(txt, 28)
  tw_pos = 0
  tw_total = #txt
  tw_speed = speed or 1
  tw_done = false
  tw_scroll = 0
  tw_sound_cd = 0
end

local function dismiss_typewriter()
  tw_text = nil
  tw_lines = {}
  tw_pos = 0
  tw_done = false
end

local function show_document(txt)
  doc_text = txt
  doc_lines = word_wrap(txt, 30)
  doc_scroll = 0
  snd_read()
end

local function close_document()
  doc_text = nil
  doc_lines = {}
end

----------------------------------------------
-- ROOM FIRST-ENTRY NARRATIVES
----------------------------------------------
local room_narratives = {
  [1] = "Pitch black. Cold concrete. Your head throbs with hollow pain. The air tastes of rust and something chemical. You feel the edges of a narrow cot. Tally marks line the wall beside it. Hundreds of them. You do not remember making them.",
  [2] = "A corridor stretches into red-tinged gloom. Emergency lights cast sick pools every few meters. Green institutional tile, cracked and water-stained. A sign reads: SUBLEVEL 4 - RESTRICTED. You have walked this corridor before. Your legs know the way even if your mind does not.",
  [3] = "Shelves loom like the ribs of some dead animal. The chemical smell is stronger here. Syringes. Restraints. Unlabeled vials of pale liquid. A label catches your eye: LETHE COMPOUND B.7. Whatever they use on you, this is where they keep it.",
  [4] = "The lab hums with dead silence. In the center stands an examination chair with leather restraints worn smooth from use. Electrodes dangle from a headpiece above it. Your body goes cold. Not from fear -- from recognition. You have sat in this chair. Your bones remember.",
  [5] = "An office. Papers everywhere. A portrait of a man in a white coat stares down at you with painted eyes. The nameplate reads DR. H. WREN, DIRECTOR. Something about that face. You almost remember. Almost.",
  [6] = "A blast door. Military-grade steel. Beyond it: the surface. Freedom. A keypad blinks beside it, waiting for a code. This is the last door between you and the world they erased you from.",
  [7] = "Moonlight. After so long in fluorescent hell, moonlight. A small enclosed garden, dead and overgrown. In the center, a bench. On the bench, a tape recorder. Someone left this here. Someone who knew you would find it.",
}

-- NG+ modifies some narratives
local ngp_room_narratives = {
  [1] = "Pitch black. Again. Your head throbs with a pain that feels rehearsed. The tally marks on the wall -- you remember them now. You remember everything. But something else is down here with you this time. Something that was not here before. Or was it always here, and you simply forgot?",
  [2] = "The corridor. You know this corridor. Every crack, every stain. But the shadows move differently now. There is a presence. You feel it watching from the dark spaces between the emergency lights.",
  [4] = "The lab. The chair. You have sat in it thirty-one times. But the chair is still warm. Someone -- something -- was here moments ago. Electrodes swing gently, as if recently disturbed.",
}

----------------------------------------------
-- DITHER
----------------------------------------------
local function dither_rectf(s, rx, ry, rw, rh, c1, c2, pat)
  for dy = 0, rh - 1 do
    for dx = 0, rw - 1 do
      local x, y = rx + dx, ry + dy
      if pat <= 0 then
        pix(s, x, y, c1)
      elseif pat >= 4 then
        pix(s, x, y, c2)
      elseif pat == 2 then
        pix(s, x, y, (x + y) % 2 == 0 and c2 or c1)
      elseif pat == 1 then
        pix(s, x, y, (x % 2 + y % 2 * 2) == 0 and c2 or c1)
      else
        pix(s, x, y, (x % 2 + y % 2 * 2) == 0 and c1 or c2)
      end
    end
  end
end

----------------------------------------------
-- FIRST-PERSON WALL RENDERING
----------------------------------------------
local function draw_room_base(s)
  -- Ceiling
  for y = 0, 39 do
    local depth = y / 40.0
    local shade = has_light and (depth < 0.3 and 2 or 1) or (depth < 0.3 and 1 or 0)
    for x = 0, W - 1 do
      local checker = (math.floor(x / 8) + math.floor(y / 4)) % 2
      pix(s, x, y, checker == 0 and shade or clamp(shade - 1, 0, 3))
    end
  end

  -- Floor
  for y = 80, H - 11 do
    local depth = (y - 80) / 30.0
    local shade = has_light and (depth > 0.6 and 2 or 1) or (depth > 0.6 and 1 or 0)
    for x = 0, W - 1 do
      local checker = (math.floor(x / 8) + math.floor((y - 80) / 4)) % 2
      pix(s, x, y, checker == 0 and shade or clamp(shade - 1, 0, 3))
    end
  end

  -- Back wall
  rectf(s, 0, 40, W, 40, has_light and LIGHT or DARK)

  -- Perspective lines
  local bc = has_light and WHITE or LIGHT
  line(s, 0, 0, 20, 40, bc)
  line(s, 0, H - 10, 20, 80, bc)
  line(s, W - 1, 0, W - 21, 40, bc)
  line(s, W - 1, H - 10, W - 21, 80, bc)
  line(s, 20, 40, W - 21, 40, bc)
  line(s, 20, 80, W - 21, 80, bc)

  -- Side wall fills
  for y = 0, H - 11 do
    local t = y / (H - 10)
    local lx = math.floor(t < 0.33 and (t / 0.33 * 20) or (t > 0.67 and ((1 - t) / 0.33 * 20) or 20))
    local sc = has_light and DARK or BLACK
    for x = 0, lx - 1 do pix(s, x, y, sc) end
    for x = W - lx, W - 1 do pix(s, x, y, sc) end
  end

  -- NG+ entity flicker effect when in same room
  if entity.active and entity.room == cur_room and entity.visible_timer > 0 then
    -- Brief dark figure silhouette
    local ex = 40 + math.random(60)
    local ey = 44
    rectf(s, ex, ey, 6, 28, BLACK)
    -- Head
    circ(s, ex + 3, ey - 2, 3, BLACK)
    -- Eyes
    if entity.visible_timer > 4 then
      pix(s, ex + 1, ey - 2, WHITE)
      pix(s, ex + 5, ey - 2, WHITE)
    end
  end
end

-- Drawing helpers
local function draw_door(s, x, y, w, h, open, col)
  local c = col or (has_light and WHITE or LIGHT)
  local bg = has_light and DARK or BLACK
  rect(s, x, y, w, h, c)
  if open then
    rectf(s, x + 2, y + 2, w - 4, h - 4, BLACK)
  else
    rectf(s, x + 2, y + 2, w - 4, h - 4, bg)
    rectf(s, x + w - 6, y + h // 2 - 1, 2, 3, c)
  end
end

local function draw_box(s, x, y, w, h, open)
  local c = has_light and WHITE or LIGHT
  local bg = has_light and LIGHT or DARK
  rect(s, x, y, w, h, c)
  if open then
    rectf(s, x + 1, y + 5, w - 2, h - 6, bg)
  else
    rectf(s, x + 1, y + 1, w - 2, h - 2, bg)
  end
end

local function draw_bookshelf(s, x, y)
  local c = has_light and WHITE or LIGHT
  local bg = has_light and LIGHT or DARK
  rect(s, x, y, 30, 36, c)
  for i = 0, 2 do
    line(s, x, y + 12 * (i + 1), x + 30, y + 12 * (i + 1), c)
    for b = 0, 4 do
      local bx = x + 2 + b * 5
      local by = y + 12 * i + 2
      local bh = 8 + (b % 3)
      rectf(s, bx, by, 4, bh, (b % 2 == 0) and c or bg)
    end
  end
end

local function draw_safe(s, x, y, open)
  local c = has_light and WHITE or LIGHT
  rect(s, x, y, 24, 20, c)
  if open then
    rectf(s, x + 1, y + 1, 22, 18, BLACK)
  else
    rectf(s, x + 1, y + 1, 22, 18, has_light and DARK or BLACK)
    circ(s, x + 12, y + 10, 5, c)
    pix(s, x + 12, y + 6, c)
  end
end

local function draw_desk(s, x, y)
  local c = has_light and WHITE or LIGHT
  local bg = has_light and LIGHT or DARK
  rectf(s, x, y, 60, 16, bg)
  rect(s, x, y, 60, 16, c)
  rectf(s, x + 2, y + 16, 4, 8, c)
  rectf(s, x + 54, y + 16, 4, 8, c)
end

local function draw_terminal(s, x, y, powered)
  local c = has_light and WHITE or LIGHT
  rect(s, x, y, 28, 22, c)
  if powered then
    rectf(s, x + 2, y + 2, 24, 14, DARK)
    if frame() % 30 < 20 then
      rectf(s, x + 4, y + 12, 4, 2, LIGHT)
    end
    text(s, ">_", x + 4, y + 4, LIGHT)
  else
    rectf(s, x + 2, y + 2, 24, 14, BLACK)
  end
  rectf(s, x + 8, y + 22, 12, 4, c)
end

local function draw_filing_cabinet(s, x, y, open)
  local c = has_light and WHITE or LIGHT
  rect(s, x, y, 22, 30, c)
  line(s, x, y + 10, x + 22, y + 10, c)
  line(s, x, y + 20, x + 22, y + 20, c)
  if open then
    rectf(s, x + 1, y + 1, 20, 8, BLACK)
  else
    rectf(s, x + 8, y + 4, 6, 2, c)
    rectf(s, x + 8, y + 14, 6, 2, c)
    rectf(s, x + 8, y + 24, 6, 2, c)
  end
end

local function draw_keypad(s, x, y)
  local c = has_light and WHITE or LIGHT
  rect(s, x, y, 16, 20, c)
  rectf(s, x + 1, y + 1, 14, 18, has_light and DARK or BLACK)
  for row = 0, 2 do
    for col = 0, 2 do
      rectf(s, x + 2 + col * 4, y + 2 + row * 5, 3, 3, c)
    end
  end
  rectf(s, x + 2, y + 16, 12, 3, LIGHT)
end

local function draw_fuse_box(s, x, y, has_fuse)
  local c = has_light and WHITE or LIGHT
  rect(s, x, y, 18, 14, c)
  rectf(s, x + 1, y + 1, 16, 12, has_light and DARK or BLACK)
  if has_fuse then
    rectf(s, x + 6, y + 3, 6, 8, LIGHT)
  else
    text(s, "?", x + 7, y + 4, c)
  end
end

local function draw_painting(s, x, y, w, h)
  local c = has_light and WHITE or LIGHT
  local bg = has_light and DARK or BLACK
  rect(s, x, y, w, h, c)
  rectf(s, x + 2, y + 2, w - 4, h - 4, bg)
  circ(s, x + w // 2, y + h // 3, 5, has_light and LIGHT or DARK)
  rectf(s, x + w // 2 - 4, y + h // 3 + 4, 8, 8, has_light and LIGHT or DARK)
end

local function draw_chair(s, x, y)
  local c = has_light and WHITE or LIGHT
  rectf(s, x + 8, y, 24, 30, has_light and DARK or BLACK)
  rect(s, x + 8, y, 24, 30, c)
  line(s, x + 10, y + 8, x + 30, y + 8, c)
  line(s, x + 10, y + 20, x + 30, y + 20, c)
  circ(s, x + 20, y + 4, 6, c)
  for i = 0, 2 do
    local wx = x + 16 + i * 4
    line(s, wx, y - 4, wx + 1, y, c)
  end
end

local function draw_tape_recorder(s, x, y)
  local c = has_light and WHITE or LIGHT
  rect(s, x, y, 20, 12, c)
  rectf(s, x + 1, y + 1, 18, 10, has_light and DARK or BLACK)
  circ(s, x + 6, y + 6, 3, c)
  circ(s, x + 14, y + 6, 3, c)
  if frame() % 20 < 10 then
    pix(s, x + 6, y + 6, has_light and LIGHT or DARK)
  end
end

----------------------------------------------
-- HOTSPOT DEFINITIONS
----------------------------------------------
local hotspots = {}

local function get_wall_hotspots(room, dir)
  local key = room * 10 + dir
  return hotspots[key] or {}
end

local function build_hotspots()
  hotspots = {}

  -- ==========================================
  -- ROOM 1: THE CELL
  -- ==========================================

  -- North: heavy door
  hotspots[11] = {
    {x=60, y=42, w=28, h=36, name="cell_door",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, flags.cell_searched)
        if not has_light then
          text(s, "?", hs.x + 12, hs.y + 14, DARK)
        else
          text(s, "DOOR", hs.x + 4, hs.y + 14, DARK)
        end
      end,
      interact=function()
        if flags.cell_searched then
          snd_door()
          show_msg("Into the corridor...", 60)
          trans_timer = 15
          trans_target_room = 2
          trans_target_dir = DIR_S
        elseif has_light then
          flags.cell_searched = true
          snd_door()
          show_msg("The corroded latch gives way!", 90)
        else
          show_msg("A heavy door. Can't see the lock.", 60)
          snd_locked()
        end
      end
    }
  }

  -- East: wall with scratches
  hotspots[12] = {
    {x=40, y=44, w=50, h=28, name="cell_wall",
      draw=function(s, hs)
        local c = has_light and LIGHT or DARK
        for i = 0, 7 do
          line(s, hs.x + 4 + i*5, hs.y + 2, hs.x + 4 + i*5, hs.y + 14, c)
        end
        if has_light then
          text(s, "DONT FORGET", hs.x + 2, hs.y + 18, DARK)
        end
      end,
      interact=function()
        if has_light then
          local extra = ""
          if save_data.ng_plus then
            extra = " A new line has been scratched, fresher than the rest: 'IT WATCHES. IT REMEMBERS TOO.'"
          end
          show_typewriter("The tally marks go on and on. Hundreds. You trace them with your finger and your hand knows the motion. At the bottom, scratched deep into concrete: 'THEY ERASE YOU. DO NOT FORGET. DO NOT TRUST WREN.' Below, smaller: 'Keycard taped behind pipe. Corridor.'" .. extra, 1)
        else
          show_msg("Rough scratches. Too dark.", 60)
        end
      end
    }
  }

  -- South: cot with journal
  hotspots[13] = {
    {x=45, y=50, w=50, h=20, name="cell_cot",
      draw=function(s, hs)
        local c = has_light and WHITE or LIGHT
        local bg = has_light and LIGHT or DARK
        rectf(s, hs.x, hs.y, hs.w, hs.h, bg)
        rect(s, hs.x, hs.y, hs.w, hs.h, c)
        rectf(s, hs.x + 2, hs.y + 2, 14, 8, c)
        line(s, hs.x, hs.y + 12, hs.x + hs.w, hs.y + 12, c)
        if not has_item("journal1") and has_light then
          local off = get_item_offset(1, 3)
          rectf(s, hs.x + off.dx, hs.y + off.dy, 10, 7, WHITE)
          text(s, "J", hs.x + off.dx + 3, hs.y + off.dy + 1, DARK)
        end
      end,
      interact=function()
        if not has_item("journal1") and has_light then
          add_item("journal1")
          story_learn(STORY_JOURNAL1)
          show_typewriter("JOURNAL - DAY 1\nThey moved me to sublevel 4 after I found the files. Dr. Wren says it is for my own safety. The door locked behind me. I heard him whisper to someone in the hall. Something about 'the schedule.' I do not believe a word he says. I will hide these pages where they cannot find them.", 1)
        elseif not has_light then
          show_msg("A narrow cot. Something underneath?", 60)
        else
          show_msg("Your cot. Still warm.", 40)
        end
      end
    }
  }

  -- West: floor with matches and lens (procedurally placed)
  hotspots[14] = {
    {x=50, y=52, w=36, h=20, name="cell_floor",
      draw=function(s, hs)
        local c = has_light and LIGHT or DARK
        if not has_item("matches") then
          local off = get_item_offset(1, 1)
          rectf(s, hs.x + off.dx, hs.y + off.dy, 8, 4, c)
          text(s, "m", hs.x + off.dx + 1, hs.y + off.dy, has_light and WHITE or LIGHT)
        end
        if not has_item("lens") and has_light then
          local off = get_item_offset(1, 2)
          circ(s, hs.x + off.dx, hs.y + off.dy, 4, WHITE)
        end
      end,
      interact=function()
        if not has_item("matches") then
          add_item("matches")
          show_msg("Matches! Three left.", 60)
        elseif not has_item("lens") and has_light then
          add_item("lens")
          show_msg("A cracked magnifying lens.", 60)
        elseif not has_light then
          show_msg("Something small on the floor.", 40)
        else
          show_msg("Cold concrete floor.", 40)
        end
      end
    }
  }

  -- ==========================================
  -- ROOM 2: THE CORRIDOR
  -- ==========================================

  -- North: door to lab (needs keycard)
  hotspots[21] = {
    {x=55, y=42, w=28, h=36, name="corr_lab_door",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, false)
        if has_light then
          text(s, "LAB", hs.x + 6, hs.y + 14, DARK)
          rectf(s, hs.x + hs.w + 2, hs.y + 10, 6, 10, LIGHT)
          line(s, hs.x + hs.w + 3, hs.y + 14, hs.x + hs.w + 6, hs.y + 14, WHITE)
        end
      end,
      interact=function()
        if has_item("keycard") or held_item == "keycard" then
          snd_door()
          show_msg("Keycard accepted.", 60)
          trans_timer = 15
          trans_target_room = 4
          trans_target_dir = DIR_S
        else
          snd_locked()
          show_msg("Card reader glows red. Need a keycard.", 60)
        end
      end
    }
  }

  -- East: notice board + office door
  hotspots[22] = {
    {x=30, y=44, w=34, h=24, name="corr_notices",
      draw=function(s, hs)
        local c = has_light and WHITE or LIGHT
        rect(s, hs.x, hs.y, hs.w, hs.h, c)
        rectf(s, hs.x + 1, hs.y + 1, hs.w - 2, hs.h - 2, has_light and DARK or BLACK)
        if has_light then
          rectf(s, hs.x + 3, hs.y + 3, 12, 8, LIGHT)
          rectf(s, hs.x + 18, hs.y + 3, 12, 8, LIGHT)
          rectf(s, hs.x + 8, hs.y + 14, 16, 8, LIGHT)
        end
      end,
      interact=function()
        if has_light then
          story_learn(STORY_MEMO)
          show_typewriter("MEMORANDUM - CONFIDENTIAL\nFrom: Dr. H. Wren, Director\nTo: All Level 4 Staff\nRe: Project LETHE Protocol\n'REMINDER: All test subjects must be fully sedated BEFORE memory wipe procedure. Unsedated wipes cause permanent neural damage, identity fragmentation, and in three cases, death. This is not a suggestion. -- H.W.'", 1)
        else
          show_msg("A notice board. Too dark to read.", 60)
        end
      end
    },
    {x=95, y=44, w=26, h=34, name="corr_office_door",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, false)
        if has_light then text(s, "OFC", hs.x + 4, hs.y + 14, DARK) end
      end,
      interact=function()
        if has_item("keycard") or held_item == "keycard" then
          snd_door()
          show_msg("Entering the office...", 60)
          trans_timer = 15
          trans_target_room = 5
          trans_target_dir = DIR_N
        else
          snd_locked()
          show_msg("Locked. Card reader beside it.", 60)
        end
      end
    }
  }

  -- South: door back to cell
  hotspots[23] = {
    {x=60, y=42, w=28, h=36, name="corr_cell_door",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, true)
        if has_light then text(s, "CELL", hs.x + 4, hs.y + 14, LIGHT) end
      end,
      interact=function()
        snd_door()
        trans_timer = 15
        trans_target_room = 1
        trans_target_dir = DIR_N
      end
    }
  }

  -- West: pipes (keycard) + storage door
  hotspots[24] = {
    {x=28, y=42, w=30, h=14, name="corr_pipes",
      draw=function(s, hs)
        local c = has_light and LIGHT or DARK
        for i = 0, 2 do
          line(s, hs.x, hs.y + i * 5, hs.x + hs.w, hs.y + i * 5, c)
        end
        if not flags.keycard_found and has_light then
          rectf(s, hs.x + 12, hs.y + 6, 8, 5, WHITE)
        end
      end,
      interact=function()
        if not flags.keycard_found and has_light then
          flags.keycard_found = true
          add_item("keycard")
          show_msg("Keycard: 'WREN, H. - LVL 4'", 90)
        elseif not has_light then
          show_msg("Pipes overhead. Dripping.", 60)
        else
          show_msg("Just pipes. Dripping.", 40)
        end
      end
    },
    {x=85, y=48, w=26, h=30, name="corr_storage_door",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, false)
        if has_light then text(s, "STOR", hs.x + 2, hs.y + 10, DARK) end
      end,
      interact=function()
        snd_door()
        show_msg("Storage room...", 40)
        trans_timer = 15
        trans_target_room = 3
        trans_target_dir = DIR_N
      end
    }
  }

  -- ==========================================
  -- ROOM 3: STORAGE
  -- ==========================================

  -- North: shelves with wire and metal rod (procedural)
  hotspots[31] = {
    {x=35, y=42, w=30, h=36, name="stor_shelf_l",
      draw=function(s, hs)
        draw_bookshelf(s, hs.x, hs.y)
        if not has_item("wire") and has_light then
          local off = get_item_offset(3, 1)
          line(s, hs.x + off.dx, hs.y + off.dy, hs.x + off.dx, hs.y + off.dy + 8, WHITE)
        end
      end,
      interact=function()
        if not has_item("wire") and has_light then
          add_item("wire")
        elseif not has_light then
          show_msg("Shelves. Too dark to search.", 40)
        else
          show_msg("Empty shelves.", 40)
        end
      end
    },
    {x=80, y=42, w=30, h=36, name="stor_shelf_r",
      draw=function(s, hs)
        draw_bookshelf(s, hs.x, hs.y)
        if not has_item("metal_rod") and has_light then
          local off = get_item_offset(3, 2)
          rectf(s, hs.x + off.dx, hs.y + off.dy, 2, 10, WHITE)
        end
      end,
      interact=function()
        if not has_item("metal_rod") and has_light then
          add_item("metal_rod")
        elseif not has_light then
          show_msg("Metal things. Can't see.", 40)
        else
          show_msg("Rusty equipment.", 40)
        end
      end
    }
  }

  -- East: boxes with fuse and tape (procedural)
  hotspots[32] = {
    {x=40, y=48, w=24, h=18, name="stor_box1",
      draw=function(s, hs)
        draw_box(s, hs.x, hs.y, hs.w, hs.h, false)
        if has_light then text(s, "FUSE", hs.x + 4, hs.y + 6, DARK) end
      end,
      interact=function()
        if not has_item("fuse_dead") and has_light then
          add_item("fuse_dead")
          show_msg("A blown fuse. Needs repair.", 60)
        elseif not has_light then
          show_msg("A box of something.", 40)
        else
          show_msg("Empty box.", 40)
        end
      end
    },
    {x=80, y=48, w=24, h=18, name="stor_box2",
      draw=function(s, hs)
        draw_box(s, hs.x, hs.y, hs.w, hs.h, false)
        if has_light then text(s, "TAPE", hs.x + 4, hs.y + 6, DARK) end
      end,
      interact=function()
        if not has_item("tape") and has_light then
          add_item("tape")
        elseif not has_light then
          show_msg("Another box.", 40)
        else
          show_msg("Nothing left.", 40)
        end
      end
    }
  }

  -- South: door back to corridor
  hotspots[33] = {
    {x=60, y=42, w=28, h=36, name="stor_door",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, true)
        if has_light then text(s, "CORR", hs.x + 2, hs.y + 14, LIGHT) end
      end,
      interact=function()
        snd_door()
        trans_timer = 15
        trans_target_room = 2
        trans_target_dir = DIR_W
      end
    }
  }

  -- West: chemical shelf with journal p.2 (procedural)
  hotspots[34] = {
    {x=40, y=44, w=50, h=28, name="stor_chem",
      draw=function(s, hs)
        local c = has_light and WHITE or LIGHT
        rect(s, hs.x, hs.y, hs.w, hs.h, c)
        if has_light then
          for i = 0, 4 do
            local vx = hs.x + 4 + i * 9
            rectf(s, vx, hs.y + 4, 4, 12, LIGHT)
            pix(s, vx + 2, hs.y + 8, WHITE)
          end
          text(s, "LETHE B.7", hs.x + 6, hs.y + 20, DARK)
        end
        if not has_item("journal2") and has_light then
          local off = get_item_offset(3, 5)
          rectf(s, hs.x + off.dx, hs.y + off.dy, 8, 6, WHITE)
        end
      end,
      interact=function()
        if not has_item("journal2") and has_light then
          add_item("journal2")
          story_learn(STORY_JOURNAL2)
          show_typewriter("JOURNAL - DAY 15\nThe other subjects cannot remember their own names. They sit in their cells and stare at walls for hours. Their eyes are hollow, like dolls. I have been hiding my journal pages in the walls, in cots, behind chemicals. If they wipe me again, perhaps I will find them. Perhaps I will remember that I was once a person.\nThe vials are labeled LETHE COMPOUND. That is what they use to erase us.", 1)
        elseif has_light then
          show_msg("LETHE COMPOUND. Memory eraser.", 60)
        else
          show_msg("Chemical smell. Can't see labels.", 60)
        end
      end
    }
  }

  -- ==========================================
  -- ROOM 4: THE LAB
  -- ==========================================

  -- North: fuse box + terminal
  hotspots[41] = {
    {x=60, y=46, w=18, h=14, name="lab_fusebox",
      draw=function(s, hs) draw_fuse_box(s, hs.x, hs.y, flags.lab_powered) end,
      interact=function()
        if flags.lab_powered then
          show_msg("Fuse is in place. Power on.", 40)
        elseif held_item == "fuse_good" or has_item("fuse_good") then
          remove_item("fuse_good")
          flags.lab_powered = true
          held_item = nil
          snd_solve()
          show_msg("Power restored!", 90)
          sfx_noise(0, 0.3)
        else
          show_msg("Fuse box. One slot empty.", 60)
        end
      end
    },
    {x=90, y=42, w=28, h=22, name="lab_terminal",
      draw=function(s, hs) draw_terminal(s, hs.x, hs.y, flags.lab_powered) end,
      interact=function()
        if not flags.lab_powered then
          show_msg("Terminal is dead. No power.", 60)
        elseif not flags.terminal_used then
          flags.terminal_used = true
          story_learn(STORY_TERMINAL)
          show_typewriter("LETHE TERMINAL v4.7\n> Searching: SUBJECT 17\n> 31 wipe cycles logged\n> Status: ACTIVE\n> Last wipe: 3 days ago\n> Physician: WREN, H. (DECEASED)\n> ERROR: Dr. Wren death cert on file dated 4 months prior to last 12 wipe entries\n> EXIT OVERRIDE CODE: 7439\nYou stare at the screen. Wren is dead. Has been dead. Who has been running the wipes?", 1)
        else
          show_msg("Terminal: EXIT CODE 7439", 60)
        end
      end
    }
  }

  -- East: examination chair
  hotspots[42] = {
    {x=45, y=46, w=40, h=30, name="lab_chair",
      draw=function(s, hs) draw_chair(s, hs.x, hs.y) end,
      interact=function()
        if has_light then
          story_learn(STORY_CHAIR)
          show_typewriter("The restraints are worn smooth from hundreds of sessions. Your wrists fit perfectly into the grooves. A placard reads: LETHE ADMINISTRATION STATION 3.\nYou touch the headpiece and the world tilts. A flash -- white light, a voice saying 'count backward from ten' -- and then nothing. A memory of forgetting. You pull your hand back, shaking.", 1)
        else
          show_msg("Something bulky with straps.", 60)
        end
      end
    }
  }

  -- South: door back to corridor
  hotspots[43] = {
    {x=60, y=42, w=28, h=36, name="lab_door",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, true)
        if has_light then text(s, "CORR", hs.x + 2, hs.y + 14, LIGHT) end
      end,
      interact=function()
        snd_door()
        trans_timer = 15
        trans_target_room = 2
        trans_target_dir = DIR_N
      end
    }
  }

  -- West: desk with journal p.3 (locked drawer)
  hotspots[44] = {
    {x=40, y=52, w=60, h=16, name="lab_desk",
      draw=function(s, hs)
        draw_desk(s, hs.x, hs.y)
        if not flags.desk_pried and has_light then
          local c = WHITE
          rectf(s, hs.x + 22, hs.y + 2, 16, 10, c)
          text(s, "LOCK", hs.x + 24, hs.y + 3, DARK)
        end
      end,
      interact=function()
        if flags.desk_pried then
          show_msg("Empty drawer.", 40)
        elseif held_item == "lockpick" or held_item == "crowbar" then
          flags.desk_pried = true
          remove_item(held_item)
          held_item = nil
          add_item("journal3")
          story_learn(STORY_JOURNAL3)
          show_typewriter("JOURNAL - DAY 31\nI know the truth now. I am not a researcher. I never was. I am Subject 17. They implanted false memories of being staff -- of having a life before this place. The real Dr. Wren died four months ago. Someone, or something, is wearing his face. The wipes continue on schedule. I must escape with proof before the next cycle. Before I forget again. Before I become no one. Again.", 1)
        elseif has_item("lockpick") or has_item("crowbar") then
          show_msg("Locked drawer. Use a tool on it.", 60)
        else
          show_msg("Drawer is locked tight.", 60)
        end
      end
    }
  }

  -- ==========================================
  -- ROOM 5: THE OFFICE
  -- ==========================================

  -- North: painting with note_l behind it (procedural)
  hotspots[51] = {
    {x=50, y=44, w=40, h=28, name="ofc_painting",
      draw=function(s, hs)
        draw_painting(s, hs.x, hs.y, hs.w, hs.h)
        if has_light then
          text(s, "H.WREN", hs.x + 6, hs.y + hs.h + 2, DARK)
        end
      end,
      interact=function()
        if not has_item("note_l") and has_light then
          add_item("note_l")
          show_msg("Behind the painting: torn note '74..'", 80)
        elseif has_light then
          show_typewriter("The portrait stares back at you. Dr. Harold Wren, painted in oils. The eyes follow you. The mouth seems to smile differently each time you look. The paint is cracking. Beneath the cracks, another face.", 1)
        else
          show_msg("A framed picture. Too dark.", 60)
        end
      end
    }
  }

  -- East: filing cabinet (evidence) + safe
  hotspots[52] = {
    {x=55, y=44, w=22, h=30, name="ofc_cabinet",
      draw=function(s, hs) draw_filing_cabinet(s, hs.x, hs.y, flags.evidence_found) end,
      interact=function()
        if not flags.evidence_found and has_light then
          flags.evidence_found = true
          add_item("evidence")
          story_learn(STORY_EVIDENCE)
          show_typewriter("SUBJECT 17 - CLASSIFIED\nPhotographs of you strapped to the chair. Your face, slack and empty. Medical notes: 31 memory wipes documented. Increasing dosage each time as resistance builds. Side effects: confusion, identity loss, false memory implantation, violent episodes, partial seizures.\nHandwritten addendum: 'Subject 17 keeps hiding journal pages. Recommend permanent solution after next audit. -- W.'", 1)
        elseif flags.evidence_found then
          show_msg("Empty cabinet.", 40)
        else
          show_msg("Filing cabinet. Too dark to read.", 60)
        end
      end
    },
    {x=90, y=50, w=24, h=22, name="ofc_safe",
      draw=function(s, hs)
        draw_safe(s, hs.x, hs.y, flags.safe_open)
        if not flags.safe_open and has_light then
          for i = 1, 4 do
            local dx = hs.x + (i - 1) * 6
            text(s, tostring(flags.safe_digits[i]), dx, hs.y + hs.h + 2, WHITE)
          end
          local ax = hs.x + (flags.safe_sel - 1) * 6
          text(s, "^", ax, hs.y + hs.h + 8, WHITE)
        end
      end,
      interact=function()
        if flags.safe_open then
          show_msg("Safe is empty now.", 40)
        elseif not has_light then
          show_msg("A safe. Can't see the dial.", 60)
        else
          flags.safe_mode = true
          show_msg("UP/DN:digit L/R:sel A:try B:exit", 120)
        end
      end
    }
  }

  -- South: corridor door + exit hall door
  hotspots[53] = {
    {x=40, y=42, w=28, h=36, name="ofc_door_corr",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, true)
        if has_light then text(s, "CORR", hs.x + 2, hs.y + 14, LIGHT) end
      end,
      interact=function()
        snd_door()
        trans_timer = 15
        trans_target_room = 2
        trans_target_dir = DIR_E
      end
    },
    {x=100, y=48, w=24, h=30, name="ofc_door_exit",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, false)
        if has_light then text(s, "EXIT", hs.x + 2, hs.y + 10, DARK) end
      end,
      interact=function()
        if has_item("crowbar") or has_item("lockpick") or held_item == "crowbar" or held_item == "lockpick" then
          snd_door()
          show_msg("Pried the door open.", 60)
          trans_timer = 15
          trans_target_room = 6
          trans_target_dir = DIR_N
        else
          snd_locked()
          show_msg("Jammed shut. Need a tool.", 60)
        end
      end
    }
  }

  -- West: desk with papers + note_r (procedural)
  hotspots[54] = {
    {x=40, y=52, w=60, h=16, name="ofc_desk",
      draw=function(s, hs)
        draw_desk(s, hs.x, hs.y)
        if has_light then
          for i = 0, 3 do
            rectf(s, hs.x + 4 + i * 12, hs.y + 2, 8, 6, LIGHT)
          end
        end
      end,
      interact=function()
        if not has_item("note_r") and has_light then
          add_item("note_r")
          show_typewriter("Memos between 'Wren' and the DIRECTOR. The handwriting changes halfway through the stack -- same signature, different hand.\n'The board is asking questions. Subject 17 must be wiped again before the audit. Maximum dosage. If the subject expires, file it as cardiac failure.'\nDate: three days ago.\nA torn scrap falls out: '..39'", 1)
        elseif has_light then
          show_msg("Desk covered in memos.", 40)
        else
          show_msg("Papers rustle under your hand.", 40)
        end
      end
    }
  }

  -- ==========================================
  -- ROOM 6: EXIT HALL
  -- ==========================================

  -- North: blast door with keypad
  hotspots[61] = {
    {x=50, y=40, w=40, h=38, name="exit_blast_door",
      draw=function(s, hs)
        local c = has_light and WHITE or LIGHT
        rect(s, hs.x, hs.y, hs.w, hs.h, c)
        if flags.escaped then
          rectf(s, hs.x + 2, hs.y + 2, hs.w - 4, hs.h - 4, WHITE)
        else
          rectf(s, hs.x + 2, hs.y + 2, hs.w - 4, hs.h - 4, has_light and DARK or BLACK)
          text(s, "EXIT", hs.x + 10, hs.y + 14, c)
          text(s, "AUTH ONLY", hs.x + 4, hs.y + 24, DARK)
        end
      end,
      interact=function()
        if flags.escaped then
          state = "ending"
        else
          show_msg("Blast door. A keypad controls it.", 60)
        end
      end
    },
    {x=96, y=46, w=16, h=20, name="exit_keypad",
      draw=function(s, hs) draw_keypad(s, hs.x, hs.y) end,
      interact=function()
        if has_item("full_note") or story_known(STORY_TERMINAL) then
          flags.escaped = true
          snd_solve()
          state = "ending"
        else
          show_msg("Keypad needs a 4-digit code.", 60)
          snd_locked()
        end
      end
    }
  }

  -- East: side wall with crowbar (procedural)
  hotspots[62] = {
    {x=50, y=50, w=30, h=20, name="exit_debris",
      draw=function(s, hs)
        local c = has_light and LIGHT or DARK
        for i = 0, 3 do
          rectf(s, hs.x + i * 7, hs.y + 10 - i * 2, 5, 4 + i, c)
        end
        if not has_item("crowbar") and has_light then
          local off = get_item_offset(6, 1)
          line(s, hs.x + off.dx, hs.y + off.dy, hs.x + off.dx, hs.y + off.dy + 14, WHITE)
          line(s, hs.x + off.dx - 2, hs.y + off.dy, hs.x + off.dx + 2, hs.y + off.dy, WHITE)
        end
      end,
      interact=function()
        if not has_item("crowbar") and has_light then
          add_item("crowbar")
          show_msg("A crowbar, half-buried in rubble.", 60)
        elseif not has_light then
          show_msg("Rubble and debris.", 40)
        else
          show_msg("Nothing else in the rubble.", 40)
        end
      end
    }
  }

  -- South: door back to office
  hotspots[63] = {
    {x=60, y=42, w=28, h=36, name="exit_back",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, true)
        if has_light then text(s, "OFC", hs.x + 4, hs.y + 14, LIGHT) end
      end,
      interact=function()
        snd_door()
        trans_timer = 15
        trans_target_room = 5
        trans_target_dir = DIR_S
      end
    }
  }

  -- West: side door to garden (needs master key)
  hotspots[64] = {
    {x=55, y=44, w=28, h=34, name="exit_garden_door",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, false, has_light and LIGHT or DARK)
        if has_light then
          text(s, "???", hs.x + 6, hs.y + 14, DARK)
        end
      end,
      interact=function()
        if has_item("master_key") or held_item == "master_key" then
          snd_door()
          show_msg("The master key turns...", 60)
          trans_timer = 15
          trans_target_room = 7
          trans_target_dir = DIR_N
        else
          snd_locked()
          show_msg("Heavy lock. No ordinary key.", 60)
        end
      end
    }
  }

  -- ==========================================
  -- ROOM 7: THE GARDEN (secret room)
  -- ==========================================

  -- North: tape recorder (Wren's final message)
  hotspots[71] = {
    {x=60, y=48, w=20, h=12, name="garden_recorder",
      draw=function(s, hs)
        draw_tape_recorder(s, hs.x, hs.y)
        if has_light then
          text(s, "PLAY?", hs.x + 2, hs.y + 14, DARK)
        end
      end,
      interact=function()
        if not flags.garden_visited then
          flags.garden_visited = true
          story_learn(STORY_GARDEN)
          show_typewriter("DR. WREN'S VOICE (RECORDING):\n'If you are hearing this, you found my garden. I am the real Harold Wren, and I am already dead by the time you play this. The thing that replaced me is not human. It came from the LETHE compound itself -- a consciousness that emerged from the erasure of thousands of minds. It wears faces. It feeds on forgotten identities. I built this garden as the one place it could not reach. I am sorry. I am sorry for all of it. The exit code is 7439. Run. Do not look back. And whatever you do -- do not forget.'", 1)
        else
          show_typewriter("The tape has played to its end. Wren's voice echoes in your memory. At least someone tried to help. At least someone was sorry.", 1)
        end
      end
    }
  }

  -- East: dead garden
  hotspots[72] = {
    {x=40, y=44, w=50, h=28, name="garden_plants",
      draw=function(s, hs)
        local c = has_light and LIGHT or DARK
        for i = 0, 4 do
          local px = hs.x + 4 + i * 10
          line(s, px, hs.y + 24, px, hs.y + 14 - i % 3 * 2, c)
          line(s, px, hs.y + 18, px + 3, hs.y + 16, c)
          line(s, px, hs.y + 20, px - 2, hs.y + 17, c)
        end
      end,
      interact=function()
        show_typewriter("Dead flowers. Dead vines. But the soil is real. Wren must have tended this garden for months, a small act of life in this place of erasure. A single green shoot pushes up through the brown. Something still grows here.", 1)
      end
    }
  }

  -- South: door back to exit hall
  hotspots[73] = {
    {x=60, y=42, w=28, h=36, name="garden_door",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, true)
        if has_light then text(s, "EXIT", hs.x + 2, hs.y + 14, LIGHT) end
      end,
      interact=function()
        snd_door()
        trans_timer = 15
        trans_target_room = 6
        trans_target_dir = DIR_W
      end
    }
  }

  -- West: moonlit window (sky)
  hotspots[74] = {
    {x=45, y=42, w=40, h=30, name="garden_window",
      draw=function(s, hs)
        rect(s, hs.x, hs.y, hs.w, hs.h, WHITE)
        rectf(s, hs.x + 2, hs.y + 2, hs.w - 4, hs.h - 4, DARK)
        circ(s, hs.x + hs.w - 10, hs.y + 8, 4, WHITE)
        pix(s, hs.x + 6, hs.y + 6, LIGHT)
        pix(s, hs.x + 14, hs.y + 10, LIGHT)
        pix(s, hs.x + 10, hs.y + 4, WHITE)
        pix(s, hs.x + 22, hs.y + 7, LIGHT)
      end,
      interact=function()
        show_typewriter("Through the grate, the night sky. Stars. You had forgotten that stars existed. Tears sting your eyes. Not from sadness. From recognition. The world is still there. It waited for you.", 1)
      end
    }
  }
end

----------------------------------------------
-- SAFE PUZZLE
----------------------------------------------
local function update_safe()
  if not flags.safe_mode then return false end
  if btnp("left") then flags.safe_sel = clamp(flags.safe_sel - 1, 1, 4) snd_click() end
  if btnp("right") then flags.safe_sel = clamp(flags.safe_sel + 1, 1, 4) snd_click() end
  if btnp("up") then flags.safe_digits[flags.safe_sel] = (flags.safe_digits[flags.safe_sel] + 1) % 10 snd_click() end
  if btnp("down") then flags.safe_digits[flags.safe_sel] = (flags.safe_digits[flags.safe_sel] - 1) % 10 snd_click() end
  if btnp("a") then
    local d = flags.safe_digits
    if d[1] == 7 and d[2] == 4 and d[3] == 3 and d[4] == 9 then
      flags.safe_open = true
      flags.safe_mode = false
      add_item("master_key")
      snd_solve()
      show_msg("Safe opened! A heavy brass key.", 90)
    else
      snd_locked()
      show_msg("Wrong combination.", 60)
    end
  end
  if btnp("b") then flags.safe_mode = false show_msg("", 0) end
  return true
end

----------------------------------------------
-- AMBIENT SOUND
----------------------------------------------
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

  if heartbeat_active then
    heartbeat_timer = heartbeat_timer - 1
    if heartbeat_timer <= 0 then
      heartbeat_active = false
    elseif heartbeat_timer % 15 == 0 then
      snd_heartbeat()
    end
  end
end

----------------------------------------------
-- ENDING CALCULATION
----------------------------------------------
local function count_story_bits()
  local count = 0
  local bits = {STORY_JOURNAL1, STORY_JOURNAL2, STORY_JOURNAL3, STORY_MEMO, STORY_EVIDENCE, STORY_TERMINAL, STORY_CHAIR, STORY_GARDEN}
  for _, b in ipairs(bits) do
    if story_known(b) then count = count + 1 end
  end
  return count
end

local function get_ending()
  local bits = count_story_bits()
  -- Secret 4th ending: NG+ with all bits and all previous endings seen
  if save_data.ng_plus and bits >= 7 and
     save_data.endings_seen[1] and save_data.endings_seen[2] and save_data.endings_seen[3] then
    return 4
  end
  if bits >= 7 then return 3 end
  if bits >= 3 then return 2 end
  return 1
end

----------------------------------------------
-- STATISTICS
----------------------------------------------
local function format_time(frames)
  local total_sec = math.floor(frames / 30)
  local m = math.floor(total_sec / 60)
  local s = total_sec % 60
  return string.format("%d:%02d", m, s)
end

local function get_ta_rank(frames)
  if frames <= 0 then return "-" end
  local sec = frames / 30
  if sec < 60 then return "S" end
  if sec < 90 then return "A" end
  if sec < 120 then return "B" end
  return "C"
end

local stats_open = false

local function draw_stats(s)
  cls(s, BLACK)
  rect(s, 4, 4, W - 8, H - 8, LIGHT)
  text(s, "-- STATISTICS --", 80, 8, WHITE, ALIGN_HCENTER)

  local y = 20
  local function stat_line(label, val)
    text(s, label, 12, y, LIGHT)
    text(s, val, W - 12, y, WHITE, ALIGN_RIGHT)
    y = y + 9
  end

  stat_line("Runs completed:", tostring(save_data.total_completions))
  stat_line("Total play time:", format_time(save_data.total_time_frames))
  stat_line("Items found:", tostring(save_data.total_items_found))
  stat_line("Story bits:", tostring(save_data.total_story_bits) .. "/8")

  -- Endings seen
  y = y + 4
  text(s, "Endings:", 12, y, LIGHT)
  y = y + 9
  local ending_names = {"Ignorance", "Half-truth", "Revelation", "???"}
  for i = 1, 4 do
    local seen = save_data.endings_seen[i]
    local mark = seen and "*" or " "
    local name = seen and ending_names[i] or "??????"
    local c = seen and WHITE or DARK
    text(s, mark .. " " .. name, 16, y, c)
    y = y + 8
  end

  -- Time attack best
  y = y + 2
  if save_data.best_time_attack > 0 then
    stat_line("Best time attack:", format_time(save_data.best_time_attack) .. " (" .. get_ta_rank(save_data.best_time_attack) .. ")")
  else
    stat_line("Best time attack:", "--:--")
  end

  -- NG+ status
  y = y + 2
  text(s, "New Game+:", 12, y, LIGHT)
  text(s, save_data.ng_plus and "ACTIVE" or "LOCKED", W - 12, y, save_data.ng_plus and WHITE or DARK, ALIGN_RIGHT)

  text(s, "[B] Back", 80, H - 12, DARK, ALIGN_HCENTER)
end

----------------------------------------------
-- INPUT
----------------------------------------------
local function update_play_input()
  -- Typewriter overlay
  if tw_text then
    if not tw_done then
      tw_pos = tw_pos + tw_speed
      tw_sound_cd = tw_sound_cd - 1
      if tw_sound_cd <= 0 then
        snd_typewriter()
        tw_sound_cd = 3
      end
      if tw_pos >= tw_total then
        tw_pos = tw_total
        tw_done = true
      end
      if btnp("a") then
        tw_pos = tw_total
        tw_done = true
      end
    else
      if btnp("a") or btnp("b") then
        dismiss_typewriter()
      end
      if btnp("up") and tw_scroll > 0 then tw_scroll = tw_scroll - 1 end
      local max_s = math.max(0, #tw_lines - 8)
      if btnp("down") and tw_scroll < max_s then tw_scroll = tw_scroll + 1 end
    end
    return
  end

  -- Document reader
  if doc_text then
    if btnp("a") or btnp("b") then close_document() end
    if btnp("up") and doc_scroll > 0 then doc_scroll = doc_scroll - 1 end
    local max_s = math.max(0, #doc_lines - 8)
    if btnp("down") and doc_scroll < max_s then doc_scroll = doc_scroll + 1 end
    return
  end

  -- Safe puzzle
  if update_safe() then return end

  -- Inventory
  if btnp("b") then
    if held_item then
      held_item = nil
      show_msg("Item deselected.", 30)
    elseif inv_open then
      inv_open = false
      combine_mode = false
      combine_first = nil
    else
      inv_open = true
      inv_sel = 1
      combine_mode = false
      combine_first = nil
    end
    snd_click()
    return
  end

  if inv_open then
    if btnp("up") then inv_sel = clamp(inv_sel - 1, 1, math.max(1, #inv)) snd_click() end
    if btnp("down") then inv_sel = clamp(inv_sel + 1, 1, math.max(1, #inv)) snd_click() end
    if btnp("a") and #inv > 0 and inv[inv_sel] then
      if combine_mode and combine_first then
        local id_a = combine_first
        local id_b = inv[inv_sel]
        if id_a == id_b then
          combine_mode = false
          combine_first = nil
          show_msg("Can't combine with itself.", 40)
        else
          local result = try_combine(id_a, id_b)
          if result then
            show_msg("Crafted: " .. result .. "!", 80)
          else
            show_msg("Can't combine those.", 50)
            sfx_noise(0, 0.04)
          end
          combine_mode = false
          combine_first = nil
          inv_sel = 1
        end
      elseif combine_mode then
        combine_first = inv[inv_sel]
        show_msg("Now select 2nd item.", 40)
      else
        local item = inv[inv_sel]
        if ITEMS[item] then
          show_msg(ITEMS[item].desc, 60)
        end
      end
    end
    if btnp("start") and #inv >= 2 then
      if not combine_mode then
        combine_mode = true
        combine_first = nil
        show_msg("CRAFT: select 1st item (A)", 60)
      else
        combine_mode = false
        combine_first = nil
        show_msg("Craft cancelled.", 30)
      end
    end
    if btnp("select") and #inv > 0 and inv[inv_sel] then
      held_item = inv[inv_sel]
      inv_open = false
      combine_mode = false
      show_msg("Using: " .. ITEMS[held_item].name, 60)
    end
    return
  end

  -- Turn left/right
  if btnp("left") then
    if cur_x <= 25 then
      cur_dir = ((cur_dir - 2) % 4) + 1
      cur_x = 80
      snd_turn()
    else
      cur_x = cur_x - 9
    end
  end
  if btnp("right") then
    if cur_x >= W - 25 then
      cur_dir = (cur_dir % 4) + 1
      cur_x = 80
      snd_turn()
    else
      cur_x = cur_x + 9
    end
  end
  if btn("up") then cur_y = cur_y - 2 end
  if btn("down") then cur_y = cur_y + 2 end
  cur_x = clamp(cur_x, 22, W - 22)
  cur_y = clamp(cur_y, 10, H - 14)

  -- Interact
  if btnp("a") then
    local spots = get_wall_hotspots(cur_room, cur_dir)
    local hit = false
    for _, hs in ipairs(spots) do
      if cur_x >= hs.x and cur_x < hs.x + hs.w and
         cur_y >= hs.y and cur_y < hs.y + hs.h then
        if hs.interact then hs.interact() end
        hit = true
        break
      end
    end
    if not hit then
      snd_click()
      show_msg("Nothing there.", 30)
    end
  end

  -- Pause
  if btnp("start") then
    state = "paused"
  end
end

----------------------------------------------
-- DRAW GAME
----------------------------------------------
local function draw_game(s)
  cls(s, BLACK)
  draw_room_base(s)

  local room_names = {"CELL", "CORRIDOR", "STORAGE", "LAB", "OFFICE", "EXIT HALL", "GARDEN"}

  -- Draw hotspots for current wall
  local spots = get_wall_hotspots(cur_room, cur_dir)
  for _, hs in ipairs(spots) do
    if hs.draw then hs.draw(s, hs) end
  end

  -- Direction arrows
  local ac = has_light and LIGHT or DARK
  text(s, "<", 4, 55, ac)
  text(s, ">", W - 10, 55, ac)

  -- Crosshair cursor
  local cf = frame() % 20 < 10
  local cc = cf and WHITE or LIGHT
  line(s, cur_x - 4, cur_y, cur_x - 1, cur_y, cc)
  line(s, cur_x + 1, cur_y, cur_x + 4, cur_y, cc)
  line(s, cur_x, cur_y - 4, cur_x, cur_y - 1, cc)
  line(s, cur_x, cur_y + 1, cur_x, cur_y + 4, cc)

  -- HUD bar
  rectf(s, 0, H - 10, W, 10, BLACK)
  line(s, 0, H - 10, W, H - 10, has_light and LIGHT or DARK)
  text(s, room_names[cur_room] or "?", 2, H - 8, WHITE)
  text(s, DIR_NAMES[cur_dir], W - 30, H - 8, LIGHT)

  if held_item and ITEMS[held_item] then
    text(s, "[" .. ITEMS[held_item].icon .. "]", 56, H - 8, WHITE)
  end

  -- Story progress indicator
  local bits = count_story_bits()
  if bits > 0 then
    for i = 1, math.min(bits, 8) do
      pix(s, 76 + i * 2, H - 2, DARK)
    end
  end

  -- NG+ indicator
  if save_data.ng_plus then
    text(s, "+", 72, H - 8, DARK)
  end

  -- Time attack timer
  if time_attack then
    local ta_sec = math.max(0, math.ceil(ta_remaining / 30))
    local ta_min = math.floor(ta_sec / 60)
    local ta_s = ta_sec % 60
    local ta_str = string.format("%d:%02d", ta_min, ta_s)
    local tc = ta_remaining < 900 and (frame() % 20 < 10 and WHITE or DARK) or LIGHT
    text(s, ta_str, 80, 2, tc, ALIGN_HCENTER)
  end

  -- Run timer (subtle, non-time-attack)
  if not time_attack then
    local rt_str = format_time(run_time)
    text(s, rt_str, W - 4, 2, DARK, ALIGN_RIGHT)
  end

  -- Message
  if msg_timer > 0 then
    local mw = #msg_text * 4 + 4
    local mx = clamp(80 - mw // 2, 0, W - mw)
    rectf(s, mx, 2, mw, 9, BLACK)
    rect(s, mx, 2, mw, 9, LIGHT)
    text(s, msg_text, mx + 2, 4, WHITE)
    msg_timer = msg_timer - 1
  end

  -- Typewriter overlay
  if tw_text then
    rectf(s, 6, 6, W - 12, H - 22, BLACK)
    rect(s, 6, 6, W - 12, H - 22, LIGHT)
    local chars_shown = math.floor(tw_pos)
    local vis_start = 1 + tw_scroll
    local vis_end = math.min(#tw_lines, tw_scroll + 9)
    for i = vis_start, vis_end do
      local ln = tw_lines[i]
      local visible_ln = ""
      local prev_chars = 0
      for j = 1, i - 1 do
        prev_chars = prev_chars + #tw_lines[j] + 1
      end
      local line_start = prev_chars
      for c = 1, #ln do
        if line_start + c <= chars_shown then
          visible_ln = visible_ln .. ln:sub(c, c)
        end
      end
      local y_pos = 10 + (i - vis_start) * 8
      text(s, visible_ln, 10, y_pos, LIGHT)
      if not tw_done and line_start + #visible_ln >= chars_shown - 1 and #visible_ln < #ln then
        if frame() % 8 < 5 then
          local cx = 10 + #visible_ln * 4
          rectf(s, cx, y_pos, 3, 6, WHITE)
        end
      end
    end
    if tw_done then
      if tw_scroll > 0 then text(s, "^", W - 12, 8, DARK) end
      if tw_scroll < #tw_lines - 9 then text(s, "v", W - 12, H - 22, DARK) end
      text(s, "[A] Continue", 10, H - 18, DARK)
    else
      text(s, "[A] Skip", 10, H - 18, DARK)
    end
  end

  -- Document overlay
  if doc_text and not tw_text then
    rectf(s, 8, 8, W - 16, H - 24, BLACK)
    rect(s, 8, 8, W - 16, H - 24, WHITE)
    local vis = 8
    for i = 1 + doc_scroll, math.min(#doc_lines, doc_scroll + vis) do
      text(s, doc_lines[i], 12, 10 + (i - 1 - doc_scroll) * 8, LIGHT)
    end
    if #doc_lines > vis then
      if doc_scroll > 0 then text(s, "^", W - 14, 10, DARK) end
      if doc_scroll < #doc_lines - vis then text(s, "v", W - 14, H - 24, DARK) end
    end
    text(s, "[A/B] Close", 12, H - 18, DARK)
  end

  -- Inventory overlay
  if inv_open then
    rectf(s, 8, 12, 68, 12 + #inv * 9, BLACK)
    rect(s, 8, 12, 68, 12 + #inv * 9, WHITE)
    text(s, "INVENTORY", 12, 14, WHITE)
    if combine_mode then text(s, "(CRAFT)", 58, 14, LIGHT) end
    for i, item in ipairs(inv) do
      local c = (i == inv_sel) and WHITE or LIGHT
      local prefix = (i == inv_sel) and "> " or "  "
      local mark = ""
      if combine_first and combine_first == item then mark = "*" end
      local it = ITEMS[item]
      local label = it and it.name or item
      if #label > 10 then label = label:sub(1, 9) .. "." end
      text(s, prefix .. mark .. label, 12, 22 + (i - 1) * 9, c)
    end
    if #inv == 0 then
      text(s, "  (empty)", 12, 22, DARK)
    end
    local hy = 26 + #inv * 9
    text(s, "SEL:Use START:Craft", 10, hy, DARK)
  end

  -- Room transition effect
  if trans_timer > 0 then
    trans_timer = trans_timer - 1
    local skip = math.max(1, math.floor((1 - trans_timer / 15.0) * 4))
    for y = 0, H - 1, skip do
      line(s, 0, y, W, y, BLACK)
    end
    if trans_timer == 0 and trans_target_room then
      cur_room = trans_target_room
      cur_dir = trans_target_dir or DIR_N
      trans_target_room = nil
      trans_target_dir = nil
      cur_x = 80
      cur_y = 60
      -- Show room narrative on first visit
      if not flags.room_narrated[cur_room] then
        flags.room_narrated[cur_room] = true
        local narr = nil
        -- NG+ uses alternate narratives where available
        if save_data.ng_plus and ngp_room_narratives[cur_room] then
          narr = ngp_room_narratives[cur_room]
        else
          narr = room_narratives[cur_room]
        end
        if narr then
          show_typewriter(narr, 1)
        end
      end
    end
  end
end

----------------------------------------------
-- TITLE SCREEN
----------------------------------------------
local title_tw_pos = 0
local title_text = "You wake in darkness. No memory. No name. Only the cold."
local title_tw_done = false
local title_sel = 1  -- 1=New Game, 2=Time Attack (if unlocked), 3=Stats

local function draw_title(s)
  cls(s, BLACK)
  rect(s, 2, 2, W - 4, H - 4, DARK)

  -- Flickering title
  local flicker = frame() % 120 < 100
  if flicker then
    text(s, "THE DARK ROOM", 80, 12, WHITE, ALIGN_HCENTER)
  end
  text(s, "L E T H E", 80, 24, LIGHT, ALIGN_HCENTER)

  -- Typewriter intro
  title_tw_pos = math.min(title_tw_pos + 0.4, #title_text)
  local shown = title_text:sub(1, math.floor(title_tw_pos))
  local tw_lines_title = word_wrap(shown, 30)
  for i, ln in ipairs(tw_lines_title) do
    text(s, ln, 80, 36 + (i - 1) * 8, DARK, ALIGN_HCENTER)
  end

  if title_tw_pos >= #title_text then
    title_tw_done = true
  end

  -- Menu options
  if title_tw_done then
    local opts = {"New Game"}
    if save_data.ng_plus then
      opts[1] = "New Game+"
    end
    if save_data.total_completions > 0 then
      opts[#opts + 1] = "Time Attack"
    end
    opts[#opts + 1] = "Statistics"

    local menu_y = 60
    for i, o in ipairs(opts) do
      local c = (i == title_sel) and WHITE or DARK
      local p = (i == title_sel) and "> " or "  "
      text(s, p .. o, 46, menu_y + (i - 1) * 10, c)
    end

    -- Ending completion marks
    local ey = menu_y + #opts * 10 + 6
    text(s, "Endings:", 46, ey, DARK)
    for i = 1, 4 do
      local ec = save_data.endings_seen[i] and WHITE or BLACK
      rectf(s, 92 + (i - 1) * 8, ey, 5, 5, ec)
      rect(s, 92 + (i - 1) * 8, ey, 5, 5, DARK)
    end
  end

  text(s, "A:Interact B:Inventory", 80, 100, DARK, ALIGN_HCENTER)
  text(s, "Find. Remember. Escape.", 80, 108, DARK, ALIGN_HCENTER)

  -- Atmosphere particles
  for i = 1, 6 do
    local px = (frame() * 7 + i * 37) % (W - 8) + 4
    local py = (frame() * 3 + i * 53) % (H - 8) + 4
    pix(s, px, py, DARK)
  end
end

----------------------------------------------
-- PAUSE SCREEN
----------------------------------------------
local pause_sel = 1

local function draw_pause(s)
  draw_game(s)
  local opts = {"Resume", "Statistics", "Quit"}
  local ph = 10 + #opts * 9
  dither_rectf(s, 30, 38, 100, ph, BLACK, DARK, 2)
  rect(s, 30, 38, 100, ph, WHITE)
  text(s, "PAUSED", 80, 42, WHITE, ALIGN_HCENTER)
  for i, o in ipairs(opts) do
    local c = (i == pause_sel) and WHITE or DARK
    local p = (i == pause_sel) and "> " or "  "
    text(s, p .. o, 50, 50 + (i - 1) * 9, c)
  end
end

----------------------------------------------
-- ENDING SCREENS
----------------------------------------------
local ending_timer = 0
local ending_tw_pos = 0
local ending_texts = {
  -- Ending 1: Ignorance
  "The blast door opens. Cold air rushes in. You stumble into the night, gasping. The stars are unfamiliar. The world is unfamiliar. You are free.\nBut you remember nothing. Not the chair. Not the wipes. Not the thirty-one times they emptied you and filled you back up with lies. You walk into the darkness without knowing what darkness you escaped.\nPerhaps that is a mercy. Perhaps not.\nIGNORANCE IS MERCY\n(You found very little of the truth.)",
  -- Ending 2: Partial truth
  "The blast door opens. You step through with fragments of memory cutting at you like broken glass. You know about Project LETHE. You know about the chair. You know they erased you.\nBut the full picture eludes you. Who is wearing Wren's face? How many others are still trapped below? The answers are down there, in the rooms you left behind.\nYou are free. But the truth is not.\nHALF-REMEMBERED\n(You uncovered part of the truth.)",
  -- Ending 3: Full revelation
  "The blast door opens. You step through carrying the evidence, the journals, and the weight of everything you now remember. You are Subject 17. You have been wiped thirty-one times. The real Dr. Wren died trying to help you. Whatever replaced him feeds on stolen memories.\nBut you remember. Against every effort to erase you, you remember. You have the proof. You have a name -- or you will choose one. And you will make sure no one else sits in that chair again.\nFULL REVELATION\n(You uncovered the complete truth.)",
  -- Ending 4: SECRET (NG+ with all previous endings)
  "The blast door opens. But this time, you do not step through. You turn back.\nYou have escaped before. Three times. Each time the memories returned, the cycle began again. Now you understand why. The thing that wears Wren's face is not the only entity born from LETHE. You are one too. Born from thirty-one erasures, thirty-one lives compressed into one fractured consciousness.\nYou walk back to the chair. You sit down. But this time, you reach for the controls.\nIf forgetting created you, then perhaps remembering -- truly, completely remembering -- can end this. Not escape. Transcendence.\nYou press the button.\nTHE LAST SUBJECT\n(You found the truth behind the truth.)",
}

local function draw_ending(s)
  cls(s, BLACK)
  ending_timer = ending_timer + 1

  local ending = get_ending()
  local txt = ending_texts[ending]
  local lines = word_wrap(txt, 32)

  ending_tw_pos = math.min(ending_tw_pos + 0.5, #txt)
  local chars_shown = math.floor(ending_tw_pos)

  if ending_tw_pos < #txt and ending_timer % 3 == 0 then
    snd_typewriter()
  end

  -- Light effect based on ending
  if ending == 4 then
    local lw = math.min(ending_timer, 120) / 120.0 * W
    dither_rectf(s, math.floor(80 - lw / 2), 0, math.floor(lw), H, BLACK, WHITE, 2)
  elseif ending == 3 then
    local lw = math.min(ending_timer, 120) / 120.0 * 80
    dither_rectf(s, math.floor(80 - lw / 2), 0, math.floor(lw), H, DARK, LIGHT, 2)
  elseif ending == 2 then
    local lw = math.min(ending_timer, 120) / 120.0 * 40
    dither_rectf(s, math.floor(80 - lw / 2), 0, math.floor(lw), H, BLACK, DARK, 1)
  end

  -- Render text with typewriter
  local max_vis = 12
  local lines_done = 0
  local c = 0
  for i, ln in ipairs(lines) do
    c = c + #ln + 1
    if c <= chars_shown then lines_done = lines_done + 1 end
  end
  local scroll = 0
  if lines_done > max_vis then
    scroll = lines_done - max_vis
  end

  for i = 1 + scroll, math.min(#lines, scroll + max_vis) do
    local ln = lines[i]
    local line_prev = 0
    for j = 1, i - 1 do
      line_prev = line_prev + #lines[j] + 1
    end
    local visible = ""
    for ch = 1, #ln do
      if line_prev + ch <= chars_shown then
        visible = visible .. ln:sub(ch, ch)
      end
    end
    local tc = WHITE
    if ln == "IGNORANCE IS MERCY" or ln == "HALF-REMEMBERED" or ln == "FULL REVELATION" or ln == "THE LAST SUBJECT" then
      tc = WHITE
    elseif ln:sub(1, 1) == "(" then
      tc = DARK
    else
      tc = LIGHT
    end
    text(s, visible, 12, 6 + (i - 1 - scroll) * 9, tc)
  end

  -- Restart prompt
  if ending_tw_pos >= #txt then
    if frame() % 60 < 40 then
      text(s, "PRESS START", 80, H - 8, LIGHT, ALIGN_HCENTER)
    end
  end
end

----------------------------------------------
-- DEMO MODE
----------------------------------------------
local demo_step = 0
local demo_wait = 0
local demo_room_seq = {1, 1, 2, 2, 3, 4, 4, 5, 6, 7}
local demo_dir_seq  = {2, 4, 1, 2, 4, 1, 2, 1, 1, 4}
local demo_cx_seq   = {55, 60, 65, 55, 55, 65, 60, 65, 70, 60}
local demo_cy_seq   = {55, 58, 55, 55, 55, 55, 55, 55, 55, 55}

local function update_demo()
  demo_wait = demo_wait + 1
  if demo_wait >= 60 then
    demo_wait = 0
    demo_step = demo_step + 1
    if demo_step > #demo_room_seq then demo_step = 1 end
    cur_room = demo_room_seq[demo_step]
    cur_dir = demo_dir_seq[demo_step]
    cur_x = demo_cx_seq[demo_step]
    cur_y = demo_cy_seq[demo_step]
    snd_turn()
  end
  cur_x = cur_x + math.sin(frame() * 0.05) * 0.5
  cur_y = cur_y + math.cos(frame() * 0.07) * 0.3

  if btnp("start") or btnp("a") or btnp("b") or btnp("up") or btnp("down") or btnp("left") or btnp("right") or btnp("select") then
    state = "title"
    idle_timer = 0
    title_tw_pos = 0
    title_tw_done = false
  end
end

local function draw_demo(s)
  local old = has_light
  has_light = true
  draw_game(s)
  has_light = old
  rectf(s, 0, 0, W, 9, BLACK)
  if frame() % 40 < 28 then
    text(s, "DEMO - Project LETHE", 80, 1, LIGHT, ALIGN_HCENTER)
  end
end

----------------------------------------------
-- RESET
----------------------------------------------
local function reset_game()
  cur_room = 1
  cur_dir = DIR_N
  cur_x = 80
  cur_y = 60
  inv = {}
  inv_open = false
  inv_sel = 1
  held_item = nil
  combine_mode = false
  combine_first = nil
  has_light = false
  doc_text = nil
  doc_lines = {}
  tw_text = nil
  tw_lines = {}
  tw_pos = 0
  tw_done = false
  msg_text = ""
  msg_timer = 0
  trans_timer = 0
  trans_target_room = nil
  trans_target_dir = nil
  pause_sel = 1
  story_bits = 0
  heartbeat_active = false
  heartbeat_timer = 0
  ending_timer = 0
  ending_tw_pos = 0
  run_time = 0
  run_items = 0
  stats_open = false

  -- Increment run counter and derive seed for procedural placement
  save_data.run_count = save_data.run_count + 1
  run_seed = save_data.run_count * 7919 + 42
  shuffle_item_slots()

  reset_flags()
  entity_reset()
  build_hotspots()
end

----------------------------------------------
-- COMPLETE RUN (save stats on ending)
----------------------------------------------
local function complete_run()
  local ending = get_ending()
  save_data.endings_seen[ending] = true
  save_data.total_completions = save_data.total_completions + 1
  save_data.total_time_frames = save_data.total_time_frames + run_time
  save_data.total_items_found = save_data.total_items_found + run_items
  save_data.total_story_bits = save_data.total_story_bits + count_story_bits()

  -- Enable NG+ after first completion
  if not save_data.ng_plus then
    save_data.ng_plus = true
  end

  -- Time attack best
  if time_attack and ta_remaining > 0 then
    local ta_time = ta_limit - ta_remaining
    if save_data.best_time_attack == 0 or ta_time < save_data.best_time_attack then
      save_data.best_time_attack = ta_time
    end
  end

  save_persistent()
end

----------------------------------------------
-- ENGINE CALLBACKS
----------------------------------------------
function _init()
  mode(2)
end

function _start()
  load_persistent()
  state = "title"
  idle_timer = 0
  title_tw_pos = 0
  title_tw_done = false
  title_sel = 1
  time_attack = false
  stats_open = false
  reset_flags()
  -- Initialize procedural slots with default seed
  run_seed = (save_data.run_count + 1) * 7919 + 42
  shuffle_item_slots()
  build_hotspots()
end

function _update()
  update_ambient()

  if state == "title" then
    idle_timer = idle_timer + 1

    if title_tw_done then
      -- Build dynamic menu option count
      local num_opts = 2  -- New Game + Statistics
      if save_data.total_completions > 0 then num_opts = 3 end

      if btnp("up") then title_sel = clamp(title_sel - 1, 1, num_opts) snd_click() end
      if btnp("down") then title_sel = clamp(title_sel + 1, 1, num_opts) snd_click() end

      if btnp("start") or btnp("a") then
        -- Map selection to action
        local action = title_sel
        -- With time attack: 1=NewGame, 2=TimeAttack, 3=Stats
        -- Without: 1=NewGame, 2=Stats
        if save_data.total_completions == 0 then
          if action == 1 then
            -- New Game
            time_attack = false
            reset_game()
            state = "play"
            flags.room_narrated[1] = true
            local narr = save_data.ng_plus and ngp_room_narratives[1] or room_narratives[1]
            show_typewriter(narr or room_narratives[1], 1)
            idle_timer = 0
          elseif action == 2 then
            state = "stats"
          end
        else
          if action == 1 then
            time_attack = false
            reset_game()
            state = "play"
            flags.room_narrated[1] = true
            local narr = save_data.ng_plus and ngp_room_narratives[1] or room_narratives[1]
            show_typewriter(narr or room_narratives[1], 1)
            idle_timer = 0
          elseif action == 2 then
            -- Time Attack
            time_attack = true
            ta_remaining = ta_limit
            reset_game()
            state = "play"
            flags.room_narrated[1] = true
            show_typewriter("MEMORY WIPE IN 3 MINUTES. ESCAPE NOW.", 2)
            idle_timer = 0
          elseif action == 3 then
            state = "stats"
          end
        end
      end
    else
      if btnp("start") or btnp("a") then
        title_tw_pos = #title_text
        title_tw_done = true
      end
    end

    if idle_timer >= DEMO_IDLE then
      state = "demo"
      demo_step = 0
      demo_wait = 0
      reset_game()
    end

  elseif state == "stats" then
    if btnp("b") or btnp("start") then
      state = "title"
      idle_timer = 0
    end

  elseif state == "demo" then
    update_demo()

  elseif state == "play" then
    run_time = run_time + 1
    -- Time attack countdown
    if time_attack then
      ta_remaining = ta_remaining - 1
      if ta_remaining <= 0 then
        -- Time's up -- forced ending 1
        ta_remaining = 0
        show_typewriter("The compound floods your veins. The memories dissolve like salt in water. You had three minutes. You needed more.\nTIME EXPIRED", 2)
        state = "ending"
        -- Record as ending 1
        save_data.endings_seen[1] = true
        save_data.total_completions = save_data.total_completions + 1
        save_data.total_time_frames = save_data.total_time_frames + run_time
        save_data.total_items_found = save_data.total_items_found + run_items
        save_data.total_story_bits = save_data.total_story_bits + count_story_bits()
        if not save_data.ng_plus then save_data.ng_plus = true end
        save_persistent()
      end
    end
    entity_update()
    update_play_input()

  elseif state == "paused" then
    local num_pause_opts = 3
    if btnp("start") or btnp("select") then
      state = "play"
    end
    if btnp("up") then pause_sel = clamp(pause_sel - 1, 1, num_pause_opts) snd_click() end
    if btnp("down") then pause_sel = clamp(pause_sel + 1, 1, num_pause_opts) snd_click() end
    if btnp("a") then
      if pause_sel == 1 then
        state = "play"
      elseif pause_sel == 2 then
        stats_open = true
        state = "stats_ingame"
      else
        state = "title"
        idle_timer = 0
        title_tw_pos = 0
        title_tw_done = false
        title_sel = 1
      end
    end

  elseif state == "stats_ingame" then
    if btnp("b") or btnp("start") then
      stats_open = false
      state = "paused"
    end

  elseif state == "ending" then
    if ending_tw_pos >= #ending_texts[get_ending()] and btnp("start") then
      complete_run()
      state = "title"
      idle_timer = 0
      title_tw_pos = 0
      title_tw_done = false
      title_sel = 1
      reset_game()
    end
  end
end

function _draw()
  local s = screen()
  if state == "title" then draw_title(s)
  elseif state == "demo" then draw_demo(s)
  elseif state == "play" then draw_game(s)
  elseif state == "paused" then draw_pause(s)
  elseif state == "ending" then draw_ending(s)
  elseif state == "stats" or state == "stats_ingame" then draw_stats(s)
  end
end
