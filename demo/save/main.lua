-- Save Demo — exercises every data_* function against the local save bucket.
--
-- Layout (top → bottom):
--   "SAVE DEMO"           — title
--   visits: N             — incremented once per boot, persists across reloads
--   best:   N             — highest dice roll seen for this cart
--   color:  N             — last A-button color preference (0..15)
--   last 5 rolls:         — 5 colored squares; oldest fades on the left
--
-- Controls:
--   A       roll d100 (math.random); bumps `best` if higher, prepends to history
--   B       cycle color preference (0..15)
--   START   clears the entire save bucket — visits resets to 1 next boot
--
-- Persistence:
--   Every state change calls data_save immediately (write-through). Reload
--   the page and the values come back. Open DevTools → Application →
--   localStorage and you'll see one entry: "mono:save:demo:save".
--
-- Attract mode:
--   With no input for 60 frames, the demo auto-rolls every 30 frames so
--   the headless coverage scanner exercises data_save / data_load even
--   when nobody presses anything.

local scr = screen()

-- In-memory mirror of the save bucket. Seeded from disk on _start, kept
-- in sync via the data_save calls below. Drawing reads from these locals
-- (data_load on every frame would be wasteful and rnd-in-draw-style ugly).
local visits = 0
local best = 0
local color_pref = 7
local rolls = {}     -- array of last-5 dice rolls (newest first)

local cleared_flash = 0   -- frames remaining to flash "CLEARED" message
local last_input_frame = 0

function _init()
  mode(4)              -- 16 grayscale
end

function _start()
  -- Read every persisted value once. data_load returns nil for missing
  -- keys; coalesce into sensible defaults.
  visits     = (data_load("visits")      or 0) + 1
  best       =  data_load("best")        or 0
  color_pref =  data_load("color_pref")  or 7
  rolls      =  data_load("rolls")       or {}

  -- Persist the bumped visit count immediately so a crash mid-session
  -- still records that we ran.
  data_save("visits", visits)
end

local function record_roll(value)
  if value > best then
    best = value
    data_save("best", best)
  end
  -- Prepend new roll, cap history at 5.
  table.insert(rolls, 1, value)
  while #rolls > 5 do table.remove(rolls) end
  data_save("rolls", rolls)
end

local function clear_all()
  data_clear()
  visits = 1
  best = 0
  color_pref = 7
  rolls = {}
  cleared_flash = 30
  -- Bumping visits=1 immediately after clear so the visits row stays
  -- coherent with what the user sees on screen.
  data_save("visits", visits)
end

function _update()
  if btnp("a") then
    record_roll(math.random(1, 100))
    last_input_frame = frame()
  elseif btnp("b") then
    color_pref = (color_pref + 1) % 16
    data_save("color_pref", color_pref)
    last_input_frame = frame()
  elseif btnp("start") then
    clear_all()
    last_input_frame = frame()
  end

  -- Attract mode: if the player isn't touching anything, auto-roll
  -- every 30 frames so the headless scanner exercises data_save.
  if frame() - last_input_frame > 60 and frame() % 30 == 0 then
    record_roll(math.random(1, 100))
  end

  if cleared_flash > 0 then cleared_flash = cleared_flash - 1 end
end

local function draw_label_value(label, value, y, value_color)
  text(scr, label, 6, y, 11)
  text(scr, tostring(value), 60, y, value_color or 15)
end

function _draw()
  cls(scr, 0)

  -- Title
  text(scr, "SAVE DEMO", 6, 4, 15)
  line(scr, 6, 12, 90, 12, 8)

  draw_label_value("visits:", visits,     18)
  draw_label_value("best:",   best,       28, 14)
  draw_label_value("color:",  color_pref, 38, color_pref)

  -- Color preference swatch (next to the number)
  rectf(scr, 75, 38, 7, 7, color_pref)
  rect (scr, 75, 38, 7, 7, 8)

  -- Last 5 rolls — show numeric value above each square
  text(scr, "last 5:", 6, 52, 11)
  for i = 1, 5 do
    local x = 6 + (i - 1) * 16
    local y = 62
    if rolls[i] then
      -- Brightness scales with value (1..100 → 4..15).
      local c = 4 + math.floor((rolls[i] / 100) * 11)
      rectf(scr, x, y, 12, 14, c)
      rect (scr, x, y, 12, 14, 15)
      text(scr, tostring(rolls[i]), x + 1, y + 4, 0)
    else
      rect(scr, x, y, 12, 14, 6)
    end
  end

  -- Footer hints
  text(scr, "A roll  B color", 6, 88,  8)
  text(scr, "START clear",     6, 98,  8)
  text(scr, "(reload to see persistence)", 6, 110, 7)

  -- Cleared flash overlay
  if cleared_flash > 0 then
    rectf(scr, 32, 50, 96, 20, 0)
    rect (scr, 32, 50, 96, 20, 15)
    text(scr, "CLEARED", 56, 58, 15)
  end
end
