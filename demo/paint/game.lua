-- Paint Demo
-- Covers: touch, touch_start, touch_end, touch_pos, touch_posf,
--         touch_count, swipe, gpix
--
-- Controls:
--   Touch / click : paint
--   Swipe left    : clear canvas
--   Swipe right   : cycle color
--   Multi-touch   : increases brush size
--   Tap palette (right strip) : pick color

local scr = screen()

local PAL_W = 16       -- right-side palette width
local canvas_w = 144   -- actual drawing area width
local current_color = 15
local last_x, last_y
local status_msg = ""
local status_timer = 0

function _init()
  mode(4)
end

function _start()
  cls(scr, 0)
end

local function show_msg(msg)
  status_msg = msg
  status_timer = 60
end

local function in_canvas(x, y)
  return x >= 0 and x < canvas_w and y >= 0 and y < SCREEN_H - 12
end

local function draw_brush(x, y, size)
  if size <= 1 then
    pix(scr, x, y, current_color)
  else
    circf(scr, x, y, size, current_color)
  end
end

function _update()
  -- Poll all touch/swipe APIs every frame so scan coverage sees them.
  -- Cached reads also let us use them below without multiple calls.
  local dir = swipe()
  local is_touching = touch()
  local started = touch_start()
  local ended = touch_end()
  local tc = touch_count()
  local tix, tiy = touch_pos()
  local tfx, tfy = touch_posf()

  if dir == "left" then
    cls(scr, 0)
    show_msg("CLEAR")
  elseif dir == "right" then
    current_color = (current_color % 15) + 1
    show_msg("COLOR " .. current_color)
  end

  if is_touching and tfx then
    local x = math.floor(tfx)
    local y = math.floor(tfy)

    if x >= canvas_w then
      if started then
        current_color = math.max(1, math.min(15, math.floor((y / SCREEN_H) * 15) + 1))
        show_msg("PICK " .. current_color)
      end
    elseif in_canvas(x, y) then
      local brush = tc
      if started or not last_x then
        draw_brush(x, y, brush)
      else
        line(scr, last_x, last_y, x, y, current_color)
        if brush > 1 then circf(scr, x, y, brush, current_color) end
      end
      last_x = x
      last_y = y
    end
  elseif ended then
    last_x = nil
    last_y = nil
  end

  if status_timer > 0 then status_timer = status_timer - 1 end
end

function _draw()
  -- NOTE: we draw persistently, so no cls() in _draw().
  -- Palette strip on the right
  for i = 1, 15 do
    local yy = math.floor((i - 1) * (SCREEN_H / 15))
    local hh = math.ceil(SCREEN_H / 15)
    rectf(scr, canvas_w, yy, PAL_W, hh, i)
  end
  -- Current color indicator (sample with gpix to verify palette render)
  local sampled = gpix(scr, canvas_w + 2, (current_color - 1) * (SCREEN_H / 15) + 2)
  if sampled >= 0 then
    rect(scr, canvas_w - 1, (current_color - 1) * (SCREEN_H / 15), PAL_W + 1,
         math.ceil(SCREEN_H / 15), 15)
  end

  -- Separator line
  line(scr, canvas_w - 1, 0, canvas_w - 1, SCREEN_H - 1, 8)

  -- Status bar at bottom
  rectf(scr, 0, SCREEN_H - 10, canvas_w, 10, 0)
  text(scr, "PAINT", 2, SCREEN_H - 8, 11)
  if status_timer > 0 then
    text(scr, status_msg, canvas_w - 2, SCREEN_H - 8, 14, ALIGN_RIGHT)
  end
end
