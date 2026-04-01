-- Test 5: Hello World text (1-bit)

function _draw()
  cls(0)
  text("HELLO WORLD", 25, 68, 1)
end

function _start()
  cls(0)
  text("A", 0, 0, 1)
  -- 'A' top-left: row 0 should be .XX. pattern (pixels 1,2 set)
  if gpix(1, 0) == 1 then print("PASS: text pixel set") else print("FAIL: text pixel set") end
  if gpix(0, 0) == 0 then print("PASS: text pixel empty") else print("FAIL: text pixel empty") end
  -- check that gpix works after text
  local found = false
  for y = 0, 6 do
    for x = 0, 3 do
      if gpix(x, y) == 1 then found = true end
    end
  end
  if found then print("PASS: text has pixels") else print("FAIL: text has no pixels") end
end
