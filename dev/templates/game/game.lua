-- Gameplay scene.
-- SELECT is handled by the engine (pause toggle) -- no need to implement it.
-- If you want SELECT for inventory / menu / etc., call use_pause(false)
-- in game_init and handle btnp("select") yourself.
local scr = screen()

local player_x, player_y
local score = 0

function game_init()
  player_x = SCREEN_W / 2
  player_y = SCREEN_H / 2
  score = 0
end

function game_update()
  if btn("left")  then player_x = player_x - 1 end
  if btn("right") then player_x = player_x + 1 end
  if btn("up")    then player_y = player_y - 1 end
  if btn("down")  then player_y = player_y + 1 end

  if btnp("a") then
    score = score + 1
    note(0, "C5", 0.05)
  end

  if btnr("b") then
    go("gameover")
  end
end

function game_draw()
  cls(scr, 0)
  text(scr, "SCORE " .. score, 2, 2, 11)
  rectf(scr, math.floor(player_x) - 2, math.floor(player_y) - 2, 5, 5, 15)
  text(scr, "A = SCORE   B = END", 80, 110, 7, ALIGN_HCENTER)
end
