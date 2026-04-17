-- SHAKE FIGHTER
-- Motion-controlled 1v1 fighting game
-- Punch by thrusting phone forward, block by holding still, dodge by tilting!
-- 160x120 | 16 grayscale | 30fps

---------- CONSTANTS ----------
local W = 160
local H = 120
local S -- screen surface

-- Colors (1-bit mode: 0=black, 1=white)
local C_BG = 0
local C_RING = 1
local C_ROPE = 1
local C_HUD = 1
local C_HP_P = 1
local C_HP_E = 1
local C_STAM = 1
local C_TEXT = 1
local C_SHADOW = 0
local C_FLASH = 1

-- Ring bounds
local RING_LEFT = 16
local RING_RIGHT = 144
local RING_FLOOR = 90
local RING_Y = 88

-- Fighter dimensions
local FIGHTER_W = 20
local FIGHTER_H = 32

-- Motion thresholds
local THRESH_JAB = 0.3
local THRESH_POWER = 0.6
local THRESH_UPPER = 0.5
local THRESH_BLOCK_XY = 0.1
local THRESH_BLOCK_Z = 0.15
local THRESH_DODGE = 0.4

-- Combat
local MAX_HP = 100
local MAX_STAMINA = 100
local JAB_DAMAGE = 8
local POWER_DAMAGE = 18
local UPPER_DAMAGE = 22
local JAB_STAM_COST = 10
local POWER_STAM_COST = 25
local UPPER_STAM_COST = 30
local BLOCK_REDUCTION = 0.3
local STAMINA_REGEN = 0.6
local BLOCK_STAM_DRAIN = 0.15

-- Timing (frames)
local JAB_WINDUP = 3
local JAB_ACTIVE = 4
local JAB_RECOVERY = 8
local POWER_WINDUP = 8
local POWER_ACTIVE = 5
local POWER_RECOVERY = 14
local UPPER_WINDUP = 6
local UPPER_ACTIVE = 5
local UPPER_RECOVERY = 12
local DODGE_DURATION = 12
local HIT_STUN = 10
local KNOCKDOWN_DURATION = 60
local KO_COUNT_FRAMES = 30    -- frames per count digit
local ROUND_PAUSE = 60
local ROUND_TIME = 90 * 30   -- 90 seconds * 30fps

-- Round system
local MAX_ROUNDS = 3
local WINS_NEEDED = 2

-- Attract / demo
local ATTRACT_IDLE = 150      -- 5 seconds at 30fps
local ATTRACT_DURATION = 450  -- 15 seconds

---------- UTILITY ----------
local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function text_center(str, y, c)
  text(S, str, W / 2, y, c, ALIGN_CENTER)
end

local function sfx_note(ch, n, dur)
  if note then note(ch, n, dur) end
end

local function sfx_noise(ch, dur)
  if noise then noise(ch, dur) end
end

---------- FORWARD DECLARATIONS ----------
local has_motion = false

---------- GLOBAL STATE ----------
local state            -- "title", "fight", "round_end", "match_end", "attract"
local attract_timer = 0
local idle_timer = 0

-- Round tracking
local current_round = 0
local p_wins = 0
local e_wins = 0
local round_timer = 0
local round_pause_timer = 0
local round_result = ""

-- Screen shake
local shake_x = 0
local shake_y = 0
local shake_timer = 0
local shake_amt = 0

-- Particles
local particles = {}

---------- FIGHTER ----------
local function new_fighter(x, facing, is_player)
  return {
    x = x,
    y = RING_Y,
    facing = facing,      -- 1 = right, -1 = left
    is_player = is_player,
    hp = MAX_HP,
    stamina = MAX_STAMINA,
    -- States: "idle","windup","attack","recovery","block","dodge","hit","knockdown","ko"
    state = "idle",
    state_timer = 0,
    attack_type = nil,    -- "jab","power","uppercut"
    dodge_dir = 0,        -- -1 left, 1 right
    knockdowns = 0,
    ko = false,
    hit_landed = false,   -- prevent multi-hit per attack
    -- Animation
    anim_frame = 0,
    flash_timer = 0,
    -- AI fields
    ai_action_timer = 0,
    ai_aggression = 0.4,
    ai_react_speed = 8,
  }
end

local player = nil
local enemy = nil

---------- PARTICLES ----------
local function spawn_particle(x, y, vx, vy, life, color, size)
  if #particles < 40 then
    table.insert(particles, {
      x = x, y = y, vx = vx, vy = vy,
      life = life, max_life = life,
      color = color, size = size or 1,
    })
  end
end

local function spawn_hit_particles(x, y, count, color)
  for i = 1, count do
    local angle = math.random() * math.pi * 2
    local spd = 0.5 + math.random() * 2
    spawn_particle(x, y,
      math.cos(angle) * spd,
      math.sin(angle) * spd - 1,
      8 + math.random(0, 8),
      color or C_FLASH, 1 + math.random(0, 1))
  end
end

local function update_particles()
  local i = 1
  while i <= #particles do
    local p = particles[i]
    p.x = p.x + p.vx
    p.y = p.y + p.vy
    p.vy = p.vy + 0.08
    p.life = p.life - 1
    if p.life <= 0 then
      table.remove(particles, i)
    else
      i = i + 1
    end
  end
end

local function draw_particles()
  for _, p in ipairs(particles) do
    local c = (p.life > 0) and 1 or 0
    if p.size > 1 then
      rectf(S, math.floor(p.x), math.floor(p.y), p.size, p.size, c)
    else
      pix(S, math.floor(p.x), math.floor(p.y), c)
    end
  end
end

---------- SCREEN SHAKE ----------
local function do_shake(amount, duration)
  shake_amt = amount
  shake_timer = duration
end

local function update_shake()
  if shake_timer > 0 then
    shake_timer = shake_timer - 1
    shake_x = math.random(-shake_amt, shake_amt)
    shake_y = math.random(-shake_amt, shake_amt)
  else
    shake_x = 0
    shake_y = 0
  end
end

---------- MOTION INPUT ----------
local function read_motion()
  if not has_motion then
    return 0, 0, 0
  end
  local mx = motion_x() or 0
  local my = motion_y() or 0
  local mz = motion_z() or 0
  return mx, my, mz
end

local function get_player_action()
  local mx, my, mz = read_motion()
  local amx = math.abs(mx)
  local amy = math.abs(my)
  local amz = math.abs(mz)

  -- Motion controls (prioritized)
  if has_motion then
    -- Block: phone held very still
    if amx < THRESH_BLOCK_XY and amy < THRESH_BLOCK_XY and amz < THRESH_BLOCK_Z then
      return "block", 0
    end
    -- Uppercut: strong upward motion
    if my > THRESH_UPPER and amz < THRESH_POWER then
      return "uppercut", 0
    end
    -- Power punch: big forward thrust
    if amz > THRESH_POWER then
      return "power", 0
    end
    -- Jab: moderate forward thrust
    if amz > THRESH_JAB then
      return "jab", 0
    end
    -- Dodge: tilt left/right
    if mx < -THRESH_DODGE then
      return "dodge", -1
    elseif mx > THRESH_DODGE then
      return "dodge", 1
    end
  end

  -- Button fallback
  if btn("b") then
    return "block", 0
  end
  if btnp("a") then
    -- Check for uppercut (up+A)
    if btn("up") then
      return "uppercut", 0
    end
    return "jab", 0
  end
  -- Double-tap A for power (hold down+A)
  if btnp("a") and btn("down") then
    return "power", 0
  end
  if btnp("left") then
    return "dodge", -1
  end
  if btnp("right") then
    return "dodge", 1
  end

  return "none", 0
end

---------- COMBAT LOGIC ----------
local function get_attack_params(attack_type)
  if attack_type == "jab" then
    return JAB_DAMAGE, JAB_STAM_COST, JAB_WINDUP, JAB_ACTIVE, JAB_RECOVERY
  elseif attack_type == "power" then
    return POWER_DAMAGE, POWER_STAM_COST, POWER_WINDUP, POWER_ACTIVE, POWER_RECOVERY
  elseif attack_type == "uppercut" then
    return UPPER_DAMAGE, UPPER_STAM_COST, UPPER_WINDUP, UPPER_ACTIVE, UPPER_RECOVERY
  end
  return 0, 0, 0, 0, 0
end

local function start_attack(f, attack_type)
  local _, cost = get_attack_params(attack_type)
  if f.stamina < cost then return false end
  f.state = "windup"
  f.attack_type = attack_type
  local _, _, windup = get_attack_params(attack_type)
  f.state_timer = windup
  f.stamina = f.stamina - cost
  f.hit_landed = false
  return true
end

local function start_block(f)
  f.state = "block"
  f.state_timer = 0
end

local function start_dodge(f, dir)
  if f.stamina < 15 then return end
  f.state = "dodge"
  f.dodge_dir = dir
  f.state_timer = DODGE_DURATION
  f.stamina = f.stamina - 15
end

local function fighters_in_range(attacker, defender)
  local dist = math.abs(attacker.x - defender.x)
  return dist < 28
end

local function apply_hit(attacker, defender, attack_type)
  if attacker.hit_landed then return end
  if not fighters_in_range(attacker, defender) then return end

  -- Dodge avoids everything
  if defender.state == "dodge" then return end

  local damage = get_attack_params(attack_type)

  -- Block reduces damage
  if defender.state == "block" then
    damage = math.floor(damage * BLOCK_REDUCTION)
    defender.stamina = defender.stamina - 8
    sfx_noise(1, 0.08)
    spawn_hit_particles(defender.x, defender.y - 16, 3, 1)
  else
    -- Full hit
    defender.state = "hit"
    defender.state_timer = HIT_STUN
    if attack_type == "power" then
      do_shake(3, 6)
      sfx_noise(0, 0.2)
      sfx_note(1, "C2", 0.15)
      spawn_hit_particles(defender.x, defender.y - 18, 8, C_FLASH)
    elseif attack_type == "uppercut" then
      do_shake(4, 8)
      sfx_noise(0, 0.25)
      sfx_note(1, "D2", 0.2)
      spawn_hit_particles(defender.x, defender.y - 22, 10, C_FLASH)
    else
      do_shake(1, 3)
      sfx_noise(0, 0.1)
      spawn_hit_particles(defender.x, defender.y - 16, 5, 1)
    end
    defender.flash_timer = 4
  end

  defender.hp = math.max(0, defender.hp - damage)
  attacker.hit_landed = true

  -- Knockdown check
  if defender.hp <= 0 then
    defender.state = "knockdown"
    defender.state_timer = KNOCKDOWN_DURATION
    defender.knockdowns = defender.knockdowns + 1
    do_shake(5, 12)
    sfx_noise(0, 0.4)
    sfx_note(1, "A1", 0.3)
    sfx_note(2, "E1", 0.3)
    spawn_hit_particles(defender.x, defender.y - 16, 15, C_FLASH)
  elseif damage > 15 and defender.state == "hit" and math.random() < 0.15 then
    -- Random knockdown on big hits
    defender.state = "knockdown"
    defender.state_timer = KNOCKDOWN_DURATION
    defender.knockdowns = defender.knockdowns + 1
    do_shake(4, 8)
  end
end

---------- FIGHTER UPDATE ----------
local function update_fighter(f, action, action_dir)
  f.anim_frame = f.anim_frame + 1

  -- Flash timer
  if f.flash_timer > 0 then
    f.flash_timer = f.flash_timer - 1
  end

  -- Stamina regen (slower while blocking)
  if f.state == "block" then
    f.stamina = math.min(MAX_STAMINA, f.stamina - BLOCK_STAM_DRAIN)
    if f.stamina <= 0 then
      f.state = "idle"
      f.stamina = 0
    end
  else
    f.stamina = math.min(MAX_STAMINA, f.stamina + STAMINA_REGEN)
  end

  -- State machine
  if f.state == "ko" then
    return
  end

  if f.state == "knockdown" then
    f.state_timer = f.state_timer - 1
    if f.state_timer <= 0 then
      if f.hp <= 0 then
        f.state = "ko"
        f.ko = true
      else
        f.state = "idle"
        f.hp = math.max(f.hp, 10)
      end
    end
    return
  end

  if f.state == "hit" then
    f.state_timer = f.state_timer - 1
    if f.state_timer <= 0 then
      f.state = "idle"
    end
    return
  end

  if f.state == "dodge" then
    f.state_timer = f.state_timer - 1
    f.x = f.x + f.dodge_dir * 2.5
    f.x = clamp(f.x, RING_LEFT + 8, RING_RIGHT - 8)
    if f.state_timer <= 0 then
      f.state = "idle"
    end
    return
  end

  if f.state == "windup" then
    f.state_timer = f.state_timer - 1
    if f.state_timer <= 0 then
      f.state = "attack"
      local _, _, _, active = get_attack_params(f.attack_type)
      f.state_timer = active
      -- Sound for windup -> attack transition
      if f.attack_type == "jab" then
        sfx_note(0, "G4", 0.03)
      elseif f.attack_type == "power" then
        sfx_note(0, "C3", 0.06)
      elseif f.attack_type == "uppercut" then
        sfx_note(0, "E3", 0.05)
      end
    end
    return
  end

  if f.state == "attack" then
    f.state_timer = f.state_timer - 1
    if f.state_timer <= 0 then
      f.state = "recovery"
      local _, _, _, _, recovery = get_attack_params(f.attack_type)
      f.state_timer = recovery
    end
    return
  end

  if f.state == "recovery" then
    f.state_timer = f.state_timer - 1
    if f.state_timer <= 0 then
      f.state = "idle"
    end
    return
  end

  -- Idle or block: can accept new actions
  if f.state == "idle" or f.state == "block" then
    if action == "block" then
      if f.state ~= "block" then
        start_block(f)
      end
    elseif action == "jab" or action == "power" or action == "uppercut" then
      start_attack(f, action)
    elseif action == "dodge" then
      start_dodge(f, action_dir)
    else
      if f.state == "block" then
        f.state = "idle"
      end
    end
  end
end

---------- AI OPPONENT ----------
local function ai_decide(ai, target)
  ai.ai_action_timer = ai.ai_action_timer - 1
  if ai.ai_action_timer > 0 then
    return "none", 0
  end

  local dist = math.abs(ai.x - target.x)
  local in_range = dist < 30
  local close = dist < 20

  -- React to player attacks
  if target.state == "windup" or target.state == "attack" then
    if math.random() < 0.6 then
      ai.ai_action_timer = ai.ai_react_speed
      if math.random() < 0.4 then
        -- Dodge
        local dir = ai.x < target.x and -1 or 1
        return "dodge", dir
      else
        return "block", 0
      end
    end
  end

  -- Offensive when target is recovering or in hitstun
  if target.state == "recovery" or target.state == "hit" then
    if in_range and math.random() < ai.ai_aggression + 0.3 then
      ai.ai_action_timer = 6
      local r = math.random()
      if r < 0.5 then return "jab", 0
      elseif r < 0.8 then return "power", 0
      else return "uppercut", 0 end
    end
  end

  -- Approach if far
  if not in_range then
    ai.ai_action_timer = 3
    local dir = target.x > ai.x and 1 or -1
    ai.x = ai.x + dir * 1.2
    ai.x = clamp(ai.x, RING_LEFT + 8, RING_RIGHT - 8)
    return "none", 0
  end

  -- Random attacks when in range
  if in_range and math.random() < ai.ai_aggression then
    ai.ai_action_timer = 10 + math.random(0, 10)
    local r = math.random()
    if r < 0.45 then return "jab", 0
    elseif r < 0.75 then return "power", 0
    elseif r < 0.9 then return "uppercut", 0
    else return "block", 0 end
  end

  -- Idle behavior
  ai.ai_action_timer = 4 + math.random(0, 6)

  -- Subtle movement
  if close then
    local dir = ai.x < target.x and -1 or 1
    ai.x = ai.x + dir * 0.5
  end

  -- Sometimes block preemptively
  if math.random() < 0.15 then
    return "block", 0
  end

  return "none", 0
end

---------- DRAW FIGHTER ----------
local function draw_fighter(f, color_body, color_detail)
  local x = math.floor(f.x + shake_x)
  local y = math.floor(f.y + shake_y)
  local facing = f.facing

  -- Flash on hit
  if f.flash_timer > 0 and f.flash_timer % 2 == 0 then
    color_body = C_FLASH
    color_detail = C_FLASH
  end

  -- Knockdown / KO: lying down
  if f.state == "knockdown" or f.state == "ko" then
    -- Body horizontal on ground
    rectf(S, x - 10, y - 4, 20, 6, color_body)
    -- Head
    rectf(S, x + facing * 10, y - 6, 5, 5, color_detail)
    -- Stars if KO
    if f.state == "ko" then
      local t = f.anim_frame
      for i = 0, 2 do
        local a = t * 0.1 + i * 2.09
        local sx = x + math.cos(a) * 8
        local sy = y - 10 + math.sin(a) * 4
        pix(S, math.floor(sx), math.floor(sy), C_TEXT)
      end
    end
    return
  end

  -- Shadow
  rectf(S, x - 8, y + 1, 16, 2, C_SHADOW)

  -- Dodge: shifted and slightly transparent
  if f.state == "dodge" then
    local ox = f.dodge_dir * 4
    -- Ghost trail
    rectf(S, x - ox - 4, y - 24, 8, 18, C_SHADOW)
    x = x + ox
  end

  -- Body
  local body_top = y - 26
  rectf(S, x - 5, body_top + 8, 10, 14, color_body)  -- torso
  rectf(S, x - 3, body_top, 6, 8, color_detail)        -- head
  -- Eyes
  pix(S, x + facing * 1, body_top + 3, C_BG)
  pix(S, x + facing * 3, body_top + 3, C_BG)

  -- Legs
  local leg_spread = 0
  if f.state == "block" then leg_spread = 2 end
  rectf(S, x - 4 - leg_spread, y - 8, 3, 8, color_body)
  rectf(S, x + 1 + leg_spread, y - 8, 3, 8, color_body)

  -- Arms / fists based on state
  local fist_color = color_body

  if f.state == "block" then
    -- Arms up in guard
    rectf(S, x - 7, body_top + 4, 3, 8, color_body)
    rectf(S, x + 4, body_top + 4, 3, 8, color_body)
    -- Gloves at face level
    rectf(S, x - 8, body_top + 2, 4, 4, fist_color)
    rectf(S, x + 4, body_top + 2, 4, 4, fist_color)
  elseif f.state == "windup" then
    -- Pulling back
    local pull = facing * -6
    rectf(S, x + pull - 2, body_top + 8, 3, 6, color_body)
    rectf(S, x + pull - 2, body_top + 6, 4, 4, fist_color)
    -- Other arm guard
    rectf(S, x - facing * 4, body_top + 6, 3, 6, color_body)
    rectf(S, x - facing * 5, body_top + 4, 4, 4, fist_color)
  elseif f.state == "attack" then
    -- Extended punch
    local ext = facing * 12
    if f.attack_type == "uppercut" then
      -- Fist goes up
      rectf(S, x + facing * 4, body_top - 4, 3, 10, color_body)
      rectf(S, x + facing * 3, body_top - 6, 5, 5, fist_color)
    else
      -- Forward punch
      rectf(S, x + ext - 2, body_top + 8, facing * 8, 3, color_body)
      rectf(S, x + ext - 2, body_top + 7, 5, 5, fist_color)
    end
    -- Other arm back
    rectf(S, x - facing * 6, body_top + 10, 3, 4, color_body)
  elseif f.state == "hit" then
    -- Recoiling
    local recoil = -facing * 2
    rectf(S, x + recoil - 6, body_top + 10, 3, 6, color_body)
    rectf(S, x + recoil + 3, body_top + 10, 3, 6, color_body)
  else
    -- Idle stance - subtle bob
    local bob = math.sin(f.anim_frame * 0.15) * 1
    -- Lead arm
    rectf(S, x + facing * 6, body_top + 6 + math.floor(bob), 3, 6, color_body)
    rectf(S, x + facing * 6, body_top + 4 + math.floor(bob), 4, 4, fist_color)
    -- Rear arm
    rectf(S, x - facing * 6, body_top + 10, 3, 5, color_body)
    rectf(S, x - facing * 7, body_top + 8, 4, 4, fist_color)
  end
end

---------- DRAW RING ----------
local function draw_ring()
  local ox = shake_x
  local oy = shake_y

  -- Ring floor
  rectf(S, RING_LEFT + ox, RING_FLOOR + oy, RING_RIGHT - RING_LEFT, 4, C_RING)
  -- Below ring
  rectf(S, RING_LEFT + ox - 2, RING_FLOOR + 4 + oy, RING_RIGHT - RING_LEFT + 4, 30, 0)

  -- Corner posts
  for _, px in ipairs({RING_LEFT, RING_RIGHT}) do
    rectf(S, px - 2 + ox, 38 + oy, 4, RING_FLOOR - 38, 1)
  end

  -- Ropes
  for i = 0, 2 do
    local ry = 44 + i * 14 + oy
    line(S, RING_LEFT + ox, ry, RING_RIGHT + ox, ry, C_ROPE)
  end
end

---------- DRAW HUD ----------
local function draw_hud()
  -- Player HP bar (left)
  rectf(S, 4, 4, 62, 6, 0)
  local pw = math.floor((player.hp / MAX_HP) * 60)
  if pw > 0 then
    rectf(S, 5, 5, pw, 4, 1)
  end

  -- Enemy HP bar (right, fills from right)
  rectf(S, 94, 4, 62, 6, 0)
  local ew = math.floor((enemy.hp / MAX_HP) * 60)
  if ew > 0 then
    rectf(S, 95 + (60 - ew), 5, ew, 4, 1)
  end

  -- Names
  text(S, "YOU", 5, 11, 1)
  text(S, "CPU", 138, 11, 1)

  -- Stamina bars (smaller, below HP)
  rectf(S, 4, 18, 42, 3, 0)
  local ps = math.floor((player.stamina / MAX_STAMINA) * 40)
  if ps > 0 then
    rectf(S, 5, 19, ps, 1, 1)
  end
  rectf(S, 114, 18, 42, 3, 0)
  local es = math.floor((enemy.stamina / MAX_STAMINA) * 40)
  if es > 0 then
    rectf(S, 115 + (40 - es), 19, es, 1, 1)
  end

  -- Round indicator
  text_center("R" .. current_round, 3, 1)

  -- Round wins
  for i = 1, p_wins do
    rectf(S, 66 - i * 6, 12, 4, 4, 1)
  end
  for i = 1, e_wins do
    rectf(S, 88 + (i - 1) * 6, 12, 4, 4, 1)
  end

  -- Timer
  local secs = math.max(0, math.floor(round_timer / 30))
  text_center(string.format("%02d", secs), 23, 1)
end

---------- GAME INIT ----------
local function init_round()
  player = new_fighter(55, 1, true)
  enemy = new_fighter(105, -1, false)
  enemy.ai_aggression = 0.3 + current_round * 0.1
  enemy.ai_react_speed = math.max(4, 10 - current_round * 2)
  round_timer = ROUND_TIME
  particles = {}
  shake_timer = 0
  shake_x = 0
  shake_y = 0
end

local function init_match()
  current_round = 1
  p_wins = 0
  e_wins = 0
  round_result = ""
  init_round()
  state = "fight"
end

---------- ROUND END LOGIC ----------
local function check_round_end()
  if player.ko then
    e_wins = e_wins + 1
    round_result = "KO!"
    round_pause_timer = ROUND_PAUSE * 2
    state = "round_end"
    sfx_note(0, "C2", 0.5)
    sfx_note(1, "E2", 0.5)
    return true
  end
  if enemy.ko then
    p_wins = p_wins + 1
    round_result = "KO!"
    round_pause_timer = ROUND_PAUSE * 2
    state = "round_end"
    sfx_note(0, "C5", 0.15)
    sfx_note(1, "E5", 0.15)
    sfx_note(2, "G5", 0.15)
    return true
  end
  if round_timer <= 0 then
    -- Decision by HP
    if player.hp > enemy.hp then
      p_wins = p_wins + 1
      round_result = "DECISION"
    elseif enemy.hp > player.hp then
      e_wins = e_wins + 1
      round_result = "DECISION"
    else
      -- Draw goes to nobody; extra round if possible
      round_result = "DRAW"
    end
    round_pause_timer = ROUND_PAUSE * 2
    state = "round_end"
    return true
  end
  return false
end

---------- FIGHT UPDATE ----------
local function update_fight()
  -- Decrement round timer
  round_timer = round_timer - 1

  -- Player input
  local action, action_dir = get_player_action()
  update_fighter(player, action, action_dir)

  -- AI input
  local ai_action, ai_dir = ai_decide(enemy, player)
  update_fighter(enemy, ai_action, ai_dir)

  -- Face each other
  if player.state == "idle" then
    player.facing = player.x < enemy.x and 1 or -1
  end
  if enemy.state == "idle" then
    enemy.facing = enemy.x < player.x and 1 or -1
  end

  -- Hit detection during attack active frames
  if player.state == "attack" then
    apply_hit(player, enemy, player.attack_type)
  end
  if enemy.state == "attack" then
    apply_hit(enemy, player, enemy.attack_type)
  end

  update_particles()
  update_shake()

  check_round_end()
end

---------- FIGHT DRAW ----------
local function draw_fight()
  draw_ring()

  -- Draw fighters (back one first)
  if player.x < enemy.x then
    draw_fighter(player, 1, 1)
    draw_fighter(enemy, 1, 1)
  else
    draw_fighter(enemy, 1, 1)
    draw_fighter(player, 1, 1)
  end

  draw_particles()
  draw_hud()

  -- Action labels
  if player.state == "attack" then
    local label = player.attack_type == "jab" and "JAB" or
                  player.attack_type == "power" and "POW" or "UP!"
    text(S, label, math.floor(player.x) - 6, math.floor(player.y) - 34, C_TEXT)
  end
  if enemy.state == "attack" then
    local label = enemy.attack_type == "jab" and "JAB" or
                  enemy.attack_type == "power" and "POW" or "UP!"
    text(S, label, math.floor(enemy.x) - 6, math.floor(enemy.y) - 34, C_HP_E)
  end
end

---------- ROUND END ----------
local function update_round_end()
  round_pause_timer = round_pause_timer - 1
  update_particles()
  update_shake()

  if round_pause_timer <= 0 then
    -- Check match over
    if p_wins >= WINS_NEEDED or e_wins >= WINS_NEEDED then
      state = "match_end"
      round_pause_timer = ROUND_PAUSE * 3
      if p_wins >= WINS_NEEDED then
        sfx_note(0, "C5", 0.1)
        sfx_note(0, "E5", 0.1)
        sfx_note(0, "G5", 0.1)
        sfx_note(1, "C6", 0.3)
      else
        sfx_note(0, "C3", 0.3)
        sfx_note(1, "G2", 0.3)
      end
      return
    end
    -- Next round
    current_round = current_round + 1
    init_round()
    state = "fight"
  end
end

local function draw_round_end()
  draw_fight()

  -- Overlay
  rectf(S, 30, 42, 100, 36, 0)
  rectf(S, 31, 43, 98, 34, 0)

  text_center(round_result, 48, 1)

  if player.ko or (round_timer <= 0 and enemy.hp > player.hp) then
    text_center("YOU LOSE", 58, 1)
  elseif enemy.ko or (round_timer <= 0 and player.hp > enemy.hp) then
    text_center("YOU WIN!", 58, 1)
  else
    text_center("DRAW", 58, 1)
  end

  text_center("ROUND " .. current_round, 68, 1)
end

---------- MATCH END ----------
local function update_match_end()
  round_pause_timer = round_pause_timer - 1
  update_particles()

  if round_pause_timer <= 0 then
    if btnp("start") or btnp("a") then
      go("title")
    end
  end
end

local function draw_match_end()
  draw_ring()
  draw_particles()

  rectf(S, 20, 30, 120, 60, 0)
  rectf(S, 21, 31, 118, 58, 0)

  if p_wins >= WINS_NEEDED then
    text_center("VICTORY!", 38, 1)
    text_center("YOU ARE THE", 52, 1)
    text_center("SHAKE CHAMPION!", 62, 1)
  else
    text_center("DEFEAT", 38, 1)
    text_center("BETTER LUCK", 52, 1)
    text_center("NEXT TIME...", 62, 1)
  end

  text_center("PRESS START", 78, 1)
end

---------- TITLE SCREEN ----------
local function draw_title_bg()
  -- Stylized background
  cls(S, 0)
  -- Ring silhouette
  rectf(S, 10, 80, 140, 3, 1)
  line(S, 10, 45, 10, 80, 1)
  line(S, 150, 45, 150, 80, 1)
  for i = 0, 2 do
    line(S, 10, 50 + i * 10, 150, 50 + i * 10, 1)
  end
end

---------- ATTRACT MODE ----------
local attract_p, attract_e

local function init_attract()
  attract_p = new_fighter(55, 1, false)
  attract_e = new_fighter(105, -1, false)
  attract_p.ai_aggression = 0.5
  attract_e.ai_aggression = 0.5
end

local function update_attract()
  attract_timer = attract_timer + 1

  -- Both AI controlled
  local a1, d1 = ai_decide(attract_p, attract_e)
  update_fighter(attract_p, a1, d1)
  local a2, d2 = ai_decide(attract_e, attract_p)
  update_fighter(attract_e, a2, d2)

  -- Face each other
  if attract_p.state == "idle" then
    attract_p.facing = attract_p.x < attract_e.x and 1 or -1
  end
  if attract_e.state == "idle" then
    attract_e.facing = attract_e.x < attract_p.x and 1 or -1
  end

  -- Hits
  if attract_p.state == "attack" then
    apply_hit(attract_p, attract_e, attract_p.attack_type)
  end
  if attract_e.state == "attack" then
    apply_hit(attract_e, attract_p, attract_e.attack_type)
  end

  update_particles()
  update_shake()

  -- Reset if someone gets KO'd
  if attract_p.ko or attract_e.ko then
    init_attract()
  end

  -- End attract
  if attract_timer >= ATTRACT_DURATION then
    state = "title"
    idle_timer = 0
    attract_timer = 0
  end

  -- Any button exits attract
  if btnp("start") or btnp("a") or btnp("b") then
    state = "title"
    idle_timer = 0
    attract_timer = 0
  end
end

local function draw_attract()
  draw_ring()

  if attract_p.x < attract_e.x then
    draw_fighter(attract_p, 1, 1)
    draw_fighter(attract_e, 1, 1)
  else
    draw_fighter(attract_e, 1, 1)
    draw_fighter(attract_p, 1, 1)
  end

  draw_particles()

  -- HP bars for attract
  rectf(S, 4, 4, 62, 6, 0)
  local pw = math.floor((attract_p.hp / MAX_HP) * 60)
  if pw > 0 then rectf(S, 5, 5, pw, 4, 1) end
  rectf(S, 94, 4, 62, 6, 0)
  local ew = math.floor((attract_e.hp / MAX_HP) * 60)
  if ew > 0 then rectf(S, 95 + (60 - ew), 5, ew, 4, 1) end

  -- Demo label
  rectf(S, 45, 110, 70, 9, 0)
  text_center("- DEMO -", 111, 1)
end

---------- SCENE: TITLE ----------
function title_init()
  idle_timer = 0
  attract_timer = 0
  state = "title"
  particles = {}
end

function title_update()
  idle_timer = idle_timer + 1

  if state == "attract" then
    update_attract()
    return
  end

  if btnp("start") or btnp("a") then
    go("fight")
    return
  end

  -- Any button press resets idle
  if btnp("b") or btnp("up") or btnp("down") or btnp("left") or btnp("right") then
    idle_timer = 0
  end

  -- Enter attract mode
  if idle_timer >= ATTRACT_IDLE then
    state = "attract"
    attract_timer = 0
    init_attract()
  end
end

function title_draw()
  S = screen()

  if state == "attract" then
    draw_attract()
    return
  end

  draw_title_bg()

  -- Title
  local t = frame()
  local pulse = math.floor(math.sin(t * 0.08) * 2)

  text_center("SHAKE", 20 + pulse, C_FLASH)
  text_center("FIGHTER", 30 + pulse, C_HP_P)

  -- Subtitle
  text_center("MOTION CONTROLLED COMBAT", 48, 1)

  -- Controls
  local cy = 66
  text_center("CONTROLS:", cy, 1)
  if has_motion then
    text(S, "THRUST = PUNCH", 20, cy + 10, 1)
    text(S, "HOLD STILL = BLOCK", 20, cy + 20, 1)
    text(S, "TILT L/R = DODGE", 20, cy + 30, 1)
  else
    text(S, "A = PUNCH  B = BLOCK", 16, cy + 10, 1)
    text(S, "UP+A = UPPERCUT", 16, cy + 20, 1)
    text(S, "L/R = DODGE", 16, cy + 30, 1)
  end

  -- Start prompt
  local blink = math.floor(t * 0.1) % 2
  if blink == 0 then
    text_center("PRESS START", 108, C_TEXT)
  end
end

---------- SCENE: FIGHT ----------
function fight_init()
  init_match()
end

function fight_update()
  if state == "fight" then
    update_fight()
  elseif state == "round_end" then
    update_round_end()
  elseif state == "match_end" then
    update_match_end()
  end
end

function fight_draw()
  S = screen()

  if state == "fight" then
    draw_fight()

    -- Round start announcement
    if round_timer > ROUND_TIME - 45 then
      local t = ROUND_TIME - round_timer
      if t < 30 then
        text_center("ROUND " .. current_round, 40, C_FLASH)
      elseif t < 45 then
        text_center("FIGHT!", 40, C_HP_P)
      end
    end
  elseif state == "round_end" then
    draw_round_end()
  elseif state == "match_end" then
    draw_match_end()
  end
end

---------- MAIN CALLBACKS ----------
function _init()
  mode(1)
  -- Check for motion support
  if motion_enabled then
    has_motion = motion_enabled()
  end
end

function _start()
  go("title")
end
