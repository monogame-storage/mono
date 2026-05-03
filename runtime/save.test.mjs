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
    b.write("g", '{"score":42,"name":"a"}');
    assert.deepEqual(b.read("g"), { score: 42, name: "a" });
  });

  it("isolates cartIds", () => {
    const b = new MonoSave.MemoryBackend();
    b.write("a", '{"v":1}');
    b.write("b", '{"v":2}');
    assert.deepEqual(b.read("a"), { v: 1 });
    assert.deepEqual(b.read("b"), { v: 2 });
  });

  it("clear removes the bucket", () => {
    const b = new MonoSave.MemoryBackend();
    b.write("g", '{"v":1}');
    b.clear("g");
    assert.deepEqual(b.read("g"), {});
  });

  it("returns a deep copy on read so callers can't mutate stored state", () => {
    const b = new MonoSave.MemoryBackend();
    b.write("g", '{"nested":{"x":1}}');
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

describe("validateKey", () => {
  it("accepts simple alphanumerics", () => {
    assert.doesNotThrow(() => MonoSave.validateKey("hi_score"));
    assert.doesNotThrow(() => MonoSave.validateKey("a"));
  });

  it("accepts max-length key", () => {
    assert.doesNotThrow(() => MonoSave.validateKey("k".repeat(MonoSave.MAX_KEY_LEN)));
  });

  it("rejects empty string", () => {
    assert.throws(() => MonoSave.validateKey(""), /save: invalid key/);
  });

  it("rejects non-string", () => {
    assert.throws(() => MonoSave.validateKey(42), /save: invalid key/);
    assert.throws(() => MonoSave.validateKey(null), /save: invalid key/);
    assert.throws(() => MonoSave.validateKey(undefined), /save: invalid key/);
  });

  it("rejects > MAX_KEY_LEN", () => {
    assert.throws(
      () => MonoSave.validateKey("k".repeat(MonoSave.MAX_KEY_LEN + 1)),
      /save: invalid key/
    );
  });

  it("rejects keys containing NUL", () => {
    assert.throws(() => MonoSave.validateKey("a\u0000b"), /save: invalid key/);
  });

  it("rejects keys containing whitespace", () => {
    assert.throws(() => MonoSave.validateKey("a b"), /save: invalid key/);
    assert.throws(() => MonoSave.validateKey("a\tb"), /save: invalid key/);
    assert.throws(() => MonoSave.validateKey("a\nb"), /save: invalid key/);
  });
});

describe("WebBackend — localStorage path", () => {
  // Minimal fake localStorage that Node tests can use.
  function makeFakeStorage() {
    const map = new Map();
    return {
      getItem: (k) => map.has(k) ? map.get(k) : null,
      setItem: (k, v) => { map.set(k, String(v)); },
      removeItem: (k) => { map.delete(k); },
      // Expose for assertions only:
      _entries: () => Array.from(map.entries()),
    };
  }

  let storage;
  beforeEach(() => { storage = makeFakeStorage(); });

  it("read returns {} for a missing entry", () => {
    const b = new MonoSave.WebBackend({ storage });
    assert.deepEqual(b.read("g"), {});
  });

  it("write stores under the spec'd key", () => {
    const b = new MonoSave.WebBackend({ storage });
    b.write("g", '{"v":1}');
    assert.deepEqual(storage._entries(), [["mono:save:g", '{"v":1}']]);
  });

  it("read deserializes a previously-written bucket", () => {
    const b = new MonoSave.WebBackend({ storage });
    b.write("g", '{"score":7}');
    assert.deepEqual(b.read("g"), { score: 7 });
  });

  it("isolates cartIds via key prefix", () => {
    const b = new MonoSave.WebBackend({ storage });
    b.write("a", '{"v":1}');
    b.write("b", '{"v":2}');
    assert.deepEqual(b.read("a"), { v: 1 });
    assert.deepEqual(b.read("b"), { v: 2 });
  });

  it("clear removes the entry entirely", () => {
    const b = new MonoSave.WebBackend({ storage });
    b.write("g", '{"v":1}');
    b.clear("g");
    assert.deepEqual(storage._entries(), []);
  });

  it("recovers from a corrupt entry by returning {} and warning once", () => {
    storage.setItem("mono:save:g", "{not json");
    let warnings = 0;
    const warn = () => { warnings++; };
    const b = new MonoSave.WebBackend({ storage, warn });
    assert.deepEqual(b.read("g"), {});
    assert.deepEqual(b.read("g"), {});  // second read does not re-warn
    assert.equal(warnings, 1);
  });
});

describe("WebBackend — native bridge path", () => {
  function makeFakeBridge() {
    const map = new Map();
    return {
      read: (cartId) => map.get(cartId) || "",
      write: (cartId, json) => { map.set(cartId, json); return true; },
      clear: (cartId) => { map.delete(cartId); },
      _entries: () => Array.from(map.entries()),
    };
  }

  it("uses the bridge when present and ignores storage", () => {
    const bridge = makeFakeBridge();
    const storage = { getItem: () => "SHOULD_NOT_BE_READ", setItem: () => {}, removeItem: () => {} };
    const b = new MonoSave.WebBackend({ storage, bridge });
    b.write("g", '{"v":1}');
    assert.deepEqual(bridge._entries(), [["g", '{"v":1}']]);
    assert.deepEqual(b.read("g"), { v: 1 });
  });

  it("write throws 'backend write failed' when bridge.write returns false", () => {
    const bridge = {
      read: () => "",
      write: () => false,
      clear: () => {},
    };
    const b = new MonoSave.WebBackend({ bridge });
    assert.throws(() => b.write("g", '{"v":1}'), /save: backend write failed/);
  });

  it("write surfaces the underlying storage error message", () => {
    const storage = {
      getItem: () => null,
      setItem: () => { throw new Error("QuotaExceededError"); },
      removeItem: () => {},
    };
    const b = new MonoSave.WebBackend({ storage, bridge: null });
    assert.throws(() => b.write("g", '{"v":1}'), /save: backend write failed: QuotaExceededError/);
  });

  it("clear throws when no transport is configured", () => {
    const b = new MonoSave.WebBackend({ storage: null, bridge: null });
    assert.throws(() => b.clear("g"), /save: backend write failed/);
  });

  it("write throws when no transport is configured", () => {
    const b = new MonoSave.WebBackend({ storage: null, bridge: null });
    assert.throws(() => b.write("g", '{"v":1}'), /save: backend write failed/);
  });
});

describe("WebBackend — keyPrefix option", () => {
  function makeFakeStorage() {
    const map = new Map();
    return {
      getItem: (k) => map.has(k) ? map.get(k) : null,
      setItem: (k, v) => { map.set(k, String(v)); },
      removeItem: (k) => { map.delete(k); },
      _entries: () => Array.from(map.entries()),
    };
  }

  it("defaults to 'mono:save:' when no keyPrefix is provided", () => {
    const storage = makeFakeStorage();
    const b = new MonoSave.WebBackend({ storage });
    b.write("g", '{"v":1}');
    assert.deepEqual(storage._entries(), [["mono:save:g", '{"v":1}']]);
  });

  it("uses a custom keyPrefix when supplied", () => {
    const storage = makeFakeStorage();
    const b = new MonoSave.WebBackend({ storage, keyPrefix: "mono:save:abc:" });
    b.write("g", '{"v":1}');
    assert.deepEqual(storage._entries(), [["mono:save:abc:g", '{"v":1}']]);
  });

  it("two backends with different prefixes do not collide", () => {
    const storage = makeFakeStorage();
    const a = new MonoSave.WebBackend({ storage, keyPrefix: "mono:save:" });
    const u = new MonoSave.WebBackend({ storage, keyPrefix: "mono:save:user1:" });
    a.write("hi", '{"a":1}');
    u.write("hi", '{"a":2}');
    assert.deepEqual(a.read("hi"), { a: 1 });
    assert.deepEqual(u.read("hi"), { a: 2 });
  });

  it("clear respects the prefix", () => {
    const storage = makeFakeStorage();
    const a = new MonoSave.WebBackend({ storage, keyPrefix: "mono:save:" });
    const u = new MonoSave.WebBackend({ storage, keyPrefix: "mono:save:user1:" });
    a.write("hi", '{"a":1}');
    u.write("hi", '{"a":2}');
    u.clear("hi");
    assert.deepEqual(a.read("hi"), { a: 1 });    // anon untouched
    assert.deepEqual(u.read("hi"), {});          // user1 cleared
  });
});

describe("CloudBackend — constructor + read happy path", () => {
  function makeFakeStorage() {
    const map = new Map();
    return {
      getItem: (k) => map.has(k) ? map.get(k) : null,
      setItem: (k, v) => { map.set(k, String(v)); },
      removeItem: (k) => { map.delete(k); },
      _entries: () => Array.from(map.entries()),
    };
  }

  it("calls GET <apiUrl>/save/<cartId> with the bearer token", async () => {
    const calls = [];
    const fetchFn = async (url, init) => {
      calls.push({ url, init });
      return new Response(JSON.stringify({ bucket: { hi: 7 } }), { status: 200 });
    };
    const storage = makeFakeStorage();
    const b = new MonoSave.CloudBackend({
      uid: "user1",
      getToken: async () => "TOKEN",
      apiUrl: "https://api.example.com",
      fetch: fetchFn,
      storage,
    });
    const out = await b.read("demo:bounce");
    assert.deepEqual(out, { hi: 7 });
    assert.equal(calls.length, 1);
    assert.equal(calls[0].url, "https://api.example.com/save/demo%3Abounce");
    assert.equal(calls[0].init.method, "GET");
    assert.equal(calls[0].init.headers.Authorization, "Bearer TOKEN");
  });

  it("writes the returned bucket to the per-uid mirror", async () => {
    const fetchFn = async () =>
      new Response(JSON.stringify({ bucket: { hi: 7 } }), { status: 200 });
    const storage = makeFakeStorage();
    const b = new MonoSave.CloudBackend({
      uid: "user1",
      getToken: async () => "TOKEN",
      apiUrl: "https://api.example.com",
      fetch: fetchFn,
      storage,
    });
    await b.read("demo:bounce");
    const entries = storage._entries();
    assert.equal(entries.length, 1);
    assert.equal(entries[0][0], "mono:save:user1:demo:bounce");
    assert.deepEqual(JSON.parse(entries[0][1]), { hi: 7 });
  });
});

describe("CloudBackend — read failure paths", () => {
  function makeFakeStorage() {
    const map = new Map();
    return {
      getItem: (k) => map.has(k) ? map.get(k) : null,
      setItem: (k, v) => { map.set(k, String(v)); },
      removeItem: (k) => { map.delete(k); },
      _entries: () => Array.from(map.entries()),
    };
  }

  it("returns {} on 404 when no anonymous mirror exists", async () => {
    const fetchFn = async () => new Response(null, { status: 404 });
    const storage = makeFakeStorage();
    const b = new MonoSave.CloudBackend({
      uid: "u1", getToken: async () => "T", apiUrl: "https://x",
      fetch: fetchFn, storage,
    });
    assert.deepEqual(await b.read("demo:bounce"), {});
  });

  it("falls back to per-uid mirror on network error", async () => {
    const storage = makeFakeStorage();
    storage.setItem("mono:save:u1:demo:bounce", '{"hi":99}');
    const fetchFn = async () => { throw new Error("offline"); };
    const b = new MonoSave.CloudBackend({
      uid: "u1", getToken: async () => "T", apiUrl: "https://x",
      fetch: fetchFn, storage,
    });
    assert.deepEqual(await b.read("demo:bounce"), { hi: 99 });
  });

  it("returns {} and warns once on 401", async () => {
    const fetchFn = async () => new Response(null, { status: 401 });
    const storage = makeFakeStorage();
    const warnings = [];
    const b = new MonoSave.CloudBackend({
      uid: "u1", getToken: async () => "T", apiUrl: "https://x",
      fetch: fetchFn, storage, warn: (m) => warnings.push(m),
    });
    assert.deepEqual(await b.read("demo:bounce"), {});
    assert.equal(warnings.length, 1);
    assert.match(warnings[0], /401/);
  });

  it("after 401 the backend is auth-dead (writes/clears no-op)", async () => {
    // We won't fully exercise write yet (Task 8) — just verify the flag.
    const fetchFn = async () => new Response(null, { status: 401 });
    const b = new MonoSave.CloudBackend({
      uid: "u1", getToken: async () => "T", apiUrl: "https://x",
      fetch: fetchFn, storage: makeFakeStorage(), warn: () => {},
    });
    await b.read("demo:bounce");
    assert.equal(b._authDead, true);   // internal flag, exposed for test introspection
  });
});

describe("CloudBackend — migration on 404 + anonymous mirror", () => {
  function makeFakeStorage() {
    const map = new Map();
    return {
      getItem: (k) => map.has(k) ? map.get(k) : null,
      setItem: (k, v) => { map.set(k, String(v)); },
      removeItem: (k) => { map.delete(k); },
      _entries: () => Array.from(map.entries()),
    };
  }

  it("returns the anonymous bucket on 404 and writes it to the per-uid mirror", async () => {
    const storage = makeFakeStorage();
    storage.setItem("mono:save:demo:bounce", '{"hi":42}');   // anon mirror
    let putBody = null;
    const fetchFn = async (url, init) => {
      if (init.method === "GET") return new Response(null, { status: 404 });
      if (init.method === "PUT") { putBody = init.body; return new Response(null, { status: 204 }); }
      throw new Error("unexpected method");
    };
    const b = new MonoSave.CloudBackend({
      uid: "u1", getToken: async () => "T", apiUrl: "https://x",
      fetch: fetchFn, storage,
      // Inject setTimeout that runs immediately so the migration push happens synchronously for the test.
      setTimeout: (fn) => { fn(); return 0; },
      clearTimeout: () => {},
    });
    const out = await b.read("demo:bounce");
    assert.deepEqual(out, { hi: 42 });

    // Per-uid mirror now has the migrated data.
    assert.equal(storage.getItem("mono:save:u1:demo:bounce"), '{"hi":42}');

    // Anonymous mirror is preserved.
    assert.equal(storage.getItem("mono:save:demo:bounce"), '{"hi":42}');

    // Migration push was sent.
    assert.ok(putBody, "expected a PUT to be issued for migration");
    assert.deepEqual(JSON.parse(putBody), { bucket: { hi: 42 } });
  });

  it("returns {} on 404 when anonymous mirror is corrupt", async () => {
    const storage = makeFakeStorage();
    storage.setItem("mono:save:demo:bounce", "{not json");
    const fetchFn = async () => new Response(null, { status: 404 });
    const b = new MonoSave.CloudBackend({
      uid: "u1", getToken: async () => "T", apiUrl: "https://x",
      fetch: fetchFn, storage, warn: () => {},
      setTimeout: (fn) => { fn(); return 0; }, clearTimeout: () => {},
    });
    assert.deepEqual(await b.read("demo:bounce"), {});
  });
});
