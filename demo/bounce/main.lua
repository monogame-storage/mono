-- Bounce Ball
-- Ball bounces on a holey floor.
-- Move left/right to land on solid ground.
-- A = one-shot air dash (30-frame cooldown).

local scr = screen()
local W = SCREEN_W
local H = SCREEN_H

-- units: 1m = H/10 = 12px
local M = H / 10

-- ball
local bx, by     -- position
local bvy = 0    -- vertical velocity
local br = 3     -- radius
local spd = 1.2  -- horizontal speed (baked default)

-- physics
local GRAVITY = 0.3
local BOUNCE_VY = -4.2   -- ~1m jump
local FLOOR_Y

-- air dash
local DASH_VX = 3.0
local DASH_COOLDOWN_FRAMES = 30
local dash_cd = 0
local dash_dir = 0   -- -1 / +1 boost applied this frame

-- floor
local SOLID_W_BASE = M * 1.0   -- 12px
local HOLE_W_BASE = M * 0.8    -- ~10px
local floors = {}

-- squash-stretch
local squash_frames = 0  -- frames remaining where ball is squashed

-- motion trail (ring buffer)
local TRAIL_SIZE = 8
local trail = {}
local trail_head = 1

-- game state
local frames = 0
local game_over = false
local over_frames = 0
local OVER_DELAY = 60
local best = 0

local function init_trail()
  trail = {}
  trail_head = 1
  for i = 1, TRAIL_SIZE do
    trail[i] = false
  end
end

local function push_trail(x, y)
  trail[trail_head] = { x = x, y = y }
  trail_head = trail_head + 1
  if trail_head > TRAIL_SIZE then trail_head = 1 end
end

local function current_solid_w()
  -- ramp 12 -> 8 over ~30s (900 frames)
  local t = math.min(frames / 900, 1)
  return SOLID_W_BASE - (SOLID_W_BASE - 8) * t
end

local function current_hole_w()
  -- ramp 10 -> 14 over ~30s
  local t = math.min(frames / 900, 1)
  return HOLE_W_BASE + (14 - HOLE_W_BASE) * t
end

local function build_floor()
  floors = {}
  local sw = current_solid_w()
  local hw = current_hole_w()
  local x = 1
  local floor_end = W - 1
  while x < floor_end do
    local seg_w = sw
    if x + seg_w > floor_end then seg_w = floor_end - x end
    floors[#floors + 1] = { x = x, w = seg_w }
    -- jitter hole/solid widths slightly so each run differs
    x = x + seg_w + hw + math.random(-1, 1)
  end
end

local function on_solid_floor(cx)
  local margin = br * 0.5
  local left = cx - margin
  local right = cx + margin
  for i = 1, #floors do
    local f = floors[i]
    if right >= f.x and left <= f.x + f.w then
      return true
    end
  end
  return false
end

local function reset_game()
  math.randomseed(math.floor(time() * 1000))
  FLOOR_Y = H - 1 - br
  bx = M * 0.5
  by = FLOOR_Y
  bvy = BOUNCE_VY
  frames = 0
  game_over = false
  over_frames = 0
  dash_cd = 0
  squash_frames = 0
  build_floor()
  init_trail()
end

function _init()
  mode(4)
end

function _start()
  best = data_load("bounce_best") or 0
  reset_game()
end

function _update()
  if game_over then
    over_frames = over_frames + 1
    -- after OVER_DELAY, accept A or START to restart
    if over_frames >= OVER_DELAY then
      if btnp("a") or btnp("start") then
        reset_game()
      end
    end
    return
  end

  -- horizontal movement
  if btn("left") and bx - br > 1 then
    bx = bx - spd
  end
  if btn("right") and bx + br < W - 1 then
    bx = bx + spd
  end

  -- one-shot air dash (A)
  if dash_cd > 0 then dash_cd = dash_cd - 1 end
  if btnp("a") and dash_cd == 0 then
    -- dash in the held horizontal direction; default to right if neither held
    local dir = 0
    if btn("left") then dir = -1
    elseif btn("right") then dir = 1
    else dir = 1 end
    bx = bx + dir * DASH_VX
    dash_cd = DASH_COOLDOWN_FRAMES
  end

  -- clamp inside walls
  if bx - br < 1 then bx = 1 + br end
  if bx + br > W - 1 then bx = W - 1 - br end

  -- gravity
  bvy = bvy + GRAVITY
  by = by + bvy

  -- record trail (pre-collision position is fine)
  push_trail(math.floor(bx), math.floor(by))

  -- countdown squash
  if squash_frames > 0 then squash_frames = squash_frames - 1 end

  -- floor collision
  if by >= FLOOR_Y then
    if on_solid_floor(bx) then
      by = FLOOR_Y
      bvy = BOUNCE_VY
      squash_frames = 2
      note(0, "G4", 0.04)
    else
      -- fell through hole
      game_over = true
      over_frames = 0
      noise(0, 0.25, "low", 400)
      cam_shake(4)
      -- best score
      if frames > best then
        best = frames
        data_save("bounce_best", best)
      end
      return
    end
  end

  frames = frames + 1
end

function _draw()
  cls(scr, 0)

  -- walls
  line(scr, 0, 0, W - 1, 0, 15)
  line(scr, 0, 0, 0, H - 1, 15)
  line(scr, W - 1, 0, W - 1, H - 1, 15)

  -- floor segments
  local fy = H - 1
  for i = 1, #floors do
    local f = floors[i]
    line(scr, f.x, fy, f.x + f.w, fy, 15)
  end

  -- motion trail (older pixels dimmer)
  for i = 1, TRAIL_SIZE do
    local idx = ((trail_head - 1 - i - 1) % TRAIL_SIZE) + 1
    local p = trail[idx]
    if p then
      -- color ramp: closer = brighter
      local c = 4 + (TRAIL_SIZE - i)  -- 4..11ish
      if c > 11 then c = 11 end
      if c < 3 then c = 3 end
      pix(scr, p.x, p.y, c)
      pix(scr, p.x - 1, p.y, c)
    end
  end

  -- ball: squash on landing
  local ix, iy = math.floor(bx), math.floor(by)
  if squash_frames > 0 then
    -- wide and short ellipse approximation: 4 wide, 2 tall
    rectf(scr, ix - 4, iy - 1, 9, 3, 15)
  else
    circf(scr, ix, iy, br, 15)
  end

  -- HUD: centered TIME and BEST
  local tsec = math.floor(frames / 30)
  text(scr, "TIME " .. tsec, W / 2, 4, 15, ALIGN_HCENTER)
  text(scr, "BEST " .. math.floor(best / 30), W / 2, 13, 7, ALIGN_HCENTER)

  -- game over overlay
  if game_over then
    rectf(scr, 30, 45, 100, 30, 0)
    rect(scr, 30, 45, 100, 30, 15)
    text(scr, "GAME OVER", W / 2, 52, 15, ALIGN_HCENTER)
    if over_frames >= OVER_DELAY then
      -- blink "PRESS A"
      if math.floor(frame() / 15) % 2 == 0 then
        text(scr, "PRESS A", W / 2, 64, 11, ALIGN_HCENTER)
      end
    else
      text(scr, "TIME " .. tsec, W / 2, 64, 7, ALIGN_HCENTER)
    end
  end
end
