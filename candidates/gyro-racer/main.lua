-- GYRO RACER
-- Steer by tilting your phone. Lean into the turns.
-- Motion Madness contest entry (1-bit, 160x120)

------------------------------------------------------------
-- CONSTANTS
------------------------------------------------------------
local W = 160
local H = 120
local ROAD_W = 600
local SEG_LEN = 100
local DRAW_DIST = 40
local MAX_SPEED = 280
local ACCEL = 5
local BRAKE = 10
local FRICTION = 1.5
local OFFROAD_DRAG = 6
local TURN_RATE = 0.035
local CAM_HEIGHT = 900

------------------------------------------------------------
-- TRACK DATA (curve, hill_delta per section)
------------------------------------------------------------
local TRACK = {
  {len=40, curve=0,    hill=0},
  {len=60, curve=0.6,  hill=0.3},
  {len=30, curve=0,    hill=-0.2},
  {len=70, curve=-0.8, hill=0.1},
  {len=25, curve=0,    hill=0},
  {len=50, curve=1.0,  hill=0.4},
  {len=35, curve=0,    hill=-0.3},
  {len=80, curve=-0.5, hill=0.2},
  {len=20, curve=0,    hill=0},
  {len=45, curve=0.7,  hill=-0.1},
  {len=30, curve=0,    hill=0.5},
  {len=55, curve=-1.0, hill=-0.4},
  {len=40, curve=0.3,  hill=0},
  {len=20, curve=0,    hill=-0.2},
}

------------------------------------------------------------
-- STATE
------------------------------------------------------------
local segs = {}
local numSegs = 0
local playerX = 0       -- -1..1 on road
local speed = 0
local dist = 0
local steer = 0         -- visual steering angle
local lap = 0
local lapTime = 0
local bestTime = 0
local totalTime = 0
local raceStarted = false

-- Demo mode
local demoMode = true
local demoTimer = 0
local idleTimer = 0
local IDLE_TIMEOUT = 180  -- frames (~3 sec) of no input to enter demo

-- Sound timers
local engineTimer = 0
local screechTimer = 0

-- Screen surface
local scr

------------------------------------------------------------
-- TRACK BUILDING
------------------------------------------------------------
local function buildTrack()
  segs = {}
  local idx = 0
  for _, sec in ipairs(TRACK) do
    for i = 1, sec.len do
      idx = idx + 1
      local s = {}
      s.index = idx
      s.curve = sec.curve
      s.y = math.sin(idx * 0.015) * 400 * sec.hill
      s.z1 = (idx - 1) * SEG_LEN
      s.z2 = idx * SEG_LEN
      segs[idx] = s
    end
  end
  numSegs = idx
end

------------------------------------------------------------
-- 3D PROJECTION
------------------------------------------------------------
local function project(wz, wy, wx, camZ, camY, camX)
  local dz = wz - camZ
  if dz <= 10 then return nil end
  local scale = 0.75 / dz
  local sx = math.floor(W * 0.5 + scale * (wx - camX) * W)
  local sy = math.floor(H * 0.5 - scale * (wy - camY) * H + 20)
  local sw = math.floor(scale * ROAD_W * W)
  return sx, sy, sw
end

------------------------------------------------------------
-- DRAW FILLED TRAPEZOID (road segment)
------------------------------------------------------------
local function trapezoid(x1, y1, w1, x2, y2, w2, col)
  if y1 == y2 then return end
  local yA = math.max(0, math.min(y1, y2))
  local yB = math.min(H - 1, math.max(y1, y2))
  for y = yA, yB do
    local t = (y - y1) / (y2 - y1)
    local cx = x1 + t * (x2 - x1)
    local hw = (w1 + t * (w2 - w1)) * 0.5
    local lx = math.max(0, math.floor(cx - hw))
    local rx = math.min(W - 1, math.floor(cx + hw))
    if rx >= lx then
      rectf(scr, lx, y, rx - lx + 1, 1, col)
    end
  end
end

------------------------------------------------------------
-- DITHER PATTERN: fill a horizontal span with 50% dither
-- Uses horizontal line stripes (every other row) for speed
------------------------------------------------------------
local function ditherRow(y, x1, x2, col)
  if y % 2 == 0 then
    local lx = math.max(0, math.floor(x1))
    local rx = math.min(W - 1, math.floor(x2))
    if rx >= lx then
      rectf(scr, lx, y, rx - lx + 1, 1, col)
    end
  end
end

------------------------------------------------------------
-- AI STEERING (for demo mode)
------------------------------------------------------------
local function aiSteer()
  local segIdx = math.floor(dist / SEG_LEN) % numSegs + 1
  local seg = segs[segIdx]
  -- steer toward center and anticipate curves
  local target = -seg.curve * 0.4 - playerX * 0.6
  return math.max(-1, math.min(1, target))
end

------------------------------------------------------------
-- DRAW CAR
------------------------------------------------------------
local function drawCar(tilt)
  local cx = W / 2
  local cy = H - 18
  -- Tilt offset for visual feedback
  local tx = math.floor(tilt * 4)

  -- Body
  rectf(scr, cx - 7 + tx, cy, 14, 10, 1)
  rectf(scr, cx - 5 + tx, cy - 4, 10, 5, 1)

  -- Cabin window
  rectf(scr, cx - 3 + tx, cy - 3, 6, 3, 0)

  -- Wheels
  rectf(scr, cx - 9 + tx, cy + 1, 3, 4, 1)
  rectf(scr, cx + 6 + tx, cy + 1, 3, 4, 1)
  rectf(scr, cx - 9 + tx, cy + 6, 3, 4, 1)
  rectf(scr, cx + 6 + tx, cy + 6, 3, 4, 1)
end

------------------------------------------------------------
-- DRAW SCENERY (trees/posts along road)
------------------------------------------------------------
local function drawPost(sx, sy, sw, side)
  local px = sx + side * (sw * 0.5 + 6)
  local ph = math.max(2, math.floor(sw * 0.02))
  if px >= 0 and px < W and sy > 10 then
    rectf(scr, math.floor(px), sy - ph * 3, 2, ph * 3, 1)
    rectf(scr, math.floor(px) - 1, sy - ph * 3 - 2, 4, 3, 1)
  end
end

------------------------------------------------------------
-- DRAW BACKGROUND
------------------------------------------------------------
local function drawBG()
  -- Sky: top half white
  rectf(scr, 0, 0, W, H / 2 + 10, 0)

  -- Horizon mountains
  for x = 0, W - 1 do
    local mh = 8 + math.sin(x * 0.06 + dist * 0.0001) * 5
                  + math.sin(x * 0.12) * 3
    local my = math.floor(H / 2 + 10 - mh)
    rectf(scr, x, my, 1, math.floor(mh), 1)
  end
end

------------------------------------------------------------
-- DRAW HUD
------------------------------------------------------------
local function drawHUD()
  -- Speed bar
  local spd = speed / MAX_SPEED
  rectf(scr, W - 44, 3, 40, 5, 0)
  rect(scr, W - 44, 3, 40, 5, 1)
  if spd > 0 then
    rectf(scr, W - 43, 4, math.floor(38 * spd), 3, 1)
  end
  text(scr, "SPD", W - 62, 4, 1)

  -- Lap
  text(scr, "LAP " .. lap, 3, 4, 1)

  -- Time
  local t = math.floor(lapTime / 60)
  local f = math.floor((lapTime % 60) / 60 * 100)
  local ts = string.format("%d.%02d", t, f)
  text(scr, ts, 3, 14, 1)

  -- Best time
  if bestTime > 0 then
    local bt = math.floor(bestTime / 60)
    local bf = math.floor((bestTime % 60) / 60 * 100)
    text(scr, "BEST " .. string.format("%d.%02d", bt, bf), W - 62, 14, 1)
  end

  -- Demo label
  if demoMode then
    text(scr, "DEMO", W / 2 - 10, H / 2 - 20, 1)
    local blink = math.floor(totalTime / 30) % 2
    if blink == 0 then
      text(scr, "TILT TO PLAY", W / 2 - 28, H / 2 - 10, 1)
    end
  end
end

------------------------------------------------------------
-- SOUND
------------------------------------------------------------
local function doSound()
  engineTimer = engineTimer + 1
  if engineTimer >= 4 then
    engineTimer = 0
    if speed > 10 then
      local freq = 60 + math.floor(speed * 0.5)
      if tone then tone(0, freq, freq + 20, 0.1) end
    end
  end

  -- Screech on hard steering at speed
  if math.abs(steer) > 0.6 and speed > 100 then
    screechTimer = screechTimer + 1
    if screechTimer >= 8 then
      screechTimer = 0
      if noise then noise(1, 0.1) end
    end
  else
    screechTimer = 0
  end
end

------------------------------------------------------------
-- CHECK INPUT ACTIVITY
------------------------------------------------------------
local function hasInput()
  if motion_enabled and motion_enabled() then
    local mx = motion_x()
    local my = motion_y()
    if math.abs(mx) > 0.08 or math.abs(my) > 0.08 then
      return true
    end
  end
  if btn("left") or btn("right") or btn("up") or btn("down") then
    return true
  end
  if btn("a") or btn("b") or btn("start") then
    return true
  end
  return false
end

------------------------------------------------------------
-- READ STEERING INPUT
------------------------------------------------------------
local function readSteer()
  local sx = 0
  if motion_enabled and motion_enabled() then
    sx = motion_x()  -- -1..1
    -- Apply a slight deadzone and curve for natural feel
    if math.abs(sx) < 0.05 then
      sx = 0
    else
      -- Smooth cubic response curve
      sx = sx * math.abs(sx)
    end
  elseif axis_x then
    sx = axis_x()
    if sx == 0 then
      if btn("left") then sx = -1 end
      if btn("right") then sx = 1 end
    end
  end
  return math.max(-1, math.min(1, sx))
end

local function readAccel()
  local ay = 0
  if motion_enabled and motion_enabled() then
    ay = motion_y()  -- positive = forward tilt
    if math.abs(ay) < 0.08 then ay = 0 end
  else
    if btn("up") or btn("a") then ay = 1 end
    if btn("down") or btn("b") then ay = -1 end
  end
  return math.max(-1, math.min(1, ay))
end

------------------------------------------------------------
-- LIFECYCLE
------------------------------------------------------------
function _init()
  mode(1)
end

function _start()
  buildTrack()
  playerX = 0
  speed = 0
  dist = 0
  steer = 0
  lap = 0
  bestTime = 0
  lapTime = 0
  totalTime = 0
  raceStarted = false
  demoMode = true
  demoTimer = 0
  idleTimer = 0
  engineTimer = 0
  screechTimer = 0
end

function _update()
  totalTime = totalTime + 1

  -- Check for demo mode transitions
  if demoMode then
    if hasInput() then
      demoMode = false
      speed = 0
      playerX = 0
      dist = 0
      lap = 0
      lapTime = 0
      raceStarted = true
      -- Lap completion chime
      if note then note(0, "C5", 8) end
    end
  else
    if not hasInput() then
      idleTimer = idleTimer + 1
      if idleTimer > IDLE_TIMEOUT then
        demoMode = true
        idleTimer = 0
      end
    else
      idleTimer = 0
    end
  end

  -- Read input
  local turnInput, accelInput
  if demoMode then
    -- AI drives
    turnInput = aiSteer()
    accelInput = 0.7  -- constant acceleration
    demoTimer = demoTimer + 1
  else
    turnInput = readSteer()
    accelInput = readAccel()
  end

  -- Steering (speed-sensitive)
  local steerFactor = math.min(speed / 120, 1.0) * TURN_RATE
  steer = turnInput
  playerX = playerX + turnInput * steerFactor

  -- Track curve influence on player (centrifugal force)
  local segIdx = math.floor(dist / SEG_LEN) % numSegs + 1
  local curSeg = segs[segIdx]
  if curSeg then
    playerX = playerX + curSeg.curve * speed * 0.000015
  end

  -- Clamp player on road area
  playerX = math.max(-1.8, math.min(1.8, playerX))

  -- Off-road check
  local offroad = math.abs(playerX) > 0.85

  -- Acceleration / braking
  if accelInput > 0.1 then
    speed = speed + ACCEL * accelInput
  elseif accelInput < -0.1 then
    speed = speed + BRAKE * accelInput  -- negative = braking
  else
    speed = speed - FRICTION
  end

  if offroad then
    speed = speed - OFFROAD_DRAG
  end

  speed = math.max(0, math.min(speed, MAX_SPEED))

  -- Move forward
  dist = dist + speed * 0.12

  -- Lap detection
  local trackLen = numSegs * SEG_LEN
  if dist >= trackLen then
    dist = dist - trackLen
    if raceStarted then
      lap = lap + 1
      if bestTime == 0 or lapTime < bestTime then
        bestTime = lapTime
      end
      lapTime = 0
      -- Lap chime
      if note then note(0, "C5", 6) end
      if note then note(1, "E5", 6) end
      if note then note(2, "G5", 6) end
    end
  end

  -- Timer
  if raceStarted and not demoMode then
    lapTime = lapTime + 1
  end

  -- Sound
  doSound()
end

function _draw()
  scr = screen()
  cls(scr, 0)
  drawBG()

  -- Road rendering
  local baseSeg = math.floor(dist / SEG_LEN) % numSegs
  local camZ = dist
  local baseY = 0
  if segs[baseSeg + 1] then
    baseY = segs[baseSeg + 1].y
  end
  local camY = CAM_HEIGHT + baseY
  local camX = playerX * ROAD_W

  -- Accumulate curve offset for rendering
  local curveOff = 0
  local dcurve = 0

  -- Store projected segments for far-to-near drawing
  local projected = {}
  for n = 0, DRAW_DIST do
    local si = (baseSeg + n) % numSegs + 1
    local seg = segs[si]
    curveOff = curveOff + dcurve
    dcurve = dcurve + seg.curve * 0.001

    local wz1 = seg.z1 + (n > 0 and 0 or 0)
    -- Adjust z for wrapping
    if si <= baseSeg then
      wz1 = wz1 + numSegs * SEG_LEN
    end
    local wz2 = wz1 + SEG_LEN

    local wx1 = curveOff * ROAD_W
    local wx2 = (curveOff + dcurve) * ROAD_W
    local wy1 = seg.y
    local nextSi = (baseSeg + n + 1) % numSegs + 1
    local wy2 = segs[nextSi].y

    local sx1, sy1, sw1 = project(wz1, wy1, wx1, camZ, camY, camX)
    local sx2, sy2, sw2 = project(wz2, wy2, wx2, camZ, camY, camX)

    if sx1 and sx2 then
      projected[#projected + 1] = {
        sx1=sx1, sy1=sy1, sw1=sw1,
        sx2=sx2, sy2=sy2, sw2=sw2,
        idx=si, n=n
      }
    end
  end

  -- Draw far to near
  for i = #projected, 1, -1 do
    local p = projected[i]
    local stripe = (math.floor((p.idx - 1) / 3) % 2 == 0)

    -- Grass (full width)
    if p.sy2 ~= p.sy1 then
      local yA = math.min(p.sy1, p.sy2)
      local yB = math.max(p.sy1, p.sy2)
      yA = math.max(0, yA)
      yB = math.min(H - 1, yB)
      for y = yA, yB do
        if stripe then
          ditherRow(y, 0, W - 1, 1)
        else
          rectf(scr, 0, y, W, 1, 0)
        end
      end
    end

    -- Road surface
    local roadCol = stripe and 1 or 0
    trapezoid(p.sx1, p.sy1, p.sw1, p.sx2, p.sy2, p.sw2, roadCol)

    -- Road edge lines (always white on black road, black on white road)
    local edgeCol = stripe and 0 or 1
    local ew1 = math.max(1, math.floor(p.sw1 * 0.03))
    local ew2 = math.max(1, math.floor(p.sw2 * 0.03))
    -- Left edge
    trapezoid(p.sx1 - math.floor(p.sw1*0.5), p.sy1, ew1,
              p.sx2 - math.floor(p.sw2*0.5), p.sy2, ew2, edgeCol)
    -- Right edge
    trapezoid(p.sx1 + math.floor(p.sw1*0.5), p.sy1, ew1,
              p.sx2 + math.floor(p.sw2*0.5), p.sy2, ew2, edgeCol)

    -- Center dashes
    if p.idx % 4 < 2 then
      local cw1 = math.max(1, math.floor(p.sw1 * 0.015))
      local cw2 = math.max(1, math.floor(p.sw2 * 0.015))
      trapezoid(p.sx1, p.sy1, cw1, p.sx2, p.sy2, cw2, edgeCol)
    end

    -- Roadside posts every 8 segments
    if p.idx % 8 == 0 and p.n < DRAW_DIST - 2 then
      drawPost(p.sx1, p.sy1, p.sw1, -1)
      drawPost(p.sx1, p.sy1, p.sw1, 1)
    end
  end

  -- Player car
  drawCar(steer)

  -- Off-road rumble strips (visual)
  if math.abs(playerX) > 0.85 then
    local blink = math.floor(totalTime / 2) % 2
    if blink == 1 then
      rectf(scr, 0, H - 4, W, 2, 1)
    end
    -- Camera shake when off-road at speed
    if speed > 50 then
      cam_shake(1)
    end
  end

  -- HUD
  drawHUD()
end
