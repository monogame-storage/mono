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

  return {
    MemoryBackend,
    serializeBucket,
    deserializeBucket,
    QUOTA_BYTES,
    MAX_KEY_LEN,
    MAX_DEPTH,
  };
});
