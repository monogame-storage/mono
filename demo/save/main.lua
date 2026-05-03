-- Save Demo — exercises all six data_* functions plus the error contract.
--
-- One vertical menu, two sections:
--   FIELDS   3 persisted values (name / age / gender)
--   ERRORS   5 intentionally-bad calls that should throw
--
-- Controls (context-sensitive on the highlighted row):
--   ↑ ↓     navigate the menu
--   ← →     change the FIELD value (no-op on error rows)
--   A       FIELD row : data_save all 3 fields   ("SAVED")
--           ERROR row : trigger the bad call via pcall, show the message
--   B       FIELD row : data_delete just this key
--   START   data_clear the entire bucket; resets fields to defaults
--
-- After START or a save, reload the page to see persistence in action.

local scr = screen()

-- ── Field state ─────────────────────────────────────────────────────────
local NAMES    = { "Alice", "Bob", "Carol", "Dave", "Erin" }
local GENDERS  = { "M", "F", "X" }
local KEYS     = { "name_idx", "age", "gender_idx" }
local LABELS   = { "name", "age", "gender" }
local DEFAULTS = { 1, 20, 1 }

local values = { 1, 20, 1 }   -- in-memory editable copy

-- ── Error tests (each entry is a menu item) ─────────────────────────────
-- Each fn deliberately violates the data_* contract. Selecting an
-- error item with A wraps fn in pcall and renders the captured message.
local err_tests = {
  { label = "empty key",      fn = function() data_load("") end },
  { label = "whitespace key", fn = function() data_save("hi score", 1) end },
  { label = "long key",       fn = function() data_save(string.rep("k", 65), 1) end },
  { label = "function value", fn = function() data_save("k", function() end) end },
  { label = "NaN value",      fn = function() data_save("k", 0/0) end },
}

-- ── Menu navigation ─────────────────────────────────────────────────────
-- One flat selection index covers FIELDS (1..3) and ERRORS (4..8).
local FIELD_COUNT = 3
local ERR_COUNT   = #err_tests
local TOTAL       = FIELD_COUNT + ERR_COUNT
local sel = 1

local function is_field(i) return i >= 1 and i <= FIELD_COUNT end
local function is_error(i) return i > FIELD_COUNT and i <= TOTAL end
local function err_index(i) return i - FIELD_COUNT end

-- ── Flash + error overlay ───────────────────────────────────────────────
local flash, flash_msg = 0, ""
local function flash_text(msg) flash, flash_msg = 30, msg end
local err_msg = nil

-- ── Display helpers ─────────────────────────────────────────────────────
local function display_value(i)
  if     i == 1 then return NAMES[values[1]]
  elseif i == 2 then return tostring(values[2])
  elseif i == 3 then return GENDERS[values[3]]
  end
end

-- ── Lifecycle ───────────────────────────────────────────────────────────
function _init() mode(4) end

function _start()
  for i = 1, FIELD_COUNT do
    -- data_load on a missing key returns nil; the `or DEFAULTS[i]`
    -- fallback is the canonical idiom for first-run init.
    values[i] = data_load(KEYS[i]) or DEFAULTS[i]
  end
end

function _update()
  if btnp("up")    then sel = (sel - 2) % TOTAL + 1 end
  if btnp("down")  then sel = sel % TOTAL + 1 end

  if is_field(sel) then
    if btnp("left") then
      if     sel == 1 then values[1] = (values[1] - 2) % #NAMES   + 1
      elseif sel == 2 then values[2] = math.max(0, values[2] - 1)
      elseif sel == 3 then values[3] = (values[3] - 2) % #GENDERS + 1
      end
    elseif btnp("right") then
      if     sel == 1 then values[1] = values[1] % #NAMES + 1
      elseif sel == 2 then values[2] = math.min(120, values[2] + 1)
      elseif sel == 3 then values[3] = values[3] % #GENDERS + 1
      end
    end
  end

  if btnp("a") then
    if is_field(sel) then
      for i = 1, FIELD_COUNT do data_save(KEYS[i], values[i]) end
      flash_text("SAVED")
    elseif is_error(sel) then
      local test = err_tests[err_index(sel)]
      local ok, err = pcall(test.fn)
      if ok then
        err_msg = "[" .. test.label .. "] no error?"
      else
        err_msg = tostring(err)
      end
    end
  elseif btnp("b") and is_field(sel) then
    if data_delete(KEYS[sel]) then
      flash_text("DEL " .. LABELS[sel])
    else
      flash_text("NO KEY")
    end
  elseif btnp("start") then
    data_clear()
    for i = 1, FIELD_COUNT do values[i] = DEFAULTS[i] end
    err_msg = nil
    flash_text("CLEARED")
  end

  if flash > 0 then flash = flash - 1 end
end

-- ── Drawing ─────────────────────────────────────────────────────────────
local function draw_caret(y)
  text(scr, ">", 2, y, 15)
end

local function draw_field_row(i, y)
  if sel == i then draw_caret(y) end
  -- data_has indicator: filled = persisted, hollow = unsaved edit
  if data_has(KEYS[i]) then circf(scr, 12, y + 2, 2, 14)
                       else circ (scr, 12, y + 2, 2, 7)  end
  text(scr, LABELS[i],            18, y, 11)
  text(scr, display_value(i),     78, y, 15)
end

local function draw_err_row(idx, y)
  local i = FIELD_COUNT + idx
  if sel == i then draw_caret(y) end
  -- Bullet to distinguish from field rows' has-dot
  text(scr, ".", 12, y, 12)
  text(scr, err_tests[idx].label, 18, y, 12)
end

function _draw()
  cls(scr, 0)

  text(scr, "SAVE DEMO", 2, 2, 15)
  text(scr, "keys " .. tostring(#data_keys()) .. "/3", 110, 2, 8)

  draw_field_row(1, 12)
  draw_field_row(2, 20)
  draw_field_row(3, 28)

  -- Section divider + label
  line(scr, 2, 38, 158, 38, 6)
  text(scr, "ERRORS", 2, 40, 8)

  for i = 1, ERR_COUNT do
    draw_err_row(i, 48 + (i - 1) * 8)
  end

  text(scr, "A=ACT B=DEL START=CLR", 2, 100, 7)

  -- Last captured error from A on an error row.
  if err_msg then
    rectf(scr, 0, 108, SCREEN_W, 12, 0)
    line (scr, 0, 108, SCREEN_W - 1, 108, 12)
    text (scr, err_msg:sub(1, 26), 2, 110, 12)
  end

  if flash > 0 then
    local w = math.max(48, #flash_msg * 6 + 12)
    local x = math.floor((SCREEN_W - w) / 2)
    local y = 60
    rectf(scr, x, y, w, 14, 0)
    rect (scr, x, y, w, 14, 15)
    text(scr, flash_msg, x + 6, y + 5, 15)
  end
end
