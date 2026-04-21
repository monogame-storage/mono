// ── AI Tab: Chat, send message, test & fix ──

import { state, esc, chatTime } from './state.js';
import { apiFetch, saveChatHistory } from './api.js';
import { runHeadlessTest } from './editor-play.js';
import { openAIProviders } from './settings.js';

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

function monoTypingCard() {
  return `<div class="ai-card-mono working" id="mono-typing">
    <div class="ai-card-status working">MONO · working…</div>
    <div class="ai-card-response" style="color:#888">Thinking…</div>
  </div>`;
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
  chat.innerHTML += errorCard(msg, "RUNTIME ERROR");
  chat.scrollTop = chat.scrollHeight;
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

// ── Send message ──

export async function sendMessage(autoMsg) {
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
      "Register an AI provider in Settings → AI Providers, then pick it from the pill above to enable chat.",
      "NO PROVIDER",
      false,
    );
    chatEl.scrollTop = chatEl.scrollHeight;
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
  chat.scrollTop = chat.scrollHeight;

  state.chatHistory.push({ role: "user", content: msg });

  try {
    const provider = state.aiProviders.find(p => p.id === selectedValue.slice(9));
    if (!provider) throw new Error("Selected provider no longer exists — pick another one from the pill above.");
    const model = provider.model;
    const byok = {
      key: provider.key,
      url: provider.url || undefined,
      modelName: provider.modelName || undefined,
    };

    console.group("[MONO Chat]");
    console.log("→ model:", model, byok.modelName ? `(override: ${byok.modelName})` : "");
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

    console.group("[MONO Response]");
    console.log("← status:", res.status);
    console.log("← message:", data.message);
    console.log("← files:", data.files?.map(f => ({ name: f.name, size: f.content?.length || 0 })) || []);
    if (data.usage) console.log("← usage:", data.usage);
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
        chat.scrollTop = chat.scrollHeight;
      }
    }
  } catch (e) {
    const typing = document.getElementById("mono-typing");
    if (typing) {
      typing.outerHTML = errorCard(e.message, "API ERROR", false);
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
    // Fix button on error card → show prompt confirmation popup
    const fixBtn = e.target.closest(".ai-card-fix");
    if (fixBtn) {
      const card = fixBtn.closest(".ai-card-error");
      const errText = card?.querySelector(".ai-card-response")?.textContent || "";
      const label = card?.querySelector(".ai-card-status")?.textContent || "ERROR";
      if (errText) showFixConfirm(errText, label);
      return;
    }
  });
}
