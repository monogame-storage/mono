// Lockstep protocol tests — two LockstepSession instances paired via
// InProcessTransport, driven through frames to assert identical state
// and detect desync.

import { test } from "node:test";
import assert from "node:assert";

const lockstepMod = await import("./lockstep.js");
const transportsMod = await import("./transports.js");
const { LockstepSession, HASH_INTERVAL, DEFAULT_DELAY } = lockstepMod.default || lockstepMod;
const { InProcessTransport } = transportsMod.default || transportsMod;

function drain() { return new Promise((r) => setImmediate(r)); }

function makePair(opts = {}) {
  const [tA, tB] = InProcessTransport.pair();
  let ts = 1000;
  const a = new LockstepSession({ transport: tA, cartHash: opts.cartHash || "abc", now: () => ts++ });
  const b = new LockstepSession({ transport: tB, cartHash: opts.cartHashB || opts.cartHash || "abc", now: () => ts++ });
  return { a, b };
}

async function pair(a, b) {
  a.start(); b.start();
  // Both sides exchange hellos; allow microtasks to drain.
  for (let i = 0; i < 5 && (a.status !== "playing" || b.status !== "playing"); i++) await drain();
}

// Simulated deterministic per-frame state update — both peers must reach
// the same value given the same input streams.
function step(state, inputs) {
  // XOR-mix to make state sensitive to every input bit and frame.
  return ((state * 1664525 + 1013904223 + inputs[0] * 31 + inputs[1] * 17) >>> 0);
}

test("two peers pair via hello exchange and agree on roles + seed", async () => {
  const { a, b } = makePair();
  await pair(a, b);
  assert.equal(a.status, "playing");
  assert.equal(b.status, "playing");
  // One is host (player 0), one is joiner (player 1) — assigned by ts ordering.
  assert.notEqual(a.localPlayer, b.localPlayer);
  assert.ok(a.localPlayer === 0 || a.localPlayer === 1);
  // Shared seed must match.
  assert.equal(a.seed, b.seed);
  assert.ok(a.seed !== 0);
});

test("600 frames of lockstep produce identical state on both peers", async () => {
  const { a, b } = makePair();
  await pair(a, b);

  let stateA = 1, stateB = 1;

  for (let f = 0; f < 600; f++) {
    // Each peer reads its own "hardware" — fabricated as a frame-dependent
    // bit pattern that differs per player so we exercise input routing.
    const localBitsA = (f * 7 + (a.localPlayer === 0 ? 0xA : 0x5)) & 0xff;
    const localBitsB = (f * 7 + (b.localPlayer === 0 ? 0xA : 0x5)) & 0xff;
    a.submitLocalInput(localBitsA);
    b.submitLocalInput(localBitsB);

    await drain();

    assert.ok(a.canAdvance(), `A stuck at frame ${f}`);
    assert.ok(b.canAdvance(), `B stuck at frame ${f}`);

    const inA = a.inputsForFrame(a.frame);
    const inB = b.inputsForFrame(b.frame);
    // Both peers see the same canonical inputs for this frame.
    assert.deepEqual(inA, inB, `frame ${f}: A=${inA} B=${inB}`);

    stateA = step(stateA, inA);
    stateB = step(stateB, inB);

    if (f % HASH_INTERVAL === 0) {
      a.submitLocalHash(stateA);
      b.submitLocalHash(stateB);
      await drain();
      assert.notEqual(a.status, "desync", `A desync at frame ${f}: ${a.error}`);
      assert.notEqual(b.status, "desync", `B desync at frame ${f}: ${b.error}`);
    }

    a.advance();
    b.advance();
  }

  assert.equal(stateA, stateB);
  assert.equal(a.frame, 600);
  assert.equal(b.frame, 600);
});

test("desync is detected via hash mismatch", async () => {
  const { a, b } = makePair();
  await pair(a, b);

  // Run a few frames cleanly, then deliberately diverge B's state.
  let stateA = 1, stateB = 1;
  let diverged = false;
  for (let f = 0; f < 120 && a.status === "playing" && b.status === "playing"; f++) {
    a.submitLocalInput(f & 0xff);
    b.submitLocalInput(f & 0xff);
    await drain();
    const inA = a.inputsForFrame(a.frame);
    const inB = b.inputsForFrame(b.frame);
    stateA = step(stateA, inA);
    stateB = step(stateB, inB);
    if (f === 60) { stateB = (stateB ^ 0xdeadbeef) >>> 0; diverged = true; }
    if (f % HASH_INTERVAL === 0) {
      a.submitLocalHash(stateA);
      b.submitLocalHash(stateB);
      await drain();
    }
    a.advance();
    b.advance();
  }

  assert.ok(diverged);
  // At least one side must have flagged desync.
  assert.ok(a.status === "desync" || b.status === "desync", `neither side flagged desync: a=${a.status} b=${b.status}`);
});

test("cart hash mismatch fails the handshake", async () => {
  const { a, b } = makePair({ cartHash: "alpha", cartHashB: "beta" });
  a.start(); b.start();
  for (let i = 0; i < 5; i++) await drain();
  assert.equal(a.status, "closed");
  assert.equal(b.status, "closed");
  assert.match(a.error, /cart hash/);
  assert.match(b.error, /cart hash/);
});

test("pre-filled delay frames let frame 0 run with zero inputs", async () => {
  const { a, b } = makePair();
  await pair(a, b);
  // Before any submitLocalInput call, frame 0 should already have inputs.
  assert.ok(a.canAdvance());
  assert.deepEqual(a.inputsForFrame(0), [0, 0]);
  assert.deepEqual(a.inputsForFrame(DEFAULT_DELAY - 1), [0, 0]);
});

test("realistic Date.now() timestamps assign distinct roles (regression: 32-bit truncation collapsed both peers to player 1)", async () => {
  const [tA, tB] = InProcessTransport.pair();
  let tsA = 1778752127436; // realistic Date.now() value
  let tsB = 1778752130517;
  const a = new LockstepSession({ transport: tA, cartHash: "abc", now: () => tsA });
  const b = new LockstepSession({ transport: tB, cartHash: "abc", now: () => tsB });
  await pair(a, b);
  assert.equal(a.status, "playing");
  assert.equal(b.status, "playing");
  // A had smaller ts → host (0). B had larger → joiner (1).
  assert.equal(a.localPlayer, 0);
  assert.equal(b.localPlayer, 1);
  assert.equal(a.seed, b.seed);
});

test("peer arriving late still pairs (rebroadcast)", async () => {
  const [tA, tB] = InProcessTransport.pair();
  let ts = 1000;
  const a = new LockstepSession({ transport: tA, cartHash: "abc", now: () => ts++ });
  a.start();
  // A's hello is delivered to B's inbox queue — buffered until B subscribes
  // when its session is constructed. So even though B is "late", the
  // initial hello is preserved by the queue's pre-subscribe buffer.
  const b = new LockstepSession({ transport: tB, cartHash: "abc", now: () => ts++ });
  b.start();
  for (let i = 0; i < 5; i++) await drain();
  assert.equal(a.status, "playing");
  assert.equal(b.status, "playing");
});
