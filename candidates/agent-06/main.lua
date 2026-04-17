-- THE DARK ROOM: TIME PRESSURE
-- Something is coming. Solve puzzles. Escape before time runs out.
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
local TOTAL_TIME = 90 * 30  -- 90 seconds at 30fps
local WARN_TIME = 30 * 30   -- last 30 seconds = warning
local CRIT_TIME = 10 * 30   -- last 10 seconds = critical

-- Demo
local IDLE_TIMEOUT = 150     -- 5 seconds to demo
local DEMO_DURATION = 600    -- 20 seconds of demo

-- Puzzle types
local PUZZLE_LOCK = 1    -- pattern lock: match the sequence
local PUZZLE_WIRE = 2    -- wire sequence: connect pairs
local PUZZLE_CODE = 3    -- code cipher: decode the number

---------- UTILITY ----------
local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function text_center(s, str, y, c)
  text(s, str, W / 2, y, c, ALIGN_HCENTER)
end

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

---------- STATE ----------
local state            -- "title","game","win","lose","attract"
local idle_timer = 0
local demo_timer = 0
local demo_step = 0
local demo_room = 0

-- Game state
local timer = 0        -- countdown in frames
local room = 1         -- current room 1-3
local rooms_solved = {false, false, false}
local flash_timer = 0
local pulse_phase = 0
local shake_x = 0
local shake_y = 0
local shake_timer = 0
local transition_timer = 0
local transition_dir = 0  -- 1=entering, -1=leaving
local msg = ""
local msg_timer = 0
local paused = false

-- Pattern lock puzzle (room 1): match a 4-symbol sequence
local lock_target = {}
local lock_input = {}
local lock_cursor = 0
local lock_symbols = {"^", "v", "<", ">"}

-- Wire puzzle (room 2): connect 4 wire pairs in order
local wire_pairs = {}
local wire_current = 0
local wire_cursor = 1
local wire_flash = 0

-- Code puzzle (room 3): decode a 3-digit number
local code_target = {}
local code_input = {0, 0, 0}
local code_cursor = 1
local code_hints = {}

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
  -- 4 pairs: each pair is a left-index -> right-index mapping
  local right = {1, 2, 3, 4}
  -- shuffle right side
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
  -- Generate hints: show offset hints
  for i = 1, 3 do
    local offset = math.random(1, 3)
    code_hints[i] = (code_target[i] + offset) % 10
    -- hint text: "digit X is Y more than shown"
  end
end

---------- VIGNETTE / ATMOSPHERE ----------
local function draw_vignette(s, intensity)
  -- intensity 0.0 to 1.0: how much darkness encroaches
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
  -- Screen edge pulse effect
  if intensity < 0.1 then return end
  local alpha = math.floor(intensity * 3)
  local c = clamp(alpha, 0, 2)
  -- Pulsing border rectangle
  local phase = math.sin(pulse_phase * 0.15) * 0.5 + 0.5
  if phase > 0.5 then
    rect(s, 0, 0, W - 1, H - 1, c)
    rect(s, 1, 1, W - 2, H - 2, c)
  end
end

---------- TITLE SCREEN ----------
local title_blink = 0

local function title_update()
  title_blink = title_blink + 1
  idle_timer = idle_timer + 1

  if btnp("start") or btnp("a") then
    -- Start game
    state = "game"
    timer = TOTAL_TIME
    room = 1
    rooms_solved = {false, false, false}
    flash_timer = 0
    pulse_phase = 0
    paused = false
    msg = ""
    msg_timer = 0
    gen_lock()
    gen_wire()
    gen_code()
    idle_timer = 0
    sfx_door()
    transition_timer = 15
    transition_dir = 1
    return
  end

  -- Enter demo mode after idle
  if idle_timer > IDLE_TIMEOUT then
    state = "attract"
    demo_timer = 0
    demo_step = 0
    demo_room = 1
    timer = TOTAL_TIME
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

  -- Title
  text_center(s, "THE DARK ROOM", 20, WHITE)
  text_center(s, "TIME PRESSURE", 32, LIGHT)

  -- Decorative line
  line(s, 30, 42, 130, 42, DARK)

  -- Subtitle
  text_center(s, "Something is coming.", 50, DARK)
  text_center(s, "Escape before time runs out.", 60, DARK)

  -- Blink prompt
  if math.floor(title_blink / 20) % 2 == 0 then
    text_center(s, "PRESS START", 80, WHITE)
  end

  -- Controls
  text_center(s, "D-PAD:Select  A:Confirm", 100, DARK)
  text_center(s, "START:Begin  SELECT:Pause", 110, DARK)
end

---------- GAME UPDATE ----------
local function update_lock()
  if rooms_solved[1] then return end

  if btnp("up") then
    lock_input[#lock_input + 1] = 1
    sfx_select()
  elseif btnp("down") then
    lock_input[#lock_input + 1] = 2
    sfx_select()
  elseif btnp("left") then
    lock_input[#lock_input + 1] = 3
    sfx_select()
  elseif btnp("right") then
    lock_input[#lock_input + 1] = 4
    sfx_select()
  end

  if btnp("b") and #lock_input > 0 then
    -- Undo last input
    table.remove(lock_input)
    noise(0, 0.03)
  end

  -- Check when 4 inputs entered
  if #lock_input >= 4 then
    local correct = true
    for i = 1, 4 do
      if lock_input[i] ~= lock_target[i] then
        correct = false
        break
      end
    end
    if correct then
      rooms_solved[1] = true
      sfx_success()
      msg = "LOCK OPENED!"
      msg_timer = 45
      flash_timer = 10
    else
      sfx_fail()
      lock_input = {}
      msg = "WRONG SEQUENCE"
      msg_timer = 30
      shake_timer = 8
      shake_x = 0
      shake_y = 0
      -- Time penalty
      timer = timer - 90  -- 3 second penalty
    end
  end
end

local function update_wire()
  if rooms_solved[2] then return end

  if btnp("up") then
    wire_cursor = clamp(wire_cursor - 1, 1, 4)
    sfx_select()
  elseif btnp("down") then
    wire_cursor = clamp(wire_cursor + 1, 1, 4)
    sfx_select()
  end

  if btnp("a") then
    -- Check if this right-side index matches current pair
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
      sfx_fail()
      msg = "WRONG WIRE"
      msg_timer = 30
      shake_timer = 8
      timer = timer - 90  -- 3 second penalty
    end
  end
end

local function update_code()
  if rooms_solved[3] then return end

  if btnp("left") then
    code_cursor = clamp(code_cursor - 1, 1, 3)
    sfx_select()
  elseif btnp("right") then
    code_cursor = clamp(code_cursor + 1, 1, 3)
    sfx_select()
  end

  if btnp("up") then
    code_input[code_cursor] = (code_input[code_cursor] + 1) % 10
    sfx_select()
  elseif btnp("down") then
    code_input[code_cursor] = (code_input[code_cursor] - 1) % 10
    sfx_select()
  end

  if btnp("a") then
    local correct = true
    for i = 1, 3 do
      if code_input[i] ~= code_target[i] then
        correct = false
        break
      end
    end
    if correct then
      rooms_solved[3] = true
      sfx_success()
      msg = "CODE CRACKED!"
      msg_timer = 45
      flash_timer = 10
    else
      sfx_fail()
      msg = "WRONG CODE"
      msg_timer = 30
      shake_timer = 8
      timer = timer - 90
    end
  end
end

local function game_update()
  if paused then
    if btnp("select") or btnp("start") then
      paused = false
    end
    return
  end

  if btnp("select") then
    paused = true
    return
  end

  -- Transition animation
  if transition_timer > 0 then
    transition_timer = transition_timer - 1
    return
  end

  -- Countdown
  timer = timer - 1
  pulse_phase = pulse_phase + 1

  -- Time-based sounds
  if timer > WARN_TIME then
    -- Normal ticking every second
    if timer % 30 == 0 then sfx_tick(2) end
  elseif timer > CRIT_TIME then
    -- Warning: tick every half second
    if timer % 15 == 0 then sfx_warn() end
  else
    -- Critical: rapid ticking + heartbeat
    if timer % 8 == 0 then sfx_crit() end
    if timer % 20 == 0 then sfx_heartbeat() end
  end

  -- Time up = lose
  if timer <= 0 then
    timer = 0
    state = "lose"
    result_timer = 0
    result_blink = 0
    sfx_fail()
    return
  end

  -- Screen shake update
  if shake_timer > 0 then
    shake_timer = shake_timer - 1
    shake_x = math.random(-2, 2)
    shake_y = math.random(-1, 1)
  else
    shake_x = 0
    shake_y = 0
  end

  -- Flash update
  if flash_timer > 0 then
    flash_timer = flash_timer - 1
  end

  -- Message update
  if msg_timer > 0 then
    msg_timer = msg_timer - 1
  end

  -- Room switching with shoulder buttons or after solving
  local all_solved = rooms_solved[1] and rooms_solved[2] and rooms_solved[3]
  if all_solved then
    state = "win"
    result_timer = 0
    result_blink = 0
    sfx_success()
    sfx_door()
    return
  end

  -- Navigate between rooms (only unsolved ones matter)
  if btnp("start") then
    -- Cycle to next room
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
  if room == 1 then
    update_lock()
  elseif room == 2 then
    update_wire()
  elseif room == 3 then
    update_code()
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
local function draw_timer(s)
  local secs = math.ceil(timer / 30)
  local mins = math.floor(secs / 60)
  secs = secs % 60
  local time_str = string.format("%d:%02d", mins, secs)

  -- Timer color based on urgency
  local c = WHITE
  if timer < CRIT_TIME then
    -- Flash between white and dark in critical
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
  -- Room 1: Pattern Lock
  text_center(s, "PATTERN LOCK", 22, LIGHT)

  -- Show target sequence
  text(s, "MATCH:", 10, 34, DARK)
  for i = 1, 4 do
    local sym = lock_symbols[lock_target[i]]
    text(s, sym, 46 + (i - 1) * 14, 34, WHITE)
  end

  -- Show current input
  text(s, "INPUT:", 10, 50, DARK)
  for i = 1, #lock_input do
    local sym = lock_symbols[lock_input[i]]
    text(s, sym, 46 + (i - 1) * 14, 50, LIGHT)
  end
  -- Show cursor position
  if #lock_input < 4 then
    local cx = 46 + #lock_input * 14
    if math.floor(pulse_phase / 10) % 2 == 0 then
      text(s, "_", cx, 50, WHITE)
    end
  end

  -- Instructions
  text_center(s, "D-PAD: Enter direction", 70, DARK)
  text_center(s, "B: Undo", 80, DARK)

  -- Draw directional hint
  local dx, dy = 80, 98
  text(s, "^", dx, dy - 8, LIGHT, ALIGN_HCENTER)
  text(s, "v", dx, dy + 4, LIGHT, ALIGN_HCENTER)
  text(s, "<", dx - 10, dy - 2, LIGHT, ALIGN_HCENTER)
  text(s, ">", dx + 10, dy - 2, LIGHT, ALIGN_HCENTER)
end

local function draw_wire(s)
  -- Room 2: Wire Sequence
  text_center(s, "WIRE CONNECT", 22, LIGHT)

  local lx = 30
  local rx = 120
  local base_y = 38

  -- Draw left terminals (numbered 1-4)
  for i = 1, 4 do
    local y = base_y + (i - 1) * 16
    local c = (i < wire_current) and DARK or WHITE
    if i == wire_current then c = WHITE end
    rectf(s, lx - 4, y - 3, lx + 4, y + 3, DARK)
    rect(s, lx - 4, y - 3, lx + 4, y + 3, c)
    text(s, tostring(i), lx, y - 2, c, ALIGN_HCENTER)
  end

  -- Draw right terminals
  for i = 1, 4 do
    local y = base_y + (i - 1) * 16
    local c = (i == wire_cursor) and WHITE or LIGHT
    -- Highlight if already connected
    local connected = false
    for j = 1, wire_current - 1 do
      if wire_pairs[j] == i then connected = true break end
    end
    if connected then c = DARK end

    rectf(s, rx - 4, y - 3, rx + 4, y + 3, DARK)
    rect(s, rx - 4, y - 3, rx + 4, y + 3, c)

    local labels = {"A", "B", "C", "D"}
    text(s, labels[i], rx, y - 2, c, ALIGN_HCENTER)

    -- Cursor arrow
    if i == wire_cursor and wire_current <= 4 then
      text(s, ">", rx - 14, y - 2, WHITE)
    end
  end

  -- Draw completed connections
  for i = 1, wire_current - 1 do
    local ly = base_y + (i - 1) * 16
    local ry = base_y + (wire_pairs[i] - 1) * 16
    line(s, lx + 6, ly, rx - 6, ry, LIGHT)
  end

  -- Current connection line (blinking)
  if wire_current <= 4 and math.floor(pulse_phase / 8) % 2 == 0 then
    local ly = base_y + (wire_current - 1) * 16
    local ry = base_y + (wire_cursor - 1) * 16
    line(s, lx + 6, ly, rx - 6, ry, DARK)
  end

  text_center(s, "UP/DN:Select  A:Connect", 108, DARK)
end

local function draw_code(s)
  -- Room 3: Code Cipher
  text_center(s, "CODE CIPHER", 22, LIGHT)

  -- Show hint numbers
  text_center(s, "CLUE:", 36, DARK)
  for i = 1, 3 do
    local x = 55 + (i - 1) * 24
    text(s, tostring(code_hints[i]), x, 36, LIGHT, ALIGN_HCENTER)
  end

  -- Show offset hint
  text_center(s, "Each digit is offset by", 48, DARK)
  text_center(s, "1 to 3 from the clue above", 56, DARK)

  -- Digit entry
  for i = 1, 3 do
    local x = 55 + (i - 1) * 24
    local y = 72
    local c = (i == code_cursor) and WHITE or LIGHT

    -- Up arrow
    if i == code_cursor then
      text(s, "^", x, y - 10, WHITE, ALIGN_HCENTER)
    end

    -- Digit box
    rect(s, x - 8, y - 4, x + 8, y + 7, c)
    text(s, tostring(code_input[i]), x, y - 2, c, ALIGN_HCENTER)

    -- Down arrow
    if i == code_cursor then
      text(s, "v", x, y + 10, WHITE, ALIGN_HCENTER)
    end
  end

  -- Cursor indicator
  local cx = 55 + (code_cursor - 1) * 24
  rectf(s, cx - 6, 92, cx + 6, 93, WHITE)

  text_center(s, "L/R:Digit UP/DN:Value A:Submit", 102, DARK)
end

local function game_draw()
  local s = screen()

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
    draw_timer(s)
    return
  end

  -- Paused overlay
  if paused then
    cls(s, BLACK)
    text_center(s, "PAUSED", 50, WHITE)
    text_center(s, "SELECT to resume", 65, LIGHT)
    draw_timer(s)
    return
  end

  -- Draw timer and room indicators
  draw_timer(s)
  draw_room_indicator(s)

  -- Draw current room puzzle
  if room == 1 then
    draw_lock(s)
  elseif room == 2 then
    draw_wire(s)
  elseif room == 3 then
    draw_code(s)
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

  -- Atmospheric effects based on time remaining
  local urgency = 1.0 - (timer / TOTAL_TIME)
  draw_vignette(s, urgency * 0.8)
  draw_pulse(s, urgency)

  -- Critical time: random scanlines
  if timer < CRIT_TIME then
    for i = 1, 3 do
      local y = math.random(0, H - 1)
      line(s, 0, y, W - 1, y, DARK)
    end
  end

  -- Apply screen shake offset (draw a shifted border)
  if shake_timer > 0 then
    -- Draw black edges to simulate shake
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
  end
end

local function win_draw()
  local s = screen()
  cls(s, BLACK)

  -- Triumphant reveal
  if result_timer < 15 then
    -- Flash
    if result_timer % 3 == 0 then cls(s, WHITE) end
    return
  end

  text_center(s, "ESCAPED!", 30, WHITE)

  local secs_left = math.ceil(timer / 30)
  text_center(s, "Time remaining: " .. secs_left .. "s", 48, LIGHT)

  -- Rating
  local rating = "CLOSE CALL"
  if secs_left > 60 then rating = "MASTERMIND" end
  if secs_left > 30 then rating = "QUICK THINKER" end
  text_center(s, rating, 64, WHITE)

  if result_timer > 60 and math.floor(result_blink / 20) % 2 == 0 then
    text_center(s, "PRESS START", 90, LIGHT)
  end
end

local function lose_update()
  result_timer = result_timer + 1
  result_blink = result_blink + 1

  -- Ominous sounds
  if result_timer == 10 then
    noise(0, 0.4)
    note(1, "C2", 0.5)
  end
  if result_timer == 40 then
    noise(1, 0.3)
    note(2, "A1", 0.5)
  end

  if result_timer > 90 and (btnp("start") or btnp("a")) then
    state = "title"
    idle_timer = 0
    title_blink = 0
  end
end

local function lose_draw()
  local s = screen()
  cls(s, BLACK)

  if result_timer < 30 then
    -- Darkness creeping in
    local progress = result_timer / 30
    draw_vignette(s, progress)
    -- Fading text
    if result_timer > 10 then
      text_center(s, "TOO LATE", 55, DARK)
    end
    return
  end

  -- Random glitch lines
  if math.random() < 0.1 then
    local y = math.random(0, H - 1)
    line(s, 0, y, W - 1, y, DARK)
  end

  text_center(s, "TOO LATE", 35, WHITE)
  text_center(s, "It found you.", 50, LIGHT)
  text_center(s, "The darkness consumed", 65, DARK)
  text_center(s, "everything.", 75, DARK)

  -- Rooms solved count
  local solved = 0
  for i = 1, 3 do if rooms_solved[i] then solved = solved + 1 end end
  text_center(s, "Rooms escaped: " .. solved .. "/3", 90, LIGHT)

  if result_timer > 90 and math.floor(result_blink / 20) % 2 == 0 then
    text_center(s, "PRESS START", 108, DARK)
  end
end

---------- DEMO / ATTRACT MODE ----------
local demo_input_timer = 0

local function attract_update()
  demo_timer = demo_timer + 1
  pulse_phase = pulse_phase + 1
  timer = timer - 1
  if timer < 0 then timer = 0 end

  -- Auto-solve puzzles for demo
  demo_input_timer = demo_input_timer + 1
  if demo_input_timer >= 15 then
    demo_input_timer = 0
    demo_step = demo_step + 1

    if demo_room == 1 then
      -- Auto-enter lock pattern
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
      -- Auto-connect wires
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
      -- Auto-enter code
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
    return
  end

  -- End demo after duration or all solved
  local all_done = rooms_solved[1] and rooms_solved[2] and rooms_solved[3]
  if demo_timer > DEMO_DURATION or all_done then
    state = "title"
    idle_timer = 0
    title_blink = 0
  end
end

local function attract_draw()
  local s = screen()
  cls(s, BLACK)

  -- Show DEMO banner
  text(s, "DEMO", 2, 2, DARK)

  -- Draw current demo room
  room = demo_room
  draw_timer(s)
  draw_room_indicator(s)

  if demo_room == 1 then
    draw_lock(s)
  elseif demo_room == 2 then
    draw_wire(s)
  elseif demo_room == 3 then
    draw_code(s)
  end

  -- Vignette
  local urgency = 1.0 - (timer / TOTAL_TIME)
  draw_vignette(s, urgency * 0.5)

  -- "Press START" overlay
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
  result_timer = 0
  result_blink = 0
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
