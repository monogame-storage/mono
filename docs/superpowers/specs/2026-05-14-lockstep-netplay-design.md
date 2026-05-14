# Lockstep Netplay — Design

**Date:** 2026-05-14
**Status:** Shipped (v1, WebRTC DataChannel + manual SDP paste)
**Related:** `docs/CLI-RUNNER.md` (determinism harness), PR #101 (engine determinism prerequisite)

**Implementation note:** v1 ships with `WebRTCTransport` for real cross-machine play (DataChannel, STUN-only, no signaling server). The host generates a base64 offer code that the joiner pastes back as an answer code — paste happens out-of-band (Discord, SMS, etc.). The `BroadcastChannel` same-tab transport was briefly built and removed: it isolates per-browser-instance and cannot cross devices, which is exactly what netplay needs to do.

## Problem

Mono carts run a deterministic 30 FPS Lua loop, but there is no way for two players to share state across the network. Couch co-op via local gamepad works; remote co-op does not exist. The CLI runner already documents the determinism requirement ("Lockstep multiplayer requires deterministic execution") but no transport, input-sync, or API has been built.

## Goals

- Two players on two browser tabs can play the same cart with synchronized state, observing identical VRAM each frame.
- A cart opts into netplay by calling a single new `net.*` API. Single-player carts are unaffected.
- The runtime, not the cart, owns the network transport and input exchange. Carts only see `btn(key, player)`.
- Disconnect / desync is detectable and surfaced (the game pauses with a clear message rather than silently drifting).
- Headless harness can drive two in-process engine instances through the same protocol so lockstep can be unit-tested without WebRTC.

## Non-Goals

- More than 2 players (the protocol generalises later, but the v1 API and lobby are 2P only).
- Rollback netplay (GGPO-style). Lockstep with input delay is simpler and good enough for 30 FPS turn/arcade games.
- Matchmaking / lobby server. v1 uses manual SDP code paste (host generates offer, joiner pastes back the answer).
- Live spectators, replay, voice chat, chat overlay.
- NAT traversal beyond what plain WebRTC + a public STUN server gives. No TURN.
- Cross-version play. Both peers must run the same engine build + cart hash.

## Decisions (as shipped)

| # | Question | v1 decision |
|---|---|---|
| 1 | Transport | `WebRTCTransport` — `RTCPeerConnection` + ordered `DataChannel`. STUN-only (`stun:stun.l.google.com:19302`), no TURN, no signaling server. ICE gathering completes before SDP is returned so the pasted blob is self-contained ("non-trickle"). `InProcessTransport` ships alongside for headless tests. |
| 2 | Pairing | Manual SDP code paste. Host calls `Mono.net.host()` → base64 offer (~1 KB). Joiner calls `Mono.net.join(offer)` → base64 answer. Host calls `Mono.net.accept(answer)` → DataChannel opens. Host = player 0, joiner = player 1. |
| 3 | Init / seed | Host generates a 32-bit random seed and sends it as the first DataChannel message (`{type: "init", seed, cartHash, proto, delay}`). Joiner validates `cartHash` and `proto`, adopts seed, ACKs. Both transition to `"playing"`. |
| 4 | Input delay | Fixed 3 frames (≈100 ms at 30 FPS). Queue is pre-filled with zeros for the first `delay` frames so frame 0 can run immediately. |
| 5 | Tick model | Engine advances logical frame only when `canAdvance()` (peer input available). Stalled frames render an overlay. `_draw` runs **inside** the fixed-timestep loop so the VRAM-hash exchange captures the correct logical frame. |
| 6 | RNG | `setEngineSeed(session.seed)` is called once on `matching → playing` transition. Carts seed `math.random` themselves via `net.seed()`. |
| 7 | Cart hash | `cartHash = opts.cartId` is included in the host's init message and validated by the joiner. Mismatch → `"closed"` with reason. SHA256 of cart source is a v2 hardening. |
| 8 | Desync detection | Every `HASH_INTERVAL = 30` frames each peer fnv1a-hashes `scr.colorBuf` (160×120 bytes) and posts the result. Mismatch → `status = "desync"` + `DESYNC` overlay. |
| 9 | Cart-facing API | `net.start()` (opt-in flag), `net.status()`, `net.local_player()`, `net.seed()`, `net.error()`, `net.close()`. `btn(k)` / `btnp(k)` / `btnr(k)` accept an optional second arg `player` (0 or 1; defaults to local). |
| 10 | Runner-facing API | `Mono.net.host()` / `Mono.net.join(offer)` / `Mono.net.accept(answer)` / `Mono.net.cancel()`. The runner shell (`play.html`) drives a Host/Join modal that calls these — carts never see SDP. |

## Architecture

```
                       Lua cart
       btn(key, 0/1)   net.host() / net.join() / net.status()
                          │
                          ▼
              runtime/engine-bindings.js
                  (input router + net API)
                          │
                          ▼
                runtime/netplay/lockstep.js
                  ┌───────┴────────┐
                  ▼                ▼
            input queue       frame scheduler
           (per-peer, per-frame)  (wait-until-both-ready)
                  │                │
                  └────────┬───────┘
                           ▼
                  runtime/netplay/transport.js
                  ┌───────┴────────┐
                  ▼                ▼
              WebRTC DC        InProcessPair   ← used by headless tests
```

Three new files under `runtime/netplay/`:

1. **`lockstep.js`** — input queue, frame scheduler, handshake (seed + cart hash + protocol version), periodic VRAM-hash exchange. Transport-agnostic.
2. **`transport.js`** — abstract `Transport` interface (`send(msg)`, `onMessage(cb)`, `close()`). Two implementations:
   - `WebRTCTransport` — DataChannel wrapper, exposes offer/answer codes as base64-encoded JSON.
   - `InProcessTransport` — paired in-memory queues, for tests. Created via `InProcessTransport.pair()`.
3. **`hash.js`** — small VRAM hasher (fnv1a over the visible surface bytes).

`engine-bindings.js` exposes:

```lua
net.host()              -- returns offer code, transitions to "waiting_for_answer"
net.accept(answer)      -- host pastes joiner's answer code
net.join(offer)         -- joiner pastes host's offer code, returns answer code
net.status()            -- "idle" | "waiting_for_answer" | "connecting" | "playing" | "paused" | "desync" | "closed"
net.local_player()      -- 0 if host, 1 if joiner
btn(key, player)        -- player defaults to local_player() when omitted (single-player carts unchanged)
```

## Frame loop

Today: `tick()` reads local input → runs `_update()` → flushes screen → schedules next RAF.

With netplay active:

```
tick(frame N):
  if status != "playing": draw paused overlay, schedule next tick, return
  enqueue local input for frame N+delay              ← input delay
  send {type: "input", frame: N+delay, bits} to peer
  if peer has not sent input for frame N: stall (counter++, draw "waiting"), return
  run _update() using inputs(N) from queue
  if N % 30 == 0: send {type: "hash", frame: N, hash: vramHash}
                  if peer hash for N arrived and != local: status="desync"
  flush screen
  schedule next tick
```

Two consequences:

- **Determinism becomes mandatory.** Anything that affects screen state must be reproducible from `(seed, input stream)`. `Math.random()` calls in the engine (cam_shake) and any unseeded Lua usage are bugs.
- **`time()` must be derived from frame count**, not wall clock. Already true on most paths — needs audit.

## Handshake

1. Host calls `net.host()`. Engine generates `{ seed: random64(), cartHash, protocolVersion: 1 }`, creates WebRTC offer, returns base64(offer+meta).
2. Host pastes offer to joiner out-of-band (Discord, etc.).
3. Joiner calls `net.join(offer)`. Engine decodes meta, checks `cartHash` matches local cart, checks `protocolVersion`. If OK, creates answer, returns base64(answer).
4. Joiner pastes answer back to host.
5. Host calls `net.accept(answer)`. DC opens. Both peers seed their RNG with `seed`, set `status="playing"`, and start the loop at frame 0.

If `cartHash` or `protocolVersion` mismatches, `net.join` returns `nil` and `net.status()` becomes `"closed"` with a reason readable via `net.error()`.

## Determinism work (pre-requisite)

Before netplay can ship, these need to land:

- Replace `Math.random()` in `engine.js:1222-1223` (cam_shake) with seeded engine RNG.
- Audit `time()` and any frame timing that feeds gameplay — must be derived from frame count.
- Add `--seed` flag to `mono-runner.js` if not already there, and confirm the determinism harness still passes on all demos with the seeded RNG in place.

A separate small PR can do the determinism work first so it can be reviewed independently.

## Test plan

- **Unit:** `lockstep.test.mjs` drives two engines through `InProcessTransport`, runs 600 frames of a deterministic demo, asserts identical VRAM hash every 30 frames.
- **Unit:** desync injection — flip one input bit on peer 1, confirm `status` transitions to `"desync"` within one hash window.
- **Unit:** handshake — cartHash mismatch → `"closed"`. Protocol version mismatch → `"closed"`.
- **Manual:** two browser tabs, paste codes, play `demo/pong-2p` (new minimal demo), verify identical screens recorded with `data:image` capture at frame 300.

## Lessons learned (v1 implementation)

- **BroadcastChannel was the wrong primitive.** v1 was briefly built on `BroadcastChannel` to skip the SDP UX. That made local same-browser two-tab testing trivially work — but BroadcastChannel is browser-instance-scoped and cannot reach a different device, defeating the goal of network play. Removed before merge; the lesson is to validate the transport against the actual user scenario (two devices on a network) before optimizing for the convenient one (two tabs on a machine).
- **Hash timing**: the original engine ran `_draw` once per RAF tick (outside the fixed-timestep loop). With multiple logic frames per tick, the VRAM hash captured a stale render. v1 moves `_draw` inside the loop so each logical frame's hash matches its render. Slight CPU overhead when a tick catches up multiple frames; acceptable in ALPHA.
- **Cart-side asymmetric rendering breaks lockstep.** Showing a "you are player N" marker from cart Lua diverges VRAM between peers and trips the desync detector. Carts must render an identical screen on both peers; "which side am I" must come from the engine HUD, not the cart, or be omitted.
- **Async Lua is awkward.** WebRTC offer/answer generation is async (~1-2s ICE gathering). Lua 5.4 has no native async/await, so the SDP exchange UX lives in the runner shell (`play.html`), not in the cart. Cart just calls `net.start()` and reads `net.status()`.

## Future work (v2+)

- Signaling worker on `api.monogame.cc` so room codes replace the long base64 paste (still anonymous, still STUN-only between peers).
- TURN relay fallback for users behind symmetric NAT (currently STUN-only, which fails for some mobile carriers / corporate networks).
- 3-4P (protocol generalises by indexing inputs by peer id rather than 0/1).
- Rollback prediction layer on top of the same input queue.
- Hosted lobby + matchmaking.
- Spectator mode (read-only third peer that receives inputs and simulates).
- Per-peer HUD ("you are player N") drawn by the engine on a layer excluded from hash comparison, so carts don't have to choose between UX and determinism.
