#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const HEADER = path.join(ROOT, "docs", "api-header.md");
const FOOTER = path.join(ROOT, "docs", "api-footer.md");
const OUT    = path.join(ROOT, "docs", "API.md");

function readText(p) {
  return fs.readFileSync(p, "utf8").replace(/\s+$/, "") + "\n";
}

function compose(body) {
  const header = readText(HEADER);
  const footer = readText(FOOTER);
  return `${header}\n${body}\n${footer}`;
}

function main() {
  const body = "<!-- generated body goes here -->";
  const out = compose(body);
  fs.writeFileSync(OUT, out);
  console.log(`wrote ${path.relative(ROOT, OUT)}`);
}

main();
