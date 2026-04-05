-- Dodge Game: avoid falling obstacles

local scr = screen()
local player = { x = 76, y = 130, w = 8, h = 6 }
local obstacles = {}
local score = 0
local speed = 1.5
local spawn_timer = 0
local game_over = false

function _init()
  mode(4)
end

function _start()
  player.x = 76
  obstacles = {}
  score = 0
  speed = 1.5
  spawn_timer = 0
  game_over = false
end

function _update()
  if game_over then
    if btnp("start") then _start() end
    return
  end

  -- player movement
  if btn("left") and player.x > 2 then player.x = player.x - 3 end
  if btn("right") and player.x + player.w < SCREEN_W - 2 then player.x = player.x + 3 end

  -- spawn obstacles
  spawn_timer = spawn_timer + 1
  if spawn_timer >= 12 then
    spawn_timer = 0
    local w = math.random(6, 20)
    local x = math.random(2, SCREEN_W - w - 2)
    table.insert(obstacles, { x = x, y = -8, w = w, h = 6 })
  end

  -- move obstacles
  for i = #obstacles, 1, -1 do
    local ob = obstacles[i]
    ob.y = ob.y + speed
    if ob.y > SCREEN_H then
      table.remove(obstacles, i)
      score = score + 1
    end
  end

  -- collision check
  for _, ob in ipairs(obstacles) do
    if player.x < ob.x + ob.w and player.x + player.w > ob.x and
       player.y < ob.y + ob.h and player.y + player.h > ob.y then
      game_over = true
      print("GAME OVER: " .. score)
      break
    end
  end

  -- increase difficulty
  if score > 0 and score % 10 == 0 then
    speed = 1.5 + score * 0.05
  end
end

function _draw()
  cls(scr, 0)

  -- border
  rect(scr, 0, 0, SCREEN_W, SCREEN_H, 3)

  -- obstacles
  for _, ob in ipairs(obstacles) do
    rectf(scr, ob.x, ob.y, ob.w, ob.h, 8)
  end

  -- player
  rectf(scr, player.x, player.y, player.w, player.h, 15)

  -- score
  text(scr, "SCORE " .. score, 2, 2, 12)

  -- game over
  if game_over then
    rectf(scr, 30, 55, 100, 30, 0)
    rect(scr, 30, 55, 100, 30, 15)
    text(scr, "GAME OVER", 48, 62, 15)
    text(scr, "SCORE: " .. score, 52, 74, 10)
  end
end
