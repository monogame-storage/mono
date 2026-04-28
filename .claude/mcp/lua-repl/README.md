# mono-lua-repl MCP server

Lightweight Model Context Protocol server that exposes a Lua REPL backed by the Mono engine. Lets Claude evaluate API snippets and see the resulting VRAM state without writing a full demo file.

## Tools

- **`lua_eval`** — run a Lua snippet for N frames and return the rendered screen as a VRAM hex dump (160×120, one character per pixel, values 0-f = color index) or just the VRAM hash.
- **`lua_check`** — fast OK/error validation (1 frame, no rendering output).

Snippets that don't define `_draw()` are auto-wrapped: the code becomes the body of a default `_draw()` that runs against a cleared screen. You can also define the full lifecycle (`_init/_start/_update/_draw`) yourself.

## Installation in Claude Code

This server is registered at the project level via `.mcp.json` at the repo root. When you open this repo in Claude Code, it prompts once to approve the project MCP servers, then the tools are available for every session.

Tools appear as `mcp__mono-lua-repl__lua_eval` and `mcp__mono-lua-repl__lua_check`.

If you want to register it manually at the user level instead (e.g., to use from outside this repo), run:

```bash
claude mcp add mono-lua-repl node /absolute/path/to/mono/.claude/mcp/lua-repl/server.js
```

## Manual test

```bash
cat <<'JSON' | node server.js
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
{"jsonrpc":"2.0","id":2,"method":"tools/list"}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"lua_check","arguments":{"code":"rectf(scr,10,10,20,20,15)"}}}
JSON
```

## Why no SDK

MCP is JSON-RPC over stdio. This server implements it directly in ~200 lines with zero dependencies beyond Node's `readline` and `child_process`. Matches Mono's "constraint = creativity" philosophy and keeps install simple.

## Dependency

Requires `mono-runner.js` at `dev/headless/mono-runner.js` (resolved via `__dirname`). The server spawns it as a subprocess via `--source` for each eval.
