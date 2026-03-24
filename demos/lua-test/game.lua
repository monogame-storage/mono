-- Mono Lua Test Game
-- Minimal test: title screen + moving square

local x = 160
local y = 120

function title_draw()
  cls(0)
  text("MONO LUA TEST", 100, 80, 3)
  text("PRESS START", 108, 140, 2)
end

function play_update()
  if btn("left") then x = x - 2 end
  if btn("right") then x = x + 2 end
  if btn("up") then y = y - 2 end
  if btn("down") then y = y + 2 end
end

function play_draw()
  cls(0)
  rectf(x - 8, y - 8, 16, 16, 3)
  text("X=" .. flr(x) .. " Y=" .. flr(y), 2, 2, 2)
  text("ARROWS TO MOVE", 2, 230, 1)
end
