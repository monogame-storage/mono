/**
 * Mono Runtime Engine
 * 160x144, grayscale (1/2/4-bit), Lua 5.4 via Wasmoon.
 *
 * Mono.boot("screen", { game: "game.lua", colors: 1 })
 *   colors: 1 (2色), 2 (4色), 4 (16色). Default: 1
 */
var Mono = (() => {
  "use strict";

  const W = 160, H = 144, FPS = 30, FRAME_MS = 1000 / FPS;

  // --- Color palette ---
  function buildPalette(bits) {
    const n = 1 << bits;  // 2, 4, or 16
    const colors = new Uint32Array(n);
    for (let i = 0; i < n; i++) {
      const v = Math.round((i / (n - 1)) * 255);
      colors[i] = (255 << 24) | (v << 16) | (v << 8) | v;  // ABGR
    }
    return colors;
  }

  // --- Pixel buffer (color indices, not ABGR) ---
  let colorBuf = null;  // Uint8Array[W*H] storing color indices

  // --- Font (4x7 bitmap) ---
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

  // --- Graphics ---
  let palette = null;
  let canvas, ctx, imgData, buf32;

  function setPix(x, y, c) {
    x = Math.floor(x); y = Math.floor(y);
    if (x >= 0 && x < W && y >= 0 && y < H) {
      const idx = y * W + x;
      buf32[idx] = palette[c] || palette[0];
      colorBuf[idx] = c;
    }
  }

  function getPix(x, y) {
    x = Math.floor(x); y = Math.floor(y);
    if (x >= 0 && x < W && y >= 0 && y < H) return colorBuf[y * W + x];
    return 0;
  }

  function cls(c) {
    const col = palette[c] || palette[0];
    buf32.fill(col);
    colorBuf.fill(c || 0);
    debugShapes = [];
  }

  function line(x0, y0, x1, y1, c) {
    x0 = Math.floor(x0); y0 = Math.floor(y0);
    x1 = Math.floor(x1); y1 = Math.floor(y1);
    let dx = Math.abs(x1 - x0), dy = Math.abs(y1 - y0);
    let sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
    let err = dx - dy;
    while (true) {
      setPix(x0, y0, c);
      if (x0 === x1 && y0 === y1) break;
      let e2 = 2 * err;
      if (e2 > -dy) { err -= dy; x0 += sx; }
      if (e2 < dx) { err += dx; y0 += sy; }
    }
  }

  function rect(x, y, w, h, c) {
    x = Math.floor(x); y = Math.floor(y);
    w = Math.floor(w); h = Math.floor(h);
    for (let i = 0; i < w; i++) { setPix(x + i, y, c); setPix(x + i, y + h - 1, c); }
    for (let i = 0; i < h; i++) { setPix(x, y + i, c); setPix(x + w - 1, y + i, c); }
    if (debugMode) debugShapes.push({ x, y, w, h });
  }

  function rectf(x, y, w, h, c) {
    x = Math.floor(x); y = Math.floor(y);
    w = Math.floor(w); h = Math.floor(h);
    for (let py = y; py < y + h; py++)
      for (let px = x; px < x + w; px++)
        setPix(px, py, c);
    if (debugMode) debugShapes.push({ x, y, w, h });
  }

  function circ(cx, cy, r, c) {
    cx = Math.floor(cx); cy = Math.floor(cy); r = Math.floor(r);
    let x = r, y = 0, d = 1 - r;
    while (x >= y) {
      setPix(cx + x, cy + y, c); setPix(cx - x, cy + y, c);
      setPix(cx + x, cy - y, c); setPix(cx - x, cy - y, c);
      setPix(cx + y, cy + x, c); setPix(cx - y, cy + x, c);
      setPix(cx + y, cy - x, c); setPix(cx - y, cy - x, c);
      y++;
      if (d < 0) { d += 2 * y + 1; }
      else { x--; d += 2 * (y - x) + 1; }
    }
    if (debugMode) debugShapes.push({ x: cx - r, y: cy - r, w: r * 2 + 1, h: r * 2 + 1 });
  }

  function circf(cx, cy, r, c) {
    cx = Math.floor(cx); cy = Math.floor(cy); r = Math.floor(r);
    let x = r, y = 0, d = 1 - r;
    while (x >= y) {
      for (let i = cx - x; i <= cx + x; i++) { setPix(i, cy + y, c); setPix(i, cy - y, c); }
      for (let i = cx - y; i <= cx + y; i++) { setPix(i, cy + x, c); setPix(i, cy - x, c); }
      y++;
      if (d < 0) { d += 2 * y + 1; }
      else { x--; d += 2 * (y - x) + 1; }
    }
    if (debugMode) debugShapes.push({ x: cx - r, y: cy - r, w: r * 2 + 1, h: r * 2 + 1 });
  }

  function drawText(str, x, y, c) {
    str = String(str).toUpperCase();
    let cx = Math.floor(x);
    const cy = Math.floor(y);
    for (const ch of str) {
      const glyph = FONT[ch];
      if (glyph) {
        for (let py = 0; py < FONT_H; py++)
          for (let px = 0; px < FONT_W; px++)
            if (glyph[py * FONT_W + px]) setPix(cx + px, cy + py, c);
      }
      cx += FONT_W + 1;
    }
  }

  // --- VRAM dump ---
  function vrow(y) {
    y = Math.floor(y);
    if (y < 0 || y >= H) return "";
    let s = "";
    const off = y * W;
    for (let x = 0; x < W; x++) s += colorBuf[off + x].toString(16);
    return s;
  }

  function vdump() {
    const rows = [];
    for (let y = 0; y < H; y++) rows.push(vrow(y));
    return rows.join("\n");
  }

  // --- Debug / Pause ---
  let debugMode = false;
  let debugShapes = [];
  let paused = false;

  // --- Input ---
  const keyMap = {
    "ArrowUp": "up", "ArrowDown": "down", "ArrowLeft": "left", "ArrowRight": "right",
    "w": "up", "s": "down", "a": "left", "d": "right",
    "z": "a", "Z": "a", "x": "b", "X": "b",
    "Enter": "start", " ": "select"
  };
  const keys = {};
  const keysPrev = {};

  function btn(k) { return keys[k] ? true : false; }
  function btnp(k) { return (keys[k] && !keysPrev[k]) ? true : false; }

  function inputUpdate() {
    for (const k in keys) keysPrev[k] = keys[k];
  }

  // --- Flush buffer to canvas ---
  let frame = 0;
  function flush() {
    imgData.data.set(new Uint8Array(buf32.buffer));
    ctx.putImageData(imgData, 0, 0);
  }
  let flushFn = flush;

  // --- Boot ---
  const API = {};

  API.boot = async (canvasId, opts) => {
    if (!opts || !opts.game) return;

    const bits = opts.colors || 1;
    if (bits !== 1 && bits !== 2 && bits !== 4) throw new Error("colors must be 1, 2, or 4");
    palette = buildPalette(bits);

    // Canvas
    canvas = document.getElementById(canvasId);
    canvas.width = W;
    canvas.height = H;
    ctx = canvas.getContext("2d");
    ctx.imageSmoothingEnabled = false;
    imgData = ctx.createImageData(W, H);
    buf32 = new Uint32Array(imgData.data.buffer);
    colorBuf = new Uint8Array(W * H);

    // Fit canvas to window
    function fitCanvas() {
      const maxW = window.innerWidth - 40;
      const maxH = window.innerHeight - 60;
      const s = Math.min(maxW / W, maxH / H);
      canvas.style.width = (W * s) + "px";
      canvas.style.height = (H * s) + "px";
    }
    fitCanvas();
    window.addEventListener("resize", fitCanvas);

    // Input handling
    document.addEventListener("keydown", e => {
      if (e.key === "1") { debugMode = !debugMode; return; }
      if (e.key === " ") { paused = !paused; e.preventDefault(); return; }
      const k = keyMap[e.key];
      if (k) { keys[k] = true; e.preventDefault(); }
    });
    document.addEventListener("keyup", e => {
      const k = keyMap[e.key];
      if (k) { keys[k] = false; e.preventDefault(); }
    });

    // Fetch game source
    const gameSrc = await fetch(opts.game).then(r => r.text());

    // Load Wasmoon
    const { LuaFactory } = await import("https://cdn.jsdelivr.net/npm/wasmoon@1.16.0/+esm");
    const factory = new LuaFactory();
    const lua = await factory.createEngine();

    // Expose globals to Lua
    lua.global.set("SCREEN_W", W);
    lua.global.set("SCREEN_H", H);
    lua.global.set("COLORS", palette.length);
    lua.global.set("cls", cls);
    lua.global.set("pix", setPix);
    lua.global.set("gpix", getPix);
    lua.global.set("line", line);
    lua.global.set("rect", rect);
    lua.global.set("rectf", rectf);
    lua.global.set("circ", circ);
    lua.global.set("circf", circf);
    lua.global.set("text", drawText);
    lua.global.set("_btn", (k) => keys[k] ? 1 : 0);
    lua.global.set("_btnp", (k) => (keys[k] && !keysPrev[k]) ? 1 : 0);
    lua.global.set("vrow", vrow);
    lua.global.set("vdump", vdump);
    lua.global.set("print", (...args) => console.log("[Lua]", ...args));

    // Lua wrappers (avoid Wasmoon false→nil issue)
    await lua.doString(`
function btn(k)
  return _btn(k) == 1
end
function btnp(k)
  return _btnp(k) == 1
end
    `);

    // Run game script
    try {
      await lua.doString(gameSrc);
    } catch (e) {
      console.error("Mono: Lua error:", e);
    }

    // Call _init if defined
    const initFn = lua.global.get("_init");
    if (initFn) {
      try { initFn(); } catch (e) { console.error("Mono: _init error:", e); }
    }

    // Expose internals for plugins
    API._internal = { canvas, ctx, buf32, colorBuf, palette, imgData, W, H };

    // Game loop
    const updateFn = lua.global.get("_update");
    const drawFn = lua.global.get("_draw");
    setInterval(() => {
      if (!paused && updateFn) try { updateFn(); } catch (e) { console.error("Mono: _update error:", e); }
      if (drawFn) try { drawFn(); } catch (e) { console.error("Mono: _draw error:", e); }
      if (paused) {
        const maxC = palette.length - 1;
        const label = "PAUSED";
        const tw = label.length * (FONT_W + 1) - 1;  // text width
        const pad = 6;
        const pw = tw + pad * 2, ph = FONT_H + pad * 2;
        const px = Math.floor((W - pw) / 2), py = Math.floor((H - ph) / 2);
        rectf(px, py, pw, ph, 0);
        rect(px, py, pw, ph, maxC);
        if (Math.floor(Date.now() / 500) % 2 === 0) {
          drawText(label, px + pad, py + pad, maxC);
        }
      }
      frame++;
      flushFn();
      inputUpdate();
    }, FRAME_MS);
  };

  API.vrow = vrow;
  API.vdump = vdump;

  // Plugin hooks
  API._internal = null;  // set during boot
  API._setFlush = (fn) => { flushFn = fn; };
  API._getFrame = () => frame;

  return API;
})();
