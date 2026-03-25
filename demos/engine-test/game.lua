-- Engine Test Suite: Menu-based tests for Mono Engine v2
-- Tests: shooter, camera, sprites, input, sound, tilemap, mini RPG

local W = 320
local H = 240
local SS = 16

---------------------------------------------------------------
-- SPRITE HELPER: parse visual 16x16 sprite and register
---------------------------------------------------------------
local _sprNames = {}
local _sprNext = 1

local function defVisual(name, art)
  local data = ""
  for line in art:gmatch("[^\n]+") do
    local trimmed = line:match("^%s*(.-)%s*$")
    if #trimmed == 16 then
      for i = 1, 16 do
        local ch = trimmed:sub(i, i)
        if ch == "." or ch == "0" then data = data .. "0"
        else data = data .. ch end
      end
    end
  end
  if #data == 256 then
    defSprite(_sprNext, data)
    _sprNames[name] = _sprNext
    _sprNext = _sprNext + 1
  end
end

-- Override sprite_id to use our local names
local _orig_sprite_id = sprite_id
sprite_id = function(name)
  return _sprNames[name] or 0
end

---------------------------------------------------------------
-- SPRITES (all 16x16 visual format)
---------------------------------------------------------------
defVisual("ship", [[
.......33.......
......3333......
.....333333.....
....33333333....
...3333333333...
..333332233333..
.33333322333333.
3333332..2333333
.33332....23333.
..3332....2333..
...332....233...
....32....23....
.....2....2.....
......2..2......
.......22.......
................
]])

defVisual("bullet", [[
................
................
................
................
................
.......33.......
......3333......
.....333333.....
......3333......
.......33.......
................
................
................
................
................
................
]])

defVisual("enemy_a1", [[
................
...22222222.....
..222222222222..
.22211222211222.
2222112222112222
2222222222222222
.22222222222222.
..222222222222..
...2222222222...
....222..222....
.....22..22.....
................
................
................
................
................
]])

defVisual("enemy_a2", [[
................
...33333333.....
..333333333333..
.33311333311333.
3333113333113333
3333333333333333
.33333333333333.
..333333333333..
...3333333333...
....333..333....
.....33..33.....
................
................
................
................
................
]])

defVisual("enemy_b", [[
.......11.......
......1111......
.....111111.....
....11111111....
...1111221111...
..111122221111..
.11112222221111.
..111122221111..
...1111221111...
....11111111....
.....111111.....
......1111......
.......11.......
................
................
................
]])

defVisual("particle", [[
33..............
33..............
................
................
................
................
................
................
................
................
................
................
................
................
................
................
]])

defVisual("star", [[
................
.......3........
................
...1............
................
................
..........2.....
................
................
.....3..........
................
................
............1...
................
..2.............
................
]])

defVisual("star2", [[
..1.......2.....
................
........1.......
................
....3...........
................
..........1.....
................
.1..............
..........3.....
................
.......1........
................
...........2....
.2..............
................
]])

-- Tile sprites for tilemap and RPG modes
defVisual("tile_wall", [[
3333333333333333
3222222222222223
3211111111111123
3211111111111123
3211111111111123
3211111111111123
3211111111111123
3211111111111123
3211111111111123
3211111111111123
3211111111111123
3211111111111123
3211111111111123
3211111111111123
3222222222222223
3333333333333333
]])

defVisual("tile_floor", [[
1...............
................
....1...........
................
................
..........1.....
................
................
......1.........
................
................
...........1....
................
.1..............
................
...........1....
]])

defVisual("tile_grass", [[
.......2........
..2.........2...
................
....2.........2.
2...............
........2.......
...2............
..........2.....
.2..............
..........2.....
....2...........
................
2.........2.....
........2.......
...2............
.........2......
]])

defVisual("tile_deco", [[
......3333......
.....333333.....
....33322333....
...3332222333...
..333222222333..
.33322222222333.
3332222222222333
3322222222222233
3322222222222233
3332222222222333
.33322222222333.
..333222222333..
...3332222333...
....33322333....
.....333333.....
......3333......
]])

defVisual("tile_path", [[
2222222222222222
2111111111111112
2111111111111112
2111111111111112
2111111111111112
2111111111111112
2111111111111112
2111111111111112
2111111111111112
2111111111111112
2111111111111112
2111111111111112
2111111111111112
2111111111111112
2111111111111112
2222222222222222
]])

defVisual("npc", [[
......1111......
.....111111.....
....11311311....
....11111111....
.....111111.....
......3333......
.....333333.....
....33333333....
...3333333333...
....33333333....
.....333333.....
......3333......
.....33..33.....
....33....33....
...33......33...
..33........33..
]])

---------------------------------------------------------------
-- SHARED STATE
---------------------------------------------------------------
local MODE_MENU = 0
local MODE_SHOOTER = 1
local MODE_CAMERA = 2
local MODE_SPRITES = 3
local MODE_INPUT = 4
local MODE_SOUND = 5
local MODE_TILEMAP = 6
local MODE_RPG = 7

local currentMode = MODE_MENU
local menuCursor = 0
local menuItems = { "SHOOTER", "CAMERA", "SPRITES", "INPUT", "SOUND", "TILEMAP", "MINI RPG" }
local titleBlink = 0

---------------------------------------------------------------
-- INPUT MONITOR (drawn on every screen)
---------------------------------------------------------------
function drawInputMonitor()
  local y = 0
  local x = 220
  local ul = btn("up") and 3 or 1
  local dl = btn("down") and 3 or 1
  local ll = btn("left") and 3 or 1
  local rl = btn("right") and 3 or 1
  text("U", x + 10, y, ul)
  text("L", x, y + 8, ll)
  text("R", x + 20, y + 8, rl)
  text("D", x + 10, y + 16, dl)
  local al = btn("a") and 3 or 1
  local bl = btn("b") and 3 or 1
  local sl = btn("start") and 3 or 1
  local sel = btn("select") and 3 or 1
  text("A", x + 50, y + 4, al)
  text("B", x + 60, y + 4, bl)
  text("ST", x + 72, y, sl)
  text("SE", x + 72, y + 10, sel)
end

---------------------------------------------------------------
-- TILEMAP SETUP (scrolling starfield for shooter)
---------------------------------------------------------------
-- Star background: individual dots falling at different speeds
local stars = {}
local STAR_COUNT = 40

local function initStars()
  stars = {}
  for i = 1, STAR_COUNT do
    stars[i] = {
      x = flr(rnd(320)),
      y = flr(rnd(240)),
      speed = 0.3 + rnd(1.2),
      bright = flr(rnd(3)) + 1  -- color 1, 2, or 3
    }
  end
end

local function updateStars()
  for i = 1, #stars do
    local s = stars[i]
    s.y = s.y + s.speed
    if s.y > 240 then
      s.y = -2
      s.x = flr(rnd(320))
      s.speed = 0.3 + rnd(1.2)
      s.bright = flr(rnd(3)) + 1
    end
  end
end

local function drawStars()
  for i = 1, #stars do
    local s = stars[i]
    pix(flr(s.x), flr(s.y), s.bright)
  end
end

---------------------------------------------------------------
-- SHOOTER TEST STATE
---------------------------------------------------------------
local SHIP_SPEED = 3
local BULLET_SPEED = -5
local ENEMY_SPEED = 1.2
local SPAWN_RATE = 50
local MAX_BULLETS = 6

local playerX = 0
local playerY = 0
local shootCooldown = 0
local spawnTimer = 0
local invincible = 0
local scrollY = 0
local shooterScore = 0
local shooterLives = 3
local shooterLevel = 1
local weaponType = 0  -- 0=single, 1=double, 2=spread, 3=rapid
local WEAPON_NAMES = {"SINGLE", "DOUBLE", "SPREAD", "RAPID"}
local WEAPON_COUNT = 4

local function spawnExplosion(x, y)
  local partId = sprite_id("particle")
  local count = flr(rnd(4)) + 5
  for i = 1, count do
    local angle = rnd(6.28)
    local speed = rnd(2.5) + 0.5
    spawn({
      group = "particle",
      pos = { x = x, y = y },
      vel = { x = speed * math.cos(angle), y = speed * math.sin(angle) - 1.5 },
      sprite = partId,
      gravity = 0.1,
      lifetime = flr(rnd(10)) + 15,
      offscreen = true,
      anchor_x = 0.5, anchor_y = 0.5,
    })
  end
  note(1, "C5", 0.06)
end

local function shooterInit()
  shooterScore = 0
  shooterLives = 3
  shooterLevel = 1
  weaponType = 0
  playerX = W / 2 - SS / 2
  playerY = H - 30
  shootCooldown = 0
  spawnTimer = 0
  invincible = 60
  scrollY = 0
  killAll("bullet")
  killAll("enemy")
  killAll("particle")
  killAll("player")
  initStars()

  -- Register collision tags (no callbacks — poll in update)
  onCollide("bullet", "enemy", "bullet_enemy")
  onCollide("player", "enemy", "player_enemy")

  bgm({
    "E4 . G4 . A4 . G4 . E4 . D4 . E4 . G4 . A4 . B4 . A4 . G4 . E4 . D4 . C4 . D4 .",
    "C3 - - - E3 - - - A2 - - - E3 - - - C3 - - - G2 - - - A2 - - - E3 - - -",
  }, 180, true)
end

local function shooterUpdate()
  -- Return to menu
  if false then -- was btnp("b")
    killAll("bullet")
    killAll("enemy")
    killAll("particle")
    killAll("player")
    bgm_stop()
    currentMode = MODE_MENU
    return
  end

  -- Game over restart
  if shooterLives <= 0 then
    if btnp("a") or btnp("start") then
      shooterInit()
    end
    return
  end

  -- Poll collisions (no async callbacks)
  while true do
    local hit = pollCollision()
    if not hit then break end
    if hit.tag == "bullet_enemy" then
      spawnExplosion(hit.bx + 7, hit.by + 5)
      shooterScore = shooterScore + 100
      note(0, "E5", 0.08)
    elseif hit.tag == "player_enemy" then
      if invincible <= 0 then
        spawnExplosion(playerX + 8, playerY + 5)
        shooterLives = shooterLives - 1
        invincible = 90
        note(0, "C3", 0.2)
        if shooterLives <= 0 then
          shooterLives = 0
        end
      end
    end
  end

  scrollY = scrollY + 0.5
  updateStars()

  if btn("left") and playerX > 0 then
    playerX = playerX - SHIP_SPEED
  end
  if btn("right") and playerX < W - SS then
    playerX = playerX + SHIP_SPEED
  end
  if btn("up") and playerY > H / 3 then
    playerY = playerY - SHIP_SPEED
  end
  if btn("down") and playerY < H - SS then
    playerY = playerY + SHIP_SPEED
  end

  if invincible > 0 then
    invincible = invincible - 1
  end

  -- Weapon rotation
  if btnp("b") then
    weaponType = (weaponType + 1) % WEAPON_COUNT
    note(0, "C5", 0.05)
  end

  if shootCooldown > 0 then
    shootCooldown = shootCooldown - 1
  end
  local bulletId = sprite_id("bullet")
  if btn("a") and shootCooldown <= 0 and ecount("bullet") < MAX_BULLETS then
    local cx = playerX + 8
    local cy = playerY - 4
    if weaponType == 0 then
      -- Single shot
      spawn({
        group = "bullet",
        pos = { x = cx, y = cy },
        vel = { x = 0, y = BULLET_SPEED },
        sprite = bulletId,
        hitbox = { r = 3 },
        offscreen = true,
        anchor_x = 0.5, anchor_y = 0.5,
      })
      shootCooldown = 6
    elseif weaponType == 1 then
      -- Double shot
      spawn({
        group = "bullet",
        pos = { x = cx - 5, y = cy },
        vel = { x = 0, y = BULLET_SPEED },
        sprite = bulletId,
        hitbox = { r = 3 },
        offscreen = true,
        anchor_x = 0.5, anchor_y = 0.5,
      })
      spawn({
        group = "bullet",
        pos = { x = cx + 5, y = cy },
        vel = { x = 0, y = BULLET_SPEED },
        sprite = bulletId,
        hitbox = { r = 3 },
        offscreen = true,
        anchor_x = 0.5, anchor_y = 0.5,
      })
      shootCooldown = 8
    elseif weaponType == 2 then
      -- Spread (3-way)
      spawn({
        group = "bullet",
        pos = { x = cx, y = cy },
        vel = { x = 0, y = BULLET_SPEED },
        sprite = bulletId,
        hitbox = { r = 3 },
        offscreen = true,
        anchor_x = 0.5, anchor_y = 0.5,
      })
      spawn({
        group = "bullet",
        pos = { x = cx, y = cy },
        vel = { x = -2, y = BULLET_SPEED },
        sprite = bulletId,
        hitbox = { r = 3 },
        offscreen = true,
        anchor_x = 0.5, anchor_y = 0.5,
      })
      spawn({
        group = "bullet",
        pos = { x = cx, y = cy },
        vel = { x = 2, y = BULLET_SPEED },
        sprite = bulletId,
        hitbox = { r = 3 },
        offscreen = true,
        anchor_x = 0.5, anchor_y = 0.5,
      })
      shootCooldown = 10
    elseif weaponType == 3 then
      -- Rapid
      spawn({
        group = "bullet",
        pos = { x = cx, y = cy },
        vel = { x = 0, y = BULLET_SPEED * 1.5 },
        sprite = bulletId,
        hitbox = { r = 3 },
        offscreen = true,
        anchor_x = 0.5, anchor_y = 0.5,
      })
      shootCooldown = 3
    end
    note(0, "A5", 0.03)
  end

  spawnTimer = spawnTimer + 1
  local rate = SPAWN_RATE - shooterLevel * 4
  if rate < 15 then rate = 15 end

  if spawnTimer >= rate then
    spawnTimer = 0
    local ex = flr(rnd(W - SS * 2)) + SS
    local etype = flr(rnd(3))

    if etype == 0 then
      local ea1 = sprite_id("enemy_a1")
      local ea2 = sprite_id("enemy_a2")
      spawn({
        group = "enemy",
        pos = { x = ex, y = -SS },
        vel = { x = rnd(2) - 1, y = ENEMY_SPEED + rnd(0.5) },
        sprite = ea1,
        hitbox = { w = 14, h = 10, ox = -7, oy = -5 },
        offscreen = true,
        anchor_x = 0.5, anchor_y = 0.5,
      })
    elseif etype == 1 then
      local ebId = sprite_id("enemy_b")
      spawn({
        group = "enemy",
        pos = { x = ex, y = -SS },
        vel = { x = rnd(1.6) - 0.8, y = ENEMY_SPEED + rnd(0.3) },
        sprite = ebId,
        hitbox = { r = 6 },
        offscreen = true,
        anchor_x = 0.5, anchor_y = 0.5,
      })
    else
      local ea1 = sprite_id("enemy_a1")
      spawn({
        group = "enemy",
        pos = { x = ex, y = -SS },
        vel = { x = rnd(2.4) - 1.2, y = ENEMY_SPEED + 0.8 },
        sprite = ea1,
        hitbox = { w = 14, h = 10, ox = -7, oy = -5 },
        offscreen = true,
        anchor_x = 0.5, anchor_y = 0.5,
      })
    end
  end

  each("enemy", function(e)
    if e.isRotating then
      e.rotAngle = e.rotAngle + 0.1
    end
  end)

  local newLevel = flr(shooterScore / 1000) + 1
  if newLevel > shooterLevel then
    shooterLevel = newLevel
  end

  killAll("player")
  if invincible <= 0 or flr(invincible / 3) % 2 == 0 then
    spawn({
      group = "player",
      pos = { x = playerX + 8, y = playerY + 8 },
      hitbox = { w = 12, h = 14, ox = -6, oy = -7 },
      anchor_x = 0.5, anchor_y = 0.5,
    })
  end
end

local function shooterDraw()
  cls(0)

  if shooterLives <= 0 then
    -- Game over sub-screen
    drawStars()
    text("GAME OVER", 120, 80, 3)
    text("SCORE:" .. shooterScore, 120, 110, 2)
    if flr(frame() / 20) % 2 == 0 then
      text("PRESS A TO RETRY", 95, 150, 3)
    end
    text("[B] BACK TO MENU", 95, 180, 1)
    drawInputMonitor()
    return
  end

  drawStars()

  local shipId = sprite_id("ship")
  if invincible <= 0 or flr(invincible / 3) % 2 == 0 then
    sprT(shipId, flr(playerX), flr(playerY))
  end

  each("enemy", function(e)
    if e.isRotating and e.rotSprite then
      sprRot(e.rotSprite, flr(e.pos.x) + 8, flr(e.pos.y) + 7, e.rotAngle)
    end
  end)

  text("SCORE:" .. shooterScore, 4, 4, 3)
  text("LV:" .. shooterLevel, 140, 4, 2)
  text("[B]" .. WEAPON_NAMES[weaponType + 1], 4, 14, 2)

  for i = 1, shooterLives do
    sprT(shipId, W - 20 * i, 1)
  end

  text("[B] MENU", 4, H - 10, 1)
  drawInputMonitor()
end

---------------------------------------------------------------
-- CAMERA TEST STATE
---------------------------------------------------------------
local CAM_MAP_W = 640
local CAM_MAP_H = 480
local camPX = 320
local camPY = 240
local camSpeed = 2

local function cameraInit()
  camPX = CAM_MAP_W / 2
  camPY = CAM_MAP_H / 2
  cam_reset()
end

local function cameraUpdate()
  -- B = dash (3x speed while held)
  local spd = camSpeed
  if btn("b") then spd = camSpeed * 3 end

  local dx = 0
  local dy = 0
  if btn("left") then dx = dx - 1 end
  if btn("right") then dx = dx + 1 end
  if btn("up") then dy = dy - 1 end
  if btn("down") then dy = dy + 1 end

  -- Normalize diagonal
  if dx ~= 0 and dy ~= 0 then
    local inv = 0.7071 -- 1/sqrt(2)
    dx = dx * inv
    dy = dy * inv
  end

  camPX = camPX + dx * spd
  camPY = camPY + dy * spd

  -- Clamp to map bounds
  if camPX < 8 then camPX = 8 end
  if camPX > CAM_MAP_W - 8 then camPX = CAM_MAP_W - 8 end
  if camPY < 8 then camPY = 8 end
  if camPY > CAM_MAP_H - 8 then camPY = CAM_MAP_H - 8 end

  -- Camera shake on A
  if btnp("a") then
    cam_shake(8)
    note(0, "C3", 0.1)
  end

  -- Camera follows player (centered)
  local cx = camPX - W / 2
  local cy = camPY - H / 2
  if cx < 0 then cx = 0 end
  if cy < 0 then cy = 0 end
  if cx > CAM_MAP_W - W then cx = CAM_MAP_W - W end
  if cy > CAM_MAP_H - H then cy = CAM_MAP_H - H end
  cam(cx, cy)
end

local function cameraDraw()
  cls(0)

  -- Draw grid over the large map
  -- Vertical lines every 32px
  for gx = 0, CAM_MAP_W, 32 do
    line(gx, 0, gx, CAM_MAP_H, 1)
  end
  -- Horizontal lines every 32px
  for gy = 0, CAM_MAP_H, 32 do
    line(0, gy, CAM_MAP_W, gy, 1)
  end

  -- Draw markers at 64px intervals
  for mx = 0, CAM_MAP_W, 64 do
    for my = 0, CAM_MAP_H, 64 do
      circf(mx, my, 2, 2)
    end
  end

  -- Draw boundary rectangle
  rect(0, 0, CAM_MAP_W, CAM_MAP_H, 3)

  -- Draw cross at center of map
  local mcx = CAM_MAP_W / 2
  local mcy = CAM_MAP_H / 2
  line(mcx - 20, mcy, mcx + 20, mcy, 2)
  line(mcx, mcy - 20, mcx, mcy + 20, 2)

  -- Draw corner labels (world-space coordinates rendered via spr-affected draw)
  rectf(4, 4, 40, 12, 0)
  rectf(CAM_MAP_W - 60, 4, 60, 12, 0)
  rectf(4, CAM_MAP_H - 16, 40, 12, 0)
  rectf(CAM_MAP_W - 60, CAM_MAP_H - 16, 60, 12, 0)

  -- Draw player (ship sprite)
  local shipId = sprite_id("ship")
  sprT(shipId, flr(camPX) - 8, flr(camPY) - 8)

  -- Player position circle indicator
  circ(flr(camPX), flr(camPY), 12, 3)

  -- HUD (text is NOT affected by cam, so it draws in screen space)
  text("CAMERA TEST", 4, 4, 3)
  text("POS:" .. flr(camPX) .. "," .. flr(camPY), 4, 14, 2)
  text("MAP:" .. CAM_MAP_W .. "x" .. CAM_MAP_H, 4, 24, 1)
  text("[A] SHAKE  [B] DASH  [START] MENU", 4, H - 10, 1)
  text("ARROWS: MOVE", 4, H - 20, 1)
  drawInputMonitor()
end

---------------------------------------------------------------
-- SPRITES GALLERY STATE
---------------------------------------------------------------
local sprNames = { "ship", "bullet", "enemy_a1", "enemy_a2", "enemy_b", "particle", "star", "star2" }
local sprCursor = 0
local sprFlipX = false
local sprFlipY = false
local sprTimer = 0

local function spritesInit()
  sprCursor = 0
  sprFlipX = false
  sprFlipY = false
  sprTimer = 0
end

local function spritesUpdate()
  sprTimer = sprTimer + 1
  -- Navigate
  if btnp("left") then
    sprCursor = sprCursor - 1
    if sprCursor < 0 then sprCursor = #sprNames - 1 end
    sprFlipX = false
    sprFlipY = false
    note(0, "G5", 0.03)
  end
  if btnp("right") then
    sprCursor = sprCursor + 1
    if sprCursor >= #sprNames then sprCursor = 0 end
    sprFlipX = false
    sprFlipY = false
    note(0, "G5", 0.03)
  end
  -- Toggle flip
  if btnp("a") then
    sprFlipX = not sprFlipX
    note(0, "E5", 0.03)
  end
  if false then -- was btnp("b")
    sprFlipY = not sprFlipY
    note(0, "D5", 0.03)
  end
end

local function spritesDraw()
  cls(0)
  text("SPRITE GALLERY", 100, 4, 3)

  -- Thumbnail strip
  local thumbSize = 28
  local stripX = flr((W - #sprNames * thumbSize) / 2)
  local stripY = 20

  for idx = 1, #sprNames do
    local sid = sprite_id(sprNames[idx])
    local tx = stripX + (idx - 1) * thumbSize
    local selected = (sprCursor == idx - 1)

    -- Cell background
    if selected then
      rectf(tx, stripY, thumbSize - 2, thumbSize - 2, 1)
      rect(tx - 1, stripY - 1, thumbSize, thumbSize, 3)
    else
      rect(tx, stripY, thumbSize - 2, thumbSize - 2, 1)
    end
    sprT(sid, tx + 5, stripY + 5)
  end

  local selName = sprNames[sprCursor + 1]
  local selId = sprite_id(selName)

  -- === Main preview: large center with flip applied ===
  local pvCX = W / 2
  local pvCY = 105

  -- Preview background
  rectf(pvCX - 30, pvCY - 30, 60, 60, 1)
  rect(pvCX - 31, pvCY - 31, 62, 62, 2)

  -- Draw with current flip state + hitbox
  sprT(selId, pvCX - 8, pvCY - 8, sprFlipX, sprFlipY)
  dbg(pvCX - 8, pvCY - 8, 16, 16)

  -- Label
  text(selName, pvCX - flr(#selName * 5 / 2), pvCY + 36, 3)

  -- === Animated demos (right side) ===
  local demoX = 250

  -- 1. Auto-rotation (using unified draw)
  text("ROTATE", demoX - 8, 58, 2)
  local autoAngle = sprTimer * 0.06
  draw(selId, demoX + 8, 82, autoAngle, 1, 1, 8, 8)

  -- 2. Scale animation (using unified draw)
  text("SCALE", demoX - 6, 105, 2)
  local sc = 1 + math.sin(sprTimer * 0.08) * 0.8
  draw(selId, demoX + 8, 125, 0, sc, sc, 8, 8)
  local scSz = flr(16 * sc)
  dbg(demoX + 8 - flr(scSz / 2), 125 - flr(scSz / 2), scSz, scSz)
  text(tostring(flr(sc * 100) / 100) .. "x", demoX - 4, 142, 1)

  -- 3. Rot+Scale combo (using unified draw)
  text("R+S", demoX - 2, 148, 2)
  local comboSc = 0.8 + math.sin(sprTimer * 0.1) * 0.4
  draw(selId, demoX + 8, 168, sprTimer * 0.04, comboSc, comboSc, 8, 8)
  local csSz = flr(16 * comboSc)
  dbgC(demoX + 8, 168, flr(csSz / 2))

  -- === Static demos (left side) ===
  local leftX = 20

  -- Normal
  text("NORMAL", leftX, 58, 2)
  sprT(selId, leftX + 2, 68)

  -- Flip-X
  text("FLIP-X", leftX, 92, 2)
  sprT(selId, leftX + 2, 102, true, false)

  -- Flip-Y
  text("FLIP-Y", leftX, 126, 2)
  sprT(selId, leftX + 2, 136, false, true)

  -- Both
  text("BOTH", leftX, 160, 2)
  sprT(selId, leftX + 2, 170, true, true)

  -- === Flip state indicator ===
  local flipLabel = "FLIP:"
  if sprFlipX then flipLabel = flipLabel .. " X" end
  if sprFlipY then flipLabel = flipLabel .. " Y" end
  if not sprFlipX and not sprFlipY then flipLabel = flipLabel .. " -" end
  text(flipLabel, pvCX - 20, pvCY + 46, 2)

  -- Controls
  text("LR:SEL A:FLIPX B:FLIPY UD:ROT", 20, H - 20, 1)
  text("[START] MENU", 4, H - 10, 1)
  drawInputMonitor()
end

---------------------------------------------------------------
-- INPUT TEST STATE
---------------------------------------------------------------
local function inputInit()
end

local function inputUpdate()
  if false then -- was btnp("b")
    currentMode = MODE_MENU
    return
  end
end

local function inputDraw()
  cls(0)
  text("INPUT MONITOR", 105, 8, 3)

  -- D-pad (large circles)
  local dpadX = 80
  local dpadY = 120
  local btnR = 16

  -- Up
  local upOn = btn("up")
  circ(dpadX, dpadY - 40, btnR, upOn and 3 or 1)
  if upOn then circf(dpadX, dpadY - 40, btnR - 2, 3) end
  text("UP", dpadX - 6, dpadY - 44, upOn and 0 or 2)

  -- Down
  local downOn = btn("down")
  circ(dpadX, dpadY + 40, btnR, downOn and 3 or 1)
  if downOn then circf(dpadX, dpadY + 40, btnR - 2, 3) end
  text("DN", dpadX - 6, dpadY + 36, downOn and 0 or 2)

  -- Left
  local leftOn = btn("left")
  circ(dpadX - 40, dpadY, btnR, leftOn and 3 or 1)
  if leftOn then circf(dpadX - 40, dpadY, btnR - 2, 3) end
  text("LT", dpadX - 46, dpadY - 4, leftOn and 0 or 2)

  -- Right
  local rightOn = btn("right")
  circ(dpadX + 40, dpadY, btnR, rightOn and 3 or 1)
  if rightOn then circf(dpadX + 40, dpadY, btnR - 2, 3) end
  text("RT", dpadX + 34, dpadY - 4, rightOn and 0 or 2)

  -- Action buttons
  local actX = 240
  local actY = 100

  -- A button
  local aOn = btn("a")
  circ(actX, actY, btnR, aOn and 3 or 1)
  if aOn then circf(actX, actY, btnR - 2, 3) end
  text("A", actX - 3, actY - 4, aOn and 0 or 2)

  -- B button
  local bOn = btn("b")
  circ(actX - 36, actY + 10, btnR, bOn and 3 or 1)
  if bOn then circf(actX - 36, actY + 10, btnR - 2, 3) end
  text("B", actX - 39, actY + 6, bOn and 0 or 2)

  -- Start
  local stOn = btn("start")
  circ(actX - 10, actY + 50, 12, stOn and 3 or 1)
  if stOn then circf(actX - 10, actY + 50, 10, 3) end
  text("ST", actX - 17, actY + 46, stOn and 0 or 2)

  -- Select
  local seOn = btn("select")
  circ(actX - 40, actY + 50, 12, seOn and 3 or 1)
  if seOn then circf(actX - 40, actY + 50, 10, 3) end
  text("SE", actX - 47, actY + 46, seOn and 0 or 2)

  -- Labels
  text("D-PAD", dpadX - 12, dpadY + 65, 2)
  text("BUTTONS", actX - 40, actY + 75, 2)

  -- Note: B returns to menu, shown at bottom
  text("(B exits to menu after release)", 50, H - 20, 1)
  text("[B] MENU", 4, H - 10, 1)
  drawInputMonitor()
end

---------------------------------------------------------------
-- SOUND TEST STATE
---------------------------------------------------------------
local soundBgmOn = false
local soundLastNote = ""

local function soundInit()
  soundBgmOn = false
  soundLastNote = ""
end

local function soundUpdate()
  if false then -- was btnp("b")
    bgm_stop()
    soundBgmOn = false
    currentMode = MODE_MENU
    return
  end

  -- Direction keys play notes
  if btnp("up") then
    note(0, "C4", 0.2)
    soundLastNote = "C4"
  end
  if btnp("down") then
    note(0, "E4", 0.2)
    soundLastNote = "E4"
  end
  if btnp("left") then
    note(0, "G4", 0.2)
    soundLastNote = "G4"
  end
  if btnp("right") then
    note(0, "A4", 0.2)
    soundLastNote = "A4"
  end

  -- A toggles BGM
  if btnp("a") then
    if soundBgmOn then
      bgm_stop()
      soundBgmOn = false
    else
      bgm({
        "E4 . G4 . A4 . G4 . E4 . D4 . E4 . G4 . A4 . B4 . A4 . G4 . E4 . D4 . C4 . D4 .",
        "C3 - - - E3 - - - A2 - - - E3 - - - C3 - - - G2 - - - A2 - - - E3 - - -",
      }, 180, true)
      soundBgmOn = true
    end
  end
end

local function soundDraw()
  cls(0)
  text("SOUND TEST", 115, 8, 3)

  -- Note display area
  local cx = W / 2
  local cy = 80

  text("PRESS DIRECTION KEYS TO PLAY NOTES:", 30, 40, 2)

  -- Show note mapping
  text("UP    = C4", 100, 60, 1)
  text("DOWN  = E4", 100, 72, 1)
  text("LEFT  = G4", 100, 84, 1)
  text("RIGHT = A4", 100, 96, 1)

  -- Current note display
  if soundLastNote ~= "" then
    text("LAST NOTE: " .. soundLastNote, 100, 120, 3)
    -- Visual indicator
    circf(cx, 150, 20, 3)
    text(soundLastNote, cx - 8, 146, 0)
  else
    text("LAST NOTE: ---", 100, 120, 1)
    circ(cx, 150, 20, 1)
  end

  -- BGM status
  local bgmLabel = soundBgmOn and "BGM: ON" or "BGM: OFF"
  local bgmColor = soundBgmOn and 3 or 1
  text(bgmLabel, 130, 185, bgmColor)
  text("[A] TOGGLE BGM", 105, 200, 2)

  text("[B] MENU", 4, H - 10, 1)
  drawInputMonitor()
end

---------------------------------------------------------------
-- TILEMAP TEST STATE
---------------------------------------------------------------
local TMAP_W = 20
local TMAP_H = 15
local tmapCurX = 0
local tmapCurY = 0
local tmapBlink = 0
local tmapSelectedTile = 1  -- index into tmapTileSprIds (0=empty,1=wall,2=floor,3=deco)
-- Tile types: 0=empty, 1=wall, 2=floor, 3=decoration
local TMAP_TILE_NAMES = {"EMPTY", "WALL", "FLOOR", "DECO"}
local tmapTileSprIds = {}  -- filled at init

local function tilemapInit()
  tmapCurX = 0
  tmapCurY = 0
  tmapBlink = 0
  tmapSelectedTile = 1
  tmapTileSprIds[0] = 0
  tmapTileSprIds[1] = sprite_id("tile_wall")
  tmapTileSprIds[2] = sprite_id("tile_floor")
  tmapTileSprIds[3] = sprite_id("tile_deco")

  -- Initialize tilemap with a border of walls and floor inside
  for ty = 0, TMAP_H - 1 do
    for tx = 0, TMAP_W - 1 do
      if tx == 0 or tx == TMAP_W - 1 or ty == 0 or ty == TMAP_H - 1 then
        mset(tx, ty, tmapTileSprIds[1])  -- wall border
      else
        mset(tx, ty, tmapTileSprIds[2])  -- floor inside
      end
    end
  end
  -- Place some decorations
  mset(5, 5, tmapTileSprIds[3])
  mset(10, 7, tmapTileSprIds[3])
  mset(14, 3, tmapTileSprIds[3])
  mset(8, 12, tmapTileSprIds[3])
end

local function tilemapUpdate()
  tmapBlink = tmapBlink + 1

  -- Move cursor
  if btnp("up") and tmapCurY > 0 then
    tmapCurY = tmapCurY - 1
    note(0, "G5", 0.02)
  end
  if btnp("down") and tmapCurY < TMAP_H - 1 then
    tmapCurY = tmapCurY + 1
    note(0, "G5", 0.02)
  end
  if btnp("left") and tmapCurX > 0 then
    tmapCurX = tmapCurX - 1
    note(0, "G5", 0.02)
  end
  if btnp("right") and tmapCurX < TMAP_W - 1 then
    tmapCurX = tmapCurX + 1
    note(0, "G5", 0.02)
  end

  -- B cycles selected tile type
  if btnp("b") then
    tmapSelectedTile = (tmapSelectedTile + 1) % 4
    note(0, "E5", 0.04)
  end

  -- A places the selected tile at cursor
  if btnp("a") then
    mset(tmapCurX, tmapCurY, tmapTileSprIds[tmapSelectedTile])
    note(0, "C5", 0.04)
  end
end

local function tilemapDraw()
  cls(0)

  -- Draw the map using map() function
  map(0, 0, TMAP_W, TMAP_H, 0, 0)

  -- Blinking cursor overlay
  if flr(tmapBlink / 8) % 2 == 0 then
    rect(tmapCurX * SS, tmapCurY * SS, SS, SS, 3)
  else
    rect(tmapCurX * SS, tmapCurY * SS, SS, SS, 2)
  end

  -- HUD
  local curTile = mget(tmapCurX, tmapCurY)
  local tileName = "EMPTY"
  for k, v in pairs(tmapTileSprIds) do
    if v == curTile then tileName = TMAP_TILE_NAMES[k + 1] break end
  end

  local selName = TMAP_TILE_NAMES[tmapSelectedTile + 1]

  rectf(0, H - 34, W, 34, 0)
  text("TILEMAP " .. TMAP_W .. "x" .. TMAP_H, 4, H - 32, 3)
  text("BRUSH: " .. selName, 100, H - 32, 3)
  -- Draw selected tile preview
  if tmapTileSprIds[tmapSelectedTile] ~= 0 then
    sprT(tmapTileSprIds[tmapSelectedTile], 160, H - 34)
  end
  text("POS:" .. tmapCurX .. "," .. tmapCurY .. " TILE:" .. tileName .. " ID:" .. curTile, 4, H - 20, 2)
  text("[A] PLACE  [B] CYCLE  [START] MENU", 4, H - 10, 1)
  drawInputMonitor()
end

---------------------------------------------------------------
-- MINI RPG TEST STATE
---------------------------------------------------------------
local RPG_MAP_W = 40
local RPG_MAP_H = 30
local rpgPX = 5     -- player tile X
local rpgPY = 5     -- player tile Y
local rpgTargetX = 5
local rpgTargetY = 5
local rpgMoving = false
local rpgMoveTimer = 0
local rpgMoveFrames = 8
local rpgMoveFromX = 0
local rpgMoveFromY = 0
local rpgCamX = 0
local rpgCamY = 0
local rpgDialogText = ""
local rpgDialogActive = false
local rpgNearNPC = false
local rpgNPCList = {}
local rpgFrame = 0
local RPG_WEAPONS = {"SWORD", "BOW", "STAFF", "SHIELD"}
local rpgWeaponIdx = 1

local rpgWallId = 0
local rpgFloorId = 0
local rpgGrassId = 0
local rpgPathId = 0
local rpgNpcSprId = 0
local rpgShipId = 0

local function rpgIsWall(tx, ty)
  if tx < 0 or tx >= RPG_MAP_W or ty < 0 or ty >= RPG_MAP_H then return true end
  return mget(tx, ty) == rpgWallId
end

local function rpgBuildMap()
  rpgWallId = sprite_id("tile_wall")
  rpgFloorId = sprite_id("tile_floor")
  rpgGrassId = sprite_id("tile_grass")
  rpgPathId = sprite_id("tile_path")
  rpgNpcSprId = sprite_id("npc")
  rpgShipId = sprite_id("ship")

  -- Fill with grass
  for ty = 0, RPG_MAP_H - 1 do
    for tx = 0, RPG_MAP_W - 1 do
      mset(tx, ty, rpgGrassId)
    end
  end

  -- Build dungeon rooms (walls)
  -- Room 1: top-left area
  for tx = 2, 12 do
    mset(tx, 2, rpgWallId)
    mset(tx, 10, rpgWallId)
  end
  for ty = 2, 10 do
    mset(2, ty, rpgWallId)
    mset(12, ty, rpgWallId)
  end
  -- Floor inside room 1
  for ty = 3, 9 do
    for tx = 3, 11 do
      mset(tx, ty, rpgFloorId)
    end
  end
  -- Door in room 1
  mset(7, 10, rpgFloorId)

  -- Room 2: right area
  for tx = 20, 35 do
    mset(tx, 5, rpgWallId)
    mset(tx, 15, rpgWallId)
  end
  for ty = 5, 15 do
    mset(20, ty, rpgWallId)
    mset(35, ty, rpgWallId)
  end
  -- Floor inside room 2
  for ty = 6, 14 do
    for tx = 21, 34 do
      mset(tx, ty, rpgFloorId)
    end
  end
  -- Door in room 2
  mset(20, 10, rpgFloorId)

  -- Room 3: bottom area
  for tx = 5, 18 do
    mset(tx, 18, rpgWallId)
    mset(tx, 26, rpgWallId)
  end
  for ty = 18, 26 do
    mset(5, ty, rpgWallId)
    mset(18, ty, rpgWallId)
  end
  -- Floor inside room 3
  for ty = 19, 25 do
    for tx = 6, 17 do
      mset(tx, ty, rpgFloorId)
    end
  end
  -- Door in room 3
  mset(12, 18, rpgFloorId)

  -- Paths connecting rooms (using path tiles)
  -- Path from room1 door (7,10) down to room3 door (12,18)
  for ty = 11, 17 do
    mset(7, ty, rpgPathId)
    mset(8, ty, rpgPathId)
  end
  for tx = 8, 12 do
    mset(tx, 17, rpgPathId)
  end

  -- Path from room1 area to room2 door (20,10)
  for tx = 8, 19 do
    mset(tx, 11, rpgPathId)
    mset(tx, 12, rpgPathId)
  end

  -- Path from room2 down
  for ty = 16, 22 do
    mset(25, ty, rpgPathId)
    mset(26, ty, rpgPathId)
  end

  -- Some scattered walls as obstacles
  mset(15, 14, rpgWallId)
  mset(16, 14, rpgWallId)
  mset(15, 15, rpgWallId)
end

local function rpgInit()
  rpgPX = 5
  rpgPY = 5
  rpgTargetX = 5
  rpgTargetY = 5
  rpgMoving = false
  rpgMoveTimer = 0
  rpgDialogText = ""
  rpgDialogActive = false
  rpgNearNPC = false
  rpgFrame = 0
  rpgWeaponIdx = 1

  killAll("npc")

  rpgBuildMap()

  -- Place player in room 1
  rpgPX = 6
  rpgPY = 6
  rpgTargetX = 6
  rpgTargetY = 6

  -- Spawn NPCs using ECS
  rpgNPCList = {
    { tx = 8, ty = 5, msg = "WELCOME TO THE DUNGEON!\nBE CAREFUL OUT THERE." },
    { tx = 27, ty = 9, msg = "THIS IS ROOM TWO.\nFIND THE TREASURE!" },
    { tx = 10, ty = 22, msg = "I GUARD THIS ROOM.\nNOTHING SHALL PASS!" },
  }

  for i, npc in ipairs(rpgNPCList) do
    spawn({
      group = "npc",
      pos = { x = npc.tx * SS + 8, y = npc.ty * SS + 8 },
      sprite = rpgNpcSprId,
      anchor_x = 0.5, anchor_y = 0.5,
      npcIndex = i,
      tileX = npc.tx,
      tileY = npc.ty,
      z = npc.ty,
    })
  end
end

local function rpgUpdate()
  rpgFrame = rpgFrame + 1

  -- Dialog handling
  if rpgDialogActive then
    if btnp("a") then
      rpgDialogActive = false
      rpgDialogText = ""
    end
    return  -- freeze movement while dialog open
  end

  -- B cycles weapon (cosmetic)
  if btnp("b") then
    rpgWeaponIdx = rpgWeaponIdx % #RPG_WEAPONS + 1
    note(0, "A5", 0.03)
  end

  -- Movement (tile-based with smooth interpolation)
  if rpgMoving then
    rpgMoveTimer = rpgMoveTimer + 1
    if rpgMoveTimer >= rpgMoveFrames then
      rpgPX = rpgTargetX
      rpgPY = rpgTargetY
      rpgMoving = false
      rpgMoveTimer = 0
    end
  end

  if not rpgMoving then
    local dx = 0
    local dy = 0
    if btnp("up") then dy = -1
    elseif btnp("down") then dy = 1
    elseif btnp("left") then dx = -1
    elseif btnp("right") then dx = 1
    end

    if dx ~= 0 or dy ~= 0 then
      local nx = rpgPX + dx
      local ny = rpgPY + dy
      if not rpgIsWall(nx, ny) then
        rpgMoveFromX = rpgPX
        rpgMoveFromY = rpgPY
        rpgTargetX = nx
        rpgTargetY = ny
        rpgMoving = true
        rpgMoveTimer = 0
        note(0, "G5", 0.02)
      else
        note(0, "C3", 0.03)
      end
    end

    -- Check proximity to NPCs
    rpgNearNPC = false
    each("npc", function(e)
      local dist = abs(e.tileX - rpgPX) + abs(e.tileY - rpgPY)
      if dist <= 1 then
        rpgNearNPC = true
        if btnp("a") then
          rpgDialogActive = true
          rpgDialogText = rpgNPCList[e.npcIndex].msg
          note(0, "E5", 0.05)
        end
      end
    end)
  end

  -- Smooth camera follow
  local playerPixelX = rpgPX * SS
  local playerPixelY = rpgPY * SS
  if rpgMoving then
    local t = rpgMoveTimer / rpgMoveFrames
    playerPixelX = rpgMoveFromX * SS + (rpgTargetX - rpgMoveFromX) * SS * t
    playerPixelY = rpgMoveFromY * SS + (rpgTargetY - rpgMoveFromY) * SS * t
  end

  local targetCamX = playerPixelX - W / 2 + 8
  local targetCamY = playerPixelY - H / 2 + 8
  -- Clamp camera
  local maxCamX = RPG_MAP_W * SS - W
  local maxCamY = RPG_MAP_H * SS - H
  if targetCamX < 0 then targetCamX = 0 end
  if targetCamY < 0 then targetCamY = 0 end
  if targetCamX > maxCamX then targetCamX = maxCamX end
  if targetCamY > maxCamY then targetCamY = maxCamY end
  -- Smooth lerp
  rpgCamX = rpgCamX + (targetCamX - rpgCamX) * 0.15
  rpgCamY = rpgCamY + (targetCamY - rpgCamY) * 0.15
  cam(flr(rpgCamX), flr(rpgCamY))

  -- Update NPC z-order based on tileY
  each("npc", function(e)
    e.z = e.tileY
  end)
end

local function rpgDraw()
  cls(0)

  -- Draw tilemap (the full visible area)
  map(0, 0, RPG_MAP_W, RPG_MAP_H, 0, 0)

  -- Collect drawables for z-order sorting
  local drawList = {}

  -- Player pixel position (with smooth interpolation)
  local ppx = rpgPX * SS
  local ppy = rpgPY * SS
  if rpgMoving then
    local t = rpgMoveTimer / rpgMoveFrames
    ppx = rpgMoveFromX * SS + (rpgTargetX - rpgMoveFromX) * SS * t
    ppy = rpgMoveFromY * SS + (rpgTargetY - rpgMoveFromY) * SS * t
  end

  -- Add player to draw list
  drawList[#drawList + 1] = { y = ppy, kind = "player", px = ppx, py = ppy }

  -- Add NPCs to draw list
  each("npc", function(e)
    drawList[#drawList + 1] = { y = e.tileY * SS, kind = "npc", px = e.tileX * SS, py = e.tileY * SS }
  end)

  -- Sort by y (z-order: lower y drawn first, higher y drawn on top)
  table.sort(drawList, function(a, b) return a.y < b.y end)

  -- Draw in z-order
  for i = 1, #drawList do
    local d = drawList[i]
    if d.kind == "player" then
      -- Player shadow
      circf(flr(d.px) + 8, flr(d.py) + 14, 5, 1)
      sprT(rpgShipId, flr(d.px), flr(d.py))
    elseif d.kind == "npc" then
      -- NPC shadow
      circf(flr(d.px) + 8, flr(d.py) + 14, 5, 1)
      sprT(rpgNpcSprId, flr(d.px), flr(d.py))
      -- Exclamation mark above NPC if player is nearby
      local dist = abs(flr(d.px / SS) - rpgPX) + abs(flr(d.py / SS) - rpgPY)
      if dist <= 2 then
        if flr(rpgFrame / 10) % 2 == 0 then
          text("!", flr(d.px) + 6, flr(d.py) - 8, 3)
        end
      end
    end
  end

  -- HUD (drawn in screen space, text is not affected by cam)
  text("MINI RPG", 4, 4, 3)
  text("POS:" .. rpgPX .. "," .. rpgPY, 4, 14, 2)
  text("WPN:" .. RPG_WEAPONS[rpgWeaponIdx], 4, 24, 3)

  if rpgNearNPC and not rpgDialogActive then
    if flr(rpgFrame / 15) % 2 == 0 then
      text("PRESS A TO TALK", W / 2 - 40, H - 28, 3)
    end
  end

  text("[START] MENU", 4, H - 10, 1)

  -- Dialog box
  if rpgDialogActive then
    rectf(20, H - 70, W - 40, 50, 0)
    rect(20, H - 70, W - 40, 50, 3)
    rect(21, H - 69, W - 42, 48, 2)
    -- Split text by newline
    local lineY = 0
    for dline in rpgDialogText:gmatch("[^\n]+") do
      text(dline, 30, H - 62 + lineY, 3)
      lineY = lineY + 12
    end
    text("[A] CLOSE", W - 90, H - 26, 1)
  end

  drawInputMonitor()
end

---------------------------------------------------------------
-- MENU HELPERS
---------------------------------------------------------------
local function enterMode(mode)
  currentMode = mode
  killAll("bullet")
  killAll("enemy")
  killAll("particle")
  killAll("player")
  killAll("npc")
  bgm_stop()
  cam_reset()

  if mode == MODE_SHOOTER then
    shooterInit()
  elseif mode == MODE_CAMERA then
    cameraInit()
  elseif mode == MODE_SPRITES then
    spritesInit()
  elseif mode == MODE_INPUT then
    inputInit()
  elseif mode == MODE_SOUND then
    soundInit()
  elseif mode == MODE_TILEMAP then
    tilemapInit()
  elseif mode == MODE_RPG then
    rpgInit()
  end
end

---------------------------------------------------------------
-- TITLE SCENE (menu selection screen)
---------------------------------------------------------------
function title_init()
  titleBlink = 0
  menuCursor = 0
  currentMode = MODE_MENU
  initStars()
end

function title_update()
  titleBlink = titleBlink + 1
  updateStars()
  if btnp("a") or btnp("start") then
    go("play")
  end
end

function title_draw()
  cls(0)
  drawStars()

  text("ENGINE TEST SUITE", 85, 25, 3)

  -- Animated ship with hitbox
  local shipId = sprite_id("ship")
  local demoY = 50 + flr(math.sin(titleBlink * 0.06) * 4)
  sprT(shipId, 152, demoY)
  dbg(152, demoY, 16, 16)

  -- Rotating enemies with hitboxes
  local ebId = sprite_id("enemy_b")
  sprRot(ebId, 90, 60, titleBlink * 0.08)
  sprRot(ebId, 230, 60, -titleBlink * 0.08)
  dbgC(90, 60, 7)
  dbgC(230, 60, 7)

  -- Demo fill shapes (visible with key 3)
  local bx = 40 + flr(math.sin(titleBlink * 0.04) * 20)
  rectf(bx, 130, 30, 12, 1)
  circf(280 - flr(math.sin(titleBlink * 0.05) * 20), 136, 6, 2)

  -- Bullet with hitbox
  local bulId = sprite_id("bullet")
  local bulY = 90 + flr(math.sin(titleBlink * 0.1) * 30)
  sprT(bulId, 160, bulY)
  dbgC(168, bulY + 4, 3)

  if flr(titleBlink / 20) % 2 == 0 then
    text("PRESS START", 115, 180, 3)
  end

  text("1:HITBOX/2:SPRITE/3:FILL", 60, 200, 1)
  text("7 TEST MODES INSIDE", 85, 212, 1)
  text("SHOOTER CAM SPRITE INPUT SFX MAP RPG", 10, 224, 1)

  drawInputMonitor()
end

---------------------------------------------------------------
-- PLAY SCENE (hosts menu + all test modes)
---------------------------------------------------------------
function play_init()
  currentMode = MODE_MENU
  menuCursor = 0
  cam_reset()
end

function play_update()
  if currentMode == MODE_MENU then
    -- Menu navigation
    if btnp("up") then
      menuCursor = menuCursor - 1
      if menuCursor < 0 then menuCursor = #menuItems - 1 end
      note(0, "G5", 0.03)
    end
    if btnp("down") then
      menuCursor = menuCursor + 1
      if menuCursor >= #menuItems then menuCursor = 0 end
      note(0, "G5", 0.03)
    end
    if btnp("a") or btnp("start") then
      enterMode(menuCursor + 1)
      note(0, "C5", 0.05)
      return
    end
  else
    -- Start returns to menu from any test mode
    if btnp("start") then
      enterMode(MODE_MENU)
      currentMode = MODE_MENU
      return
    end

    if currentMode == MODE_SHOOTER then
      shooterUpdate()
    elseif currentMode == MODE_CAMERA then
      cameraUpdate()
    elseif currentMode == MODE_SPRITES then
      spritesUpdate()
    elseif currentMode == MODE_INPUT then
      inputUpdate()
    elseif currentMode == MODE_SOUND then
      soundUpdate()
    elseif currentMode == MODE_TILEMAP then
      tilemapUpdate()
    elseif currentMode == MODE_RPG then
      rpgUpdate()
    end
  end
end

function play_draw()
  if currentMode == MODE_MENU then
    cls(0)

    text("SELECT TEST", 115, 20, 3)
    line(100, 32, 220, 32, 2)

    local menuStartY = 50
    local menuSpacing = 24
    local descriptions = {
      "Vertical shooter - full game test",
      "Camera follow + shake on large map",
      "Display all sprites + sprRot demo",
      "Full 8-button visual input monitor",
      "Play notes + toggle BGM",
      "20x15 tile grid - mget/mset/map test",
      "Dungeon RPG - cam+ECS+tween+z-order",
    }

    for i = 1, #menuItems do
      local y = menuStartY + (i - 1) * menuSpacing
      local selected = (menuCursor == i - 1)
      local col = selected and 3 or 1

      if selected then
        -- Highlight bar
        rectf(30, y - 2, 260, 18, 1)
        -- Cursor arrow
        text(">", 34, y, 3)
      end

      text(tostring(i) .. ". " .. menuItems[i], 48, y, col)
      text(descriptions[i], 56, y + 9, selected and 2 or 1)
    end

    -- Footer
    line(30, menuStartY + #menuItems * menuSpacing + 4, 290, menuStartY + #menuItems * menuSpacing + 4, 1)
    text("UP/DOWN: SELECT   A/START: ENTER", 40, menuStartY + #menuItems * menuSpacing + 12, 2)

    drawInputMonitor()
  elseif currentMode == MODE_SHOOTER then
    shooterDraw()
  elseif currentMode == MODE_CAMERA then
    cameraDraw()
  elseif currentMode == MODE_SPRITES then
    spritesDraw()
  elseif currentMode == MODE_INPUT then
    inputDraw()
  elseif currentMode == MODE_SOUND then
    soundDraw()
  elseif currentMode == MODE_TILEMAP then
    tilemapDraw()
  elseif currentMode == MODE_RPG then
    rpgDraw()
  end
end

---------------------------------------------------------------
-- GAMEOVER SCENE (fallback, not used by menu system)
---------------------------------------------------------------
function gameover_init()
  bgm_stop()
end

function gameover_update()
  if btnp("a") or btnp("start") then
    go("title")
  end
end

function gameover_draw()
  cls(0)
  text("GAME OVER", 120, 80, 3)
  if flr(frame() / 20) % 2 == 0 then
    text("PRESS A TO CONTINUE", 85, 140, 3)
  end
  drawInputMonitor()
end
