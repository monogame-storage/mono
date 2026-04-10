-- Starfighter Demo
-- Covers: loadImage, imageWidth, imageHeight, spr, sspr, drawImage,
--         drawImageRegion, tone, noise
--
-- Controls:
--   UP/DOWN : move ship vertically
--   A       : fire laser

local scr = screen()

local sprites, bg
local sprites_w, sprites_h
local ship_y
local bullets, enemies, explosions

function _init()
  mode(4)
end

function _start()
  sprites = loadImage("sprites.png")
  bg = loadImage("bg.png")
  sprites_w = imageWidth(sprites)
  sprites_h = imageHeight(sprites)
  ship_y = SCREEN_H / 2 - 8
  bullets = {}
  enemies = {}
  explosions = {}
end

local function spawn_enemy()
  enemies[#enemies + 1] = {
    x = SCREEN_W + 4,
    y = math.random(0, SCREEN_H - 16),
    t = 0,
  }
end

function _update()
  if btn("up")   then ship_y = ship_y - 2 end
  if btn("down") then ship_y = ship_y + 2 end
  if ship_y < 0 then ship_y = 0 end
  if ship_y > SCREEN_H - 16 then ship_y = SCREEN_H - 16 end

  -- Attract mode: auto-fire every 20 frames so scan mode exercises tone/noise
  if btnp("a") or frame() % 20 == 10 then
    bullets[#bullets + 1] = { x = 16, y = ship_y + 8 }
    tone(0, 1500, 3000, 0.08)
  end

  -- Move bullets
  for i = #bullets, 1, -1 do
    bullets[i].x = bullets[i].x + 4
    if bullets[i].x > SCREEN_W then table.remove(bullets, i) end
  end

  -- Spawn enemies periodically
  if frame() % 40 == 0 then spawn_enemy() end

  -- Move enemies
  for i = #enemies, 1, -1 do
    local e = enemies[i]
    e.x = e.x - 1
    e.t = e.t + 1
    if e.x < -16 then table.remove(enemies, i) end
  end

  -- Bullet vs enemy collisions
  for i = #enemies, 1, -1 do
    local e = enemies[i]
    for j = #bullets, 1, -1 do
      local b = bullets[j]
      if b.x > e.x and b.x < e.x + 16
         and b.y > e.y and b.y < e.y + 16 then
        explosions[#explosions + 1] = { x = e.x, y = e.y, t = 0 }
        table.remove(enemies, i)
        table.remove(bullets, j)
        noise(1, 0.15, "low", 500)
        break
      end
    end
  end

  -- Age explosions
  for i = #explosions, 1, -1 do
    explosions[i].t = explosions[i].t + 1
    if explosions[i].t > 10 then table.remove(explosions, i) end
  end
end

function _draw()
  -- Background: full image draw (covers drawImage)
  drawImage(scr, bg, 0, 0)

  -- Ship: sub-region blit from sheet (covers sspr)
  sspr(scr, sprites, 0, 0, 16, 16, 0, math.floor(ship_y))

  -- Enemies: alternate between spr and drawImageRegion for API coverage
  for i, e in ipairs(enemies) do
    if i % 2 == 0 then
      drawImageRegion(scr, sprites, 16, 0, 16, 16, math.floor(e.x), math.floor(e.y))
    else
      -- spr draws the whole sprite sheet; we use it for visual variety
      -- (overdraws ship area but it's a demo, not production)
      spr(scr, sprites, math.floor(e.x) - 16, math.floor(e.y))
    end
  end

  -- Bullets
  for _, b in ipairs(bullets) do
    rectf(scr, math.floor(b.x), math.floor(b.y), 4, 2, 15)
  end

  -- Explosions (expanding circles)
  for _, ex in ipairs(explosions) do
    circ(scr, ex.x + 8, ex.y + 8, ex.t, 15 - ex.t)
  end

  -- HUD
  cam(0, 0)
  text(scr, "STARFIGHTER", 2, 2, 15)
  text(scr, "SPRITE " .. sprites_w .. "X" .. sprites_h, 2, SCREEN_H - 10, 8)
end
