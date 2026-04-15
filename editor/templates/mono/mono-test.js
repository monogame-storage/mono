#!/usr/bin/env node
/**
 * mono-test.js — Headless CLI Test Runner for Mono Engine
 *
 * Runs Lua game code in Node.js without a browser.
 * Uses Wasmoon for Lua 5.4, replicates engine.js drawing core.
 * Outputs vdump (VRAM hex text) for LLM verification.
 *
 * Usage:
 *   node mono-test.js <main.lua> [options]
 *
 * Options:
 *   --frames N       Run N frames (default: 0 = init+start only)
 *   --colors N       Color depth: 1, 2, or 4 (default: 1)
 *   --vdump          Print full vdump after execution
 *   --vrow Y         Print specific row Y (0-143)
 *   --suite          Test suite mode: parse PASS/FAIL output, exit code
 *   --input "F:K"    Inject input at frame F key K (e.g., "3:a,5:up")
 *   --touch "F:A:X,Y" Inject touch events inline or from file
 *                     Inline: "5:start:80,60;7:end:80,60"
 *                     File:   touch-events.txt (one event per line, # comments)
 *   --snapshot FILE  Save vdump to file
 *   --diff FILE      Compare vdump against expected file
 *   --replay FILE    Load input sequence from file and replay
 *   --record FILE    Record input sequence to file during run
 *   --determinism N  Run N times with same seed, verify identical VRAM
 *   --coverage       Report which engine APIs were called (and how often)
 *   --trace FILE     Write per-frame gameplay trace (JSONL) for AI analysis
 *   --golden FILE    Record/check hash snapshots at key frames (regression)
 *   --golden-update  Update the golden file with current hashes
 *   --bench          Measure per-frame time (avg/p50/p95/p99/max) + heap
 *   --fuzz N         Run N times with random inputs, report crash rate
 *   --scan DIR       Run every main.lua found in DIR/**, report pass/fail
 *   --quiet          Suppress frame-by-frame logs
 *   --console        Print Lua print() output (default: true in suite mode)
 *   --png FILE       Save screen as PNG image
 *   --region X,Y,W,H Crop vdump to region (e.g., "0,0,40,20")
 *   --until "TEXT"   Stop when Lua prints matching text (e.g., "WINS")
 *   --runs N         Run N times, report stats (use with --until)
 *   --seed N         Set math.randomseed for reproducible runs
 */

const fs = require("fs");
const path = require("path");

// --- Parse arguments ---
const args = process.argv.slice(2);
if (args.length === 0 || args[0] === "--help" || args[0] === "-h") {
  console.log(`Usage: node mono-test.js <main.lua> [options]

Options:
  --frames N       Run N frames (default: 0)
  --colors N       Color depth: 1, 2, or 4 (default: 1)
  --vdump          Print full vdump after execution
  --vrow Y         Print specific row(s), comma-separated
  --suite          Test suite mode (parse PASS/FAIL)
  --input "F:K"    Inject input (e.g., "3:a,5:up")
  --touch "F:A:X,Y" Inject touch inline or from file
  --snapshot FILE  Save vdump to file
  --diff FILE      Compare vdump against expected file
  --replay FILE    Load input sequence from file and replay
  --record FILE    Record input sequence to file during run
  --determinism N  Run N times with same seed, verify identical VRAM
  --coverage       Report which engine APIs were called
  --trace FILE     Write per-frame gameplay trace (JSONL)
  --golden FILE    Record/check hash snapshots at key frames
  --golden-update  Update golden file with current hashes
  --bench          Measure per-frame time + heap usage
  --fuzz N         Run N times with random inputs, report crash rate
  --scan DIR       Run every main.lua in DIR/** and report pass/fail
  --quiet          Suppress frame logs
  --console        Print Lua print() output
  --png FILE       Save screen as PNG
  --region X,Y,W,H Crop output to region
  --until "TEXT"   Stop when Lua prints matching text
  --runs N         Run N times, report stats (with --until)
  --seed N         Set random seed for reproducibility`);
  process.exit(0);
}

function getOpt(name, defaultVal) {
  const idx = args.indexOf("--" + name);
  if (idx === -1) return defaultVal;
  if (idx + 1 < args.length && !args[idx + 1].startsWith("--")) return args[idx + 1];
  return true;
}
const hasFlag = (name) => args.includes("--" + name);

const inlineSource = getOpt("source", null);
// First non-flag argument is the lua file (skip if --source is used)
const luaFile = (() => {
  if (inlineSource) return null;
  for (const a of args) {
    if (!a.startsWith("--")) return a;
  }
  return null;
})();

const frameCount = parseInt(getOpt("frames", "0")) || 0;
const colorBits = parseInt(getOpt("colors", "1")) || 1;
const doVdump = hasFlag("vdump");
const vrowArg = getOpt("vrow", null);
const suiteMode = hasFlag("suite");
const inputArg = getOpt("input", null);
const snapshotFile = getOpt("snapshot", null);
const diffFile = getOpt("diff", null);
const quiet = hasFlag("quiet");
const showConsole = hasFlag("console") || suiteMode;
const pngFile = getOpt("png", null);
const regionArg = getOpt("region", null);
const untilText = getOpt("until", null);
const totalRuns = parseInt(getOpt("runs", "1")) || 1;
const seedArg = getOpt("seed", null);
const touchArg = getOpt("touch", null);
const replayFile = getOpt("replay", null);
const recordFile = getOpt("record", null);
const determinismRuns = parseInt(getOpt("determinism", "0")) || 0;
// --coverage-json is an internal flag used by --scan --coverage to collect
// machine-readable coverage output from each child process.
const coverageAggregate = hasFlag("coverage-json");
const coverageMode = hasFlag("coverage") || coverageAggregate;
const traceFile = getOpt("trace", null);
const goldenFile = getOpt("golden", null);
const goldenUpdate = hasFlag("golden-update");
const benchMode = hasFlag("bench");
const fuzzRuns = parseInt(getOpt("fuzz", "0")) || 0;
const scanDir = getOpt("scan", null);
let runSeed = null;

// --- Engine core (replicated from engine.js, no DOM) ---
const W = 160, H = 120;

function buildPalette(bits) {
  const n = 1 << bits;
  const colors = new Uint32Array(n);
  for (let i = 0; i < n; i++) {
    const v = Math.round((i / (n - 1)) * 255);
    colors[i] = (255 << 24) | (v << 16) | (v << 8) | v;
  }
  return colors;
}

let palette = buildPalette(colorBits);
let camX = 0, camY = 0;
let debugMode = false;
let debugShapes = [];

// --- Surfaces ---
let surfaces = [];
const colorBuf = new Uint8Array(W * H);
const buf32 = new Uint32Array(W * H);
surfaces[0] = { w: W, h: H, buf32, colorBuf };

function getSurf(id) { return surfaces[id]; }
function requireSurf(name, id) {
  const s = surfaces[id];
  if (!s) throw new Error(name + "(): first arg must be a valid surface id (got " + id + "). Did you forget screen()?");
  return s;
}
function requireColor(name, c) {
  if (c === undefined || c === null) throw new Error(name + "(): color is undefined, expected number (0-" + (palette.length - 1) + ")");
  if (typeof c !== "number") throw new Error(name + "(): color must be a number, got " + typeof c);
  if (c !== Math.floor(c)) throw new Error(name + "(): color must be an integer, got " + c);
  if (c < 0 || c >= palette.length) throw new Error(name + "(): color " + c + " out of range (0-" + (palette.length - 1) + ")");
}

// Images
let images = [];
let imageIdCounter = 0;

// Font (4x7 bitmap) — copied from engine.js
const FONT_W = 4, FONT_H = 7;
const FONT = {};
const fontData = {
  "A":"0110100110011111100110011001","B":"1110100110101110100110011110",
  "C":"0110100110001000100001100110","D":"1100101010011001100110101100",
  "E":"1111100010001110100010001111","F":"1111100010001110100010001000",
  "G":"0111100010001011100101100111","H":"1001100110011111100110011001",
  "I":"1110010001000100010001001110","J":"0111001000100010001010100100",
  "K":"1001101011001100101010011001","L":"1000100010001000100010001111",
  "M":"1001111111011001100110011001","N":"1001110111011001100110011001",
  "O":"0110100110011001100110010110","P":"1110100110011110100010001000",
  "Q":"0110100110011001101101100001","R":"1110100110011110101010011001",
  "S":"0111100010000110000110001110","T":"1111001000100010001000100010",
  "U":"1001100110011001100110010110","V":"1001100110011001100101100110",
  "W":"1001100110011001101111011001","X":"1001100101100110011010011001",
  "Y":"1001100101100010001000100010","Z":"1111000100100100100010001111",
  "0":"0110100111011011101110010110","1":"0100110001000100010001001110",
  "2":"0110100100010010010010001111","3":"1110000100010110000110011110",
  "4":"1001100110011111000100010001","5":"1111100010001110000100011110",
  "6":"0110100010001110100110010110","7":"1111000100010010010001001000",
  "8":"0110100110010110100110010110","9":"0110100110010111000100010110",
  " ":"0000000000000000000000000000",
  ".":"0000000000000000000001000100",
  ",":"0000000000000000001000101000",
  "!":"0100010001000100000000000100",
  "?":"0110100100010010000000000010",
  "-":"0000000000001110000000000000",
  "+":"0000001001001110010000100000",
  ":":"0000010001000000010001000000",
  "/":"0001000100100010010010001000",
  "*":"0000101001001110010010100000",
  "#":"0101111101011111010100000000",
  "(":"0010010010001000010001000010",
  ")":"0100001000010001000100100100",
  "=":"0000000011110000111100000000",
  "'":"0100010010000000000000000000",
  "\"":"1010101000000000000000000000",
  "<":"0010010010001000010000100010",
  ">":"1000010000100001001001001000",
  "_":"0000000000000000000000001111",
};
for (const [ch, bits] of Object.entries(fontData)) {
  FONT[ch] = new Uint8Array(FONT_W * FONT_H);
  for (let i = 0; i < bits.length; i++) FONT[ch][i] = bits[i] === "1" ? 1 : 0;
}

// --- Drawing functions (match engine.js — first arg is surface) ---
function setPix(s, x, y, c) {
  x = Math.floor(x); y = Math.floor(y);
  if (x >= 0 && x < s.w && y >= 0 && y < s.h) {
    const idx = y * s.w + x;
    s.buf32[idx] = palette[c] || palette[0];
    s.colorBuf[idx] = c;
  }
}

function getPix(s, x, y) {
  x = Math.floor(x); y = Math.floor(y);
  if (x >= 0 && x < s.w && y >= 0 && y < s.h) return s.colorBuf[y * s.w + x];
  return 0;
}

function cls(s, c) {
  const col = palette[c] || palette[0];
  s.buf32.fill(col);
  s.colorBuf.fill(c || 0);
  debugShapes = [];
}

function line(s, x0, y0, x1, y1, c) {
  x0 = Math.floor(x0) - camX; y0 = Math.floor(y0) - camY;
  x1 = Math.floor(x1) - camX; y1 = Math.floor(y1) - camY;
  let dx = Math.abs(x1 - x0), dy = Math.abs(y1 - y0);
  let sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
  let err = dx - dy;
  while (true) {
    setPix(s, x0, y0, c);
    if (x0 === x1 && y0 === y1) break;
    let e2 = 2 * err;
    if (e2 > -dy) { err -= dy; x0 += sx; }
    if (e2 < dx) { err += dx; y0 += sy; }
  }
}

function rect(s, x, y, w, h, c) {
  x = Math.floor(x) - camX; y = Math.floor(y) - camY;
  w = Math.floor(w); h = Math.floor(h);
  for (let i = 0; i < w; i++) { setPix(s, x + i, y, c); setPix(s, x + i, y + h - 1, c); }
  for (let i = 0; i < h; i++) { setPix(s, x, y + i, c); setPix(s, x + w - 1, y + i, c); }
  if (debugMode) debugShapes.push({ x, y, w, h });
}

function rectf(s, x, y, w, h, c) {
  x = Math.floor(x) - camX; y = Math.floor(y) - camY;
  w = Math.floor(w); h = Math.floor(h);
  for (let py = y; py < y + h; py++)
    for (let px = x; px < x + w; px++)
      setPix(s, px, py, c);
  if (debugMode) debugShapes.push({ x, y, w, h });
}

function circ(s, cx, cy, r, c) {
  cx = Math.floor(cx) - camX; cy = Math.floor(cy) - camY; r = Math.floor(r);
  let x = r, y = 0, d = 1 - r;
  while (x >= y) {
    setPix(s, cx + x, cy + y, c); setPix(s, cx - x, cy + y, c);
    setPix(s, cx + x, cy - y, c); setPix(s, cx - x, cy - y, c);
    setPix(s, cx + y, cy + x, c); setPix(s, cx - y, cy + x, c);
    setPix(s, cx + y, cy - x, c); setPix(s, cx - y, cy - x, c);
    y++;
    if (d < 0) { d += 2 * y + 1; }
    else { x--; d += 2 * (y - x) + 1; }
  }
}

function circf(s, cx, cy, r, c) {
  cx = Math.floor(cx) - camX; cy = Math.floor(cy) - camY; r = Math.floor(r);
  let x = r, y = 0, d = 1 - r;
  while (x >= y) {
    for (let i = cx - x; i <= cx + x; i++) { setPix(s, i, cy + y, c); setPix(s, i, cy - y, c); }
    for (let i = cx - y; i <= cx + y; i++) { setPix(s, i, cy + x, c); setPix(s, i, cy - x, c); }
    y++;
    if (d < 0) { d += 2 * y + 1; }
    else { x--; d += 2 * (y - x) + 1; }
  }
}

const ALIGN_LEFT = 0, ALIGN_HCENTER = 1, ALIGN_RIGHT = 2, ALIGN_VCENTER = 4, ALIGN_CENTER = 5;

function drawText(s, str, x, y, c, align) {
  str = String(str).toUpperCase();
  align = align || 0;
  const textW = str.length * (FONT_W + 1) - 1;
  if (align & ALIGN_HCENTER) x = x - textW / 2;
  else if (align & ALIGN_RIGHT) x = x - textW;
  if (align & ALIGN_VCENTER) y = y - FONT_H / 2;
  let cx = Math.floor(x);
  const cy = Math.floor(y);
  for (const ch of str) {
    const glyph = FONT[ch];
    if (glyph) {
      for (let py = 0; py < FONT_H; py++)
        for (let px = 0; px < FONT_W; px++)
          if (glyph[py * FONT_W + px]) setPix(s, cx + px, cy + py, c);
    }
    cx += FONT_W + 1;
  }
}

function camFn(x, y) { camX = x || 0; camY = y || 0; }

// --- Surface management ---
function screenFn() { return 0; }

function canvasFn(w, h) {
  w = Math.floor(w); h = Math.floor(h);
  if (w < 1 || h < 1 || w > 1024 || h > 1024) return false;
  const cb = new Uint8Array(w * h);
  const b32 = new Uint32Array(w * h);
  const col = palette[0] || 0xFF000000;
  b32.fill(col);
  const id = surfaces.length;
  surfaces.push({ w, h, buf32: b32, colorBuf: cb });
  return id;
}

function canvasDel(id) {
  if (id <= 0 || id >= surfaces.length) return;
  surfaces[id] = null;
}

function canvasW(id) {
  const s = surfaces[id]; return s ? s.w : 0;
}

function canvasH(id) {
  const s = surfaces[id]; return s ? s.h : 0;
}

function blitFn(srcId, dstId, dx, dy, dw, dh, sx, sy, sw, sh) {
  const src = requireSurf("blit", srcId);
  const dst = requireSurf("blit", dstId);
  sx = sx || 0; sy = sy || 0;
  sw = sw || src.w; sh = sh || src.h;
  dw = dw || sw; dh = dh || sh;
  dx = Math.floor(dx) - camX; dy = Math.floor(dy) - camY;
  for (let py = 0; py < dh; py++) {
    const destY = dy + py;
    if (destY < 0 || destY >= dst.h) continue;
    const srcY = Math.floor(py * sh / dh) + sy;
    if (srcY < 0 || srcY >= src.h) continue;
    for (let px = 0; px < dw; px++) {
      const destX = dx + px;
      if (destX < 0 || destX >= dst.w) continue;
      const srcX = Math.floor(px * sw / dw) + sx;
      if (srcX < 0 || srcX >= src.w) continue;
      const c = src.colorBuf[srcY * src.w + srcX];
      if (c === 255) continue;
      const idx = destY * dst.w + destX;
      dst.colorBuf[idx] = c;
      dst.buf32[idx] = palette[c];
    }
  }
}

// --- VRAM dump (always reads screen = surfaces[0]) ---
function vrow(y) {
  const scr = surfaces[0];
  y = Math.floor(y);
  if (!scr || y < 0 || y >= H) return "";
  let s = "";
  const off = y * W;
  for (let x = 0; x < W; x++) s += scr.colorBuf[off + x].toString(16);
  return s;
}

function vdump() {
  const rows = [];
  for (let y = 0; y < H; y++) rows.push(vrow(y));
  return rows.join("\n");
}

// FNV-1a 32-bit hash of current VRAM — for determinism checks
function vramHash() {
  const buf = surfaces[0].colorBuf;
  let hash = 0x811c9dc5;
  for (let i = 0; i < buf.length; i++) {
    hash ^= buf[i];
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(16).padStart(8, "0");
}

// --- Golden snapshots ---
// File format (one per line):
//   # mono golden snapshots
//   # seed=42 colors=1
//   30 1b2ae874
//   60 65a4c22a
//   120 04718784
const goldenTargets = {};  // { frame: expectedHash }
const goldenCaptured = {}; // { frame: actualHash } — filled during run
if (goldenFile && !goldenUpdate && fs.existsSync(goldenFile)) {
  const lines = fs.readFileSync(goldenFile, "utf8").split("\n");
  for (const raw of lines) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    const parts = line.split(/\s+/);
    const frame = parseInt(parts[0]);
    const hash = parts[1];
    if (!isNaN(frame) && hash) goldenTargets[frame] = hash;
  }
}

// Image quantization (no DOM needed)
function quantizeRGBA(rgba, w, h, pal) {
  const out = new Uint8Array(w * h);
  const palGray = [];
  for (let i = 0; i < pal.length; i++) palGray[i] = pal[i] & 0xFF;
  const n = pal.length;
  for (let i = 0; i < w * h; i++) {
    const ri = i * 4;
    if (rgba[ri + 3] < 128) { out[i] = 255; continue; }
    const lum = Math.round(0.299 * rgba[ri] + 0.587 * rgba[ri + 1] + 0.114 * rgba[ri + 2]);
    let best = 0, bestD = 999;
    for (let j = 0; j < n; j++) {
      const d = Math.abs(lum - palGray[j]);
      if (d < bestD) { bestD = d; best = j; }
    }
    out[i] = best;
  }
  return out;
}

function drawImageFn(s, id, x, y) {
  const img = images[id];
  if (!img) return;
  x = Math.floor(x) - camX; y = Math.floor(y) - camY;
  for (let py = 0; py < img.h; py++) {
    const sy = y + py;
    if (sy < 0 || sy >= s.h) continue;
    for (let px = 0; px < img.w; px++) {
      const sx = x + px;
      if (sx < 0 || sx >= s.w) continue;
      const c = img.data[py * img.w + px];
      if (c === 255) continue;
      const idx = sy * s.w + sx;
      s.colorBuf[idx] = c;
      s.buf32[idx] = palette[c];
    }
  }
}

function drawImageRegionFn(s, id, sx, sy, sw, sh, dx, dy) {
  const img = images[id];
  if (!img) return;
  dx = Math.floor(dx) - camX; dy = Math.floor(dy) - camY;
  sx = Math.floor(sx); sy = Math.floor(sy);
  sw = Math.floor(sw); sh = Math.floor(sh);
  if (sx < 0) { sw += sx; dx -= sx; sx = 0; }
  if (sy < 0) { sh += sy; dy -= sy; sy = 0; }
  if (sx + sw > img.w) sw = img.w - sx;
  if (sy + sh > img.h) sh = img.h - sy;
  for (let py = 0; py < sh; py++) {
    const screenY = dy + py;
    if (screenY < 0 || screenY >= s.h) continue;
    for (let px = 0; px < sw; px++) {
      const screenX = dx + px;
      if (screenX < 0 || screenX >= s.w) continue;
      const c = img.data[(sy + py) * img.w + (sx + px)];
      if (c === 255) continue;
      const idx = screenY * s.w + screenX;
      s.colorBuf[idx] = c;
      s.buf32[idx] = palette[c];
    }
  }
}

// --- Input simulation ---
const keys = {};
const keysPrev = {};
const inputSchedule = {};

if (inputArg) {
  // Parse "3:a,5:up,10:left" → { 3: ["a"], 5: ["up"], 10: ["left"] }
  for (const part of inputArg.split(",")) {
    const [f, k] = part.trim().split(":");
    const frame = parseInt(f);
    if (!inputSchedule[frame]) inputSchedule[frame] = [];
    inputSchedule[frame].push(k.trim());
  }
}

// --- Replay: load input sequence from file ---
// Format:
//   # mono replay v1
//   # seed=42 colors=1
//   0
//   1
//   2 right
//   3 right a
let replaySeed = null;
let replayColors = null;
if (replayFile) {
  if (!fs.existsSync(replayFile)) {
    console.error(`Replay file not found: ${replayFile}`);
    process.exit(1);
  }
  const lines = fs.readFileSync(replayFile, "utf8").split("\n");
  for (const raw of lines) {
    const line = raw.trim();
    if (!line) continue;
    if (line.startsWith("#")) {
      // Parse metadata from comments
      const seedMatch = line.match(/seed=(\d+)/);
      if (seedMatch) replaySeed = parseInt(seedMatch[1]);
      const colorsMatch = line.match(/colors=(\d+)/);
      if (colorsMatch) replayColors = parseInt(colorsMatch[1]);
      continue;
    }
    // frame followed by keys: "2 right a"
    const parts = line.split(/\s+/);
    const frame = parseInt(parts[0]);
    if (isNaN(frame)) continue;
    const frameKeys = parts.slice(1).filter(k => k.length > 0);
    if (frameKeys.length > 0) {
      if (!inputSchedule[frame]) inputSchedule[frame] = [];
      for (const k of frameKeys) inputSchedule[frame].push(k);
    }
  }
  if (replaySeed !== null && seedArg === null) {
    runSeed = replaySeed;
  }
}

// --- Record: capture input sequence during run ---
const recordedFrames = [];  // [{ frame, keys: [...] }]

function recordInput(f) {
  if (!recordFile) return;
  const activeKeys = Object.keys(keys).filter(k => keys[k]);
  if (activeKeys.length > 0) {
    recordedFrames.push({ frame: f, keys: activeKeys });
  }
}

function inputUpdate() {
  for (const k in keys) keysPrev[k] = keys[k];
}

function applyInput(frame) {
  // Reset all keys each frame, then apply scheduled
  for (const k in keys) keys[k] = false;
  if (inputSchedule[frame]) {
    for (const k of inputSchedule[frame]) keys[k] = true;
  }
}

function saveRecording(filePath, totalFrames) {
  const lines = [];
  lines.push("# mono replay v1");
  const seed = runSeed !== null ? runSeed : (seedArg !== null ? parseInt(seedArg) : 0);
  lines.push(`# seed=${seed} colors=${colorBits} frames=${totalFrames}`);
  for (const entry of recordedFrames) {
    lines.push(`${entry.frame} ${entry.keys.join(" ")}`);
  }
  fs.writeFileSync(filePath, lines.join("\n") + "\n");
}

// --- Touch simulation ---
const touches = [];              // [{ id, x, y, fx, fy }]
let touchStartedFlag = false;
let touchEndedFlag = false;
let touchStarted = false;
let touchEnded = false;
const touchSchedule = {};        // { frame: [{ id, action, x, y }] }

if (touchArg) {
  // Support both inline and file-based touch input
  let touchRaw = touchArg;
  if (fs.existsSync(touchArg)) {
    touchRaw = fs.readFileSync(touchArg, "utf8");
  }
  // Split by semicolons or newlines
  for (const part of touchRaw.split(/[;\n]/)) {
    const trimmed = part.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const segs = trimmed.split(":");
    let frame, id, action, coords;
    if (segs.length === 3) {
      frame = parseInt(segs[0]);
      id = 1;
      action = segs[1].trim();
      coords = segs[2].trim();
    } else if (segs.length === 4) {
      frame = parseInt(segs[0]);
      id = parseInt(segs[1]);
      action = segs[2].trim();
      coords = segs[3].trim();
    } else {
      console.error(`Invalid touch format: "${trimmed}"`);
      process.exit(1);
    }
    if (action !== "start" && action !== "move" && action !== "end") {
      console.error(`Invalid touch action "${action}" (expected start/move/end): "${trimmed}"`);
      process.exit(1);
    }
    const [cx, cy] = coords.split(",").map(s => parseFloat(s.trim()));
    if (!touchSchedule[frame]) touchSchedule[frame] = [];
    touchSchedule[frame].push({ id, action, x: cx, y: cy });
  }
}

function applyTouch(frame) {
  if (!touchSchedule[frame]) return;
  for (const evt of touchSchedule[frame]) {
    const fx = evt.x;
    const fy = evt.y;
    const x = Math.floor(fx);
    const y = Math.floor(fy);
    if (evt.action === "start") {
      const existIdx = touches.findIndex(t => t.id === evt.id);
      if (existIdx !== -1) touches.splice(existIdx, 1);
      touches.push({ id: evt.id, x, y, fx, fy });
      touchStartedFlag = true;
    } else if (evt.action === "move") {
      const idx = touches.findIndex(t => t.id === evt.id);
      if (idx !== -1) touches[idx] = { id: evt.id, x, y, fx, fy };
    } else if (evt.action === "end") {
      const idx = touches.findIndex(t => t.id === evt.id);
      if (idx !== -1) touches.splice(idx, 1);
      touchEndedFlag = true;
    }
  }
}

function touchUpdate() {
  touchStarted = touchStartedFlag;
  touchEnded = touchEndedFlag;
  touchStartedFlag = false;
  touchEndedFlag = false;
}

// --- Main execution ---
async function main() {
  // Resolve lua source
  let gameSrc, gameDir;
  if (inlineSource) {
    gameSrc = inlineSource;
    gameDir = process.cwd();
  } else if (luaFile) {
    const luaPath = path.resolve(luaFile);
    if (!fs.existsSync(luaPath)) {
      console.error(`Error: file not found: ${luaPath}`);
      process.exit(1);
    }
    gameSrc = fs.readFileSync(luaPath, "utf8");
    gameDir = path.dirname(luaPath);
  } else {
    console.error("Error: provide a .lua file or --source 'code'");
    process.exit(1);
  }

  // Load Wasmoon
  const { LuaFactory } = require("wasmoon");
  const factory = new LuaFactory();
  const lua = await factory.createEngine();

  // API coverage: wrap lua.global.set to count function calls
  const apiCounts = {};
  if (coverageMode) {
    const origSet = lua.global.set.bind(lua.global);
    lua.global.set = function(name, value) {
      if (typeof value === "function") {
        apiCounts[name] = 0;
        const wrapped = function(...args) {
          apiCounts[name]++;
          return value.apply(this, args);
        };
        return origSet(name, wrapped);
      }
      return origSet(name, value);
    };
  }

  // Collect console output
  const luaOutput = [];

  // Expose globals
  lua.global.set("SCREEN_W", W);
  lua.global.set("SCREEN_H", H);
  lua.global.set("COLORS", palette.length);
  lua.global.set("ALIGN_LEFT", ALIGN_LEFT);
  lua.global.set("ALIGN_HCENTER", ALIGN_HCENTER);
  lua.global.set("ALIGN_RIGHT", ALIGN_RIGHT);
  lua.global.set("ALIGN_VCENTER", ALIGN_VCENTER);
  lua.global.set("ALIGN_CENTER", ALIGN_CENTER);
  // Drawing functions — first arg is surface id
  lua.global.set("cls", (id, c) => { const s = requireSurf("cls", id); requireColor("cls", c); cls(s, c); });
  lua.global.set("pix", (id, x, y, c) => { const s = requireSurf("pix", id); requireColor("pix", c); setPix(s, Math.floor(x) - camX, Math.floor(y) - camY, c); });
  lua.global.set("gpix", (id, x, y) => { const s = requireSurf("gpix", id); return getPix(s, x, y); });
  lua.global.set("line", (id, x0, y0, x1, y1, c) => { const s = requireSurf("line", id); requireColor("line", c); line(s, x0, y0, x1, y1, c); });
  lua.global.set("rect", (id, x, y, w, h, c) => { const s = requireSurf("rect", id); requireColor("rect", c); rect(s, x, y, w, h, c); });
  lua.global.set("rectf", (id, x, y, w, h, c) => { const s = requireSurf("rectf", id); requireColor("rectf", c); rectf(s, x, y, w, h, c); });
  lua.global.set("circ", (id, cx, cy, r, c) => { const s = requireSurf("circ", id); requireColor("circ", c); circ(s, cx, cy, r, c); });
  lua.global.set("circf", (id, cx, cy, r, c) => { const s = requireSurf("circf", id); requireColor("circf", c); circf(s, cx, cy, r, c); });
  lua.global.set("text", (id, str, x, y, c, align) => { const s = requireSurf("text", id); requireColor("text", c); drawText(s, str, x, y, c, align); });
  lua.global.set("vrow", (y) => vrow(y));
  lua.global.set("cam", camFn);
  lua.global.set("_cam_get_x", () => camX);
  lua.global.set("_cam_get_y", () => camY);
  // Audio stubs (headless — no sound, but validate args)
  const NOTE_NAMES = new Set();
  (() => {
    const names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"];
    for (let oct = 0; oct <= 8; oct++)
      for (const n of names) NOTE_NAMES.add(n + oct);
  })();
  lua.global.set("note", (ch, noteStr, dur) => {
    if (!NOTE_NAMES.has(String(noteStr).toUpperCase())) {
      throw new Error("note: invalid note '" + noteStr + "'. Use note name strings like 'C4', 'F#5' (not MIDI numbers)");
    }
  });
  lua.global.set("tone", () => {});
  lua.global.set("noise", () => {});
  lua.global.set("wave", () => {});
  lua.global.set("sfx_stop", () => {});
  lua.global.set("cam_shake", () => {});
  lua.global.set("cam_reset", () => {});
  lua.global.set("axis_x", () => 0);
  lua.global.set("axis_y", () => 0);
  // Motion sensor stubs (headless = no motion)
  lua.global.set("motion_x", () => 0);
  lua.global.set("motion_y", () => 0);
  lua.global.set("motion_z", () => 0);
  lua.global.set("gyro_alpha", () => 0);
  lua.global.set("gyro_beta", () => 0);
  lua.global.set("gyro_gamma", () => 0);
  lua.global.set("motion_enabled", () => 0);
  lua.global.set("spr", (id, imgId, x, y) => { const s = requireSurf("spr", id); drawImageFn(s, imgId, x, y); });
  lua.global.set("sspr", (id, imgId, sx, sy, sw, sh, dx, dy) => { const s = requireSurf("sspr", id); drawImageRegionFn(s, imgId, sx, sy, sw, sh, dx, dy); });
  lua.global.set("drawImage", (id, imgId, x, y) => { const s = requireSurf("drawImage", id); drawImageFn(s, imgId, x, y); });
  lua.global.set("drawImageRegion", (id, imgId, sx, sy, sw, sh, dx, dy) => { const s = requireSurf("drawImageRegion", id); drawImageRegionFn(s, imgId, sx, sy, sw, sh, dx, dy); });
  // Surface management
  lua.global.set("screen", screenFn);
  lua.global.set("canvas", canvasFn);
  lua.global.set("canvas_w", canvasW);
  lua.global.set("canvas_h", canvasH);
  lua.global.set("canvas_del", canvasDel);
  lua.global.set("blit", blitFn);
  lua.global.set("imageWidth", (id) => { const img = images[id]; return img ? img.w : 0; });
  lua.global.set("imageHeight", (id) => { const img = images[id]; return img ? img.h : 0; });

  // frame counter
  let frameNum = 0;
  lua.global.set("frame", () => frameNum);
  // use_pause — API parity with runtime engine. Headless mode has no
  // pause behavior to toggle, so this is a no-op stub; games calling it
  // behave identically in both environments.
  lua.global.set("use_pause", () => {});

  // time() / date() — real-time APIs. Headless mode still uses wall-clock
  // for parity with the browser runtime; tests that need determinism
  // should not read time() / date() (or should seed with a fixed value
  // via --seed).
  const bootTime = process.hrtime.bigint();
  lua.global.set("time", () => {
    const ns = Number(process.hrtime.bigint() - bootTime);
    return ns / 1e9;
  });
  lua.global.set("date", () => {
    const d = new Date();
    // yday via UTC diff to avoid DST edge-case drift.
    const yearStart = Date.UTC(d.getFullYear(), 0, 0);
    const today     = Date.UTC(d.getFullYear(), d.getMonth(), d.getDate());
    return {
      year:  d.getFullYear(),
      month: d.getMonth() + 1,
      day:   d.getDate(),
      hour:  d.getHours(),
      min:   d.getMinutes(),
      sec:   d.getSeconds(),
      wday:  d.getDay() + 1,
      yday:  Math.floor((today - yearStart) / 86400000),
      ms:    d.getMilliseconds(),
    };
  });

  // Trace state (for --trace)
  const traceEvents = [];
  let traceLogCount = 0;

  // Benchmark state (for --bench)
  const frameTimesNs = [];

  // Scene system
  let currentScene = null;
  let scenePending = null;
  const loadedSceneFiles = {};

  let sceneObj = null; // state pattern: table returned by scene file

  async function activateScene(name) {
    if (!loadedSceneFiles[name]) {
      const scenePath = path.resolve(gameDir, name + ".lua");
      if (fs.existsSync(scenePath)) {
        const src = fs.readFileSync(scenePath, "utf8");
        const result = await lua.doString(src);
        if (result && typeof result === "object") {
          loadedSceneFiles[name] = result;
        } else {
          loadedSceneFiles[name] = true;
        }
      } else {
        loadedSceneFiles[name] = true;
      }
    }
    currentScene = name;
    const cached = loadedSceneFiles[name];
    if (cached && typeof cached === "object") {
      sceneObj = cached;
      if (sceneObj.init) sceneObj.init();
    } else {
      sceneObj = null;
      const basename = name.includes("/") ? name.split("/").pop() : name;
      const initFn = lua.global.get(basename + "_init");
      if (initFn) initFn();
    }
  }

  lua.global.set("go", (name) => { scenePending = name; });
  lua.global.set("scene_name", () => currentScene || false);



  // print — capture output
  let untilTriggered = false;
  let untilFrame = 0;
  let untilMatch = "";
  lua.global.set("print", (...a) => {
    const line = a.map(x => String(x)).join("\t");
    luaOutput.push(line);
    if (showConsole) console.log("[Lua]", line);
    if (untilText && !untilTriggered && line.includes(untilText)) {
      untilTriggered = true;
      untilMatch = line;
    }
  });

  // mode(bits)
  lua.global.set("mode", (bits) => {
    if (bits !== 1 && bits !== 2 && bits !== 4) throw new Error("mode() invalid: " + bits);
    palette = buildPalette(bits);
    lua.global.set("COLORS", palette.length);
  });

  // Input stubs
  const validKeys = {"up":1,"down":1,"left":1,"right":1,"a":1,"b":1,"start":1,"select":1};
  lua.global.set("_btn", (k) => {
    if (typeof k !== "string" || !validKeys[k]) throw new Error('btn() invalid key "' + k + '"');
    return keys[k] ? 1 : 0;
  });
  lua.global.set("_btnp", (k) => {
    if (typeof k !== "string" || !validKeys[k]) throw new Error('btnp() invalid key "' + k + '"');
    return (keys[k] && !keysPrev[k]) ? 1 : 0;
  });

  // Touch simulation (matches engine.js semantics)
  lua.global.set("_touch", () => touches.length > 0 || touchStartedFlag ? 1 : 0);
  lua.global.set("_touch_start", () => touchStarted || touchStartedFlag ? 1 : 0);
  lua.global.set("_touch_end", () => touchEnded || touchEndedFlag ? 1 : 0);
  lua.global.set("touch_count", () => touches.length);
  lua.global.set("_touch_pos_x", (i) => { const t = touches[(i || 1) - 1]; return t ? t.x : false; });
  lua.global.set("_touch_pos_y", (i) => { const t = touches[(i || 1) - 1]; return t ? t.y : false; });
  lua.global.set("_touch_posf_x", (i) => { const t = touches[(i || 1) - 1]; return t ? t.fx : false; });
  lua.global.set("_touch_posf_y", (i) => { const t = touches[(i || 1) - 1]; return t ? t.fy : false; });
  lua.global.set("swipe", () => false);

  // loadImage — Node.js version using PNG decoder
  let pendingLoads = [];
  lua.global.set("loadImage", (imgPath) => {
    const id = imageIdCounter++;
    const fullPath = path.resolve(gameDir, imgPath);
    // Defer loading; we'll await all after _start
    pendingLoads.push((async () => {
      try {
        const { PNG } = require("pngjs");
        const data = fs.readFileSync(fullPath);
        const png = PNG.sync.read(data);
        const rgba = new Uint8Array(png.data);
        images[id] = { w: png.width, h: png.height, data: quantizeRGBA(rgba, png.width, png.height, palette) };
      } catch (e) {
        console.error(`Warning: loadImage("${imgPath}") failed: ${e.message}`);
        // Create empty 1x1 image as fallback
        images[id] = { w: 1, h: 1, data: new Uint8Array([0]) };
      }
    })());
    return id;
  });

  // Lua wrappers
  await lua.doString(`
function btn(k)
  return _btn(k) == 1
end
function btnp(k)
  return _btnp(k) == 1
end
function cam_get()
  return _cam_get_x(), _cam_get_y()
end
function touch()
  return _touch() == 1
end
function touch_start()
  return _touch_start() == 1
end
function touch_end()
  return _touch_end() == 1
end
function touch_pos(i)
  i = i or 1
  local x = _touch_pos_x(i)
  if x == false then return false end
  return x, _touch_pos_y(i)
end
function touch_posf(i)
  i = i or 1
  local x = _touch_posf_x(i)
  if x == false then return false end
  return x, _touch_posf_y(i)
end
  `);

  // --- Execute game ---
  let hasError = false;

  // Set random seed
  if (seedArg !== null) {
    await lua.doString(`math.randomseed(${parseInt(seedArg)})`);
  } else if (typeof runSeed !== "undefined" && runSeed) {
    await lua.doString(`math.randomseed(${runSeed})`);
  }

  // Preload modules for require() support (Wasmoon io.open can't read real filesystem)
  const gameDirAbs = path.resolve(gameDir);
  function collectLuaFiles(dir, prefix) {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    const result = [];
    for (const e of entries) {
      if (e.name.startsWith(".")) continue;
      const full = path.join(dir, e.name);
      const rel = prefix ? prefix + "/" + e.name : e.name;
      if (e.isDirectory()) result.push(...collectLuaFiles(full, rel));
      else if (e.name.endsWith(".lua") && rel !== "main.lua") result.push(rel);
    }
    return result;
  }
  for (const f of collectLuaFiles(gameDirAbs, "")) {
    const modName = f.replace(/\.lua$/, "").replace(/\//g, ".");
    const src = fs.readFileSync(path.join(gameDirAbs, f), "utf8");
    lua.global.set("_tmp_mod_src", src);
    lua.global.set("_tmp_mod_name", modName);
    await lua.doString(`package.preload[_tmp_mod_name] = load(_tmp_mod_src, "@" .. _tmp_mod_name .. ".lua")`);
  }
  await lua.doString("_tmp_mod_src = nil; _tmp_mod_name = nil");

  // Run main script
  try {
    await lua.doString(gameSrc);
  } catch (e) {
    console.error("Script error:", e.message || e);
    process.exit(1);
  }

  // Call _init
  const initFn = lua.global.get("_init");
  if (initFn) {
    try {
      initFn();
      if (!quiet) console.log("_init OK");
    } catch (e) {
      console.error("_init error:", e.message || e);
      process.exit(1);
    }
  }

  // Call _start
  const startFn = lua.global.get("_start");
  if (startFn) {
    try {
      startFn();
      if (!quiet) console.log("_start OK");
    } catch (e) {
      console.error("_start error:", e.message || e);
      process.exit(1);
    }
  }

  // Wait for image loads
  if (pendingLoads.length > 0) {
    await Promise.all(pendingLoads);
    pendingLoads = [];
  }

  // Call _ready (after images loaded)
  const readyFn = lua.global.get("_ready");
  if (readyFn) {
    try {
      readyFn();
      if (!quiet) console.log("_ready OK");
    } catch (e) {
      console.error("_ready error:", e.message || e);
      process.exit(1);
    }
  }

  // Process boot-time go() (e.g. go("title") in _ready)
  if (scenePending) {
    await activateScene(scenePending);
    scenePending = null;
  }

  // Run frames

  // --- Bot: Lua-scriptable auto-player ---
  const botArg = getOpt("bot", null);
  const botEnabled = botArg !== null;
  let botFn = null;

  if (botEnabled) {
    // Load bot script: --bot bot.lua (external file) or --bot (built-in tracker)
    if (typeof botArg === "string" && !botArg.endsWith(".lua")) {
      console.error(`Bot file must end with .lua: ${botArg}`);
      process.exit(1);
    }
    if (typeof botArg === "string" && botArg.endsWith(".lua")) {
      const botPath = path.resolve(botArg);
      if (!fs.existsSync(botPath)) {
        console.error(`Bot file not found: ${botPath}`);
        process.exit(1);
      }
      const botSrc = fs.readFileSync(botPath, "utf8");
      try { await lua.doString(botSrc); } catch (e) {
        console.error("Bot script error:", e.message || e);
        process.exit(1);
      }
    } else {
      // Built-in default bot: scan VRAM for brightest cluster, track it
      await lua.doString(`
function _bot()
  -- find ball: brightest pixel cluster in middle 70% of screen
  local best_y = -1
  local best_count = 0
  for y = 4, SCREEN_H - 5 do
    local count = 0
    for x = math.floor(SCREEN_W * 0.3), SCREEN_W - 11 do
      if gpix(x, y) >= 12 then count = count + 1 end
    end
    if count > best_count then
      best_count = count
      best_y = y
    end
  end
  -- find paddle: rightmost bright vertical bar
  local pad_sum = 0
  local pad_count = 0
  for y = 0, SCREEN_H - 1 do
    for x = SCREEN_W - 12, SCREEN_W - 3 do
      if gpix(x, y) >= 12 then pad_sum = pad_sum + y; pad_count = pad_count + 1 end
    end
  end
  local pad_y = pad_count > 0 and (pad_sum / pad_count) or (SCREEN_H / 2)
  if best_y >= 0 then
    if best_y < pad_y - 4 then return "up" end
    if best_y > pad_y + 4 then return "down" end
  end
  return false
end
`);
    }
    botFn = lua.global.get("_bot");
    if (!botFn) {
      console.error("Bot error: _bot() function not defined");
      process.exit(1);
    }
  }

  for (let f = 1; f <= frameCount; f++) {
    applyInput(f);
    applyTouch(f);

    // Bot: call _bot() after draw, inject result as input for next frame
    if (botFn && f > 1) {
      try {
        const action = botFn();
        keys["up"] = false;
        keys["down"] = false;
        keys["left"] = false;
        keys["right"] = false;
        keys["a"] = false;
        keys["b"] = false;
        if (typeof action === "string") {
          // Single key or comma-separated: "up" or "up,a"
          for (const k of action.split(",")) {
            const key = k.trim();
            if (key && validKeys[key]) keys[key] = true;
          }
        }
      } catch (e) {
        if (!quiet) console.error(`_bot error (frame ${f}):`, e.message || e);
      }
    }

    // Process pending scene transition
    if (scenePending) {
      await activateScene(scenePending);
      scenePending = null;
    }

    const basename = currentScene ? (currentScene.includes("/") ? currentScene.split("/").pop() : currentScene) : null;
    const frameStart = benchMode ? process.hrtime.bigint() : 0n;
    const uf = sceneObj ? sceneObj.update : lua.global.get(basename ? basename + "_update" : "_update");
    if (uf) {
      try { uf(); }
      catch (e) { console.error(`${currentScene || ""} update error (frame ${f}):`, e.message || e); hasError = true; break; }
    }
    const df = sceneObj ? sceneObj.draw : lua.global.get(basename ? basename + "_draw" : "_draw");
    if (df) {
      try { df(); }
      catch (e) { console.error(`${currentScene || ""} draw error (frame ${f}):`, e.message || e); hasError = true; break; }
    }
    if (benchMode) {
      const elapsedNs = Number(process.hrtime.bigint() - frameStart);
      frameTimesNs.push(elapsedNs);
    }
    frameNum = f;
    recordInput(f);

    // Trace: capture per-frame state for AI analysis
    if (traceFile) {
      const activeKeys = Object.keys(keys).filter(k => keys[k]);
      const newLogs = luaOutput.slice(traceLogCount);
      traceLogCount = luaOutput.length;
      traceEvents.push({
        frame: f,
        hash: vramHash(),
        keys: activeKeys,
        logs: newLogs,
      });
    }

    // Golden snapshot capture: record hash at target frames
    if (goldenFile) {
      if (goldenUpdate) {
        // Record every 30 frames by default (1 sec intervals at 30fps)
        if (f % 30 === 0 || f === frameCount) {
          goldenCaptured[f] = vramHash();
        }
      } else if (goldenTargets[f] !== undefined) {
        goldenCaptured[f] = vramHash();
      }
    }

    inputUpdate();
    touchUpdate();
    if (untilTriggered) {
      untilFrame = f;
      if (!quiet) console.log(`--until matched at frame ${f}: "${untilMatch}"`);
      break;
    }
    if (!quiet && (f <= 5 || f === frameCount || f % 10 === 0)) {
      console.log(`Frame ${f}: OK`);
    }
  }

  // --- Region cropping helper ---
  let cropX = 0, cropY = 0, cropW = W, cropH = H;
  if (regionArg) {
    const parts = regionArg.split(",").map(s => parseInt(s.trim()));
    if (parts.length === 4) {
      [cropX, cropY, cropW, cropH] = parts;
    }
  }

  function getPixelInRegion(rx, ry) {
    const scr = surfaces[0];
    const x = cropX + rx, y = cropY + ry;
    if (x >= 0 && x < W && y >= 0 && y < H) return scr.colorBuf[y * W + x];
    return 0;
  }

  // --- PNG export ---
  function savePng(filePath) {
    const { PNG } = require("pngjs");
    const png = new PNG({ width: cropW, height: cropH });
    for (let y = 0; y < cropH; y++) {
      for (let x = 0; x < cropW; x++) {
        const c = getPixelInRegion(x, y);
        const abgr = palette[c] || palette[0];
        const r = abgr & 0xFF;
        const g = (abgr >> 8) & 0xFF;
        const b = (abgr >> 16) & 0xFF;
        const idx = (y * cropW + x) * 4;
        png.data[idx] = r;
        png.data[idx + 1] = g;
        png.data[idx + 2] = b;
        png.data[idx + 3] = 255;
      }
    }
    const buffer = PNG.sync.write(png);
    fs.writeFileSync(filePath, buffer);
  }

  // --- Output ---
  if (doVdump) {
    console.log("\n--- vdump ---");
    if (regionArg) {
      for (let y = 0; y < cropH; y++) {
        let row = "";
        for (let x = 0; x < cropW; x++) row += getPixelInRegion(x, y).toString(16);
        console.log(row);
      }
    } else {
      console.log(vdump());
    }
  }

  if (typeof vrowArg === "string") {
    const rows = vrowArg.split(",").map(s => parseInt(s.trim()));
    console.log("\n--- vrow ---");
    for (const y of rows) {
      console.log(`row ${y}: ${vrow(y)}`);
    }
  }

  if (snapshotFile) {
    const snapshotPath = path.resolve(snapshotFile);
    fs.writeFileSync(snapshotPath, vdump());
    console.log(`Snapshot saved: ${snapshotPath}`);
  }

  if (diffFile) {
    const diffPath = path.resolve(diffFile);
    if (!fs.existsSync(diffPath)) {
      console.error(`Diff file not found: ${diffPath}`);
      process.exit(1);
    }
    const expected = fs.readFileSync(diffPath, "utf8").trim();
    const actual = vdump().trim();
    if (expected === actual) {
      console.log("DIFF: MATCH ✓");
    } else {
      console.log("DIFF: MISMATCH ✗");

      // Parse expected vdump text back into a VRAM buffer for precise
      // pixel-level comparison.
      const expRows = expected.split("\n");
      const actRows = actual.split("\n");
      const expBuf = new Uint8Array(W * H);
      for (let y = 0; y < Math.min(expRows.length, H); y++) {
        const row = expRows[y];
        for (let x = 0; x < Math.min(row.length, W); x++) {
          expBuf[y * W + x] = parseInt(row[x], 16) || 0;
        }
      }
      const actBuf = surfaces[0].colorBuf;

      // Count differing pixels
      let diffCount = 0;
      for (let i = 0; i < W * H; i++) {
        if (expBuf[i] !== actBuf[i]) diffCount++;
      }
      const diffPct = ((diffCount / (W * H)) * 100).toFixed(2);
      console.log(`  ${diffCount} pixels differ (${diffPct}%)`);

      // List up to the first 10 differing rows in hex form — caller can
      // re-run with --vdump --region or --snapshot to inspect further.
      const diffRows = [];
      for (let i = 0; i < Math.max(expRows.length, actRows.length); i++) {
        if (expRows[i] !== actRows[i]) diffRows.push(i);
      }
      if (diffRows.length > 0) {
        const shown = diffRows.slice(0, 10);
        console.log(`  differing rows: ${diffRows.length} total (showing first ${shown.length})`);
        for (const i of shown) {
          const exp = (expRows[i] || "(missing)").substring(0, 60);
          const act = (actRows[i] || "(missing)").substring(0, 60);
          console.log(`    row ${String(i).padStart(3)}  exp: ${exp}${exp.length >= 60 ? "..." : ""}`);
          console.log(`              act: ${act}${act.length >= 60 ? "..." : ""}`);
        }
        if (diffRows.length > shown.length) {
          console.log(`    ... ${diffRows.length - shown.length} more differing rows`);
        }
      }

      hasError = true;
    }
  }

  // PNG export
  if (typeof pngFile === "string") {
    const pngPath = path.resolve(pngFile);
    savePng(pngPath);
    console.log(`PNG saved: ${pngPath}`);
  }

  // Suite mode: parse output for PASS/FAIL
  if (suiteMode) {
    let passes = 0, fails = 0;
    const failLines = [];
    for (const l of luaOutput) {
      if (l.startsWith("FAIL:")) { fails++; failLines.push(l); }
      else if (l.includes("PASSED:") || l.includes("passed")) passes++;
    }
    console.log(`\nSuite: ${passes} references, ${fails} failures`);
    if (failLines.length > 0) {
      console.log("Failed assertions:");
      for (const fl of failLines) console.log("  " + fl);
      hasError = true;
    }
  }

  // --until summary
  if (untilText) {
    if (untilTriggered) {
      const secs = (untilFrame / 30).toFixed(1);
      console.log(`\n--until "${untilText}" matched at frame ${untilFrame} (${secs}s game time)`);
      console.log(`  "${untilMatch}"`);
    } else {
      console.log(`\n--until "${untilText}" NOT matched in ${frameCount} frames`);
    }
  }

  // Save recording if --record was specified
  if (recordFile) {
    const recordPath = path.resolve(recordFile);
    saveRecording(recordPath, frameNum);
    console.log(`Recording saved: ${recordPath} (${recordedFrames.length} frames with input)`);
  }

  // Golden snapshot check / update
  if (goldenFile) {
    if (goldenUpdate) {
      // Write current captures to the golden file
      const lines = [];
      lines.push("# mono golden snapshots");
      const seed = runSeed !== null ? runSeed : (seedArg !== null ? parseInt(seedArg) : 0);
      lines.push(`# seed=${seed} colors=${colorBits}`);
      const frames = Object.keys(goldenCaptured).map(Number).sort((a, b) => a - b);
      for (const fr of frames) {
        lines.push(`${fr} ${goldenCaptured[fr]}`);
      }
      fs.writeFileSync(path.resolve(goldenFile), lines.join("\n") + "\n");
      console.log(`Golden snapshots saved: ${goldenFile} (${frames.length} snapshots)`);
    } else {
      // Compare captures to targets
      const targetFrames = Object.keys(goldenTargets).map(Number).sort((a, b) => a - b);
      let pass = 0, fail = 0;
      const failures = [];
      for (const fr of targetFrames) {
        const expected = goldenTargets[fr];
        const actual = goldenCaptured[fr];
        if (actual === undefined) {
          fail++;
          failures.push(`frame ${fr}: expected ${expected}, but frame not reached`);
        } else if (actual === expected) {
          pass++;
        } else {
          fail++;
          failures.push(`frame ${fr}: expected ${expected}, got ${actual}`);
        }
      }
      console.log(`\n=== GOLDEN SNAPSHOTS ===`);
      console.log(`Targets: ${targetFrames.length}`);
      console.log(`Passed:  ${pass}`);
      console.log(`Failed:  ${fail}`);
      if (failures.length > 0) {
        console.log(`\nFailures:`);
        for (const f of failures) console.log(`  ${f}`);
        hasError = true;
      } else if (pass > 0) {
        console.log(`GOLDEN: PASS ✓`);
      }
    }
  }

  // Save trace file if --trace was specified
  if (traceFile) {
    const tracePath = path.resolve(traceFile);
    const lines = traceEvents.map(e => JSON.stringify(e));
    fs.writeFileSync(tracePath, lines.join("\n") + "\n");
    console.log(`Trace saved: ${tracePath} (${traceEvents.length} frames)`);
  }

  // Benchmark report
  if (benchMode && frameTimesNs.length > 0) {
    const sorted = [...frameTimesNs].sort((a, b) => a - b);
    const n = sorted.length;
    const avg = sorted.reduce((s, v) => s + v, 0) / n;
    const p50 = sorted[Math.floor(n * 0.50)];
    const p95 = sorted[Math.floor(n * 0.95)];
    const p99 = sorted[Math.floor(n * 0.99)];
    const max = sorted[n - 1];
    const min = sorted[0];
    const fmt = (ns) => (ns / 1e6).toFixed(3) + "ms";
    const mem = process.memoryUsage();
    const mb = (b) => (b / 1024 / 1024).toFixed(2) + "MB";
    console.log("\n=== BENCHMARK ===");
    console.log(`Frames: ${n}`);
    console.log(`min:    ${fmt(min)}`);
    console.log(`avg:    ${fmt(avg)}`);
    console.log(`p50:    ${fmt(p50)}`);
    console.log(`p95:    ${fmt(p95)}`);
    console.log(`p99:    ${fmt(p99)}`);
    console.log(`max:    ${fmt(max)}`);
    const budget = 33.333;  // 30 FPS = 33.33ms/frame
    const overBudget = sorted.filter(ns => ns / 1e6 > budget).length;
    console.log(`budget: 33.333ms (30 FPS)`);
    console.log(`over:   ${overBudget} frames (${((overBudget / n) * 100).toFixed(1)}%)`);
    console.log(`\nHeap:   ${mb(mem.heapUsed)} used / ${mb(mem.heapTotal)} total`);
    console.log(`RSS:    ${mb(mem.rss)}`);
  }

  // API coverage report
  if (coverageMode) {
    // Internal JS functions (prefixed with _) are invoked via Lua wrappers.
    // Map them to their public names so the report shows what the user
    // actually called. Source of truth:
    //   .claude/scripts/lib/engine-apis.js  (in the mono repo)
    // When this file ships as an editor template to a standalone user
    // project, the shared lib isn't available — fall back to an inlined
    // copy. Keep the two in sync; drift is caught by /mono-lint when
    // run from inside the repo.
    let API_RENAME;
    try {
      API_RENAME = require("../../../.claude/scripts/lib/engine-apis").buildCoverageRename();
    } catch (e) {
      API_RENAME = {
        _btn: "btn",
        _btnp: "btnp",
        _cam_get_x: "cam_get",
        _cam_get_y: null,
        _touch: "touch",
        _touch_start: "touch_start",
        _touch_end: "touch_end",
        _touch_pos_x: "touch_pos",
        _touch_pos_y: null,
        _touch_posf_x: "touch_posf",
        _touch_posf_y: null,
      };
    }
    // APIs that are not really Mono APIs — routed to stdio for dev convenience
    // or Lua built-ins that happen to be overridden. Exclude from coverage totals.
    const API_EXCLUDE = new Set(["print"]);
    const merged = {};
    for (const [name, count] of Object.entries(apiCounts)) {
      if (API_EXCLUDE.has(name)) continue;
      if (name in API_RENAME) {
        const pub = API_RENAME[name];
        if (pub === null) continue;  // skip; counted via its partner
        merged[pub] = (merged[pub] || 0) + count;
      } else if (name.startsWith("_")) {
        // Any other _prefixed helpers not in the rename map are truly internal
        continue;
      } else {
        merged[name] = (merged[name] || 0) + count;
      }
    }
    const publicEntries = Object.entries(merged).sort((a, b) => b[1] - a[1]);
    const used = publicEntries.filter(([_, c]) => c > 0);
    const unused = publicEntries.filter(([_, c]) => c === 0);

    if (coverageAggregate) {
      // Emit machine-readable coverage for aggregation (used by --scan --coverage)
      console.log("__COVERAGE_JSON__" + JSON.stringify(Object.fromEntries(publicEntries)));
    } else {
      console.log("\n=== API COVERAGE ===");
      console.log(`Public APIs: ${publicEntries.length}  (internal _prefixed hidden)`);
      console.log(`Used:        ${used.length} (${((used.length / publicEntries.length) * 100).toFixed(1)}%)`);
      console.log(`Unused:      ${unused.length}`);
      if (used.length > 0) {
        console.log("\nUsed APIs (by call count):");
        const nameWidth = Math.max(...used.map(([n]) => n.length));
        for (const [name, count] of used) {
          console.log(`  ${name.padEnd(nameWidth)}  ${count.toString().padStart(8)} calls`);
        }
      }
      if (unused.length > 0) {
        console.log("\nUnused APIs:");
        const unusedNames = unused.map(([n]) => n);
        const perLine = 6;
        for (let i = 0; i < unusedNames.length; i += perLine) {
          console.log("  " + unusedNames.slice(i, i + perLine).join(", "));
        }
      }
    }
  }

  // Summary
  if (!quiet) {
    console.log(`\n${hasError ? "FAILED" : "OK"} (${frameCount} frames, ${luaOutput.length} log lines)`);
  }

  const finalHash = vramHash();

  lua.global.close();

  // Return result for multi-run mode
  return { hasError, untilTriggered, untilFrame, untilMatch, luaOutput, vramHash: finalHash };
}

// --- Multi-run mode ---
if (totalRuns > 1) {
  (async () => {
    const results = [];
    const matchCounts = {};
    let totalFrames = 0;
    let minFrame = Infinity, maxFrame = 0;

    for (let r = 1; r <= totalRuns; r++) {
      // Reset state for each run
      palette = buildPalette(colorBits);
      const cb = new Uint8Array(W * H);
      const b32 = new Uint32Array(W * H);
      surfaces = [{ w: W, h: H, buf32: b32, colorBuf: cb }];
      camX = 0; camY = 0;
      images = []; imageIdCounter = 0;
      for (const k in keys) keys[k] = false;
      for (const k in keysPrev) keysPrev[k] = false;
      // Auto-seed each run differently (unless --seed is explicit)
      if (seedArg === null) {
        runSeed = r * 7919 + 42;  // deterministic but different per run
      }

      const result = await main();
      results.push(result);

      if (result.untilTriggered) {
        totalFrames += result.untilFrame;
        if (result.untilFrame < minFrame) minFrame = result.untilFrame;
        if (result.untilFrame > maxFrame) maxFrame = result.untilFrame;
        // Count unique match texts
        matchCounts[result.untilMatch] = (matchCounts[result.untilMatch] || 0) + 1;
      }
    }

    // Stats
    const matched = results.filter(r => r.untilTriggered).length;
    console.log(`\n=== ${totalRuns} RUNS COMPLETE ===`);
    console.log(`Matched: ${matched}/${totalRuns}`);
    if (matched > 0) {
      const avgFrame = (totalFrames / matched).toFixed(0);
      console.log(`Frames to match: min=${minFrame}, avg=${avgFrame}, max=${maxFrame}`);
      console.log(`Game time: min=${(minFrame/30).toFixed(1)}s, avg=${(totalFrames/matched/30).toFixed(1)}s, max=${(maxFrame/30).toFixed(1)}s`);
      console.log(`Results:`);
      for (const [text, count] of Object.entries(matchCounts)) {
        const pct = ((count / matched) * 100).toFixed(0);
        console.log(`  "${text}": ${count}/${matched} (${pct}%)`);
      }
    }

    process.exit(results.some(r => r.hasError) ? 1 : 0);
  })().catch(e => { console.error("Fatal:", e); process.exit(1); });
} else if (scanDir) {
  // --- Scan mode ---
  // Recursively find all main.lua files under scanDir and run each one
  // as a subprocess. Report pass/fail + final VRAM hash per game.
  //
  // main.lua is the canonical entry file convention — see demo/README.md.
  (() => {
    const { spawnSync } = require("child_process");
    const rootDir = path.resolve(scanDir);
    if (!fs.existsSync(rootDir)) {
      console.error(`Scan directory not found: ${rootDir}`);
      process.exit(1);
    }

    function findGames(dir) {
      const found = [];
      const entries = fs.readdirSync(dir, { withFileTypes: true });
      for (const e of entries) {
        const full = path.join(dir, e.name);
        if (e.isDirectory()) {
          found.push(...findGames(full));
        } else if (e.isFile() && e.name === "main.lua") {
          found.push(full);
        }
      }
      return found;
    }

    const games = findGames(rootDir);
    if (games.length === 0) {
      console.log(`No main.lua files found under ${rootDir}`);
      process.exit(0);
    }

    console.log(`=== SCAN ${rootDir} ===`);
    console.log(`Found ${games.length} game(s)`);
    console.log();

    const thisScript = process.argv[1];
    const frames = frameCount > 0 ? frameCount : 30;
    const results = [];
    const aggregatedCoverage = {};  // apiName → total count across all games
    const perGameCoverage = {};     // relPath → { apiName: count }

    for (const gamePath of games) {
      const gameDir = path.dirname(gamePath);
      const relPath = path.relative(rootDir, gamePath);
      const start = Date.now();
      const childArgs = [
        thisScript,
        "main.lua",
        "--frames", String(frames),
        "--colors", String(colorBits),
        "--quiet",
        "--snapshot", "/dev/null",
      ];
      if (coverageMode) childArgs.push("--coverage-json");
      const child = spawnSync("node", childArgs, {
        cwd: gameDir,
        encoding: "utf8",
      });
      const elapsed = Date.now() - start;

      const ok = child.status === 0;
      const output = (child.stdout || "") + (child.stderr || "");
      const errorLine = ok ? "" : (output.split("\n").find(l => l.includes("error")) || "").trim().substring(0, 80);

      // Parse coverage JSON from child output
      if (coverageMode) {
        const covLine = output.split("\n").find(l => l.startsWith("__COVERAGE_JSON__"));
        if (covLine) {
          try {
            const gameCov = JSON.parse(covLine.substring("__COVERAGE_JSON__".length));
            perGameCoverage[relPath] = gameCov;
            for (const [name, count] of Object.entries(gameCov)) {
              aggregatedCoverage[name] = (aggregatedCoverage[name] || 0) + count;
            }
          } catch (e) { /* ignore parse errors */ }
        }
      }

      results.push({ path: relPath, ok, elapsed, errorLine });
      const status = ok ? "✓ PASS" : "✗ FAIL";
      console.log(`  ${status}  ${relPath.padEnd(40)} ${elapsed.toString().padStart(5)}ms`);
      if (!ok && errorLine) {
        console.log(`         ${errorLine}`);
      }
    }

    // Aggregated coverage report (when --coverage is used with --scan)
    if (coverageMode && Object.keys(aggregatedCoverage).length > 0) {
      const entries = Object.entries(aggregatedCoverage).sort((a, b) => b[1] - a[1]);
      const used = entries.filter(([_, c]) => c > 0);
      const unused = entries.filter(([_, c]) => c === 0);
      console.log(`\n=== AGGREGATED COVERAGE (${games.length} games) ===`);
      console.log(`Public APIs: ${entries.length}`);
      console.log(`Used:        ${used.length} (${((used.length / entries.length) * 100).toFixed(1)}%)`);
      console.log(`Unused:      ${unused.length}`);
      if (used.length > 0) {
        console.log("\nUsed APIs (by total call count):");
        const nameWidth = Math.max(...used.map(([n]) => n.length));
        for (const [name, count] of used) {
          // Show which games use this API
          const userGames = Object.keys(perGameCoverage)
            .filter(g => perGameCoverage[g][name] > 0)
            .map(g => path.basename(path.dirname(g)));
          const gameList = userGames.length <= 3
            ? userGames.join(", ")
            : `${userGames.slice(0, 3).join(", ")}, +${userGames.length - 3}`;
          console.log(`  ${name.padEnd(nameWidth)}  ${count.toString().padStart(8)} calls   [${gameList}]`);
        }
      }
      if (unused.length > 0) {
        console.log(`\nUnused APIs (dead code candidates):`);
        const names = unused.map(([n]) => n);
        const perLine = 6;
        for (let i = 0; i < names.length; i += perLine) {
          console.log("  " + names.slice(i, i + perLine).join(", "));
        }
      }
    }

    const passCount = results.filter(r => r.ok).length;
    const failCount = results.length - passCount;
    console.log();
    console.log(`=== SCAN RESULTS ===`);
    console.log(`Total:  ${results.length}`);
    console.log(`Passed: ${passCount}`);
    console.log(`Failed: ${failCount}`);
    if (failCount === 0) {
      console.log(`SCAN: PASS ✓`);
      process.exit(0);
    } else {
      console.log(`SCAN: FAIL ✗`);
      process.exit(1);
    }
  })();
} else if (fuzzRuns > 0) {
  // --- Fuzz mode ---
  // Run the game N times with random inputs at random frames.
  // Report crash rate and collect unique error messages.
  (async () => {
    const validKeys = ["up", "down", "left", "right", "a", "b"];
    const results = { crashes: 0, ok: 0 };
    const errorSamples = {};  // message → count
    const errorFirstSeed = {}; // message → first seed that triggered it

    for (let r = 1; r <= fuzzRuns; r++) {
      // Reset state per run
      palette = buildPalette(colorBits);
      const cb = new Uint8Array(W * H);
      const b32 = new Uint32Array(W * H);
      surfaces = [{ w: W, h: H, buf32: b32, colorBuf: cb }];
      camX = 0; camY = 0;
      images = []; imageIdCounter = 0;
      for (const k in keys) keys[k] = false;
      for (const k in keysPrev) keysPrev[k] = false;

      // Per-run deterministic seed so failing cases can be reproduced
      const fuzzSeed = r * 6037 + 13;
      runSeed = fuzzSeed;

      // Generate random input schedule for this run
      for (const k of Object.keys(inputSchedule)) delete inputSchedule[k];
      const rng = (() => {
        // Mulberry32 PRNG seeded with fuzzSeed
        let a = fuzzSeed >>> 0;
        return () => {
          a = (a + 0x6D2B79F5) >>> 0;
          let t = a;
          t = Math.imul(t ^ (t >>> 15), t | 1);
          t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
          return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
        };
      })();
      // Random number of input events: 1-20
      const numEvents = 1 + Math.floor(rng() * 20);
      for (let i = 0; i < numEvents; i++) {
        const frame = 1 + Math.floor(rng() * Math.max(1, frameCount));
        const key = validKeys[Math.floor(rng() * validKeys.length)];
        if (!inputSchedule[frame]) inputSchedule[frame] = [];
        inputSchedule[frame].push(key);
      }

      // Suppress verbose output during fuzz runs
      const origLog = console.log;
      const origErr = console.error;
      const capturedErrors = [];
      console.log = () => {};
      console.error = (...args) => { capturedErrors.push(args.join(" ")); };

      let result;
      try {
        result = await main();
      } catch (e) {
        result = { hasError: true };
        capturedErrors.push(e.message || String(e));
      }

      console.log = origLog;
      console.error = origErr;

      if (result && result.hasError || capturedErrors.length > 0) {
        results.crashes++;
        // Capture the first error line as the sample
        for (const err of capturedErrors) {
          // Normalize by stripping frame numbers and paths
          const normalized = err
            .replace(/\(frame \d+\)/g, "(frame N)")
            .replace(/line \d+/g, "line N")
            .substring(0, 200);
          errorSamples[normalized] = (errorSamples[normalized] || 0) + 1;
          if (errorFirstSeed[normalized] === undefined) {
            errorFirstSeed[normalized] = fuzzSeed;
          }
        }
      } else {
        results.ok++;
      }

      if (!quiet && r % 10 === 0) {
        process.stdout.write(`\rFuzz progress: ${r}/${fuzzRuns} (${results.crashes} crashes)`);
      }
    }

    if (!quiet) process.stdout.write("\n");
    const crashRate = ((results.crashes / fuzzRuns) * 100).toFixed(2);
    console.log(`\n=== FUZZ RESULTS ===`);
    console.log(`Runs:     ${fuzzRuns}`);
    console.log(`OK:       ${results.ok}`);
    console.log(`Crashes:  ${results.crashes} (${crashRate}%)`);
    const uniqueErrors = Object.keys(errorSamples);
    console.log(`Unique errors: ${uniqueErrors.length}`);
    if (uniqueErrors.length > 0) {
      console.log(`\nError samples (sorted by frequency):`);
      const sorted = uniqueErrors.sort((a, b) => errorSamples[b] - errorSamples[a]);
      for (const err of sorted.slice(0, 10)) {
        console.log(`  [${errorSamples[err]}x, first seed=${errorFirstSeed[err]}] ${err}`);
      }
    }
    process.exit(results.crashes > 0 ? 1 : 0);
  })().catch(e => { console.error("Fatal:", e); process.exit(1); });
} else if (determinismRuns > 1) {
  // --- Determinism verification mode ---
  // Run the same game N times with the same seed; all VRAM hashes must match.
  (async () => {
    const fixedSeed = seedArg !== null ? parseInt(seedArg) : 42;
    runSeed = fixedSeed;
    const hashes = [];
    let anyError = false;

    for (let r = 1; r <= determinismRuns; r++) {
      // Full state reset
      palette = buildPalette(colorBits);
      const cb = new Uint8Array(W * H);
      const b32 = new Uint32Array(W * H);
      surfaces = [{ w: W, h: H, buf32: b32, colorBuf: cb }];
      camX = 0; camY = 0;
      images = []; imageIdCounter = 0;
      for (const k in keys) keys[k] = false;
      for (const k in keysPrev) keysPrev[k] = false;
      runSeed = fixedSeed;

      const result = await main();
      if (result.hasError) anyError = true;
      hashes.push(result.vramHash);
      if (!quiet) console.log(`  Run ${r}: hash=${result.vramHash}`);
    }

    const unique = [...new Set(hashes)];
    console.log(`\n=== DETERMINISM CHECK ===`);
    console.log(`Runs:   ${determinismRuns}`);
    console.log(`Seed:   ${fixedSeed}`);
    console.log(`Frames: ${frameCount}`);
    console.log(`Unique VRAM hashes: ${unique.length}`);

    if (unique.length === 1) {
      console.log(`DETERMINISM: PASS ✓  (all runs produced hash ${unique[0]})`);
      process.exit(anyError ? 1 : 0);
    } else {
      console.log(`DETERMINISM: FAIL ✗  (${unique.length} distinct hashes)`);
      const counts = {};
      for (const h of hashes) counts[h] = (counts[h] || 0) + 1;
      for (const [h, c] of Object.entries(counts)) {
        console.log(`  ${h}: ${c} runs`);
      }
      console.log(`\nLockstep multiplayer requires deterministic execution.`);
      console.log(`Common causes: unseeded math.random(), table iteration order,`);
      console.log(`time-based APIs, uninitialized state.`);
      process.exit(1);
    }
  })().catch(e => { console.error("Fatal:", e); process.exit(1); });
} else {
  main().then(r => process.exit(r.hasError ? 1 : 0)).catch(e => {
    console.error("Fatal:", e.message || e);
    process.exit(1);
  });
}
