-- THE DARK ROOM: FRACTURED MEMORIES
-- Agent 07 - Mystery Adventure with Multiple Endings
-- 160x120 | 2-bit (0-3) | mode(2)
-- D-Pad: Navigate | A: Confirm/Interact | B: Inventory | START: Begin | SELECT: Pause

---------- CONSTANTS ----------
local W = 160
local H = 120
local S -- screen surface

-- 2-bit palette: 0=black, 1=dark gray, 2=light gray, 3=white
local BLK = 0
local DRK = 1
local LIT = 2
local WHT = 3

---------- SAFE AUDIO ----------
local function snd_note(ch, n, dur)
  if note then note(ch, n, dur) end
end
local function snd_noise(ch, dur)
  if noise then noise(ch, dur) end
end

---------- UTILITIES ----------
local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function text_c(str, y, c)
  text(S, str, W / 2, y, c or WHT, ALIGN_CENTER)
end

local function text_l(str, x, y, c)
  text(S, str, x, y, c or WHT)
end

local function draw_box(x, y, w, h, border, bg)
  rectf(S, x, y, w, h, bg or BLK)
  rect(S, x, y, w, h, border or WHT)
end

---------- FORWARD DECLARATIONS ----------
local init_game, change_room, check_endings
local draw_room_art, get_room_actions, do_action
local play_ambient, play_step, play_discover, play_danger

---------- STATE ----------
local state       -- "title","play","paused","ending","demo"
local tick = 0
local idle_timer = 0
local IDLE_MAX = 300 -- 10 seconds at 30fps

-- Game state
local room         -- current room id
local cursor       -- menu cursor index
local inv = {}     -- inventory list of item ids
local flags = {}   -- boolean flags
local msg = ""     -- current message text
local msg_timer = 0
local fade = 0     -- fade effect (0=none, >0 fading)
local fade_dir = 0 -- 1=fade out, -1=fade in
local fade_target_room = nil
local ending_id = nil -- which ending
local ending_timer = 0

-- Demo mode
local demo_step = 0
local demo_timer = 0
local demo_actions = {
  {wait=30, room="dark_room", act=1},
  {wait=60, room="dark_room", act=2},
  {wait=45, room="hallway", act=1},
  {wait=60, room="lab", act=1},
  {wait=45, room="lab", act=2},
  {wait=90},
}

---------- INVENTORY HELPERS ----------
local function has_item(id)
  for _, v in ipairs(inv) do
    if v == id then return true end
  end
  return false
end

local function add_item(id)
  if not has_item(id) and #inv < 6 then
    inv[#inv + 1] = id
    play_discover()
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

local ITEM_NAMES = {
  key = "Key",
  badge = "ID Badge",
  evidence = "Evidence",
  flashlight = "Flashlight",
  note1 = "Memo",
  fuse = "Fuse",
}

---------- ROOM DEFINITIONS ----------
-- Each room: name, art_fn, actions_fn
local rooms = {}

-- DARK ROOM (starting room)
rooms.dark_room = {
  name = "Dark Room",
  ambient = "C2",
  actions = function()
    local a = {}
    if not has_item("flashlight") then
      a[#a+1] = {label="Feel around in dark", id="feel"}
    else
      a[#a+1] = {label="Use flashlight", id="light"}
    end
    if not has_item("key") and flags.searched_desk then
      a[#a+1] = {label="Check drawer again", id="drawer2"}
    elseif not flags.searched_desk then
      a[#a+1] = {label="Search the desk", id="desk"}
    end
    if flags.has_light or has_item("flashlight") then
      a[#a+1] = {label="Go to Hallway", id="go_hallway"}
    end
    a[#a+1] = {label="Examine walls", id="walls"}
    return a
  end,
}

rooms.hallway = {
  name = "Hallway",
  ambient = "D2",
  actions = function()
    local a = {}
    a[#a+1] = {label="Go to Dark Room", id="go_dark_room"}
    a[#a+1] = {label="Go to Lab", id="go_lab"}
    a[#a+1] = {label="Go to Office", id="go_office"}
    if has_item("fuse") then
      a[#a+1] = {label="Go to Basement", id="go_basement"}
    end
    if has_item("badge") then
      a[#a+1] = {label="Go to Roof", id="go_roof"}
    end
    if flags.saw_files and has_item("evidence") then
      a[#a+1] = {label="Go to Vault", id="go_vault"}
    end
    a[#a+1] = {label="Try front door", id="front_door"}
    return a
  end,
}

rooms.lab = {
  name = "Laboratory",
  ambient = "E2",
  actions = function()
    local a = {}
    a[#a+1] = {label="Examine equipment", id="lab_equip"}
    if not has_item("evidence") then
      a[#a+1] = {label="Search cabinets", id="lab_cabinet"}
    end
    if not has_item("fuse") and not flags.got_fuse then
      a[#a+1] = {label="Check power panel", id="lab_fuse"}
    end
    a[#a+1] = {label="Read whiteboard", id="lab_board"}
    a[#a+1] = {label="Go to Hallway", id="go_hallway"}
    return a
  end,
}

rooms.office = {
  name = "Office",
  ambient = "F2",
  actions = function()
    local a = {}
    a[#a+1] = {label="Search desk", id="off_desk"}
    if not flags.saw_files then
      a[#a+1] = {label="Open filing cabinet", id="off_files"}
    else
      a[#a+1] = {label="Review files again", id="off_files2"}
    end
    if not has_item("badge") and not flags.got_badge then
      a[#a+1] = {label="Check coat rack", id="off_coat"}
    end
    a[#a+1] = {label="Look at computer", id="off_computer"}
    a[#a+1] = {label="Go to Hallway", id="go_hallway"}
    return a
  end,
}

rooms.basement = {
  name = "Basement",
  ambient = "A1",
  actions = function()
    local a = {}
    a[#a+1] = {label="Examine generator", id="bas_gen"}
    if has_item("fuse") and not flags.power_on then
      a[#a+1] = {label="Install fuse", id="bas_fuse"}
    end
    if flags.power_on then
      a[#a+1] = {label="Override lockdown", id="bas_override"}
      a[#a+1] = {label="Activate lockdown", id="bas_lockdown"}
    end
    a[#a+1] = {label="Search shelves", id="bas_shelves"}
    a[#a+1] = {label="Go to Hallway", id="go_hallway"}
    return a
  end,
}

rooms.roof = {
  name = "Rooftop",
  ambient = "G2",
  actions = function()
    local a = {}
    a[#a+1] = {label="Look at city", id="roof_city"}
    if not has_item("note1") then
      a[#a+1] = {label="Check antenna base", id="roof_antenna"}
    end
    a[#a+1] = {label="Examine hatch lock", id="roof_hatch"}
    a[#a+1] = {label="Go to Hallway", id="go_hallway"}
    return a
  end,
}

rooms.vault = {
  name = "The Vault",
  ambient = "C1",
  actions = function()
    local a = {}
    a[#a+1] = {label="Read classified docs", id="vault_docs"}
    a[#a+1] = {label="Access terminal", id="vault_terminal"}
    a[#a+1] = {label="Go to Hallway", id="go_hallway"}
    return a
  end,
}

---------- ACTION HANDLER ----------
do_action = function(action_id)
  -- Navigation
  if action_id == "go_hallway" then change_room("hallway") return end
  if action_id == "go_dark_room" then change_room("dark_room") return end
  if action_id == "go_lab" then change_room("lab") return end
  if action_id == "go_office" then change_room("office") return end
  if action_id == "go_basement" then change_room("basement") return end
  if action_id == "go_roof" then change_room("roof") return end
  if action_id == "go_vault" then change_room("vault") return end

  -- Dark Room actions
  if action_id == "feel" then
    msg = "Your hand finds something cold\nand metallic... a flashlight!"
    add_item("flashlight")
    flags.has_light = true
  elseif action_id == "light" then
    msg = "The beam reveals a small room.\nA desk, a chair, a locked door."
    flags.has_light = true
  elseif action_id == "desk" then
    flags.searched_desk = true
    msg = "Dusty desk. Drawer is jammed.\nSomething rattles inside."
  elseif action_id == "drawer2" then
    msg = "You force it open. A small\nbrass key falls out!"
    add_item("key")
  elseif action_id == "walls" then
    msg = "Scratches on the wall:\n\"THEY ARE WATCHING. DON'T TRUST.\""
    play_danger()

  -- Hallway actions
  elseif action_id == "front_door" then
    if has_item("key") and not flags.lockdown_triggered then
      -- GOOD ENDING: escape
      ending_id = "escape"
      state = "ending"
      ending_timer = 0
      snd_note(0, "C5", 0.3)
      snd_note(1, "E5", 0.3)
      return
    elseif flags.lockdown_triggered then
      msg = "The door is sealed. Steel\nbolts engaged. No way out."
      play_danger()
    else
      msg = "Locked. Needs a key.\nThere must be one somewhere."
    end

  -- Lab actions
  elseif action_id == "lab_equip" then
    msg = "Medical equipment. Syringes,\nmonitors... memory experiments?"
    flags.saw_lab = true
  elseif action_id == "lab_cabinet" then
    msg = "Test results with YOUR name.\nSubject 7: Memory Wipe Protocol."
    add_item("evidence")
    flags.found_evidence = true
  elseif action_id == "lab_fuse" then
    msg = "A spare fuse in the panel.\nMight be useful somewhere."
    add_item("fuse")
    flags.got_fuse = true
  elseif action_id == "lab_board" then
    msg = "Formulas... diagrams of a\nbrain. \"Phase 3: Permanent.\""
    play_danger()

  -- Office actions
  elseif action_id == "off_desk" then
    msg = "Paperwork. Redacted names.\n\"Project DARK ROOM - ACTIVE\""
  elseif action_id == "off_files" then
    flags.saw_files = true
    msg = "Classified files! A conspiracy\nspanning years. A hidden vault..."
    play_discover()
  elseif action_id == "off_files2" then
    msg = "The files detail a program\nto erase and rewrite memories."
  elseif action_id == "off_coat" then
    msg = "An ID badge in the pocket!\n\"Dr. Null - Level 5 Access\""
    add_item("badge")
    flags.got_badge = true
  elseif action_id == "off_computer" then
    if flags.saw_files then
      msg = "Terminal shows active subjects.\nYou are Subject 07."
    else
      msg = "Password protected. Maybe\nthere are clues elsewhere."
    end

  -- Basement actions
  elseif action_id == "bas_gen" then
    if flags.power_on then
      msg = "Generator humming steadily.\nAll systems operational."
    else
      msg = "Dead generator. Fuse slot\nis empty. Needs a fuse."
    end
  elseif action_id == "bas_fuse" then
    remove_item("fuse")
    flags.power_on = true
    msg = "Fuse installed! Generator\nroars to life. Power restored!"
    snd_note(0, "C3", 0.2)
    snd_note(1, "G3", 0.2)
  elseif action_id == "bas_override" then
    msg = "Lockdown DISENGAGED.\nAll doors unlocked."
    flags.lockdown_triggered = false
    snd_note(0, "E4", 0.15)
  elseif action_id == "bas_lockdown" then
    -- BAD ENDING: lockdown triggers trap
    flags.lockdown_triggered = true
    ending_id = "trapped"
    state = "ending"
    ending_timer = 0
    snd_noise(0, 0.5)
    snd_noise(1, 0.5)
    return
  elseif action_id == "bas_shelves" then
    msg = "Old supplies. Dust everywhere.\nA label reads: \"SUBJECT HOLDING\""

  -- Roof actions
  elseif action_id == "roof_city" then
    msg = "A sprawling city below. You\ndon't recognize anything."
  elseif action_id == "roof_antenna" then
    msg = "A crumpled memo: \"Broadcast\nfrequency controls subjects.\""
    add_item("note1")
  elseif action_id == "roof_hatch" then
    msg = "The hatch locks from inside.\nEmergency exit only."

  -- Vault actions
  elseif action_id == "vault_docs" then
    flags.read_vault = true
    msg = "Full records of the program.\nNames, dates, methods. Proof."
    play_discover()
  elseif action_id == "vault_terminal" then
    if flags.read_vault and has_item("evidence") and has_item("note1") then
      -- TRUE ENDING: expose conspiracy
      ending_id = "truth"
      state = "ending"
      ending_timer = 0
      snd_note(0, "C5", 0.4)
      snd_note(1, "E5", 0.4)
      snd_note(0, "G5", 0.4)
      return
    elseif flags.read_vault then
      msg = "Need more evidence to\ntransmit a credible report."
    else
      msg = "Terminal active. Read the\ndocuments first."
    end
  end

  msg_timer = 180 -- 6 seconds
end

---------- ROOM TRANSITIONS ----------
change_room = function(target)
  fade_target_room = target
  fade = 10
  fade_dir = 1 -- fade to black
  play_step()
end

local function finish_room_change()
  room = fade_target_room
  fade_target_room = nil
  cursor = 0
  fade = 10
  fade_dir = -1 -- fade in
  msg = rooms[room].name
  msg_timer = 90
  play_ambient()
end

---------- SOUND EFFECTS ----------
play_ambient = function()
  local r = rooms[room]
  if r and r.ambient then
    snd_note(2, r.ambient, 0.8)
  end
end

play_step = function()
  snd_noise(0, 0.04)
end

play_discover = function()
  snd_note(0, "E5", 0.08)
  snd_note(1, "G5", 0.08)
end

play_danger = function()
  snd_note(0, "C2", 0.15)
  snd_noise(1, 0.1)
end

---------- ROOM ART DRAWING ----------
-- Minimal atmospheric pixel art for each room (top 68px)
local function draw_dark_room()
  -- Dark room with desk outline
  rectf(S, 0, 0, W, 68, BLK)
  if flags.has_light then
    -- Flashlight cone
    for i = 0, 30 do
      local spread = i * 0.8
      local bright = i < 15 and LIT or DRK
      line(S, 80, 10, 60 - spread, 10 + i * 2, bright)
      line(S, 80, 10, 100 + spread, 10 + i * 2, bright)
    end
    -- Desk
    rectf(S, 50, 40, 60, 20, DRK)
    rect(S, 50, 40, 60, 20, LIT)
    -- Chair
    rectf(S, 68, 55, 24, 12, DRK)
    rect(S, 68, 55, 24, 12, LIT)
  else
    -- Pure darkness with faint outline
    local flicker = tick % 60 < 30 and DRK or BLK
    rect(S, 50, 40, 60, 20, flicker)
    text_c("...darkness...", 30, DRK)
  end
end

local function draw_hallway()
  rectf(S, 0, 0, W, 68, BLK)
  -- Perspective hallway
  rectf(S, 40, 10, 80, 50, DRK)
  -- Floor lines
  for i = 0, 4 do
    line(S, 30 + i * 5, 60, 60 + i * 4, 10, DRK)
    line(S, 130 - i * 5, 60, 100 - i * 4, 10, DRK)
  end
  -- Doors along hallway
  rect(S, 20, 25, 18, 35, LIT)
  rect(S, 122, 25, 18, 35, LIT)
  rectf(S, 65, 15, 30, 40, DRK)
  rect(S, 65, 15, 30, 40, LIT)
  -- Door handles
  pix(S, 35, 42, WHT)
  pix(S, 125, 42, WHT)
  pix(S, 92, 35, WHT)
  -- Front door at end
  rectf(S, 72, 18, 16, 25, LIT)
  rect(S, 72, 18, 16, 25, WHT)
end

local function draw_lab()
  rectf(S, 0, 0, W, 68, BLK)
  -- Lab benches
  rectf(S, 10, 35, 60, 8, DRK)
  rectf(S, 90, 35, 60, 8, DRK)
  rect(S, 10, 35, 60, 8, LIT)
  rect(S, 90, 35, 60, 8, LIT)
  -- Equipment shapes
  rectf(S, 15, 20, 12, 15, DRK)
  rect(S, 15, 20, 12, 15, LIT)
  rectf(S, 35, 22, 8, 13, DRK)
  rect(S, 35, 22, 8, 13, LIT)
  -- Monitor
  rectf(S, 100, 15, 20, 18, DRK)
  rect(S, 100, 15, 20, 18, LIT)
  -- Blinking light
  if tick % 40 < 20 then
    pix(S, 110, 28, WHT)
  end
  -- Whiteboard
  rectf(S, 50, 5, 40, 25, LIT)
  rect(S, 50, 5, 40, 25, WHT)
end

local function draw_office()
  rectf(S, 0, 0, W, 68, BLK)
  -- Desk
  rectf(S, 30, 38, 70, 14, DRK)
  rect(S, 30, 38, 70, 14, LIT)
  -- Computer monitor
  rectf(S, 55, 20, 25, 18, DRK)
  rect(S, 55, 20, 25, 18, LIT)
  if flags.saw_files then
    rectf(S, 57, 22, 21, 14, LIT)
    text(S, "DATA", 60, 26, WHT)
  end
  -- Filing cabinet
  rectf(S, 130, 20, 20, 40, DRK)
  rect(S, 130, 20, 20, 40, LIT)
  rect(S, 132, 22, 16, 10, LIT)
  rect(S, 132, 34, 16, 10, LIT)
  -- Coat rack
  line(S, 15, 15, 15, 58, LIT)
  line(S, 10, 15, 20, 15, LIT)
end

local function draw_basement()
  rectf(S, 0, 0, W, 68, BLK)
  -- Generator
  rectf(S, 50, 25, 40, 30, DRK)
  rect(S, 50, 25, 40, 30, LIT)
  -- Pipes
  line(S, 55, 25, 55, 8, LIT)
  line(S, 85, 25, 85, 8, LIT)
  line(S, 55, 8, 85, 8, LIT)
  -- Power indicator
  if flags.power_on then
    rectf(S, 65, 35, 10, 10, LIT)
    pix(S, 70, 40, WHT)
  else
    rectf(S, 65, 35, 10, 10, BLK)
    rect(S, 65, 35, 10, 10, DRK)
  end
  -- Shelves
  for i = 0, 2 do
    rectf(S, 5, 20 + i * 16, 35, 3, DRK)
  end
  rectf(S, 120, 20, 35, 3, DRK)
  rectf(S, 120, 36, 35, 3, DRK)
end

local function draw_roof()
  rectf(S, 0, 0, W, 68, BLK)
  -- Sky (dark with stars)
  for i = 1, 12 do
    local sx = (i * 37 + tick) % W
    local sy = (i * 13) % 30
    pix(S, sx, sy, (i % 2 == 0) and WHT or LIT)
  end
  -- City skyline
  rectf(S, 0, 40, 25, 28, DRK)
  rectf(S, 28, 45, 15, 23, DRK)
  rectf(S, 46, 35, 20, 33, DRK)
  rectf(S, 70, 48, 18, 20, DRK)
  rectf(S, 92, 38, 22, 30, DRK)
  rectf(S, 118, 42, 15, 26, DRK)
  rectf(S, 136, 50, 24, 18, DRK)
  -- Building windows
  for i = 0, 3 do
    for j = 0, 2 do
      if (i + j + tick / 30) % 3 < 2 then
        pix(S, 50 + i * 4, 38 + j * 6, LIT)
      end
    end
  end
  -- Antenna
  line(S, 80, 10, 80, 48, LIT)
  line(S, 75, 15, 85, 15, LIT)
  if tick % 30 < 15 then
    pix(S, 80, 10, WHT)
  end
  -- Railing
  line(S, 0, 60, W, 60, LIT)
  for i = 0, 10 do
    line(S, i * 16, 60, i * 16, 67, DRK)
  end
end

local function draw_vault()
  rectf(S, 0, 0, W, 68, BLK)
  -- Vault walls
  rect(S, 5, 5, 150, 58, LIT)
  -- Filing rows
  for i = 0, 4 do
    rectf(S, 15 + i * 28, 12, 20, 40, DRK)
    rect(S, 15 + i * 28, 12, 20, 40, LIT)
    -- Labels
    for j = 0, 3 do
      rect(S, 17 + i * 28, 14 + j * 10, 16, 8, DRK)
    end
  end
  -- Terminal
  rectf(S, 60, 55, 30, 10, DRK)
  rect(S, 60, 55, 30, 10, LIT)
  if tick % 20 < 10 then
    pix(S, 75, 59, WHT)
  end
end

local room_art = {
  dark_room = draw_dark_room,
  hallway = draw_hallway,
  lab = draw_lab,
  office = draw_office,
  basement = draw_basement,
  roof = draw_roof,
  vault = draw_vault,
}

---------- DRAWING ----------
local function draw_inventory()
  -- Inventory bar at bottom
  local iy = H - 11
  rectf(S, 0, iy, W, 11, BLK)
  line(S, 0, iy, W, iy, DRK)
  for i = 1, 6 do
    local ix = (i - 1) * 26 + 3
    rect(S, ix, iy + 1, 24, 9, DRK)
    if inv[i] then
      local nm = ITEM_NAMES[inv[i]] or inv[i]
      text(S, nm, ix + 2, iy + 2, LIT)
    end
  end
end

local function draw_message()
  if msg_timer > 0 and msg ~= "" then
    local bx, by = 4, 68
    local bw, bh = W - 8, 20
    draw_box(bx, by, bw, bh, LIT, BLK)
    -- Split message on \n
    local y = by + 3
    for line_str in msg:gmatch("[^\n]+") do
      text(S, line_str, bx + 4, y, WHT)
      y = y + 8
    end
  end
end

local function draw_action_menu()
  local actions = rooms[room].actions()
  local ax, ay = 4, 68
  local aw = W - 8

  if msg_timer > 0 then
    ay = 88
  end

  local menu_h = #actions * 9 + 4
  local max_y = H - 12
  if ay + menu_h > max_y then
    ay = max_y - menu_h
  end

  for i, a in ipairs(actions) do
    local y = ay + (i - 1) * 9
    local sel = (cursor == i - 1)
    if sel then
      rectf(S, ax, y, aw, 9, DRK)
    end
    local prefix = sel and "> " or "  "
    text(S, prefix .. a.label, ax + 2, y + 1, sel and WHT or LIT)
  end
end

local function draw_hud()
  -- Room name top-left
  text(S, rooms[room].name, 2, 0, LIT)
end

local function apply_fade()
  if fade <= 0 then return end
  -- Draw black overlay with varying coverage
  local alpha = fade / 10
  if alpha > 0.7 then
    rectf(S, 0, 0, W, H, BLK)
  elseif alpha > 0.3 then
    -- Dither pattern
    for y = 0, H - 1, 2 do
      for x = 0, W - 1, 2 do
        pix(S, x, y, BLK)
      end
    end
  end
end

---------- TITLE SCREEN ----------
local function draw_title()
  rectf(S, 0, 0, W, H, BLK)

  -- Atmospheric flicker
  local flick = tick % 90

  -- Title
  if flick < 70 or flick > 80 then
    text_c("THE DARK ROOM", 20, WHT)
  end
  text_c("FRACTURED MEMORIES", 32, LIT)

  -- Flickering border
  if flick < 60 then
    rect(S, 10, 14, 140, 30, DRK)
  end

  -- Spooky eye
  local ey = 60
  circ(S, 80, ey, 12, LIT)
  circ(S, 80, ey, 8, DRK)
  rectf(S, 76, ey - 2, 8, 4, WHT)
  pix(S, 80, ey, BLK)

  -- Instructions
  text_c("PRESS START", 85, (tick % 40 < 25) and WHT or DRK)
  text_c("A:Act B:Items D-Pad:Move", 100, DRK)
end

---------- ENDING SCREENS ----------
local function draw_ending_escape()
  rectf(S, 0, 0, W, H, BLK)
  -- Dawn light gradient
  for i = 0, 30 do
    local c = i < 10 and WHT or (i < 20 and LIT or DRK)
    line(S, 0, 40 + i, W, 40 + i, c)
  end
  rectf(S, 0, 71, W, H - 71, DRK)

  text_c("ENDING: ESCAPE", 10, WHT)
  text_c("You step into the dawn.", 25, LIT)
  text_c("Free, but memories lost.", 80, LIT)
  text_c("The truth remains buried.", 90, DRK)

  if ending_timer > 120 then
    text_c("PRESS START", 108, (tick % 40 < 25) and WHT or BLK)
  end
end

local function draw_ending_trapped()
  rectf(S, 0, 0, W, H, BLK)
  -- Steel door slamming animation
  local door_y = clamp(ending_timer * 2, 0, 60)
  rectf(S, 30, 0, 100, door_y, LIT)
  rect(S, 30, 0, 100, door_y, WHT)
  if door_y > 30 then
    -- Bolts
    for i = 0, 3 do
      rectf(S, 28, 10 + i * 14, 6, 4, WHT)
      rectf(S, 126, 10 + i * 14, 6, 4, WHT)
    end
  end

  text_c("ENDING: TRAPPED", 65, WHT)
  text_c("Lockdown engaged.", 78, LIT)
  text_c("The steel seals forever.", 88, LIT)
  text_c("You are Subject 07. Again.", 98, DRK)

  if ending_timer > 120 then
    text_c("PRESS START", 108, (tick % 40 < 25) and WHT or BLK)
  end
end

local function draw_ending_truth()
  rectf(S, 0, 0, W, H, BLK)
  -- Data stream effect
  for i = 1, 20 do
    local sx = (i * 19 + tick * 2) % W
    local sy = (i * 7 + tick) % H
    local ch = string.char(48 + (tick + i) % 26)
    text(S, ch, sx, sy, DRK)
  end

  -- Transmission animation
  if ending_timer > 30 then
    draw_box(20, 20, 120, 60, WHT, BLK)
    text_c("ENDING: THE TRUTH", 25, WHT)
    text_c("Transmission sent.", 38, LIT)
    text_c("Evidence broadcast to", 48, LIT)
    text_c("every screen in the city.", 56, LIT)
    text_c("Project DARK ROOM exposed.", 68, WHT)
  end

  if ending_timer > 60 then
    text_c("You remember everything.", 85, LIT)
    text_c("You are free.", 95, WHT)
  end

  if ending_timer > 150 then
    text_c("PRESS START", 108, (tick % 40 < 25) and WHT or BLK)
  end
end

---------- DEMO MODE ----------
local function update_demo()
  demo_timer = demo_timer + 1
  if demo_step > #demo_actions then
    state = "title"
    idle_timer = 0
    return
  end
  local da = demo_actions[demo_step]
  if demo_timer >= da.wait then
    if da.room and room ~= da.room then
      room = da.room
      cursor = 0
      msg = rooms[room].name
      msg_timer = 90
    end
    if da.act then
      local actions = rooms[room].actions()
      if actions[da.act] then
        do_action(actions[da.act].id)
      end
    end
    demo_step = demo_step + 1
    demo_timer = 0
  end
end

---------- GAME INIT ----------
init_game = function()
  room = "dark_room"
  cursor = 0
  inv = {}
  flags = {}
  msg = "You wake in darkness.\nHead pounding. No memories."
  msg_timer = 180
  fade = 10
  fade_dir = -1
  ending_id = nil
  ending_timer = 0
end

---------- MAIN CALLBACKS ----------
function _init()
  mode(2)
end

function _start()
  state = "title"
  tick = 0
  idle_timer = 0
  init_game()
end

function _update()
  tick = tick + 1

  -- Fade logic
  if fade > 0 then
    if fade_dir > 0 then
      fade = fade - 1
      if fade <= 0 and fade_target_room then
        finish_room_change()
      end
    elseif fade_dir < 0 then
      fade = fade - 1
    end
  end

  if state == "title" then
    idle_timer = idle_timer + 1
    if btnp("start") or (touch_start and touch_start()) then
      init_game()
      state = "play"
      idle_timer = 0
      play_ambient()
      return
    end
    -- Enter demo after idle
    if idle_timer >= IDLE_MAX then
      state = "demo"
      demo_step = 1
      demo_timer = 0
      init_game()
      return
    end

  elseif state == "demo" then
    update_demo()
    if btnp("start") or btnp("a") or (touch_start and touch_start()) then
      state = "title"
      idle_timer = 0
      init_game()
    end

  elseif state == "play" then
    if fade > 0 then return end -- wait for fade

    -- Pause
    if btnp("start") or btnp("select") then
      state = "paused"
      return
    end

    -- Message timer
    if msg_timer > 0 then
      msg_timer = msg_timer - 1
      -- Allow dismiss
      if btnp("a") then
        msg_timer = 0
      end
      return
    end

    -- Navigate actions
    local actions = rooms[room].actions()
    local num_actions = #actions
    if num_actions > 0 then
      if btnp("up") then
        cursor = (cursor - 1) % num_actions
        snd_noise(0, 0.02)
      end
      if btnp("down") then
        cursor = (cursor + 1) % num_actions
        snd_noise(0, 0.02)
      end
      if btnp("a") then
        cursor = clamp(cursor, 0, num_actions - 1)
        do_action(actions[cursor + 1].id)
        snd_note(0, "A4", 0.03)
      end
    end

    -- Ambient sound loop
    if tick % 300 == 0 then
      play_ambient()
    end

  elseif state == "paused" then
    if btnp("start") or btnp("select") then
      state = "play"
    end

  elseif state == "ending" then
    ending_timer = ending_timer + 1
    local threshold = ending_id == "truth" and 150 or 120
    if ending_timer > threshold and (btnp("start") or btnp("a")) then
      state = "title"
      idle_timer = 0
      init_game()
    end
  end
end

function _draw()
  S = screen()

  if state == "title" then
    draw_title()
    return
  end

  if state == "ending" then
    if ending_id == "escape" then
      draw_ending_escape()
    elseif ending_id == "trapped" then
      draw_ending_trapped()
    elseif ending_id == "truth" then
      draw_ending_truth()
    end
    return
  end

  -- Game / Demo / Paused all draw the room
  rectf(S, 0, 0, W, H, BLK)

  -- Room art
  local art_fn = room_art[room]
  if art_fn then art_fn() end

  -- HUD
  draw_hud()

  -- Message or action menu
  draw_message()
  if msg_timer <= 0 then
    draw_action_menu()
  end

  -- Inventory
  draw_inventory()

  -- Fade overlay
  apply_fade()

  -- Pause overlay
  if state == "paused" then
    rectf(S, 0, 0, W, H, BLK)
    draw_box(30, 35, 100, 50, WHT, BLK)
    text_c("PAUSED", 42, WHT)
    text_c("START to resume", 55, LIT)
    text_c("Items: " .. #inv .. "/6", 68, DRK)
  end

  -- Demo overlay
  if state == "demo" then
    rectf(S, 0, 0, W, 10, BLK)
    text_c("DEMO - PRESS START", 1, (tick % 40 < 25) and WHT or DRK)
  end
end
