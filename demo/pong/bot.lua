-- Pong Bot: reads VRAM to track ball, controls P2 paddle
-- Usage: node headless/mono-runner.js demos/pong/main.lua --bot demos/pong/bot.lua

function _bot()
  -- find ball: scan middle area for brightest pixel cluster
  local best_y = -1
  local best_count = 0
  for y = 4, SCREEN_H - 5 do
    local count = 0
    for x = 48, 140 do
      if gpix(x, y) >= 12 then count = count + 1 end
    end
    if count > best_count then
      best_count = count
      best_y = y
    end
  end

  -- find P2 paddle: bright pixels on right edge
  local pad_sum = 0
  local pad_count = 0
  for y = 0, SCREEN_H - 1 do
    for x = 148, 156 do
      if gpix(x, y) >= 12 then
        pad_sum = pad_sum + y
        pad_count = pad_count + 1
      end
    end
  end
  local pad_y = pad_count > 0 and (pad_sum / pad_count) or 72

  -- track ball with deadzone
  if best_y >= 0 then
    if best_y < pad_y - 6 then return "up" end
    if best_y > pad_y + 6 then return "down" end
  end
  return false
end
