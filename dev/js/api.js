// ── API fetch wrapper ──
// Auto-attaches auth header from state.auth

import { state, API_URL } from './state.js';

export async function apiFetch(path, options = {}) {
  const token = await state.auth.currentUser.getIdToken();
  const headers = { Authorization: `Bearer ${token}`, ...options.headers };
  return fetch(`${API_URL}${path}`, { ...options, headers });
}

export async function saveFile(filename, content) {
  await apiFetch(`/games/${state.currentGameId}/files/${filename}`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ content }),
  });
}

export async function loadFiles() {
  const res = await apiFetch(`/games/${state.currentGameId}/files`);
  return (await res.json()).files;
}

export async function saveChatHistory() {
  try {
    await apiFetch(`/games/${state.currentGameId}/files/_chat.json`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ content: JSON.stringify({ history: state.chatHistory }) }),
    });
  } catch {}
}

export async function deleteR2File(name) {
  await apiFetch(`/games/${state.currentGameId}/files/${name}`, { method: "DELETE" });
}
