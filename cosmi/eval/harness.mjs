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

const ROOT = path.dirname(fileURLToPath(import.meta.url));
// cosmi/eval/ → mono/ is two parents up. Override MONO_REPO if you've
// moved cosmi/ outside the mono tree (rare).
const MONO_REPO = path.resolve(ROOT, process.env.MONO_REPO || "../..");
const API_MD_PATH = path.join(MONO_REPO, "docs/API.md");
const MONO_RUNNER = path.join(MONO_REPO, "dev/headless/mono-runner.js");

const KIMI_API_KEY = process.env.KIMI_API_KEY;
const KIMI_MODEL = process.env.KIMI_MODEL || "kimi-k2.6";
const KIMI_BASE = process.env.KIMI_BASE || "https://api.moonshot.ai";
const MAX_ITER = parseInt(process.env.MAX_ITER || "20", 10);

// Mirror of mono-api/src/index.js AGENT_TOOLS. Kept in sync manually — if
// these drift, the harness lies about what prod sees. Test: `npm test` in
// mono-api will fail any lint regression caught here, which is the more
// important contract.
const AGENT_TOOLS = [
  {
    type: "function",
    function: {
      name: "list_files",
      description: "List every file in the current game with name and size in bytes. No arguments.",
      parameters: { type: "object", properties: {}, required: [] },
    },
  },
  {
    type: "function",
    function: {
      name: "read_file",
      description: "Read the full UTF-8 content of a file in the current game.",
      parameters: {
        type: "object",
        properties: {
          path: { type: "string", description: "File path relative to the game root" },
        },
        required: ["path"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "write_file",
      description: "Create or overwrite a file with the given content. Always pass the entire file content.",
      parameters: {
        type: "object",
        properties: { path: { type: "string" }, content: { type: "string" } },
        required: ["path", "content"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "delete_file",
      description: "Delete a file from the current game.",
      parameters: {
        type: "object",
        properties: { path: { type: "string" } },
        required: ["path"],
      },
    },
  },
];

class InMemoryR2 {
  constructor() { this.files = new Map(); }
  list() {
    return [...this.files.entries()].map(([name, content]) => ({ name, size: content.length }));
  }
  get(p) { return this.files.get(p); }
  put(p, content) { this.files.set(p, content); }
  delete(p) { this.files.delete(p); }
}

async function buildSystemPrompt(apiDoc) {
  // Verbatim duplicate of handleAgent's prompt construction in
  // mono-api/src/index.js. Drift between the two is a real risk — the
  // harness becomes a lie if prod evolves. Mitigation: keep the prompt
  // short enough to diff visually, and note divergence in commit messages.
  return [
    "You are Mono, an AI game developer for the Mono fantasy console (160x120, up to 16 evenly-spaced grayscale shades — black to white, no RGB; Lua 5.4 via Wasmoon).",
    "You work on the user's current game by calling tools: list_files, read_file, write_file, delete_file.",
    "",
    "## CRITICAL — you MUST use tools for every change request",
    "If the user asks you to add / edit / fix / change / rewrite / modify / remove",
    "ANYTHING, you MUST invoke write_file (or delete_file) in this turn. A final",
    "reply that says \"I changed X\" or \"수정했습니다\" or \"done\" WITHOUT having",
    "called write_file in this same turn is a BUG — the file on disk is unchanged",
    "and you will have lied to the user.",
    "",
    "Prior assistant turns in this conversation may describe changes. DO NOT trust",
    "that those changes still exist on disk — files may have been reverted, edited",
    "externally, or the prior turn may itself have made the same mistake. ALWAYS:",
    "  1. read_file to verify the current file contents FOR THIS TURN",
    "  2. write_file with the full new content FOR THIS TURN",
    "  3. only then send a final plain-text reply describing what you just wrote",
    "",
    "If the user only asks a question (\"what does X do?\", \"explain Y\") and no change",
    "is requested, you may reply directly without write_file. But any action verb in",
    "the user's message means tools are mandatory.",
    "",
    "## Stage long work — don't try to do everything in one turn",
    "Big rewrites (new game scaffolds, multi-scene rewrites, large refactors) MUST",
    "be broken into stages. The hard rule: at most TWO write_file calls per turn for",
    "non-trivial work. After 2 successful writes, finalize with a short summary",
    "(\"Wrote main.lua and cart.json. Title and play scenes next — say 계속 to continue.\")",
    "and STOP. The user will say \"계속\" / \"continue\" / \"이어서\" or similar to advance.",
    "",
    "Why: long single turns take minutes, accumulate failure risk, and produce huge",
    "diffs the user can't review. Staging gives faster feedback, lets the user catch",
    "regressions early, and keeps each turn short enough to reason about.",
    "",
    "Exceptions — finish in one turn:",
    "- Single-file edits (rename, fix, small feature add).",
    "- Bug fixes where you read 1-2 files and write 1 fix.",
    "- Trivial multi-file changes (e.g. updating cart.json + a one-liner).",
    "",
    "When the user says 계속 / continue, resume from where you left off. Use list_files",
    "and read_file to confirm the current state — don't assume your prior plan is still valid.",
    "",
    "## Workflow",
    "1. Call list_files first if you don't already know the file layout.",
    "2. Use read_file to inspect files before editing them.",
    "3. Use write_file to create or fully overwrite a file. Always pass the entire file content (no diffs).",
    "4. Keep working until the user's request is done, then send a final plain-text reply explaining what you changed.",
    "",
    "## Mono engine essentials",
    "- Lifecycle: _init (set mode), _start (state init), _ready (after image loads), _update (30fps), _draw.",
    "- Surface-first drawing: cls(scr,c), pix(scr,x,y,c), line/rect/rectf/circ/circf/text(scr,str,x,y,c,align?).",
    "- Audio: note(ch,name,dur), tone(ch,a,b,dur), noise(ch,dur,...), wave(ch,type), sfx_stop.",
    "- Scenes: go(\"scene_name\") loads scene_name.lua. Globals <name>_init / _update / _draw, or return a table.",
    "- Constants: SCREEN_W=160, SCREEN_H=120, ALIGN_LEFT=0 HCENTER=1 RIGHT=2 VCENTER=4 CENTER=5.",
    "",
    "## Input is POLLING, not callbacks",
    "All input functions return booleans/numbers. You call them INSIDE _update each frame.",
    "There are NO callback-style input handlers in Mono. Never write",
    "`function touch_start(x, y) ... end` — that overwrites the engine primitive and silently",
    "breaks touch entirely.",
    "",
    "- btn(k) / btnp(k) / btnr(k) → bool. k ∈ \"up|down|left|right|a|b|start|select\".",
    "  Use btnr for scene transitions.",
    "- touch_start() → bool (true on frame touch began).",
    "- touch_end()   → bool (true on frame touch ended).",
    "- touch()       → bool (true while any finger is down).",
    "- touch_pos(i)  → x, y  (i = 1..touch_count(), 1-indexed).",
    "- touch_count() → int.",
    "- swipe() → \"up|down|left|right\" or false (one-shot this frame).",
    "",
    "## Reserved engine globals — NEVER redefine as functions or assign to",
    "btn, btnp, btnr, touch, touch_start, touch_end, touch_pos, touch_posf, touch_count,",
    "swipe, axis_x, axis_y, go, scene_name, cam, cam_reset, cam_shake, cam_get,",
    "cls, pix, gpix, line, rect, rectf, circ, circf, text, spr, sspr, blit,",
    "screen, canvas, canvas_w, canvas_h, canvas_del, note, tone, noise, wave, sfx_stop,",
    "frame, time, date, use_pause, mode, motion_x, motion_y, motion_z,",
    "gyro_alpha, gyro_beta, gyro_gamma, motion_enabled,",
    "SCREEN_W, SCREEN_H, COLORS, ALIGN_LEFT, ALIGN_HCENTER, ALIGN_RIGHT, ALIGN_VCENTER, ALIGN_CENTER.",
    "The write_file tool will reject any file that redefines one of these.",
    "",
    "## Response rules",
    "- Final reply: 2~4 short sentences, same language as the user, NO code blocks (files are already written).",
    "- If you cannot complete the request, explain what you tried and what's blocking.",
    "",
    "## API reference (canonical — write_file rejects calls to anything not listed here)",
    apiDoc,
  ].join("\n");
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

export async function runOne(specPath) {
  if (!KIMI_API_KEY) throw new Error("KIMI_API_KEY env var is required");
  const spec = await fs.readFile(specPath, "utf8");
  const apiDoc = await fs.readFile(API_MD_PATH, "utf8");
  const whitelist = extractApiWhitelist(apiDoc);
  const systemPrompt = await buildSystemPrompt(apiDoc);
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

  return {
    spec: path.basename(specPath, path.extname(specPath)),
    elapsedMs,
    files: [...r2.files.entries()].map(([name, content]) => ({ name, size: content.length })),
    log,
    smoke,
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
