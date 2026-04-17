-- Win Scene
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
    sfx_win_fanfare()
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

  -- Celebratory particles
  for i = 1, 40 do
    local bx = (i * 17 + timer * 0.7) % W
    local by = (i * 29 + timer * 0.3) % H
    local bc = 6 + (i % 8)
    pix(scr, math.floor(bx), math.floor(by), bc)
  end

  -- Rising sparkles
  for i = 1, 12 do
    local sx = (i * 13 + timer * 0.3) % W
    local sy = H - (timer * (0.3 + i * 0.08) + i * 17) % H
    local sc = 10 + (i % 5)
    pix(scr, math.floor(sx), math.floor(sy), sc)
    pix(scr, math.floor(sx) + 1, math.floor(sy), math.max(1, sc - 2))
  end

  -- Bright border pulse
  local pulse_c = 10 + math.floor(math.sin(timer * 0.1) * 4)
  if pulse_c < 6 then pulse_c = 6 end
  if pulse_c > 15 then pulse_c = 15 end

  -- Box
  rectf(scr, 18, 20, 124, 85, 1)
  rect(scr, 18, 20, 124, 85, 15)
  rect(scr, 19, 21, 122, 83, pulse_c)
  rect(scr, 20, 22, 120, 81, 6)

  -- Trophy icon
  rectf(scr, 73, 27, 14, 10, 13)
  rectf(scr, 75, 27, 10, 10, 15)
  rectf(scr, 77, 37, 6, 3, 13)
  rectf(scr, 75, 40, 10, 2, 13)
  -- Trophy handles
  rectf(scr, 71, 29, 3, 5, 13)
  rectf(scr, 86, 29, 3, 5, 13)
  -- Trophy sparkle
  if math.floor(frame() / 6) % 3 == 0 then
    pix(scr, 76, 28, 15)
    pix(scr, 84, 30, 15)
  elseif math.floor(frame() / 6) % 3 == 1 then
    pix(scr, 78, 30, 15)
    pix(scr, 82, 28, 15)
  end

  text(scr, "CONGRATULATIONS!", 26, 47, 15)

  text(scr, "YOU ESCAPED THE", 33, 59, 12)
  text(scr, "SHADOW REALM!", 37, 68, 12)

  -- Score breakdown
  text(scr, "FINAL SCORE: " .. G.score, 32, 80, 15)
  text(scr, "COINS: " .. G.coins_collected, 48, 89, 13)

  if timer > 60 then
    if math.floor(frame() / 12) % 2 == 0 then
      text(scr, "PRESS START", 42, 98, 13)
    else
      text(scr, "PRESS START", 42, 98, 8)
    end
  end
end

return scene
