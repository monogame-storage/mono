-- Mono Engine Test Suite
-- Procedural tests, no game loop callbacks

local scr = screen()
local pass, fail = 0, 0

local function assert_eq(name, got, expected)
  if got == expected then
    pass = pass + 1
  else
    fail = fail + 1
    print("FAIL: " .. name .. " got=" .. tostring(got) .. " expected=" .. tostring(expected))
  end
end

local function assert_neq(name, got, rejected)
  if got ~= rejected then
    pass = pass + 1
  else
    fail = fail + 1
    print("FAIL: " .. name .. " got=" .. tostring(got) .. " (should differ)")
  end
end

local function section(name)
  print("--- " .. name .. " ---")
end

-- ============================================================
section("pix / gpix")
-- ============================================================
cls(scr, 0)
pix(scr, 80, 60, 1)
assert_eq("center pixel set",   gpix(scr, 80, 60), 1)
assert_eq("empty pixel",        gpix(scr, 0, 0),   0)

-- out of bounds should return 0
assert_eq("oob left",   gpix(scr, -1, 0),  0)
assert_eq("oob right",  gpix(scr, 160, 0), 0)
assert_eq("oob top",    gpix(scr, 0, -1),  0)
assert_eq("oob bottom", gpix(scr, 0, 120), 0)

-- ============================================================
section("cls")
-- ============================================================
cls(scr, 1)
assert_eq("cls fill",   gpix(scr, 0, 0),     1)
assert_eq("cls fill 2", gpix(scr, 159, 119), 1)
cls(scr, 0)
assert_eq("cls clear",  gpix(scr, 0, 0),     0)

-- ============================================================
section("line")
-- ============================================================
cls(scr, 0)
line(scr, 0, 0, 10, 0, 1)
for x = 0, 10 do
  assert_eq("hline x=" .. x, gpix(scr, x, 0), 1)
end
assert_eq("hline outside", gpix(scr, 11, 0), 0)

-- vertical line
cls(scr, 0)
line(scr, 5, 0, 5, 10, 1)
for y = 0, 10 do
  assert_eq("vline y=" .. y, gpix(scr, 5, y), 1)
end
assert_eq("vline outside", gpix(scr, 5, 11), 0)

-- diagonal
cls(scr, 0)
line(scr, 0, 0, 5, 5, 1)
assert_eq("diag start", gpix(scr, 0, 0), 1)
assert_eq("diag end",   gpix(scr, 5, 5), 1)

-- ============================================================
section("rect")
-- ============================================================
cls(scr, 0)
rect(scr, 10, 10, 10, 10, 1)
-- corners
assert_eq("rect tl", gpix(scr, 10, 10), 1)
assert_eq("rect tr", gpix(scr, 19, 10), 1)
assert_eq("rect bl", gpix(scr, 10, 19), 1)
assert_eq("rect br", gpix(scr, 19, 19), 1)
-- edges
assert_eq("rect top edge",    gpix(scr, 15, 10), 1)
assert_eq("rect bottom edge", gpix(scr, 15, 19), 1)
assert_eq("rect left edge",   gpix(scr, 10, 15), 1)
assert_eq("rect right edge",  gpix(scr, 19, 15), 1)
-- inside should be empty
assert_eq("rect inside", gpix(scr, 15, 15), 0)
-- outside
assert_eq("rect outside", gpix(scr, 9, 9), 0)

-- ============================================================
section("rectf")
-- ============================================================
cls(scr, 0)
rectf(scr, 20, 20, 5, 5, 1)
for y = 20, 24 do
  for x = 20, 24 do
    assert_eq("rectf " .. x .. "," .. y, gpix(scr, x, y), 1)
  end
end
assert_eq("rectf outside", gpix(scr, 25, 20), 0)

-- ============================================================
section("circ")
-- ============================================================
cls(scr, 0)
circ(scr, 80, 60, 10, 1)
-- cardinal points on circle
assert_eq("circ right",  gpix(scr, 90, 60), 1)
assert_eq("circ left",   gpix(scr, 70, 60), 1)
assert_eq("circ top",    gpix(scr, 80, 50), 1)
assert_eq("circ bottom", gpix(scr, 80, 70), 1)
-- center should be empty
assert_eq("circ center empty", gpix(scr, 80, 60), 0)
-- outside
assert_eq("circ outside", gpix(scr, 92, 60), 0)

-- ============================================================
section("circf")
-- ============================================================
cls(scr, 0)
circf(scr, 80, 60, 10, 1)
assert_eq("circf center", gpix(scr, 80, 60), 1)
assert_eq("circf edge",   gpix(scr, 90, 60), 1)
assert_eq("circf outside", gpix(scr, 92, 60), 0)

-- ============================================================
section("text")
-- ============================================================
cls(scr, 0)
text(scr, "A", 0, 0, 1)
-- 'A' glyph: row 0 = .XX. → pixels 1,2 set
assert_eq("text A px1", gpix(scr, 1, 0), 1)
assert_eq("text A px2", gpix(scr, 2, 0), 1)
assert_eq("text A px0", gpix(scr, 0, 0), 0)
assert_eq("text A px3", gpix(scr, 3, 0), 0)

-- ============================================================
section("vrow")
-- ============================================================
cls(scr, 0)
pix(scr, 0, 0, 1)
pix(scr, 1, 0, 1)
pix(scr, 159, 0, 1)
local row = vrow(0)
assert_eq("vrow length", #row, 160)
assert_eq("vrow start",  row:sub(1, 2), "11")
assert_eq("vrow end",    row:sub(160, 160), "1")
assert_eq("vrow mid",    row:sub(3, 3), "0")

-- ============================================================
-- SUMMARY
-- ============================================================
print("")
print("========================================")
if fail == 0 then
  print("ALL PASSED: " .. pass .. " tests")
else
  print("RESULT: " .. pass .. " passed, " .. fail .. " FAILED")
end
print("========================================")
