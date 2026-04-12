-- Win screen
local scr = screen()

local t

function clear_init()
  t = 0
end

function clear_update()
  t = t + 1
  if btnp("a") or btnp("start") then
    go("title")
  end
end

function clear_draw()
  cls(scr, 0)
  text(scr, "CLEAR!", 0, 32, 15, ALIGN_HCENTER)
  text(scr, "YOU MADE IT", 0, 50, 11, ALIGN_HCENTER)
  -- Sparkle effect
  for i = 1, 20 do
    local x = (i * 17 + t * 3) % SCREEN_W
    local y = (i * 11 + t) % SCREEN_H
    pix(scr, x, y, (t + i) % 15 + 1)
  end
  text(scr, "A: AGAIN", 0, 92, 14, ALIGN_HCENTER)
  text(scr, scene_name(), 2, SCREEN_H - 10, 6)
end
