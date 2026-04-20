// ── Game Tab: Meta editing, publishing, delete ──

import { state, esc, showView } from './state.js';
import { apiFetch } from './api.js';
import {
  doc,
  serverTimestamp,
} from "https://www.gstatic.com/firebasejs/11.7.1/firebase-firestore.js";
import { runHeadlessTest } from './editor-play.js';
import { openAIProviders } from './settings.js';
import { loadCart, saveCart, buildCart, serializeCart } from './cart.js';

// ── Copyable error popup ──

function showErrorPopup(title, body) {
  const sheet = document.getElementById("file-sheet");
  if (!sheet) { alert(title + "\n\n" + body); return; }

  sheet.innerHTML = `
    <div class="file-sheet-dim"></div>
    <div class="file-sheet-panel">
      <div class="file-sheet-handle"><div class="file-sheet-handle-bar"></div></div>
      <div class="file-sheet-header">
        <div class="file-sheet-left">
          <span class="file-sheet-name">${esc(title)}</span>
        </div>
      </div>
      <div class="fix-confirm-body">
        <div class="fix-confirm-label">Error (click Copy to grab)</div>
        <textarea class="fix-confirm-textarea" id="err-popup-text" spellcheck="false" readonly>${esc(body)}</textarea>
      </div>
      <div class="sync-actions">
        <button class="sync-cancel" id="btn-err-close">Close</button>
        <button class="sync-confirm" id="btn-err-copy">Copy</button>
      </div>
    </div>`;
  sheet.classList.add("open");

  const ta = document.getElementById("err-popup-text");
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
  document.getElementById("btn-err-close").addEventListener("click", close);
  document.getElementById("btn-err-copy").addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(body);
      const btn = document.getElementById("btn-err-copy");
      const orig = btn.textContent;
      btn.textContent = "Copied!";
      setTimeout(() => { btn.textContent = orig; }, 1500);
    } catch {
      ta.select();
    }
  });
}

// ── Publish UI ──

function updatePublishUI() {
  const badge = document.getElementById("publish-badge");
  const version = document.getElementById("publish-version");
  const desc = document.getElementById("publish-desc");
  const btn = document.getElementById("btn-publish");
  const btnUpdate = document.getElementById("btn-update");

  if (state.currentGameStatus === "published") {
    badge.className = "publish-badge published";
    badge.textContent = "Published";
    version.textContent = state.currentPublishedVersion ? `v${state.currentPublishedVersion}` : "";
    desc.textContent = "This game is live. Update to push latest changes, or unpublish to take it offline.";
    btn.textContent = "Unpublish";
    btn.className = "game-publish-btn unpublish";
    btnUpdate.style.display = "";
    btnUpdate.className = "game-publish-btn update";
    btnUpdate.textContent = "Update";
    btnUpdate.disabled = false;
  } else {
    badge.className = "publish-badge draft";
    badge.textContent = "Draft";
    version.textContent = "";
    desc.textContent = "Publish this game to make it publicly playable. A snapshot of the current files will be saved.";
    btn.textContent = "Publish";
    btn.className = "game-publish-btn";
    btnUpdate.style.display = "none";
  }
  btn.disabled = false;
}

function fileListDump() {
  return state.currentFiles
    .filter(f => !f.name.startsWith("_"))
    .map(f => `  ${f.name} (${f.content ? f.content.length : 0} bytes)`)
    .join("\n");
}

async function publishGame() {
  const btn = document.getElementById("btn-publish");
  const mainFile = state.currentFiles.find(f => f.name === "main.lua");
  if (!mainFile) {
    showErrorPopup("Cannot publish", "main.lua is required.\n\nFiles:\n" + fileListDump());
    return;
  }

  btn.disabled = true;
  btn.textContent = "Testing...";

  const result = await runHeadlessTest(state.currentFiles, 30);
  if (!result.success) {
    const errors = (result.errors || []).join("\n");
    const body =
      `Test failed.\n\nErrors:\n${errors}\n\n` +
      `Output:\n${(result.output || []).join("\n") || "(none)"}\n\n` +
      `Files:\n${fileListDump()}`;
    showErrorPopup("Cannot publish: test failed", body);
    btn.disabled = false;
    btn.textContent = "Publish";
    return;
  }

  btn.textContent = "Publishing...";

  // Generate thumbnail
  if (result.screen) {
    try {
      const { buf, w, h, palette } = result.screen;
      const c = new OffscreenCanvas(w, h);
      const ctx = c.getContext("2d");
      const img = ctx.createImageData(w, h);
      for (let i = 0; i < buf.length; i++) {
        const v = palette[buf[i]] ?? 0;
        img.data[i * 4] = v;
        img.data[i * 4 + 1] = v;
        img.data[i * 4 + 2] = v;
        img.data[i * 4 + 3] = 255;
      }
      ctx.putImageData(img, 0, 0);
      const blob = await c.convertToBlob({ type: "image/png" });
      await apiFetch(`/games/${state.currentGameId}/files/thumbnail.png`, {
        method: "PUT",
        headers: { "Content-Type": "application/octet-stream" },
        body: blob,
      });
    } catch (e) {
      console.warn("Thumbnail generation failed:", e);
    }
  }

  try {
    const res = await apiFetch(`/games/${state.currentGameId}/publish`, { method: "POST" });
    if (!res.ok) {
      const text = await res.text();
      let parsed = null;
      try { parsed = JSON.parse(text); } catch {}
      const reason = parsed?.error || parsed?.detail || text || `HTTP ${res.status}`;
      const body =
        `HTTP ${res.status} ${res.statusText}\n\n` +
        `Response:\n${text || "(empty)"}\n\n` +
        `Game ID: ${state.currentGameId}\n\n` +
        `Files:\n${fileListDump()}`;
      showErrorPopup("Publish failed — " + reason.split("\n")[0], body);
      btn.disabled = false;
      btn.textContent = "Publish";
      return;
    }
    const data = await res.json();
    state.currentGameStatus = "published";
    state.currentPublishedVersion = data.version || (state.currentPublishedVersion + 1);
    updatePublishUI();
  } catch (e) {
    const body = `${e.message || e}\n\nGame ID: ${state.currentGameId}\n\nFiles:\n${fileListDump()}`;
    showErrorPopup("Publish failed", body);
    btn.disabled = false;
    btn.textContent = "Publish";
  }
}

async function unpublishGame() {
  if (!confirm("Unpublish this game? It will no longer be publicly playable.")) return;

  const btn = document.getElementById("btn-publish");
  btn.disabled = true;
  btn.textContent = "Unpublishing...";

  try {
    const res = await apiFetch(`/games/${state.currentGameId}/unpublish`, { method: "POST" });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err.error || `Unpublish failed (${res.status})`);
    }
    state.currentGameStatus = "draft";
    updatePublishUI();
  } catch (e) {
    alert("Unpublish failed: " + e.message);
    btn.disabled = false;
    btn.textContent = "Unpublish";
  }
}

// ── Init ──

export function initEditorGame() {
  // Save game info
  document.getElementById("btn-save-info").addEventListener("click", async () => {
    const newTitle = document.getElementById("game-title").value.trim();
    const newDesc = document.getElementById("game-desc").value.trim();
    if (!newTitle) return;

    const btn = document.getElementById("btn-save-info");
    btn.disabled = true;
    btn.textContent = "Saving...";
    try {
      // Firestore is the source of truth — write it first so the value
      // is durable even if the cart.json mirror below fails.
      const { updateDoc } = await import("https://www.gstatic.com/firebasejs/11.7.1/firebase-firestore.js");
      await updateDoc(doc(state.db, "games", state.currentGameId), {
        title: newTitle,
        description: newDesc,
        updatedAt: serverTimestamp(),
      });
      state.currentGameTitle = newTitle;
      state.currentGameDesc = newDesc;
      document.getElementById("editor-title").textContent = newTitle;

      // Mirror to cart.json for offline consumers.
      try {
        const cart = (await loadCart(state.currentGameId)) || await buildCart(newTitle, newDesc);
        cart.title = newTitle;
        if (newDesc) cart.description = newDesc;
        else delete cart.description;
        await saveCart(state.currentGameId, cart);
        const content = serializeCart(cart);
        const existing = state.currentFiles.find(f => f.name === "cart.json");
        if (existing) existing.content = content;
        else state.currentFiles.push({ name: "cart.json", content });
      } catch (e) {
        console.warn("cart.json mirror failed:", e);
      }

      btn.textContent = "Saved!";
      setTimeout(() => { btn.textContent = "Save"; btn.disabled = false; }, 1500);
    } catch (e) {
      alert("Failed to save: " + e.message);
      btn.textContent = "Save";
      btn.disabled = false;
    }
  });

  // Publish / Unpublish
  document.getElementById("btn-publish").addEventListener("click", async () => {
    if (state.currentGameStatus === "published") {
      await unpublishGame();
    } else {
      await publishGame();
    }
  });
  document.getElementById("btn-update").addEventListener("click", async () => {
    await publishGame();
  });

  // AI Provider link
  document.getElementById("btn-game-aip").addEventListener("click", openAIProviders);

  // Delete game
  document.getElementById("btn-delete-game").addEventListener("click", async () => {
    if (!confirm("Are you sure? This will permanently delete this game.")) return;
    if (!confirm("This cannot be undone. Delete forever?")) return;

    try {
      const res = await apiFetch(`/games/${state.currentGameId}/files`);
      const { files } = await res.json();
      if (files) {
        for (const f of files) {
          await apiFetch(`/games/${state.currentGameId}/files/${f.name}`, { method: "DELETE" });
        }
      }

      const { deleteDoc } = await import("https://www.gstatic.com/firebasejs/11.7.1/firebase-firestore.js");
      await deleteDoc(doc(state.db, "games", state.currentGameId));

      const { stopGame } = await import('./editor-play.js');
      stopGame();
      state.currentGameId = null;
      showView("dashboard");
    } catch (e) {
      alert("Failed to delete: " + e.message);
    }
  });

  // Update game tab fields when tab is shown
  const observer = new MutationObserver(() => {
    const panel = document.getElementById("tab-game");
    if (panel && panel.classList.contains("active")) {
      document.getElementById("game-title").value = state.currentGameTitle;
      document.getElementById("game-desc").value = state.currentGameDesc || "";
      updatePublishUI();
    }
  });
  const tabGame = document.getElementById("tab-game");
  if (tabGame) observer.observe(tabGame, { attributes: true, attributeFilter: ["class"] });
}
