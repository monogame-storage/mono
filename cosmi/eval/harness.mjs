#!/usr/bin/env node
// Eval harness — drive Cosmi (KIMI k2.6) headlessly with a single game spec
// and report what the agent produced. Mirrors mono-api's /chat/agent loop:
//   - same system prompt (built from local mono/docs/API.md)
//   - same AGENT_TOOLS schema
//   - same write_file lint pipeline (engine-primitive + API.md compliance,
//     with cross-file project globals merged in)
// File I/O is an in-memory R2 stub instead of Cloudflare's bucket so we can
// run hundreds of these per minute. After the agent finishes, every produced
// .lua is shelled through dev/headless/mono-runner.js for a 40-frame smoke
// test so we catch runtime errors the linter can't see.
//
// Usage:
//   KIMI_API_KEY=sk-... node harness.mjs specs/brick.txt
// Optional env:
//   KIMI_MODEL    default "kimi-k2.6"
//   KIMI_BASE     default "https://api.moonshot.ai"
//   MONO_REPO     default "../../mono" (resolved from this file)
//   MAX_ITER      default 20

import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

import {
  extractApiWhitelist,
  lintApiCompliance,
  collectFileDefinedNames,
} from "../src/lib/api-lint.js";
import { lintEnginePrimitiveOverwrite } from "../src/lib/lint.js";
import { validateAgentPath } from "../src/lib/path.js";
import { AGENT_TOOLS, AGENT_MAX_ITER, buildAgentSystemPrompt } from "../src/lib/agent-prompt.js";

const ROOT = path.dirname(fileURLToPath(import.meta.url));
// cosmi/eval/ → mono/ is two parents up. Override MONO_REPO if you've
// moved cosmi/ outside the mono tree (rare).
const MONO_REPO = path.resolve(ROOT, process.env.MONO_REPO || "../..");
const API_MD_PATH = path.join(MONO_REPO, "docs/API.md");
const MONO_RUNNER = path.join(MONO_REPO, "dev/headless/mono-runner.js");

const KIMI_API_KEY = process.env.KIMI_API_KEY;
const KIMI_MODEL = process.env.KIMI_MODEL || "kimi-k2.6";
const KIMI_BASE = process.env.KIMI_BASE || "https://api.moonshot.ai";
// The judge defaults to the same model — fine for first-pass scoring
// since the judge prompt lists explicit rubric items, leaving little
// room for self-flattery. Override with KIMI_JUDGE_MODEL=kimi-k2.5
// (etc.) to cross-check or save cost.
const KIMI_JUDGE_MODEL = process.env.KIMI_JUDGE_MODEL || KIMI_MODEL;
// Set NO_JUDGE=1 to skip the judge phase entirely (useful when
// iterating on lint logic — saves ~30s and ~5k tokens per spec).
const SKIP_JUDGE = process.env.NO_JUDGE === "1";
// Override only when probing model behaviour at extreme depths;
// default mirrors the prod Worker so harness numbers match what
// users actually hit.
const MAX_ITER = parseInt(process.env.MAX_ITER || String(AGENT_MAX_ITER), 10);

class InMemoryR2 {
  constructor() { this.files = new Map(); }
  list() {
    return [...this.files.entries()].map(([name, content]) => ({ name, size: content.length }));
  }
  get(p) { return this.files.get(p); }
  put(p, content) { this.files.set(p, content); }
  delete(p) { this.files.delete(p); }
}

async function execTool(name, input, ctx) {
  const { r2, whitelist, log } = ctx;
  switch (name) {
    case "list_files":
      return { files: r2.list() };
    case "read_file": {
      const bad = validateAgentPath(input?.path);
      if (bad) return { error: bad };
      const content = r2.get(input.path);
      if (content == null) return { error: `file not found: ${input.path}` };
      return { path: input.path, content };
    }
    case "write_file": {
      const bad = validateAgentPath(input?.path);
      if (bad) return { error: bad };
      if (typeof input.content !== "string") return { error: "content must be a string" };
      if (input.path.endsWith(".lua")) {
        const v1 = lintEnginePrimitiveOverwrite(input.content);
        if (v1) {
          log.rejections.push({ kind: "engine_primitive", path: input.path, reason: v1 });
          return { error: `write_file blocked: ${v1}` };
        }
        const projectDefined = new Set();
        for (const [name, content] of r2.files) {
          if (name === input.path || !name.endsWith(".lua")) continue;
          for (const id of collectFileDefinedNames(content)) projectDefined.add(id);
        }
        const v2 = lintApiCompliance(input.content, whitelist, { projectDefined });
        if (v2.length > 0) {
          const list = v2.map((x) => `${x.name}() at line ${x.line}`).join(", ");
          log.rejections.push({ kind: "api_compliance", path: input.path, violations: v2 });
          return { error: `write_file blocked: unknown function call(s) — ${list}` };
        }
      }
      r2.put(input.path, input.content);
      log.writes.push({ path: input.path, size: input.content.length });
      return { ok: true, path: input.path, bytes: input.content.length };
    }
    case "delete_file": {
      const bad = validateAgentPath(input?.path);
      if (bad) return { error: bad };
      r2.delete(input.path);
      log.deletes.push({ path: input.path });
      return { ok: true, path: input.path };
    }
    default:
      return { error: `unknown tool: ${name}` };
  }
}

async function callKimi(messages) {
  const res = await fetch(`${KIMI_BASE.replace(/\/$/, "")}/v1/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${KIMI_API_KEY}`,
    },
    body: JSON.stringify({
      model: KIMI_MODEL,
      messages,
      tools: AGENT_TOOLS,
      tool_choice: "auto",
      max_tokens: 8192,
    }),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`kimi ${res.status}: ${body.slice(0, 500)}`);
  }
  return res.json();
}

async function runAgentLoop(systemPrompt, userMessage, ctx) {
  const { log } = ctx;
  const messages = [
    { role: "system", content: systemPrompt },
    { role: "user", content: userMessage },
  ];

  for (let iter = 0; iter < MAX_ITER; iter++) {
    log.iterations = iter + 1;
    const t0 = Date.now();
    const response = await callKimi(messages);
    log.elapsedPerTurn.push(Date.now() - t0);
    const usage = response.usage || {};
    log.tokens.input += usage.prompt_tokens || 0;
    log.tokens.output += usage.completion_tokens || 0;

    const choice = response.choices?.[0];
    const msg = choice?.message;
    if (!msg) {
      log.error = "no choice in response";
      return;
    }
    // Diagnostic — capture finish_reason so we can tell truncation
    // (`length`) from natural stop / tool_calls.
    log.finishReasons = log.finishReasons || [];
    log.finishReasons.push(choice.finish_reason || null);
    // Push the assistant turn back so subsequent tool calls can chain.
    messages.push(msg);

    if (msg.tool_calls?.length > 0) {
      for (const tc of msg.tool_calls) {
        let input;
        try {
          input = JSON.parse(tc.function.arguments || "{}");
        } catch (e) {
          input = {};
          log.parseErrors.push({ tool: tc.function.name, raw: tc.function.arguments });
        }
        const result = await execTool(tc.function.name, input, ctx);
        messages.push({
          role: "tool",
          tool_call_id: tc.id,
          content: JSON.stringify(result),
        });
      }
      continue;
    }

    // No tool calls → final text. We've fulfilled this turn.
    log.finalText = msg.content || "";
    return;
  }
  log.timedOut = true;
}

async function smokeTest(r2) {
  if (!r2.get("main.lua")) return { passed: false, reason: "no main.lua produced" };

  const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "mono-eval-"));
  try {
    for (const [name, content] of r2.files) {
      const fp = path.join(tmpDir, name);
      await fs.mkdir(path.dirname(fp), { recursive: true });
      await fs.writeFile(fp, content);
    }
    const result = await new Promise((resolve) => {
      const proc = spawn("node", [
        MONO_RUNNER,
        path.join(tmpDir, "main.lua"),
        "--frames", "40",
        "--quiet",
        "--colors", "4",
      ], { stdio: ["ignore", "pipe", "pipe"] });
      let stdout = "", stderr = "";
      proc.stdout.on("data", (d) => { stdout += d; });
      proc.stderr.on("data", (d) => { stderr += d; });
      const timer = setTimeout(() => proc.kill("SIGKILL"), 30000);
      proc.on("exit", (code) => {
        clearTimeout(timer);
        resolve({ code, stdout, stderr });
      });
    });
    return {
      passed: result.code === 0,
      code: result.code,
      stdout: result.stdout.slice(-2000),
      stderr: result.stderr.slice(-2000),
    };
  } finally {
    await fs.rm(tmpDir, { recursive: true, force: true });
  }
}

// LLM judge — score the produced game against the spec on a 0-10
// scale. Smoke says "did it boot for 40 frames"; the judge says "did
// it actually do what was asked". Deliberately uses a separate
// session from the agent so the judge has no memory of the model's
// own writes / reasoning.
async function judgeOutput({ spec, files, smoke, log }) {
  if (SKIP_JUDGE) return { skipped: true };
  if (files.length === 0) {
    return {
      score: 0,
      summary: "Agent produced no files.",
      missing: ["any output"],
      present: [],
    };
  }

  const fileBlock = files
    .map(({ name, content }) => `### ${name}\n\`\`\`lua\n${content}\n\`\`\``)
    .join("\n\n");
  const smokeBlock = smoke.passed
    ? `Smoke test PASSED (booted + ran 40 frames cleanly).`
    : `Smoke test FAILED (exit ${smoke.code}). Stderr: ${(smoke.stderr || "").slice(0, 400)}`;

  const judgePrompt = [
    "You are reviewing a Mono fantasy console game produced by an AI agent against a user spec.",
    "Mono runs Lua 5.4, 160x120, up to 16 grayscale shades. The agent had access to docs/API.md.",
    "",
    "Score 0-10 on how well the produced code FULFILS THE SPEC, not on code style.",
    "Rubric:",
    "- 0-3: skeleton only or missing major features",
    "- 4-6: most features present but with significant gaps or bugs",
    "- 7-8: all primary features present, minor polish or edge-case gaps",
    "- 9-10: spec fully realized including edge cases (game-over, restart, etc.)",
    "",
    "Reply with ONLY a JSON object, no prose, no code fences:",
    '{ "score": <0-10>, "summary": "<one sentence>", "present": ["<feature>", ...], "missing": ["<feature>", ...] }',
    "",
    "## Spec",
    spec.trim(),
    "",
    "## Smoke",
    smokeBlock,
    "",
    "## Files",
    fileBlock,
  ].join("\n");

  try {
    const res = await fetch(`${KIMI_BASE.replace(/\/$/, "")}/v1/chat/completions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${KIMI_API_KEY}`,
      },
      body: JSON.stringify({
        // temperature is not set — KIMI k2.6 currently rejects any
        // value other than 1, and the rubric is concrete enough that
        // determinism isn't critical. max_tokens matches the agent
        // loop budget — k2.6 spends 4-6k tokens on internal reasoning
        // for a long file review and returns an empty content if it
        // hits the cap mid-thought (observed: 2/4 judge calls came
        // back blank at 4096).
        model: KIMI_JUDGE_MODEL,
        messages: [
          { role: "system", content: "You output only a single JSON object." },
          { role: "user", content: judgePrompt },
        ],
        max_tokens: 8192,
      }),
    });
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      return { error: `judge ${res.status}: ${body.slice(0, 300)}` };
    }
    const data = await res.json();
    log.judgeTokens = {
      input: data.usage?.prompt_tokens || 0,
      output: data.usage?.completion_tokens || 0,
    };
    const text = data.choices?.[0]?.message?.content || "";
    // Strip ```json fences if the model adds them despite instructions.
    const cleaned = text.trim().replace(/^```(?:json)?\s*/i, "").replace(/```\s*$/i, "");
    try {
      const parsed = JSON.parse(cleaned);
      const score = Number(parsed.score);
      return {
        score: Number.isFinite(score) ? Math.max(0, Math.min(10, score)) : null,
        summary: typeof parsed.summary === "string" ? parsed.summary : "",
        present: Array.isArray(parsed.present) ? parsed.present : [],
        missing: Array.isArray(parsed.missing) ? parsed.missing : [],
      };
    } catch {
      return { error: "judge response was not JSON", raw: text.slice(0, 500) };
    }
  } catch (e) {
    return { error: e?.message || String(e) };
  }
}

export async function runOne(specPath) {
  if (!KIMI_API_KEY) throw new Error("KIMI_API_KEY env var is required");
  const spec = await fs.readFile(specPath, "utf8");
  const apiDoc = await fs.readFile(API_MD_PATH, "utf8");
  const whitelist = extractApiWhitelist(apiDoc);
  const systemPrompt = buildAgentSystemPrompt(apiDoc);
  const r2 = new InMemoryR2();
  const log = {
    rejections: [],
    writes: [],
    deletes: [],
    parseErrors: [],
    tokens: { input: 0, output: 0 },
    elapsedPerTurn: [],
    iterations: 0,
    timedOut: false,
    finalText: "",
    error: null,
  };

  const t0 = Date.now();
  try {
    await runAgentLoop(systemPrompt, spec, { r2, whitelist, log });
  } catch (e) {
    log.error = e?.message || String(e);
  }
  const elapsedMs = Date.now() - t0;
  const smoke = await smokeTest(r2);
  const filesFull = [...r2.files.entries()].map(([name, content]) => ({ name, content }));
  const judge = await judgeOutput({ spec, files: filesFull, smoke, log });

  return {
    spec: path.basename(specPath, path.extname(specPath)),
    elapsedMs,
    files: filesFull.map(({ name, content }) => ({ name, size: content.length })),
    log,
    smoke,
    judge,
  };
}

// CLI entry
if (import.meta.url === `file://${process.argv[1]}`) {
  const specArg = process.argv[2];
  if (!specArg) {
    console.error("Usage: KIMI_API_KEY=... node harness.mjs <spec-file>");
    process.exit(2);
  }
  const specPath = path.resolve(process.cwd(), specArg);
  runOne(specPath).then(
    (r) => {
      console.log(JSON.stringify(r, null, 2));
      // Non-zero exit if the smoke test failed so CI / batch runners can
      // distinguish a successful run from a runtime regression.
      process.exit(r.smoke.passed ? 0 : 1);
    },
    (e) => {
      console.error("harness error:", e?.stack || e);
      process.exit(2);
    },
  );
}
