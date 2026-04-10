# mono-play MCP server

Lets Claude actually play a Mono game: boot it, take an action, see the next VRAM frame, decide the next move, repeat. Useful for LLM-driven playtesting, bug reproduction, and AI self-play experiments.

## Tools

- **`play_start`** — boot a game (`demo/pong/main.lua`, etc.), run initial frames, return VRAM hex dump + `session_id`. VRAM is 160×144 hex digits, one character per pixel, `0` = empty / `f` = brightest.
- **`play_step`** — advance a session by N frames with given inputs (held during the first new frame). Returns the resulting VRAM + any new Lua `print()` output.
- **`play_list`** — list all active sessions in the current server process.
- **`play_stop`** — destroy a session.

## Session model

Because `mono-test.js` is one-shot, the server keeps an in-memory session record `{gamePath, inputs[], totalFrames}` and re-runs the entire game from frame 0 on every step, with the accumulated input schedule. This is slow for long sessions but dead simple and deterministic. Good for short playtest loops (tens of steps). For longer plays, use `mono-test.js --replay` with a `.replay` file instead.

Sessions live only for the lifetime of the MCP server process. A fresh Claude Code launch means empty state.

## Installation in Claude Code

This server is registered at the project level via `.mcp.json` at the repo root. When you open this repo in Claude Code, it prompts once to approve the project MCP servers, then the tools are available for every session.

Tools appear as `mcp__mono-play__play_start`, `mcp__mono-play__play_step`, etc.

If you want to register it manually at the user level instead (e.g., to use from outside this repo):

```bash
claude mcp add mono-play node /absolute/path/to/mono/.claude/mcp/play/server.js
```

## Example flow (manual JSON-RPC)

```bash
cat <<'JSON' | node server.js
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"play_start","arguments":{"game_path":"demo/pong/main.lua","initial_frames":5}}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"play_list"}}
JSON
```

## Use cases

- **LLM QA**: "Play pong for 200 frames and tell me if the AI ever scores." The agent plays, sees the score update, reports back.
- **Bug reproduction**: Given a bug description, the agent tries input sequences until it reproduces the failing state, then exports the session to a `.replay` file.
- **Gameplay balancing**: Let the agent play multiple times with different strategies and report which wins.
- **Demo discovery**: Drop a new `main.lua`, ask the agent to figure out the controls by experimentation.

## Dependencies

None beyond Node stdlib. Spawns `mono-test.js` via `child_process.spawnSync` for each step.
