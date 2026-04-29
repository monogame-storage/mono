#!/usr/bin/env node
// Run every spec in eval/specs/*.txt through harness.runOne and write
// per-spec JSON results to eval/results/<spec>-<ts>.json. Prints a
// summary table at the end. Concurrency-bounded so we don't hammer KIMI.
//
// Usage:
//   KIMI_API_KEY=sk-... node run-battery.mjs [--parallel N] [--filter brick]

import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { runOne } from "./harness.mjs";

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const SPECS_DIR = path.join(ROOT, "specs");
const RESULTS_DIR = path.join(ROOT, "results");

const args = process.argv.slice(2);
const PARALLEL = parseInt(getOpt("parallel", "2"), 10);
const FILTER = getOpt("filter", null);

function getOpt(name, def) {
  const i = args.indexOf("--" + name);
  if (i === -1) return def;
  return args[i + 1] ?? def;
}

async function pickSpecs() {
  const all = await fs.readdir(SPECS_DIR);
  return all
    .filter((f) => f.endsWith(".txt"))
    .filter((f) => !FILTER || f.includes(FILTER))
    .map((f) => path.join(SPECS_DIR, f));
}

// Bounded-concurrency pool. Native Promise.all would either run all at
// once (rate-limited by KIMI) or serialize. This middle ground keeps
// throughput up while staying polite.
async function runPool(items, n, fn) {
  const results = new Array(items.length);
  let next = 0;
  async function worker() {
    while (next < items.length) {
      const i = next++;
      try {
        results[i] = await fn(items[i], i);
      } catch (e) {
        results[i] = { error: e?.message || String(e) };
      }
    }
  }
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, worker));
  return results;
}

function fmtRow(r) {
  const writes = r.log?.writes?.length ?? 0;
  const rejs = r.log?.rejections?.length ?? 0;
  const iters = r.log?.iterations ?? 0;
  const sec = ((r.elapsedMs ?? 0) / 1000).toFixed(1);
  const tokIn = r.log?.tokens?.input ?? 0;
  const tokOut = r.log?.tokens?.output ?? 0;
  const smoke = r.smoke?.passed ? "PASS" : `FAIL${r.smoke?.code != null ? `(${r.smoke.code})` : ""}`;
  return `${r.spec.padEnd(8)} | iters ${String(iters).padStart(2)} | writes ${String(writes).padStart(2)} | rej ${String(rejs).padStart(2)} | smoke ${smoke.padEnd(8)} | ${sec}s | tok ${tokIn}/${tokOut}`;
}

async function main() {
  const specs = await pickSpecs();
  if (specs.length === 0) {
    console.error("no specs matched");
    process.exit(2);
  }
  await fs.mkdir(RESULTS_DIR, { recursive: true });
  const ts = new Date().toISOString().replace(/[:.]/g, "-");

  console.error(`Running ${specs.length} spec(s) with parallel=${PARALLEL}\n`);
  const results = await runPool(specs, PARALLEL, async (specPath, i) => {
    const name = path.basename(specPath, path.extname(specPath));
    console.error(`  → start: ${name}`);
    const r = await runOne(specPath);
    console.error(`  ✓ done:  ${name} (${(r.elapsedMs / 1000).toFixed(1)}s, smoke=${r.smoke.passed ? "pass" : "fail"})`);
    const out = path.join(RESULTS_DIR, `${name}-${ts}.json`);
    await fs.writeFile(out, JSON.stringify(r, null, 2));
    return r;
  });

  console.log("\n=== Summary ===");
  for (const r of results) {
    if (r?.error) console.log(`error: ${r.error}`);
    else console.log(fmtRow(r));
  }

  const passed = results.filter((r) => r?.smoke?.passed).length;
  console.log(`\n${passed}/${results.length} smoke tests passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => {
  console.error(e?.stack || e);
  process.exit(2);
});
