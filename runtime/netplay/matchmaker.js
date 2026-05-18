/**
 * Mono Netplay — Firestore-based matchmaker
 *
 * Pairs two peers on a shared cart via a single Firestore collection:
 *
 *   /netplay-rooms (auto-id docs)
 *     { cartId, state, hostUid, offer, createdAt, joinerUid?, answer? }
 *
 * Dependency-injected (Firestore SDK + transport factory) so tests can
 * swap in fakes. The browser entry point (play.html) wires the real
 * Firestore SDK and WebRTCTransport in.
 *
 * Two strategies, selectable per matchmaker instance:
 *
 *   "legacy"            — query → createOffer → addDoc. The original
 *                          flow. Race-window = ICE gathering (~1-2 s):
 *                          peers arriving in that window all become hosts.
 *
 *   "reserve-then-fill" — the fix, combining three guards against the
 *                          burst-pairing race:
 *
 *     1. Reserve-then-fill: addDoc({offer:""}) first, then createOffer,
 *        then updateDoc(offer). Joiner waits via onSnapshot if the room
 *        is still mid-ICE. Shrinks the host-host collision window from
 *        ~2 s (ICE) to ~one Firestore RTT (~100 ms).
 *
 *     2. Reserve-then-confirm: after reserving, briefly wait, then
 *        re-query. If a strictly older signaling room exists, delete
 *        our reservation and become a joiner of that older room.
 *        Catches simultaneous reserve calls where both peers' addDocs
 *        commit within the RTT window.
 *
 *     3. Phase-1 atomic claim: joiners claim the host's room via a fast
 *        transaction (state→"claiming", joinerUid) BEFORE running their
 *        own ICE for the answer. Losers get RACE_TAKEN immediately —
 *        no wasted ICE — and re-enter the flow with a small jitter
 *        so they don't stampede each other as new hosts.
 *
 * The strategy parameter exists so the headless tests can demonstrate
 * the bug under "legacy" and the fix under "reserve-then-fill". Prod
 * defaults to "reserve-then-fill".
 */
(() => {
  "use strict";

  const ROOM_STALE_MS           = 30000;
  const HOST_WAIT_FOR_ANSWER_MS = 60000;
  const DC_OPEN_TIMEOUT_MS      = 30000;
  const WAIT_OFFER_MS           = 10000;
  // confirmReserveMs adds latency to every host startup — but it has to
  // be wider than the Firestore RTT × ~2 to catch concurrent reservers
  // that committed shortly after us. 300 ms covers a 50-150 ms RTT range
  // comfortably; tune down if your network is fast and predictable.
  const CONFIRM_RESERVE_MS      = 300;
  const RACE_RETRY_JITTER_MS    = 400;

  function createMatchmaker(deps) {
    const {
      db, fs,
      createTransport,
      ensureAuth,
      now,
      strategy,
      timeouts,
    } = deps;

    const _nowMs = now || (() => Date.now());
    const _strategy = strategy || "reserve-then-fill";
    const T = {
      roomStaleMs:          (timeouts && timeouts.roomStaleMs)          || ROOM_STALE_MS,
      hostWaitForAnswerMs:  (timeouts && timeouts.hostWaitForAnswerMs)  || HOST_WAIT_FOR_ANSWER_MS,
      dcOpenTimeoutMs:      (timeouts && timeouts.dcOpenTimeoutMs)      || DC_OPEN_TIMEOUT_MS,
      waitOfferMs:          (timeouts && timeouts.waitOfferMs)          || WAIT_OFFER_MS,
      confirmReserveMs:     (timeouts && timeouts.confirmReserveMs != null) ? timeouts.confirmReserveMs : CONFIRM_RESERVE_MS,
      raceRetryJitterMs:    (timeouts && timeouts.raceRetryJitterMs != null) ? timeouts.raceRetryJitterMs : RACE_RETRY_JITTER_MS,
    };

    let _cancelled = false;
    let _activeUnsub = null;
    const state = {
      activeRoomRef: null,
      activeRoomPath: null,
    };

    async function _findOpenRoom(cartId) {
      const cutoff = fs.Timestamp.fromMillis(_nowMs() - T.roomStaleMs);
      const q = fs.query(
        fs.collection(db, "netplay-rooms"),
        fs.where("cartId", "==", cartId),
        fs.where("state",  "==", "signaling"),
        fs.where("createdAt", ">", cutoff),
        fs.orderBy("createdAt", "asc"),
        fs.limit(1),
      );
      const snap = await fs.getDocs(q);
      return snap.empty ? null : snap.docs[0];
    }

    function _awaitOfferField(roomRef) {
      return new Promise((resolve, reject) => {
        const unsub = fs.onSnapshot(roomRef, (snap) => {
          if (!snap.exists()) { try { unsub(); } catch {} reject(new Error("room vanished")); return; }
          const d = snap.data();
          if (d.offer) { try { unsub(); } catch {} resolve(d.offer); return; }
          if (d.state !== "signaling") { try { unsub(); } catch {} reject(new Error("room state changed: " + d.state)); }
        });
      });
    }

    function _withTimeout(promise, ms, msg) {
      return new Promise((resolve, reject) => {
        const t = setTimeout(() => reject(new Error(msg)), ms);
        promise.then(
          (v) => { clearTimeout(t); resolve(v); },
          (e) => { clearTimeout(t); reject(e); },
        );
      });
    }

    async function autoMatch({ cartId, onStatus, onRole }) {
      _cancelled = false;
      const status = onStatus || (() => {});
      if (!cartId) throw new Error("autoMatch: cartId required");
      const u = await ensureAuth();

      status("Looking for an open room…");
      const existing = await _findOpenRoom(cartId);
      const transport = createTransport();

      let role, roomRef;
      if (!existing) {
        role = "host";
        if (_strategy === "legacy") {
          // Old flow: do the slow ICE work BEFORE publishing the doc.
          status("Generating offer…");
          const offerCode = await transport.createOffer();
          if (_cancelled) { try { transport.close(); } catch {}; return null; }
          status("Creating room…");
          roomRef = await fs.addDoc(fs.collection(db, "netplay-rooms"), {
            cartId,
            state: "signaling",
            hostUid: u.uid,
            offer: offerCode,
            createdAt: fs.serverTimestamp(),
          });
          state.activeRoomRef  = roomRef;
          state.activeRoomPath = "netplay-rooms/" + roomRef.id;
          if (onRole) onRole(role, state.activeRoomPath);
        } else {
          // reserve-then-fill: publish the slot first, ICE in background,
          // then patch in the offer. This shrinks the race window from
          // ~2 s (ICE) to ~one Firestore RTT (~100 ms).
          status("Reserving room…");
          roomRef = await fs.addDoc(fs.collection(db, "netplay-rooms"), {
            cartId,
            state: "signaling",
            hostUid: u.uid,
            offer: "",
            createdAt: fs.serverTimestamp(),
          });
          if (_cancelled) { try { transport.close(); } catch {}; try { await fs.deleteDoc(roomRef); } catch {}; return null; }
          state.activeRoomRef  = roomRef;
          state.activeRoomPath = "netplay-rooms/" + roomRef.id;
          if (onRole) onRole(role, state.activeRoomPath);

          // reserve-then-confirm: wait briefly for any concurrent
          // reservers to commit, then re-query. If a strictly older
          // signaling room exists, defer to it instead. This converts
          // a same-RTT host stampede into clean host+joiner pairs.
          if (T.confirmReserveMs > 0) {
            await new Promise((r) => setTimeout(r, T.confirmReserveMs));
            if (_cancelled) {
              try { transport.close(); } catch {}
              try { await fs.deleteDoc(roomRef); } catch {}
              state.activeRoomRef = null; state.activeRoomPath = null;
              return null;
            }
            const earliest = await _findOpenRoom(cartId);
            if (earliest && earliest.ref.id !== roomRef.id) {
              status("Older host found — deferring…");
              try { await fs.deleteDoc(roomRef); } catch {}
              state.activeRoomRef = null; state.activeRoomPath = null;
              try { transport.close(); } catch {}
              return autoMatch({ cartId, onStatus, onRole });
            }
          }

          status("Generating offer…");
          let offerCode;
          try {
            offerCode = await transport.createOffer();
          } catch (e) {
            try { await fs.deleteDoc(roomRef); } catch {}
            state.activeRoomRef = null; state.activeRoomPath = null;
            throw e;
          }
          if (_cancelled) {
            try { transport.close(); } catch {}
            try { await fs.deleteDoc(roomRef); } catch {}
            state.activeRoomRef = null; state.activeRoomPath = null;
            return null;
          }
          status("Publishing offer…");
          await fs.updateDoc(roomRef, { offer: offerCode });
        }
      } else {
        role = "joiner";
        roomRef = existing.ref;
        if (onRole) onRole(role, "netplay-rooms/" + roomRef.id);
        let offerCode = existing.data().offer;
        if (!offerCode) {
          // Under "legacy" this never happens (rooms only become visible
          // once offer is filled). Under reserve-then-fill it's the
          // common case for a peer arriving while host is mid-ICE.
          status("Waiting for host's offer…");
          try {
            offerCode = await _withTimeout(_awaitOfferField(roomRef),
              T.waitOfferMs, "host did not publish offer in time");
          } catch (e) {
            try { transport.close(); } catch {}
            try { await fs.deleteDoc(roomRef); } catch {}
            return autoMatch({ cartId, onStatus, onRole });
          }
          if (_cancelled) { try { transport.close(); } catch {}; return null; }
        }
        // Phase-1 atomic claim: mark the room as "claiming" with our uid
        // BEFORE running ICE for the answer. When 3+ joiners all see the
        // same host's offer, only one wins phase-1 — the rest get
        // RACE_TAKEN immediately, without wasting 1-2 s of ICE work.
        status("Claiming room…");
        try {
          await fs.runTransaction(db, async (tx) => {
            const snap = await tx.get(roomRef);
            const data = snap.exists() ? snap.data() : null;
            if (!data || data.state !== "signaling" || data.joinerUid) {
              throw new Error("RACE_TAKEN");
            }
            tx.update(roomRef, { state: "claiming", joinerUid: u.uid });
          });
        } catch (e) {
          try { transport.close(); } catch {}
          if (String(e.message).includes("RACE_TAKEN")) {
            // Jitter before retry: when several losers re-enter at once
            // they otherwise query Firestore in lockstep, see "empty"
            // (no committed reservations yet from the other losers),
            // and collide as hosts again. A short random delay lets
            // the first retrier's addDoc commit before the others query.
            await new Promise((r) => setTimeout(r, Math.random() * T.raceRetryJitterMs));
            return autoMatch({ cartId, onStatus, onRole });
          }
          throw e;
        }

        status("Generating answer…");
        let answerCode;
        try {
          answerCode = await transport.createAnswer(offerCode);
        } catch (e) {
          // Release the claim so the host can either pair with a fresh
          // joiner or time out cleanly.
          try { await fs.updateDoc(roomRef, { state: "signaling", joinerUid: null }); } catch {}
          try { transport.close(); } catch {}
          throw e;
        }
        if (_cancelled) {
          try { await fs.updateDoc(roomRef, { state: "signaling", joinerUid: null }); } catch {}
          try { transport.close(); } catch {}
          return null;
        }
        status("Publishing answer…");
        try {
          await fs.updateDoc(roomRef, { state: "paired", answer: answerCode });
        } catch (e) {
          // Host gave up (timed out, tab closed) and deleted the room
          // while we were ICE-ing the answer. Real Firestore returns
          // NOT_FOUND / FAILED_PRECONDITION here; treat as a race loss
          // and retry the whole flow.
          try { transport.close(); } catch {}
          await new Promise((r) => setTimeout(r, Math.random() * T.raceRetryJitterMs));
          return autoMatch({ cartId, onStatus, onRole });
        }
      }
      if (_cancelled) {
        try { transport.close(); } catch {}
        if (role === "host") { try { await fs.deleteDoc(roomRef); } catch {} }
        return null;
      }

      if (role === "host") {
        status("Waiting for joiner…");
        try {
          await _withTimeout(new Promise((resolve, reject) => {
            _activeUnsub = fs.onSnapshot(roomRef, (snap) => {
              if (_cancelled) { resolve(); return; }
              if (!snap.exists()) return;
              const d = snap.data();
              if (d.answer && d.state === "paired") {
                const unsub = _activeUnsub; _activeUnsub = null;
                try { unsub(); } catch {}
                transport.acceptAnswer(d.answer).then(resolve, reject);
              }
            });
          }), T.hostWaitForAnswerMs, "no joiner within " + (T.hostWaitForAnswerMs / 1000) + " s");
        } catch (e) {
          if (_activeUnsub) { try { _activeUnsub(); } catch {} _activeUnsub = null; }
          try { transport.close(); } catch {}
          try { await fs.deleteDoc(roomRef); } catch {}
          state.activeRoomRef = null; state.activeRoomPath = null;
          throw e;
        }
      }

      status("Opening data channel…");
      try {
        await _withTimeout(new Promise((resolve) => {
          let resolved = false;
          if (typeof transport.onOpen === "function") {
            transport.onOpen(() => { if (!resolved) { resolved = true; resolve(); } });
          }
          setTimeout(() => {
            if (resolved) return;
            if (transport.isOpen && transport.isOpen()) { resolved = true; resolve(); }
            else if (transport._dc && transport._dc.readyState === "open") { resolved = true; resolve(); }
          }, 100);
        }), T.dcOpenTimeoutMs, "data channel did not open within " + (T.dcOpenTimeoutMs / 1000) + " s");
      } catch (e) {
        try { transport.close(); } catch {}
        if (role === "host") { try { await fs.deleteDoc(roomRef); } catch {} }
        state.activeRoomRef = null; state.activeRoomPath = null;
        throw e;
      }

      if (role === "host") {
        try { await fs.deleteDoc(roomRef); } catch {}
      }
      state.activeRoomRef = null; state.activeRoomPath = null;
      status(role === "host" ? "Connected as host" : "Connected as joiner");
      return { role, transport };
    }

    function cancel() {
      _cancelled = true;
      if (_activeUnsub) { try { _activeUnsub(); } catch {} _activeUnsub = null; }
    }

    function getActiveRoomPath() { return state.activeRoomPath; }

    return { autoMatch, cancel, getActiveRoomPath };
  }

  const NS = { createMatchmaker, ROOM_STALE_MS, HOST_WAIT_FOR_ANSWER_MS, DC_OPEN_TIMEOUT_MS, WAIT_OFFER_MS };
  if (typeof module !== "undefined" && module.exports) module.exports = NS;
  else if (typeof globalThis !== "undefined") globalThis.MonoNetMatchmaker = NS;
})();
