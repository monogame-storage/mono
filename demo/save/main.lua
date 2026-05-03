-- Save Demo — exercises all six data_* functions.
--
-- Three fields persisted under their own keys:
--   name      ← cycles through preset names  (key: "name_idx")
--   age       ← 0..120                       (key: "age")
--   gender    ← M / F / X                    (key: "gender_idx")
--
-- Each row shows a dot indicating data_has(key): filled = persisted,
-- hollow = unsaved edit. The footer shows #data_keys() — how many keys
-- are currently in the bucket.
--
-- Controls:
--   ↑ ↓     pick a field
--   ← →     change the value of the selected field
--   A       data_save the current values for all three fields
--   B       data_delete just the selected field's key
--   START   data_clear the entire bucket; resets values to defaults
--   SELECT  trigger an error on purpose (e.g. invalid key) and display
--          the message — shows that data_* functions throw and can be
--          caught with pcall

local scr = screen()

local NAMES   = { "Alice", "Bob", "Carol", "Dave", "Erin" }
local GENDERS = { "M", "F", "X" }
local KEYS    = { "name_idx", "age", "gender_idx" }
local LABELS  = { "name", "age", "gender" }
local DEFAULTS = { 1, 20, 1 }

local values = { 1, 20, 1 }   -- in-memory editable copy
local field = 1
local flash, flash_msg = 0, ""
local err_msg = nil           -- last captured pcall error, drawn at the bottom

-- A small catalog of intentionally-bad calls that exercise different
-- branches of the error contract. SELECT cycles through them so you
-- can see each thrown message verbatim.
local err_tests = {
  { label = "empty key",      fn = function() data_load("") end },
  { label = "key w/ space",   fn = function() data_save("hi score", 1) end },
  { label = "key 65 chars",   fn = function() data_save(string.rep("k", 65), 1) end },
  { label = "function value", fn = function() data_save("k", function() end) end },
  { label = "NaN value",      fn = function() data_save("k", 0/0) end },
}
local err_idx = 1

local function flash_text(msg)
  flash, flash_msg = 30, msg
end

local function display_value(i)
  if     i == 1 then return NAMES[values[1]]
  elseif i == 2 then return values[2]
  elseif i == 3 then return GENDERS[values[3]]
  end
end

function _init() mode(4) end

function _start()
  for i = 1, 3 do
    -- data_load on a missing key returns nil (no throw) — the `or
    -- DEFAULTS[i]` fallback is the canonical idiom for first-run init.
    values[i] = data_load(KEYS[i]) or DEFAULTS[i]
  end
end

function _update()
  if btnp("up")    then field = (field - 2) % 3 + 1 end
  if btnp("down")  then field = field % 3 + 1 end

  if btnp("left") then
    if     field == 1 then values[1] = (values[1] - 2) % #NAMES   + 1
    elseif field == 2 then values[2] = math.max(0, values[2] - 1)
    elseif field == 3 then values[3] = (values[3] - 2) % #GENDERS + 1
    end
  elseif btnp("right") then
    if     field == 1 then values[1] = values[1] % #NAMES + 1
    elseif field == 2 then values[2] = math.min(120, values[2] + 1)
    elseif field == 3 then values[3] = values[3] % #GENDERS + 1
    end
  end

  if btnp("a") then
    for i = 1, 3 do data_save(KEYS[i], values[i]) end
    flash_text("SAVED")
  elseif btnp("b") then
    -- Delete only the selected field's key; in-memory value stays so
    -- the user can re-save it. data_delete returns true if the key
    -- existed — message reflects which case happened.
    if data_delete(KEYS[field]) then
      flash_text("DEL " .. LABELS[field])
    else
      flash_text("NO KEY")
    end
  elseif btnp("start") then
    data_clear()
    for i = 1, 3 do values[i] = DEFAULTS[i] end
    flash_text("CLEARED")
  elseif btnp("select") then
    -- Run the next bad call through pcall and capture the message.
    -- The bucket is unchanged after the throw (atomic validation).
    local test = err_tests[err_idx]
    local ok, err = pcall(test.fn)
    if ok then
      err_msg = "[" .. test.label .. "] no error?"
    else
      err_msg = "[" .. test.label .. "] " .. tostring(err)
    end
    err_idx = err_idx % #err_tests + 1
  end

  if flash > 0 then flash = flash - 1 end
end

local function row(i, y)
  -- Selection caret
  if field == i then text(scr, ">", 6, y, 15) end
  -- data_has indicator: filled circle = persisted, hollow = unsaved
  if data_has(KEYS[i]) then circf(scr, 16, y + 2, 2, 14)
                       else circ (scr, 16, y + 2, 2, 7)  end
  text(scr, LABELS[i],          22, y, 11)
  text(scr, tostring(display_value(i)), 78, y, 15)
end

function _draw()
  cls(scr, 0)
  text(scr, "SAVE DEMO", 6, 4, 15)
  line(scr, 6, 12, 100, 12, 8)

  row(1, 24)
  row(2, 38)
  row(3, 52)

  -- data_keys() count — drops to 0 after START, climbs back as you save.
  text(scr, "keys: " .. tostring(#data_keys()) .. "/3", 6, 70, 8)

  text(scr, "A SAVE  B DEL",     6, 78,  8)
  text(scr, "START CLR  SEL ERR", 6, 88,  8)

  -- Last captured error from SELECT. Renders in red-ish (color 12) so
  -- it's clearly distinct from the normal UI. Wraps to two lines if long.
  if err_msg then
    local s = err_msg
    rectf(scr, 0, 100, SCREEN_W, 20, 0)
    line (scr, 0, 100, SCREEN_W - 1, 100, 12)
    text (scr, s:sub(1, 26),       2, 102, 12)
    text (scr, s:sub(27, 26 + 26), 2, 110, 12)
  else
    text(scr, "SEL: trigger error",   6, 102, 7)
    text(scr, "(reload to verify)",   6, 110, 7)
  end

  if flash > 0 then
    local w = math.max(48, #flash_msg * 6 + 12)
    local x = math.floor((SCREEN_W - w) / 2)
    rectf(scr, x, 76, w, 14, 0)
    rect (scr, x, 76, w, 14, 15)
    text(scr, flash_msg, x + 6, 81, 15)
  end
end
