-- Title Scene with Attract/Demo Mode
local scene = {}
local timer = 0
local idle_timer = 0
local IDLE_THRESHOLD = 90  -- ~3 seconds at 30fps
local DEMO_DURATION = 300  -- ~10 seconds at 30fps

-- Demo mode state
local demo_active = false
local demo_timer = 0
local demo_player = {}
local demo_enemies_list = {}
local demo_coins_list = {}
local demo_particles = {}

-- Simulated input script for demo: {frame, action}
-- Actions: "right", "left", "jump", "dash", "idle"
local demo_script = {
  {0, "right"}, {15, "jump"}, {20, "right"}, {45, "jump"},
  {55, "right"}, {70, "left"}, {80, "jump"}, {90, "right"},
  {100, "dash"}, {110, "right"}, {130, "jump"}, {140, "right"},
  {155, "left"}, {165, "jump"}, {175, "right"}, {190, "jump"},
  {200, "right"}, {215, "dash"}, {225, "left"}, {240, "jump"},
  {250, "right"}, {265, "jump"}, {275, "right"}, {290, "idle"},
}

----------------------------------------------------------------
-- DEMO SIMULATION (simplified physics for attract mode)
----------------------------------------------------------------
local DEMO_GRAV = 0.3
local DEMO_MAX_FALL = 3.5
local DEMO_RUN_SPEED = 1.4
local DEMO_JUMP_VEL = -3.2

-- Simple demo level layout: platforms and coins for visual interest
local demo_platforms = {
  {x=0,   y=105, w=160, h=15},  -- ground
  {x=20,  y=85,  w=30,  h=4},
  {x=65,  y=75,  w=25,  h=4},
  {x=100, y=65,  w=30,  h=4},
  {x=40,  y=55,  w=25,  h=4},
  {x=110, y=85,  w=35,  h=4},
  {x=5,   y=68,  w=20,  h=4},
}

local demo_coin_positions = {
  {x=35, y=78}, {x=78, y=68}, {x=115, y=58},
  {x=52, y=48}, {x=125, y=78}, {x=15, y=60},
}

local function demo_init()
  demo_timer = 0
  demo_player = {
    x = 20, y = 95, vx = 0, vy = 0,
    w = 5, h = 7, on_ground = false,
    facing = 1, dashing = 0, dash_timer = 0,
    anim = 0
  }
  demo_enemies_list = {
    {x = 80, y = 98, dir = 1, w = 6, h = 7, anim = 0, alive = true},
    {x = 130, y = 78, dir = -1, w = 6, h = 7, anim = 0, alive = true},
  }
  demo_coins_list = {}
  for _, cp in ipairs(demo_coin_positions) do
    table.insert(demo_coins_list, {x = cp.x, y = cp.y, collected = false, anim = math.random() * 6.28})
  end
  demo_particles = {}
end

local function demo_check_platform(x, y, w, h)
  for _, plat in ipairs(demo_platforms) do
    if x + w > plat.x and x < plat.x + plat.w and
       y + h > plat.y and y < plat.y + plat.h then
      return plat
    end
  end
  return nil
end

local function demo_spawn_particle(x, y, vx, vy, life, c)
  if #demo_particles < 60 then
    table.insert(demo_particles, {x=x, y=y, vx=vx, vy=vy, life=life, max_life=life, c=c})
  end
end

local function demo_get_action()
  local action = "idle"
  for i = #demo_script, 1, -1 do
    if demo_timer >= demo_script[i][1] then
      action = demo_script[i][2]
      break
    end
  end
  return action
end

local function demo_update()
  demo_timer = demo_timer + 1
  local dp = demo_player
  dp.anim = dp.anim + 1

  -- Loop demo indefinitely: restart script when sequence ends
  if demo_timer >= DEMO_DURATION then
    demo_init()
  end

  local action = demo_get_action()

  -- Dashing
  if dp.dashing > 0 then
    dp.dashing = dp.dashing - 1
    dp.x = dp.x + dp.facing * 3.5
    -- Trail particles
    demo_spawn_particle(dp.x + dp.w/2, dp.y + dp.h/2, -dp.facing * 0.5, 0, 5, 12)
    if dp.dashing <= 0 then
      dp.vx = dp.facing * 0.5
    end
  else
    -- Horizontal movement
    if action == "right" or action == "dash" then
      dp.vx = DEMO_RUN_SPEED
      dp.facing = 1
    elseif action == "left" then
      dp.vx = -DEMO_RUN_SPEED
      dp.facing = -1
    else
      dp.vx = dp.vx * 0.85
      if math.abs(dp.vx) < 0.1 then dp.vx = 0 end
    end

    -- Jump
    if action == "jump" and dp.on_ground then
      dp.vy = DEMO_JUMP_VEL
      dp.on_ground = false
      demo_spawn_particle(dp.x + dp.w/2, dp.y + dp.h, -1, -0.5, 6, 8)
      demo_spawn_particle(dp.x + dp.w/2, dp.y + dp.h, 1, -0.5, 6, 8)
    end

    -- Dash
    if action == "dash" and dp.dash_timer <= 0 then
      dp.dashing = 5
      dp.dash_timer = 20
      dp.vy = 0
      demo_spawn_particle(dp.x + dp.w/2, dp.y + dp.h/2, 0, 0, 8, 15)
    end

    -- Gravity
    dp.vy = dp.vy + DEMO_GRAV
    if dp.vy > DEMO_MAX_FALL then dp.vy = DEMO_MAX_FALL end

    -- Move X
    dp.x = dp.x + dp.vx

    -- Move Y
    dp.on_ground = false
    local new_y = dp.y + dp.vy
    local plat = demo_check_platform(dp.x, new_y, dp.w, dp.h)
    if plat and dp.vy > 0 then
      dp.y = plat.y - dp.h
      dp.vy = 0
      dp.on_ground = true
      -- Landing dust
      if dp.vy ~= 0 then
        demo_spawn_particle(dp.x + dp.w/2, dp.y + dp.h, -0.5, -0.3, 5, 8)
        demo_spawn_particle(dp.x + dp.w/2, dp.y + dp.h, 0.5, -0.3, 5, 8)
      end
    else
      dp.y = new_y
    end
  end

  -- Dash cooldown
  if dp.dash_timer > 0 then dp.dash_timer = dp.dash_timer - 1 end

  -- Screen wrap
  if dp.x > 160 then dp.x = -dp.w end
  if dp.x < -dp.w then dp.x = 160 end
  -- Fall reset
  if dp.y > 130 then
    dp.x = 20
    dp.y = 95
    dp.vy = 0
    dp.vx = 0
  end

  -- Coin collection
  for _, c in ipairs(demo_coins_list) do
    if not c.collected then
      c.anim = c.anim + 0.08
      local dx = (dp.x + dp.w/2) - c.x
      local dy = (dp.y + dp.h/2) - c.y
      if math.abs(dx) < 8 and math.abs(dy) < 8 then
        c.collected = true
        for j = 1, 5 do
          local a = math.random() * 6.28
          demo_spawn_particle(c.x, c.y, math.cos(a)*1.5, math.sin(a)*1.5, 8, 15)
        end
      end
    end
  end

  -- Enemy movement
  for _, e in ipairs(demo_enemies_list) do
    if e.alive then
      e.anim = e.anim + 1
      e.x = e.x + 0.4 * e.dir
      -- Bounce off edges
      if e.x < 5 or e.x > 150 then e.dir = -e.dir end

      -- Check stomp by demo player
      if dp.vy > 0 and dp.dashing <= 0 and
         dp.x + dp.w > e.x and dp.x < e.x + e.w and
         dp.y + dp.h > e.y and dp.y + dp.h < e.y + 5 then
        e.alive = false
        dp.vy = -2.5
        for j = 1, 6 do
          local a = math.random() * 6.28
          demo_spawn_particle(e.x + e.w/2, e.y + e.h/2, math.cos(a)*2, math.sin(a)*2, 8, 12)
        end
      end
      -- Check dash kill
      if dp.dashing > 0 and
         dp.x + dp.w > e.x and dp.x < e.x + e.w and
         dp.y + dp.h > e.y and dp.y < e.y + e.h then
        e.alive = false
        for j = 1, 6 do
          local a = math.random() * 6.28
          demo_spawn_particle(e.x + e.w/2, e.y + e.h/2, math.cos(a)*2, math.sin(a)*2, 8, 12)
        end
      end
    end
  end

  -- Particle update
  for i = #demo_particles, 1, -1 do
    local p = demo_particles[i]
    p.x = p.x + p.vx
    p.y = p.y + p.vy
    p.vy = p.vy + 0.04
    p.vx = p.vx * 0.95
    p.life = p.life - 1
    if p.life <= 0 then
      table.remove(demo_particles, i)
    end
  end
end

----------------------------------------------------------------
-- 7-SEGMENT CLOCK DISPLAY (HH:MM) for demo mode
----------------------------------------------------------------
-- Segment map:  _a_
--              |   |
--              f   b
--              |_g_|
--              |   |
--              e   c
--              |_d_|
-- Each digit ~7px wide x 11px tall, segment thickness 2px
local seg_digits = {
  [0] = {a=true, b=true, c=true, d=true, e=true, f=true,  g=false},
  [1] = {a=false,b=true, c=true, d=false,e=false,f=false, g=false},
  [2] = {a=true, b=true, c=false,d=true, e=true, f=false, g=true},
  [3] = {a=true, b=true, c=true, d=true, e=false,f=false, g=true},
  [4] = {a=false,b=true, c=true, d=false,e=false,f=true,  g=true},
  [5] = {a=true, b=false,c=true, d=true, e=false,f=true,  g=true},
  [6] = {a=true, b=false,c=true, d=true, e=true, f=true,  g=true},
  [7] = {a=true, b=true, c=true, d=false,e=false,f=false, g=false},
  [8] = {a=true, b=true, c=true, d=true, e=true, f=true,  g=true},
  [9] = {a=true, b=true, c=true, d=true, e=false,f=true,  g=true},
}

local function draw_7seg_digit(sx, sy, digit, col)
  local scr = screen()
  local s = seg_digits[digit]
  if not s then return end
  -- segment a: top horizontal
  if s.a then rectf(scr, sx + 2, sy, 3, 2, col) end
  -- segment b: top-right vertical
  if s.b then rectf(scr, sx + 5, sy + 2, 2, 3, col) end
  -- segment c: bottom-right vertical
  if s.c then rectf(scr, sx + 5, sy + 7, 2, 3, col) end
  -- segment d: bottom horizontal
  if s.d then rectf(scr, sx + 2, sy + 9, 3, 2, col) end
  -- segment e: bottom-left vertical
  if s.e then rectf(scr, sx, sy + 7, 2, 3, col) end
  -- segment f: top-left vertical
  if s.f then rectf(scr, sx, sy + 2, 2, 3, col) end
  -- segment g: middle horizontal
  if s.g then rectf(scr, sx + 2, sy + 5, 3, 1, col) end
end

local function draw_clock(ox, oy, col)
  local scr = screen()
  local d = date()
  local h = d.hour
  local m = d.min
  local d1 = math.floor(h / 10)
  local d2 = h % 10
  local d3 = math.floor(m / 10)
  local d4 = m % 10
  draw_7seg_digit(ox, oy, d1, col)
  draw_7seg_digit(ox + 9, oy, d2, col)
  -- colon: blinks every 30 frames
  if math.floor(frame() / 30) % 2 == 0 then
    rectf(scr, ox + 18, oy + 3, 2, 2, col)
    rectf(scr, ox + 18, oy + 7, 2, 2, col)
  end
  draw_7seg_digit(ox + 22, oy, d3, col)
  draw_7seg_digit(ox + 31, oy, d4, col)
end

local function demo_draw()
  local scr = screen()
  cls(scr, 0)

  -- Background stars
  for i = 1, 20 do
    local bx = (i * 37 + demo_timer) % W
    local by = (i * 23 + demo_timer * 0.3) % H
    if math.sin(demo_timer * 0.05 + i) > 0 then
      pix(scr, math.floor(bx), math.floor(by), 3)
    end
  end

  -- Platforms
  for _, plat in ipairs(demo_platforms) do
    rectf(scr, plat.x, plat.y, plat.w, plat.h, 6)
    line(scr, plat.x, plat.y, plat.x + plat.w - 1, plat.y, 8)
    line(scr, plat.x, plat.y + plat.h - 1, plat.x + plat.w - 1, plat.y + plat.h - 1, 4)
  end

  -- Coins
  for _, c in ipairs(demo_coins_list) do
    if not c.collected then
      circf(scr, math.floor(c.x), math.floor(c.y), 3, 4)
      circf(scr, math.floor(c.x), math.floor(c.y), 2, 13)
      pix(scr, math.floor(c.x), math.floor(c.y), 15)
    end
  end

  -- Enemies
  for _, e in ipairs(demo_enemies_list) do
    if e.alive then
      local ex = math.floor(e.x)
      local ey = math.floor(e.y)
      rectf(scr, ex, ey, e.w, e.h, 10)
      rectf(scr, ex+1, ey+1, e.w-2, 2, 12)
      local eye_off = e.dir > 0 and (e.w - 2) or 1
      pix(scr, ex + eye_off, ey + 2, 0)
    end
  end

  -- Player
  local dp = demo_player
  local px = math.floor(dp.x)
  local py = math.floor(dp.y)
  if dp.dashing > 0 then
    rectf(scr, px, py, dp.w, dp.h, 15)
    rectf(scr, px - dp.facing * 4, py, dp.w, dp.h, 8)
  else
    rectf(scr, px, py, dp.w, dp.h, 14)
    rectf(scr, px, py, dp.w, 3, 15)
    local eye_x = dp.facing > 0 and (px + dp.w - 2) or (px + 1)
    pix(scr, eye_x, py + 1, 0)
    -- Running animation
    if dp.on_ground and math.abs(dp.vx) > 0.3 then
      local foot = math.floor(dp.anim / 4) % 2
      if foot == 0 then
        pix(scr, px + 1, py + dp.h, 10)
      else
        pix(scr, px + dp.w - 2, py + dp.h, 10)
      end
    end
  end

  -- Particles
  for _, p in ipairs(demo_particles) do
    local alpha = p.life / p.max_life
    local c = math.max(1, math.floor(p.c * alpha))
    pix(scr, math.floor(p.x), math.floor(p.y), c)
  end

  -- "DEMO" label top
  rectf(scr, 0, 0, W, 9, 1)
  text(scr, "DEMO", 66, 1, 8)

  -- 7-segment clock in top-right corner (dim color 3)
  draw_clock(W - 40, 0, 3)

  -- Overlay: PRESS START (always blinking)
  local overlay_y = 110
  if math.floor(demo_timer / 15) % 2 == 0 then
    text(scr, "PRESS START", 42, overlay_y, 15)
  else
    text(scr, "PRESS START", 42, overlay_y, 8)
  end
end

----------------------------------------------------------------
-- TITLE SCENE
----------------------------------------------------------------
function scene.init()
  timer = 0
  idle_timer = 0
  demo_active = false
end

function scene.update()
  timer = timer + 1

  -- Check for any input to reset idle timer
  local any_input = btnp("start") or btnp("a") or btnp("b") or
                    btn("left") or btn("right") or btn("up") or btn("down")

  if demo_active then
    -- Exit demo on ANY button press
    if any_input then
      sfx_menu_select()
      demo_active = false
      idle_timer = 0
      timer = 0
      -- If start was pressed, go straight to gameplay
      if btnp("start") then
        G.score = 0
        G.lives = 3
        G.cur_level = 1
        G.coins_collected = 0
        load_level(G.cur_level)
        init_bg()
        go("play")
        return
      end
      -- Otherwise return to title screen
      return
    end
    demo_update()
    return
  end

  -- Normal title mode
  idle_timer = idle_timer + 1
  if any_input then
    idle_timer = 0
  end

  if btnp("start") then
    sfx_menu_select()
    G.score = 0
    G.lives = 3
    G.cur_level = 1
    G.coins_collected = 0
    load_level(G.cur_level)
    init_bg()
    go("play")
    return
  end

  -- Enter demo mode after idle threshold
  if idle_timer >= IDLE_THRESHOLD then
    demo_active = true
    demo_init()
  end
end

function scene.draw()
  if demo_active then
    demo_draw()
    return
  end

  local scr = screen()
  cls(scr, 0)

  -- Animated background particles
  for i = 1, 30 do
    local bx = (i * 37 + timer) % W
    local by = (i * 23 + timer * 0.5) % H
    local bc = 2 + (i % 3)
    pix(scr, math.floor(bx), math.floor(by), bc)
  end

  -- Ground decoration
  rectf(scr, 0, 105, W, 15, 3)
  rectf(scr, 0, 104, W, 1, 5)
  -- Some terrain bumps
  for i = 0, 19 do
    local bh = math.floor(math.sin(i * 0.7) * 3 + 3)
    rectf(scr, i * 8, 105 - bh, 8, bh, 4)
    pix(scr, i * 8, 104 - bh, 6)
    pix(scr, i * 8 + 1, 104 - bh, 6)
  end

  -- Title text with shadow
  text(scr, "SHADOW", 49, 20, 4)
  text(scr, "SHADOW", 48, 19, 15)

  text(scr, "LEAP", 60, 32, 4)
  text(scr, "LEAP", 59, 31, 15)

  -- Decorative line
  line(scr, 30, 42, 130, 42, 6)
  line(scr, 30, 43, 130, 43, 3)

  -- Animated character preview
  local demo_y = 55 + math.floor(math.sin(timer * 0.08) * 3)
  -- Shadow
  rectf(scr, 77, demo_y + 9, 7, 2, 3)
  -- Character body
  rectf(scr, 78, demo_y, 5, 7, 14)
  rectf(scr, 78, demo_y, 5, 3, 15)
  pix(scr, 81, demo_y + 1, 0)

  -- Platform under character
  rectf(scr, 70, demo_y + 9, 20, 4, 6)
  line(scr, 70, demo_y + 9, 89, demo_y + 9, 8)

  -- Coins around character
  local coin_t = timer * 0.05
  for i = 0, 2 do
    local cx = 78 + math.floor(math.cos(coin_t + i * 2.1) * 18)
    local cy = demo_y + 3 + math.floor(math.sin(coin_t + i * 2.1) * 8)
    circf(scr, cx, cy, 2, 13)
    pix(scr, cx, cy, 15)
  end

  -- Controls info
  text(scr, "ARROWS: MOVE", 38, 78, 7)
  text(scr, "A: JUMP  B: DASH", 30, 87, 7)

  -- Blinking start prompt
  if math.floor(timer / 15) % 2 == 0 then
    text(scr, "PRESS START", 42, 97, 15)
  else
    text(scr, "PRESS START", 42, 97, 8)
  end
end

return scene
