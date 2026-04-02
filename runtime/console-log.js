/**
 * Mono Console Log — shared console.log panel module.
 *
 * Expects DOM:
 *   #log-body           — log output container
 *   #btn-clear          — clear button
 *   #btn-copy-log       — copy button (optional)
 *
 * Hooks console.log/error to capture [Lua] output.
 */
(() => {
  "use strict";

  const logBody = document.getElementById("log-body");
  if (!logBody) return;

  function logToConsole(msg, cls) {
    const el = document.createElement("div");
    el.className = "log-line" + (cls ? " " + cls : "");
    el.textContent = msg;
    logBody.appendChild(el);
    logBody.scrollTop = logBody.scrollHeight;
  }

  // Clear button
  const clearBtn = document.getElementById("btn-clear");
  if (clearBtn) {
    clearBtn.addEventListener("click", () => { logBody.innerHTML = ""; });
  }

  // Copy button (editor has this, playground may not)
  const copyBtn = document.getElementById("btn-copy-log");
  if (copyBtn) {
    copyBtn.addEventListener("click", () => {
      const text = [...logBody.querySelectorAll(".log-line")].map(el => el.textContent).join("\n");
      navigator.clipboard.writeText(text).then(() => {
        copyBtn.textContent = "copied!";
        setTimeout(() => copyBtn.textContent = "copy", 1500);
      });
    });
  }

  // Hook console for Lua output
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

  // Expose for external use
  window.logToConsole = logToConsole;
})();
