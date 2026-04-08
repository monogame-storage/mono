#!/usr/bin/env node
/**
 * mono-test.js — Headless CLI Test Runner for Mono Engine
 *
 * Runs Lua game code in Node.js without a browser.
 * Uses Wasmoon for Lua 5.4, replicates engine.js drawing core.
 * Outputs vdump (VRAM hex text) for LLM verification.
 *
 * Usage:
 *   node mono-test.js <game.lua> [options]
 *
 * Options:
 *   --frames N       Run N frames (default: 0 = init+start only)
 *   --colors N       Color depth: 1, 2, or 4 (default: 1)
 *   --vdump          Print full vdump after execution
 *   --vrow Y         Print specific row Y (0-143)
 *   --suite          Test suite mode: parse PASS/FAIL output, exit code
 *   --input "F:K"    Inject input at frame F key K (e.g., "3:a,5:up")
 *   --snapshot FILE  Save vdump to file
 *   --diff FILE      Compare vdump against expected file
 *   --quiet          Suppress frame-by-frame logs
 *   --console        Print Lua print() output (default: true in suite mode)
 *   --ascii          Print ASCII art of screen (downscaled)
 *   --ascii-full     Print full-resolution ASCII art (160x144)
 *   --png FILE       Save screen as PNG image
 *   --region X,Y,W,H Crop vdump/ascii to region (e.g., "0,0,40,20")
 *   --until "TEXT"   Stop when Lua prints matching text (e.g., "WINS")
 *   --runs N         Run N times, report stats (use with --until)
 *   --seed N         Set math.randomseed for reproducible runs
 */

const fs = require("fs");
const path = require("path");

// --- Parse arguments ---
const args = process.argv.slice(2);
if (args.length === 0 || args[0] === "--help" || args[0] === "-h") {
  console.log(`Usage: node mono-test.js <game.lua> [options]

Options:
  --frames N       Run N frames (default: 0)
  --colors N       Color depth: 1, 2, or 4 (default: 1)
  --vdump          Print full vdump after execution
  --vrow Y         Print specific row(s), comma-separated
  --suite          Test suite mode (parse PASS/FAIL)
  --input "F:K"    Inject input (e.g., "3:a,5:up")
  --snapshot FILE  Save vdump to file
  --diff FILE      Compare vdump against expected file
  --quiet          Suppress frame logs
  --console        Print Lua print() output
  --ascii          Print ASCII art (downscaled 4:1)
  --ascii-full     Print full ASCII art (160x144)
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
const doAscii = hasFlag("ascii");
const doAsciiFull = hasFlag("ascii-full");
const pngFile = getOpt("png", null);
const regionArg = getOpt("region", null);
const untilText = getOpt("until", null);
const totalRuns = parseInt(getOpt("runs", "1")) || 1;
const seedArg = getOpt("seed", null);
let runSeed = null;

// --- Engine core (replicated from engine.js, no DOM) ---
const W = 160, H = 144;

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
  const src = getSurf(srcId), dst = getSurf(dstId);
  if (!src || !dst) return;
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
  lua.global.set("cls", (id, c) => { const s = getSurf(id); if (s) cls(s, c); });
  lua.global.set("pix", (id, x, y, c) => { const s = getSurf(id); if (s) setPix(s, Math.floor(x) - camX, Math.floor(y) - camY, c); });
  lua.global.set("gpix", (id, x, y) => { const s = getSurf(id); return s ? getPix(s, x, y) : 0; });
  lua.global.set("line", (id, x0, y0, x1, y1, c) => { const s = getSurf(id); if (s) line(s, x0, y0, x1, y1, c); });
  lua.global.set("rect", (id, x, y, w, h, c) => { const s = getSurf(id); if (s) rect(s, x, y, w, h, c); });
  lua.global.set("rectf", (id, x, y, w, h, c) => { const s = getSurf(id); if (s) rectf(s, x, y, w, h, c); });
  lua.global.set("circ", (id, cx, cy, r, c) => { const s = getSurf(id); if (s) circ(s, cx, cy, r, c); });
  lua.global.set("circf", (id, cx, cy, r, c) => { const s = getSurf(id); if (s) circf(s, cx, cy, r, c); });
  lua.global.set("text", (id, str, x, y, c, align) => { const s = getSurf(id); if (s) drawText(s, str, x, y, c, align); });
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
  lua.global.set("sfx_stop", () => {});
  lua.global.set("cam_shake", () => {});
  lua.global.set("cam_reset", () => {});
  lua.global.set("axis_x", () => 0);
  lua.global.set("axis_y", () => 0);
  lua.global.set("spr", (id, imgId, x, y) => { const s = getSurf(id); if (s) drawImageFn(s, imgId, x, y); });
  lua.global.set("sspr", (id, imgId, sx, sy, sw, sh, dx, dy) => { const s = getSurf(id); if (s) drawImageRegionFn(s, imgId, sx, sy, sw, sh, dx, dy); });
  lua.global.set("drawImage", (id, imgId, x, y) => { const s = getSurf(id); if (s) drawImageFn(s, imgId, x, y); });
  lua.global.set("drawImageRegion", (id, imgId, sx, sy, sw, sh, dx, dy) => { const s = getSurf(id); if (s) drawImageRegionFn(s, imgId, sx, sy, sw, sh, dx, dy); });
  // Surface management
  lua.global.set("screen", screenFn);
  lua.global.set("canvas", canvasFn);
  lua.global.set("canvas_w", canvasW);
  lua.global.set("canvas_h", canvasH);
  lua.global.set("canvas_del", canvasDel);
  lua.global.set("blit", blitFn);
  lua.global.set("imageWidth", (id) => { const img = images[id]; return img ? img.w : 0; });
  lua.global.set("imageHeight", (id) => { const img = images[id]; return img ? img.h : 0; });
  lua.global.set("vrow", vrow);
  lua.global.set("vdump", vdump);

  // frame counter
  let frameNum = 0;
  lua.global.set("frame", () => frameNum);

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

  // Touch stubs (no touch/mouse in headless mode)
  lua.global.set("_touch", () => 0);
  lua.global.set("_touch_start", () => 0);
  lua.global.set("_touch_end", () => 0);
  lua.global.set("touch_count", () => 0);
  lua.global.set("_touch_pos_x", () => false);
  lua.global.set("_touch_pos_y", () => false);
  lua.global.set("_touch_posf_x", () => false);
  lua.global.set("_touch_posf_y", () => false);
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
    frameNum = f;
    inputUpdate();
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

  // --- ASCII art renderer ---
  // Maps grayscale palette indices to density characters
  function renderAscii(downscale) {
    const scale = downscale || 1;
    // 16-color grayscale ramp: dark to bright
    const chars16 = " .:-=+*#%@";
    const maxColor = palette.length - 1;
    const lines = [];
    const outW = Math.ceil(cropW / scale);
    const outH = Math.ceil(cropH / scale);
    for (let sy = 0; sy < outH; sy++) {
      let row = "";
      for (let sx = 0; sx < outW; sx++) {
        // Average the block
        let sum = 0, count = 0;
        for (let dy = 0; dy < scale && (sy * scale + dy) < cropH; dy++) {
          for (let dx = 0; dx < scale && (sx * scale + dx) < cropW; dx++) {
            sum += getPixelInRegion(sx * scale + dx, sy * scale + dy);
            count++;
          }
        }
        const avg = sum / count;
        const charIdx = Math.round((avg / maxColor) * (chars16.length - 1));
        // Double-width for aspect ratio correction
        const ch = chars16[Math.min(charIdx, chars16.length - 1)];
        row += ch + ch;
      }
      lines.push(row);
    }
    return lines.join("\n");
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
      // Find first differing row
      const expRows = expected.split("\n");
      const actRows = actual.split("\n");
      for (let i = 0; i < Math.max(expRows.length, actRows.length); i++) {
        if (expRows[i] !== actRows[i]) {
          console.log(`  First diff at row ${i}:`);
          console.log(`  expected: ${(expRows[i] || "(missing)").substring(0, 40)}...`);
          console.log(`  actual:   ${(actRows[i] || "(missing)").substring(0, 40)}...`);
          break;
        }
      }
      hasError = true;
    }
  }

  // ASCII art output
  if (doAscii) {
    console.log("\n--- ascii (4:1 downscale) ---");
    console.log(renderAscii(4));
  }
  if (doAsciiFull) {
    console.log("\n--- ascii (full) ---");
    console.log(renderAscii(1));
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

  // Summary
  if (!quiet) {
    console.log(`\n${hasError ? "FAILED" : "OK"} (${frameCount} frames, ${luaOutput.length} log lines)`);
  }

  lua.global.close();

  // Return result for multi-run mode
  return { hasError, untilTriggered, untilFrame, untilMatch, luaOutput };
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
} else {
  main().then(r => process.exit(r.hasError ? 1 : 0)).catch(e => {
    console.error("Fatal:", e.message || e);
    process.exit(1);
  });
}
