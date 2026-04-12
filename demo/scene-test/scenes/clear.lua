-- scenes/clear.lua (state pattern)
local scr = screen()
local scene = {}
local wait = 0

function scene.init()
  wait = 0
end

function scene.update()
  wait = wait + 1
  if btnp("start") or wait >= 90 then
    go("scenes/title")
  end
end

function scene.draw()
  cls(scr, 0)
  text(scr, "STAGE CLEAR!", 35, 44, 15)
  text(scr, "scene: " .. (scene_name() or "nil"), 35, 62, 10)
  text(scr, "frame: " .. frame(), 35, 76, 10)
end

return scene
