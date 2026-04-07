/**
 * Mono Console Log — self-contained log panel module.
 *
 * Usage: <div id="log-panel"></div>
 * Generates: scrollable log with clear/copy buttons.
 * Hooks console.log/error to capture [Lua] output.
 */
(() => {
  "use strict";

  const style = document.createElement("style");
  style.textContent = `
    .mono-log {
      display:flex; flex-direction:column; background:#212121;
      border-top:1px solid #333; font:11px/1.6 monospace; color:#aaa;
      height:120px; overflow:hidden;
    }
    .mono-log-header {
      display:flex; align-items:center; padding:4px 8px;
      font:10px monospace; color:#777; flex-shrink:0;
    }
    .mono-log-header span { flex:1; }
    .mono-log-header button {
      background:none; border:none; color:#777; font:9px monospace;
      cursor:pointer; margin-left:8px;
    }
    .mono-log-header button:hover { color:#e8e8e8; }
    .mono-log-body {
      flex:1; overflow:auto; padding:4px 8px; min-height:0;
    }
    .mono-log-body .log-line { white-space:pre-wrap; word-break:break-all; user-select:text; -webkit-user-select:text; }
    .mono-log-body .log-error { color:#e66; }
  `;
  document.head.appendChild(style);

  function init() {
    const container = document.getElementById("log-panel");
    if (!container) return;

    container.innerHTML = `
      <div class="mono-log">
        <div class="mono-log-header">
          <span>\u276f_ console.log</span>
          <button id="mono-log-clear">clear</button>
          <button id="mono-log-copy">copy</button>
        </div>
        <div class="mono-log-body" id="log-body"></div>
      </div>
    `;

    const logBody = container.querySelector("#log-body");

    function logToConsole(msg, cls) {
      const el = document.createElement("div");
      el.className = "log-line" + (cls ? " " + cls : "");
      el.textContent = msg;
      logBody.appendChild(el);
      logBody.scrollTop = logBody.scrollHeight;
    }

    container.querySelector("#mono-log-clear").addEventListener("click", () => {
      logBody.innerHTML = "";
    });

    container.querySelector("#mono-log-copy").addEventListener("click", () => {
      const text = [...logBody.querySelectorAll(".log-line")].map(el => el.textContent).join("\n");
      navigator.clipboard.writeText(text).then(() => {
        const btn = container.querySelector("#mono-log-copy");
        btn.textContent = "copied!";
        setTimeout(() => btn.textContent = "copy", 1500);
      });
    });

    // Hook console
    const _origLog = console.log;
    const _origErr = console.error;
    console.log = (...args) => {
      const msg = args.join(" ");
      if (msg.startsWith("[Lua]")) logToConsole(msg.replace("[Lua] ", ""));
      _origLog.apply(console, args);
    };
    console.error = (...args) => {
      logToConsole(args.join(" "), "log-error");
      _origErr.apply(console, args);
    };

    window.logToConsole = logToConsole;
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
