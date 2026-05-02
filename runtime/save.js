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
