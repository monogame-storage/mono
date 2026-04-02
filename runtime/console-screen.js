/**
 * Mono Console Screen — shared shader toggle module.
 *
 * Expects DOM:
 *   #shader-toggle      — shader on/off button
 */
(() => {
  "use strict";

  const shaderBtn = document.getElementById("shader-toggle");
  if (!shaderBtn) return;

  let shaderOn = true;
  shaderBtn.addEventListener("click", () => {
    shaderOn = !shaderOn;
    shaderBtn.classList.toggle("active", shaderOn);
    if (typeof Mono !== "undefined" && Mono.shader) {
      ["tint", "scanlines", "lcd3d", "crt"].forEach(s => {
        if (shaderOn) Mono.shader.enable(s);
        else Mono.shader.disable(s);
      });
    }
  });
})();
