/**
 * Mono Console Screen — shader toggle + scale select module.
 *
 * Usage: <div id="screen-panel"></div>  (or <div id="screen-footer"></div>)
 * Generates: footer with label, scale select, and shader toggle below canvas.
 * Expects canvas#screen to already exist.
 *
 * Options (data attributes on container):
 *   data-no-scale     — hide scale select (editor manages its own)
 *   data-no-footer    — skip footer generation entirely (editor provides HTML)
 */
(() => {
  "use strict";

  const style = document.createElement("style");
  style.textContent = `
    .mono-screen-footer {
      display:flex; align-items:center; padding:2px 4px; width:100%; flex-shrink:0;
    }
    .mono-screen-label { font:8px monospace; color:#3d3d3d; }
    .mono-screen-select {
      margin-left:auto; background:none; border:1px solid #3d3d3d;
      border-radius:3px; color:#3d3d3d; font:7px monospace;
      padding:1px 2px; cursor:pointer; appearance:none; -webkit-appearance:none;
    }
    .mono-screen-select:hover { color:#aaa; border-color:#aaa; }
    .mono-shader-toggle {
      background:none; border:1px solid #3d3d3d;
      border-radius:3px; color:#3d3d3d; font:7px monospace;
      padding:1px 5px; cursor:pointer;
    }
    .mono-shader-toggle:hover { color:#aaa; border-color:#aaa; }
    .mono-shader-toggle.active { color:#00d4aa; border-color:#00d4aa; }
  `;
  document.head.appendChild(style);

  function init() {
    const canvas = document.getElementById("screen");
    if (!canvas) return;

    // Find insertion point: explicit footer container, or fall back to after canvas
    const container = document.getElementById("screen-panel-footer")
      || document.getElementById("screen-panel")
      || document.getElementById("screen-footer");
    if (!container) return;
    // Skip if already has footer content
    if (container.querySelector(".mono-screen-footer")) return;

    const W = 160, H = 120;

    // Build footer
    const footer = document.createElement("div");
    footer.className = "mono-screen-footer";

    const label = document.createElement("span");
    label.className = "mono-screen-label";
    label.textContent = W + "x" + H + " // fit";
    footer.appendChild(label);

    // Scale select
    const select = document.createElement("select");
    select.className = "mono-screen-select";
    ["fit", "1", "2", "3", "4"].forEach(v => {
      const opt = document.createElement("option");
      opt.value = v;
      opt.textContent = v === "fit" ? "fit" : v + "x";
      if (v === "fit") opt.selected = true;
      select.appendChild(opt);
    });
    footer.appendChild(select);

    select.addEventListener("change", () => {
      const val = select.value;
      const glCanvas = canvas.nextElementSibling;
      if (val === "fit") {
        [canvas, glCanvas].forEach(c => { if (c) { c.style.width = ""; c.style.height = ""; }});
        label.textContent = W + "x" + H + " // fit";
      } else {
        const s = parseInt(val);
        const w = W * s + "px", h = H * s + "px";
        [canvas, glCanvas].forEach(c => { if (c) { c.style.width = w; c.style.height = h; }});
        label.textContent = W + "x" + H + " // " + s + "x";
      }
    });

    // Shader toggle
    const btn = document.createElement("button");
    btn.className = "mono-shader-toggle";
    btn.textContent = "SHADER";
    footer.appendChild(btn);

    function syncBtn() {
      if (typeof Mono !== "undefined" && Mono.shader) {
        const isOn = Mono.shader.current().chain.length > 0;
        btn.classList.toggle("active", isOn);
      }
    }

    btn.addEventListener("click", () => {
      if (typeof Mono === "undefined" || !Mono.shader) return;
      const isOn = Mono.shader.current().chain.length > 0;
      if (isOn) Mono.shader.off(); else Mono.shader.preset();
      syncBtn();
    });

    // Sync button when shaders are (re-)initialized by boot
    document.addEventListener("mono:shader-sync", syncBtn);

    // Insert into explicit footer container, or after canvas
    if (container.id === "screen-panel-footer") {
      container.appendChild(footer);
    } else if (canvas.nextSibling) {
      canvas.parentElement.insertBefore(footer, canvas.nextSibling);
    } else {
      canvas.parentElement.appendChild(footer);
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
