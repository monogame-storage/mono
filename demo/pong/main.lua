-- Mono Pong
-- 2P: left=W/S, right=Up/Down | 1P: left=auto, right=Up/Down

local scr = screen()

-- constants
local PW = 4    -- paddle width
local PH = 24   -- paddle height
local BS = 3    -- ball size (radius)
local SPEED = 2.5
local MAX_SCORE = 9
local MIN_ANGLE = 0.18  -- ~10 degrees from vertical (tan(10°))
local OBS_BOOST = 1.3   -- speed multiplier on obstacle hit
local RALLY_ACCEL = 0.02 -- speed increase per rally hit

-- difficulty
local DIFFICULTIES = { "EASY", "NORM", "HARD" }
local AI_SPEEDS    = { 1.2,    1.8,    2.4 }
local difficulty_idx = 2  -- NORM default
local AI_SPEED = AI_SPEEDS[difficulty_idx]

-- state
local state -- "title" | "play" | "over"
local p1, p2, ball
local score1, score2
local obstacles
local serve_dir
local paused
local winner
local rally_speed  -- current ball speed (increases during rally)
local rally_hits   -- count of paddle face hits this rally (for milestone chord)
local rally_chord_pending -- frame on which to play the second chord note
local wins_total   -- persisted wins count

local function sfx_paddle()
  note(0, "C5", 0.05)
  cam_shake(1)
end

local function sfx_wall()
  note(0, "C4", 0.03)
end

local function sfx_obstacle()
  note(0, "C6", 0.06)
  cam_shake(2)
end

local function sfx_score()
  -- sfx_stop() cuts any lingering audio before the victory chime
  sfx_stop()
  note(0, "C3", 0.15)
end

local function sfx_victory()
  sfx_stop()
  tone(0, 400, 1200, 0.3)
end

local function sfx_loss()
  sfx_stop()
  tone(0, 1200, 200, 0.4)
end

-- enforce minimum angle from vertical
local function enforce_min_angle(dx, dy)
  if math.abs(dy) > 0 and math.abs(dx) / math.abs(dy) < MIN_ANGLE then
    dx = math.abs(dy) * MIN_ANGLE
    if ball.dx < 0 then dx = -dx end
  end
  return dx, dy
end

local function reset_ball(dir)
  rally_speed = SPEED
  rally_hits = 0
  rally_chord_pending = nil
  local angle = math.random(1, 2) == 1 and 1.5 or -1.5
  angle = angle + (math.random() - 0.5) * 0.8
  ball = {
    x = 80, y = 60,
    dx = SPEED * dir,
    dy = angle
  }
  ball.dx, ball.dy = enforce_min_angle(ball.dx, ball.dy)
end

local circle_obs  -- circle obstacles (orbit their anchor)

local function init_obstacles()
  obstacles = {}
  -- Anchors at the original positions; phase π apart so they oscillate opposite.
  circle_obs = {
    { anchor_y = 30, cx = 80, cy = 30, r = 6, phase = 0 },
    { anchor_y = 90, cx = 80, cy = 90, r = 6, phase = math.pi },
  }
end

function _init()
  mode(4)
end

local function begin_match()
  p1 = { x = 6, y = 48 }
  p2 = { x = 150, y = 48 }
  score1 = 0
  score2 = 0
  serve_dir = 1
  winner = nil
  paused = false
  init_obstacles()
  reset_ball(serve_dir)
  state = "play"
end

function _start()
  wins_total = data_load("pong_wins") or 0
  state = "title"
  paused = false
  -- Initialise obstacle table so the title screen can preview them if desired.
  init_obstacles()
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
    if center < 56 then
      p1.y = p1.y + 0.5
    elseif center > 64 then
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

-- paddle collision with side detection
local function paddle_hit(paddle, bounce_dir)
  if not ball_rect_collide(ball.x, ball.y, BS, paddle.x, paddle.y, PW, PH) then
    return false
  end

  -- determine if ball hit the face (front) or the edge (top/bottom)
  local prev_x = ball.x - ball.dx
  local hit_face

  if bounce_dir > 0 then
    -- left paddle: face is on the right side
    hit_face = prev_x >= paddle.x + PW - 1
  else
    -- right paddle: face is on the left side
    hit_face = prev_x <= paddle.x + 1
  end

  if not hit_face then
    -- hit top or bottom edge — reflect vertically, keep horizontal direction
    ball.dy = -ball.dy
    ball.y = ball.y + ball.dy * 2
    sfx_wall()
    return true
  end

  -- face hit — normal pong bounce
  rally_speed = rally_speed + RALLY_ACCEL
  if bounce_dir > 0 then
    ball.x = paddle.x + PW + BS
  else
    ball.x = paddle.x - BS
  end
  ball.dx = rally_speed * bounce_dir
  local hit = (ball.y - (paddle.y + PH / 2)) / (PH / 2)
  ball.dy = hit * 3.0
  ball.dx, ball.dy = enforce_min_angle(ball.dx, ball.dy)
  sfx_paddle()

  -- Rally milestone: every 5 face hits play C5 then E5 next frame.
  rally_hits = rally_hits + 1
  if rally_hits % 5 == 0 then
    note(0, "C5", 0.05)
    rally_chord_pending = frame() + 1
  end

  return true
end

local function title_update()
  if btnp("left") then
    difficulty_idx = difficulty_idx - 1
    if difficulty_idx < 1 then difficulty_idx = #DIFFICULTIES end
    AI_SPEED = AI_SPEEDS[difficulty_idx]
    note(0, "E4", 0.03)
  end
  if btnp("right") then
    difficulty_idx = difficulty_idx + 1
    if difficulty_idx > #DIFFICULTIES then difficulty_idx = 1 end
    AI_SPEED = AI_SPEEDS[difficulty_idx]
    note(0, "E4", 0.03)
  end
  if btnr("start") or touch_end() then
    begin_match()
  end
end

local function play_update()
  -- Deferred rally chord second note
  if rally_chord_pending and frame() >= rally_chord_pending then
    note(0, "E5", 0.05)
    rally_chord_pending = nil
  end

  if winner then
    if btnr("start") or touch_end() then
      state = "title"
    end
    return
  end

  -- pause toggle
  if btnp("select") then
    paused = not paused
  end
  if paused then return end

  -- Animate orbiting circle obstacles around their anchor.
  for _, ob in ipairs(circle_obs) do
    ob.cy = ob.anchor_y + math.sin(frame() * 0.02 + ob.phase) * 25
  end

  -- player 2 input (right paddle)
  local dy = 0
  local has_input = false
  if btn("up")   then dy = -1; has_input = true end
  if btn("down") then dy =  1; has_input = true end
  if touch() then
    local _, ty = touch_pos()
    local center = p2.y + PH / 2
    if ty < center - 2 then dy = -1 end
    if ty > center + 2 then dy =  1 end
    has_input = true
  end
  -- Attract mode: if no human input, p2 auto-tracks the ball (slower than AI p1)
  if not has_input and ball.dx > 0 then
    local p2_center = p2.y + PH / 2
    if     p2_center < ball.y - 3 then dy = 1
    elseif p2_center > ball.y + 3 then dy = -1 end
  end
  p2.y = p2.y + dy * 3
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
    sfx_wall()
  end
  if ball.y + BS >= SCREEN_H then
    ball.y = SCREEN_H - BS
    ball.dy = -ball.dy
    sfx_wall()
  end

  -- paddle collisions
  paddle_hit(p1, 1)
  paddle_hit(p2, -1)

  -- rect obstacle collision
  for _, ob in ipairs(obstacles) do
    if ball_rect_collide(ball.x, ball.y, BS, ob.x, ob.y, ob.w, ob.h) then
      local prev_x = ball.x - ball.dx
      local from_side = (prev_x < ob.x or prev_x > ob.x + ob.w)
      if from_side then
        ball.dx = -ball.dx * OBS_BOOST
        ball.x = ball.x + ball.dx * 2
      else
        ball.dy = -ball.dy * OBS_BOOST
        ball.y = ball.y + ball.dy * 2
      end
      ball.dx, ball.dy = enforce_min_angle(ball.dx, ball.dy)
      sfx_obstacle()
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
      ball.dx = (ball.dx - 2 * dot * nx) * OBS_BOOST
      ball.dy = (ball.dy - 2 * dot * ny) * OBS_BOOST
      ball.x = ob.cx + nx * min_dist
      ball.y = ob.cy + ny * min_dist
      ball.dx, ball.dy = enforce_min_angle(ball.dx, ball.dy)
      sfx_obstacle()
      break
    end
  end

  -- scoring
  if ball.x < 0 then
    score2 = score2 + 1
    serve_dir = -1
    sfx_score()
    if score2 >= MAX_SCORE then
      winner = "P2"
      wins_total = wins_total + 1
      data_save("pong_wins", wins_total)
      sfx_victory()
    else
      reset_ball(serve_dir)
    end
  end
  if ball.x > SCREEN_W then
    score1 = score1 + 1
    serve_dir = 1
    sfx_score()
    if score1 >= MAX_SCORE then
      winner = "CPU"
      sfx_loss()
    else
      reset_ball(serve_dir)
    end
  end
end

function _update()
  if state == "title" then
    title_update()
  else
    play_update()
  end
end

local function title_draw()
  cls(scr, 0)
  -- Title
  text(scr, "PONG", 80, 20, 15, ALIGN_HCENTER)
  text(scr, "PONG", 81, 20, 8, ALIGN_HCENTER)  -- subtle drop shadow

  text(scr, "DIFFICULTY", 80, 50, 10, ALIGN_HCENTER)

  -- Difficulty options (highlight selected)
  local labels = { "EASY", "NORM", "HARD" }
  local xs = { 40, 80, 120 }
  for i = 1, 3 do
    local col = (i == difficulty_idx) and 15 or 6
    text(scr, labels[i], xs[i], 64, col, ALIGN_HCENTER)
  end
  -- Selection brackets
  local bx = xs[difficulty_idx]
  text(scr, "<", bx - 14, 64, 12, ALIGN_HCENTER)
  text(scr, ">", bx + 14, 64, 12, ALIGN_HCENTER)

  -- Press start (blink)
  if math.floor(frame() / 15) % 2 == 0 then
    text(scr, "PRESS START", 80, 88, 14, ALIGN_HCENTER)
  end

  -- Wins counter
  text(scr, "WINS: " .. wins_total, 80, 102, 8, ALIGN_HCENTER)
end

local function play_draw()
  cls(scr, 0)

  -- center line (dashed)
  for y = 0, SCREEN_H - 1, 6 do
    rectf(scr, 79, y, 2, 3, 3)
  end

  -- rect obstacles
  for _, ob in ipairs(obstacles) do
    rectf(scr, ob.x, ob.y, ob.w, ob.h, 7)
    rect(scr, ob.x, ob.y, ob.w, ob.h, 10)
  end

  -- circle obstacles
  for _, ob in ipairs(circle_obs) do
    circf(scr, ob.cx, ob.cy, ob.r, 7)
    circ(scr, ob.cx, ob.cy, ob.r, 10)
  end

  -- paddles
  rectf(scr, p1.x, p1.y, PW, PH, 12)
  rectf(scr, p2.x, p2.y, PW, PH, 15)

  -- ball
  circf(scr, ball.x, ball.y, BS, 15)

  -- score (centered on each half)
  text(scr, tostring(score1), 40, 4, 8, ALIGN_HCENTER)
  text(scr, tostring(score2), 120, 4, 8, ALIGN_HCENTER)

  -- border
  line(scr, 0, 0, SCREEN_W - 1, 0, 5)
  line(scr, 0, SCREEN_H - 1, SCREEN_W - 1, SCREEN_H - 1, 5)

  -- pause overlay
  if paused then
    text(scr, "PAUSED", 80, 56, 10, ALIGN_HCENTER)
  end

  -- winner screen
  if winner then
    rectf(scr, 30, 36, 100, 50, 0)
    rect(scr, 30, 36, 100, 50, 15)
    text(scr, winner .. " WINS!", 80, 44, 15, ALIGN_HCENTER)
    text(scr, "PRESS START", 80, 60, 8, ALIGN_HCENTER)
    text(scr, "WINS: " .. wins_total, 80, 74, 12, ALIGN_HCENTER)
  end
end

function _draw()
  if state == "title" then
    title_draw()
  else
    play_draw()
  end
end
