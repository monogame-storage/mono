-- THE DARK ROOM
-- First-person mystery adventure
-- Agent 09 | 160x120 | 2-bit (4 shades) | 30fps
-- D-Pad: Move cursor / Turn | A: Interact | B: Inventory | START: Start/Pause

----------------------------------------------
-- CONSTANTS
----------------------------------------------
local W, H = 160, 120
local BLACK, DARK, LIGHT, WHITE = 0, 1, 2, 3

-- Directions: 1=North, 2=East, 3=South, 4=West
local DIR_N, DIR_E, DIR_S, DIR_W = 1, 2, 3, 4
local DIR_NAMES = {"NORTH", "EAST", "SOUTH", "WEST"}

-- Cursor
local CUR_SPEED = 2

-- Demo
local DEMO_IDLE = 300  -- 10 seconds at 30fps

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
local function snd_turn()
  sfx_note(0, "C2", 0.05)
end

local function snd_step()
  sfx_note(0, "G2", 0.04)
  sfx_noise(1, 0.03)
end

local function snd_pickup()
  sfx_note(0, "C5", 0.06)
  sfx_note(0, "E5", 0.06)
  sfx_note(0, "G5", 0.06)
end

local function snd_door()
  sfx_note(0, "C2", 0.15)
  sfx_note(1, "E2", 0.1)
end

local function snd_locked()
  sfx_noise(0, 0.08)
  sfx_note(1, "C2", 0.08)
end

local function snd_solve()
  sfx_note(0, "C5", 0.1)
  sfx_note(0, "E5", 0.1)
  sfx_note(0, "G5", 0.1)
  sfx_note(0, "C6", 0.2)
end

local function snd_ambient()
  -- subtle drip every so often
  if frame() % 120 == 0 then
    sfx_note(1, "B6", 0.02)
  end
  if frame() % 180 == 60 then
    sfx_note(1, "G6", 0.015)
  end
end

local function snd_click()
  sfx_note(0, "A4", 0.03)
end

----------------------------------------------
-- GLOBAL STATE
----------------------------------------------
local state = "title"   -- title, demo, play, paused, win
local idle_timer = 0
local msg_text = ""
local msg_timer = 0
local has_light = false  -- candle lit?

-- Player state
local cur_room = 1       -- 1=bedroom, 2=hallway, 3=study, 4=kitchen
local cur_dir = DIR_N    -- facing direction
local cur_x, cur_y = 80, 60  -- cursor position

-- Inventory
local inv = {}           -- list of item names
local inv_open = false
local inv_sel = 1
local held_item = nil    -- item selected from inventory to use

-- Puzzle state
local flags = {
  nightstand_open = false,
  has_matchbox = false,
  has_small_key = false,
  has_candle = false,
  candle_lit = false,
  cabinet_open = false,
  has_journal = false,
  safe_open = false,
  has_master_key = false,
  painting_seen = false,
  safe_digits = {0, 0, 0},
  safe_sel = 1,
  safe_mode = false,
  escaped = false,
}

-- Demo state
local demo_t = 0
local demo_actions = {}

-- Transition effect
local trans_timer = 0
local trans_dir = 0  -- 0=none, 1=in, -1=out

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
  if not has_item(name) then
    table.insert(inv, name)
    snd_pickup()
    show_msg("Got: " .. name, 60)
  end
end

local function remove_item(name)
  local found, idx = has_item(name)
  if found then
    table.remove(inv, idx)
    if held_item == name then held_item = nil end
  end
end

----------------------------------------------
-- DITHER PATTERNS for shading
----------------------------------------------
local function dither_pixel(s, x, y, c1, c2, pattern)
  -- pattern: 0=solid c1, 1=25% c2, 2=50%, 3=75% c2, 4=solid c2
  if pattern <= 0 then
    pix(s, x, y, c1)
  elseif pattern >= 4 then
    pix(s, x, y, c2)
  else
    local checker = (x + y) % 2
    local fine = (x % 2 + y % 2 * 2) -- 0-3 pattern
    if pattern == 1 then
      pix(s, x, y, (fine == 0) and c2 or c1)
    elseif pattern == 2 then
      pix(s, x, y, checker == 0 and c2 or c1)
    else -- 3
      pix(s, x, y, (fine == 0) and c1 or c2)
    end
  end
end

local function dither_rectf(s, rx, ry, rw, rh, c1, c2, pattern)
  for dy = 0, rh - 1 do
    for dx = 0, rw - 1 do
      dither_pixel(s, rx + dx, ry + dy, c1, c2, pattern)
    end
  end
end

----------------------------------------------
-- WALL RENDERING - First Person View
----------------------------------------------

-- Draw floor and ceiling with perspective
local function draw_room_base(s)
  local fc = has_light and DARK or BLACK
  local cc = has_light and DARK or BLACK
  local wc = has_light and LIGHT or DARK

  -- Ceiling
  for y = 0, 39 do
    local depth = y / 40.0
    local shade = has_light and (depth < 0.3 and 2 or 1) or (depth < 0.3 and 1 or 0)
    for x = 0, W - 1 do
      local checker = (math.floor(x / 8) + math.floor(y / 4)) % 2
      if checker == 0 then
        pix(s, x, y, shade)
      else
        pix(s, x, y, clamp(shade - 1, 0, 3))
      end
    end
  end

  -- Floor
  for y = 80, H - 11 do
    local depth = (y - 80) / 30.0
    local shade = has_light and (depth > 0.6 and 2 or 1) or (depth > 0.6 and 1 or 0)
    for x = 0, W - 1 do
      local checker = (math.floor(x / 8) + math.floor((y - 80) / 4)) % 2
      if checker == 0 then
        pix(s, x, y, shade)
      else
        pix(s, x, y, clamp(shade - 1, 0, 3))
      end
    end
  end

  -- Back wall fill
  local wallc = has_light and LIGHT or DARK
  rectf(s, 0, 40, W, 40, wallc)

  -- Wall border lines for perspective
  local bc = has_light and WHITE or LIGHT
  -- Left wall edge
  line(s, 0, 0, 20, 40, bc)
  line(s, 0, H - 10, 20, 80, bc)
  -- Right wall edge
  line(s, W - 1, 0, W - 21, 40, bc)
  line(s, W - 1, H - 10, W - 21, 80, bc)
  -- Top/bottom wall edges
  line(s, 20, 40, W - 21, 40, bc)
  line(s, 20, 80, W - 21, 80, bc)

  -- Side wall fills
  for y = 0, H - 11 do
    local t = y / (H - 10)
    local lx = math.floor(t < 0.33 and (t / 0.33 * 20) or (t > 0.67 and ((1 - t) / 0.33 * 20) or 20))
    local sc = has_light and DARK or BLACK
    for x = 0, lx - 1 do
      pix(s, x, y, sc)
    end
    for x = W - lx, W - 1 do
      pix(s, x, y, sc)
    end
  end
end

----------------------------------------------
-- HOTSPOT DEFINITIONS
-- Each wall has hotspots: {x, y, w, h, name, draw_fn, interact_fn}
----------------------------------------------
local hotspots = {}

local function get_wall_hotspots(room, dir)
  local key = room * 10 + dir
  return hotspots[key] or {}
end

-- Draw a simple door shape
local function draw_door(s, x, y, w, h, open, col)
  local c = col or (has_light and WHITE or LIGHT)
  local bg = has_light and DARK or BLACK
  rect(s, x, y, w, h, c)
  if open then
    rectf(s, x + 2, y + 2, w - 4, h - 4, BLACK)
  else
    rectf(s, x + 2, y + 2, w - 4, h - 4, bg)
    -- door handle
    rectf(s, x + w - 6, y + h // 2 - 1, 2, 3, c)
  end
end

-- Draw a box/container
local function draw_box(s, x, y, w, h, open)
  local c = has_light and WHITE or LIGHT
  local bg = has_light and LIGHT or DARK
  rect(s, x, y, w, h, c)
  if open then
    line(s, x, y, x + w, y + 4, c)
    rectf(s, x + 1, y + 5, w - 2, h - 6, bg)
  else
    rectf(s, x + 1, y + 1, w - 2, h - 2, bg)
  end
end

-- Draw a painting frame
local function draw_painting(s, x, y, w, h)
  local c = has_light and WHITE or LIGHT
  local bg = has_light and DARK or BLACK
  rect(s, x, y, w, h, c)
  rectf(s, x + 2, y + 2, w - 4, h - 4, bg)
  -- simple landscape inside
  line(s, x + 3, y + h - 6, x + w // 2, y + 4, has_light and LIGHT or DARK)
  line(s, x + w // 2, y + 4, x + w - 3, y + h - 6, has_light and LIGHT or DARK)
end

-- Draw a bed
local function draw_bed(s, x, y)
  local c = has_light and WHITE or LIGHT
  local bg = has_light and LIGHT or DARK
  -- frame
  rectf(s, x, y, 50, 20, bg)
  rect(s, x, y, 50, 20, c)
  -- pillow
  rectf(s, x + 2, y + 2, 14, 8, c)
  -- blanket line
  line(s, x, y + 12, x + 50, y + 12, c)
end

-- Draw a desk
local function draw_desk(s, x, y)
  local c = has_light and WHITE or LIGHT
  local bg = has_light and LIGHT or DARK
  rectf(s, x, y, 60, 16, bg)
  rect(s, x, y, 60, 16, c)
  -- legs
  rectf(s, x + 2, y + 16, 4, 8, c)
  rectf(s, x + 54, y + 16, 4, 8, c)
end

-- Draw a bookshelf
local function draw_bookshelf(s, x, y)
  local c = has_light and WHITE or LIGHT
  local bg = has_light and LIGHT or DARK
  rect(s, x, y, 30, 36, c)
  -- shelves
  for i = 0, 2 do
    line(s, x, y + 12 * (i + 1), x + 30, y + 12 * (i + 1), c)
    -- books
    for b = 0, 4 do
      local bx = x + 2 + b * 5
      local by = y + 12 * i + 2
      local bh = 8 + (b % 3)
      rectf(s, bx, by, 4, bh, (b % 2 == 0) and c or bg)
    end
  end
end

-- Draw a safe
local function draw_safe(s, x, y, open)
  local c = has_light and WHITE or LIGHT
  rect(s, x, y, 24, 20, c)
  if open then
    rectf(s, x + 1, y + 1, 22, 18, BLACK)
  else
    rectf(s, x + 1, y + 1, 22, 18, has_light and DARK or BLACK)
    -- dial
    circ(s, x + 12, y + 10, 5, c)
    pix(s, x + 12, y + 6, c)
  end
end

-- Draw a fridge
local function draw_fridge(s, x, y)
  local c = has_light and WHITE or LIGHT
  rect(s, x, y, 20, 36, c)
  line(s, x, y + 14, x + 20, y + 14, c)
  -- handle
  rectf(s, x + 16, y + 4, 2, 8, c)
  rectf(s, x + 16, y + 18, 2, 12, c)
end

-- Draw a counter
local function draw_counter(s, x, y)
  local c = has_light and WHITE or LIGHT
  local bg = has_light and LIGHT or DARK
  rectf(s, x, y, 70, 12, bg)
  rect(s, x, y, 70, 12, c)
  rectf(s, x + 2, y + 12, 4, 10, c)
  rectf(s, x + 64, y + 12, 4, 10, c)
end

----------------------------------------------
-- BUILD HOTSPOT DATA
----------------------------------------------
local function build_hotspots()
  hotspots = {}

  -- ROOM 1: BEDROOM
  -- North wall: locked door to hallway
  hotspots[11] = {
    {x=60, y=42, w=28, h=36, name="door_hallway",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, false)
        if not has_light then
          text(s, "?", hs.x + 12, hs.y + 14, LIGHT)
        else
          text(s, "DOOR", hs.x + 4, hs.y + 14, DARK)
        end
      end,
      interact=function()
        if flags.has_small_key or flags.nightstand_open then
          snd_door()
          show_msg("The door creaks open...", 60)
          trans_timer = 15
          cur_room = 2
          cur_dir = DIR_S
          return
        end
        snd_locked()
        show_msg("Locked. Need a key.", 60)
      end
    }
  }

  -- East wall: boarded window
  hotspots[12] = {
    {x=55, y=44, w=40, h=28, name="window",
      draw=function(s, hs)
        local c = has_light and WHITE or LIGHT
        rect(s, hs.x, hs.y, hs.w, hs.h, c)
        -- boards
        for i = 0, 3 do
          line(s, hs.x, hs.y + i * 7, hs.x + hs.w, hs.y + i * 7, c)
        end
        -- X nails
        line(s, hs.x, hs.y, hs.x + hs.w, hs.y + hs.h, c)
        line(s, hs.x + hs.w, hs.y, hs.x, hs.y + hs.h, c)
      end,
      interact=function()
        show_msg("Boarded shut. No way out.", 60)
      end
    }
  }

  -- South wall: bed
  hotspots[13] = {
    {x=50, y=50, w=50, h=20, name="bed",
      draw=function(s, hs) draw_bed(s, hs.x, hs.y) end,
      interact=function()
        show_msg("Your bed. Still warm.", 60)
      end
    }
  }

  -- West wall: nightstand with drawer
  hotspots[14] = {
    {x=55, y=48, w=30, h=24, name="nightstand",
      draw=function(s, hs)
        draw_box(s, hs.x, hs.y, hs.w, hs.h, flags.nightstand_open)
        if not flags.nightstand_open then
          text(s, "DRAWER", hs.x + 2, hs.y + 8, has_light and DARK or BLACK)
        end
      end,
      interact=function()
        if not flags.nightstand_open then
          flags.nightstand_open = true
          flags.has_matchbox = true
          flags.has_small_key = true
          add_item("MATCHBOX")
          add_item("SMALL KEY")
          show_msg("Found matchbox and key!", 90)
          snd_solve()
        else
          show_msg("Empty drawer.", 60)
        end
      end
    }
  }

  -- ROOM 2: HALLWAY
  -- North wall: door to study
  hotspots[21] = {
    {x=60, y=42, w=28, h=36, name="door_study",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, false)
        if has_light then text(s, "STUDY", hs.x + 2, hs.y + 14, DARK) end
      end,
      interact=function()
        snd_door()
        show_msg("Entering the study...", 60)
        trans_timer = 15
        cur_room = 3
        cur_dir = DIR_S
      end
    }
  }

  -- East wall: painting with year clue
  hotspots[22] = {
    {x=50, y=44, w=40, h=28, name="painting",
      draw=function(s, hs)
        draw_painting(s, hs.x, hs.y, hs.w, hs.h)
        if has_light then
          text(s, "1947", hs.x + 10, hs.y + hs.h + 2, WHITE)
        end
      end,
      interact=function()
        flags.painting_seen = true
        if has_light then
          show_msg("A landscape dated '1947'.", 90)
        else
          show_msg("Too dark to see clearly.", 60)
        end
      end
    }
  }

  -- South wall: door back to bedroom
  hotspots[23] = {
    {x=60, y=42, w=28, h=36, name="door_bedroom",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, true)
        if has_light then text(s, "BED", hs.x + 4, hs.y + 14, LIGHT) end
      end,
      interact=function()
        snd_door()
        trans_timer = 15
        cur_room = 1
        cur_dir = DIR_N
      end
    }
  }

  -- West wall: locked cabinet
  hotspots[24] = {
    {x=55, y=46, w=30, h=28, name="cabinet",
      draw=function(s, hs)
        draw_box(s, hs.x, hs.y, hs.w, hs.h, flags.cabinet_open)
        if not flags.cabinet_open then
          -- lock symbol
          local lx = hs.x + 12
          local ly = hs.y + 10
          circ(s, lx, ly, 3, has_light and WHITE or LIGHT)
          rectf(s, lx - 3, ly + 2, 7, 5, has_light and WHITE or LIGHT)
        end
      end,
      interact=function()
        if flags.cabinet_open then
          show_msg("Empty cabinet.", 60)
          return
        end
        if held_item == "SMALL KEY" then
          flags.cabinet_open = true
          remove_item("SMALL KEY")
          add_item("CANDLE")
          flags.has_candle = true
          held_item = nil
          show_msg("Unlocked! Found a candle.", 90)
          snd_solve()
        else
          snd_locked()
          show_msg("Locked. Need a small key.", 60)
        end
      end
    }
  }

  -- ROOM 3: STUDY
  -- North wall: bookshelf
  hotspots[31] = {
    {x=50, y=42, w=30, h=36, name="bookshelf",
      draw=function(s, hs)
        draw_bookshelf(s, hs.x, hs.y)
      end,
      interact=function()
        if has_light then
          show_msg("Old books. Nothing useful.", 60)
        else
          show_msg("Can't see the titles.", 60)
        end
      end
    }
  }

  -- East wall: safe
  hotspots[32] = {
    {x=58, y=48, w=24, h=20, name="safe",
      draw=function(s, hs)
        draw_safe(s, hs.x, hs.y, flags.safe_open)
        if not flags.safe_open and has_light then
          -- draw combo digits
          for i = 1, 3 do
            local dx = hs.x + 2 + (i - 1) * 8
            text(s, tostring(flags.safe_digits[i]), dx, hs.y + hs.h + 2, WHITE)
          end
          -- selector arrow
          local ax = hs.x + 3 + (flags.safe_sel - 1) * 8
          text(s, "^", ax, hs.y + hs.h + 8, WHITE)
        end
      end,
      interact=function()
        if flags.safe_open then
          show_msg("Safe is empty now.", 60)
          return
        end
        if not has_light then
          show_msg("Too dark to read the dial.", 60)
          return
        end
        -- Enter safe mode
        flags.safe_mode = true
        show_msg("UP/DOWN: digit  LEFT/RIGHT: select  A: try", 120)
      end
    }
  }

  -- South wall: door back to hallway
  hotspots[33] = {
    {x=60, y=42, w=28, h=36, name="door_hallway2",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, true)
        if has_light then text(s, "HALL", hs.x + 4, hs.y + 14, LIGHT) end
      end,
      interact=function()
        snd_door()
        trans_timer = 15
        cur_room = 2
        cur_dir = DIR_N
      end
    }
  }

  -- West wall: desk with journal
  hotspots[34] = {
    {x=40, y=52, w=60, h=16, name="desk",
      draw=function(s, hs)
        draw_desk(s, hs.x, hs.y)
        -- journal on desk
        if not flags.has_journal then
          local c = has_light and WHITE or LIGHT
          rectf(s, hs.x + 22, hs.y + 2, 16, 10, c)
          text(s, "J", hs.x + 27, hs.y + 3, has_light and DARK or BLACK)
        end
      end,
      interact=function()
        if not flags.has_journal then
          flags.has_journal = true
          add_item("JOURNAL")
          show_msg("'The year we arrived, reversed.'", 120)
        else
          show_msg("An old wooden desk.", 60)
        end
      end
    }
  }

  -- ROOM 4: KITCHEN
  -- North wall: door back to hallway (from hallway east wall)
  hotspots[41] = {
    {x=60, y=42, w=28, h=36, name="door_hallway3",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, true)
        if has_light then text(s, "HALL", hs.x + 4, hs.y + 14, LIGHT) end
      end,
      interact=function()
        snd_door()
        trans_timer = 15
        cur_room = 2
        cur_dir = DIR_E
      end
    }
  }

  -- East wall: fridge with note
  hotspots[42] = {
    {x=60, y=40, w=20, h=36, name="fridge",
      draw=function(s, hs)
        draw_fridge(s, hs.x, hs.y)
      end,
      interact=function()
        if has_light then
          show_msg("A note: 'Don't forget 749'", 90)
        else
          show_msg("A cold metal box.", 60)
        end
      end
    }
  }

  -- South wall: back door (exit)
  hotspots[43] = {
    {x=55, y=42, w=32, h=36, name="back_door",
      draw=function(s, hs)
        local c = has_light and WHITE or LIGHT
        draw_door(s, hs.x, hs.y, hs.w, hs.h, false, c)
        if has_light then
          text(s, "EXIT", hs.x + 6, hs.y + 14, DARK)
        end
        -- heavy lock symbol
        local lx = hs.x + hs.w // 2
        local ly = hs.y + hs.h - 8
        if not flags.escaped then
          circ(s, lx, ly, 4, c)
          rectf(s, lx - 4, ly + 2, 9, 6, c)
        end
      end,
      interact=function()
        if held_item == "MASTER KEY" then
          flags.escaped = true
          remove_item("MASTER KEY")
          snd_solve()
          state = "win"
          show_msg("ESCAPED!", 300)
          return
        end
        snd_locked()
        show_msg("Heavy lock. Need a master key.", 90)
      end
    }
  }

  -- West wall: counter
  hotspots[44] = {
    {x=35, y=54, w=70, h=12, name="counter",
      draw=function(s, hs)
        draw_counter(s, hs.x, hs.y)
      end,
      interact=function()
        show_msg("Kitchen counter. Nothing here.", 60)
      end
    }
  }

  -- Also add door from hallway to kitchen (east wall of hallway)
  -- We need to modify hallway east wall to add a door
  table.insert(hotspots[22], {
    x=100, y=48, w=24, h=30, name="door_kitchen",
    draw=function(s, hs)
      draw_door(s, hs.x, hs.y, hs.w, hs.h, false)
      if has_light then text(s, "KTCN", hs.x + 2, hs.y + 10, DARK) end
    end,
    interact=function()
      snd_door()
      show_msg("Entering the kitchen...", 60)
      trans_timer = 15
      cur_room = 4
      cur_dir = DIR_N
    end
  })
end

----------------------------------------------
-- SAFE PUZZLE LOGIC
----------------------------------------------
local function update_safe()
  if not flags.safe_mode then return end

  if btnp("left") then
    flags.safe_sel = clamp(flags.safe_sel - 1, 1, 3)
    snd_click()
  end
  if btnp("right") then
    flags.safe_sel = clamp(flags.safe_sel + 1, 1, 3)
    snd_click()
  end
  if btnp("up") then
    flags.safe_digits[flags.safe_sel] = (flags.safe_digits[flags.safe_sel] + 1) % 10
    snd_click()
  end
  if btnp("down") then
    flags.safe_digits[flags.safe_sel] = (flags.safe_digits[flags.safe_sel] - 1) % 10
    snd_click()
  end
  if btnp("a") then
    -- Check code: 749
    if flags.safe_digits[1] == 7 and flags.safe_digits[2] == 4 and flags.safe_digits[3] == 9 then
      flags.safe_open = true
      flags.safe_mode = false
      flags.has_master_key = true
      add_item("MASTER KEY")
      snd_solve()
      show_msg("Safe opened! Got MASTER KEY!", 120)
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
-- INPUT HANDLING
----------------------------------------------
local function update_play_input()
  -- Safe puzzle intercepts input
  if flags.safe_mode then
    update_safe()
    return
  end

  -- Inventory toggle
  if btnp("b") then
    if held_item then
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
      -- Use matchbox on candle?
      local item = inv[inv_sel]
      if item == "MATCHBOX" and has_item("CANDLE") then
        flags.candle_lit = true
        has_light = true
        remove_item("MATCHBOX")
        snd_solve()
        show_msg("Lit the candle! Light!", 90)
        inv_open = false
      elseif item == "JOURNAL" then
        show_msg("'The year we arrived, reversed.'", 120)
      else
        held_item = item
        inv_open = false
        show_msg("Using: " .. item, 60)
      end
      snd_click()
    end
    return
  end

  -- Turn left/right
  if btnp("left") then
    -- Check if cursor is at left edge
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

  -- Move cursor up/down
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
      show_msg("Nothing there.", 30)
    end
  end

  -- Pause
  if btnp("start") or btnp("select") then
    state = "paused"
  end
end

----------------------------------------------
-- DRAW CURRENT VIEW
----------------------------------------------
local function draw_game(s)
  -- Room base (floor, ceiling, walls)
  cls(s, BLACK)
  draw_room_base(s)

  -- Room label
  local room_names = {"BEDROOM", "HALLWAY", "STUDY", "KITCHEN"}
  local rc = has_light and WHITE or LIGHT

  -- Draw hotspots for current wall
  local spots = get_wall_hotspots(cur_room, cur_dir)
  for _, hs in ipairs(spots) do
    if hs.draw then hs.draw(s, hs) end
  end

  -- Direction arrows on sides
  local ac = has_light and LIGHT or DARK
  -- Left arrow
  text(s, "<", 4, 55, ac)
  -- Right arrow
  text(s, ">", W - 10, 55, ac)

  -- Cursor
  local cf = frame() % 20 < 10
  local cc = cf and WHITE or LIGHT
  -- Crosshair cursor
  line(s, cur_x - 4, cur_y, cur_x - 1, cur_y, cc)
  line(s, cur_x + 1, cur_y, cur_x + 4, cur_y, cc)
  line(s, cur_x, cur_y - 4, cur_x, cur_y - 1, cc)
  line(s, cur_x, cur_y + 1, cur_x, cur_y + 4, cc)

  -- HUD bar at bottom
  rectf(s, 0, H - 10, W, 10, BLACK)
  line(s, 0, H - 10, W, H - 10, has_light and LIGHT or DARK)

  -- Room name + direction
  text(s, room_names[cur_room], 2, H - 8, WHITE)
  text(s, DIR_NAMES[cur_dir], W - 30, H - 8, LIGHT)

  -- Held item indicator
  if held_item then
    text(s, "[" .. held_item .. "]", 50, H - 8, WHITE)
  end

  -- Message display
  if msg_timer > 0 then
    local my = 2
    local mw = #msg_text * 4 + 4
    local mx = clamp(80 - mw // 2, 0, W - mw)
    rectf(s, mx, my, mw, 9, BLACK)
    rect(s, mx, my, mw, 9, LIGHT)
    text(s, msg_text, mx + 2, my + 2, WHITE)
    msg_timer = msg_timer - 1
  end

  -- Inventory overlay
  if inv_open then
    rectf(s, 10, 15, 60, 8 + #inv * 9, BLACK)
    rect(s, 10, 15, 60, 8 + #inv * 9, WHITE)
    text(s, "INVENTORY", 14, 17, WHITE)
    for i, item in ipairs(inv) do
      local c = (i == inv_sel) and WHITE or LIGHT
      local prefix = (i == inv_sel) and "> " or "  "
      text(s, prefix .. item, 14, 17 + i * 9, c)
    end
    if #inv == 0 then
      text(s, "  (empty)", 14, 26, DARK)
    end
  end

  -- Transition effect
  if trans_timer > 0 then
    trans_timer = trans_timer - 1
    local alpha = trans_timer / 15.0
    -- Fade by drawing black scanlines
    local skip = math.max(1, math.floor((1 - alpha) * 4))
    for y = 0, H - 1, skip do
      line(s, 0, y, W, y, BLACK)
    end
  end
end

----------------------------------------------
-- DRAW TITLE SCREEN
----------------------------------------------
local function draw_title(s)
  cls(s, BLACK)

  -- Atmospheric border
  rect(s, 2, 2, W - 4, H - 4, DARK)

  -- Title
  local ty = 25
  text(s, "THE DARK ROOM", 80, ty, WHITE, ALIGN_HCENTER)
  text(s, "THE DARK ROOM", 81, ty + 1, DARK, ALIGN_HCENTER)

  -- Subtitle
  text(s, "A Mystery Adventure", 80, ty + 14, LIGHT, ALIGN_HCENTER)

  -- Flickering prompt
  if frame() % 40 < 28 then
    text(s, "PRESS START", 80, 80, LIGHT, ALIGN_HCENTER)
  end

  -- Credits
  text(s, "Agent 09", 80, 100, DARK, ALIGN_HCENTER)

  -- Ambient visual - random dim pixels for dust/atmosphere
  for i = 1, 8 do
    local px = (frame() * 7 + i * 37) % (W - 8) + 4
    local py = (frame() * 3 + i * 53) % (H - 8) + 4
    pix(s, px, py, DARK)
  end
end

----------------------------------------------
-- DRAW PAUSE SCREEN
----------------------------------------------
local function draw_pause(s)
  draw_game(s)
  -- Overlay
  dither_rectf(s, 30, 40, 100, 30, BLACK, DARK, 2)
  rect(s, 30, 40, 100, 30, WHITE)
  text(s, "PAUSED", 80, 48, WHITE, ALIGN_HCENTER)
  text(s, "START to resume", 80, 58, LIGHT, ALIGN_HCENTER)
end

----------------------------------------------
-- DRAW WIN SCREEN
----------------------------------------------
local function draw_win(s)
  cls(s, BLACK)

  -- Light streams in
  local t = math.min(frame() % 300, 120) / 120.0
  local lw = math.floor(t * 80)
  dither_rectf(s, 80 - lw // 2, 0, lw, H, DARK, LIGHT, 2)

  text(s, "YOU ESCAPED", 80, 30, WHITE, ALIGN_HCENTER)
  text(s, "THE DARK ROOM", 80, 44, WHITE, ALIGN_HCENTER)

  if frame() % 60 < 40 then
    text(s, "Freedom at last.", 80, 65, LIGHT, ALIGN_HCENTER)
  end

  text(s, "PRESS START", 80, 90, LIGHT, ALIGN_HCENTER)
end

----------------------------------------------
-- DEMO MODE
----------------------------------------------
local demo_step = 0
local demo_wait = 0
local demo_room_seq = {1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 4, 4}
local demo_dir_seq  = {1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 1, 3}
local demo_cx_seq   = {65, 70, 75, 60, 65, 80, 70, 60, 60, 65, 65, 70}
local demo_cy_seq   = {58, 55, 58, 55, 55, 58, 55, 58, 55, 55, 55, 55}

local function update_demo()
  demo_wait = demo_wait + 1
  if demo_wait >= 45 then
    demo_wait = 0
    demo_step = demo_step + 1
    if demo_step > #demo_room_seq then
      demo_step = 1
    end
    cur_room = demo_room_seq[demo_step]
    cur_dir = demo_dir_seq[demo_step]
    cur_x = demo_cx_seq[demo_step]
    cur_y = demo_cy_seq[demo_step]
    snd_turn()
  end

  -- Slowly drift cursor
  cur_x = cur_x + math.sin(frame() * 0.05) * 0.5
  cur_y = cur_y + math.cos(frame() * 0.07) * 0.3

  -- Any button exits demo
  if btnp("start") or btnp("a") or btnp("b") or btnp("up") or btnp("down") or btnp("left") or btnp("right") or btnp("select") then
    state = "title"
    idle_timer = 0
  end
end

local function draw_demo(s)
  -- Temporarily enable light for demo visibility
  local old_light = has_light
  has_light = true
  draw_game(s)
  has_light = old_light

  -- Demo overlay
  rectf(s, 0, 0, W, 9, BLACK)
  if frame() % 40 < 28 then
    text(s, "DEMO", 80, 1, LIGHT, ALIGN_HCENTER)
  end
end

----------------------------------------------
-- ENGINE CALLBACKS
----------------------------------------------
function _init()
  mode(2)
end

function _start()
  state = "title"
  idle_timer = 0
  build_hotspots()
end

local function reset_game()
  cur_room = 1
  cur_dir = DIR_N
  cur_x = 80
  cur_y = 60
  inv = {}
  inv_open = false
  inv_sel = 1
  held_item = nil
  has_light = false
  flags = {
    nightstand_open = false,
    has_matchbox = false,
    has_small_key = false,
    has_candle = false,
    candle_lit = false,
    cabinet_open = false,
    has_journal = false,
    safe_open = false,
    has_master_key = false,
    painting_seen = false,
    safe_digits = {0, 0, 0},
    safe_sel = 1,
    safe_mode = false,
    escaped = false,
  }
  msg_text = ""
  msg_timer = 0
  trans_timer = 0
  build_hotspots()
end

function _update()
  snd_ambient()

  if state == "title" then
    idle_timer = idle_timer + 1
    if btnp("start") then
      reset_game()
      state = "play"
      show_msg("You wake up. It's dark...", 120)
      idle_timer = 0
    end
    if idle_timer >= DEMO_IDLE then
      state = "demo"
      demo_step = 0
      demo_wait = 0
      reset_game()
    end

  elseif state == "demo" then
    update_demo()

  elseif state == "play" then
    update_play_input()

  elseif state == "paused" then
    if btnp("start") or btnp("select") then
      state = "play"
    end

  elseif state == "win" then
    if btnp("start") then
      state = "title"
      idle_timer = 0
      reset_game()
    end
  end
end

function _draw()
  local s = screen()

  if state == "title" then
    draw_title(s)
  elseif state == "demo" then
    draw_demo(s)
  elseif state == "play" then
    draw_game(s)
  elseif state == "paused" then
    draw_pause(s)
  elseif state == "win" then
    draw_win(s)
  end
end
