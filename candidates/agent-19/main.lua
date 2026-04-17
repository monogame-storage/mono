-- IT APPROACHES
-- Time-pressure horror: solve 3 puzzles before the entity catches you.
-- The countdown IS the entity. Darkness closes in. Eyes watch from shadows.
-- 160x120 | 2-bit (4 grayscale 0-3) | 30fps

---------- CONSTANTS ----------
local W = 160
local H = 120

-- 2-bit palette: 0=black, 1=dark gray, 2=light gray, 3=white
local BLACK = 0
local DARK = 1
local LIGHT = 2
local WHITE = 3

-- Timing
local TOTAL_TIME = 90 * 30   -- 90 seconds at 30fps
local WARN_TIME = 30 * 30    -- last 30s = warning
local CRIT_TIME = 10 * 30    -- last 10s = critical

-- Demo
local IDLE_TIMEOUT = 150      -- 5 seconds to demo
local DEMO_DURATION = 600     -- 20 seconds of demo

-- Puzzle types
local PUZZLE_LOCK = 1
local PUZZLE_WIRE = 2
local PUZZLE_CODE = 3

---------- UTILITY ----------
local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function text_center(s, str, y, c)
  text(s, str, W / 2, y, c, ALIGN_HCENTER)
end

---------- SOUND EFFECTS ----------
local function sfx_tick(ch)
  note(ch, "C2", 0.02)
end

local function sfx_warn()
  note(0, "A3", 0.05)
  noise(1, 0.03)
end

local function sfx_crit()
  note(0, "E4", 0.08)
  note(1, "A4", 0.08)
end

local function sfx_success()
  note(0, "C5", 0.08)
  note(1, "E5", 0.1)
  note(2, "G5", 0.12)
end

local function sfx_fail()
  note(0, "C3", 0.15)
  noise(1, 0.2)
  note(2, "A2", 0.2)
end

local function sfx_select()
  note(0, "E4", 0.04)
end

local function sfx_door()
  note(0, "C4", 0.06)
  note(1, "G4", 0.08)
  note(2, "C5", 0.1)
end

local function sfx_heartbeat()
  noise(0, 0.06)
  note(1, "C2", 0.08)
end

-- Horror-specific sounds (from agent-04)
local function sfx_scare(intensity)
  noise(0, 0.15 + intensity * 0.1)
  note(1, "C2", 0.2 + intensity * 0.1)
  note(2, "F#2", 0.15)
end

local function sfx_drip()
  note(3, "E6", 0.02)
end

local function sfx_creak()
  local creaks = {"A2", "B2", "G2", "D2"}
  note(2, creaks[math.random(#creaks)], 0.12)
end

local function sfx_entity_near()
  note(3, "D2", 0.08)
  noise(2, 0.04)
end

---------- STATE ----------
local state            -- "title","game","win","lose","attract"
local idle_timer = 0
local demo_timer = 0
local demo_step = 0
local demo_room = 0

-- Game state
local timer = 0
local room = 1
local rooms_solved = {false, false, false}
local flash_timer = 0
local pulse_phase = 0
local shake_x = 0
local shake_y = 0
local shake_timer = 0
local shake_amt = 0
local transition_timer = 0
local transition_dir = 0
local msg = ""
local msg_timer = 0
local paused = false

-- Pattern lock puzzle (room 1)
local lock_target = {}
local lock_input = {}
local lock_cursor = 0
local lock_symbols = {"^", "v", "<", ">"}

-- Wire puzzle (room 2)
local wire_pairs = {}
local wire_current = 0
local wire_cursor = 1
local wire_flash = 0

-- Code puzzle (room 3)
local code_target = {}
local code_input = {0, 0, 0}
local code_cursor = 1
local code_hints = {}

-- Horror state (from agent-04 concepts)
local entity_eyes = {}       -- {x, y, life, blink_phase} pairs of watching eyes
local scare_timer = 0        -- countdown to next scare event
local scare_flash = 0        -- white flash frames on scare
local amb_drip_timer = 0     -- ambient drip sound timer
local amb_creak_timer = 0    -- ambient creak sound timer
local heartbeat_intensity = 0 -- 0..1 how fast/loud heartbeat is
local heartbeat_timer = 0
local darkness_tendrils = {} -- visual tendrils creeping from edges
local entity_face_timer = 0  -- frames showing the entity face on failure
local static_amount = 0      -- screen static intensity 0..1

---------- PUZZLE GENERATION ----------
local function gen_lock()
  lock_target = {}
  lock_input = {}
  lock_cursor = 0
  for i = 1, 4 do
    lock_target[i] = math.random(1, 4)
  end
end

local function gen_wire()
  wire_pairs = {}
  wire_current = 1
  wire_cursor = 1
  wire_flash = 0
  local right = {1, 2, 3, 4}
  for i = 4, 2, -1 do
    local j = math.random(1, i)
    right[i], right[j] = right[j], right[i]
  end
  for i = 1, 4 do
    wire_pairs[i] = right[i]
  end
end

local function gen_code()
  code_target = {}
  code_input = {0, 0, 0}
  code_cursor = 1
  code_hints = {}
  for i = 1, 3 do
    code_target[i] = math.random(0, 9)
  end
  for i = 1, 3 do
    local offset = math.random(1, 3)
    code_hints[i] = (code_target[i] + offset) % 10
  end
end

---------- ENTITY EYES SYSTEM ----------
local function spawn_entity_eyes(urgency)
  -- Spawn watching eyes at screen edges, more as time runs out
  if #entity_eyes >= 6 then return end
  local side = math.random(1, 4)
  local ex, ey
  if side == 1 then     -- top
    ex = math.random(10, W - 10)
    ey = math.random(2, 12)
  elseif side == 2 then -- bottom
    ex = math.random(10, W - 10)
    ey = math.random(H - 14, H - 4)
  elseif side == 3 then -- left
    ex = math.random(2, 16)
    ey = math.random(10, H - 10)
  else                  -- right
    ex = math.random(W - 18, W - 4)
    ey = math.random(10, H - 10)
  end
  entity_eyes[#entity_eyes + 1] = {
    x = ex, y = ey,
    life = math.random(30, 90),
    blink = math.random(0, 100),
  }
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
    -- Eyes blink occasionally
    local blinking = (e.blink % 40) < 3
    if not blinking then
      local c = (e.life < 10) and DARK or LIGHT
      pix(s, e.x, e.y, c)
      pix(s, e.x + 3, e.y, c)
    end
  end
end

---------- DARKNESS TENDRILS ----------
local function update_tendrils(urgency)
  -- Spawn tendrils from screen edges proportional to urgency
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
  -- Update existing tendrils
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
      -- Thicker tendrils near source
      if t.life > t.len * 0.7 then
        if tx + 1 < W then pix(s, tx + 1, ty, BLACK) end
        if ty + 1 < H then pix(s, tx, ty + 1, BLACK) end
      end
    end
  end
end

---------- VIGNETTE / ATMOSPHERE ----------
local function draw_vignette(s, intensity)
  local border = math.floor(intensity * 30)
  if border < 1 then return end
  -- Top and bottom bars
  for y = 0, border - 1 do
    local c = (y < border / 2) and BLACK or DARK
    line(s, 0, y, W - 1, y, c)
    line(s, 0, H - 1 - y, W - 1, H - 1 - y, c)
  end
  -- Left and right bars
  for x = 0, border - 1 do
    local c = (x < border / 2) and BLACK or DARK
    line(s, x, border, x, H - 1 - border, c)
    line(s, W - 1 - x, border, W - 1 - x, H - 1 - border, c)
  end
end

local function draw_pulse(s, intensity)
  if intensity < 0.1 then return end
  local alpha = math.floor(intensity * 3)
  local c = clamp(alpha, 0, 2)
  local phase = math.sin(pulse_phase * 0.15) * 0.5 + 0.5
  if phase > 0.5 then
    rect(s, 0, 0, W - 1, H - 1, c)
    rect(s, 1, 1, W - 2, H - 2, c)
  end
end

local function draw_static(s, amount)
  -- TV static effect proportional to amount (0..1)
  if amount < 0.05 then return end
  local num = math.floor(amount * 60)
  for i = 1, num do
    local sx = math.random(0, W - 1)
    local sy = math.random(0, H - 1)
    pix(s, sx, sy, math.random(0, 1))
  end
end

-- Entity face flash (jump scare on wrong answer)
local function draw_entity_face(s)
  if entity_face_timer <= 0 then return end
  -- Crude horrifying face filling part of the screen
  local cx, cy = W / 2, H / 2
  -- Head outline
  circ(s, cx, cy, 25, WHITE)
  circ(s, cx, cy, 24, DARK)
  -- Hollow eyes
  circ(s, cx - 9, cy - 5, 6, WHITE)
  circ(s, cx + 9, cy - 5, 6, WHITE)
  circ(s, cx - 9, cy - 5, 3, BLACK)
  circ(s, cx + 9, cy - 5, 3, BLACK)
  -- Pupils (staring)
  pix(s, cx - 9, cy - 5, WHITE)
  pix(s, cx + 9, cy - 5, WHITE)
  -- Mouth - jagged grin
  for i = -12, 12 do
    local my = cy + 10 + math.floor(math.sin(i * 0.8) * 3)
    if cx + i >= 0 and cx + i < W and my >= 0 and my < H then
      pix(s, cx + i, my, WHITE)
    end
  end
end

---------- AMBIENT HORROR ----------
local function update_ambient(urgency)
  -- Water drips
  amb_drip_timer = amb_drip_timer - 1
  if amb_drip_timer <= 0 then
    amb_drip_timer = 40 + math.random(80)
    sfx_drip()
  end

  -- Random creaks
  amb_creak_timer = amb_creak_timer - 1
  if amb_creak_timer <= 0 then
    amb_creak_timer = 60 + math.random(math.floor(lerp(120, 30, urgency)))
    sfx_creak()
  end

  -- Heartbeat: faster as entity approaches (urgency rises)
  heartbeat_intensity = urgency
  if heartbeat_intensity > 0.15 then
    heartbeat_timer = heartbeat_timer - 1
    local interval = math.floor(lerp(30, 6, heartbeat_intensity))
    if heartbeat_timer <= 0 then
      heartbeat_timer = interval
      sfx_heartbeat()
    end
  end

  -- Entity proximity sound (urgent tones)
  if urgency > 0.6 and math.random(100) < math.floor(urgency * 8) then
    sfx_entity_near()
  end

  -- Spawn entity eyes more frequently as urgency rises
  if math.random(100) < math.floor(urgency * 12) then
    spawn_entity_eyes(urgency)
  end

  -- Scare events: random jump scares that increase with urgency
  scare_timer = scare_timer - 1
  if scare_timer <= 0 then
    scare_timer = math.floor(lerp(300, 60, urgency)) + math.random(60)
    if urgency > 0.3 and math.random(100) < math.floor(urgency * 40) then
      sfx_scare(urgency)
      scare_flash = math.floor(urgency * 4) + 2
      shake_timer = math.floor(urgency * 6) + 4
      shake_amt = math.floor(urgency * 3) + 1
    end
  end

  -- Static increases near the end
  static_amount = 0
  if urgency > 0.5 then
    static_amount = (urgency - 0.5) * 0.6
    if urgency > 0.85 then
      static_amount = static_amount + math.random() * 0.2
    end
  end

  -- Entity face timer countdown
  if entity_face_timer > 0 then
    entity_face_timer = entity_face_timer - 1
  end
end

---------- TITLE SCREEN ----------
local title_blink = 0
local title_reveal = 0

local function title_update()
  title_blink = title_blink + 1
  title_reveal = title_reveal + 1
  idle_timer = idle_timer + 1

  if btnp("start") or btnp("a") then
    state = "game"
    timer = TOTAL_TIME
    room = 1
    rooms_solved = {false, false, false}
    flash_timer = 0
    pulse_phase = 0
    paused = false
    msg = ""
    msg_timer = 0
    entity_eyes = {}
    darkness_tendrils = {}
    scare_timer = 120
    scare_flash = 0
    entity_face_timer = 0
    static_amount = 0
    heartbeat_timer = 30
    amb_drip_timer = 40
    amb_creak_timer = 60
    gen_lock()
    gen_wire()
    gen_code()
    idle_timer = 0
    sfx_door()
    transition_timer = 15
    transition_dir = 1
    return
  end

  -- Enter demo after idle
  if idle_timer > IDLE_TIMEOUT then
    state = "attract"
    demo_timer = 0
    demo_step = 0
    demo_room = 1
    timer = TOTAL_TIME
    entity_eyes = {}
    darkness_tendrils = {}
    scare_timer = 200
    gen_lock()
    gen_wire()
    gen_code()
  end
end

local function title_draw()
  local s = screen()
  cls(s, BLACK)

  -- Atmospheric flicker
  if math.random() < 0.03 then
    cls(s, DARK)
  end

  -- Title with horror flicker
  local flick = math.random(100)
  local tc = WHITE
  if flick < 5 then tc = DARK
  elseif flick < 10 then tc = LIGHT end

  text_center(s, "IT APPROACHES", 18, tc)

  -- Decorative line
  line(s, 30, 28, 130, 28, DARK)

  -- Staged reveal text (horror style from agent-04)
  if title_reveal > 20 then
    text_center(s, "you wake in darkness.", 36, DARK)
  end
  if title_reveal > 50 then
    text_center(s, "something is hunting you.", 46, DARK)
  end
  if title_reveal > 80 then
    text_center(s, "you have 90 seconds.", 56, LIGHT)
  end
  if title_reveal > 110 then
    text_center(s, "solve the puzzles. escape.", 66, DARK)
  end

  -- Blink prompt
  if title_reveal > 130 and math.floor(title_blink / 20) % 2 == 0 then
    text_center(s, "PRESS START", 82, WHITE)
  end

  -- Ambient eyes in darkness (from agent-04)
  if title_reveal > 60 and math.random(100) < 5 then
    local ex2 = math.random(10, W - 10)
    local ey2 = math.random(88, H - 8)
    pix(s, ex2, ey2, DARK)
    pix(s, ex2 + 3, ey2, DARK)
  end

  -- Controls
  text_center(s, "D-PAD:Select  A:Confirm", 100, DARK)
  text_center(s, "START:Begin  SELECT:Pause", 110, DARK)
end

---------- PUZZLE UPDATES ----------
local function trigger_fail_scare()
  -- Wrong answer: the entity reacts -- scare + entity face flash
  sfx_scare(1.5)
  scare_flash = 6
  shake_timer = 12
  shake_amt = 3
  entity_face_timer = 12
end

local function update_lock()
  if rooms_solved[1] then return end

  if btnp("up") then
    lock_input[#lock_input + 1] = 1; sfx_select()
  elseif btnp("down") then
    lock_input[#lock_input + 1] = 2; sfx_select()
  elseif btnp("left") then
    lock_input[#lock_input + 1] = 3; sfx_select()
  elseif btnp("right") then
    lock_input[#lock_input + 1] = 4; sfx_select()
  end

  if btnp("b") and #lock_input > 0 then
    table.remove(lock_input)
    noise(0, 0.03)
  end

  if #lock_input >= 4 then
    local correct = true
    for i = 1, 4 do
      if lock_input[i] ~= lock_target[i] then correct = false; break end
    end
    if correct then
      rooms_solved[1] = true
      sfx_success()
      msg = "LOCK OPENED!"
      msg_timer = 45
      flash_timer = 10
    else
      trigger_fail_scare()
      lock_input = {}
      msg = "WRONG! IT DRAWS CLOSER..."
      msg_timer = 40
      timer = timer - 120  -- 4 second penalty (harsher)
    end
  end
end

local function update_wire()
  if rooms_solved[2] then return end

  if btnp("up") then
    wire_cursor = clamp(wire_cursor - 1, 1, 4); sfx_select()
  elseif btnp("down") then
    wire_cursor = clamp(wire_cursor + 1, 1, 4); sfx_select()
  end

  if btnp("a") then
    if wire_pairs[wire_current] == wire_cursor then
      wire_current = wire_current + 1
      sfx_door()
      wire_flash = 8
      if wire_current > 4 then
        rooms_solved[2] = true
        sfx_success()
        msg = "WIRES CONNECTED!"
        msg_timer = 45
        flash_timer = 10
      end
    else
      trigger_fail_scare()
      msg = "WRONG WIRE! IT STIRS..."
      msg_timer = 40
      timer = timer - 120
    end
  end
end

local function update_code()
  if rooms_solved[3] then return end

  if btnp("left") then
    code_cursor = clamp(code_cursor - 1, 1, 3); sfx_select()
  elseif btnp("right") then
    code_cursor = clamp(code_cursor + 1, 1, 3); sfx_select()
  end

  if btnp("up") then
    code_input[code_cursor] = (code_input[code_cursor] + 1) % 10; sfx_select()
  elseif btnp("down") then
    code_input[code_cursor] = (code_input[code_cursor] - 1) % 10; sfx_select()
  end

  if btnp("a") then
    local correct = true
    for i = 1, 3 do
      if code_input[i] ~= code_target[i] then correct = false; break end
    end
    if correct then
      rooms_solved[3] = true
      sfx_success()
      msg = "CODE CRACKED!"
      msg_timer = 45
      flash_timer = 10
    else
      trigger_fail_scare()
      msg = "WRONG CODE! IT HUNGERS..."
      msg_timer = 40
      timer = timer - 120
    end
  end
end

---------- GAME UPDATE ----------
local function game_update()
  if paused then
    if btnp("select") or btnp("start") then paused = false end
    return
  end

  if btnp("select") then paused = true; return end

  -- Transition animation
  if transition_timer > 0 then
    transition_timer = transition_timer - 1
    return
  end

  -- Countdown
  timer = timer - 1
  pulse_phase = pulse_phase + 1

  -- Urgency: 0 at start, 1 at time-up
  local urgency = 1.0 - (timer / TOTAL_TIME)

  -- Time-based sounds (layered with ambient horror)
  if timer > WARN_TIME then
    if timer % 30 == 0 then sfx_tick(2) end
  elseif timer > CRIT_TIME then
    if timer % 15 == 0 then sfx_warn() end
  else
    if timer % 8 == 0 then sfx_crit() end
  end

  -- Ambient horror updates
  update_ambient(urgency)
  update_entity_eyes()
  update_tendrils(urgency)

  -- Time up = entity catches you
  if timer <= 0 then
    timer = 0
    state = "lose"
    result_timer = 0
    result_blink = 0
    sfx_scare(3)
    return
  end

  -- Screen shake update
  if shake_timer > 0 then
    shake_timer = shake_timer - 1
    shake_x = math.random(-shake_amt, shake_amt)
    shake_y = math.random(-math.ceil(shake_amt / 2), math.ceil(shake_amt / 2))
  else
    shake_x = 0
    shake_y = 0
  end

  -- Flash update
  if flash_timer > 0 then flash_timer = flash_timer - 1 end

  -- Scare flash update
  if scare_flash > 0 then scare_flash = scare_flash - 1 end

  -- Message update
  if msg_timer > 0 then msg_timer = msg_timer - 1 end

  -- Check win
  local all_solved = rooms_solved[1] and rooms_solved[2] and rooms_solved[3]
  if all_solved then
    state = "win"
    result_timer = 0
    result_blink = 0
    sfx_success()
    sfx_door()
    return
  end

  -- Navigate between rooms
  if btnp("start") then
    local next_room = room % 3 + 1
    for i = 1, 3 do
      if not rooms_solved[next_room] then break end
      next_room = next_room % 3 + 1
    end
    if next_room ~= room then
      room = next_room
      sfx_door()
      transition_timer = 8
      transition_dir = 1
    end
  end

  -- Update current puzzle
  if room == 1 then update_lock()
  elseif room == 2 then update_wire()
  elseif room == 3 then update_code()
  end

  -- Auto-advance to next unsolved room after solving
  if rooms_solved[room] and msg_timer <= 0 then
    for i = 1, 3 do
      local r = (room + i - 1) % 3 + 1
      if not rooms_solved[r] then
        room = r
        transition_timer = 8
        transition_dir = 1
        break
      end
    end
  end
end

---------- GAME DRAW ----------
local function draw_timer_bar(s)
  local secs = math.ceil(timer / 30)
  local mins = math.floor(secs / 60)
  secs = secs % 60
  local time_str = string.format("%d:%02d", mins, secs)

  local c = WHITE
  if timer < CRIT_TIME then
    c = (math.floor(pulse_phase / 4) % 2 == 0) and WHITE or DARK
  elseif timer < WARN_TIME then
    c = LIGHT
  end

  text(s, time_str, W / 2, 2, c, ALIGN_HCENTER)
end

local function draw_room_indicator(s)
  for i = 1, 3 do
    local x = W / 2 - 12 + (i - 1) * 12
    local y = 11
    if rooms_solved[i] then
      rect(s, x, y, x + 8, y + 5, LIGHT)
      rectf(s, x + 1, y + 1, x + 7, y + 4, DARK)
      text(s, "OK", x + 4, y + 1, WHITE, ALIGN_HCENTER)
    elseif i == room then
      rect(s, x, y, x + 8, y + 5, WHITE)
      text(s, tostring(i), x + 4, y + 1, WHITE, ALIGN_HCENTER)
    else
      rect(s, x, y, x + 8, y + 5, DARK)
      text(s, tostring(i), x + 4, y + 1, DARK, ALIGN_HCENTER)
    end
  end
end

local function draw_lock(s)
  text_center(s, "PATTERN LOCK", 22, LIGHT)

  text(s, "MATCH:", 10, 34, DARK)
  for i = 1, 4 do
    local sym = lock_symbols[lock_target[i]]
    text(s, sym, 46 + (i - 1) * 14, 34, WHITE)
  end

  text(s, "INPUT:", 10, 50, DARK)
  for i = 1, #lock_input do
    local sym = lock_symbols[lock_input[i]]
    text(s, sym, 46 + (i - 1) * 14, 50, LIGHT)
  end
  if #lock_input < 4 then
    local cx = 46 + #lock_input * 14
    if math.floor(pulse_phase / 10) % 2 == 0 then
      text(s, "_", cx, 50, WHITE)
    end
  end

  text_center(s, "D-PAD: Enter direction", 70, DARK)
  text_center(s, "B: Undo", 80, DARK)

  local dx, dy = 80, 98
  text(s, "^", dx, dy - 8, LIGHT, ALIGN_HCENTER)
  text(s, "v", dx, dy + 4, LIGHT, ALIGN_HCENTER)
  text(s, "<", dx - 10, dy - 2, LIGHT, ALIGN_HCENTER)
  text(s, ">", dx + 10, dy - 2, LIGHT, ALIGN_HCENTER)
end

local function draw_wire(s)
  text_center(s, "WIRE CONNECT", 22, LIGHT)

  local lx = 30
  local rx = 120
  local base_y = 38

  for i = 1, 4 do
    local y = base_y + (i - 1) * 16
    local c = (i < wire_current) and DARK or WHITE
    if i == wire_current then c = WHITE end
    rectf(s, lx - 4, y - 3, lx + 4, y + 3, DARK)
    rect(s, lx - 4, y - 3, lx + 4, y + 3, c)
    text(s, tostring(i), lx, y - 2, c, ALIGN_HCENTER)
  end

  for i = 1, 4 do
    local y = base_y + (i - 1) * 16
    local c = (i == wire_cursor) and WHITE or LIGHT
    local connected = false
    for j = 1, wire_current - 1 do
      if wire_pairs[j] == i then connected = true; break end
    end
    if connected then c = DARK end

    rectf(s, rx - 4, y - 3, rx + 4, y + 3, DARK)
    rect(s, rx - 4, y - 3, rx + 4, y + 3, c)

    local labels = {"A", "B", "C", "D"}
    text(s, labels[i], rx, y - 2, c, ALIGN_HCENTER)

    if i == wire_cursor and wire_current <= 4 then
      text(s, ">", rx - 14, y - 2, WHITE)
    end
  end

  for i = 1, wire_current - 1 do
    local ly = base_y + (i - 1) * 16
    local ry = base_y + (wire_pairs[i] - 1) * 16
    line(s, lx + 6, ly, rx - 6, ry, LIGHT)
  end

  if wire_current <= 4 and math.floor(pulse_phase / 8) % 2 == 0 then
    local ly = base_y + (wire_current - 1) * 16
    local ry = base_y + (wire_cursor - 1) * 16
    line(s, lx + 6, ly, rx - 6, ry, DARK)
  end

  text_center(s, "UP/DN:Select  A:Connect", 108, DARK)
end

local function draw_code(s)
  text_center(s, "CODE CIPHER", 22, LIGHT)

  text_center(s, "CLUE:", 36, DARK)
  for i = 1, 3 do
    local x = 55 + (i - 1) * 24
    text(s, tostring(code_hints[i]), x, 36, LIGHT, ALIGN_HCENTER)
  end

  text_center(s, "Each digit is offset by", 48, DARK)
  text_center(s, "1 to 3 from the clue above", 56, DARK)

  for i = 1, 3 do
    local x = 55 + (i - 1) * 24
    local y = 72
    local c = (i == code_cursor) and WHITE or LIGHT

    if i == code_cursor then
      text(s, "^", x, y - 10, WHITE, ALIGN_HCENTER)
    end

    rect(s, x - 8, y - 4, x + 8, y + 7, c)
    text(s, tostring(code_input[i]), x, y - 2, c, ALIGN_HCENTER)

    if i == code_cursor then
      text(s, "v", x, y + 10, WHITE, ALIGN_HCENTER)
    end
  end

  local cx = 55 + (code_cursor - 1) * 24
  rectf(s, cx - 6, 92, cx + 6, 93, WHITE)

  text_center(s, "L/R:Digit UP/DN:Value A:Submit", 102, DARK)
end

local function game_draw()
  local s = screen()

  -- Scare flash overrides everything briefly
  if scare_flash > 0 and scare_flash % 2 == 0 then
    cls(s, WHITE)
    draw_entity_face(s)
    return
  end

  -- Flash effect on success
  if flash_timer > 0 and flash_timer % 2 == 0 then
    cls(s, WHITE)
  else
    cls(s, BLACK)
  end

  -- Transition wipe
  if transition_timer > 0 then
    cls(s, BLACK)
    local progress = transition_timer / 15
    local bar_h = math.floor(progress * H / 2)
    rectf(s, 0, 0, W - 1, bar_h, BLACK)
    rectf(s, 0, H - 1 - bar_h, W - 1, H - 1, BLACK)
    draw_timer_bar(s)
    return
  end

  -- Paused overlay
  if paused then
    cls(s, BLACK)
    text_center(s, "PAUSED", 45, WHITE)
    text_center(s, "SELECT to resume", 60, LIGHT)
    text_center(s, "...it waits...", 75, DARK)
    draw_timer_bar(s)
    return
  end

  -- Draw timer and room indicators
  draw_timer_bar(s)
  draw_room_indicator(s)

  -- Draw current room puzzle
  if room == 1 then draw_lock(s)
  elseif room == 2 then draw_wire(s)
  elseif room == 3 then draw_code(s)
  end

  -- Message overlay
  if msg_timer > 0 then
    local my = 112
    rectf(s, 0, my - 2, W - 1, my + 8, BLACK)
    text_center(s, msg, my, WHITE)
  end

  -- Room navigation hint
  if msg_timer <= 0 then
    text(s, "START:Next Room", W / 2, 112, DARK, ALIGN_HCENTER)
  end

  -- === HORROR OVERLAYS ===
  local urgency = 1.0 - (timer / TOTAL_TIME)

  -- Darkness vignette (gets much worse than base agent-06)
  draw_vignette(s, urgency * 1.0)

  -- Pulsing border
  draw_pulse(s, urgency)

  -- Entity eyes watching from shadows
  draw_entity_eyes(s)

  -- Darkness tendrils creeping inward
  draw_tendrils(s)

  -- Screen static
  draw_static(s, static_amount)

  -- Critical time: scanlines
  if timer < CRIT_TIME then
    for i = 1, 5 do
      local y = math.random(0, H - 1)
      line(s, 0, y, W - 1, y, DARK)
    end
  end

  -- Entity face overlay on fail
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
end

---------- WIN / LOSE SCREENS ----------
local result_timer = 0
local result_blink = 0

local function win_update()
  result_timer = result_timer + 1
  result_blink = result_blink + 1

  if result_timer > 60 and (btnp("start") or btnp("a")) then
    state = "title"
    idle_timer = 0
    title_blink = 0
    title_reveal = 0
  end
end

local function win_draw()
  local s = screen()
  cls(s, BLACK)

  if result_timer < 15 then
    -- Blinding escape flash
    if result_timer % 3 == 0 then cls(s, WHITE) end
    return
  end

  text_center(s, "ESCAPED!", 25, WHITE)

  local secs_left = math.ceil(timer / 30)
  text_center(s, "Time remaining: " .. secs_left .. "s", 42, LIGHT)

  -- Rating
  local rating = "BARELY ALIVE"
  if secs_left > 60 then rating = "UNTOUCHABLE"
  elseif secs_left > 30 then rating = "SWIFT ESCAPE"
  elseif secs_left > 15 then rating = "CLOSE CALL"
  end
  text_center(s, rating, 58, WHITE)

  -- Flavor text
  if result_timer > 30 then
    text_center(s, "The light outside", 72, DARK)
    text_center(s, "has never felt so warm.", 82, DARK)
  end

  if result_timer > 60 and math.floor(result_blink / 20) % 2 == 0 then
    text_center(s, "PRESS START", 100, LIGHT)
  end
end

local function lose_update()
  result_timer = result_timer + 1
  result_blink = result_blink + 1

  -- Death sounds
  if result_timer == 10 then
    noise(0, 0.4)
    note(1, "C2", 0.5)
  end
  if result_timer == 30 then
    noise(1, 0.3)
    note(2, "A1", 0.5)
  end
  if result_timer == 50 then
    note(0, "F#2", 0.4)
  end

  if result_timer > 90 and (btnp("start") or btnp("a")) then
    state = "title"
    idle_timer = 0
    title_blink = 0
    title_reveal = 0
  end
end

local function lose_draw()
  local s = screen()
  cls(s, BLACK)

  if result_timer < 20 then
    -- Entity catches you: static burst + face
    for i = 1, 100 do
      pix(s, math.random(0, W - 1), math.random(0, H - 1), math.random(0, WHITE))
    end
    if result_timer > 8 then
      draw_entity_face(s)
    end
    return
  end

  if result_timer < 40 then
    -- Darkness consuming
    local progress = (result_timer - 20) / 20
    draw_vignette(s, progress)
    text_center(s, "IT FOUND YOU", 55, DARK)
    return
  end

  -- Glitch lines
  if math.random() < 0.1 then
    local y = math.random(0, H - 1)
    line(s, 0, y, W - 1, y, DARK)
  end

  text_center(s, "IT FOUND YOU", 28, WHITE)
  text_center(s, "The darkness consumed", 44, LIGHT)
  text_center(s, "everything.", 54, DARK)

  -- Stats
  local solved = 0
  for i = 1, 3 do if rooms_solved[i] then solved = solved + 1 end end
  text_center(s, "Puzzles solved: " .. solved .. "/3", 70, LIGHT)

  local secs_survived = math.floor((TOTAL_TIME - timer) / 30)
  text_center(s, "Survived: " .. secs_survived .. "s", 80, DARK)

  if result_timer > 90 and math.floor(result_blink / 20) % 2 == 0 then
    text_center(s, "PRESS START", 100, DARK)
  end
end

---------- DEMO / ATTRACT MODE ----------
local demo_input_timer = 0

local function attract_update()
  demo_timer = demo_timer + 1
  pulse_phase = pulse_phase + 1
  timer = timer - 1
  if timer < 0 then timer = 0 end

  local urgency = 1.0 - (timer / TOTAL_TIME)

  -- Update horror ambient for demo too
  update_entity_eyes()
  update_tendrils(urgency)
  if math.random(100) < math.floor(urgency * 8) then
    spawn_entity_eyes(urgency)
  end

  -- Auto-solve puzzles for demo
  demo_input_timer = demo_input_timer + 1
  if demo_input_timer >= 15 then
    demo_input_timer = 0
    demo_step = demo_step + 1

    if demo_room == 1 then
      if demo_step <= 4 then
        lock_input[demo_step] = lock_target[demo_step]
        sfx_select()
      elseif demo_step == 5 then
        rooms_solved[1] = true
        sfx_success()
        demo_room = 2
        demo_step = 0
      end
    elseif demo_room == 2 then
      if demo_step <= 4 then
        wire_cursor = wire_pairs[demo_step]
        wire_current = demo_step + 1
        sfx_door()
      elseif demo_step == 5 then
        rooms_solved[2] = true
        sfx_success()
        demo_room = 3
        demo_step = 0
      end
    elseif demo_room == 3 then
      if demo_step <= 3 then
        code_input[demo_step] = code_target[demo_step]
        code_cursor = demo_step
        sfx_select()
      elseif demo_step == 4 then
        rooms_solved[3] = true
        sfx_success()
      end
    end
  end

  -- Any button exits demo
  if btnp("start") or btnp("a") or btnp("b") or btnp("up") or btnp("down") or btnp("left") or btnp("right") then
    state = "title"
    idle_timer = 0
    title_blink = 0
    title_reveal = 0
    return
  end

  local all_done = rooms_solved[1] and rooms_solved[2] and rooms_solved[3]
  if demo_timer > DEMO_DURATION or all_done then
    state = "title"
    idle_timer = 0
    title_blink = 0
    title_reveal = 0
  end
end

local function attract_draw()
  local s = screen()
  cls(s, BLACK)

  text(s, "DEMO", 2, 2, DARK)

  room = demo_room
  draw_timer_bar(s)
  draw_room_indicator(s)

  if demo_room == 1 then draw_lock(s)
  elseif demo_room == 2 then draw_wire(s)
  elseif demo_room == 3 then draw_code(s)
  end

  -- Horror effects in demo
  local urgency = 1.0 - (timer / TOTAL_TIME)
  draw_vignette(s, urgency * 0.5)
  draw_entity_eyes(s)
  draw_tendrils(s)

  if math.floor(demo_timer / 25) % 2 == 0 then
    text_center(s, "PRESS START", 112, LIGHT)
  end
end

---------- MAIN CALLBACKS ----------
function _init()
  mode(2)
end

function _start()
  state = "title"
  idle_timer = 0
  title_blink = 0
  title_reveal = 0
  result_timer = 0
  result_blink = 0
  entity_eyes = {}
  darkness_tendrils = {}
  scare_timer = 200
  amb_drip_timer = 40
  amb_creak_timer = 60
end

function _update()
  if state == "title" then
    title_update()
  elseif state == "game" then
    game_update()
  elseif state == "win" then
    win_update()
  elseif state == "lose" then
    lose_update()
  elseif state == "attract" then
    attract_update()
  end
end

function _draw()
  if state == "title" then
    title_draw()
  elseif state == "game" then
    game_draw()
  elseif state == "win" then
    win_draw()
  elseif state == "lose" then
    lose_draw()
  elseif state == "attract" then
    attract_draw()
  end
end
