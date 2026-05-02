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

describe("serializeBucket — happy paths", () => {
  it("serializes primitives", () => {
    assert.equal(
      MonoSave.serializeBucket({ a: 1, b: "hi", c: true, d: null }),
      '{"a":1,"b":"hi","c":true,"d":null}'
    );
  });

  it("serializes nested objects and arrays", () => {
    const out = MonoSave.serializeBucket({ t: { x: [1, 2, 3], y: { z: "ok" } } });
    assert.equal(out, '{"t":{"x":[1,2,3],"y":{"z":"ok"}}}');
  });

  it("serializes a bucket of exactly QUOTA_BYTES", () => {
    // Build a string that, with the JSON wrapper, lands on exactly 65536 bytes.
    // Wrapper: {"k":"<value>"} = 8 chars + value length.
    const value = "x".repeat(MonoSave.QUOTA_BYTES - 8);
    const out = MonoSave.serializeBucket({ k: value });
    assert.equal(out.length, MonoSave.QUOTA_BYTES);
  });
});

describe("serializeBucket — rejection messages", () => {
  it("rejects functions", () => {
    assert.throws(
      () => MonoSave.serializeBucket({ f: () => 1 }),
      /save: unserializable function/
    );
  });

  it("rejects undefined values", () => {
    assert.throws(
      () => MonoSave.serializeBucket({ u: undefined }),
      /save: unserializable undefined/
    );
  });

  it("rejects NaN", () => {
    assert.throws(
      () => MonoSave.serializeBucket({ n: NaN }),
      /save: unserializable NaN\/Inf/
    );
  });

  it("rejects Infinity", () => {
    assert.throws(
      () => MonoSave.serializeBucket({ n: Infinity }),
      /save: unserializable NaN\/Inf/
    );
  });

  it("rejects -Infinity", () => {
    assert.throws(
      () => MonoSave.serializeBucket({ n: -Infinity }),
      /save: unserializable NaN\/Inf/
    );
  });

  it("rejects BigInt", () => {
    assert.throws(
      () => MonoSave.serializeBucket({ b: 1n }),
      /save: unserializable bigint/
    );
  });

  it("rejects cycles", () => {
    const a = { x: 1 };
    a.self = a;
    assert.throws(
      () => MonoSave.serializeBucket({ root: a }),
      /save: cycle detected/
    );
  });

  it("accepts depth 16 (16 nested levels)", () => {
    let v = { leaf: 1 };
    for (let i = 0; i < 15; i++) v = { inner: v };
    // Total depth = 16 (root + 15 wrappers); leaf is at depth 16.
    assert.doesNotThrow(() => MonoSave.serializeBucket({ root: v }));
  });

  it("rejects depth 17", () => {
    let v = { leaf: 1 };
    for (let i = 0; i < 16; i++) v = { inner: v };
    assert.throws(
      () => MonoSave.serializeBucket({ root: v }),
      /save: too deep/
    );
  });

  it("rejects bucket exceeding QUOTA_BYTES by one byte", () => {
    const value = "x".repeat(MonoSave.QUOTA_BYTES - 7);
    assert.throws(
      () => MonoSave.serializeBucket({ k: value }),
      /save: quota exceeded \(65537 bytes > 65536\)/
    );
  });

  it("rejects Date instances", () => {
    assert.throws(
      () => MonoSave.serializeBucket({ d: new Date(0) }),
      /save: unserializable Date/
    );
  });

  it("rejects Map instances", () => {
    assert.throws(
      () => MonoSave.serializeBucket({ m: new Map() }),
      /save: unserializable Map/
    );
  });

  it("rejects Set instances", () => {
    assert.throws(
      () => MonoSave.serializeBucket({ s: new Set() }),
      /save: unserializable Set/
    );
  });

  it("rejects RegExp instances", () => {
    assert.throws(
      () => MonoSave.serializeBucket({ r: /abc/ }),
      /save: unserializable RegExp/
    );
  });

  it("accepts Object.create(null) (null-proto plain object)", () => {
    const o = Object.create(null);
    o.x = 1;
    assert.doesNotThrow(() => MonoSave.serializeBucket({ root: o }));
  });
});
