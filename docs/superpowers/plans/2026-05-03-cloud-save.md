# Cloud Save / `CloudBackend` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `CloudBackend` that syncs per-cart `data_*` save state to a Cloudflare Worker + R2 for logged-in players, while keeping anonymous + headless flows on existing local backends. Anonymous local data is never deleted; first login uploads it only when cloud is empty.

**Architecture:** `runtime/save.js` adds a `keyPrefix` option to `WebBackend` and a new `CloudBackend` class that composes a prefixed WebBackend as its durable mirror. Three new authenticated cosmi worker routes (`GET/PUT/DELETE /save/:cartId`) persist buckets to R2 under `save/<uid>/<cartId>`. `runtime/engine.js` accepts a pre-built backend via `opts.save` so runners (`play.html`, `dev/js/editor-play.js`) can inject CloudBackend when Firebase reports a signed-in user; otherwise the existing default-build path stays.

**Tech Stack:** Vanilla JS classic scripts (UMD), Cloudflare Workers + R2, Firebase Auth (Web SDK 11.7.1, ES modules), Node `node:test`.

**Spec:** `docs/superpowers/specs/2026-05-03-cloud-save-design.md`

**Conventions assumed by this plan:**
- All new code is in plain JS / no transpilation. `runtime/save.js` is UMD; cosmi files are ES modules with the existing `node --test` runner.
- New `CloudBackend` accepts injected dependencies (`fetch`, `storage`, `now`, `setTimeout`, `clearTimeout`) via constructor opts so unit tests can drive the timeline.
- Worker endpoints follow the existing helper pattern: a thin route handler in `index.js` that calls a focused helper (`handleSaveGet/Put/Delete`) with `(env, uid, cartId, request?)` arguments.
- R2 record format: `{ "version": 1, "bucket": <object>, "updated_at": <unix_ms> }`. Wrapper is added/stripped at the worker boundary so the client only sees `{ bucket }`.

---

### Task 1: WebBackend `keyPrefix` option

**Files:**
- Modify: `runtime/save.js`
- Modify: `runtime/save.test.mjs`

`WebBackend` currently hardcodes `"mono:save:" + cartId` as its localStorage key. Adding an optional `keyPrefix` constructor option lets `CloudBackend` reuse the class for its per-uid mirror without forking it.

- [ ] **Step 1: Write failing tests for the new option**

Append to `runtime/save.test.mjs` (after the existing WebBackend describe blocks):

```js
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test runtime/save.test.mjs`
Expected: FAIL — the keyPrefix option isn't honored yet (write goes to `mono:save:g` regardless).

- [ ] **Step 3: Implement the option**

In `runtime/save.js`, find the `WebBackend` class. Modify the constructor and `_key` method:

```js
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
      this._warnedFor = new Set();
      // keyPrefix lets CloudBackend reuse this class as a per-uid mirror
      // without colliding with anonymous saves under the default prefix.
      this._keyPrefix = (typeof o.keyPrefix === "string") ? o.keyPrefix : "mono:save:";
    }
    _key(cartId) { return this._keyPrefix + cartId; }
    // ... rest unchanged ...
```

(The `read`, `write`, `clear` methods already call `this._key(cartId)` and need no further change.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test runtime/save.test.mjs`
Expected: PASS — 4 new + all prior tests.

- [ ] **Step 5: Commit**

```bash
git add runtime/save.js runtime/save.test.mjs
git commit -m "feat(save): WebBackend gains optional keyPrefix"
```

---

### Task 2: `validateCartId` helper

**Files:**
- Modify: `cosmi/src/lib/path.js`
- Modify: `cosmi/test/path.test.mjs`

The existing `validateGameId` enforces the bare-alphanumeric R2 gameId format. The cloud-save endpoints accept richer cartIds (`demo:bounce`, `pkg:com.foo.bar`, etc.) — separate validator with its own ruleset.

- [ ] **Step 1: Write failing tests**

Append to `cosmi/test/path.test.mjs`:

```js
import { validateAgentPath, validateGameId, validateCartId } from "../src/lib/path.js";
// ↑ replace the existing import line (validateAgentPath, validateGameId) with this

describe("validateCartId", () => {
  it("accepts plain alphanumerics", () => {
    assert.equal(validateCartId("game42"), null);
  });

  it("accepts colons and underscores and hyphens", () => {
    assert.equal(validateCartId("demo:bounce"), null);
    assert.equal(validateCartId("pkg:com.foo"), "must match /^[a-zA-Z0-9:_-]{1,80}$/"); // dot rejected
    assert.equal(validateCartId("pkg:com_foo"), null);
    assert.equal(validateCartId("hi-score_v2"), null);
  });

  it("accepts boundary length 80", () => {
    assert.equal(validateCartId("a".repeat(80)), null);
  });

  it("rejects empty / null / non-string", () => {
    assert.match(validateCartId(""), /required/);
    assert.match(validateCartId(null), /required/);
    assert.match(validateCartId(undefined), /required/);
    assert.match(validateCartId(42), /required/);
  });

  it("rejects > 80 chars", () => {
    assert.match(validateCartId("a".repeat(81)), /must match/);
  });

  it("rejects path traversal vectors", () => {
    assert.match(validateCartId("../foo"), /must match/);
    assert.match(validateCartId("foo/bar"), /must match/);
    assert.match(validateCartId("foo\\bar"), /must match/);
    assert.match(validateCartId(".."), /must match/);
  });

  it("rejects whitespace and control chars", () => {
    assert.match(validateCartId("foo bar"), /must match/);
    assert.match(validateCartId("foo\tbar"), /must match/);
    assert.match(validateCartId("foo\0bar"), /must match/);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test cosmi/test/path.test.mjs`
Expected: FAIL — `validateCartId` is not exported.

- [ ] **Step 3: Implement `validateCartId`**

In `cosmi/src/lib/path.js`, append:

```js
// Reject malformed cartId values before they hit R2 as a save key. cartId
// is a richer namespace than gameId — it carries scheme prefixes like
// "demo:bounce" or "pkg:com.foo.bar" — but path-traversal characters
// (slash, backslash, dot, NUL, whitespace) must be rejected. The colon
// is allowed because the only place cartIds appear is *inside* a path
// segment, never as a delimiter on the worker side.
export function validateCartId(s) {
  if (typeof s !== "string" || !s) return "cartId required";
  if (!/^[a-zA-Z0-9:_-]{1,80}$/.test(s)) {
    return "must match /^[a-zA-Z0-9:_-]{1,80}$/";
  }
  return null;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test cosmi/test/path.test.mjs`
Expected: PASS — 7 new + all prior tests.

- [ ] **Step 5: Commit**

```bash
git add cosmi/src/lib/path.js cosmi/test/path.test.mjs
git commit -m "feat(cosmi): add validateCartId for cloud-save endpoints"
```

---

### Task 3: Worker `/save/:cartId` endpoints

**Files:**
- Modify: `cosmi/src/index.js`
- Create: `cosmi/test/save-endpoint.test.mjs`

Three authenticated routes that read/write/delete a per-user-per-cart R2 record. Helper functions are extracted (matching the existing `getFile/putFile/deleteFile` style around index.js:508) so they can be unit-tested with a fake R2 BUCKET.

- [ ] **Step 1: Write failing tests**

Create `cosmi/test/save-endpoint.test.mjs`:

```js
// Cloud-save worker route tests. Drives the helpers directly with a
// fake R2 BUCKET so we don't need a wrangler runtime.
import { describe, it, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { handleSaveGet, handleSavePut, handleSaveDelete } from "../src/save-handlers.js";

function makeFakeR2() {
  const map = new Map();
  return {
    map,
    get: async (key) => {
      const v = map.get(key);
      if (v == null) return null;
      return { text: async () => v };
    },
    put: async (key, body) => { map.set(key, body); },
    delete: async (key) => { map.delete(key); },
  };
}
function makeEnv() { return { BUCKET: makeFakeR2() }; }
function jsonBodyRequest(method, body, headers = {}) {
  return new Request("https://x/save/test", {
    method,
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

describe("handleSaveGet", () => {
  let env;
  beforeEach(() => { env = makeEnv(); });

  it("returns 404 when the entry is missing", async () => {
    const res = await handleSaveGet(env, "user1", "demo:bounce");
    assert.equal(res.status, 404);
  });

  it("returns 200 with the bucket field when present", async () => {
    env.BUCKET.map.set(
      "save/user1/demo:bounce",
      JSON.stringify({ version: 1, bucket: { hi: 42 }, updated_at: 1700000000000 }),
    );
    const res = await handleSaveGet(env, "user1", "demo:bounce");
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { bucket: { hi: 42 } });
  });

  it("isolates by uid prefix", async () => {
    env.BUCKET.map.set(
      "save/user1/demo:bounce",
      JSON.stringify({ version: 1, bucket: { hi: 42 }, updated_at: 1 }),
    );
    const res = await handleSaveGet(env, "user2", "demo:bounce");
    assert.equal(res.status, 404);
  });

  it("returns 200 + empty bucket when the R2 record is corrupt JSON", async () => {
    env.BUCKET.map.set("save/user1/demo:bounce", "{not json");
    const res = await handleSaveGet(env, "user1", "demo:bounce");
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { bucket: {} });
  });
});

describe("handleSavePut", () => {
  let env;
  beforeEach(() => { env = makeEnv(); });

  it("writes a record with version + updated_at", async () => {
    const req = jsonBodyRequest("PUT", { bucket: { hi: 42 } });
    const res = await handleSavePut(env, "user1", "demo:bounce", req);
    assert.equal(res.status, 204);
    const stored = JSON.parse(env.BUCKET.map.get("save/user1/demo:bounce"));
    assert.equal(stored.version, 1);
    assert.deepEqual(stored.bucket, { hi: 42 });
    assert.equal(typeof stored.updated_at, "number");
  });

  it("returns 413 when Content-Length exceeds 70000", async () => {
    const req = new Request("https://x/save/test", {
      method: "PUT",
      headers: { "Content-Type": "application/json", "Content-Length": "70001" },
      body: JSON.stringify({ bucket: {} }),
    });
    const res = await handleSavePut(env, "user1", "demo:bounce", req);
    assert.equal(res.status, 413);
  });

  it("returns 400 when body is not JSON", async () => {
    const req = new Request("https://x/save/test", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: "{not json",
    });
    const res = await handleSavePut(env, "user1", "demo:bounce", req);
    assert.equal(res.status, 400);
  });

  it("returns 400 when body lacks a bucket field", async () => {
    const req = jsonBodyRequest("PUT", { not_bucket: 1 });
    const res = await handleSavePut(env, "user1", "demo:bounce", req);
    assert.equal(res.status, 400);
  });

  it("returns 400 when bucket is not a plain object", async () => {
    const req = jsonBodyRequest("PUT", { bucket: [1, 2] });
    const res = await handleSavePut(env, "user1", "demo:bounce", req);
    assert.equal(res.status, 400);
  });
});

describe("handleSaveDelete", () => {
  let env;
  beforeEach(() => { env = makeEnv(); });

  it("returns 204 even when the entry was missing (idempotent)", async () => {
    const res = await handleSaveDelete(env, "user1", "demo:bounce");
    assert.equal(res.status, 204);
  });

  it("removes an existing entry", async () => {
    env.BUCKET.map.set("save/user1/demo:bounce", "stub");
    const res = await handleSaveDelete(env, "user1", "demo:bounce");
    assert.equal(res.status, 204);
    assert.equal(env.BUCKET.map.has("save/user1/demo:bounce"), false);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test cosmi/test/save-endpoint.test.mjs`
Expected: FAIL — `Cannot find module '../src/save-handlers.js'`.

- [ ] **Step 3: Create the helper module**

Create `cosmi/src/save-handlers.js`:

```js
// Cloud save handlers. Pure functions over (env, uid, cartId[, request]) →
// Response. Extracted from index.js's route table so they can be tested
// without booting a wrangler runtime. Each handler is the leaf called
// after auth + cartId validation in the main fetch handler.
//
// R2 record shape: { version: 1, bucket: <object>, updated_at: <unix_ms> }
// The wrapper is opaque to the client; GET strips it down to { bucket }.

const R2_PREFIX = "save/";
const MAX_BODY_BYTES = 70_000;   // ~64KB JSON + headroom; defense in depth

function r2Key(uid, cartId) {
  return R2_PREFIX + uid + "/" + cartId;
}

function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
      "Access-Control-Allow-Headers": "Authorization, Content-Type",
    },
  });
}

function noContent() {
  return new Response(null, {
    status: 204,
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
      "Access-Control-Allow-Headers": "Authorization, Content-Type",
    },
  });
}

export async function handleSaveGet(env, uid, cartId) {
  const obj = await env.BUCKET.get(r2Key(uid, cartId));
  if (!obj) return json(404, { error: "Not found" });
  const text = await obj.text();
  let parsed;
  try { parsed = JSON.parse(text); } catch { parsed = null; }
  // If the stored record is corrupt or shape-wrong, treat as empty bucket
  // rather than 500. The client's mirror is the source of truth here;
  // a successful 200 lets the client overwrite on next save.
  const bucket = (parsed && typeof parsed === "object" && parsed.bucket
                  && typeof parsed.bucket === "object" && !Array.isArray(parsed.bucket))
    ? parsed.bucket : {};
  return json(200, { bucket });
}

export async function handleSavePut(env, uid, cartId, request) {
  const lenHeader = request.headers.get("Content-Length");
  const len = lenHeader ? parseInt(lenHeader, 10) : 0;
  if (len > MAX_BODY_BYTES) return json(413, { error: "body too large" });
  let body;
  try { body = await request.json(); }
  catch { return json(400, { error: "invalid JSON" }); }
  if (!body || typeof body !== "object") return json(400, { error: "body must be an object" });
  const bucket = body.bucket;
  if (!bucket || typeof bucket !== "object" || Array.isArray(bucket)) {
    return json(400, { error: "body.bucket must be a plain object" });
  }
  const record = { version: 1, bucket, updated_at: Date.now() };
  await env.BUCKET.put(r2Key(uid, cartId), JSON.stringify(record));
  return noContent();
}

export async function handleSaveDelete(env, uid, cartId) {
  await env.BUCKET.delete(r2Key(uid, cartId));
  return noContent();
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test cosmi/test/save-endpoint.test.mjs`
Expected: PASS — all 12 cases.

- [ ] **Step 5: Wire the routes into `cosmi/src/index.js`**

Find the import block near the top of `cosmi/src/index.js` (around the existing `import { lintEnginePrimitiveOverwrite, lintDataKeys } from "./lib/lint.js";`). Add:

```js
import { handleSaveGet, handleSavePut, handleSaveDelete } from "./save-handlers.js";
```

(Keep its companion below the existing path import.) Update the path import line from:

```js
import { validateAgentPath, validateGameId } from "./lib/path.js";
```

to:

```js
import { validateAgentPath, validateGameId, validateCartId } from "./lib/path.js";
```

In the `default.fetch(request, env)` block, just after the `// ── Admin: lint rejection log` block (around line 110-111) and before the file-endpoint match, add the save route table:

```js
      // ── Save endpoints (cloud-save / data_*) ──
      const saveMatch = url.pathname.match(/^\/save\/([^/]+)$/);
      if (saveMatch) {
        const cartId = decodeURIComponent(saveMatch[1]);
        const badCart = validateCartId(cartId);
        if (badCart) return json(400, { error: badCart });
        if (request.method === "GET")    return await handleSaveGet(env, uid, cartId);
        if (request.method === "PUT")    return await handleSavePut(env, uid, cartId, request);
        if (request.method === "DELETE") return await handleSaveDelete(env, uid, cartId);
        return json(405, { error: "Method not allowed" });
      }
```

- [ ] **Step 6: Smoke-check the wiring**

Run: `node -e "import('./cosmi/src/index.js').then(() => console.log('OK'))"`
Expected: prints `OK`. (The index.js is ESM via `package.json` `"type":"module"`, so dynamic import is the right load mechanism.)

Run: `node --test cosmi/test/`
Expected: PASS — all cosmi tests.

- [ ] **Step 7: Commit**

```bash
git add cosmi/src/save-handlers.js cosmi/src/index.js cosmi/test/save-endpoint.test.mjs
git commit -m "feat(cosmi): GET/PUT/DELETE /save/:cartId — per-uid R2 cloud save"
```

---

### Task 4: `runtime/engine.js` accepts pre-built `opts.save`

**Files:**
- Modify: `runtime/engine.js`

The current backend resolution in `Mono.boot` always builds a fresh `WebBackend` or `MemoryBackend` from `opts.saveBackend`. Runners that want to inject `CloudBackend` (or any pre-built backend) need a passthrough — same shape `dev/headless/mono-runner.js` already uses (`save: { backend, cartId }`).

- [ ] **Step 1: Modify the backend resolution block**

In `runtime/engine.js`, find the block starting with `// ── Save backend resolution ──` (around line 1087-1108). Replace it with:

```js
    // ── Save backend resolution ──
    // Two paths:
    //   1. Runner supplied a pre-built hook (`opts.save = { backend, cartId }`)
    //      — we use it verbatim. This is how dev/headless/mono-runner.js
    //      injects MemoryBackend, and how play.html / editor inject
    //      CloudBackend when a Firebase user is signed in.
    //   2. Runner only supplied opts.cartId / opts.saveBackend — engine
    //      builds a default WebBackend (persistent) or MemoryBackend.
    let saveHook;
    if (opts.save && opts.save.backend && typeof opts.save.cartId === "string" && opts.save.cartId) {
      saveHook = opts.save;
    } else {
      const SaveLib = (typeof globalThis !== "undefined" && globalThis.MonoSave)
                   || (typeof window !== "undefined" && window.MonoSave);
      if (!SaveLib) {
        showError("MonoSave not loaded. Include <script src=\"/runtime/save.js\"> before engine.js.");
        return;
      }
      const _cartId = opts.cartId || ("anon:" + Math.random().toString(36).slice(2, 10));
      const _requested = opts.saveBackend || (opts.cartId ? "persistent" : "memory");
      if (_requested === "persistent" && !opts.cartId) {
        throw new Error("Mono.boot: saveBackend=\"persistent\" requires opts.cartId");
      }
      saveHook = {
        backend: (_requested === "memory") ? new SaveLib.MemoryBackend() : new SaveLib.WebBackend(),
        cartId: _cartId,
      };
    }
```

(The subsequent `await Bindings.bind(lua, { ..., save: saveHook });` call is unchanged.)

- [ ] **Step 2: Smoke-check engine.js parses**

Run: `node --check runtime/engine.js`
Expected: no output (no syntax errors).

- [ ] **Step 3: Verify existing tests still pass**

Run: `node --test runtime/save.test.mjs cosmi/test/`
Expected: PASS — no regressions.

- [ ] **Step 4: Commit**

```bash
git add runtime/engine.js
git commit -m "feat(engine): Mono.boot accepts pre-built opts.save passthrough"
```

---

### Task 5: `CloudBackend` skeleton + happy-path read

**Files:**
- Modify: `runtime/save.js`
- Modify: `runtime/save.test.mjs`

Lay down the constructor + the 200-response read path. Subsequent tasks layer on the failure paths, migration, debounce, clear, and flush.

- [ ] **Step 1: Write failing tests**

Append to `runtime/save.test.mjs`:

```js
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
  function fetchOk(body, init = {}) {
    return Object.assign(
      Promise.resolve(new Response(JSON.stringify(body), {
        status: 200, headers: { "Content-Type": "application/json" }, ...init,
      })),
      { _calls: [] },
    );
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test runtime/save.test.mjs`
Expected: FAIL — `MonoSave.CloudBackend is not a constructor`.

- [ ] **Step 3: Implement the skeleton + happy-path read**

In `runtime/save.js`, immediately after the `WebBackend` class (and before the closing `return { ... }`), add:

```js
  // ── CloudBackend — per-uid R2-backed save with a localStorage mirror.
  // Composes a prefixed WebBackend as the durable mirror so any read in
  // offline or post-throw conditions falls back to the last known bucket
  // without a network round-trip. All transports (fetch, storage, timing)
  // are injectable so unit tests drive the timeline deterministically.
  class CloudBackend {
    constructor(opts) {
      const o = opts || {};
      if (typeof o.uid !== "string" || !o.uid) throw new Error("CloudBackend: uid required");
      if (typeof o.getToken !== "function")    throw new Error("CloudBackend: getToken required");
      if (typeof o.apiUrl !== "string" || !o.apiUrl) throw new Error("CloudBackend: apiUrl required");
      this._uid = o.uid;
      this._getToken = o.getToken;
      this._apiUrl = o.apiUrl.replace(/\/+$/, "");
      this._fetch = o.fetch || ((typeof globalThis !== "undefined" && globalThis.fetch) ? globalThis.fetch.bind(globalThis) : null);
      if (!this._fetch) throw new Error("CloudBackend: fetch unavailable");
      this._storage = ("storage" in o) ? o.storage :
        (typeof globalThis !== "undefined" && globalThis.localStorage) ? globalThis.localStorage : null;
      this._warn = o.warn || ((typeof console !== "undefined") ? (m => console.warn(m)) : (() => {}));
      // Mirror = WebBackend at "mono:save:<uid>:" prefix. Reuses parse +
      // warn-once + JSON shape checks without re-implementing them.
      this._mirror = new WebBackend({
        storage: this._storage,
        bridge: null,                                        // mirror is localStorage-only
        keyPrefix: "mono:save:" + this._uid + ":",
        warn: this._warn,
      });
    }
    _url(cartId) { return this._apiUrl + "/save/" + encodeURIComponent(cartId); }
    async _authHeaders() {
      const token = await this._getToken();
      return { "Authorization": "Bearer " + token };
    }
    async read(cartId) {
      const headers = await this._authHeaders();
      const res = await this._fetch(this._url(cartId), { method: "GET", headers });
      if (res.status === 200) {
        const body = await res.json();
        const bucket = (body && typeof body.bucket === "object" && body.bucket && !Array.isArray(body.bucket))
          ? body.bucket : {};
        this._mirror.write(cartId, JSON.stringify(bucket));
        return bucket;
      }
      // Other paths land in later tasks. For now, fall back to mirror.
      return this._mirror.read(cartId);
    }
    write(cartId, json) { /* Task 8 */ }
    clear(cartId)       { /* Task 9 */ }
  }
```

Update the `return { ... }` block at the bottom of the IIFE to export `CloudBackend`:

```js
  return {
    MemoryBackend,
    WebBackend,
    CloudBackend,
    serializeBucket,
    validateKey,
    QUOTA_BYTES,
    MAX_KEY_LEN,
    MAX_DEPTH,
  };
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test runtime/save.test.mjs`
Expected: PASS — 2 new + all prior tests.

- [ ] **Step 5: Commit**

```bash
git add runtime/save.js runtime/save.test.mjs
git commit -m "feat(save): CloudBackend skeleton + 200 read path"
```

---

### Task 6: `CloudBackend.read` — 404, 401, network-error fallbacks

**Files:**
- Modify: `runtime/save.js`
- Modify: `runtime/save.test.mjs`

Now flesh out the failure paths around `read`. Migration (404 + anonymous mirror has data) is the next task — this one covers 404+empty, network error, and 401.

- [ ] **Step 1: Write failing tests**

Append to `runtime/save.test.mjs`:

```js
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test runtime/save.test.mjs`
Expected: FAIL — current `read` returns `{}` from mirror on 404/401 but doesn't track auth-dead.

- [ ] **Step 3: Update `CloudBackend.read`**

Replace the `read` method in `runtime/save.js` with:

```js
    async read(cartId) {
      const headers = await this._authHeaders();
      let res;
      try {
        res = await this._fetch(this._url(cartId), { method: "GET", headers });
      } catch (e) {
        // Network failure — fall back to mirror, leave push enabled
        // so subsequent writes can recover when connectivity returns.
        return this._mirror.read(cartId);
      }
      if (res.status === 200) {
        const body = await res.json();
        const bucket = (body && typeof body.bucket === "object" && body.bucket && !Array.isArray(body.bucket))
          ? body.bucket : {};
        this._mirror.write(cartId, JSON.stringify(bucket));
        return bucket;
      }
      if (res.status === 401) {
        this._authDead = true;
        this._warn("CloudBackend: 401 from cloud — disabling push for this session");
        return {};
      }
      if (res.status === 404) {
        // Migration logic in Task 7. For now, no anon mirror means {}.
        return {};
      }
      // 5xx or other — fall back to mirror.
      return this._mirror.read(cartId);
    }
```

Initialize `_authDead` to `false` in the constructor (right after `this._mirror = ...`):

```js
      this._authDead = false;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test runtime/save.test.mjs`
Expected: PASS — 4 new + all prior.

- [ ] **Step 5: Commit**

```bash
git add runtime/save.js runtime/save.test.mjs
git commit -m "feat(save): CloudBackend handles 404 / 401 / network failure on read"
```

---

### Task 7: `CloudBackend.read` — migration on 404 + anonymous mirror

**Files:**
- Modify: `runtime/save.js`
- Modify: `runtime/save.test.mjs`

When the cloud GET returns 404 *and* the anonymous bucket (`mono:save:<cartId>`) has data, the user is "first-login on this device with prior anonymous progress." Push that bucket to cloud, mirror it under the per-uid prefix, leave the anonymous key untouched. The push uses the same debounce pipeline as regular writes (introduced in Task 8) — for this task, schedule it via `setTimeout(_, 0)` and we'll reuse the wiring once writes exist.

- [ ] **Step 1: Write failing tests**

Append to `runtime/save.test.mjs`:

```js
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test runtime/save.test.mjs`
Expected: FAIL — migration path not implemented; PUT is never called.

- [ ] **Step 3: Implement migration**

In `runtime/save.js`, accept `setTimeout` / `clearTimeout` overrides in the constructor (so tests can drive timing). Update the constructor — add to the bottom of the body:

```js
      this._setTimeout = o.setTimeout || ((typeof globalThis !== "undefined") ? globalThis.setTimeout.bind(globalThis) : null);
      this._clearTimeout = o.clearTimeout || ((typeof globalThis !== "undefined") ? globalThis.clearTimeout.bind(globalThis) : null);
      this._pending = new Map();   // cartId → JSON string awaiting push
      this._timer = null;
```

Add a private push method (placed right above `read`):

```js
    _schedulePush(cartId, json, delayMs) {
      this._pending.set(cartId, json);
      if (this._timer && this._clearTimeout) this._clearTimeout(this._timer);
      this._timer = this._setTimeout ? this._setTimeout(() => this._flush(), delayMs) : null;
    }
    async _flush() {
      this._timer = null;
      if (this._authDead) { this._pending.clear(); return; }
      const headers = await this._authHeaders();
      const entries = Array.from(this._pending.entries());
      for (const [cartId, json] of entries) {
        try {
          const res = await this._fetch(this._url(cartId), {
            method: "PUT",
            headers: { ...headers, "Content-Type": "application/json" },
            body: JSON.stringify({ bucket: JSON.parse(json) }),
          });
          if (res.ok) { this._pending.delete(cartId); continue; }
          if (res.status === 401) {
            this._authDead = true;
            this._pending.clear();
            this._warn("CloudBackend: 401 on push — disabling push for this session");
            return;
          }
          if (res.status === 413) {
            this._pending.delete(cartId);
            this._warn("CloudBackend: 413 on push (cartId=" + cartId + ") — clientside cap should have prevented this");
            continue;
          }
          // 5xx: leave in pending, retry next debounce.
        } catch {
          // Network error: leave in pending, retry next debounce.
        }
      }
    }
```

Then update the 404 branch in `read`:

```js
      if (res.status === 404) {
        // First login on this device with anonymous progress on the same
        // cartId? Read the anonymous mirror (DIFFERENT prefix from our
        // per-uid mirror), and if it has a usable bucket, write it through
        // to our mirror and schedule an immediate migration push. Anonymous
        // key is intentionally NOT removed.
        const anonRaw = this._storage ? this._storage.getItem("mono:save:" + cartId) : null;
        if (anonRaw) {
          let anonBucket;
          try {
            const parsed = JSON.parse(anonRaw);
            if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) anonBucket = parsed;
          } catch {}
          if (anonBucket) {
            this._mirror.write(cartId, anonRaw);
            this._schedulePush(cartId, anonRaw, 0);
            return anonBucket;
          }
        }
        return {};
      }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test runtime/save.test.mjs`
Expected: PASS — 2 new + all prior.

- [ ] **Step 5: Commit**

```bash
git add runtime/save.js runtime/save.test.mjs
git commit -m "feat(save): CloudBackend migrates anonymous bucket on first login"
```

---

### Task 8: `CloudBackend.write` — debounce pipeline

**Files:**
- Modify: `runtime/save.js`
- Modify: `runtime/save.test.mjs`

`write` writes to mirror immediately + schedules a debounced push. Multiple writes in <1s collapse into one PUT (via `_pending` map replacement, already wired in Task 7).

- [ ] **Step 1: Write failing tests**

Append to `runtime/save.test.mjs`:

```js
describe("CloudBackend — write + debounce", () => {
  function makeFakeStorage() {
    const map = new Map();
    return {
      getItem: (k) => map.has(k) ? map.get(k) : null,
      setItem: (k, v) => { map.set(k, String(v)); },
      removeItem: (k) => { map.delete(k); },
      _entries: () => Array.from(map.entries()),
    };
  }
  function makeFakeTimer() {
    let pendingFn = null;
    let pendingDelay = -1;
    return {
      setTimeout: (fn, ms) => { pendingFn = fn; pendingDelay = ms; return 1; },
      clearTimeout: () => { pendingFn = null; pendingDelay = -1; },
      run: async () => {
        const fn = pendingFn;
        pendingFn = null; pendingDelay = -1;
        if (fn) await fn();
      },
      get pendingDelay() { return pendingDelay; },
      get hasPending() { return pendingFn !== null; },
    };
  }

  it("writes to mirror immediately and schedules a 1000ms push", async () => {
    const storage = makeFakeStorage();
    const timer = makeFakeTimer();
    const fetchFn = async () => new Response(null, { status: 204 });
    const b = new MonoSave.CloudBackend({
      uid: "u1", getToken: async () => "T", apiUrl: "https://x",
      fetch: fetchFn, storage, setTimeout: timer.setTimeout, clearTimeout: timer.clearTimeout,
    });
    b.write("demo:bounce", '{"hi":42}');
    assert.equal(storage.getItem("mono:save:u1:demo:bounce"), '{"hi":42}');
    assert.equal(timer.pendingDelay, 1000);
  });

  it("multiple writes within debounce collapse into one PUT", async () => {
    const storage = makeFakeStorage();
    const timer = makeFakeTimer();
    const calls = [];
    const fetchFn = async (url, init) => { calls.push(init); return new Response(null, { status: 204 }); };
    const b = new MonoSave.CloudBackend({
      uid: "u1", getToken: async () => "T", apiUrl: "https://x",
      fetch: fetchFn, storage, setTimeout: timer.setTimeout, clearTimeout: timer.clearTimeout,
    });
    b.write("demo:bounce", '{"hi":1}');
    b.write("demo:bounce", '{"hi":2}');
    b.write("demo:bounce", '{"hi":3}');
    assert.ok(timer.hasPending);
    await timer.run();
    assert.equal(calls.length, 1);
    assert.deepEqual(JSON.parse(calls[0].body), { bucket: { hi: 3 } });
  });

  it("network error on push leaves entry in pending for retry", async () => {
    const storage = makeFakeStorage();
    const timer = makeFakeTimer();
    let attempts = 0;
    const fetchFn = async () => { attempts++; throw new Error("offline"); };
    const b = new MonoSave.CloudBackend({
      uid: "u1", getToken: async () => "T", apiUrl: "https://x",
      fetch: fetchFn, storage, setTimeout: timer.setTimeout, clearTimeout: timer.clearTimeout,
    });
    b.write("demo:bounce", '{"hi":1}');
    await timer.run();
    assert.equal(attempts, 1);
    assert.equal(b._pending.get("demo:bounce"), '{"hi":1}');
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test runtime/save.test.mjs`
Expected: FAIL — `write` is still a stub.

- [ ] **Step 3: Implement `write`**

Replace the `write(cartId, json)` stub with:

```js
    write(cartId, json) {
      // Mirror is the authoritative local copy. A failed cloud push must
      // not leave the mirror behind — so write to mirror first, push next.
      this._mirror.write(cartId, json);
      if (this._authDead) return;
      this._schedulePush(cartId, json, 1000);
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test runtime/save.test.mjs`
Expected: PASS — 3 new + all prior.

- [ ] **Step 5: Commit**

```bash
git add runtime/save.js runtime/save.test.mjs
git commit -m "feat(save): CloudBackend.write — debounced PUT with retry on failure"
```

---

### Task 9: `CloudBackend.clear` — immediate DELETE + cancel pending

**Files:**
- Modify: `runtime/save.js`
- Modify: `runtime/save.test.mjs`

Clear is destructive intent — issue DELETE immediately (not debounced). Cancel any pending push for this cartId.

- [ ] **Step 1: Write failing tests**

Append to `runtime/save.test.mjs`:

```js
describe("CloudBackend — clear", () => {
  function makeFakeStorage() {
    const map = new Map();
    return {
      getItem: (k) => map.has(k) ? map.get(k) : null,
      setItem: (k, v) => { map.set(k, String(v)); },
      removeItem: (k) => { map.delete(k); },
      _entries: () => Array.from(map.entries()),
    };
  }
  function makeFakeTimer() {
    let pendingFn = null;
    return {
      setTimeout: (fn) => { pendingFn = fn; return 1; },
      clearTimeout: () => { pendingFn = null; },
      get hasPending() { return pendingFn !== null; },
    };
  }

  it("issues DELETE immediately and clears the per-uid mirror", async () => {
    const storage = makeFakeStorage();
    storage.setItem("mono:save:u1:demo:bounce", '{"hi":1}');
    const calls = [];
    const fetchFn = async (url, init) => { calls.push({ url, method: init.method }); return new Response(null, { status: 204 }); };
    const b = new MonoSave.CloudBackend({
      uid: "u1", getToken: async () => "T", apiUrl: "https://x",
      fetch: fetchFn, storage, setTimeout: () => 0, clearTimeout: () => {},
    });
    await b.clear("demo:bounce");
    assert.equal(storage.getItem("mono:save:u1:demo:bounce"), null);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].method, "DELETE");
    assert.equal(calls[0].url, "https://x/save/demo%3Abounce");
  });

  it("cancels a pending push for the same cartId", async () => {
    const storage = makeFakeStorage();
    const timer = makeFakeTimer();
    const fetchFn = async () => new Response(null, { status: 204 });
    const b = new MonoSave.CloudBackend({
      uid: "u1", getToken: async () => "T", apiUrl: "https://x",
      fetch: fetchFn, storage, setTimeout: timer.setTimeout, clearTimeout: timer.clearTimeout,
    });
    b.write("demo:bounce", '{"hi":1}');
    assert.ok(timer.hasPending);
    await b.clear("demo:bounce");
    // Pending push for this cartId must be gone.
    assert.equal(b._pending.has("demo:bounce"), false);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test runtime/save.test.mjs`
Expected: FAIL — `clear` is a stub.

- [ ] **Step 3: Implement `clear`**

Replace the `clear(cartId)` stub with:

```js
    async clear(cartId) {
      this._mirror.clear(cartId);
      this._pending.delete(cartId);
      if (this._authDead) return;
      try {
        const headers = await this._authHeaders();
        await this._fetch(this._url(cartId), { method: "DELETE", headers });
      } catch {
        // Network failure — local cleared, cloud will be cleared on next
        // successful clear or overwritten on next save. Acceptable: a
        // clear that doesn't reach the server is rare and not catastrophic.
      }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test runtime/save.test.mjs`
Expected: PASS — 2 new + all prior.

- [ ] **Step 5: Commit**

```bash
git add runtime/save.js runtime/save.test.mjs
git commit -m "feat(save): CloudBackend.clear — immediate DELETE + cancel pending"
```

---

### Task 10: `CloudBackend` keepalive flush on page leave

**Files:**
- Modify: `runtime/save.js`
- Modify: `runtime/save.test.mjs`

`visibilitychange` (state==='hidden') and `beforeunload` listeners flush pending pushes via `fetch(..., { keepalive: true })`. Browsers guarantee keepalive requests survive page teardown.

- [ ] **Step 1: Write failing tests**

Append to `runtime/save.test.mjs`:

```js
describe("CloudBackend — keepalive flush on page leave", () => {
  function makeFakeStorage() {
    const map = new Map();
    return {
      getItem: (k) => map.has(k) ? map.get(k) : null,
      setItem: (k, v) => { map.set(k, String(v)); },
      removeItem: (k) => { map.delete(k); },
    };
  }
  function makeEventTarget() {
    const handlers = {};
    return {
      addEventListener: (ev, fn) => { (handlers[ev] = handlers[ev] || []).push(fn); },
      removeEventListener: () => {},
      dispatchEvent: (ev) => { (handlers[ev.type] || []).forEach(fn => fn(ev)); },
    };
  }

  it("registers visibilitychange + beforeunload listeners on construction", () => {
    const target = makeEventTarget();
    const b = new MonoSave.CloudBackend({
      uid: "u1", getToken: async () => "T", apiUrl: "https://x",
      fetch: async () => new Response(null, { status: 204 }),
      storage: makeFakeStorage(), setTimeout: () => 0, clearTimeout: () => {},
      eventTarget: target, visibilityState: () => "visible",
    });
    // Bookkeeping: handlers were attached. (We don't expose them, but
    // dispatching now should not throw.)
    target.dispatchEvent({ type: "visibilitychange" });
    target.dispatchEvent({ type: "beforeunload" });
  });

  it("issues a keepalive PUT for each pending entry on visibilitychange to hidden", async () => {
    const target = makeEventTarget();
    const calls = [];
    const fetchFn = async (url, init) => { calls.push(init); return new Response(null, { status: 204 }); };
    let visState = "visible";
    const b = new MonoSave.CloudBackend({
      uid: "u1", getToken: async () => "T", apiUrl: "https://x",
      fetch: fetchFn, storage: makeFakeStorage(),
      setTimeout: () => 0, clearTimeout: () => {},
      eventTarget: target, visibilityState: () => visState,
    });
    b.write("a", '{"v":1}');
    b.write("b", '{"v":2}');
    visState = "hidden";
    target.dispatchEvent({ type: "visibilitychange" });
    // Allow microtasks to drain.
    await Promise.resolve();
    await Promise.resolve();
    assert.equal(calls.length, 2);
    assert.equal(calls[0].keepalive, true);
    assert.equal(calls[1].keepalive, true);
  });

  it("issues a keepalive PUT on beforeunload regardless of visibility", async () => {
    const target = makeEventTarget();
    const calls = [];
    const fetchFn = async (url, init) => { calls.push(init); return new Response(null, { status: 204 }); };
    const b = new MonoSave.CloudBackend({
      uid: "u1", getToken: async () => "T", apiUrl: "https://x",
      fetch: fetchFn, storage: makeFakeStorage(),
      setTimeout: () => 0, clearTimeout: () => {},
      eventTarget: target, visibilityState: () => "visible",
    });
    b.write("a", '{"v":1}');
    target.dispatchEvent({ type: "beforeunload" });
    await Promise.resolve();
    await Promise.resolve();
    assert.equal(calls.length, 1);
    assert.equal(calls[0].keepalive, true);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test runtime/save.test.mjs`
Expected: FAIL — listeners not attached.

- [ ] **Step 3: Implement keepalive flush**

In the CloudBackend constructor, before the `_pending` initialization, add `eventTarget` + `visibilityState` injection:

```js
      this._eventTarget = ("eventTarget" in o) ? o.eventTarget :
        (typeof globalThis !== "undefined" && globalThis.addEventListener) ? globalThis : null;
      this._visibilityState = o.visibilityState ||
        ((typeof document !== "undefined") ? (() => document.visibilityState) : (() => "visible"));
```

After the `_pending` / `_timer` init, register listeners:

```js
      if (this._eventTarget && this._eventTarget.addEventListener) {
        this._eventTarget.addEventListener("visibilitychange", () => {
          if (this._visibilityState() === "hidden") this._flushKeepalive();
        });
        this._eventTarget.addEventListener("beforeunload", () => this._flushKeepalive());
      }
```

Add the `_flushKeepalive` method (alongside `_flush`):

```js
    async _flushKeepalive() {
      if (this._pending.size === 0 || this._authDead) return;
      const headers = await this._authHeaders();
      const entries = Array.from(this._pending.entries());
      for (const [cartId, json] of entries) {
        try {
          await this._fetch(this._url(cartId), {
            method: "PUT",
            headers: { ...headers, "Content-Type": "application/json" },
            body: JSON.stringify({ bucket: JSON.parse(json) }),
            keepalive: true,
          });
          this._pending.delete(cartId);
        } catch {
          // Page is unloading — best-effort. Mirror is durable, retry on next boot.
        }
      }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test runtime/save.test.mjs`
Expected: PASS — 3 new + all prior.

- [ ] **Step 5: Commit**

```bash
git add runtime/save.js runtime/save.test.mjs
git commit -m "feat(save): CloudBackend flushes pending pushes via fetch keepalive on page leave"
```

---

### Task 11: `play.html` — Firebase auth + backend selection

**Files:**
- Modify: `play.html`

`play.html` doesn't currently load Firebase. Add a small ESM module that initializes Firebase Auth, waits for the auth state to settle, then constructs `CloudBackend` (logged in) or relies on `Mono.boot`'s default `WebBackend` (anonymous). Boot is gated on auth-ready.

- [ ] **Step 1: Add Firebase init + auth gating**

In `play.html`, find the existing `<script>` block that defines `GAMES` (around line 108-122) and the boot logic that follows. Replace the entire boot block with an async ESM initializer that runs after Firebase auth settles. The change is contained to the inline `<script>` block at the bottom of the file.

Replace:

```html
<script>
  var GAMES = { /* ... existing entries ... */ };
  var API_URL = "https://api.monogame.cc";
  var params = new URLSearchParams(location.search);
  var gameName = params.get("game");
  var gameId = params.get("id");
  var entry = gameName && GAMES[gameName];

  if (gameId) {
    /* ... existing boot logic ... */
  } else if (!entry) {
    /* ... existing error UI ... */
  } else {
    /* ... existing demo boot ... */
  }
</script>
```

with the following two scripts (a classic config script, then a module that gates on auth):

```html
<script>
  var GAMES = {
    bounce:      { path: "/demo/bounce/main.lua",      colors: 1 },
    dodge:       { path: "/demo/dodge/main.lua",       colors: 4 },
    pong:        { path: "/demo/pong/main.lua",        colors: 4 },
    invaders:    { path: "/demo/invaders/main.lua",    colors: 1 },
    bubble:      { path: "/demo/bubble/main.lua",      colors: 4 },
    starfighter: { path: "/demo/starfighter/main.lua", colors: 4 },
    paint:       { path: "/demo/paint/main.lua",       colors: 4 },
    tiltmaze:    { path: "/demo/tiltmaze/main.lua",    colors: 4 },
    synth:       { path: "/demo/synth/main.lua",       colors: 4 },
    clock:       { path: "/demo/clock/main.lua",       colors: 4 },
    "engine-test": { path: "/demo/engine-test/main.lua", colors: 4 },
    motion:      { path: "/demo/motion/main.lua",      colors: 4 },
    save:        { path: "/demo/save/main.lua",        colors: 4 }
  };
  var API_URL = "https://api.monogame.cc";
</script>

<script type="module">
  import { initializeApp } from "https://www.gstatic.com/firebasejs/11.7.1/firebase-app.js";
  import { getAuth, onAuthStateChanged } from "https://www.gstatic.com/firebasejs/11.7.1/firebase-auth.js";

  const app = initializeApp({
    apiKey: "AIzaSyAyTiJx_JkVdQoh8b5bDo-ttvp175vy8PM",
    authDomain: "mono-5b951.firebaseapp.com",
    projectId: "mono-5b951",
    storageBucket: "mono-5b951.firebasestorage.app",
    messagingSenderId: "850069827366",
    appId: "1:850069827366:web:a196c04bbf4c93bd061be7"
  });
  const auth = getAuth(app);

  // Wait for the first auth state callback so we know whether we have a
  // signed-in user before booting Mono. Resolves to the user (or null).
  const user = await new Promise((resolve) => {
    const unsub = onAuthStateChanged(auth, (u) => { unsub(); resolve(u); });
  });

  // Build the save backend if we're logged in; otherwise leave it for
  // Mono.boot to default to WebBackend (anonymous).
  function makeSaveHook(cartId) {
    if (!user) return undefined;
    return {
      backend: new Mono.MonoSave.CloudBackend({
        uid: user.uid,
        getToken: () => user.getIdToken(),
        apiUrl: API_URL,
      }),
      cartId,
    };
  }

  const params = new URLSearchParams(location.search);
  const gameName = params.get("game");
  const gameId = params.get("id");
  const entry = gameName && GAMES[gameName];

  if (gameId) {
    try {
      const res = await fetch(API_URL + "/games/" + gameId + "/published");
      if (!res.ok) throw new Error("Game not found");
      const data = await res.json();
      document.title = "Mono \u2014 " + (data.title || "Game");
      document.getElementById("back-btn").href = "/";

      let mainSrc = "";
      const modules = {};
      const assets = {};
      const textFiles = {};
      const mimeByExt = { png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", gif: "image/gif", webp: "image/webp", bmp: "image/bmp" };
      for (const f of data.files) {
        if (f.encoding === "base64") {
          const bin = Uint8Array.from(atob(f.content), (c) => c.charCodeAt(0));
          const ext = f.name.split(".").pop().toLowerCase();
          const mime = mimeByExt[ext] || "application/octet-stream";
          assets[f.name] = URL.createObjectURL(new Blob([bin], { type: mime }));
        } else if (f.name === "main.lua") {
          mainSrc = f.content;
        } else if (f.name.endsWith(".lua")) {
          modules[f.name] = f.content;
        } else {
          textFiles[f.name] = f.content;
        }
      }
      if (!mainSrc) throw new Error("No main.lua in published files");
      try {
        await Mono.boot("screen", {
          source: mainSrc,
          modules: modules,
          assets: assets,
          colors: 4,
          readFile: (name) => modules[name] || textFiles[name] || null,
          cartId: gameId,
          save: makeSaveHook(gameId),
        });
      } finally {
        for (const k in assets) URL.revokeObjectURL(assets[k]);
      }
      Mono.shader.preset();
    } catch (e) {
      console.error("Boot failed:", e);
      document.getElementById("error").style.display = "block";
      document.getElementById("error").textContent = "Failed to load game: " + e.message;
      document.getElementById("console").style.display = "none";
    }
  } else if (!entry) {
    document.getElementById("error").style.display = "block";
    document.getElementById("error").textContent = gameName
      ? 'Unknown game: "' + gameName + '". Available: ' + Object.keys(GAMES).join(", ")
      : "No game specified. Use ?game=bounce or ?id=gameId";
    document.getElementById("console").style.display = "none";
  } else {
    document.title = "Mono \u2014 " + gameName.charAt(0).toUpperCase() + gameName.slice(1);
    const cartId = "demo:" + gameName;
    Mono.boot("screen", {
      game: entry.path,
      colors: entry.colors,
      cartId,
      save: makeSaveHook(cartId),
    }).then(() => {
      Mono.shader.preset();
    }).catch((e) => {
      console.error("Boot failed:", e);
      document.getElementById("error").style.display = "block";
      document.getElementById("error").textContent = "Boot failed: " + e.message;
    });
  }
</script>
```

Note: `Mono.MonoSave` doesn't exist as a property on `Mono` — `MonoSave` is a separate global set by `runtime/save.js`. Replace `Mono.MonoSave.CloudBackend` with `MonoSave.CloudBackend`. (Lift to a one-liner above the `if (gameId)` block to avoid duplication.)

```js
  const MonoSave = window.MonoSave;
```

- [ ] **Step 2: Smoke-test the static HTML**

There's no JS test suite to drive a browser test. Open `play.html?game=save` in a browser:
- Without signing in, the boot should work as before. localStorage entry `mono:save:demo:save` populates after a save.
- (Sign-in flow needs end-to-end manual verification — see Task 13.)

Run: `node --test runtime/save.test.mjs cosmi/test/`
Expected: PASS — JS regressions still pass; no Lua/HTML test changes.

- [ ] **Step 3: Commit**

```bash
git add play.html
git commit -m "feat(save): play.html selects CloudBackend when Firebase user signed in"
```

---

### Task 12: `dev/js/editor-play.js` — auth-aware backend selection

**Files:**
- Modify: `dev/js/editor-play.js`

The editor already has `state.auth` and runs only after auth fires (per `dev/js/app.js`). At boot time, `state.auth.currentUser` is the live Firebase user.

- [ ] **Step 1: Update the boot call**

In `dev/js/editor-play.js`, find the `Mono.boot("editor-screen", { ... })` call (around line 116). Replace it with the auth-aware version:

```js
  const user = state.auth && state.auth.currentUser;
  const cartId = state.currentGameId || "scratch";
  const saveHook = (user && state.currentGameId)
    ? {
        backend: new window.MonoSave.CloudBackend({
          uid: user.uid,
          getToken: () => user.getIdToken(),
          apiUrl: "https://api.monogame.cc",
        }),
        cartId,
      }
    : undefined;

  Mono.boot("editor-screen", {
    source: mainFile.content,
    colors: 4,
    noAutoFit: true,
    readFile: async (name) => fileMap[name] || "",
    modules: moduleMap,
    assets: state.currentAssets,
    cartId,
    saveBackend: state.currentGameId ? "persistent" : "memory",
    save: saveHook,
  }).then(() => {
    applyShaderConfig();
  }).catch((e) => {
    showEngineError(e.message || String(e));
    consolePrint("[error] " + (e.message || String(e)), "error");
    stopGame();
  });
```

The `save` field is consumed by `Mono.boot`'s passthrough (Task 4); `saveBackend` is left for the case where `save` is not supplied (logged-out scratch session — falls back to memory).

- [ ] **Step 2: Smoke-test in the editor**

This requires the dev server running. Manual: open `dev/index.html`, sign in, open a saved game, hit Play. Confirm no console errors mentioning `CloudBackend` or `MonoSave`. (Cloud round-trip verification is part of Task 13's manual end-to-end.)

- [ ] **Step 3: Commit**

```bash
git add dev/js/editor-play.js
git commit -m "feat(save): editor-play.js selects CloudBackend for logged-in users"
```

---

### Task 13: Update local-save spec future-work pointer

**Files:**
- Modify: `docs/superpowers/specs/2026-05-02-local-save-design.md`

The original spec's Future Work section now has a concrete shipped implementation. Update the bullet to point at this spec.

- [ ] **Step 1: Edit the file**

Replace the first bullet under `## Future Work` in `docs/superpowers/specs/2026-05-02-local-save-design.md`:

From:

```
- **Cloud sync for published games on logged-in users.** Add a `CloudBackend` that mirrors locally for offline + speed and pushes debounced writes to a new Cosmi Worker endpoint (`GET/PUT/DELETE /save/<cartId>`) keyed by `<uid>:<cartId>` in R2. Last-write-wins for conflicts. The backend interface is already shaped to accommodate this — the runner's auth-detection branch picks `CloudBackend` when a Firebase user is signed in and the cart is a published R2 cart.
```

To:

```
- **Cloud sync for logged-in users.** Implemented in `docs/superpowers/specs/2026-05-03-cloud-save-design.md`. CloudBackend composes a per-uid WebBackend mirror, debounce-pushes to `GET/PUT/DELETE /save/:cartId` in cosmi, persists to R2 under `save/<uid>/<cartId>`. Cloud-wins on first login (anonymous local preserved, never deleted). All authenticated boots with a cartId go through CloudBackend.
```

- [ ] **Step 2: Run all tests one more time as a final regression sweep**

Run: `node --test runtime/save.test.mjs cosmi/test/`
Expected: PASS — every test in both suites.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-05-02-local-save-design.md
git commit -m "docs(spec): point local-save future work at the cloud-save implementation"
```

---

## Manual end-to-end verification

After all 13 tasks land, run this verification (browser + production cosmi or `wrangler dev`):

1. Open `play.html?game=save` while signed out.
2. Save some fields in the demo. Confirm `localStorage["mono:save:demo:save"]` has the bucket.
3. Sign in (via the editor / dashboard, then return to `play.html?game=save`).
4. Reload. Confirm:
   - The fields show the previously-saved values (came from the migration push → cloud → mirror round-trip).
   - `localStorage["mono:save:<uid>:demo:save"]` has the bucket.
   - `localStorage["mono:save:demo:save"]` is **still there** (anonymous preserved).
   - In the cosmi worker logs (or R2 directly), `save/<uid>/demo:save` has a record with `version: 1` and `bucket: { ... }`.
5. Sign out. Reload `play.html?game=save`. Confirm anonymous values reappear.
6. Sign in on a second browser / incognito with the same account, open `play.html?game=save`. Confirm the cloud values appear (cloud → fresh mirror).

If any step fails, check the browser console for `CloudBackend:` warnings and the cosmi worker logs (`wrangler tail`).

## Self-review

**Spec coverage:**

- Lua API unchanged → no task needed.
- Anonymous + headless flows preserved → Tasks 1, 4 (no behavior change paths).
- WebBackend keyPrefix → Task 1.
- CloudBackend class → Tasks 5, 6, 7, 8, 9, 10.
- Worker endpoints → Task 3.
- cartId validator → Task 2.
- Engine.js opts.save passthrough → Task 4.
- play.html backend selection → Task 11.
- editor-play.js backend selection → Task 12.
- Local-save spec future-work pointer → Task 13.
- Migration policy → Task 7 (404 + anon → push, anon preserved).
- Push timing (debounce + keepalive flush) → Tasks 8 + 10.
- Auth detection at boot → Tasks 11 + 12.

**Placeholder scan:** No `TBD`, `TODO`, "fill in later", "similar to". Each step has full code or full command.

**Type consistency:**
- `CloudBackend` constructor accepts `{ uid, getToken, apiUrl, fetch?, storage?, warn?, setTimeout?, clearTimeout?, eventTarget?, visibilityState? }` everywhere it's referenced.
- `_pending` is `Map<cartId: string, json: string>`, consistent across `write`, `_schedulePush`, `_flush`, `_flushKeepalive`, `clear`.
- `saveHook = { backend, cartId }` matches the existing engine-bindings.js contract.
- Worker handlers signature: `(env, uid, cartId[, request])` consistent across `handleSaveGet/Put/Delete`.
- R2 record `{ version: 1, bucket: <object>, updated_at: <unix_ms> }` matches the spec.
