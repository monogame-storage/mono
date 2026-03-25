-- Engine Test Suite: Menu-based tests for Mono Engine v2
-- Tests: shooter, camera, sprites, input, sound

local W: number = 320
local H: number = 240
local SS: number = 16

---------------------------------------------------------------
-- SPRITE HELPER: parse visual 16x16 sprite and register
---------------------------------------------------------------
local _sprNames = {}
local _sprNext = 1

local function defVisual(name: string, art: string)
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
sprite_id = function(name: string): number
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
......33........
.....3333.......
.....3333.......
......33........
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

---------------------------------------------------------------
-- SHARED STATE
---------------------------------------------------------------
local MODE_MENU: number = 0
local MODE_SHOOTER: number = 1
local MODE_CAMERA: number = 2
local MODE_SPRITES: number = 3
local MODE_INPUT: number = 4
local MODE_SOUND: number = 5

local currentMode: number = MODE_MENU
local menuCursor: number = 0
local menuItems = { "SHOOTER", "CAMERA", "SPRITES", "INPUT", "SOUND" }
local titleBlink: number = 0

---------------------------------------------------------------
-- INPUT MONITOR (drawn on every screen)
---------------------------------------------------------------
function drawInputMonitor()
  local y: number = 0
  local x: number = 220
  local ul: number = btn("up") and 3 or 1
  local dl: number = btn("down") and 3 or 1
  local ll: number = btn("left") and 3 or 1
  local rl: number = btn("right") and 3 or 1
  text("U", x + 10, y, ul)
  text("L", x, y + 8, ll)
  text("R", x + 20, y + 8, rl)
  text("D", x + 10, y + 16, dl)
  local al: number = btn("a") and 3 or 1
  local bl: number = btn("b") and 3 or 1
  local sl: number = btn("start") and 3 or 1
  local sel: number = btn("select") and 3 or 1
  text("A", x + 50, y + 4, al)
  text("B", x + 60, y + 4, bl)
  text("ST", x + 72, y, sl)
  text("SE", x + 72, y + 10, sel)
end

---------------------------------------------------------------
-- TILEMAP SETUP (scrolling starfield for shooter)
---------------------------------------------------------------
local TILE_COLS: number = 20
local TILE_ROWS: number = 30

local function setupTilemap()
  local starId: number = sprite_id("star")
  local star2Id: number = sprite_id("star2")
  for ty = 0, TILE_ROWS - 1 do
    for tx = 0, TILE_COLS - 1 do
      local r: number = rnd(100)
      if r < 6 then
        mset(tx, ty, starId)
      elseif r < 9 then
        mset(tx, ty, star2Id)
      else
        mset(tx, ty, 0)
      end
    end
  end
end

local function drawStarfield(offset: number)
  local sy: number = offset % (TILE_ROWS * SS)
  local tileOffY: number = flr(sy / SS)
  local pixOffY: number = flr(sy) % SS
  for ty = 0, 16 do
    for tx = 0, TILE_COLS - 1 do
      local tile: number = mget(tx, (ty + tileOffY) % TILE_ROWS)
      if tile > 0 then
        sprT(tile, tx * SS, ty * SS + pixOffY)
      end
    end
  end
end

---------------------------------------------------------------
-- SHOOTER TEST STATE
---------------------------------------------------------------
local SHIP_SPEED: number = 3
local BULLET_SPEED: number = -5
local ENEMY_SPEED: number = 1.2
local SPAWN_RATE: number = 50
local MAX_BULLETS: number = 6

local playerX: number = 0
local playerY: number = 0
local shootCooldown: number = 0
local spawnTimer: number = 0
local invincible: number = 0
local scrollY: number = 0
local shooterScore: number = 0
local shooterLives: number = 3
local shooterLevel: number = 1

local function spawnExplosion(x: number, y: number)
  local partId: number = sprite_id("particle")
  local count: number = flr(rnd(4)) + 5
  for i = 1, count do
    local angle: number = rnd(6.28)
    local speed: number = rnd(2.5) + 0.5
    spawn({
      group = "particle",
      pos = { x = x, y = y },
      vel = { x = speed * math.cos(angle), y = speed * math.sin(angle) - 1.5 },
      gravity = 0.1,
      lifetime = flr(rnd(10)) + 15,
      sprite = partId,
      offscreen = true,
    })
  end
  note(1, "C5", 0.06)
end

local function shooterInit()
  shooterScore = 0
  shooterLives = 3
  shooterLevel = 1
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
  setupTilemap()

  onCollide("bullet", "enemy", function(bullet, enemy)
    kill(bullet)
    kill(enemy)
    spawnExplosion(enemy.pos.x + 7, enemy.pos.y + 5)
    shooterScore = shooterScore + 100
    note(0, "E5", 0.08)
  end)

  onCollide("player", "enemy", function(player, enemy)
    if invincible > 0 then return end
    kill(enemy)
    spawnExplosion(playerX + 8, playerY + 5)
    shooterLives = shooterLives - 1
    invincible = 90
    note(0, "C3", 0.2)
    note(1, "E3", 0.15)
    if shooterLives <= 0 then
      shooterLives = 0
    end
  end)

  bgm({
    "E4 . G4 . A4 . G4 . E4 . D4 . E4 . G4 . A4 . B4 . A4 . G4 . E4 . D4 . C4 . D4 .",
    "C3 - - - E3 - - - A2 - - - E3 - - - C3 - - - G2 - - - A2 - - - E3 - - -",
  }, 180, true)
end

local function shooterUpdate()
  -- Return to menu
  if btnp("b") then
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

  scrollY = scrollY + 0.5

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

  if shootCooldown > 0 then
    shootCooldown = shootCooldown - 1
  end
  if btn("a") and shootCooldown <= 0 and ecount("bullet") < MAX_BULLETS then
    local bulletId: number = sprite_id("bullet")
    spawn({
      group = "bullet",
      pos = { x = playerX + 5, y = playerY - 4 },
      vel = { x = 0, y = BULLET_SPEED },
      sprite = bulletId,
      hitbox = { r = 3, ox = 3, oy = 2 },
      offscreen = true,
    })
    shootCooldown = 6
    note(0, "A5", 0.03)
  end

  spawnTimer = spawnTimer + 1
  local rate: number = SPAWN_RATE - shooterLevel * 4
  if rate < 15 then rate = 15 end

  if spawnTimer >= rate then
    spawnTimer = 0
    local ex: number = flr(rnd(W - SS * 2)) + SS
    local etype: number = flr(rnd(3))

    if etype == 0 then
      local ea1: number = sprite_id("enemy_a1")
      local ea2: number = sprite_id("enemy_a2")
      spawn({
        group = "enemy",
        pos = { x = ex, y = -SS },
        vel = { x = rnd(2) - 1, y = ENEMY_SPEED + rnd(0.5) },
        sprite = ea1,
        anim = { frames = { ea1, ea2 }, speed = 10, timer = 0, index = 0 },
        hitbox = { w = 14, h = 10, ox = 1, oy = 1 },
        offscreen = true,
        isRotating = false,
      })
    elseif etype == 1 then
      local ebId: number = sprite_id("enemy_b")
      spawn({
        group = "enemy",
        pos = { x = ex, y = -SS },
        vel = { x = rnd(1.6) - 0.8, y = ENEMY_SPEED + rnd(0.3) },
        hitbox = { r = 6, ox = 8, oy = 7 },
        offscreen = true,
        isRotating = true,
        rotAngle = rnd(6.28),
        rotSprite = ebId,
      })
    else
      local ea1: number = sprite_id("enemy_a1")
      spawn({
        group = "enemy",
        pos = { x = ex, y = -SS },
        vel = { x = rnd(2.4) - 1.2, y = ENEMY_SPEED + 0.8 },
        sprite = ea1,
        hitbox = { w = 14, h = 10, ox = 1, oy = 1 },
        offscreen = true,
        isRotating = false,
      })
    end
  end

  each("enemy", function(e)
    if e.isRotating then
      e.rotAngle = e.rotAngle + 0.1
    end
  end)

  local newLevel: number = flr(shooterScore / 1000) + 1
  if newLevel > shooterLevel then
    shooterLevel = newLevel
  end

  killAll("player")
  if invincible <= 0 or flr(invincible / 3) % 2 == 0 then
    spawn({
      group = "player",
      pos = { x = playerX, y = playerY },
      hitbox = { w = 12, h = 14, ox = 2, oy = 1 },
    })
  end
end

local function shooterDraw()
  cls(0)

  if shooterLives <= 0 then
    -- Game over sub-screen
    drawStarfield(scrollY)
    text("GAME OVER", 120, 80, 3)
    text("SCORE:" .. shooterScore, 120, 110, 2)
    if flr(frame() / 20) % 2 == 0 then
      text("PRESS A TO RETRY", 95, 150, 3)
    end
    text("[B] BACK TO MENU", 95, 180, 1)
    drawInputMonitor()
    return
  end

  drawStarfield(scrollY)

  local shipId: number = sprite_id("ship")
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

  for i = 1, shooterLives do
    sprT(shipId, W - 20 * i, 1)
  end

  text("[B] MENU", 4, H - 10, 1)
  drawInputMonitor()
end

---------------------------------------------------------------
-- CAMERA TEST STATE
---------------------------------------------------------------
local CAM_MAP_W: number = 640
local CAM_MAP_H: number = 480
local camPX: number = 320
local camPY: number = 240
local camSpeed: number = 2

local function cameraInit()
  camPX = CAM_MAP_W / 2
  camPY = CAM_MAP_H / 2
  cam_reset()
end

local function cameraUpdate()
  if btnp("b") then
    cam_reset()
    currentMode = MODE_MENU
    return
  end

  if btn("left") then camPX = camPX - camSpeed end
  if btn("right") then camPX = camPX + camSpeed end
  if btn("up") then camPY = camPY - camSpeed end
  if btn("down") then camPY = camPY + camSpeed end

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
  local cx: number = camPX - W / 2
  local cy: number = camPY - H / 2
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
  local mcx: number = CAM_MAP_W / 2
  local mcy: number = CAM_MAP_H / 2
  line(mcx - 20, mcy, mcx + 20, mcy, 2)
  line(mcx, mcy - 20, mcx, mcy + 20, 2)

  -- Draw corner labels (world-space coordinates rendered via spr-affected draw)
  rectf(4, 4, 40, 12, 0)
  rectf(CAM_MAP_W - 60, 4, 60, 12, 0)
  rectf(4, CAM_MAP_H - 16, 40, 12, 0)
  rectf(CAM_MAP_W - 60, CAM_MAP_H - 16, 60, 12, 0)

  -- Draw player (ship sprite)
  local shipId: number = sprite_id("ship")
  sprT(shipId, flr(camPX) - 8, flr(camPY) - 8)

  -- Player position circle indicator
  circ(flr(camPX), flr(camPY), 12, 3)

  -- HUD (text is NOT affected by cam, so it draws in screen space)
  text("CAMERA TEST", 4, 4, 3)
  text("POS:" .. flr(camPX) .. "," .. flr(camPY), 4, 14, 2)
  text("MAP:" .. CAM_MAP_W .. "x" .. CAM_MAP_H, 4, 24, 1)
  text("[A] SHAKE  [B] MENU", 4, H - 10, 1)
  text("ARROWS: MOVE", 4, H - 20, 1)
  drawInputMonitor()
end

---------------------------------------------------------------
-- SPRITES TEST STATE
---------------------------------------------------------------
local sprTestAngle: number = 0

local function spritesInit()
  sprTestAngle = 0
end

local function spritesUpdate()
  if btnp("b") then
    currentMode = MODE_MENU
    return
  end
  sprTestAngle = sprTestAngle + 0.05
end

local function spritesDraw()
  cls(0)
  text("SPRITE GALLERY", 100, 4, 3)

  local names = { "ship", "bullet", "enemy_a1", "enemy_a2", "enemy_b", "particle", "star", "star2" }
  local cols: number = 4
  local startX: number = 30
  local startY: number = 30
  local cellW: number = 70
  local cellH: number = 50

  for idx = 1, #names do
    local name: string = names[idx]
    local sid: number = sprite_id(name)
    local col: number = (idx - 1) % cols
    local row: number = flr((idx - 1) / cols)
    local cx: number = startX + col * cellW
    local cy: number = startY + row * cellH

    -- Background cell
    rect(cx - 2, cy - 2, cellW - 4, cellH - 4, 1)

    -- Sprite name
    text(name, cx, cy + cellH - 16, 2)

    -- Draw normal sprite
    sprT(sid, cx + 8, cy + 4)
  end

  -- Rotating demo section
  local demoY: number = startY + 2 * cellH + 20
  text("sprT (normal)", 30, demoY, 2)
  local demoSpr: number = sprite_id("enemy_b")
  sprT(demoSpr, 140, demoY - 4)

  text("sprRot (rotating)", 30, demoY + 30, 2)
  sprRot(demoSpr, 156, demoY + 34, sprTestAngle)

  text("Angle: " .. tostring(flr(sprTestAngle * 100) / 100), 190, demoY + 30, 1)

  text("[B] MENU", 4, H - 10, 1)
  drawInputMonitor()
end

---------------------------------------------------------------
-- INPUT TEST STATE
---------------------------------------------------------------
local function inputInit()
end

local function inputUpdate()
  if btnp("b") then
    currentMode = MODE_MENU
    return
  end
end

local function inputDraw()
  cls(0)
  text("INPUT MONITOR", 105, 8, 3)

  -- D-pad (large circles)
  local dpadX: number = 80
  local dpadY: number = 120
  local btnR: number = 16

  -- Up
  local upOn: boolean = btn("up")
  circ(dpadX, dpadY - 40, btnR, upOn and 3 or 1)
  if upOn then circf(dpadX, dpadY - 40, btnR - 2, 3) end
  text("UP", dpadX - 6, dpadY - 44, upOn and 0 or 2)

  -- Down
  local downOn: boolean = btn("down")
  circ(dpadX, dpadY + 40, btnR, downOn and 3 or 1)
  if downOn then circf(dpadX, dpadY + 40, btnR - 2, 3) end
  text("DN", dpadX - 6, dpadY + 36, downOn and 0 or 2)

  -- Left
  local leftOn: boolean = btn("left")
  circ(dpadX - 40, dpadY, btnR, leftOn and 3 or 1)
  if leftOn then circf(dpadX - 40, dpadY, btnR - 2, 3) end
  text("LT", dpadX - 46, dpadY - 4, leftOn and 0 or 2)

  -- Right
  local rightOn: boolean = btn("right")
  circ(dpadX + 40, dpadY, btnR, rightOn and 3 or 1)
  if rightOn then circf(dpadX + 40, dpadY, btnR - 2, 3) end
  text("RT", dpadX + 34, dpadY - 4, rightOn and 0 or 2)

  -- Action buttons
  local actX: number = 240
  local actY: number = 100

  -- A button
  local aOn: boolean = btn("a")
  circ(actX, actY, btnR, aOn and 3 or 1)
  if aOn then circf(actX, actY, btnR - 2, 3) end
  text("A", actX - 3, actY - 4, aOn and 0 or 2)

  -- B button
  local bOn: boolean = btn("b")
  circ(actX - 36, actY + 10, btnR, bOn and 3 or 1)
  if bOn then circf(actX - 36, actY + 10, btnR - 2, 3) end
  text("B", actX - 39, actY + 6, bOn and 0 or 2)

  -- Start
  local stOn: boolean = btn("start")
  circ(actX - 10, actY + 50, 12, stOn and 3 or 1)
  if stOn then circf(actX - 10, actY + 50, 10, 3) end
  text("ST", actX - 17, actY + 46, stOn and 0 or 2)

  -- Select
  local seOn: boolean = btn("select")
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
local soundBgmOn: boolean = false
local soundLastNote: string = ""

local function soundInit()
  soundBgmOn = false
  soundLastNote = ""
end

local function soundUpdate()
  if btnp("b") then
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
  local cx: number = W / 2
  local cy: number = 80

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
  local bgmLabel: string = soundBgmOn and "BGM: ON" or "BGM: OFF"
  local bgmColor: number = soundBgmOn and 3 or 1
  text(bgmLabel, 130, 185, bgmColor)
  text("[A] TOGGLE BGM", 105, 200, 2)

  text("[B] MENU", 4, H - 10, 1)
  drawInputMonitor()
end

---------------------------------------------------------------
-- MENU HELPERS
---------------------------------------------------------------
local function enterMode(mode: number)
  currentMode = mode
  killAll("bullet")
  killAll("enemy")
  killAll("particle")
  killAll("player")
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
  end
end

---------------------------------------------------------------
-- TITLE SCENE (menu selection screen)
---------------------------------------------------------------
function title_init()
  titleBlink = 0
  menuCursor = 0
  currentMode = MODE_MENU
  setupTilemap()
end

function title_update()
  titleBlink = titleBlink + 1
  if btnp("a") or btnp("start") then
    go("play")
  end
end

function title_draw()
  cls(0)
  drawStarfield(titleBlink * 0.5)

  text("ENGINE TEST SUITE", 85, 25, 3)

  -- Animated ship
  local shipId: number = sprite_id("ship")
  local demoY: number = 50 + flr(math.sin(titleBlink * 0.06) * 4)
  sprT(shipId, 152, demoY)

  -- Rotating enemies
  local ebId: number = sprite_id("enemy_b")
  sprRot(ebId, 90, 60, titleBlink * 0.08)
  sprRot(ebId, 230, 60, -titleBlink * 0.08)

  if flr(titleBlink / 20) % 2 == 0 then
    text("PRESS START", 115, 180, 3)
  end

  text("5 TEST MODES INSIDE", 85, 210, 1)
  text("SHOOTER CAMERA SPRITES INPUT SFX", 25, 222, 1)

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
    if btnp("a") then
      enterMode(menuCursor + 1)
      note(0, "C5", 0.05)
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
    end
  end
end

function play_draw()
  if currentMode == MODE_MENU then
    cls(0)

    text("SELECT TEST", 115, 20, 3)
    line(100, 32, 220, 32, 2)

    local menuStartY: number = 50
    local menuSpacing: number = 24
    local descriptions = {
      "Vertical shooter - full game test",
      "Camera follow + shake on large map",
      "Display all sprites + sprRot demo",
      "Full 8-button visual input monitor",
      "Play notes + toggle BGM",
    }

    for i = 1, #menuItems do
      local y: number = menuStartY + (i - 1) * menuSpacing
      local selected: boolean = (menuCursor == i - 1)
      local col: number = selected and 3 or 1

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
