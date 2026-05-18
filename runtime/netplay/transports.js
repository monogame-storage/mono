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
 *   WebRTCTransport                   — RTCPeerConnection + ordered DataChannel
 *                                       with manual SDP offer/answer paste
 *                                       (no signaling server, anonymous)
 */
(() => {
  "use strict";

  // ── InProcessTransport ─────────────────────────────────────────────────
  // Two endpoints share a pair of queues. Messages are delivered on a
  // microtask so callers see realistic async ordering. Closing one side
  // notifies the peer's onClose handler so tests can exercise the
  // peer-disconnect path that WebRTC's DataChannel onclose covers in prod.
  class InProcessTransport {
    constructor(out, inbox) {
      this._out = out;
      this._inbox = inbox;
      this._handler = null;
      this._onClose = null;
      this._closed = false;
      this._peer = null;
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
    onClose(cb)   { this._onClose = cb; }
    close() {
      if (this._closed) return;
      this._closed = true;
      const peer = this._peer;
      if (peer && !peer._closed) {
        queueMicrotask(() => { if (peer._onClose) peer._onClose(); });
      }
    }

    static pair() {
      const qA = new _Queue();
      const qB = new _Queue();
      const a = new InProcessTransport(qB, qA);
      const b = new InProcessTransport(qA, qB);
      a._peer = b; b._peer = a;
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

  // ── WebRTCTransport ────────────────────────────────────────────────────
  // Host calls createOffer() → base64 SDP. Joiner pastes that into
  // createAnswer() → returns its own base64 SDP. Host pastes that into
  // acceptAnswer(). DataChannel opens; both sides exchange JSON messages.
  //
  // ICE gathering is complete-before-return ("non-trickle"): we wait for
  // iceGatheringState === "complete" before encoding the SDP, so the
  // pasted blob is self-contained — no out-of-band candidate exchange.
  // Trade-off: ~1-2 s delay on offer/answer generation; we accept that
  // for a much simpler paste flow.
  const DEFAULT_ICE = [{ urls: "stun:stun.l.google.com:19302" }];

  class WebRTCTransport {
    constructor(opts = {}) {
      if (typeof RTCPeerConnection === "undefined") {
        throw new Error("WebRTC unavailable in this environment");
      }
      this._pc = new RTCPeerConnection({ iceServers: opts.iceServers || DEFAULT_ICE });
      this._dc = null;
      this._handler = null;
      this._buf = [];
      this._closed = false;
      this._role = null;            // "host" | "joiner"
      this._onOpen = null;
      this._onClose = null;
      this._pc.ondatachannel = (ev) => this._attachChannel(ev.channel);
    }

    onOpen(cb)  { this._onOpen = cb; }
    onClose(cb) { this._onClose = cb; }
    onMessage(cb) { this._handler = cb; }

    _attachChannel(ch) {
      this._dc = ch;
      ch.binaryType = "arraybuffer";
      ch.onopen = () => {
        for (const m of this._buf) ch.send(JSON.stringify(m));
        this._buf = [];
        if (this._onOpen) this._onOpen();
      };
      ch.onmessage = (ev) => {
        if (this._closed) return;
        try {
          const msg = JSON.parse(ev.data);
          if (this._handler) this._handler(msg);
        } catch {}
      };
      ch.onclose = () => {
        if (this._closed) return;
        this._closed = true;
        if (this._onClose) this._onClose();
      };
    }

    async createOffer() {
      if (this._role) throw new Error("WebRTCTransport: already in use");
      this._role = "host";
      this._attachChannel(this._pc.createDataChannel("mono", { ordered: true }));
      const offer = await this._pc.createOffer();
      await this._pc.setLocalDescription(offer);
      await this._waitIceComplete();
      return _encodeSDP(this._pc.localDescription);
    }

    async createAnswer(offerCode) {
      if (this._role) throw new Error("WebRTCTransport: already in use");
      this._role = "joiner";
      await this._pc.setRemoteDescription(_decodeSDP(offerCode));
      const answer = await this._pc.createAnswer();
      await this._pc.setLocalDescription(answer);
      await this._waitIceComplete();
      return _encodeSDP(this._pc.localDescription);
    }

    async acceptAnswer(answerCode) {
      if (this._role !== "host") throw new Error("acceptAnswer: not host");
      await this._pc.setRemoteDescription(_decodeSDP(answerCode));
    }

    send(msg) {
      if (this._closed) return;
      if (!this._dc || this._dc.readyState !== "open") {
        this._buf.push(msg);
        return;
      }
      this._dc.send(JSON.stringify(msg));
    }

    close() {
      if (this._closed) return;
      this._closed = true;
      try { this._dc && this._dc.close(); } catch {}
      try { this._pc.close(); } catch {}
    }

    _waitIceComplete() {
      return new Promise((resolve) => {
        if (this._pc.iceGatheringState === "complete") return resolve();
        const onChange = () => {
          if (this._pc.iceGatheringState === "complete") {
            this._pc.removeEventListener("icegatheringstatechange", onChange);
            resolve();
          }
        };
        this._pc.addEventListener("icegatheringstatechange", onChange);
        // Failsafe: some browsers stall at "gathering" if no candidates appear.
        setTimeout(() => {
          this._pc.removeEventListener("icegatheringstatechange", onChange);
          resolve();
        }, 4000);
      });
    }
  }

  function _encodeSDP(desc) {
    // Compact: { t: type-char, s: SDP }. Base64 + URL-safe.
    const obj = { t: desc.type[0], s: desc.sdp };
    const json = JSON.stringify(obj);
    return _b64UrlSafe(json);
  }

  function _decodeSDP(code) {
    const json = _b64UrlDecode(String(code).trim());
    const obj = JSON.parse(json);
    const type = obj.t === "o" ? "offer" : obj.t === "a" ? "answer" : obj.type;
    return { type, sdp: obj.s };
  }

  function _b64UrlSafe(s) {
    const b64 = btoa(unescape(encodeURIComponent(s)));
    return b64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }
  function _b64UrlDecode(s) {
    const b64 = s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4);
    return decodeURIComponent(escape(atob(b64)));
  }

  const NS = { InProcessTransport, WebRTCTransport };
  if (typeof module !== "undefined" && module.exports) module.exports = NS;
  else if (typeof globalThis !== "undefined") globalThis.MonoNetTransports = NS;
})();
