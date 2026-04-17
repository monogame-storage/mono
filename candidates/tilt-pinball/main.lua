-- TILT PINBALL
-- Classic pinball with motion tilt control
-- A=left flipper, B=right flipper, Tilt phone to nudge table

------------------------------------------------------------
-- CONSTANTS
------------------------------------------------------------
local W = 160
local H = 120
local GRAVITY = 0.12
local BALL_R = 2
local FLIPPER_LEN = 18
local FLIPPER_REST = 0.4    -- rest angle (radians from horizontal)
local FLIPPER_UP = -0.6     -- activated angle
local FLIPPER_SPEED = 0.25
local TILT_THRESHOLD = 0.7
local TILT_PENALTY_TIME = 90 -- 3 seconds at 30fps
local PLUNGER_MAX = 30
local BUMPER_BOUNCE = 3.5
local FLIPPER_POWER = 4.2
local MAX_BALLS = 3
local TILT_NUDGE = 0.06     -- how much motion affects ball
local WALL_LEFT = 10
local WALL_RIGHT = 150
local WALL_TOP = 8
local DRAIN_Y = 116
local LAUNCH_X = 154
local LAUNCH_Y = 100

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function dist(x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  return math.sqrt(dx * dx + dy * dy)
end
local function dot(x1, y1, x2, y2) return x1 * x2 + y1 * y2 end
local function len(x, y) return math.sqrt(x * x + y * y) end
local function normalize(x, y)
  local l = len(x, y)
  if l < 0.001 then return 0, 0 end
  return x / l, y / l
end

------------------------------------------------------------
-- STATE
------------------------------------------------------------
local state = "title"
local ball = {}
local balls_left = 0
local score = 0
local hi_score = 0
local multiplier = 1
local multi_timer = 0

-- flippers: {x, y, angle, dir} dir=1 for left, -1 for right
local flippers = {}

-- bumpers: {x, y, r, flash}
local bumpers = {}

-- targets: {x, y, w, h, hit, flash}
local targets = {}

-- plunger
local plunger_power = 0
local plunger_charging = false
local ball_in_launcher = false

-- tilt
local tilt_penalty = 0
local tilt_flash = 0
local tilt_accum = 0

-- multi-ball
local extra_balls = {}
local multi_ball_active = false
local combo_count = 0

-- demo/attract mode
local demo_mode = false
local demo_timer = 0
local idle_timer = 0
local IDLE_TIMEOUT = 150  -- 5 seconds to enter demo

-- animation
local anim_frame = 0
local shake_x = 0
local shake_y = 0
local drain_flash = 0

------------------------------------------------------------
-- TABLE LAYOUT
------------------------------------------------------------
local function setup_table()
  -- flippers (positioned near bottom)
  flippers = {
    { x = 52, y = 106, angle = FLIPPER_REST, dir = 1 },   -- left
    { x = 108, y = 106, angle = -FLIPPER_REST, dir = -1 }  -- right
  }

  -- bumpers (circular)
  bumpers = {
    { x = 55, y = 35, r = 7, flash = 0, pts = 100 },
    { x = 80, y = 28, r = 7, flash = 0, pts = 100 },
    { x = 105, y = 35, r = 7, flash = 0, pts = 100 },
    { x = 68, y = 55, r = 5, flash = 0, pts = 50 },
    { x = 92, y = 55, r = 5, flash = 0, pts = 50 },
    { x = 80, y = 48, r = 4, flash = 0, pts = 150 },
  }

  -- score targets (rectangular hit zones)
  targets = {
    { x = 25, y = 25, w = 6, h = 12, hit = false, flash = 0, pts = 200 },
    { x = 129, y = 25, w = 6, h = 12, hit = false, flash = 0, pts = 200 },
    { x = 40, y = 70, w = 4, h = 8, hit = false, flash = 0, pts = 150 },
    { x = 116, y = 70, w = 4, h = 8, hit = false, flash = 0, pts = 150 },
    { x = 77, y = 15, w = 6, h = 4, hit = false, flash = 0, pts = 500 },
  }
end

local function reset_targets()
  for _, t in ipairs(targets) do
    t.hit = false
    t.flash = 0
  end
end

------------------------------------------------------------
-- BALL
------------------------------------------------------------
local function launch_ball()
  ball = {
    x = LAUNCH_X, y = LAUNCH_Y,
    vx = 0, vy = 0,
    active = false
  }
  ball_in_launcher = true
  plunger_power = 0
  plunger_charging = false
end

local function spawn_ball_at(bx, by, bvx, bvy)
  return { x = bx, y = by, vx = bvx, vy = bvy, active = true }
end

------------------------------------------------------------
-- COLLISION
------------------------------------------------------------
local function collide_ball_walls(b)
  -- left wall
  if b.x - BALL_R < WALL_LEFT then
    b.x = WALL_LEFT + BALL_R
    b.vx = math.abs(b.vx) * 0.8
    if tone then tone(2, 800, 600, 0.03) end
  end
  -- right wall (except launcher channel)
  if b.x + BALL_R > WALL_RIGHT then
    if b.y < 85 or b.x > LAUNCH_X + 4 then
      b.x = WALL_RIGHT - BALL_R
      b.vx = -math.abs(b.vx) * 0.8
      if tone then tone(2, 800, 600, 0.03) end
    end
  end
  -- top wall
  if b.y - BALL_R < WALL_TOP then
    b.y = WALL_TOP + BALL_R
    b.vy = math.abs(b.vy) * 0.8
    if tone then tone(2, 900, 700, 0.03) end
  end
  -- launcher channel right wall
  if b.x + BALL_R > W - 2 then
    b.x = W - 2 - BALL_R
    b.vx = -math.abs(b.vx) * 0.6
  end
  -- launcher channel entry (top curve guide to send ball into play)
  if ball_in_launcher == false and b.x > WALL_RIGHT - 4 and b.y < 20 then
    b.vx = -math.abs(b.vx) - 1
    b.vy = math.abs(b.vy) * 0.5
  end
end

local function collide_ball_bumper(b, bump)
  local d = dist(b.x, b.y, bump.x, bump.y)
  local min_d = BALL_R + bump.r
  if d < min_d and d > 0.01 then
    -- push ball away
    local nx, ny = normalize(b.x - bump.x, b.y - bump.y)
    b.x = bump.x + nx * (min_d + 1)
    b.y = bump.y + ny * (min_d + 1)
    -- reflect velocity and boost
    local spd = len(b.vx, b.vy)
    b.vx = nx * math.max(spd, BUMPER_BOUNCE)
    b.vy = ny * math.max(spd, BUMPER_BOUNCE)
    bump.flash = 8
    score = score + bump.pts * multiplier
    combo_count = combo_count + 1
    if combo_count >= 5 then
      multiplier = math.min(multiplier + 1, 5)
      multi_timer = 120
      combo_count = 0
    end
    -- sound
    if tone then tone(0, 600 + bump.pts, 400, 0.06) end
    if tone then tone(1, 1200, 800, 0.03) end
    return true
  end
  return false
end

local function collide_ball_target(b, tgt)
  if tgt.hit then return false end
  if b.x + BALL_R > tgt.x and b.x - BALL_R < tgt.x + tgt.w and
     b.y + BALL_R > tgt.y and b.y - BALL_R < tgt.y + tgt.h then
    tgt.hit = true
    tgt.flash = 12
    score = score + tgt.pts * multiplier
    -- reflect ball
    b.vy = -b.vy
    if tone then tone(0, 1000, 1400, 0.08) end
    -- check if all targets hit
    local all_hit = true
    for _, t in ipairs(targets) do
      if not t.hit then all_hit = false; break end
    end
    if all_hit then
      -- bonus: multi-ball or extra points
      score = score + 2000 * multiplier
      multiplier = math.min(multiplier + 2, 5)
      multi_timer = 180
      -- spawn extra ball for multi-ball
      if not multi_ball_active then
        multi_ball_active = true
        table.insert(extra_balls, spawn_ball_at(80, 50, 1.5, -2))
        if tone then tone(0, 400, 1200, 0.15) end
        if tone then tone(1, 600, 1400, 0.12) end
      end
      reset_targets()
    end
    return true
  end
  return false
end

local function point_to_seg_dist(px, py, ax, ay, bx, by)
  local abx, aby = bx - ax, by - ay
  local apx, apy = px - ax, py - ay
  local t = dot(apx, apy, abx, aby) / (dot(abx, aby, abx, aby) + 0.001)
  t = clamp(t, 0, 1)
  local cx, cy = ax + abx * t, ay + aby * t
  return dist(px, py, cx, cy), cx, cy, t
end

local function collide_ball_flipper(b, fl)
  local ang = fl.angle
  local ex = fl.x + math.cos(ang) * FLIPPER_LEN * fl.dir
  local ey = fl.y + math.sin(ang) * FLIPPER_LEN
  local d, cx, cy, t = point_to_seg_dist(b.x, b.y, fl.x, fl.y, ex, ey)

  if d < BALL_R + 3 and d > 0.01 then
    -- normal from segment to ball
    local nx, ny = normalize(b.x - cx, b.y - cy)
    b.x = cx + nx * (BALL_R + 3.5)
    b.y = cy + ny * (BALL_R + 3.5)

    -- flipper moving up? add power
    local is_active = (fl.dir == 1 and fl.angle < FLIPPER_REST - 0.1)
                   or (fl.dir == -1 and fl.angle > -FLIPPER_REST + 0.1)
    local power = is_active and FLIPPER_POWER or 1.0
    -- launch angle: mostly upward, slightly outward
    local launch_nx, launch_ny = nx, -math.abs(ny) * 1.2
    local ln = len(launch_nx, launch_ny)
    if ln > 0.01 then
      launch_nx, launch_ny = launch_nx / ln, launch_ny / ln
    end
    b.vx = launch_nx * power + fl.dir * t * 1.5
    b.vy = launch_ny * power
    if is_active then
      if tone then tone(2, 300, 150, 0.04) end
    end
    return true
  end
  return false
end

-- guide rails (diagonal walls near the drain)
local function collide_guide_rails(b)
  -- left guide rail
  local d1, cx1, cy1 = point_to_seg_dist(b.x, b.y, WALL_LEFT, 95, 40, 112)
  if d1 < BALL_R + 1 then
    local nx, ny = normalize(b.x - cx1, b.y - cy1)
    b.x = cx1 + nx * (BALL_R + 2)
    b.y = cy1 + ny * (BALL_R + 2)
    local ref = dot(b.vx, b.vy, nx, ny)
    b.vx = b.vx - 1.6 * ref * nx
    b.vy = b.vy - 1.6 * ref * ny
  end
  -- right guide rail
  local d2, cx2, cy2 = point_to_seg_dist(b.x, b.y, WALL_RIGHT, 95, 120, 112)
  if d2 < BALL_R + 1 then
    local nx, ny = normalize(b.x - cx2, b.y - cy2)
    b.x = cx2 + nx * (BALL_R + 2)
    b.y = cy2 + ny * (BALL_R + 2)
    local ref = dot(b.vx, b.vy, nx, ny)
    b.vx = b.vx - 1.6 * ref * nx
    b.vy = b.vy - 1.6 * ref * ny
  end
end

------------------------------------------------------------
-- GAME LOGIC
------------------------------------------------------------
local function update_ball_physics(b)
  -- gravity
  b.vy = b.vy + GRAVITY

  -- motion tilt
  if tilt_penalty <= 0 then
    if motion_enabled and motion_enabled() then
      local mx = motion_x()
      local my = motion_y()
      b.vx = b.vx + mx * TILT_NUDGE
      b.vy = b.vy + my * TILT_NUDGE * 0.5
    else
      -- keyboard fallback
      if btn("left") then b.vx = b.vx - TILT_NUDGE * 4 end
      if btn("right") then b.vx = b.vx + TILT_NUDGE * 4 end
    end
  end

  -- friction
  b.vx = b.vx * 0.998
  b.vy = b.vy * 0.998

  -- speed cap
  local spd = len(b.vx, b.vy)
  if spd > 6 then
    b.vx = b.vx / spd * 6
    b.vy = b.vy / spd * 6
  end

  -- move
  b.x = b.x + b.vx
  b.y = b.y + b.vy

  -- collisions
  collide_ball_walls(b)
  for _, bump in ipairs(bumpers) do
    collide_ball_bumper(b, bump)
  end
  for _, tgt in ipairs(targets) do
    collide_ball_target(b, tgt)
  end
  collide_guide_rails(b)
  if tilt_penalty <= 0 then
    for _, fl in ipairs(flippers) do
      collide_ball_flipper(b, fl)
    end
  end
end

local function check_drain(b)
  return b.y > DRAIN_Y
end

local function update_flippers()
  local la = (tilt_penalty <= 0) and (btn("a") or (demo_mode and demo_flip_l()))
  local ra = (tilt_penalty <= 0) and (btn("b") or (demo_mode and demo_flip_r()))

  -- left flipper
  if la then
    flippers[1].angle = flippers[1].angle - FLIPPER_SPEED
    if flippers[1].angle < FLIPPER_UP then flippers[1].angle = FLIPPER_UP end
  else
    flippers[1].angle = flippers[1].angle + FLIPPER_SPEED * 0.7
    if flippers[1].angle > FLIPPER_REST then flippers[1].angle = FLIPPER_REST end
  end
  -- right flipper
  if ra then
    flippers[2].angle = flippers[2].angle + FLIPPER_SPEED
    if flippers[2].angle > -FLIPPER_UP then flippers[2].angle = -FLIPPER_UP end
  else
    flippers[2].angle = flippers[2].angle - FLIPPER_SPEED * 0.7
    if flippers[2].angle < -FLIPPER_REST then flippers[2].angle = -FLIPPER_REST end
  end
end

local function check_tilt()
  if not motion_enabled or not motion_enabled() then return end
  local mx = math.abs(motion_x())
  local my = math.abs(motion_y())
  local intensity = math.max(mx, my)
  if intensity > TILT_THRESHOLD then
    tilt_accum = tilt_accum + intensity
  else
    tilt_accum = math.max(0, tilt_accum - 0.05)
  end
  if tilt_accum > 2.0 and tilt_penalty <= 0 then
    -- TILT!
    tilt_penalty = TILT_PENALTY_TIME
    tilt_flash = 30
    tilt_accum = 0
    if tone then tone(0, 200, 80, 0.3) end
    if tone then tone(1, 150, 50, 0.3) end
    shake_x = 4
    shake_y = 2
  end
end

------------------------------------------------------------
-- DEMO AI
------------------------------------------------------------
local demo_ai_timer = 0
local demo_ai_action = 0

function demo_flip_l()
  if ball.active and ball.y > 85 and ball.x < 80 then return true end
  return demo_ai_action == 1
end

function demo_flip_r()
  if ball.active and ball.y > 85 and ball.x >= 80 then return true end
  return demo_ai_action == 2
end

local function update_demo_ai()
  demo_ai_timer = demo_ai_timer + 1
  if demo_ai_timer > 20 then
    demo_ai_timer = 0
    demo_ai_action = math.random(0, 3)
  end
  -- auto-launch
  if ball_in_launcher then
    plunger_power = plunger_power + 1
    if plunger_power >= PLUNGER_MAX * 0.8 then
      ball.vy = -plunger_power * 0.15
      ball.vx = -0.5
      ball.active = true
      ball_in_launcher = false
      plunger_power = 0
      if tone then tone(0, 200, 600, 0.1) end
    end
  end
end

------------------------------------------------------------
-- INIT
------------------------------------------------------------
function _init()
  mode(1)
  hi_score = 0
end

function _start()
  go("title")
end

------------------------------------------------------------
-- TITLE SCENE
------------------------------------------------------------
function title_init()
  idle_timer = 0
  demo_mode = false
  anim_frame = 0
end

function title_update()
  anim_frame = anim_frame + 1

  if btnp("start") or btnp("a") or btnp("b") then
    if demo_mode then
      demo_mode = false
      idle_timer = 0
      return
    end
    go("game")
    return
  end

  -- enter demo mode after idle
  if not demo_mode then
    idle_timer = idle_timer + 1
    if idle_timer > IDLE_TIMEOUT then
      demo_mode = true
      setup_table()
      launch_ball()
      ball.vy = -3.5
      ball.vx = -0.5
      ball.active = true
      ball_in_launcher = false
      score = 0
      balls_left = 3
      tilt_penalty = 0
      extra_balls = {}
      multi_ball_active = false
      multiplier = 1
    end
  else
    -- run demo game
    update_demo_ai()
    update_flippers()
    if ball.active then
      update_ball_physics(ball)
      if check_drain(ball) then
        launch_ball()
        ball.vy = -3.5
        ball.vx = -0.5
        ball.active = true
        ball_in_launcher = false
      end
    end
    -- update bumper/target flash
    for _, b in ipairs(bumpers) do
      if b.flash > 0 then b.flash = b.flash - 1 end
    end
    for _, t in ipairs(targets) do
      if t.flash > 0 then t.flash = t.flash - 1 end
    end
  end
end

function title_draw()
  local s = screen()
  cls(s, 0)

  if demo_mode then
    draw_table(s)
    draw_ball(s, ball)
    -- overlay "DEMO" text
    if anim_frame % 40 < 25 then
      rectf(s, 54, 55, 52, 11, 0)
      text(s, "- DEMO -", 56, 57, 1)
    end
    text(s, "PRESS START", 44, 2, 1)
  else
    -- title screen
    rectf(s, 20, 15, 120, 30, 1)
    rectf(s, 22, 17, 116, 26, 0)
    text(s, "TILT PINBALL", 40, 22, 1)
    if anim_frame % 40 < 28 then
      text(s, "PRESS START", 44, 34, 1)
    end

    -- draw decorative pinball
    circf(s, 80, 65, 6, 1)
    circf(s, 80, 65, 4, 0)
    circf(s, 80, 65, 2, 1)

    -- instructions
    text(s, "A=LEFT FLIP", 20, 82, 1)
    text(s, "B=RIGHT FLIP", 86, 82, 1)
    text(s, "TILT TO NUDGE", 42, 94, 1)

    if hi_score > 0 then
      text(s, "HI:" .. hi_score, 56, 108, 1)
    end
  end
end

------------------------------------------------------------
-- GAME SCENE
------------------------------------------------------------
function game_init()
  setup_table()
  score = 0
  balls_left = MAX_BALLS
  multiplier = 1
  multi_timer = 0
  combo_count = 0
  tilt_penalty = 0
  tilt_flash = 0
  tilt_accum = 0
  extra_balls = {}
  multi_ball_active = false
  demo_mode = false
  drain_flash = 0
  shake_x = 0
  shake_y = 0
  anim_frame = 0
  reset_targets()
  launch_ball()
end

function game_update()
  anim_frame = anim_frame + 1

  -- tilt penalty countdown
  if tilt_penalty > 0 then
    tilt_penalty = tilt_penalty - 1
    if tilt_flash > 0 then tilt_flash = tilt_flash - 1 end
  end

  -- multiplier timer
  if multi_timer > 0 then
    multi_timer = multi_timer - 1
    if multi_timer <= 0 then
      multiplier = math.max(1, multiplier - 1)
    end
  end

  -- screen shake decay
  shake_x = shake_x * 0.8
  shake_y = shake_y * 0.8
  if math.abs(shake_x) < 0.3 then shake_x = 0 end
  if math.abs(shake_y) < 0.3 then shake_y = 0 end

  -- drain flash
  if drain_flash > 0 then drain_flash = drain_flash - 1 end

  -- check tilt
  check_tilt()

  -- flippers
  update_flippers()

  -- plunger
  if ball_in_launcher then
    if btn("a") or btn("b") or btnp("start") then
      plunger_charging = true
    end
    if plunger_charging then
      plunger_power = plunger_power + 0.8
      if plunger_power > PLUNGER_MAX then plunger_power = PLUNGER_MAX end
      -- release
      if not btn("a") and not btn("b") and not btn("start") then
        ball.vy = -plunger_power * 0.15
        ball.vx = -0.5
        ball.active = true
        ball_in_launcher = false
        plunger_charging = false
        if tone then tone(0, 200, 600, 0.1) end
      end
    end
  end

  -- ball physics
  if ball.active then
    update_ball_physics(ball)
    if check_drain(ball) then
      ball.active = false
      balls_left = balls_left - 1
      drain_flash = 15
      shake_y = 3
      if tone then tone(0, 400, 100, 0.2) end
      if tone then tone(1, 300, 80, 0.15) end
      if balls_left <= 0 and #extra_balls == 0 then
        if score > hi_score then hi_score = score end
        go("gameover")
        return
      end
      if #extra_balls > 0 then
        -- promote an extra ball
        ball = table.remove(extra_balls, 1)
      else
        launch_ball()
      end
    end
  end

  -- extra balls physics
  for i = #extra_balls, 1, -1 do
    local eb = extra_balls[i]
    update_ball_physics(eb)
    if check_drain(eb) then
      table.remove(extra_balls, i)
    end
  end
  if #extra_balls == 0 then multi_ball_active = false end

  -- update bumper/target flash
  for _, b in ipairs(bumpers) do
    if b.flash > 0 then b.flash = b.flash - 1 end
  end
  for _, t in ipairs(targets) do
    if t.flash > 0 then t.flash = t.flash - 1 end
  end
end

------------------------------------------------------------
-- DRAWING
------------------------------------------------------------
function draw_table(s)
  -- playfield border
  rect(s, WALL_LEFT - 1, WALL_TOP - 1, WALL_RIGHT - WALL_LEFT + 2, DRAIN_Y - WALL_TOP + 2, 1)

  -- launcher channel
  line(s, WALL_RIGHT, 85, WALL_RIGHT, DRAIN_Y, 1)
  line(s, W - 2, WALL_TOP, W - 2, DRAIN_Y, 1)

  -- guide rails
  line(s, WALL_LEFT, 95, 40, 112, 1)
  line(s, WALL_RIGHT, 95, 120, 112, 1)

  -- bumpers
  for _, b in ipairs(bumpers) do
    if b.flash > 0 and b.flash % 2 == 0 then
      circf(s, b.x, b.y, b.r + 1, 1)
      circf(s, b.x, b.y, b.r - 1, 0)
    else
      circ(s, b.x, b.y, b.r, 1)
      -- inner dot
      circf(s, b.x, b.y, 1, 1)
    end
  end

  -- targets
  for _, t in ipairs(targets) do
    if t.hit then
      -- dithered (hit marker)
      rect(s, t.x, t.y, t.w, t.h, 1)
    else
      if t.flash > 0 and t.flash % 2 == 0 then
        rectf(s, t.x - 1, t.y - 1, t.w + 2, t.h + 2, 1)
      else
        rectf(s, t.x, t.y, t.w, t.h, 1)
      end
    end
  end

  -- flippers
  for _, fl in ipairs(flippers) do
    local ex = fl.x + math.cos(fl.angle) * FLIPPER_LEN * fl.dir
    local ey = fl.y + math.sin(fl.angle) * FLIPPER_LEN
    line(s, fl.x, fl.y, ex, ey, 1)
    -- thicken flipper
    line(s, fl.x, fl.y - 1, ex, ey - 1, 1)
    line(s, fl.x, fl.y + 1, ex, ey + 1, 1)
    -- pivot dot
    circf(s, fl.x, fl.y, 2, 1)
  end

  -- plunger
  if ball_in_launcher then
    local py = LAUNCH_Y + 8 + plunger_power * 0.3
    rectf(s, LAUNCH_X - 2, py, 5, 4, 1)
    line(s, LAUNCH_X, LAUNCH_Y + 6, LAUNCH_X, py, 1)
    -- power indicator
    if plunger_charging then
      local bars = math.floor(plunger_power / PLUNGER_MAX * 5)
      for i = 0, bars do
        rectf(s, LAUNCH_X + 4, LAUNCH_Y + 8 - i * 3, 2, 2, 1)
      end
    end
  end

  -- drain zone markers
  if drain_flash > 0 and drain_flash % 3 < 2 then
    line(s, WALL_LEFT, DRAIN_Y, WALL_RIGHT, DRAIN_Y, 1)
  end
end

function draw_ball(s, b)
  if not b.active and not ball_in_launcher then return end
  local bx = ball_in_launcher and b.x or b.x
  local by = ball_in_launcher and b.y or b.y
  circf(s, math.floor(bx), math.floor(by), BALL_R, 1)
  -- highlight dot
  pix(s, math.floor(bx) - 1, math.floor(by) - 1, 0)
end

function draw_hud(s)
  -- score
  rectf(s, 0, 0, W, 7, 0)
  text(s, tostring(score), 2, 1, 1)

  -- balls left indicator
  for i = 1, balls_left do
    circf(s, W - 6 - (i - 1) * 7, 4, 2, 1)
  end

  -- multiplier
  if multiplier > 1 then
    local mtxt = "x" .. multiplier
    if multi_timer > 0 and multi_timer % 10 < 6 then
      text(s, mtxt, 70, 1, 1)
    elseif multi_timer <= 0 then
      text(s, mtxt, 70, 1, 1)
    end
  end

  -- tilt warning
  if tilt_penalty > 0 then
    if tilt_flash > 0 and tilt_flash % 4 < 2 then
      rectf(s, 52, 50, 56, 20, 1)
      rectf(s, 54, 52, 52, 16, 0)
      text(s, "!! TILT !!", 56, 56, 1)
    elseif tilt_penalty % 8 < 5 then
      text(s, "TILT", 68, 1, 1)
    end
  end

  -- multi-ball indicator
  if multi_ball_active then
    if anim_frame % 8 < 5 then
      text(s, "MULTI", 2, H - 6, 1)
    end
  end
end

function game_draw()
  local s = screen()
  cls(s, 0)

  -- apply screen shake
  local ox = math.floor(shake_x * (math.random() * 2 - 1))
  local oy = math.floor(shake_y * (math.random() * 2 - 1))

  -- Note: shake is visual only via offset drawing
  -- For simplicity we just draw normally (the low-res makes shake subtle)

  draw_table(s)
  draw_ball(s, ball)

  -- extra balls
  for _, eb in ipairs(extra_balls) do
    -- draw extra balls with slightly different look
    circf(s, math.floor(eb.x), math.floor(eb.y), BALL_R, 1)
  end

  draw_hud(s)
end

------------------------------------------------------------
-- GAME OVER SCENE
------------------------------------------------------------
local go_timer = 0

function gameover_init()
  go_timer = 0
end

function gameover_update()
  go_timer = go_timer + 1
  if go_timer > 60 and (btnp("start") or btnp("a") or btnp("b")) then
    go("title")
  end
  -- auto return to title after 10 seconds
  if go_timer > 300 then
    go("title")
  end
end

function gameover_draw()
  local s = screen()
  cls(s, 0)

  rectf(s, 25, 25, 110, 70, 1)
  rectf(s, 27, 27, 106, 66, 0)

  text(s, "GAME OVER", 48, 32, 1)

  text(s, "SCORE", 60, 46, 1)
  text(s, tostring(score), 60, 56, 1)

  if score >= hi_score and score > 0 then
    if go_timer % 20 < 14 then
      text(s, "NEW HIGH SCORE!", 34, 68, 1)
    end
  else
    text(s, "BEST:" .. hi_score, 50, 68, 1)
  end

  if go_timer > 60 and go_timer % 30 < 20 then
    text(s, "PRESS START", 44, 82, 1)
  end
end
