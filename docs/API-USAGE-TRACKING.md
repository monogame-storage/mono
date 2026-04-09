# API Usage Tracking (Design Note)

When Mono enters the publishing phase (GAMMA), we need to know which engine APIs are actually used by published games. This tells us:

1. **Which APIs are safe to remove** — if no published game uses `cam_get`, it's a real dead-code candidate.
2. **Which APIs deserve better docs/examples** — if many games use `cam_shake` but few call `cam_reset`, the relationship needs explaining.
3. **Which APIs are driving adoption** — trending usage of `touch_*` means mobile is taking off; we should invest there.

## Chosen Approach: Static Analysis at Publish Time

When a developer publishes a game through the site (Firebase Auth path) or via PR (GitHub path), a Firebase Function runs static analysis on the submitted `game.lua` (and any additional scene files) and records which public APIs are referenced.

### Why Static Analysis (not Runtime Telemetry)

| Approach | Pros | Cons | Verdict |
|---|---|---|---|
| Runtime telemetry | Shows real usage | Privacy, network dependency, spam risk, user consent | ❌ |
| Static analysis | No network, no consent, deterministic | Only source presence (not runtime hit) | ✅ |
| Periodic CI scan | Reuses `--scan --coverage` | Needs running games, slower | complementary |

Static analysis is enough because:
- If a game has `cam_get()` in its source, we assume it uses it (false positives are harmless — we just don't remove).
- If no game has `cam_get()` in its source across the whole catalog, it's a removal candidate.
- We don't need to know *how often* an API is called in production — existence is the signal.

## Pipeline Integration

```
  Developer publishes game
          │
          ▼
  ┌────────────────────────────────────────┐
  │  Firebase Function: publishGame()       │
  │                                        │
  │  1. Auth check                          │
  │  2. Validate structure (game.lua, etc.) │
  │  3. Static API analysis                 │
  │     ├─ parse game.lua with Lua lexer   │
  │     ├─ extract function call names     │
  │     └─ intersect with known API set    │
  │  4. Commit to release repo (as mono-bot)│
  │  5. Update Firestore                    │
  │     ├─ games/{slug}: { apis: [...] }   │
  │     └─ api_usage/{api}:                 │
  │         { used_by: [slug1, slug2, ...]} │
  │  6. Return success                      │
  └────────────────────────────────────────┘
```

## Firestore Schema

```
games/
  space-dodge/
    slug: "space-dodge"
    author: "deviankim"
    apis: ["cls", "rectf", "btn", "note", "cam_shake"]
    ...

api_usage/
  cam_shake/
    name: "cam_shake"
    used_by: ["space-dodge", "pong-master"]
    first_seen: "2026-04-10"
    last_seen: "2026-04-10"
  cam_get/
    name: "cam_get"
    used_by: []
    first_seen: null
```

## Queries This Enables

```
  "Which APIs have 0 games using them?"
    → api_usage collection where used_by array is empty

  "Which APIs are most used?"
    → api_usage ordered by used_by.length DESC

  "Which games will break if I remove cam_get?"
    → games collection where apis array-contains "cam_get"

  "What's the usage trend for touch_count this quarter?"
    → aggregate games.created_at + apis array-contains
```

## Detection Technique

A small Lua parser inside the Function extracts identifiers that look like function calls:

```
  game.lua:
    cam(px, py)                    → call: cam
    if btnp("a") then              → call: btnp
    rectf(scr, x, y, w, h, c)      → call: rectf

  Known public API set (from engine.js):
    ["cls", "pix", "gpix", "line", "rect", "rectf", ...]

  Intersection:
    ["cam", "btnp", "rectf"]       ← this game's API set
```

Implementation options:
- **Simplest**: regex for `\b(\w+)\s*\(` and intersect with known set. False positives on Lua keywords but harmless.
- **Better**: use a Lua parser (e.g. `luaparse` on npm) to get real AST and extract `CallExpression` nodes.
- **Best**: run the game through `mono-test.js --coverage` in scan mode for runtime-accurate data (but slower).

Start with regex. Upgrade if false positive rate matters.

## Surfacing the Data

When the maintainer wants to clean up dead APIs:

```
  $ node scripts/unused-apis.js
  Fetching api_usage from Firestore...

  Unused (0 games):
    cam_get      — never seen
    canvas_del   — never seen

  Rarely used (<3 games):
    swipe        — 1 game  [paint-demo]
    noise        — 2 games [starfighter, synth]

  Heavily used (>50% of catalog):
    cls, rectf, text, btn, btnp
```

Same data can power a public dashboard (`monogame-storage.github.io/release/api-usage.html`) showing which APIs are load-bearing for the community.

## Stage Gating

- **ALPHA** (now): no need; `mono-test.js --scan --coverage` on local `demo/` is enough.
- **BETA** (editor): still local; maybe track in editor telemetry if developers opt in.
- **GAMMA** (publishing): implement this doc. Firebase Function does static analysis on every publish.
- **PUBLIC** (community): expose the usage dashboard publicly so developers know which APIs are "safe" (widely used) vs "experimental" (rarely used).

## Related

- `docs/CLI-TEST-RUNNER.md` — `--coverage` flag (runtime-based, single run)
- `docs/HEADLESS-TEST-IDEAS.md` — API Coverage section
- Issue ssk-play/mono#39 — publishing platform architecture
