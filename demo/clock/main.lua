-- Clock Demo
-- Showcases the date() API in four skins:
--   1. small digital  — compact 7-segment HH:MM
--   2. large digital  — big 7-segment HH:MM filling most of the screen
--   3. small analog   — compact round face with three hands
--   4. large analog   — big round face with three hands
--
-- Controls:
--   A — cycle to next skin
--   B — context toggle:
--         digital modes → 24-hour ↔ 12-hour
--         analog modes  → second hand on ↔ off
--
-- The digital colon blink uses frame() (not time()) so the animation
-- advances identically in browser and headless runs. The hh/mm/ss values
-- come from date().

local scr = screen()

local MODE_COUNT = 4
local mode_idx = 1
local use_12h = false       -- digital skins: false = 24-hour, true = 12-hour
local show_seconds = true   -- analog skins: draw the second hand?

function _init()
  mode(4)
end

function _start()
  mode_idx = 1
end

local function is_digital() return mode_idx == 1 or mode_idx == 2 end
local function is_analog()  return mode_idx == 3 or mode_idx == 4 end

function _update()
  if btnp("a") then
    mode_idx = mode_idx % MODE_COUNT + 1
  elseif btnp("b") then
    if is_digital() then
      use_12h = not use_12h
    elseif is_analog() then
      show_seconds = not show_seconds
    end
  end
end

-- ─── 7-segment digits ────────────────────────────────────────────────────
-- Segments are labelled a..g like a real 7-seg display:
--     aaa
--    f   b
--    f   b
--     ggg
--    e   c
--    e   c
--     ddd
local SEG = {
  ["0"] = { a=1, b=1, c=1, d=1, e=1, f=1, g=0 },
  ["1"] = { a=0, b=1, c=1, d=0, e=0, f=0, g=0 },
  ["2"] = { a=1, b=1, c=0, d=1, e=1, f=0, g=1 },
  ["3"] = { a=1, b=1, c=1, d=1, e=0, f=0, g=1 },
  ["4"] = { a=0, b=1, c=1, d=0, e=0, f=1, g=1 },
  ["5"] = { a=1, b=0, c=1, d=1, e=0, f=1, g=1 },
  ["6"] = { a=1, b=0, c=1, d=1, e=1, f=1, g=1 },
  ["7"] = { a=1, b=1, c=1, d=0, e=0, f=0, g=0 },
  ["8"] = { a=1, b=1, c=1, d=1, e=1, f=1, g=1 },
  ["9"] = { a=1, b=1, c=1, d=1, e=0, f=1, g=1 },
}

-- Draw one 7-seg digit inside a (w × h) box whose top-left is (x, y).
local function draw_digit(x, y, w, h, ch, color)
  local seg = SEG[ch]
  if not seg then return end
  local t = math.max(1, math.floor(math.min(w, h) * 0.16))  -- segment thickness
  local half_h = math.floor((h - 3 * t) / 2)
  local mid = y + t + half_h
  -- horizontal segments (top, middle, bottom)
  if seg.a == 1 then rectf(scr, x + t, y, w - 2 * t, t, color) end
  if seg.g == 1 then rectf(scr, x + t, mid, w - 2 * t, t, color) end
  if seg.d == 1 then rectf(scr, x + t, y + h - t, w - 2 * t, t, color) end
  -- vertical segments
  if seg.f == 1 then rectf(scr, x, y + t, t, half_h, color) end
  if seg.b == 1 then rectf(scr, x + w - t, y + t, t, half_h, color) end
  if seg.e == 1 then rectf(scr, x, mid + t, t, half_h, color) end
  if seg.c == 1 then rectf(scr, x + w - t, mid + t, t, half_h, color) end
end

-- Blinking colon between two digits, vertically centered in a height-h box.
local function draw_colon(x, y, h, color, visible)
  if not visible then return end
  local d = math.max(2, math.floor(h * 0.12))
  rectf(scr, x, y + math.floor(h * 0.33) - math.floor(d / 2), d, d, color)
  rectf(scr, x, y + math.floor(h * 0.66) - math.floor(d / 2), d, d, color)
end

-- Render a HH:MM display centered on (cx, cy) with digit (dw × dh).
-- Respects the global use_12h toggle: in 12-hour mode, 0 → 12 and
-- 13..23 wrap to 1..11. Leading zero is kept either way for stable
-- positioning.
local function draw_digital(cx, cy, dw, dh, color)
  local d = date()
  local h = d.hour
  if use_12h then
    h = h % 12
    if h == 0 then h = 12 end
  end
  local digits = string.format("%02d%02d", h, d.min)
  local gap    = math.max(1, math.floor(dw * 0.25))  -- inter-digit spacing
  local col_w  = math.max(3, math.floor(dw * 0.35))  -- colon column width
  local total  = 4 * dw + 2 * gap + col_w + 2 * gap
  local x0     = cx - math.floor(total / 2)
  local y0     = cy - math.floor(dh / 2)

  draw_digit(x0,                         y0, dw, dh, digits:sub(1, 1), color)
  draw_digit(x0 + dw + gap,              y0, dw, dh, digits:sub(2, 2), color)

  local col_x = x0 + 2 * dw + 2 * gap
  local blink = (math.floor(frame() / 15) % 2 == 0)
  draw_colon(col_x, y0, dh, color, blink)

  draw_digit(col_x + col_w + gap,        y0, dw, dh, digits:sub(3, 3), color)
  draw_digit(col_x + col_w + gap + dw + gap, y0, dw, dh, digits:sub(4, 4), color)
end

-- ─── Skin 1: small digital ───────────────────────────────────────────────
local function draw_small()
  draw_digital(SCREEN_W / 2, SCREEN_H / 2, 10, 18, 14)
end

-- ─── Skin 2: large digital ───────────────────────────────────────────────
local function draw_large()
  draw_digital(SCREEN_W / 2, SCREEN_H / 2 - 2, 20, 42, 15)
end

-- ─── Analog renderer (parameterized for both sizes) ─────────────────────
-- Draws a circular clock face centered on (cx, cy) with radius r. All
-- decorations — tick marks, hand lengths, center cap — scale with r so
-- the same function powers both the small and large analog skins.
local function draw_analog(cx, cy, r)
  -- face
  circf(scr, cx, cy, r, 1)
  circ (scr, cx, cy, r, 11)
  circ (scr, cx, cy, r - 1, 11)

  -- hour markers (12 ticks; every 3rd one is longer for 12/3/6/9)
  local long_tick  = math.max(3, math.floor(r * 0.18))
  local short_tick = math.max(2, math.floor(r * 0.10))
  for i = 0, 11 do
    local a     = i * math.pi / 6 - math.pi / 2
    local inset = (i % 3 == 0) and long_tick or short_tick
    local x1 = cx + math.floor(math.cos(a) * (r - inset))
    local y1 = cy + math.floor(math.sin(a) * (r - inset))
    local x2 = cx + math.floor(math.cos(a) * (r - 1))
    local y2 = cy + math.floor(math.sin(a) * (r - 1))
    line(scr, x1, y1, x2, y2, 15)
  end

  local d = date()

  -- hour hand (short): slow sweep including minute offset
  local ha = ((d.hour % 12) + d.min / 60) * math.pi / 6 - math.pi / 2
  line(scr, cx, cy,
       cx + math.floor(math.cos(ha) * (r * 0.55)),
       cy + math.floor(math.sin(ha) * (r * 0.55)), 15)

  -- minute hand (medium) — smooth drift with second offset
  local ma = (d.min + d.sec / 60) * math.pi / 30 - math.pi / 2
  line(scr, cx, cy,
       cx + math.floor(math.cos(ma) * (r * 0.78)),
       cy + math.floor(math.sin(ma) * (r * 0.78)), 14)

  -- second hand (long) — ticks once per second. Hidden when the
  -- user has toggled show_seconds off via B.
  if show_seconds then
    local sa = d.sec * math.pi / 30 - math.pi / 2
    line(scr, cx, cy,
         cx + math.floor(math.cos(sa) * (r * 0.88)),
         cy + math.floor(math.sin(sa) * (r * 0.88)), 12)
  end

  -- center cap: grows slightly with radius
  local cap = math.max(1, math.floor(r * 0.05))
  circf(scr, cx, cy, cap, 15)
end

local function draw_analog_small()
  draw_analog(SCREEN_W / 2, SCREEN_H / 2 - 2, 26)
end

local function draw_analog_large()
  draw_analog(SCREEN_W / 2, SCREEN_H / 2 - 2, 52)
end

-- ─── Draw ────────────────────────────────────────────────────────────────
function _draw()
  cls(scr, 0)

  if     mode_idx == 1 then draw_small()
  elseif mode_idx == 2 then draw_large()
  elseif mode_idx == 3 then draw_analog_small()
  elseif mode_idx == 4 then draw_analog_large()
  end
end
