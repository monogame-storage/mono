/**
 * Mono Console Gamepad — self-contained virtual gamepad module.
 *
 * Usage: <div id="gamepad" data-gamepad-mode="event"></div>
 * The module generates all DOM + CSS inside the container.
 *
 * D-pad: anchor-based analog input (works outside bounds).
 * Modes: "event" (KeyboardEvent) | "setKey" (Mono.setKey)
 * Axis: calls Mono.setAxis(x, y) if available.
 */
(() => {
  "use strict";

  const DRAG_RANGE = 40;
  const DEADZONE_PX = 6;

  // --- Inject CSS ---
  const style = document.createElement("style");
  style.textContent = `
    .mono-gp { display:flex; flex-direction:column; gap:20px; }
    .mono-gp-meta { display:flex; justify-content:center; gap:50px; align-items:center; }
    .mono-gp-meta button {
      background:#444; border:none; border-radius:8px; color:#777;
      font:700 7px/16px monospace; letter-spacing:0.5px; padding:0 16px;
      cursor:pointer; -webkit-tap-highlight-color:transparent;
    }
    .mono-gp-meta button:active, .mono-gp-meta button.pressed { background:#666; color:#fff; }
    .mono-gp-row { display:flex; justify-content:space-between; align-items:center; }
    .mono-dpad {
      width:130px; height:130px; position:relative; flex-shrink:0;
    }
    .mono-dpad-btn {
      position:absolute; width:44px; height:44px; background:#444; border:none;
      border-radius:4px; color:#999; font-size:18px; cursor:pointer;
      display:flex; align-items:center; justify-content:center;
      -webkit-tap-highlight-color:transparent;
    }
    .mono-dpad-btn.pressed { background:#666; color:#fff; }
    .mono-dpad-up    { left:43px; top:0; }
    .mono-dpad-down  { left:43px; top:86px; }
    .mono-dpad-left  { left:0; top:43px; }
    .mono-dpad-right { left:86px; top:43px; }
    .mono-dpad-center { position:absolute; left:43px; top:43px; width:44px; height:44px; background:#444; }
    .mono-ab { width:130px; height:100px; position:relative; flex-shrink:0; }
    .mono-ab-btn {
      position:absolute; width:56px; height:56px; border-radius:50%;
      background:#f07070; border:none; color:#fff; font:800 20px monospace;
      cursor:pointer; display:flex; align-items:center; justify-content:center;
      -webkit-tap-highlight-color:transparent;
    }
    .mono-ab-btn:active, .mono-ab-btn.pressed { background:#ff9090; }
    .mono-ab .btn-b { left:0; top:44px; }
    .mono-ab .btn-a { left:74px; top:14px; }
  `;
  document.head.appendChild(style);

  // --- Build DOM ---
  function buildUI(container) {
    container.innerHTML = `
      <div class="mono-gp">
        <div class="mono-gp-meta">
          <button data-key=" ">SELECT</button>
          <button data-key="Enter">START</button>
        </div>
        <div class="mono-gp-row">
          <div class="mono-dpad dpad">
            <button class="mono-dpad-btn mono-dpad-up dpad-up" data-key="ArrowUp">\u25B2</button>
            <button class="mono-dpad-btn mono-dpad-down dpad-down" data-key="ArrowDown">\u25BC</button>
            <button class="mono-dpad-btn mono-dpad-left dpad-left" data-key="ArrowLeft">\u25C0</button>
            <button class="mono-dpad-btn mono-dpad-right dpad-right" data-key="ArrowRight">\u25B6</button>
            <div class="mono-dpad-center"></div>
          </div>
          <div class="mono-ab">
            <button class="mono-ab-btn btn-b" data-key="x">B</button>
            <button class="mono-ab-btn btn-a" data-key="z">A</button>
          </div>
        </div>
      </div>
    `;
  }

  // --- Input logic ---
  function detectMode(el) {
    let node = el;
    while (node) {
      if (node.dataset && node.dataset.gamepadMode) return node.dataset.gamepadMode;
      node = node.parentElement;
    }
    return "setKey";
  }

  function getKeyName(key) {
    return (typeof Mono !== "undefined" && Mono.keyMap && Mono.keyMap[key]) || key;
  }

  function press(mode, key, down) {
    if (mode === "event") {
      document.dispatchEvent(new KeyboardEvent(down ? "keydown" : "keyup", { key, bubbles: true }));
    } else {
      if (typeof Mono !== "undefined" && Mono.setKey) Mono.setKey(getKeyName(key), down);
    }
  }

  // --- D-pad ---
  const KEY_MAP = { up: "ArrowUp", down: "ArrowDown", left: "ArrowLeft", right: "ArrowRight" };
  const BTN_CLASS = {
    ArrowUp: ".dpad-up", ArrowDown: ".dpad-down",
    ArrowLeft: ".dpad-left", ArrowRight: ".dpad-right"
  };

  function setupDpad(dpad) {
    const mode = detectMode(dpad);
    let anchor = null;
    let activeKeys = new Set();
    let mouseDown = false;

    function clamp(v, min, max) { return Math.max(min, Math.min(max, v)); }

    function updateFromDelta(dx, dy) {
      const dist = Math.sqrt(dx * dx + dy * dy);
      let ax = 0, ay = 0;
      if (dist > DEADZONE_PX) {
        ax = clamp(dx / DRAG_RANGE, -1, 1);
        ay = clamp(dy / DRAG_RANGE, -1, 1);
      }
      if (typeof Mono !== "undefined" && Mono.setAxis) Mono.setAxis(ax, ay);

      const newKeys = new Set();
      if (ay < -0.2) newKeys.add(KEY_MAP.up);
      if (ay >  0.2) newKeys.add(KEY_MAP.down);
      if (ax < -0.2) newKeys.add(KEY_MAP.left);
      if (ax >  0.2) newKeys.add(KEY_MAP.right);

      for (const key of activeKeys) {
        if (!newKeys.has(key)) {
          press(mode, key, false);
          const b = dpad.querySelector(BTN_CLASS[key]);
          if (b) b.classList.remove("pressed");
        }
      }
      for (const key of newKeys) {
        if (!activeKeys.has(key)) {
          press(mode, key, true);
          const b = dpad.querySelector(BTN_CLASS[key]);
          if (b) b.classList.add("pressed");
        }
      }
      activeKeys = newKeys;
    }

    function releaseAll() {
      for (const key of activeKeys) {
        press(mode, key, false);
        const b = dpad.querySelector(BTN_CLASS[key]);
        if (b) b.classList.remove("pressed");
      }
      activeKeys = new Set();
      anchor = null;
      if (typeof Mono !== "undefined" && Mono.clearAxis) Mono.clearAxis();
    }

    function startInput(clientX, clientY) {
      // Anchor = dpad center (so initial touch position gives immediate direction)
      const rect = dpad.getBoundingClientRect();
      anchor = { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 };
      updateFromDelta(clientX - anchor.x, clientY - anchor.y);
    }

    let dpadTouchId = null;
    dpad.addEventListener("touchstart", (e) => {
      e.preventDefault();
      const t = e.changedTouches[0];
      dpadTouchId = t.identifier;
      startInput(t.clientX, t.clientY);
    }, {passive: false});
    document.addEventListener("touchmove", (e) => {
      if (dpadTouchId == null) return;
      for (let i = 0; i < e.touches.length; i++) {
        if (e.touches[i].identifier === dpadTouchId) {
          updateFromDelta(e.touches[i].clientX - anchor.x, e.touches[i].clientY - anchor.y);
          return;
        }
      }
    }, {passive: false});
    document.addEventListener("touchend", (e) => {
      if (dpadTouchId == null) return;
      for (let i = 0; i < e.changedTouches.length; i++) {
        if (e.changedTouches[i].identifier === dpadTouchId) {
          dpadTouchId = null;
          releaseAll();
          return;
        }
      }
    });
    document.addEventListener("touchcancel", (e) => {
      if (dpadTouchId == null) return;
      for (let i = 0; i < e.changedTouches.length; i++) {
        if (e.changedTouches[i].identifier === dpadTouchId) {
          dpadTouchId = null;
          releaseAll();
          return;
        }
      }
    });

    dpad.addEventListener("mousedown", (e) => { e.preventDefault(); mouseDown = true; startInput(e.clientX, e.clientY); });
    document.addEventListener("mousemove", (e) => { if (mouseDown && anchor) updateFromDelta(e.clientX - anchor.x, e.clientY - anchor.y); });
    document.addEventListener("mouseup", () => { if (mouseDown) { mouseDown = false; releaseAll(); } });
  }

  // --- Button setup ---
  function setupButtons(container) {
    container.querySelectorAll("[data-key]:not(.mono-dpad-btn)").forEach(btn => {
      const key = btn.dataset.key;
      const mode = detectMode(btn);
      function down(e) { e.preventDefault(); press(mode, key, true); btn.classList.add("pressed"); }
      function up(e) { if (e) e.preventDefault(); press(mode, key, false); btn.classList.remove("pressed"); }
      btn.addEventListener("mousedown", down);
      btn.addEventListener("mouseup", up);
      btn.addEventListener("mouseleave", up);
      btn.addEventListener("touchstart", down, {passive: false});
      btn.addEventListener("touchend", up, {passive: false});
      btn.addEventListener("touchcancel", up);
    });
  }

  // --- Init ---
  function init() {
    const containers = document.querySelectorAll("#gamepad, [data-mono-gamepad]");
    containers.forEach(container => {
      buildUI(container);
      container.querySelectorAll(".dpad").forEach(setupDpad);
      setupButtons(container);
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
