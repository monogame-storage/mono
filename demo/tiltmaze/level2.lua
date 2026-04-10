-- Level 2: simpler, just demonstrates scene navigation + another canvas
local scr = screen()

local bg_canvas
local ball_x, ball_y
local ball_vx, ball_vy
local frames

function level2_init()
  -- Prerender a simple spiral pattern
  bg_canvas = canvas(SCREEN_W, SCREEN_H)
  cls(bg_canvas, 0)
  for r = 5, 70, 5 do
    circ(bg_canvas, SCREEN_W / 2, SCREEN_H / 2, r, r % 15 + 1)
  end
  rect(bg_canvas, 0, 0, SCREEN_W, SCREEN_H, 8)
  -- Goal zone at bottom-right
  rectf(bg_canvas, SCREEN_W - 16, SCREEN_H - 16, 16, 16, 11)

  ball_x = 10
  ball_y = 10
  ball_vx = 0
  ball_vy = 0
  frames = 0
end

function level2_update()
  frames = frames + 1

  -- SELECT = skip
  if btnp("select") then
    canvas_del(bg_canvas)
    go("clear")
    return
  end

  local ax = axis_x()
  local ay = axis_y()
  if btn("left")  then ax = ax - 1 end
  if btn("right") then ax = ax + 1 end
  if btn("up")    then ay = ay - 1 end
  if btn("down")  then ay = ay + 1 end

  ball_vx = ball_vx + ax * 0.2
  ball_vy = ball_vy + ay * 0.2
  ball_vx = ball_vx * 0.92
  ball_vy = ball_vy * 0.92

  ball_x = ball_x + ball_vx
  ball_y = ball_y + ball_vy
  if ball_x < 2 then ball_x = 2; ball_vx = 0 end
  if ball_y < 2 then ball_y = 2; ball_vy = 0 end
  if ball_x > SCREEN_W - 2 then ball_x = SCREEN_W - 2; ball_vx = 0 end
  if ball_y > SCREEN_H - 2 then ball_y = SCREEN_H - 2; ball_vy = 0 end

  -- Goal check
  if ball_x > SCREEN_W - 16 and ball_y > SCREEN_H - 16 then
    canvas_del(bg_canvas)
    go("clear")
  end
end

function level2_draw()
  cls(scr, 0)
  blit(bg_canvas, scr, 0, 0)
  circf(scr, math.floor(ball_x), math.floor(ball_y), 2, 15)
  text(scr, scene_name(), 2, 2, 14)
end
