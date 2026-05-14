/**
 * Mono Lockstep Netplay — Transports
 *
 * Transport interface:
 *   transport.send(msg)               — fire-and-forget; msg is JSON-serializable
 *   transport.onMessage(cb)           — register a handler; called per inbound msg
 *   transport.close()                 — release resources
 *
 * Two implementations:
 *   InProcessTransport.pair()         — synchronous in-memory pair (for tests)
 *   BroadcastChannelTransport         — same-origin tab pair via BroadcastChannel
 *                                       (no signaling, no server, anonymous)
 */
(() => {
  "use strict";

  // ── InProcessTransport ─────────────────────────────────────────────────
  // Two endpoints share a pair of queues. Messages are delivered on a
  // microtask so callers see realistic async ordering.
  class InProcessTransport {
    constructor(out, inbox) {
      this._out = out;
      this._inbox = inbox;
      this._handler = null;
      this._closed = false;
      // Drain queue once handler is attached.
      this._inbox.subscribe((msg) => {
        if (this._closed) return;
        if (this._handler) this._handler(msg);
      });
    }
    send(msg) {
      if (this._closed) return;
      const copy = JSON.parse(JSON.stringify(msg));
      this._out.push(copy);
    }
    onMessage(cb) { this._handler = cb; }
    close() { this._closed = true; }

    static pair() {
      const qA = new _Queue();
      const qB = new _Queue();
      // A's outbox is B's inbox, and vice versa.
      const a = new InProcessTransport(qB, qA);
      const b = new InProcessTransport(qA, qB);
      return [a, b];
    }
  }

  class _Queue {
    constructor() { this._sub = null; this._buf = []; }
    subscribe(cb) {
      this._sub = cb;
      const buf = this._buf; this._buf = [];
      for (const m of buf) cb(m);
    }
    push(msg) {
      if (this._sub) queueMicrotask(() => { if (this._sub) this._sub(msg); });
      else this._buf.push(msg);
    }
  }

  // ── BroadcastChannelTransport ──────────────────────────────────────────
  // Same-origin, multi-tab. No signaling server. Each tab opens the same
  // channel name and posts/receives messages. Echo of our own posts is
  // filtered via a per-tab nonce.
  class BroadcastChannelTransport {
    constructor(channelName) {
      if (typeof BroadcastChannel === "undefined") {
        throw new Error("BroadcastChannel unavailable in this environment");
      }
      this._ch = new BroadcastChannel(channelName);
      this._nonce = (Math.random() * 0xffffffff) >>> 0;
      this._handler = null;
      this._closed = false;
      this._ch.onmessage = (ev) => {
        if (this._closed) return;
        const d = ev.data;
        if (!d || d._from === this._nonce) return; // ignore self-echo
        if (this._handler) this._handler(d.msg);
      };
    }
    send(msg) {
      if (this._closed) return;
      this._ch.postMessage({ _from: this._nonce, msg });
    }
    onMessage(cb) { this._handler = cb; }
    close() {
      if (this._closed) return;
      this._closed = true;
      try { this._ch.close(); } catch {}
    }
  }

  const NS = { InProcessTransport, BroadcastChannelTransport };
  if (typeof module !== "undefined" && module.exports) module.exports = NS;
  else if (typeof globalThis !== "undefined") globalThis.MonoNetTransports = NS;
})();
