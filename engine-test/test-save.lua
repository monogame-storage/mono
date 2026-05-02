-- Local save / data_* round-trip and behavior tests.
-- Engine harness is loaded with saveBackend="memory" + cartId="test:save"
-- (set in run.html below) so each test load starts with a clean bucket.

local pass, fail = 0, 0

local function assert_eq(name, got, expected)
  if got == expected then
    pass = pass + 1
  else
    fail = fail + 1
    print("FAIL: " .. name .. " got=" .. tostring(got) .. " expected=" .. tostring(expected))
  end
end

local function assert_throws(name, fn, pattern)
  local ok, err = pcall(fn)
  if ok then
    fail = fail + 1
    print("FAIL: " .. name .. " (expected throw, got success)")
    return
  end
  if pattern and not string.find(tostring(err), pattern, 1, true) then
    fail = fail + 1
    print("FAIL: " .. name .. " (wrong message: " .. tostring(err) .. ")")
    return
  end
  pass = pass + 1
end

print("--- data_save / data_load primitives ---")
data_save("score", 42)
assert_eq("load number", data_load("score"), 42)

data_save("name", "alice")
assert_eq("load string", data_load("name"), "alice")

data_save("on", true)
assert_eq("load bool true", data_load("on"), true)

data_save("off", false)
assert_eq("load bool false", data_load("off"), false)

assert_eq("missing key returns nil", data_load("nope"), nil)

print("--- data_has / data_delete ---")
assert_eq("has existing", data_has("score"), true)
assert_eq("has missing", data_has("nope"), false)

assert_eq("delete existing returns true", data_delete("score"), true)
assert_eq("after delete: has", data_has("score"), false)
assert_eq("after delete: load", data_load("score"), nil)
assert_eq("delete missing returns false", data_delete("score"), false)

print("--- nested table round-trip ---")
data_save("settings", { music = true, volume = 7, levels = {1, 2, 3} })
local s = data_load("settings")
assert_eq("nested.music", s.music, true)
assert_eq("nested.volume", s.volume, 7)
assert_eq("nested.levels[1]", s.levels[1], 1)
assert_eq("nested.levels[3]", s.levels[3], 3)

print("--- data_keys() sorted ---")
data_clear()
data_save("c", 1); data_save("a", 1); data_save("b", 1)
local keys = data_keys()
assert_eq("keys count", #keys, 3)
assert_eq("keys[1]", keys[1], "a")
assert_eq("keys[2]", keys[2], "b")
assert_eq("keys[3]", keys[3], "c")

print("--- mutating loaded table does not auto-persist ---")
data_save("box", { x = 1 })
local b1 = data_load("box")
b1.x = 999
local b2 = data_load("box")
assert_eq("loaded mutation isolated", b2.x, 1)

print("--- data_clear() ---")
data_save("k", 1)
data_clear()
assert_eq("after clear: has", data_has("k"), false)
assert_eq("after clear: keys empty", #data_keys(), 0)

print("--- data_save(k, nil) deletes the key ---")
data_save("doomed", 7)
assert_eq("before nil-save: has", data_has("doomed"), true)
data_save("doomed", nil)
assert_eq("after nil-save: has", data_has("doomed"), false)
assert_eq("after nil-save: load", data_load("doomed"), nil)
-- nil-save on a missing key is a no-op (no error).
data_save("never_existed", nil)
assert_eq("nil-save on missing: has", data_has("never_existed"), false)

print("--- error contract ---")
assert_throws("invalid empty key", function() data_save("", 1) end, "save: invalid key")
assert_throws("function rejected", function() data_save("k", function() end) end, "save: unserializable")

print("")
print("========================================")
if fail == 0 then
  print("ALL PASSED: " .. pass .. " tests")
else
  print("RESULT: " .. pass .. " passed, " .. fail .. " FAILED")
end
print("========================================")
