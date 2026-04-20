-- Game over scene. Any input returns to the title.
local scr = screen()

local function any_input_released()
  return btnr("start") or btnr("select") or btnr("a") or btnr("b")
      or btnr("up") or btnr("down") or btnr("left") or btnr("right")
      or touch_start()
end

function gameover_init()
  tone(0, 800, 200, 0.4)
end

function gameover_update()
  if any_input_released() then
    go("title")
  end
end

function gameover_draw()
  cls(scr, 0)
  text(scr, "GAME OVER", 80, 55, 15, ALIGN_CENTER)
  if math.floor(frame() / 15) % 2 == 0 then
    text(scr, "ANY KEY", 80, 75, 8, ALIGN_HCENTER)
  end
end
