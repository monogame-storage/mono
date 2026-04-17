-- THE DARK ROOM: PRESSURE PROTOCOL
-- Agent 20 = Agent 06 (time pressure) + Agent 07 (multiple endings)
-- Time pressure with consequences: HOW you escape matters.
-- 160x120 | 2-bit (0-3) | mode(2) | 30fps

---------- CONSTANTS ----------
local W = 160
local H = 120

local BLACK = 0
local DARK  = 1
local LIGHT = 2
local WHITE = 3

-- Timing
local TOTAL_TIME = 90 * 30   -- 90 seconds at 30fps
local WARN_TIME  = 30 * 30   -- last 30s = warning
local CRIT_TIME  = 10 * 30   -- last 10s = critical

-- Demo
local IDLE_TIMEOUT  = 150     -- 5s idle -> demo
local DEMO_DURATION = 600     -- 20s demo

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

local function text_center(s, str, y, c)
  text(s, str, W / 2, y, c, ALIGN_HCENTER)
end

---------- SOUND ----------
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

local function sfx_discover()
  note(0, "E5", 0.08)
  note(1, "G5", 0.1)
end

local function sfx_danger()
  note(0, "C2", 0.15)
  noise(1, 0.1)
end

local function sfx_broadcast()
  note(0, "C5", 0.15)
  note(1, "E5", 0.15)
  note(2, "G5", 0.2)
end

---------- STATE ----------
local state            -- "title","game","ending_escape","ending_truth","ending_trapped","attract"
local idle_timer = 0
local demo_timer = 0
local demo_step = 0
local demo_room = 0
local tick = 0

-- Game state
local timer = 0
local room = 1         -- 1=Lab, 2=Office, 3=Vault
local rooms_solved = {false, false, false}
local flash_timer = 0
local pulse_phase = 0
local shake_x = 0
local shake_y = 0
local shake_timer = 0
local transition_timer = 0
local transition_dir = 0
local msg = ""
local msg_timer = 0
local paused = false

-- Evidence flags (from agent-07 branching)
local evidence = {
  lab_notes = false,     -- found in room 1 (Lab) via search
  classified = false,    -- found in room 2 (Office) via search
  broadcast_key = false, -- found in room 3 (Vault) via search
}
local evidence_count = 0
local search_mode = false  -- true when B is held to search instead of solve

-- Room names for display
local room_names = {"LABORATORY", "OFFICE", "VAULT"}
local room_evidence_names = {"Lab Notes", "Classified Files", "Broadcast Key"}

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

-- Evidence search state per room
local search_progress = {0, 0, 0}  -- 0-3 search steps needed
local search_target = 3             -- need 3 searches to find evidence
local searching_anim = 0

-- Result screen
local result_timer = 0
local result_blink = 0

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

local function count_evidence()
  local c = 0
  if evidence.lab_notes then c = c + 1 end
  if evidence.classified then c = c + 1 end
  if evidence.broadcast_key then c = c + 1 end
  evidence_count = c
  return c
end

---------- VIGNETTE / ATMOSPHERE ----------
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

---------- TITLE SCREEN ----------
local title_blink = 0

local function title_update()
  title_blink = title_blink + 1
  idle_timer = idle_timer + 1

  if btnp("start") or btnp("a") then
    state = "game"
    timer = TOTAL_TIME
    room = 1
    rooms_solved = {false, false, false}
    evidence = {lab_notes = false, classified = false, broadcast_key = false}
    evidence_count = 0
    search_progress = {0, 0, 0}
    search_mode = false
    searching_anim = 0
    flash_timer = 0
    pulse_phase = 0
    paused = false
    msg = "You wake in a locked facility."
    msg_timer = 60
    gen_lock()
    gen_wire()
    gen_code()
    idle_timer = 0
    sfx_door()
    transition_timer = 15
    transition_dir = 1
    return
  end

  if idle_timer > IDLE_TIMEOUT then
    state = "attract"
    demo_timer = 0
    demo_step = 0
    demo_room = 1
    timer = TOTAL_TIME
    rooms_solved = {false, false, false}
    evidence = {lab_notes = false, classified = false, broadcast_key = false}
    evidence_count = 0
    search_progress = {0, 0, 0}
    gen_lock()
    gen_wire()
    gen_code()
  end
end

local function title_draw()
  local s = screen()
  cls(s, BLACK)

  if math.random() < 0.03 then
    cls(s, DARK)
  end

  text_center(s, "THE DARK ROOM", 15, WHITE)
  text_center(s, "PRESSURE PROTOCOL", 27, LIGHT)

  line(s, 30, 37, 130, 37, DARK)

  text_center(s, "90 seconds. 3 rooms.", 44, DARK)
  text_center(s, "Escape is not enough.", 54, LIGHT)
  text_center(s, "The truth costs time.", 64, DARK)

  if math.floor(title_blink / 20) % 2 == 0 then
    text_center(s, "PRESS START", 80, WHITE)
  end

  text_center(s, "D-PAD:Solve  A:Confirm  B:Search", 98, DARK)
  text_center(s, "START:Next Room  SELECT:Pause", 108, DARK)
end

---------- SEARCH MECHANIC ----------
-- B button: spend time searching for evidence instead of solving puzzles
local function update_search()
  if not search_mode then return end

  -- Searching takes time but finds evidence
  searching_anim = searching_anim + 1

  if searching_anim >= 20 then
    searching_anim = 0
    search_progress[room] = search_progress[room] + 1

    if search_progress[room] >= search_target then
      -- Found evidence in this room
      if room == 1 and not evidence.lab_notes then
        evidence.lab_notes = true
        msg = "FOUND: Lab Notes!"
        msg_timer = 40
        sfx_discover()
      elseif room == 2 and not evidence.classified then
        evidence.classified = true
        msg = "FOUND: Classified Files!"
        msg_timer = 40
        sfx_discover()
      elseif room == 3 and not evidence.broadcast_key then
        evidence.broadcast_key = true
        msg = "FOUND: Broadcast Key!"
        msg_timer = 40
        sfx_discover()
      end
      count_evidence()
      search_mode = false
    else
      -- Partial progress
      local remaining = search_target - search_progress[room]
      msg = "Searching... (" .. remaining .. " more)"
      msg_timer = 15
      noise(0, 0.02)
    end
  end
end

---------- GAME UPDATE: PUZZLES ----------
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

  if btnp("a") and #lock_input > 0 then
    -- Submit early check with partial (undo last on wrong)
  end

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
      msg = "LAB UNLOCKED!"
      msg_timer = 40
      flash_timer = 10
    else
      sfx_fail()
      lock_input = {}
      msg = "WRONG SEQUENCE"
      msg_timer = 25
      shake_timer = 8
      timer = timer - 90
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
    if wire_pairs[wire_current] == wire_cursor then
      wire_current = wire_current + 1
      sfx_door()
      wire_flash = 8
      if wire_current > 4 then
        rooms_solved[2] = true
        sfx_success()
        msg = "OFFICE CRACKED!"
        msg_timer = 40
        flash_timer = 10
      end
    else
      sfx_fail()
      msg = "WRONG WIRE"
      msg_timer = 25
      shake_timer = 8
      timer = timer - 90
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
      msg = "VAULT OPEN!"
      msg_timer = 40
      flash_timer = 10
    else
      sfx_fail()
      msg = "WRONG CODE"
      msg_timer = 25
      shake_timer = 8
      timer = timer - 90
    end
  end
end

---------- DETERMINE ENDING ----------
local function check_ending()
  local all_solved = rooms_solved[1] and rooms_solved[2] and rooms_solved[3]
  if not all_solved then return false end

  count_evidence()
  result_timer = 0
  result_blink = 0

  if evidence_count >= 3 then
    -- TRUE ENDING: found all evidence AND solved all puzzles
    state = "ending_truth"
    sfx_broadcast()
  else
    -- QUICK ESCAPE: solved puzzles but missed evidence
    state = "ending_escape"
    sfx_door()
  end
  return true
end

---------- GAME UPDATE ----------
local function game_update()
  tick = tick + 1

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

  if transition_timer > 0 then
    transition_timer = transition_timer - 1
    return
  end

  -- Countdown
  timer = timer - 1
  pulse_phase = pulse_phase + 1

  -- Time sounds
  if timer > WARN_TIME then
    if timer % 30 == 0 then sfx_tick(2) end
  elseif timer > CRIT_TIME then
    if timer % 15 == 0 then sfx_warn() end
  else
    if timer % 8 == 0 then sfx_crit() end
    if timer % 20 == 0 then sfx_heartbeat() end
  end

  -- TRAPPED ending: time ran out
  if timer <= 0 then
    timer = 0
    state = "ending_trapped"
    result_timer = 0
    result_blink = 0
    sfx_fail()
    return
  end

  -- Screen shake
  if shake_timer > 0 then
    shake_timer = shake_timer - 1
    shake_x = math.random(-2, 2)
    shake_y = math.random(-1, 1)
  else
    shake_x = 0
    shake_y = 0
  end

  if flash_timer > 0 then flash_timer = flash_timer - 1 end
  if msg_timer > 0 then msg_timer = msg_timer - 1 end

  -- Check win condition
  if check_ending() then return end

  -- B button: toggle search mode (costs time to find evidence)
  if btnp("b") then
    if search_mode then
      search_mode = false
      msg = "Back to puzzle."
      msg_timer = 20
    else
      -- Check if evidence already found in this room
      local found = (room == 1 and evidence.lab_notes) or
                    (room == 2 and evidence.classified) or
                    (room == 3 and evidence.broadcast_key)
      if found then
        msg = "Evidence already secured."
        msg_timer = 25
      elseif rooms_solved[room] then
        -- Can search after solving
        search_mode = true
        searching_anim = 0
        msg = "Searching for evidence..."
        msg_timer = 20
        sfx_danger()
      else
        -- Can search even before solving, but risky
        search_mode = true
        searching_anim = 0
        msg = "Searching... clock ticking!"
        msg_timer = 20
        sfx_danger()
      end
    end
  end

  -- Update search if active
  if search_mode then
    update_search()
    return  -- can't solve puzzle while searching
  end

  -- Navigate rooms
  if btnp("start") then
    local next_room = room % 3 + 1
    for i = 1, 3 do
      if not rooms_solved[next_room] then break end
      -- If solved, still allow visiting (for evidence search)
      break
    end
    if next_room ~= room then
      room = next_room
      search_mode = false
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

local function draw_evidence_bar(s)
  -- Show evidence count top-right
  local ev_str = "EVD:" .. evidence_count .. "/3"
  local c = evidence_count >= 3 and WHITE or LIGHT
  text(s, ev_str, W - 2, 2, c, ALIGN_RIGHT)
end

local function draw_room_indicator(s)
  for i = 1, 3 do
    local x = W / 2 - 20 + (i - 1) * 16
    local y = 11

    -- Evidence dot above room indicator
    local has_ev = (i == 1 and evidence.lab_notes) or
                   (i == 2 and evidence.classified) or
                   (i == 3 and evidence.broadcast_key)

    if rooms_solved[i] then
      rect(s, x, y, x + 10, y + 5, LIGHT)
      rectf(s, x + 1, y + 1, x + 9, y + 4, DARK)
      text(s, "OK", x + 5, y + 1, WHITE, ALIGN_HCENTER)
    elseif i == room then
      rect(s, x, y, x + 10, y + 5, WHITE)
      text(s, tostring(i), x + 5, y + 1, WHITE, ALIGN_HCENTER)
    else
      rect(s, x, y, x + 10, y + 5, DARK)
      text(s, tostring(i), x + 5, y + 1, DARK, ALIGN_HCENTER)
    end

    if has_ev then
      pix(s, x + 5, y - 2, WHITE)
    end
  end
end

local function draw_lock(s)
  text_center(s, "PATTERN LOCK", 22, LIGHT)
  text(s, "MATCH:", 10, 36, DARK)
  for i = 1, 4 do
    text(s, lock_symbols[lock_target[i]], 46 + (i - 1) * 14, 36, WHITE)
  end
  text(s, "INPUT:", 10, 52, DARK)
  for i = 1, #lock_input do
    text(s, lock_symbols[lock_input[i]], 46 + (i - 1) * 14, 52, LIGHT)
  end
  if #lock_input < 4 then
    if math.floor(pulse_phase / 10) % 2 == 0 then
      text(s, "_", 46 + #lock_input * 14, 52, WHITE)
    end
  end
  text_center(s, "D-PAD: Enter direction", 70, DARK)
  local dx, dy = 80, 88
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
      if wire_pairs[j] == i then connected = true break end
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

  text_center(s, "UP/DN:Select  A:Connect", 104, DARK)
end

local function draw_code(s)
  text_center(s, "CODE CIPHER", 22, LIGHT)
  text_center(s, "CLUE:", 36, DARK)
  for i = 1, 3 do
    local x = 55 + (i - 1) * 24
    text(s, tostring(code_hints[i]), x, 36, LIGHT, ALIGN_HCENTER)
  end
  text_center(s, "Each digit offset 1-3", 48, DARK)

  for i = 1, 3 do
    local x = 55 + (i - 1) * 24
    local y = 64
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
  rectf(s, cx - 6, 84, cx + 6, 85, WHITE)
  text_center(s, "L/R:Digit UP/DN:Value A:Submit", 92, DARK)
end

local function draw_search_overlay(s)
  if not search_mode then return end

  -- Searching animation: scanning lines
  local scan_y = (searching_anim * 6) % 60 + 20
  line(s, 10, scan_y, W - 10, scan_y, LIGHT)
  line(s, 10, scan_y + 1, W - 10, scan_y + 1, DARK)

  -- Progress bar
  local prog = search_progress[room] / search_target
  local bar_w = 80
  local bar_x = W / 2 - bar_w / 2
  local bar_y = 100
  rect(s, bar_x, bar_y, bar_x + bar_w, bar_y + 5, LIGHT)
  rectf(s, bar_x + 1, bar_y + 1, bar_x + 1 + math.floor(prog * (bar_w - 2)), bar_y + 4, WHITE)

  text_center(s, "SEARCHING...", 92, WHITE)
  text_center(s, "B: Cancel", 108, DARK)
end

local function game_draw()
  local s = screen()

  if flash_timer > 0 and flash_timer % 2 == 0 then
    cls(s, WHITE)
  else
    cls(s, BLACK)
  end

  if transition_timer > 0 then
    cls(s, BLACK)
    local progress = transition_timer / 15
    local bar_h = math.floor(progress * H / 2)
    rectf(s, 0, 0, W - 1, bar_h, BLACK)
    rectf(s, 0, H - 1 - bar_h, W - 1, H - 1, BLACK)
    draw_timer_bar(s)
    return
  end

  if paused then
    cls(s, BLACK)
    text_center(s, "PAUSED", 40, WHITE)
    text_center(s, "SELECT to resume", 55, LIGHT)
    text_center(s, "Evidence: " .. evidence_count .. "/3", 70, LIGHT)
    local solved = 0
    for i = 1, 3 do if rooms_solved[i] then solved = solved + 1 end end
    text_center(s, "Puzzles: " .. solved .. "/3", 80, LIGHT)
    draw_timer_bar(s)
    return
  end

  -- Draw HUD
  draw_timer_bar(s)
  draw_evidence_bar(s)
  draw_room_indicator(s)

  -- Room name
  text(s, room_names[room], 2, 2, DARK)

  -- Draw puzzle or solved indicator
  if search_mode then
    -- Show room art hint while searching
    text_center(s, room_names[room], 30, LIGHT)
    text_center(s, "Investigating...", 45, DARK)

    -- Draw searching evidence flavor text
    if room == 1 then
      text_center(s, "Checking lab equipment...", 58, DARK)
    elseif room == 2 then
      text_center(s, "Rifling through files...", 58, DARK)
    elseif room == 3 then
      text_center(s, "Scanning terminal data...", 58, DARK)
    end

    draw_search_overlay(s)
  elseif rooms_solved[room] then
    text_center(s, room_names[room] .. " SOLVED", 40, LIGHT)
    -- Show evidence status for this room
    local has_ev = (room == 1 and evidence.lab_notes) or
                   (room == 2 and evidence.classified) or
                   (room == 3 and evidence.broadcast_key)
    if has_ev then
      text_center(s, "Evidence: SECURED", 55, WHITE)
    else
      text_center(s, "Evidence: NOT FOUND", 55, DARK)
      text_center(s, "Press B to search", 68, LIGHT)
    end
  else
    if room == 1 then
      draw_lock(s)
    elseif room == 2 then
      draw_wire(s)
    elseif room == 3 then
      draw_code(s)
    end
  end

  -- Message overlay
  if msg_timer > 0 then
    local my = 112
    rectf(s, 0, my - 2, W - 1, my + 8, BLACK)
    text_center(s, msg, my, WHITE)
  end

  -- Navigation hint
  if msg_timer <= 0 and not search_mode then
    local hint = "START:Room  B:Search"
    text(s, hint, W / 2, 112, DARK, ALIGN_HCENTER)
  end

  -- Atmosphere
  local urgency = 1.0 - (timer / TOTAL_TIME)
  draw_vignette(s, urgency * 0.8)
  draw_pulse(s, urgency)

  if timer < CRIT_TIME then
    for i = 1, 3 do
      local y = math.random(0, H - 1)
      line(s, 0, y, W - 1, y, DARK)
    end
  end

  if shake_timer > 0 then
    if shake_x > 0 then rectf(s, 0, 0, shake_x, H - 1, BLACK) end
    if shake_x < 0 then rectf(s, W + shake_x, 0, W - 1, H - 1, BLACK) end
    if shake_y > 0 then rectf(s, 0, 0, W - 1, shake_y, BLACK) end
    if shake_y < 0 then rectf(s, 0, H + shake_y, W - 1, H - 1, BLACK) end
  end
end

---------- ENDING SCREENS ----------

-- ENDING 1: Quick Escape (bad - missed evidence)
local function ending_escape_update()
  result_timer = result_timer + 1
  result_blink = result_blink + 1
  if result_timer > 90 and (btnp("start") or btnp("a")) then
    state = "title"
    idle_timer = 0
    title_blink = 0
  end
end

local function ending_escape_draw()
  local s = screen()
  cls(s, BLACK)

  if result_timer < 15 then
    if result_timer % 3 == 0 then cls(s, WHITE) end
    return
  end

  -- Dawn gradient
  for i = 0, 20 do
    local c = i < 7 and WHITE or (i < 14 and LIGHT or DARK)
    line(s, 0, 45 + i, W - 1, 45 + i, c)
  end

  text_center(s, "ENDING: ESCAPE", 10, WHITE)
  text_center(s, "You step outside.", 25, LIGHT)

  local secs_left = math.ceil(timer / 30)
  text_center(s, "Time left: " .. secs_left .. "s", 38, LIGHT)

  text_center(s, "Free... but the truth", 72, LIGHT)
  text_center(s, "remains buried inside.", 82, DARK)

  if evidence_count > 0 then
    text_center(s, "Evidence found: " .. evidence_count .. "/3", 92, DARK)
  end

  if result_timer > 90 and math.floor(result_blink / 20) % 2 == 0 then
    text_center(s, "PRESS START", 108, LIGHT)
  end
end

-- ENDING 2: The Truth (true ending - all evidence + all puzzles)
local function ending_truth_update()
  result_timer = result_timer + 1
  result_blink = result_blink + 1

  if result_timer == 30 then
    sfx_broadcast()
  end

  if result_timer > 150 and (btnp("start") or btnp("a")) then
    state = "title"
    idle_timer = 0
    title_blink = 0
  end
end

local function ending_truth_draw()
  local s = screen()
  cls(s, BLACK)

  -- Data stream effect
  for i = 1, 15 do
    local sx = (i * 19 + result_timer * 2) % W
    local sy = (i * 7 + result_timer) % H
    local ch = string.char(48 + (result_timer + i) % 26)
    text(s, ch, sx, sy, DARK)
  end

  if result_timer > 20 then
    rectf(s, 15, 15, W - 30, 70, BLACK)
    rect(s, 15, 15, W - 30, 70, WHITE)

    text_center(s, "ENDING: THE TRUTH", 20, WHITE)
    text_center(s, "Transmission sent.", 34, LIGHT)
    text_center(s, "All evidence broadcast", 44, LIGHT)
    text_center(s, "to every screen in the city.", 54, LIGHT)
    text_center(s, "Project DARK ROOM exposed.", 68, WHITE)
  end

  if result_timer > 60 then
    text_center(s, "You remember everything.", 88, LIGHT)
    text_center(s, "You are free.", 98, WHITE)
  end

  if result_timer > 150 and math.floor(result_blink / 20) % 2 == 0 then
    text_center(s, "PRESS START", 108, WHITE)
  end
end

-- ENDING 3: Trapped (time ran out)
local function ending_trapped_update()
  result_timer = result_timer + 1
  result_blink = result_blink + 1

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

local function ending_trapped_draw()
  local s = screen()
  cls(s, BLACK)

  if result_timer < 30 then
    local progress = result_timer / 30
    draw_vignette(s, progress)
    if result_timer > 10 then
      text_center(s, "TOO LATE", 55, DARK)
    end
    return
  end

  -- Steel door slamming
  local door_y = clamp(result_timer * 2, 0, 60)
  rectf(s, 30, 0, 100, door_y, DARK)
  rect(s, 30, 0, 100, door_y, LIGHT)
  if door_y > 30 then
    for i = 0, 3 do
      rectf(s, 28, 10 + i * 14, 6, 4, WHITE)
      rectf(s, 126, 10 + i * 14, 6, 4, WHITE)
    end
  end

  if math.random() < 0.1 then
    local y = math.random(0, H - 1)
    line(s, 0, y, W - 1, y, DARK)
  end

  text_center(s, "ENDING: TRAPPED", 65, WHITE)
  text_center(s, "The darkness consumed you.", 78, LIGHT)

  local solved = 0
  for i = 1, 3 do if rooms_solved[i] then solved = solved + 1 end end
  text_center(s, "Puzzles: " .. solved .. "/3", 88, DARK)
  text_center(s, "Evidence: " .. evidence_count .. "/3", 96, DARK)

  if result_timer > 90 and math.floor(result_blink / 20) % 2 == 0 then
    text_center(s, "PRESS START", 108, DARK)
  end
end

---------- DEMO / ATTRACT MODE ----------
local demo_input_timer = 0

local function attract_update()
  demo_timer = demo_timer + 1
  tick = tick + 1
  pulse_phase = pulse_phase + 1
  timer = timer - 1
  if timer < 0 then timer = 0 end

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

  if btnp("start") or btnp("a") or btnp("b") or btnp("up") or btnp("down") or btnp("left") or btnp("right") then
    state = "title"
    idle_timer = 0
    title_blink = 0
    return
  end

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

  text(s, "DEMO", 2, 2, DARK)

  room = demo_room
  draw_timer_bar(s)
  draw_room_indicator(s)

  if demo_room == 1 then
    draw_lock(s)
  elseif demo_room == 2 then
    draw_wire(s)
  elseif demo_room == 3 then
    draw_code(s)
  end

  local urgency = 1.0 - (timer / TOTAL_TIME)
  draw_vignette(s, urgency * 0.5)

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
  tick = 0
  result_timer = 0
  result_blink = 0
end

function _update()
  if state == "title" then
    title_update()
  elseif state == "game" then
    game_update()
  elseif state == "ending_escape" then
    ending_escape_update()
  elseif state == "ending_truth" then
    ending_truth_update()
  elseif state == "ending_trapped" then
    ending_trapped_update()
  elseif state == "attract" then
    attract_update()
  end
end

function _draw()
  if state == "title" then
    title_draw()
  elseif state == "game" then
    game_draw()
  elseif state == "ending_escape" then
    ending_escape_draw()
  elseif state == "ending_truth" then
    ending_truth_draw()
  elseif state == "ending_trapped" then
    ending_trapped_draw()
  elseif state == "attract" then
    attract_draw()
  end
end
