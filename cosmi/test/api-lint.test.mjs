// API.md compliance lint tests. Two layers:
//   - extractApiWhitelist: parse the canonical API.md format.
//   - lintApiCompliance: scan Lua and report calls outside the whitelist.
// Bias is permissive — a valid game must NEVER be falsely blocked.
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { extractApiWhitelist, lintApiCompliance, collectFileDefinedNames } from "../src/lib/api-lint.js";

const FIXTURE_API_MD = `# Mono API Reference

## Constants

| Constant | Value | Description |
|----------|-------|-------------|
| \`SCREEN_W\` | 160 | Screen width |
| \`SCREEN_H\` | 120 | Screen height |
| \`COLORS\` | 2 / 4 / 16 | Number of colors |

## Graphics

### circ(surface: number, cx: number, cy: number, r: number, color: Color): void
Draw a circle outline.

### circf(surface: number, cx: number, cy: number, r: number, color: Color): void
Draw a filled circle.

### cls(surface: number, color?: Color): void
Clear the surface.

### text(surface: number, str: string, x: number, y: number, color: Color, align?: number): void
Draw text.

## Input

### btn(key: Key): boolean

### btnp(key: Key): boolean

### touch_start(): boolean

### touch_pos(i?: number): number, number | false

## Misc

### axis_x

### axis_y

### mode

### screen

### go
`;

describe("extractApiWhitelist", () => {
  it("captures function names from typed signatures", () => {
    const { functions } = extractApiWhitelist(FIXTURE_API_MD);
    for (const fn of ["circ", "circf", "cls", "text", "btn", "btnp", "touch_start", "touch_pos"]) {
      assert.ok(functions.has(fn), `missing function: ${fn}`);
    }
  });

  it("captures bare-name Misc entries", () => {
    const { functions } = extractApiWhitelist(FIXTURE_API_MD);
    for (const fn of ["axis_x", "axis_y", "screen"]) {
      assert.ok(functions.has(fn), `missing bare entry: ${fn}`);
    }
  });

  it("always seeds lifecycle hooks", () => {
    const { functions } = extractApiWhitelist("");
    for (const fn of ["_init", "_start", "_ready", "_update", "_draw"]) {
      assert.ok(functions.has(fn), `missing lifecycle: ${fn}`);
    }
  });

  it("captures constants from markdown table", () => {
    const { constants } = extractApiWhitelist(FIXTURE_API_MD);
    for (const c of ["SCREEN_W", "SCREEN_H", "COLORS"]) {
      assert.ok(constants.has(c), `missing constant: ${c}`);
    }
  });

  it("ignores h2 section headings (## ...)", () => {
    const { functions } = extractApiWhitelist(FIXTURE_API_MD);
    assert.ok(!functions.has("Graphics"));
    assert.ok(!functions.has("Input"));
  });

  it("returns empty sets for non-string input", () => {
    const out = extractApiWhitelist(null);
    assert.equal(out.functions.size, 5); // lifecycle hooks
    assert.equal(out.constants.size, 0);
  });
});

const WL = extractApiWhitelist(FIXTURE_API_MD);

describe("lintApiCompliance — flags unknown calls", () => {
  it("flags a hallucinated function name", () => {
    const code = `
function _draw()
  local scr = screen()
  circle(scr, 80, 60, 10, 1)
end`;
    const v = lintApiCompliance(code, WL);
    assert.equal(v.length, 1);
    assert.equal(v[0].name, "circle");
  });

  it("reports line numbers", () => {
    const code = `function _draw()
  scrolltext(0, "hi")
end`;
    const v = lintApiCompliance(code, WL);
    assert.equal(v[0].name, "scrolltext");
    assert.equal(v[0].line, 2);
  });

  it("flags multiple distinct unknowns once each", () => {
    const code = `
function _draw()
  pset(0, 0, 0, 1)
  pset(0, 1, 1, 1)
  scrolltext(0, "hi")
end`;
    const v = lintApiCompliance(code, WL);
    const names = v.map((x) => x.name).sort();
    assert.deepEqual(names, ["pset", "scrolltext"]);
  });
});

describe("lintApiCompliance — does not flag valid code", () => {
  it("passes a typical bouncing-ball game", () => {
    const code = `
local x, y = 80, 60
local dx, dy = 1, 1

function _init() mode(4) end

function _draw()
  local scr = screen()
  cls(scr, 0)
  circf(scr, x, y, 5, 15)
  text(scr, "HELLO", 10, 10, 15)
end

function _update()
  x = x + dx
  y = y + dy
  if x < 0 or x > SCREEN_W then dx = -dx end
  if y < 0 or y > SCREEN_H then dy = -dy end
  if btnp("a") then dx, dy = 0, 0 end
end`;
    assert.deepEqual(lintApiCompliance(code, WL), []);
  });

  it("does not flag user-defined helpers", () => {
    const code = `
local function spawn(x, y)
  return { x = x, y = y }
end

function _update()
  local p = spawn(10, 20)
end`;
    assert.deepEqual(lintApiCompliance(code, WL), []);
  });

  it("does not flag Lua keywords / builtins", () => {
    const code = `
function _update()
  for i = 1, 10 do
    print("hello")
    assert(i > 0)
    local t = type(i)
  end
end`;
    assert.deepEqual(lintApiCompliance(code, WL), []);
  });

  it("does not flag method calls on tables", () => {
    const code = `
local t = {}
function t.foo() end
function t:bar() end

function _update()
  t.foo()
  t:bar()
  math.floor(1.5)
  string.format("%d", 5)
end`;
    assert.deepEqual(lintApiCompliance(code, WL), []);
  });

  it("does not flag scene-callback names (game_update, title_init)", () => {
    const code = `
function _update()
  if some_condition then
    title_update()
    game_init()
  end
end`;
    const v = lintApiCompliance(code, WL);
    // some_condition is not a call site (no parens)
    assert.deepEqual(v, []);
  });

  it("does not flag identifiers in comments / strings", () => {
    const code = `
-- circle(scr, 1, 2, 3) is wrong; use circ instead
function _draw()
  text(0, "circle(0,0,0)", 10, 10, 1)
end`;
    assert.deepEqual(lintApiCompliance(code, WL), []);
  });

  it("does not flag block-comment content", () => {
    const code = `
--[[
  scrolltext(0, "old API")
  pset(0, 0, 0, 1)
]]
function _draw()
  cls(0)
end`;
    assert.deepEqual(lintApiCompliance(code, WL), []);
  });

  it("does not flag long-string content", () => {
    const code = `
local doc = [[
  use circle(x, y, r) -- deprecated
]]
function _draw() cls(0) end`;
    assert.deepEqual(lintApiCompliance(code, WL), []);
  });

  it("does not flag function parameters being called", () => {
    const code = `
local function each(list, fn)
  for i, v in ipairs(list) do
    fn(v)
  end
end`;
    assert.deepEqual(lintApiCompliance(code, WL), []);
  });

  it("does not flag local variables being called", () => {
    const code = `
local handler = function(x) return x end

function _update()
  handler(5)
end`;
    assert.deepEqual(lintApiCompliance(code, WL), []);
  });

  it("does not flag multi-local with one being a function", () => {
    const code = `
local a, b, fn = 1, 2, function(x) return x * 2 end

function _update()
  fn(a + b)
end`;
    assert.deepEqual(lintApiCompliance(code, WL), []);
  });

  it("returns [] for empty / non-string input", () => {
    assert.deepEqual(lintApiCompliance("", WL), []);
    assert.deepEqual(lintApiCompliance(null, WL), []);
    assert.deepEqual(lintApiCompliance(undefined, WL), []);
  });

  it("returns [] when whitelist is missing (fail-open)", () => {
    const code = `function _draw() circ(0, 0, 0, 5, 1) end`;
    assert.deepEqual(lintApiCompliance(code, null), []);
    assert.deepEqual(lintApiCompliance(code, {}), []);
  });
});

describe("lintApiCompliance — cross-file project globals", () => {
  it("flags a cross-file helper when no projectDefined is provided", () => {
    // title.lua calls draw_stickman() which lives in main.lua. Without
    // the project-wide scan, this looks like a hallucinated call.
    const titleLua = `
function title_draw()
  local scr = screen()
  cls(scr, 0)
  draw_stickman(scr, 80, 60)
end`;
    const v = lintApiCompliance(titleLua, WL);
    assert.equal(v.length, 1);
    assert.equal(v[0].name, "draw_stickman");
  });

  it("does NOT flag the same helper when projectDefined includes it", () => {
    const titleLua = `
function title_draw()
  local scr = screen()
  cls(scr, 0)
  draw_stickman(scr, 80, 60)
end`;
    const projectDefined = new Set(["draw_stickman"]);
    assert.deepEqual(lintApiCompliance(titleLua, WL, { projectDefined }), []);
  });

  it("collectFileDefinedNames extracts global functions from main.lua", () => {
    const mainLua = `
function C(r, g, b) return r * 36 + g * 6 + b end

function draw_stickman(scr, x, y)
  circ(scr, x, y, 3, 15)
end

local function private_helper() end

helper_var = 5
local local_var = 10
`;
    const names = collectFileDefinedNames(mainLua);
    assert.ok(names.has("C"));
    assert.ok(names.has("draw_stickman"));
    assert.ok(names.has("private_helper")); // local but still file-scope, OK
    assert.ok(names.has("helper_var"));
    assert.ok(names.has("local_var"));
  });

  it("real-world scenario: main defines, scene calls", () => {
    const mainLua = `
function C(idx) return idx end
function draw_stickman(scr, x, y) circ(scr, x, y, 5, 15) end
function _init() mode(4) end
function _draw() local scr = screen() cls(scr, 0) end
`;
    const playLua = `
function play_update()
  if btnp("a") then go("title") end
end
function play_draw()
  local scr = screen()
  cls(scr, 0)
  draw_stickman(scr, 80, 60)
  text(scr, "P1", 10, 10, C(15))
end`;
    const projectDefined = collectFileDefinedNames(mainLua);
    assert.deepEqual(lintApiCompliance(playLua, WL, { projectDefined }), []);
  });

  it("ignores non-Set projectDefined gracefully", () => {
    const code = `function _draw() unknown_fn() end`;
    const v = lintApiCompliance(code, WL, { projectDefined: ["unknown_fn"] });
    // arrays are not Sets, so projectDefined is ignored → still flagged.
    assert.equal(v.length, 1);
    assert.equal(v[0].name, "unknown_fn");
  });
});
