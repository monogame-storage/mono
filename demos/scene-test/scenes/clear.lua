-- scenes/clear.lua (state pattern)
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
  cls(0)
  text("STAGE CLEAR!", 35, 55, 15)
  text("scene: " .. (scene_name() or "nil"), 35, 75, 10)
  text("frame: " .. frame(), 35, 90, 10)
end

return scene
