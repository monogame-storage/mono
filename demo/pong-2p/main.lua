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
local SPEED = 2.5
local MAX_SCORE = 9

-- state
local p1, p2, ball
local score1, score2
local serve_dir
local game_started

local function reset_ball(dir)
  local angle = (math.random() - 0.5) * 2.0
  ball = { x = 80, y = 60, dx = SPEED * dir, dy = angle }
end

local function init_match()
  p1 = { x = 6,   y = 48 }
  p2 = { x = 150, y = 48 }
  score1 = 0
  score2 = 0
  serve_dir = 1
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

  -- Two human paddles.
  move_paddle(p1, 0)
  move_paddle(p2, 1)

  -- Ball physics.
  ball.x = ball.x + ball.dx
  ball.y = ball.y + ball.dy
  if ball.y - BS <= 0 then ball.y = BS; ball.dy = -ball.dy end
  if ball.y + BS >= SCREEN_H then ball.y = SCREEN_H - BS; ball.dy = -ball.dy end

  if ball_paddle_collide(ball, p1) and ball.dx < 0 then
    ball.dx = -ball.dx
    ball.x  = p1.x + PW + BS
    ball.dy = ((ball.y - (p1.y + PH / 2)) / (PH / 2)) * 3.0
  end
  if ball_paddle_collide(ball, p2) and ball.dx > 0 then
    ball.dx = -ball.dx
    ball.x  = p2.x - BS
    ball.dy = ((ball.y - (p2.y + PH / 2)) / (PH / 2)) * 3.0
  end

  -- Scoring.
  if ball.x < 0 then
    score2 = score2 + 1
    serve_dir = -1
    reset_ball(serve_dir)
  end
  if ball.x > SCREEN_W then
    score1 = score1 + 1
    serve_dir = 1
    reset_ball(serve_dir)
  end
end

function _draw()
  cls(scr, 0)

  -- Pre-match: gameplay-area status indicator. The engine also draws a
  -- centered "WAITING FOR PEER" badge over everything; this just keeps the
  -- screen non-blank.
  if not game_started then
    text(scr, "PONG 2P", 80, 50, 12, ALIGN_HCENTER)
    text(scr, "open in 2 tabs", 80, 66, 6, ALIGN_HCENTER)
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

  -- score
  text(scr, tostring(score1), 40,  4, 8, ALIGN_HCENTER)
  text(scr, tostring(score2), 120, 4, 8, ALIGN_HCENTER)
  -- (No "you are player N" marker in the cart — both peers must render an
  -- identical screen for the lockstep hash exchange to verify sync.)
end
