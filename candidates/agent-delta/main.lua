-- NITRO DASH
-- A pseudo-3D arcade racer for Mono
-- Dodge traffic, hit checkpoints, use nitro boost!

------------------------------------------------------------
-- CONSTANTS
------------------------------------------------------------
local W = 160
local H = 120
local ROAD_W = 2000         -- road half-width in world units
local SEG_LEN = 200          -- segment length in world units
local DRAW_DIST = 120        -- how many segments ahead to draw
local CAM_H = 1500           -- camera height
local CAM_DEPTH = nil        -- computed in init
local LANES = 3
local MAX_SPEED = 320
local ACCEL = 8
local BRAKE = 12
local DECEL = 4              -- natural deceleration
local STEER_SPEED = 4200
local OFF_ROAD_DECEL = 16
local NITRO_BOOST = 140
local NITRO_DURATION = 60    -- frames
local MAX_NITRO = 3
local CENTRIFUGAL = 0.35
local CHECKPOINT_TIME = 30   -- seconds per checkpoint
local NUM_SEGMENTS = 600     -- total track segments

------------------------------------------------------------
-- GLOBAL STATE
------------------------------------------------------------
local segments = {}
local player = {}
local cars = {}
local obstacles = {}
local game_timer = 0
local game_over = false
local paused = false
local best_time = nil
local race_time = 0
local checkpoint_idx = 0
local total_checkpoints = 5
local track_length = 0
local lap_complete = false
local bg_offset = 0
local bg_hill_offset = 0
local engine_pitch = 200
local flash_timer = 0
local crash_timer = 0
local nitro_active = 0
local nitro_count = 0
local score = 0
local cars_passed = 0
local speed_lines = {}
local title_anim = 0
local hi_score = 0

-- attract mode state
local attract_mode = false
local attract_timer = 0
local attract_player = {}
local attract_steer = 0
local attract_dodge_dir = 0
local ATTRACT_IDLE_FRAMES = 90
local ATTRACT_DURATION = 300  -- ~10s at 30fps

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function lerp(a, b, t) return a + (b - a) * t end
local function sign(x) return x > 0 and 1 or (x < 0 and -1 or 0) end

local function rumble(n, freq)
  return math.floor(n / freq) % 2 == 0
end

local function project(wx, wy, wz, cx, cy, cz, depth)
  local tx = wx - cx
  local ty = wy - cy
  local tz = wz - cz
  if tz <= 0 then return nil end
  local scale = depth / tz
  local sx = W / 2 + scale * tx
  local sy = H / 2 - scale * ty
  return sx, sy, scale
end

------------------------------------------------------------
-- 7-SEGMENT CLOCK (attract mode)
------------------------------------------------------------
-- Segment map: a=1 b=2 c=4 d=8 e=16 f=32 g=64
local SEG7 = {
  [0] = 1+2+4+8+16+32,    -- abcdef
  [1] = 2+4,               -- bc
  [2] = 1+2+8+16+64,       -- abdeg
  [3] = 1+2+4+8+64,        -- abcdg
  [4] = 2+4+32+64,         -- bcfg
  [5] = 1+4+8+32+64,       -- acdfg
  [6] = 1+4+8+16+32+64,    -- acdefg
  [7] = 1+2+4,             -- abc
  [8] = 1+2+4+8+16+32+64,  -- abcdefg
  [9] = 1+2+4+8+32+64,     -- abcdfg
}

local function draw_seg7(s, digit, ox, oy, col)
  local segs = SEG7[digit] or 0
  local t = 2  -- segment thickness
  -- a: top horizontal
  if segs % 2 >= 1 then rectf(s, ox + t, oy, 3, t, col) end
  -- b: top-right vertical
  if math.floor(segs / 2) % 2 == 1 then rectf(s, ox + t + 3, oy + t, t, 4, col) end
  -- c: bottom-right vertical
  if math.floor(segs / 4) % 2 == 1 then rectf(s, ox + t + 3, oy + t + 4 + 1, t, 4, col) end
  -- d: bottom horizontal
  if math.floor(segs / 8) % 2 == 1 then rectf(s, ox + t, oy + t + 4 + 1 + 4, 3, t, col) end
  -- e: bottom-left vertical
  if math.floor(segs / 16) % 2 == 1 then rectf(s, ox, oy + t + 4 + 1, t, 4, col) end
  -- f: top-left vertical
  if math.floor(segs / 32) % 2 == 1 then rectf(s, ox, oy + t, t, 4, col) end
  -- g: middle horizontal
  if math.floor(segs / 64) % 2 == 1 then rectf(s, ox + t, oy + t + 4, 3, 1, col) end
end

local function draw_clock7(s, ox, oy, col)
  local d = date()
  local h = d.hour
  local m = d.min
  draw_seg7(s, math.floor(h / 10), ox, oy, col)
  draw_seg7(s, h % 10, ox + 9, oy, col)
  -- blinking colon
  if math.floor(frame() / 30) % 2 == 0 then
    rectf(s, ox + 18, oy + 3, 2, 2, col)
    rectf(s, ox + 18, oy + 8, 2, 2, col)
  end
  draw_seg7(s, math.floor(m / 10), ox + 21, oy, col)
  draw_seg7(s, m % 10, ox + 30, oy, col)
end

------------------------------------------------------------
-- TRACK GENERATION
------------------------------------------------------------
local function build_track()
  segments = {}
  local curve = 0
  local hill = 0
  for i = 1, NUM_SEGMENTS do
    -- vary curves
    if i > 20 and i < 80 then curve = 3.5
    elseif i > 100 and i < 160 then curve = -5
    elseif i > 180 and i < 220 then curve = 4
    elseif i > 240 and i < 300 then curve = -3
    elseif i > 320 and i < 380 then curve = 6
    elseif i > 400 and i < 440 then curve = -4.5
    elseif i > 460 and i < 520 then curve = 2.5
    elseif i > 540 and i < 580 then curve = -6
    else curve = 0 end

    -- vary hills
    if i > 40 and i < 70 then hill = 30
    elseif i > 130 and i < 150 then hill = -20
    elseif i > 250 and i < 280 then hill = 40
    elseif i > 350 and i < 370 then hill = -35
    elseif i > 450 and i < 480 then hill = 25
    elseif i > 530 and i < 560 then hill = -30
    else hill = 0 end

    segments[i] = {
      z = (i - 1) * SEG_LEN,
      y = hill,
      curve = curve,
      clip = 0,
      is_checkpoint = false,
      obstacle = nil,
      car = nil,
    }
  end

  -- mark checkpoints
  local cp_spacing = math.floor(NUM_SEGMENTS / total_checkpoints)
  for c = 1, total_checkpoints do
    local idx = c * cp_spacing
    if idx <= NUM_SEGMENTS then
      segments[idx].is_checkpoint = true
    end
  end

  track_length = NUM_SEGMENTS * SEG_LEN
end

------------------------------------------------------------
-- SPAWN AI CARS & OBSTACLES
------------------------------------------------------------
local function spawn_traffic()
  cars = {}
  for i = 1, 18 do
    local seg_idx = math.random(30, NUM_SEGMENTS - 10)
    local lane = math.random(-1, 1)
    cars[i] = {
      seg = seg_idx,
      z = seg_idx * SEG_LEN,  -- track actual z position
      offset = lane * (ROAD_W * 0.4),
      speed = math.random(60, 180),
      w = 6,
      h = 4,
      color = math.random(4, 12),
      passed = false,
    }
  end

  obstacles = {}
  for i = 1, 12 do
    local seg_idx = math.random(40, NUM_SEGMENTS - 10)
    local side = math.random() > 0.5 and 1 or -1
    local otype = math.random(1, 3)  -- 1=rock, 2=oil, 3=cone
    obstacles[i] = {
      seg = seg_idx,
      offset = side * math.random(200, 800),
      otype = otype,
    }
  end
end

------------------------------------------------------------
-- INIT
------------------------------------------------------------
function _init()
  mode(4)
  best_time = nil
  hi_score = 0
end

function _start()
  go("title")
end

------------------------------------------------------------
-- TITLE SCENE
------------------------------------------------------------
function title_init()
  title_anim = 0
  attract_mode = false
  attract_timer = 0
end

function title_update()
  title_anim = title_anim + 1

  if btnp("start") or btnp("a") or btnp("b") or btnp("up") or btnp("down") or btnp("left") or btnp("right") then
    if attract_mode then
      attract_mode = false
      attract_timer = 0
      return
    end
    go("race")
    return
  end

  -- enter attract mode after idle
  if not attract_mode then
    attract_timer = attract_timer + 1
    if attract_timer >= ATTRACT_IDLE_FRAMES then
      -- start attract mode
      attract_mode = true
      attract_timer = 0
      -- set up attract auto-play state
      CAM_DEPTH = 1 / math.tan(50 * math.pi / 180)
      build_track()
      spawn_traffic()
      attract_player = {
        x = 0, y = 0, z = 0,
        speed = 0, seg = 1,
      }
      attract_steer = 0
      attract_dodge_dir = 0
    end
  else
    -- attract mode update
    attract_timer = attract_timer + 1

    -- auto-play AI: accelerate and dodge traffic
    local ap = attract_player

    -- accelerate to a nice cruising speed
    if ap.speed < MAX_SPEED * 0.75 then
      ap.speed = ap.speed + ACCEL
    else
      ap.speed = ap.speed + 1
    end
    ap.speed = clamp(ap.speed, 0, MAX_SPEED * 0.85)

    -- get current segment
    local seg_idx = math.floor(ap.z / SEG_LEN) % NUM_SEGMENTS + 1
    ap.seg = seg_idx

    -- apply curve centrifugal force
    if seg_idx >= 1 and seg_idx <= NUM_SEGMENTS then
      local seg = segments[seg_idx]
      ap.x = ap.x - seg.curve * CENTRIFUGAL * (ap.speed / MAX_SPEED) * 60
    end

    -- auto-steer: look ahead for cars to dodge
    local target_x = 0
    local dodge_needed = false
    for _, c in ipairs(cars) do
      local cz = c.z
      local dz = cz - ap.z
      if dz > 0 and dz < SEG_LEN * 15 then
        local dx = c.offset - ap.x
        if math.abs(dx) < 600 then
          -- dodge away from this car
          if dx > 0 then
            target_x = ap.x - 800
          else
            target_x = ap.x + 800
          end
          dodge_needed = true
          break
        end
      end
    end

    -- also counter-steer into curves for style
    if seg_idx >= 1 and seg_idx <= NUM_SEGMENTS then
      local seg = segments[seg_idx]
      if not dodge_needed then
        target_x = seg.curve * 200  -- lean into curves
      end
    end

    -- smooth steering toward target
    local steer_diff = target_x - ap.x
    local steer_amt = clamp(steer_diff * 0.01, -1, 1)
    ap.x = ap.x + steer_amt * STEER_SPEED * (ap.speed / MAX_SPEED)
    attract_steer = steer_amt

    ap.x = clamp(ap.x, -ROAD_W * 1.5, ROAD_W * 1.5)

    -- move forward
    ap.z = ap.z + ap.speed

    -- wrap around
    if ap.z >= track_length then
      ap.z = ap.z - track_length
    end

    -- move AI cars
    for _, c in ipairs(cars) do
      c.z = c.z + c.speed
      if c.z >= track_length then c.z = c.z - track_length end
      c.seg = math.floor(c.z / SEG_LEN) % NUM_SEGMENTS + 1
    end

    -- update bg offsets
    bg_offset = (bg_offset + ap.speed * 0.002) % W
    bg_hill_offset = (bg_hill_offset + ap.speed * 0.004) % W
  end
end

function title_draw()
  local s = screen()
  cls(s, 0)

  if attract_mode then
    -- draw the race view in attract mode
    draw_attract_race(s)

    -- darken overlay
    rectf(s, 0, 0, W, 12, 0)
    rectf(s, 0, H - 14, W, 14, 0)

    -- title overlay
    text(s, "NITRO DASH", W / 2, 2, 15, ALIGN_CENTER)

    -- flashing PRESS START
    if math.floor(title_anim / 15) % 2 == 0 then
      text(s, "PRESS START", W / 2, H - 12, 15, ALIGN_CENTER)
    end

    -- demo label
    text(s, "- DEMO -", W / 2, H - 8, 8, ALIGN_CENTER)

    -- 7-segment clock in top-right corner (dim)
    draw_clock7(s, W - 41, 2, 3)
    return
  end

  -- scrolling road lines for background flair
  for i = 0, 15 do
    local y = 70 + i * 4
    local shade = 1 + (i % 2)
    local off = (title_anim * 2 + i * 8) % 40 - 20
    line(s, 0, y, W, y, shade)
    if i % 2 == 0 then
      rectf(s, 60 + off, y, 40, 2, 3)
    end
  end

  -- perspective road lines
  for i = 0, 8 do
    local y = 68 + i * 6
    local spread = 80 - i * 6
    local lx = W / 2 - spread
    local rx = W / 2 + spread
    line(s, lx, y, rx, y, 2 + (i % 2))
  end

  -- title
  local bounce = math.sin(title_anim * 0.08) * 3
  text(s, "NITRO DASH", W / 2, 15 + bounce, 15, ALIGN_CENTER)
  text(s, "____________", W / 2, 20 + bounce, 8, ALIGN_CENTER)

  -- subtitle
  text(s, "ARCADE RACER", W / 2, 28 + bounce, 10, ALIGN_CENTER)

  -- car icon with animated wheels
  local wheel_spin = math.floor(title_anim / 4) % 2
  rectf(s, 72, 40, 16, 8, 12)
  rectf(s, 74, 38, 12, 3, 10)
  rectf(s, 70, 48, 4, 3, 8)
  rectf(s, 86, 48, 4, 3, 8)
  -- exhaust puff
  if title_anim % 8 < 4 then
    rectf(s, 78, 49, 3, 2, 7)
  else
    rectf(s, 76, 50, 2, 1, 5)
  end

  -- instructions
  if math.floor(title_anim / 20) % 2 == 0 then
    text(s, "PRESS START", W / 2, 86, 15, ALIGN_CENTER)
  end

  text(s, "LEFT/RIGHT: STEER", W / 2, 96, 7, ALIGN_CENTER)
  text(s, "A: ACCEL  B: NITRO", W / 2, 104, 7, ALIGN_CENTER)

  if best_time then
    text(s, string.format("BEST: %d.%ds", math.floor(best_time), math.floor((best_time % 1) * 10)), W / 2, 58, 11, ALIGN_CENTER)
  end
  if hi_score > 0 then
    text(s, string.format("HI: %05d", hi_score), W / 2, 66, 12, ALIGN_CENTER)
  end
end

------------------------------------------------------------
-- ATTRACT MODE RACE DRAW
------------------------------------------------------------
function draw_attract_race(s)
  local ap = attract_player

  -- camera
  local cam_x = ap.x
  local cam_y = CAM_H
  local cam_z = ap.z - 600

  local base_seg = math.floor(cam_z / SEG_LEN) % NUM_SEGMENTS + 1
  if base_seg < 1 then base_seg = 1 end

  -- sky gradient
  for row = 0, 45 do
    local c = math.floor(row / 10)
    line(s, 0, row, W, row, c)
  end

  -- mountains
  for mx = -20, W + 20, 30 do
    local px = mx - (bg_offset % 30)
    local mh = 15 + math.sin(px * 0.05) * 10
    for my = 0, mh do
      local mw = (mh - my) * 0.8
      line(s, px - mw, 46 - my, px + mw, 46 - my, 3 + math.floor(my / 6))
    end
  end

  -- far hills
  for hx = -10, W + 10, 20 do
    local px = hx - (bg_hill_offset % 20)
    local hh = 8 + math.sin(px * 0.08 + 1) * 5
    for hy = 0, hh do
      local hw = (hh - hy) * 0.6
      line(s, px - hw, 46 - hy, px + hw, 46 - hy, 2)
    end
  end

  -- road
  local x_acc = 0
  local y_acc = 0
  local seg_screen = {}
  for i = 1, DRAW_DIST do
    local idx = ((base_seg - 1 + i) % NUM_SEGMENTS) + 1
    local seg = segments[idx]
    local world_z = seg.z
    if world_z < cam_z then world_z = world_z + track_length end
    local tz = world_z - cam_z
    if tz <= 0 then tz = 1 end
    x_acc = x_acc + seg.curve
    y_acc = y_acc + seg.y
    local scale = CAM_DEPTH * H / tz
    local sx = W / 2 + (scale * (x_acc - cam_x) * 0.5)
    local sy = math.floor(H / 2 - scale * (y_acc - cam_y) * 0.003)
    local sw = math.floor(scale * ROAD_W * 0.5)
    seg_screen[i] = { sx = sx, sy = sy, sw = sw, idx = idx, scale = scale, tz = tz }
  end

  for i = DRAW_DIST, 2, -1 do
    local s1 = seg_screen[i]
    local s2 = seg_screen[i - 1]
    if s1 and s2 and s1.sy < H then
      local idx = s1.idx
      local is_rumble = rumble(idx, 4)
      local is_line = rumble(idx, 2)
      local grass_c = is_rumble and 2 or 1
      local y_top = math.max(0, math.floor(s1.sy))
      local y_bot = math.min(H - 1, math.floor(s2.sy))
      if y_top <= y_bot then
        for row = y_top, y_bot do
          line(s, 0, row, W, row, grass_c)
        end
        local road_c = is_rumble and 5 or 4
        for row = y_top, y_bot do
          local t = 0
          if y_bot ~= y_top then t = (row - y_top) / (y_bot - y_top) end
          local rx = lerp(s1.sx, s2.sx, t)
          local rw = lerp(s1.sw, s2.sw, t)
          local lx = math.floor(rx - rw)
          local rx2 = math.floor(rx + rw)
          if lx < 0 then lx = 0 end
          if rx2 >= W then rx2 = W - 1 end
          line(s, lx, row, rx2, row, road_c)
          local rumble_w = math.max(1, math.floor(rw * 0.08))
          local rumble_c = is_rumble and 15 or 8
          line(s, lx, row, lx + rumble_w, row, rumble_c)
          line(s, rx2 - rumble_w, row, rx2, row, rumble_c)
          if is_line and rw > 3 then
            local cl = math.floor(rx - 1)
            local cr = math.floor(rx + 1)
            line(s, cl, row, cr, row, 15)
          end
        end
      end
    end
  end

  -- draw AI cars in attract
  for i = DRAW_DIST - 1, 2, -1 do
    local ss = seg_screen[i]
    if ss and ss.tz > 0 then
      local idx = ss.idx
      for _, c in ipairs(cars) do
        if c.seg == idx then
          local scale = ss.scale
          local cx3 = ss.sx + c.offset * scale * 0.0005
          local cy3 = ss.sy
          local cw = math.max(2, math.floor(c.w * scale * 20))
          local ch2 = math.max(1, math.floor(c.h * scale * 20))
          if cw < 40 and ch2 < 25 and cx3 > -10 and cx3 < W + 10 then
            rectf(s, math.floor(cx3) - cw / 2, math.floor(cy3) - ch2, cw, ch2, c.color)
            if ch2 > 2 then
              rectf(s, math.floor(cx3) - cw / 4, math.floor(cy3) - ch2 + 1, math.floor(cw / 2), math.max(1, math.floor(ch2 / 3)), c.color - 2)
            end
          end
        end
      end
    end
  end

  -- draw attract player car
  local px2 = W / 2
  local py2 = H - 18
  local steer_vis = math.floor(attract_steer * 3)
  steer_vis = clamp(steer_vis, -3, 3)

  rectf(s, px2 - 9, py2 + 7, 18, 3, 1)
  rectf(s, px2 - 8 + steer_vis, py2 - 4, 16, 10, 12)
  rectf(s, px2 - 5 + steer_vis, py2 - 6, 10, 4, 10)
  rectf(s, px2 - 4 + steer_vis, py2 - 5, 8, 2, 14)
  rectf(s, px2 - 9 + steer_vis, py2 - 2, 3, 4, 8)
  rectf(s, px2 + 6 + steer_vis, py2 - 2, 3, 4, 8)
  rectf(s, px2 - 9 + steer_vis, py2 + 4, 3, 3, 8)
  rectf(s, px2 + 6 + steer_vis, py2 + 4, 3, 3, 8)

  -- speed lines in attract
  if ap.speed > MAX_SPEED * 0.4 then
    local intensity = (ap.speed - MAX_SPEED * 0.4) / (MAX_SPEED * 0.5)
    for i = 1, 6 do
      local sx2 = (i * 29 + math.floor(attract_timer * 3.7)) % W
      local sy2 = 50 + (i * 13 + math.floor(attract_timer * 2.1)) % 50
      local slen = math.floor(5 * intensity)
      if slen > 0 then
        line(s, sx2, sy2, sx2, sy2 + slen, 6)
      end
    end
  end
end

------------------------------------------------------------
-- RACE SCENE
------------------------------------------------------------
function race_init()
  CAM_DEPTH = 1 / math.tan(50 * math.pi / 180)  -- FOV ~100 degrees

  build_track()
  spawn_traffic()

  player = {
    x = 0,
    y = 0,
    z = 0,
    speed = 0,
    steer = 0,
    seg = 1,
  }

  game_timer = CHECKPOINT_TIME * 2  -- starting time
  race_time = 0
  game_over = false
  paused = false
  lap_complete = false
  checkpoint_idx = 0
  crash_timer = 0
  nitro_active = 0
  nitro_count = MAX_NITRO
  score = 0
  cars_passed = 0
  flash_timer = 0
  speed_lines = {}

  -- init speed lines
  for i = 1, 8 do
    speed_lines[i] = {
      x = math.random(0, W),
      y = math.random(40, H),
      len = math.random(3, 8),
    }
  end
end

function race_update()
  -- pause
  if btnp("select") then
    paused = not paused
    if paused then
      tone(0, 300, 200, 0.1)
    end
  end
  if paused then return end
  if game_over then
    if btnp("start") then
      go("title")
    end
    return
  end

  -- FIX: game runs at 30fps, not 60fps
  local dt = 1 / 30

  -- timers
  game_timer = game_timer - dt
  race_time = race_time + dt
  if game_timer <= 0 then
    game_timer = 0
    game_over = true
    -- record best
    if not best_time or race_time < best_time then
      best_time = race_time
    end
    if score > hi_score then
      hi_score = score
    end
    -- game over sound
    noise(0, 0.5)
    tone(0, 200, 80, 0.5)
    cam_shake(4)
    return
  end

  -- flash timer (for checkpoint flash, etc.)
  if flash_timer > 0 then flash_timer = flash_timer - 1 end
  if crash_timer > 0 then crash_timer = crash_timer - 1 end

  -- nitro
  if nitro_active > 0 then nitro_active = nitro_active - 1 end

  -- input
  local accel = btn("a")
  local steer_input = 0
  if btn("left") then steer_input = -1 end
  if btn("right") then steer_input = 1 end

  -- nitro boost
  if btnp("b") and nitro_count > 0 and nitro_active == 0 then
    nitro_active = NITRO_DURATION
    nitro_count = nitro_count - 1
    -- boost sound
    tone(1, 800, 400, 0.3)
    noise(1, 0.15)
    cam_shake(3)
  end

  -- acceleration
  local current_max = MAX_SPEED
  if nitro_active > 0 then current_max = MAX_SPEED + NITRO_BOOST end

  if accel or btn("up") then
    player.speed = player.speed + ACCEL
  elseif btn("down") then
    player.speed = player.speed - BRAKE
  else
    player.speed = player.speed - DECEL
  end

  -- off-road penalty
  if math.abs(player.x) > ROAD_W then
    player.speed = player.speed - OFF_ROAD_DECEL
    -- rumble feedback
    if frame() % 4 == 0 then
      noise(2, 0.04)
      cam_shake(1)
    end
  end

  player.speed = clamp(player.speed, 0, current_max)

  -- steering
  if player.speed > 0 then
    player.x = player.x + steer_input * STEER_SPEED * (player.speed / MAX_SPEED)
  end

  -- get current segment
  local seg_idx = math.floor(player.z / SEG_LEN) % NUM_SEGMENTS + 1
  player.seg = seg_idx

  -- apply curve centrifugal force
  if seg_idx >= 1 and seg_idx <= NUM_SEGMENTS then
    local seg = segments[seg_idx]
    player.x = player.x - seg.curve * CENTRIFUGAL * (player.speed / MAX_SPEED) * 60
  end

  player.x = clamp(player.x, -ROAD_W * 2, ROAD_W * 2)

  -- move forward
  player.z = player.z + player.speed

  -- lap detection
  if player.z >= track_length then
    player.z = player.z - track_length
    lap_complete = true
    score = score + 1000
    game_timer = game_timer + CHECKPOINT_TIME
    flash_timer = 40
    tone(0, 600, 900, 0.3)
    tone(1, 800, 1200, 0.2)
  end

  -- checkpoint detection
  local new_seg = math.floor(player.z / SEG_LEN) % NUM_SEGMENTS + 1
  if new_seg >= 1 and new_seg <= NUM_SEGMENTS and segments[new_seg].is_checkpoint then
    local cp_id = new_seg
    if cp_id ~= checkpoint_idx then
      checkpoint_idx = cp_id
      game_timer = game_timer + CHECKPOINT_TIME
      flash_timer = 30
      score = score + 500
      tone(0, 500, 800, 0.2)
      tone(1, 700, 1000, 0.15)
    end
  end

  -- update AI cars (FIX: properly track z position)
  for _, c in ipairs(cars) do
    c.z = c.z + c.speed
    if c.z >= track_length then c.z = c.z - track_length end
    c.seg = math.floor(c.z / SEG_LEN) % NUM_SEGMENTS + 1

    -- collision with player
    local dz = math.abs(c.z - player.z)
    -- also check wrap-around proximity
    if dz > track_length / 2 then dz = track_length - dz end
    local dx = math.abs(c.offset - player.x)

    if dz < SEG_LEN * 1.5 and dx < 500 then
      -- crash!
      if player.speed > 100 and crash_timer == 0 then
        player.speed = player.speed * 0.3
        crash_timer = 20
        cam_shake(5)
        noise(0, 0.25)
        tone(2, 150, 60, 0.2)
        score = math.max(0, score - 100)
      end
    end

    -- count cars passed (award points for overtaking)
    if not c.passed and c.z < player.z and dz < SEG_LEN * 3 then
      c.passed = true
      cars_passed = cars_passed + 1
      score = score + 50
      if cars_passed % 5 == 0 then
        tone(0, 600, 700, 0.1)
      end
    end
    -- reset passed flag if car is far ahead
    if c.z > player.z and dz > SEG_LEN * 10 then
      c.passed = false
    end
  end

  -- obstacle collision
  for _, ob in ipairs(obstacles) do
    local oz = ob.seg * SEG_LEN
    local dz = math.abs(oz - player.z)
    local dx = math.abs(ob.offset - player.x)
    if dz < SEG_LEN and dx < 400 then
      if ob.otype == 1 then -- rock: big slow
        player.speed = player.speed * 0.2
        crash_timer = 25
        cam_shake(6)
        noise(0, 0.3)
        tone(2, 100, 40, 0.3)
      elseif ob.otype == 2 then -- oil: slip
        player.x = player.x + math.random(-600, 600)
        crash_timer = 15
        cam_shake(3)
        noise(1, 0.15)
      elseif ob.otype == 3 then -- cone: small bump
        player.speed = player.speed * 0.7
        crash_timer = 10
        cam_shake(2)
        noise(0, 0.1)
      end
      -- move obstacle so it doesn't re-trigger
      ob.seg = math.random(40, NUM_SEGMENTS - 10)
    end
  end

  -- engine sound (varies with speed, richer sound)
  if frame() % 4 == 0 then
    local pitch = 100 + player.speed * 2.5
    if nitro_active > 0 then pitch = pitch + 100 end
    tone(3, pitch, pitch + 20, 0.07)
  end
  -- secondary engine harmonic for depth
  if frame() % 8 == 0 and player.speed > 50 then
    local pitch2 = 80 + player.speed * 1.2
    tone(2, pitch2, pitch2 + 10, 0.03)
  end

  -- tire screech on hard turns at speed
  if math.abs(steer_input) > 0 and player.speed > MAX_SPEED * 0.7 then
    if frame() % 6 == 0 then
      noise(3, 0.02)
    end
  end

  -- update speed lines
  for _, sl in ipairs(speed_lines) do
    sl.y = sl.y + player.speed * 0.05
    if sl.y > H then
      sl.y = math.random(40, 60)
      sl.x = math.random(0, W)
      sl.len = math.random(3, 8)
    end
  end
end

------------------------------------------------------------
-- RACE DRAW
------------------------------------------------------------
function race_draw()
  local s = screen()
  cls(s, 0)

  -- camera
  local cam_x = player.x
  local cam_y = CAM_H
  local cam_z = player.z - 600

  local base_seg = math.floor(cam_z / SEG_LEN) % NUM_SEGMENTS + 1
  if base_seg < 1 then base_seg = 1 end

  local max_y = H  -- clip from bottom up

  -- parallax sky / mountains
  -- sky gradient
  for row = 0, 45 do
    local c = math.floor(row / 10)
    line(s, 0, row, W, row, c)
  end

  -- mountains
  bg_offset = (bg_offset + player.speed * 0.002) % W
  for mx = -20, W + 20, 30 do
    local px = mx - (bg_offset % 30)
    local mh = 15 + math.sin(px * 0.05) * 10
    -- mountain triangle
    for my = 0, mh do
      local mw = (mh - my) * 0.8
      line(s, px - mw, 46 - my, px + mw, 46 - my, 3 + math.floor(my / 6))
    end
  end

  -- far hills
  bg_hill_offset = (bg_hill_offset + player.speed * 0.004) % W
  for hx = -10, W + 10, 20 do
    local px = hx - (bg_hill_offset % 20)
    local hh = 8 + math.sin(px * 0.08 + 1) * 5
    for hy = 0, hh do
      local hw = (hh - hy) * 0.6
      line(s, px - hw, 46 - hy, px + hw, 46 - hy, 2)
    end
  end

  -- accumulate curvature for perspective
  local x_acc = 0
  local y_acc = 0

  -- road rendering
  local seg_screen = {}
  for i = 1, DRAW_DIST do
    local idx = ((base_seg - 1 + i) % NUM_SEGMENTS) + 1
    local seg = segments[idx]
    local world_z = seg.z
    -- handle wrapping
    if world_z < cam_z then world_z = world_z + track_length end

    local tz = world_z - cam_z
    if tz <= 0 then tz = 1 end

    x_acc = x_acc + seg.curve
    y_acc = y_acc + seg.y

    local scale = CAM_DEPTH * H / tz
    local sx = W / 2 + (scale * (x_acc - cam_x) * 0.5)
    local sy = math.floor(H / 2 - scale * (y_acc - cam_y) * 0.003)
    local sw = math.floor(scale * ROAD_W * 0.5)

    seg_screen[i] = {
      sx = sx, sy = sy, sw = sw, idx = idx, scale = scale, tz = tz
    }
  end

  -- draw segments far to near (high i to low i)
  for i = DRAW_DIST, 2, -1 do
    local s1 = seg_screen[i]
    local s2 = seg_screen[i - 1]
    if s1 and s2 and s1.sy < max_y then
      local idx = s1.idx
      local is_rumble = rumble(idx, 4)
      local is_line = rumble(idx, 2)
      local is_cp = segments[idx].is_checkpoint

      -- grass
      local grass_c = is_rumble and 2 or 1
      local y_top = math.max(0, math.floor(s1.sy))
      local y_bot = math.min(H - 1, math.floor(s2.sy))
      if y_top <= y_bot then
        for row = y_top, y_bot do
          line(s, 0, row, W, row, grass_c)
        end
      end

      -- road
      local road_c = is_rumble and 5 or 4
      if is_cp then road_c = is_rumble and 9 or 8 end
      if crash_timer > 0 and frame() % 4 < 2 then road_c = road_c + 2 end

      -- interpolate road edges
      if y_top <= y_bot then
        for row = y_top, y_bot do
          local t = 0
          if y_bot ~= y_top then t = (row - y_top) / (y_bot - y_top) end
          local rx = lerp(s1.sx, s2.sx, t)
          local rw = lerp(s1.sw, s2.sw, t)
          local lx = math.floor(rx - rw)
          local rx2 = math.floor(rx + rw)
          if lx < 0 then lx = 0 end
          if rx2 >= W then rx2 = W - 1 end
          -- road surface
          line(s, lx, row, rx2, row, road_c)
          -- rumble strips (edges)
          local rumble_w = math.max(1, math.floor(rw * 0.08))
          local rumble_c = is_rumble and 15 or 8
          if is_cp then rumble_c = 15 end
          line(s, lx, row, lx + rumble_w, row, rumble_c)
          line(s, rx2 - rumble_w, row, rx2, row, rumble_c)
          -- center line
          if is_line and rw > 3 then
            local cl = math.floor(rx - 1)
            local cr = math.floor(rx + 1)
            line(s, cl, row, cr, row, 15)
          end
          -- lane markers
          if is_rumble and rw > 6 then
            local lane_off = math.floor(rw * 0.33)
            pix(s, math.floor(rx - lane_off), row, 10)
            pix(s, math.floor(rx + lane_off), row, 10)
          end
        end
      end
    end
  end

  -- draw obstacles and cars (sprites)
  for i = DRAW_DIST - 1, 2, -1 do
    local ss = seg_screen[i]
    if ss and ss.tz > 0 then
      local idx = ss.idx

      -- draw obstacles at this segment
      for _, ob in ipairs(obstacles) do
        if ob.seg == idx then
          local scale = ss.scale
          local ox = ss.sx + ob.offset * scale * 0.0005
          local oy = ss.sy
          local ow = math.max(2, math.floor(6 * scale * 20))
          local oh = math.max(2, math.floor(4 * scale * 20))
          if ow < 30 and oh < 20 and ox > -10 and ox < W + 10 then
            if ob.otype == 1 then -- rock
              circf(s, math.floor(ox), math.floor(oy) - oh, math.max(1, math.floor(ow / 3)), 6)
            elseif ob.otype == 2 then -- oil
              rectf(s, math.floor(ox) - ow / 2, math.floor(oy) - 1, ow, math.max(1, oh / 3), 2)
            elseif ob.otype == 3 then -- cone
              local cx2 = math.floor(ox)
              local cy2 = math.floor(oy)
              line(s, cx2, cy2 - oh, cx2 - math.floor(ow / 4), cy2, 12)
              line(s, cx2, cy2 - oh, cx2 + math.floor(ow / 4), cy2, 12)
            end
          end
        end
      end

      -- draw AI cars at this segment
      for _, c in ipairs(cars) do
        if c.seg == idx then
          local scale = ss.scale
          local cx3 = ss.sx + c.offset * scale * 0.0005
          local cy3 = ss.sy
          local cw = math.max(2, math.floor(c.w * scale * 20))
          local ch2 = math.max(1, math.floor(c.h * scale * 20))
          if cw < 40 and ch2 < 25 and cx3 > -10 and cx3 < W + 10 then
            -- car body
            rectf(s, math.floor(cx3) - cw / 2, math.floor(cy3) - ch2, cw, ch2, c.color)
            -- windshield
            if ch2 > 2 then
              rectf(s, math.floor(cx3) - cw / 4, math.floor(cy3) - ch2 + 1, math.floor(cw / 2), math.max(1, math.floor(ch2 / 3)), c.color - 2)
            end
            -- taillights when close
            if ch2 > 3 then
              pix(s, math.floor(cx3) - math.floor(cw / 2) + 1, math.floor(cy3) - 1, 8)
              pix(s, math.floor(cx3) + math.floor(cw / 2) - 1, math.floor(cy3) - 1, 8)
            end
          end
        end
      end
    end
  end

  -- draw player car
  local px2 = W / 2
  local py2 = H - 18
  local steer_vis = 0
  if btn("left") then steer_vis = -2 end
  if btn("right") then steer_vis = 2 end

  if crash_timer > 0 then
    -- shaky car
    px2 = px2 + math.random(-2, 2)
    py2 = py2 + math.random(-1, 1)
  end

  -- car shadow
  rectf(s, px2 - 9, py2 + 7, 18, 3, 1)

  -- car body
  rectf(s, px2 - 8 + steer_vis, py2 - 4, 16, 10, 12)
  -- cockpit
  rectf(s, px2 - 5 + steer_vis, py2 - 6, 10, 4, 10)
  -- windshield
  rectf(s, px2 - 4 + steer_vis, py2 - 5, 8, 2, 14)
  -- wheels (animate spin)
  local wspin = frame() % 2
  rectf(s, px2 - 9 + steer_vis, py2 - 2, 3, 4, 8 + wspin)
  rectf(s, px2 + 6 + steer_vis, py2 - 2, 3, 4, 8 + wspin)
  rectf(s, px2 - 9 + steer_vis, py2 + 4, 3, 3, 8 + wspin)
  rectf(s, px2 + 6 + steer_vis, py2 + 4, 3, 3, 8 + wspin)
  -- headlights
  pix(s, px2 - 7 + steer_vis, py2 - 4, 15)
  pix(s, px2 + 7 + steer_vis, py2 - 4, 15)

  -- nitro flames
  if nitro_active > 0 then
    local fw = math.random(2, 5)
    local fh = math.random(3, 8)
    rectf(s, px2 - fw / 2, py2 + 7, fw, fh, 15)
    rectf(s, px2 - fw / 4, py2 + 7, math.floor(fw / 2), fh + 2, 12)
    -- side sparks
    if frame() % 3 == 0 then
      pix(s, px2 + math.random(-6, 6), py2 + 8 + math.random(0, 4), 15)
    end
  end

  -- exhaust particles when moving
  if player.speed > 50 and frame() % 3 == 0 then
    local ex = px2 + math.random(-1, 1)
    local ey = py2 + 8 + math.random(0, 2)
    pix(s, ex, ey, 5)
  end

  -- speed lines when going fast
  if player.speed > MAX_SPEED * 0.6 then
    local intensity = (player.speed - MAX_SPEED * 0.6) / (MAX_SPEED * 0.4)
    for _, sl in ipairs(speed_lines) do
      local slen = math.floor(sl.len * intensity)
      if slen > 0 then
        line(s, sl.x, math.floor(sl.y), sl.x, math.floor(sl.y) + slen, 6)
      end
    end
  end

  -- screen edge flash on crash
  if crash_timer > 15 then
    line(s, 0, 0, W, 0, 8)
    line(s, 0, H - 1, W, H - 1, 8)
    line(s, 0, 0, 0, H, 8)
    line(s, W - 1, 0, W - 1, H, 8)
  end

  -- HUD
  draw_hud(s)

  -- pause overlay
  if paused then
    rectf(s, 30, 40, 100, 40, 0)
    rect(s, 30, 40, 100, 40, 15)
    text(s, "PAUSED", W / 2, 48, 15, ALIGN_CENTER)
    text(s, "SELECT TO RESUME", W / 2, 60, 8, ALIGN_CENTER)
    text(s, string.format("SCORE: %05d", score), W / 2, 70, 12, ALIGN_CENTER)
  end

  -- game over overlay
  if game_over then
    rectf(s, 20, 25, 120, 70, 0)
    rect(s, 20, 25, 120, 70, 15)
    rect(s, 21, 26, 118, 68, 8)
    text(s, "TIME UP!", W / 2, 30, 15, ALIGN_CENTER)
    text(s, string.format("SCORE: %05d", score), W / 2, 42, 12, ALIGN_CENTER)
    text(s, string.format("TIME: %d.%ds", math.floor(race_time), math.floor((race_time % 1) * 10)), W / 2, 52, 10, ALIGN_CENTER)
    text(s, string.format("CARS PASSED: %d", cars_passed), W / 2, 62, 7, ALIGN_CENTER)
    if best_time then
      text(s, string.format("BEST: %d.%ds", math.floor(best_time), math.floor((best_time % 1) * 10)), W / 2, 72, 8, ALIGN_CENTER)
    end
    if math.floor(frame() / 20) % 2 == 0 then
      text(s, "PRESS START", W / 2, 84, 15, ALIGN_CENTER)
    end
  end
end

function draw_hud(s)
  -- top bar background
  rectf(s, 0, 0, W, 10, 0)

  -- speed
  local speed_pct = math.floor((player.speed / MAX_SPEED) * 100)
  text(s, string.format("%d", speed_pct), 2, 2, 15, 0)
  text(s, "MPH", 18, 2, 7, 0)

  -- timer
  local t_col = 15
  if game_timer < 10 then
    t_col = (math.floor(frame() / 8) % 2 == 0) and 15 or 8
  end
  if game_timer < 5 then
    t_col = (math.floor(frame() / 4) % 2 == 0) and 15 or 8
  end
  text(s, string.format("TIME:%d.%d", math.floor(game_timer), math.floor((game_timer % 1) * 10)), W / 2, 2, t_col, ALIGN_CENTER)

  -- score
  text(s, string.format("%05d", score), W - 2, 2, 12, 7)

  -- nitro indicators
  for i = 1, MAX_NITRO do
    local nc = i <= nitro_count and 15 or 3
    if nitro_active > 0 and i == nitro_count + 1 then
      nc = (frame() % 6 < 3) and 15 or 8
    end
    rectf(s, 2 + (i - 1) * 8, H - 8, 6, 5, nc)
    text(s, "N", 3 + (i - 1) * 8, H - 7, 0, 0)
  end

  -- speed bar
  local bar_w = math.floor((player.speed / (MAX_SPEED + NITRO_BOOST)) * 50)
  rectf(s, W - 52, H - 7, 50, 4, 2)
  local bar_c = 8
  if player.speed > MAX_SPEED * 0.8 then bar_c = 12 end
  if nitro_active > 0 then bar_c = 15 end
  rectf(s, W - 52, H - 7, bar_w, 4, bar_c)

  -- checkpoint flash
  if flash_timer > 0 then
    local fc = (flash_timer % 6 < 3) and 15 or 0
    text(s, "CHECKPOINT!", W / 2, 15, fc, ALIGN_CENTER)
    -- bonus text
    if flash_timer > 20 then
      text(s, "+500", W / 2, 23, 12, ALIGN_CENTER)
    end
  end
end
