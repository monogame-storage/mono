#!/usr/bin/env node
// mono-docs-sync: verify that docs/DEV.md and runtime/engine.js agree
// on the public API surface.
//
// Parses:
//   runtime/engine.js               → every lua.global.set("name", ...) → set of API names
//   docs/DEV.md                     → every `name(...)` or `name` in a code block → set of documented names
//
// Reports:
//   - APIs in engine but NOT in DEV.md          (undocumented)
//   - APIs in DEV.md but NOT in engine           (ghost / renamed / removed)
//   - Internal helpers (prefixed with _)         (informational, skipped from "undocumented" bucket)
//
// Usage:
//   node mono-docs-sync.js
//
// Exit code:
//   0 — docs and engine agree
//   1 — mismatch detected

"use strict";

const fs = require("fs");
const path = require("path");

const REPO_ROOT = path.resolve(__dirname, "../..");
const ENGINE_JS = path.join(REPO_ROOT, "runtime/engine.js");
const DEV_MD = path.join(REPO_ROOT, "docs/DEV.md");

const ANSI = {
  red:    s => `\x1b[31m${s}\x1b[0m`,
  yellow: s => `\x1b[33m${s}\x1b[0m`,
  green:  s => `\x1b[32m${s}\x1b[0m`,
  dim:    s => `\x1b[2m${s}\x1b[0m`,
  bold:   s => `\x1b[1m${s}\x1b[0m`,
};

// Shared helper knows about _internal → public mapping and the engine.js
// parsing logic. Kept minimal here so this script focuses on the sync check.
const { loadPublicAPIs } = require("./lib/engine-apis");

// APIs that are intentionally not documented (Lua built-ins, internal wrappers)
const UNDOCUMENTED_OK = new Set([
  "print",  // Lua built-in, routed for debugging
]);

function extractEngineAPIs() {
  return loadPublicAPIs(ENGINE_JS);
}

function extractDocAPIs() {
  const src = fs.readFileSync(DEV_MD, "utf8");
  const lines = src.split("\n");
  const names = new Set();
  let inCodeBlock = false;
  let codeLang = "";

  // Also scan the whole doc (not just code blocks) for backtick-quoted
  // constant-style identifiers: `SCREEN_W`, `COLORS`, `ALIGN_CENTER`, etc.
  // This lets docs document uppercase constants in prose or tables.
  const constRe = /`([A-Z][A-Z0-9_]*)`/g;
  let constMatch;
  while ((constMatch = constRe.exec(src)) !== null) {
    names.add(constMatch[1]);
  }

  for (const line of lines) {
    const fence = line.match(/^```(\w*)/);
    if (fence) {
      if (inCodeBlock) {
        inCodeBlock = false;
        codeLang = "";
      } else {
        inCodeBlock = true;
        codeLang = fence[1] || "";
      }
      continue;
    }
    if (!inCodeBlock) continue;
    // Only scan lua / typescript-ish blocks (skip shell, etc.)
    if (codeLang && !/lua|typescript|ts|js/i.test(codeLang)) continue;
    // Skip lua comments
    if (line.trim().startsWith("--")) continue;
    // Match function calls: identifier directly followed by ( (no space allowed)
    // This avoids matching prose like "at (x, y)" where there's whitespace.
    const callRe = /(?:^|[^.\w])([a-z_][\w]*)\(/g;
    let m;
    while ((m = callRe.exec(line)) !== null) {
      const name = m[1];
      // Filter out Lua keywords and common generic names
      if (["function", "if", "for", "while", "return", "local", "end", "then", "do"].includes(name)) continue;
      // Filter out common stdlib identifiers
      if (["math", "string", "table", "io", "os", "require", "print", "pairs", "ipairs", "tostring", "tonumber", "type", "unpack", "select"].includes(name)) continue;
      names.add(name);
    }
    // Also catch uppercase constants referenced inside code blocks
    const uppercaseRe = /(?:^|[^.\w])([A-Z][A-Z0-9_]+)\b/g;
    let u;
    while ((u = uppercaseRe.exec(line)) !== null) {
      names.add(u[1]);
    }
  }
  return names;
}

function main() {
  if (!fs.existsSync(ENGINE_JS)) {
    console.error(`not found: ${ENGINE_JS}`);
    process.exit(2);
  }
  if (!fs.existsSync(DEV_MD)) {
    console.error(`not found: ${DEV_MD}`);
    process.exit(2);
  }

  const engineAPIs = extractEngineAPIs();
  const docAPIs = extractDocAPIs();

  // Undocumented: in engine but not in docs (excluding OK list)
  const undocumented = [...engineAPIs]
    .filter(n => !docAPIs.has(n))
    .filter(n => !UNDOCUMENTED_OK.has(n))
    .sort();

  // Ghost: in docs but not in engine
  // Some docs mention utility names that aren't APIs (e.g., variables); filter obvious ones
  const ghost = [...docAPIs]
    .filter(n => !engineAPIs.has(n))
    // Ignore lifecycle callbacks (user-defined, not engine APIs)
    .filter(n => !/^_(init|start|update|draw)$/.test(n))
    // Ignore scene-prefixed lifecycle (e.g., play_init, title_draw)
    .filter(n => !/_(init|start|update|draw)$/.test(n))
    // Ignore names that look like local variables or helpers from example code
    .filter(n => !/^(my|new|local|self|state|game|world|scene|entity|player|enemy|bullet|tile)/.test(n))
    // Ignore common example identifiers
    .filter(n => !["init", "update", "draw", "handle", "spawn", "fire", "move", "hit", "next_page"].includes(n))
    .sort();

  console.log(ANSI.bold("=== MONO DOCS SYNC ==="));
  console.log(`engine.js: ${engineAPIs.size} public APIs`);
  console.log(`DEV.md:    ${docAPIs.size} symbols referenced in code blocks`);
  console.log();

  if (undocumented.length === 0) {
    console.log(ANSI.green("✓ All engine APIs are documented in DEV.md"));
  } else {
    console.log(ANSI.red(`✗ ${undocumented.length} API(s) in engine.js but not in DEV.md:`));
    for (const n of undocumented) {
      console.log(`  ${ANSI.red(n)}`);
    }
  }
  console.log();

  if (ghost.length === 0) {
    console.log(ANSI.green("✓ No ghost APIs in DEV.md"));
  } else {
    console.log(ANSI.yellow(`⚠ ${ghost.length} symbol(s) in DEV.md but not in engine.js (possibly renamed, removed, or example-only):`));
    // Trim to a reasonable limit
    const shown = ghost.slice(0, 30);
    for (const n of shown) {
      console.log(`  ${ANSI.yellow(n)}`);
    }
    if (ghost.length > shown.length) {
      console.log(`  ${ANSI.dim("... " + (ghost.length - shown.length) + " more")}`);
    }
  }

  console.log();
  const strictFail = undocumented.length > 0;
  if (strictFail) {
    console.log(ANSI.red("RESULT: DOCS OUT OF SYNC"));
    process.exit(1);
  } else {
    console.log(ANSI.green("RESULT: DOCS IN SYNC"));
    process.exit(0);
  }
}

main();
