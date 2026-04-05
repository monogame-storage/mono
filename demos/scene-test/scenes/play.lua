-- scenes/play.lua (state pattern)
local scr = screen()
local scene = {}
local px, py = 80, 72
local timer = 0

function scene.init()
  px = 80
  py = 72
  timer = 0
end

function scene.update()
  timer = timer + 1
  if btn("left") then px = px - 1 end
  if btn("right") then px = px + 1 end
  if btn("up") then py = py - 1 end
  if btn("down") then py = py + 1 end
  if btnp("b") then
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
  text(scr, "WASD=move B=back", 20, 125, 7)
  text(scr, "auto-clear in " .. (300 - timer), 20, 135, 7)
end

return scene
