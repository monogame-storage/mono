// ── Editor main controller ──
// Tab switching, openEditor(), state binding

import { state, esc, showView } from './state.js';
import { apiFetch } from './api.js';
import {
  doc,
  getDoc,
} from "https://www.gstatic.com/firebasejs/11.7.1/firebase-firestore.js";
import { decryptData, updateModelSelector, saveProviders, openAIProviders } from './settings.js';
import { initEditorAI, renderChatHistory, clearEngineError } from './editor-ai.js';
import { initEditorPlay, stopGame } from './editor-play.js';
import { initEditorFiles } from './editor-files.js';
import { initEditorGame } from './editor-game.js';

// ── Tab switching ──

let currentTab = "files";

const TAB_TOPBAR_BUTTONS = {
  files: (nav) => {
    // Push (upload) + Pull (download) buttons per design
    nav.innerHTML = `
      <button class="editor-icon-btn" id="btn-push" title="Push to Local">
        <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/></svg>
      </button>
      <button class="editor-icon-btn" id="btn-pull" title="Pull from Local">
        <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
      </button>`;
    // Re-init sync handlers after DOM rebuild
    const { initTopbarHandlers } = window._editorFiles || {};
    if (initTopbarHandlers) initTopbarHandlers();
  },
  ai: (nav) => {
    // Provider pill — shows current model name
    const sel = document.getElementById("model-select");
    const label = sel ? sel.options[sel.selectedIndex]?.textContent || "Model" : "Model";
    nav.innerHTML = `
      <button class="ai-provider-pill" id="btn-provider-pill">
        <span class="pill-icon"><svg viewBox="0 0 24 24" width="12" height="12" fill="currentColor"><path d="M12 2L9.19 8.63 2 9.24l5.46 4.73L5.82 21 12 17.27 18.18 21l-1.64-7.03L22 9.24l-7.19-.61z"/></svg></span>
        <span class="pill-label">${label}</span>
        <span class="pill-chev"><svg viewBox="0 0 24 24" width="10" height="10" fill="none" stroke="currentColor" stroke-width="2"><polyline points="6 9 12 15 18 9"/></svg></span>
      </button>`;
    // Click pill → open hidden <select>
    nav.querySelector("#btn-provider-pill")?.addEventListener("click", () => {
      const select = document.getElementById("model-select");
      if (select) {
        select.style.display = "block";
        select.style.position = "fixed";
        select.style.opacity = "0";
        select.focus();
        select.click();
        // On change/blur, re-hide and update pill label
        const hide = () => {
          select.style.display = "none";
          const newLabel = select.options[select.selectedIndex]?.textContent || "Model";
          const pillLabel = nav.querySelector(".pill-label");
          if (pillLabel) pillLabel.textContent = newLabel;
          select.removeEventListener("blur", hide);
        };
        select.addEventListener("change", hide, { once: true });
        select.addEventListener("blur", hide, { once: true });
      }
    });
  },
  play: (nav) => {
    const shaderOn = state._shaderEnabled;
    nav.innerHTML = `
      <button class="editor-icon-btn${shaderOn ? ' active-toggle' : ''}" id="btn-shader" title="Shader">
        <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 2.69l5.66 5.66a8 8 0 11-11.31 0z"/></svg>
      </button>
      <button class="editor-icon-btn" id="btn-reset" title="Reset">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M1 4v6h6"/><path d="M3.51 15a9 9 0 102.13-9.36L1 10"/></svg>
      </button>`;
    // Re-init play handlers after DOM rebuild
    const { initPlayTopbarHandlers } = window._editorPlay || {};
    if (initPlayTopbarHandlers) initPlayTopbarHandlers();
  },
  game: (nav) => {
    nav.innerHTML = '';
  },
};

export function switchTab(name) {
  const prevTab = currentTab;
  currentTab = name;

  // Toggle panels
  document.querySelectorAll(".editor-tab-panel").forEach(p => p.classList.remove("active"));
  const panel = document.getElementById(`tab-${name}`);
  if (panel) panel.classList.add("active");
  // Toggle bottomnav
  document.querySelectorAll(".editor-bottomnav button").forEach(b => {
    b.classList.toggle("active", b.dataset.tab === name);
  });
  // Update topbar right
  const nav = document.getElementById("editor-nav-right");
  const builder = TAB_TOPBAR_BUTTONS[name];
  if (builder) builder(nav);

  // Update URL hash to reflect tab
  if (state.currentGameId) {
    location.hash = `editor/${state.currentGameId}/${name}`;
  }

  // Auto-run game when entering Play tab, stop when leaving
  if (name === "play" && prevTab !== "play") {
    const { runGame } = window._editorPlay || {};
    if (runGame && !state.gameRunning) runGame();
  } else if (name !== "play" && prevTab === "play" && state.gameRunning) {
    stopGame();
  }
}

// ── openEditor ──

export async function openEditor(gameId, title, desc) {
  // Stop any running game
  if (state.gameRunning) stopGame();
  try { Mono.stop(); } catch {}
  const canvas = document.getElementById("editor-screen");
  const ctx = canvas.getContext("2d");
  ctx.clearRect(0, 0, canvas.width, canvas.height);

  // Reset state
  state.currentGameId = gameId;
  state.currentGameTitle = title;
  state.currentGameDesc = desc || "";
  state.currentGameStatus = "draft";
  state.currentPublishedVersion = 0;
  state.chatHistory.length = 0;
  state.currentFiles = [];
  for (const url of Object.values(state.currentAssets)) { try { URL.revokeObjectURL(url); } catch {} }
  state.currentAssets = {};
  state.sessionTokens = { prompt: 0, completion: 0, total: 0 };
  state.lastEngineError = null;
  clearEngineError();

  // Clear UI from previous session
  document.getElementById("editor-msg").value = "";
  // (usage display removed — tracked in state only)

  // Load game status
  try {
    const gameSnap = await getDoc(doc(state.db, "games", gameId));
    if (gameSnap.exists()) {
      const gd = gameSnap.data();
      state.currentGameStatus = gd.status || "draft";
      state.currentPublishedVersion = gd.publishedVersion || 0;
    }
  } catch {}

  // Load AI providers if needed
  if (state.aiProviders.length === 0 && localStorage.getItem("mono_vault_pp")) {
    try {
      const uid = state.auth.currentUser.uid;
      const snap = await getDoc(doc(state.db, "users", uid, "settings", "ai"));
      if (snap.exists() && snap.data().encrypted) {
        state.aiProviders = await decryptData(localStorage.getItem("mono_vault_pp"), snap.data().encrypted);
        updateModelSelector();
      }
    } catch {}
  }

  document.getElementById("editor-title").textContent = title;
  location.hash = `editor/${gameId}/files`;

  // Show loading state
  document.getElementById("editor-chat").innerHTML =
    '<div class="chat-msg"><span class="chat-sender mono">MONO</span><span class="chat-status">Loading...</span></div>';

  showView("editor");

  // Default to Files tab
  switchTab("files");

  // Load files from R2
  try {
    const res = await apiFetch(`/games/${gameId}/files`);
    const { files } = await res.json();
    if (files && files.length > 0) {
      const gameFiles = files.filter(f => !f.name.startsWith("_"));
      const isImage = (n) => /\.(png|jpg|jpeg|gif|bmp|webp)$/i.test(n);
      const results = await Promise.allSettled(gameFiles.map(async (f) => {
        const r = await apiFetch(`/games/${gameId}/files/${f.name}`);
        if (!r.ok) throw new Error(`${f.name}: ${r.status}`);
        if (isImage(f.name)) {
          const blob = await r.blob();
          return { name: f.name, blobUrl: URL.createObjectURL(blob) };
        }
        const { content } = await r.json();
        return { name: f.name, content };
      }));
      for (const r of results) {
        if (r.status !== "fulfilled") continue;
        const f = r.value;
        if (f.blobUrl) {
          state.currentAssets[f.name] = f.blobUrl;
        } else {
          state.currentFiles.push(f);
        }
      }
    }
  } catch {}

  // Load chat history
  try {
    const histRes = await apiFetch(`/games/${gameId}/files/_chat.json`);
    if (histRes.ok) {
      const histData = await histRes.json();
      if (histData.content) {
        const saved = JSON.parse(histData.content);
        if (saved.history) state.chatHistory.push(...saved.history);
      }
    }
  } catch {}

  // Render content for each tab
  renderChatHistory();
  const { renderFileTree } = window._editorFiles || {};
  if (renderFileTree) renderFileTree();

}

// ── Init ──

export function initEditor() {
  // Back button
  document.getElementById("btn-editor-back").addEventListener("click", () => {
    stopGame();
    state.currentGameId = null;
    location.hash = "";
    showView("dashboard");
  });

  // Bottom nav
  document.querySelector(".editor-bottomnav").addEventListener("click", (e) => {
    const btn = e.target.closest("button[data-tab]");
    if (btn) switchTab(btn.dataset.tab);
  });

  // Model selector persistence
  const savedModel = localStorage.getItem("mono_model");
  if (savedModel) document.getElementById("model-select").value = savedModel;
  document.getElementById("model-select").addEventListener("change", (e) => {
    const val = e.target.value;
    localStorage.setItem("mono_model", val);
    if (val.startsWith("provider:")) {
      const noUserDefault = !state.aiProviders.some(p => p.isDefault);
      if (noUserDefault) {
        const pid = val.slice(9);
        state.aiProviders.forEach(p => p.isDefault = (p.id === pid));
        saveProviders();
      }
    }
  });

  // (AI provider shortcut moved to topbar provider pill)

  // Key interception: only forward to engine when game running and no input focused
  document.addEventListener("keydown", (e) => {
    const focused = e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA" || e.target.tagName === "SELECT";
    if (focused || !state.gameRunning) e.stopPropagation();
  }, true);
  document.addEventListener("keyup", (e) => {
    const focused = e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA" || e.target.tagName === "SELECT";
    if (focused || !state.gameRunning) e.stopPropagation();
  }, true);

  // Init sub-modules
  initEditorAI();
  initEditorPlay();
  initEditorFiles();
  initEditorGame();
}
