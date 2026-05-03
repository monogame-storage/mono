/**
 * Mono Save — per-cart key/value persistence
 *
 * Loaded as a classic script (browser / Web Worker / Node) — same UMD
 * pattern as engine-bindings.js so `<script src>`, `importScripts()`,
 * and `require()` all work without a bundler.
 *
 * Public surface (exported via globalThis.MonoSave or module.exports):
 *   - MemoryBackend   — in-process bucket map, no persistence
 *   - WebBackend      — localStorage (auto-routes to native bridge if present)
 *   - serializeBucket — validate + JSON.stringify with quota check
 *   - validateKey     — key shape validator (used by bindings)
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

  // ── MemoryBackend — in-process Map keyed by cartId. Stores the
  // serialized JSON string so every read returns a fresh parse; callers
  // cannot mutate stored state by holding on to a returned reference.
  // write() expects a pre-stringified JSON string (the bindings layer
  // computes it once via serializeBucket; passing it through avoids a
  // redundant stringify per save).
  class MemoryBackend {
    constructor() { this._buckets = new Map(); }
    read(cartId) {
      const stored = this._buckets.get(cartId);
      return stored ? JSON.parse(stored) : {};
    }
    write(cartId, json) {
      this._buckets.set(cartId, json);
    }
    clear(cartId) {
      this._buckets.delete(cartId);
    }
  }

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
    // Plain objects + arrays only. Class instances (Date, Map, Set, RegExp,
    // WeakRef, user classes) pass typeof === "object" but get silently
    // mangled by JSON.stringify (Date → string, Map/Set → {}). Reject up
    // front so the failure mode is loud.
    if (!Array.isArray(v)) {
      const proto = Object.getPrototypeOf(v);
      if (proto !== Object.prototype && proto !== null) {
        const name = (v.constructor && v.constructor.name) || "object";
        throw new Error("save: unserializable " + name);
      }
    }
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

  function utf8ByteLength(s) {
    if (typeof TextEncoder !== "undefined") return new TextEncoder().encode(s).length;
    // Node < 12 / very old environments: fall back to manual count.
    let n = 0;
    for (let i = 0; i < s.length; i++) {
      const c = s.charCodeAt(i);
      if (c < 0x80) n += 1;
      else if (c < 0x800) n += 2;
      else if (c >= 0xd800 && c < 0xdc00) {
        const next = (i + 1 < s.length) ? s.charCodeAt(i + 1) : 0;
        if ((next & 0xfc00) === 0xdc00) { n += 4; i++; }  // valid surrogate pair
        else n += 3;                                      // lone high surrogate → U+FFFD
      }
      else n += 3;
    }
    return n;
  }

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
      // keyPrefix lets CloudBackend reuse this class as a per-uid mirror
      // without colliding with anonymous saves under the default prefix.
      this._keyPrefix = (typeof o.keyPrefix === "string") ? o.keyPrefix : "mono:save:";
    }
    _key(cartId) { return this._keyPrefix + cartId; }
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
    write(cartId, json) {
      if (this._bridge) {
        const ok = this._bridge.write(cartId, json);
        if (!ok) throw new Error("save: backend write failed");
        return;
      }
      if (this._storage) {
        try { this._storage.setItem(this._key(cartId), json); }
        catch (e) { throw new Error("save: backend write failed: " + (e && e.message || e)); }
        return;
      }
      throw new Error("save: backend write failed");
    }
    clear(cartId) {
      if (this._bridge) { this._bridge.clear(cartId); return; }
      if (this._storage) { this._storage.removeItem(this._key(cartId)); return; }
      throw new Error("save: backend write failed");
    }
  }

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
      this._authDead = false;
    }
    _url(cartId) { return this._apiUrl + "/save/" + encodeURIComponent(cartId); }
    async _authHeaders() {
      const token = await this._getToken();
      return { "Authorization": "Bearer " + token };
    }
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
    write(cartId, json) { /* Task 8 */ }
    clear(cartId)       { /* Task 9 */ }
  }

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
});
