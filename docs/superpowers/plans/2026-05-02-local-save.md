# Local Save / `data_*` API — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a six-function Lua persistence API (`data_save`, `data_load`, `data_delete`, `data_has`, `data_keys`, `data_clear`) backed by per-cart isolated storage, with a 64KB hard cap, three backends (web localStorage, Android SharedPreferences via JS bridge, in-memory), and matching tests.

**Architecture:** New `runtime/save.js` (UMD classic script, mirrors `runtime/engine-bindings.js` packaging) defines a `Backend` interface plus three implementations and the validate-and-serialize pipeline. `engine-bindings.js` gains a `hooks.save` parameter and registers the six Lua globals. Each runner (`runtime/engine.js`, `dev/headless/mono-runner.js`, `dev/test-worker.js`, `dev/js/editor-play.js`, `play.html`) wires `cartId` and `saveBackend` through. Android adds a `MonoSaveBridge` Kotlin class registered as a `@JavascriptInterface` on the WebView.

**Tech Stack:** Wasmoon (Lua 5.4 in WASM), Vanilla JS classic scripts (no bundler), Node `node:test` for JS unit tests, `engine-test/test-*.lua` for Lua-driven tests, Kotlin + Android SharedPreferences.

**Spec:** `docs/superpowers/specs/2026-05-02-local-save-design.md`

**Conventions assumed by this plan:**
- `runtime/save.js` is a classic UMD script (CommonJS export when `module.exports` exists; `globalThis.MonoSave` otherwise) — exact mirror of `runtime/engine-bindings.js` lines 34-39.
- JS unit tests live in `cosmi/test/*.test.mjs` style. New file: `runtime/save.test.mjs` runs via `node --test runtime/save.test.mjs`. Use `node:test` + `node:assert/strict`. Use `import { createRequire } from "node:module"` if you need to load `runtime/save.js` as CommonJS.
- Lua tests follow `engine-test/test-*.lua` shape, executed via `engine-test/run.html?test=save` and added as a cell to `engine-test/index.html`'s grid.
- Cosmi lint tests: `cosmi/test/lint.test.mjs` via `node --test cosmi/test/`.

---

### Task 1: Scaffold `runtime/save.js` with `MemoryBackend`

**Files:**
- Create: `runtime/save.js`
- Create: `runtime/save.test.mjs`

This task lays the file down with a UMD wrapper and the simplest backend (`MemoryBackend`) so subsequent tasks have something to build on.

- [ ] **Step 1: Write the failing test for `MemoryBackend`**

Create `runtime/save.test.mjs`:

```js
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test runtime/save.test.mjs`
Expected: FAIL — `Cannot find module './save.js'`.

- [ ] **Step 3: Write minimal `runtime/save.js`**

Create `runtime/save.js`:

```js
/**
 * Mono Save — per-cart key/value persistence
 *
 * Loaded as a classic script (browser / Web Worker / Node) — same UMD
 * pattern as engine-bindings.js so `<script src>`, `importScripts()`,
 * and `require()` all work without a bundler.
 *
 * Public surface (exported via globalThis.MonoSave or module.exports):
 *   - MemoryBackend     — in-process bucket map, no persistence
 *   - WebBackend        — localStorage (auto-routes to native bridge if present)
 *   - serializeBucket   — validate + JSON.stringify with quota check
 *   - deserializeBucket — JSON.parse with safe fallback
 *   - QUOTA_BYTES, MAX_KEY_LEN, MAX_DEPTH — limits exposed for tests
 *
 * The bindings layer (engine-bindings.js) owns the in-memory cache and
 * the Lua globals. This file owns storage + validation only.
 */
(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else if (typeof self !== "undefined") self.MonoSave = api;
  else if (typeof globalThis !== "undefined") globalThis.MonoSave = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  const QUOTA_BYTES = 65536;
  const MAX_KEY_LEN = 64;
  const MAX_DEPTH = 16;

  // ── MemoryBackend — in-process Map keyed by cartId, JSON deep-copied
  // on every read/write so callers cannot mutate stored state by holding
  // on to a returned reference.
  class MemoryBackend {
    constructor() { this._buckets = new Map(); }
    read(cartId) {
      const stored = this._buckets.get(cartId);
      return stored ? JSON.parse(stored) : {};
    }
    write(cartId, bucket) {
      this._buckets.set(cartId, JSON.stringify(bucket));
    }
    clear(cartId) {
      this._buckets.delete(cartId);
    }
  }

  return {
    MemoryBackend,
    QUOTA_BYTES,
    MAX_KEY_LEN,
    MAX_DEPTH,
  };
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test runtime/save.test.mjs`
Expected: PASS — 5 tests for MemoryBackend.

- [ ] **Step 5: Commit**

```bash
git add runtime/save.js runtime/save.test.mjs
git commit -m "feat(save): scaffold runtime/save.js with MemoryBackend"
```

---

### Task 2: Add `serializeBucket` validation + quota

**Files:**
- Modify: `runtime/save.js`
- Modify: `runtime/save.test.mjs`

Adds the validate-and-serialize pipeline that bindings will use before every `write`. Throws on bad input with the exact messages from the spec.

- [ ] **Step 1: Write failing tests for `serializeBucket`**

Append to `runtime/save.test.mjs` after the `MemoryBackend` describe block:

```js
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
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test runtime/save.test.mjs`
Expected: FAIL — `MonoSave.serializeBucket is not a function`.

- [ ] **Step 3: Implement `serializeBucket` and `deserializeBucket`**

Replace the `return { MemoryBackend, ... }` block in `runtime/save.js` with the full implementation:

```js
  // ── Validate a value tree. Throws with the spec's exact messages on
  // any rejection. Walks before serializing so a partially-valid
  // bucket never lands in storage. The depth limit applies to
  // *object/array nesting only*; primitives (numbers, strings, bools,
  // null) never trigger "too deep" since they don't add structure.
  // The bucket itself is depth 0; a value directly in the bucket is
  // depth 1; a value one level deeper is depth 2; etc.
  function validateValue(v, depth, seen) {
    if (v === null) return;
    const t = typeof v;
    if (t === "boolean" || t === "string") return;
    if (t === "number") {
      if (!isFinite(v)) throw new Error("save: unserializable NaN/Inf");
      return;
    }
    if (t === "function") throw new Error("save: unserializable function");
    if (t === "undefined") throw new Error("save: unserializable undefined");
    if (t === "bigint") throw new Error("save: unserializable bigint");
    if (t !== "object") throw new Error("save: unserializable " + t);
    if (depth > MAX_DEPTH) throw new Error("save: too deep");
    if (seen.has(v)) throw new Error("save: cycle detected");
    seen.add(v);
    if (Array.isArray(v)) {
      for (let i = 0; i < v.length; i++) validateValue(v[i], depth + 1, seen);
    } else {
      for (const k of Object.keys(v)) validateValue(v[k], depth + 1, seen);
    }
    seen.delete(v);
  }

  // ── Serialize a bucket (a plain object whose top-level keys are the
  // game's saved keys). Validates first, then JSON.stringify's the
  // result, then enforces the quota in bytes (UTF-16 length is fine
  // for ASCII; for the 64KB cap we measure UTF-8 byte length).
  function serializeBucket(bucket) {
    validateValue(bucket, 0, new WeakSet());
    const json = JSON.stringify(bucket);
    const bytes = utf8ByteLength(json);
    if (bytes > QUOTA_BYTES) {
      throw new Error("save: quota exceeded (" + bytes + " bytes > " + QUOTA_BYTES + ")");
    }
    return json;
  }

  // ── Parse a serialized bucket. Returns {} on malformed input — the
  // caller should `console.warn` once when this happens.
  function deserializeBucket(json) {
    if (!json) return {};
    try {
      const parsed = JSON.parse(json);
      return (parsed && typeof parsed === "object" && !Array.isArray(parsed)) ? parsed : {};
    } catch {
      return {};
    }
  }

  function utf8ByteLength(s) {
    if (typeof TextEncoder !== "undefined") return new TextEncoder().encode(s).length;
    // Node < 12 / very old environments: fall back to manual count.
    let n = 0;
    for (let i = 0; i < s.length; i++) {
      const c = s.charCodeAt(i);
      if (c < 0x80) n += 1;
      else if (c < 0x800) n += 2;
      else if (c >= 0xd800 && c < 0xdc00) { n += 4; i++; }
      else n += 3;
    }
    return n;
  }
```

Update the `return` at the bottom to include the new exports:

```js
  return {
    MemoryBackend,
    serializeBucket,
    deserializeBucket,
    QUOTA_BYTES,
    MAX_KEY_LEN,
    MAX_DEPTH,
  };
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test runtime/save.test.mjs`
Expected: PASS — all `serializeBucket` cases plus prior `MemoryBackend` cases.

- [ ] **Step 5: Commit**

```bash
git add runtime/save.js runtime/save.test.mjs
git commit -m "feat(save): add serializeBucket validation + quota check"
```

---

### Task 3: Add `validateKey` and `WebBackend`

**Files:**
- Modify: `runtime/save.js`
- Modify: `runtime/save.test.mjs`

Adds the key validator (used by bindings to reject `data_save("", ...)` etc) and `WebBackend` — which auto-routes to `window.MonoSaveNative` when the Android bridge is present, otherwise uses `window.localStorage`.

- [ ] **Step 1: Write failing tests for `validateKey` and `WebBackend`**

Append to `runtime/save.test.mjs`:

```js
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
    b.write("g", { v: 1 });
    assert.deepEqual(storage._entries(), [["mono:save:g", '{"v":1}']]);
  });

  it("read deserializes a previously-written bucket", () => {
    const b = new MonoSave.WebBackend({ storage });
    b.write("g", { score: 7 });
    assert.deepEqual(b.read("g"), { score: 7 });
  });

  it("isolates cartIds via key prefix", () => {
    const b = new MonoSave.WebBackend({ storage });
    b.write("a", { v: 1 });
    b.write("b", { v: 2 });
    assert.deepEqual(b.read("a"), { v: 1 });
    assert.deepEqual(b.read("b"), { v: 2 });
  });

  it("clear removes the entry entirely", () => {
    const b = new MonoSave.WebBackend({ storage });
    b.write("g", { v: 1 });
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
    b.write("g", { v: 1 });
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
    assert.throws(() => b.write("g", { v: 1 }), /save: backend write failed/);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test runtime/save.test.mjs`
Expected: FAIL — `MonoSave.validateKey is not a function`, `MonoSave.WebBackend is not a constructor`.

- [ ] **Step 3: Implement `validateKey` and `WebBackend`**

Add to `runtime/save.js` (above the `return` block):

```js
  // ── Validate a save key. Throws with the spec's "save: invalid key"
  // message on any rejection. Whitespace check uses /\s/ (covers ASCII
  // space, tab, newline, form feed, vertical tab, carriage return).
  function validateKey(k) {
    if (typeof k !== "string") throw new Error("save: invalid key");
    if (k.length === 0 || k.length > MAX_KEY_LEN) throw new Error("save: invalid key");
    if (/\u0000/.test(k)) throw new Error("save: invalid key");
    if (/\s/.test(k)) throw new Error("save: invalid key");
  }

  // ── WebBackend — writes to localStorage by default. If the page has
  // a `MonoSaveNative` JS interface (injected by Android WebView), all
  // reads/writes/clears go through that instead so the OS keystore
  // (SharedPreferences on Android) is the source of truth. The
  // `bridge` and `storage` constructor options exist so the unit test
  // can inject fakes without touching real globals.
  class WebBackend {
    constructor(opts) {
      const o = opts || {};
      this._bridge =
        ("bridge" in o) ? o.bridge :
        (typeof globalThis !== "undefined" && globalThis.MonoSaveNative) ? globalThis.MonoSaveNative :
        null;
      this._storage =
        ("storage" in o) ? o.storage :
        (typeof globalThis !== "undefined" && globalThis.localStorage) ? globalThis.localStorage :
        null;
      this._warn = o.warn || ((typeof console !== "undefined") ? (m => console.warn(m)) : (() => {}));
      this._warnedFor = new Set();   // cartIds we've already warned about
    }
    _key(cartId) { return "mono:save:" + cartId; }
    read(cartId) {
      const raw = this._bridge ? this._bridge.read(cartId)
                : this._storage ? this._storage.getItem(this._key(cartId))
                : null;
      if (raw == null || raw === "") return {};
      try {
        const parsed = JSON.parse(raw);
        if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) return parsed;
      } catch {}
      // Either parse failed or shape was wrong — warn once per cart, then return blank.
      if (!this._warnedFor.has(cartId)) {
        this._warnedFor.add(cartId);
        this._warn("MonoSave: unparseable bucket for cart \"" + cartId + "\" — starting fresh");
      }
      return {};
    }
    write(cartId, bucket) {
      const json = JSON.stringify(bucket);
      if (this._bridge) {
        const ok = this._bridge.write(cartId, json);
        if (!ok) throw new Error("save: backend write failed");
        return;
      }
      if (this._storage) {
        try { this._storage.setItem(this._key(cartId), json); }
        catch (e) { throw new Error("save: backend write failed"); }
        return;
      }
      throw new Error("save: backend write failed");
    }
    clear(cartId) {
      if (this._bridge) { this._bridge.clear(cartId); return; }
      if (this._storage) { this._storage.removeItem(this._key(cartId)); return; }
    }
  }
```

Update the `return` block to include the new exports:

```js
  return {
    MemoryBackend,
    WebBackend,
    serializeBucket,
    deserializeBucket,
    validateKey,
    QUOTA_BYTES,
    MAX_KEY_LEN,
    MAX_DEPTH,
  };
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test runtime/save.test.mjs`
Expected: PASS — all `validateKey` and `WebBackend` cases plus prior cases.

- [ ] **Step 5: Commit**

```bash
git add runtime/save.js runtime/save.test.mjs
git commit -m "feat(save): add validateKey + WebBackend (storage / bridge auto-route)"
```

---

### Task 4: Wire `data_*` Lua globals into `engine-bindings.js`

**Files:**
- Modify: `runtime/engine-bindings.js` (binding signature + 6 globals)

The bindings layer owns the in-memory cache (single `bucket` object) and the six Lua globals. Each runner injects a backend instance via `hooks.save = { read, write, clear, cartId }`. The bindings:

1. Call `hooks.save.read(cartId)` once at bind time → seed `bucket`.
2. `data_load`/`data_has`/`data_keys` read from `bucket` directly.
3. `data_save`/`data_delete`/`data_clear` mutate `bucket`, then `serializeBucket` + `hooks.save.write(cartId, bucket)`.

If `hooks.save` is omitted, the bindings install the six globals as no-ops that throw a clear "save backend not configured" error so a misconfigured runner doesn't fail silently.

- [ ] **Step 1: Add the binding code**

In `runtime/engine-bindings.js`, locate the line right before `// ── Doc stubs for Lua-side wrappers` (currently around line 129). Insert this block immediately before it:

```js
    // ── Persistence (data_save / data_load / data_delete / data_has /
    // data_keys / data_clear). The runner supplies hooks.save with a
    // backend (read/write/clear) plus the cartId string. We hold the
    // bucket in JS-side memory so reads are zero-allocation and writes
    // are write-through. validateKey + serializeBucket throw on any
    // policy violation; those throws become Lua errors via Wasmoon.
    if (hooks.save) {
      const MonoSaveLib =
        (typeof globalThis !== "undefined" && globalThis.MonoSave) ? globalThis.MonoSave :
        (typeof self !== "undefined" && self.MonoSave) ? self.MonoSave :
        (typeof require === "function" ? require("./save.js") : null);
      if (!MonoSaveLib) throw new Error("MonoSave library not loaded");

      const backend = hooks.save.backend;
      const cartId = hooks.save.cartId;
      if (!backend) throw new Error("hooks.save.backend is required");
      if (typeof cartId !== "string" || !cartId) throw new Error("hooks.save.cartId must be a non-empty string");

      let bucket = backend.read(cartId);
      if (!bucket || typeof bucket !== "object" || Array.isArray(bucket)) bucket = {};

      function flush() {
        const json = MonoSaveLib.serializeBucket(bucket);
        backend.write(cartId, bucket);
        return json;
      }

      lua.global.set("data_save", (key, value) => {
        MonoSaveLib.validateKey(key);
        // Wasmoon presents Lua tables to JS as plain objects; JSON.stringify
        // (called inside serializeBucket) walks them like any other object.
        // Take a defensive deep copy via JSON round-trip so later mutations
        // to the Lua table don't reach into our cache.
        const next = Object.assign({}, bucket);
        next[key] = (value === undefined) ? null : JSON.parse(JSON.stringify(value));
        // serializeBucket runs validation on the candidate bucket; if it
        // throws (bad value, NaN, cycle, depth, quota), `bucket` is unchanged.
        MonoSaveLib.serializeBucket(next);
        bucket = next;
        backend.write(cartId, bucket);
      });

      lua.global.set("data_load", (key) => {
        MonoSaveLib.validateKey(key);
        const v = bucket[key];
        if (v === undefined) return null;
        // Return a fresh copy so Lua-side mutations don't reach into the cache.
        if (v !== null && typeof v === "object") return JSON.parse(JSON.stringify(v));
        return v;
      });

      lua.global.set("data_delete", (key) => {
        MonoSaveLib.validateKey(key);
        if (!Object.prototype.hasOwnProperty.call(bucket, key)) return false;
        const next = Object.assign({}, bucket);
        delete next[key];
        bucket = next;
        backend.write(cartId, bucket);
        return true;
      });

      lua.global.set("data_has", (key) => {
        MonoSaveLib.validateKey(key);
        return Object.prototype.hasOwnProperty.call(bucket, key);
      });

      lua.global.set("data_keys", () => {
        // Lua tables don't differentiate array/dict — Wasmoon converts a
        // JS array into a 1-indexed Lua sequence. Sort for determinism.
        return Object.keys(bucket).sort();
      });

      lua.global.set("data_clear", () => {
        bucket = {};
        backend.clear(cartId);
      });
    } else {
      // No save hook installed (legacy boot calls). Stub out the six
      // globals so a game's call surface fails loud instead of silent.
      const stub = () => { throw new Error("save: backend not configured"); };
      lua.global.set("data_save",   stub);
      lua.global.set("data_load",   stub);
      lua.global.set("data_delete", stub);
      lua.global.set("data_has",    stub);
      lua.global.set("data_keys",   stub);
      lua.global.set("data_clear",  stub);
    }
```

- [ ] **Step 2: Update the bindings docblock**

In `runtime/engine-bindings.js`, find the JSDoc block at lines 60-77 (the parameter list for `bind`). Add `hooks.save` documentation. Replace the existing block with:

```js
  /**
   * Register the shared API surface on a Lua instance.
   *
   * @param {object} lua   — Wasmoon Lua engine instance
   * @param {object} hooks — runner-specific callbacks
   *   hooks.input: {
   *     btn(k), btnp(k), btnr(k),          // bool
   *     touch(), touchStart(), touchEnd(), // bool
   *     touchCount(),                      // int
   *     touchPosX(i), touchPosY(i),        // int | false
   *     touchPosfX(i), touchPosfY(i),      // number | false
   *     swipe(),                           // "up"|"down"|"left"|"right"|false
   *     axisX(), axisY(),                  // number
   *   }
   *   hooks.cam: { getX(), getY() }
   *   hooks.scene: { current: string|null, pending: string|null }   // mutable
   *   hooks.modules: { "path/to.lua": "source", ... }               // optional
   *   hooks.save: { backend, cartId } | undefined                   // optional
   *     backend: MonoSave.MemoryBackend | MonoSave.WebBackend instance
   *     cartId:  non-empty string identifying the cart's save bucket
   *     If absent, data_* globals are installed as throwing stubs.
   */
```

- [ ] **Step 3: Verify nothing else broke**

Run: `node --test cosmi/test/`
Expected: PASS — existing cosmi tests still pass (we haven't changed cosmi yet).

There's no JS test invoking `MonoBindings.bind` directly; the wiring is verified end-to-end in the Lua test (Task 9). For now, just confirm the file parses by importing it indirectly:

Run: `node -e "require('./runtime/engine-bindings.js'); console.log('OK')"`
Expected: prints `OK`.

- [ ] **Step 4: Commit**

```bash
git add runtime/engine-bindings.js
git commit -m "feat(save): bind data_* Lua globals to MonoSave backend"
```

---

### Task 5: Accept `cartId` + `saveBackend` in `runtime/engine.js` `Mono.boot`

**Files:**
- Modify: `runtime/engine.js`

Threads the new boot options through to the bindings layer.

- [ ] **Step 1: Add MonoSave script load to `play.html` boot path expectation**

(No edit yet; tracking note.) `runtime/engine.js` will reference `globalThis.MonoSave`. Pages that use `engine.js` must include `runtime/save.js` before it. We'll update those pages in later tasks.

- [ ] **Step 2: Modify the `Bindings.bind` call in `runtime/engine.js`**

In `runtime/engine.js`, find the `await Bindings.bind(lua, { ... });` call (currently around lines 1083-1110). Right before that block, add backend resolution:

```js
    // ── Save backend resolution ──
    // opts.saveBackend ∈ "persistent" | "memory"; default depends on
    // whether cartId was supplied. A page that forgot to pass either
    // (e.g. legacy demo runners) gets memory + a generated cartId so
    // games that call data_save don't crash — saves just don't persist.
    let saveHook;
    {
      const SaveLib = (typeof globalThis !== "undefined" ? globalThis.MonoSave : null);
      if (SaveLib) {
        const cartId = opts.cartId || ("anon:" + Math.random().toString(36).slice(2, 10));
        const requested = opts.saveBackend || (opts.cartId ? "persistent" : "memory");
        if (requested === "persistent" && !opts.cartId) {
          throw new Error("Mono.boot: saveBackend=\"persistent\" requires opts.cartId");
        }
        const backend = (requested === "memory")
          ? new SaveLib.MemoryBackend()
          : new SaveLib.WebBackend();
        saveHook = { backend, cartId };
      }
    }
```

Then change the `Bindings.bind(lua, { ... })` call to pass `save: saveHook`:

```js
    await Bindings.bind(lua, {
      input: {
        // ... unchanged ...
      },
      cam: { getX: () => camX, getY: () => camY },
      scene: sceneRef,
      modules: opts.modules || {},
      save: saveHook,
    });
```

- [ ] **Step 3: Update boot doc-comment**

At the top of `runtime/engine.js`, lines 4-7, the example currently reads:

```js
 * Mono.boot("screen", { game: "main.lua", colors: 1 })
 *   colors: 1 (2色), 2 (4色), 4 (16色). Default: 1
 */
```

Replace with:

```js
 * Mono.boot("screen", { game: "main.lua", colors: 1, cartId: "myGame" })
 *   colors: 1 (2色), 2 (4色), 4 (16色). Default: 1
 *   cartId: string — required if saveBackend is "persistent" (the default
 *           when cartId is supplied). Used to scope data_save/data_load.
 *   saveBackend: "persistent" | "memory" — defaults to "persistent" when
 *           cartId is provided, "memory" otherwise.
 */
```

- [ ] **Step 4: Sanity-check parse**

Run: `node -e "require('./runtime/engine.js')"`
Expected: parses without ReferenceError. (It will not actually execute the engine because there's no DOM, but the script body is module-level safe.)

If the parse hits an unrelated module-level error (e.g. existing reference to `document`), the existing harness already tolerates that — confirm the new code is the only module-level addition.

- [ ] **Step 5: Commit**

```bash
git add runtime/engine.js
git commit -m "feat(save): wire cartId/saveBackend through Mono.boot"
```

---

### Task 6: Inject `MemoryBackend` in `dev/headless/mono-runner.js`

**Files:**
- Modify: `dev/headless/mono-runner.js`

The Node CLI test runner used by Cosmi's `/test` endpoint must always use the in-memory backend so tests never bleed save state.

- [ ] **Step 1: Load `runtime/save.js` and pass save hook**

In `dev/headless/mono-runner.js`, find the `const MonoBindings = loadRuntime("engine-bindings.js");` line (around line 57). Add immediately after:

```js
const MonoSave = loadRuntime("save.js");
```

Then find the `await MonoBindings.bind(lua, { ... });` call (around line 843) and change it to include the save hook:

```js
  await MonoBindings.bind(lua, {
    input: {
      // ... unchanged ...
    },
    cam: { getX: () => camX, getY: () => camY },
    scene: sceneRef,
    modules,
    save: { backend: new MonoSave.MemoryBackend(), cartId: "headless" },
  });
```

- [ ] **Step 2: Verify the runner still parses**

Run: `node -e "require('./dev/headless/mono-runner.js')"` — and adjust if it requires CLI args (depends on how the file is structured). If `mono-runner.js` runs immediately on load (not module-style), instead run a smoke command:

Run: `node dev/headless/mono-runner.js --help` (or whatever the existing invocation is per `dev/headless/mono-runner.js` top-of-file usage comment)
Expected: runs without crashing.

If there's no easy smoke-test path, run a known game:

Run: `node dev/headless/mono-runner.js demo/bounce` (or the established CLI form for this runner)
Expected: prior behavior — frames advance, no error from missing `data_*`.

- [ ] **Step 3: Commit**

```bash
git add dev/headless/mono-runner.js
git commit -m "feat(save): inject MemoryBackend in dev/headless mono-runner"
```

---

### Task 7: Inject `MemoryBackend` in `dev/test-worker.js`

**Files:**
- Modify: `dev/test-worker.js`

The Web Worker pre-publish smoke test runs in a sandbox that should never touch persistent storage.

- [ ] **Step 1: Load save and pass save hook**

In `dev/test-worker.js`, find the line that loads `engine-bindings.js` via `importScripts` (search for `engine-bindings`). Add a sibling `importScripts` for `save.js` immediately after it. The existing pattern is something like:

```js
importScripts("/runtime/engine-bindings.js");
```

Add:

```js
importScripts("/runtime/save.js");
```

Then find the `await self.MonoBindings.bind(lua, { ... });` call (around line 71) and add the save hook:

```js
  await self.MonoBindings.bind(lua, {
    input: {
      // ... unchanged ...
    },
    cam: { getX: () => camX, getY: () => camY },
    scene: sceneRef,
    modules,
    save: { backend: new self.MonoSave.MemoryBackend(), cartId: "smoke" },
  });
```

- [ ] **Step 2: Sanity-check via the dev editor**

Manually: open `dev/index.html`, edit a cart, watch the Play tab — the smoke test runs on edit. Confirm no console errors mentioning `MonoSave` or `data_*`.

- [ ] **Step 3: Commit**

```bash
git add dev/test-worker.js
git commit -m "feat(save): inject MemoryBackend in dev/test-worker.js"
```

---

### Task 8: Pass `cartId` from `dev/js/editor-play.js`

**Files:**
- Modify: `dev/js/editor-play.js`

The dev editor uses `state.currentGameId` (the R2 game ID) so save data is shared with `play.html?id=<gameId>`.

- [ ] **Step 1: Add cartId + saveBackend to the boot call**

In `dev/js/editor-play.js`, find the `Mono.boot("editor-screen", { ... })` call (around line 116). Change the options object to include `cartId` and `saveBackend`:

```js
  Mono.boot("editor-screen", {
    source: mainFile.content,
    colors: 4,
    noAutoFit: true,
    readFile: async (name) => fileMap[name] || "",
    modules: moduleMap,
    assets: state.currentAssets,
    cartId: state.currentGameId || "scratch",
    saveBackend: state.currentGameId ? "persistent" : "memory",
  })
```

The fallback to `"scratch"` + memory backend covers the brand-new-game-not-yet-saved-to-R2 case so the editor never crashes.

- [ ] **Step 2: Manual verification in the editor**

Open `dev/index.html`, load any saved game, hit Play. Open DevTools → Application → localStorage. After a `data_save("hi", 42)` triggered from the in-page game (or via the JS console: `Mono._lua.global.get("data_save")("hi", 42)` — replace with whatever exposed handle exists if any), confirm an entry `mono:save:<gameId>` appears.

If the `Mono._lua` handle isn't exposed, fall back to the simpler check: an editor reload should keep `data_load("hi") == 42`.

- [ ] **Step 3: Commit**

```bash
git add dev/js/editor-play.js
git commit -m "feat(save): pass cartId from editor-play to Mono.boot"
```

---

### Task 9: Pass `cartId` from `play.html`

**Files:**
- Modify: `play.html`

`play.html` decides cartId based on URL: R2 game → `gameId`; demo → `"demo:" + name`.

- [ ] **Step 1: Add `runtime/save.js` script tag**

Find the `<script src="/runtime/engine.js"></script>` line in `play.html`. Add immediately before it:

```html
<script src="/runtime/save.js"></script>
```

(The order matters — `save.js` must be loaded before `engine.js` so `globalThis.MonoSave` is set when `Mono.boot` runs.)

- [ ] **Step 2: Compute and pass cartId in both boot paths**

In `play.html`, find the published-game `Mono.boot("screen", { source: mainSrc, modules, assets, colors: 4, readFile: ... })` call (around line 168). Add `cartId: gameId` to the options:

```js
        await Mono.boot("screen", {
          source: mainSrc,
          modules: modules,
          assets: assets,
          colors: 4,
          readFile: function(name) {
            return modules[name] || textFiles[name] || null;
          },
          cartId: gameId,
        });
```

Find the demo-game boot call (around line 199):

```js
    Mono.boot("screen", { game: entry.path, colors: entry.colors }).then(...)
```

Change to:

```js
    Mono.boot("screen", {
      game: entry.path,
      colors: entry.colors,
      cartId: "demo:" + gameName,
    }).then(...)
```

- [ ] **Step 3: Manual verification**

Open `play.html?game=bounce` in a browser. Open DevTools console:

```js
Mono._lua.global.get("data_save")("test", 99);
Mono._lua.global.get("data_load")("test");  // → 99
```

Reload. Re-run `data_load("test")` — should still be 99 (persistent), and the localStorage entry under key `mono:save:demo:bounce` should hold `{"test":99}`.

- [ ] **Step 4: Commit**

```bash
git add play.html
git commit -m "feat(save): pass cartId from play.html to Mono.boot"
```

---

### Task 10: Add Lua test `engine-test/test-save.lua` + cell in `index.html`

**Files:**
- Create: `engine-test/test-save.lua`
- Modify: `engine-test/index.html`

Lua-side behavior tests run via `engine-test/run.html?test=save`, results visible in `engine-test/index.html` grid.

- [ ] **Step 1: Create the test file**

Create `engine-test/test-save.lua`:

```lua
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

print("--- error contract ---")
assert_throws("invalid empty key", function() data_save("", 1) end, "save: invalid key")
assert_throws("nil value rejected", function() data_save("k", nil) end, nil)  -- nil-value is acceptable rejection or coercion to remove; document either
assert_throws("function rejected", function() data_save("k", function() end) end, "save: unserializable")

print("")
print("========================================")
if fail == 0 then
  print("ALL PASSED: " .. pass .. " tests")
else
  print("RESULT: " .. pass .. " passed, " .. fail .. " FAILED")
end
print("========================================")
```

- [ ] **Step 2: Allow the test runner to set cartId/saveBackend per test**

In `engine-test/run.html` find the `Mono.boot("screen", { game: gameFile, colors: colors })` line and replace with:

```js
  Mono.boot("screen", {
    game: gameFile,
    colors: colors,
    cartId: "test:" + test,
    saveBackend: "memory",
  })
```

(The save tests need the in-memory backend so reloads start clean. Other tests don't touch save APIs but get a cartId anyway, harmless.)

Add a `<script src="../runtime/save.js"></script>` line immediately before the existing `<script src="../runtime/engine.js"></script>` in `engine-test/run.html`.

- [ ] **Step 3: Add a "save" cell to the engine-test grid**

In `engine-test/index.html`, find the `<div class="grid">` block under `<h2>Drawing Primitives</h2>` (around line 136). Either add a new section, or append into the existing grid. Adding a new section is clearer:

After the closing `</div>` of the Drawing Primitives section (around line 178, before `<div class="section">` for Test Suite), insert:

```html
<div class="section">
  <h2>Persistence</h2>
  <div class="grid">
    <div class="cell" data-test="save">
      <iframe src="run.html?test=save"></iframe>
      <div class="footer">
        <span class="label">save</span>
        <span class="chip wait" id="chip-save">...</span>
      </div>
    </div>
  </div>
</div>
```

(No `VRAM` button — save tests don't render to the canvas.)

- [ ] **Step 4: Manual verification**

Open `engine-test/index.html` in a browser. The "save" cell should show a green "PASS" chip after running. Opening DevTools console for that iframe should show `ALL PASSED: <N> tests` from the Lua-side assertions.

If the chip doesn't update automatically, check `engine-test/index.html`'s message-handling script for how it auto-detects results from `run.html` postMessage; the existing pattern at line 51-58 of `run.html` posts `test-result` for individual tests — make sure the save iframe gets the same handling.

- [ ] **Step 5: Commit**

```bash
git add engine-test/test-save.lua engine-test/run.html engine-test/index.html
git commit -m "test(save): Lua-driven data_* behavior tests"
```

---

### Task 11: Update Cosmi lint `ENGINE_GLOBALS`

**Files:**
- Modify: `cosmi/src/lib/lint.js`
- Modify: `cosmi/test/lint.test.mjs`

So that LLM-generated code can't accidentally `function data_save(...) end` and shadow the engine binding.

- [ ] **Step 1: Write the failing tests**

In `cosmi/test/lint.test.mjs`, find the existing `describe("ENGINE_GLOBALS", ...)` block (around line 70). Add a new `it`:

```js
  it("includes the data_* persistence primitives", () => {
    for (const k of ["data_save", "data_load", "data_delete", "data_has", "data_keys", "data_clear"]) {
      assert.ok(ENGINE_GLOBALS.includes(k), `missing: ${k}`);
    }
  });
```

And in the `describe("lintEnginePrimitiveOverwrite — flagged patterns", ...)` block (around line 10), add:

```js
  it("flags shadowing data_save", () => {
    assert.match(lintEnginePrimitiveOverwrite("function data_save(k, v) end"), /data_save/);
  });

  it("flags assigning to data_load", () => {
    assert.match(lintEnginePrimitiveOverwrite("data_load = nil"), /data_load/);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test cosmi/test/lint.test.mjs`
Expected: FAIL — the new `it`s.

- [ ] **Step 3: Update `cosmi/src/lib/lint.js`**

In `cosmi/src/lib/lint.js`, find the `ENGINE_GLOBALS` array (lines 8-27). Add a new section:

```js
export const ENGINE_GLOBALS = [
  // input (polling)
  "btn", "btnp", "btnr",
  "touch", "touch_start", "touch_end", "touch_pos", "touch_posf", "touch_count",
  "swipe", "axis_x", "axis_y",
  // scene + camera
  "go", "scene_name", "cam", "cam_reset", "cam_shake", "cam_get",
  // drawing
  "cls", "pix", "gpix", "line", "rect", "rectf", "circ", "circf", "text",
  "spr", "sspr", "blit",
  // surfaces
  "screen", "canvas", "canvas_w", "canvas_h", "canvas_del",
  // audio
  "note", "tone", "noise", "wave", "sfx_stop",
  // runtime info
  "frame", "time", "date", "use_pause", "mode",
  // sensors
  "motion_x", "motion_y", "motion_z",
  "gyro_alpha", "gyro_beta", "gyro_gamma", "motion_enabled",
  // persistence
  "data_save", "data_load", "data_delete", "data_has", "data_keys", "data_clear",
];
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test cosmi/test/lint.test.mjs`
Expected: PASS — all old tests + new ones.

- [ ] **Step 5: Commit**

```bash
git add cosmi/src/lib/lint.js cosmi/test/lint.test.mjs
git commit -m "feat(cosmi): reserve data_* engine globals against shadowing"
```

---

### Task 12: Document `data_*` in `docs/API.md`

**Files:**
- Modify: `docs/API.md`

Promotes save/load out of "Under Consideration" and adds a new `## Data` section that the Cosmi `api-lint.js` whitelist will pick up automatically.

- [ ] **Step 1: Add the `## Data` section**

In `docs/API.md`, the existing structure has top-level sections like `## Input`, `## Sound`, etc. Insert a new `## Data` section after `## Misc` and before `## Under Consideration`. (Verify exact placement matches the alphabetical-ish flow used in the file.)

Add:

```markdown
## Data

Per-cart persistent key/value storage. Each cart gets an isolated 64KB bucket on the player's device — values survive across sessions but never leak between carts. All values are JSON-serializable: numbers, strings, booleans, nil, and nested tables.

### data_save(key: string, value: any): void
Persist `value` under `key`. `value` may be a number, string, boolean, nil, or table (nested up to 16 levels). Throws on invalid input or quota overflow:
- `save: invalid key` — key is not a non-empty string ≤ 64 chars, or contains NUL/whitespace
- `save: unserializable <type>` — value contains a function, userdata, BigInt, NaN, or Infinity
- `save: cycle detected` — table references itself (directly or transitively)
- `save: too deep` — nesting > 16 levels
- `save: quota exceeded (N bytes > 65536)` — total bucket would exceed 64KB

### data_load(key: string): any
Returns the value previously stored under `key`, or `nil` if missing. Returns a fresh copy — mutating the returned table does **not** auto-persist; call `data_save` again to write back.

### data_delete(key: string): boolean
Removes `key` from the bucket. Returns `true` if the key existed, `false` otherwise.

### data_has(key: string): boolean
Returns `true` if `key` is currently stored.

### data_keys(): table
Returns a sorted array of currently-stored keys. Suitable for save-slot UIs and debug listings.

### data_clear(): void
Wipes the entire bucket for the current cart.
```

- [ ] **Step 2: Remove the obsolete entry from "Under Consideration"**

Lower in `docs/API.md`, the "Under Consideration" section (around line 278) lists `- save(key, value) / load(key) — local data storage`. Delete that bullet.

- [ ] **Step 3: Verify cosmi `api-lint.js` whitelist picks up the new functions**

Run: `node --test cosmi/test/api-lint.test.mjs`
Expected: PASS — the test that asserts `extractApiWhitelist` recognizes `### name` and `### name(...)` headings now produces 6 new entries.

If the test file has a fixture that snapshots a known whitelist size, update its expected count by 6. (Read `cosmi/test/api-lint.test.mjs` first to spot whether such a count assertion exists.)

- [ ] **Step 4: Commit**

```bash
git add docs/API.md
git commit -m "docs(api): document data_* persistence in ## Data section"
```

---

### Task 13: Add `MonoSaveBridge.kt`

**Files:**
- Create: `android/app/src/main/kotlin/com/mono/game/MonoSaveBridge.kt`

Backs the WebBackend native-bridge path with `SharedPreferences`.

- [ ] **Step 1: Create the file**

Create `android/app/src/main/kotlin/com/mono/game/MonoSaveBridge.kt`:

```kotlin
package com.mono.game

import android.content.Context
import android.webkit.JavascriptInterface

/**
 * Native bridge for Mono's local save API. Exposed to the WebView as
 * `MonoSaveNative`; the JS side (runtime/save.js WebBackend) auto-routes
 * through this when present, otherwise falls back to localStorage.
 *
 * Storage layout: one SharedPreferences file ("mono_save") whose entries
 * are cartId → JSON bucket string. One entry per cart.
 */
class MonoSaveBridge(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(
        "mono_save", Context.MODE_PRIVATE
    )

    /** Returns the stored JSON for `cartId`, or "" if nothing is stored. */
    @JavascriptInterface
    fun read(cartId: String): String {
        return prefs.getString(cartId, "") ?: ""
    }

    /** Synchronously writes `json` under `cartId`. Returns whether commit succeeded. */
    @JavascriptInterface
    fun write(cartId: String, json: String): Boolean {
        return prefs.edit().putString(cartId, json).commit()
    }

    /** Removes `cartId`'s entry. */
    @JavascriptInterface
    fun clear(cartId: String) {
        prefs.edit().remove(cartId).apply()
    }
}
```

- [ ] **Step 2: Confirm the file compiles by building**

Run: `cd android && ./gradlew assembleDebug` (or whatever the project's standard build command is — see `android/run.sh` if uncertain)
Expected: BUILD SUCCESSFUL.

If the build complains about `androidx.webkit` imports, double-check `android/app/build.gradle.kts` already pulls in WebView — it should, since `MonoConsole.kt` already uses `WebView` and `WebViewClient`.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/com/mono/game/MonoSaveBridge.kt
git commit -m "feat(android): MonoSaveBridge — SharedPreferences via JavascriptInterface"
```

---

### Task 14: Register `MonoSaveBridge` on the WebView

**Files:**
- Modify: `android/app/src/main/kotlin/com/mono/game/MonoConsole.kt`

Wires the bridge into the WebView so JS can find `window.MonoSaveNative`.

- [ ] **Step 1: Register the interface**

In `android/app/src/main/kotlin/com/mono/game/MonoConsole.kt`, find the `WebView(context).apply { ... }` block (around line 52). Inside, after `WebView.setWebContentsDebuggingEnabled(true)` (around line 57) and before the `webChromeClient` setup, add:

```kotlin
                addJavascriptInterface(MonoSaveBridge(context), "MonoSaveNative")
```

(Indentation should match surrounding lines — read the surrounding code first to be precise.)

- [ ] **Step 2: Verify on device or emulator**

Run: `cd android && ./gradlew installDebug && adb shell am start -n com.mono.game/.MainActivity`
Expected: app launches; in a connected DevTools session you can confirm `window.MonoSaveNative` exists.

If a packaged cart is being run, `data_save("k", 1)` followed by app restart and `data_load("k")` should return `1`. Use a known demo cart to test.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/com/mono/game/MonoConsole.kt
git commit -m "feat(android): register MonoSaveBridge on WebView"
```

---

## Final verification

After all tasks complete, run the full test matrix:

```bash
node --test runtime/save.test.mjs
node --test cosmi/test/
```

Open in browser:
- `engine-test/index.html` — confirm save cell PASS, suite still PASS.
- `play.html?game=bounce` — confirm `data_save`/`data_load` work in DevTools console.
- `dev/index.html` — load any saved cart, run, confirm no console errors.

Optional Android: run a packaged cart that calls `data_save("hi", 1)` in `_init`, kill the app, relaunch, confirm `data_load("hi") == 1`.

## Self-Review

**Spec coverage:**
- Lua API (6 functions) → Task 4 binds them; Task 10 tests behavior.
- Error contract (8 cases) → Tasks 2, 3 test JS-side; Task 10 tests Lua surfacing.
- Cart identity table → Tasks 6, 7, 8, 9.
- Boot sequence → Task 5 wires; Task 4 implements read/cache/write-through.
- Storage layout `mono:save:<cartId>` → Task 3 (WebBackend); Task 13 (Android).
- Android bridge → Tasks 13, 14.
- Quotas → Task 2 (quota check); Task 3 (key validation).
- Testing matrix (Lua + JS) → Task 10 (Lua); Tasks 1–3 (JS).
- File changed list → Tasks map 1:1.
- Future work (cloud) → not in plan, correctly deferred.

**Placeholder scan:** No `TBD`, `TODO`, or "implement appropriate X" — every step has concrete code or commands.

**Type consistency:** `MonoSave` exports (`MemoryBackend`, `WebBackend`, `serializeBucket`, `deserializeBucket`, `validateKey`, `QUOTA_BYTES`, `MAX_KEY_LEN`, `MAX_DEPTH`) match what the test file imports and what `engine-bindings.js` references. Hook shape `{ backend, cartId }` is consistent across engine.js, mono-runner.js, test-worker.js, and the bindings docblock. `data_*` function names are consistent across spec, plan, lint, docs, and tests.
