/**
 * Mono Runtime Engine
 * 160x120, grayscale (1/2/4-bit), Lua 5.4 via Wasmoon.
 *
 * Mono.boot("screen", { game: "main.lua", colors: 1, cartId: "myGame" })
 *   colors: 1 (2色), 2 (4色), 4 (16色). Default: 1
 *   cartId: string — required if saveBackend is "persistent" (the default
 *           when cartId is supplied). Used to scope data_save/data_load.
 *   saveBackend: "persistent" | "memory" — defaults to "persistent" when
 *           cartId is provided, "memory" otherwise.
 */
var Mono = (() => {
  "use strict";

  const W = 160, H = 120, FPS = 30, FRAME_MS = 1000 / FPS;

  // --- Wake Lock (prevent screen sleep during gameplay) ---
  let wakeLock = null;
  async function requestWakeLock() {
    try {
      if (typeof navigator !== "undefined" && navigator.wakeLock)
        wakeLock = await navigator.wakeLock.request("screen");
    } catch {}
  }
  async function releaseWakeLock() {
    try {
      if (wakeLock) { await wakeLock.release(); wakeLock = null; }
    } catch {}
  }
  // Re-acquire wake lock when tab becomes visible (browser releases it on hide)
  if (typeof document !== "undefined") {
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible" && wakeLock === null && _loopId)
        requestWakeLock();
    });
  }

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

  // --- Surfaces (canvas abstraction) ---
  // Surface = { w, h, buf32: Uint32Array, colorBuf: Uint8Array }
  // surfaces[0] = screen, surfaces[1..n] = virtual canvases
  let surfaces = [];

  function getSurf(id) { return surfaces[id]; }

  // --- Camera ---
  let camX = 0, camY = 0;
  let shakeAmount = 0, shakeX = 0, shakeY = 0;

  // --- Audio (2-channel synth: square/sawtooth/triangle/sine + noise) ---
  let audioCtx = null;
  const channels = [null, null]; // { src, gain }
  const channelWave = ["square", "square"]; // waveform per channel
  const NOTE_FREQ = {};
  (() => {
    const names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"];
    for (let oct = 0; oct <= 8; oct++)
      for (let i = 0; i < 12; i++)
        NOTE_FREQ[names[i] + oct] = 440 * Math.pow(2, (oct - 4) + (i - 9) / 12);
  })();

  function ensureAudio() {
    if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    if (audioCtx.state === "suspended") audioCtx.resume();
    return audioCtx;
  }

  // One-shot audio unlock. Mobile WebViews and Mobile Safari keep
  // AudioContext suspended until creation+resume happens inside a real
  // user-gesture event, even when mediaPlaybackRequiresUserGesture=false.
  // We attach capture-phase listeners on the document so the very first
  // touch/mouse/key event primes the context — earlier than any in-game
  // sfx call would. The listener removes itself once the context is
  // running so it's free after the first interaction.
  let _audioUnlocked = false;
  function _unlockAudio() {
    if (_audioUnlocked) return;
    try {
      ensureAudio();
      // Some browsers report state === "running" only after resume() resolves.
      if (audioCtx && audioCtx.state !== "running" && audioCtx.resume) {
        audioCtx.resume().catch(() => {});
      }
      _audioUnlocked = true;
    } catch (e) { /* ignore — retry on next gesture */ }
  }
  if (typeof document !== "undefined") {
    const opts = { capture: true, passive: true };
    const fn = () => {
      _unlockAudio();
      if (_audioUnlocked) {
        document.removeEventListener("touchstart", fn, opts);
        document.removeEventListener("mousedown",  fn, opts);
        document.removeEventListener("keydown",     fn, opts);
        document.removeEventListener("pointerdown", fn, opts);
      }
    };
    document.addEventListener("touchstart", fn, opts);
    document.addEventListener("mousedown",  fn, opts);
    document.addEventListener("keydown",     fn, opts);
    document.addEventListener("pointerdown", fn, opts);
  }

  let _noiseBuf = null; // shared noise buffer (lazy init)
  function getNoiseBuf() {
    const ctx = audioCtx;
    if (!_noiseBuf || _noiseBuf.sampleRate !== ctx.sampleRate) {
      const len = ctx.sampleRate; // 1 second
      _noiseBuf = ctx.createBuffer(1, len, ctx.sampleRate);
      const data = _noiseBuf.getChannelData(0);
      for (let i = 0; i < len; i++) data[i] = Math.random() * 2 - 1;
    }
    return _noiseBuf;
  }

  function stopChannel(ch) {
    if (channels[ch]) { try { channels[ch].src.stop(); } catch(e) {} channels[ch] = null; }
  }

  function startChannel(ch, src, gain, dur, filter) {
    const ctx = audioCtx;
    gain.gain.value = 0.15;
    const fadeStart = Math.max(ctx.currentTime, ctx.currentTime + dur - 0.02);
    gain.gain.setValueAtTime(0.15, fadeStart);
    gain.gain.linearRampToValueAtTime(0, ctx.currentTime + dur);
    if (filter) { src.connect(filter); filter.connect(gain); }
    else { src.connect(gain); }
    gain.connect(ctx.destination);
    src.start();
    src.stop(ctx.currentTime + dur);
    channels[ch] = { src, gain };
    src.onended = () => { if (channels[ch] && channels[ch].src === src) channels[ch] = null; };
  }

  function notePlay(ch, noteStr, dur) {
    ch = Math.floor(ch);
    if (ch < 0 || ch > 1) return;
    dur = dur || 0.1;
    const key = String(noteStr).toUpperCase();
    const freq = NOTE_FREQ[key];
    if (!freq) throw new Error("note: invalid note '" + noteStr + "'. Use note name strings like 'C4', 'F#5' (not MIDI numbers)");
    const ctx = ensureAudio();
    stopChannel(ch);
    const osc = ctx.createOscillator();
    osc.type = channelWave[ch];
    osc.frequency.value = freq;
    startChannel(ch, osc, ctx.createGain(), dur);
  }

  function tonePlay(ch, startHz, endHz, dur) {
    ch = Math.floor(ch);
    if (ch < 0 || ch > 1) return;
    startHz = Number(startHz) || 200;
    endHz = Number(endHz) || 200;
    dur = dur || 0.2;
    const ctx = ensureAudio();
    stopChannel(ch);
    const osc = ctx.createOscillator();
    osc.type = channelWave[ch];
    osc.frequency.setValueAtTime(Math.max(startHz, 1), ctx.currentTime);
    osc.frequency.exponentialRampToValueAtTime(Math.max(endHz, 1), ctx.currentTime + dur);
    startChannel(ch, osc, ctx.createGain(), dur);
  }

  function noisePlay(ch, dur, filterType, filterFreq) {
    ch = Math.floor(ch);
    if (ch < 0 || ch > 1) return;
    dur = dur || 0.2;
    const ctx = ensureAudio();
    stopChannel(ch);
    const src = ctx.createBufferSource();
    src.buffer = getNoiseBuf();
    src.loop = true;
    var filter = null;
    if (filterType) {
      var ft = String(filterType).toLowerCase();
      if (ft === "low") ft = "lowpass";
      else if (ft === "high") ft = "highpass";
      else if (ft === "band") ft = "bandpass";
      if (ft === "lowpass" || ft === "highpass" || ft === "bandpass") {
        filter = ctx.createBiquadFilter();
        filter.type = ft;
        filter.frequency.value = Number(filterFreq) || 1000;
      }
    }
    startChannel(ch, src, ctx.createGain(), dur, filter);
  }

  function waveSet(ch, type) {
    ch = Math.floor(ch);
    if (ch < 0 || ch > 1) return;
    const valid = ["square", "sawtooth", "triangle", "sine"];
    type = String(type).toLowerCase();
    if (valid.indexOf(type) === -1) return;
    channelWave[ch] = type;
  }

  function sfxStop(ch) {
    if (ch === undefined || ch === false) {
      for (let i = 0; i < 2; i++) stopChannel(i);
    } else {
      ch = Math.floor(ch);
      if (ch >= 0 && ch <= 1) stopChannel(ch);
    }
  }

  // --- Image storage ---
  let images = [];         // { w, h, data: Uint8Array(w*h) } palette indices, 255=transparent
  let imageIdCounter = 0;
  let pendingLoads = [];

  // --- Font (4x7 bitmap) ---
  // FONT + FONT_W/FONT_H now live in runtime/engine-draw.js. Pulled in via
  // the <script src="engine-draw.js"> tag that precedes this file.
  const Draw = (typeof globalThis !== "undefined" && globalThis.MonoDraw)
            || (typeof window !== "undefined" && window.MonoDraw);
  if (!Draw) throw new Error("MonoDraw not loaded. Include <script src=\"/runtime/engine-draw.js\"> before engine.js.");
  const { FONT, FONT_W, FONT_H } = Draw;

  // --- Graphics ---
  let palette = null;
  let canvas, ctx, imgData, buf32;

  // Color validation removed from engine — handled by headless runner (mono-runner.js)
  // for zero runtime overhead. See requireColor() in mono-runner.js.

  function setPix(s, x, y, c) {
    x = Math.floor(x); y = Math.floor(y);
    if (x >= 0 && x < s.w && y >= 0 && y < s.h) {
      const idx = y * s.w + x;
      s.buf32[idx] = palette[c] || palette[0];
      s.colorBuf[idx] = c;
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

  function cam(x, y) { camX = x || 0; camY = y || 0; }
  function camReset() { camX = 0; camY = 0; shakeAmount = 0; shakeX = 0; shakeY = 0; }
  function camShake(amount) { shakeAmount = amount; }

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

  // line / rect / rectf / circ / circf / drawText come from MonoDraw so the
  // browser runtime, CLI test runner, and Web Worker smoke test all share
  // the same pixel algorithms.
  const _draw = Draw.create({
    setPix,
    getCam: () => [camX, camY],
    onShape: (shape) => { if (debugMode) debugShapes.push(shape); },
  });
  const line = _draw.line, rect = _draw.rect, rectf = _draw.rectf;
  const circ = _draw.circ, circf = _draw.circf, drawText = _draw.drawText;

  // --- Surface management ---
  function screenFn() { return 0; }

  function canvasFn(w, h) {
    w = Math.floor(w); h = Math.floor(h);
    if (w < 1 || h < 1 || w > 1024 || h > 1024) return false;
    const colorBuf = new Uint8Array(w * h);
    const buf32 = new Uint32Array(w * h);
    const col = palette[0] || 0xFF000000;
    buf32.fill(col);
    const id = surfaces.length;
    surfaces.push({ w, h, buf32, colorBuf });
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

  // --- Debug / Pause ---
  let debugMode = true;
  let debugShapes = [];
  let paused = false;
  // Default: engine auto-toggles pause on SELECT press. Games that want to
  // use SELECT for their own meta functions (inventory, map, etc.) can call
  // use_pause(false) from Lua to opt out. The game then reads btnp("select")
  // itself and is responsible for its own pause (if any).
  let pauseEnabled = true;

  // --- Input ---
  const keyMap = {
    "ArrowUp": "up", "ArrowDown": "down", "ArrowLeft": "left", "ArrowRight": "right",
    "w": "up", "s": "down", "a": "left", "d": "right",
    "ㅈ": "up", "ㄴ": "down", "ㅁ": "left", "ㅇ": "right",
    "z": "a", "Z": "a", "ㅋ": "a", "x": "b", "X": "b", "ㅌ": "b",
    "Enter": "start", " ": "select",
    // Android hardware gamepad (sent as KeyboardEvent)
    "GamepadA": "a", "GamepadB": "b",
    "GamepadDPadUp": "up", "GamepadDPadDown": "down",
    "GamepadDPadLeft": "left", "GamepadDPadRight": "right"
  };
  // Android gamepad keyCode fallback (some devices use keyCode instead of e.key)
  const keyCodeMap = { 96: "a", 97: "b", 19: "up", 20: "down", 21: "left", 22: "right" };
  const keys = {};
  const keysPrev = {};

  // --- Axis (analog) ---
  let axisX = 0, axisY = 0;
  let axisSource = "none"; // "keyboard" | "gamepad" | "none"

  // --- Motion sensor (accelerometer/gyroscope) ---
  let motionX = 0, motionY = 0, motionZ = 0; // accelerometer (-1 to 1, normalized)
  let gyroAlpha = 0, gyroBeta = 0, gyroGamma = 0; // gyroscope (degrees)
  let motionEnabled = false;
  if (typeof window !== "undefined" && window.DeviceMotionEvent) {
    window.addEventListener("devicemotion", (e) => {
      const a = e.accelerationIncludingGravity;
      if (!a) return;
      motionEnabled = true;
      motionX = Math.max(-1, Math.min(1, -(a.x || 0) / 9.8)); // negated: tilt right = positive screen x
      motionY = Math.max(-1, Math.min(1, (a.y || 0) / 9.8));
      motionZ = Math.max(-1, Math.min(1, (a.z || 0) / 9.8));
    });
    window.addEventListener("deviceorientation", (e) => {
      gyroAlpha = e.alpha || 0;
      gyroBeta = e.beta || 0;
      gyroGamma = e.gamma || 0;
    });
  }

  // --- Touch / Mouse ---
  let touches = [];           // [{ id, x, y, fx, fy }]
  // Snapshot of touches removed by the most recent `touchend` DOM event.
  // touch_pos(i) falls back to this while touch_end() is true so that
  //   if touch_end() then local x, y = touch_pos(1) end
  // reads the release position instead of false — otherwise splice()
  // happens before touchEndedFlag flips, leaving touches[] empty on the
  // single frame touch_end() fires.
  let endedTouches = [];
  let touchStartedFlag = false;
  let touchEndedFlag = false;
  let touchStarted = false;
  let touchEnded = false;
  let swipeDir = false;
  let swipeDirFlag = false;
  let swipeAnchor = null;
  const SWIPE_THRESHOLD = 10; // game pixels

  function getVisibleCanvas() {
    return canvas.style.display === "none" ? canvas.nextElementSibling || canvas : canvas;
  }

  // Compute the actual content rect inside the CSS box,
  // accounting for object-fit: contain / aspect-ratio letterboxing.
  function getContentRect() {
    const vc = getVisibleCanvas();
    const box = vc.getBoundingClientRect();
    const canvasRatio = W / H;
    const boxRatio = box.width / box.height;
    let cw, ch;
    if (boxRatio > canvasRatio) {
      // wider box → content height-fitted, horizontally centered
      ch = box.height;
      cw = ch * canvasRatio;
    } else {
      // taller box → content width-fitted, vertically centered
      cw = box.width;
      ch = cw / canvasRatio;
    }
    return {
      left: box.left + (box.width - cw) / 2,
      top: box.top + (box.height - ch) / 2,
      width: cw,
      height: ch,
    };
  }

  function mapToScreenWithRect(clientX, clientY, rect) {
    const fx = (clientX - rect.left) / rect.width * W;
    const fy = (clientY - rect.top) / rect.height * H;
    const x = Math.max(0, Math.min(W - 1, Math.floor(fx)));
    const y = Math.max(0, Math.min(H - 1, Math.floor(fy)));
    return { x, y, fx, fy };
  }

  function mapToScreen(clientX, clientY) {
    return mapToScreenWithRect(clientX, clientY, getContentRect());
  }

  function isInsideRect(clientX, clientY, rect) {
    return clientX >= rect.left && clientX <= rect.left + rect.width &&
           clientY >= rect.top && clientY <= rect.top + rect.height;
  }

  function detectSwipe(endX, endY) {
    if (!swipeAnchor) return;
    const dx = endX - swipeAnchor.x;
    const dy = endY - swipeAnchor.y;
    if (Math.abs(dx) < SWIPE_THRESHOLD && Math.abs(dy) < SWIPE_THRESHOLD) return;
    if (Math.abs(dx) > Math.abs(dy)) {
      swipeDirFlag = dx > 0 ? "right" : "left";
    } else {
      swipeDirFlag = dy > 0 ? "down" : "up";
    }
  }

  function btn(k) { return keys[k] ? true : false; }
  function btnp(k) { return (keys[k] && !keysPrev[k]) ? true : false; }
  function btnr(k) { return (!keys[k] && keysPrev[k]) ? true : false; }

  // --- Hardware gamepad (Bluetooth / USB) ---
  const hwPrev = {};
  const gpBtnMap = {0:"a", 1:"b", 8:"select", 9:"start", 12:"up", 13:"down", 14:"left", 15:"right"};
  function pollHardwareGamepad() {
    const gamepads = navigator.getGamepads ? navigator.getGamepads() : [];
    for (let i = 0; i < gamepads.length; i++) {
      const gp = gamepads[i];
      if (!gp) continue;
      // Axes → analog
      axisX = Math.abs(gp.axes[0]) > 0.15 ? gp.axes[0] : 0;
      axisY = Math.abs(gp.axes[1]) > 0.15 ? gp.axes[1] : 0;
      axisSource = "gamepad";
      // Buttons: only set true on press, only set false on hw release
      for (const [idx, name] of Object.entries(gpBtnMap)) {
        const btn = gp.buttons[idx];
        const pressed = btn ? btn.pressed : false;
        if (pressed) keys[name] = true;
        else if (hwPrev[name]) keys[name] = false;
        hwPrev[name] = pressed;
      }
      return true;
    }
    if (axisSource === "gamepad") axisSource = "none";
    return false;
  }

  function inputUpdate() {
    // Save previous state BEFORE polling so btnp() can detect edges
    for (const k in keys) keysPrev[k] = keys[k];

    const hwGamepad = pollHardwareGamepad();

    // Keyboard → axis (digital: -1/0/+1)
    if (!hwGamepad && axisSource !== "gamepad") {
      axisX = 0; axisY = 0;
      if (keys["left"])  axisX = -1;
      if (keys["right"]) axisX =  1;
      if (keys["up"])    axisY = -1;
      if (keys["down"])  axisY =  1;
    }

    // Axis → btn derivation (analog stick → digital keys)
    if (axisSource === "gamepad") {
      const al = axisX < -0.5, ar = axisX > 0.5, au = axisY < -0.5, ad = axisY > 0.5;
      // Only override if D-pad buttons are not already pressed
      if (!hwPrev["left"]  && !hwPrev["right"]) { keys["left"] = al; keys["right"] = ar; }
      if (!hwPrev["up"]    && !hwPrev["down"])   { keys["up"] = au; keys["down"] = ad; }
    }

    // Select button toggles pause (mirrors spacebar behavior) unless the
    // game has opted out via use_pause(false).
    if (pauseEnabled && keys["select"] && !keysPrev["select"]) paused = !paused;

    // Touch edge flags are cleared here at frame end, after uf() has had
    // one shot at observing them via touchStart() / touchEnd(). endedTouches
    // holds the release snapshot consumed by touch_pos(i) during touch_end();
    // clear it at the same time as the flag so stale data can't leak forward.
    if (touchEndedFlag) endedTouches = [];
    touchStartedFlag = false;
    touchEndedFlag = false;
    swipeDir = swipeDirFlag;
    swipeDirFlag = false;
  }

  // --- Flush buffer to canvas (always screen = surfaces[0]) ---
  let frame = 0;
  // bootTime is captured per engine start so `time()` reads as monotonic
  // seconds since the game booted (and resets along with `frame` when the
  // engine reloads a game via API.stop).
  let bootTime = performance.now();
  function flush() {
    const scr = surfaces[0];
    if (!scr) return;
    imgData.data.set(new Uint8Array(scr.buf32.buffer));
    ctx.putImageData(imgData, 0, 0);
  }
  let flushFn = flush;

  // --- Scene system ---
  // Scene state lives in a single ref object so MonoBindings can mutate
  // sceneRef.pending when Lua calls go(). The engine reads sceneRef.current
  // as the active scene name.
  const sceneRef = { current: null, pending: null };
  let loadedSceneFiles = {};

  // --- Boot ---
  const API = {};
  let _loopId = null;
  let _lua = null;
  let _tickFn = null;
  // Listener refs for clean teardown. Populated by attachListeners inside
  // boot(), drained by detachListeners on suspend/stop.
  let _listeners = [];
  // Created per boot(); invoked by resume() to re-install the same
  // listener bundle onto the document/touchTarget after a suspend.
  let _attachListeners = null;
  // Stored per boot so resume() can re-fit the canvas against the
  // current window size (the user may have resized while suspended).
  let _fitCanvas = null;
  let _suspended = false;

  function detachListeners() {
    for (const { target, type, fn, opts } of _listeners) {
      target.removeEventListener(type, fn, opts);
    }
    _listeners = [];
  }

  API.boot = async (canvasId, opts) => {
    if (!opts || (!opts.game && !opts.source)) return;

    // Stop previous run if any
    if (_loopId) { cancelAnimationFrame(_loopId); _loopId = null; }
    if (_lua) { _lua.global.close(); _lua = null; }
    // Detach any listeners from a prior boot — new boot re-attaches via
    // _attachListeners() below.
    detachListeners();
    _suspended = false;
    _attachListeners = null;
    _fitCanvas = null;
    images = []; imageIdCounter = 0; pendingLoads = [];
    camX = 0; camY = 0; shakeAmount = 0; shakeX = 0; shakeY = 0; sfxStop(); surfaces = [];
    // Reset bootTime at each boot so time() starts near 0 on the very
    // first boot too (not just after an API.stop()). The module-level
    // initializer captures `performance.now()` at script parse time,
    // which would include however long the user took to click play.
    bootTime = performance.now();

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
    const colorBuf = new Uint8Array(W * H);
    surfaces[0] = { w: W, h: H, buf32, colorBuf };

    // Bind to canvas parent to work even when shader replaces canvas with glCanvas
    const touchTarget = canvas.parentNode || canvas;
    let mouseDown = false;

    // All event handlers live in a reinstallable bundle so the engine can
    // cleanly release them on suspend/stop (prevents wasd/zx from being
    // swallowed in editor textareas once the Play tab is left).
    const on = (target, type, fn, evOpts) => {
      target.addEventListener(type, fn, evOpts);
      _listeners.push({ target, type, fn, opts: evOpts });
    };

    // Fit canvas to window now (skip if opts.noAutoFit). The matching
    // resize listener is registered inside _attachListeners so it
    // cleanly detaches/reattaches across suspend/resume. resume() also
    // calls this directly via _fitCanvas to catch window resizes that
    // happened while the engine was suspended.
    function fitCanvas() {
      if (opts.noAutoFit) return;
      const maxW = window.innerWidth - 40;
      const maxH = window.innerHeight - 60;
      const s = Math.min(maxW / W, maxH / H);
      canvas.style.width = (W * s) + "px";
      canvas.style.height = (H * s) + "px";
    }
    _fitCanvas = fitCanvas;
    fitCanvas();

    const isEditableTarget = (el) =>
      !!el && (el.tagName === "INPUT" || el.tagName === "TEXTAREA" ||
               el.isContentEditable === true);

    _attachListeners = function attachListeners() {
      if (!opts.noAutoFit) on(window, "resize", fitCanvas);
      // Input handling (skip if external controller manages input)
      if (!opts.externalInput) {
        on(document, "keydown", (e) => {
          // Never intercept while the user is typing in an editable
          // element — safety net if the engine runs while a form is focused.
          if (isEditableTarget(e.target)) return;
          if (e.key === "1") { debugMode = !debugMode; return; }
          if (e.key === " " && pauseEnabled) { paused = !paused; e.preventDefault(); return; }
          const k = keyMap[e.key] || keyCodeMap[e.keyCode];
          if (k) { keys[k] = true; e.preventDefault(); }
        });
        on(document, "keyup", (e) => {
          if (isEditableTarget(e.target)) return;
          const k = keyMap[e.key] || keyCodeMap[e.keyCode];
          if (k) { keys[k] = false; e.preventDefault(); }
        });
      }

      on(touchTarget, "touchstart", (e) => {
        e.preventDefault();
        const rect = getContentRect();
        let added = 0;
        for (const t of e.changedTouches) {
          if (!isInsideRect(t.clientX, t.clientY, rect)) continue;
          const p = mapToScreenWithRect(t.clientX, t.clientY, rect);
          touches.push({ id: t.identifier, ...p });
          added++;
        }
        if (added === 0) return;
        touchStartedFlag = true;
        if (!swipeAnchor) {
          swipeAnchor = { x: touches[touches.length - added].fx, y: touches[touches.length - added].fy };
        }
      }, { passive: false });

      on(touchTarget, "touchmove", (e) => {
        e.preventDefault();
        for (const t of e.changedTouches) {
          const idx = touches.findIndex(tt => tt.id === t.identifier);
          if (idx >= 0) {
            const p = mapToScreen(t.clientX, t.clientY);
            touches[idx] = { id: t.identifier, ...p };
          }
        }
      }, { passive: false });

      const onTouchEnd = (e) => {
        e.preventDefault();
        // Snapshot release positions BEFORE splice so touch_pos(i) on
        // the touch_end() frame still returns the last coord.
        endedTouches = [];
        for (const t of e.changedTouches) {
          const idx = touches.findIndex(tt => tt.id === t.identifier);
          if (idx >= 0) {
            endedTouches.push({ ...touches[idx] });
            detectSwipe(touches[idx].fx, touches[idx].fy);
            touches.splice(idx, 1);
          }
        }
        touchEndedFlag = true;
        if (touches.length === 0) swipeAnchor = null;
      };
      on(touchTarget, "touchend",    onTouchEnd, { passive: false });
      on(touchTarget, "touchcancel", onTouchEnd, { passive: false });

      on(touchTarget, "mousedown", (e) => {
        const rect = getContentRect();
        if (!isInsideRect(e.clientX, e.clientY, rect)) return;
        const p = mapToScreenWithRect(e.clientX, e.clientY, rect);
        touches = touches.filter(t => t.id !== -1);
        touches.push({ id: -1, ...p });
        mouseDown = true;
        touchStartedFlag = true;
        swipeAnchor = { x: p.fx, y: p.fy };
      });
      on(document, "mousemove", (e) => {
        if (!mouseDown) return;
        const idx = touches.findIndex(t => t.id === -1);
        if (idx >= 0) {
          const p = mapToScreen(e.clientX, e.clientY);
          touches[idx] = { id: -1, ...p };
        }
      });
      on(document, "mouseup", () => {
        if (!mouseDown) return;
        mouseDown = false;
        endedTouches = [];
        const idx = touches.findIndex(t => t.id === -1);
        if (idx >= 0) {
          endedTouches.push({ ...touches[idx] });
          detectSwipe(touches[idx].fx, touches[idx].fy);
          touches.splice(idx, 1);
        }
        touchEndedFlag = true;
        if (touches.length === 0) swipeAnchor = null;
      });
    };
    _attachListeners();

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
    // ALIGN_* constants installed by MonoBindings.bind() below.
    // Drawing functions — first arg is surface id
    /**
     * @lua cls(surface: number, color?: Color): void
     * @group Graphics
     * @desc Clear the surface with the given color. Default 0 (BLACK).
     */
    lua.global.set("cls", (id, c) => { const s = getSurf(id); if (s) cls(s, c); });
    /**
     * @lua pix(surface: number, x: number, y: number, color: Color): void
     * @group Graphics
     * @desc Set a single pixel.
     */
    lua.global.set("pix", (id, x, y, c) => { const s = getSurf(id); if (s) setPix(s, Math.floor(x) - camX, Math.floor(y) - camY, c); });
    lua.global.set("gpix", (id, x, y) => { const s = getSurf(id); return s ? getPix(s, x, y) : 0; });
    /**
     * @lua line(surface: number, x0: number, y0: number, x1: number, y1: number, color: Color): void
     * @group Graphics
     * @desc Draw a line between two points.
     */
    lua.global.set("line", (id, x0, y0, x1, y1, c) => { const s = getSurf(id); if (s) line(s, x0, y0, x1, y1, c); });
    /**
     * @lua rect(surface: number, x: number, y: number, w: number, h: number, color: Color): void
     * @group Graphics
     * @desc Draw a rectangle outline.
     */
    lua.global.set("rect", (id, x, y, w, h, c) => { const s = getSurf(id); if (s) rect(s, x, y, w, h, c); });
    /**
     * @lua rectf(surface: number, x: number, y: number, w: number, h: number, color: Color): void
     * @group Graphics
     * @desc Draw a filled rectangle.
     */
    lua.global.set("rectf", (id, x, y, w, h, c) => { const s = getSurf(id); if (s) rectf(s, x, y, w, h, c); });
    /**
     * @lua circ(surface: number, cx: number, cy: number, r: number, color: Color): void
     * @group Graphics
     * @desc Draw a circle outline (1-pixel stroke).
     */
    lua.global.set("circ", (id, cx, cy, r, c) => { const s = getSurf(id); if (s) circ(s, cx, cy, r, c); });
    /**
     * @lua circf(surface: number, cx: number, cy: number, r: number, color: Color): void
     * @group Graphics
     * @desc Draw a filled circle.
     */
    lua.global.set("circf", (id, cx, cy, r, c) => { const s = getSurf(id); if (s) circf(s, cx, cy, r, c); });
    /**
     * @lua text(surface: number, str: string, x: number, y: number, color: Color, align?: number): void
     * @group Graphics
     * @desc Draw text with the built-in 4×7 pixel font (uppercase, digits, basic punctuation). Optional align is a bit flag (combine ALIGN_HCENTER, ALIGN_RIGHT, ALIGN_VCENTER, ALIGN_CENTER). Not affected by camera.
     */
    lua.global.set("text", (id, str, x, y, c, align) => { const s = getSurf(id); if (s) drawText(s, str, x, y, c, align); });
    lua.global.set("cam", cam);
    lua.global.set("cam_reset", camReset);
    lua.global.set("cam_shake", camShake);
    // _cam_get_x/_y installed by MonoBindings.bind() below.
    // Audio
    /**
     * @lua note(channel: 0 | 1, note: string, duration: number): void
     * @group Sound
     * @desc Play a note on the given channel. note is "C4" / "A#3" / etc. duration in seconds.
     */
    lua.global.set("note", notePlay);
    lua.global.set("tone", tonePlay);
    lua.global.set("noise", noisePlay);
    lua.global.set("wave", waveSet);
    /**
     * @lua sfx_stop(channel?: 0 | 1): void
     * @group Sound
     * @desc Stop a channel. With no argument, stops all channels.
     */
    lua.global.set("sfx_stop", sfxStop);
    /**
     * @lua spr(surface: number, id: number, x: number, y: number): void
     * @group Sprite
     * @desc Draw a registered sprite or loaded image at (x, y). Camera-affected.
     */
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
    // Input primitives (_btn/_btnp/_btnr/_touch_*) + swipe/axis_x/axis_y are
    // installed by MonoBindings.bind() below; hooks below delegate to the
    // engine's own state.

    // Motion sensor APIs (accelerometer + gyroscope)
    lua.global.set("motion_x", () => motionX);     // -1 to 1 (tilt left/right)
    lua.global.set("motion_y", () => motionY);     // -1 to 1 (tilt forward/back)
    lua.global.set("motion_z", () => motionZ);     // -1 to 1 (face up/down)
    lua.global.set("gyro_alpha", () => gyroAlpha); // 0-360 compass heading
    lua.global.set("gyro_beta", () => gyroBeta);   // -180 to 180 front/back tilt
    lua.global.set("gyro_gamma", () => gyroGamma); // -90 to 90 left/right tilt
    lua.global.set("motion_enabled", () => motionEnabled ? 1 : 0);
    /**
     * @lua frame(): number
     * @group Globals
     * @desc Current frame number, starts at 0 and increments by 1 each frame.
     */
    lua.global.set("frame", () => frame);
    // use_pause(true)  — engine auto-pauses on SELECT (this is the default)
    // use_pause(false) — engine stops auto-pausing; game owns SELECT
    // When opted out, the game must read btnp("select") itself and provide
    // its own pause if desired. Any active pause state is cleared.
    lua.global.set("use_pause", (v) => { pauseEnabled = !!v; if (!v) paused = false; });
    /**
     * @lua time(): number
     * @group Globals
     * @desc Elapsed seconds since the game booted. Returns a **float** (sub-frame resolution). For random seeding in Lua 5.4, wrap it: `math.randomseed(math.floor(time() * 1000))` — passing the raw float fails with "number has no integer representation".
     */
    lua.global.set("time", () => (performance.now() - bootTime) / 1000);
    // date() — current wall-clock as an os.date("*t")-shaped table, plus ms.
    lua.global.set("date", () => {
      const d = new Date();
      // yday: compute via UTC-based calendar day diff so DST transitions
      // (23h or 25h local days) don't shift the result by ±1.
      const yearStart = Date.UTC(d.getFullYear(), 0, 0);
      const today     = Date.UTC(d.getFullYear(), d.getMonth(), d.getDate());
      return {
        year:  d.getFullYear(),
        month: d.getMonth() + 1,
        day:   d.getDate(),
        hour:  d.getHours(),
        min:   d.getMinutes(),
        sec:   d.getSeconds(),
        wday:  d.getDay() + 1,   // 1 = Sunday, matching stock Lua os.date
        yday:  Math.floor((today - yearStart) / 86400000),
        ms:    d.getMilliseconds(),
      };
    });
    /**
     * @lua print(...): void
     * @group Util
     * @desc Logs values to the host console (prefixed with [Lua]). Useful during development. On platforms without a visible console (e.g. mobile builds) this is a no-op for end users.
     */
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

    // Lua wrappers (btn/btnp/btnr/touch/touch_*/cam_get) installed by
    // MonoBindings.bind() below.

    // --- Scene system ---
    sceneRef.current = null;
    sceneRef.pending = null;
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
      sceneRef.current = name;
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

    // go() / scene_name() registered by MonoBindings.bind() below.

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

    // Preload modules for require() support (browser has no filesystem)
    // 1. Auto-discover from modules.json (generated by build tools)
    if (!opts.modules) {
      try {
        const r = await fetch(gameBase + "modules.json");
        if (r.ok) {
          const list = await r.json();
          if (Array.isArray(list)) {
            opts.modules = {};
            const fetches = list.map(async (f) => {
              const src = await readFile(f);
              if (src !== null) opts.modules[f] = src;
            });
            await Promise.all(fetches);
          }
        }
      } catch (e) { if (e instanceof SyntaxError) console.warn("modules.json parse error:", e); }
    }
    // 2. Install the shared Lua API surface via MonoBindings. This owns
    //    input primitives + Lua wrappers + package.preload + go/scene_name
    //    + ALIGN_* constants so the browser runtime, the CLI test runner,
    //    and the Web Worker smoke test stay in lockstep.
    const Bindings = (typeof globalThis !== "undefined" && globalThis.MonoBindings)
                  || (typeof window !== "undefined" && window.MonoBindings);
    if (!Bindings) {
      showError("MonoBindings not loaded. Include <script src=\"/runtime/engine-bindings.js\"> before engine.js.");
      return;
    }
    // ── Save backend resolution ──
    // Two paths:
    //   1. Runner supplied a pre-built hook (`opts.save = { backend, cartId }`)
    //      — we use it verbatim. This is how dev/headless/mono-runner.js
    //      injects MemoryBackend, and how play.html / editor inject
    //      CloudBackend when a Firebase user is signed in.
    //   2. Runner only supplied opts.cartId / opts.saveBackend — engine
    //      builds a default WebBackend (persistent) or MemoryBackend.
    let saveHook;
    if (opts.save && opts.save.backend && typeof opts.save.cartId === "string" && opts.save.cartId) {
      saveHook = opts.save;
    } else {
      const SaveLib = (typeof globalThis !== "undefined" && globalThis.MonoSave)
                   || (typeof window !== "undefined" && window.MonoSave);
      if (!SaveLib) {
        showError("MonoSave not loaded. Include <script src=\"/runtime/save.js\"> before engine.js.");
        return;
      }
      const _cartId = opts.cartId || ("anon:" + Math.random().toString(36).slice(2, 10));
      const _requested = opts.saveBackend || (opts.cartId ? "persistent" : "memory");
      if (_requested === "persistent" && !opts.cartId) {
        throw new Error("Mono.boot: saveBackend=\"persistent\" requires opts.cartId");
      }
      saveHook = {
        backend: (_requested === "memory") ? new SaveLib.MemoryBackend() : new SaveLib.WebBackend(),
        cartId: _cartId,
      };
    }
    await Bindings.bind(lua, {
      input: {
        btn:        (k) => !!keys[k],
        btnp:       (k) => !!(keys[k] && !keysPrev[k]),
        btnr:       (k) => !!(!keys[k] && keysPrev[k]),
        touch:      () => touches.length > 0,
        // touch_start/touch_end are edge-triggered: true for exactly one update
        // frame, beginning on the frame the event was dispatched. The previous
        // `state || flag` form caused a 2-frame visibility bleed that could leak
        // an event into a scene activated via go() on the same frame.
        touchStart: () => touchStartedFlag,
        touchEnd:   () => touchEndedFlag,
        touchCount: () => touches.length || (touchEndedFlag ? endedTouches.length : 0),
        // While touch_end() is true (one frame), fall back to the release
        // snapshot so `if touch_end() then local x, y = touch_pos(1) end`
        // returns the lift coordinates instead of false.
        touchPosX:  (i) => { const t = touches[(i || 1) - 1] || (touchEndedFlag ? endedTouches[(i || 1) - 1] : null); return t ? t.x  : false; },
        touchPosY:  (i) => { const t = touches[(i || 1) - 1] || (touchEndedFlag ? endedTouches[(i || 1) - 1] : null); return t ? t.y  : false; },
        touchPosfX: (i) => { const t = touches[(i || 1) - 1] || (touchEndedFlag ? endedTouches[(i || 1) - 1] : null); return t ? t.fx : false; },
        touchPosfY: (i) => { const t = touches[(i || 1) - 1] || (touchEndedFlag ? endedTouches[(i || 1) - 1] : null); return t ? t.fy : false; },
        swipe: () => swipeDir || false,
        axisX: () => axisX,
        axisY: () => axisY,
      },
      cam: { getX: () => camX, getY: () => camY },
      scene: sceneRef,
      modules: opts.modules || {},
      save: saveHook,
    });

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
    API._internal = { canvas, ctx, palette, imgData, W, H, surfaces };

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
    if (sceneRef.pending) {
      const name = sceneRef.pending;
      sceneRef.pending = null;
      await activateScene(name);
    }

    // Game loop (async setTimeout chain for scene loading support)
    function stopWithError(msg) { showError(msg); cancelAnimationFrame(_loopId); _loopId = null; }
    API._showError = (msg) => { stopWithError(msg); };

    let accumulator = 0;
    let lastTimestamp = performance.now();

    async function tick() {
      const now = performance.now();
      const dt = now - lastTimestamp;
      lastTimestamp = now;
      accumulator = Math.min(accumulator + dt, FRAME_MS * 10); // cap to avoid freeze after tab background

      // Process pending scene transition
      if (sceneRef.pending) {
        const name = sceneRef.pending;
        sceneRef.pending = null;
        await activateScene(name);
      }

      // Fixed timestep update (30fps logic)
      let updated = false;
      while (accumulator >= FRAME_MS) {
        accumulator -= FRAME_MS;
        if (!paused) {
          const uf = sceneObj ? sceneObj.update : lua.global.get(sceneRef.current ? (sceneRef.current.includes("/") ? sceneRef.current.split("/").pop() : sceneRef.current) + "_update" : "_update");
          if (uf) try { uf(); } catch (e) { stopWithError((sceneRef.current || "") + " update: " + (e.message || e)); return; }
        }
        frame++;
        inputUpdate();
        updated = true;
      }

      // Render every frame (uncapped)
      // Apply camera shake (save/restore so cam_get() stays clean)
      if (shakeAmount > 0.5) {
        shakeX = Math.floor((Math.random() - 0.5) * shakeAmount * 2);
        shakeY = Math.floor((Math.random() - 0.5) * shakeAmount * 2);
        shakeAmount *= 0.9;
      } else { shakeAmount = 0; shakeX = 0; shakeY = 0; }
      camX += shakeX; camY += shakeY;
      {
        const df = sceneObj ? sceneObj.draw : lua.global.get(sceneRef.current ? (sceneRef.current.includes("/") ? sceneRef.current.split("/").pop() : sceneRef.current) + "_draw" : "_draw");
        if (df) try { df(); } catch (e) { camX -= shakeX; camY -= shakeY; stopWithError((sceneRef.current || "") + " draw: " + (e.message || e)); return; }
      }
      camX -= shakeX; camY -= shakeY;
      if (paused) {
        const scr = surfaces[0];
        const maxC = palette.length - 1;
        const label = "PAUSED";
        const tw = label.length * (FONT_W + 1) - 1;
        const pad = 6;
        const pw = tw + pad * 2, ph = FONT_H + pad * 2;
        const px = Math.floor((W - pw) / 2), py = Math.floor((H - ph) / 2);
        const savedCamX = camX, savedCamY = camY; camX = 0; camY = 0;
        rectf(scr, px, py, pw, ph, 0);
        rect(scr, px, py, pw, ph, maxC);
        if (Math.floor(Date.now() / 500) % 2 === 0) {
          drawText(scr, label, px + pad, py + pad, maxC);
        }
        camX = savedCamX; camY = savedCamY;
      }
      flushFn();
      _loopId = requestAnimationFrame(tick);
    }
    _tickFn = tick;
    _loopId = requestAnimationFrame(tick);
    requestWakeLock();
  };

  API.suspend = () => {
    if (_loopId) { cancelAnimationFrame(_loopId); _loopId = null; }
    sfxStop();
    releaseWakeLock();
  };

  API.resume = () => {
    if (!_loopId && _tickFn && _lua) { _tickFn(); requestWakeLock(); }
  };

  API.stop = () => {
    if (_loopId) { cancelAnimationFrame(_loopId); _loopId = null; }
    _tickFn = null;
    _attachListeners = null;
    _fitCanvas = null;
    _suspended = false;
    detachListeners();
    releaseWakeLock();
    if (_lua) { _lua.global.close(); _lua = null; }
    paused = false;
    pauseEnabled = true;
    frame = 0;
    bootTime = performance.now();
    images = []; imageIdCounter = 0; pendingLoads = [];
    camX = 0; camY = 0; shakeAmount = 0; shakeX = 0; shakeY = 0; sfxStop(); surfaces = [];
    touches = []; endedTouches = []; touchStarted = false; touchEnded = false; touchStartedFlag = false; touchEndedFlag = false;
    swipeDir = false; swipeDirFlag = false; swipeAnchor = null;
    sceneRef.current = null; sceneRef.pending = null; loadedSceneFiles = {};
  };

  // Pause the running game without tearing down Lua/surfaces. Frees the
  // global DOM listeners (so wasd/zx work in editor textareas) and halts
  // the render loop. Cheap to call repeatedly — no-op if not running or
  // already suspended.
  API.suspend = () => {
    if (_suspended || !_loopId) return;
    _suspended = true;
    cancelAnimationFrame(_loopId);
    _loopId = null;
    detachListeners();
    // Silence any in-flight audio — Web Audio oscillators have their own
    // timeline and would keep ringing otherwise while the render loop
    // is halted.
    sfxStop();
    // Clear any held input so nothing "sticks" across the gap — mirrors
    // the full reset list in API.stop() so suspend and stop leave input
    // state equivalently idle.
    for (const k in keys) { keys[k] = false; keysPrev[k] = false; }
    axisX = 0; axisY = 0;
    touches = []; endedTouches = []; touchStarted = false; touchEnded = false;
    touchStartedFlag = false; touchEndedFlag = false;
    swipeDir = false; swipeDirFlag = false; swipeAnchor = null;
    releaseWakeLock();
  };

  // Resume a previously suspended game. Reattaches listeners and
  // restarts the RAF loop; assumes Lua state + surfaces are intact.
  API.resume = () => {
    if (!_suspended) return;
    _suspended = false;
    if (_attachListeners) _attachListeners();
    // Catch any window resize that happened while suspended — the
    // resize listener was detached so CSS sizing may be stale.
    if (_fitCanvas) _fitCanvas();
    requestWakeLock();
    if (_tickFn) {
      _loopId = requestAnimationFrame(_tickFn);
    } else {
      console.warn("Mono.resume: no tick function — game was not fully booted before suspend; skipping RAF restart.");
    }
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
