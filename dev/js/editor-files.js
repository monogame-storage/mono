// ── Files Tab: File tree, bottom sheet, local sync ──

import { state, esc } from './state.js';
import { apiFetch, saveFile, deleteR2File } from './api.js';

// ── Lua keywords for basic syntax highlight ──
const LUA_KW = /\b(function|end|local|if|then|else|elseif|for|while|do|return|repeat|until|in|not|and|or|true|false|nil|break|goto)\b/g;

function highlightLua(code) {
  return esc(code)
    .replace(/^(--.*)/gm, '<span class="sh-cm">$1</span>')
    .replace(LUA_KW, '<span class="sh-kw">$1</span>')
    .replace(/(&quot;[^&]*?&quot;|&#x27;[^&]*?&#x27;)/g, '<span class="sh-str">$1</span>');
}

// ── File tree rendering ──

function renderFileTree() {
  const tree = document.getElementById("file-tree");
  if (!tree) return;

  const allFiles = state.currentFiles.filter(f => !f.name.startsWith("_"));
  const assetNames = Object.keys(state.currentAssets);
  const totalFiles = allFiles.length + assetNames.length;

  if (totalFiles === 0) {
    tree.innerHTML = '<div class="ft-empty">No files yet. Use the AI tab to generate code.</div>';
    return;
  }

  // Group files by folder
  const folders = {};
  const rootFiles = [];

  for (const f of allFiles) {
    const slash = f.name.indexOf("/");
    if (slash > 0) {
      const folder = f.name.substring(0, slash);
      if (!folders[folder]) folders[folder] = [];
      folders[folder].push(f);
    } else {
      rootFiles.push(f);
    }
  }
  for (const name of assetNames) {
    const slash = name.indexOf("/");
    if (slash > 0) {
      const folder = name.substring(0, slash);
      if (!folders[folder]) folders[folder] = [];
      folders[folder].push({ name, isAsset: true });
    } else {
      rootFiles.push({ name, isAsset: true });
    }
  }

  const folderCount = Object.keys(folders).length;
  const totalSize = allFiles.reduce((s, f) => s + (f.content?.length || 0), 0);
  let html = '';

  // Header
  html += `<div class="ft-header">
    <span class="ft-header-icon">📁</span>
    <span class="ft-header-label">PROJECT FILES</span>
    <span class="ft-header-spacer"></span>
    <span class="ft-header-count">${folderCount ? folderCount + ' folders · ' : ''}${totalFiles} files · ${formatSize(totalSize)}</span>
  </div>`;

  // Root files
  for (const f of rootFiles) {
    const isMain = f.name === "main.lua";
    const isAsset = f.isAsset;
    const icon = isAsset ? '🖼' : (isMain ? '📄' : fileIcon(f.name));
    const iconCls = isMain ? ' main' : '';
    const name = f.name;
    const info = isAsset ? '' : formatFileInfo(f);
    const desc = isAsset ? 'image' : getFirstLine(f.content);
    html += `<div class="ft-file${isMain ? ' active' : ''}" data-name="${esc(name)}" data-asset="${isAsset ? '1' : ''}">
      <span class="ft-file-icon${iconCls}">${icon}</span>
      <div class="ft-file-meta">
        <div class="ft-file-name">${esc(name)}${info ? ' · ' + info : ''}</div>
        <div class="ft-file-desc">${esc(desc)}</div>
      </div>
      ${isMain ? '<div class="ft-file-dot"></div>' : ''}
    </div>`;
  }

  // Folders
  for (const [folder, files] of Object.entries(folders)) {
    const isOpen = state._openFolders?.[folder] !== false; // default open
    const totalSize = files.reduce((s, f) => s + (f.isAsset ? 0 : (f.content?.length || 0)), 0);
    const chevron = isOpen ? '▾' : '▸';
    const folderIcon = isOpen ? '📂' : '📁';
    html += `<div class="ft-folder${isOpen ? '' : ' closed'}" data-folder="${esc(folder)}">
      <span class="ft-folder-chev">${chevron}</span>
      <span class="ft-folder-icon">${folderIcon}</span>
      <span class="ft-folder-name">${esc(folder)}/</span>
      <span class="ft-folder-count">${files.length} files · ${formatSize(totalSize)}</span>
    </div>`;

    if (isOpen) {
      for (const f of files) {
        const shortName = f.name.substring(folder.length + 1);
        const isAsset = f.isAsset;
        const icon = isAsset ? '🖼' : fileIcon(f.name);
        const info = isAsset ? '' : formatFileInfo(f);
        const desc = isAsset ? 'image' : getFirstLine(f.content);
        html += `<div class="ft-subfile" data-name="${esc(f.name)}" data-asset="${isAsset ? '1' : ''}">
          <span class="ft-file-icon">${icon}</span>
          <div class="ft-file-meta">
            <div class="ft-file-name">${esc(shortName)}${info ? ' · ' + info : ''}</div>
            <div class="ft-file-desc">${esc(desc)}</div>
          </div>
        </div>`;
      }
    }
  }

  tree.innerHTML = html;
}

function fileIcon(name) {
  if (name.endsWith(".lua")) return '📜';
  if (name.endsWith(".json")) return '📋';
  return '📄';
}

function formatFileInfo(f) {
  if (!f.content) return '';
  const lines = f.content.split('\n').length;
  const size = formatSize(f.content.length);
  return `${lines} ln · ${size}`;
}

function formatSize(bytes) {
  return (bytes / 1024).toFixed(1) + ' KB';
}

function getFirstLine(content) {
  if (!content) return '';
  const line = content.split('\n')[0]?.trim() || '';
  return line.substring(0, 40);
}

// ── Bottom sheet ──

function openFileSheet(name) {
  const sheet = document.getElementById("file-sheet");
  const isAsset = !!state.currentAssets[name];

  if (isAsset) {
    const blobUrl = state.currentAssets[name];
    sheet.innerHTML = `
      <div class="file-sheet-dim"></div>
      <div class="file-sheet-panel">
        <div class="file-sheet-handle"><div class="file-sheet-handle-bar"></div></div>
        <div class="file-sheet-header">
          <div class="file-sheet-left">
            <span class="file-sheet-icon">🖼</span>
            <span class="file-sheet-name">${esc(name)}</span>
          </div>
        </div>
        <div class="file-sheet-code" style="display:flex;align-items:center;justify-content:center">
          <img src="${blobUrl}" style="max-width:100%;image-rendering:pixelated;border-radius:4px">
        </div>
      </div>`;
  } else {
    const file = state.currentFiles.find(f => f.name === name);
    if (!file) return;
    sheet.innerHTML = `
      <div class="file-sheet-dim"></div>
      <div class="file-sheet-panel">
        <div class="file-sheet-handle"><div class="file-sheet-handle-bar"></div></div>
        <div class="file-sheet-header">
          <div class="file-sheet-left">
            <span class="file-sheet-icon">${fileIcon(name)}</span>
            <span class="file-sheet-name">${esc(name.split('/').pop())}</span>
          </div>
          <button class="file-sheet-edit" id="btn-sheet-edit">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 013 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
            Edit
          </button>
        </div>
        <div class="file-sheet-code">
          <pre>${name.endsWith('.lua') ? highlightLua(file.content) : esc(file.content)}</pre>
        </div>
      </div>`;
  }

  sheet.classList.add("open");
  if (state.currentGameId) location.hash = `editor/${state.currentGameId}/files/view/${encodeURIComponent(name)}`;

  const closeSheet = () => {
    sheet.classList.remove("open");
    if (state.currentGameId) location.hash = `editor/${state.currentGameId}/files`;
  };

  // Close on dim click
  const dim = sheet.querySelector(".file-sheet-dim");
  if (dim) dim.addEventListener("click", closeSheet, { once: true });

  // Edit button
  const editBtn = sheet.querySelector("#btn-sheet-edit");
  if (editBtn) editBtn.addEventListener("click", () => openEditMode(name));
}

// ── Edit mode (fullscreen editor) ──

function openEditMode(name) {
  const file = state.currentFiles.find(f => f.name === name);
  if (!file) return;

  const sheet = document.getElementById("file-sheet");
  const originalContent = file.content;
  const shortName = name.split('/').pop();

  sheet.innerHTML = `
    <div class="file-edit-full">
      <div class="file-sheet-handle"><div class="file-sheet-handle-bar"></div></div>
      <div class="file-edit-header">
        <div class="file-edit-left">
          <span class="file-sheet-icon" style="color:#c9a0dc">${fileIcon(name)}</span>
          <span class="file-sheet-name">${esc(shortName)}</span>
          <span class="file-edit-badge">EDITING</span>
        </div>
        <div class="file-edit-actions">
          <button class="file-edit-btn" id="btn-edit-reset" title="Reset">
            <svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2"><path d="M1 4v6h6"/><path d="M3.51 15a9 9 0 102.13-9.36L1 10"/></svg>
            Reset
          </button>
          <button class="file-edit-icon-btn" id="btn-edit-undo" title="Undo" disabled>
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 7v6h6"/><path d="M21 17a9 9 0 00-9-9 9 9 0 00-6.69 3L3 13"/></svg>
          </button>
          <button class="file-edit-icon-btn" id="btn-edit-redo" title="Redo" disabled>
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 7v6h-6"/><path d="M3 17a9 9 0 019-9 9 9 0 016.69 3L21 13"/></svg>
          </button>
          <button class="file-edit-btn" id="btn-edit-done" title="Done">
            <svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2"><polyline points="20 6 9 17 4 12"/></svg>
            Done
          </button>
        </div>
      </div>
      <div class="file-edit-area">
        <textarea id="file-edit-textarea" spellcheck="false">${esc(file.content)}</textarea>
      </div>
    </div>`;

  sheet.classList.add("open");
  if (state.currentGameId) location.hash = `editor/${state.currentGameId}/files/edit/${encodeURIComponent(name)}`;

  const textarea = document.getElementById("file-edit-textarea");
  textarea.focus();

  // Prevent engine key interception while editing
  textarea.addEventListener("keydown", (e) => e.stopPropagation());
  textarea.addEventListener("keyup", (e) => e.stopPropagation());
  textarea.addEventListener("keypress", (e) => e.stopPropagation());

  // Undo/Redo stack
  const undoStack = [file.content];
  let redoStack = [];
  let lastSnapshot = file.content;
  let snapshotTimer = null;
  const undoBtn = document.getElementById("btn-edit-undo");
  const redoBtn = document.getElementById("btn-edit-redo");

  function updateUndoRedoState() {
    undoBtn.disabled = undoStack.length <= 1;
    redoBtn.disabled = redoStack.length === 0;
  }

  function pushSnapshot() {
    const val = textarea.value;
    if (val === lastSnapshot) return;
    undoStack.push(val);
    if (undoStack.length > 100) undoStack.shift();
    redoStack = [];
    lastSnapshot = val;
    updateUndoRedoState();
  }

  textarea.addEventListener("input", () => {
    clearTimeout(snapshotTimer);
    snapshotTimer = setTimeout(pushSnapshot, 400);
  });

  undoBtn.addEventListener("click", () => {
    pushSnapshot(); // flush pending
    if (undoStack.length <= 1) return;
    redoStack.push(undoStack.pop());
    const prev = undoStack[undoStack.length - 1];
    textarea.value = prev;
    lastSnapshot = prev;
    updateUndoRedoState();
  });

  redoBtn.addEventListener("click", () => {
    if (redoStack.length === 0) return;
    const next = redoStack.pop();
    undoStack.push(next);
    textarea.value = next;
    lastSnapshot = next;
    updateUndoRedoState();
  });

  // Tab key inserts 2 spaces
  textarea.addEventListener("keydown", (e) => {
    if (e.key === "Tab") {
      e.preventDefault();
      const start = textarea.selectionStart;
      const end = textarea.selectionEnd;
      textarea.value = textarea.value.substring(0, start) + "  " + textarea.value.substring(end);
      textarea.selectionStart = textarea.selectionEnd = start + 2;
      pushSnapshot();
    }
    // Ctrl/Cmd+Z → undo, Ctrl/Cmd+Shift+Z → redo
    if ((e.ctrlKey || e.metaKey) && e.key === "z" && !e.shiftKey) {
      e.preventDefault();
      undoBtn.click();
    }
    if ((e.ctrlKey || e.metaKey) && e.key === "z" && e.shiftKey) {
      e.preventDefault();
      redoBtn.click();
    }
  });

  // Reset button
  document.getElementById("btn-edit-reset").addEventListener("click", () => {
    if (confirm("Reset to original? Unsaved changes will be lost.")) {
      textarea.value = originalContent;
      undoStack.length = 0;
      undoStack.push(originalContent);
      redoStack = [];
      lastSnapshot = originalContent;
      updateUndoRedoState();
    }
  });

  // Done button → save & close
  document.getElementById("btn-edit-done").addEventListener("click", async () => {
    file.content = textarea.value;
    // Save to R2
    try {
      const { saveFile } = await import('./api.js');
      await saveFile(name, file.content);
    } catch (e) {
      console.warn("Auto-save failed:", e);
    }
    sheet.classList.remove("open");
    if (state.currentGameId) location.hash = `editor/${state.currentGameId}/files`;
    renderFileTree();
  });
}

// ── Local Sync ──

function syncLog(msg, files) {
  const chat = document.getElementById("editor-chat");
  if (!chat) return;
  let html = `<div class="ai-card-mono">
    <div class="ai-card-status">SYNC</div>
    <div class="ai-card-response">${esc(msg)}</div>`;
  if (files && files.length) {
    for (const f of files) html += `<div class="ai-card-file">${esc(f)}</div>`;
  }
  html += '</div>';
  chat.innerHTML += html;
  chat.scrollTop = chat.scrollHeight;
}

// Root-level wrapper scripts planted by seedMonoDir(). The broader
// `_*`/`.*` filter below catches `.mono/` and editor meta files;
// this set covers the two non-dotted names that belong with them.
const SYNC_IGNORE_NAMES = new Set(["mono-run", "mono-run.cmd"]);

async function readDirRecursive(dirHandle, prefix = "") {
  const entries = [];
  for await (const [name, handle] of dirHandle) {
    if (name.startsWith("_") || name.startsWith(".")) continue;
    if (SYNC_IGNORE_NAMES.has(name)) continue;
    const path = prefix ? prefix + "/" + name : name;
    if (handle.kind === "file") {
      entries.push({ path, handle, dirHandle });
    } else if (handle.kind === "directory") {
      entries.push(...await readDirRecursive(handle, path));
    }
  }
  return entries;
}

// ── .mono/ bundle planting (push-time only) ──
// Drops engine.js + bindings + draw + mono-runner + CONTEXT.md + VERSION
// under `.mono/`, plus a shell/bat wrapper at the project root so
// `./mono-run main.lua` just works.

async function writeFile(dirHandle, name, content) {
  const fh = await dirHandle.getFileHandle(name, { create: true });
  const w = await fh.createWritable();
  await w.write(content);
  await w.close();
}

async function seedMonoDir(rootHandle) {
  const fetchText = async (url) => {
    const r = await fetch(url + "?v=" + Date.now());
    if (!r.ok) throw new Error(`${url} (${r.status})`);
    return await r.text();
  };

  // Parallel fetch of every source file first, then sequential writes
  // (File System Access API handles one writable at a time per handle).
  const [version, engineJs, bindingsJs, drawJs, runnerJs, ctxRaw] = await Promise.all([
    fetchText("/VERSION").then(s => s.trim()),
    fetchText("/runtime/engine.js"),
    fetchText("/runtime/engine-bindings.js"),
    fetchText("/runtime/engine-draw.js"),
    fetchText("/headless/mono-runner.js"),
    fetchText("/templates/mono/CONTEXT.md"),
  ]);

  const monoDir = await rootHandle.getDirectoryHandle(".mono", { create: true });
  await writeFile(monoDir, "engine.js",          engineJs);
  await writeFile(monoDir, "engine-bindings.js", bindingsJs);
  await writeFile(monoDir, "engine-draw.js",     drawJs);
  await writeFile(monoDir, "mono-runner.js",     runnerJs);
  // CONTEXT.md uses {{VERSION}} / {{BASE_URL}} placeholders.
  await writeFile(monoDir, "CONTEXT.md",
    ctxRaw
      .replace(/\{\{VERSION\}\}/g, version)
      .replace(/\{\{BASE_URL\}\}/g, "https://github.com/monogame-storage/mono/blob/main"));
  await writeFile(monoDir, "VERSION", version);

  // Shell wrappers at the project root. SYNC_IGNORE_NAMES keeps pull
  // from mistakenly uploading them back to R2.
  await writeFile(rootHandle, "mono-run",     '#!/bin/sh\nnode "$(dirname "$0")/.mono/mono-runner.js" "$@"\n');
  await writeFile(rootHandle, "mono-run.cmd", '@node "%~dp0.mono\\mono-runner.js" %*\r\n');
}

async function getFileHandleDeep(rootHandle, path, create = false) {
  const parts = path.split("/");
  let dir = rootHandle;
  for (let i = 0; i < parts.length - 1; i++) {
    dir = await dir.getDirectoryHandle(parts[i], { create });
  }
  return await dir.getFileHandle(parts[parts.length - 1], { create });
}

// Link folder on first push/pull if not linked
async function ensureLinked() {
  if (state.linkedDirHandle) return true;
  if (!window.showDirectoryPicker) { alert("This browser does not support folder access."); return false; }
  try {
    state.linkedDirHandle = await window.showDirectoryPicker({ mode: "readwrite" });
    syncLog(`Linked to folder: ${state.linkedDirHandle.name}`);
    return true;
  } catch { return false; }
}

// ── Sync confirmation sheet ──

function showSyncConfirm(title, changes, onConfirm) {
  const sheet = document.getElementById("file-sheet");
  const added = changes.filter(c => c.action === "add");
  const modified = changes.filter(c => c.action === "modify");
  const deleted = changes.filter(c => c.action === "delete");
  const unchanged = changes.filter(c => c.action === "unchanged");

  let listHtml = '';
  if (added.length) {
    listHtml += `<div class="sync-group-label">+ ${added.length} new</div>`;
    for (const c of added) listHtml += `<div class="sync-item add">+ ${esc(c.name)}</div>`;
  }
  if (modified.length) {
    listHtml += `<div class="sync-group-label">~ ${modified.length} modified</div>`;
    for (const c of modified) listHtml += `<div class="sync-item modify">~ ${esc(c.name)}</div>`;
  }
  if (deleted.length) {
    listHtml += `<div class="sync-group-label">- ${deleted.length} deleted</div>`;
    for (const c of deleted) listHtml += `<div class="sync-item delete">- ${esc(c.name)}</div>`;
  }
  if (unchanged.length) {
    listHtml += `<div class="sync-group-label">${unchanged.length} unchanged</div>`;
  }

  if (!added.length && !modified.length && !deleted.length) {
    listHtml = '<div class="sync-item" style="color:#888;text-align:center;padding:20px 0">No changes to sync.</div>';
  }

  sheet.innerHTML = `
    <div class="file-sheet-dim"></div>
    <div class="file-sheet-panel">
      <div class="file-sheet-handle"><div class="file-sheet-handle-bar"></div></div>
      <div class="file-sheet-header">
        <div class="file-sheet-left">
          <span class="file-sheet-name">${esc(title)}</span>
        </div>
      </div>
      <div class="sync-list">${listHtml}</div>
      <div class="sync-actions">
        <button class="sync-cancel" id="btn-sync-cancel">Cancel</button>
        <button class="sync-confirm" id="btn-sync-confirm" ${(!added.length && !modified.length && !deleted.length) ? 'disabled' : ''}>Confirm</button>
      </div>
    </div>`;

  sheet.classList.add("open");

  sheet.querySelector(".file-sheet-dim").addEventListener("click", () => sheet.classList.remove("open"), { once: true });
  document.getElementById("btn-sync-cancel").addEventListener("click", () => sheet.classList.remove("open"));
  document.getElementById("btn-sync-confirm").addEventListener("click", async () => {
    const btn = document.getElementById("btn-sync-confirm");
    btn.disabled = true;
    btn.textContent = "Syncing…";
    try {
      await onConfirm(changes);
    } catch (e) {
      alert("Sync failed: " + e.message);
    }
    sheet.classList.remove("open");
  });
}

// ── Push: compute diff then confirm ──

async function doPush() {
  if (state.syncBusy) return;
  if (!await ensureLinked()) return;
  state.syncBusy = true;
  const btn = document.getElementById("btn-push");
  if (btn) btn.style.opacity = "0.5";

  try {
    const gameFiles = state.currentFiles.filter(f => !f.name.startsWith("_"));
    const cloudNames = new Set([...gameFiles.map(f => f.name), ...Object.keys(state.currentAssets)]);
    const localEntries = await readDirRecursive(state.linkedDirHandle);
    const localMap = new Map();
    const isImage = (n) => /\.(png|jpg|jpeg|gif|bmp|webp)$/i.test(n);

    for (const entry of localEntries) {
      if (!isImage(entry.path)) {
        const file = await entry.handle.getFile();
        localMap.set(entry.path, await file.text());
      } else {
        localMap.set(entry.path, null); // binary — can't diff content
      }
    }

    const changes = [];
    // Cloud files → write to local
    for (const f of gameFiles) {
      const localContent = localMap.get(f.name);
      if (localContent === undefined) {
        changes.push({ name: f.name, action: "add" });
      } else if (localContent !== null && localContent !== f.content) {
        changes.push({ name: f.name, action: "modify" });
      } else {
        changes.push({ name: f.name, action: "unchanged" });
      }
    }
    for (const name of Object.keys(state.currentAssets)) {
      if (!localMap.has(name)) changes.push({ name, action: "add" });
      else changes.push({ name, action: "unchanged" });
    }
    // Local files not in cloud → delete
    for (const [path] of localMap) {
      if (!cloudNames.has(path)) changes.push({ name: path, action: "delete" });
    }

    showSyncConfirm("Push to Local", changes, async (ch) => {
      const toWrite = ch.filter(c => c.action === "add" || c.action === "modify");
      const toDelete = ch.filter(c => c.action === "delete");

      for (const c of toWrite) {
        const file = gameFiles.find(f => f.name === c.name);
        if (file) {
          const fh = await getFileHandleDeep(state.linkedDirHandle, c.name, true);
          const w = await fh.createWritable();
          await w.write(file.content);
          await w.close();
        } else if (state.currentAssets[c.name]) {
          const fh = await getFileHandleDeep(state.linkedDirHandle, c.name, true);
          const w = await fh.createWritable();
          const res = await fetch(state.currentAssets[c.name]);
          await w.write(await res.blob());
          await w.close();
        }
      }
      for (const c of toDelete) {
        const parts = c.name.split("/");
        let dir = state.linkedDirHandle;
        for (let i = 0; i < parts.length - 1; i++) dir = await dir.getDirectoryHandle(parts[i]);
        await dir.removeEntry(parts[parts.length - 1]);
      }
      syncLog(`Pushed ${toWrite.length} files`, toWrite.map(c => c.name));
      if (toDelete.length) syncLog(`Deleted ${toDelete.length} local files`, toDelete.map(c => c.name));

      try {
        await seedMonoDir(state.linkedDirHandle);
        syncLog(`Planted .mono/ engine bundle`);
      } catch (e) {
        syncLog(`.mono/ plant failed: ${e.message || e}`);
      }
    });
  } catch (e) { alert("Push failed: " + e.message); }

  state.syncBusy = false;
  if (btn) btn.style.opacity = "1";
}

// ── Pull: compute diff then confirm ──

async function doPull() {
  if (state.syncBusy) return;
  if (!await ensureLinked()) return;
  state.syncBusy = true;
  const btn = document.getElementById("btn-pull");
  if (btn) btn.style.opacity = "0.5";

  try {
    const isImage = (n) => /\.(png|jpg|jpeg|gif|bmp|webp)$/i.test(n);
    const entries = await readDirRecursive(state.linkedDirHandle);
    const localFiles = [];
    const localBinaries = [];
    for (const entry of entries) {
      const file = await entry.handle.getFile();
      if (isImage(entry.path)) localBinaries.push({ name: entry.path, file });
      else { const content = await file.text(); localFiles.push({ name: entry.path, content }); }
    }

    const localNames = new Set([...localFiles.map(f => f.name), ...localBinaries.map(f => f.name)]);
    const cloudFileNames = state.currentFiles.filter(f => !f.name.startsWith("_")).map(f => f.name);
    const allCloudNames = [...cloudFileNames, ...Object.keys(state.currentAssets)];

    const changes = [];
    // Local text files → cloud
    for (const f of localFiles) {
      const existing = state.currentFiles.find(c => c.name === f.name);
      if (!existing) {
        changes.push({ name: f.name, action: "add", type: "text" });
      } else if (existing.content !== f.content) {
        changes.push({ name: f.name, action: "modify", type: "text" });
      } else {
        changes.push({ name: f.name, action: "unchanged" });
      }
    }
    // Local binaries → cloud
    for (const f of localBinaries) {
      if (!state.currentAssets[f.name]) changes.push({ name: f.name, action: "add", type: "binary" });
      else changes.push({ name: f.name, action: "unchanged" });
    }
    // Cloud files not in local → delete
    for (const name of allCloudNames) {
      if (!localNames.has(name)) changes.push({ name, action: "delete" });
    }

    showSyncConfirm("Pull from Local", changes, async (ch) => {
      const toAdd = ch.filter(c => (c.action === "add" || c.action === "modify") && c.type === "text");
      const toBinary = ch.filter(c => (c.action === "add" || c.action === "modify") && c.type === "binary");
      const toDelete = ch.filter(c => c.action === "delete");

      // Text files
      for (const c of toAdd) {
        const f = localFiles.find(l => l.name === c.name);
        if (!f) continue;
        const idx = state.currentFiles.findIndex(cf => cf.name === f.name);
        if (idx >= 0) state.currentFiles[idx].content = f.content;
        else state.currentFiles.push(f);
      }
      await Promise.all(toAdd.map(c => {
        const f = localFiles.find(l => l.name === c.name);
        return f ? saveFile(f.name, f.content) : null;
      }));

      // Binary files
      if (toBinary.length) {
        await Promise.all(toBinary.map(async (c) => {
          const f = localBinaries.find(l => l.name === c.name);
          if (!f) return;
          const buf = await f.file.arrayBuffer();
          await apiFetch(`/games/${state.currentGameId}/files/${f.name}`, {
            method: "PUT", headers: { "Content-Type": "application/octet-stream" }, body: buf,
          });
          if (state.currentAssets[f.name]) { try { URL.revokeObjectURL(state.currentAssets[f.name]); } catch {} }
          state.currentAssets[f.name] = URL.createObjectURL(f.file);
        }));
      }

      // Delete
      if (toDelete.length) {
        await Promise.all(toDelete.map(c => deleteR2File(c.name)));
        state.currentFiles = state.currentFiles.filter(f => !toDelete.some(d => d.name === f.name));
        for (const c of toDelete) {
          if (state.currentAssets[c.name]) { try { URL.revokeObjectURL(state.currentAssets[c.name]); } catch {} delete state.currentAssets[c.name]; }
        }
      }

      syncLog(`Pulled ${toAdd.length + toBinary.length} files`, [...toAdd, ...toBinary].map(c => c.name));
      if (toDelete.length) syncLog(`Deleted ${toDelete.length} cloud files`, toDelete.map(c => c.name));
      renderFileTree();
    });
  } catch (e) { alert("Pull failed: " + e.message); }

  state.syncBusy = false;
  if (btn) btn.style.opacity = "1";
}

// ── Topbar handlers (re-called when tab switches) ──

function initTopbarHandlers() {
  document.getElementById("btn-push")?.addEventListener("click", doPush);
  document.getElementById("btn-pull")?.addEventListener("click", doPull);
}

// ── Init ──

export function initEditorFiles() {
  // Track open/closed folders
  if (!state._openFolders) state._openFolders = {};

  // Expose for external use
  window._editorFiles = { initTopbarHandlers, renderFileTree, openFileSheet, openEditMode };

  // File tree click delegation
  document.getElementById("file-tree").addEventListener("click", (e) => {
    // Folder toggle
    const folder = e.target.closest(".ft-folder");
    if (folder) {
      const name = folder.dataset.folder;
      state._openFolders[name] = state._openFolders[name] === false ? true : !!(state._openFolders[name] === undefined ? false : false);
      // Toggle: if currently default-open, close; if closed, open
      const isCurrentlyOpen = !folder.classList.contains("closed");
      state._openFolders[name] = !isCurrentlyOpen;
      renderFileTree();
      return;
    }
    // File click → open sheet
    const file = e.target.closest(".ft-file, .ft-subfile");
    if (file) openFileSheet(file.dataset.name);
  });
}
