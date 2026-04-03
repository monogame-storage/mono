/**
 * Mono Gamepad — shared virtual gamepad input module.
 *
 * D-pad: anchor-based analog input.
 *   Touch/click sets anchor point, drag distance determines axis values.
 *   Works outside D-pad bounds (document-level tracking).
 * Other buttons: standard press/release per button.
 *
 * Modes:
 *   "setKey" — calls Mono.setKey(name, bool)  (playground, editor)
 *   "event"  — dispatches KeyboardEvent         (standalone demos)
 *
 * Axis: always calls Mono.setAxis(x, y) if available.
 */
(() => {
  "use strict";

  const DRAG_RANGE = 40;  // px for full axis = 1.0
  const DEADZONE_PX = 6;

  function init() {
    const dpads = document.querySelectorAll(".dpad");
    dpads.forEach(setupDpad);

    // Non-dpad [data-key] buttons
    document.querySelectorAll("[data-key]:not(.dpad-btn)").forEach(btn => {
      const key = btn.dataset.key;
      const mode = detectMode(btn);

      function down(e) {
        e.preventDefault();
        press(mode, key, true);
        btn.classList.add("pressed");
      }
      function up(e) {
        if (e) e.preventDefault();
        press(mode, key, false);
        btn.classList.remove("pressed");
      }

      btn.addEventListener("mousedown", down);
      btn.addEventListener("mouseup", up);
      btn.addEventListener("mouseleave", up);
      btn.addEventListener("touchstart", down);
      btn.addEventListener("touchend", up);
      btn.addEventListener("touchcancel", up);
    });
  }

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
      if (typeof Mono !== "undefined" && Mono.setKey) {
        Mono.setKey(getKeyName(key), down);
      }
    }
  }

  // --- D-pad button classes ---

  const KEY_MAP = {
    up:    "ArrowUp",
    down:  "ArrowDown",
    left:  "ArrowLeft",
    right: "ArrowRight",
  };

  const BTN_CLASS = {
    ArrowUp:    ".dpad-up",
    ArrowDown:  ".dpad-down",
    ArrowLeft:  ".dpad-left",
    ArrowRight: ".dpad-right",
  };

  function setupDpad(dpad) {
    const mode = detectMode(dpad);
    let anchor = null;       // {x, y} touch start point
    let activeKeys = new Set();
    let mouseDown = false;

    function clamp(v, min, max) { return Math.max(min, Math.min(max, v)); }

    function updateFromDelta(dx, dy) {
      const dist = Math.sqrt(dx * dx + dy * dy);

      // Axis values (float -1..1)
      let ax = 0, ay = 0;
      if (dist > DEADZONE_PX) {
        ax = clamp(dx / DRAG_RANGE, -1, 1);
        ay = clamp(dy / DRAG_RANGE, -1, 1);
      }

      // Send axis to engine
      if (typeof Mono !== "undefined" && Mono.setAxis) {
        Mono.setAxis(ax, ay);
      }

      // Derive digital directions from axis
      const newKeys = new Set();
      if (ay < -0.3) newKeys.add(KEY_MAP.up);
      if (ay >  0.3) newKeys.add(KEY_MAP.down);
      if (ax < -0.3) newKeys.add(KEY_MAP.left);
      if (ax >  0.3) newKeys.add(KEY_MAP.right);

      // Release old, press new
      for (const key of activeKeys) {
        if (!newKeys.has(key)) {
          press(mode, key, false);
          const btn = dpad.querySelector(BTN_CLASS[key]);
          if (btn) btn.classList.remove("pressed");
        }
      }
      for (const key of newKeys) {
        if (!activeKeys.has(key)) {
          press(mode, key, true);
          const btn = dpad.querySelector(BTN_CLASS[key]);
          if (btn) btn.classList.add("pressed");
        }
      }
      activeKeys = newKeys;
    }

    function releaseAll() {
      for (const key of activeKeys) {
        press(mode, key, false);
        const btn = dpad.querySelector(BTN_CLASS[key]);
        if (btn) btn.classList.remove("pressed");
      }
      activeKeys = new Set();
      anchor = null;
      if (typeof Mono !== "undefined" && Mono.clearAxis) Mono.clearAxis();
    }

    // --- Touch ---
    dpad.addEventListener("touchstart", (e) => {
      e.preventDefault();
      const t = e.touches[0];
      anchor = { x: t.clientX, y: t.clientY };
    });
    document.addEventListener("touchmove", (e) => {
      if (!anchor) return;
      const t = e.touches[0];
      updateFromDelta(t.clientX - anchor.x, t.clientY - anchor.y);
    });
    document.addEventListener("touchend", (e) => {
      if (!anchor) return;
      e.preventDefault();
      releaseAll();
    });
    document.addEventListener("touchcancel", () => {
      if (anchor) releaseAll();
    });

    // --- Mouse ---
    dpad.addEventListener("mousedown", (e) => {
      e.preventDefault();
      mouseDown = true;
      anchor = { x: e.clientX, y: e.clientY };
    });
    document.addEventListener("mousemove", (e) => {
      if (!mouseDown || !anchor) return;
      updateFromDelta(e.clientX - anchor.x, e.clientY - anchor.y);
    });
    document.addEventListener("mouseup", () => {
      if (!mouseDown) return;
      mouseDown = false;
      releaseAll();
    });
  }

  // Auto-init
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
