-- Bounce Ball (1-bit)
-- Ball bounces up/down automatically
-- Player controls left/right movement
-- Avoid holes in the floor!

local W = SCREEN_W
local H = SCREEN_H

-- units: 1m = H/10 = 14.4px
local M = H / 10

-- ball
local bx, by     -- position
local bvy = 0     -- vertical velocity
local br = 3      -- radius
local spd = 1.0   -- horizontal speed

-- physics
local GRAVITY = 0.3
local BOUNCE_VY = -4.2   -- ~1m jump
local FLOOR_Y

-- floor: segments with holes
-- hole = 0.8m wide, gap every 1m
local HOLE_W = M * 0.8
local GAP = M * 1
local floors = {}  -- {x, w} solid segments

-- score
local frames = 0

local SOLID_W = M * 1   -- 1m solid

local function build_floor()
  floors = {}
  local x = 1
  local floor_end = W - 1
  while x < floor_end do
    -- solid 1m
    local sw = SOLID_W
    if x + sw > floor_end then sw = floor_end - x end
    floors[#floors + 1] = { x = x, w = sw }
    x = x + sw + HOLE_W
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

function _init()
  FLOOR_Y = H - 1 - br
  bx = W / 2
  by = FLOOR_Y
  bvy = BOUNCE_VY
  frames = 0
  build_floor()
  bx = M * 0.5
end

function _update()
  -- player controls horizontal
  if btn("left") and bx - br > 1 then
    bx = bx - spd
  end
  if btn("right") and bx + br < W - 1 then
    bx = bx + spd
  end

  -- speed adjust
  if btnp("a") then spd = spd * 1.1 end
  if btnp("b") then spd = spd * 0.9 end
  -- jump adjust
  if btnp("up") then BOUNCE_VY = BOUNCE_VY * 1.1 end
  if btnp("down") then BOUNCE_VY = BOUNCE_VY * 0.9 end

  -- gravity + bounce
  bvy = bvy + GRAVITY
  by = by + bvy

  -- floor collision
  if by >= FLOOR_Y then
    if on_solid_floor(bx) then
      by = FLOOR_Y
      bvy = BOUNCE_VY
    else
      -- fell through hole, restart
      _init()
      return
    end
  end

  frames = frames + 1
end

function _draw()
  cls(0)

  -- walls (top, left, right)
  line(0, 0, W - 1, 0, 1)
  line(0, 0, 0, H - 1, 1)
  line(W - 1, 0, W - 1, H - 1, 1)

  -- floor segments
  local fy = H - 1
  for i = 1, #floors do
    local f = floors[i]
    line(f.x, fy, f.x + f.w, fy, 1)
  end

  -- ball
  circf(math.floor(bx), math.floor(by), br, 1)

  -- score
  text("TIME " .. math.floor(frames / 30), 3, 3, 1)

  -- debug: world + pixel coords (top right)
  local wx = string.format("%.1f", bx / M)
  local wy = string.format("%.1f", by / M)
  local px = tostring(math.floor(bx))
  local py = tostring(math.floor(by))
  text("W " .. wx .. "," .. wy, W - 75, 3, 1)
  text("P " .. px .. "," .. py, W - 75, 12, 1)
  text("S " .. string.format("%.2f", spd), W - 75, 21, 1)
  text("J " .. string.format("%.1f", -BOUNCE_VY), W - 75, 30, 1)
end
