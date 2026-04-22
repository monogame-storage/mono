// ── AI Provider Vault + Dev Settings ──

import { state, esc, showView } from './state.js';
import { apiFetch } from './api.js';
import {
  doc,
  getDoc,
  setDoc,
} from "https://www.gstatic.com/firebasejs/11.7.1/firebase-firestore.js";
import { signOut } from "https://www.gstatic.com/firebasejs/11.7.1/firebase-auth.js";

// ── Vault Encryption (AES-GCM + PBKDF2) ──

async function deriveKey(passphrase, salt) {
  const enc = new TextEncoder();
  const keyMaterial = await crypto.subtle.importKey("raw", enc.encode(passphrase), "PBKDF2", false, ["deriveKey"]);
  return crypto.subtle.deriveKey(
    { name: "PBKDF2", salt, iterations: 100000, hash: "SHA-256" },
    keyMaterial, { name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]
  );
}

async function encryptData(passphrase, data) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const key = await deriveKey(passphrase, salt);
  const encrypted = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, new TextEncoder().encode(JSON.stringify(data)));
  const buf = new Uint8Array(salt.length + iv.length + encrypted.byteLength);
  buf.set(salt, 0);
  buf.set(iv, salt.length);
  buf.set(new Uint8Array(encrypted), salt.length + iv.length);
  return btoa(String.fromCharCode(...buf));
}

export async function decryptData(passphrase, b64) {
  const buf = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  const salt = buf.slice(0, 16);
  const iv = buf.slice(16, 28);
  const ciphertext = buf.slice(28);
  const key = await deriveKey(passphrase, salt);
  const decrypted = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, ciphertext);
  return JSON.parse(new TextDecoder().decode(decrypted));
}

// ── Master key persistence ──
// Keys are scoped per-uid so multiple accounts on the same browser
// don't collide. If "save on this device" is enabled, pp is kept in
// localStorage; otherwise pp lives only in state.vaultPp (lost on
// reload / tab close).

function currentUid() {
  return state.auth?.currentUser?.uid || null;
}

function ppKey(uid) { return `mono_vault_pp_${uid}`; }
function savePrefKey(uid) { return `mono_vault_save_local_${uid}`; }

function getSaveLocalPref() {
  const uid = currentUid();
  if (!uid) return true;
  return localStorage.getItem(savePrefKey(uid)) !== "0";
}

function setSaveLocalPref(enabled) {
  const uid = currentUid();
  if (!uid) return;
  localStorage.setItem(savePrefKey(uid), enabled ? "1" : "0");
}

export function getVaultPp() {
  const uid = currentUid();
  if (!uid) return "";
  return state.vaultPp || localStorage.getItem(ppKey(uid)) || "";
}

function setVaultPp(pp) {
  const uid = currentUid();
  if (!uid) return;
  state.vaultPp = pp;
  if (getSaveLocalPref()) {
    localStorage.setItem(ppKey(uid), pp);
  } else {
    localStorage.removeItem(ppKey(uid));
  }
}

function clearVaultPp() {
  const uid = currentUid();
  state.vaultPp = null;
  if (uid) localStorage.removeItem(ppKey(uid));
}

// ── Provider Storage ──

export async function loadProviders() {
  const pp = getVaultPp() || document.getElementById("aip-passphrase").value;
  if (!pp) { renderProviderList(); return; }
  try {
    const uid = state.auth.currentUser.uid;
    const snap = await getDoc(doc(state.db, "users", uid, "settings", "ai"));
    if (snap.exists() && snap.data().encrypted) {
      state.aiProviders = await decryptData(pp, snap.data().encrypted);
    } else {
      state.aiProviders = [];
    }
  } catch {
    state.aiProviders = [];
  }
  renderProviderList();
}

export async function saveProviders() {
  const pp = getVaultPp() || document.getElementById("aip-passphrase").value;
  if (!pp) { alert("Set a vault passphrase first"); return; }
  const encrypted = await encryptData(pp, state.aiProviders);
  const uid = state.auth.currentUser.uid;
  await setDoc(doc(state.db, "users", uid, "settings", "ai"), { encrypted });
}

function renderProviderList() {
  const list = document.getElementById("aip-list");
  if (state.aiProviders.length === 0) {
    list.innerHTML = '<div style="color:#555;font-size:12px;text-align:center;padding:16px">No providers added yet</div>';
    return;
  }
  list.innerHTML = state.aiProviders.map((p, i) => `
    <div class="aip-provider-card" data-idx="${i}">
      <div>
        <div class="aip-provider-name">${esc(p.alias)}</div>
        <div class="aip-provider-model">${esc(p.model)}</div>
      </div>
      ${p.isDefault ? '<span class="aip-provider-badge">DEFAULT</span>' : '<span style="color:#555;font-size:14px">›</span>'}
    </div>
  `).join("");
  updateModelSelector();
}

// Event delegation for provider cards
function onProviderListClick(e) {
  const card = e.target.closest(".aip-provider-card");
  if (!card) return;
  editProvider(parseInt(card.dataset.idx));
}

export function updateModelSelector() {
  const sel = document.getElementById("model-select");
  if (!sel) return;
  // Chat is BYOK-only: rebuild the full list from state.aiProviders so
  // there is no "mono default" option lingering in the DOM.
  sel.innerHTML = "";
  for (const p of state.aiProviders) {
    const opt = document.createElement("option");
    opt.value = `provider:${p.id}`;
    opt.textContent = p.alias;
    sel.appendChild(opt);
  }
  const def = state.aiProviders.find(p => p.isDefault);
  if (def) sel.value = `provider:${def.id}`;
  // Refresh the provider pill label if the AI tab's topbar is mounted.
  const pillLabel = document.querySelector("#btn-provider-pill .pill-label");
  if (pillLabel) {
    pillLabel.textContent = sel.options.length === 0
      ? "No provider"
      : (sel.options[sel.selectedIndex]?.textContent || "Model");
  }
}

// ── AI Providers navigation ──

async function checkOnlineProviders() {
  try {
    const uid = state.auth.currentUser.uid;
    const snap = await getDoc(doc(state.db, "users", uid, "settings", "ai"));
    state.hasOnlineProviders = snap.exists() && !!snap.data().encrypted;
  } catch { state.hasOnlineProviders = false; }
}

function renderMasterKeyState() {
  const pp = getVaultPp();
  const input = document.getElementById("aip-passphrase");
  const actionBtn = document.getElementById("aip-mk-action");
  const resetBtn = document.getElementById("aip-mk-reset");
  const status = document.getElementById("aip-mk-status");
  const subtitle = document.getElementById("aip-mk-subtitle");
  const strength = document.getElementById("aip-strength");
  document.getElementById("aip-mk-save-local").checked = getSaveLocalPref();

  strength.textContent = "";
  strength.className = "aip-strength";
  resetBtn.style.display = "none";
  status.textContent = "";
  status.className = "aip-mk-status";

  if (pp) {
    input.value = "##########";
    input.disabled = true;
    input.dataset.masked = "1";
    actionBtn.textContent = "Change";
    actionBtn.style.display = "block";
    subtitle.textContent = "Encrypts your API keys. Never stored online — if lost, you must re-enter all keys.";
    subtitle.style.color = "";
    status.textContent = "✓ Master key set";
    status.className = "aip-mk-status success";
  } else if (state.hasOnlineProviders) {
    input.value = "";
    input.disabled = false;
    input.dataset.masked = "";
    input.placeholder = "Enter your master key to unlock";
    actionBtn.textContent = "Unlock";
    actionBtn.style.display = "block";
    subtitle.textContent = "Encrypted providers found. Enter your master key to unlock.";
    subtitle.style.color = "#fa3";
    status.textContent = "";
  } else {
    input.value = "";
    input.disabled = false;
    input.dataset.masked = "";
    input.placeholder = "Enter master key";
    actionBtn.textContent = "Set";
    actionBtn.style.display = "block";
    subtitle.textContent = "Required — set a master key to encrypt your API keys.";
    subtitle.style.color = "#ff6666";
    status.textContent = "No master key set";
    status.className = "aip-mk-status error";
  }
}

export async function openAIProviders() {
  await checkOnlineProviders();
  renderMasterKeyState();
  if (getVaultPp()) {
    await loadProviders();
  } else {
    state.aiProviders = [];
    renderProviderList();
  }
  showView("ai-providers");
}

function evaluateStrength(val) {
  let score = 0;
  if (val.length >= 8) score++;
  if (val.length >= 12) score++;
  if (/[A-Z]/.test(val) && /[a-z]/.test(val)) score++;
  if (/[0-9]/.test(val) && /[^a-zA-Z0-9]/.test(val)) score++;
  return Math.min(score, 3);
}

// ── Add/Edit Provider ──

function editProvider(idx) {
  state.editingProviderIdx = idx;
  const p = state.aiProviders[idx];
  document.getElementById("apf-title").textContent = "Edit Provider";
  document.getElementById("apf-alias").value = p.alias;
  document.getElementById("apf-model").value = p.model;
  document.getElementById("apf-key").value = p.key;
  document.getElementById("apf-url").value = p.url || "";
  document.getElementById("apf-model-name").value = p.modelName || "";
  document.getElementById("apf-default-toggle").className = p.isDefault ? "apf-toggle on" : "apf-toggle";
  document.getElementById("apf-test-result").className = "apf-test-result";
  document.getElementById("btn-apf-delete").className = "apf-delete-btn show";
  document.getElementById("btn-apf-duplicate").className = "apf-duplicate-btn show";
  showView("add-provider");
}

// ── Dev Settings ──

export function openDevSettings() {
  const user = state.auth.currentUser;
  if (user) {
    document.getElementById("devsettings-name").textContent = user.displayName || "Developer";
    document.getElementById("devsettings-email").textContent = user.email || "";
    const avatar = document.getElementById("devsettings-avatar");
    if (user.photoURL) {
      avatar.style.backgroundImage = `url(${user.photoURL})`;
      avatar.style.backgroundSize = "cover";
    }
  }
  location.hash = "settings";
  showView("devsettings");
}

export function initSettings() {
  // Dev settings
  document.getElementById("btn-settings").addEventListener("click", openDevSettings);
  document.getElementById("btn-devsettings-back").addEventListener("click", () => { location.hash = ""; showView("dashboard"); });
  document.getElementById("btn-signout").addEventListener("click", () => {
    if (confirm("Sign out?")) signOut(state.auth);
  });
  document.getElementById("btn-ai-providers").addEventListener("click", () => {
    location.hash = "settings/ai";
    openAIProviders();
  });

  // Copy JWT button (convenience for API testing; JWT is already in-memory)
  const status = document.getElementById("copy-token-status");
  document.getElementById("btn-copy-token").addEventListener("click", async () => {
    try {
      const user = state.auth?.currentUser;
      if (!user) { status.textContent = "Not signed in"; return; }
      const token = await user.getIdToken();
      await navigator.clipboard.writeText(token);
      status.textContent = "Copied!";
    } catch (e) {
      status.textContent = "Failed";
      console.error("Copy token failed:", e);
    }
    setTimeout(() => { status.textContent = "›"; }, 2000);
  });

  // AI Providers view
  document.getElementById("btn-aip-back").addEventListener("click", () => { location.hash = "settings"; showView("devsettings"); });
  document.getElementById("aip-list").addEventListener("click", onProviderListClick);

  // Save-local checkbox
  document.getElementById("aip-mk-save-local").addEventListener("change", (e) => {
    setSaveLocalPref(e.target.checked);
    const pp = getVaultPp();
    if (pp) setVaultPp(pp);
    else {
      const uid = currentUid();
      if (uid) localStorage.removeItem(ppKey(uid));
    }
  });

  // Master key action
  document.getElementById("aip-mk-action").addEventListener("click", async () => {
    const input = document.getElementById("aip-passphrase");
    const status = document.getElementById("aip-mk-status");
    const resetBtn = document.getElementById("aip-mk-reset");
    const pp = getVaultPp();

    if (pp && input.dataset.masked === "1") {
      input.value = "";
      input.disabled = false;
      input.dataset.masked = "";
      input.dataset.verifying = "1";
      input.placeholder = "Enter current master key";
      input.focus();
      document.getElementById("aip-mk-action").textContent = "Verify";
      status.textContent = "";
      return;
    }

    if (input.dataset.verifying === "1") {
      const entered = input.value.trim();
      if (!entered) { status.textContent = "Enter current key"; status.className = "aip-mk-status error"; return; }
      if (entered !== pp) {
        status.textContent = "✗ Wrong key";
        status.className = "aip-mk-status error";
        return;
      }
      input.value = "";
      input.dataset.verifying = "";
      input.placeholder = "Enter new master key";
      input.focus();
      document.getElementById("aip-mk-action").textContent = "Set";
      status.textContent = "✓ Verified. Enter new key.";
      status.className = "aip-mk-status success";
      return;
    }

    const newKey = input.value.trim();
    if (!newKey) { status.textContent = "Enter a key"; status.className = "aip-mk-status error"; return; }

    if (state.hasOnlineProviders && !pp) {
      try {
        const uid = state.auth.currentUser.uid;
        const snap = await getDoc(doc(state.db, "users", uid, "settings", "ai"));
        const encrypted = snap.data().encrypted;
        state.aiProviders = await decryptData(newKey, encrypted);
        setVaultPp(newKey);
        status.textContent = "✓ Unlocked";
        status.className = "aip-mk-status success";
        resetBtn.style.display = "none";
        renderMasterKeyState();
        renderProviderList();
      } catch {
        status.textContent = "✗ Wrong master key";
        status.className = "aip-mk-status error";
        resetBtn.style.display = "block";
        state.aiProviders = [];
        renderProviderList();
      }
      return;
    }

    if (pp && newKey !== pp) {
      const oldKey = pp;
      try {
        const uid = state.auth.currentUser.uid;
        const snap = await getDoc(doc(state.db, "users", uid, "settings", "ai"));
        if (snap.exists() && snap.data().encrypted) {
          state.aiProviders = await decryptData(oldKey, snap.data().encrypted);
        }
      } catch {}
      setVaultPp(newKey);
      await saveProviders();
      status.textContent = "✓ Master key changed and providers re-encrypted";
      status.className = "aip-mk-status success";
      renderMasterKeyState();
      return;
    }

    setVaultPp(newKey);
    renderMasterKeyState();
    await loadProviders();
  });

  // Reset
  document.getElementById("aip-mk-reset").addEventListener("click", async () => {
    if (!confirm("This will delete all saved providers. Are you sure?")) return;
    try {
      const uid = state.auth.currentUser.uid;
      await setDoc(doc(state.db, "users", uid, "settings", "ai"), { encrypted: null });
      state.hasOnlineProviders = false;
      state.aiProviders = [];
      clearVaultPp();
      renderProviderList();
      renderMasterKeyState();
      document.getElementById("aip-mk-status").textContent = "Providers cleared";
      document.getElementById("aip-mk-status").className = "aip-mk-status warn";
    } catch (e) {
      alert("Failed: " + e.message);
    }
  });

  // Strength indicator
  document.getElementById("aip-passphrase").addEventListener("input", () => {
    const input = document.getElementById("aip-passphrase");
    if (input.dataset.masked === "1") return;
    const val = input.value;
    const el = document.getElementById("aip-strength");
    if (!val) { el.textContent = ""; el.className = "aip-strength"; return; }
    const score = evaluateStrength(val);
    const levels = [
      { cls: "weak", label: "WEAK" },
      { cls: "fair", label: "FAIR" },
      { cls: "good", label: "GOOD" },
      { cls: "strong", label: "STRONG" },
    ];
    const level = levels[score];
    el.textContent = level.label;
    el.className = "aip-strength " + level.cls;
  });

  // Add provider
  document.getElementById("btn-aip-add").addEventListener("click", () => {
    state.editingProviderIdx = -1;
    document.getElementById("apf-title").textContent = "Add Provider";
    document.getElementById("apf-alias").value = "";
    document.getElementById("apf-model").value = "gpt-5.3-codex";
    document.getElementById("apf-key").value = "";
    document.getElementById("apf-url").value = "";
    document.getElementById("apf-model-name").value = "";
    document.getElementById("apf-default-toggle").className = "apf-toggle";
    document.getElementById("apf-test-result").className = "apf-test-result";
    document.getElementById("btn-apf-delete").className = "apf-delete-btn";
    document.getElementById("btn-apf-duplicate").className = "apf-duplicate-btn";
    showView("add-provider");
  });

  document.getElementById("btn-apf-back").addEventListener("click", () => showView("ai-providers"));
  document.getElementById("apf-default-toggle").addEventListener("click", function () {
    this.classList.toggle("on");
  });

  // Save provider
  document.getElementById("btn-apf-save").addEventListener("click", async () => {
    const alias = document.getElementById("apf-alias").value.trim();
    const model = document.getElementById("apf-model").value;
    const key = document.getElementById("apf-key").value.trim();
    const url = document.getElementById("apf-url").value.trim();
    const modelName = document.getElementById("apf-model-name").value.trim();
    const isDefault = document.getElementById("apf-default-toggle").classList.contains("on");
    if (!alias || !key) { alert("Alias and API Key are required"); return; }

    if (isDefault) state.aiProviders.forEach(p => p.isDefault = false);

    if (state.editingProviderIdx >= 0) {
      const p = state.aiProviders[state.editingProviderIdx];
      p.alias = alias; p.model = model; p.key = key; p.url = url;
      p.modelName = modelName; p.isDefault = isDefault;
    } else {
      state.aiProviders.push({
        id: crypto.randomUUID(), alias, model, key, url, modelName, isDefault,
      });
    }

    await saveProviders();
    renderProviderList();
    showView("ai-providers");
  });

  // Delete provider
  document.getElementById("btn-apf-delete").addEventListener("click", async () => {
    if (!confirm("Delete this provider?")) return;
    state.aiProviders.splice(state.editingProviderIdx, 1);
    await saveProviders();
    renderProviderList();
    showView("ai-providers");
  });

  // Duplicate provider — clones the currently edited entry with a fresh
  // id, " (copy)" suffix on the alias, and isDefault forced off. Stays
  // on the list so the user can tweak either copy.
  document.getElementById("btn-apf-duplicate").addEventListener("click", async () => {
    if (state.editingProviderIdx < 0) return;
    const src = state.aiProviders[state.editingProviderIdx];
    const copy = {
      ...src,
      id: crypto.randomUUID(),
      alias: `${src.alias} (copy)`,
      isDefault: false,
    };
    state.aiProviders.push(copy);
    await saveProviders();
    renderProviderList();
    showView("ai-providers");
  });

  // Test connection
  document.getElementById("btn-apf-test").addEventListener("click", async () => {
    const model = document.getElementById("apf-model").value;
    const key = document.getElementById("apf-key").value.trim();
    const url = document.getElementById("apf-url").value.trim();
    const modelName = document.getElementById("apf-model-name").value.trim();
    if (!key) { alert("Enter an API key first"); return; }

    const btn = document.getElementById("btn-apf-test");
    btn.textContent = "Testing...";
    const result = document.getElementById("apf-test-result");
    const start = Date.now();

    try {
      const res = await apiFetch("/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          gameId: "_test",
          message: "Say hi in one word",
          files: [],
          history: [],
          model,
          byok: {
            key,
            url: url || undefined,
            modelName: modelName || undefined,
          },
        }),
      });
      const elapsed = Date.now() - start;
      const data = await res.json();
      if (res.ok) {
        result.className = "apf-test-result success show";
        document.getElementById("apf-test-title").textContent = `✓ Connected — ${model}`;
        document.getElementById("apf-test-title").style.color = "#6c6";
        document.getElementById("apf-test-detail").textContent = `Response: ${elapsed}ms`;
      } else {
        throw new Error(data.error || data.detail || "Unknown error");
      }
    } catch (e) {
      result.className = "apf-test-result fail show";
      document.getElementById("apf-test-title").textContent = `✗ Failed`;
      document.getElementById("apf-test-title").style.color = "#f66";
      document.getElementById("apf-test-detail").textContent = e.message;
    }
    btn.textContent = "⚡ Test Connection";
  });

  // Fetch model list — calls mono-api /models with the BYOK url+key,
  // populates the Custom Model Name datalist for autocomplete.
  document.getElementById("btn-apf-fetch-models").addEventListener("click", async () => {
    const model = document.getElementById("apf-model").value;
    const key = document.getElementById("apf-key").value.trim();
    const url = document.getElementById("apf-url").value.trim();
    const status = document.getElementById("apf-fetch-status");
    const btn = document.getElementById("btn-apf-fetch-models");
    if (!key) { status.textContent = "Enter an API key first"; status.className = "apf-fetch-status warn"; return; }

    btn.disabled = true;
    btn.textContent = "Fetching…";
    status.textContent = "";
    status.className = "apf-fetch-status";

    try {
      const res = await apiFetch("/models", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ url: url || undefined, key, model }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || data.detail || `HTTP ${res.status}`);
      const list = document.getElementById("apf-model-name-list");
      list.innerHTML = "";
      const models = data.models || [];
      // Sort: reasoning-capable first, then vision, then alpha.
      models.sort((a, b) => {
        if (a.reasoning !== b.reasoning) return a.reasoning ? -1 : 1;
        if (a.vision !== b.vision) return a.vision ? -1 : 1;
        return a.id.localeCompare(b.id);
      });
      for (const m of models) {
        const opt = document.createElement("option");
        opt.value = m.id;
        const tags = [];
        if (m.reasoning) tags.push("reasoning");
        if (m.vision) tags.push("vision");
        if (m.context) tags.push(`${Math.round(m.context / 1024)}K ctx`);
        if (tags.length) opt.label = `${m.id} — ${tags.join(", ")}`;
        list.appendChild(opt);
      }
      status.textContent = `✓ ${models.length} models — type or click the field to browse`;
      status.className = "apf-fetch-status success";
    } catch (e) {
      status.textContent = `✗ ${e.message}`;
      status.className = "apf-fetch-status error";
    }
    btn.disabled = false;
    btn.textContent = "🔍 Fetch";
  });
}
