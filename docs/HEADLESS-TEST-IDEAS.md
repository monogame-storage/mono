# Headless Test Enhancement Ideas

Mono's headless test runner (`mono-test.js`) already uses VRAM inspection via `vdump()` for deterministic verification. This document collects ideas for extending it further.

## ALPHA Stage — Build Now

### 1. Input Replay

Record real gameplay → save input sequence → replay in tests.

```
Record:  actual play session → .replay file (frame, key, pressed)
Replay:  test loads .replay → runs engine with scripted inputs
         → compare final VRAM hash with expected
```

**Use case:** bug reported → save as `.replay` file → fix engine → run same replay to verify fix → keep as regression test forever.

**Format:**
```
frame:   0  input: right  pressed
frame:  12  input: right  released
frame:  15  input: a      pressed
frame:  16  input: a      released
```

---

### 2. ASCII VRAM Diff

When a test fails, show the difference as ASCII art so humans (and AIs) can understand immediately.

```
expected:          actual:            diff:
..##..            ..##..             ......
.####.            .####.             ......
######            #####.             .....X
.####.            .####.             ......
```

**Why:** hash-only failures give no clue. ASCII diff makes the failure visual without needing an image renderer.

---

### 3. Determinism Verification

Verify that same seed + same inputs always produces identical output.

```lua
for i = 1, 100 do
    result[i] = run_game(seed=42, inputs=fixed)
end
assert(all(result[i] == result[1]))
```

**Why critical:** this is the prerequisite for lockstep multiplayer (issue #29). If the engine isn't deterministic, lockstep can never work. Better to discover it now in ALPHA than later.

**Common determinism breakers to check:**
- `math.random()` without fixed seed
- Iterating over Lua tables (order not guaranteed)
- Floating point operations that differ across platforms
- Time-based APIs

---

## BETA Stage — Build Later

### 4. API Coverage

Track which engine APIs are actually called during test runs.

```
pix():     1,203 calls ✓
rect():      842 calls ✓
circ():       12 calls ✓
note():        0 calls ✗ ← no demo uses this
```

**Why:** identify dead APIs for removal. In ALPHA we can break things freely, so unused APIs should be deleted.

---

### 5. AI Self-Play Testing

LLM plays the game autonomously while observing VRAM state.

```
1. Game state (VRAM or screenshot) → LLM
2. LLM: "I will move left to avoid the enemy"
3. Engine executes input → next frame
4. Repeat
5. If LLM gets stuck → report "unplayable" with context
```

**Why valuable:** AI becomes a QA tester that plays the game with intent, not random fuzzing. Finds actual gameplay bugs, not just crashes.

---

### 6. Golden Snapshot Regression

Store known-good VRAM hashes for each demo at key frames.

```
demos/pacman/snapshots/
├── frame_060.hash
├── frame_120.hash
└── frame_300.hash
```

Run all demos after any engine change → compare hashes → instantly know which demos were affected.

---

### 7. Performance Benchmarks

Track frame time and memory usage over time.

```
bench: 1000 frames of pacman
  avg:  2.3ms/frame
  p99:  4.1ms/frame
  heap: 8.2MB
```

**Why:** catch performance regressions in CI before they ship.

---

## GAMMA Stage — Build Much Later

### 8. Fuzzing / Chaos Testing

Random inputs + random API calls to find engine crashes.

```
1000 runs:
  - 2 crashes: rectf(-100, -100, ...)
  - 1 hang:    note("XYZ") infinite loop
```

**Why:** required before accepting user-submitted games in the publishing system.

---

### 9. Cross-Version Compatibility

Verify that older demos still work on newer engines.

```
engine-v1.0.js + pacman → VRAM hash A
engine-v1.1.js + pacman → VRAM hash A (must match)
```

**Why:** when publishing system goes live, published games should not break when the engine updates.

---

## Priority Summary

**Highest impact right now (~200 lines total):**
- Input Replay (#1)
- ASCII VRAM Diff (#2)
- Determinism Verification (#3)

These three together unlock:
- Lockstep multiplayer foundation (#29)
- Regression test loop for AI-generated code
- Bug reports as `.replay` files → instant reproduction
