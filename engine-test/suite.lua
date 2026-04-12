-- Mono Engine Test Suite
-- Procedural tests, no game loop callbacks

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
cls(0)
pix(80, 72, 1)
assert_eq("center pixel set",   gpix(80, 72), 1)
assert_eq("empty pixel",        gpix(0, 0),   0)

-- out of bounds should return 0
assert_eq("oob left",   gpix(-1, 0),  0)
assert_eq("oob right",  gpix(160, 0), 0)
assert_eq("oob top",    gpix(0, -1),  0)
assert_eq("oob bottom", gpix(0, 120), 0)

-- ============================================================
section("cls")
-- ============================================================
cls(1)
assert_eq("cls fill",   gpix(0, 0),     1)
assert_eq("cls fill 2", gpix(159, 143), 1)
cls(0)
assert_eq("cls clear",  gpix(0, 0),     0)

-- ============================================================
section("line")
-- ============================================================
cls(0)
line(0, 0, 10, 0, 1)
for x = 0, 10 do
  assert_eq("hline x=" .. x, gpix(x, 0), 1)
end
assert_eq("hline outside", gpix(11, 0), 0)

-- vertical line
cls(0)
line(5, 0, 5, 10, 1)
for y = 0, 10 do
  assert_eq("vline y=" .. y, gpix(5, y), 1)
end
assert_eq("vline outside", gpix(5, 11), 0)

-- diagonal
cls(0)
line(0, 0, 5, 5, 1)
assert_eq("diag start", gpix(0, 0), 1)
assert_eq("diag end",   gpix(5, 5), 1)

-- ============================================================
section("rect")
-- ============================================================
cls(0)
rect(10, 10, 10, 10, 1)
-- corners
assert_eq("rect tl", gpix(10, 10), 1)
assert_eq("rect tr", gpix(19, 10), 1)
assert_eq("rect bl", gpix(10, 19), 1)
assert_eq("rect br", gpix(19, 19), 1)
-- edges
assert_eq("rect top edge",    gpix(15, 10), 1)
assert_eq("rect bottom edge", gpix(15, 19), 1)
assert_eq("rect left edge",   gpix(10, 15), 1)
assert_eq("rect right edge",  gpix(19, 15), 1)
-- inside should be empty
assert_eq("rect inside", gpix(15, 15), 0)
-- outside
assert_eq("rect outside", gpix(9, 9), 0)

-- ============================================================
section("rectf")
-- ============================================================
cls(0)
rectf(20, 20, 5, 5, 1)
for y = 20, 24 do
  for x = 20, 24 do
    assert_eq("rectf " .. x .. "," .. y, gpix(x, y), 1)
  end
end
assert_eq("rectf outside", gpix(25, 20), 0)

-- ============================================================
section("circ")
-- ============================================================
cls(0)
circ(80, 72, 10, 1)
-- cardinal points on circle
assert_eq("circ right",  gpix(90, 72), 1)
assert_eq("circ left",   gpix(70, 72), 1)
assert_eq("circ top",    gpix(80, 62), 1)
assert_eq("circ bottom", gpix(80, 82), 1)
-- center should be empty
assert_eq("circ center empty", gpix(80, 72), 0)
-- outside
assert_eq("circ outside", gpix(92, 72), 0)

-- ============================================================
section("circf")
-- ============================================================
cls(0)
circf(80, 72, 10, 1)
assert_eq("circf center", gpix(80, 72), 1)
assert_eq("circf edge",   gpix(90, 72), 1)
assert_eq("circf outside", gpix(92, 72), 0)

-- ============================================================
section("text")
-- ============================================================
cls(0)
text("A", 0, 0, 1)
-- 'A' glyph: row 0 = .XX. → pixels 1,2 set
assert_eq("text A px1", gpix(1, 0), 1)
assert_eq("text A px2", gpix(2, 0), 1)
assert_eq("text A px0", gpix(0, 0), 0)
assert_eq("text A px3", gpix(3, 0), 0)

-- ============================================================
section("vrow")
-- ============================================================
cls(0)
pix(0, 0, 1)
pix(1, 0, 1)
pix(159, 0, 1)
local row = vrow(0)
assert_eq("vrow length", #row, 160)
assert_eq("vrow start",  row:sub(1, 2), "11")
assert_eq("vrow end",    row:sub(160, 160), "1")
assert_eq("vrow mid",    row:sub(3, 3), "0")

-- ============================================================
section("INTENTIONAL FAILURES (remove after testing)")
-- ============================================================
assert_eq("should fail: 1 ~= 0", 1, 0)
assert_eq("should fail: black is white", gpix(0, 0), 99)

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
