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
  // Default localStorage namespace. Anonymous saves land at
  // DEFAULT_KEY_PREFIX + cartId. CloudBackend's per-uid mirror appends
  // the uid before passing the prefix to its inner WebBackend, but it
  // also reads anonymous saves directly from this namespace during
  // first-login migration — keeping a single source of truth here
  // prevents the two sites from drifting.
  const DEFAULT_KEY_PREFIX = "mono:save:";

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
      this._keyPrefix = (typeof o.keyPrefix === "string") ? o.keyPrefix : DEFAULT_KEY_PREFIX;
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
        keyPrefix: DEFAULT_KEY_PREFIX + this._uid + ":",
        warn: this._warn,
      });
      this._authDead = false;
      this._setTimeout = o.setTimeout || ((typeof globalThis !== "undefined") ? globalThis.setTimeout.bind(globalThis) : null);
      this._clearTimeout = o.clearTimeout || ((typeof globalThis !== "undefined") ? globalThis.clearTimeout.bind(globalThis) : null);
      this._eventTarget = ("eventTarget" in o) ? o.eventTarget :
        (typeof globalThis !== "undefined" && globalThis.addEventListener) ? globalThis : null;
      this._visibilityState = o.visibilityState ||
        ((typeof document !== "undefined") ? (() => document.visibilityState) : (() => "visible"));
      this._pending = new Map();   // cartId → JSON string awaiting push
      this._timer = null;
      // Bind listener fns so dispose() can remove the exact same references.
      // Without this, every CloudBackend constructed in a long-lived page
      // (editor reset, hot reload) leaks one pair of listeners that fire
      // a redundant keepalive PUT on every tab blur for the rest of the
      // session.
      this._onVisibility = () => {
        if (this._visibilityState() === "hidden") this._flushKeepalive();
      };
      this._onBeforeUnload = () => this._flushKeepalive();
      if (this._eventTarget && this._eventTarget.addEventListener) {
        this._eventTarget.addEventListener("visibilitychange", this._onVisibility);
        this._eventTarget.addEventListener("beforeunload",   this._onBeforeUnload);
      }
    }
    // Detach the page-leave listeners so this backend can be garbage-collected
    // without leaking handlers across editor resets / hot reloads.
    dispose() {
      if (this._eventTarget && this._eventTarget.removeEventListener) {
        this._eventTarget.removeEventListener("visibilitychange", this._onVisibility);
        this._eventTarget.removeEventListener("beforeunload",   this._onBeforeUnload);
      }
      if (this._timer && this._clearTimeout) this._clearTimeout(this._timer);
      this._timer = null;
      this._pending.clear();
    }
    _url(cartId) { return this._apiUrl + "/save/" + encodeURIComponent(cartId); }
    async _authHeaders() {
      const token = await this._getToken();
      return { "Authorization": "Bearer " + token };
    }
    _schedulePush(cartId, json, delayMs) {
      this._pending.set(cartId, json);
      if (this._timer && this._clearTimeout) this._clearTimeout(this._timer);
      // Track the in-flight flush as a Promise on the instance so callers
      // and tests can `await b._flushed` to drain pending work without
      // racing on microtasks. The setTimeout-driven invocation can't be
      // awaited externally since the timer discards its return; the
      // Promise we attach here closes that observability gap.
      this._timer = this._setTimeout
        ? this._setTimeout(() => { this._flushed = this._flush(); }, delayMs)
        : null;
    }
    async _flush() {
      this._timer = null;
      if (this._authDead) { this._pending.clear(); return; }
      try {
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
      } catch (e) {
        // getToken (or anything else outside the per-entry try) threw.
        // Surfacing as warn so we don't leak unhandled rejections through
        // the timer-driven invocation. Pending stays — next attempt may
        // succeed once the token provider recovers.
        this._warn("CloudBackend: push aborted — " + (e && e.message || e));
      }
    }
    async _flushKeepalive() {
      if (this._pending.size === 0 || this._authDead) return;
      const headers = await this._authHeaders();
      const entries = Array.from(this._pending.entries());
      // Fire all PUTs synchronously: the page may be unloading any
      // moment, and keepalive requests must be issued before the
      // event handler returns to survive teardown. await'ing them
      // sequentially would let later entries race the unload.
      const inflight = entries.map(([cartId, json]) => {
        const p = this._fetch(this._url(cartId), {
          method: "PUT",
          headers: { ...headers, "Content-Type": "application/json" },
          body: JSON.stringify({ bucket: JSON.parse(json) }),
          keepalive: true,
        });
        return p.then(() => { this._pending.delete(cartId); }, () => {
          // Page is unloading — best-effort. Mirror is durable, retry on next boot.
        });
      });
      await Promise.all(inflight);
    }
    async read(cartId) {
      // Once the session is auth-dead (a 401 has poisoned getToken or the
      // session token), every read would be a guaranteed-failure round
      // trip. Skip the network and serve from the mirror.
      if (this._authDead) return this._mirror.read(cartId);
      // Wrap the entire read in try/catch so any thrown async (getToken
      // hang, IndexedDB lock, malformed JSON response, transient SDK bug)
      // falls back to the mirror instead of crashing Mono.boot. The
      // game's last-known-good state stays playable when the cloud is
      // unreachable for any reason — that's the offline-first guarantee.
      try {
        return await this._readNetwork(cartId);
      } catch (e) {
        this._warn("CloudBackend: read failed (" + (e && e.message || e) + ") — serving from mirror");
        return this._mirror.read(cartId);
      }
    }
    async _readNetwork(cartId) {
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
        // Empty bucket on a cart that has anonymous data MUST trigger
        // migration. Without this, a previously-corrupt R2 record (which
        // the worker rewrites to {bucket:{}} for graceful UX) silently
        // hides the user's anonymous progress on first login. Treat
        // "200 empty" the same as "404" for the migration check —
        // the cloud authoritatively has nothing for this cart, but the
        // local anon mirror has data we can recover.
        if (Object.keys(bucket).length === 0) {
          const migrated = this._tryMigrateAnon(cartId);
          if (migrated) return migrated;
        }
        this._mirror.write(cartId, JSON.stringify(bucket));
        return bucket;
      }
      if (res.status === 401) {
        this._authDead = true;
        this._warn("CloudBackend: 401 from cloud — disabling push for this session");
        return {};
      }
      if (res.status === 404) {
        const migrated = this._tryMigrateAnon(cartId);
        if (migrated) return migrated;
        return {};
      }
      // 5xx or other — fall back to mirror.
      return this._mirror.read(cartId);
    }
    // First login on this device with anonymous progress on the same
    // cartId? Read the anonymous mirror (DIFFERENT prefix from the
    // per-uid mirror), and if it has a usable bucket, write it through
    // to our mirror and schedule an immediate migration push. Anonymous
    // key is intentionally NOT removed. The push is scheduled (delay 0)
    // — fire-and-forget. The keepalive flush catches it on tab close;
    // the next debounce cycle catches it if the user keeps playing.
    // Tests observe it via `await b._flushed`. Returns the migrated
    // bucket on success, null when there's nothing to migrate.
    _tryMigrateAnon(cartId) {
      const anonRaw = this._storage ? this._storage.getItem(DEFAULT_KEY_PREFIX + cartId) : null;
      if (!anonRaw) return null;
      let anonBucket;
      try {
        const parsed = JSON.parse(anonRaw);
        if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) anonBucket = parsed;
      } catch {}
      if (!anonBucket) return null;
      this._mirror.write(cartId, anonRaw);
      this._schedulePush(cartId, anonRaw, 0);
      return anonBucket;
    }
    write(cartId, json) {
      // Mirror is the authoritative local copy. A failed cloud push must
      // not leave the mirror behind — so write to mirror first, push next.
      this._mirror.write(cartId, json);
      if (this._authDead) return;
      this._schedulePush(cartId, json, 1000);
    }
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
