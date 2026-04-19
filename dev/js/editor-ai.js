// ── AI Tab: Chat, send message, test & fix ──

import { state, esc, chatTime, API_URL, MAX_FIX_RETRIES } from './state.js';
import { apiFetch, saveChatHistory } from './api.js';
import { runHeadlessTest } from './editor-play.js';

// ── Chat rendering ──

export function addChatMsg(sender, body) {
  const chat = document.getElementById("editor-chat");
  const cls = sender === "mono" ? "mono" : "";
  chat.innerHTML += `<div class="chat-msg"><span class="chat-sender ${cls}">${sender.toUpperCase()}<span class="chat-time">${chatTime()}</span></span><span class="chat-body">${esc(body)}</span><button class="chat-copy" title="Copy"><svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"/></svg></button></div>`;
  chat.scrollTop = chat.scrollHeight;
}

export function renderChatHistory() {
  const chat = document.getElementById("editor-chat");
  const usage = document.getElementById("editor-usage");
  if (usage) usage.textContent = "";

  if (state.chatHistory.length > 0) {
    let html = '';
    for (const h of state.chatHistory) {
      const cls = h.role === "assistant" ? "mono" : "";
      const label = h.role === "assistant" ? "MONO" : "YOU";
      html += `<div class="chat-msg"><span class="chat-sender ${cls}">${label}</span><span class="chat-body">${esc(h.content)}</span></div>`;
    }
    chat.innerHTML = html;
    if (state.currentFiles.length > 0) {
      chat.innerHTML += '<div class="chat-msg"><span class="chat-sender mono">MONO</span><span class="chat-body">Session restored.</span><div class="chat-files">';
      for (const f of state.currentFiles) chat.innerHTML += `<span class="chat-file">${esc(f.name)}</span>`;
      chat.innerHTML += '</div></div>';
    }
  } else if (state.currentFiles.length > 0) {
    let html = '<div class="chat-msg"><span class="chat-sender mono">MONO</span><span class="chat-body">Loaded existing files.</span><div class="chat-files">';
    for (const f of state.currentFiles) html += `<span class="chat-file">${esc(f.name)}</span>`;
    html += '</div></div>';
    chat.innerHTML = html;
  } else {
    chat.innerHTML = '<div class="chat-msg"><span class="chat-sender mono">MONO</span><span class="chat-body">Game created. Describe what you want to build!</span></div>';
  }
  chat.scrollTop = chat.scrollHeight;
}

// ── Error bar ──

export function showEngineError(msg) {
  state.lastEngineError = msg;
  const bar = document.getElementById("editor-error-bar");
  document.getElementById("editor-error-msg").textContent = msg;
  bar.classList.add("show");
}

export function clearEngineError() {
  state.lastEngineError = null;
  document.getElementById("editor-error-bar").classList.remove("show");
}

// ── Usage display ──

function updateUsageDisplay(data) {
  const usage = data?.usage;
  if (!usage) return;
  state.sessionTokens.prompt += usage.prompt_tokens || 0;
  state.sessionTokens.completion += usage.completion_tokens || 0;
  state.sessionTokens.total += usage.total_tokens || 0;
  const game = data.gameUsage;
  const display = game
    ? `game: ${game.total_tokens.toLocaleString()} · session: ${state.sessionTokens.total.toLocaleString()} (↑${state.sessionTokens.prompt.toLocaleString()} ↓${state.sessionTokens.completion.toLocaleString()})`
    : `tokens: ${state.sessionTokens.total.toLocaleString()} (↑${state.sessionTokens.prompt.toLocaleString()} ↓${state.sessionTokens.completion.toLocaleString()})`;
  document.getElementById("editor-usage").textContent = display;
}

// ── Send message ──

export async function sendMessage(autoMsg) {
  const input = document.getElementById("editor-msg");
  const msg = autoMsg || input.value.trim();
  if (!msg) return;
  if (!autoMsg) { input.value = ""; input.style.height = "auto"; }

  const chat = document.getElementById("editor-chat");
  chat.innerHTML += `<div class="chat-msg"><span class="chat-sender">YOU<span class="chat-time">${chatTime()}</span></span><span class="chat-body">${esc(msg)}</span><button class="chat-copy" title="Copy"><svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"/></svg></button></div>`;
  chat.innerHTML += `<div class="chat-msg" id="mono-typing"><span class="chat-sender mono">MONO</span><span class="chat-status">working...</span></div>`;
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
        history: [],
        model,
        byok,
      }),
    });

    const data = await res.json();
    console.group("[MONO Response]");
    console.log("← status:", res.status);
    console.log("← message:", data.message);
    console.log("← files:", data.files?.map(f => f.name));
    console.log("← test:", data.test);
    console.log("← usage:", data.usage);
    if (data.error) console.error("← error:", data.error, data.detail);
    console.groupEnd();

    if (!res.ok) throw new Error(data.error || "Request failed");

    state.chatHistory.push({ role: "assistant", content: data.message });
    updateUsageDisplay(data);
    saveChatHistory();

    // Update files
    if (data.files && data.files.length > 0) {
      for (const f of data.files) {
        const idx = state.currentFiles.findIndex(c => c.name === f.name);
        if (idx >= 0) state.currentFiles[idx] = f;
        else state.currentFiles.push(f);
      }
      // Refresh file tree
      const { renderFileTree } = window._editorFiles || {};
      if (renderFileTree) renderFileTree();
    }

    const typing = document.getElementById("mono-typing");
    if (typing) {
      let html = `<span class="chat-sender mono">MONO<span class="chat-time">${chatTime()}</span></span><span class="chat-body">${esc(data.message)}</span>`;
      if (data.files && data.files.length > 0) {
        html += '<div class="chat-files">';
        for (const f of data.files) {
          html += `<span class="chat-file created">${esc(f.name)}</span>`;
        }
        html += '</div>';
      }
      html += `<button class="chat-copy" title="Copy"><svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"/></svg></button>`;
      typing.id = "";
      typing.innerHTML = html;
    }

    // Auto headless test
    if (state.autoFixEnabled && data.files && data.files.length > 0) {
      if (!autoMsg) state.currentFixAttempt = 0;
      addChatMsg("mono", "Running test...");
      const testResult = await runHeadlessTest(state.currentFiles, 30);
      if (testResult.success) {
        addChatMsg("mono", "✓ Test passed (" + (testResult.frames || 30) + " frames)");
      } else {
        const testErrors = (testResult.errors || []).join("\n");
        addChatMsg("mono", "✗ Test failed:\n" + testErrors);
        if (state.currentFixAttempt < MAX_FIX_RETRIES) {
          state.currentFixAttempt++;
          addChatMsg("mono", "Auto-fixing... (" + state.currentFixAttempt + "/" + MAX_FIX_RETRIES + ")");
          await sendMessage("Fix these runtime errors:\n" + testErrors);
        }
      }
    }
  } catch (e) {
    const typing = document.getElementById("mono-typing");
    if (typing) {
      typing.id = "";
      typing.innerHTML = `<span class="chat-sender mono">MONO</span><span class="chat-body" style="color:#ff6666">Error: ${esc(e.message)}</span>`;
    }
  }
  chat.scrollTop = chat.scrollHeight;
}

// ── Test & Fix ──

async function testAndFix() {
  const mainFile = state.currentFiles.find(f => f.name === "main.lua");
  if (!mainFile) {
    addChatMsg("mono", "No main.lua to test.");
    return;
  }

  const btn = document.getElementById("btn-test-fix");
  btn.className = "editor-test-btn testing";
  btn.innerHTML = '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M14.7 6.3a1 1 0 000 1.4l1.6 1.6a1 1 0 001.4 0l3.77-3.77a6 6 0 01-7.94 7.94l-6.91 6.91a2.12 2.12 0 01-3-3l6.91-6.91a6 6 0 017.94-7.94l-3.76 3.76z"/></svg> Testing...';

  const result = await runHeadlessTest(state.currentFiles, 30);

  if (result.success) {
    btn.className = "editor-test-btn pass";
    btn.innerHTML = '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><polyline points="20 6 9 17 4 12"/></svg> Pass';
    addChatMsg("mono", "✓ Test passed (" + (result.frames || 30) + " frames)");
  } else {
    btn.className = "editor-test-btn fail";
    btn.innerHTML = '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg> Failed';
    const errorText = (result.errors || []).join("\n");
    addChatMsg("mono", "✗ Test failed:\n" + errorText);
    state.currentFixAttempt = 0;
    await sendMessage("Fix these runtime errors:\n" + errorText);
  }
  setTimeout(() => resetTestBtn(), 3000);
}

function resetTestBtn() {
  const btn = document.getElementById("btn-test-fix");
  btn.className = "editor-test-btn";
  btn.innerHTML = '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M14.7 6.3a1 1 0 000 1.4l1.6 1.6a1 1 0 001.4 0l3.77-3.77a6 6 0 01-7.94 7.94l-6.91 6.91a2.12 2.12 0 01-3-3l6.91-6.91a6 6 0 017.94-7.94l-3.76 3.76z"/></svg> Test &amp; Fix';
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
  editorMsg.addEventListener("input", () => {
    editorMsg.style.height = "auto";
    editorMsg.style.height = Math.min(editorMsg.scrollHeight, 120) + "px";
  });

  // Test & Fix
  document.getElementById("btn-test-fix").addEventListener("click", testAndFix);

  // Error bar fix
  document.getElementById("btn-error-fix").addEventListener("click", () => {
    if (!state.lastEngineError) return;
    document.getElementById("editor-msg").value = "Fix this runtime error:\n" + state.lastEngineError;
    clearEngineError();
    sendMessage();
  });

  // Copy chat (event delegation)
  document.getElementById("editor-chat").addEventListener("click", async (e) => {
    const btn = e.target.closest(".chat-copy");
    if (!btn) return;
    const msg = btn.closest(".chat-msg");
    const body = msg.querySelector(".chat-body");
    if (body) {
      await navigator.clipboard.writeText(body.textContent);
      btn.classList.add("copied");
      setTimeout(() => btn.classList.remove("copied"), 1500);
    }
  });
}
