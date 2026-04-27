// ── Play Tab: Engine, gamepad, console ──

import { state } from './state.js';
import { showEngineError, clearEngineError } from './editor-ai.js';

// ── Headless test (used by AI tab too) ──

// Back-compat: runHeadlessTest(files, 60) still works; new callers pass
// { frames, inputScript } to simulate taps / button presses and exercise
// code paths that a pure idle loop would miss (e.g. touch_start polling).
export function runHeadlessTest(files, opts = {}) {
  const options = typeof opts === "number" ? { frames: opts } : (opts || {});
  const { frames = 30, inputScript = null } = options;
  return new Promise((resolve) => {
    const w = new Worker("/dev/test-worker.js?v=" + Date.now());
    const timeout = setTimeout(() => { w.terminate(); resolve({ success: false, errors: ["Test timed out"] }); }, 15000);
    w.onmessage = (e) => { clearTimeout(timeout); w.terminate(); resolve(e.data); };
    w.onerror = (e) => { clearTimeout(timeout); w.terminate(); resolve({ success: false, errors: [e.message] }); };
    w.postMessage({ files, frames, inputScript });
  });
}

// Default smoke-test scenario for the agent path: boots + runs a brief
// idle stretch, then simulates a single tap at screen center with a
// touch_start / held / touch_end sequence. Catches most "works until the
// player touches something" runtime errors (missing nil guards, wrong
// touch_pos semantics, scene callbacks that throw on input).
export function defaultSmokeScenario() {
  return {
    frames: 40,
    inputScript: [
      { frame: 10, touchStart: true, touches: [{ x: 80, y: 60 }] },
      { frame: 11, touches: [{ x: 80, y: 60 }] },
      { frame: 12, touches: [{ x: 80, y: 60 }] },
      { frame: 13, touchEnd: true, touches: [{ x: 80, y: 60 }] },
    ],
  };
}

// ── Console log ──

function consolePrint(text, cls = "") {
  const lines = document.getElementById("console-lines");
  if (!lines) return;
  const el = document.createElement("div");
  el.className = "play-console-line" + (cls ? " " + cls : "");
  el.textContent = text;
  lines.appendChild(el);
  lines.scrollTop = lines.scrollHeight;
}

function clearConsole() {
  const lines = document.getElementById("console-lines");
  if (lines) lines.innerHTML = "";
}

// ── Run / Stop ──

export async function runGame() {
  if (state.gameRunning) stopGame();
  clearEngineError();
  const mainFile = state.currentFiles.find(f => f.name === "main.lua");
  if (!mainFile) return;

  const fileMap = {};
  for (const f of state.currentFiles) fileMap[f.name] = f.content;

  state.gameRunning = true;
  consolePrint("[engine] running...", "success");

  // Patch console.error to catch engine errors
  window._origConsoleError = console.error;
  const origConsoleError = console.error;
  console.error = (...args) => {
    const msg = args.join(" ");
    if (msg.startsWith("Mono:")) {
      const errMsg = msg.slice(6);
      setTimeout(() => showEngineError(errMsg), 0);
      consolePrint("[error] " + errMsg, "error");
    }
    origConsoleError.apply(console, args);
  };

  // Patch console.log/warn for console output
  window._origConsoleLog = console.log;
  window._origConsoleWarn = console.warn;
  const origLog = console.log;
  const origWarn = console.warn;
  console.log = (...args) => {
    const msg = args.join(" ");
    if (msg.startsWith("Mono:") || msg.startsWith("[")) {
      consolePrint(msg, "");
    }
    origLog.apply(console, args);
  };
  console.warn = (...args) => {
    const msg = args.join(" ");
    consolePrint("[warn] " + msg, "warn");
    origWarn.apply(console, args);
  };

  const onUnhandled = (e) => {
    if (e.reason?.message) {
      setTimeout(() => showEngineError(e.reason.message), 0);
      consolePrint("[error] " + e.reason.message, "error");
    }
  };
  window.addEventListener("unhandledrejection", onUnhandled, { once: true });

  const moduleMap = {};
  for (const f of state.currentFiles) {
    if (f.name === "main.lua") continue;
    if (f.name.endsWith(".lua")) moduleMap[f.name] = f.content;
  }

  Mono.boot("editor-screen", {
    source: mainFile.content,
    colors: 4,
    noAutoFit: true,
    readFile: async (name) => fileMap[name] || "",
    modules: moduleMap,
    assets: state.currentAssets,
  }).then(() => {
    // Apply shader config after engine is ready
    applyShaderConfig();
  }).catch((e) => {
    showEngineError(e.message || String(e));
    consolePrint("[error] " + (e.message || String(e)), "error");
    stopGame();
  });
}

export function stopGame() {
  if (!state.gameRunning) return;
  try { if (Mono.shader) Mono.shader.off(); } catch {}
  try { Mono.stop(); } catch {}
  state.gameRunning = false;
  state._shaderEnabled = false;
  // Restore patched console methods
  if (window._origConsoleError) {
    console.error = window._origConsoleError;
    window._origConsoleError = null;
  }
  if (window._origConsoleLog) {
    console.log = window._origConsoleLog;
    window._origConsoleLog = null;
  }
  if (window._origConsoleWarn) {
    console.warn = window._origConsoleWarn;
    window._origConsoleWarn = null;
  }
}

// ── Shader support ──

function applyShaderConfig() {
  if (typeof Mono === "undefined" || !Mono.shader) return;
  const shaderFile = state.currentFiles.find(f => f.name === "shader.json");
  if (!shaderFile) {
    // No shader.json → use preset
    Mono.shader.preset();
    state._shaderEnabled = true;
    consolePrint("[shader] preset applied (tint + lcd)", "success");
    return;
  }
  try {
    const config = JSON.parse(shaderFile.content);
    // config format: { "chain": ["tint","lcd3d"], "params": { "tint": { "tint": [1,0.75,0.3] } } }
    if (config.chain && Array.isArray(config.chain)) {
      Mono.shader.off();
      for (const name of config.chain) {
        const params = config.params?.[name];
        Mono.shader.enable(name, params || undefined);
      }
      Mono.shader.order(config.chain);
      state._shaderEnabled = true;
      consolePrint("[shader] " + config.chain.join(" → "), "success");
    }
  } catch (e) {
    consolePrint("[shader] invalid shader.json: " + e.message, "warn");
  }
}

function toggleShader() {
  if (typeof Mono === "undefined" || !Mono.shader) return;
  if (state._shaderEnabled) {
    Mono.shader.off();
    state._shaderEnabled = false;
    consolePrint("[shader] off", "");
  } else {
    applyShaderConfig();
  }
  // Update button visual
  const btn = document.getElementById("btn-shader");
  if (btn) btn.classList.toggle("active-toggle", state._shaderEnabled);
}

// ── Screen Scale (auto-fit to stage) ──

export function buildScaleOptions() { /* no-op: auto-fit only */ }
export function applyScale() { /* no-op: fixed 320x240 per design */ }

// ── Gamepad ──

function setupDpad() {
  const dpad = document.getElementById("gp-dpad");
  if (!dpad) return;
  const DEADZONE_PX = 6;
  let anchor = null, cellHalf = 0, dragRange = 0;
  let activeKeys = new Set();
  let dpadTouchId = null;
  let mouseDown = false;

  function clamp(v, min, max) { return Math.max(min, Math.min(max, v)); }

  function updateFromDelta(dx, dy) {
    const dist = Math.sqrt(dx * dx + dy * dy);
    let ax = 0, ay = 0;
    if (dist > DEADZONE_PX) {
      ax = clamp(dx / dragRange, -1, 1);
      ay = clamp(dy / dragRange, -1, 1);
    }
    if (typeof Mono !== "undefined" && Mono.setAxis) Mono.setAxis(ax, ay);

    const newKeys = new Set();
    if (dist > DEADZONE_PX) {
      if (dy < -cellHalf) newKeys.add("up");
      if (dy > cellHalf) newKeys.add("down");
      if (dx < -cellHalf) newKeys.add("left");
      if (dx > cellHalf) newKeys.add("right");
    }

    for (const key of activeKeys) {
      if (!newKeys.has(key) && typeof Mono !== "undefined" && Mono.setKey) Mono.setKey(key, false);
    }
    for (const key of newKeys) {
      if (!activeKeys.has(key) && typeof Mono !== "undefined" && Mono.setKey) Mono.setKey(key, true);
    }
    activeKeys = newKeys;
  }

  function releaseAll() {
    for (const key of activeKeys) {
      if (typeof Mono !== "undefined" && Mono.setKey) Mono.setKey(key, false);
    }
    activeKeys = new Set();
    anchor = null;
    if (typeof Mono !== "undefined" && Mono.clearAxis) Mono.clearAxis();
  }

  function startInput(clientX, clientY) {
    const rect = dpad.getBoundingClientRect();
    anchor = { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 };
    cellHalf = rect.width / 6;
    dragRange = rect.width / 3;
    updateFromDelta(clientX - anchor.x, clientY - anchor.y);
  }

  dpad.addEventListener("touchstart", (e) => {
    e.preventDefault();
    const t = e.changedTouches[0];
    dpadTouchId = t.identifier;
    startInput(t.clientX, t.clientY);
  }, { passive: false });
  document.addEventListener("touchmove", (e) => {
    if (dpadTouchId == null || !anchor) return;
    for (let i = 0; i < e.touches.length; i++) {
      if (e.touches[i].identifier === dpadTouchId) {
        updateFromDelta(e.touches[i].clientX - anchor.x, e.touches[i].clientY - anchor.y);
        return;
      }
    }
  }, { passive: false });
  document.addEventListener("touchend", (e) => {
    if (dpadTouchId == null) return;
    for (let i = 0; i < e.changedTouches.length; i++) {
      if (e.changedTouches[i].identifier === dpadTouchId) { dpadTouchId = null; releaseAll(); return; }
    }
  });
  document.addEventListener("touchcancel", (e) => {
    if (dpadTouchId == null) return;
    for (let i = 0; i < e.changedTouches.length; i++) {
      if (e.changedTouches[i].identifier === dpadTouchId) { dpadTouchId = null; releaseAll(); return; }
    }
  });
  dpad.addEventListener("mousedown", (e) => { e.preventDefault(); mouseDown = true; startInput(e.clientX, e.clientY); });
  document.addEventListener("mousemove", (e) => { if (mouseDown && anchor) updateFromDelta(e.clientX - anchor.x, e.clientY - anchor.y); });
  document.addEventListener("mouseup", () => { if (mouseDown) { mouseDown = false; releaseAll(); } });
}

function setupButtons() {
  document.querySelectorAll("[data-key]").forEach(btn => {
    if (btn.closest(".play-dpad")) return; // skip dpad zone buttons
    const key = btn.dataset.key;
    btn.style.touchAction = "none";
    btn.style.userSelect = "none";

    function down(e) { e.preventDefault(); if (typeof Mono !== "undefined" && Mono.setKey) Mono.setKey(key, true); btn.classList.add("pressed"); }
    function up(e) { if (e) e.preventDefault(); if (typeof Mono !== "undefined" && Mono.setKey) Mono.setKey(key, false); btn.classList.remove("pressed"); }

    btn.addEventListener("mousedown", down);
    btn.addEventListener("mouseup", up);
    btn.addEventListener("mouseleave", up);
    btn.addEventListener("touchstart", down, { passive: false });
    btn.addEventListener("touchend", up, { passive: false });
    btn.addEventListener("touchcancel", up);
  });
}

// ── Topbar handlers (re-called when tab switches) ──

function initPlayTopbarHandlers() {
  const resetBtn = document.getElementById("btn-reset");
  if (resetBtn) {
    resetBtn.addEventListener("click", () => {
      stopGame();
      clearConsole();
      runGame();
    });
  }
  const shaderBtn = document.getElementById("btn-shader");
  if (shaderBtn) {
    shaderBtn.addEventListener("click", toggleShader);
  }
}

// ── Init ──

export function initEditorPlay() {
  // Expose for dynamic topbar rebuild and tab auto-run
  window._editorPlay = { initPlayTopbarHandlers, runGame };

  // Console clear button
  document.getElementById("btn-console-clear").addEventListener("click", clearConsole);

  // D-pad + buttons
  setupDpad();
  setupButtons();
}
