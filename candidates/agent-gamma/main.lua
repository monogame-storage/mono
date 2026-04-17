-- VOID STORM
-- A vertical scrolling shmup for Mono Fantasy Console
-- 160x120 | 16 grayscale | 30fps
-- D-Pad: Move | A: Shoot | B: Bomb | START: Start/Pause | SELECT: Pause

---------- CONSTANTS ----------
local W = SCREEN_W or 160
local H = SCREEN_H or 120
local S -- screen surface, set each frame in _draw
local DIAG = 0.7071
local PLAYER_SPEED = 2.2
local BULLET_SPEED = 5
local EBULLET_SPEED = 1.8
local MAX_PARTICLES = 60
local MAX_STARS = 35
local MAX_BULLETS = 20
local MAX_EBULLETS = 40

---------- FORWARD DECLARATIONS ----------
local init_game, start_wave, spawn_powerup
local add_explosion, add_particles, player_die
local update_play, draw_play
local update_boss_pattern

---------- SAFE AUDIO ----------
local function sfx_note(ch, n, dur)
  if note then note(ch, n, dur) end
end
local function sfx_noise(ch, dur)
  if noise then noise(ch, dur) end
end

---------- UTILITY ----------
local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function dist(x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  return math.sqrt(dx * dx + dy * dy)
end

local function aabb(x1, y1, w1, h1, x2, y2, w2, h2)
  return x1 < x2 + w2 and x1 + w1 > x2 and y1 < y2 + h2 and y1 + h1 > y2
end

-- Centered text helper using ALIGN_CENTER
local function text_center(str, cx, y, c)
  text(S, str, cx, y, c, ALIGN_CENTER)
end

---------- GLOBAL STATE ----------
local state         -- "title", "play", "paused", "gameover", "attract"
local high_score = 0

-- Player
local px, py
local p_lives, p_bombs
local p_weapon       -- 0=single, 1=double, 2=spread, 3=laser
local p_power        -- weapon power level 0-3
local p_shield       -- shield hits remaining
local p_inv          -- invincibility timer
local p_shoot_cd
local p_bomb_active  -- bomb effect timer
local p_flash

-- Game
local score
local wave_num, wave_timer, wave_enemies_left
local enemies, bullets, ebullets, particles, powerups, stars
local boss, boss_active
local shake_timer, shake_amt
local combo, combo_timer
local paused

-- Attract mode
local attract_timer = 0
local attract_frame = 0
local ATTRACT_IDLE_FRAMES = 90
local ATTRACT_DURATION = 300 -- ~10 seconds at 30fps

-- AI state for attract mode
local ai_target_x, ai_target_y
local ai_dodge_timer = 0

-- Touch state
local touch_last_tap_time = -999  -- frame of last tap (for double-tap bomb)
local TOUCH_DOUBLE_TAP_WINDOW = 12  -- frames for double-tap detection
local TOUCH_FOLLOW_SPEED = 2.8  -- smooth follow speed (slightly above PLAYER_SPEED for responsive feel)

---------- STAR FIELD ----------
local function init_stars()
  stars = {}
  for i = 1, MAX_STARS do
    stars[i] = {
      x = math.random(0, W - 1),
      y = math.random(0, H - 1),
      spd = 0.3 + math.random() * 1.2,
      bright = math.random(2, 5)
    }
  end
end

local function update_stars()
  for i = 1, #stars do
    local s = stars[i]
    s.y = s.y + s.spd
    if s.y > H then
      s.y = 0
      s.x = math.random(0, W - 1)
    end
  end
end

local function draw_stars()
  for i = 1, #stars do
    local st = stars[i]
    pix(S, math.floor(st.x), math.floor(st.y), st.bright)
  end
end

---------- PARTICLES ----------
add_particles = function(x, y, count, col, spd_mult, life_mult)
  spd_mult = spd_mult or 1
  life_mult = life_mult or 1
  for i = 1, count do
    if #particles >= MAX_PARTICLES then return end
    local angle = math.random() * 6.2832
    local speed = (0.5 + math.random() * 2.5) * spd_mult
    particles[#particles + 1] = {
      x = x, y = y,
      vx = math.cos(angle) * speed,
      vy = math.sin(angle) * speed,
      life = math.floor((8 + math.random(0, 12)) * life_mult),
      max_life = math.floor((8 + math.random(0, 12)) * life_mult),
      col = col or 15
    }
  end
end

add_explosion = function(x, y, size)
  size = size or 1
  local count = math.floor(6 * size)
  add_particles(x, y, count, 15, size, size * 0.8)
  add_particles(x, y, math.floor(count * 0.6), 12, size * 0.7, size)
  add_particles(x, y, math.floor(count * 0.3), 8, size * 0.5, size * 1.2)
  shake_timer = math.floor(4 * size)
  shake_amt = math.floor(2 * size)
end

local function update_particles()
  local i = 1
  while i <= #particles do
    local p = particles[i]
    p.x = p.x + p.vx
    p.y = p.y + p.vy
    p.vx = p.vx * 0.92
    p.vy = p.vy * 0.92
    p.life = p.life - 1
    if p.life <= 0 then
      table.remove(particles, i)
    else
      i = i + 1
    end
  end
end

local function draw_particles()
  for i = 1, #particles do
    local p = particles[i]
    local ratio = p.life / p.max_life
    local col = math.floor(p.col * ratio)
    if col < 1 then col = 1 end
    if col > 15 then col = 15 end
    local ix, iy = math.floor(p.x), math.floor(p.y)
    if ix >= 0 and ix < W and iy >= 0 and iy < H then
      pix(S, ix, iy, col)
    end
  end
end

---------- SCREEN SHAKE ----------
local function apply_shake()
  if shake_timer and shake_timer > 0 then
    shake_timer = shake_timer - 1
    if cam_shake then cam_shake(shake_amt) end
  end
end

---------- PLAYER BULLETS ----------
local function fire_player()
  if p_shoot_cd > 0 then return end

  if p_weapon == 0 then
    -- Single shot
    if #bullets < MAX_BULLETS then
      bullets[#bullets + 1] = {x = px, y = py - 6, vx = 0, vy = -BULLET_SPEED, dmg = 1, w = 2, h = 4}
    end
    p_shoot_cd = 5
    sfx_note(0, "C6", 0.04)

  elseif p_weapon == 1 then
    -- Double shot
    if #bullets < MAX_BULLETS - 1 then
      bullets[#bullets + 1] = {x = px - 4, y = py - 4, vx = 0, vy = -BULLET_SPEED, dmg = 1, w = 2, h = 4}
      bullets[#bullets + 1] = {x = px + 4, y = py - 4, vx = 0, vy = -BULLET_SPEED, dmg = 1, w = 2, h = 4}
    end
    p_shoot_cd = 5
    sfx_note(0, "D6", 0.04)

  elseif p_weapon == 2 then
    -- Spread shot (3-way)
    if #bullets < MAX_BULLETS - 2 then
      bullets[#bullets + 1] = {x = px, y = py - 6, vx = 0, vy = -BULLET_SPEED, dmg = 1, w = 2, h = 4}
      bullets[#bullets + 1] = {x = px - 3, y = py - 4, vx = -1.2, vy = -BULLET_SPEED * 0.9, dmg = 1, w = 2, h = 3}
      bullets[#bullets + 1] = {x = px + 3, y = py - 4, vx = 1.2, vy = -BULLET_SPEED * 0.9, dmg = 1, w = 2, h = 3}
    end
    p_shoot_cd = 6
    sfx_note(0, "E6", 0.04)

  elseif p_weapon == 3 then
    -- Laser (piercing)
    if #bullets < MAX_BULLETS then
      bullets[#bullets + 1] = {x = px, y = py - 8, vx = 0, vy = -BULLET_SPEED * 1.5, dmg = 2, w = 1, h = 10, pierce = true}
    end
    p_shoot_cd = 3
    sfx_note(0, "G6", 0.03)
  end
end

---------- BOMB ----------
local function use_bomb()
  if p_bombs <= 0 then return end
  p_bombs = p_bombs - 1
  p_bomb_active = 30

  -- Damage all enemies on screen
  for i = 1, #enemies do
    local e = enemies[i]
    if e.alive then
      e.hp = e.hp - 5
      if e.hp <= 0 then
        e.alive = false
        add_explosion(e.x, e.y, 1.5)
        score = score + e.score_val
      end
    end
  end

  -- Clear enemy bullets
  ebullets = {}

  -- Damage boss
  if boss_active and boss then
    boss.hp = boss.hp - 10
    boss.flash = 8
  end

  -- Big screen effect
  shake_timer = 12
  shake_amt = 4
  add_particles(W / 2, H / 2, 30, 15, 3, 1.5)
  sfx_note(0, "C2", 0.3)
  sfx_note(1, "E2", 0.3)
  sfx_noise(2, 0.3)
end

---------- POWERUP SYSTEM ----------
-- Types: "weapon", "shield", "bomb", "points"
spawn_powerup = function(x, y)
  local roll = math.random(1, 100)
  local ptype
  if roll <= 40 then
    ptype = "weapon"
  elseif roll <= 60 then
    ptype = "shield"
  elseif roll <= 80 then
    ptype = "bomb"
  else
    ptype = "points"
  end
  powerups[#powerups + 1] = {
    x = x, y = y,
    vy = 0.5,
    ptype = ptype,
    timer = 300 -- disappear after 10 seconds
  }
end

local function collect_powerup(pu)
  if pu.ptype == "weapon" then
    if p_weapon < 3 then
      p_weapon = p_weapon + 1
    else
      score = score + 500
    end
    sfx_note(0, "C5", 0.05)
    sfx_note(0, "E5", 0.05)
  elseif pu.ptype == "shield" then
    p_shield = math.min(p_shield + 1, 3)
    sfx_note(0, "G4", 0.08)
  elseif pu.ptype == "bomb" then
    p_bombs = math.min(p_bombs + 1, 5)
    sfx_note(0, "A4", 0.06)
  elseif pu.ptype == "points" then
    score = score + 1000
    sfx_note(0, "C5", 0.03)
    sfx_note(0, "G5", 0.03)
  end
  add_particles(pu.x, pu.y, 8, 15, 0.8, 0.5)
end

---------- ENEMY TYPES ----------
-- kind 1: Drifter - sine wave, occasional shot
-- kind 2: Charger - dives at player
-- kind 3: Turret - stationary, aimed shots
-- kind 4: Spreader - fires spread patterns
-- kind 5: Swooper - arc path

local function spawn_enemy(kind, x, y, extra)
  extra = extra or {}
  local e = {
    kind = kind,
    x = x, y = y,
    alive = true,
    timer = 0,
    flash = 0,
    hp = 1,
    score_val = 100,
    base_x = x
  }

  if kind == 1 then -- Drifter
    e.hp = 1
    e.vy = 0.8 + math.random() * 0.5
    e.amp = 20 + math.random(0, 15)
    e.freq = 0.04 + math.random() * 0.02
    e.score_val = 100
  elseif kind == 2 then -- Charger
    e.hp = 2
    e.phase = 0 -- 0=approach, 1=charge
    e.vy = 1
    e.vx = 0
    e.score_val = 200
  elseif kind == 3 then -- Turret
    e.hp = 3
    e.vy = 0.3
    e.shoot_cd = 40 + math.random(0, 20)
    e.score_val = 300
  elseif kind == 4 then -- Spreader
    e.hp = 2
    e.vy = 0.6
    e.shoot_cd = 50
    e.score_val = 250
  elseif kind == 5 then -- Swooper
    e.hp = 1
    e.angle = extra.angle or 0
    e.radius = extra.radius or 30
    e.center_x = extra.center_x or x
    e.arc_speed = extra.arc_speed or 0.06
    e.vy = 0.5
    e.score_val = 150
  end

  -- Scale HP by wave
  if wave_num > 5 then
    e.hp = e.hp + math.floor((wave_num - 5) / 5)
  end

  enemies[#enemies + 1] = e
end

---------- ENEMY AI ----------
local function update_enemy(e)
  if not e.alive then return end
  e.timer = e.timer + 1
  if e.flash > 0 then e.flash = e.flash - 1 end

  if e.kind == 1 then -- Drifter
    e.y = e.y + e.vy
    e.x = e.base_x + math.sin(e.timer * e.freq) * e.amp
    if e.timer % 80 == 40 and e.y > 10 and e.y < H - 20 then
      if #ebullets < MAX_EBULLETS then
        local dx, dy = px - e.x, py - e.y
        local d = dist(e.x, e.y, px, py)
        if d < 1 then d = 1 end
        ebullets[#ebullets + 1] = {
          x = e.x, y = e.y,
          vx = dx / d * EBULLET_SPEED,
          vy = dy / d * EBULLET_SPEED
        }
      end
    end

  elseif e.kind == 2 then -- Charger
    if e.phase == 0 then
      e.y = e.y + e.vy
      if e.y > H * 0.3 then
        e.phase = 1
        local dx, dy = px - e.x, py - e.y
        local d = dist(e.x, e.y, px, py)
        if d < 1 then d = 1 end
        e.vx = dx / d * 3
        e.vy = dy / d * 3
        sfx_note(1, "F3", 0.06)
      end
    else
      e.x = e.x + e.vx
      e.y = e.y + e.vy
    end

  elseif e.kind == 3 then -- Turret
    e.y = e.y + e.vy
    if e.y > 15 then e.vy = 0 end -- Stop and shoot
    e.shoot_cd = e.shoot_cd - 1
    if e.shoot_cd <= 0 and e.y > 5 and e.y < H - 10 then
      e.shoot_cd = math.max(20, 50 - wave_num * 2)
      local dx, dy = px - e.x, py - e.y
      local d = dist(e.x, e.y, px, py)
      if d < 1 then d = 1 end
      if #ebullets < MAX_EBULLETS then
        ebullets[#ebullets + 1] = {
          x = e.x, y = e.y,
          vx = dx / d * EBULLET_SPEED,
          vy = dy / d * EBULLET_SPEED
        }
      end
      sfx_note(1, "A4", 0.03)
    end

  elseif e.kind == 4 then -- Spreader
    e.y = e.y + e.vy
    e.x = e.base_x + math.sin(e.timer * 0.03) * 15
    e.shoot_cd = e.shoot_cd - 1
    if e.shoot_cd <= 0 and e.y > 10 and e.y < H * 0.6 then
      e.shoot_cd = math.max(30, 60 - wave_num)
      -- Fire spread of 5 bullets
      for a = -2, 2 do
        if #ebullets < MAX_EBULLETS then
          local angle = math.atan(py - e.y, px - e.x) + a * 0.25
          ebullets[#ebullets + 1] = {
            x = e.x, y = e.y,
            vx = math.cos(angle) * EBULLET_SPEED,
            vy = math.sin(angle) * EBULLET_SPEED
          }
        end
      end
      sfx_note(1, "D4", 0.05)
    end

  elseif e.kind == 5 then -- Swooper
    e.angle = e.angle + e.arc_speed
    e.x = e.center_x + math.cos(e.angle) * e.radius
    e.y = e.y + e.vy
    if e.timer % 60 == 30 and e.y > 5 and e.y < H - 10 then
      if #ebullets < MAX_EBULLETS then
        local dx, dy = px - e.x, py - e.y
        local d = dist(e.x, e.y, px, py)
        if d < 1 then d = 1 end
        ebullets[#ebullets + 1] = {
          x = e.x, y = e.y,
          vx = dx / d * EBULLET_SPEED * 0.8,
          vy = dy / d * EBULLET_SPEED * 0.8
        }
      end
    end
  end

  -- Remove if off screen
  if e.y > H + 20 or e.y < -40 or e.x < -30 or e.x > W + 30 then
    e.alive = false
  end
end

---------- BOSS SYSTEM ----------
local function spawn_boss()
  boss_active = true
  local boss_tier = math.floor(wave_num / 5)
  local base_hp = 40 + boss_tier * 20
  boss = {
    x = W / 2, y = -30,
    target_y = 25,
    hp = base_hp,
    max_hp = base_hp,
    phase = 0,
    timer = 0,
    flash = 0,
    pattern = 0,
    pattern_timer = 0,
    alive = true,
    entering = true,
    -- Visual size
    w = 32, h = 20
  }
  sfx_note(0, "C3", 0.15)
  sfx_note(1, "G2", 0.15)
end

update_boss_pattern = function()
  if not boss or not boss.alive then return end
  boss.timer = boss.timer + 1
  if boss.flash > 0 then boss.flash = boss.flash - 1 end

  -- Entry
  if boss.entering then
    boss.y = boss.y + 1
    if boss.y >= boss.target_y then
      boss.entering = false
    end
    return
  end

  -- Movement: sway side to side
  boss.x = W / 2 + math.sin(boss.timer * 0.02) * 50

  -- Phase based on HP
  local hp_ratio = boss.hp / boss.max_hp
  if hp_ratio > 0.6 then
    boss.phase = 0
  elseif hp_ratio > 0.3 then
    boss.phase = 1
  else
    boss.phase = 2
  end

  boss.pattern_timer = boss.pattern_timer + 1

  if boss.phase == 0 then
    -- Phase 1: aimed shots
    if boss.pattern_timer % 25 == 0 then
      local dx, dy = px - boss.x, py - boss.y
      local d = dist(boss.x, boss.y, px, py)
      if d < 1 then d = 1 end
      if #ebullets < MAX_EBULLETS then
        ebullets[#ebullets + 1] = {
          x = boss.x, y = boss.y + 10,
          vx = dx / d * EBULLET_SPEED * 1.2,
          vy = dy / d * EBULLET_SPEED * 1.2
        }
      end
      sfx_note(1, "E3", 0.04)
    end

  elseif boss.phase == 1 then
    -- Phase 2: ring burst + aimed
    if boss.pattern_timer % 40 == 0 then
      for a = 0, 7 do
        local angle = a * 0.7854 -- pi/4
        if #ebullets < MAX_EBULLETS then
          ebullets[#ebullets + 1] = {
            x = boss.x, y = boss.y + 10,
            vx = math.cos(angle) * EBULLET_SPEED,
            vy = math.sin(angle) * EBULLET_SPEED
          }
        end
      end
      sfx_note(1, "C4", 0.05)
    end
    if boss.pattern_timer % 20 == 10 then
      local dx, dy = px - boss.x, py - boss.y
      local d = dist(boss.x, boss.y, px, py)
      if d < 1 then d = 1 end
      if #ebullets < MAX_EBULLETS then
        ebullets[#ebullets + 1] = {
          x = boss.x, y = boss.y + 10,
          vx = dx / d * EBULLET_SPEED * 1.3,
          vy = dy / d * EBULLET_SPEED * 1.3
        }
      end
    end

  else
    -- Phase 3: spiral + fast aimed
    if boss.pattern_timer % 5 == 0 then
      local angle = boss.pattern_timer * 0.3
      if #ebullets < MAX_EBULLETS then
        ebullets[#ebullets + 1] = {
          x = boss.x, y = boss.y + 10,
          vx = math.cos(angle) * EBULLET_SPEED * 1.1,
          vy = math.sin(angle) * EBULLET_SPEED * 1.1
        }
      end
    end
    if boss.pattern_timer % 15 == 0 then
      local dx, dy = px - boss.x, py - boss.y
      local d = dist(boss.x, boss.y, px, py)
      if d < 1 then d = 1 end
      for spread = -1, 1 do
        if #ebullets < MAX_EBULLETS then
          ebullets[#ebullets + 1] = {
            x = boss.x + spread * 8, y = boss.y + 12,
            vx = dx / d * EBULLET_SPEED * 1.4 + spread * 0.3,
            vy = dy / d * EBULLET_SPEED * 1.4
          }
        end
      end
      sfx_note(1, "F3", 0.03)
    end
  end

  -- Boss death check
  if boss.hp <= 0 then
    boss.alive = false
    boss_active = false
    add_explosion(boss.x, boss.y, 3)
    add_explosion(boss.x - 10, boss.y - 5, 2)
    add_explosion(boss.x + 10, boss.y + 5, 2)
    score = score + 5000 + wave_num * 500
    shake_timer = 20
    shake_amt = 5
    sfx_note(0, "C2", 0.4)
    sfx_note(1, "C2", 0.4)
    sfx_noise(2, 0.4)
    -- Drop powerups
    spawn_powerup(boss.x - 10, boss.y)
    spawn_powerup(boss.x + 10, boss.y)
    -- Next wave
    wave_timer = 90
  end
end

---------- WAVE SYSTEM ----------
start_wave = function()
  wave_num = wave_num + 1

  -- Boss every 5 waves
  if wave_num % 5 == 0 then
    spawn_boss()
    return
  end

  local difficulty = math.min(wave_num, 20)
  local count = 3 + math.floor(difficulty * 0.8)
  local pattern = math.random(1, 5)
  wave_enemies_left = count

  if pattern == 1 then
    -- V-formation of drifters
    for i = 1, count do
      local offset = (i - math.ceil(count / 2)) * 16
      spawn_enemy(1, W / 2 + offset, -10 - math.abs(offset) * 0.5)
    end

  elseif pattern == 2 then
    -- Line of chargers
    for i = 1, math.min(count, 6) do
      spawn_enemy(2, 20 + (i - 1) * 24, -10 - i * 12)
    end

  elseif pattern == 3 then
    -- Turrets + drifter escort
    local turrets = math.min(math.floor(count / 3) + 1, 3)
    for i = 1, turrets do
      spawn_enemy(3, 30 + (i - 1) * 50, -10 - i * 8)
    end
    for i = 1, count - turrets do
      spawn_enemy(1, math.random(20, W - 20), -10 - math.random(0, 30))
    end

  elseif pattern == 4 then
    -- Swooper squad
    local cx = W / 2
    for i = 1, count do
      spawn_enemy(5, cx, -10 - i * 10, {
        center_x = cx,
        angle = i * 1.2,
        radius = 25 + i * 3,
        arc_speed = 0.05 + math.random() * 0.02
      })
    end

  elseif pattern == 5 then
    -- Mixed: spreader center + charger flanks
    if difficulty >= 4 then
      spawn_enemy(4, W / 2, -15)
    end
    for i = 1, math.floor(count / 2) do
      spawn_enemy(2, 15 + math.random(0, 20), -10 - i * 15)
      spawn_enemy(2, W - 15 - math.random(0, 20), -10 - i * 15)
    end
  end
end

---------- COLLISIONS ----------
local function check_collisions()
  -- Player bullets vs enemies
  local bi = 1
  while bi <= #bullets do
    local b = bullets[bi]
    local hit = false

    -- vs enemies
    for ei = #enemies, 1, -1 do
      local e = enemies[ei]
      if e.alive and aabb(b.x - b.w / 2, b.y - b.h / 2, b.w, b.h, e.x - 6, e.y - 6, 12, 12) then
        e.hp = e.hp - b.dmg
        e.flash = 3
        if e.hp <= 0 then
          e.alive = false
          add_explosion(e.x, e.y, 1.2)
          score = score + e.score_val
          wave_enemies_left = wave_enemies_left - 1
          combo = combo + 1
          combo_timer = 60
          if combo >= 5 then
            score = score + combo * 50
          end
          -- Powerup drop chance
          if math.random(1, 100) <= 15 then
            spawn_powerup(e.x, e.y)
          end
          sfx_note(1, "C3", 0.06)
        else
          sfx_note(1, "E5", 0.02)
        end
        if not b.pierce then
          hit = true
        end
        break
      end
    end

    -- vs boss
    if not hit and boss_active and boss and boss.alive and not boss.entering then
      if aabb(b.x - b.w / 2, b.y - b.h / 2, b.w, b.h,
              boss.x - boss.w / 2, boss.y - boss.h / 2, boss.w, boss.h) then
        boss.hp = boss.hp - b.dmg
        boss.flash = 2
        hit = not b.pierce
        add_particles(b.x, b.y, 2, 12, 0.5, 0.3)
        sfx_note(1, "A4", 0.02)
      end
    end

    if hit then
      table.remove(bullets, bi)
    else
      bi = bi + 1
    end
  end

  -- Enemy bullets vs player
  if p_inv <= 0 and p_bomb_active <= 0 then
    local i = 1
    while i <= #ebullets do
      local b = ebullets[i]
      if aabb(b.x - 2, b.y - 2, 4, 4, px - 3, py - 3, 6, 6) then
        table.remove(ebullets, i)
        if p_shield > 0 then
          p_shield = p_shield - 1
          p_inv = 15
          add_particles(px, py, 6, 10, 1, 0.5)
          sfx_note(0, "E4", 0.05)
        else
          player_die()
          return
        end
      else
        i = i + 1
      end
    end

    -- Enemy collision with player
    for i = 1, #enemies do
      local e = enemies[i]
      if e.alive and aabb(e.x - 5, e.y - 5, 10, 10, px - 3, py - 3, 6, 6) then
        e.alive = false
        add_explosion(e.x, e.y, 1)
        if p_shield > 0 then
          p_shield = p_shield - 1
          p_inv = 15
          sfx_note(0, "E4", 0.05)
        else
          player_die()
          return
        end
      end
    end

    -- Boss collision
    if boss_active and boss and boss.alive and not boss.entering then
      if aabb(px - 3, py - 3, 6, 6, boss.x - boss.w / 2, boss.y - boss.h / 2, boss.w, boss.h) then
        player_die()
        return
      end
    end
  end

  -- Powerup collection
  local i = 1
  while i <= #powerups do
    local pu = powerups[i]
    if aabb(pu.x - 5, pu.y - 5, 10, 10, px - 6, py - 6, 12, 12) then
      collect_powerup(pu)
      table.remove(powerups, i)
    else
      i = i + 1
    end
  end
end

---------- PLAYER DEATH ----------
player_die = function()
  p_lives = p_lives - 1
  p_flash = 10
  add_explosion(px, py, 2)
  shake_timer = 10
  shake_amt = 3
  sfx_note(0, "C2", 0.2)
  sfx_note(1, "E2", 0.2)
  sfx_noise(2, 0.2)

  if p_lives <= 0 then
    state = "gameover"
    if score > high_score then high_score = score end
  else
    -- Reset position and give invincibility
    px = W / 2
    py = H - 20
    p_inv = 90
    -- Downgrade weapon
    if p_weapon > 0 then p_weapon = p_weapon - 1 end
    p_shield = 0
    ebullets = {}
  end
end

---------- GAME INIT ----------
init_game = function()
  px, py = W / 2, H - 20
  p_lives = 3
  p_bombs = 2
  p_weapon = 0
  p_power = 0
  p_shield = 0
  p_inv = 60
  p_shoot_cd = 0
  p_bomb_active = 0
  p_flash = 0

  score = 0
  wave_num = 0
  wave_timer = 60
  wave_enemies_left = 0

  enemies = {}
  bullets = {}
  ebullets = {}
  particles = {}
  powerups = {}
  boss = nil
  boss_active = false

  shake_timer = 0
  shake_amt = 0
  combo = 0
  combo_timer = 0
  paused = false

  init_stars()
end

---------- AI FOR ATTRACT MODE ----------
local function ai_find_nearest_threat()
  -- Find nearest enemy bullet or enemy to dodge
  local nearest_dist = 999
  local nearest_x, nearest_y = nil, nil

  for i = 1, #ebullets do
    local b = ebullets[i]
    local d = dist(px, py, b.x, b.y)
    if d < nearest_dist and d < 60 then
      nearest_dist = d
      nearest_x = b.x
      nearest_y = b.y
    end
  end

  for i = 1, #enemies do
    local e = enemies[i]
    if e.alive then
      local d = dist(px, py, e.x, e.y)
      if d < nearest_dist and d < 50 then
        nearest_dist = d
        nearest_x = e.x
        nearest_y = e.y
      end
    end
  end

  return nearest_x, nearest_y, nearest_dist
end

local function ai_update()
  -- AI always shoots
  fire_player()

  -- Find threats to dodge
  local threat_x, threat_y, threat_d = ai_find_nearest_threat()

  -- Pick target position: weave around while dodging
  ai_dodge_timer = ai_dodge_timer + 1

  local target_x, target_y

  if threat_x and threat_d < 35 then
    -- Dodge away from threat
    local dodge_dx = px - threat_x
    local dodge_dy = py - threat_y
    local dd = math.sqrt(dodge_dx * dodge_dx + dodge_dy * dodge_dy)
    if dd < 1 then dd = 1 end
    target_x = px + (dodge_dx / dd) * 30
    target_y = py + (dodge_dy / dd) * 20
  else
    -- Weave pattern: figure-8 in lower portion of screen
    local t = ai_dodge_timer * 0.04
    target_x = W / 2 + math.sin(t) * 50
    target_y = H * 0.65 + math.sin(t * 2.1) * 15
  end

  -- Clamp target
  target_x = clamp(target_x, 12, W - 12)
  target_y = clamp(target_y, 20, H - 12)

  -- Move toward target
  local dx = target_x - px
  local dy = target_y - py
  local move_d = math.sqrt(dx * dx + dy * dy)
  if move_d > 1 then
    local spd = math.min(PLAYER_SPEED, move_d)
    px = px + (dx / move_d) * spd
    py = py + (dy / move_d) * spd
  end

  px = clamp(px, 8, W - 8)
  py = clamp(py, 12, H - 8)

  -- Occasionally use bomb if lots of bullets on screen
  if #ebullets > 20 and p_bombs > 0 and ai_dodge_timer % 60 == 0 then
    use_bomb()
  end
end

---------- UPDATE ----------
update_play = function()
  if paused then return end

  update_stars()
  update_particles()

  -- Bomb effect
  if p_bomb_active > 0 then p_bomb_active = p_bomb_active - 1 end
  if p_flash > 0 then p_flash = p_flash - 1 end
  if p_inv > 0 then p_inv = p_inv - 1 end
  if p_shoot_cd > 0 then p_shoot_cd = p_shoot_cd - 1 end

  -- Combo decay
  if combo_timer > 0 then
    combo_timer = combo_timer - 1
    if combo_timer <= 0 then combo = 0 end
  end

  -- Player movement (AI or human)
  if state == "attract" then
    ai_update()
  else
    local dx, dy = 0, 0
    if btn("left")  then dx = -1 end
    if btn("right") then dx = 1 end
    if btn("up")    then dy = -1 end
    if btn("down")  then dy = 1 end
    if dx ~= 0 and dy ~= 0 then
      dx = dx * DIAG
      dy = dy * DIAG
    end
    px = clamp(px + dx * PLAYER_SPEED, 8, W - 8)
    py = clamp(py + dy * PLAYER_SPEED, 12, H - 8)

    -- Shooting
    if btn("a") then fire_player() end

    -- Bomb
    if btnp("b") then use_bomb() end

    -- Touch controls (additive to d-pad/buttons)
    if touch and touch_pos then
      -- Double-tap detection for bomb
      if touch_start and touch_start() then
        local cur_frame = frame()
        if cur_frame - touch_last_tap_time <= TOUCH_DOUBLE_TAP_WINDOW then
          use_bomb()
          touch_last_tap_time = -999  -- reset so triple-tap doesn't re-trigger
        else
          touch_last_tap_time = cur_frame
        end
      end

      if touch() then
        local tx, ty = touch_pos()
        if tx and ty then
          -- Smooth follow toward touch position
          local tdx = tx - px
          local tdy = ty - py
          local td = math.sqrt(tdx * tdx + tdy * tdy)
          if td > 1 then
            local spd = math.min(TOUCH_FOLLOW_SPEED, td)
            px = clamp(px + (tdx / td) * spd, 8, W - 8)
            py = clamp(py + (tdy / td) * spd, 12, H - 8)
          end

          -- Auto-fire while touching
          fire_player()
        end
      end
    end
  end

  -- Update player bullets
  local i = 1
  while i <= #bullets do
    local b = bullets[i]
    b.x = b.x + b.vx
    b.y = b.y + b.vy
    if b.y < -10 or b.x < -5 or b.x > W + 5 then
      table.remove(bullets, i)
    else
      i = i + 1
    end
  end

  -- Update enemy bullets
  i = 1
  while i <= #ebullets do
    local b = ebullets[i]
    b.x = b.x + b.vx
    b.y = b.y + b.vy
    if b.x < -5 or b.x > W + 5 or b.y < -5 or b.y > H + 5 then
      table.remove(ebullets, i)
    else
      i = i + 1
    end
  end

  -- Update enemies
  for ei = #enemies, 1, -1 do
    local e = enemies[ei]
    if e.alive then
      update_enemy(e)
    end
    if not e.alive then
      table.remove(enemies, ei)
    end
  end

  -- Update powerups
  i = 1
  while i <= #powerups do
    local pu = powerups[i]
    pu.y = pu.y + pu.vy
    pu.timer = pu.timer - 1
    if pu.y > H + 10 or pu.timer <= 0 then
      table.remove(powerups, i)
    else
      i = i + 1
    end
  end

  -- Update boss
  if boss_active and boss and boss.alive then
    update_boss_pattern()
  end

  -- Collisions
  check_collisions()

  -- Wave management
  if not boss_active then
    -- Count alive enemies
    local alive_count = 0
    for ei = 1, #enemies do
      if enemies[ei].alive then alive_count = alive_count + 1 end
    end

    if alive_count == 0 and wave_timer <= 0 then
      wave_timer = 60
    end

    if wave_timer > 0 then
      wave_timer = wave_timer - 1
      if wave_timer <= 0 then
        start_wave()
      end
    end
  end

  -- Screen shake
  apply_shake()
end

---------- DRAW: PLAYER ----------
local function draw_player()
  if p_inv > 0 and frame() % 4 < 2 then return end
  local x, y = math.floor(px), math.floor(py)

  -- Engine glow (flicker)
  local glow = 8 + (frame() % 3)
  rectf(S, x - 1, y + 4, 2, 3, glow)
  if p_weapon >= 2 then
    rectf(S, x - 5, y + 3, 2, 2, glow - 2)
    rectf(S, x + 3, y + 3, 2, 2, glow - 2)
  end

  -- Main body
  rectf(S, x - 2, y - 5, 4, 8, 13)  -- fuselage
  rectf(S, x - 1, y - 6, 2, 2, 15)  -- nose
  rectf(S, x - 6, y - 1, 12, 3, 11) -- wings
  rectf(S, x - 5, y - 2, 10, 1, 10) -- wing top
  rectf(S, x - 1, y - 3, 2, 5, 14)  -- cockpit stripe

  -- Shield visual
  if p_shield > 0 then
    local scol = 6 + p_shield * 2
    if scol > 12 then scol = 12 end
    circ(S, x, y, 8 + (frame() % 2), scol)
  end
end

---------- DRAW: ENEMIES ----------
local function draw_enemy(e)
  if not e.alive then return end
  local x, y = math.floor(e.x), math.floor(e.y)
  local col = e.flash > 0 and 15 or nil

  if e.kind == 1 then -- Drifter: diamond shape
    local c = col or 9
    line(S, x, y - 5, x + 5, y, c)
    line(S, x + 5, y, x, y + 5, c)
    line(S, x, y + 5, x - 5, y, c)
    line(S, x - 5, y, x, y - 5, c)
    rectf(S, x - 2, y - 2, 4, 4, col or 11)
    pix(S, x, y, col or 13)

  elseif e.kind == 2 then -- Charger: arrow shape
    local c = col or 10
    -- Body
    rectf(S, x - 3, y - 4, 6, 8, c)
    -- Point
    rectf(S, x - 1, y - 6, 2, 2, col or 12)
    -- Wings
    rectf(S, x - 6, y, 3, 4, c)
    rectf(S, x + 3, y, 3, 4, c)
    pix(S, x, y - 2, col or 14)

  elseif e.kind == 3 then -- Turret: hexagonal
    local c = col or 8
    rectf(S, x - 5, y - 3, 10, 6, c)
    rectf(S, x - 3, y - 5, 6, 10, c)
    rectf(S, x - 2, y - 2, 4, 4, col or 12)
    -- Gun barrel
    rectf(S, x - 1, y + 5, 2, 3, col or 10)
    pix(S, x, y, col or 15)

  elseif e.kind == 4 then -- Spreader: wide ship
    local c = col or 9
    rectf(S, x - 7, y - 2, 14, 4, c)
    rectf(S, x - 4, y - 4, 8, 8, col or 11)
    rectf(S, x - 2, y - 5, 4, 2, col or 13)
    -- Side guns
    pix(S, x - 6, y + 2, col or 15)
    pix(S, x + 5, y + 2, col or 15)
    pix(S, x, y + 3, col or 15)

  elseif e.kind == 5 then -- Swooper: small fast
    local c = col or 10
    rectf(S, x - 3, y - 3, 6, 6, c)
    rectf(S, x - 1, y - 4, 2, 2, col or 12)
    line(S, x - 4, y + 1, x - 2, y - 1, c)
    line(S, x + 3, y + 1, x + 1, y - 1, c)
  end
end

---------- DRAW: BOSS ----------
local function draw_boss()
  if not boss or not boss.alive then return end
  local x, y = math.floor(boss.x), math.floor(boss.y)
  local f = boss.flash > 0

  -- Main hull
  local hull_c = f and 15 or 7
  rectf(S, x - 16, y - 6, 32, 12, hull_c)
  rectf(S, x - 12, y - 10, 24, 20, f and 15 or 8)
  rectf(S, x - 8, y - 12, 16, 24, f and 15 or 9)

  -- Core
  local core_c = f and 15 or 13
  rectf(S, x - 4, y - 4, 8, 8, core_c)
  rectf(S, x - 2, y - 2, 4, 4, f and 15 or 15)

  -- Side turrets
  rectf(S, x - 14, y + 4, 4, 6, f and 15 or 10)
  rectf(S, x + 10, y + 4, 4, 6, f and 15 or 10)

  -- Phase indicator (pulsing based on phase)
  if boss.phase >= 1 then
    local pulse = math.floor(math.sin(boss.timer * 0.2) * 2 + 3)
    circ(S, x, y, pulse, f and 15 or 14)
  end
  if boss.phase >= 2 then
    circ(S, x - 10, y, 2, f and 15 or 12)
    circ(S, x + 10, y, 2, f and 15 or 12)
  end

  -- HP bar
  local bar_w = 40
  local bar_x = x - bar_w / 2
  local bar_y = y - 16
  rectf(S, bar_x - 1, bar_y - 1, bar_w + 2, 4, 0)
  rectf(S, bar_x, bar_y, bar_w, 2, 3)
  local hp_w = math.floor(bar_w * boss.hp / boss.max_hp)
  if hp_w > 0 then
    local hp_col = 15
    if boss.hp / boss.max_hp < 0.3 then
      hp_col = (frame() % 4 < 2) and 15 or 10
    end
    rectf(S, bar_x, bar_y, hp_w, 2, hp_col)
  end
end

---------- DRAW: BULLETS ----------
local function draw_bullets()
  -- Player bullets
  for i = 1, #bullets do
    local b = bullets[i]
    local bx, by = math.floor(b.x), math.floor(b.y)
    if b.pierce then
      -- Laser beam
      rectf(S, bx, by, 1, b.h, 15)
      rectf(S, bx - 1, by + 1, 3, b.h - 2, 12)
    else
      rectf(S, bx - 1, by - 2, 2, 4, 15)
      pix(S, bx, by - 3, 13)
    end
  end

  -- Enemy bullets
  for i = 1, #ebullets do
    local b = ebullets[i]
    local bx, by = math.floor(b.x), math.floor(b.y)
    circf(S, bx, by, 2, 12)
    pix(S, bx, by, 15)
  end
end

---------- DRAW: POWERUPS ----------
local function draw_powerups()
  for i = 1, #powerups do
    local pu = powerups[i]
    local x, y = math.floor(pu.x), math.floor(pu.y)

    -- Blinking when about to expire
    if pu.timer < 60 and frame() % 4 < 2 then
      -- skip draw (blink)
    else
      rectf(S, x - 4, y - 4, 8, 8, 0)
      rect(S, x - 4, y - 4, 8, 8, 12)

      if pu.ptype == "weapon" then
        -- W marker
        rectf(S, x - 2, y - 2, 4, 4, 15)
        pix(S, x, y, 0)
      elseif pu.ptype == "shield" then
        -- S: circle
        circ(S, x, y, 2, 15)
      elseif pu.ptype == "bomb" then
        -- B: filled
        circf(S, x, y, 2, 13)
        pix(S, x, y - 3, 15)
      elseif pu.ptype == "points" then
        -- Star
        pix(S, x, y - 2, 15)
        pix(S, x - 2, y, 15)
        pix(S, x + 2, y, 15)
        pix(S, x, y + 2, 15)
        pix(S, x, y, 15)
      end
    end
  end
end

---------- DRAW: HUD ----------
local function draw_hud()
  -- Top bar background
  rectf(S, 0, 0, W, 9, 0)
  line(S, 0, 9, W, 9, 3)

  -- Score
  text(S, "SC:" .. string.format("%06d", score), 2, 1, 15)

  -- Wave indicator
  text(S, "W" .. wave_num, 72, 1, 10)

  -- High score
  text(S, "HI:" .. string.format("%06d", high_score), 95, 1, 7)

  -- Lives (bottom left)
  for i = 1, p_lives - 1 do
    local lx = 2 + (i - 1) * 8
    rectf(S, lx + 1, H - 7, 2, 3, 12)
    rectf(S, lx, H - 4, 4, 2, 12)
  end

  -- Bombs (bottom right)
  for i = 1, p_bombs do
    local bx = W - 6 - (i - 1) * 7
    circf(S, bx, H - 5, 2, 10)
  end

  -- Weapon indicator (bottom center)
  local wnames = {"SINGLE", "DOUBLE", "SPREAD", "LASER"}
  local wname = wnames[p_weapon + 1] or "SINGLE"
  text_center(wname, W / 2, H - 7, 8)

  -- Shield indicator
  if p_shield > 0 then
    for i = 1, p_shield do
      rectf(S, W / 2 - 12 + (i - 1) * 8, H - 14, 6, 3, 10)
    end
  end

  -- Combo display
  if combo >= 3 and combo_timer > 0 then
    local cc = combo >= 10 and 15 or 12
    text_center(combo .. "x COMBO!", W / 2, 14, cc)
  end

  -- Boss warning
  if boss_active and boss and boss.entering then
    if frame() % 10 < 6 then
      text_center("!! WARNING !!", W / 2, H / 2 - 10, 15)
      text_center("BOSS INCOMING", W / 2, H / 2, 12)
    end
  end

  -- Bomb flash effect
  if p_bomb_active > 0 then
    local alpha = math.floor(15 * p_bomb_active / 30)
    if alpha > 0 and frame() % 2 == 0 then
      -- Flash border
      rectf(S, 0, 0, W, 2, alpha)
      rectf(S, 0, H - 2, W, 2, alpha)
      rectf(S, 0, 0, 2, H, alpha)
      rectf(S, W - 2, 0, 2, H, alpha)
    end
  end

  -- Death flash
  if p_flash > 0 and p_flash % 2 == 0 then
    rectf(S, 0, 0, W, H, 15)
  end
end

---------- DRAW: TITLE SCREEN ----------
local function draw_title()
  cls(S, 0)
  local f = frame()

  -- Animated starfield
  draw_stars()

  -- Decorative lines
  line(S, 20, 22, 140, 22, 4)
  line(S, 20, 23, 140, 23, 2)

  -- Title
  text_center("VOID STORM", W / 2, 30, 15)
  line(S, 30, 38, 130, 38, 4)
  line(S, 30, 39, 130, 39, 2)

  -- Ship display
  local sx = W / 2
  local sy = 52
  rectf(S, sx - 2, sy - 5, 4, 8, 13)
  rectf(S, sx - 1, sy - 6, 2, 2, 15)
  rectf(S, sx - 6, sy - 1, 12, 3, 11)
  rectf(S, sx - 5, sy - 2, 10, 1, 10)
  rectf(S, sx - 1, sy - 3, 2, 5, 14)
  -- Engine flicker
  local glow = 8 + (f % 3)
  rectf(S, sx - 1, sy + 4, 2, 2, glow)

  -- Controls
  text_center("D-PAD:MOVE", W / 2, 68, 8)
  text_center("A:SHOOT  B:BOMB", W / 2, 77, 8)

  -- Start prompt (blinking)
  if math.floor(f / 15) % 2 == 0 then
    text_center("PRESS START", W / 2, 95, 12)
  end

  -- High score
  if high_score > 0 then
    text_center("HI:" .. string.format("%06d", high_score), W / 2, 108, 7)
  end
end

---------- DRAW: PAUSE ----------
local function draw_pause()
  rectf(S, 40, 45, 80, 30, 0)
  rect(S, 40, 45, 80, 30, 10)
  rect(S, 41, 46, 78, 28, 5)
  text_center("PAUSED", W / 2, 52, 15)
  if math.floor(frame() / 20) % 2 == 0 then
    text_center("PRESS START", W / 2, 64, 10)
  end
end

---------- DRAW: GAME OVER ----------
local function draw_gameover()
  -- Darken effect
  rectf(S, 30, 30, 100, 60, 0)
  rect(S, 30, 30, 100, 60, 8)
  rect(S, 31, 31, 98, 58, 4)

  text_center("GAME OVER", W / 2, 38, 15)

  line(S, 42, 46, 118, 46, 5)

  text_center("SCORE", W / 2, 52, 8)
  text_center(string.format("%06d", score), W / 2, 60, 15)

  text_center("WAVE " .. wave_num, W / 2, 70, 10)

  if score >= high_score and score > 0 then
    if frame() % 20 < 14 then
      text_center("NEW HIGH SCORE!", W / 2, 78, 15)
    end
  end

  if math.floor(frame() / 15) % 2 == 0 then
    text_center("PRESS START", W / 2, 84, 12)
  end
end

---------- DRAW: PLAY ----------
draw_play = function()
  cls(S, 0)
  draw_stars()
  draw_powerups()
  draw_bullets()

  -- Draw all enemies
  for i = 1, #enemies do
    draw_enemy(enemies[i])
  end

  draw_boss()
  draw_player()
  draw_particles()
  draw_hud()

  if paused then
    draw_pause()
  end
end

---------- 7-SEGMENT CLOCK (ATTRACT MODE) ----------
-- Segment layout for a digit ~7px wide x 11px tall, 2px thick
--  _a_
-- |   |
-- f   b
-- |_g_|
-- |   |
-- e   c
-- |_d_|
local SEG_PATTERNS = {
  [0] = 0x3F, -- abcdef  = 0b0111111
  [1] = 0x06, -- bc      = 0b0000110
  [2] = 0x5B, -- abdeg   = 0b1011011
  [3] = 0x4F, -- abcdg   = 0b1001111
  [4] = 0x66, -- bcfg    = 0b1100110
  [5] = 0x6D, -- acdfg   = 0b1101101
  [6] = 0x7D, -- acdefg  = 0b1111101
  [7] = 0x07, -- abc     = 0b0000111
  [8] = 0x7F, -- abcdefg = 0b1111111
  [9] = 0x6F, -- abcdfg  = 0b1101111
}

local function draw_seg_digit(x, y, digit, c)
  local p = SEG_PATTERNS[digit] or 0
  -- a: top horizontal
  if p & 0x01 ~= 0 then rectf(S, x + 2, y, 3, 2, c) end
  -- b: top-right vertical
  if p & 0x02 ~= 0 then rectf(S, x + 5, y + 1, 2, 4, c) end
  -- c: bottom-right vertical
  if p & 0x04 ~= 0 then rectf(S, x + 5, y + 6, 2, 4, c) end
  -- d: bottom horizontal
  if p & 0x08 ~= 0 then rectf(S, x + 2, y + 9, 3, 2, c) end
  -- e: bottom-left vertical
  if p & 0x10 ~= 0 then rectf(S, x, y + 6, 2, 4, c) end
  -- f: top-left vertical
  if p & 0x20 ~= 0 then rectf(S, x, y + 1, 2, 4, c) end
  -- g: middle horizontal
  if p & 0x40 ~= 0 then rectf(S, x + 2, y + 5, 3, 2, c) end
end

local function draw_clock()
  local t = date()
  local h = t.hour or 0
  local m = t.min or 0
  local c = 3 -- dim color
  local ox = W - 39 -- top-right corner
  local oy = 1

  -- HH
  draw_seg_digit(ox, oy, math.floor(h / 10), c)
  draw_seg_digit(ox + 9, oy, h % 10, c)

  -- Colon (blinks every 30 frames)
  if math.floor(frame() / 30) % 2 == 0 then
    rectf(S, ox + 17, oy + 3, 2, 2, c)
    rectf(S, ox + 17, oy + 7, 2, 2, c)
  end

  -- MM
  draw_seg_digit(ox + 21, oy, math.floor(m / 10), c)
  draw_seg_digit(ox + 30, oy, m % 10, c)
end

---------- DRAW: ATTRACT OVERLAY ----------
local function draw_attract_overlay()
  -- Semi-transparent banner at top
  rectf(S, 0, 0, W, 11, 0)
  text_center("VOID STORM", W / 2, 2, 15)

  -- 7-segment clock in top-right
  draw_clock()

  -- Blinking PRESS START overlay
  if math.floor(frame() / 12) % 2 == 0 then
    rectf(S, W / 2 - 36, H - 18, 72, 11, 0)
    rect(S, W / 2 - 36, H - 18, 72, 11, 10)
    text_center("PRESS START", W / 2, H - 15, 15)
  end
end

---------- ENGINE CALLBACKS ----------
function _init()
  mode(4)
end

function _start()
  high_score = 0
  state = "title"
  attract_timer = 0
  init_stars()
end

function _update()
  if state == "title" then
    update_stars()
    attract_timer = attract_timer + 1

    if btnp("start") or (touch_start and touch_start()) then
      init_game()
      state = "play"
      attract_timer = 0
      touch_last_tap_time = -999
      return
    end

    -- Enter attract mode after idle
    if attract_timer >= ATTRACT_IDLE_FRAMES then
      state = "attract"
      attract_frame = 0
      ai_dodge_timer = 0
      init_game()
      p_weapon = 2 -- give spread for flashy demo
      p_lives = 99 -- don't die in attract
      p_shield = 2
      return
    end

  elseif state == "attract" then
    attract_frame = attract_frame + 1

    -- Exit attract on any button press or touch
    if btnp("start") or btnp("a") or btnp("b") or btnp("up") or btnp("down") or btnp("left") or btnp("right") or btnp("select") or (touch_start and touch_start()) then
      state = "title"
      attract_timer = 0
      init_stars()
      return
    end

    -- Loop demo indefinitely: restart when sequence ends
    if attract_frame >= ATTRACT_DURATION then
      attract_frame = 0
      ai_dodge_timer = 0
      init_game()
      p_weapon = 2   -- spread for flashy demo
      p_lives = 99   -- don't die in attract
      p_shield = 2
    end

    update_play()

  elseif state == "play" then
    -- Pause toggle
    if btnp("start") or btnp("select") then
      paused = not paused
      return
    end
    if not paused then
      update_play()
    end

  elseif state == "gameover" then
    update_stars()
    update_particles()
    if btnp("start") or (touch_start and touch_start()) then
      state = "title"
      attract_timer = 0
      init_stars()
    end
  end
end

function _draw()
  S = screen()

  if state == "title" then
    draw_title()
  elseif state == "attract" then
    draw_play()
    draw_attract_overlay()
  elseif state == "play" then
    draw_play()
  elseif state == "gameover" then
    draw_play()
    draw_gameover()
  end
end
