-- Test 2: Lines (1-bit)

function _draw()
  cls(0)
  -- cross
  line(0, 0, 159, 143, 1)
  line(159, 0, 0, 143, 1)
  -- border
  line(0, 0, 159, 0, 1)
  line(159, 0, 159, 143, 1)
  line(159, 143, 0, 143, 1)
  line(0, 143, 0, 0, 1)
end

function _init()
  cls(0)
  line(0, 0, 10, 0, 1)
  -- check horizontal line
  local pass = true
  for x = 0, 10 do
    if gpix(x, 0) ~= 1 then pass = false end
  end
  if pass then
    print("PASS: horizontal line")
  else
    print("FAIL: horizontal line")
  end
  -- check pixel outside line
  if gpix(11, 0) == 0 then
    print("PASS: outside line = 0")
  else
    print("FAIL: outside line")
  end
end
