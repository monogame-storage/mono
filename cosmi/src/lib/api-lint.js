// API.md compliance lint — reject Lua code that calls a function not
// documented in mono/docs/API.md. The agent path runs this in
// execAgentTool's write_file branch alongside lintEnginePrimitiveOverwrite,
// so an LLM that hallucinates `circle()` / `pset()` / `scrolltext()` gets
// a structured rejection it can self-correct on the next iteration.
//
// Two-step pipeline:
//   1. extractApiWhitelist(apiMd)  → Set<string>
//   2. lintApiCompliance(code, wl) → [{ name, line }, ...]  (empty = ok)
//
// extractApiWhitelist treats `### name(...)` and bare `### name` headings
// as functions. Lifecycle hooks (_init/_start/_ready/_update/_draw) are
// added explicitly because API.md only describes them in prose.
//
// lintApiCompliance is intentionally permissive: it errs toward NOT
// flagging anything that could plausibly be a user-defined name. False
// negatives (a hallucinated call slips through) are recoverable; false
// positives (a valid game gets blocked) make the agent loop unusable.
// Any identifier that appears on the LHS of `=`, after `function`, or as
// a `for` loop variable anywhere in the file is treated as defined and
// not flagged.

const LUA_KEYWORDS = new Set([
  "and", "break", "do", "else", "elseif", "end", "false", "for",
  "function", "goto", "if", "in", "local", "nil", "not", "or",
  "repeat", "return", "then", "true", "until", "while",
]);

const LUA_BUILTINS = new Set([
  "assert", "collectgarbage", "error", "getmetatable", "ipairs",
  "load", "next", "pairs", "pcall", "print", "rawequal", "rawget",
  "rawlen", "rawset", "select", "setmetatable", "tonumber", "tostring",
  "type", "unpack", "xpcall", "require",
]);

// Used two ways: the names are seeded into the whitelist verbatim
// (because API.md describes lifecycle hooks in prose, not headings),
// AND any identifier that *ends* with one of these is treated as a
// scene callback (game_update, title_init) defined in another file.
const SCENE_HOOK_NAMES = ["_init", "_start", "_ready", "_update", "_draw"];

export function extractApiWhitelist(apiMd) {
  const functions = new Set(SCENE_HOOK_NAMES);
  if (typeof apiMd !== "string") return functions;

  // `### name` or `### name(...)` — function reference headings.
  const headingRe = /^### +([a-z_][a-zA-Z0-9_]*)\b/gm;
  let m;
  while ((m = headingRe.exec(apiMd)) !== null) {
    functions.add(m[1]);
  }
  return functions;
}

// `opts.projectDefined`: optional Set of identifiers defined in OTHER
// files of the same project. Cross-file globals are normal in Mono — a
// scene file calls a helper declared in main.lua — so the harness
// computes this set from every .lua sibling on R2 and passes it in to
// suppress false positives.
export function lintApiCompliance(code, whitelist, opts = {}) {
  if (typeof code !== "string" || !code) return [];
  // Fail-open: an empty / missing whitelist means we don't have a doc to
  // check against (e.g. API.md fetch failed). Don't block writes.
  const wl = whitelist instanceof Set ? whitelist : null;
  if (!wl || wl.size === 0) return [];

  const stripped = stripCommentsAndStrings(code);
  const defined = collectDefinedNames(stripped);
  if (opts.projectDefined instanceof Set) {
    for (const n of opts.projectDefined) defined.add(n);
  }

  const callRe = /(?<![.:\w])([a-zA-Z_][a-zA-Z0-9_]*)\s*\(/g;
  const violations = [];
  const seen = new Set();

  let m;
  while ((m = callRe.exec(stripped)) !== null) {
    const name = m[1];
    if (seen.has(name)) continue;
    if (LUA_KEYWORDS.has(name)) continue;
    if (LUA_BUILTINS.has(name)) continue;
    if (defined.has(name)) continue;
    if (wl.has(name)) continue;
    if (SCENE_HOOK_NAMES.some((s) => name.endsWith(s))) continue;
    seen.add(name);
    violations.push({ name, line: countNewlines(stripped, m.index) + 1 });
  }
  return violations;
}

// Public version of the file-local definition scanner — exposed so the
// harness can pre-collect cross-file globals and feed them back into
// lintApiCompliance via opts.projectDefined.
export function collectFileDefinedNames(code) {
  if (typeof code !== "string" || !code) return new Set();
  return collectDefinedNames(stripCommentsAndStrings(code));
}

// ── helpers ──

function stripCommentsAndStrings(code) {
  let out = code.replace(/--\[\[[\s\S]*?\]\]/g, " ");
  out = out.replace(/--[^\n]*/g, "");
  out = out.replace(/"(?:[^"\\\n]|\\.)*"/g, '""');
  out = out.replace(/'(?:[^'\\\n]|\\.)*'/g, "''");
  out = out.replace(/\[\[[\s\S]*?\]\]/g, "[[]]");
  return out;
}

function collectDefinedNames(code) {
  const defined = new Set();

  // Function decls: `function NAME(` or `local function NAME(`. Method
  // / field decls `function ns.NAME(` and `function ns:NAME(` are
  // skipped — they don't pollute the global scope.
  const fnRe = /(?:^|[^.\w:])function\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(/g;
  let m;
  while ((m = fnRe.exec(code)) !== null) defined.add(m[1]);

  // Assignments: `NAME =`, `local NAME =`, `local NAME` (no init).
  // Match anywhere a word boundary precedes the identifier, so this
  // catches both line-start and inline forms (`local x = 1; y = 2`).
  // Reject `==` by requiring the next char isn't `=`.
  const assignRe = /(?:^|[\s,({;])(?:local\s+)?([a-zA-Z_][a-zA-Z0-9_]*)\s*=(?!=)/g;
  while ((m = assignRe.exec(code)) !== null) defined.add(m[1]);

  // Multi-name local: `local a, b, c = ...` — capture the trailing names.
  const multiRe = /\blocal\s+([a-zA-Z_][a-zA-Z0-9_]*(?:\s*,\s*[a-zA-Z_][a-zA-Z0-9_]*)+)/g;
  while ((m = multiRe.exec(code)) !== null) {
    for (const part of m[1].split(",")) defined.add(part.trim());
  }

  // For loops: `for NAME = ...`, `for NAME, NAME2 in ...`.
  const forRe = /\bfor\s+([a-zA-Z_][a-zA-Z0-9_]*(?:\s*,\s*[a-zA-Z_][a-zA-Z0-9_]*)*)\s+(?:=|in)\b/g;
  while ((m = forRe.exec(code)) !== null) {
    for (const part of m[1].split(",")) defined.add(part.trim());
  }

  // Function parameters: `function any(p1, p2, ...) ...`.
  const paramRe = /\bfunction\s*[a-zA-Z_0-9.:]*\(([^)]*)\)/g;
  while ((m = paramRe.exec(code)) !== null) {
    for (const param of m[1].split(",")) {
      const trimmed = param.trim().replace(/^\.\.\.$/, "");
      if (/^[a-zA-Z_]\w*$/.test(trimmed)) defined.add(trimmed);
    }
  }

  return defined;
}

function countNewlines(s, end) {
  let n = 0;
  for (let i = 0; i < end; i++) if (s.charCodeAt(i) === 10) n++;
  return n;
}
