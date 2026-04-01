-- Test 4: Circles (1-bit)

function _draw()
  cls(0)
  -- filled circle
  circf(50, 72, 30, 1)
  -- outline circles
  circ(120, 72, 30, 1)
  circ(120, 72, 20, 1)
  circ(120, 72, 10, 1)
end

function _start()
  cls(0)
  -- test circf: center should be filled
  circf(80, 72, 10, 1)
  if gpix(80, 72) == 1 then print("PASS: circf center") else print("FAIL: circf center") end
  -- edge should be filled
  if gpix(90, 72) == 1 then print("PASS: circf edge") else print("FAIL: circf edge") end
  -- outside should be empty
  if gpix(92, 72) == 0 then print("PASS: circf outside") else print("FAIL: circf outside") end

  -- test circ outline
  cls(0)
  circ(80, 72, 10, 1)
  if gpix(90, 72) == 1 then print("PASS: circ edge") else print("FAIL: circ edge") end
  if gpix(80, 72) == 0 then print("PASS: circ center empty") else print("FAIL: circ center empty") end
end
