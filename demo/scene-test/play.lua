-- play scene (auto-loaded by go("play"))
local px, py = 80, 60
local timer = 0

function play_init()
  px = 80
  py = 60
  timer = 0
end

function play_update()
  timer = timer + 1
  if btn("left") then px = px - 1 end
  if btn("right") then px = px + 1 end
  if btn("up") then py = py - 1 end
  if btn("down") then py = py + 1 end
  if btnr("b") then
    go("title")
  end
  if timer >= 300 then
    go("clear")
  end
end

function play_draw()
  cls(2)
  text("PLAYING", 55, 10, 15)
  text("scene: " .. (scene_name() or "nil"), 35, 25, 10)
  rectf(px - 4, py - 4, 8, 8, 15)
  text("WASD=move B=back", 20, 100, 7)
  text("auto-clear in " .. (300 - timer), 20, 110, 7)
end
