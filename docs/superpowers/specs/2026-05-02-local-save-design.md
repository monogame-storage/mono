# Local Save / Data Storage — Design

**Date:** 2026-05-02
**Status:** Approved (brainstorming)

## Problem

Mono has no persistence. A game can render the player's current state, but after the cart is closed every value is lost — high scores, settings, run progress, "intro seen" flags, inventories. `docs/API.md` lists `save(key, value)` / `load(key)` under "Under Consideration" but the contract was never pinned down.

This spec defines a per-cart key/value store with a small, explicit Lua surface, three storage backends (web, Android, in-memory), and a hard 64KB-per-cart cap. Cloud sync is deliberately deferred.

## Goals

- Games can persist arbitrary JSON-shaped state (numbers, strings, booleans, nested tables).
- Each cart is automatically isolated — no naming convention required, no risk of cross-cart bleed.
- The same Lua API works on web (`play.html`, `dev/`), Android (WebView), and headless (tests, future Cosmi `run_game` tool).
- Save data survives cart code changes (e.g., when Cosmi rewrites a published cart).
- Clear failure modes: invalid input throws Lua errors; quota overflow throws; backend failures throw.
- Mono's constraint aesthetic is preserved: 64KB hard cap per cart.

## Non-Goals

- Cloud sync. Local only. (Future work: published games for logged-in users.)
- Cross-cart data sharing. Isolation is enforced.
- Schema migration / versioning. Games own their own value shape.
- Encryption. Plain JSON.
- Backup / export UI. Out of scope.
- Async streaming or partial reads. Whole-bucket read on boot, write-through on every mutation.

## Lua API

Six globals, all `data_*` prefixed for namespace clarity and discoverability:

```lua
data_save(key, value)    -- void; throws on invalid input or quota
data_load(key)           -- → value | nil
data_delete(key)         -- → boolean (true if key existed)
data_has(key)            -- → boolean
data_keys()              -- → table (sorted array of strings)
data_clear()             -- void; wipes this cart's bucket
```

### Behaviors

- `data_load` returns a **fresh** value reconstructed from the stored JSON. Mutating the returned table does **not** auto-persist; the game must call `data_save` again. This is the explicit-write model.
- `data_keys()` returns keys sorted alphabetically (deterministic; eases test snapshots and UI listings).
- `data_clear()` removes the cart's bucket entirely from the backend (not just the in-memory cache).
- All six functions are reserved engine globals — overwriting them in user code is rejected by Cosmi's lint (`ENGINE_GLOBALS`).

### Error contract (`data_save` throws)

| Trigger | Message |
|---|---|
| Key not a non-empty string ≤ 64 chars, or contains NUL/whitespace | `save: invalid key` |
| Value contains function or userdata | `save: unserializable <type>` |
| Number is `NaN` or `±Infinity` | `save: unserializable NaN/Inf` |
| Table has cycle | `save: cycle detected` |
| Table nested deeper than 16 levels | `save: too deep` |
| Serialized bucket would exceed 64KB | `save: quota exceeded (N bytes > 65536)` |
| Backend write fails (localStorage full, native bridge error, etc.) | `save: backend write failed` |

Validation runs before mutating the in-memory bucket. On any throw the bucket and backend remain unchanged (atomicity).

`data_delete` and `data_clear` only throw on backend write failure. `data_load`, `data_has`, `data_keys` never throw.

## Cart Identity (cartId)

Save isolation is keyed by `cartId`, set by the runner at boot:

| Runner | cartId source |
|---|---|
| `play.html?id=<gameId>` (R2 published) | `gameId` verbatim |
| `play.html?game=<demo>` (built-in demo) | `"demo:" + demo` |
| `dev/` editor (`dev/js/editor-play.js`) | `state.currentGameId` verbatim — same as `play.html?id=` so the same cart preserves save data across dev → publish → play |
| `dev/headless/mono-runner.js`, `dev/test-worker.js` | not set; backend is forced to `"memory"` |
| `android/` | `"pkg:" + Android package name` |

The `demo:`/`dev:`/`pkg:` prefixes prevent collision with R2 gameIds, which are bare alphanumeric.

`Mono.boot({ cartId, saveBackend, ... })` — boot fails fast (throws) if `saveBackend === "persistent"` but `cartId` is missing.

## Architecture

```
                 Lua user code
       data_save / data_load / data_delete / ...
                       │
                       ▼
        runtime/engine-bindings.js
        ─ binds 6 Lua globals
        ─ Lua↔JS table marshalling
        ─ key/value validation, throws on violation
        ─ enforces 64KB cap by serializing
          a candidate bucket and measuring length
                       │
                       ▼
              runtime/save.js
              backend interface:
                read(cartId)   → object
                write(cartId, bucket) → void/throws
                clear(cartId)  → void
                       │
       ┌───────────────┼───────────────┐
       ▼               ▼               ▼
  WebBackend     AndroidBackend    MemoryBackend
  localStorage   SharedPrefs       in-process Map
                 via JS bridge
```

`WebBackend` and `AndroidBackend` are merged into one class that auto-detects `window.MonoSaveNative` (the Android-injected JS interface) at construction and routes there if present, else uses `window.localStorage`. This keeps the runtime branch in one place rather than per-call.

### Boot sequence

1. `Mono.boot({ cartId, saveBackend })` is called by the runner.
2. Engine instantiates the chosen backend (`WebBackend` or `MemoryBackend` — Android piggybacks on `WebBackend`).
3. Backend `read(cartId)` returns parsed JSON or `{}` if the entry is missing or unparseable. On parse failure, `console.warn` is emitted once (no Lua error — game proceeds as first run).
4. The bucket is held in a JS-side cache. `data_load`/`data_has`/`data_keys` read from cache without re-parsing.
5. Every successful `data_save`/`data_delete`/`data_clear` writes the entire bucket through to the backend (write-through). No batching.

### Storage layout

```
localStorage / SharedPreferences:
  key:   "mono:save:<cartId>"
  value: JSON string of bucket object

Bucket shape:
  { "<key>": <value>, "<key>": <value>, ... }
```

One entry per cart. No metadata wrapper — every byte of the 64KB budget is the game's. Cart deletion = backend `removeItem` of that single entry.

### Android bridge

New `android/app/src/main/kotlin/com/mono/game/MonoSaveBridge.kt`:

```kotlin
class MonoSaveBridge(context: Context) {
    private val prefs = context.getSharedPreferences("mono_save", Context.MODE_PRIVATE)

    @JavascriptInterface
    fun read(cartId: String): String = prefs.getString(cartId, "") ?: ""

    @JavascriptInterface
    fun write(cartId: String, json: String): Boolean =
        prefs.edit().putString(cartId, json).commit()

    @JavascriptInterface
    fun clear(cartId: String) {
        prefs.edit().remove(cartId).apply()
    }
}
```

Registered in `MonoConsole.kt`:

```kotlin
webView.addJavascriptInterface(MonoSaveBridge(context), "MonoSaveNative")
```

Notes:
- One `SharedPreferences` file (`mono_save`) holds all carts; cart isolation is by entry key (cartId).
- `commit()` (synchronous) is used in `write` so the JS side gets a real success/failure boolean.
- Empty string from `read` means "missing entry" — the JS side parses it as `{}`.

## Quotas and Limits

| Item | Limit | On violation |
|---|---|---|
| Bucket size (serialized JSON) | 65536 bytes | `error("save: quota exceeded")` |
| Key | non-empty string, ≤64 chars, no NUL/whitespace | `error("save: invalid key")` |
| Value type | nil/bool/number/string/table only | `error("save: unserializable <type>")` |
| Table depth | ≤16 levels of object/array nesting (primitives don't count) | `error("save: too deep")` |
| Cycles | rejected | `error("save: cycle detected")` |

Quota check: serialize the candidate bucket (current cache plus the proposed change), measure UTF-8 byte length, reject if > 65536. The serialized form is the same one written to the backend, so what's measured is what's stored.

## Testing

Two test surfaces (matching existing patterns in this repo):

**`engine-test/test-save.lua`** — Lua-driven, runs through the engine like the other `test-*.lua` files. Covers user-visible behavior:

- Happy paths for all 6 functions, including round-trip of nested tables.
- `data_keys()` returns sorted output.
- `data_load` of a missing key returns `nil`.
- `data_clear` removes everything; `data_keys()` is empty after.
- Mutating the table returned by `data_load` does not auto-persist.

**JS-side unit tests** (location: alongside `runtime/save.js`, e.g. `runtime/save.test.js`, or wherever existing JS tests live — match the convention found at implementation time). Covers serialization and backend mechanics that are awkward to provoke from Lua:

- Quota boundary — bucket at exactly 65536 bytes succeeds; one byte more throws.
- Serialization rejection — function, userdata, NaN, Infinity, cyclic table each throw with the documented message.
- Key validation — empty string, > 64 chars, contains NUL, contains space, non-string each throw.
- Depth — nested table at depth 16 succeeds; depth 17 throws.
- Isolation — write under cart A, instantiate a new backend with cart B, confirm A's keys invisible.
- Web backend round-trip — writes the expected `mono:save:<cartId>` localStorage entry shape; a fresh backend boot restores values.
- Memory backend — fresh instance starts empty regardless of any prior instance's writes.
- Parse-failure recovery — pre-poison the localStorage entry with invalid JSON; next boot starts empty and emits exactly one `console.warn`.
- Cosmi lint — `lintEnginePrimitiveOverwrite` rejects `function data_save(...) end` and `data_save = ...`. (Lives with the existing lint tests in `cosmi/test/`.)

## Files Changed

| File | Change |
|---|---|
| `runtime/save.js` (new) | Backend interface, `WebBackend`, `MemoryBackend`, JSON serialization with validation |
| `runtime/engine-bindings.js` | Bind 6 Lua globals; Lua↔JS table marshalling for save values |
| `runtime/engine.js` | Accept `cartId` and `saveBackend` boot options; instantiate backend; expose accessor for bindings |
| `play.html` | Compute cartId from `?id=` (R2) or `?game=` (demo) and pass to `Mono.boot` |
| `dev/js/editor-play.js` | Pass `cartId: state.currentGameId` to the editor's boot call (same id play.html uses) |
| `dev/headless/mono-runner.js` | Pass `saveBackend: "memory"` (Node CLI test runner) |
| `dev/test-worker.js` | Pass `saveBackend: "memory"` (Web Worker pre-publish smoke test) |
| `android/app/src/main/kotlin/com/mono/game/MonoSaveBridge.kt` (new) | `@JavascriptInterface` over `SharedPreferences` |
| `android/app/src/main/kotlin/com/mono/game/MonoConsole.kt` | Register bridge on the WebView |
| `docs/API.md` | Move `save/load` out of "Under Consideration"; document the 6 `data_*` functions in a new `## Data` section. `cosmi/src/lib/api-lint.js` derives its whitelist from these headings — no change needed there. |
| `cosmi/src/lib/lint.js` | Append the 6 names to `ENGINE_GLOBALS` |
| `engine-test/test-save.lua` (new) | Lua-driven behavior tests |
| `runtime/save.test.js` (new, or matching existing JS test convention) | JS-side serialization/backend tests |

## Future Work

- **Cloud sync for published games on logged-in users.** Add a `CloudBackend` that mirrors locally for offline + speed and pushes debounced writes to a new Cosmi Worker endpoint (`GET/PUT/DELETE /save/<cartId>`) keyed by `<uid>:<cartId>` in R2. Last-write-wins for conflicts. The backend interface is already shaped to accommodate this — the runner's auth-detection branch picks `CloudBackend` when a Firebase user is signed in and the cart is a published R2 cart.
- **Save inspector** in `dev/`: list keys, show JSON, manual edit/delete during development.
- **Per-cart quota raise** if a real game hits the 64KB limit. The cap is intentionally low to start; raising it is a one-line change once warranted.
