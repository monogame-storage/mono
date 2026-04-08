-- Scene Test: main.lua
-- Tests go() with state pattern + folder structure (scenes/)
local scr = screen()

function _init()
  mode(4)
end

function _ready()
  go("scenes/title")
end

-- Fallback (should not run if scenes work)
function _update() end
function _draw()
  cls(scr, 0)
  text(scr, "SCENE SYSTEM BROKEN", 10, 60, 15)
  text(scr, "go() did not work", 10, 75, 7)
end
