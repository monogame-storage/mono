-- SHAKE DICE
-- Shake your phone to roll dice, race around the board!
-- 2-player hot-seat or vs AI

------------------------------------------------------------
-- CONSTANTS
------------------------------------------------------------
local W = 160
local H = 120
local BOARD_SIZE = 20         -- number of squares on the board
local SHAKE_THRESHOLD = 0.5   -- minimum delta magnitude to count as shake
local SHAKE_SUSTAIN = 8       -- frames of shake needed to roll
local DICE_TUMBLE_BASE = 20   -- minimum tumble frames
local DICE_TUMBLE_MAX = 60    -- maximum tumble frames
local AI_PLAYER = 2           -- player 2 is AI by default

------------------------------------------------------------
-- BOARD LAYOUT (positions for each square in screen coords)
------------------------------------------------------------
local board = {}        -- {x, y, event} for each square
local board_path = {}   -- precomputed screen positions

-- Event types: nil=normal, "bonus"=roll again, "skip"=lose turn,
-- "warp+"=jump forward 3, "warp-"=jump back 3, "pts+"=gain 5pts, "pts-"=lose 3pts
local event_map = {}

local function build_board()
  board = {}
  event_map = {}
  -- lay out squares in a snake path
  -- row 0: left to right (squares 1-6)
  -- row 1: right to left (squares 7-12)
  -- row 2: left to right (squares 13-18)
  -- row 3: last 2 squares
  local cols = 6
  local sq_w = 20
  local sq_h = 16
  local ox = 10
  local oy = 28

  for i = 1, BOARD_SIZE do
    local idx = i - 1
    local row = math.floor(idx / cols)
    local col = idx % cols
    -- snake: even rows go right, odd rows go left
    if row % 2 == 1 then
      col = cols - 1 - col
    end
    local x = ox + col * (sq_w + 3)
    local y = oy + row * (sq_h + 3)
    board[i] = {x = x, y = y}
  end

  -- assign events to specific squares
  event_map[3]  = "pts+"
  event_map[5]  = "warp-"
  event_map[7]  = "bonus"
  event_map[9]  = "skip"
  event_map[11] = "pts+"
  event_map[13] = "warp+"
  event_map[15] = "pts-"
  event_map[17] = "bonus"
  event_map[19] = "skip"
end

------------------------------------------------------------
-- GAME STATE
------------------------------------------------------------
local players = {}    -- {pos, score, skip_turn, color, is_ai}
local current_player = 1
local num_players = 2
local vs_ai = true

-- dice state
local dice_value = 0
local dice_rolling = false
local dice_tumble = 0       -- frames remaining in tumble
local dice_display = 1      -- currently shown face during tumble
local dice_settled = false
local dice_result_timer = 0

-- shake detection
local prev_mx, prev_my, prev_mz = 0, 0, 0
local shake_energy = 0
local shake_frames = 0
local has_motion = false

-- turn flow
local turn_phase = "shake"  -- "shake", "rolling", "result", "moving", "event", "done"
local move_anim = 0
local move_from = 0
local move_target = 0
local event_msg = ""
local event_timer = 0
local winner = 0

-- attract / demo
local demo_mode = false
local demo_timer = 0
local DEMO_IDLE = 150

-- AI state
local ai_shake_timer = 0
local ai_shake_dur = 0

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function get_event_label(ev)
  if ev == "bonus" then return "ROLL AGAIN!"
  elseif ev == "skip" then return "SKIP A TURN!"
  elseif ev == "warp+" then return "WARP +3!"
  elseif ev == "warp-" then return "WARP -3!"
  elseif ev == "pts+" then return "+5 POINTS!"
  elseif ev == "pts-" then return "-3 POINTS!"
  end
  return ""
end

local function get_event_color(ev)
  return 1
end

local function get_square_color(i)
  return 1
end

------------------------------------------------------------
-- DICE FACE DRAWING (dot patterns on a square)
------------------------------------------------------------
local function draw_dice(s, cx, cy, size, value, shade)
  local half = math.floor(size / 2)
  -- dice body
  rectf(s, cx - half, cy - half, size, size, 1)
  -- border
  rectf(s, cx - half, cy - half, size, 1, 0)
  rectf(s, cx - half, cy + half, size, 1, 0)
  rectf(s, cx - half, cy - half, 1, size, 0)
  rectf(s, cx + half, cy - half, 1, size + 1, 0)

  -- dot positions relative to center
  local d = math.floor(size / 4)
  local dots = {}
  if value == 1 then
    dots = {{0, 0}}
  elseif value == 2 then
    dots = {{-d, -d}, {d, d}}
  elseif value == 3 then
    dots = {{-d, -d}, {0, 0}, {d, d}}
  elseif value == 4 then
    dots = {{-d, -d}, {d, -d}, {-d, d}, {d, d}}
  elseif value == 5 then
    dots = {{-d, -d}, {d, -d}, {0, 0}, {-d, d}, {d, d}}
  elseif value == 6 then
    dots = {{-d, -d}, {d, -d}, {-d, 0}, {d, 0}, {-d, d}, {d, d}}
  end

  for _, dot in ipairs(dots) do
    local dx = cx + dot[1]
    local dy = cy + dot[2]
    rectf(s, dx, dy, 2, 2, 1)
  end
end

------------------------------------------------------------
-- INIT
------------------------------------------------------------
function _init()
  mode(1)
  build_board()
end

function _start()
  go("title")
end

------------------------------------------------------------
-- TITLE SCENE
------------------------------------------------------------
local title_anim = 0
local title_idle = 0

function title_init()
  title_anim = 0
  title_idle = 0
  demo_mode = false
end

function title_update()
  title_anim = title_anim + 1

  if btnp("start") or btnp("a") then
    vs_ai = true
    go("setup")
    return
  end
  if btnp("b") then
    vs_ai = false
    go("setup")
    return
  end

  -- attract/demo after idle
  title_idle = title_idle + 1
  if title_idle >= DEMO_IDLE then
    demo_mode = true
    vs_ai = true
    go("setup")
    return
  end
end

function title_draw()
  local s = screen()
  cls(s, 0)

  -- decorative border
  rectf(s, 0, 0, W, 2, 1)
  rectf(s, 0, H - 2, W, 2, 1)
  rectf(s, 0, 0, 2, H, 1)
  rectf(s, W - 2, 0, 2, H, 1)

  -- title
  local bounce = math.floor(math.sin(title_anim * 0.08) * 2)
  text(s, "SHAKE DICE", W / 2, 16 + bounce, 1, ALIGN_CENTER)
  text(s, "----------", W / 2, 24 + bounce, 1, ALIGN_CENTER)

  -- animated dice
  local d1 = (math.floor(title_anim / 8) % 6) + 1
  local d2 = (math.floor(title_anim / 6 + 3) % 6) + 1
  local wobble1 = math.sin(title_anim * 0.15) * 3
  local wobble2 = math.cos(title_anim * 0.12) * 3
  draw_dice(s, 60 + math.floor(wobble1), 46, 16, d1)
  draw_dice(s, 100 + math.floor(wobble2), 46, 16, d2)

  -- instructions
  text(s, "SHAKE TO ROLL!", W / 2, 66, 1, ALIGN_CENTER)

  if math.floor(title_anim / 20) % 2 == 0 then
    text(s, "A: VS AI", W / 2, 82, 1, ALIGN_CENTER)
  end
  text(s, "B: 2 PLAYER", W / 2, 92, 1, ALIGN_CENTER)

  -- shake hint
  text(s, "or press A to roll", W / 2, 108, 1, ALIGN_CENTER)
end

------------------------------------------------------------
-- SETUP SCENE (initialize game)
------------------------------------------------------------
function setup_init()
  players = {
    {pos = 1, score = 0, skip_turn = false, color = 1, is_ai = false},
    {pos = 1, score = 0, skip_turn = false, color = 1, is_ai = vs_ai},
  }
  current_player = 1
  dice_value = 0
  dice_rolling = false
  dice_tumble = 0
  dice_settled = false
  winner = 0
  turn_phase = "shake"
  shake_energy = 0
  shake_frames = 0
  prev_mx, prev_my, prev_mz = 0, 0, 0
  event_msg = ""
  event_timer = 0
  ai_shake_timer = 0
  ai_shake_dur = 0

  -- check motion
  has_motion = motion_enabled and motion_enabled()

  go("game")
end

function setup_update() end
function setup_draw() end

------------------------------------------------------------
-- GAME SCENE
------------------------------------------------------------

-- shake detection
local function detect_shake()
  if not has_motion then return 0 end
  local mx = motion_x()
  local my = motion_y()
  local mz = motion_z()
  local mag = math.abs(mx - prev_mx) + math.abs(my - prev_my) + math.abs(mz - prev_mz)
  prev_mx, prev_my, prev_mz = mx, my, mz
  return mag
end

-- apply event on landing
local function apply_event(p_idx)
  local p = players[p_idx]
  local ev = event_map[p.pos]
  if not ev then
    event_msg = ""
    return false
  end

  event_msg = get_event_label(ev)
  event_timer = 45

  if ev == "bonus" then
    -- player gets another roll (don't advance turn)
    tone(0, 600, 900, 0.3)
    return true  -- signal bonus roll
  elseif ev == "skip" then
    p.skip_turn = true
    tone(0, 300, 100, 0.2)
  elseif ev == "warp+" then
    p.pos = math.min(BOARD_SIZE, p.pos + 3)
    tone(0, 400, 800, 0.3)
  elseif ev == "warp-" then
    p.pos = math.max(1, p.pos - 3)
    tone(0, 400, 200, 0.2)
  elseif ev == "pts+" then
    p.score = p.score + 5
    tone(0, 500, 700, 0.25)
  elseif ev == "pts-" then
    p.score = math.max(0, p.score - 3)
    tone(0, 300, 150, 0.2)
  end
  return false
end

-- start the dice rolling animation
local function start_roll(energy)
  dice_rolling = true
  dice_settled = false
  dice_result_timer = 0
  -- tumble duration scales with shake energy
  local t = DICE_TUMBLE_BASE + math.floor(energy * 10)
  dice_tumble = clamp(t, DICE_TUMBLE_BASE, DICE_TUMBLE_MAX)
  dice_display = math.random(1, 6)
  -- roll sound
  tone(1, 200, 600, 0.15)
end

-- advance to next player's turn
local function next_turn()
  current_player = (current_player % num_players) + 1
  turn_phase = "shake"
  shake_energy = 0
  shake_frames = 0
  event_msg = ""
  event_timer = 0
  ai_shake_timer = 0
  ai_shake_dur = 0

  -- check if next player must skip
  local p = players[current_player]
  if p.skip_turn then
    p.skip_turn = false
    event_msg = "P" .. current_player .. " SKIPPED!"
    event_timer = 30
    turn_phase = "event"
  end
end

function game_init()
  -- already set up in setup_init
end

function game_update()
  local p = players[current_player]

  -- back to title
  if btnp("select") then
    go("title")
    return
  end

  -- win check
  if winner > 0 then
    if btnp("start") or btnp("a") then
      go("title")
    end
    return
  end

  -- event display timer
  if turn_phase == "event" then
    event_timer = event_timer - 1
    if event_timer <= 0 then
      -- if it was a skip event from next_turn, advance again
      if event_msg:find("SKIPPED") then
        next_turn()
      else
        turn_phase = "done"
      end
    end
    return
  end

  -- done phase: brief pause then next turn
  if turn_phase == "done" then
    event_timer = event_timer - 1
    if event_timer <= 0 then
      next_turn()
    end
    return
  end

  -- SHAKE / ROLL PHASE
  if turn_phase == "shake" then
    local is_ai = p.is_ai and not demo_mode == false
    -- AI and demo both auto-shake
    local ai_active = p.is_ai or demo_mode

    if ai_active then
      -- AI: simulate shaking after a brief delay
      ai_shake_timer = ai_shake_timer + 1
      if ai_shake_timer > 15 then
        if ai_shake_dur == 0 then
          ai_shake_dur = math.random(10, 25)
        end
        if ai_shake_timer < 15 + ai_shake_dur then
          shake_energy = shake_energy + 0.3
          shake_frames = shake_frames + 1
        end
        if shake_frames >= SHAKE_SUSTAIN then
          start_roll(clamp(shake_energy, 1, 4))
          turn_phase = "rolling"
        end
      end
    else
      -- human player
      local mag = detect_shake()
      if mag > SHAKE_THRESHOLD then
        shake_energy = shake_energy + mag
        shake_frames = shake_frames + 1
        -- dice rattle sound
        if shake_frames % 3 == 0 then
          tone(2, 100 + shake_frames * 10, 150 + shake_frames * 10, 0.08)
        end
      else
        -- decay shake if not shaking
        if shake_frames > 0 then
          shake_frames = shake_frames - 1
        end
      end

      -- button fallback
      if btnp("a") then
        shake_energy = 2.0
        shake_frames = SHAKE_SUSTAIN
      end

      if shake_frames >= SHAKE_SUSTAIN then
        start_roll(clamp(shake_energy, 1, 4))
        turn_phase = "rolling"
      end
    end
  end

  -- ROLLING ANIMATION
  if turn_phase == "rolling" then
    dice_tumble = dice_tumble - 1
    -- change displayed face rapidly, slowing down
    local change_rate = 2
    if dice_tumble < 20 then change_rate = 4 end
    if dice_tumble < 10 then change_rate = 6 end
    if dice_tumble < 5 then change_rate = 10 end

    if dice_tumble % change_rate == 0 then
      dice_display = math.random(1, 6)
      -- tick sound
      tone(2, 300 + math.random(0, 200), 300 + math.random(0, 200), 0.05)
    end

    if dice_tumble <= 0 then
      -- settle on final value
      dice_value = math.random(1, 6)
      dice_display = dice_value
      dice_rolling = false
      dice_settled = true
      dice_result_timer = 30
      turn_phase = "result"
      -- thud sound
      tone(0, 150, 80, 0.3)
      tone(1, 100, 50, 0.2)
    end
  end

  -- RESULT DISPLAY
  if turn_phase == "result" then
    dice_result_timer = dice_result_timer - 1
    if dice_result_timer <= 0 then
      -- start moving
      move_from = p.pos
      move_target = math.min(BOARD_SIZE, p.pos + dice_value)
      move_anim = 0
      turn_phase = "moving"
    end
  end

  -- MOVING ANIMATION
  if turn_phase == "moving" then
    move_anim = move_anim + 1
    if move_anim % 6 == 0 then
      if p.pos < move_target then
        p.pos = p.pos + 1
        -- step sound
        tone(2, 400 + p.pos * 20, 500 + p.pos * 20, 0.1)
      end
    end

    if p.pos >= move_target then
      -- check win
      if p.pos >= BOARD_SIZE then
        p.pos = BOARD_SIZE
        winner = current_player
        -- victory fanfare
        tone(0, 400, 800, 0.4)
        tone(1, 600, 1000, 0.3)
        turn_phase = "shake"  -- stop processing
        return
      end

      -- apply event
      local bonus = apply_event(current_player)
      if bonus then
        -- bonus roll: reset shake state, stay on current player
        turn_phase = "event"
        -- after event display, go back to shake
      elseif event_msg ~= "" then
        turn_phase = "event"
      else
        -- no event, brief pause then next turn
        event_timer = 10
        turn_phase = "done"
      end
    end
  end

  -- after bonus event display, go back to shake for same player
  if turn_phase == "event" and event_timer > 0 then
    event_timer = event_timer - 1
    if event_timer <= 0 then
      if event_msg == "ROLL AGAIN!" then
        -- bonus roll
        turn_phase = "shake"
        shake_energy = 0
        shake_frames = 0
        ai_shake_timer = 0
        ai_shake_dur = 0
      else
        event_timer = 10
        turn_phase = "done"
      end
    end
  end

  -- demo mode: return to title on any press
  if demo_mode then
    if btnp("start") or btnp("a") or btnp("b") then
      demo_mode = false
      go("title")
      return
    end
    -- end demo after a winner
    if winner > 0 then
      demo_mode = false
      go("title")
    end
  end
end

------------------------------------------------------------
-- GAME DRAW
------------------------------------------------------------
local function draw_board(s, highlight_sq)
  for i = 1, BOARD_SIZE do
    local sq = board[i]
    local col = get_square_color(i)

    -- highlight current target
    if i == highlight_sq and math.floor(frame() / 8) % 2 == 0 then
      col = 15
    end

    rectf(s, sq.x, sq.y, 18, 14, col)
    -- border
    rectf(s, sq.x, sq.y, 18, 1, 0)
    rectf(s, sq.x, sq.y + 13, 18, 1, 0)

    -- square number
    text(s, tostring(i), sq.x + 9, sq.y + 4, 0, ALIGN_CENTER)

    -- event icon
    local ev = event_map[i]
    if ev == "bonus" then
      text(s, "+", sq.x + 15, sq.y + 1, 0)
    elseif ev == "skip" then
      text(s, "X", sq.x + 15, sq.y + 1, 0)
    elseif ev == "warp+" then
      text(s, ">", sq.x + 15, sq.y + 1, 0)
    elseif ev == "warp-" then
      text(s, "<", sq.x + 15, sq.y + 1, 0)
    elseif ev == "pts+" then
      text(s, "$", sq.x + 15, sq.y + 1, 0)
    elseif ev == "pts-" then
      text(s, "!", sq.x + 15, sq.y + 1, 0)
    end

    -- start/finish labels
    if i == 1 then
      text(s, "S", sq.x + 2, sq.y + 8, 0)
    elseif i == BOARD_SIZE then
      text(s, "F", sq.x + 2, sq.y + 8, 0)
    end
  end
end

local function draw_players(s)
  for pi = 1, num_players do
    local p = players[pi]
    if p.pos >= 1 and p.pos <= BOARD_SIZE then
      local sq = board[p.pos]
      -- offset tokens so both visible on same square
      local ox = pi == 1 and 4 or 12
      local oy = 10
      -- token: filled circle-ish (small rect)
      local tc = p.color
      rectf(s, sq.x + ox - 2, sq.y + oy - 2, 5, 5, tc)
      rectf(s, sq.x + ox - 1, sq.y + oy - 3, 3, 7, tc)
      -- player number on token
      text(s, tostring(pi), sq.x + ox, sq.y + oy - 1, 0, ALIGN_CENTER)
    end
  end
end

function game_draw()
  local s = screen()
  cls(s, 0)

  -- HUD top bar
  rectf(s, 0, 0, W, 10, 1)
  local p1_label = "P1:" .. players[1].score
  local p2_label = (vs_ai and "AI:" or "P2:") .. players[2].score
  text(s, p1_label, 2, 2, 0)
  text(s, p2_label, W - 2, 2, 0, ALIGN_RIGHT)

  -- current player indicator
  local turn_label = "P" .. current_player .. "'s TURN"
  if players[current_player].is_ai and not demo_mode then
    turn_label = "AI's TURN"
  end
  if demo_mode then
    turn_label = "- DEMO -"
  end
  text(s, turn_label, W / 2, 2, 0, ALIGN_CENTER)

  -- HUD bottom bar
  rectf(s, 0, H - 10, W, 10, 1)

  -- draw board
  draw_board(s, (turn_phase == "moving") and move_target or 0)

  -- draw player tokens
  draw_players(s)

  -- DICE DISPLAY (bottom right area)
  local dice_cx = W - 20
  local dice_cy = H - 22
  local dice_size = 14

  if turn_phase == "shake" then
    -- show shake prompt
    if not (players[current_player].is_ai or demo_mode) then
      local shake_bar = math.floor((shake_frames / SHAKE_SUSTAIN) * 30)
      -- shake meter
      rectf(s, 4, H - 8, 32, 5, 0)
      if shake_bar > 0 then
        rectf(s, 4, H - 8, math.min(shake_bar, 32), 5, 1)
      end
      text(s, "SHAKE!", 20, H - 8, 0, ALIGN_CENTER)

      -- draw idle dice
      local wobble = math.sin(frame() * 0.1) * 1
      draw_dice(s, dice_cx + math.floor(wobble), dice_cy, dice_size, (math.floor(frame() / 15) % 6) + 1, 1)
    else
      -- AI shaking indicator
      if ai_shake_timer > 15 then
        local wobble = math.sin(frame() * 0.3) * 3
        draw_dice(s, dice_cx + math.floor(wobble), dice_cy + math.floor(math.cos(frame() * 0.4) * 2), dice_size, math.random(1, 6), 1)
        text(s, "SHAKING...", W / 2, H - 8, 0, ALIGN_CENTER)
      else
        text(s, "WAITING...", W / 2, H - 8, 0, ALIGN_CENTER)
      end
    end
  elseif turn_phase == "rolling" then
    -- tumbling dice with shake animation
    local wobble_x = math.sin(frame() * 0.5) * (dice_tumble / 10)
    local wobble_y = math.cos(frame() * 0.7) * (dice_tumble / 12)
    draw_dice(s, dice_cx + math.floor(wobble_x), dice_cy + math.floor(wobble_y), dice_size, dice_display, 1)
    text(s, "ROLLING...", W / 2, H - 8, 0, ALIGN_CENTER)
  elseif turn_phase == "result" then
    -- show final result prominently
    draw_dice(s, dice_cx, dice_cy, dice_size, dice_value, 1)
    -- flash the result
    if math.floor(frame() / 4) % 2 == 0 then
      text(s, "ROLLED: " .. dice_value, W / 2, H - 8, 0, ALIGN_CENTER)
    end
  elseif turn_phase == "moving" then
    draw_dice(s, dice_cx, dice_cy, dice_size, dice_value, 1)
    text(s, "MOVING...", W / 2, H - 8, 0, ALIGN_CENTER)
  end

  -- event message overlay
  if event_msg ~= "" and event_timer > 0 then
    rectf(s, 20, 52, 120, 16, 1)
    rectf(s, 21, 53, 118, 14, 0)
    text(s, event_msg, W / 2, 57, 1, ALIGN_CENTER)
  end

  -- winner overlay
  if winner > 0 then
    rectf(s, 20, 35, 120, 50, 1)
    rectf(s, 22, 37, 116, 46, 0)
    local wlabel = "PLAYER " .. winner .. " WINS!"
    if players[winner].is_ai then
      wlabel = "AI WINS!"
    end
    text(s, wlabel, W / 2, 44, 1, ALIGN_CENTER)
    text(s, "SCORE: " .. players[winner].score, W / 2, 56, 1, ALIGN_CENTER)

    -- show both scores
    text(s, "P1: " .. players[1].score .. " pts", W / 2, 66, 1, ALIGN_CENTER)
    local p2tag = vs_ai and "AI" or "P2"
    text(s, p2tag .. ": " .. players[2].score .. " pts", W / 2, 74, 1, ALIGN_CENTER)

    if math.floor(frame() / 20) % 2 == 0 then
      text(s, "PRESS START", W / 2, H - 8, 0, ALIGN_CENTER)
    end
  end

  -- legend (bottom)
  if turn_phase == "shake" and winner == 0 and not (players[current_player].is_ai or demo_mode) then
    text(s, "A=roll", W - 2, H - 8, 0, ALIGN_RIGHT)
  end
end
