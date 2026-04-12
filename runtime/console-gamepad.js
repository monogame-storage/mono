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

  const DEADZONE_PX = 6;

  // --- Inject CSS ---
  // All styles use Mono 16-grayscale palette only.
  // Shape/size hints only, no labels or icons: crosshair D-pad, bigger bright A
  // vs smaller dark B, empty pill SELECT/START.
  const style = document.createElement("style");
  style.textContent = `
    .mono-gp { display:flex; flex-direction:column; gap:22px; align-items:center; }
    .mono-gp-row { display:flex; justify-content:space-between; align-items:center; gap:64px; }

    /* SELECT / START — empty pill buttons with outline for visibility on OLED */
    .mono-gp-meta { display:flex; justify-content:center; gap:28px; align-items:center; }
    .mono-gp-meta button {
      background:#333333; border:1px solid #666666; border-radius:11px;
      height:22px; padding:0; font-size:0; color:transparent;
      cursor:pointer; -webkit-tap-highlight-color:transparent;
    }
    .mono-gp-meta button:active, .mono-gp-meta button.pressed { background:#555555; }
    .mono-gp-meta .btn-select { width:64px; }
    .mono-gp-meta .btn-start  { width:60px; }

    /* D-pad — 3x3 grid cross shape with outline (OLED visibility) */
    .mono-dpad { width:150px; height:150px; position:relative; flex-shrink:0; }
    .mono-dpad-btn {
      position:absolute; width:50px; height:50px;
      background:#4a4a4a; border:1px solid #6a6a6a;
      border-radius:6px; color:transparent; font-size:0;
      cursor:pointer; -webkit-tap-highlight-color:transparent;
    }
    .mono-dpad-btn.pressed { background:#6a6a6a; border-color:#888888; }
    .mono-dpad-up    { left:50px;  top:0;     }
    .mono-dpad-down  { left:50px;  top:100px; }
    .mono-dpad-left  { left:0;     top:50px;  }
    .mono-dpad-right { left:100px; top:50px;  }
    .mono-dpad-center {
      position:absolute; left:50px; top:50px; width:50px; height:50px;
      background:#333333; border:1px solid #555555; border-radius:4px;
    }

    /* A/B — B dark/small on left with outline, A bright/bigger top-right */
    .mono-ab { width:148px; height:110px; position:relative; flex-shrink:0; }
    .mono-ab-btn {
      position:absolute; border-radius:50%; border:none;
      color:transparent; font-size:0;
      cursor:pointer; -webkit-tap-highlight-color:transparent;
    }
    .mono-ab .btn-b {
      left:4px; top:44px; width:58px; height:58px;
      background:#4a4a4a; border:1px solid #6a6a6a;
    }
    .mono-ab .btn-b:active, .mono-ab .btn-b.pressed { background:#6a6a6a; border-color:#888888; }
    .mono-ab .btn-a {
      left:82px; top:14px; width:62px; height:62px; background:#eeeeee;
    }
    .mono-ab .btn-a:active, .mono-ab .btn-a.pressed { background:#cccccc; }
  `;
  document.head.appendChild(style);

  // --- Build DOM ---
  function buildUI(container) {
    container.innerHTML = `
      <div class="mono-gp">
        <div class="mono-gp-meta">
          <button tabindex="-1" class="btn-select" data-key=" ">SELECT</button>
          <button tabindex="-1" class="btn-start" data-key="Enter">START</button>
        </div>
        <div class="mono-gp-row">
          <div class="mono-dpad dpad">
            <button tabindex="-1" class="mono-dpad-btn mono-dpad-up dpad-up" data-key="ArrowUp">\u25B2</button>
            <button tabindex="-1" class="mono-dpad-btn mono-dpad-down dpad-down" data-key="ArrowDown">\u25BC</button>
            <button tabindex="-1" class="mono-dpad-btn mono-dpad-left dpad-left" data-key="ArrowLeft">\u25C0</button>
            <button tabindex="-1" class="mono-dpad-btn mono-dpad-right dpad-right" data-key="ArrowRight">\u25B6</button>
            <div class="mono-dpad-center"></div>
          </div>
          <div class="mono-ab">
            <button tabindex="-1" class="mono-ab-btn btn-b" data-key="x">B</button>
            <button tabindex="-1" class="mono-ab-btn btn-a" data-key="z">A</button>
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
    // Cell-based detection — set on each startInput from actual dpad rect.
    // cellHalf = half of one grid cell (3x3 grid → rect.width / 6).
    // A direction key fires only when the finger is past the center cell on
    // that axis, so while the finger is still within the UP button rect the
    // RIGHT key cannot accidentally fire (and vice versa).
    let cellHalf, dragRange;
    let activeKeys = new Set();
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
        if (dy < -cellHalf) newKeys.add(KEY_MAP.up);
        if (dy >  cellHalf) newKeys.add(KEY_MAP.down);
        if (dx < -cellHalf) newKeys.add(KEY_MAP.left);
        if (dx >  cellHalf) newKeys.add(KEY_MAP.right);
      }

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
      // D-pad is a 3x3 grid. Each cell is rect.width / 3, half is rect.width / 6.
      // This scales with the current dpad size (base 150px or vw-based on Android).
      cellHalf = rect.width / 6;
      // Analog saturates at cardinal button center (one cell from the dpad center).
      dragRange = rect.width / 3;
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
      if (dpadTouchId == null || !anchor) return;
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
