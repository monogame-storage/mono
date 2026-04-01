-- Shader Test (4-bit / 16 colors)
-- Visual content for testing shader effects
-- Shader control is in the HTML UI, not in Lua

local W = SCREEN_W
local H = SCREEN_H

local boxes = {}
local NUM_BOXES = 8

function _start()
  for i = 1, NUM_BOXES do
    boxes[i] = {
      x = math.random(10, W - 30),
      y = math.random(10, H - 30),
      w = math.random(8, 24),
      h = math.random(8, 24),
      dx = (math.random() - 0.5) * 2,
      dy = (math.random() - 0.5) * 2,
      c = math.random(1, 15),
    }
  end
end

function _update()
  for i = 1, NUM_BOXES do
    local b = boxes[i]
    b.x = b.x + b.dx
    b.y = b.y + b.dy
    if b.x <= 0 or b.x + b.w >= W then b.dx = -b.dx end
    if b.y <= 0 or b.y + b.h >= H then b.dy = -b.dy end
  end
end

function _draw()
  cls(0)

  -- boxes
  for i = 1, NUM_BOXES do
    local b = boxes[i]
    rectf(math.floor(b.x), math.floor(b.y), b.w, b.h, b.c)
  end

  -- circles
  circf(W / 2, H / 2, 20, 8)
  circ(W / 2, H / 2, 25, 15)

  -- gradient bar
  local bw = math.floor(W / 16)
  for i = 0, 15 do
    rectf(i * bw, H - 12, bw, 12, i)
  end

  -- title
  text("SHADER TEST", 3, 3, 15)
end
