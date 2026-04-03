/**
 * Mono Gamepad — shared virtual gamepad input module.
 *
 * D-pad: supports 8-way input (cardinals + diagonals) via touch/mouse drag.
 *   Uses angle from dpad center to determine direction(s).
 * Other buttons: standard press/release per button.
 *
 * Modes:
 *   "setKey" — calls Mono.setKey(name, bool)  (playground, editor)
 *   "event"  — dispatches KeyboardEvent         (standalone demos)
 *
 * Usage:
 *   <script src="runtime/gamepad.js"></script>
 *   Automatically initializes on DOMContentLoaded.
 *   Set data-gamepad-mode="event" on .dpad parent to use event mode.
 */
(() => {
  "use strict";

  const DEADZONE = 0.18; // fraction of dpad radius

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
    // Walk up to find data-gamepad-mode, default to "setKey"
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

  // --- D-pad with 8-way support ---

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
    let activeKeys = new Set(); // currently pressed direction keys
    let mouseDown = false;

    function getDirections(clientX, clientY) {
      const rect = dpad.getBoundingClientRect();
      // Outside dpad bounds → release all
      if (clientX < rect.left || clientX > rect.right ||
          clientY < rect.top || clientY > rect.bottom) return [];

      const cx = rect.left + rect.width / 2;
      const cy = rect.top + rect.height / 2;
      const radius = Math.min(rect.width, rect.height) / 2;

      const dx = (clientX - cx) / radius;
      const dy = (clientY - cy) / radius;
      const dist = Math.sqrt(dx * dx + dy * dy);

      if (dist < DEADZONE) return [];

      const dirs = [];
      // Use thresholds for 8-way: if component > 0.38 of the unit vector, activate
      const threshold = 0.38;
      if (dy < -threshold) dirs.push(KEY_MAP.up);
      if (dy > threshold)  dirs.push(KEY_MAP.down);
      if (dx < -threshold) dirs.push(KEY_MAP.left);
      if (dx > threshold)  dirs.push(KEY_MAP.right);

      return dirs;
    }

    function updateDpad(clientX, clientY) {
      const dirs = getDirections(clientX, clientY);
      const newKeys = new Set(dirs);

      // Release keys no longer active
      for (const key of activeKeys) {
        if (!newKeys.has(key)) {
          press(mode, key, false);
          const btn = dpad.querySelector(BTN_CLASS[key]);
          if (btn) btn.classList.remove("pressed");
        }
      }
      // Press newly active keys
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
    }

    // Touch
    dpad.addEventListener("touchstart", (e) => {
      e.preventDefault();
      updateDpad(e.touches[0].clientX, e.touches[0].clientY);
    });
    dpad.addEventListener("touchmove", (e) => {
      e.preventDefault();
      updateDpad(e.touches[0].clientX, e.touches[0].clientY);
    });
    dpad.addEventListener("touchend", (e) => { e.preventDefault(); releaseAll(); });
    dpad.addEventListener("touchcancel", (e) => { e.preventDefault(); releaseAll(); });

    // Mouse
    dpad.addEventListener("mousedown", (e) => {
      e.preventDefault();
      mouseDown = true;
      updateDpad(e.clientX, e.clientY);
    });
    document.addEventListener("mousemove", (e) => {
      if (!mouseDown) return;
      updateDpad(e.clientX, e.clientY);
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
