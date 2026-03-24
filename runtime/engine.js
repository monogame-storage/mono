/**
 * GrayBox Runtime Engine v0.1
 *
 * 480×320, 4-color grayscale, 30fps, 2ch square wave
 * Standalone runtime — no game code included.
 *
 * Usage:
 *   1. Include this script
 *   2. Set GrayBox._init, GrayBox._update, GrayBox._draw
 *   3. Call GrayBox.boot()
 */
const GrayBox = (() => {
  "use strict";

  const W = 480;
  const H = 320;
  const FPS = 30;
  const COLORS = ["#1a1a1a", "#6b6b6b", "#b0b0b0", "#e8e8e8"];

  let canvas, ctx, buf, buf32;

  function hexToABGR(hex) {
    const r = parseInt(hex.slice(1, 3), 16);
    const g = parseInt(hex.slice(3, 5), 16);
    const b = parseInt(hex.slice(5, 7), 16);
    return (255 << 24) | (b << 16) | (g << 8) | r;
  }

  const COLOR_U32 = COLORS.map(hexToABGR);

  // --- Sprite storage ---
  const sprites = {};
  const spriteImgs = {};

  // --- Tilemap storage ---
  const tilemap = {};

  // --- Input ---
  const keyMap = {
    "ArrowUp": "up", "ArrowDown": "down", "ArrowLeft": "left", "ArrowRight": "right",
    "w": "up", "s": "down", "a": "left", "d": "right", "ㅈ": "up", "ㄴ": "down", "ㅁ": "left", "ㅇ": "right",
    "z": "a", "Z": "a", "x": "b", "X": "b", "ㅋ": "a", "ㅌ": "b",
    "Enter": "a", " ": "a"
  };
  const keys = {};
  const keysPressed = {};
  const keysPrev = {};

  // --- Audio ---
  let audioCtx = null;
  const channels = [null, null];
  const channelGains = [null, null];

  function ensureAudio() {
    if (!audioCtx) {
      audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      for (let i = 0; i < 2; i++) {
        channelGains[i] = audioCtx.createGain();
        channelGains[i].gain.value = 0.15;
        channelGains[i].connect(audioCtx.destination);
      }
    }
  }

  const NOTE_NAMES = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"];

  function noteToFreq(noteStr) {
    const match = noteStr.match(/^([A-G]#?)(\d)$/);
    if (!match) return 440;
    const name = match[1];
    const octave = parseInt(match[2]);
    const semitone = NOTE_NAMES.indexOf(name);
    if (semitone === -1) return 440;
    const midi = (octave + 1) * 12 + semitone;
    return 440 * Math.pow(2, (midi - 69) / 12);
  }

  // --- Font (4×6 built-in) ---
  const FONT_W = 4;
  const FONT_H = 7;
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
    FONT[ch] = [];
    for (let i = 0; i < bits.length; i++) FONT[ch].push(parseInt(bits[i]));
  }

  // =========================================================
  // Public API
  // =========================================================
  const API = {};

  // Lifecycle hooks (set by game code)
  API._init = null;
  API._update = null;
  API._draw = null;

  // --- Graphics ---
  API.cls = function(c = 0) {
    buf32.fill(COLOR_U32[c] || COLOR_U32[0]);
  };

  API.pix = function(x, y, c) {
    x = Math.floor(x); y = Math.floor(y);
    if (x < 0 || x >= W || y < 0 || y >= H) return;
    buf32[y * W + x] = COLOR_U32[c] || COLOR_U32[0];
  };

  API.line = function(x0, y0, x1, y1, c) {
    x0 = Math.floor(x0); y0 = Math.floor(y0);
    x1 = Math.floor(x1); y1 = Math.floor(y1);
    const dx = Math.abs(x1 - x0), dy = Math.abs(y1 - y0);
    const sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
    let err = dx - dy;
    while (true) {
      API.pix(x0, y0, c);
      if (x0 === x1 && y0 === y1) break;
      const e2 = 2 * err;
      if (e2 > -dy) { err -= dy; x0 += sx; }
      if (e2 < dx) { err += dx; y0 += sy; }
    }
  };

  API.rect = function(x, y, w, h, c) {
    API.line(x, y, x + w - 1, y, c);
    API.line(x + w - 1, y, x + w - 1, y + h - 1, c);
    API.line(x + w - 1, y + h - 1, x, y + h - 1, c);
    API.line(x, y + h - 1, x, y, c);
  };

  API.rectf = function(x, y, w, h, c) {
    x = Math.floor(x); y = Math.floor(y);
    const col = COLOR_U32[c] || COLOR_U32[0];
    for (let py = Math.max(0, y); py < Math.min(H, y + h); py++)
      for (let px = Math.max(0, x); px < Math.min(W, x + w); px++)
        buf32[py * W + px] = col;
  };

  API.circ = function(cx, cy, r, c) {
    let x = r, y = 0, d = 1 - r;
    cx = Math.floor(cx); cy = Math.floor(cy);
    while (x >= y) {
      API.pix(cx + x, cy + y, c); API.pix(cx - x, cy + y, c);
      API.pix(cx + x, cy - y, c); API.pix(cx - x, cy - y, c);
      API.pix(cx + y, cy + x, c); API.pix(cx - y, cy + x, c);
      API.pix(cx + y, cy - x, c); API.pix(cx - y, cy - x, c);
      y++;
      if (d < 0) { d += 2 * y + 1; } else { x--; d += 2 * (y - x) + 1; }
    }
  };

  API.circf = function(cx, cy, r, c) {
    cx = Math.floor(cx); cy = Math.floor(cy);
    const col = COLOR_U32[c] || COLOR_U32[0];
    const r2 = r * r;
    for (let py = -r; py <= r; py++)
      for (let px = -r; px <= r; px++)
        if (px * px + py * py <= r2) {
          const sx = cx + px, sy = cy + py;
          if (sx >= 0 && sx < W && sy >= 0 && sy < H) buf32[sy * W + sx] = col;
        }
  };

  // --- Sprites ---
  API.sprite = function(id, data) {
    const arr = new Uint8Array(64);
    let i = 0;
    for (const ch of data) {
      if (ch >= '0' && ch <= '3') { arr[i++] = parseInt(ch); if (i >= 64) break; }
    }
    sprites[id] = arr;
    const img = ctx.createImageData(8, 8);
    const d32 = new Uint32Array(img.data.buffer);
    for (let j = 0; j < 64; j++) d32[j] = COLOR_U32[arr[j]];
    spriteImgs[id] = img;
  };

  API.spr = function(id, x, y, flipX, flipY) {
    const s = sprites[id];
    if (!s) return;
    x = Math.floor(x); y = Math.floor(y);
    for (let py = 0; py < 8; py++) {
      for (let px = 0; px < 8; px++) {
        const sx = flipX ? 7 - px : px;
        const sy = flipY ? 7 - py : py;
        const c = s[sy * 8 + sx];
        const dx = x + px, dy = y + py;
        if (dx >= 0 && dx < W && dy >= 0 && dy < H) {
          buf32[dy * W + dx] = COLOR_U32[c];
        }
      }
    }
  };

  // --- Text ---
  API.text = function(str, x, y, c) {
    str = String(str).toUpperCase();
    let cx = Math.floor(x);
    const cy = Math.floor(y);
    const col = COLOR_U32[c] || COLOR_U32[3];
    for (const ch of str) {
      const glyph = FONT[ch];
      if (glyph) {
        for (let py = 0; py < FONT_H; py++) {
          for (let px = 0; px < FONT_W; px++) {
            if (glyph[py * FONT_W + px]) {
              const dx = cx + px, dy = cy + py;
              if (dx >= 0 && dx < W && dy >= 0 && dy < H)
                buf32[dy * W + dx] = col;
            }
          }
        }
      }
      cx += FONT_W + 1;
    }
  };

  // --- Tilemap ---
  API.mget = function(cx, cy) { return tilemap[cx + "," + cy] || 0; };
  API.mset = function(cx, cy, id) { tilemap[cx + "," + cy] = id; };
  API.map = function(mx, my, mw, mh, sx, sy) {
    for (let ty = 0; ty < mh; ty++)
      for (let tx = 0; tx < mw; tx++) {
        const id = API.mget(mx + tx, my + ty);
        if (id > 0) API.spr(id, sx + tx * 8, sy + ty * 8);
      }
  };

  // --- Input ---
  const VALID_KEYS = {up:1,down:1,left:1,right:1,a:1,b:1};
  API.btn = function(k) { if(!VALID_KEYS[k]) console.warn("GrayBox: invalid key \""+k+"\". Use: up/down/left/right/a/b"); return !!keys[k]; };
  API.btnp = function(k) { if(!VALID_KEYS[k]) console.warn("GrayBox: invalid key \""+k+"\". Use: up/down/left/right/a/b"); return !!keys[k] && !keysPrev[k]; };

  // --- Sound ---
  API.note = function(ch, noteStr, dur) {
    ensureAudio();
    if (ch < 0 || ch > 1) return;
    API.stop(ch);
    const osc = audioCtx.createOscillator();
    osc.type = "square";
    osc.frequency.value = noteToFreq(noteStr);
    osc.connect(channelGains[ch]);
    osc.start();
    osc.stop(audioCtx.currentTime + dur);
    channels[ch] = osc;
  };

  API.stop = function(ch) {
    if (ch === undefined) { API.stop(0); API.stop(1); return; }
    if (channels[ch]) {
      try { channels[ch].stop(); } catch (e) {}
      channels[ch] = null;
    }
  };

  // --- Utility ---
  API.rnd = function(max) { return Math.random() * max; };
  API.flr = Math.floor;
  API.abs = Math.abs;
  API.min = Math.min;
  API.max = Math.max;
  API.sin = Math.sin;
  API.cos = Math.cos;
  API.vibrate = function(ms) { if (navigator.vibrate) navigator.vibrate(ms || 0); };

  // --- Global state ---
  API.frame = 0;

  // --- Constants ---
  API.WIDTH = W;
  API.HEIGHT = H;
  API.COLORS = COLORS;

  // =========================================================
  // Boot
  // =========================================================
  function tick() {
    for (const k in keys) keysPressed[k] = keys[k] && !keysPrev[k];
    if (API._update) API._update();
    if (API._draw) API._draw();
    ctx.putImageData(buf, 0, 0);
    for (const k in keys) keysPrev[k] = keys[k];
    API.frame++;
  }

  API.boot = function(canvasId = "screen") {
    canvas = document.getElementById(canvasId);
    canvas.width = W;
    canvas.height = H;
    function fitCanvas() {
      var maxW = window.innerWidth - 40;
      var maxH = window.innerHeight - 60;
      var s = Math.min(maxW / W, maxH / H);
      canvas.style.width = (W * s) + "px";
      canvas.style.height = (H * s) + "px";
    }
    fitCanvas();
    window.addEventListener("resize", fitCanvas);
    ctx = canvas.getContext("2d");
    ctx.imageSmoothingEnabled = false;
    buf = ctx.createImageData(W, H);
    buf32 = new Uint32Array(buf.data.buffer);

    document.addEventListener("keydown", e => {
      const k = keyMap[e.key];
      if (k) { keys[k] = true; e.preventDefault(); }
    });
    document.addEventListener("keyup", e => {
      const k = keyMap[e.key];
      if (k) { keys[k] = false; e.preventDefault(); }
    });
    document.addEventListener("keydown", ensureAudio, { once: true });
    document.addEventListener("click", ensureAudio, { once: true });

    if (API._init) API._init();
    setInterval(tick, 1000 / FPS);
  };

  return API;
})();
