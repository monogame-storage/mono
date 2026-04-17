-- THE DARK ROOM: WITNESS
-- First-person horror + crafting + multiple endings
-- Agent 26 (Wave 3) = Agent 17 (horror) + Agent 18 (crafting) + Agent 15 (endings)
-- 160x120 | 2-bit (4 shades) | mode(2) | surface-first
-- D-Pad: Move cursor / Turn | A: Interact | B: Inventory | START: Pause

----------------------------------------------
-- CONSTANTS
----------------------------------------------
local W, H = 160, 120
local BLACK, DARK, LIGHT, WHITE = 0, 1, 2, 3
local DIR_N, DIR_E, DIR_S, DIR_W = 1, 2, 3, 4
local DIR_NAMES = {"NORTH", "EAST", "SOUTH", "WEST"}
local CUR_SPEED = 2
local DEMO_IDLE = 300
local S -- screen surface

----------------------------------------------
-- SAFE AUDIO
----------------------------------------------
local function sfx_note(ch, n, dur)
  if note then pcall(note, ch, n, dur) end
end
local function sfx_noise(ch, dur)
  if noise then pcall(noise, ch, dur) end
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
local function snd_read() sfx_note(0, "D4", 0.06) sfx_note(1, "F4", 0.04) end

----------------------------------------------
-- HORROR SOUNDS
----------------------------------------------
local function snd_heartbeat(intensity)
  sfx_note(0, "C3", 0.06)
  if intensity > 0.4 then sfx_note(0, "C3", 0.04) end
end
local function snd_scare(intensity)
  sfx_noise(0, 0.15 + intensity * 0.1)
  sfx_note(1, "C2", 0.2 + intensity * 0.1)
  sfx_note(2, "F#2", 0.15)
end
local function snd_creak()
  local creaks = {"A2", "B2", "G2", "D2"}
  sfx_note(2, creaks[math.random(#creaks)], 0.12)
end
local function snd_drip() sfx_note(3, "E6", 0.02) end
local function snd_whisper() sfx_noise(3, 0.06) sfx_note(2, "B5", 0.03) end
local function snd_entity_step()
  local steps = {"D4", "E4", "D4", "C4"}
  sfx_note(3, steps[math.random(#steps)], 0.03)
end

----------------------------------------------
-- GLOBAL STATE
----------------------------------------------
local state = "title"
local tick = 0
local idle_timer = 0
local msg_text = ""
local msg_timer = 0
local has_light = false

-- Document viewer
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

-- Puzzle flags
local flags = {}

-- Transition
local trans_timer = 0

-- Entity (horror AI)
local entity_room = 3
local entity_wall = DIR_N
local entity_timer = 0
local entity_visible = false
local entity_appear_timer = 0
local entity_grace = 0
local entity_encounters = 0

-- Horror atmosphere
local heartbeat_rate = 0
local heartbeat_timer = 0
local amb_drip_timer = 60
local amb_creak_timer = 120
local scare_flash = 0
local shake_timer = 0
local shake_amt = 0
local candle_flicker = 0
local darkness_pulse = 0

-- Ending
local ending_id = nil
local ending_timer = 0

-- Demo
local demo_step = 0
local demo_wait = 0

----------------------------------------------
-- ITEM DATABASE
----------------------------------------------
local ITEMS = {
  matches   = {name="Matches",     desc="Three matches left.",          icon="M"},
  lens      = {name="Glass Lens",  desc="Cracked magnifying lens.",     icon="O"},
  lantern   = {name="Lantern",     desc="Makeshift light. It works!",   icon="*"},
  wire      = {name="Wire",        desc="Thin copper wire.",            icon="W"},
  metal_rod = {name="Metal Rod",   desc="Short iron rod.",              icon="I"},
  lockpick  = {name="Lockpick",    desc="Bent wire pick.",              icon="P"},
  tape      = {name="Tape",        desc="Roll of electrical tape.",     icon="T"},
  fuse_dead = {name="Dead Fuse",   desc="Blown 30-amp fuse.",          icon="F"},
  fuse_good = {name="Fixed Fuse",  desc="Taped fuse. Might work.",     icon="f"},
  keycard   = {name="Keycard",     desc="Dr. Wren - Level 4 Access.",   icon="K"},
  note_l    = {name="Note(left)",  desc="Torn paper: '74..'",          icon="1"},
  note_r    = {name="Note(right)", desc="Torn paper: '..39'",          icon="2"},
  full_note = {name="Full Note",   desc="Code: 7439",                  icon="N"},
  crowbar   = {name="Crowbar",     desc="Heavy. Pries things open.",    icon="C"},
  evidence  = {name="Evidence",    desc="Subject 26 file. Proof.",      icon="E"},
  journal1  = {name="Journal p.1", desc="Day 1: moved to sublevel 4.", icon="J"},
  journal2  = {name="Journal p.2", desc="Day 15: they erase you.",     icon="J"},
  journal3  = {name="Journal p.3", desc="Day 31: I am Subject 26.",    icon="J"},
  master_key= {name="Master Key",  desc="Heavy brass key.",             icon="Q"},
}

-- Crafting recipes
local RECIPES = {
  {a="matches",   b="lens",      result="lantern"},
  {a="wire",      b="metal_rod", result="lockpick"},
  {a="tape",      b="fuse_dead", result="fuse_good"},
  {a="note_l",    b="note_r",    result="full_note"},
}

----------------------------------------------
-- UTILITY
----------------------------------------------
local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function lerp(a, b, t) return a + (b - a) * t end

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
  if not has_item(name) and #inv < 8 then
    inv[#inv + 1] = name
    snd_pickup()
    show_msg("Got: " .. (ITEMS[name] and ITEMS[name].name or name), 60)
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

-- Word wrap for documents
local function word_wrap(str, max)
  local lines = {}
  for para in str:gmatch("[^\n]+") do
    local ln = ""
    for w in para:gmatch("%S+") do
      if #ln + #w + 1 > max then
        lines[#lines + 1] = ln
        ln = w
      else
        ln = #ln > 0 and (ln .. " " .. w) or w
      end
    end
    if #ln > 0 then lines[#lines + 1] = ln end
  end
  if #lines == 0 then lines[1] = "" end
  return lines
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
-- DRAWING HELPERS
----------------------------------------------
local function text_c(str, y, c)
  text(S, str, W / 2, y, c or WHITE, ALIGN_CENTER)
end

local function draw_ui_box(x, y, w, h, border, bg)
  rectf(S, x, y, w, h, bg or BLACK)
  rect(S, x, y, w, h, border or WHITE)
end

----------------------------------------------
-- DITHER
----------------------------------------------
local function dither_rectf(s, rx, ry, rw, rh, c1, c2, pat)
  for dy = 0, rh - 1 do
    for dx = 0, rw - 1 do
      local x, y = rx + dx, ry + dy
      if pat <= 0 then pix(s, x, y, c1)
      elseif pat >= 4 then pix(s, x, y, c2)
      elseif pat == 2 then pix(s, x, y, (x + y) % 2 == 0 and c2 or c1)
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
  local dim_all = (entity_room == cur_room and not has_light)

  -- Ceiling
  for y = 0, 39 do
    local depth = y / 40.0
    local shade = has_light and (depth < 0.3 and 2 or 1) or (depth < 0.3 and 1 or 0)
    if candle_flicker > 0 and has_light and math.random(10) < 3 then
      shade = clamp(shade - 1, 0, 3)
    end
    for x = 0, W - 1 do
      local checker = (math.floor(x / 8) + math.floor(y / 4)) % 2
      pix(s, x, y, checker == 0 and shade or clamp(shade - 1, 0, 3))
    end
  end

  -- Floor
  for y = 80, H - 11 do
    local depth = (y - 80) / 30.0
    local shade = has_light and (depth > 0.6 and 2 or 1) or (depth > 0.6 and 1 or 0)
    if candle_flicker > 0 and has_light and math.random(10) < 3 then
      shade = clamp(shade - 1, 0, 3)
    end
    for x = 0, W - 1 do
      local checker = (math.floor(x / 8) + math.floor((y - 80) / 4)) % 2
      pix(s, x, y, checker == 0 and shade or clamp(shade - 1, 0, 3))
    end
  end

  -- Back wall
  local wallc = has_light and LIGHT or DARK
  if candle_flicker > 0 and has_light and math.random(6) < 2 then
    wallc = DARK
  end
  rectf(s, 0, 40, W, 40, wallc)

  -- Perspective lines
  local bc = has_light and WHITE or LIGHT
  line(s, 0, 0, 20, 40, bc)
  line(s, 0, H - 10, 20, 80, bc)
  line(s, W - 1, 0, W - 21, 40, bc)
  line(s, W - 1, H - 10, W - 21, 80, bc)
  line(s, 20, 40, W - 21, 40, bc)
  line(s, 20, 80, W - 21, 80, bc)

  -- Side walls (dark for claustrophobia)
  for y = 0, H - 11 do
    local t = y / (H - 10)
    local lx = math.floor(t < 0.33 and (t / 0.33 * 20) or (t > 0.67 and ((1 - t) / 0.33 * 20) or 20))
    local sc = BLACK
    for x = 0, lx - 1 do pix(s, x, y, sc) end
    for x = W - lx, W - 1 do pix(s, x, y, sc) end
  end
end

----------------------------------------------
-- OBJECT DRAWING
----------------------------------------------
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

local function draw_box_obj(s, x, y, w, h, open)
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
    if tick % 30 < 20 then rectf(s, x + 4, y + 12, 4, 2, LIGHT) end
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

local function draw_antenna(s, x, y, active)
  local c = has_light and WHITE or LIGHT
  -- mast
  line(s, x + 10, y, x + 10, y + 30, c)
  -- crossbars
  line(s, x, y + 4, x + 20, y + 4, c)
  line(s, x + 3, y + 10, x + 17, y + 10, c)
  -- blinking light
  if active and tick % 20 < 10 then
    pix(s, x + 10, y, WHITE)
    pix(s, x + 10, y - 1, WHITE)
  end
end

local function draw_painting(s, x, y, w, h)
  local c = has_light and WHITE or LIGHT
  local bg = has_light and DARK or BLACK
  rect(s, x, y, w, h, c)
  rectf(s, x + 2, y + 2, w - 4, h - 4, bg)
  line(s, x + 3, y + h - 6, x + w // 2, y + 4, has_light and LIGHT or DARK)
  line(s, x + w // 2, y + 4, x + w - 3, y + h - 6, has_light and LIGHT or DARK)
end

----------------------------------------------
-- ENTITY RENDERING
----------------------------------------------
local function draw_entity_eyes(s, intensity)
  local ex = 75 + math.sin(tick * 0.03) * 8
  local ey = 52 + math.cos(tick * 0.02) * 4
  local blink = math.floor(tick / 4) % 8
  if blink == 0 then return end

  local eye_c = WHITE
  if intensity < 0.5 then eye_c = LIGHT end
  if candle_flicker > 0 and math.random(4) == 1 then eye_c = DARK end

  -- Left eye
  pix(s, math.floor(ex) - 3, math.floor(ey), eye_c)
  pix(s, math.floor(ex) - 2, math.floor(ey), eye_c)
  -- Right eye
  pix(s, math.floor(ex) + 2, math.floor(ey), eye_c)
  pix(s, math.floor(ex) + 3, math.floor(ey), eye_c)

  -- Close encounter: more face detail
  if intensity > 0.7 then
    pix(s, math.floor(ex) - 4, math.floor(ey) - 1, DARK)
    pix(s, math.floor(ex) + 4, math.floor(ey) - 1, DARK)
    local mouth_y = math.floor(ey) + 4
    for mx = -2, 2 do
      pix(s, math.floor(ex) + mx, mouth_y, DARK)
    end
  end
end

local function draw_entity_shadow(s)
  local corner = (tick / 30) % 4
  if corner < 1 then
    for i = 0, 4 do pix(s, 22 + i, 78 - i, DARK) end
  elseif corner < 2 then
    for i = 0, 4 do pix(s, W - 23 - i, 78 - i, DARK) end
  end
end

----------------------------------------------
-- HOTSPOT SYSTEM
----------------------------------------------
local hotspots = {}

local function get_wall_hotspots(room, dir)
  local key = room * 10 + dir
  return hotspots[key] or {}
end

local function build_hotspots()
  hotspots = {}

  -- ==========================================
  -- ROOM 1: CELL (start room)
  -- ==========================================

  -- North: heavy door to corridor
  hotspots[11] = {
    {x=60, y=42, w=28, h=36, name="cell_door",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, flags.cell_open)
        if not has_light then
          text(s, "?", hs.x + 12, hs.y + 14, DARK)
        else
          text(s, "DOOR", hs.x + 4, hs.y + 14, DARK)
        end
      end,
      interact=function()
        if flags.cell_open then
          snd_door()
          show_msg("Into the corridor...", 60)
          trans_timer = 15
          cur_room = 2
          cur_dir = DIR_S
        elseif has_light then
          flags.cell_open = true
          snd_door()
          show_msg("The corroded latch gives way!", 90)
        else
          show_msg("A heavy door. Can't see the lock.", 60)
          snd_locked()
        end
      end
    }
  }

  -- East: wall with scratches (lore)
  hotspots[12] = {
    {x=40, y=44, w=50, h=28, name="cell_wall",
      draw=function(s, hs)
        local c = has_light and LIGHT or DARK
        for i = 0, 7 do
          line(s, hs.x + 4 + i * 5, hs.y + 2, hs.x + 4 + i * 5, hs.y + 14, c)
        end
        if has_light then
          text(s, "DONT FORGET", hs.x + 2, hs.y + 18, DARK)
        end
      end,
      interact=function()
        if has_light then
          show_document("Tally marks cover the wall. Hundreds. Scratched deep at the bottom: 'THEY ERASE YOU. DO NOT FORGET.' Below: 'Keycard taped behind pipe, corridor.'")
          flags.wall_hint = true
        else
          show_msg("Rough scratches on the wall.", 60)
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
          rectf(s, hs.x + 30, hs.y + 3, 10, 7, WHITE)
          text(s, "J", hs.x + 33, hs.y + 4, DARK)
        end
      end,
      interact=function()
        if not has_item("journal1") and has_light then
          add_item("journal1")
          flags.j1_read = true
          show_document("Journal, Day 1: 'They moved me to sublevel 4 after I found the files. Dr. Wren says it is for my safety. I do not believe him. I will hide these pages.'")
        elseif not has_light then
          show_msg("A narrow cot. Something under the pillow?", 60)
        else
          show_msg("Your cot. Still warm.", 40)
        end
      end
    }
  }

  -- West: floor with matches and lens
  hotspots[14] = {
    {x=50, y=52, w=36, h=20, name="cell_floor",
      draw=function(s, hs)
        local c = has_light and LIGHT or DARK
        if not has_item("matches") then
          rectf(s, hs.x + 4, hs.y + 8, 8, 4, c)
          text(s, "m", hs.x + 5, hs.y + 8, has_light and WHITE or LIGHT)
        end
        if not has_item("lens") and has_light then
          circ(s, hs.x + 24, hs.y + 10, 4, WHITE)
        end
      end,
      interact=function()
        if not has_item("matches") then
          add_item("matches")
          show_msg("A matchbox! Three left.", 60)
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
  -- ROOM 2: CORRIDOR (hub)
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
          cur_room = 4
          cur_dir = DIR_S
        else
          snd_locked()
          show_msg("Card reader. Need a keycard.", 60)
        end
      end
    }
  }

  -- East: notice board + door to office
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
          show_document("REMINDER: All Project LETHE test subjects must be sedated before memory wipe. Unsedated wipes cause permanent brain damage. -- Dr. H. Wren, Director")
          flags.memo_read = true
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
        snd_door()
        show_msg("Entering the office...", 60)
        trans_timer = 15
        cur_room = 3
        cur_dir = DIR_N
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
        cur_room = 1
        cur_dir = DIR_N
      end
    }
  }

  -- West: pipe with keycard + stairs to roof
  hotspots[24] = {
    {x=35, y=46, w=30, h=20, name="corr_pipe",
      draw=function(s, hs)
        local c = has_light and LIGHT or DARK
        -- pipe
        rectf(s, hs.x, hs.y + 8, hs.w, 4, c)
        line(s, hs.x, hs.y + 8, hs.x, hs.y + 16, c)
        if not has_item("keycard") and not flags.keycard_taken and has_light then
          rectf(s, hs.x + 10, hs.y + 4, 8, 6, WHITE)
          text(s, "K", hs.x + 12, hs.y + 5, DARK)
        end
      end,
      interact=function()
        if not has_item("keycard") and not flags.keycard_taken and has_light then
          add_item("keycard")
          flags.keycard_taken = true
          show_msg("Keycard taped behind the pipe!", 90)
        elseif not has_light then
          show_msg("A thick pipe. Something taped on?", 60)
        else
          show_msg("Just a rusty pipe.", 40)
        end
      end
    },
    {x=90, y=42, w=24, h=36, name="corr_stairs",
      draw=function(s, hs)
        local c = has_light and WHITE or LIGHT
        -- stairs up
        for i = 0, 4 do
          rectf(s, hs.x, hs.y + i * 7, hs.w - i * 3, 6, has_light and DARK or BLACK)
          rect(s, hs.x, hs.y + i * 7, hs.w - i * 3, 6, c)
        end
        if has_light then text(s, "ROOF", hs.x + 2, hs.y - 6, LIGHT) end
      end,
      interact=function()
        if flags.lab_powered then
          snd_step()
          show_msg("Climbing to roof access...", 60)
          trans_timer = 15
          cur_room = 5
          cur_dir = DIR_N
        else
          show_msg("Sealed hatch. No power.", 60)
          snd_locked()
        end
      end
    }
  }

  -- ==========================================
  -- ROOM 3: OFFICE
  -- ==========================================

  -- North: desk with torn note
  hotspots[31] = {
    {x=40, y=52, w=60, h=16, name="office_desk",
      draw=function(s, hs)
        draw_desk(s, hs.x, hs.y)
        if not has_item("note_l") and has_light then
          rectf(s, hs.x + 22, hs.y + 2, 14, 9, WHITE)
          text(s, "74", hs.x + 24, hs.y + 3, DARK)
        end
      end,
      interact=function()
        if not has_item("note_l") and has_light then
          add_item("note_l")
          show_msg("Torn paper: '74..'", 60)
        elseif not has_light then
          show_msg("A desk. Papers on it?", 40)
        else
          show_msg("Old wooden desk. Scratched.", 40)
        end
      end
    }
  }

  -- East: filing cabinet (needs lockpick)
  hotspots[32] = {
    {x=55, y=42, w=22, h=30, name="office_cabinet",
      draw=function(s, hs)
        draw_filing_cabinet(s, hs.x, hs.y, flags.cabinet_open)
      end,
      interact=function()
        if flags.cabinet_open then
          if not has_item("evidence") then
            add_item("evidence")
            flags.evidence_found = true
            show_msg("Subject 26 file. PROOF.", 90)
          else
            show_msg("Empty cabinet.", 40)
          end
        elseif held_item == "lockpick" then
          flags.cabinet_open = true
          remove_item("lockpick")
          held_item = nil
          snd_solve()
          show_msg("Picked the lock! Files inside.", 90)
        else
          snd_locked()
          show_msg("Locked tight. Need a tool.", 60)
        end
      end
    },
    {x=100, y=44, w=30, h=26, name="office_bookshelf",
      draw=function(s, hs) draw_bookshelf(s, hs.x, hs.y) end,
      interact=function()
        if has_light then
          if not has_item("journal2") then
            add_item("journal2")
            flags.j2_read = true
            show_document("Journal, Day 15: 'Hiding these pages in the books. They check the cells now. The wipes are getting worse. I forget more each time. Writing is all I have left.'")
          else
            show_msg("Old medical texts. Dust.", 40)
          end
        else
          show_msg("Shelves. Something breathing?", 60)
        end
      end
    }
  }

  -- South: safe with combination lock
  hotspots[33] = {
    {x=58, y=48, w=24, h=20, name="office_safe",
      draw=function(s, hs)
        draw_safe(s, hs.x, hs.y, flags.safe_open)
        if not flags.safe_open and has_light then
          for i = 1, 4 do
            local dx = hs.x - 2 + (i - 1) * 7
            text(s, tostring(flags.safe_digits and flags.safe_digits[i] or 0), dx, hs.y + hs.h + 2, WHITE)
          end
          if flags.safe_mode then
            local ax = hs.x - 1 + ((flags.safe_sel or 1) - 1) * 7
            text(s, "^", ax, hs.y + hs.h + 8, WHITE)
          end
        end
      end,
      interact=function()
        if flags.safe_open then
          if not flags.master_key_taken then
            flags.master_key_taken = true
            add_item("master_key")
            show_msg("Master key! Heavy brass.", 90)
          else
            show_msg("Safe is empty now.", 40)
          end
          return
        end
        if not has_light then
          show_msg("Too dark to see the dial.", 60)
          return
        end
        flags.safe_mode = true
        if not flags.safe_digits then flags.safe_digits = {0,0,0,0} end
        if not flags.safe_sel then flags.safe_sel = 1 end
        show_msg("UP/DN:digit LR:sel A:try B:exit", 120)
      end
    }
  }

  -- West: door back to corridor + note_r
  hotspots[34] = {
    {x=60, y=42, w=28, h=36, name="office_door",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, true)
        if has_light then text(s, "CORR", hs.x + 2, hs.y + 14, LIGHT) end
      end,
      interact=function()
        snd_door()
        trans_timer = 15
        cur_room = 2
        cur_dir = DIR_E
      end
    },
    {x=30, y=62, w=16, h=10, name="office_note",
      draw=function(s, hs)
        if not has_item("note_r") and has_light then
          rectf(s, hs.x, hs.y, hs.w, hs.h, WHITE)
          text(s, "39", hs.x + 2, hs.y + 2, DARK)
        end
      end,
      interact=function()
        if not has_item("note_r") and has_light then
          add_item("note_r")
          show_msg("Torn paper: '..39'", 60)
        elseif not has_light then
          show_msg("Something on the floor.", 40)
        else
          show_msg("Floor tile. Cracked.", 40)
        end
      end
    }
  }

  -- ==========================================
  -- ROOM 4: LAB
  -- ==========================================

  -- North: terminal
  hotspots[41] = {
    {x=56, y=42, w=28, h=26, name="lab_terminal",
      draw=function(s, hs) draw_terminal(s, hs.x, hs.y, flags.lab_powered) end,
      interact=function()
        if flags.lab_powered then
          show_document("TERMINAL LOG: Subject 26 scheduled for final wipe. Status: ESCAPED CONTAINMENT. Alert: Entity protocol engaged. Deploy to sublevel 4.")
          flags.terminal_read = true
        else
          show_msg("Dead screen. No power.", 60)
        end
      end
    }
  }

  -- East: fuse box
  hotspots[42] = {
    {x=55, y=44, w=18, h=14, name="lab_fusebox",
      draw=function(s, hs) draw_fuse_box(s, hs.x, hs.y, flags.lab_powered) end,
      interact=function()
        if flags.lab_powered then
          show_msg("Fuse is good. Power is on.", 40)
        elseif held_item == "fuse_good" then
          flags.lab_powered = true
          remove_item("fuse_good")
          held_item = nil
          snd_solve()
          show_msg("POWER RESTORED! Terminal online.", 120)
        else
          show_msg("Empty fuse slot. Need a fuse.", 60)
        end
      end
    },
    {x=90, y=46, w=30, h=24, name="lab_shelf",
      draw=function(s, hs)
        local c = has_light and WHITE or LIGHT
        rect(s, hs.x, hs.y, hs.w, hs.h, c)
        rectf(s, hs.x + 1, hs.y + 1, hs.w - 2, hs.h - 2, has_light and DARK or BLACK)
        if not has_item("tape") and has_light then
          rectf(s, hs.x + 8, hs.y + 8, 10, 6, LIGHT)
          text(s, "T", hs.x + 11, hs.y + 9, WHITE)
        end
        if not has_item("fuse_dead") and has_light then
          rectf(s, hs.x + 4, hs.y + 16, 8, 4, LIGHT)
          text(s, "F", hs.x + 6, hs.y + 16, WHITE)
        end
      end,
      interact=function()
        if not has_item("tape") and has_light then
          add_item("tape")
          show_msg("Electrical tape.", 60)
        elseif not has_item("fuse_dead") and has_light then
          add_item("fuse_dead")
          show_msg("Blown fuse. Maybe fixable?", 60)
        elseif not has_light then
          show_msg("Shelves. Glass rattles.", 60)
        else
          show_msg("Lab supplies. Nothing useful.", 40)
        end
      end
    }
  }

  -- South: door to corridor
  hotspots[43] = {
    {x=60, y=42, w=28, h=36, name="lab_door",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, true)
        if has_light then text(s, "CORR", hs.x + 2, hs.y + 14, LIGHT) end
      end,
      interact=function()
        snd_door()
        trans_timer = 15
        cur_room = 2
        cur_dir = DIR_N
      end
    }
  }

  -- West: examination table + wire + rod
  hotspots[44] = {
    {x=35, y=50, w=50, h=20, name="lab_table",
      draw=function(s, hs)
        local c = has_light and WHITE or LIGHT
        local bg = has_light and LIGHT or DARK
        rectf(s, hs.x, hs.y, hs.w, 8, bg)
        rect(s, hs.x, hs.y, hs.w, 8, c)
        rectf(s, hs.x + 4, hs.y + 8, 3, 10, c)
        rectf(s, hs.x + hs.w - 7, hs.y + 8, 3, 10, c)
        if not has_item("wire") and has_light then
          line(s, hs.x + 10, hs.y + 2, hs.x + 20, hs.y + 5, WHITE)
        end
        if not has_item("metal_rod") and has_light then
          rectf(s, hs.x + 28, hs.y + 2, 12, 3, WHITE)
        end
      end,
      interact=function()
        if not has_item("wire") and has_light then
          add_item("wire")
          show_msg("Thin copper wire.", 60)
        elseif not has_item("metal_rod") and has_light then
          add_item("metal_rod")
          show_msg("Short iron rod.", 60)
        elseif not has_light then
          show_msg("A metal table. Tools on it?", 60)
        else
          show_msg("Examination table. Stained.", 40)
        end
      end
    },
    {x=35, y=42, w=20, h=8, name="lab_journal3",
      draw=function(s, hs)
        if not has_item("journal3") and has_light and flags.lab_powered then
          rectf(s, hs.x, hs.y, hs.w, hs.h, WHITE)
          text(s, "J", hs.x + 7, hs.y + 1, DARK)
        end
      end,
      interact=function()
        if not has_item("journal3") and has_light and flags.lab_powered then
          add_item("journal3")
          flags.j3_read = true
          show_document("Journal, Day 31: 'I remember now. I am Subject 26. The Entity is not supernatural. It is another subject, warped by failed wipes. They set it loose to recapture escapees. I must transmit the truth.'")
        elseif flags.lab_powered then
          show_msg("Empty drawer.", 40)
        end
      end
    }
  }

  -- ==========================================
  -- ROOM 5: ROOF ACCESS
  -- ==========================================

  -- North: transmitter antenna
  hotspots[51] = {
    {x=55, y=38, w=30, h=34, name="roof_antenna",
      draw=function(s, hs)
        draw_antenna(s, hs.x, hs.y, flags.broadcast_sent)
        if has_light then text(s, "XMIT", hs.x + 4, hs.y + 32, LIGHT) end
      end,
      interact=function()
        if flags.broadcast_sent then
          show_msg("Signal broadcasting. It's done.", 60)
          return
        end
        -- TRUTH ENDING: need evidence + all 3 journals
        if has_item("evidence") and flags.j1_read and flags.j2_read and flags.j3_read then
          flags.broadcast_sent = true
          ending_id = "truth"
          state = "ending"
          ending_timer = 0
          snd_solve()
          return
        end
        -- Partial
        if has_item("evidence") then
          show_msg("Need more documentation. Find all journal pages.", 90)
        else
          show_msg("Transmitter. Need evidence to broadcast.", 90)
        end
      end
    }
  }

  -- East: view + escape route
  hotspots[52] = {
    {x=40, y=40, w=60, h=30, name="roof_view",
      draw=function(s, hs)
        local c = has_light and LIGHT or DARK
        -- city skyline
        for i = 0, 5 do
          local bx = hs.x + i * 10
          local bh = 8 + (i * 3) % 12
          rectf(s, bx, hs.y + 30 - bh, 8, bh, c)
        end
        -- stars
        if tick % 3 == 0 then
          pix(s, hs.x + 10, hs.y + 2, WHITE)
          pix(s, hs.x + 35, hs.y + 6, WHITE)
          pix(s, hs.x + 50, hs.y + 3, WHITE)
        end
      end,
      interact=function()
        show_msg("The city below. You don't recognize it.", 90)
      end
    }
  }

  -- South: stairs down
  hotspots[53] = {
    {x=60, y=42, w=28, h=36, name="roof_stairs",
      draw=function(s, hs)
        local c = has_light and WHITE or LIGHT
        for i = 0, 4 do
          rectf(s, hs.x + i * 2, hs.y + i * 7, hs.w - i * 4, 6, has_light and DARK or BLACK)
          rect(s, hs.x + i * 2, hs.y + i * 7, hs.w - i * 4, 6, c)
        end
        if has_light then text(s, "DOWN", hs.x + 4, hs.y - 6, LIGHT) end
      end,
      interact=function()
        snd_step()
        trans_timer = 15
        cur_room = 2
        cur_dir = DIR_W
      end
    }
  }

  -- West: exit door (ESCAPE ending)
  hotspots[54] = {
    {x=55, y=42, w=32, h=36, name="roof_exit",
      draw=function(s, hs)
        local c = has_light and WHITE or LIGHT
        draw_door(s, hs.x, hs.y, hs.w, hs.h, false, c)
        if has_light then text(s, "EXIT", hs.x + 6, hs.y + 14, DARK) end
        if not flags.escaped then
          local lx = hs.x + hs.w // 2
          local ly = hs.y + hs.h - 8
          circ(s, lx, ly, 4, c)
          rectf(s, lx - 4, ly + 2, 9, 6, c)
        end
      end,
      interact=function()
        if held_item == "master_key" or has_item("master_key") then
          flags.escaped = true
          remove_item("master_key")
          ending_id = "escape"
          state = "ending"
          ending_timer = 0
          snd_solve()
          return
        end
        snd_locked()
        show_msg("Heavy lock. Need a master key.", 90)
      end
    }
  }
end

----------------------------------------------
-- SAFE PUZZLE (embedded in office)
----------------------------------------------
local function update_safe()
  if not flags.safe_mode then return end
  if not flags.safe_digits then flags.safe_digits = {0,0,0,0} end
  if not flags.safe_sel then flags.safe_sel = 1 end

  if btnp("left") then flags.safe_sel = clamp(flags.safe_sel - 1, 1, 4) snd_click() end
  if btnp("right") then flags.safe_sel = clamp(flags.safe_sel + 1, 1, 4) snd_click() end
  if btnp("up") then
    flags.safe_digits[flags.safe_sel] = (flags.safe_digits[flags.safe_sel] + 1) % 10
    snd_click()
  end
  if btnp("down") then
    flags.safe_digits[flags.safe_sel] = (flags.safe_digits[flags.safe_sel] - 1) % 10
    snd_click()
  end
  if btnp("a") then
    -- Code: 7439 (from combining note_l "74" + note_r "39")
    if flags.safe_digits[1] == 7 and flags.safe_digits[2] == 4 and
       flags.safe_digits[3] == 3 and flags.safe_digits[4] == 9 then
      flags.safe_open = true
      flags.safe_mode = false
      snd_solve()
      show_msg("CLICK! Safe opens!", 90)
    else
      snd_locked()
      show_msg("Wrong combination.", 60)
    end
  end
  if btnp("b") then
    flags.safe_mode = false
    show_msg("", 0)
  end
end

----------------------------------------------
-- ENTITY AI
----------------------------------------------
local function update_entity()
  if state ~= "play" then return end

  entity_timer = entity_timer + 1

  -- Grace period after scare
  if entity_grace > 0 then
    entity_grace = entity_grace - 1
    entity_visible = false
    return
  end

  -- Move between rooms periodically
  if entity_timer % 180 == 0 then
    local old_room = entity_room
    if math.random(100) < 40 then
      entity_room = cur_room
    else
      local adj = {[1]={2}, [2]={1,3,4}, [3]={2}, [4]={2}, [5]={2}}
      local options = adj[entity_room] or {2}
      entity_room = options[math.random(#options)]
    end
    entity_wall = math.random(1, 4)

    if old_room ~= entity_room then
      if entity_room == cur_room then
        sfx_note(2, "G2", 0.1)
        show_msg("...a door creaks...", 60)
      elseif old_room == cur_room then
        sfx_note(2, "D2", 0.06)
      end
    end
  end

  -- Change wall
  if entity_timer % 90 == 0 then
    entity_wall = math.random(1, 4)
  end

  local was_visible = entity_visible
  entity_visible = (entity_room == cur_room and entity_wall == cur_dir)

  if entity_visible then
    entity_appear_timer = entity_appear_timer + 1

    -- Stare too long = scare
    if entity_appear_timer > 90 then
      snd_scare(2)
      scare_flash = 6
      shake_timer = 12
      shake_amt = 4
      entity_encounters = entity_encounters + 1
      entity_grace = 120
      entity_appear_timer = 0
      entity_wall = ((entity_wall) % 4) + 1
      show_msg("IT SEES YOU", 60)

      -- CONSUMED ENDING: too many encounters
      if entity_encounters >= 5 then
        ending_id = "consumed"
        state = "ending"
        ending_timer = 0
        snd_scare(3)
        return
      end
    end

    -- Mini-scare on first spot
    if entity_appear_timer == 1 and not was_visible then
      if math.random(3) == 1 then
        scare_flash = 2
        shake_timer = 4
        shake_amt = 1
        snd_whisper()
      end
    end
  else
    entity_appear_timer = 0
  end

  -- Footstep sounds
  if entity_room == cur_room then
    if entity_timer % 15 == 0 then snd_entity_step() end
  elseif entity_timer % 30 == 0 then
    local adj = {[1]={2}, [2]={1,3,4}, [3]={2}, [4]={2}, [5]={2}}
    local near = adj[cur_room] or {}
    for _, r in ipairs(near) do
      if r == entity_room then
        sfx_note(3, "D4", 0.015)
        break
      end
    end
  end
end

----------------------------------------------
-- AMBIENT HORROR
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

  -- Heartbeat based on entity proximity
  if entity_room == cur_room then
    heartbeat_rate = math.min(heartbeat_rate + 0.02, 1.0)
  else
    heartbeat_rate = math.max(heartbeat_rate - 0.01, 0)
  end
  if entity_visible then
    heartbeat_rate = math.min(heartbeat_rate + 0.03, 1.0)
  end

  if heartbeat_rate > 0.1 then
    heartbeat_timer = heartbeat_timer - 1
    local interval = math.floor(lerp(30, 8, heartbeat_rate))
    if heartbeat_timer <= 0 then
      heartbeat_timer = interval
      snd_heartbeat(heartbeat_rate)
    end
  end

  -- Candle flicker
  if has_light then
    if entity_room == cur_room then
      if math.random(10) < 4 then candle_flicker = 2 + math.random(3) end
    elseif math.random(100) < 3 then
      candle_flicker = 1 + math.random(2)
    end
  end
  if candle_flicker > 0 then candle_flicker = candle_flicker - 1 end

  darkness_pulse = math.sin(tick * 0.05) * 0.5 + 0.5

  if scare_flash > 0 then scare_flash = scare_flash - 1 end
  if shake_timer > 0 then shake_timer = shake_timer - 1 end
end

----------------------------------------------
-- INPUT
----------------------------------------------
local function update_play_input()
  -- Document viewer takes priority
  if doc_text then
    if btnp("up") then doc_scroll = math.max(0, doc_scroll - 1) end
    if btnp("down") then doc_scroll = doc_scroll + 1 end
    if btnp("a") or btnp("b") then close_document() end
    return
  end

  -- Safe puzzle mode
  if flags.safe_mode then
    update_safe()
    return
  end

  -- Inventory toggle
  if btnp("b") then
    if combine_mode then
      combine_mode = false
      combine_first = nil
      show_msg("Cancelled.", 30)
    elseif held_item then
      held_item = nil
      show_msg("Item deselected.", 30)
    elseif inv_open then
      inv_open = false
    else
      inv_open = true
      inv_sel = 1
    end
    snd_click()
    return
  end

  -- Inventory navigation
  if inv_open then
    if btnp("up") then inv_sel = clamp(inv_sel - 1, 1, math.max(1, #inv)) snd_click() end
    if btnp("down") then inv_sel = clamp(inv_sel + 1, 1, math.max(1, #inv)) snd_click() end
    if btnp("a") and #inv > 0 then
      local item = inv[inv_sel]
      if combine_mode then
        -- Try combining
        local result = try_combine(combine_first, item)
        combine_mode = false
        if result then
          show_msg("Crafted: " .. result, 90)
        else
          show_msg("Can't combine those.", 60)
        end
        combine_first = nil
        inv_open = false
      else
        -- Item actions
        if item == "matches" and has_item("lens") then
          -- Auto-suggest craft
          combine_mode = true
          combine_first = item
          show_msg("Combine with? Pick another.", 90)
        elseif ITEMS[item] and ITEMS[item].desc then
          -- Show description, or hold item
          held_item = item
          inv_open = false
          show_msg("Using: " .. ITEMS[item].name, 60)
        else
          held_item = item
          inv_open = false
          show_msg("Using: " .. item, 60)
        end
      end
      snd_click()
    end
    -- Combine shortcut: select to toggle combine
    if btnp("start") and #inv > 1 and not combine_mode then
      combine_mode = true
      combine_first = inv[inv_sel]
      show_msg("Combine: pick second item", 90)
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
      cur_x = cur_x - CUR_SPEED * 3
    end
  end
  if btnp("right") then
    if cur_x >= W - 25 then
      cur_dir = (cur_dir % 4) + 1
      cur_x = 80
      snd_turn()
    else
      cur_x = cur_x + CUR_SPEED * 3
    end
  end

  if btn("up") then cur_y = cur_y - CUR_SPEED end
  if btn("down") then cur_y = cur_y + CUR_SPEED end

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
      if entity_room == cur_room then
        show_msg("...you hear breathing...", 45)
      else
        show_msg("Nothing there.", 30)
      end
    end
  end

  -- Pause
  if btnp("start") or btnp("select") then
    state = "paused"
  end
end

----------------------------------------------
-- DRAW GAME VIEW
----------------------------------------------
local function draw_game(s)
  cls(s, BLACK)

  -- Scare flash: full screen white with face
  if scare_flash > 4 then
    cls(s, WHITE)
    circ(s, 70, 50, 3, BLACK)
    circ(s, 90, 50, 3, BLACK)
    line(s, 74, 62, 86, 62, BLACK)
    return
  end

  -- Room base
  draw_room_base(s)

  -- Hotspots for current wall
  local spots = get_wall_hotspots(cur_room, cur_dir)
  for _, hs in ipairs(spots) do
    if hs.draw then hs.draw(s, hs) end
  end

  -- Entity eyes on wall
  if entity_visible and entity_grace <= 0 then
    local intensity = entity_appear_timer / 90.0
    draw_entity_eyes(s, intensity)
  end

  -- Shadow hint when entity in adjacent room
  if entity_room ~= cur_room then
    local adj = {[1]={2}, [2]={1,3,4}, [3]={2}, [4]={2}, [5]={2}}
    local near = adj[cur_room] or {}
    for _, r in ipairs(near) do
      if r == entity_room then
        draw_entity_shadow(s)
        break
      end
    end
  end

  -- Direction arrows
  local ac = has_light and LIGHT or DARK
  text(s, "<", 4, 55, ac)
  text(s, ">", W - 10, 55, ac)

  -- Cursor crosshair
  local cf = tick % 20 < 10
  local cc = cf and WHITE or LIGHT
  line(s, cur_x - 4, cur_y, cur_x - 1, cur_y, cc)
  line(s, cur_x + 1, cur_y, cur_x + 4, cur_y, cc)
  line(s, cur_x, cur_y - 4, cur_x, cur_y - 1, cc)
  line(s, cur_x, cur_y + 1, cur_x, cur_y + 4, cc)

  -- HUD bar
  rectf(s, 0, H - 10, W, 10, BLACK)
  line(s, 0, H - 10, W, H - 10, has_light and LIGHT or DARK)

  local room_names = {"CELL", "CORRIDOR", "OFFICE", "LAB", "ROOF"}
  text(s, room_names[cur_room] or "???", 2, H - 8, WHITE)
  text(s, DIR_NAMES[cur_dir], W - 30, H - 8, LIGHT)

  if held_item then
    local n = ITEMS[held_item] and ITEMS[held_item].name or held_item
    text(s, "[" .. n .. "]", 40, H - 8, WHITE)
  end

  -- Heartbeat pulsing border
  if heartbeat_rate > 0.3 then
    local pulse = math.sin(tick * heartbeat_rate * 0.3) > 0.3
    if pulse then
      local pc = heartbeat_rate > 0.7 and LIGHT or DARK
      rect(s, 0, 0, W, H - 10, pc)
    end
  end

  -- Encounter warning marks
  if entity_encounters > 0 then
    for i = 1, entity_encounters do
      pix(s, W - 4, H - 9 - i * 2, WHITE)
    end
  end

  -- Document overlay
  if doc_text then
    draw_ui_box(8, 8, W - 16, H - 24, WHITE, BLACK)
    local max_lines = 8
    for i = 1, max_lines do
      local li = i + doc_scroll
      if doc_lines[li] then
        text(s, doc_lines[li], 14, 12 + (i - 1) * 9, LIGHT)
      end
    end
    text(s, "A/B:Close", W - 50, H - 14, DARK)
    if #doc_lines > max_lines then
      text(s, "UP/DN:Scroll", 14, H - 14, DARK)
    end
  end

  -- Inventory overlay
  if inv_open then
    local iw, ih = 70, 10 + #inv * 10
    local ix, iy = W - iw - 4, 4
    draw_ui_box(ix, iy, iw, ih, LIGHT, BLACK)
    text(s, "INVENTORY", ix + 4, iy + 2, WHITE)
    for i, item in ipairs(inv) do
      local sel = (i == inv_sel)
      local ny = iy + 2 + i * 10 - 2
      if sel then rectf(s, ix + 1, ny - 1, iw - 2, 10, DARK) end
      local icon = ITEMS[item] and ITEMS[item].icon or "?"
      local name = ITEMS[item] and ITEMS[item].name or item
      text(s, (sel and ">" or " ") .. icon .. " " .. name, ix + 3, ny, sel and WHITE or LIGHT)
    end
    if #inv == 0 then
      text(s, " (empty)", ix + 3, iy + 12, DARK)
    end
    if combine_mode then
      text(s, "COMBINE MODE", ix + 4, iy + ih - 8, WHITE)
    end
  end

  -- Message
  if msg_timer > 0 and msg_text ~= "" then
    local bw = W - 8
    draw_ui_box(4, 2, bw, 12, DARK, BLACK)
    text(s, msg_text, 8, 4, WHITE)
  end
end

----------------------------------------------
-- TITLE SCREEN
----------------------------------------------
local function draw_title(s)
  cls(s, BLACK)
  local flick = tick % 90

  -- Atmospheric background
  if tick % 4 < 2 then
    for i = 1, 8 do
      local sx = (i * 23 + tick) % W
      local sy = (i * 11 + tick * 2) % (H - 30) + 20
      pix(s, sx, sy, DARK)
    end
  end

  -- Title
  if flick < 70 or flick > 80 then
    text_c("THE DARK ROOM", 16, WHITE)
  end
  text_c("WITNESS", 28, LIGHT)

  -- Eye
  circ(s, 80, 50, 12, LIGHT)
  circ(s, 80, 50, 8, DARK)
  rectf(s, 76, 48, 8, 4, WHITE)
  pix(s, 80, 50, BLACK)

  -- Entity hint: eyes blink in background
  if tick % 60 > 5 and tick % 60 < 15 then
    pix(s, 30, 45, DARK)
    pix(s, 32, 45, DARK)
  end

  text_c("PRESS START", 76, (tick % 40 < 25) and WHITE or DARK)
  text_c("A:Interact B:Inventory", 90, DARK)
  text_c("3 endings. Survive. Discover.", 104, DARK)
end

----------------------------------------------
-- ENDING SCREENS
----------------------------------------------
local function draw_ending_escape(s)
  cls(s, BLACK)
  -- Dawn light
  for i = 0, 30 do
    local c = i < 10 and WHITE or (i < 20 and LIGHT or DARK)
    line(s, 0, 40 + i, W, 40 + i, c)
  end
  rectf(s, 0, 71, W, H - 71, DARK)

  text_c("ENDING: ESCAPE", 10, WHITE)
  text_c("You step into the dawn.", 25, LIGHT)
  text_c("Free, but memories lost.", 80, LIGHT)
  text_c("The truth remains buried.", 90, DARK)
  if ending_timer > 120 then
    text_c("PRESS START", 108, (tick % 40 < 25) and WHITE or BLACK)
  end
end

local function draw_ending_consumed(s)
  cls(s, BLACK)
  -- Entity consuming screen
  local spread = clamp(ending_timer * 2, 0, 80)
  circ(s, 80, 50, spread, DARK)
  if spread > 20 then
    -- Entity face grows
    local ex, ey = 80, 50
    pix(s, ex - 5, ey - 3, WHITE)
    pix(s, ex - 4, ey - 3, WHITE)
    pix(s, ex + 4, ey - 3, WHITE)
    pix(s, ex + 5, ey - 3, WHITE)
    if spread > 40 then
      for mx = -3, 3 do pix(s, ex + mx, ey + 4, WHITE) end
    end
  end

  text_c("ENDING: CONSUMED", 4, WHITE)
  if ending_timer > 30 then
    text_c("The Entity takes you.", 86, LIGHT)
  end
  if ending_timer > 60 then
    text_c("You become part of the walls.", 96, DARK)
  end
  if ending_timer > 120 then
    text_c("PRESS START", 108, (tick % 40 < 25) and WHITE or BLACK)
  end
end

local function draw_ending_truth(s)
  cls(s, BLACK)
  -- Data cascade
  for i = 1, 20 do
    local sx = (i * 19 + tick * 2) % W
    local sy = (i * 7 + tick) % H
    local ch = string.char(48 + (tick + i) % 26)
    text(s, ch, sx, sy, DARK)
  end

  if ending_timer > 30 then
    draw_ui_box(20, 20, 120, 60, WHITE, BLACK)
    text_c("ENDING: THE TRUTH", 25, WHITE)
    text_c("Transmission sent.", 38, LIGHT)
    text_c("Evidence broadcast to", 48, LIGHT)
    text_c("every screen in the city.", 56, LIGHT)
    text_c("Project LETHE exposed.", 68, WHITE)
  end
  if ending_timer > 60 then
    text_c("You remember everything.", 85, LIGHT)
    text_c("You are Subject 26.", 95, WHITE)
  end
  if ending_timer > 150 then
    text_c("PRESS START", 108, (tick % 40 < 25) and WHITE or BLACK)
  end
end

----------------------------------------------
-- DEMO MODE
----------------------------------------------
local demo_actions = {
  {act="look",   dur=60},   -- look around cell
  {act="pickup", dur=30},   -- get matches
  {act="turn",   dur=20},   -- turn
  {act="read",   dur=60},   -- read wall
  {act="turn",   dur=20},
  {act="move",   dur=30},   -- go to corridor
  {act="look",   dur=90},
  {act="end",    dur=1},
}

local function update_demo()
  demo_wait = demo_wait - 1
  if demo_wait > 0 then return end
  demo_step = demo_step + 1
  if demo_step > #demo_actions then
    state = "title"
    idle_timer = 0
    return
  end

  local da = demo_actions[demo_step]
  demo_wait = da.dur

  if da.act == "look" then
    cur_x = 60 + math.random(40)
    cur_y = 40 + math.random(30)
  elseif da.act == "pickup" then
    if not has_item("matches") then add_item("matches") end
    show_msg("Demo: Got matches", 45)
  elseif da.act == "turn" then
    cur_dir = (cur_dir % 4) + 1
    snd_turn()
  elseif da.act == "read" then
    show_msg("Demo: 'THEY ERASE YOU...'", 50)
  elseif da.act == "move" then
    if cur_room == 1 then
      cur_room = 2
      cur_dir = DIR_S
      show_msg("Demo: Corridor", 40)
    end
  elseif da.act == "end" then
    state = "title"
    idle_timer = 0
  end
end

----------------------------------------------
-- GAME INIT
----------------------------------------------
local function init_game()
  cur_room = 1
  cur_dir = DIR_W
  cur_x, cur_y = 80, 60
  inv = {}
  inv_open = false
  inv_sel = 1
  held_item = nil
  combine_mode = false
  combine_first = nil
  has_light = false
  flags = {}
  msg_text = ""
  msg_timer = 0
  doc_text = nil
  doc_lines = {}
  trans_timer = 0
  entity_room = 3
  entity_wall = DIR_N
  entity_timer = 0
  entity_visible = false
  entity_appear_timer = 0
  entity_grace = 0
  entity_encounters = 0
  heartbeat_rate = 0
  heartbeat_timer = 0
  amb_drip_timer = 60
  amb_creak_timer = 120
  scare_flash = 0
  shake_timer = 0
  shake_amt = 0
  candle_flicker = 0
  darkness_pulse = 0
  ending_id = nil
  ending_timer = 0
  demo_step = 0
  demo_wait = 0
  build_hotspots()
end

----------------------------------------------
-- MAIN CALLBACKS
----------------------------------------------
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

  -- Transition fade
  if trans_timer > 0 then
    trans_timer = trans_timer - 1
    if trans_timer == 0 then build_hotspots() end
    return
  end

  if state == "title" then
    idle_timer = idle_timer + 1
    if btnp("start") or btnp("a") then
      init_game()
      state = "play"
      idle_timer = 0
      show_msg("You wake in darkness. No memories.", 120)
      return
    end
    if idle_timer >= DEMO_IDLE then
      state = "demo"
      init_game()
      demo_step = 0
      demo_wait = 30
      return
    end

  elseif state == "demo" then
    update_demo()
    update_entity()
    update_ambient()
    if btnp("start") or btnp("a") then
      state = "title"
      idle_timer = 0
      init_game()
    end

  elseif state == "play" then
    if msg_timer > 0 and not doc_text and not flags.safe_mode then
      msg_timer = msg_timer - 1
    end
    update_play_input()
    update_entity()
    update_ambient()

  elseif state == "paused" then
    if btnp("start") or btnp("a") then
      state = "play"
    end

  elseif state == "ending" then
    ending_timer = ending_timer + 1
    if ending_timer > 120 and (btnp("start") or btnp("a")) then
      state = "title"
      idle_timer = 0
      init_game()
    end
  end
end

function _draw()
  S = screen()
  cls(S, BLACK)

  if state == "title" then
    draw_title(S)

  elseif state == "demo" then
    draw_game(S)
    -- Demo overlay
    rectf(S, 0, 0, W, 8, BLACK)
    text_c("DEMO", 0, DARK)

  elseif state == "play" then
    draw_game(S)

  elseif state == "paused" then
    draw_game(S)
    draw_ui_box(40, 40, 80, 30, WHITE, BLACK)
    text_c("PAUSED", 46, WHITE)
    text_c("START to resume", 56, LIGHT)

  elseif state == "ending" then
    if ending_id == "escape" then
      draw_ending_escape(S)
    elseif ending_id == "consumed" then
      draw_ending_consumed(S)
    elseif ending_id == "truth" then
      draw_ending_truth(S)
    end
  end

  -- Transition overlay
  if trans_timer > 0 then
    local alpha = trans_timer / 15.0
    if alpha > 0.5 then
      cls(S, BLACK)
    else
      for y = 0, H - 1, 2 do
        for x = 0, W - 1, 2 do
          pix(S, x, y, BLACK)
        end
      end
    end
  end

  -- Scare flash overlay (low intensity)
  if scare_flash > 0 and scare_flash <= 4 then
    if scare_flash > 2 then
      rect(S, 0, 0, W, H, WHITE)
    end
  end
end
