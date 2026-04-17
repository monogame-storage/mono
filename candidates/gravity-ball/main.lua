-- GRAVITY BALL
-- Tilt to change gravity direction, collect stars, avoid spikes!

------------------------------------------------------------
-- CONSTANTS
------------------------------------------------------------
local W = 160
local H = 120
local BALL_R = 3
local GRAVITY = 0.12
local MAX_VEL = 3.0
local FRICTION = 0.985
local BOUNCE = 0.5
local JUMP_VEL = 2.8
local STAR_R = 3
local SPIKE_R = 3
local DEMO_IDLE = 180  -- frames before demo starts

------------------------------------------------------------
-- STATE
------------------------------------------------------------
local ball = {}
local gx, gy = 0, 1  -- gravity direction
local walls = {}
local stars = {}
local spikes = {}
local movers = {}     -- moving platforms
local particles = {}
local level = 1
local max_level = 10
local lives = 3
local score = 0
local hi_score = 0
local paused = false
local game_over = false
local level_complete = false
local level_timer = 0
local flash = 0
local invuln = 0

-- demo / attract
local demo_mode = false
local demo_timer = 0
local idle_timer = 0
local scene = "title"
local S  -- current screen surface for drawing

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function dist(x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  return math.sqrt(dx * dx + dy * dy)
end
local function lerp(a, b, t) return a + (b - a) * t end

local function spawn_particles(x, y, col, count)
  for i = 1, (count or 6) do
    local a = math.random() * 6.283
    local sp = 0.5 + math.random() * 1.5
    particles[#particles + 1] = {
      x = x, y = y,
      vx = math.cos(a) * sp,
      vy = math.sin(a) * sp,
      life = 15 + math.random(10),
      col = 1
    }
  end
end

local function update_particles()
  for i = #particles, 1, -1 do
    local p = particles[i]
    p.x = p.x + p.vx
    p.y = p.y + p.vy
    p.life = p.life - 1
    if p.life <= 0 then
      table.remove(particles, i)
    end
  end
end

local function draw_particles()
  for _, p in ipairs(particles) do
    pix(S, p.x, p.y, p.col)
  end
end

------------------------------------------------------------
-- LEVEL DATA
------------------------------------------------------------
local function make_wall(x, y, w, h)
  return { x = x, y = y, w = w, h = h }
end

local function make_star(x, y)
  return { x = x, y = y, collected = false }
end

local function make_spike(x, y)
  return { x = x, y = y }
end

local function make_mover(x, y, w, h, dx, dy, range)
  return { x = x, y = y, w = w, h = h, dx = dx, dy = dy, range = range, ox = x, oy = y, t = 0 }
end

local function build_border()
  -- border walls (always present)
  walls[#walls + 1] = make_wall(0, 0, W, 3)      -- top
  walls[#walls + 1] = make_wall(0, H - 3, W, 3)  -- bottom
  walls[#walls + 1] = make_wall(0, 0, 3, H)       -- left
  walls[#walls + 1] = make_wall(W - 3, 0, 3, H)   -- right
end

local function load_level(n)
  walls = {}
  stars = {}
  spikes = {}
  movers = {}
  particles = {}
  level_complete = false
  level_timer = 0
  flash = 0
  invuln = 60

  ball.x = 20
  ball.y = 60
  ball.vx = 0
  ball.vy = 0

  build_border()

  if n == 1 then
    -- simple intro
    walls[#walls + 1] = make_wall(50, 70, 60, 5)
    stars[#stars + 1] = make_star(80, 40)
    stars[#stars + 1] = make_star(120, 80)
    stars[#stars + 1] = make_star(40, 100)

  elseif n == 2 then
    walls[#walls + 1] = make_wall(40, 50, 5, 40)
    walls[#walls + 1] = make_wall(80, 30, 5, 50)
    walls[#walls + 1] = make_wall(120, 60, 5, 40)
    stars[#stars + 1] = make_star(60, 30)
    stars[#stars + 1] = make_star(100, 70)
    stars[#stars + 1] = make_star(140, 40)
    spikes[#spikes + 1] = make_spike(60, 80)

  elseif n == 3 then
    walls[#walls + 1] = make_wall(30, 40, 40, 5)
    walls[#walls + 1] = make_wall(90, 60, 40, 5)
    walls[#walls + 1] = make_wall(50, 85, 60, 5)
    stars[#stars + 1] = make_star(50, 25)
    stars[#stars + 1] = make_star(110, 45)
    stars[#stars + 1] = make_star(80, 100)
    stars[#stars + 1] = make_star(30, 75)
    spikes[#spikes + 1] = make_spike(70, 55)
    spikes[#spikes + 1] = make_spike(130, 80)

  elseif n == 4 then
    walls[#walls + 1] = make_wall(60, 20, 5, 50)
    walls[#walls + 1] = make_wall(100, 50, 5, 50)
    walls[#walls + 1] = make_wall(30, 70, 50, 5)
    movers[#movers + 1] = make_mover(70, 80, 25, 5, 1, 0, 40)
    stars[#stars + 1] = make_star(40, 30)
    stars[#stars + 1] = make_star(80, 60)
    stars[#stars + 1] = make_star(130, 30)
    stars[#stars + 1] = make_star(120, 100)
    spikes[#spikes + 1] = make_spike(45, 55)
    spikes[#spikes + 1] = make_spike(90, 35)

  elseif n == 5 then
    -- maze-like
    walls[#walls + 1] = make_wall(25, 25, 5, 70)
    walls[#walls + 1] = make_wall(50, 10, 5, 60)
    walls[#walls + 1] = make_wall(75, 40, 5, 70)
    walls[#walls + 1] = make_wall(100, 10, 5, 60)
    walls[#walls + 1] = make_wall(125, 40, 5, 70)
    stars[#stars + 1] = make_star(37, 20)
    stars[#stars + 1] = make_star(63, 90)
    stars[#stars + 1] = make_star(87, 25)
    stars[#stars + 1] = make_star(113, 90)
    stars[#stars + 1] = make_star(145, 30)
    spikes[#spikes + 1] = make_spike(37, 60)
    spikes[#spikes + 1] = make_spike(87, 70)
    spikes[#spikes + 1] = make_spike(113, 40)

  elseif n == 6 then
    walls[#walls + 1] = make_wall(40, 35, 80, 5)
    walls[#walls + 1] = make_wall(20, 65, 80, 5)
    walls[#walls + 1] = make_wall(60, 95, 80, 5)
    movers[#movers + 1] = make_mover(120, 35, 25, 5, 0, 1, 25)
    movers[#movers + 1] = make_mover(10, 50, 25, 5, 0, -1, 20)
    stars[#stars + 1] = make_star(80, 20)
    stars[#stars + 1] = make_star(50, 50)
    stars[#stars + 1] = make_star(110, 80)
    stars[#stars + 1] = make_star(30, 105)
    stars[#stars + 1] = make_star(140, 50)
    spikes[#spikes + 1] = make_spike(70, 60)
    spikes[#spikes + 1] = make_spike(100, 30)
    spikes[#spikes + 1] = make_spike(40, 90)

  elseif n == 7 then
    -- lots of small platforms
    walls[#walls + 1] = make_wall(20, 30, 20, 4)
    walls[#walls + 1] = make_wall(55, 25, 20, 4)
    walls[#walls + 1] = make_wall(90, 35, 20, 4)
    walls[#walls + 1] = make_wall(120, 20, 20, 4)
    walls[#walls + 1] = make_wall(35, 55, 20, 4)
    walls[#walls + 1] = make_wall(70, 60, 20, 4)
    walls[#walls + 1] = make_wall(105, 55, 20, 4)
    walls[#walls + 1] = make_wall(25, 85, 20, 4)
    walls[#walls + 1] = make_wall(60, 90, 20, 4)
    walls[#walls + 1] = make_wall(95, 80, 20, 4)
    walls[#walls + 1] = make_wall(130, 85, 20, 4)
    stars[#stars + 1] = make_star(30, 20)
    stars[#stars + 1] = make_star(100, 25)
    stars[#stars + 1] = make_star(45, 45)
    stars[#stars + 1] = make_star(80, 50)
    stars[#stars + 1] = make_star(65, 80)
    stars[#stars + 1] = make_star(140, 75)
    spikes[#spikes + 1] = make_spike(65, 20)
    spikes[#spikes + 1] = make_spike(110, 50)
    spikes[#spikes + 1] = make_spike(30, 75)
    spikes[#spikes + 1] = make_spike(100, 90)

  elseif n == 8 then
    -- moving platform gauntlet
    walls[#walls + 1] = make_wall(70, 10, 5, 100)
    movers[#movers + 1] = make_mover(20, 30, 30, 5, 0, 1, 30)
    movers[#movers + 1] = make_mover(20, 70, 30, 5, 0, -1, 25)
    movers[#movers + 1] = make_mover(100, 25, 30, 5, 0, 1, 35)
    movers[#movers + 1] = make_mover(100, 65, 30, 5, 0, -1, 30)
    stars[#stars + 1] = make_star(35, 15)
    stars[#stars + 1] = make_star(35, 55)
    stars[#stars + 1] = make_star(35, 100)
    stars[#stars + 1] = make_star(115, 15)
    stars[#stars + 1] = make_star(115, 55)
    stars[#stars + 1] = make_star(115, 100)
    spikes[#spikes + 1] = make_spike(50, 45)
    spikes[#spikes + 1] = make_spike(50, 85)
    spikes[#spikes + 1] = make_spike(90, 40)
    spikes[#spikes + 1] = make_spike(90, 80)

  elseif n == 9 then
    -- spiral corridors
    walls[#walls + 1] = make_wall(20, 20, 120, 4)
    walls[#walls + 1] = make_wall(20, 20, 4, 50)
    walls[#walls + 1] = make_wall(40, 45, 100, 4)
    walls[#walls + 1] = make_wall(136, 45, 4, 30)
    walls[#walls + 1] = make_wall(40, 71, 100, 4)
    walls[#walls + 1] = make_wall(20, 71, 4, 30)
    walls[#walls + 1] = make_wall(40, 97, 100, 4)
    movers[#movers + 1] = make_mover(80, 30, 20, 4, 1, 0, 30)
    stars[#stars + 1] = make_star(130, 33)
    stars[#stars + 1] = make_star(50, 58)
    stars[#stars + 1] = make_star(130, 83)
    stars[#stars + 1] = make_star(50, 108)
    stars[#stars + 1] = make_star(130, 108)
    spikes[#spikes + 1] = make_spike(80, 33)
    spikes[#spikes + 1] = make_spike(100, 58)
    spikes[#spikes + 1] = make_spike(80, 83)
    spikes[#spikes + 1] = make_spike(70, 108)

  elseif n >= 10 then
    -- final challenge
    walls[#walls + 1] = make_wall(30, 20, 4, 80)
    walls[#walls + 1] = make_wall(55, 20, 4, 60)
    walls[#walls + 1] = make_wall(80, 40, 4, 60)
    walls[#walls + 1] = make_wall(105, 20, 4, 60)
    walls[#walls + 1] = make_wall(130, 40, 4, 60)
    movers[#movers + 1] = make_mover(35, 50, 18, 4, 0, 1, 25)
    movers[#movers + 1] = make_mover(60, 40, 18, 4, 0, -1, 20)
    movers[#movers + 1] = make_mover(85, 60, 18, 4, 0, 1, 25)
    movers[#movers + 1] = make_mover(110, 35, 18, 4, 0, -1, 20)
    stars[#stars + 1] = make_star(15, 15)
    stars[#stars + 1] = make_star(42, 90)
    stars[#stars + 1] = make_star(68, 25)
    stars[#stars + 1] = make_star(92, 100)
    stars[#stars + 1] = make_star(118, 25)
    stars[#stars + 1] = make_star(145, 100)
    stars[#stars + 1] = make_star(145, 15)
    spikes[#spikes + 1] = make_spike(42, 40)
    spikes[#spikes + 1] = make_spike(68, 70)
    spikes[#spikes + 1] = make_spike(92, 40)
    spikes[#spikes + 1] = make_spike(118, 70)
    spikes[#spikes + 1] = make_spike(145, 55)
  end
end

------------------------------------------------------------
-- COLLISION
------------------------------------------------------------
local function ball_vs_rect(bx, by, br, rx, ry, rw, rh)
  -- closest point on rect to ball center
  local cx = clamp(bx, rx, rx + rw)
  local cy = clamp(by, ry, ry + rh)
  local dx = bx - cx
  local dy = by - cy
  local d2 = dx * dx + dy * dy
  return d2 < br * br, cx, cy, dx, dy, d2
end

local function resolve_ball_walls()
  for _, w in ipairs(walls) do
    local hit, cx, cy, dx, dy, d2 = ball_vs_rect(ball.x, ball.y, BALL_R, w.x, w.y, w.w, w.h)
    if hit then
      local d = math.sqrt(d2)
      if d < 0.001 then
        -- ball center inside wall, push out based on gravity
        ball.x = ball.x - gx * 2
        ball.y = ball.y - gy * 2
      else
        local nx = dx / d
        local ny = dy / d
        -- push out
        ball.x = cx + nx * BALL_R
        ball.y = cy + ny * BALL_R
        -- reflect velocity
        local dot = ball.vx * nx + ball.vy * ny
        if dot < 0 then
          ball.vx = ball.vx - (1 + BOUNCE) * dot * nx
          ball.vy = ball.vy - (1 + BOUNCE) * dot * ny
        end
      end
    end
  end

  -- also check movers
  for _, m in ipairs(movers) do
    local hit, cx, cy, dx, dy, d2 = ball_vs_rect(ball.x, ball.y, BALL_R, m.x, m.y, m.w, m.h)
    if hit then
      local d = math.sqrt(d2)
      if d < 0.001 then
        ball.x = ball.x - gx * 2
        ball.y = ball.y - gy * 2
      else
        local nx = dx / d
        local ny = dy / d
        ball.x = cx + nx * BALL_R
        ball.y = cy + ny * BALL_R
        local dot = ball.vx * nx + ball.vy * ny
        if dot < 0 then
          ball.vx = ball.vx - (1 + BOUNCE) * dot * nx
          ball.vy = ball.vy - (1 + BOUNCE) * dot * ny
        end
      end
    end
  end
end

------------------------------------------------------------
-- INPUT
------------------------------------------------------------
local function get_tilt()
  if motion_enabled() then
    return motion_x(), motion_y()
  end
  -- fallback to d-pad / axes
  local tx, ty = axis_x(), axis_y()
  if btn("left") then tx = -1 end
  if btn("right") then tx = 1 end
  if btn("up") then ty = -1 end
  if btn("down") then ty = 1 end
  return tx, ty
end

------------------------------------------------------------
-- DEMO AI
------------------------------------------------------------
local demo_target_idx = 0

local function demo_get_tilt()
  -- aim toward nearest uncollected star
  local best_d = 9999
  local tx, ty = 0, 0.5
  for i, s in ipairs(stars) do
    if not s.collected then
      local d = dist(ball.x, ball.y, s.x, s.y)
      if d < best_d then
        best_d = d
        local dx = s.x - ball.x
        local dy = s.y - ball.y
        local len = math.max(d, 0.01)
        tx = dx / len
        ty = dy / len
      end
    end
  end
  -- avoid spikes: nudge away
  for _, sp in ipairs(spikes) do
    local d = dist(ball.x, ball.y, sp.x, sp.y)
    if d < 20 then
      local repel = (20 - d) / 20
      local dx = ball.x - sp.x
      local dy = ball.y - sp.y
      local len = math.max(d, 0.01)
      tx = tx + (dx / len) * repel * 0.5
      ty = ty + (dy / len) * repel * 0.5
    end
  end
  -- normalize
  local len = math.sqrt(tx * tx + ty * ty)
  if len > 0.01 then
    tx = tx / len
    ty = ty / len
  end
  return tx, ty
end

------------------------------------------------------------
-- GAME LOGIC
------------------------------------------------------------
local function update_movers()
  for _, m in ipairs(movers) do
    m.t = m.t + 1
    local phase = math.sin(m.t * 0.03)
    m.x = m.ox + m.dx * phase * m.range
    m.y = m.oy + m.dy * phase * m.range
  end
end

local function check_stars()
  local all_done = true
  for _, s in ipairs(stars) do
    if not s.collected then
      if dist(ball.x, ball.y, s.x, s.y) < BALL_R + STAR_R then
        s.collected = true
        score = score + 100
        spawn_particles(s.x, s.y, 14, 8)
        if note then note(0, "C5", 4) end
        if note then note(1, "E5", 4) end
      else
        all_done = false
      end
    end
  end
  if all_done and #stars > 0 then
    level_complete = true
    level_timer = 60
    if note then note(0, "C5", 6) end
    if note then note(1, "E5", 6) end
    if note then note(0, "G5", 6) end
  end
end

local function check_spikes()
  if invuln > 0 then return end
  for _, s in ipairs(spikes) do
    if dist(ball.x, ball.y, s.x, s.y) < BALL_R + SPIKE_R then
      lives = lives - 1
      invuln = 90
      spawn_particles(ball.x, ball.y, 8, 12)
      cam_shake(4)
      noise(0, 0.4)
      tone(0, 200, 80, 0.3)
      if lives <= 0 then
        game_over = true
        if score > hi_score then
          hi_score = score
        end
      else
        -- respawn ball at start
        ball.x = 20
        ball.y = 60
        ball.vx = 0
        ball.vy = 0
      end
      return
    end
  end
end

local function update_game()
  if game_over then
    if btnp("a") or btnp("start") then
      lives = 3
      score = 0
      level = 1
      game_over = false
      load_level(level)
    end
    update_particles()
    return
  end

  if level_complete then
    level_timer = level_timer - 1
    update_particles()
    if level_timer <= 0 then
      level = level + 1
      if level > max_level then
        -- won the game!
        game_over = true
        score = score + 1000
        if score > hi_score then
          hi_score = score
        end
      else
        -- bonus life every 3 levels
        if level % 3 == 1 then
          lives = math.min(lives + 1, 5)
        end
        load_level(level)
      end
    end
    return
  end

  -- get gravity from tilt
  local tx, ty
  if demo_mode then
    tx, ty = demo_get_tilt()
  else
    tx, ty = get_tilt()
  end

  -- apply dead zone
  if math.abs(tx) < 0.08 then tx = 0 end
  if math.abs(ty) < 0.08 then ty = 0 end

  gx = tx
  gy = ty

  -- gravity
  ball.vx = ball.vx + gx * GRAVITY
  ball.vy = ball.vy + gy * GRAVITY

  -- jump (push against gravity)
  if btnp("a") and not demo_mode then
    local gl = math.sqrt(gx * gx + gy * gy)
    if gl > 0.1 then
      ball.vx = ball.vx - (gx / gl) * JUMP_VEL
      ball.vy = ball.vy - (gy / gl) * JUMP_VEL
      tone(0, 400, 600, 0.15)
    end
  end

  -- friction
  ball.vx = ball.vx * FRICTION
  ball.vy = ball.vy * FRICTION

  -- clamp velocity
  ball.vx = clamp(ball.vx, -MAX_VEL, MAX_VEL)
  ball.vy = clamp(ball.vy, -MAX_VEL, MAX_VEL)

  -- move
  ball.x = ball.x + ball.vx
  ball.y = ball.y + ball.vy

  -- update movers
  update_movers()

  -- collision
  resolve_ball_walls()

  -- keep in bounds
  ball.x = clamp(ball.x, BALL_R + 3, W - BALL_R - 3)
  ball.y = clamp(ball.y, BALL_R + 3, H - BALL_R - 3)

  -- check pickups
  check_stars()
  if not level_complete then
    check_spikes()
  end

  -- invulnerability countdown
  if invuln > 0 then invuln = invuln - 1 end

  update_particles()
  flash = flash + 1
end

------------------------------------------------------------
-- DRAWING
------------------------------------------------------------
local function draw_arrow()
  -- draw gravity arrow indicator in corner
  local ax = 14
  local ay = 14
  local gl = math.sqrt(gx * gx + gy * gy)
  if gl > 0.1 then
    local nx = gx / gl * 8
    local ny = gy / gl * 8
    line(S, ax, ay, ax + nx, ay + ny, 1)
    -- arrowhead
    pix(S, ax + nx, ay + ny, 1)
  end
  circ(S, ax, ay, 9, 1)
end

local function draw_walls()
  for _, w in ipairs(walls) do
    rectf(S, w.x, w.y, w.w, w.h, 1)
    rect(S, w.x, w.y, w.w, w.h, 1)
  end
end

local function draw_movers()
  for _, m in ipairs(movers) do
    rectf(S, m.x, m.y, m.w, m.h, 1)
    rect(S, m.x, m.y, m.w, m.h, 1)
  end
end

local function draw_stars()
  for _, s in ipairs(stars) do
    if not s.collected then
      local blink = math.sin(flash * 0.1) * 0.5 + 0.5
      local col = blink > 0.3 and 1 or 0
      -- draw star shape
      circf(S, s.x, s.y, 2, 1)
      pix(S, s.x, s.y - 3, 1)
      pix(S, s.x, s.y + 3, 1)
      pix(S, s.x - 3, s.y, 1)
      pix(S, s.x + 3, s.y, 1)
    end
  end
end

local function draw_spikes()
  for _, s in ipairs(spikes) do
    -- draw spike as small diamond
    local blink = 1
    line(S, s.x, s.y - SPIKE_R, s.x + SPIKE_R, s.y, blink)
    line(S, s.x + SPIKE_R, s.y, s.x, s.y + SPIKE_R, blink)
    line(S, s.x, s.y + SPIKE_R, s.x - SPIKE_R, s.y, blink)
    line(S, s.x - SPIKE_R, s.y, s.x, s.y - SPIKE_R, blink)
  end
end

local function draw_ball()
  if invuln > 0 and math.floor(invuln / 3) % 2 == 0 then
    return  -- blink when invulnerable
  end
  circf(S, ball.x, ball.y, BALL_R, 1)
  circ(S, ball.x, ball.y, BALL_R, 1)
  -- highlight
  pix(S, ball.x - 1, ball.y - 1, 0)
end

local function draw_hud()
  -- lives
  for i = 1, lives do
    circf(S, W - 8 * i, 6, 2, 1)
  end
  -- score
  text(S, tostring(score), 4, H - 10, 1)
  -- level
  text(S, "LV" .. level, W - 22, H - 10, 1)
end

local function draw_game()
  S = screen()
  -- background: subtle gradient based on gravity direction
  local bg = 0
  cls(S, bg)

  -- subtle gravity-direction background grid
  for gx_line = 0, W, 10 do
    line(S, gx_line, 0, gx_line, H, 1)
  end
  for gy_line = 0, H, 10 do
    line(S, 0, gy_line, W, gy_line, 1)
  end

  draw_walls()
  draw_movers()
  draw_stars()
  draw_spikes()
  draw_ball()
  draw_particles()
  draw_arrow()
  draw_hud()

  if level_complete then
    rectf(S, 30, 45, 100, 30, 0)
    rect(S, 30, 45, 100, 30, 1)
    if level >= max_level then
      text(S, "YOU WIN!", 80, 55, 1, ALIGN_CENTER)
      text(S, "SCORE: " .. score, 80, 65, 1, ALIGN_CENTER)
    else
      text(S, "LEVEL CLEAR!", 80, 55, 1, ALIGN_CENTER)
      text(S, "+" .. 100 .. " pts", 80, 65, 1, ALIGN_CENTER)
    end
  end

  if game_over then
    rectf(S, 30, 35, 100, 50, 0)
    rect(S, 30, 35, 100, 50, 1)
    text(S, "GAME OVER", 80, 42, 1, ALIGN_CENTER)
    text(S, "SCORE: " .. score, 80, 55, 1, ALIGN_CENTER)
    text(S, "BEST: " .. hi_score, 80, 65, 1, ALIGN_CENTER)
    text(S, "PRESS A", 80, 78, 1, ALIGN_CENTER)
  end

  if paused then
    rectf(S, 50, 50, 60, 20, 0)
    rect(S, 50, 50, 60, 20, 1)
    text(S, "PAUSED", 80, 57, 1, ALIGN_CENTER)
  end

  if demo_mode then
    text(S, "DEMO", 80, 4, 1, ALIGN_CENTER)
  end
end

------------------------------------------------------------
-- TITLE SCENE
------------------------------------------------------------
local title_anim = 0

local function title_init()
  title_anim = 0
  idle_timer = 0
  demo_mode = false
end

local function title_update()
  title_anim = title_anim + 1
  idle_timer = idle_timer + 1

  if btnp("start") or btnp("a") then
    if demo_mode then
      demo_mode = false
      idle_timer = 0
      return
    end
    scene = "game"
    lives = 3
    score = 0
    level = 1
    game_over = false
    demo_mode = false
    load_level(level)
    if note then note(0, "C4", 4) end
    return
  end

  -- start demo after idle
  if not demo_mode and idle_timer >= DEMO_IDLE then
    demo_mode = true
    lives = 99
    score = 0
    level = 1
    game_over = false
    load_level(level)
    demo_timer = 0
  end

  if demo_mode then
    update_game()
    demo_timer = demo_timer + 1
    -- end demo after a while or on any button
    if demo_timer > 600 or btnp("b") or btnp("up") or btnp("down") or btnp("left") or btnp("right") then
      demo_mode = false
      idle_timer = 0
      scene = "title"
    end
  end
end

local function title_draw()
  S = screen()
  cls(S, 0)

  if demo_mode then
    draw_game()
    -- overlay title
    rectf(S, 20, 5, 120, 18, 0)
    text(S, "GRAVITY BALL", 80, 8, 1, ALIGN_CENTER)
    text(S, "DEMO", 80, 17, 1, ALIGN_CENTER)
    return
  end

  -- animated background
  for i = 0, 15 do
    local t = title_anim * 0.02 + i * 0.4
    local bx = 80 + math.cos(t) * 50
    local by = 60 + math.sin(t * 0.7) * 35
    circ(S, bx, by, 2 + math.sin(t * 2), 1)
  end

  -- title
  local bounce = math.sin(title_anim * 0.08) * 3
  text(S, "GRAVITY BALL", 80, 25 + bounce, 1, ALIGN_CENTER)

  -- subtitle
  text(S, "Tilt to control gravity!", 80, 45, 1, ALIGN_CENTER)

  -- bouncing ball animation
  local bx = 80 + math.cos(title_anim * 0.05) * 30
  local by = 75 + math.sin(title_anim * 0.07) * 15
  circf(S, bx, by, BALL_R, 1)
  circ(S, bx, by, BALL_R, 1)

  -- instructions
  if math.floor(title_anim / 30) % 2 == 0 then
    text(S, "PRESS A TO START", 80, 100, 1, ALIGN_CENTER)
  end

  -- high score
  if hi_score > 0 then
    text(S, "HI: " .. hi_score, 80, 112, 1, ALIGN_CENTER)
  end
end

------------------------------------------------------------
-- GAME SCENE
------------------------------------------------------------
local function game_init()
  -- already set up by title transition
end

local function game_update()
  -- pause
  if btnp("start") and not demo_mode then
    paused = not paused
    return
  end
  if paused then return end

  update_game()

  -- back to title on game over + wait
  if game_over and btnp("b") then
    scene = "title"
    title_init()
  end
end

local function game_draw()
  draw_game()
end

------------------------------------------------------------
-- MAIN CALLBACKS
------------------------------------------------------------
function _init()
  mode(1)
  hi_score = 0
end

function _start()
  scene = "title"
  title_init()
end

function _update()
  if scene == "title" then
    title_update()
  elseif scene == "game" then
    game_update()
  end
end

function _draw()
  if scene == "title" then
    title_draw()
  elseif scene == "game" then
    game_draw()
  end
end
