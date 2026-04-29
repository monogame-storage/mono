# Cosmi eval harness

Drives the production `/chat/agent` loop offline against KIMI k2.6 to
measure how often Cosmi can turn a game spec into a working Mono game.

Mirrors the prod backend:
- Same system prompt (built from `mono/docs/API.md`).
- Same `AGENT_TOOLS` schema.
- Same `write_file` lint pipeline (`lintEnginePrimitiveOverwrite` +
  `lintApiCompliance` with cross-file project globals).

Differences:
- File I/O hits an in-memory R2 stub instead of Cloudflare's bucket.
- Calls Moonshot directly (no JWT, no wrangler).
- After the agent stops, every produced `.lua` runs through
  `dev/headless/mono-runner.js --frames 40` for a smoke test.

## Run

One spec:
```
KIMI_API_KEY=sk-... node harness.mjs specs/brick.txt
```

Whole battery (writes results to `results/`):
```
KIMI_API_KEY=sk-... node run-battery.mjs --parallel 2
```

Filter to a subset:
```
KIMI_API_KEY=sk-... node run-battery.mjs --filter brick
```

## Env

| var            | default                       | notes                                   |
|----------------|-------------------------------|-----------------------------------------|
| `KIMI_API_KEY` | (required)                    | Moonshot bearer key                     |
| `KIMI_MODEL`   | `kimi-k2.6`                   | override to compare model versions      |
| `KIMI_BASE`    | `https://api.moonshot.ai`     | for relays                              |
| `MONO_REPO`    | `../..`                       | path to the mono repo root (API.md + runner) |
| `MAX_ITER`     | `20`                          | agent loop cap, mirrors prod            |
| `KIMI_JUDGE_MODEL` | same as `KIMI_MODEL`      | model used for the post-run intent judge |
| `NO_JUDGE`     | `0`                           | set to `1` to skip the judge phase entirely |

## What gets recorded

Per spec, `runOne()` returns:
```
{
  spec: "brick",
  elapsedMs: 47210,
  files: [{ name, size }, ...],
  log: {
    iterations: 4,
    writes: [...],
    rejections: [...],         # write_file blocks (engine prim / API.md)
    deletes: [...],
    parseErrors: [...],        # tool args that didn't JSON.parse
    tokens: { input, output },
    elapsedPerTurn: [ms, ms, ...],
    finalText: "...",
    timedOut: false,
    error: null,
  },
  smoke: {
    passed: true,
    code: 0,
    stdout: "...",
    stderr: "...",
  }
}
```

Battery prints a summary table and writes one JSON file per spec to
`results/`. Re-running overwrites only that timestamp's batch.

## Adding specs

Drop a `<name>.txt` into `specs/`. Korean or English both fine — the
agent prompt is multilingual. Keep specs short and concrete; the model
gets the full Mono API.md so requirements should focus on game design,
not engine glue.
