-- Title scene: blinking PRESS START, reacts to START or touch.
local scr = screen()

function title_init()
end

function title_update()
  if btnr("start") or touch_end() then
    note(0, "E5", 0.08)
    go("game")
  end
end

function title_draw()
  cls(scr, 0)
  text(scr, "%TITLE%", 80, 40, 15, ALIGN_CENTER)

  if math.floor(frame() / 15) % 2 == 0 then
    text(scr, "PRESS START", 80, 90, 11, ALIGN_HCENTER)
  end

  text(scr, "V1.0", 158, 116, 5, ALIGN_RIGHT + ALIGN_VCENTER)
end
