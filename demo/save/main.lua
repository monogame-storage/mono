-- Save Demo — exercises all six data_* functions plus the error contract.
--
-- One vertical menu, three sections:
--   FIELDS  3 persisted values (name / age / gender) — edit + save
--   API     data_has / data_delete probes — pick target key with ← →
--   ERRORS  5 intentionally-bad calls that should throw
--
-- Controls (context-sensitive on the highlighted row):
--   ↑ ↓     navigate the menu
--   ← →     FIELD : change value
--           API   : cycle the target key (shared between has and delete)
--           ERROR : no-op
--   A       FIELD : data_save just this row's key (per-field save)
--           API   : data_has(target) or data_delete(target); result inline
--           ERROR : pcall the bad call; render the captured message
--   B       FIELD : data_delete just this row's key
--   START   data_clear the entire bucket; resets fields to defaults

local scr = screen()

-- ── FIELDS ──────────────────────────────────────────────────────────────
local NAMES    = { "Alice", "Bob", "Carol", "Dave", "Erin" }
local GENDERS  = { "M", "F", "X" }
local KEYS     = { "name_idx", "age", "gender_idx" }
local LABELS   = { "name", "age", "gender" }
local DEFAULTS = { 1, 20, 1 }
local values   = { 1, 20, 1 }

-- ── API target key ──────────────────────────────────────────────────────
-- "unknown" is included so the user can probe a key that has never been
-- written; data_has returns false, data_delete returns false.
local TARGETS = { "name_idx", "age", "gender_idx", "unknown" }
local target_idx = 1
local has_result = nil       -- nil / true / false — last has() result
local del_result = nil       -- "DEL" / "NO KEY" — last delete() result

-- ── Error tests ─────────────────────────────────────────────────────────
local err_tests = {
  { label = "empty key",      fn = function() data_load("") end },
  { label = "whitespace key", fn = function() data_save("hi score", 1) end },
  { label = "long key",       fn = function() data_save(string.rep("k", 65), 1) end },
  { label = "function value", fn = function() data_save("k", function() end) end },
  { label = "NaN value",      fn = function() data_save("k", 0/0) end },
}
local err_msg = nil

-- ── Menu navigation (flat index across all three sections) ──────────────
-- Indices: 1..3 = fields, 4..5 = api (has, delete), 6..10 = errors.
local FIELD_COUNT = 3
local API_COUNT   = 2
local ERR_COUNT   = #err_tests
local TOTAL       = FIELD_COUNT + API_COUNT + ERR_COUNT
local sel = 1

local function is_field(i) return i >= 1 and i <= FIELD_COUNT end
local function is_api(i)   return i > FIELD_COUNT and i <= FIELD_COUNT + API_COUNT end
local function is_error(i) return i > FIELD_COUNT + API_COUNT end
local function api_idx(i)  return i - FIELD_COUNT end           -- 1=has, 2=delete
local function err_idx(i)  return i - FIELD_COUNT - API_COUNT end

-- ── Flash ───────────────────────────────────────────────────────────────
local flash, flash_msg = 0, ""
local function flash_text(msg) flash, flash_msg = 30, msg end

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
  -- Any navigation clears the last-error overlay so each error message
  -- is unambiguously tied to the row it was triggered from.
  if btnp("up") then
    sel = (sel - 2) % TOTAL + 1
    err_msg = nil
  end
  if btnp("down") then
    sel = sel % TOTAL + 1
    err_msg = nil
  end

  -- ← → meaning depends on the selected row's section
  if btnp("left") then
    if is_field(sel) then
      if     sel == 1 then values[1] = (values[1] - 2) % #NAMES   + 1
      elseif sel == 2 then values[2] = math.max(0, values[2] - 1)
      elseif sel == 3 then values[3] = (values[3] - 2) % #GENDERS + 1
      end
    elseif is_api(sel) then
      target_idx = (target_idx - 2) % #TARGETS + 1
    end
  elseif btnp("right") then
    if is_field(sel) then
      if     sel == 1 then values[1] = values[1] % #NAMES + 1
      elseif sel == 2 then values[2] = math.min(120, values[2] + 1)
      elseif sel == 3 then values[3] = values[3] % #GENDERS + 1
      end
    elseif is_api(sel) then
      target_idx = target_idx % #TARGETS + 1
    end
  end

  if btnp("a") then
    if is_field(sel) then
      data_save(KEYS[sel], values[sel])
      flash_text("SAVED " .. LABELS[sel])
    elseif is_api(sel) then
      local key = TARGETS[target_idx]
      if api_idx(sel) == 1 then
        has_result = data_has(key)
      else
        del_result = data_delete(key) and "DEL" or "NO KEY"
      end
    elseif is_error(sel) then
      local test = err_tests[err_idx(sel)]
      local ok, err = pcall(test.fn)
      err_msg = ok and "[" .. test.label .. "] no error?" or tostring(err)
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
    has_result = nil
    del_result = nil
    err_msg    = nil
    flash_text("CLEARED")
  end

  if flash > 0 then flash = flash - 1 end
end

-- ── Drawing ─────────────────────────────────────────────────────────────
local function caret(y) text(scr, ">", 2, y, 15) end

local function draw_field(i, y)
  if sel == i then caret(y) end
  if data_has(KEYS[i]) then circf(scr, 12, y + 2, 2, 14)
                       else circ (scr, 12, y + 2, 2, 7)  end
  text(scr, LABELS[i],        18, y, 11)
  text(scr, display_value(i), 78, y, 15)
end

local function draw_api(idx, y)
  local i = FIELD_COUNT + idx
  if sel == i then caret(y) end
  local label = (idx == 1) and "has?"  or "delete"
  text(scr, label, 12, y, 13)
  text(scr, TARGETS[target_idx], 50, y, 15)
  -- Last result inline after the key
  if idx == 1 and has_result ~= nil then
    text(scr, has_result and "true" or "false", 116, y, has_result and 14 or 7)
  elseif idx == 2 and del_result ~= nil then
    text(scr, del_result, 116, y, del_result == "DEL" and 14 or 7)
  end
end

local function draw_err(idx, y)
  local i = FIELD_COUNT + API_COUNT + idx
  if sel == i then caret(y) end
  text(scr, ".",                 12, y, 12)
  text(scr, err_tests[idx].label, 18, y, 12)
end

function _draw()
  cls(scr, 0)

  text(scr, "SAVE DEMO", 2, 2, 15)
  text(scr, "keys " .. tostring(#data_keys()) .. "/3", 110, 2, 8)

  draw_field(1, 12)
  draw_field(2, 20)
  draw_field(3, 28)

  text(scr, "api",    2, 38, 8)
  draw_api(1, 46)
  draw_api(2, 54)

  text(scr, "errors", 2, 64, 8)
  for i = 1, ERR_COUNT do
    draw_err(i, 72 + (i - 1) * 8)
  end

  -- Last captured error from A on an error row
  if err_msg then
    rectf(scr, 0, 112, SCREEN_W, 8, 0)
    text(scr, err_msg:sub(1, 26), 2, 113, 12)
  end

  if flash > 0 then
    local w = math.max(48, #flash_msg * 6 + 12)
    local x = math.floor((SCREEN_W - w) / 2)
    local y = 50
    rectf(scr, x, y, w, 14, 0)
    rect (scr, x, y, w, 14, 15)
    text(scr, flash_msg, x + 6, y + 5, 15)
  end
end
