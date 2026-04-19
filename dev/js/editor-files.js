// ── Files Tab: File tree, bottom sheet, local sync ──

import { state, esc } from './state.js';
import { apiFetch, saveFile, deleteR2File } from './api.js';

// ── File tree rendering ──

function renderFileTree() {
  const tree = document.getElementById("file-tree");
  if (!tree) return;

  if (state.currentFiles.length === 0 && Object.keys(state.currentAssets).length === 0) {
    tree.innerHTML = '<div class="file-empty">No files yet. Use the AI tab to generate code.</div>';
    return;
  }

  // Group by folder
  const folders = {};
  const rootFiles = [];

  for (const f of state.currentFiles) {
    const slash = f.name.indexOf("/");
    if (slash > 0) {
      const folder = f.name.substring(0, slash);
      if (!folders[folder]) folders[folder] = [];
      folders[folder].push(f);
    } else {
      rootFiles.push(f);
    }
  }

  // Add assets
  for (const name of Object.keys(state.currentAssets)) {
    const slash = name.indexOf("/");
    if (slash > 0) {
      const folder = name.substring(0, slash);
      if (!folders[folder]) folders[folder] = [];
      folders[folder].push({ name, isAsset: true });
    } else {
      rootFiles.push({ name, isAsset: true });
    }
  }

  let html = '';

  // Root files first
  for (const f of rootFiles) {
    const icon = f.isAsset ? '🖼' : getFileIcon(f.name);
    const size = f.isAsset ? '' : formatSize(f.content?.length || 0);
    html += `<div class="file-item" data-name="${esc(f.name)}" data-asset="${f.isAsset ? '1' : ''}">
      <span class="file-icon">${icon}</span>
      <span class="file-name">${esc(f.name)}</span>
      <span class="file-size">${size}</span>
    </div>`;
  }

  // Folders
  for (const [folder, files] of Object.entries(folders)) {
    html += `<div class="file-folder">📁 ${esc(folder)}</div>`;
    for (const f of files) {
      const shortName = f.name.substring(folder.length + 1);
      const icon = f.isAsset ? '🖼' : getFileIcon(f.name);
      const size = f.isAsset ? '' : formatSize(f.content?.length || 0);
      html += `<div class="file-item" data-name="${esc(f.name)}" data-asset="${f.isAsset ? '1' : ''}" style="padding-left:36px">
        <span class="file-icon">${icon}</span>
        <span class="file-name">${esc(shortName)}</span>
        <span class="file-size">${size}</span>
      </div>`;
    }
  }

  tree.innerHTML = html;
}

function getFileIcon(name) {
  if (name.endsWith(".lua")) return '📜';
  if (name.endsWith(".json")) return '📋';
  return '📄';
}

function formatSize(bytes) {
  if (bytes < 1024) return bytes + 'B';
  return (bytes / 1024).toFixed(1) + 'K';
}

// ── Bottom sheet ──

function openFileSheet(name) {
  const sheet = document.getElementById("file-sheet");
  const isAsset = !!state.currentAssets[name];

  if (isAsset) {
    // Show image preview
    const blobUrl = state.currentAssets[name];
    sheet.innerHTML = `
      <div class="file-sheet-content">
        <div class="file-sheet-header">
          <span class="file-sheet-title">${esc(name)}</span>
          <button class="file-sheet-close" id="btn-sheet-close">✕</button>
        </div>
        <div class="file-sheet-body" style="text-align:center">
          <img src="${blobUrl}" style="max-width:100%;image-rendering:pixelated;border-radius:4px">
        </div>
      </div>`;
  } else {
    const file = state.currentFiles.find(f => f.name === name);
    if (!file) return;
    sheet.innerHTML = `
      <div class="file-sheet-content">
        <div class="file-sheet-header">
          <span class="file-sheet-title">${esc(name)}</span>
          <button class="file-sheet-close" id="btn-sheet-close">✕</button>
        </div>
        <div class="file-sheet-body">
          <pre class="file-sheet-code">${esc(file.content)}</pre>
        </div>
        <div class="file-sheet-actions">
          <button class="btn-close-sheet" id="btn-sheet-done">Done</button>
        </div>
      </div>`;
  }

  sheet.classList.add("open");

  // Close handlers
  const closeSheet = () => sheet.classList.remove("open");
  sheet.querySelector("#btn-sheet-close")?.addEventListener("click", closeSheet);
  sheet.querySelector("#btn-sheet-done")?.addEventListener("click", closeSheet);
  sheet.addEventListener("click", (e) => {
    if (e.target === sheet) closeSheet();
  }, { once: true });
}

// ── Local Sync ──

function syncLog(msg, files) {
  const chat = document.getElementById("editor-chat");
  let html = `<div class="chat-msg"><span class="chat-sender mono">SYNC</span><span class="chat-body">${esc(msg)}</span>`;
  if (files && files.length) {
    html += '<div class="chat-files">';
    for (const f of files) html += `<span class="chat-file">${esc(f)}</span>`;
    html += '</div>';
  }
  html += '</div>';
  chat.innerHTML += html;
  chat.scrollTop = chat.scrollHeight;
}

async function readDirRecursive(dirHandle, prefix = "") {
  const entries = [];
  for await (const [name, handle] of dirHandle) {
    if (name.startsWith("_") || name.startsWith(".")) continue;
    const path = prefix ? prefix + "/" + name : name;
    if (handle.kind === "file") {
      entries.push({ path, handle, dirHandle });
    } else if (handle.kind === "directory") {
      entries.push(...await readDirRecursive(handle, path));
    }
  }
  return entries;
}

async function getFileHandleDeep(rootHandle, path, create = false) {
  const parts = path.split("/");
  let dir = rootHandle;
  for (let i = 0; i < parts.length - 1; i++) {
    dir = await dir.getDirectoryHandle(parts[i], { create });
  }
  return await dir.getFileHandle(parts[parts.length - 1], { create });
}

function initSyncHandlers() {
  const syncBtn = document.getElementById("btn-sync");
  const syncMenu = document.getElementById("sync-menu");
  if (!syncBtn || !syncMenu) return;

  syncBtn.addEventListener("click", (e) => {
    e.stopPropagation();
    if (!state.syncBusy) syncMenu.classList.toggle("open");
  });
  syncMenu.addEventListener("click", (e) => e.stopPropagation());

  // Link folder
  const linkBtn = document.getElementById("btn-sync-link");
  if (linkBtn) {
    linkBtn.addEventListener("click", async () => {
      if (!window.showDirectoryPicker) { alert("This browser does not support folder access."); return; }
      try {
        state.linkedDirHandle = await window.showDirectoryPicker({ mode: "readwrite" });
        syncBtn.classList.add("linked");
        document.getElementById("btn-sync-push").disabled = false;
        document.getElementById("btn-sync-pull").disabled = false;
        const el = document.getElementById("sync-folder-name");
        el.textContent = state.linkedDirHandle.name;
        el.style.display = "block";
        linkBtn.textContent = "Change Folder…";
        syncLog(`Linked to folder: ${state.linkedDirHandle.name}`);
      } catch {}
    });
  }

  // Push to local
  const pushBtn = document.getElementById("btn-sync-push");
  if (pushBtn) {
    pushBtn.addEventListener("click", async () => {
      if (!state.linkedDirHandle || state.syncBusy) return;
      state.syncBusy = true; pushBtn.disabled = true; pushBtn.textContent = "Pushing…";
      try {
        const gameFiles = state.currentFiles.filter(f => !f.name.startsWith("_"));
        const localEntries = await readDirRecursive(state.linkedDirHandle);
        const localNames = new Set(localEntries.map(e => e.path));

        await Promise.all(gameFiles.map(async (f) => {
          const fh = await getFileHandleDeep(state.linkedDirHandle, f.name, true);
          const w = await fh.createWritable();
          await w.write(f.content);
          await w.close();
        }));

        await Promise.all(Object.entries(state.currentAssets).map(async ([name, blobUrl]) => {
          const fh = await getFileHandleDeep(state.linkedDirHandle, name, true);
          const w = await fh.createWritable();
          const res = await fetch(blobUrl);
          await w.write(await res.blob());
          await w.close();
        }));

        const allR2Names = new Set([...gameFiles.map(f => f.name), ...Object.keys(state.currentAssets)]);
        const orphanLocal = [...localNames].filter(n => !allR2Names.has(n));
        let deleted = [];
        if (orphanLocal.length > 0) {
          if (confirm(`These local files are not in the cloud and will be deleted:\n\n${orphanLocal.join("\n")}\n\nDelete them?`)) {
            for (const path of orphanLocal) {
              const parts = path.split("/");
              let dir = state.linkedDirHandle;
              for (let i = 0; i < parts.length - 1; i++) dir = await dir.getDirectoryHandle(parts[i]);
              await dir.removeEntry(parts[parts.length - 1]);
            }
            deleted = orphanLocal;
          }
        }

        syncLog(`Pushed ${gameFiles.length} files to local`, gameFiles.map(f => f.name));
        if (deleted.length) syncLog(`Deleted ${deleted.length} local files`, deleted);
        pushBtn.textContent = `Pushed ${gameFiles.length}`;
        setTimeout(() => { pushBtn.textContent = "Push to Local"; pushBtn.disabled = false; }, 1500);
      } catch (e) {
        alert("Push failed: " + e.message);
        pushBtn.textContent = "Push to Local"; pushBtn.disabled = false;
      }
      state.syncBusy = false;
    });
  }

  // Pull from local
  const pullBtn = document.getElementById("btn-sync-pull");
  if (pullBtn) {
    pullBtn.addEventListener("click", async () => {
      if (!state.linkedDirHandle || state.syncBusy) return;
      state.syncBusy = true; pullBtn.disabled = true; pullBtn.textContent = "Pulling…";
      try {
        const localFiles = [];
        const localBinaries = [];
        const isImage = (n) => /\.(png|jpg|jpeg|gif|bmp|webp)$/i.test(n);
        const entries = await readDirRecursive(state.linkedDirHandle);
        for (const entry of entries) {
          const file = await entry.handle.getFile();
          if (isImage(entry.path)) {
            localBinaries.push({ name: entry.path, file });
          } else {
            const content = await file.text();
            localFiles.push({ name: entry.path, content });
          }
        }

        for (const f of localFiles) {
          const idx = state.currentFiles.findIndex(c => c.name === f.name);
          if (idx >= 0) state.currentFiles[idx].content = f.content;
          else state.currentFiles.push(f);
        }
        await Promise.all(localFiles.map(f => saveFile(f.name, f.content)));

        if (localBinaries.length > 0) {
          await Promise.all(localBinaries.map(async (f) => {
            const buf = await f.file.arrayBuffer();
            await apiFetch(`/games/${state.currentGameId}/files/${f.name}`, {
              method: "PUT",
              headers: { "Content-Type": "application/octet-stream" },
              body: buf,
            });
            if (state.currentAssets[f.name]) { try { URL.revokeObjectURL(state.currentAssets[f.name]); } catch {} }
            state.currentAssets[f.name] = URL.createObjectURL(f.file);
          }));
        }

        const localNames = new Set([...localFiles.map(f => f.name), ...localBinaries.map(f => f.name)]);
        const allR2Names = [...state.currentFiles.filter(f => !f.name.startsWith("_")).map(f => f.name), ...Object.keys(state.currentAssets)];
        const orphanR2 = allR2Names.filter(n => !localNames.has(n));
        let deleted = [];
        if (orphanR2.length > 0) {
          if (confirm(`These cloud files are not in the local folder and will be deleted:\n\n${orphanR2.join("\n")}\n\nDelete them?`)) {
            await Promise.all(orphanR2.map(name => deleteR2File(name)));
            state.currentFiles = state.currentFiles.filter(f => !orphanR2.includes(f.name));
            for (const name of orphanR2) {
              if (state.currentAssets[name]) { try { URL.revokeObjectURL(state.currentAssets[name]); } catch {} delete state.currentAssets[name]; }
            }
            deleted = orphanR2;
          }
        }

        syncLog(`Pulled ${localFiles.length} files from local`, localFiles.map(f => f.name));
        if (deleted.length) syncLog(`Deleted ${deleted.length} cloud files`, deleted);
        renderFileTree();
        pullBtn.textContent = `Pulled ${localFiles.length}`;
        setTimeout(() => { pullBtn.textContent = "Pull from Local"; pullBtn.disabled = false; }, 1500);
      } catch (e) {
        alert("Pull failed: " + e.message);
        pullBtn.textContent = "Pull from Local"; pullBtn.disabled = false;
      }
      state.syncBusy = false;
    });
  }
}

// Close sync menu on outside click
function setupGlobalSyncClose() {
  document.addEventListener("click", () => {
    const menu = document.getElementById("sync-menu");
    if (menu && !state.syncBusy) menu.classList.remove("open");
  });
}

// ── Init ──

export function initEditorFiles() {
  // Expose for dynamic topbar rebuild + external use
  window._editorFiles = { initSyncHandlers, renderFileTree };

  // File tree click → open bottom sheet
  document.getElementById("file-tree").addEventListener("click", (e) => {
    const item = e.target.closest(".file-item");
    if (item) openFileSheet(item.dataset.name);
  });

  setupGlobalSyncClose();
}
