-- BALANCE TOWER
-- Stack blocks while keeping balance by tilting!
-- Tilt device to shift tower's center of gravity
-- 160x120 | 16 grayscale | 30fps

----------------------------------------------------------------
-- CONSTANTS
----------------------------------------------------------------
local W = 160
local H = 120
local GROUND_Y = 110          -- ground line y
local BLOCK_MIN_W = 12        -- minimum block width
local BLOCK_MAX_W = 28        -- maximum block width
local BLOCK_H = 6             -- block height
local DROP_SPEED = 1.5        -- pixels per frame falling speed
local SWAY_FACTOR = 0.6       -- how much tilt affects sway
local GRAVITY_PULL = 0.15     -- how fast tower leans when off-center
local SWAY_DAMPING = 0.92     -- damping on tower sway velocity
local MAX_LEAN = 18           -- max lean pixels before collapse
local WIND_MIN_INTERVAL = 120 -- min frames between gusts
local WIND_MAX_INTERVAL = 300 -- max frames between gusts
local WIND_DURATION = 40      -- frames a gust lasts
local WIND_FORCE_BASE = 0.3   -- base wind force
local SETTLE_FRAMES = 8       -- frames for block to settle after landing

-- Colors (1-bit: 0=black, 1=white)
local C_BG = 0
local C_GROUND = 1
local C_GROUND_LINE = 1
local C_TEXT = 1
local C_TEXT_DIM = 1
local C_BLOCK_MIN = 1
local C_BLOCK_MAX = 1
local C_DROP_BLOCK = 1
local C_WIND_ARROW = 1
local C_LEAN_WARN = 1
local C_LEAN_DANGER = 1

----------------------------------------------------------------
-- SAFE AUDIO
----------------------------------------------------------------
local function sfx_note(ch, n, dur)
  if note then note(ch, n, dur) end
end
local function sfx_noise(ch, dur)
  if noise then noise(ch, dur) end
end

----------------------------------------------------------------
-- UTILITY
----------------------------------------------------------------
local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function rnd_range(lo, hi)
  return lo + math.random() * (hi - lo)
end

local function rnd_int(lo, hi)
  return math.floor(rnd_range(lo, hi + 0.999))
end

----------------------------------------------------------------
-- MOTION INPUT
----------------------------------------------------------------
local function get_tilt()
  -- Try motion API first, then gyro, then axis fallback
  if motion_enabled and motion_enabled() then
    -- motion_x returns -1 to 1
    local mx = motion_x()
    -- Also blend in gyro for fine control if available
    if gyro_gamma then
      local gy = gyro_gamma() / 90  -- normalize to -1..1
      return clamp(mx * 0.7 + gy * 0.3, -1, 1)
    end
    return mx
  end
  -- Fallback: axis_x (joystick/dpad analog)
  if axis_x then
    return axis_x()
  end
  -- Keyboard fallback
  local t = 0
  if btn and btn("left") then t = t - 1 end
  if btn and btn("right") then t = t + 1 end
  return t
end

----------------------------------------------------------------
-- GLOBAL STATE
----------------------------------------------------------------
local state           -- "title", "play", "gameover", "attract"
local high_score = 0

-- Tower
local blocks          -- stacked blocks: {x, y, w, weight, shade, settle}
local tower_lean      -- current lean offset in pixels
local tower_lean_vel  -- lean velocity
local tower_sway_vis  -- visual sway for rendering

-- Dropping block
local drop_block      -- {x, y, w, weight, shade} or nil
local drop_active     -- is a block currently dropping?

-- Game state
local score
local level
local blocks_placed
local combo           -- consecutive good placements
local combo_max

-- Wind
local wind_timer      -- frames until next gust
local wind_active     -- frames remaining in current gust
local wind_dir        -- -1 or 1
local wind_force      -- current gust strength

-- Effects
local shake_timer
local shake_amt
local particles       -- simple falling debris on collapse
local flash_timer

-- Attract / demo mode
local attract_timer = 0
local attract_frame = 0
local ATTRACT_IDLE_FRAMES = 150   -- 5 seconds idle
local ATTRACT_DURATION = 450      -- 15 seconds demo
local ai_drop_timer = 0

-- Lean indicator
local lean_warn_timer = 0

----------------------------------------------------------------
-- PARTICLES (debris on collapse)
----------------------------------------------------------------
local MAX_PARTICLES = 40

local function add_particle(px, py, vx, vy, life, shade)
  if #particles >= MAX_PARTICLES then return end
  table.insert(particles, {
    x = px, y = py,
    vx = vx, vy = vy,
    life = life,
    max_life = life,
    shade = 1
  })
end

local function update_particles()
  local i = 1
  while i <= #particles do
    local p = particles[i]
    p.x = p.x + p.vx
    p.y = p.y + p.vy
    p.vy = p.vy + 0.2  -- gravity
    p.life = p.life - 1
    if p.life <= 0 or p.y > H then
      table.remove(particles, i)
    else
      i = i + 1
    end
  end
end

local function draw_particles(S)
  for _, p in ipairs(particles) do
    if p.life > 0 then
      rect(S, math.floor(p.x), math.floor(p.y), 2, 2, 1)
    end
  end
end

----------------------------------------------------------------
-- BLOCK GENERATION
----------------------------------------------------------------
local function make_block()
  -- Width varies; higher levels = more variation
  local base_w = rnd_int(BLOCK_MIN_W, BLOCK_MAX_W)
  -- At higher levels, blocks get narrower on average
  local level_factor = math.min(level, 10) / 10
  local w = math.floor(base_w * (1 - level_factor * 0.3))
  w = clamp(w, BLOCK_MIN_W - 2, BLOCK_MAX_W)
  -- Weight correlates with width
  local weight = w / BLOCK_MAX_W
  -- Shade: heavier blocks are brighter
  local shade = 1
  return {
    x = 0, y = 0,
    w = w,
    weight = weight,
    shade = shade,
    settle = 0
  }
end

local function spawn_drop_block()
  local b = make_block()
  -- Start at top center
  b.x = W / 2 - b.w / 2
  b.y = 2
  drop_block = b
  drop_active = true
end

----------------------------------------------------------------
-- TOWER PHYSICS
----------------------------------------------------------------
local function tower_top_y()
  if #blocks == 0 then return GROUND_Y end
  return blocks[#blocks].y
end

local function tower_center_of_mass()
  if #blocks == 0 then return W / 2, GROUND_Y end
  local total_weight = 0
  local weighted_x = 0
  for _, b in ipairs(blocks) do
    local cx = b.x + b.w / 2
    weighted_x = weighted_x + cx * b.weight
    total_weight = total_weight + b.weight
  end
  if total_weight == 0 then return W / 2, GROUND_Y end
  return weighted_x / total_weight, tower_top_y()
end

local function check_collapse()
  return math.abs(tower_lean) > MAX_LEAN
end

local function trigger_collapse()
  -- Spawn debris particles from all blocks
  for _, b in ipairs(blocks) do
    local bx = b.x + b.w / 2 + tower_lean
    local by = b.y
    for _ = 1, 3 do
      add_particle(
        bx + rnd_range(-b.w/2, b.w/2),
        by + rnd_range(-2, 2),
        rnd_range(-3, 3) + tower_lean * 0.1,
        rnd_range(-4, -1),
        rnd_int(20, 40),
        b.shade
      )
    end
  end
  -- Sound: crash
  sfx_noise(0, 0.5)
  sfx_note(1, "C2", 0.4)
  sfx_note(2, "E2", 0.3)
  shake_timer = 20
  shake_amt = 4
end

----------------------------------------------------------------
-- WIND SYSTEM
----------------------------------------------------------------
local function reset_wind()
  wind_timer = rnd_int(WIND_MIN_INTERVAL, WIND_MAX_INTERVAL)
  wind_active = 0
  wind_dir = 0
  wind_force = 0
end

local function update_wind()
  if wind_active > 0 then
    wind_active = wind_active - 1
    if wind_active <= 0 then
      wind_force = 0
      wind_dir = 0
      wind_timer = rnd_int(WIND_MIN_INTERVAL, WIND_MAX_INTERVAL)
    end
  else
    wind_timer = wind_timer - 1
    if wind_timer <= 0 then
      -- Start a gust
      wind_dir = math.random() > 0.5 and 1 or -1
      local level_mult = 1 + math.min(level, 10) * 0.15
      wind_force = WIND_FORCE_BASE * level_mult * rnd_range(0.5, 1.5)
      wind_active = WIND_DURATION + rnd_int(-10, 10)
      -- Sound: whoosh
      sfx_noise(3, 0.2)
    end
  end
end

----------------------------------------------------------------
-- GAME INIT
----------------------------------------------------------------
local function init_game()
  blocks = {}
  tower_lean = 0
  tower_lean_vel = 0
  tower_sway_vis = 0
  drop_block = nil
  drop_active = false
  score = 0
  level = 1
  blocks_placed = 0
  combo = 0
  combo_max = 0
  reset_wind()
  shake_timer = 0
  shake_amt = 0
  particles = {}
  flash_timer = 0
  lean_warn_timer = 0
  spawn_drop_block()
end

----------------------------------------------------------------
-- PLACEMENT LOGIC
----------------------------------------------------------------
local function place_block()
  local b = drop_block
  if not b then return end

  -- Determine landing y
  local land_y = tower_top_y() - BLOCK_H

  -- Offset x by current lean for visual placement
  b.y = land_y
  b.settle = SETTLE_FRAMES

  -- Check alignment with tower
  local tower_cx = W / 2
  if #blocks > 0 then
    local top = blocks[#blocks]
    tower_cx = top.x + top.w / 2
  end
  local block_cx = b.x + b.w / 2
  local offset = math.abs(block_cx - tower_cx)

  -- Score based on alignment
  local alignment_bonus = 0
  if offset < 3 then
    alignment_bonus = 10
    combo = combo + 1
    sfx_note(0, "C5", 0.06)
    sfx_note(1, "E5", 0.06)
  elseif offset < 8 then
    alignment_bonus = 5
    combo = combo + 1
    sfx_note(0, "A4", 0.05)
  else
    alignment_bonus = 1
    combo = 0
    sfx_note(0, "F3", 0.08)
  end

  -- Combo multiplier
  local mult = 1 + math.floor(combo / 3) * 0.5
  score = score + math.floor((alignment_bonus + blocks_placed) * mult)

  if combo > combo_max then combo_max = combo end

  -- Add lean force from placement offset
  tower_lean_vel = tower_lean_vel + (block_cx - W / 2) * 0.02 * b.weight

  table.insert(blocks, b)
  blocks_placed = blocks_placed + 1

  -- Level up every 5 blocks
  if blocks_placed % 5 == 0 then
    level = level + 1
    sfx_note(0, "C6", 0.08)
    sfx_note(1, "G5", 0.08)
    flash_timer = 10
  end

  drop_block = nil
  drop_active = false
end

----------------------------------------------------------------
-- UPDATE: PLAY STATE
----------------------------------------------------------------
local function update_play(tilt, is_ai)
  -- Update wind
  update_wind()

  -- Apply tilt to tower lean
  local tilt_force = tilt * SWAY_FACTOR
  local wind_effect = wind_dir * wind_force
  local height_factor = 1 + #blocks * 0.03  -- taller tower = harder to balance

  tower_lean_vel = tower_lean_vel + (tilt_force + wind_effect) * height_factor * 0.05
  -- Gravity pulling lean toward center of mass offset
  local com_x = tower_center_of_mass()
  local com_offset = (com_x - W / 2) / W
  tower_lean_vel = tower_lean_vel + com_offset * GRAVITY_PULL * height_factor

  -- Damping
  tower_lean_vel = tower_lean_vel * SWAY_DAMPING
  tower_lean = tower_lean + tower_lean_vel

  -- Visual sway (smooth)
  tower_sway_vis = lerp(tower_sway_vis, tower_lean, 0.3)

  -- Lean warning
  if math.abs(tower_lean) > MAX_LEAN * 0.7 then
    lean_warn_timer = lean_warn_timer + 1
    if lean_warn_timer % 15 == 1 then
      sfx_note(2, "A3", 0.04)
    end
  else
    lean_warn_timer = 0
  end

  -- Check collapse
  if check_collapse() then
    trigger_collapse()
    if score > high_score then high_score = score end
    state = "gameover"
    return
  end

  -- Update dropping block
  if drop_active and drop_block then
    local b = drop_block
    -- Move horizontally with tilt
    b.x = b.x + tilt * 2.5
    b.x = clamp(b.x, 2, W - b.w - 2)

    -- Fall
    b.y = b.y + DROP_SPEED

    -- Check landing
    local land_y = tower_top_y() - BLOCK_H
    if b.y >= land_y then
      b.y = land_y
      place_block()
    end
  else
    -- Spawn next block after short delay
    if not drop_active then
      -- Small delay for settling
      local settling = false
      if #blocks > 0 then
        local top = blocks[#blocks]
        if top.settle and top.settle > 0 then
          top.settle = top.settle - 1
          settling = true
        end
      end
      if not settling then
        spawn_drop_block()
      end
    end
  end

  -- Update settling blocks
  for _, b in ipairs(blocks) do
    if b.settle and b.settle > 0 then
      b.settle = b.settle - 1
    end
  end

  -- Shake decay
  if shake_timer > 0 then
    shake_timer = shake_timer - 1
  end

  -- Flash decay
  if flash_timer > 0 then
    flash_timer = flash_timer - 1
  end

  -- Particles
  update_particles()
end

----------------------------------------------------------------
-- AI for attract mode
----------------------------------------------------------------
local function ai_get_tilt()
  -- Simple AI: keep tower balanced, aim blocks at center
  local ai_tilt = 0

  -- Counter the lean
  ai_tilt = ai_tilt - tower_lean * 0.05

  -- Aim dropping block at tower center
  if drop_block and #blocks > 0 then
    local target_x = blocks[#blocks].x + blocks[#blocks].w / 2 - drop_block.w / 2
    local diff = target_x - drop_block.x
    ai_tilt = ai_tilt + clamp(diff * 0.1, -0.5, 0.5)
  elseif drop_block then
    local diff = (W / 2 - drop_block.w / 2) - drop_block.x
    ai_tilt = ai_tilt + clamp(diff * 0.1, -0.5, 0.5)
  end

  return clamp(ai_tilt, -1, 1)
end

----------------------------------------------------------------
-- DRAWING
----------------------------------------------------------------
local function draw_ground(S)
  -- Ground fill
  rect(S, 0, GROUND_Y, W, H - GROUND_Y, C_GROUND)
  -- Ground line
  line(S, 0, GROUND_Y, W, GROUND_Y, C_GROUND_LINE)
end

local function draw_tower(S)
  local sway = math.floor(tower_sway_vis + 0.5)

  -- Draw blocks from bottom to top
  for i, b in ipairs(blocks) do
    -- Each block sways proportional to its height in the tower
    local height_ratio = i / math.max(#blocks, 1)
    local block_sway = math.floor(sway * height_ratio + 0.5)
    local bx = math.floor(b.x + block_sway)
    local by = math.floor(b.y)

    -- Settling animation: slight bounce
    if b.settle and b.settle > 0 then
      by = by - math.floor(math.sin(b.settle / SETTLE_FRAMES * 3.14) * 2)
    end

    -- Block body
    rect(S, bx, by, b.w, BLOCK_H, b.shade)
    -- Block outline (darker)
    local outline = math.max(1, b.shade - 3)
    rect(S, bx, by, b.w, 1, outline)
    rect(S, bx, by + BLOCK_H - 1, b.w, 1, outline)
    rect(S, bx, by, 1, BLOCK_H, outline)
    rect(S, bx + b.w - 1, by, 1, BLOCK_H, outline)
  end
end

local function draw_drop_block(S)
  if not drop_block or not drop_active then return end
  local b = drop_block
  local bx = math.floor(b.x)
  local by = math.floor(b.y)

  -- Flashing drop indicator
  local flash = (math.floor(frame() / 3) % 2 == 0) and C_DROP_BLOCK or b.shade
  rect(S, bx, by, b.w, BLOCK_H, flash)

  -- Drop shadow/guide line
  local land_y = tower_top_y()
  if by < land_y - BLOCK_H then
    for dy = by + BLOCK_H + 2, land_y - 1, 3 do
      rect(S, bx + b.w / 2, dy, 1, 1, 1)
    end
  end
end

local function draw_lean_indicator(S)
  -- Show lean as a bar at the top
  local bar_w = 60
  local bar_x = W / 2 - bar_w / 2
  local bar_y = 2

  -- Background
  rect(S, bar_x, bar_y, bar_w, 3, 1)

  -- Center mark
  rect(S, W / 2, bar_y, 1, 3, C_TEXT_DIM)

  -- Lean position
  local lean_norm = clamp(tower_lean / MAX_LEAN, -1, 1)
  local indicator_x = W / 2 + math.floor(lean_norm * bar_w / 2)

  -- Color based on danger level
  local abs_lean = math.abs(lean_norm)
  local c = C_TEXT
  if abs_lean > 0.7 then
    c = (lean_warn_timer % 6 < 3) and C_LEAN_DANGER or C_LEAN_WARN
  elseif abs_lean > 0.4 then
    c = C_LEAN_WARN
  end

  rect(S, indicator_x - 1, bar_y, 3, 3, c)
end

local function draw_wind_indicator(S)
  if wind_active <= 0 then return end
  -- Show wind direction with arrows
  local wy = 8
  local c = C_WIND_ARROW
  if wind_dir > 0 then
    -- Right arrows
    for i = 0, 2 do
      local ax = 130 + i * 8
      local pulse = math.sin((frame() + i * 5) * 0.3) > 0
      if pulse then
        line(S, ax, wy, ax + 4, wy + 2, c)
        line(S, ax + 4, wy + 2, ax, wy + 4, c)
      end
    end
  else
    -- Left arrows
    for i = 0, 2 do
      local ax = 28 - i * 8
      local pulse = math.sin((frame() + i * 5) * 0.3) > 0
      if pulse then
        line(S, ax, wy, ax - 4, wy + 2, c)
        line(S, ax - 4, wy + 2, ax, wy + 4, c)
      end
    end
  end
  -- "WIND" text
  text(S, "WIND", wind_dir > 0 and 132 or 4, wy - 1, c)
end

local function draw_hud(S)
  -- Score
  text(S, "SCORE:" .. score, 2, GROUND_Y + 2, C_TEXT)
  -- Level
  text(S, "LV" .. level, W - 24, GROUND_Y + 2, C_TEXT_DIM)
  -- Combo
  if combo >= 3 then
    local cc = (frame() % 10 < 5) and C_TEXT or C_TEXT_DIM
    text(S, "x" .. combo, W / 2 - 6, GROUND_Y + 2, cc)
  end
  -- Height
  local height = blocks_placed
  text(S, height .. "BLK", W - 28, 7, C_TEXT_DIM)

  -- Level up flash
  if flash_timer > 0 then
    local fc = (flash_timer % 4 < 2) and C_TEXT or 0
    text(S, "LEVEL " .. level .. "!", W / 2 - 18, 30, fc)
  end
end

----------------------------------------------------------------
-- TITLE SCREEN
----------------------------------------------------------------
local function draw_title(S)
  cls(S, C_BG)

  -- Title
  local ty = 20 + math.floor(math.sin(frame() * 0.05) * 3)
  text(S, "BALANCE", W / 2 - 24, ty, C_TEXT)
  text(S, "TOWER", W / 2 - 17, ty + 12, C_LEAN_WARN)

  -- Decorative tower illustration
  local tx = W / 2
  for i = 0, 5 do
    local bw = 20 - i * 2
    local by = 80 - i * 7
    local sway = math.floor(math.sin(frame() * 0.03 + i * 0.5) * i * 0.8)
    local shade = 1
    rect(S, tx - bw / 2 + sway, by, bw, 6, shade)
  end
  -- Ground
  line(S, tx - 20, 82, tx + 20, 82, C_GROUND_LINE)

  -- Instructions
  local blink = frame() % 40 < 25
  if blink then
    text(S, "TILT TO PLAY", W / 2 - 28, 98, C_TEXT)
  end
  text(S, "PRESS START", W / 2 - 26, 108, C_TEXT_DIM)

  -- High score
  if high_score > 0 then
    text(S, "HI:" .. high_score, 2, 2, C_TEXT_DIM)
  end
end

----------------------------------------------------------------
-- GAME OVER SCREEN
----------------------------------------------------------------
local function draw_gameover(S)
  -- Darken overlay
  rect(S, 20, 25, 120, 70, 1)
  rect(S, 21, 26, 118, 68, 0)

  text(S, "TOWER FELL!", W / 2 - 28, 32, C_LEAN_DANGER)

  text(S, "SCORE", W / 2 - 14, 46, C_TEXT_DIM)
  text(S, tostring(score), W / 2 - #tostring(score) * 3, 56, C_TEXT)

  text(S, "HEIGHT:" .. blocks_placed, W / 2 - 24, 66, C_TEXT_DIM)
  text(S, "BEST COMBO:" .. combo_max, W / 2 - 32, 74, C_TEXT_DIM)

  if score >= high_score and score > 0 then
    local nc = (frame() % 10 < 5) and C_TEXT or C_LEAN_WARN
    text(S, "NEW BEST!", W / 2 - 22, 40, nc)
  end

  local blink = frame() % 40 < 25
  if blink then
    text(S, "START TO RETRY", W / 2 - 34, 86, C_TEXT)
  end
end

----------------------------------------------------------------
-- ATTRACT MODE OVERLAY
----------------------------------------------------------------
local function draw_attract_overlay(S)
  -- "DEMO" label
  local dc = (frame() % 20 < 10) and C_TEXT or C_TEXT_DIM
  text(S, "DEMO", 2, 2, dc)
end

----------------------------------------------------------------
-- ENGINE CALLBACKS
----------------------------------------------------------------
function _init()
  mode(1)
  particles = {}
end

function _start()
  high_score = 0
  state = "title"
  attract_timer = 0
  particles = {}
end

function _update()
  if state == "title" then
    attract_timer = attract_timer + 1

    if btnp("start") or (touch_start and touch_start()) then
      init_game()
      state = "play"
      attract_timer = 0
      sfx_note(0, "C5", 0.05)
      return
    end

    -- Enter attract mode after idle
    if attract_timer >= ATTRACT_IDLE_FRAMES then
      state = "attract"
      attract_frame = 0
      init_game()
      return
    end

  elseif state == "attract" then
    attract_frame = attract_frame + 1

    -- Exit attract on any input
    if btnp("start") or btnp("a") or btnp("b") or btnp("left") or btnp("right")
       or btnp("up") or btnp("down") or btnp("select")
       or (touch_start and touch_start()) then
      state = "title"
      attract_timer = 0
      particles = {}
      return
    end

    -- AI plays
    local ai_tilt = ai_get_tilt()
    update_play(ai_tilt, true)

    -- Loop demo
    if attract_frame >= ATTRACT_DURATION or state == "gameover" then
      state = "attract"
      attract_frame = 0
      init_game()
    end

  elseif state == "play" then
    local tilt = get_tilt()
    update_play(tilt, false)

    -- Pause
    if btnp("start") then
      -- Quick pause handled simply: skip frame
    end

  elseif state == "gameover" then
    update_particles()
    if shake_timer > 0 then shake_timer = shake_timer - 1 end

    if btnp("start") or (touch_start and touch_start()) then
      init_game()
      state = "play"
      sfx_note(0, "C5", 0.05)
      return
    end

    -- Return to title after long idle
    attract_timer = (attract_timer or 0) + 1
    if attract_timer > 300 then
      state = "title"
      attract_timer = 0
      particles = {}
    end
  end
end

function _draw()
  local S = screen()
  cls(S, C_BG)

  if state == "title" then
    draw_title(S)

  elseif state == "attract" then
    -- Screen shake
    local sx, sy = 0, 0
    if shake_timer and shake_timer > 0 then
      sx = math.random(-shake_amt, shake_amt)
      sy = math.random(-shake_amt, shake_amt)
    end

    draw_ground(S)
    draw_tower(S)
    draw_drop_block(S)
    draw_lean_indicator(S)
    draw_wind_indicator(S)
    draw_hud(S)
    draw_attract_overlay(S)

  elseif state == "play" then
    -- Screen shake
    local sx, sy = 0, 0
    if shake_timer and shake_timer > 0 then
      sx = math.random(-shake_amt, shake_amt)
      sy = math.random(-shake_amt, shake_amt)
    end

    draw_ground(S)
    draw_tower(S)
    draw_drop_block(S)
    draw_lean_indicator(S)
    draw_wind_indicator(S)
    draw_hud(S)
    draw_particles(S)

  elseif state == "gameover" then
    draw_ground(S)
    draw_particles(S)
    draw_gameover(S)
  end
end
