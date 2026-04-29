// ── AI Tab: Chat, send message, test & fix ──

import { state, esc, chatTime, API_URL } from './state.js';
import { apiFetch, saveChatHistory } from './api.js';
import { runHeadlessTest, defaultSmokeScenario } from './editor-play.js';
import { openAIProviders } from './settings.js';

// ── Smart auto-scroll for the chat panel ──
// The agent stream can drop dozens of token / tool-result events per
// second. Hard-pinning the chat to scrollHeight on every event breaks
// the user's ability to scroll up and read mid-stream. Pattern: track
// whether the user is "at bottom" (within a small threshold), only
// auto-scroll while true, and re-engage as soon as the user scrolls
// back to the bottom themselves.
const SCROLL_BOTTOM_THRESHOLD_PX = 50;
let chatAutoScroll = true;
function scrollChatToBottom(el) {
  if (!el) return;
  if (!el.dataset.autoScrollBound) {
    el.dataset.autoScrollBound = "1";
    el.addEventListener("scroll", () => {
      const distance = el.scrollHeight - el.scrollTop - el.clientHeight;
      chatAutoScroll = distance <= SCROLL_BOTTOM_THRESHOLD_PX;
    }, { passive: true });
  }
  if (chatAutoScroll) el.scrollTop = el.scrollHeight;
}

// ── Single-flight guard for the chat agent ──
// Without this, hitting Enter twice (or clicking Send while an agent
// turn was already streaming) kicked off a SECOND parallel /chat/agent
// request — both turns ran end-to-end against the same gameId,
// stomping on each other's R2 writes and producing two completed
// cards. The pattern: hold the AbortController for the in-flight
// request in a module slot; reject re-entry at the top of
// sendMessage; let either the in-card Stop button or the Send button
// (which morphs into a Stop button mid-flight) call abort.
let aiInFlight = null;
function isAbortError(e) {
  return e?.name === "AbortError" || e?.message === "AbortError";
}

// Glyphs swapped into #btn-send. Send is the upward arrow; running
// shows a stop square. Title attr changes for screen-reader hint.
const SEND_BTN_ARROW = '<svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor"><path d="M12 19V5M5 12l7-7 7 7"/></svg>';
const SEND_BTN_STOP = '<svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor"><rect x="6" y="6" width="12" height="12" rx="1"/></svg>';
function setSendButtonRunning(running) {
  const btn = document.getElementById("btn-send");
  if (!btn) return;
  if (running) {
    btn.classList.add("is-stop");
    btn.innerHTML = SEND_BTN_STOP;
    btn.title = "Stop (cancel current request)";
  } else {
    btn.classList.remove("is-stop");
    btn.innerHTML = SEND_BTN_ARROW;
    btn.title = "Send";
  }
}

// Provider catalog from mono-api /config — { id, protocol, ... }. The
// client uses it to decide whether a Connection routes to /chat/agent
// (openai-protocol tool-use loop) or /chat (one-shot). Fetched fire-
// and-forget at module load; until it arrives the set below carries
// the built-in openai-protocol providers so first-boot doesn't lose
// agent routing on a slow network.
let AGENT_PROTOCOLS = new Set(["openai"]);
let PROVIDER_PROTOCOL = new Map([
  ["openai",    "openai"],
  ["moonshot",  "openai"],
  ["apimart",   "openai"],
  ["custom",    "openai"],
  ["anthropic", "anthropic"],
  ["google",    "gemini"],
]);
function usesAgentPath(connection) {
  const proto = PROVIDER_PROTOCOL.get(connection?.provider);
  return !!proto && AGENT_PROTOCOLS.has(proto);
}

(async function loadCatalogFromConfig() {
  try {
    const res = await fetch(`${API_URL}/config`);
    if (!res.ok) return;
    const data = await res.json();
    if (Array.isArray(data.providers)) {
      const map = new Map();
      for (const p of data.providers) map.set(p.id, p.protocol);
      PROVIDER_PROTOCOL = map;
    }
    if (Array.isArray(data.agentProtocols)) {
      AGENT_PROTOCOLS = new Set(data.agentProtocols);
    }
  } catch {
    // Offline — keep the hardcoded fallback.
  }
})();

// ── Card builders ──

const RETRY_SVG = '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2"><path d="M1 4v6h6"/><path d="M3.51 15a9 9 0 102.13-9.36L1 10"/></svg>';
const STOP_SVG = '<svg viewBox="0 0 24 24" width="10" height="10" fill="currentColor"><rect x="6" y="6" width="12" height="12" rx="1"/></svg>';

// Strip fenced code blocks and collapse whitespace so the chat card
// shows only the explanation — code lives in the file list below.
function cleanMessage(s) {
  if (!s) return s;
  return s
    .replace(/```[\s\S]*?```/g, '')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

// Minimal markdown → HTML for chat rendering.
// Supports: # / ## / ### headers, **bold**, `inline code`, - bullets,
// blank-line paragraph breaks. Escapes first so user input is safe.
function renderMarkdown(s) {
  if (!s) return '';
  const lines = esc(s).split('\n');
  const out = [];
  let inList = false;
  let para = [];

  const flushPara = () => {
    if (para.length) { out.push(`<p>${para.join(' ')}</p>`); para = []; }
  };
  const closeList = () => {
    if (inList) { out.push('</ul>'); inList = false; }
  };
  const inline = (t) =>
    t.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
     .replace(/`([^`]+)`/g, '<code>$1</code>');

  for (const raw of lines) {
    const line = raw.trim();
    if (!line) { flushPara(); closeList(); continue; }
    let m;
    if ((m = line.match(/^###\s+(.+)$/))) {
      flushPara(); closeList();
      out.push(`<h4 class="md-h">${inline(m[1])}</h4>`); continue;
    }
    if ((m = line.match(/^##\s+(.+)$/))) {
      flushPara(); closeList();
      out.push(`<h3 class="md-h">${inline(m[1])}</h3>`); continue;
    }
    if ((m = line.match(/^#\s+(.+)$/))) {
      flushPara(); closeList();
      out.push(`<h2 class="md-h">${inline(m[1])}</h2>`); continue;
    }
    if ((m = line.match(/^[-*]\s+(.+)$/))) {
      flushPara();
      if (!inList) { out.push('<ul class="md-ul">'); inList = true; }
      out.push(`<li>${inline(m[1])}</li>`); continue;
    }
    closeList();
    para.push(inline(line));
  }
  flushPara(); closeList();
  return out.join('');
}

function userCard(msg) {
  return `<div class="ai-card-user">
    <div class="ai-card-head">
      <span class="ai-card-label">YOU</span>
      <button class="ai-card-retry" title="Retry">${RETRY_SVG}</button>
    </div>
    <div class="ai-card-body">${esc(msg)}</div>
  </div>`;
}

function monoCard(message, files, status = "completed") {
  const statusCls = status === "working" ? " working" : "";
  let html = `<div class="ai-card-mono${statusCls}">
    <div class="ai-card-status${statusCls}">MONO · ${status}</div>`;
  const cleaned = cleanMessage(message);
  if (cleaned) html += `<div class="ai-card-response">${renderMarkdown(cleaned)}</div>`;
  if (files && files.length > 0) {
    for (const f of files) {
      const action = f._action || "edited";
      html += `<div class="ai-card-file">${action === "created" ? "+ " : "~ "}${esc(f.name)}  ·  ${action}</div>`;
    }
  }
  if (status === "working") {
    html += `<button class="ai-card-stop" id="btn-ai-stop">${STOP_SVG} Stop</button>`;
  }
  html += `</div>`;
  return html;
}

// Completed agent card with a collapsed trace footer. `trace` is an
// ordered list of { kind: "reasoning"|"text"|"tool", ... } captured
// during the /chat/agent SSE run; `stats` is { iterations, tools,
// tokens } for the header summary. Trace stays collapsed by default
// so the chat looks clean; user clicks to unfold.
function formatTokens(n) {
  if (!n) return "0";
  if (n >= 1000) return `${(n / 1000).toFixed(1).replace(/\.0$/, "")}k`;
  return String(n);
}

function monoCardAgentCompleted(message, files, trace, stats) {
  let html = `<div class="ai-card-mono">
    <div class="ai-card-status">MONO · completed</div>`;
  const cleaned = cleanMessage(message);
  if (cleaned) html += `<div class="ai-card-response">${renderMarkdown(cleaned)}</div>`;
  if (files && files.length > 0) {
    for (const f of files) {
      const action = f._action || "edited";
      const prefix = action === "created" ? "+ " : action === "deleted" ? "- " : "~ ";
      html += `<div class="ai-card-file">${prefix}${esc(f.name)}  ·  ${action}</div>`;
    }
  }

  if (trace && trace.length > 0) {
    const parts = [];
    if (stats?.iterations) parts.push(`${stats.iterations} iter`);
    if (stats?.tools) parts.push(`${stats.tools} tool${stats.tools === 1 ? "" : "s"}`);
    if (stats?.tokens) parts.push(`${formatTokens(stats.tokens)} tok`);
    const summary = parts.length ? ` (${parts.join(" · ")})` : "";

    let traceHtml = "";
    for (const ev of trace) {
      if (ev.kind === "reasoning") {
        traceHtml += `<div class="ai-trace-reasoning">💭 ${esc(ev.text)}</div>`;
      } else if (ev.kind === "text") {
        traceHtml += `<div class="ai-trace-text">${esc(ev.text)}</div>`;
      } else if (ev.kind === "tool") {
        const label = toolLineLabel(ev.name, ev.input);
        const cls = ev.ok === false ? "err" : ev.ok === true ? "ok" : "working";
        const mark = ev.ok === false ? "✗" : ev.ok === true ? "✓" : "◌";
        const tail = ev.summary ? ` — ${esc(ev.summary)}` : "";
        traceHtml += `<div class="ai-tool-line ${cls}">`
          + `<span class="ai-tool-spin">${mark}</span>`
          + `<span class="ai-tool-text">${esc(label)}${tail}</span>`
          + `</div>`;
      }
    }
    html += `<button class="ai-trace-toggle" data-expanded="0">▸ Show trace${summary}</button>`;
    html += `<div class="ai-trace" hidden>${traceHtml}</div>`;
  }

  html += `</div>`;
  return html;
}

function monoTypingCard() {
  return `<div class="ai-card-mono working" id="mono-typing">
    <div class="ai-card-status working">MONO · working…</div>
    <div class="ai-card-response" style="color:#888">Thinking…</div>
  </div>`;
}

// Progress card for the /chat/agent streaming path. Events (reasoning,
// tool_start, tool_result, token deltas) land inside `.ai-agent-live`
// in arrival order, so the user watches the same interleaved trace
// that will later be folded into the completed card's collapsible.
// On final the whole card is swapped for monoCardAgentCompleted().
function monoAgentCard(id) {
  return `<div class="ai-card-mono working" id="${id}">
    <div class="ai-card-status working">MONO · working…</div>
    <div class="ai-agent-live"></div>
  </div>`;
}

const TOOL_ICON = {
  list_files: "📂",
  read_file:  "📖",
  write_file: "✏️",
  delete_file:"🗑️",
};

function toolLineLabel(name, input) {
  const p = input?.path ? ` ${input.path}` : "";
  return `${TOOL_ICON[name] || "🔧"} ${name}${p}`;
}

function errorCard(msg, label = "ERROR", showFix = true) {
  return `<div class="ai-card-error">
    <div class="ai-card-status">${esc(label)}</div>
    <div class="ai-card-response">${esc(msg)}</div>
    ${showFix ? `<button class="ai-card-fix">Fix with AI</button>` : ``}
  </div>`;
}

function systemCard(msg) {
  return `<div class="ai-card-mono">
    <div class="ai-card-status">MONO · system</div>
    <div class="ai-card-response">${esc(msg)}</div>
  </div>`;
}

// ── Chat rendering ──

export function addChatMsg(sender, body) {
  const chat = document.getElementById("editor-chat");
  if (sender === "mono") {
    chat.innerHTML += systemCard(body);
  } else {
    chat.innerHTML += userCard(body);
  }
  scrollChatToBottom(chat);
}

export function renderChatHistory() {
  const chat = document.getElementById("editor-chat");
  // Switching games (or initial load) should always land at bottom —
  // user couldn't have meaningfully scrolled past content they haven't
  // seen. Reset the auto-scroll latch so the first paint pins down.
  chatAutoScroll = true;

  if (state.chatHistory.length > 0) {
    let html = '';
    for (const h of state.chatHistory) {
      html += h.role === "user" ? userCard(h.content) : monoCard(h.content, null, "completed");
    }
    if (state.currentFiles.length > 0) {
      const files = state.currentFiles.map(f => ({ name: f.name, _action: "loaded" }));
      html += monoCard("Session restored.", files, "completed");
    }
    chat.innerHTML = html;
  } else if (state.currentFiles.length > 0) {
    const files = state.currentFiles.map(f => ({ name: f.name, _action: "loaded" }));
    chat.innerHTML = monoCard("Loaded existing files.", files, "completed");
  } else {
    chat.innerHTML = monoCard("Game created. Describe what you want to build!", null, "ready");
  }
  scrollChatToBottom(chat);
}

// ── Engine error (shown inline as error card) ──

export function showEngineError(msg) {
  state.lastEngineError = msg;
  const chat = document.getElementById("editor-chat");
  chat.innerHTML += errorCard(msg, "RUNTIME ERROR");
  scrollChatToBottom(chat);
}

// ── Fix confirmation popup ──

function showFixConfirm(errorText, label) {
  const sheet = document.getElementById("file-sheet");
  if (!sheet) return;

  const defaultPrompt = `Fix this ${label === "TEST FAILED" ? "test failure" : "runtime error"}:\n${errorText}`;

  sheet.innerHTML = `
    <div class="file-sheet-dim"></div>
    <div class="file-sheet-panel">
      <div class="file-sheet-handle"><div class="file-sheet-handle-bar"></div></div>
      <div class="file-sheet-header">
        <div class="file-sheet-left">
          <span class="file-sheet-name">Send fix request to AI?</span>
        </div>
      </div>
      <div class="fix-confirm-body">
        <div class="fix-confirm-label">Prompt (editable)</div>
        <textarea class="fix-confirm-textarea" id="fix-confirm-text" spellcheck="false">${esc(defaultPrompt)}</textarea>
      </div>
      <div class="sync-actions">
        <button class="sync-cancel" id="btn-fix-cancel">Cancel</button>
        <button class="sync-confirm" id="btn-fix-send">Send</button>
      </div>
    </div>`;

  sheet.classList.add("open");

  const ta = document.getElementById("fix-confirm-text");
  ta.focus();
  ta.addEventListener("keydown", (e) => e.stopPropagation());
  ta.addEventListener("keyup", (e) => e.stopPropagation());
  ta.addEventListener("keypress", (e) => e.stopPropagation());

  let onEsc;
  const close = () => {
    sheet.classList.remove("open");
    document.removeEventListener("keydown", onEsc, true);
  };
  onEsc = (e) => {
    if (e.key === "Escape") { e.preventDefault(); close(); }
  };
  document.addEventListener("keydown", onEsc, true);
  sheet.querySelector(".file-sheet-dim").addEventListener("click", close, { once: true });
  document.getElementById("btn-fix-cancel").addEventListener("click", close);
  document.getElementById("btn-fix-send").addEventListener("click", () => {
    const prompt = ta.value.trim();
    close();
    if (prompt) {
      clearEngineError();
      sendMessage(prompt);
    }
  });
}

export function clearEngineError() {
  state.lastEngineError = null;
}

// ── Usage tracking (internal only, no DOM display) ──

function updateUsageDisplay(data) {
  const usage = data?.usage;
  if (!usage) return;
  state.sessionTokens.prompt += usage.prompt_tokens || 0;
  state.sessionTokens.completion += usage.completion_tokens || 0;
  state.sessionTokens.total += usage.total_tokens || 0;
}

// ── Agent path (SSE tool-use loop) ──

// Parse an SSE stream into { event, data } records. Follows the
// WHATWG SSE grammar: every `data:` line in a frame contributes a
// value, and consecutive `data:` lines are joined with `\n` (not
// concatenated tightly — that corrupts JSON whose values contain
// embedded whitespace). Optional single space after the colon is
// stripped per spec; preserves all other characters verbatim.
async function* parseSSE(response) {
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buf = "";
  const stripPrefix = (line, prefix) => {
    const rest = line.slice(prefix.length);
    return rest.startsWith(" ") ? rest.slice(1) : rest;
  };
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buf += decoder.decode(value, { stream: true });
    let idx;
    while ((idx = buf.indexOf("\n\n")) !== -1) {
      const frame = buf.slice(0, idx);
      buf = buf.slice(idx + 2);
      let event = "message";
      const dataLines = [];
      for (const line of frame.split("\n")) {
        if (line.startsWith(":")) continue; // SSE comment
        if (line.startsWith("event:")) event = stripPrefix(line, "event:").trim();
        else if (line.startsWith("data:")) dataLines.push(stripPrefix(line, "data:"));
      }
      if (dataLines.length === 0) continue;
      const dataStr = dataLines.join("\n");
      let data;
      try { data = JSON.parse(dataStr); } catch { continue; }
      yield { event, data };
    }
  }
}

async function sendAgent(connection, msg, chat, signal) {
  // Defensive guard — caller already checks state.aiConnections, but the
  // user can delete the Connection between the lookup and now (rapid
  // navigation, multi-tab edit). Bail with a clear error instead of
  // crashing on `connection.provider`.
  if (!connection?.provider || !connection?.model || !connection?.apiKey) {
    throw new Error("Connection is invalid — re-pick or re-add it in Settings → Cosmi.");
  }
  const providerId = connection.provider;
  const model = connection.model;
  const byok = {
    apiKey: connection.apiKey,
    baseUrl: connection.baseUrl || undefined,
  };

  const cardId = `mono-agent-${Date.now()}`;
  const typing = document.getElementById("mono-typing");
  if (typing) typing.outerHTML = monoAgentCard(cardId);
  else chat.innerHTML += monoAgentCard(cardId);
  const toolLines = new Map(); // tool_call id → row element
  scrollChatToBottom(chat);

  // Re-query the live container on every append. A captured reference
  // would go stale the moment something else mutates chat.innerHTML
  // during the stream (engine error card, smoke test card from a prior
  // run, another sendMessage), and writes would land on a detached
  // node — invisible to the user but consuming the rest of the trace.
  const getLiveEl = () => document.getElementById(cardId)?.querySelector(".ai-agent-live");

  // Append into `.ai-agent-live` in arrival order. Consecutive reasoning
  // or token events coalesce into the same block (typing-style growth);
  // a new event type — tool call, next-turn reasoning after tools —
  // starts a fresh block underneath so the trace reads top-to-bottom.
  const appendLive = (kind, text, opts = {}) => {
    const liveEl = getLiveEl();
    if (!liveEl) return null;
    const last = liveEl.lastElementChild;
    if (kind === "reasoning") {
      if (last?.classList.contains("ai-agent-reasoning") && last.dataset.finalized !== "1") {
        last.append(text);
      } else {
        const el = document.createElement("div");
        el.className = "ai-agent-reasoning";
        el.textContent = "💭 " + text;
        liveEl.appendChild(el);
      }
    } else if (kind === "text") {
      if (last?.classList.contains("ai-agent-text") && last.dataset.finalized !== "1") {
        last.append(text);
      } else {
        const el = document.createElement("div");
        el.className = "ai-agent-text";
        el.textContent = text;
        liveEl.appendChild(el);
      }
    } else if (kind === "tool") {
      // Starting a tool row closes whatever live reasoning / text is
      // above so the next delta after the tool opens a fresh block.
      for (const child of liveEl.children) child.dataset.finalized = "1";
      const row = document.createElement("div");
      row.className = "ai-tool-line working";
      row.dataset.id = opts.id;
      row.innerHTML = `<span class="ai-tool-spin">◌</span><span class="ai-tool-text">${esc(opts.label)}</span>`;
      liveEl.appendChild(row);
      toolLines.set(opts.id, row);
    }
    scrollChatToBottom(chat);
  };
  const finishToolLine = (id, ok, summary) => {
    const row = toolLines.get(id);
    if (!row?.isConnected) return;
    row.classList.remove("working");
    row.classList.add(ok ? "ok" : "err");
    const spin = row.querySelector(".ai-tool-spin");
    if (spin) spin.textContent = ok ? "✓" : "✗";
    const txt = row.querySelector(".ai-tool-text");
    if (txt && summary) txt.textContent = `${txt.textContent} — ${summary}`;
  };

  console.group("[MONO Agent]");
  console.log("→", providerId, "·", model, byok.baseUrl ? `@ ${byok.baseUrl}` : "");
  console.log("→ message:", msg);

  let finalText = "";
  let changedList = [];
  let finalUsage = null;
  let finalIterations = 0;
  let errored = null;
  let streamBuf = ""; // per-turn token buffer, flushed on tool call / final
  // Parallel data log of every SSE event — survives the DOM swap so the
  // completed card can render a collapsed trace of reasoning / mid-turn
  // text / tool calls for user inspection. Reasoning deltas coalesce into
  // the open entry (currentReasoningEntry) until a tool_start closes it.
  const trace = [];
  const traceToolById = new Map();
  let currentReasoningEntry = null;

  try {
    const token = await state.auth.currentUser.getIdToken();
    const res = await fetch(`${API_URL}/chat/agent`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        gameId: state.currentGameId,
        message: msg,
        history: state.chatHistory.slice(0, -1),
        provider: providerId,
        model,
        byok,
      }),
      signal,
    });
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      throw new Error(`agent ${res.status}: ${body.slice(0, 200)}`);
    }

    const flushStream = (label, intoTrace) => {
      if (!streamBuf) return;
      console.log(`· ${label}:`, streamBuf);
      // Only inter-turn chatter (pre-tool text) is worth preserving in
      // the trace; the final reply is already shown above it.
      if (intoTrace) trace.push({ kind: "text", text: streamBuf });
      streamBuf = "";
    };

    for await (const { event, data } of parseSSE(res)) {
      if (event === "reasoning") {
        if (!data.text) continue;
        // Live: grow the current reasoning block (coalesce deltas).
        appendLive("reasoning", data.text);
        // Trace: same coalescing rule so deltas become one block per turn.
        if (currentReasoningEntry) {
          currentReasoningEntry.text += data.text;
        } else {
          currentReasoningEntry = { kind: "reasoning", text: data.text };
          trace.push(currentReasoningEntry);
        }
      } else if (event === "token") {
        if (!data.text) continue;
        streamBuf += data.text;
        appendLive("text", data.text);
      } else if (event === "tool_start") {
        flushStream("pre-tool text", true);
        console.log("→ tool:", data.name, data.input);
        // A tool call ends the current reasoning block: the next
        // reasoning burst belongs to the next iteration.
        currentReasoningEntry = null;
        appendLive("tool", null, { id: data.id, label: toolLineLabel(data.name, data.input) });
        const entry = { kind: "tool", id: data.id, name: data.name, input: data.input, ok: null, summary: null };
        trace.push(entry);
        traceToolById.set(data.id, entry);
      } else if (event === "tool_result") {
        console.log("← tool:", data.name, data.ok ? "ok" : "err", data.summary);
        finishToolLine(data.id, data.ok, data.summary);
        const entry = traceToolById.get(data.id);
        if (entry) { entry.ok = !!data.ok; entry.summary = data.summary || ""; }
      } else if (event === "final") {
        flushStream("final text", false);
        finalText = data.text || "";
        changedList = data.changed || [];
        finalUsage = data.usage || null;
        finalIterations = data.iterations || 0;
        console.log("← final:", { iterations: data.iterations, changed: changedList.length });
      } else if (event === "error") {
        flushStream("pre-error text", true);
        errored = data.message || "agent error";
        console.error("← error:", data);
      }
    }
    flushStream("trailing text", false);

    if (errored) throw new Error(errored);

    // Re-sync changed files from R2 so state.currentFiles matches disk.
    const changedFiles = [];
    if (changedList.length) {
      const deletes = changedList.filter(c => c.action === "delete");
      const writes = changedList.filter(c => c.action === "write");
      for (const d of deletes) {
        const idx = state.currentFiles.findIndex(c => c.name === d.name);
        if (idx >= 0) state.currentFiles.splice(idx, 1);
        changedFiles.push({ name: d.name, _action: "deleted" });
      }
      await Promise.all(writes.map(async (w) => {
        try {
          const r = await apiFetch(`/games/${state.currentGameId}/files/${w.name}`);
          if (!r.ok) return;
          // The GET returns {"content": "..."} — NOT the raw file body —
          // so we must unwrap. Previously we did r.text() which stuffed
          // the JSON envelope into state.currentFiles, making the engine
          // execute garbage on the next Play.
          const { content } = await r.json();
          const idx = state.currentFiles.findIndex(c => c.name === w.name);
          const action = idx >= 0 ? "edited" : "created";
          if (idx >= 0) state.currentFiles[idx].content = content;
          else state.currentFiles.push({ name: w.name, content });
          changedFiles.push({ name: w.name, _action: action });
        } catch (e) {
          console.warn("re-sync failed:", w.name, e);
        }
      }));
      const { renderFileTree } = window._editorFiles || {};
      if (renderFileTree) renderFileTree();
    }

    if (finalUsage) {
      state.sessionTokens.prompt += finalUsage.prompt_tokens || 0;
      state.sessionTokens.completion += finalUsage.completion_tokens || 0;
      state.sessionTokens.total += finalUsage.total_tokens || 0;
    }

    state.chatHistory.push({ role: "assistant", content: finalText });
    saveChatHistory();

    const stats = {
      iterations: finalIterations,
      tools: trace.filter(t => t.kind === "tool").length,
      tokens: finalUsage?.total_tokens || 0,
    };
    const replacement = monoCardAgentCompleted(finalText, changedFiles, trace, stats);
    // Re-query by id — if anything else appended to chat during streaming
    // (showEngineError, another message, ...) the `card` reference is
    // stale and outerHTML= would mutate a detached node. Fall back to
    // appending so the user always sees the completed card.
    const liveCard = document.getElementById(cardId);
    if (liveCard) {
      liveCard.outerHTML = replacement;
    } else {
      console.warn("[MONO Agent] working card detached before final; appending");
      chat.insertAdjacentHTML("beforeend", replacement);
    }
    console.log("← rendered:", { bytes: replacement.length, hasText: !!finalText });
    console.groupEnd();

    // Smoke test: if the agent edited any .lua file, run the headless
    // worker with a scripted tap scenario. Catches runtime errors that
    // the static write_file lint can't (nil arithmetic, wrong touch_pos
    // semantics, scene callbacks throwing on input). Always on for the
    // agent path so bad writes surface in seconds instead of next Play.
    const luaChanged = changedFiles.some(f => f.name.endsWith(".lua"));
    if (luaChanged) {
      const scenario = defaultSmokeScenario();
      const testCardId = `smoke-${Date.now()}`;
      chat.innerHTML += `<div class="ai-card-mono working" id="${testCardId}">
        <div class="ai-card-status working">MONO · running smoke test…</div>
      </div>`;
      scrollChatToBottom(chat);
      const result = await runHeadlessTest(state.currentFiles, scenario);
      const testCard = document.getElementById(testCardId);
      if (result.success) {
        if (testCard) testCard.outerHTML = `<div class="ai-card-mono">
          <div class="ai-card-status">MONO · smoke test</div>
          <div class="ai-card-response" style="color:#7bcf7b">✓ booted + tap scenario cleared (${scenario.frames} frames)</div>
        </div>`;
      } else {
        const errs = (result.errors || ["unknown error"]).join("\n");
        console.error("[smoke test] failed:", errs);
        if (testCard) testCard.outerHTML = errorCard(errs, "SMOKE TEST FAILED");
      }
      scrollChatToBottom(chat);
    }
  } catch (e) {
    console.error("agent error:", e);
    console.groupEnd();
    const cardEl = document.getElementById(cardId);
    if (cardEl) {
      const label = isAbortError(e) ? "STOPPED" : "AGENT ERROR";
      const msg = isAbortError(e) ? "Stopped by user." : e.message;
      cardEl.outerHTML = errorCard(msg, label, false);
    }
  }
  scrollChatToBottom(chat);
}

// ── Send message ──

export async function sendMessage(autoMsg) {
  // Re-entry guard. Don't clear the input or push a duplicate user
  // card — let the user keep typing the next prompt while the
  // current turn finishes (or hit Stop to cancel and resend).
  if (aiInFlight) return;

  const input = document.getElementById("editor-msg");
  const msg = autoMsg || input.value.trim();
  if (!msg) return;

  // Chat is BYOK-only. Without a registered provider there is no key
  // to send the request with — short-circuit here and point the user
  // at the provider settings instead of letting the request fail on
  // the server.
  const selectedValue = document.getElementById("model-select").value;
  if (!selectedValue.startsWith("provider:")) {
    const chatEl = document.getElementById("editor-chat");
    chatEl.innerHTML += errorCard(
      "Register a Connection in Settings → Cosmi, then pick it from the pill above to enable chat.",
      "NO CONNECTION",
      false,
    );
    scrollChatToBottom(chatEl);
    if (!autoMsg) {
      // Keep the user's draft so they can retry after registering.
      input.focus();
    }
    openAIProviders();
    return;
  }

  if (!autoMsg) { input.value = ""; input.style.height = "auto"; }

  const chat = document.getElementById("editor-chat");
  chat.innerHTML += userCard(msg);
  chat.innerHTML += monoTypingCard();
  scrollChatToBottom(chat);

  state.chatHistory.push({ role: "user", content: msg });

  const controller = new AbortController();
  aiInFlight = controller;
  setSendButtonRunning(true);
  try {
    const connection = state.aiConnections.find(p => p.id === selectedValue.slice(9));
    if (!connection) throw new Error("Selected connection no longer exists — pick another one from the pill above.");

    // openai-protocol connections run the server-side agent tool-use loop
    // over SSE; anthropic / gemini fall back to one-shot /chat.
    if (usesAgentPath(connection)) {
      await sendAgent(connection, msg, chat, controller.signal);
      return;
    }

    const providerId = connection.provider;
    const model = connection.model;
    const byok = {
      apiKey: connection.apiKey,
      baseUrl: connection.baseUrl || undefined,
    };

    console.group("[MONO Chat]");
    console.log("→", providerId, "·", model, byok.baseUrl ? `@ ${byok.baseUrl}` : "");
    console.log("→ message:", msg);
    console.log("→ files:", state.currentFiles.map(f => f.name));
    console.groupEnd();

    const res = await apiFetch("/chat", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        gameId: state.currentGameId,
        message: msg,
        files: state.currentFiles,
        history: state.chatHistory.slice(0, -1),
        provider: providerId,
        model,
        byok,
      }),
      signal: controller.signal,
    });

    const data = await res.json();
    if (!res.ok) throw new Error(data.error || "Request failed");

    console.group("[MONO Response]");
    console.log("← status:", res.status);
    console.log("← message:", data.message);
    console.log("← files:", data.files?.map(f => ({ name: f.name, size: f.content?.length || 0 })) || []);
    if (data.usage) {
      console.log("← usage:", data.usage);
      // Anthropic prompt-cache telemetry — highlights the cache-hit ratio
      // so it's obvious when the breakpoint is paying off.
      const u = data.usage;
      if (u.cache_read_input_tokens || u.cache_creation_input_tokens) {
        const fresh = u.prompt_tokens || 0;
        const cached = u.cache_read_input_tokens || 0;
        const written = u.cache_creation_input_tokens || 0;
        const total = fresh + cached;
        const hitRatio = total > 0 ? Math.round((cached / total) * 100) : 0;
        console.log(`← cache: ${cached}/${total} tokens reused (${hitRatio}% hit, ${written} newly cached)`);
      }
    }
    console.groupEnd();

    state.chatHistory.push({ role: "assistant", content: data.message });
    updateUsageDisplay(data);
    saveChatHistory();

    // Track file changes
    const changedFiles = [];
    if (data.files && data.files.length > 0) {
      for (const f of data.files) {
        const idx = state.currentFiles.findIndex(c => c.name === f.name);
        const action = idx >= 0 ? "edited" : "created";
        if (idx >= 0) state.currentFiles[idx] = f;
        else state.currentFiles.push(f);
        changedFiles.push({ name: f.name, _action: action });
      }
      const { renderFileTree } = window._editorFiles || {};
      if (renderFileTree) renderFileTree();
    }

    // Replace typing card with completed response
    const typing = document.getElementById("mono-typing");
    if (typing) {
      typing.outerHTML = monoCard(data.message, changedFiles, "completed");
    }

    // Auto headless test (no auto-retry: user must confirm fix via Fix button)
    if (state.autoFixEnabled && data.files && data.files.length > 0) {
      addChatMsg("mono", "Running test…");
      const testResult = await runHeadlessTest(state.currentFiles, 30);
      if (testResult.success) {
        addChatMsg("mono", "✓ Test passed (" + (testResult.frames || 30) + " frames)");
      } else {
        const testErrors = (testResult.errors || []).join("\n");
        chat.innerHTML += errorCard(testErrors, "TEST FAILED");
        scrollChatToBottom(chat);
      }
    }
  } catch (e) {
    const typing = document.getElementById("mono-typing");
    if (typing) {
      const label = isAbortError(e) ? "STOPPED" : "API ERROR";
      const msg = isAbortError(e) ? "Stopped by user." : e.message;
      typing.outerHTML = errorCard(msg, label, false);
    }
  } finally {
    aiInFlight = null;
    setSendButtonRunning(false);
  }
  scrollChatToBottom(chat);
}

// ── Init ──

export function initEditorAI() {
  // Send button — doubles as Stop while a request is in flight.
  // setSendButtonRunning() flips the icon + class so the click target
  // reflects what'll happen.
  document.getElementById("btn-send").addEventListener("click", () => {
    if (aiInFlight) aiInFlight.abort();
    else sendMessage();
  });

  // Textarea
  const editorMsg = document.getElementById("editor-msg");
  let isComposing = false;
  editorMsg.addEventListener("compositionstart", () => { isComposing = true; });
  editorMsg.addEventListener("compositionend", () => { isComposing = false; });
  editorMsg.addEventListener("keydown", (e) => {
    e.stopPropagation();
    if (e.key === "Enter" && !e.shiftKey && !isComposing && !e.isComposing) { e.preventDefault(); sendMessage(); }
  });
  editorMsg.addEventListener("keyup", (e) => e.stopPropagation());
  editorMsg.addEventListener("keypress", (e) => e.stopPropagation());

  // Chat area event delegation
  document.getElementById("editor-chat").addEventListener("click", async (e) => {
    // Stop button (rendered inside the working agent card) → abort
    // the in-flight fetch. The catch path in sendMessage / sendAgent
    // turns this into a "STOPPED" card and clears aiInFlight in finally.
    if (e.target.closest("#btn-ai-stop")) {
      aiInFlight?.abort();
      return;
    }
    // Retry button → re-send that user message
    const retryBtn = e.target.closest(".ai-card-retry");
    if (retryBtn) {
      const card = retryBtn.closest(".ai-card-user");
      const body = card?.querySelector(".ai-card-body");
      if (body) sendMessage(body.textContent);
      return;
    }
    // Fix button on error card → show prompt confirmation popup
    const fixBtn = e.target.closest(".ai-card-fix");
    if (fixBtn) {
      const card = fixBtn.closest(".ai-card-error");
      const errText = card?.querySelector(".ai-card-response")?.textContent || "";
      const label = card?.querySelector(".ai-card-status")?.textContent || "ERROR";
      if (errText) showFixConfirm(errText, label);
      return;
    }
    // Agent trace toggle → expand/collapse the reasoning + tool log.
    const traceBtn = e.target.closest(".ai-trace-toggle");
    if (traceBtn) {
      const card = traceBtn.closest(".ai-card-mono");
      const panel = card?.querySelector(".ai-trace");
      if (!panel) return;
      const expanded = traceBtn.dataset.expanded === "1";
      if (expanded) {
        panel.hidden = true;
        traceBtn.dataset.expanded = "0";
        traceBtn.textContent = traceBtn.textContent.replace(/^▾/, "▸").replace("Hide trace", "Show trace");
      } else {
        panel.hidden = false;
        traceBtn.dataset.expanded = "1";
        traceBtn.textContent = traceBtn.textContent.replace(/^▸/, "▾").replace("Show trace", "Hide trace");
      }
      return;
    }
  });
}
