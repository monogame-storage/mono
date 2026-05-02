// Unit tests for runtime/save.js — validation, serialization, and three backends.
// Run: node --test runtime/save.test.mjs
import { describe, it, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const MonoSave = require("./save.js");

describe("MemoryBackend", () => {
  it("starts empty for any cartId", () => {
    const b = new MonoSave.MemoryBackend();
    assert.deepEqual(b.read("game1"), {});
    assert.deepEqual(b.read("game2"), {});
  });

  it("round-trips a bucket", () => {
    const b = new MonoSave.MemoryBackend();
    b.write("g", { score: 42, name: "a" });
    assert.deepEqual(b.read("g"), { score: 42, name: "a" });
  });

  it("isolates cartIds", () => {
    const b = new MonoSave.MemoryBackend();
    b.write("a", { v: 1 });
    b.write("b", { v: 2 });
    assert.deepEqual(b.read("a"), { v: 1 });
    assert.deepEqual(b.read("b"), { v: 2 });
  });

  it("clear removes the bucket", () => {
    const b = new MonoSave.MemoryBackend();
    b.write("g", { v: 1 });
    b.clear("g");
    assert.deepEqual(b.read("g"), {});
  });

  it("returns a deep copy on read so callers can't mutate stored state", () => {
    const b = new MonoSave.MemoryBackend();
    b.write("g", { nested: { x: 1 } });
    const out = b.read("g");
    out.nested.x = 999;
    assert.deepEqual(b.read("g"), { nested: { x: 1 } });
  });
});
