// ── AI Tab: Chat, send message, test & fix ──

import { state, esc, chatTime, MAX_FIX_RETRIES } from './state.js';
import { apiFetch, saveChatHistory } from './api.js';
import { runHeadlessTest } from './editor-play.js';

// ── Card builders ──

const RETRY_SVG = '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2"><path d="M1 4v6h6"/><path d="M3.51 15a9 9 0 102.13-9.36L1 10"/></svg>';
const STOP_SVG = '<svg viewBox="0 0 24 24" width="10" height="10" fill="currentColor"><rect x="6" y="6" width="12" height="12" rx="1"/></svg>';

// Strip fenced code blocks and collapse whitespace so the chat card
// shows only the explanation — code lives in the file list below.
function cleanMessage(s) {
  if (!s) return s;
  return s
    .replace(/```[\s\S]*?```/g, '')
    .replace(/`([^`\n]+)`/g, '$1')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
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
  if (cleaned) html += `<div class="ai-card-response">${esc(cleaned)}</div>`;
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

function monoTypingCard() {
  return `<div class="ai-card-mono working" id="mono-typing">
    <div class="ai-card-status working">MONO · working…</div>
    <div class="ai-card-response" style="color:#888">Thinking…</div>
  </div>`;
}

function errorCard(msg) {
  return `<div class="ai-card-error">
    <div class="ai-card-status">ERROR</div>
    <div class="ai-card-response">${esc(msg)}</div>
    <button class="ai-card-fix" data-error="${esc(msg)}">Fix</button>
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
  chat.scrollTop = chat.scrollHeight;
}

export function renderChatHistory() {
  const chat = document.getElementById("editor-chat");

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
  chat.scrollTop = chat.scrollHeight;
}

// ── Engine error (shown inline as error card) ──

export function showEngineError(msg) {
  state.lastEngineError = msg;
  const chat = document.getElementById("editor-chat");
  chat.innerHTML += errorCard(msg);
  chat.scrollTop = chat.scrollHeight;
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

// ── Send message ──

export async function sendMessage(autoMsg) {
  const input = document.getElementById("editor-msg");
  const msg = autoMsg || input.value.trim();
  if (!msg) return;
  if (!autoMsg) { input.value = ""; input.style.height = "auto"; }

  const chat = document.getElementById("editor-chat");
  chat.innerHTML += userCard(msg);
  chat.innerHTML += monoTypingCard();
  chat.scrollTop = chat.scrollHeight;

  state.chatHistory.push({ role: "user", content: msg });

  try {
    const selectedValue = document.getElementById("model-select").value;
    let model, byok;
    if (selectedValue.startsWith("provider:")) {
      const provider = state.aiProviders.find(p => p.id === selectedValue.slice(9));
      if (provider) {
        model = provider.model;
        byok = { key: provider.key, url: provider.url || undefined };
      }
    }
    if (!model) model = selectedValue;

    console.group("[MONO Chat]");
    console.log("→ model:", model);
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
        model,
        byok,
      }),
    });

    const data = await res.json();
    if (!res.ok) throw new Error(data.error || "Request failed");

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

    // Auto headless test
    if (state.autoFixEnabled && data.files && data.files.length > 0) {
      if (!autoMsg) state.currentFixAttempt = 0;
      addChatMsg("mono", "Running test…");
      const testResult = await runHeadlessTest(state.currentFiles, 30);
      if (testResult.success) {
        addChatMsg("mono", "✓ Test passed (" + (testResult.frames || 30) + " frames)");
      } else {
        const testErrors = (testResult.errors || []).join("\n");
        addChatMsg("mono", "✗ Test failed:\n" + testErrors);
        if (state.currentFixAttempt < MAX_FIX_RETRIES) {
          state.currentFixAttempt++;
          addChatMsg("mono", "Auto-fixing… (" + state.currentFixAttempt + "/" + MAX_FIX_RETRIES + ")");
          await sendMessage("Fix these runtime errors:\n" + testErrors);
        }
      }
    }
  } catch (e) {
    const typing = document.getElementById("mono-typing");
    if (typing) {
      typing.outerHTML = errorCard(e.message);
    }
  }
  chat.scrollTop = chat.scrollHeight;
}

// ── Init ──

export function initEditorAI() {
  // Send button
  document.getElementById("btn-send").addEventListener("click", () => sendMessage());

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
    // Retry button → re-send that user message
    const retryBtn = e.target.closest(".ai-card-retry");
    if (retryBtn) {
      const card = retryBtn.closest(".ai-card-user");
      const body = card?.querySelector(".ai-card-body");
      if (body) sendMessage(body.textContent);
      return;
    }
    // Fix button on error card
    const fixBtn = e.target.closest(".ai-card-fix");
    if (fixBtn) {
      const errMsg = fixBtn.dataset.error;
      if (errMsg) {
        clearEngineError();
        sendMessage("Fix this runtime error:\n" + errMsg);
      }
      return;
    }
  });
}
