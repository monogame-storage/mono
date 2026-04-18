-- Title scene for Tilt Maze
local scr = screen()

local title_t
local preview_x, preview_y

function title_init()
  title_t = 0
  preview_x = SCREEN_W / 2
  preview_y = 76
end

function title_update()
  title_t = title_t + 1

  -- Auto-demo: live tilt preview using axis_x/y (also covers them in scan mode)
  local ax = axis_x()
  local ay = axis_y()
  preview_x = preview_x + ax * 0.5
  preview_y = preview_y + ay * 0.5
  if preview_x < 10 then preview_x = 10 end
  if preview_x > SCREEN_W - 10 then preview_x = SCREEN_W - 10 end
  if preview_y < 71 then preview_y = 71 end
  if preview_y > SCREEN_H - 15 then preview_y = SCREEN_H - 15 end

  if btnr("a") or btnr("start") or title_t >= 30 then
    go("level1")
  end
end

function title_draw()
  cls(scr, 0)
  text(scr, "TILT MAZE", 0, 14, 15, ALIGN_HCENTER)
  text(scr, "TILT TO ROLL", 0, 38, 11, ALIGN_HCENTER)
  text(scr, "REACH THE GOAL", 0, 50, 11, ALIGN_HCENTER)

  -- Tilt preview
  rect(scr, SCREEN_W / 2 - 30, 66, 60, 20, 8)
  circf(scr, math.floor(preview_x), math.floor(preview_y), 2, 14)

  text(scr, "PRESS A", 0, 96, 14, ALIGN_HCENTER)
  text(scr, scene_name(), 2, SCREEN_H - 10, 6)
end
