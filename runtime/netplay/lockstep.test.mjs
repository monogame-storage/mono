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
  const hostSeed = opts.hostSeed != null ? opts.hostSeed : 0xdeadbeef;
  const host   = new LockstepSession({ transport: tA, cartHash: opts.cartHashHost   || opts.cartHash || "abc", rng: () => hostSeed });
  const joiner = new LockstepSession({ transport: tB, cartHash: opts.cartHashJoiner || opts.cartHash || "abc" });
  return { host, joiner };
}

async function pair(host, joiner) {
  host.startAsHost();
  joiner.startAsJoiner();
  for (let i = 0; i < 5 && (host.status !== "playing" || joiner.status !== "playing"); i++) await drain();
}

// Deterministic per-frame state update that mixes both players' inputs.
function step(state, inputs) {
  return ((state * 1664525 + 1013904223 + inputs[0] * 31 + inputs[1] * 17) >>> 0);
}

test("host and joiner pair via init/init_ack with distinct roles + shared seed", async () => {
  const { host, joiner } = makePair({ hostSeed: 12345 });
  await pair(host, joiner);
  assert.equal(host.status, "playing");
  assert.equal(joiner.status, "playing");
  assert.equal(host.localPlayer, 0);
  assert.equal(joiner.localPlayer, 1);
  assert.equal(host.seed, 12345);
  assert.equal(joiner.seed, 12345);
});

test("600 frames of lockstep produce identical state on both peers", async () => {
  const { host, joiner } = makePair();
  await pair(host, joiner);

  let stateA = 1, stateB = 1;

  for (let f = 0; f < 600; f++) {
    const bitsA = (f * 7 + 0xA) & 0xff;
    const bitsB = (f * 7 + 0x5) & 0xff;
    host.submitLocalInput(bitsA);
    joiner.submitLocalInput(bitsB);

    await drain();

    assert.ok(host.canAdvance(),   `host stuck at frame ${f}`);
    assert.ok(joiner.canAdvance(), `joiner stuck at frame ${f}`);

    const inA = host.inputsForFrame(host.frame);
    const inB = joiner.inputsForFrame(joiner.frame);
    assert.deepEqual(inA, inB, `frame ${f}: A=${inA} B=${inB}`);

    stateA = step(stateA, inA);
    stateB = step(stateB, inB);

    if (f % HASH_INTERVAL === 0) {
      host.submitLocalHash(stateA);
      joiner.submitLocalHash(stateB);
      await drain();
      assert.notEqual(host.status, "desync",   `host desync at frame ${f}: ${host.error}`);
      assert.notEqual(joiner.status, "desync", `joiner desync at frame ${f}: ${joiner.error}`);
    }

    host.advance();
    joiner.advance();
  }

  assert.equal(stateA, stateB);
  assert.equal(host.frame, 600);
  assert.equal(joiner.frame, 600);
});

test("desync is detected via hash mismatch", async () => {
  const { host, joiner } = makePair();
  await pair(host, joiner);

  let stateA = 1, stateB = 1;
  let diverged = false;
  for (let f = 0; f < 120 && host.status === "playing" && joiner.status === "playing"; f++) {
    host.submitLocalInput(f & 0xff);
    joiner.submitLocalInput(f & 0xff);
    await drain();
    stateA = step(stateA, host.inputsForFrame(host.frame));
    stateB = step(stateB, joiner.inputsForFrame(joiner.frame));
    if (f === 60) { stateB = (stateB ^ 0xdeadbeef) >>> 0; diverged = true; }
    if (f % HASH_INTERVAL === 0) {
      host.submitLocalHash(stateA);
      joiner.submitLocalHash(stateB);
      await drain();
    }
    host.advance();
    joiner.advance();
  }

  assert.ok(diverged);
  assert.ok(host.status === "desync" || joiner.status === "desync",
    `neither side flagged desync: host=${host.status} joiner=${joiner.status}`);
});

test("cart hash mismatch in init fails the joiner", async () => {
  const { host, joiner } = makePair({ cartHashHost: "alpha", cartHashJoiner: "beta" });
  host.startAsHost();
  joiner.startAsJoiner();
  for (let i = 0; i < 5; i++) await drain();
  // Joiner rejects init; host stays "matching" until it would receive an
  // init_ack, which never arrives.
  assert.equal(joiner.status, "closed");
  assert.match(joiner.error, /cart hash/);
});

test("pre-filled delay frames let frame 0 run with zero inputs", async () => {
  const { host, joiner } = makePair();
  await pair(host, joiner);
  assert.ok(host.canAdvance());
  assert.ok(joiner.canAdvance());
  assert.deepEqual(host.inputsForFrame(0), [0, 0]);
  assert.deepEqual(host.inputsForFrame(DEFAULT_DELAY - 1), [0, 0]);
});

test("seed is shared via init message (not derived from timestamps)", async () => {
  const { host, joiner } = makePair({ hostSeed: 0xcafef00d });
  await pair(host, joiner);
  assert.equal(host.seed, 0xcafef00d);
  assert.equal(joiner.seed, 0xcafef00d);
});

test("transport close flips peer's session to status='closed' (peer disconnect)", async () => {
  // Pair, run a few frames, then close the host's transport. The joiner's
  // session should detect the channel drop and transition to "closed" so
  // the engine's DISCONNECTED overlay can surface it.
  const [tHost, tJoin] = InProcessTransport.pair();
  let ts = 1000;
  const host   = new LockstepSession({ transport: tHost, cartHash: "abc", now: () => ts++, rng: () => 42 });
  const joiner = new LockstepSession({ transport: tJoin, cartHash: "abc", now: () => ts++ });
  host.startAsHost();
  joiner.startAsJoiner();
  for (let i = 0; i < 5; i++) await drain();
  assert.equal(host.status,   "playing");
  assert.equal(joiner.status, "playing");

  tHost.close();
  for (let i = 0; i < 5; i++) await drain();

  assert.equal(joiner.status, "closed");
  assert.match(joiner.error, /peer disconnected/);
});

test("desync status is preserved across transport close", async () => {
  // If we already flagged desync, a later transport drop shouldn't overwrite
  // that more specific error.
  const { host, joiner } = makePair();
  await pair(host, joiner);
  // Force desync directly.
  joiner.status = "desync";
  joiner.error  = "desync at frame 30: local=abc peer=def";
  // Close the host's transport — joiner stays "desync".
  host.transport.close();
  for (let i = 0; i < 5; i++) await drain();
  assert.equal(joiner.status, "desync");
});
