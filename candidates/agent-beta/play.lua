-- Play Scene
local scene = {}

-- Sub-states for play scene
local PS_PLAYING   = "playing"
local PS_DYING     = "dying"
local PS_LEVELCLEAR = "levelclear"

local play_state = PS_PLAYING
local state_timer = 0
local level_name_timer = 0

----------------------------------------------------------------
-- PLAYER MOVEMENT
----------------------------------------------------------------
local function move_dash()
  P.dashing = P.dashing - 1
  local dx = P.dash_dir * DASH_VEL

  local new_x = P.x + dx
  if not check_solid(new_x, P.y, P.w, P.h) then
    P.x = new_x
  else
    P.dashing = 0
    P.vx = 0
  end

  -- Trail particles
  spawn_particle(
    P.x + P.w/2 + math.random(-2, 2),
    P.y + P.h/2 + math.random(-2, 2),
    -P.dash_dir * 0.5, 0, 5, 12
  )

  if P.dashing <= 0 then
    P.vx = P.dash_dir * MAX_RUN * 0.5
  end
end

local function move_player()
  if not P.alive then return end
  if P.dashing > 0 then return move_dash() end

  -- Horizontal input
  local mx = 0
  if btn("left") then mx = -1; P.facing = -1 end
  if btn("right") then mx = 1; P.facing = 1 end

  -- Horizontal acceleration
  if mx ~= 0 then
    P.vx = P.vx + mx * RUN_ACCEL
    if math.abs(P.vx) > MAX_RUN then
      P.vx = mx * MAX_RUN
    end
  else
    if math.abs(P.vx) < RUN_DECEL then
      P.vx = 0
    elseif P.vx > 0 then
      P.vx = P.vx - RUN_DECEL
    else
      P.vx = P.vx + RUN_DECEL
    end
  end

  -- Wall sliding
  P.on_wall = 0
  if not P.on_ground and P.vy > 0 then
    if mx == -1 and check_solid(P.x - 1, P.y, P.w, P.h) then
      P.on_wall = -1
    elseif mx == 1 and check_solid(P.x + 1, P.y, P.w, P.h) then
      P.on_wall = 1
    end
  end

  if P.on_wall ~= 0 then
    if P.vy > WALL_SLIDE then
      P.vy = WALL_SLIDE
    end
    -- Wall slide particles and sound
    if frame() % 3 == 0 then
      local wx = P.on_wall > 0 and (P.x + P.w) or P.x
      spawn_particle(wx, P.y + P.h/2, -P.on_wall * 0.3, -0.5, 4, 6)
    end
    if frame() % 8 == 0 then
      sfx_wall_slide()
    end
  end

  -- Gravity
  P.vy = P.vy + GRAV
  if P.vy > MAX_FALL then P.vy = MAX_FALL end

  -- Coyote time
  if P.on_ground then
    P.coyote = COYOTE
  else
    P.coyote = P.coyote - 1
  end

  -- Jump buffer
  if btnp("a") then
    P.jump_buf = JUMP_BUF
  else
    P.jump_buf = P.jump_buf - 1
  end

  -- Jump execution
  if P.jump_buf > 0 then
    if P.coyote > 0 then
      P.vy = JUMP_VEL
      P.coyote = 0
      P.jump_buf = 0
      P.on_ground = false
      P.stretch = 4
      sfx_jump()
      spawn_dust(P.x + P.w/2, P.y + P.h, P.facing)
    elseif P.on_wall ~= 0 then
      P.vy = WALL_JUMP_Y
      P.vx = -P.on_wall * WALL_JUMP_X
      P.facing = -P.on_wall
      P.on_wall = 0
      P.jump_buf = 0
      P.stretch = 4
      sfx_jump()
      spawn_burst(P.x + P.w/2, P.y + P.h/2, 4, 1.5, 10)
    end
  end

  -- Variable jump height
  if not btn("a") and P.vy < JUMP_CUT then
    P.vy = JUMP_CUT
  end

  -- Dash
  if btnp("b") and P.dash_cd <= 0 then
    P.dashing = DASH_DUR
    P.dash_cd = DASH_CD
    P.dash_dir = P.facing
    P.vy = 0
    sfx_dash()
    spawn_burst(P.x + P.w/2, P.y + P.h/2, 6, 2.0, 12)
  end
  if P.dash_cd > 0 then P.dash_cd = P.dash_cd - 1 end

  -- Horizontal collision
  local new_x = P.x + P.vx
  if not check_solid(new_x, P.y, P.w, P.h) then
    P.x = new_x
  else
    local step = P.vx > 0 and 0.5 or -0.5
    local limit = 0
    while not check_solid(P.x + step, P.y, P.w, P.h) and limit < 10 do
      P.x = P.x + step
      limit = limit + 1
    end
    P.vx = 0
  end

  -- Vertical collision
  local was_in_air = not P.on_ground
  local new_y = P.y + P.vy
  P.on_ground = false
  if not check_solid(P.x, new_y, P.w, P.h) then
    P.y = new_y
  else
    if P.vy > 0 then
      local limit = 0
      while not check_solid(P.x, P.y + 0.5, P.w, P.h) and limit < 20 do
        P.y = P.y + 0.5
        limit = limit + 1
      end
      P.on_ground = true
      if was_in_air and P.vy > 1.5 then
        P.squash = 4
        sfx_land()
        spawn_dust(P.x + P.w/2, P.y + P.h, -1)
        spawn_dust(P.x + P.w/2, P.y + P.h, 1)
      end
    elseif P.vy < 0 then
      local limit = 0
      while not check_solid(P.x, P.y - 0.5, P.w, P.h) and limit < 20 do
        P.y = P.y - 0.5
        limit = limit + 1
      end
    end
    P.vy = 0
  end

  -- Invulnerability
  if P.invuln > 0 then P.invuln = P.invuln - 1 end

  -- Animation
  P.anim = P.anim + 1
  if P.squash > 0 then P.squash = P.squash - 1 end
  if P.stretch > 0 then P.stretch = P.stretch - 1 end
end

----------------------------------------------------------------
-- ENEMY AI
----------------------------------------------------------------
local function update_enemies()
  for _, e in ipairs(enemies) do
    if not e.alive then goto continue end
    e.anim = e.anim + 1

    if e.type == E_PATROL then
      e.x = e.x + e.vx * e.dir
      local ahead_x = e.dir > 0 and (e.x + e.w + 1) or (e.x - 1)
      local below_x = e.dir > 0 and (e.x + e.w) or (e.x)
      if solid_at(ahead_x, e.y + e.h/2) or not solid_at(below_x, e.y + e.h + 1) then
        e.dir = -e.dir
      end
      e.vy = e.vy + GRAV
      if e.vy > MAX_FALL then e.vy = MAX_FALL end
      if solid_at(e.x + e.w/2, e.y + e.h + 1) then
        e.vy = 0
      end
      e.y = e.y + e.vy
      if solid_at(e.x + e.w/2, e.y + e.h) then
        e.y = math.floor((e.y + e.h) / TILE) * TILE - e.h
        e.vy = 0
      end

    elseif e.type == E_JUMPER then
      e.x = e.x + e.vx * e.dir
      local ahead_x = e.dir > 0 and (e.x + e.w + 1) or (e.x - 1)
      local below_x = e.dir > 0 and (e.x + e.w) or (e.x)
      if solid_at(ahead_x, e.y + e.h/2) or not solid_at(below_x, e.y + e.h + 1) then
        e.dir = -e.dir
      end
      e.jump_timer = e.jump_timer + 1
      if e.jump_timer > 60 and solid_at(e.x + e.w/2, e.y + e.h + 1) then
        e.vy = -3.0
        e.jump_timer = 0
      end
      e.vy = e.vy + GRAV
      if e.vy > MAX_FALL then e.vy = MAX_FALL end
      e.y = e.y + e.vy
      if solid_at(e.x + e.w/2, e.y + e.h) then
        e.y = math.floor((e.y + e.h) / TILE) * TILE - e.h
        e.vy = 0
      end

    elseif e.type == E_FLYER then
      e.x = e.x + 0.4 * e.dir
      e.y = e.base_y + math.sin(e.anim * 0.05) * 12
      if solid_at(e.x + e.w + 1, e.y + e.h/2) or solid_at(e.x - 1, e.y + e.h/2) then
        e.dir = -e.dir
      end
      if math.abs(e.x - e.start_x) > 40 then
        e.dir = -e.dir
      end
    end

    ::continue::
  end
end

----------------------------------------------------------------
-- INTERACTIONS
----------------------------------------------------------------
local function kill_player()
  if not P.alive then return end
  P.alive = false
  sfx_die()
  cam_shake(5)
  spawn_burst(P.x + P.w/2, P.y + P.h/2, 15, 3.0, 15)
  G.lives = G.lives - 1
  play_state = PS_DYING
  state_timer = 0
end

local function check_coins_collect()
  local px, py = P.x + P.w/2, P.y + P.h/2
  for _, c in ipairs(coins) do
    if not c.collected then
      local dx = px - c.x
      local dy = py - c.y
      if math.abs(dx) < 6 and math.abs(dy) < 6 then
        c.collected = true
        G.coins_collected = G.coins_collected + 1
        G.score = G.score + 100
        sfx_coin()
        spawn_burst(c.x, c.y, 6, 1.5, 15)
      end
    end
  end
end

local function check_springs_bounce()
  for _, s in ipairs(springs) do
    if P.x + P.w > s.x and P.x < s.x + TILE and
       P.y + P.h >= s.y and P.y + P.h <= s.y + 4 and P.vy >= 0 then
      P.vy = -5.5
      P.on_ground = false
      P.coyote = 0
      s.anim = 6
      sfx_spring()
      spawn_burst(s.x + TILE/2, s.y, 4, 1.0, 15)
    end
    if s.anim > 0 then s.anim = s.anim - 1 end
  end
end

local function check_exit_reach()
  local dx = (P.x + P.w/2) - (exit_pos.x + TILE/2)
  local dy = (P.y + P.h/2) - (exit_pos.y + TILE/2)
  if math.abs(dx) < 6 and math.abs(dy) < 6 then
    sfx_exit()
    spawn_burst(exit_pos.x + TILE/2, exit_pos.y + TILE/2, 12, 2.0, 15)
    G.score = G.score + 500
    play_state = PS_LEVELCLEAR
    state_timer = 0
  end
end

local function check_enemy_collision()
  if P.invuln > 0 and P.dashing <= 0 then return end

  -- When dashing, kill enemies
  if P.dashing > 0 then
    for _, e in ipairs(enemies) do
      if e.alive then
        if P.x + P.w > e.x and P.x < e.x + e.w and
           P.y + P.h > e.y and P.y < e.y + e.h then
          e.alive = false
          G.score = G.score + 200
          sfx_enemy_die()
          spawn_burst(e.x + e.w/2, e.y + e.h/2, 8, 2.0, 12)
          cam_shake(3)
        end
      end
    end
    return
  end

  if P.invuln > 0 then return end

  for _, e in ipairs(enemies) do
    if not e.alive then goto skip end
    if P.x + P.w > e.x and P.x < e.x + e.w and
       P.y + P.h > e.y and P.y < e.y + e.h then
      if P.vy > 0 and P.y + P.h - e.y < 5 then
        -- Stomp
        e.alive = false
        P.vy = JUMP_VEL * 0.7
        G.score = G.score + 200
        sfx_enemy_die()
        spawn_burst(e.x + e.w/2, e.y + e.h/2, 8, 2.0, 12)
        cam_shake(2)
      else
        kill_player()
        return
      end
    end
    ::skip::
  end
end

local function check_hazards()
  if P.invuln > 0 or P.dashing > 0 then return end
  if check_spikes(P.x, P.y, P.w, P.h) then
    kill_player()
  end
  if P.y > H + 20 then
    kill_player()
  end
end

----------------------------------------------------------------
-- SCENE CALLBACKS
----------------------------------------------------------------
function scene.init()
  play_state = PS_PLAYING
  state_timer = 0
  level_name_timer = 60  -- show level name for 2 seconds
end

function scene.update()
  state_timer = state_timer + 1
  if level_name_timer > 0 then level_name_timer = level_name_timer - 1 end

  if play_state == PS_PLAYING then
    G.level_timer = G.level_timer + 1
    move_player()
    update_enemies()
    check_coins_collect()
    check_springs_bounce()
    check_hazards()
    check_enemy_collision()
    check_exit_reach()
    update_particles()

  elseif play_state == PS_DYING then
    update_particles()
    if state_timer > 45 then
      if G.lives <= 0 then
        go("gameover")
      else
        reset_player(spawn_x, spawn_y)
        P.invuln = 45
        play_state = PS_PLAYING
        state_timer = 0
      end
    end

  elseif play_state == PS_LEVELCLEAR then
    update_particles()
    if state_timer >= 60 then
      G.cur_level = G.cur_level + 1
      if G.cur_level > #level_data then
        go("win")
      else
        load_level(G.cur_level)
        init_bg()
        play_state = PS_PLAYING
        state_timer = 0
        level_name_timer = 60
      end
    end
  end
end

function scene.draw()
  draw_level()

  local scr = screen()
  -- Level name overlay
  if level_name_timer > 0 then
    local ld = level_data[G.cur_level]
    if ld then
      local alpha_c = level_name_timer > 30 and 15 or 8
      local y = 14
      rectf(scr, 20, y - 2, 120, 14, 1)
      rect(scr, 20, y - 2, 120, 14, alpha_c)
      text(scr, "STAGE " .. G.cur_level, 52, y, alpha_c)
      text(scr, ld.name, 42, y + 7, alpha_c - 3)
    end
  end

  -- Level clear overlay
  if play_state == PS_LEVELCLEAR then
    rectf(scr, 25, 35, 110, 50, 1)
    rect(scr, 25, 35, 110, 50, 12)
    rect(scr, 26, 36, 108, 48, 4)
    text(scr, "STAGE CLEAR!", 40, 42, 15)
    local ld = level_data[G.cur_level]
    if ld then
      text(scr, ld.name, 42, 54, 10)
    end
    text(scr, "+" .. 500 .. " BONUS", 48, 66, 13)
    -- Progress bar
    local prog = math.min(state_timer / 60, 1.0)
    rectf(scr, 40, 76, math.floor(80 * prog), 3, 12)
  end
end

return scene
