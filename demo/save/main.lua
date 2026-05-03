-- Save Demo — three fields, persisted on demand.
--
--   name   ← left/right cycles through preset names
--   age    ← left/right ±1
--   gender ← left/right cycles M / F / X
--
-- Up/down picks which field is selected. A saves the current values to
-- the local bucket. START wipes the bucket. Reload the page and the
-- values you saved come back.

local scr = screen()

local NAMES   = { "Alice", "Bob", "Carol", "Dave", "Erin" }
local GENDERS = { "M", "F", "X" }

local name_idx, age, gender_idx = 1, 20, 1
local field = 1            -- 1=name, 2=age, 3=gender
local flash, flash_msg = 0, ""

local function flash_text(msg)
  flash, flash_msg = 30, msg
end

function _init() mode(4) end

function _start()
  name_idx   = data_load("name_idx")   or 1
  age        = data_load("age")        or 20
  gender_idx = data_load("gender_idx") or 1
end

function _update()
  if btnp("up")    then field = (field - 2) % 3 + 1 end
  if btnp("down")  then field = field % 3 + 1 end

  if btnp("left") then
    if     field == 1 then name_idx   = (name_idx   - 2) % #NAMES   + 1
    elseif field == 2 then age        = math.max(0, age - 1)
    elseif field == 3 then gender_idx = (gender_idx - 2) % #GENDERS + 1
    end
  elseif btnp("right") then
    if     field == 1 then name_idx   = name_idx   % #NAMES   + 1
    elseif field == 2 then age        = math.min(120, age + 1)
    elseif field == 3 then gender_idx = gender_idx % #GENDERS + 1
    end
  end

  if btnp("a") then
    data_save("name_idx",   name_idx)
    data_save("age",        age)
    data_save("gender_idx", gender_idx)
    flash_text("SAVED")
  elseif btnp("start") then
    data_clear()
    name_idx, age, gender_idx = 1, 20, 1
    flash_text("CLEARED")
  end

  if flash > 0 then flash = flash - 1 end
end

local function row(label, value, y, selected)
  if selected then text(scr, ">", 8, y, 15) end
  text(scr, label,         18, y, 11)
  text(scr, tostring(value), 78, y, 15)
end

function _draw()
  cls(scr, 0)
  text(scr, "SAVE DEMO", 8, 6, 15)
  line(scr, 8, 14, 96, 14, 8)

  row("name",   NAMES[name_idx],     28, field == 1)
  row("age",    age,                 42, field == 2)
  row("gender", GENDERS[gender_idx], 56, field == 3)

  text(scr, "A SAVE  START CLEAR", 8, 92, 8)
  text(scr, "(reload to verify)",  8, 104, 7)

  if flash > 0 then
    rectf(scr, 40, 70, 80, 14, 0)
    rect (scr, 40, 70, 80, 14, 15)
    text(scr, flash_msg, 60, 75, 15)
  end
end
