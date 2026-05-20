-- Starfighter Demo
-- Covers: loadImage, imageWidth, imageHeight, sspr, drawImage,
--         drawImageRegion, tone, noise
--
-- Controls:
--   UP/DOWN : move ship vertically
--   A       : fire laser / confirm / restart
--   START   : begin from title

local scr = screen()

-- Resources
local sprites, bg

-- Game state machine
local state = "title"  -- "title" | "play" | "over"

-- Gameplay
local ship_y
local bullets, enemies, explosions, eshots
local score, lives, best, invuln

function _init()
  mode(4)
end

local function reset_play()
  ship_y   = SCREEN_H / 2 - 8
  bullets  = {}
  enemies  = {}
  explosions = {}
  eshots   = {}
  score    = 0
  lives    = 3
  invuln   = 0
end

function _start()
  sprites = loadImage("sprites.png")
  bg = loadImage("bg.png")
  best = data_load("starfighter_best") or 0
  reset_play()
  state = "title"
end

function _ready()
  -- Image dimensions are safe to query here once loadImage() resolves.
  -- (Not currently needed but available.)
end

local function spawn_enemy()
  enemies[#enemies + 1] = {
    x = SCREEN_W + 4,
    y = math.random(0, SCREEN_H - 16),
    t = 0,
  }
end

local function rect_overlap(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end

local function on_player_hit()
  if invuln > 0 then return end
  lives = lives - 1
  invuln = 30
  tone(0, 400, 80, 0.5)
  cam_shake(6)
  if lives <= 0 then
    if score > best then
      best = score
      data_save("starfighter_best", best)
    end
    tone(0, 800, 200, 0.8)
    state = "over"
  end
end

local function title_update()
  if btnr("start") or touch_end() then
    reset_play()
    state = "play"
  end
end

local function over_update()
  if btnr("a") or touch_end() then
    reset_play()
    state = "title"
  end
end

local function play_update()
  if invuln > 0 then invuln = invuln - 1 end

  if btn("up")   then ship_y = ship_y - 2 end
  if btn("down") then ship_y = ship_y + 2 end
  if ship_y < 0 then ship_y = 0 end
  if ship_y > SCREEN_H - 16 then ship_y = SCREEN_H - 16 end

  -- Auto-fire every 20 frames for attract / A for manual
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

  -- Move enemies (off-left costs a life)
  for i = #enemies, 1, -1 do
    local e = enemies[i]
    e.x = e.x - 1
    e.t = e.t + 1
    if e.x < -16 then
      table.remove(enemies, i)
      on_player_hit()
    end
  end

  -- Enemy fire: every 30 frames a random alive enemy fires a bullet leftward
  if frame() % 30 == 0 and #enemies > 0 then
    local e = enemies[math.random(1, #enemies)]
    eshots[#eshots + 1] = { x = e.x, y = e.y + 8, dx = -2 }
    noise(1, 0.04, "high", 1500)
  end

  -- Move enemy bullets
  for i = #eshots, 1, -1 do
    local s = eshots[i]
    s.x = s.x + s.dx
    if s.x < -4 then table.remove(eshots, i) end
  end

  -- Bullet vs enemy collisions
  for i = #enemies, 1, -1 do
    local e = enemies[i]
    local killed = false
    for j = #bullets, 1, -1 do
      local b = bullets[j]
      if b.x > e.x and b.x < e.x + 16
         and b.y > e.y and b.y < e.y + 16 then
        explosions[#explosions + 1] = { x = e.x, y = e.y, t = 0 }
        table.remove(enemies, i)
        table.remove(bullets, j)
        noise(1, 0.15, "low", 500)
        score = score + 10
        killed = true
        break
      end
    end
    if killed then
      -- enemy gone; skip player-collision check for this slot
    end
  end

  -- Enemy vs player ship collision (ship is a 16x16 box at x=0, y=ship_y)
  for i = #enemies, 1, -1 do
    local e = enemies[i]
    if rect_overlap(0, ship_y, 16, 16, e.x, e.y, 16, 16) then
      explosions[#explosions + 1] = { x = e.x, y = e.y, t = 0 }
      table.remove(enemies, i)
      on_player_hit()
      if state ~= "play" then return end
    end
  end

  -- Enemy bullets vs player ship
  for i = #eshots, 1, -1 do
    local s = eshots[i]
    if rect_overlap(0, ship_y, 16, 16, s.x, s.y - 1, 4, 3) then
      table.remove(eshots, i)
      on_player_hit()
      if state ~= "play" then return end
    end
  end

  -- Age explosions
  for i = #explosions, 1, -1 do
    explosions[i].t = explosions[i].t + 1
    if explosions[i].t > 10 then table.remove(explosions, i) end
  end
end

function _update()
  if state == "title" then
    title_update()
  elseif state == "over" then
    over_update()
  else
    play_update()
  end
end

local function draw_bg()
  -- Scrolling background with wraparound
  local off = -math.floor(frame() / 2) % SCREEN_W
  drawImage(scr, bg, off, 0)
  drawImage(scr, bg, off + SCREEN_W, 0)
  -- Also handle the negative wraparound (when off > 0)
  drawImage(scr, bg, off - SCREEN_W, 0)
end

local function draw_play_world()
  draw_bg()

  -- Ship: sub-region blit from sheet (covers sspr). Blink while invulnerable.
  if invuln <= 0 or (math.floor(invuln / 3) % 2 == 0) then
    sspr(scr, sprites, 0, 0, 16, 16, 0, math.floor(ship_y))
  end

  -- Enemies — always use drawImageRegion
  for _, e in ipairs(enemies) do
    drawImageRegion(scr, sprites, 16, 0, 16, 16, math.floor(e.x), math.floor(e.y))
  end

  -- Player bullets
  for _, b in ipairs(bullets) do
    rectf(scr, math.floor(b.x), math.floor(b.y), 4, 2, 15)
  end

  -- Enemy bullets (small red-ish pellet)
  for _, s in ipairs(eshots) do
    rectf(scr, math.floor(s.x), math.floor(s.y) - 1, 3, 2, 11)
  end

  -- Explosions (expanding circles)
  for _, ex in ipairs(explosions) do
    circ(scr, ex.x + 8, ex.y + 8, ex.t, 15 - ex.t)
  end
end

local function draw_hud()
  cam(0, 0)
  -- Score top-left
  text(scr, tostring(score), 2, 2, 15)
  -- Life pips top-right (one filled rect per life)
  for i = 1, lives do
    local px = SCREEN_W - 2 - i * 6
    rectf(scr, px, 3, 4, 4, 12)
  end
end

local function title_draw()
  draw_bg()
  text(scr, "STARFIGHTER", 80, 36, 15, ALIGN_HCENTER)
  if math.floor(frame() / 15) % 2 == 0 then
    text(scr, "PRESS START", 80, 70, 14, ALIGN_HCENTER)
  end
  text(scr, "BEST: " .. best, 80, 96, 8, ALIGN_HCENTER)
end

local function over_draw()
  draw_play_world()
  draw_hud()
  -- Overlay panel
  rectf(scr, 30, 36, 100, 50, 0)
  rect(scr, 30, 36, 100, 50, 15)
  text(scr, "GAME OVER", 80, 44, 15, ALIGN_HCENTER)
  text(scr, "SCORE: " .. score, 80, 58, 12, ALIGN_HCENTER)
  text(scr, "BEST:  " .. best,  80, 70, 8, ALIGN_HCENTER)
  text(scr, "PRESS A", 80, 80, 14, ALIGN_HCENTER)
end

function _draw()
  if state == "title" then
    title_draw()
  elseif state == "over" then
    over_draw()
  else
    draw_play_world()
    draw_hud()
  end
end
