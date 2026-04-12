#!/usr/bin/env node
// Mono Play MCP server
//
// Lets Claude actually play a Mono game: take an action, see the next
// frame as ASCII, decide the next action, repeat. Sessions persist
// across tool calls via an in-memory session store keyed by session_id.
//
// Tools:
//   play_start  — boot a game and return initial ASCII frame + session_id
//   play_step   — advance the game by N frames with given inputs
//   play_stop   — destroy a session
//   play_list   — list active sessions
//
// Unlike lua-repl (which runs a one-shot snippet), play maintains a
// persistent headless engine subprocess so state is preserved between
// tool calls.

"use strict";

const { spawn } = require("child_process");
const path = require("path");
const fs = require("fs");
const readline = require("readline");
const crypto = require("crypto");

const REPO_ROOT = path.resolve(__dirname, "../../..");
const TEST_RUNNER = path.join(REPO_ROOT, "editor/templates/mono/mono-test.js");

const SERVER_INFO = { name: "mono-play", version: "0.1.0" };
const PROTOCOL_VERSION = "2024-11-05";

// --- Session store ---
// Because mono-test.js is one-shot, we persist state by re-running the
// whole game from frame 0 for each step, accumulating all inputs so far.
// This is slow for long sessions but keeps the implementation trivial.
const sessions = {};  // session_id → { gamePath, colors, inputs: [{frame, keys}], totalFrames }

function newSessionId() {
  return crypto.randomBytes(6).toString("hex");
}

function runGameOnce(gamePath, colors, frames, inputs) {
  const gameDir = path.dirname(gamePath);
  const entry = path.basename(gamePath);
  const inputStr = inputs
    .flatMap(entry => entry.keys.map(k => `${entry.frame}:${k}`))
    .join(",");
  const args = [
    TEST_RUNNER,
    entry,
    "--frames", String(frames),
    "--colors", String(colors),
    "--quiet",
    "--vdump",
  ];
  if (inputStr) args.push("--input", inputStr);
  const result = require("child_process").spawnSync("node", args, {
    cwd: gameDir,
    encoding: "utf8",
  });
  const ok = result.status === 0;
  const out = (result.stdout || "") + (result.stderr || "");
  // Extract the vdump block — 160 × 120 hex digits where each character
  // is the color index (0-f) of one pixel. This is the source of truth
  // for screen state; the LLM receives it verbatim and interprets shapes
  // directly from the pixel values.
  const vdumpStart = out.indexOf("--- vdump ---");
  let vram = "";
  if (vdumpStart >= 0) {
    const after = out.slice(vdumpStart);
    const lines = after.split("\n").slice(1);
    const endIdx = lines.findIndex(l => l.startsWith("---") || l.startsWith("OK ") || l.startsWith("FAILED"));
    vram = lines.slice(0, endIdx >= 0 ? endIdx : lines.length).join("\n").trimEnd();
  }
  // Extract any Lua print lines
  const logs = out
    .split("\n")
    .filter(l => l.startsWith("[Lua]"))
    .map(l => l.replace(/^\[Lua\]\s*/, ""));
  return { ok, vram, logs, rawOutput: out };
}

const TOOLS = [
  {
    name: "play_start",
    description:
      "Boot a Mono game and return the initial VRAM (160×120 hex dump, " +
      "one character per pixel, values 0-f = color index). Returns a " +
      "session_id that must be passed to subsequent play_step calls.",
    inputSchema: {
      type: "object",
      properties: {
        game_path: {
          type: "string",
          description: "Path to main.lua (absolute or relative to mono repo root). " +
            "Example: 'demo/pong/main.lua'",
        },
        colors: { type: "number", description: "1, 2, or 4. Default: 4", default: 4 },
        initial_frames: {
          type: "number",
          description: "Frames to run before returning the first snapshot. Default: 1",
          default: 1,
        },
      },
      required: ["game_path"],
    },
  },
  {
    name: "play_step",
    description:
      "Advance an existing session by N frames with given inputs. " +
      "Keys are applied at the first new frame and held for its duration. " +
      "Returns the resulting VRAM (160×120 hex dump) + any Lua print() " +
      "output produced.",
    inputSchema: {
      type: "object",
      properties: {
        session_id: { type: "string", description: "Session id from play_start" },
        frames: { type: "number", description: "Frames to advance. Default: 1", default: 1 },
        keys: {
          type: "array",
          items: { type: "string", enum: ["up", "down", "left", "right", "a", "b", "start", "select"] },
          description: "Keys held during the advance (applied on first new frame).",
        },
      },
      required: ["session_id"],
    },
  },
  {
    name: "play_stop",
    description: "Destroy a session and free resources.",
    inputSchema: {
      type: "object",
      properties: {
        session_id: { type: "string" },
      },
      required: ["session_id"],
    },
  },
  {
    name: "play_list",
    description: "List all active play sessions.",
    inputSchema: { type: "object", properties: {} },
  },
];

// --- Tool handlers ---
function resolveGamePath(p) {
  if (path.isAbsolute(p) && fs.existsSync(p)) return p;
  const rel = path.resolve(REPO_ROOT, p);
  if (fs.existsSync(rel)) return rel;
  return null;
}

function handlePlayStart(args) {
  const { game_path, colors = 4, initial_frames = 1 } = args;
  const resolved = resolveGamePath(game_path);
  if (!resolved) {
    return { isError: true, content: [{ type: "text", text: `game not found: ${game_path}` }] };
  }
  const session_id = newSessionId();
  sessions[session_id] = {
    gamePath: resolved,
    colors,
    inputs: [],
    totalFrames: initial_frames,
  };
  const { ok, vram, logs } = runGameOnce(resolved, colors, initial_frames, []);
  if (!ok) {
    delete sessions[session_id];
    return { isError: true, content: [{ type: "text", text: "game failed to boot:\n" + vram }] };
  }
  const body = [
    `session_id: ${session_id}`,
    `game: ${game_path}`,
    `frame: ${initial_frames}`,
    logs.length ? `logs:\n  ${logs.join("\n  ")}` : "",
    "vram (160x120, 0-f per pixel):",
    vram,
  ].filter(Boolean).join("\n");
  return { content: [{ type: "text", text: body }] };
}

function handlePlayStep(args) {
  const { session_id, frames = 1, keys = [] } = args;
  const s = sessions[session_id];
  if (!s) {
    return { isError: true, content: [{ type: "text", text: `no such session: ${session_id}` }] };
  }
  // Record inputs for the first new frame (current totalFrames + 1)
  if (keys.length > 0) {
    s.inputs.push({ frame: s.totalFrames + 1, keys: [...keys] });
  }
  s.totalFrames += frames;
  const { ok, vram, logs } = runGameOnce(s.gamePath, s.colors, s.totalFrames, s.inputs);
  if (!ok) {
    return { isError: true, content: [{ type: "text", text: "run failed:\n" + vram }] };
  }
  const body = [
    `frame: ${s.totalFrames}`,
    `inputs applied: ${keys.length > 0 ? keys.join(",") : "(none)"}`,
    logs.length ? `logs:\n  ${logs.slice(-10).join("\n  ")}` : "",
    "vram (160x120, 0-f per pixel):",
    vram,
  ].filter(Boolean).join("\n");
  return { content: [{ type: "text", text: body }] };
}

function handlePlayStop(args) {
  const { session_id } = args;
  if (sessions[session_id]) {
    delete sessions[session_id];
    return { content: [{ type: "text", text: `stopped: ${session_id}` }] };
  }
  return { isError: true, content: [{ type: "text", text: `no such session: ${session_id}` }] };
}

function handlePlayList() {
  const entries = Object.entries(sessions).map(([id, s]) => ({
    id,
    game: path.relative(REPO_ROOT, s.gamePath),
    frame: s.totalFrames,
    input_events: s.inputs.length,
  }));
  const text = entries.length === 0
    ? "(no active sessions)"
    : entries.map(e => `${e.id}  frame=${e.frame}  game=${e.game}  inputs=${e.input_events}`).join("\n");
  return { content: [{ type: "text", text }] };
}

// --- JSON-RPC ---
function send(obj) { process.stdout.write(JSON.stringify(obj) + "\n"); }
function respond(id, result) { send({ jsonrpc: "2.0", id, result }); }
function respondError(id, code, message) { send({ jsonrpc: "2.0", id, error: { code, message } }); }

const rl = readline.createInterface({ input: process.stdin });
rl.on("line", (line) => {
  if (!line.trim()) return;
  let msg;
  try { msg = JSON.parse(line); }
  catch (e) { return respondError(null, -32700, "parse error: " + e.message); }
  const { id, method, params } = msg;
  try {
    switch (method) {
      case "initialize":
        respond(id, { protocolVersion: PROTOCOL_VERSION, capabilities: { tools: {} }, serverInfo: SERVER_INFO });
        break;
      case "tools/list":
        respond(id, { tools: TOOLS });
        break;
      case "tools/call": {
        const name = params?.name;
        const args = params?.arguments || {};
        let result;
        if (name === "play_start")      result = handlePlayStart(args);
        else if (name === "play_step")  result = handlePlayStep(args);
        else if (name === "play_stop")  result = handlePlayStop(args);
        else if (name === "play_list")  result = handlePlayList();
        else result = { isError: true, content: [{ type: "text", text: `unknown tool: ${name}` }] };
        respond(id, result);
        break;
      }
      case "notifications/initialized":
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

process.stderr.write(`mono-play MCP server listening on stdio\n`);
