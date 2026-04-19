// ── Editor main controller ──
// Tab switching, openEditor(), state binding

import { state, esc, showView } from './state.js';
import { apiFetch } from './api.js';
import {
  doc,
  getDoc,
} from "https://www.gstatic.com/firebasejs/11.7.1/firebase-firestore.js";
import { decryptData, updateModelSelector, saveProviders, openAIProviders } from './settings.js';
import { initEditorAI, renderChatHistory } from './editor-ai.js';
import { initEditorPlay, stopGame, buildScaleOptions, applyScale } from './editor-play.js';
import { initEditorFiles } from './editor-files.js';
import { initEditorGame } from './editor-game.js';

// ── Tab switching ──

let currentTab = "files";

const TAB_TOPBAR_BUTTONS = {
  files: (nav) => {
    // Sync button + Save
    nav.innerHTML = `
      <button class="editor-icon-btn" id="btn-save" title="Save">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M19 21H5a2 2 0 01-2-2V5a2 2 0 012-2h11l5 5v11a2 2 0 01-2 2z"/><polyline points="17,21 17,13 7,13 7,21"/><polyline points="7,3 7,8 15,8"/></svg>
      </button>
      <div class="sync-wrap">
        <button class="editor-icon-btn" id="btn-sync" title="Local Sync">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 19a2 2 0 01-2 2H4a2 2 0 01-2-2V5a2 2 0 012-2h5l2 3h9a2 2 0 012 2z"/></svg>
        </button>
        <div class="sync-menu" id="sync-menu">
          <div class="sync-folder-name" id="sync-folder-name" style="display:none"></div>
          <button id="btn-sync-link">Link Folder…</button>
          <button id="btn-sync-push" disabled>Push to Local</button>
          <button id="btn-sync-pull" disabled>Pull from Local</button>
        </div>
      </div>`;
    // Restore linked state
    if (state.linkedDirHandle) {
      const syncBtn = nav.querySelector("#btn-sync");
      if (syncBtn) syncBtn.classList.add("linked");
      const pushBtn = nav.querySelector("#btn-sync-push");
      const pullBtn = nav.querySelector("#btn-sync-pull");
      if (pushBtn) pushBtn.disabled = false;
      if (pullBtn) pullBtn.disabled = false;
      const folderName = nav.querySelector("#sync-folder-name");
      if (folderName) {
        folderName.textContent = state.linkedDirHandle.name;
        folderName.style.display = "block";
      }
      const linkBtn = nav.querySelector("#btn-sync-link");
      if (linkBtn) linkBtn.textContent = "Change Folder…";
    }
    // Save button handler
    const saveBtn = nav.querySelector("#btn-save");
    if (saveBtn) {
      saveBtn.addEventListener("click", async () => {
        const { saveFile } = await import('./api.js');
        saveBtn.style.background = "#555";
        try {
          for (const f of state.currentFiles) {
            if (!f.name.startsWith("_")) await saveFile(f.name, f.content);
          }
          saveBtn.style.background = "#2a5a2a";
          setTimeout(() => { saveBtn.style.background = "#333"; }, 1500);
        } catch (e) {
          alert("Save failed: " + e.message);
          saveBtn.style.background = "#333";
        }
      });
    }
    // Re-init sync handlers after DOM rebuild
    const { initSyncHandlers } = window._editorFiles || {};
    if (initSyncHandlers) initSyncHandlers();
  },
  ai: (nav) => {
    nav.innerHTML = '';
  },
  play: (nav) => {
    nav.innerHTML = `
      <button class="editor-icon-btn" id="btn-run" title="Run">
        <svg viewBox="0 0 24 24" fill="currentColor"><polygon points="5,3 19,12 5,21"/></svg>
      </button>
      <select class="editor-scale-select" id="editor-scale"></select>`;
    // Re-init play handlers after DOM rebuild
    const { initPlayTopbarHandlers } = window._editorPlay || {};
    if (initPlayTopbarHandlers) initPlayTopbarHandlers();
    // Restore run button state
    if (state.gameRunning) {
      const btn = nav.querySelector("#btn-run");
      if (btn) btn.style.background = "#ff4444";
    }
  },
  game: (nav) => {
    nav.innerHTML = '';
  },
};

export function switchTab(name) {
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
  location.hash = `editor/${gameId}`;
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

  // Scale setup after layout settles
  setTimeout(() => {
    buildScaleOptions();
    applyScale();
  }, 0);
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

  // AI shortcut
  document.getElementById("btn-editor-aip").addEventListener("click", openAIProviders);

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
