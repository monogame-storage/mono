-- My Mono Game
-- 160x144, Lua 5.4

local scr = screen()

function _init()
  mode(1) -- 1=2 colors, 2=4 colors, 4=16 colors
end

function _start()
  -- initialize game state here
end

function _update()
  -- game logic (called every frame at 30fps)
end

function _draw()
  cls(scr, 0)
  text(scr, "HELLO MONO!", SCREEN_W/2, SCREEN_H/2, 1, ALIGN_CENTER)
  rect(scr, 0, 0, SCREEN_W, SCREEN_H, 1)
end
