# Cloud Save / `CloudBackend` — Design

**Date:** 2026-05-03
**Status:** Approved (brainstorming)
**Builds on:** `docs/superpowers/specs/2026-05-02-local-save-design.md` (local save / `data_*` API)

## Problem

The local save spec shipped six `data_*` Lua functions, three backends (Memory / Web / Android-bridge), and a 64KB-per-cart cap. Persistence is per-device only — a player who plays on phone, switches to laptop, sees an empty bucket. The original spec's Future Work entry pointed at this gap and sketched a `CloudBackend` for logged-in users; this spec turns that sketch into a buildable design.

## Goals

- Logged-in players see the same `data_*` state across devices for any cart they play.
- Anonymous players keep working exactly as today (localStorage only, no server round-trip on boot).
- Login while local data exists triggers a one-shot upload (cloud-empty case only); the user's offline anonymous session is not lost on the way to the cloud.
- Lua API is unchanged. `data_save` stays synchronous from the game's point of view.
- Network outages and tab closures don't lose committed writes — local mirror is durable, pushes are idempotent and retried.
- The Cloud backend slots into the existing backend interface (`read` / `write` / `clear`) without refactoring the bindings layer.

## Non-Goals

- Real-time multi-device sync (websockets, pub-sub). Sync happens at boot only; subsequent saves push from one device to the cloud, but other open sessions don't see them until their next boot.
- Conflict merging across devices. Two devices saving the same key concurrently end with last-write-wins at the cloud level.
- Per-user data export / inspect UI. Out of scope; users can manage data via in-game `data_clear` for now.
- Automatic backups, snapshots, history.
- Server-side validation that mirrors every client-side rule. The client validates; the server only enforces a defensive size cap.
- Login/logout swap mid-game. Auth state is read once at boot.

## Decisions (recap from brainstorming)

| # | Question | Decision |
|---|---|---|
| 1 | Trigger | Any authenticated boot with a cartId → CloudBackend. Anonymous → existing WebBackend. |
| 2 | Migration on first login | Cloud-wins. If cloud is empty, upload anonymous local. **Anonymous local is preserved**, not cleared. |
| 3 | Push timing | Debounced (~1s idle) + flush on `visibilitychange` (hidden) and `beforeunload`. |
| 4 | Auth detection | Boot-time only (no live re-binding). |
| 5 | Implementation | CloudBackend composes a WebBackend (with a different `keyPrefix`) as its durable mirror. |

## Architecture

```
                        Lua user code
        data_save / data_load / data_delete / ...     (unchanged)
                          │
                          ▼
              runtime/engine-bindings.js               (unchanged)
                          │
                          ▼  hooks.save.backend
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
  MemoryBackend      WebBackend       CloudBackend  ◀── new
  (headless)         (anon + offline   (logged-in carts)
                      editor)               │ wraps
                                            ▼
                                       WebBackend
                                       keyPrefix: "mono:save:<uid>:"
                                            │
                                            └── + push to cosmi worker
                                                    │
                                                    ▼
                                              R2 ("mono-dev"):
                                              save/<uid>/<cartId>
```

**Storage layout summary**

| Tier | Where | Key |
|---|---|---|
| Authoritative (logged-in) | R2 bucket `mono-dev` | `save/<uid>/<cartId>` |
| Durable cache (logged-in) | `localStorage` | `mono:save:<uid>:<cartId>` |
| Authoritative (anonymous) | `localStorage` | `mono:save:<cartId>` |
| Authoritative (Android packaged) | `SharedPreferences` "mono_save" | `cartId` (unchanged from local-save spec) |
| Lua-visible cache | engine-bindings.js in-memory bucket | (no key — single object per boot) |

The two `localStorage` namespaces (anonymous vs logged-in) never collide because the prefix differs — same device can hold both an anonymous bucket and a logged-in mirror for the same cartId without overwriting each other.

## Boot Sequence (logged-in path)

1. Runner (e.g., `play.html`) detects Firebase user is signed in. Constructs:
   ```js
   new MonoSave.CloudBackend({
     uid: user.uid,
     getToken: () => user.getIdToken(),  // refreshable
     apiUrl: "https://api.monogame.cc",
   })
   ```
2. Engine calls `backend.read(cartId)` synchronously from JS perspective. Inside CloudBackend:
   - `GET ${apiUrl}/save/<cartId>` with the user's idToken.
   - **200**: parse `{ bucket }`, write to mirror, return bucket.
   - **404**: check anonymous mirror (`mono:save:<cartId>`). If present, write to logged-in mirror, schedule a push to cloud (migration), return that bucket. If anonymous mirror is also empty, return `{}`.
   - **Network failure**: read from logged-in mirror as fallback. If mirror is empty, return `{}`.
   - **401**: warn, return `{}` and disable push for this session (token rejected — re-login needed).
3. Bindings install Lua globals as today.

The boot is allowed to be async; `Mono.boot` already returns a promise, and the engine awaits the read.

## Runtime Operations

| Lua call | CloudBackend behavior |
|---|---|
| `data_save(k, v)` | Validate + serialize via existing `serializeBucket`, mirror.write immediately, mark `pending[cartId] = json`, schedule debounced push (1s idle). |
| `data_delete(k)` | Same path — mirror.write + push. (No separate DELETE endpoint per key; full bucket replaces.) |
| `data_load(k)` | Reads from in-memory cache (engine-bindings.js layer). Zero CloudBackend involvement after boot. |
| `data_has(k)` / `data_keys()` | Same — cache only. |
| `data_clear()` | mirror.clear immediately + `DELETE /save/<cartId>` (not debounced — destructive intent should land fast). Pending push for this cartId is cancelled. |

## Debounce + Flush

CloudBackend instance state:

- `pending: Map<cartId, json>` — most recent serialized bucket awaiting push. Replaced (not appended) on each new write of the same cartId.
- `timer: number | null` — single setTimeout handle.
- Constants: `DEBOUNCE_MS = 1000`.

```
write(cartId, json):
  mirror.write(cartId, json)               # synchronous, durable
  pending.set(cartId, json)
  clearTimeout(timer)
  timer = setTimeout(flush, DEBOUNCE_MS)

flush():
  timer = null
  for [cartId, json] of pending:
    fetch PUT /save/<cartId> { body: { bucket: JSON.parse(json) } }
      .ok                       → pending.delete(cartId)
      .status === 401           → pending.clear(); console.warn; mark session "auth-dead"
      .status === 413           → pending.delete(cartId); console.warn (clientside cap should have caught this)
      .other or network error   → leave in pending; next debounce cycle retries
```

**Page-leave flush**: Constructor registers `visibilitychange` (state==='hidden') and `beforeunload` listeners. Each calls a `flushKeepalive` that issues `fetch(url, { method: 'PUT', body, headers, keepalive: true })` for each pending entry. The `keepalive` flag lets the request survive page teardown without needing the older `navigator.sendBeacon` API (which would force POST and require a separate worker route). Modern browser support: Chromium / Firefox / Safari 16+. Older Safari falls back to a best-effort synchronous fetch — acceptable, since the mirror is already durable and the push will retry on next boot.

## Worker — `cosmi/src/index.js`

Three new authenticated routes. All require `verifyAuth(request, env)` to return a non-null uid; otherwise 401.

```
GET    /save/:cartId       → 200 { bucket: <object> } | 404
PUT    /save/:cartId       → 204 on success
                              413 if Content-Length > 70_000 (defense in depth)
                              400 on body parse failure
DELETE /save/:cartId       → 204 (idempotent — 204 even if entry was missing)
```

**cartId validation**: new `validateCartId(s)` in `cosmi/src/lib/path.js`. Rules:
- 1..80 characters
- Charset `[a-zA-Z0-9:_-]` only (covers `demo:bounce`, `pkg:com_mono_game`, plain R2 gameIds — dots are intentionally rejected since cartIds end up in R2 keys)
- No path traversal (no `/`, no `..`, no `.`)

400 with `{ error: "invalid cartId" }` on violation.

**R2 layout**:
```
key:   save/<uid>/<cartId>
value: { "version": 1, "bucket": {...}, "updated_at": <unix_ms> }
```

- `version` reserved for future schema changes (rename keys, add metadata).
- `updated_at` set server-side at PUT; useful for debugging and future "last sync" UI.
- Wrapper overhead is ~50 bytes; R2 entry can be up to ~65586 bytes.

**Authorization**:
- Each request's R2 access is scoped to `save/<uid>/...` derived from the verified token. A user cannot read or write another user's cart save even by guessing the path — the worker constructs the R2 key from `verifyAuth`'s uid, never from a body field.
- CORS: existing `corsResponse` pattern. `Access-Control-Allow-Origin: *`, allow `Authorization` and `Content-Type` headers.

## Migration: First Login

Triggered when CloudBackend's boot read sees 404 from the cloud AND an anonymous mirror exists for the same cartId.

```
read(cartId):  // when GET returned 404
  anon = window.localStorage.getItem("mono:save:" + cartId)
  if anon:
    parsed = safe-parse(anon)
    if parsed is plain object:
      // 1. Write to logged-in mirror
      mirror.write(cartId, anon)             // pre-stringified, no re-parse cost
      // 2. Schedule a push (uses the standard debounce pipeline)
      pending.set(cartId, anon)
      clearTimeout(timer); timer = setTimeout(flush, 0)   // immediate, not 1s
      // 3. Return the bucket; anonymous key is NOT deleted
      return parsed
  return {}
```

The anonymous key remains in localStorage. If the user logs out later, their pre-login progress is still there. If they log back in (same uid), the cloud copy now matches what was migrated, so subsequent boots take the normal 200 path — the migration logic is dormant.

**What if anonymous mirror is corrupt?** safe-parse returns `{}` on JSON failure. Migration falls through to the empty-bucket case. Existing WebBackend warn-once behavior for corrupt local data still applies if the user goes back to anonymous mode.

## WebBackend Change (composition)

`runtime/save.js` `WebBackend` gains a single optional constructor option: `keyPrefix`. Defaults to `"mono:save:"`. Only `_key(cartId)` reads the prefix:

```js
_key(cartId) { return this._keyPrefix + cartId; }
```

CloudBackend instantiates its mirror with `new WebBackend({ keyPrefix: "mono:save:" + uid + ":" })`. All other WebBackend logic (read/write/clear, JSON parse, warn-once) is reused without change.

This is a contract-compatible additive change — existing `new WebBackend()` calls (anonymous flow) continue to use the default prefix.

## Auth Detection

Each runner injects the right backend at boot. New helper in `runtime/save.js` is **not** added — auth detection belongs in the runner because Firebase is a runner-level dependency, not an engine concern.

```js
// runner pseudo-code (play.html, dev/js/editor-play.js, etc.)
const user = firebase.auth().currentUser;
const backend = user
  ? new MonoSave.CloudBackend({
      uid: user.uid,
      getToken: () => user.getIdToken(),
      apiUrl: "https://api.monogame.cc",
    })
  : new MonoSave.WebBackend();
Mono.boot("screen", { ..., cartId, save: { backend, cartId } });
```

For boots that complete before Firebase auth has resolved, runners must `await firebase.auth().authStateReady()` (or equivalent) before constructing the backend. `play.html` already initializes Firebase asynchronously; the boot-trigger callback already runs after auth is ready.

## Quotas and Limits

| Item | Limit | On violation |
|---|---|---|
| Bucket size (client) | 65536 bytes | `serializeBucket` throws `save: quota exceeded` (existing) |
| Body size (server) | 70000 bytes (Content-Length) | 413 |
| cartId | 1..80 chars, `[a-zA-Z0-9:_-]` | 400 |
| Auth | Firebase token via `verifyAuth` | 401 |

R2 has effectively no per-user limit at this scale. Ten thousand users × fifty carts × 64KB ≈ 32 GB; well within free tier.

## Error Handling

Client-side errors map to existing `data_*` error contract — no new Lua-visible messages. Cloud-specific failure modes:

| Condition | CloudBackend reaction | Lua game sees |
|---|---|---|
| Boot GET network error | mirror fallback, push disabled until next boot | normal `data_load` returns from mirror |
| Boot GET 401 | empty bucket, push disabled, console.warn | first-run state |
| Boot GET 5xx | mirror fallback, push enabled (will retry) | mirror state |
| Push 401 | clear pending, mark "auth-dead", warn | nothing — game continues |
| Push 5xx / network | leave in pending, retry next debounce | nothing |
| Push 413 | drop from pending, warn | nothing — local kept, just not persisted |

The game itself never observes cloud failure. The mirror is always coherent with the bindings cache; the cloud may temporarily lag behind. This is the natural offline-first UX.

## Testing

**JS unit tests** — extend `runtime/save.test.mjs`:
- WebBackend `keyPrefix` option respected.
- Two WebBackend instances with different prefixes don't collide on the same cartId.
- CloudBackend constructor calls GET with the spec'd URL + Authorization header.
- 200 response → mirror written + bucket returned.
- 404 + anonymous mirror present → migration: mirror updated, push scheduled, anonymous key untouched.
- 404 + no anonymous mirror → empty bucket, no push.
- Network error → mirror fallback path returns mirror's content.
- 401 boot → empty bucket, push disabled, warn emitted once.
- `write` debounce: multiple writes in <1s collapse into one PUT.
- `clear` PUT-bypassed: DELETE issued immediately, pending push for that cartId cancelled.
- `flushKeepalive` issues `fetch(..., { keepalive: true })` for each pending entry on `visibilitychange` (hidden) and `beforeunload`.

Use a fake `fetch`, fake `localStorage`, and fake `setTimeout/clearTimeout` to drive the timeline deterministically. `node:test` already supports this style; existing WebBackend tests use injected fakes.

**Worker tests** — new `cosmi/test/save-endpoint.test.mjs`:
- Unauthenticated → 401 on all three methods.
- Invalid cartId → 400.
- GET missing → 404.
- PUT then GET round-trips the bucket; `version` and `updated_at` present in the R2 record.
- PUT with `Content-Length > 70000` → 413 (don't actually write 70KB; fake the header).
- DELETE missing → 204.
- DELETE then GET → 404.
- Cross-uid isolation: write as user A, query as user B → 404 (R2 prefix isolation).

**End-to-end (manual)**:
1. Anonymous play of `play.html?game=save` (the existing demo). Save some fields. Confirm `mono:save:demo:save` in localStorage.
2. Sign in. Reload `play.html?game=save`. Confirm:
   - The fields show the previously-saved values.
   - `mono:save:<uid>:demo:save` exists in localStorage (mirror).
   - `mono:save:demo:save` is also still there (anonymous preserved).
   - R2 has `save/<uid>/demo:save`.
3. Sign out. Reload. Confirm anonymous values reappear (logged-in mirror is dormant; anonymous bucket re-reads).
4. Sign in on a second browser/incognito with the same account. Confirm step-2 values are present (cloud → new mirror).

## Files Changed

| File | Change |
|---|---|
| `runtime/save.js` | Add `keyPrefix` option to WebBackend. New `CloudBackend` class. Export it. |
| `runtime/save.test.mjs` | Tests above. |
| `cosmi/src/index.js` | Three new routes (`GET/PUT/DELETE /save/:cartId`). |
| `cosmi/src/lib/path.js` | New `validateCartId` helper. |
| `cosmi/test/save-endpoint.test.mjs` (new) | Worker-side tests. |
| `cosmi/test/path.test.mjs` | Add `validateCartId` cases. |
| `play.html` | Auth detection + backend selection at boot. |
| `dev/js/editor-play.js` | Same. |
| `dev/headless/mono-runner.js` | Untouched (always Memory backend). |
| `dev/test-worker.js` | Untouched (always Memory backend). |
| `docs/superpowers/specs/2026-05-02-local-save-design.md` | Update Future Work section to reference this spec. |

## Future Work

- **Live multi-device sync** via Cloudflare Durable Objects + websockets. Out of scope until a real game needs it.
- **Conflict UI** when local and cloud have non-trivial divergence. Currently masked by cloud-wins.
- **Save inspector** in `dev/` (already noted in v1 spec).
- **Per-user quota cap** (e.g. 100 carts × 64KB) once usage data exists.
- **Sync timestamp UI** ("last synced 3 minutes ago") for transparency.
- **Worker body-size streaming inspection.** `handleSavePut` currently buffers the full body via `request.text()` before measuring length — an authenticated client that streams up to CF's 100MB platform cap can burn isolate CPU/memory before the 70KB post-parse check fires. Stream via `request.body.getReader()` and abort once the cap is exceeded. Bounded by `verifyAuth`, so not a public DoS, but worth tightening once we have real auth-misuse signal.
- **`getToken` deadline.** `_authHeaders()` and `_flushKeepalive()` await `getToken()` with no `Promise.race` against a timeout. If Firebase's token refresh hangs (iOS Safari background, IndexedDB lock), the keepalive PUT misses the unload window. Wrap in a 1-second deadline that falls back to skipping the push (mirror is durable; next boot recovers).
