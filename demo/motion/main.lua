-- Motion Sensor Demo
-- Tilt your device to move the ball over a scrolling grid.
local scr = screen()

function _init()
  mode(4)
end

local ball_x, ball_y
local cam_x, cam_y = 0, 0
local trail = {}
local MAX_TRAIL = 20
local mx, my, mz = 0, 0, 0
local ga, gb, gg = 0, 0, 0
local enabled = false
local GRID = 16 -- grid cell size

function _start()
  ball_x = 0
  ball_y = 0
end

function _update()
  mx = motion_x()
  my = motion_y()
  mz = motion_z()
  ga = gyro_alpha()
  gb = gyro_beta()
  gg = gyro_gamma()
  enabled = motion_enabled() == 1

  -- Move ball with tilt (world coords, no clamp)
  ball_x = ball_x + mx * 3
  ball_y = ball_y + my * 3

  -- Camera follows ball
  cam_x = ball_x - SCREEN_W / 2
  cam_y = ball_y - SCREEN_H / 2

  -- Trail
  table.insert(trail, 1, { x = ball_x, y = ball_y })
  if #trail > MAX_TRAIL then table.remove(trail) end
end

function _draw()
  cls(scr, 0)
  cam(cam_x, cam_y)

  -- Grid background (infinite feel)
  local gx0 = math.floor(cam_x / GRID) * GRID
  local gy0 = math.floor(cam_y / GRID) * GRID
  for gx = gx0, gx0 + SCREEN_W + GRID, GRID do
    line(scr, gx, gy0, gx, gy0 + SCREEN_H + GRID, 2)
  end
  for gy = gy0, gy0 + SCREEN_H + GRID, GRID do
    line(scr, gx0, gy, gx0 + SCREEN_W + GRID, gy, 2)
  end

  -- Origin marker
  line(scr, -6, 0, 6, 0, 4)
  line(scr, 0, -6, 0, 6, 4)

  -- Trail (fading)
  for i = #trail, 1, -1 do
    local t = trail[i]
    local c = math.max(1, math.floor(15 - (i - 1) * 15 / MAX_TRAIL))
    circf(scr, math.floor(t.x), math.floor(t.y), 2, c)
  end

  -- Ball
  circf(scr, math.floor(ball_x), math.floor(ball_y), 3, 15)

  -- HUD (camera-independent)
  cam(0, 0)

  local col = enabled and 15 or 5
  text(scr, "MOTION", 2, 2, 8)
  text(scr, "X:" .. string.format("%.2f", mx), 2, 12, col)
  text(scr, "Y:" .. string.format("%.2f", my), 2, 20, col)
  text(scr, "Z:" .. string.format("%.2f", mz), 2, 28, col)

  text(scr, "GYRO", 2, 40, 8)
  text(scr, "A:" .. math.floor(ga), 2, 50, 11)
  text(scr, "B:" .. math.floor(gb), 2, 58, 11)
  text(scr, "G:" .. math.floor(gg), 2, 66, 11)

  -- Position
  text(scr, math.floor(ball_x) .. "," .. math.floor(ball_y), SCREEN_W - 2, 2, 5, ALIGN_RIGHT)

  if not enabled then
    text(scr, "TILT DEVICE", 0, SCREEN_H - 10, 5, ALIGN_HCENTER)
  end
end
