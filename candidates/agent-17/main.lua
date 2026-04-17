-- THE DARK ROOM: HAUNTED
-- First-person horror adventure (Myst-style + survival horror)
-- Agent 17 | 160x120 | 2-bit (4 shades) | 30fps
-- D-Pad: Move cursor / Turn | A: Interact | B: Inventory | START: Start/Pause

----------------------------------------------
-- CONSTANTS
----------------------------------------------
local W, H = 160, 120
local BLACK, DARK, LIGHT, WHITE = 0, 1, 2, 3

-- Directions: 1=North, 2=East, 3=South, 4=West
local DIR_N, DIR_E, DIR_S, DIR_W = 1, 2, 3, 4
local DIR_NAMES = {"NORTH", "EAST", "SOUTH", "WEST"}

local CUR_SPEED = 2
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

local function snd_click()
  sfx_note(0, "A4", 0.03)
end

----------------------------------------------
-- HORROR SOUNDS
----------------------------------------------
local function snd_heartbeat(intensity)
  sfx_note(0, "C3", 0.06)
  if intensity > 0.4 then
    sfx_note(0, "C3", 0.04)  -- double beat
  end
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

local function snd_drip()
  sfx_note(3, "E6", 0.02)
end

local function snd_whisper()
  sfx_noise(3, 0.06)
  sfx_note(2, "B5", 0.03)
end

local function snd_entity_step()
  local steps = {"D4", "E4", "D4", "C4"}
  sfx_note(3, steps[math.random(#steps)], 0.03)
end

----------------------------------------------
-- GLOBAL STATE
----------------------------------------------
local state = "title"   -- title, demo, play, paused, win, dead
local idle_timer = 0
local msg_text = ""
local msg_timer = 0
local has_light = false  -- candle lit?

-- Player state
local cur_room = 1
local cur_dir = DIR_N
local cur_x, cur_y = 80, 60

-- Inventory
local inv = {}
local inv_open = false
local inv_sel = 1
local held_item = nil

-- Puzzle flags
local flags = {}

-- Demo state
local demo_step = 0
local demo_wait = 0

-- Transition effect
local trans_timer = 0

-- Entity (the horror element)
local entity_room = 3     -- which room the entity is in
local entity_wall = DIR_N -- which wall the entity appears on
local entity_timer = 0    -- AI tick timer
local entity_visible = false   -- currently showing on screen?
local entity_appear_timer = 0  -- how long entity has been visible
local entity_grace = 0         -- cooldown after scare before entity can appear again
local entity_encounters = 0    -- total close encounters (death at threshold)
local entity_blink = 0         -- eye blink animation

-- Horror atmosphere
local heartbeat_rate = 0       -- 0=calm, 1=max terror
local heartbeat_timer = 0
local amb_drip_timer = 60
local amb_creak_timer = 120
local scare_flash = 0
local shake_timer = 0
local shake_amt = 0
local candle_flicker = 0       -- extra flicker when entity near
local darkness_pulse = 0       -- subtle breathing darkness

-- Death state
local death_timer = 0

----------------------------------------------
-- UTILITY
----------------------------------------------
local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
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
-- DITHER PATTERNS
----------------------------------------------
local function dither_pixel(s, x, y, c1, c2, pattern)
  if pattern <= 0 then
    pix(s, x, y, c1)
  elseif pattern >= 4 then
    pix(s, x, y, c2)
  else
    local fine = (x % 2 + y % 2 * 2)
    if pattern == 1 then
      pix(s, x, y, (fine == 0) and c2 or c1)
    elseif pattern == 2 then
      pix(s, x, y, (x + y) % 2 == 0 and c2 or c1)
    else
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
local function draw_room_base(s)
  local fc = has_light and DARK or BLACK
  local wc = has_light and LIGHT or DARK

  -- Apply darkness pulse when entity is near
  local dim_all = (entity_room == cur_room and not has_light)

  -- Ceiling
  for y = 0, 39 do
    local depth = y / 40.0
    local shade = has_light and (depth < 0.3 and 2 or 1) or (depth < 0.3 and 1 or 0)
    -- Flicker effect when entity near
    if candle_flicker > 0 and has_light and math.random(10) < 3 then
      shade = clamp(shade - 1, 0, 3)
    end
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
    if candle_flicker > 0 and has_light and math.random(10) < 3 then
      shade = clamp(shade - 1, 0, 3)
    end
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
  if candle_flicker > 0 and has_light and math.random(6) < 2 then
    wallc = DARK  -- flicker darkens wall
  end
  rectf(s, 0, 40, W, 40, wallc)

  -- Wall border lines for perspective
  local bc = has_light and WHITE or LIGHT
  line(s, 0, 0, 20, 40, bc)
  line(s, 0, H - 10, 20, 80, bc)
  line(s, W - 1, 0, W - 21, 40, bc)
  line(s, W - 1, H - 10, W - 21, 80, bc)
  line(s, 20, 40, W - 21, 40, bc)
  line(s, 20, 80, W - 21, 80, bc)

  -- Side wall fills (darker for claustrophobia)
  for y = 0, H - 11 do
    local t = y / (H - 10)
    local lx = math.floor(t < 0.33 and (t / 0.33 * 20) or (t > 0.67 and ((1 - t) / 0.33 * 20) or 20))
    local sc = BLACK  -- always black side walls for horror
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
----------------------------------------------
local hotspots = {}

local function get_wall_hotspots(room, dir)
  local key = room * 10 + dir
  return hotspots[key] or {}
end

-- Draw primitives
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
    line(s, x, y, x + w, y + 4, c)
    rectf(s, x + 1, y + 5, w - 2, h - 6, bg)
  else
    rectf(s, x + 1, y + 1, w - 2, h - 2, bg)
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

local function draw_bed(s, x, y)
  local c = has_light and WHITE or LIGHT
  local bg = has_light and LIGHT or DARK
  rectf(s, x, y, 50, 20, bg)
  rect(s, x, y, 50, 20, c)
  rectf(s, x + 2, y + 2, 14, 8, c)
  line(s, x, y + 12, x + 50, y + 12, c)
end

local function draw_desk(s, x, y)
  local c = has_light and WHITE or LIGHT
  local bg = has_light and LIGHT or DARK
  rectf(s, x, y, 60, 16, bg)
  rect(s, x, y, 60, 16, c)
  rectf(s, x + 2, y + 16, 4, 8, c)
  rectf(s, x + 54, y + 16, 4, 8, c)
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

local function draw_fridge(s, x, y)
  local c = has_light and WHITE or LIGHT
  rect(s, x, y, 20, 36, c)
  line(s, x, y + 14, x + 20, y + 14, c)
  rectf(s, x + 16, y + 4, 2, 8, c)
  rectf(s, x + 16, y + 18, 2, 12, c)
end

local function draw_counter(s, x, y)
  local c = has_light and WHITE or LIGHT
  local bg = has_light and LIGHT or DARK
  rectf(s, x, y, 70, 12, bg)
  rect(s, x, y, 70, 12, c)
  rectf(s, x + 2, y + 12, 4, 10, c)
  rectf(s, x + 64, y + 12, 4, 10, c)
end

----------------------------------------------
-- ENTITY RENDERING ON WALLS
----------------------------------------------
local function draw_entity_eyes(s, intensity)
  -- Draw entity as glowing eyes on the current wall
  -- Position varies based on entity_blink cycle
  local ex = 75 + math.sin(frame() * 0.03) * 8
  local ey = 52 + math.cos(frame() * 0.02) * 4

  -- Eye brightness pulses
  local blink = math.floor(frame() / 4) % 8
  if blink == 0 then return end  -- blink off

  local eye_c = WHITE
  if intensity < 0.5 then eye_c = LIGHT end
  if candle_flicker > 0 and math.random(4) == 1 then eye_c = DARK end

  -- Left eye
  pix(s, math.floor(ex) - 3, math.floor(ey), eye_c)
  pix(s, math.floor(ex) - 2, math.floor(ey), eye_c)
  -- Right eye
  pix(s, math.floor(ex) + 2, math.floor(ey), eye_c)
  pix(s, math.floor(ex) + 3, math.floor(ey), eye_c)

  -- When very close, draw more of the face
  if intensity > 0.7 then
    -- Brow line
    pix(s, math.floor(ex) - 4, math.floor(ey) - 1, DARK)
    pix(s, math.floor(ex) + 4, math.floor(ey) - 1, DARK)
    -- Mouth
    local mouth_y = math.floor(ey) + 4
    for mx = -2, 2 do
      pix(s, math.floor(ex) + mx, mouth_y, DARK)
    end
  end
end

local function draw_entity_shadow(s)
  -- Subtle dark shape in corners when entity is in adjacent room
  local corner = (frame() / 30) % 4
  if corner < 1 then
    -- Bottom left corner shadow
    for i = 0, 4 do
      pix(s, 22 + i, 78 - i, DARK)
    end
  elseif corner < 2 then
    -- Bottom right
    for i = 0, 4 do
      pix(s, W - 23 - i, 78 - i, DARK)
    end
  end
end

----------------------------------------------
-- BUILD HOTSPOT DATA
----------------------------------------------
local function build_hotspots()
  hotspots = {}

  -- ROOM 1: BEDROOM
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

  hotspots[12] = {
    {x=55, y=44, w=40, h=28, name="window",
      draw=function(s, hs)
        local c = has_light and WHITE or LIGHT
        rect(s, hs.x, hs.y, hs.w, hs.h, c)
        for i = 0, 3 do
          line(s, hs.x, hs.y + i * 7, hs.x + hs.w, hs.y + i * 7, c)
        end
        line(s, hs.x, hs.y, hs.x + hs.w, hs.y + hs.h, c)
        line(s, hs.x + hs.w, hs.y, hs.x, hs.y + hs.h, c)
      end,
      interact=function()
        show_msg("Boarded shut. No escape.", 60)
        -- Occasionally scare on window interact
        if entity_room == cur_room and math.random(3) == 1 then
          snd_scare(0.5)
          scare_flash = 3
          show_msg("Something scratches outside!", 90)
        end
      end
    }
  }

  hotspots[13] = {
    {x=50, y=50, w=50, h=20, name="bed",
      draw=function(s, hs) draw_bed(s, hs.x, hs.y) end,
      interact=function()
        if entity_room == cur_room then
          show_msg("No time to rest. NOT ALONE.", 60)
        else
          show_msg("Your bed. Still warm.", 60)
        end
      end
    }
  }

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
          show_msg("Too dark... shapes moving?", 60)
        end
      end
    },
    {x=100, y=48, w=24, h=30, name="door_kitchen",
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
    }
  }

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

  hotspots[24] = {
    {x=55, y=46, w=30, h=28, name="cabinet",
      draw=function(s, hs)
        draw_box(s, hs.x, hs.y, hs.w, hs.h, flags.cabinet_open)
        if not flags.cabinet_open then
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
  hotspots[31] = {
    {x=50, y=42, w=30, h=36, name="bookshelf",
      draw=function(s, hs) draw_bookshelf(s, hs.x, hs.y) end,
      interact=function()
        if has_light then
          show_msg("Old books. Dust falls.", 60)
        else
          show_msg("Can't see. Something breathes.", 60)
        end
      end
    }
  }

  hotspots[32] = {
    {x=58, y=48, w=24, h=20, name="safe",
      draw=function(s, hs)
        draw_safe(s, hs.x, hs.y, flags.safe_open)
        if not flags.safe_open and has_light then
          for i = 1, 3 do
            local dx = hs.x + 2 + (i - 1) * 8
            text(s, tostring(flags.safe_digits[i]), dx, hs.y + hs.h + 2, WHITE)
          end
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
        flags.safe_mode = true
        show_msg("UP/DN:digit LR:sel A:try", 120)
      end
    }
  }

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

  hotspots[34] = {
    {x=40, y=52, w=60, h=16, name="desk",
      draw=function(s, hs)
        draw_desk(s, hs.x, hs.y)
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

  hotspots[42] = {
    {x=60, y=40, w=20, h=36, name="fridge",
      draw=function(s, hs) draw_fridge(s, hs.x, hs.y) end,
      interact=function()
        if has_light then
          show_msg("A note: 'Don't forget 749'", 90)
        else
          show_msg("A cold metal box.", 60)
        end
      end
    }
  }

  hotspots[43] = {
    {x=55, y=42, w=32, h=36, name="back_door",
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

  hotspots[44] = {
    {x=35, y=54, w=70, h=12, name="counter",
      draw=function(s, hs) draw_counter(s, hs.x, hs.y) end,
      interact=function()
        show_msg("Kitchen counter. Nothing.", 60)
      end
    }
  }
end

----------------------------------------------
-- SAFE PUZZLE
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
  if entity_timer % 180 == 0 then  -- every 6 seconds
    local old_room = entity_room
    -- Bias toward player's room
    if math.random(100) < 40 then
      entity_room = cur_room
    else
      -- Move to adjacent room
      local adj = {
        [1] = {2},
        [2] = {1, 3, 4},
        [3] = {2},
        [4] = {2},
      }
      local options = adj[entity_room] or {2}
      entity_room = options[math.random(#options)]
    end
    -- Pick random wall to appear on
    entity_wall = math.random(1, 4)

    -- Distant door sound when entity moves
    if old_room ~= entity_room then
      if entity_room == cur_room then
        sfx_note(2, "G2", 0.1)
        show_msg("...a door creaks...", 60)
      elseif old_room == cur_room then
        sfx_note(2, "D2", 0.06)
      end
    end
  end

  -- Change wall the entity appears on
  if entity_timer % 90 == 0 then
    entity_wall = math.random(1, 4)
  end

  -- Determine if entity is visible on current view
  local was_visible = entity_visible
  entity_visible = (entity_room == cur_room and entity_wall == cur_dir)

  -- Track appearance duration
  if entity_visible then
    entity_appear_timer = entity_appear_timer + 1

    -- After staring too long, trigger scare
    if entity_appear_timer > 90 then  -- 3 seconds of eye contact
      snd_scare(2)
      scare_flash = 6
      shake_timer = 12
      shake_amt = 4
      entity_encounters = entity_encounters + 1
      entity_grace = 120  -- 4 second grace period
      entity_appear_timer = 0
      entity_wall = ((entity_wall) % 4) + 1  -- move to different wall
      show_msg("IT SEES YOU", 60)

      -- Death after too many encounters
      if entity_encounters >= 5 then
        state = "dead"
        death_timer = 0
        snd_scare(3)
        return
      end
    end

    -- Random mini-scare when first spotted
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

  -- Entity footstep sounds when in same room
  if entity_room == cur_room then
    if entity_timer % 15 == 0 then
      snd_entity_step()
    end
  -- Distant footsteps in adjacent room
  elseif entity_timer % 30 == 0 then
    local adj = {[1]={2}, [2]={1,3,4}, [3]={2}, [4]={2}}
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
  -- Dripping water
  amb_drip_timer = amb_drip_timer - 1
  if amb_drip_timer <= 0 then
    amb_drip_timer = 40 + math.random(80)
    snd_drip()
  end

  -- Random creak
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

  -- Candle flicker intensifies when entity near
  if has_light then
    if entity_room == cur_room then
      if math.random(10) < 4 then
        candle_flicker = 2 + math.random(3)
      end
    elseif math.random(100) < 3 then
      candle_flicker = 1 + math.random(2)
    end
  end
  if candle_flicker > 0 then candle_flicker = candle_flicker - 1 end

  -- Darkness breathing pulse
  darkness_pulse = math.sin(frame() * 0.05) * 0.5 + 0.5

  -- Scare flash decay
  if scare_flash > 0 then scare_flash = scare_flash - 1 end

  -- Shake decay
  if shake_timer > 0 then
    shake_timer = shake_timer - 1
  end
end

----------------------------------------------
-- INPUT
----------------------------------------------
local function update_play_input()
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

  -- Scare flash overlay (intense)
  if scare_flash > 4 then
    cls(s, WHITE)
    -- Entity face close up
    text(s, "!", 80, 55, BLACK, ALIGN_HCENTER)
    circ(s, 70, 50, 3, BLACK)
    circ(s, 90, 50, 3, BLACK)
    line(s, 74, 62, 86, 62, BLACK)
    return
  end

  -- Screen shake offset
  local sx_off, sy_off = 0, 0
  if shake_timer > 0 then
    sx_off = math.random(-shake_amt, shake_amt)
    sy_off = math.random(-shake_amt, shake_amt)
  end

  -- Room base
  draw_room_base(s)

  -- Hotspots for current wall
  local spots = get_wall_hotspots(cur_room, cur_dir)
  for _, hs in ipairs(spots) do
    if hs.draw then hs.draw(s, hs) end
  end

  -- Entity eyes on wall (drawn over hotspots)
  if entity_visible and entity_grace <= 0 then
    local intensity = entity_appear_timer / 90.0
    draw_entity_eyes(s, intensity)
  end

  -- Subtle shadow hint when entity in adjacent room
  if entity_room ~= cur_room then
    local adj = {[1]={2}, [2]={1,3,4}, [3]={2}, [4]={2}}
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

  -- Cursor (crosshair)
  local cf = frame() % 20 < 10
  local cc = cf and WHITE or LIGHT
  line(s, cur_x - 4, cur_y, cur_x - 1, cur_y, cc)
  line(s, cur_x + 1, cur_y, cur_x + 4, cur_y, cc)
  line(s, cur_x, cur_y - 4, cur_x, cur_y - 1, cc)
  line(s, cur_x, cur_y + 1, cur_x, cur_y + 4, cc)

  -- HUD bar
  rectf(s, 0, H - 10, W, 10, BLACK)
  line(s, 0, H - 10, W, H - 10, has_light and LIGHT or DARK)

  -- Room name + direction
  local room_names = {"BEDROOM", "HALLWAY", "STUDY", "KITCHEN"}
  text(s, room_names[cur_room], 2, H - 8, WHITE)
  text(s, DIR_NAMES[cur_dir], W - 30, H - 8, LIGHT)

  -- Held item
  if held_item then
    text(s, "[" .. held_item .. "]", 50, H - 8, WHITE)
  end

  -- Heartbeat indicator (pulsing border when danger near)
  if heartbeat_rate > 0.3 then
    local pulse = math.sin(frame() * heartbeat_rate * 0.3) > 0.3
    if pulse then
      local pc = heartbeat_rate > 0.7 and LIGHT or DARK
      rect(s, 0, 0, W, H - 10, pc)
    end
  end

  -- Encounter counter (subtle warning marks)
  if entity_encounters > 0 then
    for i = 1, entity_encounters do
      pix(s, W - 4 - i * 4, 2, LIGHT)
    end
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

  -- Scare flash overlay (mild)
  if scare_flash > 0 and scare_flash <= 4 then
    local sc = scare_flash > 2 and WHITE or LIGHT
    for y = 0, H - 1, 2 do
      line(s, 0, y, W, y, sc)
    end
  end

  -- Transition effect
  if trans_timer > 0 then
    trans_timer = trans_timer - 1
    local alpha = trans_timer / 15.0
    local skip = math.max(1, math.floor((1 - alpha) * 4))
    for y = 0, H - 1, skip do
      line(s, 0, y, W, y, BLACK)
    end
  end

  -- Vignette: darken edges for claustrophobia
  for i = 0, W - 1, 2 do
    pix(s, i, 0, BLACK)
    pix(s, i, H - 11, BLACK)
  end
  for i = 0, H - 11, 2 do
    pix(s, 21, i, BLACK)
    pix(s, W - 22, i, BLACK)
  end
end

----------------------------------------------
-- TITLE SCREEN
----------------------------------------------
local title_timer = 0
local title_flicker = 0

local function draw_title(s)
  cls(s, BLACK)
  title_timer = title_timer + 1

  -- Atmospheric border
  if title_timer > 30 then
    rect(s, 2, 2, W - 4, H - 4, DARK)
  end

  -- Flickering title (horror style)
  local flick = math.random(100)
  local title_c = WHITE
  if flick < 8 then title_c = DARK
  elseif flick < 15 then title_c = LIGHT end

  -- Occasional blackout
  if title_flicker > 0 then
    title_flicker = title_flicker - 1
    if title_flicker > 3 then title_c = BLACK end
  elseif math.random(200) < 3 then
    title_flicker = 6
  end

  if title_c > BLACK then
    text(s, "THE DARK ROOM", 80, 22, title_c, ALIGN_HCENTER)
  end
  text(s, "HAUNTED", 80, 32, DARK, ALIGN_HCENTER)

  -- Creepy subtitles
  if title_timer > 40 then
    text(s, "you wake up.", 80, 48, LIGHT, ALIGN_HCENTER)
  end
  if title_timer > 70 then
    text(s, "you can't see.", 80, 58, DARK, ALIGN_HCENTER)
  end
  if title_timer > 100 then
    text(s, "you are not alone.", 80, 68, DARK, ALIGN_HCENTER)
  end

  -- Start prompt
  if title_timer > 130 then
    if math.floor(frame() / 20) % 2 == 0 then
      text(s, "PRESS START", 80, 90, LIGHT, ALIGN_HCENTER)
    end
  end

  -- Random eyes in darkness
  if title_timer > 60 and math.random(100) < 5 then
    local ex2 = math.random(20, W - 20)
    local ey2 = math.random(78, H - 15)
    pix(s, ex2, ey2, DARK)
    pix(s, ex2 + 3, ey2, DARK)
  end

  -- Dust particles
  for i = 1, 6 do
    local px2 = (frame() * 7 + i * 37) % (W - 8) + 4
    local py2 = (frame() * 3 + i * 53) % (H - 8) + 4
    pix(s, px2, py2, DARK)
  end

  text(s, "Agent 17", 80, 108, DARK, ALIGN_HCENTER)
end

----------------------------------------------
-- PAUSE SCREEN
----------------------------------------------
local function draw_pause(s)
  draw_game(s)
  dither_rectf(s, 30, 40, 100, 30, BLACK, DARK, 2)
  rect(s, 30, 40, 100, 30, WHITE)
  text(s, "PAUSED", 80, 48, WHITE, ALIGN_HCENTER)
  text(s, "START to resume", 80, 58, LIGHT, ALIGN_HCENTER)
end

----------------------------------------------
-- WIN SCREEN
----------------------------------------------
local win_timer = 0

local function draw_win(s)
  cls(s, BLACK)
  win_timer = win_timer + 1

  -- Light streams in
  local t = math.min(win_timer, 120) / 120.0
  local lw = math.floor(t * 80)
  dither_rectf(s, 80 - lw // 2, 0, lw, H, DARK, LIGHT, 2)

  text(s, "YOU ESCAPED", 80, 30, WHITE, ALIGN_HCENTER)
  text(s, "THE DARK ROOM", 80, 44, WHITE, ALIGN_HCENTER)

  if win_timer > 40 then
    text(s, "The light outside", 80, 60, LIGHT, ALIGN_HCENTER)
    text(s, "has never felt", 80, 70, LIGHT, ALIGN_HCENTER)
    text(s, "so warm.", 80, 80, LIGHT, ALIGN_HCENTER)
  end

  if win_timer > 100 then
    if math.floor(frame() / 20) % 2 == 0 then
      text(s, "PRESS START", 80, 100, LIGHT, ALIGN_HCENTER)
    end
  end
end

----------------------------------------------
-- DEATH SCREEN (from entity)
----------------------------------------------
local function draw_dead(s)
  cls(s, BLACK)
  death_timer = death_timer + 1

  -- Static/noise effect
  if death_timer < 15 then
    for i = 1, 80 do
      pix(s, math.random(0, W - 1), math.random(0, H - 1), math.random(0, WHITE))
    end
    return
  end

  -- Flickering death message
  local flick = math.random(100)
  if flick > 10 then
    text(s, "IT GOT YOU", 80, 40, WHITE, ALIGN_HCENTER)
  end

  if death_timer > 45 then
    text(s, "Encounters: " .. entity_encounters, 80, 58, LIGHT, ALIGN_HCENTER)
  end

  if death_timer > 75 then
    if math.floor(frame() / 20) % 2 == 0 then
      text(s, "START to retry", 80, 85, LIGHT, ALIGN_HCENTER)
    end
  end

  -- Eyes watching from death screen
  if death_timer > 30 and math.random(60) < 3 then
    local ex2 = math.random(30, W - 30)
    local ey2 = math.random(70, H - 20)
    pix(s, ex2, ey2, DARK)
    pix(s, ex2 + 3, ey2, DARK)
  end
end

----------------------------------------------
-- DEMO MODE
----------------------------------------------
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

  -- Drift cursor
  cur_x = cur_x + math.sin(frame() * 0.05) * 0.5
  cur_y = cur_y + math.cos(frame() * 0.07) * 0.3

  -- Simulate entity appearing occasionally in demo
  if demo_wait == 20 and math.random(4) == 1 then
    entity_room = cur_room
    entity_wall = cur_dir
    entity_visible = true
    entity_appear_timer = 1
  else
    entity_visible = false
    entity_appear_timer = 0
  end

  -- Any button exits demo
  if btnp("start") or btnp("a") or btnp("b") or btnp("up") or btnp("down") or btnp("left") or btnp("right") or btnp("select") then
    state = "title"
    title_timer = 0
    idle_timer = 0
  end
end

local function draw_demo(s)
  local old_light = has_light
  has_light = true
  draw_game(s)
  has_light = old_light

  rectf(s, 0, 0, W, 9, BLACK)
  if math.floor(frame() / 30) % 2 == 0 then
    text(s, "DEMO", 80, 1, LIGHT, ALIGN_HCENTER)
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

  -- Reset horror state
  entity_room = 3
  entity_wall = DIR_N
  entity_timer = 0
  entity_visible = false
  entity_appear_timer = 0
  entity_grace = 60  -- initial grace period
  entity_encounters = 0
  entity_blink = 0
  heartbeat_rate = 0
  heartbeat_timer = 0
  amb_drip_timer = 60
  amb_creak_timer = 120
  scare_flash = 0
  shake_timer = 0
  shake_amt = 0
  candle_flicker = 0
  darkness_pulse = 0
  death_timer = 0
  win_timer = 0

  build_hotspots()
end

----------------------------------------------
-- ENGINE CALLBACKS
----------------------------------------------
function _init()
  mode(2)
end

function _start()
  state = "title"
  title_timer = 0
  idle_timer = 0
  build_hotspots()
end

function _update()
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
    update_entity()
    update_ambient()

  elseif state == "paused" then
    if btnp("start") or btnp("select") then
      state = "play"
    end

  elseif state == "win" then
    win_timer = win_timer + 1
    if btnp("start") then
      state = "title"
      title_timer = 0
      idle_timer = 0
      reset_game()
    end

  elseif state == "dead" then
    death_timer = death_timer + 1
    if death_timer > 60 and btnp("start") then
      state = "play"
      reset_game()
      show_msg("You wake again...", 90)
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
  elseif state == "dead" then
    draw_dead(s)
  end
end
