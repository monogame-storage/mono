#!/usr/bin/env node
// Mono Lua REPL MCP server
//
// A minimal stdio-based Model Context Protocol server that lets
// Claude evaluate Lua snippets against the Mono engine and see
// the resulting VRAM state. No external SDK — speaks JSON-RPC
// directly over stdin/stdout per the MCP spec.
//
// Tools exposed:
//   lua_eval  — run a Lua snippet in a full Mono engine context
//   lua_check — same as lua_eval but returns only success/error (no VRAM)
//
// Usage:
//   node server.js        (spawned by Claude Code as an MCP server)

"use strict";

const { spawnSync } = require("child_process");
const path = require("path");
const readline = require("readline");

const REPO_ROOT = path.resolve(__dirname, "../../..");
const TEST_RUNNER = path.join(REPO_ROOT, "editor/templates/mono/mono-test.js");

const SERVER_INFO = {
  name: "mono-lua-repl",
  version: "0.1.0",
};

const PROTOCOL_VERSION = "2024-11-05";

const TOOLS = [
  {
    name: "lua_eval",
    description:
      "Evaluate a Lua snippet against the Mono engine and return the final VRAM state. " +
      "The snippet is wrapped in _init/_start/_draw as needed — include only the body. " +
      "Use for quick API experiments without writing a full demo.",
    inputSchema: {
      type: "object",
      properties: {
        code: {
          type: "string",
          description:
            "Lua source. You can define _init/_start/_update/_draw OR just provide body " +
            "statements (they will be wrapped in a default _draw that runs once).",
        },
        frames: {
          type: "number",
          description: "Number of frames to run. Default: 1",
          default: 1,
        },
        colors: {
          type: "number",
          description: "Color depth: 1, 2, or 4. Default: 4",
          default: 4,
        },
        show: {
          type: "string",
          enum: ["vdump", "hash"],
          description: "How to present the result. vdump = 160×144 hex rows (0-f per pixel). hash = no visual output, just the OK/FAIL status (fastest, use for compile-check style verification). Default: vdump",
          default: "vdump",
        },
      },
      required: ["code"],
    },
  },
  {
    name: "lua_check",
    description:
      "Lightly validate a Lua snippet — runs it for 1 frame and returns OK or the first error. " +
      "Faster than lua_eval when you only need to know if code parses and runs.",
    inputSchema: {
      type: "object",
      properties: {
        code: { type: "string", description: "Lua source" },
      },
      required: ["code"],
    },
  },
];

// --- Lua wrapping: if the snippet doesn't define _draw, wrap it ---
function wrapCode(rawCode) {
  if (/function\s+_?draw\b/.test(rawCode) || /function\s+_draw\b/.test(rawCode)) {
    return rawCode;
  }
  // No _draw — assume the snippet is the body of one draw call
  return `
local scr = screen()
function _init() mode(4) end
function _draw()
  cls(scr, 0)
${rawCode}
end
`;
}

function runLua(code, { frames = 1, colors = 4, show = "vdump" } = {}) {
  const wrapped = wrapCode(code);
  const args = [
    TEST_RUNNER,
    "--source", wrapped,
    "--frames", String(frames),
    "--colors", String(colors),
    "--quiet",
  ];
  if (show === "vdump") args.push("--vdump");
  // "hash" mode runs with no visual output at all. It's the cheapest
  // way to answer "does this snippet compile and run?"; callers only
  // inspect `ok` / `stderr`, never the final VRAM hash (mono-test.js
  // does not emit the hash to stdout in normal runs — only under
  // --determinism, which we don't enable here).

  const result = spawnSync("node", args, { encoding: "utf8" });
  const ok = result.status === 0;
  const stdout = result.stdout || "";
  const stderr = result.stderr || "";
  return { ok, stdout, stderr };
}

// --- JSON-RPC handlers ---
function handleInitialize() {
  return {
    protocolVersion: PROTOCOL_VERSION,
    capabilities: { tools: {} },
    serverInfo: SERVER_INFO,
  };
}

function handleToolsList() {
  return { tools: TOOLS };
}

function handleToolsCall(params) {
  const name = params?.name;
  const args = params?.arguments || {};
  if (name === "lua_eval") {
    const { code, frames, colors, show } = args;
    if (typeof code !== "string") {
      return { isError: true, content: [{ type: "text", text: "missing 'code' argument" }] };
    }
    const { ok, stdout, stderr } = runLua(code, { frames, colors, show });
    const body = [
      ok ? "RESULT: OK" : "RESULT: FAILED",
      stdout.trim() ? "--- stdout ---\n" + stdout.trim() : "",
      stderr.trim() ? "--- stderr ---\n" + stderr.trim() : "",
    ].filter(Boolean).join("\n\n");
    return {
      content: [{ type: "text", text: body }],
      isError: !ok,
    };
  }
  if (name === "lua_check") {
    const { code } = args;
    if (typeof code !== "string") {
      return { isError: true, content: [{ type: "text", text: "missing 'code' argument" }] };
    }
    const { ok, stderr } = runLua(code, { frames: 1, show: "hash" });
    const msg = ok ? "OK" : "FAILED\n" + (stderr.trim() || "(no error text)");
    return {
      content: [{ type: "text", text: msg }],
      isError: !ok,
    };
  }
  return {
    isError: true,
    content: [{ type: "text", text: `unknown tool: ${name}` }],
  };
}

// --- JSON-RPC loop over stdio ---
function send(obj) {
  process.stdout.write(JSON.stringify(obj) + "\n");
}

function respond(id, result) {
  send({ jsonrpc: "2.0", id, result });
}

function respondError(id, code, message) {
  send({ jsonrpc: "2.0", id, error: { code, message } });
}

const rl = readline.createInterface({ input: process.stdin });
rl.on("line", (line) => {
  if (!line.trim()) return;
  let msg;
  try {
    msg = JSON.parse(line);
  } catch (e) {
    respondError(null, -32700, "parse error: " + e.message);
    return;
  }
  const { id, method, params } = msg;
  try {
    switch (method) {
      case "initialize":
        respond(id, handleInitialize());
        break;
      case "tools/list":
        respond(id, handleToolsList());
        break;
      case "tools/call":
        respond(id, handleToolsCall(params));
        break;
      case "notifications/initialized":
        // no response for notifications
        break;
      case "ping":
        respond(id, {});
        break;
      default:
        respondError(id, -32601, `method not found: ${method}`);
    }
  } catch (e) {
    respondError(id, -32603, "internal error: " + e.message);
  }
});

process.stderr.write(`mono-lua-repl MCP server listening on stdio\n`);
