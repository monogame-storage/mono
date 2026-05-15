/**
 * Mono Lockstep Netplay — Protocol core
 *
 * Transport-agnostic. Drives the input queue, frame scheduler, and
 * VRAM-hash desync detection. Two peers exchanging deterministic inputs
 * at a fixed input-delay produce identical VRAM frame-by-frame (verified
 * every HASH_INTERVAL frames).
 *
 * Roles are set EXTERNALLY by the runner (whoever calls host() vs join()
 * on the transport). Host (player 0) generates the shared seed and sends
 * it in the init message as soon as the channel opens. Joiner (player 1)
 * waits for that message and ACKs.
 *
 * Usage:
 *   // Host side:
 *   const session = new MonoLockstep.LockstepSession({ transport, cartHash });
 *   session.startAsHost();
 *
 *   // Joiner side:
 *   const session = new MonoLockstep.LockstepSession({ transport, cartHash });
 *   session.startAsJoiner();
 *
 *   // Each engine tick (once status === "playing"):
 *   session.submitLocalInput(localBits);
 *   if (!session.canAdvance()) draw_waiting();
 *   else {
 *     const inp = session.inputsForFrame(session.frame);
 *     run_update(inp[0], inp[1]); run_draw();
 *     if (session.frame % HASH_INTERVAL === 0)
 *       session.submitLocalHash(vramHash());
 *     session.advance();
 *   }
 */
(() => {
  "use strict";

  const PROTO = 1;
  const DEFAULT_DELAY = 3;
  const HASH_INTERVAL = 30;

  class LockstepSession {
    constructor(opts) {
      if (!opts || !opts.transport) throw new Error("LockstepSession: transport required");
      this.transport = opts.transport;
      this.delay = opts.delay || DEFAULT_DELAY;
      this.cartHash = String(opts.cartHash || "default");
      this._rng = opts.rng || (() => Math.floor(Math.random() * 0xffffffff) >>> 0);

      this.status = "idle";        // idle | matching | playing | desync | closed
      this.localPlayer = -1;
      this.seed = 0;
      this.frame = 0;
      this.queue = [new Map(), new Map()];
      this.peerHashes = new Map();
      this.localHashes = new Map();
      this.error = null;

      this.transport.onMessage((m) => this._handleMessage(m));
      // When the underlying channel drops (peer closed tab, network gone),
      // flip status to "closed" so the engine's overlay surfaces it. We
      // preserve "desync" because that's a more specific failure mode.
      if (typeof this.transport.onClose === "function") {
        this.transport.onClose(() => this._onTransportClose());
      }
    }

    _onTransportClose() {
      if (this.status === "closed" || this.status === "desync") return;
      this.status = "closed";
      this.error = this.error || "peer disconnected";
    }

    startAsHost() {
      if (this.status !== "idle") return;
      this.localPlayer = 0;
      this.seed = (this._rng() >>> 0) || 1;
      this.status = "matching";
      // Sent as soon as the transport's data channel opens; transports
      // buffer until ready so this is safe to call before the peer connects.
      this.transport.send({
        type: "init",
        proto: PROTO,
        seed: this.seed,
        cartHash: this.cartHash,
        delay: this.delay,
      });
    }

    startAsJoiner() {
      if (this.status !== "idle") return;
      this.localPlayer = 1;
      this.status = "matching";
      // Joiner waits for the host's init message before transitioning.
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

    _handleMessage(msg) {
      if (!msg || typeof msg !== "object") return;
      if (this.status === "closed") return;

      if (msg.type === "init") {
        if (this.localPlayer !== 1) return; // only joiner accepts init
        if (this.status !== "matching") return;
        if (msg.cartHash !== this.cartHash) { this._fail("cart hash mismatch"); return; }
        if ((msg.proto | 0) !== PROTO) { this._fail("protocol version mismatch"); return; }
        if (typeof msg.delay === "number" && msg.delay > 0) this.delay = msg.delay | 0;
        this.seed = (msg.seed >>> 0) || 1;
        this._prefillDelay();
        this.status = "playing";
        // Ack back so host transitions too.
        this.transport.send({ type: "init_ack" });
      } else if (msg.type === "init_ack") {
        if (this.localPlayer !== 0) return; // only host expects ack
        if (this.status !== "matching") return;
        this._prefillDelay();
        this.status = "playing";
      } else if (msg.type === "input") {
        if (this.status !== "playing") return;
        const remote = 1 - this.localPlayer;
        this.queue[remote].set(msg.frame | 0, msg.bits | 0);
      } else if (msg.type === "hash") {
        if (this.status !== "playing") return;
        this.peerHashes.set(msg.frame | 0, msg.hash >>> 0);
        this._checkHash(msg.frame | 0);
      } else if (msg.type === "bye") {
        if (this.status !== "desync") {
          this.status = "closed";
          this.error = this.error || "peer left";
        }
      }
    }

    _prefillDelay() {
      for (let f = 0; f < this.delay; f++) {
        this.queue[0].set(f, 0);
        this.queue[1].set(f, 0);
      }
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

  const NS = { LockstepSession, PROTO, DEFAULT_DELAY, HASH_INTERVAL };
  if (typeof module !== "undefined" && module.exports) module.exports = NS;
  else if (typeof globalThis !== "undefined") globalThis.MonoLockstep = NS;
})();
