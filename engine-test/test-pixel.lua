-- Test 1: Center pixel (1-bit)

function _draw()
  cls(0)
  pix(80, 72, 1)
end

function _init()
  -- draw once to test gpix
  cls(0)
  pix(80, 72, 1)
  local v = gpix(80, 72)
  if v == 1 then
    print("PASS: center pixel = 1")
  else
    print("FAIL: center pixel = " .. tostring(v))
  end
  -- check empty pixel
  local v2 = gpix(0, 0)
  if v2 == 0 then
    print("PASS: empty pixel = 0")
  else
    print("FAIL: empty pixel = " .. tostring(v2))
  end
end
