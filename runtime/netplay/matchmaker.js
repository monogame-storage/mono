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
 *
 * A matchmaker instance is single-use: call autoMatch() once. cancel()
 * persists for the lifetime of the instance, so internal retries
 * triggered by races never silently override an external cancel. Create
 * a fresh matchmaker per pairing attempt.
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
  // Bound on internal retries (defer, RACE_TAKEN, missing-doc). Each
  // attempt is one full pass through autoMatch. 8 covers the cascade
  // depth even under an 8-peer burst — beyond that we're in
  // pathological contention and surfacing the error is the right call.
  const MAX_ATTEMPTS            = 8;

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
      maxAttempts:          (timeouts && timeouts.maxAttempts)          || MAX_ATTEMPTS,
    };

    // Lifetime-of-instance state. Cancel set here (not inside autoMatch)
    // so an external cancel() during an internal retry isn't overridden
    // when the recursive autoMatch starts a fresh pass.
    let _cancelled = false;
    let _attempts  = 0;
    // Cancel hooks: each pending listener registers a teardown so
    // cancel() can reject its host promise and unsub the snapshot
    // listener even when the awaited event never fires.
    const _cancelHooks = new Set();
    function _onCancel(cb) { _cancelHooks.add(cb); return () => _cancelHooks.delete(cb); }

    // Cleanup helpers — most exception paths need exactly these two
    // best-effort calls. Inlining them everywhere was just noise.
    function _close(t)      { try { if (t) t.close(); } catch {} }
    async function _del(ref) { try { await fs.deleteDoc(ref); } catch {} }

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

    // Resolves to the offer string when the host fills it in, or rejects
    // on timeout, room deletion, state change, or cancel. The snapshot
    // listener is guaranteed to be unsubscribed in every settlement
    // path, including timeout and cancel — important because Firestore
    // listeners survive page-level GC and accumulate quota cost.
    function _awaitOffer(roomRef, timeoutMs) {
      return new Promise((resolve, reject) => {
        let settled = false;
        let unsub = null;
        let releaseCancel = null;
        const cleanup = () => {
          if (settled) return; settled = true;
          clearTimeout(t);
          if (unsub) { try { unsub(); } catch {} }
          if (releaseCancel) releaseCancel();
        };
        const t = setTimeout(() => {
          cleanup(); reject(new Error("host did not publish offer in time"));
        }, timeoutMs);
        releaseCancel = _onCancel(() => {
          cleanup(); reject(new Error("cancelled"));
        });
        unsub = fs.onSnapshot(roomRef, (snap) => {
          if (settled) return;
          if (!snap.exists())                { cleanup(); reject(new Error("room vanished")); return; }
          const d = snap.data();
          if (d.offer)                       { cleanup(); resolve(d.offer); return; }
          if (d.state !== "signaling")       { cleanup(); reject(new Error("room state changed: " + d.state)); }
        });
      });
    }

    // Resolves when the joiner's answer lands and acceptAnswer succeeds,
    // or rejects on timeout / cancel / acceptAnswer error. Same listener
    // cleanup discipline as _awaitOffer.
    function _awaitAnswerAndAccept(roomRef, transport, timeoutMs) {
      return new Promise((resolve, reject) => {
        let settled = false;
        let unsub = null;
        let releaseCancel = null;
        const cleanup = () => {
          if (settled) return; settled = true;
          clearTimeout(t);
          if (unsub) { try { unsub(); } catch {} }
          if (releaseCancel) releaseCancel();
        };
        const t = setTimeout(() => {
          cleanup(); reject(new Error("no joiner within " + (timeoutMs / 1000) + " s"));
        }, timeoutMs);
        releaseCancel = _onCancel(() => {
          cleanup(); reject(new Error("cancelled"));
        });
        unsub = fs.onSnapshot(roomRef, (snap) => {
          if (settled) return;
          if (!snap.exists()) return;
          const d = snap.data();
          if (d.answer && d.state === "paired") {
            cleanup();
            transport.acceptAnswer(d.answer).then(resolve, reject);
          }
        });
      });
    }

    // Resolves when the underlying DataChannel opens, or rejects on
    // timeout. Cancel isn't observed here because by this point the
    // transport itself owns the work — close() on the transport is the
    // user-visible cancel path.
    function _awaitChannelOpen(transport, timeoutMs) {
      return new Promise((resolve, reject) => {
        let settled = false;
        const settle = (ok, err) => {
          if (settled) return; settled = true;
          clearTimeout(t);
          ok ? resolve() : reject(err);
        };
        const t = setTimeout(() => settle(false, new Error("data channel did not open within " + (timeoutMs / 1000) + " s")), timeoutMs);
        if (typeof transport.onOpen === "function") {
          transport.onOpen(() => settle(true));
        }
        // Pre-registered open: some transports flip to open before we
        // attach the callback (in-process pair, fast loopback).
        setTimeout(() => {
          if (settled) return;
          if (transport.isOpen && transport.isOpen()) settle(true);
          else if (transport._dc && transport._dc.readyState === "open") settle(true);
        }, 100);
      });
    }

    async function autoMatch({ cartId, onStatus, onRole }) {
      const status = onStatus || (() => {});
      if (!cartId) throw new Error("autoMatch: cartId required");
      if (_cancelled) return null;
      if (++_attempts > T.maxAttempts) {
        throw new Error("autoMatch: exceeded " + T.maxAttempts + " attempts (persistent contention)");
      }
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
          if (_cancelled) { _close(transport); return null; }
          status("Creating room…");
          roomRef = await fs.addDoc(fs.collection(db, "netplay-rooms"), {
            cartId, state: "signaling", hostUid: u.uid, offer: offerCode, createdAt: fs.serverTimestamp(),
          });
          if (onRole) onRole(role, "netplay-rooms/" + roomRef.id);
        } else {
          // reserve-then-fill: publish the slot first, ICE in background,
          // then patch in the offer. Shrinks the race window from ~2 s
          // (ICE) to ~one Firestore RTT (~100 ms).
          status("Reserving room…");
          roomRef = await fs.addDoc(fs.collection(db, "netplay-rooms"), {
            cartId, state: "signaling", hostUid: u.uid, offer: "", createdAt: fs.serverTimestamp(),
          });
          if (_cancelled) { _close(transport); await _del(roomRef); return null; }
          if (onRole) onRole(role, "netplay-rooms/" + roomRef.id);

          // reserve-then-confirm: wait briefly for any concurrent
          // reservers to commit, then re-query. If a strictly older
          // signaling room exists, defer to it. This converts a
          // same-RTT host stampede into clean host+joiner pairs.
          if (T.confirmReserveMs > 0) {
            await new Promise((r) => setTimeout(r, T.confirmReserveMs));
            if (_cancelled) { _close(transport); await _del(roomRef); return null; }
            const earliest = await _findOpenRoom(cartId);
            if (earliest && earliest.ref.id !== roomRef.id) {
              status("Older host found — deferring…");
              await _del(roomRef);
              _close(transport);
              return autoMatch({ cartId, onStatus, onRole });
            }
          }

          status("Generating offer…");
          let offerCode;
          try {
            offerCode = await transport.createOffer();
          } catch (e) {
            await _del(roomRef);
            throw e;
          }
          if (_cancelled) { _close(transport); await _del(roomRef); return null; }
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
            offerCode = await _awaitOffer(roomRef, T.waitOfferMs);
          } catch (e) {
            _close(transport);
            await _del(roomRef);
            if (_cancelled) return null;
            return autoMatch({ cartId, onStatus, onRole });
          }
          if (_cancelled) { _close(transport); return null; }
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
          _close(transport);
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
          _close(transport);
          throw e;
        }
        if (_cancelled) {
          try { await fs.updateDoc(roomRef, { state: "signaling", joinerUid: null }); } catch {}
          _close(transport);
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
          _close(transport);
          await new Promise((r) => setTimeout(r, Math.random() * T.raceRetryJitterMs));
          return autoMatch({ cartId, onStatus, onRole });
        }
      }
      if (_cancelled) {
        _close(transport);
        if (role === "host") await _del(roomRef);
        return null;
      }

      if (role === "host") {
        status("Waiting for joiner…");
        try {
          await _awaitAnswerAndAccept(roomRef, transport, T.hostWaitForAnswerMs);
        } catch (e) {
          _close(transport);
          await _del(roomRef);
          if (_cancelled) return null;
          throw e;
        }
      }

      status("Opening data channel…");
      try {
        await _awaitChannelOpen(transport, T.dcOpenTimeoutMs);
      } catch (e) {
        _close(transport);
        if (role === "host") await _del(roomRef);
        if (_cancelled) return null;
        throw e;
      }

      if (role === "host") await _del(roomRef);
      status(role === "host" ? "Connected as host" : "Connected as joiner");
      return { role, transport };
    }

    function cancel() {
      _cancelled = true;
      // Reject every pending listener-promise so awaits unwind instead
      // of leaking. The matchmaker's checkpoints downstream will see
      // _cancelled === true and bail out without further side effects.
      for (const cb of [..._cancelHooks]) { try { cb(); } catch {} }
      _cancelHooks.clear();
    }

    return { autoMatch, cancel };
  }

  const NS = {
    createMatchmaker,
    ROOM_STALE_MS, HOST_WAIT_FOR_ANSWER_MS, DC_OPEN_TIMEOUT_MS,
    WAIT_OFFER_MS, CONFIRM_RESERVE_MS, RACE_RETRY_JITTER_MS, MAX_ATTEMPTS,
  };
  if (typeof module !== "undefined" && module.exports) module.exports = NS;
  else if (typeof globalThis !== "undefined") globalThis.MonoNetMatchmaker = NS;
})();
