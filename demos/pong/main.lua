-- Mono Pong
-- 2P: left=W/S, right=Up/Down | 1P: left=auto, right=Up/Down

-- constants
local PW = 4    -- paddle width
local PH = 24   -- paddle height
local BS = 3    -- ball size (radius)
local SPEED = 2.5
local AI_SPEED = 1.8
local MAX_SCORE = 9

-- state
local p1, p2, ball
local score1, score2
local obstacles
local serve_dir
local paused
local winner

local function reset_ball(dir)
  ball = {
    x = 80, y = 72,
    dx = SPEED * dir,
    dy = (math.random(0, 2) - 1) * 1.2  -- -1.2, 0, or 1.2
  }
end

local circle_obs  -- circle obstacles

local function init_obstacles()
  obstacles = {}
  circle_obs = {
    { cx = 80, cy = 34, r = 6 },
    { cx = 80, cy = 110, r = 6 },
  }
end

function _init()
  mode(4)
end

function _start()
  p1 = { x = 6, y = 60 }
  p2 = { x = 150, y = 60 }
  score1 = 0
  score2 = 0
  serve_dir = 1
  winner = nil
  paused = false
  init_obstacles()
  reset_ball(serve_dir)
end

-- AI for left paddle
local function ai_update()
  local center = p1.y + PH / 2
  if ball.dx < 0 then
    -- ball coming toward AI
    if center < ball.y - 3 then
      p1.y = p1.y + AI_SPEED
    elseif center > ball.y + 3 then
      p1.y = p1.y - AI_SPEED
    end
  else
    -- ball going away, drift toward center
    if center < 68 then
      p1.y = p1.y + 0.5
    elseif center > 76 then
      p1.y = p1.y - 0.5
    end
  end
  -- clamp
  if p1.y < 0 then p1.y = 0 end
  if p1.y > SCREEN_H - PH then p1.y = SCREEN_H - PH end
end

local function clamp_paddle(p)
  if p.y < 0 then p.y = 0 end
  if p.y > SCREEN_H - PH then p.y = SCREEN_H - PH end
end

local function sign(v)
  if v > 0 then return 1 end
  if v < 0 then return -1 end
  return 0
end

local function ball_rect_collide(bx, by, br, rx, ry, rw, rh)
  local cx = bx
  local cy = by
  if cx < rx then cx = rx end
  if cx > rx + rw then cx = rx + rw end
  if cy < ry then cy = ry end
  if cy > ry + rh then cy = ry + rh end
  local dx = bx - cx
  local dy = by - cy
  return (dx * dx + dy * dy) <= (br * br)
end

function _update()
  if winner then
    if btnp("start") then
      _start()
    end
    return
  end

  -- player 2 input (right paddle)
  if btn("up") then p2.y = p2.y - 3 end
  if btn("down") then p2.y = p2.y + 3 end
  clamp_paddle(p2)

  -- AI
  ai_update()

  -- ball movement
  ball.x = ball.x + ball.dx
  ball.y = ball.y + ball.dy

  -- top/bottom wall bounce
  if ball.y - BS <= 0 then
    ball.y = BS
    ball.dy = -ball.dy
  end
  if ball.y + BS >= SCREEN_H then
    ball.y = SCREEN_H - BS
    ball.dy = -ball.dy
  end

  -- paddle collision (left)
  if ball_rect_collide(ball.x, ball.y, BS, p1.x, p1.y, PW, PH) then
    ball.x = p1.x + PW + BS
    ball.dx = SPEED
    local hit = (ball.y - (p1.y + PH / 2)) / (PH / 2)
    ball.dy = hit * 3.0
  end

  -- paddle collision (right)
  if ball_rect_collide(ball.x, ball.y, BS, p2.x, p2.y, PW, PH) then
    ball.x = p2.x - BS
    ball.dx = -SPEED
    local hit = (ball.y - (p2.y + PH / 2)) / (PH / 2)
    ball.dy = hit * 3.0
  end

  -- rect obstacle collision
  for _, ob in ipairs(obstacles) do
    if ball_rect_collide(ball.x, ball.y, BS, ob.x, ob.y, ob.w, ob.h) then
      local prev_x = ball.x - ball.dx
      local prev_y = ball.y - ball.dy
      local from_side = (prev_x < ob.x or prev_x > ob.x + ob.w)
      if from_side then
        ball.dx = -ball.dx
        ball.x = ball.x + ball.dx * 2
      else
        ball.dy = -ball.dy
        ball.y = ball.y + ball.dy * 2
      end
      break
    end
  end

  -- circle obstacle collision
  for _, ob in ipairs(circle_obs) do
    local cdx = ball.x - ob.cx
    local cdy = ball.y - ob.cy
    local dist = math.sqrt(cdx * cdx + cdy * cdy)
    local min_dist = BS + ob.r
    if dist < min_dist and dist > 0 then
      local nx = cdx / dist
      local ny = cdy / dist
      local dot = ball.dx * nx + ball.dy * ny
      ball.dx = ball.dx - 2 * dot * nx
      ball.dy = ball.dy - 2 * dot * ny
      ball.x = ob.cx + nx * min_dist
      ball.y = ob.cy + ny * min_dist
      break
    end
  end

  -- scoring
  if ball.x < 0 then
    score2 = score2 + 1
    serve_dir = -1
    if score2 >= MAX_SCORE then
      winner = "P2"
    else
      reset_ball(serve_dir)
    end
  end
  if ball.x > SCREEN_W then
    score1 = score1 + 1
    serve_dir = 1
    if score1 >= MAX_SCORE then
      winner = "CPU"
    else
      reset_ball(serve_dir)
    end
  end
end

function _draw()
  cls(0)

  -- center line (dashed)
  for y = 0, SCREEN_H - 1, 6 do
    rectf(79, y, 2, 3, 3)
  end

  -- rect obstacles
  for _, ob in ipairs(obstacles) do
    rectf(ob.x, ob.y, ob.w, ob.h, 7)
    rect(ob.x, ob.y, ob.w, ob.h, 10)
  end

  -- circle obstacles
  for _, ob in ipairs(circle_obs) do
    circf(ob.cx, ob.cy, ob.r, 7)
    circ(ob.cx, ob.cy, ob.r, 10)
  end

  -- paddles
  rectf(p1.x, p1.y, PW, PH, 12)
  rectf(p2.x, p2.y, PW, PH, 15)

  -- ball
  circf(ball.x, ball.y, BS, 15)

  -- score
  text(tostring(score1), 60, 4, 8)
  text(tostring(score2), 94, 4, 8)

  -- border
  line(0, 0, SCREEN_W - 1, 0, 5)
  line(0, SCREEN_H - 1, SCREEN_W - 1, SCREEN_H - 1, 5)

  -- winner screen
  if winner then
    rectf(40, 55, 80, 30, 0)
    rect(40, 55, 80, 30, 15)
    text(winner .. " WINS!", 52, 63, 15)
    text("PRESS START", 44, 75, 8)
  end
end
