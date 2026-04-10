---
description: Run full Mono engine validation — scan, coverage, determinism, fuzz, bench
---

Run the Mono verification pipeline by invoking the helper script:

```bash
./.claude/scripts/mono-verify.sh
```

The script runs `mono-test.js` in four modes against every `main.lua` in `demo/`:

1. **SCAN + COVERAGE** — confirms every demo boots and reports aggregated public-API coverage.
2. **DETERMINISM** (3 runs × same seed) — confirms each demo is lockstep-ready.
3. **FUZZ** (50 runs × random inputs) — catches crashes from unexpected inputs.
4. **BENCH** — reports per-frame avg / p99 vs the 30 FPS budget.

Environment overrides (optional):

- `FRAMES=300 ./.claude/scripts/mono-verify.sh` — longer runs for thorough coverage
- `FUZZ_RUNS=200 ./.claude/scripts/mono-verify.sh` — more chaos
- `DETERMINISM_RUNS=5 ./.claude/scripts/mono-verify.sh` — stricter repeatability check

When to use:

- Before committing any change to `runtime/engine.js` or `editor/templates/mono/mono-test.js`
- When adding a new demo to confirm it plays nice with existing ones
- As a quick health check during engine refactors

Report the summary to the user. If any step fails, surface the specific game and reason so the user can drill in.
