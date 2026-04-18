-- clear scene (auto-loaded by go("clear"))
local wait = 0

function clear_init()
  wait = 0
end

function clear_update()
  wait = wait + 1
  if btnr("start") or wait >= 90 then
    go("title")
  end
end

function clear_draw()
  cls(0)
  text("STAGE CLEAR!", 35, 44, 15)
  text("scene: " .. (scene_name() or "nil"), 35, 62, 10)
  text("frame: " .. frame(), 35, 76, 10)
end
