-- Engine Test: Vertical Shooter for Mono Engine v2
-- Tests: sprRot, ECS vel/gravity/lifetime/anim/offscreen,
--        game table sprites + state (S), BGM, tilemap, pause, debug overlays

local W: number = 320
local H: number = 240
local SS: number = 16

---------------------------------------------------------------
-- DECLARATIVE GAME TABLE (all sprites 16x16)
---------------------------------------------------------------
game = {
  sprites = {
    -- Player ship pointing up
    ship = [[
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
]],
    -- Bullet (centered small dot)
    bullet = [[
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
................
]],
    -- Enemy type A frame 1 (saucer)
    enemy_a1 = [[
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
]],
    -- Enemy type A frame 2 (pulsing)
    enemy_a2 = [[
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
]],
    -- Enemy type B (spinning diamond)
    enemy_b = [[
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
]],
    -- Particle (tiny dot, top-left corner)
    particle = [[
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
]],
    -- Star tile (sparse stars for tilemap)
    star = [[
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
]],
    -- Dense star tile
    star2 = [[
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
]],
  },
  state = {
    score = "u16",
    lives = "u8",
    level = "u8",
    hi = "u16",
  },
}

---------------------------------------------------------------
-- LOCALS
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
local titleBlink: number = 0

---------------------------------------------------------------
-- TILEMAP SETUP (scrolling starfield)
---------------------------------------------------------------
local TILE_COLS: number = 20  -- 320/16
local TILE_ROWS: number = 30  -- extra rows for seamless scroll

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

---------------------------------------------------------------
-- EXPLOSION PARTICLES (gravity + lifetime test)
---------------------------------------------------------------
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

---------------------------------------------------------------
-- DRAW SCROLLING STARS (shared helper)
---------------------------------------------------------------
local function drawStarfield(offset: number)
  local sy: number = offset % (TILE_ROWS * SS)
  local tileOffY: number = flr(sy / SS)
  local pixOffY: number = flr(sy) % SS

  for ty = 0, 16 do
    for tx = 0, TILE_COLS - 1 do
      local tile: number = mget(tx, (ty + tileOffY) % TILE_ROWS)
      if tile > 0 then
        sprT(tile, tx * SS, ty * SS - pixOffY)
      end
    end
  end
end

---------------------------------------------------------------
-- TITLE SCENE
---------------------------------------------------------------
function title_init()
  titleBlink = 0
  setupTilemap()
end

function title_update()
  titleBlink = titleBlink + 1
end

function title_draw()
  cls(0)

  -- Scrolling star background
  drawStarfield(titleBlink * 0.5)

  -- Title text
  text("ENGINE TEST", 110, 40, 3)
  text("VERTICAL SHOOTER", 95, 55, 2)

  -- Animated ship bobbing
  local shipId: number = sprite_id("ship")
  local demoY: number = 90 + flr(math.sin(titleBlink * 0.06) * 6)
  sprT(shipId, 152, demoY)

  -- Rotating enemies (sprRot demo)
  local ebId: number = sprite_id("enemy_b")
  sprRot(ebId, 90, 120, titleBlink * 0.08)
  sprRot(ebId, 230, 120, -titleBlink * 0.08)

  -- Animated enemy (2-frame cycle demo)
  local ea1: number = sprite_id("enemy_a1")
  local ea2: number = sprite_id("enemy_a2")
  local animSpr: number = ea1
  if flr(titleBlink / 10) % 2 == 1 then animSpr = ea2 end
  sprT(animSpr, 152, 135)

  -- Blink "PRESS START"
  if flr(titleBlink / 20) % 2 == 0 then
    text("PRESS START", 115, 180, 3)
  end

  -- Feature list
  text("TESTS: SPRROT ECS TILEMAP BGM", 35, 207, 1)
  text("S.STATE ANIM GRAVITY LIFETIME", 35, 217, 1)
  text("OFFSCREEN PAUSE DEBUG(1/2/3)", 38, 227, 1)
end

---------------------------------------------------------------
-- PLAY SCENE
---------------------------------------------------------------
function play_init()
  S.score = 0
  S.lives = 3
  S.level = 1
  playerX = W / 2 - SS / 2
  playerY = H - 30
  shootCooldown = 0
  spawnTimer = 0
  invincible = 60
  scrollY = 0

  setupTilemap()

  -- Collision: bullet vs enemy
  onCollide("bullet", "enemy", function(bullet, enemy)
    kill(bullet)
    kill(enemy)
    spawnExplosion(enemy.pos.x + 7, enemy.pos.y + 5)
    S.score = S.score + 100
    if S.score > S.hi then
      S.hi = S.score
    end
    note(0, "E5", 0.08)
  end)

  -- Collision: player vs enemy
  onCollide("player", "enemy", function(player, enemy)
    if invincible > 0 then return end
    kill(enemy)
    spawnExplosion(playerX + 8, playerY + 5)
    S.lives = S.lives - 1
    invincible = 90
    note(0, "C3", 0.2)
    note(1, "E3", 0.15)
    if S.lives <= 0 then
      go("gameover")
    end
  end)

  -- BGM: 2-channel loop (melody + bass)
  bgm({
    "E4 . G4 . A4 . G4 . E4 . D4 . E4 . G4 . A4 . B4 . A4 . G4 . E4 . D4 . C4 . D4 .",
    "C3 - - - E3 - - - A2 - - - E3 - - - C3 - - - G2 - - - A2 - - - E3 - - -",
  }, 180, true)
end

function play_update()
  scrollY = scrollY + 0.5

  -- Player movement
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

  -- Invincibility countdown
  if invincible > 0 then
    invincible = invincible - 1
  end

  -- Shooting (A button = z key)
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

  -- Enemy spawning
  spawnTimer = spawnTimer + 1
  local rate: number = SPAWN_RATE - S.level * 4
  if rate < 15 then rate = 15 end

  if spawnTimer >= rate then
    spawnTimer = 0
    local ex: number = flr(rnd(W - SS * 2)) + SS
    local etype: number = flr(rnd(3))

    if etype == 0 then
      -- Type A: animated saucer (2-frame ECS anim test)
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
      -- Type B: rotating spinner (sprRot test)
      -- No `sprite` field so ECS won't auto-draw; drawn manually with sprRot
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
      -- Type A: faster variant, no animation
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

  -- Update rotation angle for spinning enemies
  each("enemy", function(e)
    if e.isRotating then
      e.rotAngle = e.rotAngle + 0.1
    end
  end)

  -- Level up every 1000 points
  local newLevel: number = flr(S.score / 1000) + 1
  if newLevel > S.level then
    S.level = newLevel
  end

  -- Spawn player hitbox entity each frame for collision detection
  killAll("player")
  if invincible <= 0 or flr(invincible / 3) % 2 == 0 then
    spawn({
      group = "player",
      pos = { x = playerX, y = playerY },
      hitbox = { w = 12, h = 14, ox = 2, oy = 1 },
    })
  end
end

function play_draw()
  cls(0)

  -- Scrolling tilemap starfield
  drawStarfield(scrollY)

  -- Draw player ship (manual for invincibility blink effect)
  local shipId: number = sprite_id("ship")
  if invincible <= 0 or flr(invincible / 3) % 2 == 0 then
    sprT(shipId, flr(playerX), flr(playerY))
  end

  -- Draw rotating enemies manually (no sprite field, so ECS skips them)
  each("enemy", function(e)
    if e.isRotating and e.rotSprite then
      sprRot(e.rotSprite, flr(e.pos.x) + 8, flr(e.pos.y) + 7, e.rotAngle)
    end
  end)

  -- HUD
  text("SCORE:" .. S.score, 4, 4, 3)
  text("HI:" .. S.hi, 120, 4, 2)
  text("LV:" .. S.level, 220, 4, 2)

  -- Lives as small ships in top-right
  for i = 1, S.lives do
    sprT(shipId, W - 20 * i, 1)
  end
end

---------------------------------------------------------------
-- GAMEOVER SCENE
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

  -- Drifting background dots
  local t: number = frame()
  for i = 0, 40 do
    local sx: number = (i * 37 + t) % W
    local sy: number = (i * 53 + flr(t * 0.3)) % H
    local c: number = 1
    if i % 5 == 0 then c = 2 end
    pix(flr(sx), flr(sy), c)
  end

  text("GAME OVER", 120, 55, 3)

  text("FINAL SCORE", 110, 90, 2)
  text("" .. S.score, 145, 108, 3)

  if S.score >= S.hi and S.score > 0 then
    text("NEW HIGH SCORE!", 100, 130, 3)
  end

  text("HI:" .. S.hi, 135, 150, 2)

  -- Blink prompt
  if flr(frame() / 20) % 2 == 0 then
    text("PRESS A TO CONTINUE", 85, 182, 3)
  end

  -- Summary
  text("ENGINE FEATURES TESTED:", 70, 210, 1)
  text("SPRROT VEL GRAV LIFE ANIM OFF", 35, 220, 1)
  text("BGM TILE S.STATE PAUSE DEBUG", 40, 230, 1)
end
