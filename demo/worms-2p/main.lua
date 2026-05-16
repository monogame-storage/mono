-- Mono Worms 2P (lockstep netplay)
-- Turn-based artillery duel. Open the cart in two browser windows.
-- Active player only:
--   LEFT/RIGHT : aim angle
--   UP/DOWN    : adjust power
--   A (Z key)  : fire
-- Both peers must render identically (lockstep VRAM hash), so there is no
-- "you are player N" marker on screen — your local player slot is whichever
-- side the engine routes your hardware to.

local scr = screen()

local TANK_W      = 6
local TANK_H      = 4
local BARREL_LEN  = 5
local GRAVITY     = 0.12
local WIND_MAX    = 0.06
local MAX_HP      = 100
local DIRECT_HIT  = 40
local SPLASH      = 18
local TURN_DELAY  = 30        -- frames between projectile death and next turn
local ANGLE_STEP  = 1.5
local POWER_STEP  = 0.06
local POWER_MIN, POWER_MAX = 1.5, 7.5

local phase             -- "aim" | "fly" | "between" | "over"
local turn              -- 0 or 1
local phase_timer
local players           -- [0]={x,y,hp,angle,power}, [1]=...
local projectile        -- {x,y,vx,vy} or nil
local wind              -- horizontal acceleration per frame
local terrain           -- terrain[x] = ground y (top of dirt) for x in 0..SCREEN_W-1
local winner            -- 0, 1, -1 (draw), or nil
local game_started

local function gen_terrain()
  terrain = {}
  local s1 = math.random() * 100
  local s2 = math.random() * 100
  local s3 = math.random() * 100
  for x = 0, SCREEN_W - 1 do
    local h = 92
      + math.floor(math.sin(x * 0.05 + s1) * 8)
      + math.floor(math.sin(x * 0.15 + s2) * 4)
      + math.floor(math.sin(x * 0.30 + s3) * 2)
    if h < 60  then h = 60  end
    if h > 115 then h = 115 end
    terrain[x] = h
  end
end

local function flatten_at(cx, radius)
  local h = terrain[cx]
  for x = cx - radius, cx + radius do
    if x >= 0 and x < SCREEN_W then terrain[x] = h end
  end
end

local function init_match()
  local p0x, p1x = 18, 142
  gen_terrain()
  flatten_at(p0x, 4)
  flatten_at(p1x, 4)
  players = {
    [0] = { x = p0x - TANK_W/2, y = terrain[p0x] - TANK_H, hp = MAX_HP, angle =  55, power = 4 },
    [1] = { x = p1x - TANK_W/2, y = terrain[p1x] - TANK_H, hp = MAX_HP, angle = 125, power = 4 },
  }
  projectile  = nil
  turn        = 0
  phase       = "aim"
  phase_timer = 0
  wind        = (math.random() * 2 - 1) * WIND_MAX
  winner      = nil
end

function _init()
  mode(4)
  use_pause(false)
end

function _start()
  net.start()
  game_started = false
end

local function fire()
  local p = players[turn]
  local rad = math.rad(p.angle)
  local cx = p.x + TANK_W/2
  local cy = p.y
  projectile = {
    x  = cx + math.cos(rad) * BARREL_LEN,
    y  = cy - math.sin(rad) * BARREL_LEN,
    vx = math.cos(rad) * p.power,
    vy = -math.sin(rad) * p.power,
  }
  phase = "fly"
end

local function update_aim()
  local p = players[turn]
  if btn("left",  turn) then p.angle = p.angle + ANGLE_STEP end
  if btn("right", turn) then p.angle = p.angle - ANGLE_STEP end
  if btn("up",    turn) then p.power = math.min(POWER_MAX, p.power + POWER_STEP) end
  if btn("down",  turn) then p.power = math.max(POWER_MIN, p.power - POWER_STEP) end
  if p.angle < 5   then p.angle = 5   end
  if p.angle > 175 then p.angle = 175 end
  if btnp("a", turn) then fire() end
end

local function dist2(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return dx*dx + dy*dy
end

local function explode_at(x, y)
  for i = 0, 1 do
    local p = players[i]
    local d2 = dist2(x, y, p.x + TANK_W/2, p.y + TANK_H/2)
    if d2 < 25 then
      p.hp = math.max(0, p.hp - DIRECT_HIT)
    elseif d2 < 169 then
      p.hp = math.max(0, p.hp - SPLASH)
    end
  end
end

local function update_fly()
  if not projectile then return end
  projectile.vx = projectile.vx + wind
  projectile.vy = projectile.vy + GRAVITY
  projectile.x  = projectile.x + projectile.vx
  projectile.y  = projectile.y + projectile.vy
  if projectile.x < -8 or projectile.x > SCREEN_W + 8 or projectile.y > SCREEN_H + 8 then
    projectile = nil
    phase, phase_timer = "between", TURN_DELAY
    return
  end
  local ix = math.floor(projectile.x)
  if ix >= 0 and ix < SCREEN_W and projectile.y >= terrain[ix] then
    explode_at(projectile.x, projectile.y)
    projectile = nil
    phase, phase_timer = "between", TURN_DELAY
  end
end

local function check_winner()
  local a, b = players[0].hp, players[1].hp
  if a <= 0 and b <= 0 then winner = -1
  elseif a <= 0 then winner = 1
  elseif b <= 0 then winner = 0 end
end

local function next_turn()
  check_winner()
  if winner ~= nil then phase = "over"; return end
  turn  = 1 - turn
  wind  = (math.random() * 2 - 1) * WIND_MAX
  phase = "aim"
end

function _update()
  if not game_started then
    if net.status() ~= "playing" then return end
    math.randomseed(net.seed())
    init_match()
    game_started = true
    return
  end

  if     phase == "aim"     then update_aim()
  elseif phase == "fly"     then update_fly()
  elseif phase == "between" then
    phase_timer = phase_timer - 1
    if phase_timer <= 0 then next_turn() end
  end
end

local function draw_terrain()
  for x = 0, SCREEN_W - 1 do
    line(scr, x, terrain[x], x, SCREEN_H - 1, 5)
  end
end

local function draw_tank(p, color)
  rectf(scr, p.x, p.y, TANK_W, TANK_H, color)
  local cx  = p.x + TANK_W/2
  local cy  = p.y
  local rad = math.rad(p.angle)
  local bx  = cx + math.cos(rad) * BARREL_LEN
  local by  = cy - math.sin(rad) * BARREL_LEN
  line(scr, cx, cy, bx, by, color)
end

local function draw_hp(x, p, color)
  local w = math.floor((p.hp / MAX_HP) * 28)
  rect(scr, x, 2, 28, 4, 6)
  if w > 0 then rectf(scr, x + 1, 3, w, 2, color) end
end

local function draw_wind()
  local mag = math.floor(math.abs(wind) / WIND_MAX * 5 + 0.5)
  local dir = wind > 0.001 and ">" or wind < -0.001 and "<" or "-"
  text(scr, "wind " .. dir .. mag, 80, 2, 7, ALIGN_HCENTER)
end

function _draw()
  cls(scr, 1)

  if not game_started then
    text(scr, "WORMS 2P", 80, 50, 12, ALIGN_HCENTER)
    return
  end

  draw_terrain()
  draw_tank(players[0], 12)
  draw_tank(players[1], 8)
  if projectile then
    circf(scr, projectile.x, projectile.y, 1, 15)
  end

  draw_hp(4, players[0], 12)
  draw_hp(SCREEN_W - 32, players[1], 8)
  draw_wind()

  if phase == "aim" then
    local p  = players[turn]
    local a  = math.floor(p.angle + 0.5)
    local pw = math.floor(p.power * 10 + 0.5)
    local col = turn == 0 and 12 or 8
    text(scr, "P" .. (turn+1) .. "  a:" .. a .. " p:" .. pw, 80, SCREEN_H - 9, col, ALIGN_HCENTER)
  elseif phase == "over" then
    local msg = (winner == -1) and "DRAW" or ("P" .. (winner+1) .. " WINS")
    text(scr, msg, 80, 55, 15, ALIGN_HCENTER)
  end
end
