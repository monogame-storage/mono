// Engine-primitive overwrite lint — agent write_file harness. The
// classic regression: `function touch_start(x, y) ... end` shadows the
// polling primitive and silently breaks touch input. These tests lock
// down the regex coverage so a future tweak doesn't accidentally let
// the pattern through.
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { lintEnginePrimitiveOverwrite, ENGINE_GLOBALS } from "../src/lib/lint.js";

describe("lintEnginePrimitiveOverwrite — flagged patterns", () => {
  it("flags a global function decl shadowing an engine primitive", () => {
    const code = "function touch_start(x, y)\n  spawn_particles(x, y)\nend";
    assert.match(lintEnginePrimitiveOverwrite(code), /touch_start/);
  });

  it("flags assignment to an engine global", () => {
    assert.match(lintEnginePrimitiveOverwrite("frame = 0"), /frame/);
  });

  it("flags indented assignment", () => {
    assert.match(lintEnginePrimitiveOverwrite("  touch_start = nil"), /touch_start/);
  });

  it("returns the FIRST violation (deterministic)", () => {
    const code = "function touch_start(x, y) end\nfunction touch_end(x, y) end";
    const result = lintEnginePrimitiveOverwrite(code);
    assert.match(result, /touch_start/);
  });
});

describe("lintEnginePrimitiveOverwrite — passes legitimate code", () => {
  it("allows polling usage of touch_start", () => {
    const code = "if touch_start() then\n  local x, y = touch_pos(1)\nend";
    assert.equal(lintEnginePrimitiveOverwrite(code), null);
  });

  it("allows scene-prefixed names (game_touch_start)", () => {
    assert.equal(lintEnginePrimitiveOverwrite("function game_touch_start(x, y)\nend"), null);
  });

  it("allows local function with the same name", () => {
    assert.equal(lintEnginePrimitiveOverwrite("local function touch_start(x, y)\nend"), null);
  });

  it("allows local variable shadowing", () => {
    assert.equal(lintEnginePrimitiveOverwrite("local time = os.time()"), null);
  });

  it("ignores commented-out violations", () => {
    assert.equal(lintEnginePrimitiveOverwrite("-- function touch_start(x, y)"), null);
  });

  it("allows method on object (function obj:touch_start)", () => {
    assert.equal(lintEnginePrimitiveOverwrite("function obj:touch_start(x)\nend"), null);
  });

  it("allows calling an engine primitive without redefining", () => {
    const code = "function foo()\n  return touch_start()\nend";
    assert.equal(lintEnginePrimitiveOverwrite(code), null);
  });

  it("returns null for empty / non-string input", () => {
    assert.equal(lintEnginePrimitiveOverwrite(""), null);
    assert.equal(lintEnginePrimitiveOverwrite(null), null);
    assert.equal(lintEnginePrimitiveOverwrite(undefined), null);
    assert.equal(lintEnginePrimitiveOverwrite(42), null);
  });
});

describe("ENGINE_GLOBALS", () => {
  it("includes the input polling primitives", () => {
    for (const k of ["btn", "btnp", "btnr", "touch_start", "touch_end", "touch_pos"]) {
      assert.ok(ENGINE_GLOBALS.includes(k), `missing: ${k}`);
    }
  });

  it("includes scene + draw + audio primitives", () => {
    for (const k of ["go", "scene_name", "cls", "rectf", "text", "note", "tone"]) {
      assert.ok(ENGINE_GLOBALS.includes(k), `missing: ${k}`);
    }
  });

  it("has no duplicate entries", () => {
    assert.equal(new Set(ENGINE_GLOBALS).size, ENGINE_GLOBALS.length);
  });
});
