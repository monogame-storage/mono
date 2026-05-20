-- Mono Pong 2P (lockstep netplay)
-- Open this cart in two browser tabs on the same origin. Both tabs auto-pair
-- via BroadcastChannel — no SDP, no server, anonymous.
--   Player 0 (left paddle): W/S or up/down on this side's keyboard
--   Player 1 (right paddle): same keys on the other tab
-- The engine routes btn(k, 0) / btn(k, 1) to the right player; each tab's
-- hardware drives its local player slot.

local scr = screen()

-- constants
local PW = 4
local PH = 24
local BS = 3
local START_SPEED = 1.5
local MAX_SPEED   = 3.0
local SPEED_MULT  = 1.02
local MAX_SCORE   = 7
local READY_WINDOW = 120   -- frames both players have to confirm rematch

-- state
local p1, p2, ball
local score1, score2
local serve_dir
local game_started
local winner            -- nil | 1 | 2
local rally_hits        -- consecutive paddle hits this rally
local ready             -- {p1, p2} rematch consent
local ready_timer       -- frames until consent resets

local function reset_ball(dir)
  local angle = (math.random() - 0.5) * 2.0
  ball = { x = 80, y = 60, dx = START_SPEED * dir, dy = angle, speed = START_SPEED }
end

local function init_match()
  p1 = { x = 6,   y = 48 }
  p2 = { x = 150, y = 48 }
  score1 = 0
  score2 = 0
  serve_dir = 1
  winner = nil
  rally_hits = 0
  ready = { false, false }
  ready_timer = 0
  reset_ball(serve_dir)
end

function _init()
  mode(4)
  -- Disable engine pause-on-select; in lockstep, local pause would desync.
  use_pause(false)
end

function _start()
  net.start()
  game_started = false
end

local function clamp_paddle(p)
  if p.y < 0 then p.y = 0 end
  if p.y > SCREEN_H - PH then p.y = SCREEN_H - PH end
end

local function move_paddle(p, player_idx)
  if btn("up",   player_idx) then p.y = p.y - 3 end
  if btn("down", player_idx) then p.y = p.y + 3 end
  clamp_paddle(p)
end

local function ball_paddle_collide(b, p)
  if b.x - BS > p.x + PW then return false end
  if b.x + BS < p.x      then return false end
  if b.y + BS < p.y      then return false end
  if b.y - BS > p.y + PH then return false end
  return true
end

-- Accelerate ball after a paddle hit; cap at MAX_SPEED.
local function rally_accelerate()
  ball.speed = math.min(MAX_SPEED, ball.speed * SPEED_MULT)
  -- Re-normalize dx to the current speed, preserving sign.
  local sign = ball.dx >= 0 and 1 or -1
  ball.dx = ball.speed * sign
  rally_hits = rally_hits + 1
  -- Hit SFX + rally milestone chime every 5 hits.
  note(0, "C5", 0.04)
  if rally_hits % 5 == 0 then
    note(0, "E5", 0.06)
  end
end

-- Both peers must press A within READY_WINDOW frames to rematch.
local function update_ready_gate()
  if btnp("a", 0) and not ready[1] then
    ready[1] = true
    ready_timer = READY_WINDOW
    note(0, "C5", 0.06)
  end
  if btnp("a", 1) and not ready[2] then
    ready[2] = true
    ready_timer = READY_WINDOW
    note(1, "E5", 0.06)
  end
  if ready[1] and ready[2] then
    init_match()
    note(0, "C5", 0.1); note(1, "G5", 0.1)
    return
  end
  if ready_timer > 0 then
    ready_timer = ready_timer - 1
    if ready_timer <= 0 then
      ready = { false, false }
    end
  end
end

function _update()
  -- Wait for peer to pair, then deterministically seed Lua RNG from the
  -- shared session seed so both peers serve the same ball trajectory.
  if not game_started then
    if net.status() ~= "playing" then return end
    math.randomseed(net.seed())
    init_match()
    game_started = true
    return
  end

  -- Winner state: ball frozen, wait for both-A rematch consent.
  if winner then
    update_ready_gate()
    return
  end

  -- Two human paddles.
  move_paddle(p1, 0)
  move_paddle(p2, 1)

  -- Ball physics.
  ball.x = ball.x + ball.dx
  ball.y = ball.y + ball.dy
  if ball.y - BS <= 0 then
    ball.y = BS; ball.dy = -ball.dy
    note(0, "G4", 0.03)
  end
  if ball.y + BS >= SCREEN_H then
    ball.y = SCREEN_H - BS; ball.dy = -ball.dy
    note(0, "G4", 0.03)
  end

  if ball_paddle_collide(ball, p1) and ball.dx < 0 then
    ball.dx = -ball.dx
    ball.x  = p1.x + PW + BS
    ball.dy = ((ball.y - (p1.y + PH / 2)) / (PH / 2)) * 3.0
    rally_accelerate()
  end
  if ball_paddle_collide(ball, p2) and ball.dx > 0 then
    ball.dx = -ball.dx
    ball.x  = p2.x - BS
    ball.dy = ((ball.y - (p2.y + PH / 2)) / (PH / 2)) * 3.0
    rally_accelerate()
  end

  -- Scoring.
  local scored = false
  if ball.x < 0 then
    score2 = score2 + 1
    serve_dir = -1
    scored = true
  end
  if ball.x > SCREEN_W then
    score1 = score1 + 1
    serve_dir = 1
    scored = true
  end
  if scored then
    tone(0, 220, 120, 0.25)
    rally_hits = 0
    if score1 >= MAX_SCORE then
      winner = 1
    elseif score2 >= MAX_SCORE then
      winner = 2
    else
      reset_ball(serve_dir)
    end
  end
end

local function draw_pre_match()
  text(scr, "PONG 2P", 80, 30, 12, ALIGN_HCENTER)
  if math.floor(frame() / 30) % 2 == 0 then
    text(scr, "WAITING...", 80, 60, 10, ALIGN_HCENTER)
  end
  text(scr, net.status(), 80, SCREEN_H - 9, 6, ALIGN_HCENTER)
end

local function draw_winner_panel()
  local cx = 80
  rectf(scr, 18, 36, 124, 48, 0)
  rect(scr,  18, 36, 124, 48, 15)
  local label = "P" .. winner .. " WINS!"
  local color = winner == 1 and 12 or 15
  text(scr, label, cx, 46, color, ALIGN_HCENTER)
  text(scr, "PRESS A FOR REMATCH", cx, 60, 7, ALIGN_HCENTER)
  -- Show each player's ready state.
  local l1 = ready[1] and "READY" or "PRESS A"
  local l2 = ready[2] and "READY" or "PRESS A"
  text(scr, "P1 " .. l1, cx - 30, 72, ready[1] and 11 or 8, ALIGN_HCENTER)
  text(scr, "P2 " .. l2, cx + 30, 72, ready[2] and 11 or 8, ALIGN_HCENTER)
end

function _draw()
  cls(scr, 0)

  -- Pre-match: title underneath the engine's status overlay (CONNECTING /
  -- WAITING FOR PEER / DISCONNECTED) so the screen isn't blank.
  if not game_started then
    draw_pre_match()
    return
  end

  -- center line (dashed)
  for y = 0, SCREEN_H - 1, 6 do
    rectf(scr, 79, y, 2, 3, 3)
  end

  -- paddles
  rectf(scr, p1.x, p1.y, PW, PH, 12)
  rectf(scr, p2.x, p2.y, PW, PH, 15)

  -- ball
  circf(scr, ball.x, ball.y, BS, 15)

  -- HUD: P1/P2 labels next to scores. Both peers render identical labels.
  text(scr, "P1",              28,  4, 12, ALIGN_HCENTER)
  text(scr, tostring(score1),  50,  4, 8,  ALIGN_HCENTER)
  text(scr, "P2",             132,  4, 15, ALIGN_HCENTER)
  text(scr, tostring(score2), 110,  4, 8,  ALIGN_HCENTER)

  if winner then draw_winner_panel() end
  -- (No "you are player N" marker in the cart — both peers must render an
  -- identical screen for the lockstep hash exchange to verify sync.)
end
