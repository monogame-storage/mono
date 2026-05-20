-- Win screen
local scr = screen()

local t
local total_time     -- total seconds across both levels (this run)
local best_time      -- persisted best total
local new_record     -- true when this run set a new best

function clear_init()
  t = 0
  local l1 = data_load("tiltmaze_level1_t") or 0
  local l2 = data_load("tiltmaze_level2_t") or 0
  total_time = (l1 + l2) / 30
  best_time = data_load("tiltmaze_best") or 999
  new_record = total_time > 0 and total_time < best_time
  if new_record then
    best_time = total_time
    data_save("tiltmaze_best", best_time)
  end
end

function clear_update()
  t = t + 1
  if btnr("a") or btnr("start") then
    go("title")
  end
end

function clear_draw()
  cls(scr, 0)
  text(scr, "CLEAR!", 0, 24, 15, ALIGN_HCENTER)
  text(scr, "YOU MADE IT", 0, 42, 11, ALIGN_HCENTER)

  text(scr, string.format("TIME %.1f", total_time), 0, 58, 14, ALIGN_HCENTER)
  if best_time < 999 then
    text(scr, string.format("BEST %.1f", best_time), 0, 70, 11, ALIGN_HCENTER)
  end
  if new_record then
    text(scr, "NEW RECORD!", 0, 82, 15, ALIGN_HCENTER)
  end

  -- Sparkle effect
  for i = 1, 20 do
    local x = (i * 17 + t * 3) % SCREEN_W
    local y = (i * 11 + t) % SCREEN_H
    pix(scr, x, y, (t + i) % 15 + 1)
  end
  text(scr, "A: AGAIN", 0, 100, 14, ALIGN_HCENTER)
  text(scr, scene_name(), 2, SCREEN_H - 10, 6)
end
