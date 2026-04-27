#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const HEADER  = path.join(ROOT, "docs", "api-header.md");
const FOOTER  = path.join(ROOT, "docs", "api-footer.md");
const OUT     = path.join(ROOT, "docs", "API.md");
const SOURCES = [
  path.join(ROOT, "runtime", "engine.js"),
  path.join(ROOT, "runtime", "engine-bindings.js"),
];

function readText(p) {
  return fs.readFileSync(p, "utf8").replace(/\s+$/, "") + "\n";
}

function extractTags(jsdoc) {
  if (!jsdoc) return { sig: null, group: null, desc: null };
  // Strip /** */ and leading * on each line, then collapse to a single tag-stream.
  const inner = jsdoc
    .replace(/^\/\*\*/, "")
    .replace(/\*\/$/, "")
    .split(/\r?\n/)
    .map(line => line.replace(/^\s*\*\s?/, ""))
    .join("\n");
  // Tokenize tags. A tag starts at "@<word>" at line start and runs until the next "@<word>" at line start or EOF.
  const tags = {};
  const re = /^@(\w+)[ \t]*([^\n]*(?:\n(?!@)[^\n]*)*)/gm;
  let m;
  while ((m = re.exec(inner)) !== null) {
    const name = m[1];
    const value = m[2].replace(/\s+/g, " ").trim();
    if (!(name in tags)) tags[name] = value;
  }
  return {
    sig:   tags.lua   || null,
    group: tags.group || null,
    desc:  tags.desc  || null,
  };
}

// Parse one source file → array of { name, jsdoc | null }
function isPublic(api) {
  const n = api.name;
  if (n.startsWith("_")) return false;
  if (n === "SCREEN_W" || n === "SCREEN_H" || n === "COLORS") return false;
  // All-uppercase constant-style names without JSDoc are excluded.
  if (!api.sig && /^[A-Z][A-Z0-9_]+$/.test(n)) return false;
  return true;
}

function parseFile(src) {
  const text = fs.readFileSync(src, "utf8");
  const out = [];
  // Match `lua.global.set("name", ...)`. We capture the name and the byte offset.
  const reg = /lua\.global\.set\(\s*"([^"]+)"/g;
  let m;
  while ((m = reg.exec(text)) !== null) {
    const name = m[1];
    const at = m.index;
    // Walk backward from `at` to find the immediately preceding `/** ... */` block.
    // It's "preceding" if only whitespace separates it from the registration line.
    const prefix = text.slice(0, at);
    const closeIdx = prefix.lastIndexOf("*/");
    let jsdoc = null;
    if (closeIdx !== -1) {
      const between = prefix.slice(closeIdx + 2);
      if (/^\s*$/.test(between)) {
        const openIdx = prefix.lastIndexOf("/**", closeIdx);
        if (openIdx !== -1) {
          jsdoc = prefix.slice(openIdx, closeIdx + 2);
        }
      }
    }
    out.push({ name, ...extractTags(jsdoc) });
  }
  return out;
}

function parseAll() {
  const all = [];
  for (const src of SOURCES) all.push(...parseFile(src));
  return all;
}

function compose(body) {
  const header = readText(HEADER);
  const footer = readText(FOOTER);
  return `${header}\n${body}\n\n${footer}`;
}

function renderBody(apis) {
  // Bucket by @group. APIs with no JSDoc go to "Misc" too, but rendered as bare names.
  const groups = new Map();
  const ensure = (g) => {
    if (!groups.has(g)) groups.set(g, []);
    return groups.get(g);
  };
  for (const api of apis) {
    const g = api.group || "Misc";
    ensure(g).push(api);
  }
  // Always show Misc last; everything else alphabetical.
  const groupNames = [...groups.keys()].filter(g => g !== "Misc").sort();
  if (groups.has("Misc")) groupNames.push("Misc");

  const lines = [];
  for (const g of groupNames) {
    lines.push(`## ${g}`);
    lines.push("");
    const list = groups.get(g).slice().sort((a, b) => a.name.localeCompare(b.name));
    for (const api of list) {
      if (api.sig) {
        lines.push(`### ${api.sig}`);
        if (api.desc) lines.push(api.desc);
      } else {
        lines.push(`### ${api.name}`);
      }
      lines.push("");
    }
  }
  // Trim trailing blank line.
  while (lines.length && lines[lines.length - 1] === "") lines.pop();
  return lines.join("\n");
}

function main() {
  const apis = parseAll().filter(isPublic);
  const body = renderBody(apis);
  fs.writeFileSync(OUT, compose(body));
  console.log(`wrote ${path.relative(ROOT, OUT)} (${apis.length} APIs)`);
}

main();
