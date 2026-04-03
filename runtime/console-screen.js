/**
 * Mono Console Screen — self-contained shader toggle module.
 *
 * Usage: <div id="screen-panel"></div>
 * Generates: shader toggle button below canvas.
 * Expects canvas#screen to already exist (engine creates it).
 */
(() => {
  "use strict";

  const style = document.createElement("style");
  style.textContent = `
    .mono-screen-footer {
      display:flex; align-items:center; padding:2px 4px;
    }
    .mono-screen-label { font:8px monospace; color:#3d3d3d; }
    .mono-shader-toggle {
      margin-left:auto; background:none; border:1px solid #3d3d3d;
      border-radius:3px; color:#3d3d3d; font:7px monospace;
      padding:1px 5px; cursor:pointer;
    }
    .mono-shader-toggle:hover { color:#aaa; border-color:#aaa; }
    .mono-shader-toggle.active { color:#00d4aa; border-color:#00d4aa; }
  `;
  document.head.appendChild(style);

  function init() {
    const container = document.getElementById("screen-panel") || document.getElementById("screen-footer");
    if (!container) return;

    // If container is screen-panel, append footer after canvas
    const canvas = document.getElementById("screen");
    if (!canvas) return;

    const footer = document.createElement("div");
    footer.className = "mono-screen-footer";
    footer.innerHTML = `
      <span class="mono-screen-label">160x144</span>
      <button class="mono-shader-toggle active">SHADER</button>
    `;

    // Insert after canvas
    if (canvas.nextSibling) {
      canvas.parentElement.insertBefore(footer, canvas.nextSibling);
    } else {
      canvas.parentElement.appendChild(footer);
    }

    // Shader toggle
    let shaderOn = true;
    const btn = footer.querySelector(".mono-shader-toggle");
    btn.addEventListener("click", () => {
      shaderOn = !shaderOn;
      btn.classList.toggle("active", shaderOn);
      if (typeof Mono !== "undefined" && Mono.shader) {
        ["tint", "scanlines", "lcd3d", "crt"].forEach(s => {
          if (shaderOn) Mono.shader.enable(s);
          else Mono.shader.disable(s);
        });
      }
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
