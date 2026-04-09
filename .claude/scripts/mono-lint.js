#!/usr/bin/env node
// mono-lint: check a Lua game file against common Mono pitfalls
//
// Rules are derived from docs/AI-PITFALLS.md. Keep this script
// simple and pragmatic — regex heuristics, not a full Lua parser.
// False positives are acceptable; false negatives are not.
//
// Usage:
//   node mono-lint.js <file.lua> [file2.lua ...]
//   node mono-lint.js demo/pong/game.lua
//
// Exit codes:
//   0 — no findings
//   1 — at least one warning or error

"use strict";

const fs = require("fs");
const path = require("path");

const ANSI = {
  red:    s => `\x1b[31m${s}\x1b[0m`,
  yellow: s => `\x1b[33m${s}\x1b[0m`,
  dim:    s => `\x1b[2m${s}\x1b[0m`,
  bold:   s => `\x1b[1m${s}\x1b[0m`,
};

// --- Rules ---
// Each rule receives the full file content + per-line array.
// Returns an array of { line, severity, rule, msg }.
const RULES = [];

function rule(id, fn) { RULES.push({ id, fn }); }

// Rule 1: rnd() / math.random() called inside a _draw() function body
rule("draw-random", ({ lines }) => {
  const out = [];
  const funcRe = /^\s*(?:local\s+)?function\s+([\w.:_]+)\s*\(/;
  let inDraw = false;
  let drawName = "";
  let braceDepth = 0;  // Lua uses end, not braces; track with heuristic
  let endDepth = 0;

  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    const m = line.match(funcRe);
    if (m) {
      const name = m[1];
      if (/(^|_)draw$/.test(name) || /_draw\b/.test(name) || name === "draw") {
        inDraw = true;
        drawName = name;
        endDepth = 1;
        i++;
        continue;
      }
    }
    if (inDraw) {
      // Crude end-balancing: increment on for/while/if/do/function, decrement on end
      endDepth += (line.match(/\b(for|while|if|do|function|repeat)\b/g) || []).length;
      endDepth -= (line.match(/\bend\b/g) || []).length;
      endDepth -= (line.match(/\buntil\b/g) || []).length;  // repeat...until
      if (/\b(math\.random|rnd)\s*\(/.test(line) && !line.trim().startsWith("--")) {
        out.push({
          line: i + 1,
          severity: "warn",
          rule: "draw-random",
          msg: `random call inside ${drawName}() — generate once in _start() and store`,
        });
      }
      if (endDepth <= 0) {
        inDraw = false;
      }
    }
    i++;
  }
  return out;
});

// Rule 2: local function defined after it's called (forward reference)
rule("local-forward-ref", ({ lines }) => {
  const out = [];
  // Find all "local function NAME" and note their line
  const locals = {};  // name → line
  const localRe = /^\s*local\s+function\s+(\w+)\s*\(/;
  // First pass: record positions
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(localRe);
    if (m) locals[m[1]] = i + 1;
  }
  // Second pass: for each local, see if it's referenced on a line before its definition
  for (const name of Object.keys(locals)) {
    const defLine = locals[name];
    const callRe = new RegExp(`(^|[^.\\w:])${name}\\s*\\(`);
    for (let i = 0; i < defLine - 1; i++) {
      const l = lines[i];
      if (l.trim().startsWith("--")) continue;
      if (l.match(localRe) && l.match(localRe)[1] === name) continue;
      if (callRe.test(l)) {
        out.push({
          line: i + 1,
          severity: "error",
          rule: "local-forward-ref",
          msg: `local function ${name}() called here but defined later at line ${defLine}`,
        });
        break;
      }
    }
  }
  return out;
});

// Rule 3: text() inside a camera-affected block without cam reset
rule("text-after-cam", ({ lines }) => {
  const out = [];
  let camSet = false;
  let camLine = 0;
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    if (l.trim().startsWith("--")) continue;
    const camCall = l.match(/\bcam\s*\(\s*([^)]+)\)/);
    if (camCall) {
      const args = camCall[1].trim();
      // cam(0, 0) or cam_reset() resets
      if (args === "0, 0" || args === "0,0") {
        camSet = false;
      } else {
        camSet = true;
        camLine = i + 1;
      }
    }
    if (/\bcam_reset\s*\(\s*\)/.test(l)) camSet = false;
    if (camSet && /\btext\s*\(/.test(l)) {
      out.push({
        line: i + 1,
        severity: "warn",
        rule: "text-after-cam",
        msg: `text() after cam(non-zero) at line ${camLine} — text is not camera-affected, may look misaligned`,
      });
    }
  }
  return out;
});

// Rule 4: diagonal movement without normalization
rule("diagonal-unnormalized", ({ content }) => {
  const out = [];
  // Heuristic: if both x/horizontal and y/vertical movement use a raw "2" or similar
  // literal without a 0.7071 factor anywhere in the file, warn.
  const hasDiagHeuristic =
    /\bbtn\(\s*["']left["']\s*\).*\n.*?\bbtn\(\s*["']up["']\s*\)/.test(content) ||
    /\bbtn\(\s*["']up["']\s*\).*\n.*?\bbtn\(\s*["']left["']\s*\)/.test(content);
  if (hasDiagHeuristic && !/0\.7071|0\.70710|diagonal|normalize/i.test(content)) {
    out.push({
      line: 1,
      severity: "info",
      rule: "diagonal-unnormalized",
      msg: "game reads both horizontal and vertical buttons but no 0.7071 diagonal normalization detected",
    });
  }
  return out;
});

// Rule 5: rnd() used as a function (doesn't exist in Mono)
rule("rnd-nonexistent", ({ lines }) => {
  const out = [];
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    if (l.trim().startsWith("--")) continue;
    // Match rnd(...) but not math.random, not math.rnd, not foo.rnd
    if (/(^|[^.\w])rnd\s*\(/.test(l)) {
      out.push({
        line: i + 1,
        severity: "error",
        rule: "rnd-nonexistent",
        msg: "rnd() does not exist — use math.random() instead",
      });
    }
  }
  return out;
});

// Rule 6: removed/obsolete APIs (vrow, vdump)
rule("removed-api", ({ lines }) => {
  const out = [];
  const removed = ["vrow", "vdump"];
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    if (l.trim().startsWith("--")) continue;
    for (const api of removed) {
      const re = new RegExp(`(^|[^.\\w])${api}\\s*\\(`);
      if (re.test(l)) {
        out.push({
          line: i + 1,
          severity: "error",
          rule: "removed-api",
          msg: `${api}() was removed from the public API (test runner internal only)`,
        });
      }
    }
  }
  return out;
});

// Rule 7: drawing without surface (first argument) — easy to forget
rule("surface-missing", ({ lines }) => {
  const out = [];
  const drawFns = ["cls", "pix", "rect", "rectf", "circ", "circf", "line", "text", "spr", "sspr"];
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    if (l.trim().startsWith("--")) continue;
    for (const fn of drawFns) {
      // Match `fn(` with first arg that looks like a literal number or string (not a surface var)
      const re = new RegExp(`(?:^|[^.\\w])${fn}\\s*\\(\\s*(-?\\d|"[^"]|'[^'])`);
      if (re.test(l)) {
        out.push({
          line: i + 1,
          severity: "warn",
          rule: "surface-missing",
          msg: `${fn}() first arg looks like a value, not a surface — did you forget 'scr'?`,
        });
      }
    }
  }
  return out;
});

// --- Runner ---
function lintFile(file) {
  const content = fs.readFileSync(file, "utf8");
  const lines = content.split("\n");
  const findings = [];
  for (const r of RULES) {
    try {
      const fnOut = r.fn({ content, lines });
      for (const f of fnOut) findings.push(f);
    } catch (e) {
      findings.push({
        line: 0, severity: "error", rule: "lint-error",
        msg: `rule ${r.id} crashed: ${e.message}`,
      });
    }
  }
  findings.sort((a, b) => a.line - b.line);
  return findings;
}

function colorize(sev, txt) {
  if (sev === "error") return ANSI.red(txt);
  if (sev === "warn")  return ANSI.yellow(txt);
  return ANSI.dim(txt);
}

function main() {
  const files = process.argv.slice(2);
  if (files.length === 0) {
    console.error("usage: mono-lint.js <file.lua> [file2.lua ...]");
    process.exit(2);
  }
  let totalErrors = 0;
  let totalWarnings = 0;
  let totalInfos = 0;
  for (const file of files) {
    if (!fs.existsSync(file)) {
      console.error(ANSI.red(`not found: ${file}`));
      continue;
    }
    const findings = lintFile(file);
    if (findings.length === 0) {
      console.log(`${ANSI.bold(file)}: ${ANSI.dim("clean")}`);
      continue;
    }
    console.log(ANSI.bold(file));
    for (const f of findings) {
      const tag = colorize(f.severity, `[${f.severity}]`);
      console.log(`  ${tag} ${file}:${f.line} ${f.rule} — ${f.msg}`);
      if (f.severity === "error")  totalErrors++;
      else if (f.severity === "warn") totalWarnings++;
      else totalInfos++;
    }
  }
  console.log();
  console.log(`${totalErrors} error(s), ${totalWarnings} warning(s), ${totalInfos} info`);
  process.exit(totalErrors + totalWarnings > 0 ? 1 : 0);
}

main();
