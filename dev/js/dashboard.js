// ── Dashboard + Game creation ──

import { state, esc, showView } from './state.js';
import { apiFetch } from './api.js';
import {
  collection,
  doc,
  addDoc,
  query,
  where,
  orderBy,
  onSnapshot,
  serverTimestamp,
} from "https://www.gstatic.com/firebasejs/11.7.1/firebase-firestore.js";
import { openEditor } from './editor.js';

const TEMPLATE_FILES = ["main.lua", "title.lua", "game.lua", "gameover.lua"];

function escapeLuaString(s) {
  return s.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\r?\n/g, " ");
}

async function fetchTemplate(name, title) {
  const res = await fetch(`/templates/game/${name}`);
  if (!res.ok) throw new Error(`template fetch failed: ${name} (${res.status})`);
  const body = await res.text();
  return body.replaceAll("%TITLE%", escapeLuaString(title));
}

export function renderDashboard(user) {
  document.getElementById("dash-name").textContent = user.displayName || user.email;
  const avatar = document.getElementById("dash-avatar");
  if (user.photoURL) {
    avatar.style.backgroundImage = `url(${user.photoURL})`;
    avatar.style.backgroundSize = "cover";
  }
}

export function listenGames(uid) {
  if (state.unsubGames) state.unsubGames();
  const q = query(collection(state.db, "games"), where("uid", "==", uid), orderBy("createdAt", "desc"));
  state.unsubGames = onSnapshot(q, (snap) => {
    const container = document.getElementById("dash-games");
    document.getElementById("stat-games").textContent = snap.size;
    if (snap.empty) {
      container.innerHTML = '<div class="dash-empty">No games yet. Create your first game!</div>';
      return;
    }
    container.innerHTML = snap.docs.map(d => {
      const g = d.data();
      const status = g.status === "draft" ? "Draft" : "Published";
      const plays = g.plays || 0;
      return `<div class="dash-game" data-id="${d.id}" data-title="${esc(g.title)}" data-desc="${esc(g.description || "")}">
        <div class="dash-game-thumb"></div>
        <div class="dash-game-info">
          <div class="dash-game-title">${esc(g.title)}</div>
          <div class="dash-game-meta">${status} · ${plays} plays</div>
        </div>
        <span class="dash-game-arrow">›</span>
      </div>`;
    }).join("");
  });
}

async function createGame() {
  const title = document.getElementById("newgame-title").value.trim();
  if (!title) return;
  const desc = document.getElementById("newgame-desc").value.trim();
  const user = state.auth.currentUser;
  if (!user) return;

  const btn = document.getElementById("btn-newgame-submit");
  btn.disabled = true;
  btn.textContent = "Creating...";
  try {
    const docRef = await addDoc(collection(state.db, "games"), {
      uid: user.uid,
      title,
      description: desc,
      required: [],
      engine: "0.4",
      status: "draft",
      plays: 0,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    // Seed default scene files (templates/game/) + empty chat history in parallel
    const templates = await Promise.all(
      TEMPLATE_FILES.map(async name => ({ name, content: await fetchTemplate(name, title) }))
    );
    await Promise.all([
      ...templates.map(f =>
        apiFetch(`/games/${docRef.id}/files/${f.name}`, {
          method: "PUT",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ content: f.content }),
        })
      ),
      apiFetch(`/games/${docRef.id}/files/_chat.json`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ content: JSON.stringify({ history: [] }) }),
      }),
    ]);
    openEditor(docRef.id, title);
  } catch (e) {
    alert("Failed to create game: " + e.message);
  } finally {
    btn.disabled = false;
    btn.textContent = "+ Create Game";
  }
}

export function initDashboard() {
  // New game
  document.getElementById("btn-new-game").addEventListener("click", () => {
    document.getElementById("newgame-title").value = "";
    document.getElementById("newgame-desc").value = "";
    document.querySelectorAll(".newgame-chip").forEach(c => c.classList.remove("selected"));
    showView("newgame");
  });
  document.getElementById("btn-newgame-back").addEventListener("click", () => showView("dashboard"));
  document.getElementById("btn-newgame-submit").addEventListener("click", createGame);
  document.getElementById("btn-newgame-create").addEventListener("click", createGame);

  // Game click (event delegation on dash-games)
  document.getElementById("dash-games").addEventListener("click", (e) => {
    const el = e.target.closest(".dash-game");
    if (el) openEditor(el.dataset.id, el.dataset.title, el.dataset.desc);
  });
}
