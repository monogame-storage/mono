-- title scene (auto-loaded by go("title"))
local blink = 0

function title_init()
  blink = 0
end

function title_update()
  blink = blink + 1
  if btnp("start") then
    go("play")
  end
end

function title_draw()
  cls(1)
  text("SCENE TEST", 45, 30, 15)
  text("scene: " .. (scene_name() or "nil"), 35, 50, 10)
  text("frame: " .. frame(), 35, 65, 10)
  if math.floor(blink / 15) % 2 == 0 then
    text("PRESS START", 40, 100, 15)
  end
end
