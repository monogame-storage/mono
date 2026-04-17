-- THE DARK ROOM: RESONANCE
-- Agent 21 (Wave 3) | First-person sonar horror
-- Merged: Agent 13 (Echolocation) + Agent 19 (It Approaches) + Agent 18 (Forgotten)
-- You are blind. Ping to see. But IT listens. Craft. Read. Escape.
-- 160x120 | 2-bit | mode(2)

----------------------------------------------
-- CONSTANTS
----------------------------------------------
local W, H = 160, 120
local BLACK, DARK, LIGHT, WHITE = 0, 1, 2, 3
local DIR_N, DIR_E, DIR_S, DIR_W = 1, 2, 3, 4
local DIR_NAMES = {"NORTH", "EAST", "SOUTH", "WEST"}
local DEMO_IDLE = 150
local SONAR_COOLDOWN = 45
local SONAR_REVEAL_DUR = 90
local CH_SONAR, CH_OBJ, CH_AMB, CH_STEP = 0, 1, 2, 3

----------------------------------------------
-- SAFE AUDIO
----------------------------------------------
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

----------------------------------------------
-- SOUND EFFECTS
----------------------------------------------
local function snd_turn() sfx_wave(0,"triangle") sfx_tone(0, 100, 80, 0.04) end
local function snd_step() sfx_wave(0,"triangle") sfx_tone(0, 90, 70, 0.03) sfx_noise(1, 0.02) end
local function snd_pickup()
  sfx_note(0, "C5", 0.06) sfx_note(0, "E5", 0.06) sfx_note(0, "G5", 0.06)
end
local function snd_door() sfx_wave(0,"triangle") sfx_tone(0,200,300,0.15) sfx_noise(1,0.08) end
local function snd_locked() sfx_noise(0, 0.08) sfx_note(1, "C2", 0.08) end
local function snd_solve()
  sfx_note(0,"C5",0.1) sfx_note(0,"E5",0.1) sfx_note(0,"G5",0.1) sfx_note(0,"C6",0.2)
end
local function snd_craft()
  sfx_note(0,"E5",0.08) sfx_note(1,"G5",0.08) sfx_note(0,"C6",0.12)
end
local function snd_click() sfx_note(0, "A4", 0.03) end
local function snd_read() sfx_note(0, "D4", 0.06) sfx_note(1, "F4", 0.04) end

-- Sonar ping: sweeping sine
local function snd_sonar()
  sfx_wave(CH_SONAR, "sine")
  sfx_tone(CH_SONAR, 1200, 400, 0.15)
end

-- Entity hears the ping
local function snd_alert()
  sfx_wave(CH_OBJ, "square")
  sfx_tone(CH_OBJ, 120, 80, 0.08)
end

-- Heartbeat
local function snd_heartbeat(intensity)
  sfx_wave(CH_AMB, "sine")
  local base = 50 + intensity * 20
  sfx_tone(CH_AMB, base, base * 0.7, 0.06)
end

-- Entity growl
local function snd_growl()
  sfx_wave(CH_AMB, "sawtooth")
  sfx_tone(CH_AMB, 45, 35, 0.12)
end

-- Entity footstep
local function snd_entity_step(d)
  if d > 12 then return end
  local t = 1 - d / 12
  sfx_wave(CH_STEP, "square")
  sfx_tone(CH_STEP, 200 - t * 100, 150 - t * 80, 0.01 + t * 0.03)
end

-- Jump scare
local function snd_jumpscare()
  sfx_noise(CH_SONAR, 0.2)
  sfx_wave(CH_OBJ, "sawtooth")
  sfx_tone(CH_OBJ, 80, 40, 0.3)
  sfx_noise(CH_STEP, 0.15)
  sfx_wave(CH_AMB, "square")
  sfx_tone(CH_AMB, 100, 50, 0.25)
end

-- Ambient
local function snd_drip()
  sfx_wave(CH_OBJ, "sine")
  sfx_tone(CH_OBJ, 1200 + math.random(800), 600, 0.02)
end
local function snd_creak()
  sfx_wave(CH_AMB, "sawtooth")
  local f = ({55,62,48,70})[math.random(4)]
  sfx_tone(CH_AMB, f, f * 0.8, 0.1)
end

----------------------------------------------
-- UTILITY
----------------------------------------------
local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end
local function lerp(a, b, t) return a + (b - a) * t end
local function dist(x1, y1, x2, y2)
  local dx, dy = x1 - x2, y1 - y2
  return math.sqrt(dx * dx + dy * dy)
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
        ln = #ln > 0 and (ln .. " " .. w) or w
      end
    end
    if #ln > 0 then lines[#lines + 1] = ln end
  end
  if #lines == 0 then lines[1] = "" end
  return lines
end

----------------------------------------------
-- GLOBAL STATE
----------------------------------------------
local state = "title"
local idle_timer = 0
local frm = 0
local msg_text = ""
local msg_timer = 0
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

-- Sonar system (from Agent 13)
local sonar_timer = 0
local sonar_reveal = 0        -- frames remaining of wall reveal
local sonar_pulse_radius = 0  -- expanding ring visual
local sonar_active = false

-- Entity (from Agent 13 + 19)
local entity_room = 2         -- which room entity is currently in
local entity_dist = 10        -- abstract distance 0-10 (0 = caught)
local entity_alert = false    -- whether entity is alerted
local entity_chase_timer = 0
local entity_step_timer = 0
local entity_growl_timer = 0

-- Horror atmosphere (from Agent 19)
local heartbeat_timer = 0
local heartbeat_rate = 0
local amb_drip_timer = 40
local amb_creak_timer = 60
local scare_timer = 200
local scare_flash = 0
local shake_timer = 0
local shake_x, shake_y = 0, 0
local entity_eyes = {}
local darkness_tendrils = {}
local static_amount = 0
local entity_face_timer = 0

-- Lighting
local has_light = false

-- Pause
local pause_sel = 1

----------------------------------------------
-- ITEM DATABASE (from Agent 18)
----------------------------------------------
local ITEMS = {
  matches   = {name="Matches",    desc="Three matches. Won't last.",   icon="M"},
  lens      = {name="Glass Lens", desc="Cracked magnifying lens.",     icon="O"},
  lantern   = {name="Lantern",    desc="Makeshift light. It works!",   icon="*"},
  wire      = {name="Wire",       desc="Thin copper wire.",            icon="W"},
  metal_rod = {name="Metal Rod",  desc="Short iron rod.",              icon="I"},
  lockpick  = {name="Lockpick",   desc="Bent wire pick.",              icon="P"},
  tape      = {name="Tape",       desc="Roll of electrical tape.",     icon="T"},
  fuse_dead = {name="Dead Fuse",  desc="Blown 30-amp fuse.",          icon="F"},
  fuse_good = {name="Fixed Fuse", desc="Taped fuse. Might work.",     icon="f"},
  keycard   = {name="Keycard",    desc="Dr. Wren - Level 4 Access.",   icon="K"},
  note_l    = {name="Note(left)", desc="Torn paper: '74..'",          icon="1"},
  note_r    = {name="Note(right)",desc="Torn paper: '..39'",          icon="2"},
  full_note = {name="Full Note",  desc="Code: 7439",                  icon="N"},
  crowbar   = {name="Crowbar",    desc="Heavy. Pries things open.",    icon="C"},
  evidence  = {name="Evidence",   desc="Subject 17 file. Proof.",      icon="E"},
  journal1  = {name="Journal p.1",desc="Day 1: moved to sublevel 4.", icon="J"},
  journal2  = {name="Journal p.2",desc="Day 15: hiding pages.",       icon="J"},
  journal3  = {name="Journal p.3",desc="Day 31: I am Subject 17.",    icon="J"},
  master_key= {name="Master Key", desc="Heavy brass key.",             icon="Q"},
}

local RECIPES = {
  {a="matches",   b="lens",      result="lantern"},
  {a="wire",      b="metal_rod", result="lockpick"},
  {a="tape",      b="fuse_dead", result="fuse_good"},
  {a="note_l",    b="note_r",    result="full_note"},
}

----------------------------------------------
-- PUZZLE FLAGS (from Agent 18)
----------------------------------------------
local flags = {}

local function reset_flags()
  flags = {
    cell_searched = false,
    keycard_found = false,
    cabinet_open = false,
    lab_powered = false,
    terminal_used = false,
    code_found = false,
    desk_pried = false,
    evidence_found = false,
    safe_open = false,
    safe_mode = false,
    safe_digits = {0,0,0,0},
    safe_sel = 1,
    escaped = false,
    journal1_read = false,
    journal2_read = false,
    journal3_read = false,
    memo_read = false,
    docs_read = 0,
  }
end

----------------------------------------------
-- INVENTORY HELPERS
----------------------------------------------
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
    show_msg("Got: " .. ITEMS[name].name, 60)
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

local function show_document(txt)
  doc_text = txt
  doc_lines = word_wrap(txt, 30)
  doc_scroll = 0
  snd_read()
  flags.docs_read = (flags.docs_read or 0) + 1
end

local function close_document()
  doc_text = nil
  doc_lines = {}
end

----------------------------------------------
-- DITHER (from Agent 18)
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
-- FIRST-PERSON WALL RENDERING (from Agent 18)
----------------------------------------------
local function sonar_visible()
  return sonar_reveal > 0 or has_light
end

local function draw_room_base(s)
  local vis = sonar_visible()
  local lit = has_light

  -- Ceiling
  for y = 0, 39 do
    local depth = y / 40.0
    local shade
    if vis then
      shade = lit and (depth < 0.3 and 2 or 1) or (depth < 0.3 and 1 or 0)
    else
      shade = 0
    end
    for x = 0, W - 1 do
      local checker = (math.floor(x / 8) + math.floor(y / 4)) % 2
      pix(s, x, y, checker == 0 and shade or clamp(shade - 1, 0, 3))
    end
  end

  -- Floor
  for y = 80, H - 11 do
    local depth = (y - 80) / 30.0
    local shade
    if vis then
      shade = lit and (depth > 0.6 and 2 or 1) or (depth > 0.6 and 1 or 0)
    else
      shade = 0
    end
    for x = 0, W - 1 do
      local checker = (math.floor(x / 8) + math.floor((y - 80) / 4)) % 2
      pix(s, x, y, checker == 0 and shade or clamp(shade - 1, 0, 3))
    end
  end

  -- Back wall
  if vis then
    rectf(s, 0, 40, W, 40, lit and LIGHT or DARK)
  else
    rectf(s, 0, 40, W, 40, BLACK)
  end

  -- Perspective lines
  if vis then
    local bc = lit and WHITE or LIGHT
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
      local sc = lit and DARK or BLACK
      for x = 0, lx - 1 do pix(s, x, y, sc) end
      for x = W - lx, W - 1 do pix(s, x, y, sc) end
    end
  end

  -- Sonar pulse ring effect on walls (from Agent 13 adapted to first-person)
  if sonar_active and sonar_pulse_radius < 120 then
    local r = sonar_pulse_radius
    local fade = r < 60 and DARK or BLACK
    -- Horizontal ring across back wall
    if r > 20 and r < 100 then
      local wy = clamp(60 - (r - 40), 40, 80)
      if wy >= 40 and wy <= 80 then
        line(s, 20, wy, W - 21, wy, fade == BLACK and BLACK or DARK)
      end
      wy = clamp(60 + (r - 40), 40, 80)
      if wy >= 40 and wy <= 80 then
        line(s, 20, wy, W - 21, wy, fade == BLACK and BLACK or DARK)
      end
    end
  end
end

-- Drawing helpers (from Agent 18)
local function draw_door(s, x, y, w, h, open, col)
  if not sonar_visible() then return end
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
  if not sonar_visible() then return end
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
  if not sonar_visible() then return end
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
  if not sonar_visible() then return end
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
  if not sonar_visible() then return end
  local c = has_light and WHITE or LIGHT
  local bg = has_light and LIGHT or DARK
  rectf(s, x, y, 60, 16, bg)
  rect(s, x, y, 60, 16, c)
  rectf(s, x + 2, y + 16, 4, 8, c)
  rectf(s, x + 54, y + 16, 4, 8, c)
end

local function draw_terminal(s, x, y, powered)
  if not sonar_visible() then return end
  local c = has_light and WHITE or LIGHT
  rect(s, x, y, 28, 22, c)
  if powered then
    rectf(s, x + 2, y + 2, 24, 14, DARK)
    if frm % 30 < 20 then
      rectf(s, x + 4, y + 12, 4, 2, LIGHT)
    end
    text(s, ">_", x + 4, y + 4, LIGHT)
  else
    rectf(s, x + 2, y + 2, 24, 14, BLACK)
  end
  rectf(s, x + 8, y + 22, 12, 4, c)
end

local function draw_filing_cabinet(s, x, y, open)
  if not sonar_visible() then return end
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
  if not sonar_visible() then return end
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
  if not sonar_visible() then return end
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
  if not sonar_visible() then return end
  local c = has_light and WHITE or LIGHT
  local bg = has_light and DARK or BLACK
  rect(s, x, y, w, h, c)
  rectf(s, x + 2, y + 2, w - 4, h - 4, bg)
  line(s, x + 3, y + h - 6, x + w // 2, y + 4, has_light and LIGHT or DARK)
  line(s, x + w // 2, y + 4, x + w - 3, y + h - 6, has_light and LIGHT or DARK)
end

----------------------------------------------
-- SONAR SYSTEM (from Agent 13 adapted)
----------------------------------------------
local function do_sonar_ping()
  if sonar_timer > 0 then return end
  snd_sonar()
  sonar_timer = SONAR_COOLDOWN
  sonar_reveal = SONAR_REVEAL_DUR
  sonar_active = true
  sonar_pulse_radius = 0

  -- ALERT THE ENTITY
  if entity_dist > 0 then
    entity_alert = true
    entity_chase_timer = 180  -- 6 seconds of active chase
    snd_alert()
    show_msg("...IT HEARD YOU", 40)
  end
end

local function update_sonar()
  if sonar_timer > 0 then sonar_timer = sonar_timer - 1 end
  if sonar_reveal > 0 then sonar_reveal = sonar_reveal - 1 end
  if sonar_active then
    sonar_pulse_radius = sonar_pulse_radius + 3
    if sonar_pulse_radius > 160 then sonar_active = false end
  end
end

----------------------------------------------
-- ENTITY AI (from Agent 13 + 19)
----------------------------------------------
local function update_entity()
  if state ~= "play" then return end
  if entity_dist <= 0 then return end

  -- Chase logic: when alerted, entity closes distance
  if entity_alert then
    entity_chase_timer = entity_chase_timer - 1
    -- Move toward player's room
    if entity_room ~= cur_room then
      -- Move between rooms
      if frm % 30 == 0 then
        if entity_room < cur_room then
          entity_room = entity_room + 1
        elseif entity_room > cur_room then
          entity_room = entity_room - 1
        end
      end
    end

    -- If in same room, close distance
    if entity_room == cur_room then
      local speed = 0.03
      entity_dist = entity_dist - speed
    else
      -- Slowly approach through rooms
      local speed = 0.008
      entity_dist = entity_dist - speed
    end

    if entity_chase_timer <= 0 then
      entity_alert = false
      -- Entity loses interest, drift away slowly
    end
  else
    -- Patrol: slowly drift back
    if entity_dist < 10 then
      entity_dist = entity_dist + 0.005
    end
    -- Randomly wander rooms
    if frm % 120 == 0 then
      entity_room = math.random(1, 6)
    end
  end

  -- Entity footstep sounds
  entity_step_timer = entity_step_timer + 1
  local step_interval = entity_alert and 15 or 30
  if entity_step_timer >= step_interval and entity_room == cur_room then
    entity_step_timer = 0
    snd_entity_step(entity_dist)
  end

  -- Growl when close
  if entity_dist < 3 and entity_room == cur_room then
    entity_growl_timer = entity_growl_timer + 1
    if entity_growl_timer % 40 == 0 then
      snd_growl()
    end
  end

  -- CAUGHT! Jump scare
  if entity_dist <= 0 then
    entity_dist = 0
    snd_jumpscare()
    scare_flash = 15
    shake_timer = 20
    entity_face_timer = 20
    state = "death"
  end
end

----------------------------------------------
-- HORROR ATMOSPHERE (from Agent 19)
----------------------------------------------
local function spawn_entity_eyes()
  if #entity_eyes >= 6 then return end
  local side = math.random(1, 4)
  local ex, ey
  if side == 1 then
    ex = math.random(10, W - 10); ey = math.random(2, 12)
  elseif side == 2 then
    ex = math.random(10, W - 10); ey = math.random(H - 14, H - 4)
  elseif side == 3 then
    ex = math.random(2, 16); ey = math.random(10, H - 10)
  else
    ex = math.random(W - 18, W - 4); ey = math.random(10, H - 10)
  end
  entity_eyes[#entity_eyes + 1] = {x = ex, y = ey, life = math.random(30, 90), blink = math.random(0, 100)}
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

local function draw_entity_eyes(s)
  for _, e in ipairs(entity_eyes) do
    local blinking = (e.blink % 40) < 3
    if not blinking then
      local c = (e.life < 10) and DARK or LIGHT
      pix(s, e.x, e.y, c)
      pix(s, e.x + 3, e.y, c)
    end
  end
end

local function update_tendrils(urgency)
  if urgency < 0.2 then
    darkness_tendrils = {}
    return
  end
  local max_tendrils = math.floor(urgency * 20)
  while #darkness_tendrils < max_tendrils do
    local side = math.random(1, 4)
    local t = {}
    if side == 1 then
      t.x = math.random(0, W - 1); t.y = 0
      t.dx = (math.random() - 0.5) * 0.5; t.dy = 0.3 + math.random() * 0.5
    elseif side == 2 then
      t.x = math.random(0, W - 1); t.y = H - 1
      t.dx = (math.random() - 0.5) * 0.5; t.dy = -(0.3 + math.random() * 0.5)
    elseif side == 3 then
      t.x = 0; t.y = math.random(0, H - 1)
      t.dx = 0.3 + math.random() * 0.5; t.dy = (math.random() - 0.5) * 0.5
    else
      t.x = W - 1; t.y = math.random(0, H - 1)
      t.dx = -(0.3 + math.random() * 0.5); t.dy = (math.random() - 0.5) * 0.5
    end
    t.len = math.floor(urgency * 25) + math.random(5, 15)
    t.life = t.len
    darkness_tendrils[#darkness_tendrils + 1] = t
  end
  local i = 1
  while i <= #darkness_tendrils do
    local t = darkness_tendrils[i]
    t.x = t.x + t.dx
    t.y = t.y + t.dy
    t.life = t.life - 1
    if t.life <= 0 then
      darkness_tendrils[i] = darkness_tendrils[#darkness_tendrils]
      darkness_tendrils[#darkness_tendrils] = nil
    else
      i = i + 1
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
        if tx + 1 < W then pix(s, tx + 1, ty, BLACK) end
        if ty + 1 < H then pix(s, tx, ty + 1, BLACK) end
      end
    end
  end
end

local function draw_vignette(s, intensity)
  local border = math.floor(intensity * 30)
  if border < 1 then return end
  for y = 0, border - 1 do
    local c = (y < border / 2) and BLACK or DARK
    line(s, 0, y, W - 1, y, c)
    line(s, 0, H - 1 - y, W - 1, H - 1 - y, c)
  end
  for x = 0, border - 1 do
    local c = (x < border / 2) and BLACK or DARK
    line(s, x, border, x, H - 1 - border, c)
    line(s, W - 1 - x, border, W - 1 - x, H - 1 - border, c)
  end
end

local function draw_static(s, amount)
  if amount < 0.05 then return end
  local num = math.floor(amount * 60)
  for i = 1, num do
    pix(s, math.random(0, W - 1), math.random(0, H - 1), math.random(0, 1))
  end
end

local function draw_entity_face(s)
  if entity_face_timer <= 0 then return end
  local cx, cy = W / 2, H / 2
  circ(s, cx, cy, 25, WHITE)
  circ(s, cx, cy, 24, DARK)
  circ(s, cx - 9, cy - 5, 6, WHITE)
  circ(s, cx + 9, cy - 5, 6, WHITE)
  circ(s, cx - 9, cy - 5, 3, BLACK)
  circ(s, cx + 9, cy - 5, 3, BLACK)
  pix(s, cx - 9, cy - 5, WHITE)
  pix(s, cx + 9, cy - 5, WHITE)
  for i = -12, 12 do
    local my = cy + 10 + math.floor(math.sin(i * 0.8) * 3)
    if cx + i >= 0 and cx + i < W and my >= 0 and my < H then
      pix(s, cx + i, my, WHITE)
    end
  end
end

local function update_horror()
  -- Urgency based on entity distance (0=far, 1=caught)
  local urgency = clamp(1 - entity_dist / 10, 0, 1)

  -- Drips
  amb_drip_timer = amb_drip_timer - 1
  if amb_drip_timer <= 0 then
    amb_drip_timer = 40 + math.random(80)
    snd_drip()
  end

  -- Creaks
  amb_creak_timer = amb_creak_timer - 1
  if amb_creak_timer <= 0 then
    amb_creak_timer = 60 + math.random(math.floor(lerp(120, 30, urgency)))
    snd_creak()
  end

  -- Heartbeat
  heartbeat_rate = urgency
  if heartbeat_rate > 0.15 then
    heartbeat_timer = heartbeat_timer - 1
    local interval = math.floor(lerp(30, 6, heartbeat_rate))
    if heartbeat_timer <= 0 then
      heartbeat_timer = interval
      snd_heartbeat(heartbeat_rate)
    end
  end

  -- Entity eyes
  update_entity_eyes()
  if math.random(100) < math.floor(urgency * 12) then
    spawn_entity_eyes()
  end

  -- Tendrils
  update_tendrils(urgency)

  -- Static
  static_amount = 0
  if urgency > 0.5 then
    static_amount = (urgency - 0.5) * 0.6
    if urgency > 0.85 then
      static_amount = static_amount + math.random() * 0.2
    end
  end

  -- Scare events
  scare_timer = scare_timer - 1
  if scare_timer <= 0 then
    scare_timer = math.floor(lerp(300, 60, urgency)) + math.random(60)
    if urgency > 0.3 and math.random(100) < math.floor(urgency * 40) then
      snd_jumpscare()
      scare_flash = math.floor(urgency * 4) + 2
      shake_timer = math.floor(urgency * 6) + 4
    end
  end

  -- Decay effects
  if scare_flash > 0 then scare_flash = scare_flash - 1 end
  if shake_timer > 0 then
    shake_timer = shake_timer - 1
    shake_x = math.random(-2, 2)
    shake_y = math.random(-1, 1)
  else
    shake_x = 0
    shake_y = 0
  end
  if entity_face_timer > 0 then entity_face_timer = entity_face_timer - 1 end
end

----------------------------------------------
-- HOTSPOT DEFINITIONS (from Agent 18 adapted)
----------------------------------------------
local hotspots = {}

local function get_wall_hotspots(room, dir)
  local key = room * 10 + dir
  return hotspots[key] or {}
end

local function build_hotspots()
  hotspots = {}

  -- ==========================================
  -- ROOM 1: CELL
  -- ==========================================
  hotspots[11] = {
    {x=60, y=42, w=28, h=36, name="cell_door",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, flags.cell_searched)
        if sonar_visible() then
          if not has_light and sonar_reveal > 0 then
            text(s, "?", hs.x + 12, hs.y + 14, DARK)
          elseif has_light then
            text(s, "DOOR", hs.x + 4, hs.y + 14, DARK)
          end
        end
      end,
      interact=function()
        if flags.cell_searched then
          snd_door()
          show_msg("Into the corridor...", 60)
          trans_timer = 15
          cur_room = 2
          cur_dir = DIR_S
        elseif sonar_visible() then
          flags.cell_searched = true
          snd_door()
          show_msg("The corroded latch gives way!", 90)
        else
          show_msg("A heavy door. Ping to see.", 60)
          snd_locked()
        end
      end
    }
  }

  hotspots[12] = {
    {x=40, y=44, w=50, h=28, name="cell_wall",
      draw=function(s, hs)
        if not sonar_visible() then return end
        local c = has_light and LIGHT or DARK
        for i = 0, 7 do
          line(s, hs.x + 4 + i*5, hs.y + 2, hs.x + 4 + i*5, hs.y + 14, c)
        end
        if has_light then
          text(s, "DONT FORGET", hs.x + 2, hs.y + 18, DARK)
        end
      end,
      interact=function()
        if sonar_visible() then
          show_document("The tally marks cover the wall. Hundreds. At the bottom, scratched deep: 'THEY ERASE YOU. DO NOT FORGET.' Below: 'Keycard taped behind pipe, corridor.'")
        else
          show_msg("Rough scratches. Ping to see.", 60)
        end
      end
    }
  }

  hotspots[13] = {
    {x=45, y=50, w=50, h=20, name="cell_cot",
      draw=function(s, hs)
        if not sonar_visible() then return end
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
        if not has_item("journal1") and sonar_visible() then
          add_item("journal1")
          show_document("Journal, Day 1: 'They moved me to sublevel 4 after I found the files. Dr. Wren says it is for my safety. I do not believe him. I will hide these pages where they cannot find them.'")
        elseif not sonar_visible() then
          show_msg("A narrow cot. Something underneath?", 60)
        else
          show_msg("Your cot. Still warm.", 40)
        end
      end
    }
  }

  hotspots[14] = {
    {x=50, y=52, w=36, h=20, name="cell_floor",
      draw=function(s, hs)
        if not sonar_visible() then return end
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
        elseif not has_item("lens") and sonar_visible() then
          add_item("lens")
          show_msg("A cracked magnifying lens.", 60)
        elseif not sonar_visible() then
          show_msg("Something on the floor.", 40)
        else
          show_msg("Cold concrete floor.", 40)
        end
      end
    }
  }

  -- ==========================================
  -- ROOM 2: CORRIDOR
  -- ==========================================
  hotspots[21] = {
    {x=55, y=42, w=28, h=36, name="corr_lab_door",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, false)
        if sonar_visible() and has_light then
          text(s, "LAB", hs.x + 6, hs.y + 14, DARK)
          rectf(s, hs.x + hs.w + 2, hs.y + 10, 6, 10, LIGHT)
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

  hotspots[22] = {
    {x=30, y=44, w=34, h=24, name="corr_notices",
      draw=function(s, hs)
        if not sonar_visible() then return end
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
        if sonar_visible() then
          show_document("A faded memo: 'REMINDER: All Project LETHE test subjects must be sedated before memory wipe. Unsedated wipes cause permanent brain damage. -- Dr. H. Wren, Director'")
        else
          show_msg("A notice board. Too dark to read.", 60)
        end
      end
    },
    {x=95, y=44, w=26, h=34, name="corr_office_door",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, false)
        if sonar_visible() and has_light then text(s, "OFC", hs.x + 4, hs.y + 14, DARK) end
      end,
      interact=function()
        if has_item("keycard") or held_item == "keycard" then
          snd_door()
          show_msg("Entering the office...", 60)
          trans_timer = 15
          cur_room = 5
          cur_dir = DIR_N
        else
          snd_locked()
          show_msg("Locked. Needs a keycard.", 60)
        end
      end
    }
  }

  hotspots[23] = {
    {x=60, y=42, w=28, h=36, name="corr_cell_door",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, true)
        if sonar_visible() and has_light then text(s, "CELL", hs.x + 4, hs.y + 14, LIGHT) end
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
    {x=28, y=42, w=30, h=14, name="corr_pipes",
      draw=function(s, hs)
        if not sonar_visible() then return end
        local c = has_light and LIGHT or DARK
        for i = 0, 2 do
          line(s, hs.x, hs.y + i * 5, hs.x + hs.w, hs.y + i * 5, c)
        end
        if not flags.keycard_found and has_light then
          rectf(s, hs.x + 12, hs.y + 6, 8, 5, WHITE)
        end
      end,
      interact=function()
        if not flags.keycard_found and sonar_visible() then
          flags.keycard_found = true
          add_item("keycard")
          show_msg("Keycard: 'WREN, H. -- LVL 4'", 90)
        elseif not sonar_visible() then
          show_msg("Pipes overhead. Can't see well.", 60)
        else
          show_msg("Just pipes.", 40)
        end
      end
    },
    {x=85, y=48, w=26, h=30, name="corr_storage_door",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, false)
        if sonar_visible() and has_light then text(s, "STOR", hs.x + 2, hs.y + 10, DARK) end
      end,
      interact=function()
        snd_door()
        show_msg("Storage room...", 40)
        trans_timer = 15
        cur_room = 3
        cur_dir = DIR_N
      end
    }
  }

  -- ==========================================
  -- ROOM 3: STORAGE
  -- ==========================================
  hotspots[31] = {
    {x=35, y=42, w=30, h=36, name="stor_shelf_l",
      draw=function(s, hs)
        draw_bookshelf(s, hs.x, hs.y)
        if not has_item("wire") and sonar_visible() then
          line(s, hs.x + 14, hs.y + 2, hs.x + 14, hs.y + 10, has_light and WHITE or LIGHT)
        end
      end,
      interact=function()
        if not has_item("wire") and sonar_visible() then
          add_item("wire")
        elseif not sonar_visible() then
          show_msg("Shelves full of junk.", 40)
        else
          show_msg("Rusty equipment.", 40)
        end
      end
    },
    {x=80, y=42, w=30, h=36, name="stor_shelf_r",
      draw=function(s, hs)
        draw_bookshelf(s, hs.x, hs.y)
        if not has_item("metal_rod") and sonar_visible() then
          rectf(s, hs.x + 12, hs.y + 14, 2, 10, has_light and WHITE or LIGHT)
        end
      end,
      interact=function()
        if not has_item("metal_rod") and sonar_visible() then
          add_item("metal_rod")
        elseif not sonar_visible() then
          show_msg("Something metal here...", 40)
        else
          show_msg("Empty shelf.", 40)
        end
      end
    }
  }

  hotspots[32] = {
    {x=40, y=48, w=24, h=18, name="stor_box1",
      draw=function(s, hs)
        draw_box(s, hs.x, hs.y, hs.w, hs.h, false)
        if sonar_visible() and has_light then text(s, "FUSE", hs.x + 4, hs.y + 6, DARK) end
      end,
      interact=function()
        if not has_item("fuse_dead") and sonar_visible() then
          add_item("fuse_dead")
          show_msg("A blown fuse. Needs repair.", 60)
        elseif not sonar_visible() then
          show_msg("A box of something.", 40)
        else
          show_msg("Empty box.", 40)
        end
      end
    },
    {x=80, y=48, w=24, h=18, name="stor_box2",
      draw=function(s, hs)
        draw_box(s, hs.x, hs.y, hs.w, hs.h, false)
        if sonar_visible() and has_light then text(s, "TAPE", hs.x + 4, hs.y + 6, DARK) end
      end,
      interact=function()
        if not has_item("tape") and sonar_visible() then
          add_item("tape")
        elseif not sonar_visible() then
          show_msg("Another box.", 40)
        else
          show_msg("Nothing left.", 40)
        end
      end
    }
  }

  hotspots[33] = {
    {x=60, y=42, w=28, h=36, name="stor_door",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, true)
        if sonar_visible() and has_light then text(s, "CORR", hs.x + 2, hs.y + 14, LIGHT) end
      end,
      interact=function()
        snd_door()
        trans_timer = 15
        cur_room = 2
        cur_dir = DIR_W
      end
    }
  }

  hotspots[34] = {
    {x=40, y=44, w=50, h=28, name="stor_chem",
      draw=function(s, hs)
        if not sonar_visible() then return end
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
          rectf(s, hs.x + 38, hs.y + 16, 8, 6, WHITE)
        end
      end,
      interact=function()
        if not has_item("journal2") and sonar_visible() then
          add_item("journal2")
          show_document("Journal, Day 15: 'The other subjects cannot remember their own names. They stare at walls. I hide my journal pages. If they wipe me again, perhaps I will find them. The vials: LETHE COMPOUND. They use it to erase us.'")
        elseif sonar_visible() then
          show_msg("LETHE COMPOUND. Memory eraser.", 60)
        else
          show_msg("Chemical smell. Can't see.", 60)
        end
      end
    }
  }

  -- ==========================================
  -- ROOM 4: LAB
  -- ==========================================
  hotspots[41] = {
    {x=60, y=46, w=18, h=14, name="lab_fusebox",
      draw=function(s, hs)
        draw_fuse_box(s, hs.x, hs.y, flags.lab_powered)
      end,
      interact=function()
        if flags.lab_powered then
          show_msg("Fuse in place. Power on.", 40)
        elseif held_item == "fuse_good" or has_item("fuse_good") then
          remove_item("fuse_good")
          flags.lab_powered = true
          held_item = nil
          snd_solve()
          show_msg("Power restored!", 90)
          sfx_noise(0, 0.3)
        else
          show_msg("Fuse box. One fuse missing.", 60)
        end
      end
    },
    {x=90, y=42, w=28, h=22, name="lab_terminal",
      draw=function(s, hs)
        draw_terminal(s, hs.x, hs.y, flags.lab_powered)
      end,
      interact=function()
        if not flags.lab_powered then
          show_msg("Terminal is dead. No power.", 60)
        elseif not flags.terminal_used then
          flags.terminal_used = true
          flags.code_found = true
          show_document("TERMINAL: PROJECT LETHE -- Subject Database. You search for your name but cannot remember it. One flagged file: 'EXIT OVERRIDE CODE: 7439'. You memorize it.")
        else
          show_msg("Terminal: code 7439", 60)
        end
      end
    }
  }

  hotspots[42] = {
    {x=45, y=46, w=40, h=30, name="lab_chair",
      draw=function(s, hs)
        if not sonar_visible() then return end
        local c = has_light and WHITE or LIGHT
        rectf(s, hs.x + 8, hs.y, 24, hs.h, has_light and DARK or BLACK)
        rect(s, hs.x + 8, hs.y, 24, hs.h, c)
        line(s, hs.x + 10, hs.y + 8, hs.x + 30, hs.y + 8, c)
        line(s, hs.x + 10, hs.y + 20, hs.x + 30, hs.y + 20, c)
        circ(s, hs.x + 20, hs.y + 4, 6, c)
      end,
      interact=function()
        if sonar_visible() then
          show_document("Restraints worn smooth from hundreds of uses. Electrodes on a headpiece. Placard: 'LETHE ADMINISTRATION STATION 3'. Cold recognition. You have sat here. Many times.")
        else
          show_msg("Something bulky with straps.", 60)
        end
      end
    }
  }

  hotspots[43] = {
    {x=60, y=42, w=28, h=36, name="lab_door",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, true)
        if sonar_visible() and has_light then text(s, "CORR", hs.x + 2, hs.y + 14, LIGHT) end
      end,
      interact=function()
        snd_door()
        trans_timer = 15
        cur_room = 2
        cur_dir = DIR_N
      end
    }
  }

  hotspots[44] = {
    {x=40, y=52, w=60, h=16, name="lab_desk",
      draw=function(s, hs)
        draw_desk(s, hs.x, hs.y)
        if not flags.desk_pried and sonar_visible() then
          rectf(s, hs.x + 22, hs.y + 2, 16, 10, has_light and WHITE or LIGHT)
          if has_light then text(s, "LOCK", hs.x + 24, hs.y + 3, DARK) end
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
          show_document("Journal, Day 31: 'I know the truth. I am not a researcher. I am Subject 17. They gave me false memories. The real Dr. Wren died months ago. Someone impersonates him. I must escape with the evidence before they wipe me again.'")
        elseif has_item("lockpick") or has_item("crowbar") then
          show_msg("Locked drawer. Use a tool on it.", 60)
        else
          show_msg("Drawer is locked tight.", 60)
        end
      end
    }
  }

  -- ==========================================
  -- ROOM 5: OFFICE
  -- ==========================================
  hotspots[51] = {
    {x=50, y=44, w=40, h=28, name="ofc_painting",
      draw=function(s, hs)
        draw_painting(s, hs.x, hs.y, hs.w, hs.h)
        if sonar_visible() and has_light then
          text(s, "H.WREN", hs.x + 6, hs.y + hs.h + 2, DARK)
        end
      end,
      interact=function()
        if not has_item("note_l") and sonar_visible() then
          add_item("note_l")
          show_msg("Behind the painting: torn note '74..'", 80)
        elseif sonar_visible() then
          show_msg("Portrait of Dr. Wren. Hollow eyes.", 60)
        else
          show_msg("A framed picture. Too dark.", 60)
        end
      end
    }
  }

  hotspots[52] = {
    {x=55, y=44, w=22, h=30, name="ofc_cabinet",
      draw=function(s, hs)
        draw_filing_cabinet(s, hs.x, hs.y, flags.evidence_found)
      end,
      interact=function()
        if not flags.evidence_found and sonar_visible() then
          flags.evidence_found = true
          add_item("evidence")
          show_document("Subject 17 file: photographs of you strapped to the chair. 31 memory wipes documented. Dosage records. Side effects: confusion, identity loss, false memory implantation. This is the proof you need.")
        elseif flags.evidence_found then
          show_msg("Empty cabinet.", 40)
        else
          show_msg("Filing cabinet. Ping to see.", 60)
        end
      end
    },
    {x=90, y=50, w=24, h=22, name="ofc_safe",
      draw=function(s, hs)
        draw_safe(s, hs.x, hs.y, flags.safe_open)
        if not flags.safe_open and sonar_visible() then
          for i = 1, 4 do
            text(s, tostring(flags.safe_digits[i]), hs.x + (i - 1) * 6, hs.y + hs.h + 2, has_light and WHITE or LIGHT)
          end
          local ax = hs.x + (flags.safe_sel - 1) * 6
          text(s, "^", ax, hs.y + hs.h + 8, WHITE)
        end
      end,
      interact=function()
        if flags.safe_open then
          show_msg("Safe is empty.", 40)
        elseif not sonar_visible() then
          show_msg("A safe. Can't see the dial.", 60)
        else
          flags.safe_mode = true
          show_msg("UP/DN:digit L/R:sel A:try B:exit", 120)
        end
      end
    }
  }

  hotspots[53] = {
    {x=60, y=42, w=28, h=36, name="ofc_door_corr",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, true)
        if sonar_visible() and has_light then text(s, "CORR", hs.x + 2, hs.y + 14, LIGHT) end
      end,
      interact=function()
        snd_door()
        trans_timer = 15
        cur_room = 2
        cur_dir = DIR_E
      end
    },
    {x=100, y=48, w=24, h=30, name="ofc_door_exit",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, false)
        if sonar_visible() and has_light then text(s, "EXIT", hs.x + 2, hs.y + 10, DARK) end
      end,
      interact=function()
        if has_item("crowbar") or has_item("lockpick") or held_item == "crowbar" or held_item == "lockpick" then
          snd_door()
          show_msg("Pried the door open.", 60)
          trans_timer = 15
          cur_room = 6
          cur_dir = DIR_N
        else
          snd_locked()
          show_msg("Jammed shut. Need a pry tool.", 60)
        end
      end
    }
  }

  hotspots[54] = {
    {x=40, y=52, w=60, h=16, name="ofc_desk",
      draw=function(s, hs)
        draw_desk(s, hs.x, hs.y)
        if sonar_visible() and has_light then
          for i = 0, 3 do
            rectf(s, hs.x + 4 + i * 12, hs.y + 2, 8, 6, LIGHT)
          end
        end
      end,
      interact=function()
        if not has_item("note_r") and sonar_visible() then
          add_item("note_r")
          show_document("Memos between Wren and 'DIRECTOR': 'Subject 17 must be wiped again before the audit. Maximum dosage.' Date: three days ago. A torn note falls out: '..39'")
        elseif sonar_visible() then
          show_msg("Desk covered in memos.", 40)
        else
          show_msg("A large desk. Papers rustle.", 40)
        end
      end
    }
  }

  -- ==========================================
  -- ROOM 6: EXIT HALL
  -- ==========================================
  hotspots[61] = {
    {x=50, y=40, w=40, h=38, name="exit_blast_door",
      draw=function(s, hs)
        if not sonar_visible() then return end
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
          state = "win"
        elseif flags.code_found then
          show_msg("Enter code on the keypad.", 60)
        else
          show_msg("Blast door. A keypad beside it.", 60)
        end
      end
    },
    {x=96, y=46, w=16, h=20, name="exit_keypad",
      draw=function(s, hs) draw_keypad(s, hs.x, hs.y) end,
      interact=function()
        if flags.code_found then
          flags.escaped = true
          state = "win"
          snd_solve()
        else
          show_msg("Keypad needs a 4-digit code.", 60)
          snd_locked()
        end
      end
    }
  }

  hotspots[63] = {
    {x=60, y=42, w=28, h=36, name="exit_back",
      draw=function(s, hs)
        draw_door(s, hs.x, hs.y, hs.w, hs.h, true)
        if sonar_visible() and has_light then text(s, "OFC", hs.x + 4, hs.y + 14, LIGHT) end
      end,
      interact=function()
        snd_door()
        trans_timer = 15
        cur_room = 5
        cur_dir = DIR_S
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
      add_item("crowbar")
      snd_solve()
      show_msg("Safe opened! Crowbar inside!", 90)
    else
      snd_locked()
      show_msg("Wrong combination.", 60)
      -- Entity reacts to failed attempt
      if entity_dist > 2 then
        entity_alert = true
        entity_chase_timer = 90
      end
    end
  end
  if btnp("b") then flags.safe_mode = false show_msg("", 0) end
  return true
end

----------------------------------------------
-- INPUT
----------------------------------------------
local function update_play_input()
  -- Reading a document
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

  -- SONAR PING on A when cursor not on hotspot (or as primary action)
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

  -- A button: interact with hotspot OR sonar ping
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
      -- No hotspot hit: fire sonar ping
      do_sonar_ping()
    end
  end

  -- SELECT: sonar ping (dedicated button)
  if btnp("select") then
    do_sonar_ping()
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

  local room_names = {"CELL", "CORRIDOR", "STORAGE", "LAB", "OFFICE", "EXIT HALL"}

  -- Draw hotspots (only visible with sonar/light)
  local spots = get_wall_hotspots(cur_room, cur_dir)
  for _, hs in ipairs(spots) do
    if hs.draw then hs.draw(s, hs) end
  end

  -- Sonar pulse visual: expanding ring from center
  if sonar_active and sonar_pulse_radius < 120 then
    local r = sonar_pulse_radius
    local cx, cy = 80, 60
    local segs = 32
    local c = r < 40 and LIGHT or DARK
    for i = 0, segs - 1 do
      local a = (i / segs) * math.pi * 2
      local rx = cx + math.cos(a) * r
      local ry = cy + math.sin(a) * r * 0.6
      if rx >= 0 and rx < W and ry >= 0 and ry < H then
        pix(s, math.floor(rx), math.floor(ry), c)
      end
    end
  end

  -- Direction arrows
  local ac = sonar_visible() and LIGHT or DARK
  text(s, "<", 4, 55, ac)
  text(s, ">", W - 10, 55, ac)

  -- Crosshair cursor
  local cf = frm % 20 < 10
  local cc = cf and WHITE or LIGHT
  line(s, cur_x - 4, cur_y, cur_x - 1, cur_y, cc)
  line(s, cur_x + 1, cur_y, cur_x + 4, cur_y, cc)
  line(s, cur_x, cur_y - 4, cur_x, cur_y - 1, cc)
  line(s, cur_x, cur_y + 1, cur_x, cur_y + 4, cc)

  -- HUD bar
  rectf(s, 0, H - 10, W, 10, BLACK)
  line(s, 0, H - 10, W, H - 10, sonar_visible() and LIGHT or DARK)
  text(s, room_names[cur_room] or "?", 2, H - 8, WHITE)
  text(s, DIR_NAMES[cur_dir], W - 30, H - 8, LIGHT)

  if held_item and ITEMS[held_item] then
    text(s, "[" .. ITEMS[held_item].icon .. "]", 56, H - 8, WHITE)
  end

  -- Sonar cooldown indicator
  if sonar_timer > 0 then
    local bar_w = math.floor((sonar_timer / SONAR_COOLDOWN) * 16)
    rectf(s, 80 - 8, H - 4, bar_w, 2, DARK)
  else
    if frm % 40 < 30 then
      pix(s, 80, H - 3, LIGHT)
    end
  end

  -- Entity proximity warning (visual heartbeat on edges)
  local urgency = clamp(1 - entity_dist / 10, 0, 1)
  if heartbeat_rate > 0.3 then
    local pulse = math.sin(frm * 0.3) * heartbeat_rate
    if pulse > 0.3 then
      local c = heartbeat_rate > 0.7 and LIGHT or DARK
      for i = 0, W - 1, 4 do
        pix(s, i, 0, c)
        pix(s, i, H - 11, c)
      end
      for i = 0, H - 11, 4 do
        pix(s, 0, i, c)
        pix(s, W - 1, i, c)
      end
    end
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

  -- Document overlay
  if doc_text then
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
    rectf(s, 8, 12, 68, 10 + #inv * 9, BLACK)
    rect(s, 8, 12, 68, 10 + #inv * 9, WHITE)
    text(s, "INVENTORY", 12, 14, WHITE)
    if combine_mode then
      text(s, "(CRAFT)", 58, 14, LIGHT)
    end
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
    local hy = 24 + #inv * 9
    text(s, "SEL:Use START:Craft", 10, hy, DARK)
  end

  -- === HORROR OVERLAYS (from Agent 19) ===
  draw_vignette(s, urgency * 0.8)
  draw_entity_eyes(s)
  draw_tendrils(s)
  draw_static(s, static_amount)

  -- Critical: scanlines
  if urgency > 0.8 then
    for i = 1, 5 do
      local y = math.random(0, H - 1)
      line(s, 0, y, W - 1, y, DARK)
    end
  end

  -- Scare flash
  if scare_flash > 0 and scare_flash % 2 == 0 then
    cls(s, WHITE)
    draw_entity_face(s)
    return
  end

  -- Entity face overlay
  if entity_face_timer > 0 then
    draw_entity_face(s)
  end

  -- Screen shake
  if shake_timer > 0 then
    if shake_x > 0 then rectf(s, 0, 0, shake_x, H - 1, BLACK) end
    if shake_x < 0 then rectf(s, W + shake_x, 0, W - 1, H - 1, BLACK) end
    if shake_y > 0 then rectf(s, 0, 0, W - 1, shake_y, BLACK) end
    if shake_y < 0 then rectf(s, 0, H + shake_y, W - 1, H - 1, BLACK) end
  end

  -- Transition
  if trans_timer > 0 then
    trans_timer = trans_timer - 1
    local skip = math.max(1, math.floor((1 - trans_timer / 15.0) * 4))
    for y = 0, H - 1, skip do
      line(s, 0, y, W, y, BLACK)
    end
  end
end

----------------------------------------------
-- TITLE SCREEN
----------------------------------------------
local title_reveal = 0
local title_pulse = 0
local title_flicker = 0

local function draw_title(s)
  cls(s, BLACK)

  title_reveal = title_reveal + 1
  title_pulse = title_pulse + 1

  -- Atmospheric flicker
  if math.random() < 0.03 then
    cls(s, DARK)
  end

  -- Title flicker (horror)
  if title_flicker > 0 then
    title_flicker = title_flicker - 1
  elseif math.random(200) < 3 then
    title_flicker = 5
  end

  local tc = WHITE
  if title_flicker > 3 then tc = BLACK
  elseif math.random(100) < 5 then tc = DARK
  elseif math.random(100) < 10 then tc = LIGHT end

  if tc > BLACK then
    text(s, "THE DARK ROOM", W / 2, 14, tc, ALIGN_HCENTER)
  end
  text(s, "RESONANCE", W / 2, 26, LIGHT, ALIGN_HCENTER)

  line(s, 30, 34, 130, 34, DARK)

  if title_reveal > 20 then
    text(s, "you wake in darkness.", W / 2, 40, DARK, ALIGN_HCENTER)
  end
  if title_reveal > 50 then
    text(s, "no memory. no name.", W / 2, 50, DARK, ALIGN_HCENTER)
  end
  if title_reveal > 80 then
    text(s, "ping to see.", W / 2, 60, LIGHT, ALIGN_HCENTER)
  end
  if title_reveal > 100 then
    text(s, "but something listens.", W / 2, 70, DARK, ALIGN_HCENTER)
  end

  -- Sonar ring on title
  local ring_r = (title_pulse % 60) * 1.5
  if ring_r < 80 then
    local cx, cy = W / 2, 90
    local segs = 24
    for i = 0, segs - 1 do
      local a = (i / segs) * math.pi * 2
      local rx = cx + math.cos(a) * ring_r
      local ry = cy + math.sin(a) * ring_r * 0.4
      if rx >= 0 and rx < W and ry >= 0 and ry < H then
        local c = ring_r < 40 and DARK or BLACK
        if c > 0 then pix(s, math.floor(rx), math.floor(ry), c) end
      end
    end
    pix(s, cx, cy, WHITE)
  end

  -- Entity eyes in title
  if title_reveal > 60 and math.random(100) < 5 then
    local ex2 = math.random(10, W - 10)
    local ey2 = math.random(88, H - 8)
    pix(s, ex2, ey2, DARK)
    pix(s, ex2 + 3, ey2, DARK)
  end

  -- Sonar ping sound on title
  if title_pulse % 60 == 0 then
    sfx_wave(CH_SONAR, "sine")
    sfx_tone(CH_SONAR, 800, 600, 0.1)
  end

  -- Blink prompt
  if title_reveal > 120 and title_pulse % 40 < 25 then
    text(s, "PRESS START", W / 2, 104, LIGHT, ALIGN_HCENTER)
  end

  text(s, "A:Ping/Act B:Inv SEL:Ping", W / 2, H - 6, DARK, ALIGN_HCENTER)
end

----------------------------------------------
-- PAUSE SCREEN
----------------------------------------------
local function draw_pause(s)
  draw_game(s)
  dither_rectf(s, 30, 40, 100, 30, BLACK, DARK, 2)
  rect(s, 30, 40, 100, 30, WHITE)
  text(s, "PAUSED", 80, 44, WHITE, ALIGN_HCENTER)
  local opts = {"Resume", "Quit"}
  for i, o in ipairs(opts) do
    local c = (i == pause_sel) and WHITE or DARK
    local p = (i == pause_sel) and "> " or "  "
    text(s, p .. o, 50, 52 + (i - 1) * 9, c)
  end
  text(s, "...it waits...", 80, 74, DARK, ALIGN_HCENTER)
end

----------------------------------------------
-- WIN SCREEN (multiple endings from Agent 18)
----------------------------------------------
local win_timer = 0

local function draw_win(s)
  cls(s, BLACK)
  win_timer = win_timer + 1

  local t = math.min(win_timer, 120) / 120.0
  local lw = math.floor(t * 80)
  dither_rectf(s, 80 - lw // 2, 0, lw, H, DARK, LIGHT, 2)

  text(s, "YOU ESCAPED", 80, 16, WHITE, ALIGN_HCENTER)
  text(s, "THE DARK ROOM", 80, 28, WHITE, ALIGN_HCENTER)

  local docs = flags.docs_read or 0
  local has_ev = has_item("evidence")
  local has_j3 = has_item("journal3")

  -- Ending based on evidence collected
  if has_ev and has_j3 and docs >= 6 then
    -- Best ending: full truth
    text(s, "With evidence and journal,", 80, 44, LIGHT, ALIGN_HCENTER)
    text(s, "the world will know.", 80, 54, LIGHT, ALIGN_HCENTER)
    text(s, "Subject 17 is FREE.", 80, 68, WHITE, ALIGN_HCENTER)
    text(s, "ENDING: TRUTH REVEALED", 80, 82, WHITE, ALIGN_HCENTER)
  elseif has_ev then
    -- Good ending: evidence but incomplete story
    text(s, "With evidence in hand,", 80, 44, LIGHT, ALIGN_HCENTER)
    text(s, "they cannot silence you.", 80, 54, LIGHT, ALIGN_HCENTER)
    text(s, "But who are you, really?", 80, 68, DARK, ALIGN_HCENTER)
    text(s, "ENDING: INCOMPLETE FREEDOM", 80, 82, LIGHT, ALIGN_HCENTER)
  else
    -- Bare escape: no proof
    text(s, "Free, but without proof.", 80, 44, LIGHT, ALIGN_HCENTER)
    text(s, "Who will believe you?", 80, 54, DARK, ALIGN_HCENTER)
    text(s, "They will come again.", 80, 68, DARK, ALIGN_HCENTER)
    text(s, "ENDING: HOLLOW ESCAPE", 80, 82, DARK, ALIGN_HCENTER)
  end

  if win_timer > 60 and frm % 60 < 40 then
    text(s, "PRESS START", 80, 100, LIGHT, ALIGN_HCENTER)
  end
end

----------------------------------------------
-- DEATH SCREEN (from Agent 13 + 19)
----------------------------------------------
local death_timer = 0

local function draw_death(s)
  cls(s, BLACK)
  death_timer = death_timer + 1

  if death_timer < 20 then
    -- Static burst + entity face
    for i = 1, 100 do
      pix(s, math.random(0, W - 1), math.random(0, H - 1), math.random(0, WHITE))
    end
    if death_timer > 8 then
      draw_entity_face(s)
    end
    return
  end

  if death_timer < 40 then
    local progress = (death_timer - 20) / 20
    draw_vignette(s, progress)
    text(s, "IT FOUND YOU", 80, 55, DARK, ALIGN_HCENTER)
    return
  end

  -- Glitch lines
  if math.random() < 0.1 then
    local y = math.random(0, H - 1)
    line(s, 0, y, W - 1, y, DARK)
  end

  text(s, "IT FOUND YOU", 80, 24, WHITE, ALIGN_HCENTER)
  text(s, "The silence returns.", 80, 40, LIGHT, ALIGN_HCENTER)
  text(s, "Your memories scatter.", 80, 50, DARK, ALIGN_HCENTER)

  if death_timer > 90 and frm % 40 < 25 then
    text(s, "PRESS START", 80, 80, DARK, ALIGN_HCENTER)
  end
end

----------------------------------------------
-- DEMO MODE
----------------------------------------------
local demo_step = 0
local demo_wait = 0
local demo_room_seq = {1, 1, 1, 2, 2, 2, 3, 3, 4, 4, 5, 6}
local demo_dir_seq  = {1, 2, 4, 1, 2, 4, 1, 4, 1, 2, 1, 1}
local demo_cx_seq   = {65, 55, 60, 65, 60, 50, 55, 55, 65, 60, 65, 70}
local demo_cy_seq   = {55, 55, 58, 55, 55, 55, 55, 55, 55, 55, 55, 55}

local function update_demo()
  demo_wait = demo_wait + 1
  -- Fire sonar during demo
  if demo_wait == 10 then
    sonar_reveal = SONAR_REVEAL_DUR
    sonar_active = true
    sonar_pulse_radius = 0
    snd_sonar()
  end
  if demo_wait >= 50 then
    demo_wait = 0
    demo_step = demo_step + 1
    if demo_step > #demo_room_seq then demo_step = 1 end
    cur_room = demo_room_seq[demo_step]
    cur_dir = demo_dir_seq[demo_step]
    cur_x = demo_cx_seq[demo_step]
    cur_y = demo_cy_seq[demo_step]
    snd_turn()
  end
  cur_x = cur_x + math.sin(frm * 0.05) * 0.5
  cur_y = cur_y + math.cos(frm * 0.07) * 0.3
  update_sonar()

  if btnp("start") or btnp("a") or btnp("b") or btnp("up") or btnp("down") or btnp("left") or btnp("right") or btnp("select") then
    state = "title"
    idle_timer = 0
  end
end

local function draw_demo(s)
  local old_light = has_light
  has_light = true
  draw_game(s)
  has_light = old_light
  rectf(s, 0, 0, W, 9, BLACK)
  if frm % 40 < 28 then
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
  msg_text = ""
  msg_timer = 0
  trans_timer = 0
  pause_sel = 1
  sonar_timer = 0
  sonar_reveal = 0
  sonar_active = false
  sonar_pulse_radius = 0
  entity_room = 2
  entity_dist = 10
  entity_alert = false
  entity_chase_timer = 0
  entity_step_timer = 0
  entity_growl_timer = 0
  heartbeat_timer = 0
  heartbeat_rate = 0
  amb_drip_timer = 40
  amb_creak_timer = 60
  scare_timer = 200
  scare_flash = 0
  shake_timer = 0
  shake_x = 0
  shake_y = 0
  entity_eyes = {}
  darkness_tendrils = {}
  static_amount = 0
  entity_face_timer = 0
  win_timer = 0
  death_timer = 0
  reset_flags()
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
  idle_timer = 0
  title_reveal = 0
  title_pulse = 0
  title_flicker = 0
  reset_flags()
  build_hotspots()
  sfx_wave(CH_SONAR, "sine")
  sfx_wave(CH_OBJ, "sine")
  sfx_wave(CH_AMB, "triangle")
  sfx_wave(CH_STEP, "triangle")
end

function _update()
  frm = frm + 1

  if state == "title" then
    idle_timer = idle_timer + 1
    if btnp("start") or btnp("a") then
      reset_game()
      state = "play"
      show_msg("You wake. Darkness. Cold. [A] Ping.", 120)
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
    update_sonar()
    update_entity()
    update_horror()

  elseif state == "paused" then
    if btnp("start") or btnp("select") then
      state = "play"
    end
    if btnp("up") then pause_sel = clamp(pause_sel - 1, 1, 2) end
    if btnp("down") then pause_sel = clamp(pause_sel + 1, 1, 2) end
    if btnp("a") then
      if pause_sel == 1 then state = "play"
      else state = "title" idle_timer = 0 end
    end

  elseif state == "win" then
    if win_timer > 60 and (btnp("start") or btnp("a")) then
      state = "title"
      idle_timer = 0
      reset_game()
    end

  elseif state == "death" then
    if death_timer > 90 and (btnp("start") or btnp("a")) then
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
  elseif state == "death" then
    draw_death(s)
  end
end
