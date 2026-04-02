/**
 * Mono Console Accel — shared accelerometer/tilt module.
 *
 * Expects DOM:
 *   #accel-x/y/z        — accelerometer readouts
 *   #accel-status        — tilt status label
 *   #tilt-dot            — tilt visualization dot
 */
(() => {
  "use strict";

  if (!window.DeviceMotionEvent) return;

  window.addEventListener("devicemotion", (e) => {
    const a = e.accelerationIncludingGravity;
    if (!a) return;

    const elX = document.getElementById("accel-x");
    const elY = document.getElementById("accel-y");
    const elZ = document.getElementById("accel-z");
    const elStatus = document.getElementById("accel-status");
    const dot = document.getElementById("tilt-dot");

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
})();
