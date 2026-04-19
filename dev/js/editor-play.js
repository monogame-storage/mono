// ── Play Tab: Engine, gamepad, scaling, stats ──

import { state } from './state.js';
import { showEngineError, clearEngineError } from './editor-ai.js';

// ── Headless test (used by AI tab too) ──

export function runHeadlessTest(files, frames = 30) {
  return new Promise((resolve) => {
    const w = new Worker("/dev/test-worker.js");
    const timeout = setTimeout(() => { w.terminate(); resolve({ success: false, errors: ["Test timed out"] }); }, 15000);
    w.onmessage = (e) => { clearTimeout(timeout); w.terminate(); resolve(e.data); };
    w.onerror = (e) => { clearTimeout(timeout); w.terminate(); resolve({ success: false, errors: [e.message] }); };
    w.postMessage({ files, frames });
  });
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
  const runBtn = document.getElementById("btn-run");
  if (runBtn) runBtn.style.background = "#ff4444";
  document.getElementById("console-led").style.background = "#6f6";
  startStatsLoop();

  // Patch console.error to catch engine errors
  window._origConsoleError = console.error;
  const origConsoleError = console.error;
  console.error = (...args) => {
    const msg = args.join(" ");
    if (msg.startsWith("Mono:")) {
      setTimeout(() => showEngineError(msg.slice(6)), 0);
    }
    origConsoleError.apply(console, args);
  };

  const onUnhandled = (e) => {
    if (e.reason?.message) setTimeout(() => showEngineError(e.reason.message), 0);
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
  }).catch((e) => {
    showEngineError(e.message || String(e));
    stopGame();
  });
}

export function stopGame() {
  if (!state.gameRunning) return;
  try { Mono.stop(); } catch {}
  state.gameRunning = false;
  const runBtn = document.getElementById("btn-run");
  if (runBtn) runBtn.style.background = "#333";
  document.getElementById("console-led").style.background = "#2a2a2a";
  stopStatsLoop();
  if (window._origConsoleError) {
    console.error = window._origConsoleError;
    window._origConsoleError = null;
  }
}

// ── Screen Scale ──

export function buildScaleOptions() {
  const sel = document.getElementById("editor-scale");
  if (!sel) return;
  const preview = document.querySelector(".editor-preview");
  if (!preview) return;
  const maxW = preview.clientWidth - 80;
  const maxScale = Math.floor(maxW / 160) || 1;
  sel.innerHTML = "";
  for (let s = 1; s <= maxScale; s++) {
    const opt = document.createElement("option");
    opt.value = String(s);
    opt.textContent = s + "x";
    sel.appendChild(opt);
  }
  const fitOpt = document.createElement("option");
  fitOpt.value = "fit";
  fitOpt.textContent = "Fit";
  sel.appendChild(fitOpt);
  sel.value = maxScale >= 2 ? "2" : "fit";
}

export function applyScale() {
  const sel = document.getElementById("editor-scale");
  if (!sel) return;
  const val = sel.value;
  const canvas = document.getElementById("editor-screen");
  const bezel = document.querySelector(".console-bezel");
  const preview = document.querySelector(".editor-preview");
  if (!preview || !bezel) return;
  const maxW = preview.clientWidth - 80;
  let w, h;
  if (val === "fit") {
    const scale = maxW / 160;
    w = Math.floor(160 * scale);
    h = Math.floor(120 * scale);
  } else {
    const s = parseInt(val);
    w = 160 * s;
    h = 120 * s;
  }
  canvas.style.width = w + "px";
  canvas.style.height = h + "px";
  bezel.style.width = (w + 28) + "px";
}

// ── Stats loop ──

let statsInterval = null;
let statsRafActive = false;
let lastTime = 0;
let renderFrameCount = 0;

function startStatsLoop() {
  renderFrameCount = 0;
  lastTime = performance.now();
  document.querySelectorAll(".console-stat").forEach(s => s.classList.add("active"));

  statsRafActive = true;
  function countFrame() {
    if (!statsRafActive) return;
    renderFrameCount++;
    requestAnimationFrame(countFrame);
  }
  requestAnimationFrame(countFrame);

  statsInterval = setInterval(() => {
    try {
      const now = performance.now();
      const dt = (now - lastTime) / 1000;
      const fps = dt > 0 ? Math.round(renderFrameCount / dt) : 0;
      renderFrameCount = 0;
      lastTime = now;
      document.getElementById("stat-fps").textContent = fps;
      const frame = Mono._getFrame?.() || 0;
      document.getElementById("stat-frame").textContent = frame;
      const scene = Mono._internal?.sceneName;
      document.getElementById("stat-scene").textContent = scene || "--";
      const mem = performance.memory?.usedJSHeapSize;
      document.getElementById("stat-mem").textContent = mem ? (mem / 1048576).toFixed(1) + "M" : "--";
    } catch {}
  }, 1000);
}

function stopStatsLoop() {
  statsRafActive = false;
  if (statsInterval) {
    clearInterval(statsInterval);
    statsInterval = null;
  }
  document.querySelectorAll(".console-stat").forEach(s => s.classList.remove("active"));
  document.getElementById("stat-fps").textContent = "--";
}

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

  dpad.style.touchAction = "none";
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
    if (btn.closest(".gamepad-dpad")) return;
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
  const runBtn = document.getElementById("btn-run");
  if (runBtn) {
    runBtn.addEventListener("click", () => {
      if (state.gameRunning) stopGame();
      else runGame();
    });
  }
  const scaleSelect = document.getElementById("editor-scale");
  if (scaleSelect) {
    scaleSelect.addEventListener("change", applyScale);
    buildScaleOptions();
    applyScale();
  }
}

// ── Init ──

export function initEditorPlay() {
  // Expose for dynamic topbar rebuild
  window._editorPlay = { initPlayTopbarHandlers };

  // Gamepad expand
  document.getElementById("gp-expand").addEventListener("click", () => {
    const panel = document.getElementById("gamepad-panel");
    const btn = document.getElementById("gp-expand");
    const icon = document.querySelector(".gamepad-bar-icon");
    panel.classList.toggle("show");
    icon.style.visibility = panel.classList.contains("show") ? "hidden" : "visible";
    btn.innerHTML = panel.classList.contains("show")
      ? '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><polyline points="18 15 12 9 6 15"/></svg>'
      : '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><polyline points="6 9 12 15 18 9"/></svg>';
  });

  // D-pad + buttons
  setupDpad();
  setupButtons();

  // Resize
  window.addEventListener("resize", () => { buildScaleOptions(); applyScale(); });
}
