-- THE DARK ROOM: FRACTURED MEMORIES
-- Agent #16 - Multi-ending narrative + visual top-down map
-- Absorbs agent-07 branching story into agent-02 visual exploration
-- 160x120 | 2-bit (0-3) | mode(2) | single-file
-- D-Pad: Move | A: Interact | B: Inventory | START: Begin

----------------------------------------------------------------
-- CONSTANTS
----------------------------------------------------------------
local W = 160
local H = 120
local TILE = 8
local COLS = W / TILE   -- 20
local ROWS = H / TILE   -- 15
local S -- screen surface

-- Palette
local BLK, DRK, LIT, WHT = 0, 1, 2, 3

-- Game states
local ST_TITLE  = 0
local ST_PLAY   = 1
local ST_INV    = 2
local ST_MSG    = 3
local ST_ENDING = 4
local ST_DEMO   = 5
local ST_PAUSE  = 6

-- Tile types
local T_EMPTY = 0
local T_WALL  = 1
local T_DOOR  = 2
local T_FURN  = 3
local T_ITEM  = 4
local T_EXIT  = 5
local T_ZONE  = 6  -- interaction zone (triggers narrative actions)

----------------------------------------------------------------
-- SAFE AUDIO
----------------------------------------------------------------
local function snd_note(ch, n, dur)
  if note then note(ch, n, dur) end
end
local function snd_noise(ch, dur)
  if noise then noise(ch, dur) end
end
local function snd_tone(ch, a, b, dur)
  if tone then tone(ch, a, b, dur) end
end

local function sfx_step() snd_noise(0, 0.02) end
local function sfx_pickup() snd_tone(0, 600, 900, 0.08) end
local function sfx_door() snd_tone(0, 200, 100, 0.1); snd_noise(1, 0.05) end
local function sfx_locked() snd_tone(0, 100, 80, 0.1); snd_noise(1, 0.08) end
local function sfx_danger() snd_note(0, "C2", 0.15); snd_noise(1, 0.1) end
local function sfx_discover() snd_note(0, "E5", 0.08); snd_note(1, "G5", 0.08) end
local function sfx_ambient()
  if frame and frame() % 120 == 0 then
    snd_tone(0, 40, 50, 0.3)
  end
end

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local state = ST_TITLE
local tick = 0
local idle_timer = 0
local IDLE_MAX = 180

local player = {x=0, y=0, dir=3, anim=0}
local cur_room = 0
local inventory = {}
local flags = {}
local msg_text = ""
local msg_lines = {}
local msg_timer = 0
local blink_t = 0
local inv_sel = 0
local ending_id = nil
local ending_timer = 0
local light_radius = 3

-- Fog of war: track revealed tiles per room
local revealed = {}

-- Demo
local demo_timer = 0
local demo_dir = 0
local demo_change = 0

----------------------------------------------------------------
-- ROOM DEFINITIONS
-- 20x13 grid (top row=HUD row in draw, but map is 13 rows for tiles below HUD area)
-- #=wall .=floor D=door F=furniture I=item Z=interaction zone E=exit
----------------------------------------------------------------
local rooms = {}

-- Room 0: Dark Room (start)
rooms[0] = {
  name = "DARK ROOM",
  ambient = "C2",
  dark = true,
  map = {
    "####################",
    "#..................#",
    "#..FF..............#",
    "#..FF..............#",
    "#..................#",
    "#........ZZ........#",
    "#..................#",
    "#...........FF.....#",
    "#...........FF.....#",
    "#..................#",
    "#......Z...........#",
    "#..................#",
    "######D#############",
  },
  items = {
    {x=9, y=5, id="flashlight", name="FLASHLIGHT", found=false,
     desc="A small flashlight. It works!"},
    {x=7, y=10, id="key", name="BRASS KEY", found=false,
     desc="A small brass key from the drawer.",
     need_flag="searched_desk"},
  },
  furniture = {
    {x=3,y=2,w=2,h=2, name="BED", desc="Your bed. Sheets are messy."},
    {x=12,y=7,w=2,h=2, name="DESK", desc="Dusty desk. Drawer is jammed."},
  },
  zones = {
    {x=8, y=5, id="feel_dark", desc="Feel around in the darkness..."},
    {x=9, y=5, id="feel_dark"},
    {x=7, y=10, id="walls", desc="Scratch marks on the walls."},
  },
  doors = {
    {x=6, y=12, to_room=1, to_x=10, to_y=1, need_flag="has_light"},
  },
  transitions = {},
}

-- Room 1: Hallway (hub)
rooms[1] = {
  name = "HALLWAY",
  ambient = "D2",
  dark = false,
  map = {
    "######D#############",
    "#..................#",
    "#..................#",
    "D..................D",
    "#..................#",
    "#..................#",
    "D..................D",
    "#..................#",
    "#..................#",
    "D..................#",
    "#..................#",
    "#.........Z........#",
    "######D#############",
  },
  items = {},
  furniture = {},
  zones = {
    {x=10, y=11, id="front_door", desc="The main entrance."},
  },
  doors = {
    {x=6, y=0,  to_room=0, to_x=6,  to_y=11},
    {x=0, y=3,  to_room=2, to_x=18, to_y=6},
    {x=19,y=3,  to_room=3, to_x=1,  to_y=6},
    {x=0, y=6,  to_room=4, to_x=18, to_y=6, need_item="fuse"},
    {x=19,y=6,  to_room=5, to_x=1,  to_y=6, need_item="badge"},
    {x=0, y=9,  to_room=6, to_x=18, to_y=6, need_flag="saw_files", need_item="evidence"},
    {x=6, y=12, to_room=0, to_x=6,  to_y=1},
  },
  transitions = {},
}

-- Room 2: Laboratory
rooms[2] = {
  name = "LABORATORY",
  ambient = "E2",
  dark = false,
  map = {
    "####################",
    "#..FFF.......FFF...#",
    "#..................#",
    "#..................#",
    "#..................#",
    "#....Z.............#",
    "#..................D",
    "#..................#",
    "#..FF..............#",
    "#..FF......Z.......#",
    "#..................#",
    "#...........Z......#",
    "####################",
  },
  items = {
    {x=12, y=11, id="fuse", name="FUSE", found=false,
     desc="A spare fuse from the power panel."},
  },
  furniture = {
    {x=3,y=1,w=3,h=1, name="LAB BENCH", desc="Chemical equipment. Beakers and vials."},
    {x=13,y=1,w=3,h=1, name="MONITORS", desc="Medical monitors. Blinking red."},
    {x=3,y=8,w=2,h=2, name="CABINET", desc="Locked filing cabinet."},
  },
  zones = {
    {x=5, y=5, id="lab_equip", desc="Examine the equipment..."},
    {x=11,y=9, id="lab_cabinet", desc="Search the cabinets..."},
    {x=12,y=11,id="lab_fuse", desc="Check the power panel..."},
  },
  doors = {
    {x=19,y=6, to_room=1, to_x=1, to_y=3},
  },
  transitions = {},
}

-- Room 3: Office
rooms[3] = {
  name = "OFFICE",
  ambient = "F2",
  dark = false,
  map = {
    "####################",
    "#..............FFF.#",
    "#..............FFF.#",
    "#..................#",
    "#..................#",
    "#..Z...............#",
    "D..................#",
    "#..................#",
    "#........FFF.......#",
    "#........FFF.......#",
    "#..................#",
    "#.Z..........Z.....#",
    "####################",
  },
  items = {},
  furniture = {
    {x=15,y=1,w=3,h=2, name="DESK", desc="Paperwork. Redacted names."},
    {x=9,y=8,w=3,h=2,  name="FILE CABINET", desc="Heavy filing cabinet."},
  },
  zones = {
    {x=3, y=5, id="off_computer", desc="A computer terminal."},
    {x=2, y=11,id="off_coat", desc="A coat rack in the corner."},
    {x=14,y=11,id="off_files", desc="Filing cabinet overflow."},
  },
  doors = {
    {x=0, y=6, to_room=1, to_x=18, to_y=3},
  },
  transitions = {},
}

-- Room 4: Basement
rooms[4] = {
  name = "BASEMENT",
  ambient = "A1",
  dark = true,
  map = {
    "####################",
    "#..................#",
    "#...FFFF...........#",
    "#...FFFF...........#",
    "#..................#",
    "#......Z...........#",
    "#..................D",
    "#..................#",
    "#.Z................#",
    "#..................#",
    "#...........Z......#",
    "#..................#",
    "####################",
  },
  items = {},
  furniture = {
    {x=4,y=2,w=4,h=2, name="GENERATOR", desc="A large diesel generator."},
  },
  zones = {
    {x=7, y=5, id="bas_gen",   desc="Examine the generator..."},
    {x=2, y=8, id="bas_shelves", desc="Search the shelves..."},
    {x=12,y=10,id="bas_lockdown",desc="Control panel on the wall."},
  },
  doors = {
    {x=19,y=6, to_room=1, to_x=1, to_y=6},
  },
  transitions = {},
}

-- Room 5: Rooftop
rooms[5] = {
  name = "ROOFTOP",
  ambient = "G2",
  dark = false,
  map = {
    "####################",
    "#..................#",
    "#..................#",
    "#........FF........#",
    "#........FF........#",
    "#..................#",
    "D..................#",
    "#..................#",
    "#..................#",
    "#..........Z.......#",
    "#..................#",
    "#..Z...............#",
    "####################",
  },
  items = {
    {x=3, y=11, id="note1", name="MEMO", found=false,
     desc="'Broadcast freq controls subjects.'"},
  },
  furniture = {
    {x=9,y=3,w=2,h=2, name="ANTENNA", desc="A tall radio antenna."},
  },
  zones = {
    {x=11,y=9, id="roof_city",  desc="Look over the edge..."},
    {x=3, y=11,id="roof_antenna",desc="Check the antenna base..."},
  },
  doors = {
    {x=0, y=6, to_room=1, to_x=18, to_y=6},
  },
  transitions = {},
}

-- Room 6: Vault
rooms[6] = {
  name = "THE VAULT",
  ambient = "C1",
  dark = false,
  map = {
    "####################",
    "#..FFF..FFF..FFF...#",
    "#..................#",
    "#..................#",
    "#..................#",
    "#..................#",
    "#..................D",
    "#..................#",
    "#..................#",
    "#........Z.........#",
    "#..................#",
    "#.......Z..........#",
    "####################",
  },
  items = {},
  furniture = {
    {x=3,y=1,w=3,h=1, name="FILES A", desc="Classified project documents."},
    {x=8,y=1,w=3,h=1, name="FILES B", desc="Subject records."},
    {x=13,y=1,w=3,h=1, name="FILES C", desc="Funding and oversight."},
  },
  zones = {
    {x=9, y=9, id="vault_docs",     desc="Read classified documents..."},
    {x=8, y=11,id="vault_terminal", desc="Access the terminal..."},
  },
  doors = {
    {x=19,y=6, to_room=1, to_x=1, to_y=9},
  },
  transitions = {},
}

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------
local function has_item(id)
  for _, v in ipairs(inventory) do
    if v.id == id then return true end
  end
  return false
end

local function add_item(id, name, desc)
  if has_item(id) then return false end
  if #inventory >= 6 then return false end
  table.insert(inventory, {id=id, name=name, desc=desc})
  sfx_pickup()
  return true
end

local function remove_item(id)
  for i, v in ipairs(inventory) do
    if v.id == id then
      table.remove(inventory, i)
      return true
    end
  end
  return false
end

local function show_msg(txt)
  msg_text = txt
  msg_lines = {}
  local ln = ""
  for word in txt:gmatch("%S+") do
    if #ln + #word + 1 > 26 then
      table.insert(msg_lines, ln)
      ln = word
    else
      if #ln > 0 then ln = ln .. " " end
      ln = ln .. word
    end
  end
  if #ln > 0 then table.insert(msg_lines, ln) end
  msg_timer = 120
  state = ST_MSG
end

local function get_tile(rm, gx, gy)
  local r = rooms[rm]
  if not r then return T_WALL end
  if gy < 0 or gy > 12 or gx < 0 or gx > 19 then return T_WALL end
  local row = r.map[gy + 1]
  if not row then return T_WALL end
  local ch = row:sub(gx + 1, gx + 1)
  if ch == "#" then return T_WALL
  elseif ch == "D" then return T_DOOR
  elseif ch == "F" then return T_FURN
  elseif ch == "I" then return T_ITEM
  elseif ch == "E" then return T_EXIT
  elseif ch == "Z" then return T_ZONE
  else return T_EMPTY end
end

local function is_blocked(rm, px, py)
  local offsets = {{0,0},{5,0},{0,5},{5,5},{2,2}}
  for _, o in ipairs(offsets) do
    local gx = math.floor((px + o[1]) / TILE)
    local gy = math.floor((py + o[2]) / TILE)
    local t = get_tile(rm, gx, gy)
    if t == T_WALL or t == T_FURN then return true end
    if t == T_DOOR then
      local r = rooms[rm]
      for _, d in ipairs(r.doors or {}) do
        if d.x == gx and d.y == gy then
          -- Check door requirements
          if d.need_item and not has_item(d.need_item) then return true end
          if d.need_flag and not flags[d.need_flag] then return true end
        end
      end
    end
  end
  return false
end

-- Reveal tiles around player for fog of war
local function reveal_around(rm, pcx, pcy, radius)
  if not revealed[rm] then revealed[rm] = {} end
  local rev = revealed[rm]
  for gy = math.max(0, pcy - radius), math.min(12, pcy + radius) do
    for gx = math.max(0, pcx - radius), math.min(19, pcx + radius) do
      local dist = math.sqrt((gx - pcx)^2 + (gy - pcy)^2)
      if dist <= radius then
        local key = gy * 20 + gx
        rev[key] = true
      end
    end
  end
end

----------------------------------------------------------------
-- NARRATIVE ACTION HANDLER (from agent-07 branching story)
----------------------------------------------------------------
local function do_narrative_action(zone_id)
  -- Dark Room
  if zone_id == "feel_dark" then
    if not has_item("flashlight") then
      show_msg("Your hand finds something cold and metallic... a flashlight!")
      -- Mark item found in room data
      local r = rooms[0]
      for _, it in ipairs(r.items) do
        if it.id == "flashlight" then
          it.found = true
          add_item("flashlight", "FLASHLIGHT", "A small flashlight. It works!")
          flags.has_light = true
          light_radius = 7
        end
      end
    else
      show_msg("The beam reveals a small room. A desk, a chair, a locked door.")
      flags.has_light = true
    end
  elseif zone_id == "walls" then
    show_msg("Scratches on the wall: 'THEY ARE WATCHING. DON'T TRUST.'")
    sfx_danger()

  -- Desk interaction via furniture
  elseif zone_id == "desk_search" then
    if not flags.searched_desk then
      flags.searched_desk = true
      show_msg("Dusty desk. Drawer is jammed. Something rattles inside.")
    else
      if not has_item("key") then
        show_msg("You force it open. A small brass key falls out!")
        local r = rooms[0]
        for _, it in ipairs(r.items) do
          if it.id == "key" then it.found = true end
        end
        add_item("key", "BRASS KEY", "A small brass key.")
      else
        show_msg("The drawer is empty now.")
      end
    end

  -- Front door
  elseif zone_id == "front_door" then
    if has_item("key") and not flags.lockdown_triggered then
      ending_id = "escape"
      state = ST_ENDING
      ending_timer = 0
      snd_note(0, "C5", 0.3)
      snd_note(1, "E5", 0.3)
      return
    elseif flags.lockdown_triggered then
      show_msg("The door is sealed. Steel bolts engaged. No way out.")
      sfx_danger()
    else
      show_msg("Locked. Needs a key. There must be one somewhere.")
      sfx_locked()
    end

  -- Lab
  elseif zone_id == "lab_equip" then
    show_msg("Medical equipment. Syringes, monitors... memory experiments?")
    flags.saw_lab = true
  elseif zone_id == "lab_cabinet" then
    if not has_item("evidence") then
      show_msg("Test results with YOUR name. Subject 7: Memory Wipe Protocol.")
      add_item("evidence", "EVIDENCE", "Test results proving the conspiracy.")
      flags.found_evidence = true
    else
      show_msg("You already took the evidence files.")
    end
  elseif zone_id == "lab_fuse" then
    if not has_item("fuse") and not flags.got_fuse then
      show_msg("A spare fuse in the panel. Might be useful somewhere.")
      local r = rooms[2]
      for _, it in ipairs(r.items) do
        if it.id == "fuse" then it.found = true end
      end
      add_item("fuse", "FUSE", "A spare electrical fuse.")
      flags.got_fuse = true
    else
      show_msg("The panel is empty now.")
    end

  -- Office
  elseif zone_id == "off_files" then
    if not flags.saw_files then
      flags.saw_files = true
      show_msg("Classified files! A conspiracy spanning years. A hidden vault...")
      sfx_discover()
    else
      show_msg("The files detail a program to erase and rewrite memories.")
    end
  elseif zone_id == "off_coat" then
    if not has_item("badge") and not flags.got_badge then
      show_msg("An ID badge in the pocket! 'Dr. Null - Level 5 Access'")
      add_item("badge", "ID BADGE", "Dr. Null - Level 5 Access")
      flags.got_badge = true
    else
      show_msg("Empty coat. Nothing else here.")
    end
  elseif zone_id == "off_computer" then
    if flags.saw_files then
      show_msg("Terminal shows active subjects. You are Subject 07.")
    else
      show_msg("Password protected. Maybe there are clues elsewhere.")
    end

  -- Basement
  elseif zone_id == "bas_gen" then
    if flags.power_on then
      show_msg("Generator humming steadily. All systems operational.")
    elseif has_item("fuse") then
      remove_item("fuse")
      flags.power_on = true
      show_msg("Fuse installed! Generator roars to life. Power restored!")
      snd_note(0, "C3", 0.2)
      snd_note(1, "G3", 0.2)
    else
      show_msg("Dead generator. Fuse slot is empty. Needs a fuse.")
    end
  elseif zone_id == "bas_shelves" then
    show_msg("Old supplies. Dust everywhere. Label: 'SUBJECT HOLDING'")
  elseif zone_id == "bas_lockdown" then
    if flags.power_on and not flags.lockdown_choice then
      flags.lockdown_choice = true
      -- Activating lockdown = BAD ENDING
      flags.lockdown_triggered = true
      ending_id = "trapped"
      state = ST_ENDING
      ending_timer = 0
      snd_noise(0, 0.5)
      snd_noise(1, 0.5)
      return
    elseif not flags.power_on then
      show_msg("Control panel is dead. No power to the building.")
    else
      show_msg("The lockdown controls are fried.")
    end

  -- Roof
  elseif zone_id == "roof_city" then
    show_msg("A sprawling city below. You don't recognize anything.")
  elseif zone_id == "roof_antenna" then
    if not has_item("note1") then
      show_msg("A crumpled memo: 'Broadcast frequency controls subjects.'")
      local r = rooms[5]
      for _, it in ipairs(r.items) do
        if it.id == "note1" then it.found = true end
      end
      add_item("note1", "MEMO", "Broadcast freq controls subjects.")
    else
      show_msg("Nothing else here at the antenna base.")
    end

  -- Vault
  elseif zone_id == "vault_docs" then
    flags.read_vault = true
    show_msg("Full records of the program. Names, dates, methods. Proof.")
    sfx_discover()
  elseif zone_id == "vault_terminal" then
    if flags.read_vault and has_item("evidence") and has_item("note1") then
      -- TRUE ENDING
      ending_id = "truth"
      state = ST_ENDING
      ending_timer = 0
      snd_note(0, "C5", 0.4)
      snd_note(1, "E5", 0.4)
      return
    elseif flags.read_vault then
      show_msg("Need more evidence to transmit a credible report.")
    else
      show_msg("Terminal active. Read the documents first.")
    end
  else
    show_msg("Nothing interesting here.")
  end
end

----------------------------------------------------------------
-- INTERACTION
----------------------------------------------------------------
local function interact()
  local r = rooms[cur_room]
  local pgx = math.floor((player.x + 3) / TILE)
  local pgy = math.floor((player.y + 3) / TILE)

  -- Check zones nearby (narrative triggers)
  if r.zones then
    for _, z in ipairs(r.zones) do
      if math.abs(pgx - z.x) <= 1 and math.abs(pgy - z.y) <= 1 then
        do_narrative_action(z.id)
        return
      end
    end
  end

  -- Check items nearby
  if r.items then
    for _, it in ipairs(r.items) do
      if not it.found then
        if math.abs(pgx - it.x) <= 1 and math.abs(pgy - it.y) <= 1 then
          if it.need_flag and not flags[it.need_flag] then
            show_msg("Something here but you can't reach it yet.")
            return
          end
          it.found = true
          add_item(it.id, it.name, it.desc)
          show_msg("Found: " .. it.name .. "! " .. it.desc)
          if it.id == "flashlight" then
            flags.has_light = true
            light_radius = 7
          end
          return
        end
      end
    end
  end

  -- Check furniture nearby
  if r.furniture then
    for _, f in ipairs(r.furniture) do
      local fx2 = f.x + (f.w or 1) - 1
      local fy2 = f.y + (f.h or 1) - 1
      if pgx >= f.x - 1 and pgx <= fx2 + 1 and pgy >= f.y - 1 and pgy <= fy2 + 1 then
        -- Special: desk in dark room
        if cur_room == 0 and f.name == "DESK" then
          do_narrative_action("desk_search")
          return
        end
        show_msg(f.desc)
        return
      end
    end
  end

  -- Check doors that need keys
  if r.doors then
    for _, d in ipairs(r.doors) do
      if math.abs(pgx - d.x) <= 1 and math.abs(pgy - d.y) <= 1 then
        if d.need_item and not has_item(d.need_item) then
          show_msg("This door is locked. You need something.")
          sfx_locked()
          return
        end
        if d.need_flag and not flags[d.need_flag] then
          if d.need_flag == "has_light" then
            show_msg("Too dark to go this way. Find a light source.")
          else
            show_msg("This way is blocked. Explore more first.")
          end
          sfx_locked()
          return
        end
      end
    end
  end

  show_msg("Nothing interesting here.")
end

----------------------------------------------------------------
-- DOOR CHECKING
----------------------------------------------------------------
local function check_doors()
  local r = rooms[cur_room]
  if not r.doors then return end
  local pgx = math.floor((player.x + 3) / TILE)
  local pgy = math.floor((player.y + 3) / TILE)

  for _, d in ipairs(r.doors) do
    if pgx == d.x and pgy == d.y then
      -- Check requirements
      if d.need_item and not has_item(d.need_item) then
        -- blocked, handled by is_blocked
      elseif d.need_flag and not flags[d.need_flag] then
        -- blocked
      else
        sfx_door()
        cur_room = d.to_room
        player.x = d.to_x * TILE + 1
        player.y = d.to_y * TILE + 1
        -- Play room ambient
        local nr = rooms[cur_room]
        if nr and nr.ambient then
          snd_note(2, nr.ambient, 0.8)
        end
        return
      end
    end
  end
end

----------------------------------------------------------------
-- INIT
----------------------------------------------------------------
local function reset_game()
  cur_room = 0
  player.x = 10 * TILE + 1
  player.y = 6 * TILE + 1
  player.dir = 3
  player.anim = 0
  inventory = {}
  flags = {}
  light_radius = 3
  msg_text = ""
  msg_lines = {}
  msg_timer = 0
  ending_id = nil
  ending_timer = 0
  revealed = {}
  -- Reset items
  for ri = 0, 6 do
    local r = rooms[ri]
    if r and r.items then
      for _, it in ipairs(r.items) do it.found = false end
    end
  end
end

function _init()
  mode(2)
end

function _start()
  state = ST_TITLE
  tick = 0
  idle_timer = 0
  reset_game()
end

----------------------------------------------------------------
-- UPDATE
----------------------------------------------------------------
local function update_title()
  idle_timer = idle_timer + 1
  if btnp("start") or btnp("a") then
    state = ST_PLAY
    reset_game()
    show_msg("You wake in darkness. Head pounding. No memories.")
    snd_note(2, "C2", 0.8)
    return
  end
  if idle_timer > IDLE_MAX then
    state = ST_DEMO
    demo_timer = 0
    demo_change = 0
    demo_dir = 1
    reset_game()
    cur_room = 1 -- demo in hallway (lit room)
    player.x = 10 * TILE + 1
    player.y = 6 * TILE + 1
  end
end

local function update_play()
  local dx, dy = 0, 0
  local moved = false

  if btn("left")  then dx = -1; player.dir = 0; moved = true end
  if btn("right") then dx =  1; player.dir = 1; moved = true end
  if btn("up")    then dy = -1; player.dir = 2; moved = true end
  if btn("down")  then dy =  1; player.dir = 3; moved = true end

  if dx ~= 0 then
    if not is_blocked(cur_room, player.x + dx, player.y) then
      player.x = player.x + dx
    end
  end
  if dy ~= 0 then
    if not is_blocked(cur_room, player.x, player.y + dy) then
      player.y = player.y + dy
    end
  end

  if moved then
    player.anim = player.anim + 1
    if player.anim % 10 == 0 then sfx_step() end
  end

  sfx_ambient()
  blink_t = blink_t + 1

  -- Reveal fog of war
  local pcx = math.floor((player.x + 3) / TILE)
  local pcy = math.floor((player.y + 3) / TILE)
  local r = rooms[cur_room]
  local vis_r = light_radius
  if r.dark and not flags.has_light then vis_r = 3 end
  reveal_around(cur_room, pcx, pcy, vis_r)

  check_doors()

  if btnp("a") then interact() end

  if btnp("b") then
    if #inventory > 0 then
      state = ST_INV
      inv_sel = 0
    else
      show_msg("Inventory is empty.")
    end
  end

  if btnp("start") then
    state = ST_PAUSE
  end
end

local function update_msg()
  msg_timer = msg_timer - 1
  if msg_timer <= 0 or btnp("a") or btnp("b") then
    state = ST_PLAY
  end
end

local function update_inv()
  if btnp("up") then
    inv_sel = inv_sel - 1
    if inv_sel < 0 then inv_sel = #inventory - 1 end
  end
  if btnp("down") then
    inv_sel = inv_sel + 1
    if inv_sel >= #inventory then inv_sel = 0 end
  end
  if btnp("b") or btnp("a") then
    state = ST_PLAY
  end
end

local function update_ending()
  ending_timer = ending_timer + 1
  local threshold = ending_id == "truth" and 150 or 120
  if ending_timer > threshold and (btnp("start") or btnp("a")) then
    state = ST_TITLE
    idle_timer = 0
    reset_game()
  end
end

local function update_demo()
  demo_timer = demo_timer + 1
  demo_change = demo_change + 1

  if demo_change > 30 then
    demo_change = 0
    demo_dir = math.random(0, 3)
  end

  local dx, dy = 0, 0
  if demo_dir == 0 then dx = -1
  elseif demo_dir == 1 then dx = 1
  elseif demo_dir == 2 then dy = -1
  elseif demo_dir == 3 then dy = 1 end

  local nx = player.x + dx
  local ny = player.y + dy
  if not is_blocked(cur_room, nx, ny) then
    player.x = nx
    player.y = ny
    player.dir = demo_dir
  else
    demo_change = 30
  end
  player.anim = player.anim + 1
  blink_t = blink_t + 1

  -- Reveal in demo too
  local pcx = math.floor((player.x + 3) / TILE)
  local pcy = math.floor((player.y + 3) / TILE)
  reveal_around(cur_room, pcx, pcy, 6)

  if btnp("a") or btnp("start") then
    state = ST_TITLE
    idle_timer = 0
  end
  if demo_timer > 300 then
    state = ST_TITLE
    idle_timer = 0
  end
end

local function update_pause()
  if btnp("start") or btnp("a") then
    state = ST_PLAY
  end
end

function _update()
  tick = tick + 1
  if state == ST_TITLE then update_title()
  elseif state == ST_PLAY then update_play()
  elseif state == ST_MSG then update_msg()
  elseif state == ST_INV then update_inv()
  elseif state == ST_ENDING then update_ending()
  elseif state == ST_DEMO then update_demo()
  elseif state == ST_PAUSE then update_pause()
  end
end

----------------------------------------------------------------
-- DRAWING
----------------------------------------------------------------
local function draw_player()
  S = S or screen()
  local px = math.floor(player.x)
  local py = math.floor(player.y)

  -- Body
  rectf(S, px, py + 2, 6, 4, WHT)
  -- Head
  circf(S, px + 3, py + 1, 2, WHT)

  -- Eyes
  if player.dir == 0 then
    pix(S, px + 1, py + 1, BLK)
  elseif player.dir == 1 then
    pix(S, px + 4, py + 1, BLK)
  elseif player.dir == 2 then
    pix(S, px + 2, py, BLK)
    pix(S, px + 4, py, BLK)
  else
    pix(S, px + 2, py + 2, BLK)
    pix(S, px + 4, py + 2, BLK)
  end

  -- Legs animation
  if player.anim % 10 < 5 then
    pix(S, px + 1, py + 6, LIT)
    pix(S, px + 4, py + 6, LIT)
  else
    pix(S, px + 2, py + 6, LIT)
    pix(S, px + 3, py + 6, LIT)
  end

  -- Flashlight beam
  if flags.has_light then
    local bx, by = px + 3, py + 3
    if player.dir == 0 then
      line(S, bx, by, bx - 14, by - 3, DRK)
      line(S, bx, by, bx - 14, by + 3, DRK)
    elseif player.dir == 1 then
      line(S, bx, by, bx + 14, by - 3, DRK)
      line(S, bx, by, bx + 14, by + 3, DRK)
    elseif player.dir == 2 then
      line(S, bx, by, bx - 3, by - 14, DRK)
      line(S, bx, by, bx + 3, by - 14, DRK)
    else
      line(S, bx, by, bx - 3, by + 14, DRK)
      line(S, bx, by, bx + 3, by + 14, DRK)
    end
  end
end

local function draw_room()
  S = screen()
  cls(S, BLK)

  local r = rooms[cur_room]
  if not r then return end

  local pcx = math.floor((player.x + 3) / TILE)
  local pcy = math.floor((player.y + 3) / TILE)
  local lr = light_radius
  local is_dark = r.dark and not flags.has_light
  local rev = revealed[cur_room] or {}

  for gy = 0, 12 do
    for gx = 0, 19 do
      local px = gx * TILE
      local py = gy * TILE

      local dist = math.sqrt((gx - pcx)^2 + (gy - pcy)^2)
      local visible = true
      local dim = false
      local fog = false

      -- Check fog of war: revealed but not in current sight
      local key = gy * 20 + gx
      local was_revealed = rev[key]

      if is_dark then
        if dist > 4 then
          visible = false
          if was_revealed then fog = true end
        elseif dist > 2 then
          dim = true
        end
      elseif r.dark and flags.has_light then
        if dist > lr then
          visible = false
          if was_revealed then fog = true end
        elseif dist > lr - 2 then
          dim = true
        end
      else
        -- Lit room: use fog of war for unvisited areas
        if not was_revealed and dist > 8 then
          visible = false
        elseif not was_revealed and dist > 6 then
          dim = true
        end
      end

      if fog then
        -- Previously seen but not in current light: very dim outline
        local t = get_tile(cur_room, gx, gy)
        if t == T_WALL then
          rectf(S, px, py, TILE, TILE, DRK)
          -- faint brick
          if (gx + gy) % 3 == 0 then
            pix(S, px + 3, py + 3, BLK)
          end
        elseif t == T_DOOR then
          rectf(S, px, py, TILE, TILE, DRK)
          pix(S, px + 4, py + 3, BLK)
        end
        -- everything else stays black (floor barely visible)
      elseif visible then
        local t = get_tile(cur_room, gx, gy)

        if t == T_WALL then
          if dim then
            rectf(S, px, py, TILE, TILE, DRK)
          else
            rectf(S, px, py, TILE, TILE, LIT)
            -- Brick pattern
            if (gx + gy) % 2 == 0 then
              line(S, px, py + 3, px + TILE - 1, py + 3, DRK)
              line(S, px + 4, py, px + 4, py + 3, DRK)
            else
              line(S, px, py + 4, px + TILE - 1, py + 4, DRK)
              line(S, px + 2, py, px + 2, py + 4, DRK)
            end
          end
        elseif t == T_EMPTY or t == T_ZONE then
          local c = dim and BLK or DRK
          if c > 0 then
            rectf(S, px, py, TILE, TILE, c)
            if (gx + gy) % 4 == 0 then
              pix(S, px + 3, py + 3, BLK)
            end
          end
          -- Zone sparkle hint
          if t == T_ZONE and not dim then
            if math.floor(blink_t / 12) % 3 == 0 then
              pix(S, px + 4, py + 4, LIT)
            end
          end
        elseif t == T_DOOR then
          rectf(S, px, py, TILE, TILE, DRK)
          rectf(S, px + 2, py + 1, 4, 6, dim and DRK or LIT)
          if not dim then
            pix(S, px + 5, py + 4, WHT)
          end
        elseif t == T_FURN then
          rectf(S, px, py, TILE, TILE, DRK)
          rectf(S, px + 1, py + 1, TILE - 2, TILE - 2, dim and DRK or LIT)
        elseif t == T_ITEM then
          rectf(S, px, py, TILE, TILE, dim and BLK or DRK)
          -- Item sparkle
          local item_here = false
          if r.items then
            for _, it in ipairs(r.items) do
              if it.x == gx and it.y == gy and not it.found then
                item_here = true
              end
            end
          end
          if item_here and not dim then
            local sp = math.floor(blink_t / 8) % 4
            pix(S, px + 3 + sp, py + 2, WHT)
            pix(S, px + 2 + sp, py + 2, LIT)
            pix(S, px + 4 + sp, py + 2, LIT)
          end
        end
      end
    end
  end

  -- Furniture detail overlay
  if r.furniture then
    for _, f in ipairs(r.furniture) do
      local fx = f.x * TILE
      local fy = f.y * TILE
      local fw = (f.w or 1) * TILE
      local fh = (f.h or 1) * TILE
      local dist = math.sqrt((f.x - pcx)^2 + (f.y - pcy)^2)

      local vis = true
      local dm = false
      if is_dark then
        if dist > 4 then vis = false
        elseif dist > 2 then dm = true end
      elseif r.dark and flags.has_light then
        if dist > lr then vis = false
        elseif dist > lr - 2 then dm = true end
      end

      if vis then
        local c1 = dm and DRK or LIT
        local c2 = dm and DRK or WHT
        rectf(S, fx, fy, fw, fh, c1)
        rect(S, fx, fy, fw, fh, c2)
      end
    end
  end

  -- Draw player
  draw_player()

  -- Darkness overlay for dark rooms
  if r.dark then
    for gy = 0, 12 do
      for gx = 0, 19 do
        local dist = math.sqrt((gx - pcx)^2 + (gy - pcy)^2)
        if dist > lr then
          rectf(S, gx * TILE, gy * TILE, TILE, TILE, BLK)
        elseif dist > lr - 1 then
          local bpx = gx * TILE
          local bpy = gy * TILE
          for ddy = 0, TILE - 1, 2 do
            for ddx = 0, TILE - 1, 2 do
              if (ddx + ddy) % 4 == 0 then
                pix(S, bpx + ddx, bpy + ddy, BLK)
              end
            end
          end
        end
      end
    end
  end

  -- HUD
  rectf(S, 0, 104, W, 16, BLK)
  line(S, 0, 104, W, 104, DRK)
  text(S, r.name, 2, 106, LIT)
  text(S, "ITEMS:" .. #inventory, 100, 106, DRK)
  if math.floor(blink_t / 30) % 2 == 0 then
    text(S, "A:ACT B:INV", 2, 113, DRK)
  end
end

local function draw_title()
  S = screen()
  cls(S, BLK)

  local flick = tick % 90
  if flick < 70 or flick > 80 then
    text(S, "THE DARK ROOM", W / 2, 18, WHT, ALIGN_CENTER)
  end
  text(S, "FRACTURED MEMORIES", W / 2, 30, LIT, ALIGN_CENTER)

  if flick < 60 then
    rect(S, 10, 12, 140, 28, DRK)
  end

  -- Spooky eye
  circ(S, 80, 56, 12, LIT)
  circ(S, 80, 56, 8, DRK)
  rectf(S, 76, 54, 8, 4, WHT)
  pix(S, 80, 56, BLK)

  -- Mini map preview
  rect(S, 50, 72, 60, 25, DRK)
  -- Mini player
  local fy = 82 + math.floor(math.sin(tick * 0.05) * 2)
  rectf(S, 78, fy, 4, 5, LIT)
  circf(S, 80, fy - 2, 2, WHT)
  -- Mini door
  rectf(S, 107, 80, 3, 8, DRK)

  text(S, "PRESS START", W / 2, 100, (tick % 40 < 25) and WHT or DRK, ALIGN_CENTER)
  text(S, "Agent #16", 52, 112, DRK)
end

local function draw_msg()
  S = S or screen()
  rectf(S, 4, 78, 152, 26, BLK)
  rect(S, 4, 78, 152, 26, LIT)
  for i, ln in ipairs(msg_lines) do
    text(S, ln, 8, 80 + (i - 1) * 8, WHT)
  end
end

local function draw_inv()
  S = S or screen()
  rectf(S, 10, 8, 140, 104, BLK)
  rect(S, 10, 8, 140, 104, LIT)
  text(S, "INVENTORY", 52, 12, WHT)
  line(S, 12, 20, 148, 20, DRK)

  if #inventory == 0 then
    text(S, "Empty", 60, 50, DRK)
    return
  end

  for i, it in ipairs(inventory) do
    local y = 24 + (i - 1) * 12
    local c = DRK
    if i - 1 == inv_sel then
      c = WHT
      rectf(S, 12, y - 1, 136, 11, DRK)
    end
    text(S, it.name, 16, y, c)
  end

  if inv_sel >= 0 and inv_sel < #inventory then
    local it = inventory[inv_sel + 1]
    if it then
      line(S, 12, 92, 148, 92, DRK)
      text(S, it.desc, 14, 96, LIT)
    end
  end
  text(S, "B:CLOSE", 56, 105, DRK)
end

local function draw_ending_escape()
  S = screen()
  cls(S, BLK)
  for i = 0, 30 do
    local c = i < 10 and WHT or (i < 20 and LIT or DRK)
    line(S, 0, 40 + i, W, 40 + i, c)
  end
  rectf(S, 0, 71, W, H - 71, DRK)

  text(S, "ENDING: ESCAPE", W / 2, 10, WHT, ALIGN_CENTER)
  text(S, "You step into the dawn.", W / 2, 25, LIT, ALIGN_CENTER)
  text(S, "Free, but memories lost.", W / 2, 80, LIT, ALIGN_CENTER)
  text(S, "The truth remains buried.", W / 2, 90, DRK, ALIGN_CENTER)

  if ending_timer > 120 then
    text(S, "PRESS START", W / 2, 108, (tick % 40 < 25) and WHT or BLK, ALIGN_CENTER)
  end
end

local function draw_ending_trapped()
  S = screen()
  cls(S, BLK)
  local door_y = math.min(ending_timer * 2, 60)
  rectf(S, 30, 0, 100, door_y, LIT)
  rect(S, 30, 0, 100, door_y, WHT)
  if door_y > 30 then
    for i = 0, 3 do
      rectf(S, 28, 10 + i * 14, 6, 4, WHT)
      rectf(S, 126, 10 + i * 14, 6, 4, WHT)
    end
  end

  text(S, "ENDING: TRAPPED", W / 2, 65, WHT, ALIGN_CENTER)
  text(S, "Lockdown engaged.", W / 2, 78, LIT, ALIGN_CENTER)
  text(S, "The steel seals forever.", W / 2, 88, LIT, ALIGN_CENTER)
  text(S, "You are Subject 07. Again.", W / 2, 98, DRK, ALIGN_CENTER)

  if ending_timer > 120 then
    text(S, "PRESS START", W / 2, 108, (tick % 40 < 25) and WHT or BLK, ALIGN_CENTER)
  end
end

local function draw_ending_truth()
  S = screen()
  cls(S, BLK)
  for i = 1, 20 do
    local sx = (i * 19 + tick * 2) % W
    local sy = (i * 7 + tick) % H
    local ch = string.char(48 + (tick + i) % 26)
    text(S, ch, sx, sy, DRK)
  end

  if ending_timer > 30 then
    rectf(S, 20, 20, 120, 60, BLK)
    rect(S, 20, 20, 120, 60, WHT)
    text(S, "ENDING: THE TRUTH", W / 2, 25, WHT, ALIGN_CENTER)
    text(S, "Transmission sent.", W / 2, 38, LIT, ALIGN_CENTER)
    text(S, "Evidence broadcast to", W / 2, 48, LIT, ALIGN_CENTER)
    text(S, "every screen in the city.", W / 2, 56, LIT, ALIGN_CENTER)
    text(S, "Project DARK ROOM exposed.", W / 2, 68, WHT, ALIGN_CENTER)
  end

  if ending_timer > 60 then
    text(S, "You remember everything.", W / 2, 85, LIT, ALIGN_CENTER)
    text(S, "You are free.", W / 2, 95, WHT, ALIGN_CENTER)
  end

  if ending_timer > 150 then
    text(S, "PRESS START", W / 2, 108, (tick % 40 < 25) and WHT or BLK, ALIGN_CENTER)
  end
end

function _draw()
  S = screen()

  if state == ST_TITLE then
    draw_title()
  elseif state == ST_PLAY then
    draw_room()
  elseif state == ST_MSG then
    draw_room()
    draw_msg()
  elseif state == ST_INV then
    draw_room()
    draw_inv()
  elseif state == ST_ENDING then
    if ending_id == "escape" then draw_ending_escape()
    elseif ending_id == "trapped" then draw_ending_trapped()
    elseif ending_id == "truth" then draw_ending_truth()
    end
  elseif state == ST_DEMO then
    draw_room()
    rectf(S, 40, 104, 80, 10, BLK)
    text(S, "- DEMO -", W / 2, 106, LIT, ALIGN_CENTER)
  elseif state == ST_PAUSE then
    draw_room()
    rectf(S, 30, 35, 100, 50, BLK)
    rect(S, 30, 35, 100, 50, WHT)
    text(S, "PAUSED", W / 2, 42, WHT, ALIGN_CENTER)
    text(S, "START to resume", W / 2, 55, LIT, ALIGN_CENTER)
    text(S, "Items: " .. #inventory .. "/6", W / 2, 68, DRK, ALIGN_CENTER)
  end
end
