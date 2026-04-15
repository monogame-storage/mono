-- Motion Sensor Demo
-- Tilt your device to move the ball. Shows accelerometer + gyroscope data.
local scr = screen()

function _init()
  mode(4)
end

local ball_x, ball_y
local trail = {}
local MAX_TRAIL = 20
local mx, my, mz = 0, 0, 0
local ga, gb, gg = 0, 0, 0
local enabled = false

function _start()
  ball_x = SCREEN_W / 2
  ball_y = SCREEN_H / 2
end

function _update()
  -- Read sensors once per frame
  mx = motion_x()
  my = motion_y()
  mz = motion_z()
  ga = gyro_alpha()
  gb = gyro_beta()
  gg = gyro_gamma()
  enabled = motion_enabled() == 1

  -- Move ball with accelerometer tilt
  ball_x = ball_x + mx * 3
  ball_y = ball_y + my * 3

  -- Clamp to screen
  if ball_x < 4 then ball_x = 4 end
  if ball_x > SCREEN_W - 4 then ball_x = SCREEN_W - 4 end
  if ball_y < 4 then ball_y = 4 end
  if ball_y > SCREEN_H - 4 then ball_y = SCREEN_H - 4 end

  -- Trail
  table.insert(trail, 1, { x = ball_x, y = ball_y })
  if #trail > MAX_TRAIL then table.remove(trail) end
end

function _draw()
  cls(scr, 0)

  -- Crosshair at center
  local cx, cy = SCREEN_W / 2, SCREEN_H / 2
  line(scr, cx - 10, cy, cx + 10, cy, 2)
  line(scr, cx, cy - 10, cx, cy + 10, 2)

  -- Trail (fading)
  for i = #trail, 1, -1 do
    local t = trail[i]
    local c = math.max(1, math.floor(15 - (i - 1) * 15 / MAX_TRAIL))
    circf(scr, math.floor(t.x), math.floor(t.y), 2, c)
  end

  -- Ball
  circf(scr, math.floor(ball_x), math.floor(ball_y), 3, 15)

  -- Accelerometer
  local col = enabled and 15 or 5
  text(scr, "MOTION", 2, 2, 8)
  text(scr, "X:" .. string.format("%.2f", mx), 2, 12, col)
  text(scr, "Y:" .. string.format("%.2f", my), 2, 20, col)
  text(scr, "Z:" .. string.format("%.2f", mz), 2, 28, col)

  -- Gyroscope
  text(scr, "GYRO", 2, 40, 8)
  text(scr, "A:" .. math.floor(ga), 2, 50, 11)
  text(scr, "B:" .. math.floor(gb), 2, 58, 11)
  text(scr, "G:" .. math.floor(gg), 2, 66, 11)

  -- Status
  if not enabled then
    text(scr, "TILT DEVICE", 0, SCREEN_H - 10, 5, ALIGN_HCENTER)
  end
end
