-- scenes/title.lua (state pattern)
local scene = {}
local blink = 0

function scene.init()
  blink = 0
end

function scene.update()
  blink = blink + 1
  if btnp("start") then
    go("scenes/play")
  end
end

function scene.draw()
  cls(1)
  text("SCENE TEST", 45, 30, 15)
  text("scene: " .. (scene_name() or "nil"), 35, 50, 10)
  text("frame: " .. frame(), 35, 65, 10)
  if math.floor(blink / 15) % 2 == 0 then
    text("PRESS START", 40, 100, 15)
  end
end

return scene
