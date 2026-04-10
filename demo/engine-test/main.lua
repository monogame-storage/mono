-- Engine Test Demo
-- Exercises the current Mono engine API each frame so that
-- mono-test.js can catch regressions quickly.
--
-- Modes cycle automatically every 60 frames; press START to step
-- manually. Each mode hits a different slice of the API:
--   1 shapes   — rect/rectf/circ/circf/line/pix
--   2 text     — text alignment + multi-color
--   3 camera   — cam offset drawing
--   4 canvas   — off-screen canvas + blit
--   5 input    — btn/btnp readout
--   6 frame    — frame counter + animation
--   7 time     — time()/date() real-time APIs

local scr = screen()
local off                 -- off-screen canvas (mode 4)
local mode_idx = 1
local mode_frame = 0
local MODE_COUNT = 7
local MODE_LEN = 60        -- frames per mode when auto-cycling

function _init()
  mode(4)               -- 16-color mode
end

function _start()
  mode_idx = 1
  mode_frame = 0
  off = canvas(32, 32)
  -- prime the off-screen canvas once
  cls(off, 0)
  rectf(off, 0, 0, 32, 32, 3)
  circf(off, 16, 16, 10, 11)
  text(off, "OFF", 8, 13, 15)
end

local function next_mode()
  mode_idx = mode_idx + 1
  if mode_idx > MODE_COUNT then mode_idx = 1 end
  mode_frame = 0
end

function _update()
  mode_frame = mode_frame + 1
  if btnp("start") or mode_frame >= MODE_LEN then
    next_mode()
  end
end

local function draw_shapes()
  rect(scr,  4, 16, 30, 20, 12)
  rectf(scr, 38, 16, 30, 20, 8)
  circ(scr,  88, 26, 10, 11)
  circf(scr, 116, 26, 10, 10)
  line(scr, 4, 44, 156, 44, 6)
  for i = 0, 15 do
    pix(scr, 4 + i * 2, 52, i)
  end
end

local function draw_text()
  text(scr, "LEFT",   2,  18,  7)
  text(scr, "CENTER", 0,  32, 11, ALIGN_HCENTER)
  text(scr, "RIGHT",  0,  46, 13, ALIGN_RIGHT)
  text(scr, "COLORS", 0,  64, 15, ALIGN_CENTER)
end

local function draw_camera()
  -- world draw affected by camera; text stays in HUD via cam(0,0)
  cam(math.floor(math.sin(mode_frame * 0.1) * 6), 0)
  rectf(scr, 40, 40, 80, 40, 4)
  circf(scr, 80, 60, 10, 14)
  cam(0, 0)
  text(scr, "CAMERA", 0, 4, 15, ALIGN_HCENTER)
end

local function draw_canvas()
  blit(scr, off, 20, 30)
  blit(scr, off, 60, 30)
  blit(scr, off, 100, 30)
  text(scr, "CANVAS", 0, 4, 15, ALIGN_HCENTER)
end

local function draw_input()
  local y = 24
  local function row(label, on)
    text(scr, label, 20, y, on and 11 or 6)
    y = y + 10
  end
  row("UP",    btn("up"))
  row("DOWN",  btn("down"))
  row("LEFT",  btn("left"))
  row("RIGHT", btn("right"))
  row("A",     btn("a"))
  row("B",     btn("b"))
end

local function draw_frame()
  local f = frame()
  text(scr, "FRAME " .. f, 0, 40, 11, ALIGN_HCENTER)
  local bar = (mode_frame * 2) % 60
  rectf(scr, 50, 60, bar, 6, 14)
end

local function draw_time()
  local t = time()
  local d = date()
  text(scr, string.format("TIME %.2f", t), 0, 20, 11, ALIGN_HCENTER)
  text(scr, string.format("%04d-%02d-%02d", d.year, d.month, d.day),
       0, 36, 14, ALIGN_HCENTER)
  text(scr, string.format("%02d:%02d:%02d.%03d", d.hour, d.min, d.sec, d.ms),
       0, 50, 15, ALIGN_HCENTER)
  text(scr, "WDAY " .. d.wday .. "  YDAY " .. d.yday, 0, 66, 8, ALIGN_HCENTER)
end

local names = { "SHAPES", "TEXT", "CAMERA", "CANVAS", "INPUT", "FRAME", "TIME" }

function _draw()
  cls(scr, 0)
  rect(scr, 0, 0, SCREEN_W, SCREEN_H, 3)

  if     mode_idx == 1 then draw_shapes()
  elseif mode_idx == 2 then draw_text()
  elseif mode_idx == 3 then draw_camera()
  elseif mode_idx == 4 then draw_canvas()
  elseif mode_idx == 5 then draw_input()
  elseif mode_idx == 6 then draw_frame()
  elseif mode_idx == 7 then draw_time()
  end

  -- HUD (always camera-independent). The frame counter is always
  -- visible; time() / date() are NOT read here because they are
  -- non-deterministic and would make /mono-verify --determinism
  -- flaky. Mode 7 draw_time() is the only place real-time APIs
  -- are exercised, and coverage for them is handled by the
  -- dedicated demo/clock demo instead.
  cam(0, 0)
  text(scr, "ENGINE TEST", 2, 2, 15)
  text(scr, mode_idx .. "/" .. MODE_COUNT .. " " .. names[mode_idx],
       SCREEN_W - 2, 2, 12, ALIGN_RIGHT)
  text(scr, "F" .. frame(), 2, SCREEN_H - 10, 6)
end
