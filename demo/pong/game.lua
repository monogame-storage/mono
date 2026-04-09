-- Pong Demo
-- Covers: note, sfx_stop, cam_shake, cam_reset, gpix (+ basic draw APIs)
--
-- Controls:
--   UP / DOWN : move left paddle (player)
--   START     : reset match

local scr = screen()

local PAD_W, PAD_H = 3, 20
local BALL_SIZE = 3
local WIN_SCORE = 5

local p1_y, p2_y
local ball_x, ball_y, ball_dx, ball_dy
local score1, score2
local shake_frames

function _init()
  mode(4)
end

local function reset_ball(dir)
  ball_x = SCREEN_W / 2
  ball_y = SCREEN_H / 2
  ball_dx = dir or (math.random() < 0.5 and -2.5 or 2.5)
  ball_dy = (math.random() - 0.5) * 2
end

local function reset_match()
  p1_y = SCREEN_H / 2 - PAD_H / 2
  p2_y = SCREEN_H / 2 - PAD_H / 2
  score1 = 0
  score2 = 0
  shake_frames = 0
  reset_ball()
end

function _start()
  math.randomseed(1)  -- deterministic for tests
  reset_match()
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function _update()
  if btnp("start") then
    reset_match()
    return
  end

  -- Player paddle
  if btn("up")   then p1_y = p1_y - 2 end
  if btn("down") then p1_y = p1_y + 2 end
  p1_y = clamp(p1_y, 0, SCREEN_H - PAD_H)

  -- AI paddle: lag behind ball
  local target = ball_y - PAD_H / 2
  if math.abs(p2_y - target) > 1 then
    p2_y = p2_y + (p2_y < target and 1.5 or -1.5)
  end
  p2_y = clamp(p2_y, 0, SCREEN_H - PAD_H)

  -- Ball
  ball_x = ball_x + ball_dx
  ball_y = ball_y + ball_dy

  -- Walls (top/bottom)
  if ball_y < 0 then
    ball_y = 0; ball_dy = -ball_dy
    note(1, "G4", 0.03)
  elseif ball_y + BALL_SIZE > SCREEN_H then
    ball_y = SCREEN_H - BALL_SIZE; ball_dy = -ball_dy
    note(1, "G4", 0.03)
  end

  -- Paddle collisions (use gpix to sample current screen for demo purposes)
  local bx = math.floor(ball_x)
  local by = math.floor(ball_y + BALL_SIZE / 2)
  if ball_dx < 0 and bx <= PAD_W and by >= p1_y and by <= p1_y + PAD_H then
    ball_x = PAD_W
    ball_dx = -ball_dx * 1.05
    ball_dy = ball_dy + (math.random() - 0.5) * 0.5
    note(0, "C5", 0.05)
    cam_shake(2)
    shake_frames = 6
  elseif ball_dx > 0 and bx + BALL_SIZE >= SCREEN_W - PAD_W
         and by >= p2_y and by <= p2_y + PAD_H then
    ball_x = SCREEN_W - PAD_W - BALL_SIZE
    ball_dx = -ball_dx * 1.05
    ball_dy = ball_dy + (math.random() - 0.5) * 0.5
    note(0, "E5", 0.05)
    cam_shake(2)
    shake_frames = 6
  end

  -- Score
  if ball_x + BALL_SIZE < 0 then
    score2 = score2 + 1
    sfx_stop()
    note(0, "C3", 0.3)
    reset_ball(1.3)
  elseif ball_x > SCREEN_W then
    score1 = score1 + 1
    sfx_stop()
    note(0, "G5", 0.3)
    reset_ball(-1.3)
  end

  if shake_frames > 0 then
    shake_frames = shake_frames - 1
    if shake_frames == 0 then cam_reset() end
  end
end

function _draw()
  cls(scr, 0)

  -- center dashed line
  for y = 0, SCREEN_H - 1, 6 do
    rectf(scr, SCREEN_W / 2, y, 1, 3, 6)
  end

  -- paddles
  rectf(scr, 0, math.floor(p1_y), PAD_W, PAD_H, 15)
  rectf(scr, SCREEN_W - PAD_W, math.floor(p2_y), PAD_W, PAD_H, 15)

  -- ball
  rectf(scr, math.floor(ball_x), math.floor(ball_y), BALL_SIZE, BALL_SIZE, 14)

  -- HUD (camera-independent)
  cam(0, 0)
  text(scr, tostring(score1), SCREEN_W / 2 - 20, 4, 11, ALIGN_RIGHT)
  text(scr, tostring(score2), SCREEN_W / 2 + 20, 4, 11)
  text(scr, "PONG", 0, SCREEN_H - 10, 6, ALIGN_HCENTER)

  if score1 >= WIN_SCORE or score2 >= WIN_SCORE then
    text(scr, score1 > score2 and "YOU WIN" or "AI WINS",
         0, SCREEN_H / 2 - 4, 15, ALIGN_HCENTER)
  end

  -- gpix demo: sample a known pixel and render a tiny probe indicator
  local c = gpix(scr, math.floor(ball_x), math.floor(ball_y))
  if c >= 0 then
    rectf(scr, SCREEN_W - 6, SCREEN_H - 6, 4, 4, 12)
  end
end
