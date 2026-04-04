-- Scene Test: main.lua
-- Tests go(), scene_name(), frame(), and auto-loading scene files

function _init()
  mode(4)
end

function _ready()
  go("title")
end

-- Fallback (should not run if scenes work)
function _update() end
function _draw()
  cls(0)
  text("SCENE SYSTEM BROKEN", 10, 60, 15)
  text("go() did not work", 10, 75, 7)
end
