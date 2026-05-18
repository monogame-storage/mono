// Headless reproduction of the netplay pairing race.
//
// Spawns N peers with staggered arrival times against a minimal in-memory
// Firestore mock and a transport that simulates ICE-gathering latency.
// Asserts the pairing pattern under both strategies:
//
//   "legacy"            — reproduces the [wait1, wait2, join1] bug when
//                          peers arrive within the ICE window.
//   "reserve-then-fill" — pairs sequentially [wait1, join1, wait2, join2].

import { test } from "node:test";
import assert from "node:assert";

const matchmakerMod = await import("./matchmaker.js");
const { createMatchmaker } = matchmakerMod.default || matchmakerMod;

// ── Fake Firestore ────────────────────────────────────────────────────────

class FakeClock {
  constructor() { this._origin = Date.now(); this._t0 = 1_000_000_000_000; }
  now() { return this._t0 + (Date.now() - this._origin); }
}

class FakeTimestamp {
  constructor(ms) { this._ms = ms; }
  toMillis() { return this._ms; }
  static fromMillis(ms) { return new FakeTimestamp(ms); }
  valueOf() { return this._ms; }
}

class FakeDocRef {
  constructor(db, collection, id) {
    this._db = db; this._collection = collection; this.id = id;
    this.path = collection + "/" + id;
  }
}

class FakeDocSnap {
  constructor(ref, data) { this.ref = ref; this._data = data; }
  exists() { return this._data !== undefined; }
  data() { return this._data; }
}

class FakeQuery {
  constructor(db, collection, filters, orderField, orderDir, limitN) {
    this._db = db; this._collection = collection;
    this._filters = filters || []; this._orderField = orderField;
    this._orderDir = orderDir || "asc"; this._limit = limitN || 0;
  }
}

class FakeFirestore {
  constructor(clock, opts = {}) {
    this._clock = clock;
    this._cols = new Map();
    this._snapSubs = new Map();
    this._idCounter = 1;
    this._opLatencyMs = opts.opLatencyMs != null ? opts.opLatencyMs : 50;
    this._txBusy = false;
  }

  _col(name) {
    if (!this._cols.has(name)) this._cols.set(name, new Map());
    return this._cols.get(name);
  }

  async _latency() {
    if (this._opLatencyMs > 0) await new Promise((r) => setTimeout(r, this._opLatencyMs));
  }

  _resolveValue(v) {
    if (v && v.__serverTimestamp) return new FakeTimestamp(this._clock.now());
    return v;
  }

  _resolveData(data) {
    const out = {};
    for (const k of Object.keys(data)) out[k] = this._resolveValue(data[k]);
    return out;
  }

  async addDoc(collection, data) {
    await this._latency();
    const id = "d" + (this._idCounter++);
    const ref = new FakeDocRef(this, collection, id);
    this._col(collection).set(id, this._resolveData(data));
    this._fireSnap(ref);
    return ref;
  }

  async updateDoc(ref, patch) {
    await this._latency();
    const col = this._col(ref._collection);
    const cur = col.get(ref.id);
    if (!cur) throw new Error("doc missing: " + ref.path);
    Object.assign(cur, this._resolveData(patch));
    this._fireSnap(ref);
  }

  async deleteDoc(ref) {
    await this._latency();
    this._col(ref._collection).delete(ref.id);
    this._fireSnap(ref);
  }

  async getDocs(q) {
    await this._latency();
    const col = this._col(q._collection);
    let out = [];
    for (const [id, data] of col) {
      let ok = true;
      for (const [field, op, val] of q._filters) {
        const dv = data[field];
        if (op === "==") { if (dv !== val) { ok = false; break; } }
        else if (op === ">") {
          const a = dv && dv.valueOf ? dv.valueOf() : dv;
          const b = val && val.valueOf ? val.valueOf() : val;
          if (!(a > b)) { ok = false; break; }
        }
      }
      if (!ok) continue;
      out.push(new FakeDocSnap(new FakeDocRef(this, q._collection, id), data));
    }
    if (q._orderField) {
      out.sort((a, b) => {
        const av = a._data[q._orderField], bv = b._data[q._orderField];
        const an = av && av.valueOf ? av.valueOf() : av;
        const bn = bv && bv.valueOf ? bv.valueOf() : bv;
        return q._orderDir === "desc" ? bn - an : an - bn;
      });
    }
    if (q._limit) out = out.slice(0, q._limit);
    return { empty: out.length === 0, docs: out };
  }

  onSnapshot(ref, cb) {
    if (!this._snapSubs.has(ref.path)) this._snapSubs.set(ref.path, new Set());
    const set = this._snapSubs.get(ref.path);
    set.add(cb);
    queueMicrotask(() => {
      if (!set.has(cb)) return;
      const data = this._col(ref._collection).get(ref.id);
      cb(new FakeDocSnap(ref, data));
    });
    return () => { set.delete(cb); };
  }

  _fireSnap(ref) {
    const set = this._snapSubs.get(ref.path);
    if (!set || set.size === 0) return;
    const data = this._col(ref._collection).get(ref.id);
    for (const cb of [...set]) {
      queueMicrotask(() => { if (set.has(cb)) cb(new FakeDocSnap(ref, data)); });
    }
  }

  async runTransaction(fn) {
    while (this._txBusy) await new Promise((r) => setTimeout(r, 5));
    this._txBusy = true;
    try {
      const tx = {
        get: async (ref) => {
          const data = this._col(ref._collection).get(ref.id);
          return new FakeDocSnap(ref, data);
        },
        update: (ref, patch) => {
          // Real Firestore runs tx bodies with optimistic concurrency:
          // if the doc was deleted or changed since tx.get, the SDK
          // re-runs the body up to 5 times, then surfaces a typed
          // error. From the caller's perspective this looks like a
          // race — surface it as RACE_TAKEN so the matchmaker's
          // existing retry path handles it.
          const cur = this._col(ref._collection).get(ref.id);
          if (!cur) throw new Error("RACE_TAKEN (mock: doc missing)");
          Object.assign(cur, this._resolveData(patch));
          this._fireSnap(ref);
        },
      };
      return await fn(tx);
    } finally { this._txBusy = false; }
  }
}

function makeFsShim(db) {
  return {
    collection: (_db, name) => name,
    where: (field, op, value) => [field, op, value],
    orderBy: (field, dir) => ["__order__", field, dir],
    limit: (n) => ["__limit__", n],
    query: (col, ...clauses) => {
      const filters = []; let orderField = null, orderDir = "asc", limitN = 0;
      for (const c of clauses) {
        if (Array.isArray(c) && c[0] === "__order__") { orderField = c[1]; orderDir = c[2] || "asc"; }
        else if (Array.isArray(c) && c[0] === "__limit__") { limitN = c[1]; }
        else if (Array.isArray(c)) filters.push(c);
      }
      return new FakeQuery(db, col, filters, orderField, orderDir, limitN);
    },
    addDoc: (col, data) => db.addDoc(col, data),
    updateDoc: (ref, patch) => db.updateDoc(ref, patch),
    deleteDoc: (ref) => db.deleteDoc(ref),
    getDocs: (q) => db.getDocs(q),
    onSnapshot: (ref, cb) => db.onSnapshot(ref, cb),
    runTransaction: (_db, fn) => db.runTransaction(fn),
    serverTimestamp: () => ({ __serverTimestamp: true }),
    Timestamp: FakeTimestamp,
  };
}

// ── Fake WebRTC transport ──────────────────────────────────────────────────
// createOffer / createAnswer simulate ICE gathering by sleeping for
// iceDelayMs. Pairing happens via a global broker keyed by offer string.

function makeTransportFactory(opts = {}) {
  const iceDelayMs = opts.iceDelayMs != null ? opts.iceDelayMs : 1500;
  const pending = new Map(); // offerCode -> host-side opener
  let counter = 0;
  return function createTransport() {
    let _opened = false;
    let _openCb = null;
    return {
      async createOffer() {
        await new Promise((r) => setTimeout(r, iceDelayMs));
        const code = "OFFER#" + (++counter);
        pending.set(code, () => {
          if (_opened) return;
          _opened = true;
          if (_openCb) _openCb();
        });
        return code;
      },
      async createAnswer(offerCode) {
        await new Promise((r) => setTimeout(r, iceDelayMs));
        setTimeout(() => {
          if (!_opened) { _opened = true; if (_openCb) _openCb(); }
        }, 10);
        return "ANSWER_FOR_" + offerCode;
      },
      async acceptAnswer(answerCode) {
        const off = answerCode.replace(/^ANSWER_FOR_/, "");
        const opener = pending.get(off);
        if (opener) { pending.delete(off); setTimeout(opener, 10); }
      },
      onOpen(cb) { _openCb = cb; if (_opened) cb(); },
      isOpen() { return _opened; },
      close() { _opened = false; _openCb = null; },
    };
  };
}

// ── Test harness ──────────────────────────────────────────────────────────

async function runScenario({ strategy, arrivals, cartId, iceDelayMs, opLatencyMs, timeouts }) {
  const clock = new FakeClock();
  const db = new FakeFirestore(clock, { opLatencyMs });
  const fs = makeFsShim(db);
  const createTransport = makeTransportFactory({ iceDelayMs });
  let uidSeq = 0;
  const ensureAuth = async () => ({ uid: "u" + (++uidSeq) });

  const events = [];
  const t0 = Date.now();
  const peers = [];

  function spawnPeer(label) {
    const mm = createMatchmaker({
      db, fs, createTransport, ensureAuth, strategy,
      now: () => clock.now(),
      timeouts,
    });
    events.push({ t: Date.now() - t0, peer: label, event: "spawn" });
    const p = mm.autoMatch({
      cartId,
      onStatus: (m) => events.push({ t: Date.now() - t0, peer: label, status: m }),
      onRole:   (r, room) => events.push({ t: Date.now() - t0, peer: label, role: r, room }),
    }).then(
      (res) => ({ label, ok: true, role: res && res.role }),
      (e) => ({ label, ok: false, error: e.message }),
    );
    peers.push(p);
    return p;
  }

  for (const { delayMs, label } of arrivals) {
    setTimeout(() => spawnPeer(label), delayMs);
  }
  const totalDelay = arrivals.reduce((m, a) => Math.max(m, a.delayMs), 0);
  await new Promise((r) => setTimeout(r, totalDelay + 50));
  const results = await Promise.all(peers);
  return { results, events };
}

// ── Tests ─────────────────────────────────────────────────────────────────

test("LEGACY: 2 peers within ICE window both become hosts (reproduces bug)", async () => {
  // Two peers arrive 100 ms apart. Legacy strategy runs createOffer (1.5 s)
  // BEFORE addDoc, so B's query at t=100ms finds no room and both become
  // hosts. Both time out on hostWaitForAnswerMs.
  const { results, events } = await runScenario({
    strategy: "legacy",
    cartId: "cart-bug-2p",
    arrivals: [
      { label: "A", delayMs: 0 },
      { label: "B", delayMs: 100 },
    ],
    iceDelayMs: 1500,
    opLatencyMs: 50,
    timeouts: { hostWaitForAnswerMs: 3000, waitOfferMs: 3000, dcOpenTimeoutMs: 3000 },
  });
  const a = results.find((r) => r.label === "A");
  const b = results.find((r) => r.label === "B");
  // Both should be hosts, both should fail (no joiner).
  const roles = events.filter((e) => e.role).map((e) => `${e.peer}=${e.role}`).sort();
  assert.deepEqual(roles, ["A=host", "B=host"],
    "expected both peers to land as host (reproducing bug), got roles=" + JSON.stringify(roles));
  assert.equal(a.ok, false, "A should fail (timeout) under legacy bug");
  assert.equal(b.ok, false, "B should fail (timeout) under legacy bug");
});

test("LEGACY: 3 peers within ICE window — 1 pairs, 1 stranded (the bug)", async () => {
  // [wait1, wait2, join1] — A and B both become hosts; C joins A (oldest).
  // B is left stranded waiting for a fourth peer.
  const { results, events } = await runScenario({
    strategy: "legacy",
    cartId: "cart-bug-3p",
    arrivals: [
      { label: "A", delayMs: 0 },
      { label: "B", delayMs: 100 },
      // C arrives after A+B have both published their rooms (need > 1500ms ICE + 50ms addDoc).
      { label: "C", delayMs: 1700 },
    ],
    iceDelayMs: 1500,
    opLatencyMs: 50,
    timeouts: { hostWaitForAnswerMs: 3000, waitOfferMs: 3000, dcOpenTimeoutMs: 3000 },
  });
  const a = results.find((r) => r.label === "A");
  const b = results.find((r) => r.label === "B");
  const c = results.find((r) => r.label === "C");
  // A is the older host → C should pair with A. B times out.
  assert.equal(a.ok, true,  "A should pair: " + a.error);
  assert.equal(c.ok, true,  "C should pair: " + c.error);
  assert.equal(b.ok, false, "B should be stranded (the bug): unexpected success");
  assert.equal(a.role, "host");
  assert.equal(c.role, "joiner");
});

test("FIX: 2 peers within ICE window pair correctly [host, joiner]", async () => {
  const { results } = await runScenario({
    strategy: "reserve-then-fill",
    cartId: "cart-fix-2p",
    arrivals: [
      { label: "A", delayMs: 0 },
      { label: "B", delayMs: 100 },
    ],
    iceDelayMs: 1500,
    opLatencyMs: 50,
    timeouts: { hostWaitForAnswerMs: 5000, waitOfferMs: 5000, dcOpenTimeoutMs: 5000 },
  });
  const a = results.find((r) => r.label === "A");
  const b = results.find((r) => r.label === "B");
  assert.equal(a.ok, true, "A failed: " + a.error);
  assert.equal(b.ok, true, "B failed: " + b.error);
  const roles = [a.role, b.role].sort();
  assert.deepEqual(roles, ["host", "joiner"]);
});

test("FIX: 3 peers within ICE window — A+B pair, C waits cleanly", async () => {
  const { results } = await runScenario({
    strategy: "reserve-then-fill",
    cartId: "cart-fix-3p",
    arrivals: [
      { label: "A", delayMs: 0 },
      { label: "B", delayMs: 100 },
      { label: "C", delayMs: 200 },
      // D arrives after A+B pair so C+D can pair too.
      { label: "D", delayMs: 4000 },
    ],
    iceDelayMs: 1500,
    opLatencyMs: 50,
    timeouts: { hostWaitForAnswerMs: 8000, waitOfferMs: 8000, dcOpenTimeoutMs: 8000 },
  });
  for (const r of results) assert.equal(r.ok, true, r.label + " failed: " + r.error);
  const hosts   = results.filter((r) => r.role === "host").length;
  const joiners = results.filter((r) => r.role === "joiner").length;
  assert.equal(hosts, 2, "expected 2 hosts");
  assert.equal(joiners, 2, "expected 2 joiners");
});

test("FIX: 6 peers within ICE window — 3 host/joiner pairs", async () => {
  const { results } = await runScenario({
    strategy: "reserve-then-fill",
    cartId: "cart-fix-6p",
    arrivals: [
      { label: "A", delayMs: 0 },
      { label: "B", delayMs: 60 },
      { label: "C", delayMs: 120 },
      { label: "D", delayMs: 180 },
      { label: "E", delayMs: 240 },
      { label: "F", delayMs: 300 },
    ],
    iceDelayMs: 1500,
    opLatencyMs: 50,
    timeouts: { hostWaitForAnswerMs: 15000, waitOfferMs: 15000, dcOpenTimeoutMs: 15000 },
  });
  for (const r of results) assert.equal(r.ok, true, r.label + " failed: " + r.error);
  const hosts   = results.filter((r) => r.role === "host").length;
  const joiners = results.filter((r) => r.role === "joiner").length;
  assert.equal(hosts, 3, "expected 3 hosts");
  assert.equal(joiners, 3, "expected 3 joiners");
});

test("FIX: stochastic — 8 peers, random 0-400ms arrivals, all pair", async () => {
  // Run 10 randomized scenarios so flake risk surfaces immediately.
  for (let trial = 0; trial < 10; trial++) {
    const arrivals = [];
    for (let i = 0; i < 8; i++) {
      arrivals.push({ label: "P" + i, delayMs: Math.floor(Math.random() * 400) });
    }
    const { results } = await runScenario({
      strategy: "reserve-then-fill",
      cartId: "cart-stoch-" + trial,
      arrivals,
      iceDelayMs: 1500,
      opLatencyMs: 50,
      timeouts: { hostWaitForAnswerMs: 20000, waitOfferMs: 20000, dcOpenTimeoutMs: 20000 },
    });
    const failed = results.filter((r) => !r.ok);
    assert.equal(failed.length, 0,
      "trial " + trial + " — failures: " + JSON.stringify(failed) +
      " arrivals=" + JSON.stringify(arrivals));
    const hosts   = results.filter((r) => r.role === "host").length;
    const joiners = results.filter((r) => r.role === "joiner").length;
    assert.equal(hosts, 4, "trial " + trial + " — expected 4 hosts, got " + hosts);
    assert.equal(joiners, 4, "trial " + trial + " — expected 4 joiners, got " + joiners);
  }
});

// ── Solo-matchmaker helpers ──────────────────────────────────────────────
// runScenario is a multi-peer harness; the regression tests below need
// a single-peer matchmaker with hand-tuned timings, so build one inline.

function makeSoloMM(opts = {}) {
  const clock = new FakeClock();
  const db = new FakeFirestore(clock, { opLatencyMs: opts.opLatencyMs != null ? opts.opLatencyMs : 20 });
  const fs = makeFsShim(db);
  const createTransport = makeTransportFactory({ iceDelayMs: opts.iceDelayMs != null ? opts.iceDelayMs : 50 });
  let uidSeq = 0;
  const mm = createMatchmaker({
    db, fs, createTransport,
    ensureAuth: async () => ({ uid: "u" + (++uidSeq) }),
    now: () => clock.now(),
    strategy: "reserve-then-fill",
    timeouts: Object.assign({
      hostWaitForAnswerMs: 60000, waitOfferMs: 60000, dcOpenTimeoutMs: 60000,
      confirmReserveMs: 50, raceRetryJitterMs: 50,
    }, opts.timeouts || {}),
  });
  return { mm, db };
}

test("REGRESSION: cancel() during host's wait-for-joiner unwinds cleanly", async () => {
  // Lone host reserves a room and waits for a joiner; user cancels.
  // autoMatch must resolve null promptly (snapshot listener torn down
  // via cancel-hook, not left hanging) and delete the orphan room.
  const { mm, db } = makeSoloMM();
  const t0 = Date.now();
  const p = mm.autoMatch({ cartId: "cancel-host", onStatus: () => {} });
  // Reserve + confirm + ICE + publish ≈ 200 ms — wait long enough to
  // land in "Waiting for joiner…".
  await new Promise((r) => setTimeout(r, 400));
  mm.cancel();
  const res = await p;
  const elapsed = Date.now() - t0;
  assert.equal(res, null, "cancelled autoMatch should resolve null");
  assert.ok(elapsed < 2000, "cancel should unwind quickly, took " + elapsed + " ms");
  assert.equal(db._col("netplay-rooms").size, 0, "orphan host room left after cancel");
});

test("REGRESSION: cancel() during joiner's wait-for-offer unwinds cleanly", async () => {
  // Pre-seed an orphan signaling room (no offer) so the joiner falls
  // into the waitOffer path. cancel must reject the snapshot promise
  // without leaving the listener attached.
  const { mm, db } = makeSoloMM({
    timeouts: { hostWaitForAnswerMs: 60000, waitOfferMs: 60000, dcOpenTimeoutMs: 60000, confirmReserveMs: 50, raceRetryJitterMs: 50 },
  });
  await db.addDoc("netplay-rooms", {
    cartId: "cancel-joiner", state: "signaling", hostUid: "ghost", offer: "",
    createdAt: { __serverTimestamp: true },
  });
  const t0 = Date.now();
  const p = mm.autoMatch({ cartId: "cancel-joiner", onStatus: () => {} });
  await new Promise((r) => setTimeout(r, 150));  // reach waitOffer
  mm.cancel();
  const res = await p;
  const elapsed = Date.now() - t0;
  assert.equal(res, null);
  assert.ok(elapsed < 1500, "cancel during waitOffer too slow: " + elapsed + " ms");
});

test("REGRESSION: maxAttempts bounds the retry chain", async () => {
  // Pre-seed a signaling room with a valid offer, then force every
  // phase-1 tx to throw RACE_TAKEN. The matchmaker should burn its
  // attempt budget on retries, then surface the limit.
  const { mm, db } = makeSoloMM({
    iceDelayMs: 5, opLatencyMs: 5,
    timeouts: { confirmReserveMs: 0, raceRetryJitterMs: 5, maxAttempts: 3 },
  });
  await db.addDoc("netplay-rooms", {
    cartId: "exhaust", state: "signaling", hostUid: "ghost",
    offer: "STUB_OFFER", createdAt: { __serverTimestamp: true },
  });
  db.runTransaction = async () => { throw new Error("RACE_TAKEN (forced)"); };
  let err = null;
  try { await mm.autoMatch({ cartId: "exhaust", onStatus: () => {} }); }
  catch (e) { err = e; }
  assert.ok(err, "expected autoMatch to throw after exhausting maxAttempts");
  assert.match(err.message, /exceeded 3 attempts/, "unexpected error: " + (err && err.message));
});

test("FIX: 4 peers within ICE window — 2 host/joiner pairs", async () => {
  const { results, events } = await runScenario({
    strategy: "reserve-then-fill",
    cartId: "cart-fix-4p",
    arrivals: [
      { label: "A", delayMs: 0 },
      { label: "B", delayMs: 100 },
      { label: "C", delayMs: 200 },
      { label: "D", delayMs: 300 },
    ],
    iceDelayMs: 1500,
    opLatencyMs: 50,
    timeouts: { hostWaitForAnswerMs: 8000, waitOfferMs: 8000, dcOpenTimeoutMs: 8000 },
  });
  if (process.env.DEBUG_NETPLAY) {
    for (const e of events) console.log(JSON.stringify(e));
  }
  for (const r of results) assert.equal(r.ok, true, r.label + " failed: " + r.error);
  const hosts   = results.filter((r) => r.role === "host").length;
  const joiners = results.filter((r) => r.role === "joiner").length;
  assert.equal(hosts, 2);
  assert.equal(joiners, 2);
});
