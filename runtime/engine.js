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

  // --- Camera ---
  let camX = 0, camY = 0;

  // --- Image storage ---
  let images = [];         // { w, h, data: Uint8Array(w*h) } palette indices, 255=transparent
  let imageIdCounter = 0;
  let pendingLoads = [];

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

  // --- Image quantization & drawing ---
  function quantizeRGBA(rgba, w, h, pal) {
    const out = new Uint8Array(w * h);
    const palGray = [];
    for (let i = 0; i < pal.length; i++) palGray[i] = pal[i] & 0xFF;
    const n = pal.length;
    for (let i = 0; i < w * h; i++) {
      const ri = i * 4;
      if (rgba[ri + 3] < 128) { out[i] = 255; continue; } // transparent
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

  async function loadImageAsync(path, id, pal) {
    const resp = await fetch(path);
    if (!resp.ok) throw new Error("loadImage: " + path + " (" + resp.status + ")");
    const blob = await resp.blob();
    const bmp = await createImageBitmap(blob);
    const c = document.createElement("canvas");
    c.width = bmp.width; c.height = bmp.height;
    const cx = c.getContext("2d");
    cx.drawImage(bmp, 0, 0);
    const rgba = cx.getImageData(0, 0, bmp.width, bmp.height).data;
    images[id] = { w: bmp.width, h: bmp.height, data: quantizeRGBA(rgba, bmp.width, bmp.height, pal) };
  }

  function drawImageFn(id, x, y) {
    const img = images[id];
    if (!img) return;
    x = Math.floor(x) - camX; y = Math.floor(y) - camY;
    for (let py = 0; py < img.h; py++) {
      const sy = y + py;
      if (sy < 0 || sy >= H) continue;
      for (let px = 0; px < img.w; px++) {
        const sx = x + px;
        if (sx < 0 || sx >= W) continue;
        const c = img.data[py * img.w + px];
        if (c === 255) continue;
        const idx = sy * W + sx;
        colorBuf[idx] = c;
        buf32[idx] = palette[c];
      }
    }
  }

  function drawImageRegionFn(id, sx, sy, sw, sh, dx, dy) {
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
      if (screenY < 0 || screenY >= H) continue;
      for (let px = 0; px < sw; px++) {
        const screenX = dx + px;
        if (screenX < 0 || screenX >= W) continue;
        const c = img.data[(sy + py) * img.w + (sx + px)];
        if (c === 255) continue;
        const idx = screenY * W + screenX;
        colorBuf[idx] = c;
        buf32[idx] = palette[c];
      }
    }
  }

  function cam(x, y) { camX = x || 0; camY = y || 0; }

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
    x0 = Math.floor(x0) - camX; y0 = Math.floor(y0) - camY;
    x1 = Math.floor(x1) - camX; y1 = Math.floor(y1) - camY;
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
    x = Math.floor(x) - camX; y = Math.floor(y) - camY;
    w = Math.floor(w); h = Math.floor(h);
    for (let i = 0; i < w; i++) { setPix(x + i, y, c); setPix(x + i, y + h - 1, c); }
    for (let i = 0; i < h; i++) { setPix(x, y + i, c); setPix(x + w - 1, y + i, c); }
    if (debugMode) debugShapes.push({ x, y, w, h });
  }

  function rectf(x, y, w, h, c) {
    x = Math.floor(x) - camX; y = Math.floor(y) - camY;
    w = Math.floor(w); h = Math.floor(h);
    for (let py = y; py < y + h; py++)
      for (let px = x; px < x + w; px++)
        setPix(px, py, c);
    if (debugMode) debugShapes.push({ x, y, w, h });
  }

  function circ(cx, cy, r, c) {
    cx = Math.floor(cx) - camX; cy = Math.floor(cy) - camY; r = Math.floor(r);
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
    cx = Math.floor(cx) - camX; cy = Math.floor(cy) - camY; r = Math.floor(r);
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
    "ㅈ": "up", "ㄴ": "down", "ㅁ": "left", "ㅇ": "right",
    "z": "a", "Z": "a", "ㅋ": "a", "x": "b", "X": "b", "ㅌ": "b",
    "Enter": "start", " ": "select"
  };
  const keys = {};
  const keysPrev = {};

  // --- Axis (analog) ---
  let axisX = 0, axisY = 0;
  let axisSource = "none"; // "keyboard" | "gamepad" | "none"

  function btn(k) { return keys[k] ? true : false; }
  function btnp(k) { return (keys[k] && !keysPrev[k]) ? true : false; }

  function inputUpdate() {
    // Keyboard → axis (digital: -1/0/+1)
    if (axisSource !== "gamepad") {
      axisX = 0; axisY = 0;
      if (keys["left"])  axisX = -1;
      if (keys["right"]) axisX =  1;
      if (keys["up"])    axisY = -1;
      if (keys["down"])  axisY =  1;
    }

    // Axis → btn derivation (gamepad analog → digital)
    if (axisSource === "gamepad") {
      keys["left"]  = axisX < -0.5;
      keys["right"] = axisX >  0.5;
      keys["up"]    = axisY < -0.5;
      keys["down"]  = axisY >  0.5;
    }

    for (const k in keys) keysPrev[k] = keys[k];
  }

  // --- Flush buffer to canvas ---
  let frame = 0;
  function flush() {
    imgData.data.set(new Uint8Array(buf32.buffer));
    ctx.putImageData(imgData, 0, 0);
  }
  let flushFn = flush;

  // --- Scene system ---
  let currentScene = null;
  let scenePending = null;
  let loadedSceneFiles = {};

  // --- Boot ---
  const API = {};
  let _loopId = null;
  let _lua = null;

  API.boot = async (canvasId, opts) => {
    if (!opts || (!opts.game && !opts.source)) return;

    // Stop previous run if any
    if (_loopId) { clearInterval(_loopId); _loopId = null; }
    if (_lua) { _lua.global.close(); _lua = null; }
    images = []; imageIdCounter = 0; pendingLoads = [];
    camX = 0; camY = 0;

    // Clear previous error overlay
    if (canvas && canvas.parentElement) {
      const ov = canvas.parentElement.querySelector(".mono-error-overlay");
      if (ov) ov.style.display = "none";
    }

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

    // Fit canvas to window (skip if opts.noAutoFit)
    if (!opts.noAutoFit) {
      function fitCanvas() {
        const maxW = window.innerWidth - 40;
        const maxH = window.innerHeight - 60;
        const s = Math.min(maxW / W, maxH / H);
        canvas.style.width = (W * s) + "px";
        canvas.style.height = (H * s) + "px";
      }
      fitCanvas();
      window.addEventListener("resize", fitCanvas);
    }

    // Input handling (skip if external controller manages input)
    if (!opts.externalInput) {
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
    }

    // Get game source (fetch URL or use inline source)
    const gameSrc = opts.source || await fetch(opts.game).then(r => r.text());

    // Load Wasmoon
    const { LuaFactory } = await import("https://cdn.jsdelivr.net/npm/wasmoon@1.16.0/+esm");
    const factory = new LuaFactory();
    const lua = await factory.createEngine();
    _lua = lua;

    // Expose globals to Lua
    lua.global.set("SCREEN_W", W);
    lua.global.set("SCREEN_H", H);
    lua.global.set("COLORS", palette.length);
    lua.global.set("cls", cls);
    lua.global.set("pix", (x, y, c) => setPix(Math.floor(x) - camX, Math.floor(y) - camY, c));
    lua.global.set("gpix", getPix);
    lua.global.set("line", line);
    lua.global.set("rect", rect);
    lua.global.set("rectf", rectf);
    lua.global.set("circ", circ);
    lua.global.set("circf", circf);
    lua.global.set("text", drawText);
    lua.global.set("cam", cam);
    lua.global.set("_cam_get_x", () => camX);
    lua.global.set("_cam_get_y", () => camY);
    lua.global.set("drawImage", drawImageFn);
    lua.global.set("drawImageRegion", drawImageRegionFn);
    lua.global.set("imageWidth", (id) => { const img = images[id]; return img ? img.w : 0; });
    lua.global.set("imageHeight", (id) => { const img = images[id]; return img ? img.h : 0; });
    const validKeys = {"up":1,"down":1,"left":1,"right":1,"a":1,"b":1,"start":1,"select":1};
    lua.global.set("_btn", (k) => {
      if (typeof k !== "string" || !validKeys[k]) throw new Error('btn() invalid key "' + k + '". Valid: "up","down","left","right","a","b","start","select"');
      return keys[k] ? 1 : 0;
    });
    lua.global.set("_btnp", (k) => {
      if (typeof k !== "string" || !validKeys[k]) throw new Error('btnp() invalid key "' + k + '". Valid: "up","down","left","right","a","b","start","select"');
      return (keys[k] && !keysPrev[k]) ? 1 : 0;
    });
    lua.global.set("axis_x", () => axisX);
    lua.global.set("axis_y", () => axisY);
    lua.global.set("vrow", vrow);
    lua.global.set("vdump", vdump);
    lua.global.set("frame", () => frame);
    lua.global.set("print", (...args) => console.log("[Lua]", ...args));

    // mode(bits) — set color depth (1=2 colors, 2=4 colors, 4=16 colors)
    lua.global.set("mode", (bits) => {
      if (bits !== 1 && bits !== 2 && bits !== 4) throw new Error('mode() invalid: ' + bits + '. Valid: 1, 2, 4');
      palette = buildPalette(bits);
      lua.global.set("COLORS", palette.length);
    });

    // loadImage(path) — load image, quantize to current palette, return ID
    const gameBase = opts.game ? opts.game.replace(/[^/]*$/, "") : "";
    const assets = opts.assets || {};  // { "file.png": blobURL } from editor
    lua.global.set("loadImage", (path) => {
      const id = imageIdCounter++;
      const url = assets[path] || (path.startsWith("http") || path.startsWith("/") ? path : gameBase + path);
      pendingLoads.push(loadImageAsync(url, id, palette));
      return id;
    });

    // Lua wrappers (avoid Wasmoon false→nil issue)
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
    `);

    // --- Scene system ---
    currentScene = null;
    scenePending = null;
    loadedSceneFiles = {};

    const readFile = opts.readFile || (async (name) => {
      const url = gameBase + name;
      try { const r = await fetch(url); return r.ok ? await r.text() : null; }
      catch { return null; }
    });

    let sceneObj = null; // state pattern: table returned by scene file

    async function activateScene(name) {
      if (!loadedSceneFiles[name]) {
        const src = await readFile(name + ".lua");
        if (src !== null) {
          let result;
          try { result = await lua.doString(src); }
          catch (e) { showError(name + ".lua: " + (e.message || e)); return; }
          // State pattern: if scene file returns a table, use it
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
        if (sceneObj.init) {
          try { sceneObj.init(); }
          catch (e) { showError(name + ".init: " + (e.message || e)); }
        }
      } else {
        sceneObj = null;
        const basename = name.includes("/") ? name.split("/").pop() : name;
        const initFn = lua.global.get(basename + "_init");
        if (initFn) {
          try { initFn(); }
          catch (e) { showError(basename + "_init: " + (e.message || e)); }
        }
      }
    }

    lua.global.set("go", (name) => { scenePending = name; });
    lua.global.set("scene_name", () => currentScene || false);

    // Error overlay — HTML layer, not constrained by engine
    function showError(msg) {
      console.error("Mono:", msg);
      const parent = canvas.parentElement;
      let overlay = parent.querySelector(".mono-error-overlay");
      if (!overlay) {
        overlay = document.createElement("div");
        overlay.className = "mono-error-overlay";
        Object.assign(overlay.style, {
          position: "absolute", inset: "0",
          background: "rgba(0,0,0,0.55)",
          color: "#ff6b6b", padding: "16px",
          fontFamily: "'JetBrains Mono', monospace",
          fontSize: "12px", lineHeight: "1.6",
          overflow: "auto", zIndex: "100",
          whiteSpace: "pre-wrap", wordBreak: "break-word"
        });
        if (getComputedStyle(parent).position === "static") parent.style.position = "relative";
        parent.appendChild(overlay);
      }
      const clean = String(msg).replace(/^.*Error:\s*/, "");
      overlay.innerHTML = '<span style="color:#ff4444;font-size:14px;font-weight:bold">! ERROR</span>\n\n' + clean.replace(/</g, "&lt;");
      overlay.style.display = "block";
    }
    function clearError() {
      const overlay = canvas.parentElement.querySelector(".mono-error-overlay");
      if (overlay) overlay.style.display = "none";
    }
    API._showError = showError;
    API._clearError = clearError;
    clearError();

    // Run game script
    try {
      await lua.doString(gameSrc);
    } catch (e) {
      showError(e.message || e);
      return;
    }

    // Call _init (system config: mode, etc.) then _start (game init)
    const initFn = lua.global.get("_init");
    if (initFn) {
      try { initFn(); } catch (e) { showError("_init: " + (e.message || e)); return; }
    }

    // Expose internals for plugins (after _init so palette may have changed)
    API._internal = { canvas, ctx, buf32, colorBuf, palette, imgData, W, H };

    const startFn = lua.global.get("_start");
    if (startFn) {
      try { startFn(); } catch (e) { showError("_start: " + (e.message || e)); return; }
    }

    // Wait for all deferred image loads (loadImage calls from _start)
    if (pendingLoads.length > 0) {
      try { await Promise.all(pendingLoads); } catch (e) { showError("Image load: " + (e.message || e)); return; }
      pendingLoads = [];
    }

    // Call _ready after all images loaded (safe to query imageWidth/imageHeight)
    const readyFn = lua.global.get("_ready");
    if (readyFn) {
      try { readyFn(); } catch (e) { showError("_ready: " + (e.message || e)); return; }
    }

    // Process boot-time go() (e.g. go("title") in _ready)
    if (scenePending) {
      const name = scenePending;
      scenePending = null;
      await activateScene(name);
    }

    // Game loop (async setTimeout chain for scene loading support)
    function stopWithError(msg) { showError(msg); clearTimeout(_loopId); _loopId = null; }
    API._showError = (msg) => { stopWithError(msg); };

    async function tick() {
      // Process pending scene transition
      if (scenePending) {
        const name = scenePending;
        scenePending = null;
        await activateScene(name);
      }

      if (!paused) {
        const uf = sceneObj ? sceneObj.update : lua.global.get(currentScene ? (currentScene.includes("/") ? currentScene.split("/").pop() : currentScene) + "_update" : "_update");
        if (uf) try { uf(); } catch (e) { stopWithError((currentScene || "") + " update: " + (e.message || e)); return; }
      }
      {
        const df = sceneObj ? sceneObj.draw : lua.global.get(currentScene ? (currentScene.includes("/") ? currentScene.split("/").pop() : currentScene) + "_draw" : "_draw");
        if (df) try { df(); } catch (e) { stopWithError((currentScene || "") + " draw: " + (e.message || e)); return; }
      }
      if (paused) {
        const maxC = palette.length - 1;
        const label = "PAUSED";
        const tw = label.length * (FONT_W + 1) - 1;
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
      _loopId = setTimeout(tick, FRAME_MS);
    }
    _loopId = setTimeout(tick, FRAME_MS);
  };

  API.stop = () => {
    if (_loopId) { clearTimeout(_loopId); _loopId = null; }
    if (_lua) { _lua.global.close(); _lua = null; }
    paused = false;
    frame = 0;
    images = []; imageIdCounter = 0; pendingLoads = [];
    camX = 0; camY = 0;
    currentScene = null; scenePending = null; loadedSceneFiles = {};
  };

  // Expose input for external control (playground gamepad)
  API.setKey = (name, pressed) => { keys[name] = pressed; };
  API.keyMap = keyMap;

  API.vrow = vrow;
  API.vdump = vdump;
  API.setAxis = (x, y) => { axisX = x; axisY = y; axisSource = "gamepad"; };
  API.clearAxis = () => { axisX = 0; axisY = 0; axisSource = "none"; };

  // Plugin hooks
  API._internal = null;  // set during boot
  API._setFlush = (fn) => { flushFn = fn; };
  API._getFrame = () => frame;

  return API;
})();
