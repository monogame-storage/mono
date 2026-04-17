-- Game Over Scene
local scene = {}
local timer = 0
local played_sfx = false

function scene.init()
  timer = 0
  played_sfx = false
end

function scene.update()
  timer = timer + 1
  if not played_sfx and timer == 2 then
    sfx_gameover()
    played_sfx = true
  end
  if timer > 60 and btnp("start") then
    sfx_menu_select()
    go("title")
  end
end

function scene.draw()
  local scr = screen()
  cls(scr, 0)

  -- Dimmed particles
  for i = 1, 15 do
    local bx = (i * 37 + timer) % W
    local by = (i * 23 + timer * 0.3) % H
    pix(scr, math.floor(bx), math.floor(by), 2)
  end

  -- Falling debris effect
  for i = 1, 8 do
    local dx = (i * 19 + timer * 0.8) % W
    local dy = (timer * (0.5 + i * 0.1) + i * 31) % (H + 20) - 10
    pix(scr, math.floor(dx), math.floor(dy), 4)
  end

  -- Red vignette at edges
  for i = 0, 2 do
    rect(scr, i, i, W - i * 2, H - i * 2, 3 - i)
  end

  -- Box with fade-in
  local box_alpha = math.min(timer / 15, 1.0)
  local bc = math.floor(box_alpha * 8)
  if bc < 1 then bc = 1 end
  rectf(scr, 25, 28, 110, 70, 1)
  rect(scr, 25, 28, 110, 70, bc)
  rect(scr, 26, 29, 108, 68, math.max(1, bc - 4))

  -- Skull-like icon
  if timer > 10 then
    rectf(scr, 72, 34, 16, 12, 10)
    rectf(scr, 74, 36, 4, 4, 0)   -- left eye
    rectf(scr, 82, 36, 4, 4, 0)   -- right eye
    rectf(scr, 77, 42, 2, 2, 0)   -- nose
    rectf(scr, 74, 44, 12, 2, 0)  -- mouth
    -- Flickering eye glow
    if math.floor(frame() / 10) % 3 ~= 0 then
      pix(scr, 75, 37, 8)
      pix(scr, 83, 37, 8)
    end
  end

  -- Title with shake effect for first few frames
  local shake_x = 0
  local shake_y = 0
  if timer < 20 then
    shake_x = math.random(-1, 1)
    shake_y = math.random(-1, 1)
  end
  text(scr, "GAME OVER", 47 + shake_x, 52 + shake_y, 15)

  -- Stats
  if timer > 20 then
    text(scr, "SCORE: " .. G.score, 48, 64, 12)
    text(scr, "STAGE: " .. G.cur_level, 50, 73, 10)
    text(scr, "COINS: " .. G.coins_collected, 48, 82, 13)
  end

  -- Blinking restart prompt
  if timer > 60 then
    if math.floor(frame() / 15) % 2 == 0 then
      text(scr, "PRESS START", 42, 90, 15)
    else
      text(scr, "PRESS START", 42, 90, 8)
    end
  end
end

return scene
