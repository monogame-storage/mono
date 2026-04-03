/**
 * Mono Console Accel — self-contained accelerometer/tilt module.
 *
 * Usage: <div id="accel-panel"></div>
 * Generates: tilt visualization dot + x/y/z readouts.
 */
(() => {
  "use strict";

  const style = document.createElement("style");
  style.textContent = `
    .mono-accel {
      display:flex; align-items:center; justify-content:center;
      gap:20px; padding:8px 16px;
    }
    .mono-tilt-viz {
      width:80px; height:80px; border-radius:50%;
      background:#2d2d2d; border:1px solid #3d3d3d;
      position:relative; flex-shrink:0;
    }
    .mono-tilt-cross-h, .mono-tilt-cross-v { position:absolute; background:#3d3d3d; }
    .mono-tilt-cross-h { width:100%; height:1px; top:50%; }
    .mono-tilt-cross-v { height:100%; width:1px; left:50%; }
    .mono-tilt-dot {
      position:absolute; width:14px; height:14px; border-radius:50%;
      background:#ff6b35; top:50%; left:50%; transform:translate(-50%,-50%);
    }
    .mono-accel-data { display:flex; flex-direction:column; gap:4px; font:12px monospace; color:#aaa; }
    .mono-accel-data .label { font-size:9px; color:#00d4aa; margin-top:4px; }
  `;
  document.head.appendChild(style);

  function init() {
    const container = document.getElementById("accel-panel");
    if (!container) return;

    container.innerHTML = `
      <div class="mono-accel">
        <div class="mono-tilt-viz">
          <div class="mono-tilt-cross-h"></div>
          <div class="mono-tilt-cross-v"></div>
          <div class="mono-tilt-dot" id="mono-tilt-dot"></div>
        </div>
        <div class="mono-accel-data">
          <span id="mono-accel-x">x:  0.00</span>
          <span id="mono-accel-y">y:  0.00</span>
          <span id="mono-accel-z">z:  0.00</span>
          <span class="label" id="mono-accel-status">tilt: disabled</span>
        </div>
      </div>
    `;

    if (!window.DeviceMotionEvent) return;

    const dot = container.querySelector("#mono-tilt-dot");
    const elX = container.querySelector("#mono-accel-x");
    const elY = container.querySelector("#mono-accel-y");
    const elZ = container.querySelector("#mono-accel-z");
    const elStatus = container.querySelector("#mono-accel-status");

    window.addEventListener("devicemotion", (e) => {
      const a = e.accelerationIncludingGravity;
      if (!a) return;

      if (elX) elX.textContent = "x: " + (a.x || 0).toFixed(2);
      if (elY) elY.textContent = "y: " + (a.y || 0).toFixed(2);
      if (elZ) elZ.textContent = "z: " + (a.z || 0).toFixed(2);
      if (elStatus) elStatus.textContent = "tilt: enabled";

      if (dot) {
        const nx = Math.max(-1, Math.min(1, (a.x || 0) / 9.8));
        const ny = Math.max(-1, Math.min(1, (a.y || 0) / 9.8));
        dot.style.left = (50 + nx * 40) + "%";
        dot.style.top = (50 - ny * 40) + "%";
      }
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
