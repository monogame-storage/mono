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

// Parse one source file → array of { name, jsdoc | null }
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
    out.push({ name, jsdoc });
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
  return `${header}\n${body}\n${footer}`;
}

function main() {
  const apis = parseAll();
  // Debug dump for now.
  console.error(`parsed ${apis.length} registrations`);
  for (const a of apis) {
    console.error(`  ${a.name}${a.jsdoc ? "  [jsdoc]" : ""}`);
  }
  const body = "<!-- generated body goes here -->";
  fs.writeFileSync(OUT, compose(body));
}

main();
