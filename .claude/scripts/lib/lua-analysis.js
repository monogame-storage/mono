// lua-analysis.js — Lua AST analysis for the mono-lint unknown-api rule.
//
// Parses a Lua file with `luaparse`, classifies every call site as either
// known (engine API / Lua stdlib / locally defined / required-module export)
// or unknown. require()'d modules are recursively analyzed so their exports
// participate in the check.

"use strict";

const fs = require("fs");
const path = require("path");
const luaparse = require("luaparse");

const STDLIB = require("./lua-stdlib.json");

// Stdlib top-level globals (assert, print, pairs, ...) are checked against
// STDLIB._G. Stdlib modules (math, string, ...) get their own member lookup.
const STDLIB_GLOBALS = new Set(STDLIB._G);
const STDLIB_MODULES = new Set(Object.keys(STDLIB).filter(k => k !== "_G"));

// Lifecycle hooks the engine calls into. Game code may legitimately call
// them again (e.g. `_init()` to restart). Whitelisted even when the file
// being linted doesn't declare them — they're either declared elsewhere or
// resolve to nil at runtime.
const LIFECYCLE_HOOKS = new Set(["_init", "_start", "_ready", "_update", "_draw"]);

// Lua version to feed luaparse. Mono runs Lua 5.4 via Wasmoon; 5.3 is the
// closest version luaparse fully supports (covers `goto`/`::label::`,
// integer division, bitwise ops).
const LUA_VERSION = "5.3";

/** Decode a luaparse StringLiteral. luaparse leaves `value` null by default
 * and stores the source-form (with surrounding quotes) on `raw`. We strip
 * the outer quote pair — sufficient for our uses (require paths, table
 * keys), no escape-sequence handling needed because Mono module paths
 * don't use them. */
function stringLitValue(node) {
  if (!node || node.type !== "StringLiteral") return null;
  if (node.value !== null && node.value !== undefined) return node.value;
  if (typeof node.raw !== "string" || node.raw.length < 2) return null;
  return node.raw.slice(1, -1);
}

/** Walk every node in a luaparse AST, depth-first. */
function walk(node, cb) {
  if (!node || typeof node !== "object") return;
  cb(node);
  for (const key of Object.keys(node)) {
    if (key === "loc" || key === "range") continue;
    const val = node[key];
    if (!val || typeof val !== "object") continue;
    if (Array.isArray(val)) {
      for (const v of val) if (v && typeof v === "object" && v.type) walk(v, cb);
    } else if (val.type) {
      walk(val, cb);
    }
  }
}

/**
 * Collect symbols defined in a parsed AST.
 * Returns:
 *   locals          — Set of names declared via `local`
 *   globals         — Set of names declared via top-level assignment / `function name()`
 *   tableModules    — Map<varName, Set<member>> for `local M = {}; function M.x() end` patterns
 *   requireBindings — Map<varName, modulePath> for `local foo = require("path")`
 *   returnedTable   — varName the chunk returns (e.g. `return scene`), or null
 *   returnedTableLiteral — Set<member> if the chunk returns a literal table, else null
 */
function collectSymbols(ast) {
  const locals = new Set();
  const globals = new Set();
  const tableModules = new Map();
  const requireBindings = new Map();
  let returnedTable = null;
  let returnedTableLiteral = null;

  walk(ast, (node) => {
    switch (node.type) {
      case "LocalStatement": {
        for (let i = 0; i < node.variables.length; i++) {
          const v = node.variables[i];
          const init = node.init[i];
          if (v.type !== "Identifier") continue;
          locals.add(v.name);
          if (!init) continue;
          if (init.type === "CallExpression"
              && init.base.type === "Identifier"
              && init.base.name === "require"
              && init.arguments.length === 1
              && init.arguments[0].type === "StringLiteral") {
            const modPath = stringLitValue(init.arguments[0]);
            if (modPath) requireBindings.set(v.name, modPath);
          } else if (init.type === "TableConstructorExpression") {
            const exports = new Set();
            for (const field of init.fields) {
              const key = fieldKeyName(field);
              if (key) exports.add(key);
            }
            tableModules.set(v.name, exports);
          }
        }
        break;
      }
      case "FunctionDeclaration": {
        const id = node.identifier;
        if (!id) break;
        if (id.type === "Identifier") {
          if (node.isLocal) locals.add(id.name);
          else globals.add(id.name);
        } else if (id.type === "MemberExpression"
                && id.base.type === "Identifier") {
          const mod = tableModules.get(id.base.name);
          if (mod) mod.add(id.identifier.name);
        }
        break;
      }
      case "AssignmentStatement": {
        for (const v of node.variables) {
          if (v.type === "Identifier") {
            if (!locals.has(v.name)) globals.add(v.name);
          } else if (v.type === "MemberExpression"
                  && v.base.type === "Identifier") {
            const mod = tableModules.get(v.base.name);
            if (mod) mod.add(v.identifier.name);
          }
        }
        break;
      }
    }
  });

  // Find chunk-level return (last top-level statement).
  for (const stmt of ast.body) {
    if (stmt.type === "ReturnStatement" && stmt.arguments.length > 0) {
      const ret = stmt.arguments[0];
      if (ret.type === "Identifier") returnedTable = ret.name;
      else if (ret.type === "TableConstructorExpression") {
        returnedTableLiteral = new Set();
        for (const field of ret.fields) {
          const key = fieldKeyName(field);
          if (key) returnedTableLiteral.add(key);
        }
      }
    }
  }

  return { locals, globals, tableModules, requireBindings, returnedTable, returnedTableLiteral };
}

/** Return the string key of a TableConstructor field, or null. */
function fieldKeyName(field) {
  if (field.type === "TableKeyString" && field.key?.type === "Identifier") {
    return field.key.name;
  }
  if (field.type === "TableKey" && field.key?.type === "StringLiteral") {
    return stringLitValue(field.key);
  }
  return null;
}

/**
 * Resolve a Lua module path to an absolute filesystem path. Mono follows
 * Lua's dot-to-slash convention: `require("lib.utils")` → `lib/utils.lua`,
 * relative to the directory of the file doing the require.
 */
function resolveRequire(modPath, baseDir) {
  const rel = modPath.replace(/\./g, "/") + ".lua";
  const candidates = [
    path.join(baseDir, rel),
    path.join(baseDir, rel.replace(/\.lua$/, "/init.lua")),
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) return c;
  }
  return null;
}

/**
 * Recursively analyze a Lua module file and return the set of exported
 * names. Cache prevents infinite recursion on cycles. Files that fail to
 * parse or whose return shape is opaque map to null (caller treats as
 * "exports unknown — allow any member access").
 */
function moduleExports(filepath, cache) {
  if (cache.has(filepath)) return cache.get(filepath);
  cache.set(filepath, null); // placeholder to break cycles
  let ast;
  try {
    const src = fs.readFileSync(filepath, "utf8");
    ast = luaparse.parse(src, { locations: false, comments: false, luaVersion: LUA_VERSION });
  } catch {
    return null;
  }
  const sym = collectSymbols(ast);
  let exports = null;
  if (sym.returnedTable && sym.tableModules.has(sym.returnedTable)) {
    exports = sym.tableModules.get(sym.returnedTable);
  } else if (sym.returnedTableLiteral) {
    exports = sym.returnedTableLiteral;
  }
  cache.set(filepath, exports);
  return exports;
}

/**
 * Analyze a single Lua file and report unknown call sites against the given
 * set of engine APIs.
 *
 * @param {string} filepath — absolute path to the Lua file
 * @param {Set<string>} engineAPIs — names from docs/API.md
 * @param {Map} [moduleCache] — pass a shared Map across files to dedupe work
 * @returns {Array<{ line: number, name: string, kind: string }>}
 */
function findUnknownCalls(filepath, engineAPIs, moduleCache) {
  const cache = moduleCache || new Map();
  const src = fs.readFileSync(filepath, "utf8");
  let ast;
  try {
    ast = luaparse.parse(src, { locations: true, comments: false, luaVersion: LUA_VERSION });
  } catch (e) {
    return [{ line: e.line || 0, name: "<parse error>", kind: "parse-error", msg: e.message }];
  }
  const sym = collectSymbols(ast);
  const baseDir = path.dirname(filepath);

  // Resolve required modules' exports up front.
  const requireExports = new Map(); // varName → Set<string> | null
  for (const [varName, modPath] of sym.requireBindings) {
    const resolved = resolveRequire(modPath, baseDir);
    if (!resolved) {
      requireExports.set(varName, null); // unresolved: allow anything
      continue;
    }
    requireExports.set(varName, moduleExports(resolved, cache));
  }

  const findings = [];
  walk(ast, (node) => {
    if (node.type !== "CallExpression"
     && node.type !== "StringCallExpression"
     && node.type !== "TableCallExpression") return;
    const base = node.base;
    if (!base) return;
    const line = node.loc?.start?.line || 0;

    if (base.type === "Identifier") {
      const name = base.name;
      if (sym.locals.has(name)) return;
      if (sym.globals.has(name)) return;
      if (engineAPIs.has(name)) return;
      if (STDLIB_GLOBALS.has(name)) return;
      if (LIFECYCLE_HOOKS.has(name)) return;
      findings.push({ line, name: `${name}()`, kind: "unknown-call" });
      return;
    }

    if (base.type === "MemberExpression" && base.indexer === ".") {
      const modBase = base.base;
      if (modBase.type !== "Identifier") return; // chained / complex base — skip
      const mod = modBase.name;
      const fn = base.identifier.name;

      // require()-bound local: check against the module's exported names.
      // Checked BEFORE the locals/globals fallback so a typo'd member call
      // on a required module isn't silently allowed by virtue of being a
      // local binding.
      if (requireExports.has(mod)) {
        const exports = requireExports.get(mod);
        if (exports && !exports.has(fn)) {
          findings.push({ line, name: `${mod}.${fn}()`, kind: "unknown-require-member" });
        }
        return;
      }

      // Locally-built module table (`local M = {}; function M.x() end`).
      if (sym.tableModules.has(mod)) {
        if (!sym.tableModules.get(mod).has(fn)) {
          findings.push({ line, name: `${mod}.${fn}()`, kind: "unknown-member" });
        }
        return;
      }

      // Other user-declared local/global: trust it (full type tracking
      // would be needed to verify members on arbitrary values).
      if (sym.locals.has(mod) || sym.globals.has(mod)) return;

      if (STDLIB_MODULES.has(mod)) {
        if (!STDLIB[mod].includes(fn)) {
          findings.push({ line, name: `${mod}.${fn}()`, kind: "unknown-stdlib-member" });
        }
        return;
      }

      findings.push({ line, name: `${mod}.${fn}()`, kind: "unknown-module" });
    }
    // base.type === "MemberExpression" with indexer ":" → method call.
    // Skip: instance scope, would need full type tracking to verify.
  });

  return findings;
}

module.exports = {
  collectSymbols,
  moduleExports,
  resolveRequire,
  findUnknownCalls,
  STDLIB,
};
