-- Dodge: avoid falling obstacles.
-- START on title; left/right to move; survive.

local scr = screen()

-- state: "title" | "play" | "over"
local state = "title"

local player = { x = 76, y = 108, w = 8, h = 6 }
local obstacles = {}
local score = 0
local best = 0
local speed = 1.5
local spawn_timer = 0
local play_frames = 0

-- obstacle classes
-- wide-slow: w=20, speed*0.7, color 6 (dim)
-- normal:    w=10, speed*1.0, color 8
-- narrow-fast: w=6, speed*1.5, color 8 (highlight via brightness 12 actually)
-- The plan says color 6 / existing / 8 — we'll respect: wide=6, normal=8, narrow=12.
local CLASS_WIDE = 1
local CLASS_NORMAL = 2
local CLASS_NARROW = 3

local function start_play()
  player.x = 76
  obstacles = {}
  score = 0
  speed = 1.5
  spawn_timer = 0
  play_frames = 0
  state = "play"
end

local function spawn_obstacle()
  local roll = math.random()
  local class, w, sp_mul, color
  if roll < 0.25 then
    class = CLASS_WIDE
    w = 20
    sp_mul = 0.7
    color = 6
  elseif roll < 0.85 then
    class = CLASS_NORMAL
    w = 10
    sp_mul = 1.0
    color = 8
  else
    class = CLASS_NARROW
    w = 6
    sp_mul = 1.5
    color = 12
  end
  local x = math.random(2, SCREEN_W - w - 2)
  table.insert(obstacles, {
    x = x, y = -8, w = w, h = 6,
    sp_mul = sp_mul, color = color, class = class,
  })
end

function _init()
  mode(4)
end

function _start()
  math.randomseed(math.floor(time() * 1000))
  best = data_load("dodge_best") or 0
  state = "title"
end

local function update_title()
  if btnp("start") then
    start_play()
  end
end

local function update_play()
  play_frames = play_frames + 1

  -- movement
  if btn("left") and player.x > 2 then player.x = player.x - 3 end
  if btn("right") and player.x + player.w < SCREEN_W - 2 then player.x = player.x + 3 end

  -- continuous difficulty
  speed = 1.5 + math.min(score * 0.04, 3.0)

  -- spawn cadence: 12 -> 6 over first 1800 frames (~60s)
  local t = math.min(play_frames / 1800, 1)
  local spawn_period = math.floor(12 - 6 * t)
  if spawn_period < 6 then spawn_period = 6 end

  spawn_timer = spawn_timer + 1
  if spawn_timer >= spawn_period then
    spawn_timer = 0
    spawn_obstacle()
  end

  -- move obstacles
  for i = #obstacles, 1, -1 do
    local ob = obstacles[i]
    ob.y = ob.y + speed * ob.sp_mul
    if ob.y > SCREEN_H then
      table.remove(obstacles, i)
      score = score + 1
      -- per-survived tick
      note(0, "E5", 0.02)
      -- milestone chime every 25
      if score % 25 == 0 then
        note(0, "G5", 0.08)
      end
    end
  end

  -- collision
  for _, ob in ipairs(obstacles) do
    if player.x < ob.x + ob.w and player.x + player.w > ob.x and
       player.y < ob.y + ob.h and player.y + player.h > ob.y then
      state = "over"
      cam_shake(6)
      noise(0, 0.3, "low", 300)
      if score > best then
        best = score
        data_save("dodge_best", best)
      end
      break
    end
  end
end

local function update_over()
  if btnp("start") then
    start_play()
  end
end

function _update()
  if state == "title" then
    update_title()
  elseif state == "play" then
    update_play()
  else
    update_over()
  end
end

local function draw_play_scene()
  -- border
  rect(scr, 0, 0, SCREEN_W, SCREEN_H, 3)

  -- obstacles
  for _, ob in ipairs(obstacles) do
    rectf(scr, ob.x, ob.y, ob.w, ob.h, ob.color)
  end

  -- player
  rectf(scr, player.x, player.y, player.w, player.h, 15)

  -- score
  text(scr, "SCORE " .. score, 2, 2, 12)
end

function _draw()
  cls(scr, 0)

  if state == "title" then
    -- title scene
    text(scr, "DODGE", SCREEN_W / 2, 40, 15, ALIGN_HCENTER)
    if math.floor(frame() / 15) % 2 == 0 then
      text(scr, "PRESS START", SCREEN_W / 2, 70, 11, ALIGN_HCENTER)
    end
    if best > 0 then
      text(scr, "BEST " .. best, SCREEN_W / 2, 90, 7, ALIGN_HCENTER)
    end
    return
  end

  draw_play_scene()

  if state == "over" then
    rectf(scr, 30, 40, 100, 40, 0)
    rect(scr, 30, 40, 100, 40, 15)
    text(scr, "GAME OVER", SCREEN_W / 2, 47, 15, ALIGN_HCENTER)
    text(scr, "SCORE: " .. score, SCREEN_W / 2, 59, 10, ALIGN_HCENTER)
    text(scr, "BEST: " .. best, SCREEN_W / 2, 69, 7, ALIGN_HCENTER)
  end
end
