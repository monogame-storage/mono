# AI Pitfalls — Common Mistakes When Generating Mono Code

A living document of bugs AI assistants repeatedly introduce.
Include this in prompts to prevent recurrence.

---

## 1. rnd() in draw functions
**Symptom:** Objects change size/position every frame (flickering, jittering)
**Cause:** `rnd()` called inside `draw()` produces different values each frame
**Fix:** Generate random values once in `init()`, store in a table, draw from table
```lua
-- BAD: random height every frame
function play_draw()
  for x = 0, 300, 50 do
    local h = 30 + flr(rnd(30))  -- different every frame!
    rectf(x, 100 - h, 40, h, 1)
  end
end

-- GOOD: generate once, draw from table
local buildings = {}
function play_init()
  for x = 0, 300, 50 do
    buildings[#buildings+1] = {x=x, h=30+flr(rnd(30))}
  end
end
function play_draw()
  for _, b in ipairs(buildings) do
    rectf(b.x, 100 - b.h, 40, b.h, 1)
  end
end
```

---

## 2. Lua local function forward reference
**Symptom:** Game crashes silently, nothing renders
**Cause:** `local function B()` defined after `local function A()` which calls `B()`
**Fix:** Define functions before they are called — order matters for `local function`
```lua
-- BAD: bsInit calls bsGenBuildings but it's defined later
local function bsInit()
  bsGenBuildings()  -- nil! not defined yet
end
local function bsGenBuildings() ... end

-- GOOD: define helper first
local function bsGenBuildings() ... end
local function bsInit()
  bsGenBuildings()  -- works
end
```

---

## 3. Wasmoon null returns crash Lua
**Symptom:** `TypeError: Cannot read properties of null (reading 'then')`
**Cause:** JS function returns `null` to Lua — Wasmoon can't push null to Lua stack
**Fix:** Return `false` instead of `null` from JS functions exposed to Lua
```js
// BAD
function pollCollision() {
  if (queue.length === 0) return null;  // crashes Wasmoon
}

// GOOD
function pollCollision() {
  if (queue.length === 0) return false;  // Lua receives false
}
```

---

## 4. Lua number vs boolean comparison
**Symptom:** `attempt to compare number with boolean`
**Cause:** `btnp()` returns boolean, used in arithmetic/comparison with number
**Fix:** Don't mix `btnp()` (boolean) with number comparisons
```lua
-- BAD: btnp returns true/false, can't compare with number
tmapMoveDelay = btnp("up") and 8 or 3  -- fine
if moved then tmapMoveDelay = btnp("up") or btnp("down") and 8 or 3 end
-- this evaluates as: btnp("up") or (btnp("down") and 8) or 3
-- which can be boolean or number — then compared with <= 0

-- GOOD: explicit logic
if moved then
  tmapMoveDelay = 3  -- default repeat rate
end
```

---

## 5. Camera affects rectf but not text
**Symptom:** HUD elements (health bars, dialog boxes) scroll with camera, text stays fixed
**Cause:** `rectf`/`circ`/`spr` are offset by camera, `text()` is not
**Fix:** Reset camera before drawing HUD, restore after
```lua
-- BAD: dialog box moves with camera, text doesn't
rectf(10, 200, 300, 30, 0)  -- affected by camera
text("HELLO", 20, 205, 3)   -- NOT affected

-- GOOD: screen-space HUD
local cx, cy = cam_get()
cam(0, 0)
rectf(10, 200, 300, 30, 0)  -- now screen space
cam(cx, cy)
text("HELLO", 20, 205, 3)   -- also screen space (always was)
```

---

## 6. Scroll direction confusion
**Symptom:** Background scrolls wrong direction
**Cause:** AI interprets "scroll up" as "pixels move up" instead of "camera moves up / background moves down"
**Fix:** Specify in terms of what the player sees: "background moves DOWN" for upward-scrolling shooter
```lua
-- For a vertical shooter where player flies upward:
-- Stars should move DOWN (increasing Y)
starY = starY + speed  -- correct: stars fall
-- NOT starY = starY - speed  -- wrong: stars rise
```

---

## 7. ECS spawn() with Lua table proxy
**Symptom:** Spawned entities have no properties, `JSON.stringify` returns `{}`
**Cause:** Wasmoon wraps Lua tables as proxy objects — JS can't iterate them with Object.entries
**Fix:** Use a Lua-side wrapper that decomposes tables into flat arguments for JS
```lua
-- Engine injects spawn() wrapper that calls _spawnRaw with flat args
-- Game code just uses spawn({...}) normally
spawn({
  group = "bullet",
  pos = {x = 100, y = 50},
  vel = {x = 0, y = -5},
  sprite = sprite_id("bullet"),
  hitbox = {r = 3},
})
```

---

## 8. setInterval error spam
**Symptom:** Console fills with thousands of identical errors per second
**Cause:** `setInterval` game loop doesn't stop on error — keeps calling broken function 30 times/sec
**Fix:** Wrap tick in try/catch that stops the interval on repeated errors
```js
// Consider: stop loop after N consecutive errors
let errorCount = 0;
function tick() {
  try {
    stepInput(); stepUpdate(); stepRender();
    errorCount = 0;
  } catch(e) {
    console.error("Mono:", e.message);
    if (++errorCount > 10) { clearInterval(loopId); console.error("Loop stopped"); }
  }
}
```

---

## 9. Diagonal movement faster than cardinal
**Symptom:** Moving diagonally is ~1.41x faster than horizontal/vertical
**Cause:** Both X and Y velocity applied at full speed simultaneously
**Fix:** Normalize diagonal movement
```lua
local dx, dy = 0, 0
if btn("left") then dx = -1 end
if btn("right") then dx = 1 end
if btn("up") then dy = -1 end
if btn("down") then dy = 1 end
-- Normalize
if dx ~= 0 and dy ~= 0 then
  dx = dx * 0.7071
  dy = dy * 0.7071
end
px = px + dx * speed
py = py + dy * speed
```

---

*Add new entries as bugs are discovered. Format: Symptom → Cause → Fix with code examples.*
