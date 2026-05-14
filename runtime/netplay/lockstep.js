/**
 * Mono Lockstep Netplay — Protocol core
 *
 * Transport-agnostic. Drives the input queue, role negotiation, frame
 * scheduler, and VRAM-hash desync detection. Two peers exchanging
 * deterministic inputs at a fixed input-delay produce identical VRAM
 * frame-by-frame (verified every HASH_INTERVAL frames).
 *
 * Usage:
 *   const session = new MonoLockstep.LockstepSession({ transport, cartHash });
 *   session.start();                         // broadcast hello, wait for peer
 *   // each tick:
 *   session.poll();                          // drive matching/heartbeat
 *   if (session.status === "playing") {
 *     session.submitLocalInput(localBits);   // hardware → queue[+delay]
 *     if (!session.canAdvance()) draw_waiting();
 *     else {
 *       const inp = session.inputsForFrame(session.frame);
 *       run_update(inp[0], inp[1]); run_draw();
 *       if (session.frame % HASH_INTERVAL === 0)
 *         session.submitLocalHash(vramHash());
 *       session.advance();
 *     }
 *   }
 */
(() => {
  "use strict";

  const PROTO = 1;
  const DEFAULT_DELAY = 3;
  const HASH_INTERVAL = 30;
  const MATCHING_REBROADCAST_FRAMES = 10;

  class LockstepSession {
    constructor(opts) {
      if (!opts || !opts.transport) throw new Error("LockstepSession: transport required");
      this.transport = opts.transport;
      this.delay = opts.delay || DEFAULT_DELAY;
      this.cartHash = String(opts.cartHash || "default");
      this.now = opts.now || (() => Date.now());

      this.status = "idle";
      this.localPlayer = -1;
      this.seed = 0;
      this.frame = 0;
      this.queue = [new Map(), new Map()];
      this.peerHashes = new Map();
      this.localHashes = new Map();
      this.error = null;

      this._myTs = 0;
      this._peerTs = 0;
      this._matchingTicks = 0;

      this.transport.onMessage((m) => this._handleMessage(m));
    }

    start() {
      if (this.status !== "idle") return;
      this._myTs = this.now();
      this.status = "matching";
      this._broadcastHello();
    }

    poll() {
      if (this.status === "matching") {
        this._matchingTicks++;
        if (this._matchingTicks % MATCHING_REBROADCAST_FRAMES === 0) this._broadcastHello();
      }
    }

    submitLocalInput(bits) {
      if (this.status !== "playing") return -1;
      const target = this.frame + this.delay;
      this.queue[this.localPlayer].set(target, bits | 0);
      this.transport.send({ type: "input", frame: target, bits: bits | 0 });
      return target;
    }

    canAdvance() {
      if (this.status !== "playing") return false;
      const remote = 1 - this.localPlayer;
      return this.queue[remote].has(this.frame);
    }

    inputsForFrame(frame) {
      return [this.queue[0].get(frame) | 0, this.queue[1].get(frame) | 0];
    }

    submitLocalHash(hash) {
      if (this.status !== "playing") return;
      const h = hash >>> 0;
      this.localHashes.set(this.frame, h);
      this.transport.send({ type: "hash", frame: this.frame, hash: h });
      this._checkHash(this.frame);
    }

    advance() {
      if (this.status !== "playing") return;
      const f = this.frame;
      this.frame++;
      // Trim queues to keep memory bounded — anything strictly before the
      // current frame is no longer needed (we read frame=f then advance).
      this._trim(this.queue[0], f - 1);
      this._trim(this.queue[1], f - 1);
    }

    close() {
      if (this.status === "closed") return;
      try { this.transport.send({ type: "bye" }); } catch {}
      try { this.transport.close(); } catch {}
      this.status = "closed";
    }

    _trim(map, keepBelow) {
      for (const k of map.keys()) if (k < keepBelow) map.delete(k);
    }

    _broadcastHello() {
      this.transport.send({
        type: "hello",
        ts: this._myTs,
        cartHash: this.cartHash,
        proto: PROTO,
      });
    }

    _handleMessage(msg) {
      if (!msg || typeof msg !== "object") return;
      if (this.status === "closed") return;

      if (msg.type === "hello") {
        this._onHello(msg);
      } else if (msg.type === "input") {
        if (this.status !== "playing") return;
        const remote = 1 - this.localPlayer;
        this.queue[remote].set(msg.frame | 0, msg.bits | 0);
      } else if (msg.type === "hash") {
        if (this.status !== "playing") return;
        this.peerHashes.set(msg.frame | 0, msg.hash >>> 0);
        this._checkHash(msg.frame | 0);
      } else if (msg.type === "bye") {
        this.status = "closed";
      }
    }

    _onHello(msg) {
      if (this.status === "playing" || this.status === "desync") {
        // Late hello from a peer that re-broadcasted before seeing our ack —
        // ignore once we're already in session.
        return;
      }
      if (msg.cartHash !== this.cartHash) {
        this._fail("cart hash mismatch");
        return;
      }
      if ((msg.proto | 0) !== PROTO) {
        this._fail("protocol version mismatch");
        return;
      }
      if (this.status === "idle") {
        // Peer beat us to start(); join them.
        this._myTs = this.now();
        this.status = "matching";
      }
      // Ignore echoes of our own broadcast (same ts) — a transport might
      // round-trip if it doesn't filter sender.
      if (msg.ts === this._myTs && msg.ts !== 0) return;
      // Store the full Number (Date.now() is ~1.78e12 and overflows 32-bit).
      // Previous `msg.ts | 0` truncation collapsed every peer ts into the
      // signed-int range, causing both peers to compare their full _myTs
      // against a truncated _peerTs and both end up as localPlayer = 1.
      this._peerTs = Number(msg.ts);
      this._pair();
      // Re-broadcast our hello once after pairing so a peer that just came
      // up sees us. Idempotent: peers already paired ignore late hellos.
      this._broadcastHello();
    }

    _pair() {
      // Lower ts = host (player 0). Tiebreak with proto-stable rule.
      if (this._myTs < this._peerTs) this.localPlayer = 0;
      else if (this._myTs > this._peerTs) this.localPlayer = 1;
      else this.localPlayer = 0; // tie — both peers can't actually tie a wall-clock unless mocked

      // Seed mixes both ts as 32-bit halves so peers agree without losing
      // entropy. `^` of full Numbers would lose precision above 2^32.
      const a = (this._myTs   >>> 0) ^ Math.floor(this._myTs   / 0x100000000);
      const b = (this._peerTs >>> 0) ^ Math.floor(this._peerTs / 0x100000000);
      this.seed = ((a ^ b) >>> 0) || 1;
      for (let f = 0; f < this.delay; f++) {
        this.queue[0].set(f, 0);
        this.queue[1].set(f, 0);
      }
      this.status = "playing";
    }

    _checkHash(frame) {
      const peer = this.peerHashes.get(frame);
      const mine = this.localHashes.get(frame);
      if (peer === undefined || mine === undefined) return;
      if (peer !== mine) {
        this.status = "desync";
        this.error = `desync at frame ${frame}: local=${mine.toString(16)} peer=${peer.toString(16)}`;
      }
    }

    _fail(reason) {
      this.status = "closed";
      this.error = reason;
    }
  }

  const NS = {
    LockstepSession,
    PROTO,
    DEFAULT_DELAY,
    HASH_INTERVAL,
  };
  if (typeof module !== "undefined" && module.exports) module.exports = NS;
  else if (typeof globalThis !== "undefined") globalThis.MonoLockstep = NS;
})();
