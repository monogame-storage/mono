-- scenes/play.lua (state pattern)
local scr = screen()
local scene = {}
local px, py = 80, 60
local timer = 0

function scene.init()
  px = 80
  py = 60
  timer = 0
end

function scene.update()
  timer = timer + 1
  if btn("left") then px = px - 1 end
  if btn("right") then px = px + 1 end
  if btn("up") then py = py - 1 end
  if btn("down") then py = py + 1 end
  if btnr("b") then
    go("scenes/title")
  end
  if timer >= 300 then
    go("scenes/clear")
  end
end

function scene.draw()
  cls(scr, 2)
  text(scr, "PLAYING", 55, 10, 15)
  text(scr, "scene: " .. (scene_name() or "nil"), 35, 25, 10)
  rectf(scr, px - 4, py - 4, 8, 8, 15)
  text(scr, "WASD=move B=back", 20, 100, 7)
  text(scr, "auto-clear in " .. (300 - timer), 20, 110, 7)
end

return scene
