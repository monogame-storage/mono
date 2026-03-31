-- Test 3: Rectangles (1-bit)

function _draw()
  cls(0)
  -- filled rect
  rectf(20, 20, 40, 30, 1)
  -- outline rect
  rect(70, 20, 40, 30, 1)
  -- nested
  rect(30, 70, 100, 50, 1)
  rectf(50, 80, 60, 30, 1)
end

function _init()
  cls(0)
  -- test rectf
  rectf(10, 10, 5, 5, 1)
  local pass = true
  for y = 10, 14 do
    for x = 10, 14 do
      if gpix(x, y) ~= 1 then pass = false end
    end
  end
  if pass then print("PASS: rectf filled") else print("FAIL: rectf filled") end
  -- check outside
  if gpix(15, 10) == 0 then print("PASS: rectf outside") else print("FAIL: rectf outside") end

  -- test rect outline
  cls(0)
  rect(20, 20, 10, 10, 1)
  if gpix(20, 20) == 1 then print("PASS: rect corner") else print("FAIL: rect corner") end
  if gpix(25, 25) == 0 then print("PASS: rect inside empty") else print("FAIL: rect inside empty") end
end
