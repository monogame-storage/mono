// ── App entry point ──
// Firebase init, routing, module initialization

import { state, views, showView } from './state.js';
import { initAuth } from './auth.js';
import { renderDashboard, listenGames, initDashboard } from './dashboard.js';
import { initSettings, openDevSettings, openAIProviders } from './settings.js';
import { initEditor, openEditor, switchTab } from './editor.js';

import { initializeApp } from "https://www.gstatic.com/firebasejs/11.7.1/firebase-app.js";
import {
  getAuth,
  onAuthStateChanged,
  GoogleAuthProvider,
  OAuthProvider,
} from "https://www.gstatic.com/firebasejs/11.7.1/firebase-auth.js";
import {
  getFirestore,
  doc,
  getDoc,
} from "https://www.gstatic.com/firebasejs/11.7.1/firebase-firestore.js";

// ── Firebase init ──

const app = initializeApp({
  apiKey: "AIzaSyAyTiJx_JkVdQoh8b5bDo-ttvp175vy8PM",
  authDomain: "mono-5b951.firebaseapp.com",
  projectId: "mono-5b951",
  storageBucket: "mono-5b951.firebasestorage.app",
  messagingSenderId: "850069827366",
  appId: "1:850069827366:web:a196c04bbf4c93bd061be7",
  measurementId: "G-DD02EX6MWC"
});

state.auth = getAuth(app);
state.db = getFirestore(app);
state.googleProvider = new GoogleAuthProvider();
state.appleProvider = new OAuthProvider("apple.com");

// ── Register views ──

views.login = document.getElementById("view-login");
views.signup = document.getElementById("view-signup");
views.newgame = document.getElementById("view-newgame");
views.editor = document.getElementById("view-editor");
views["ai-providers"] = document.getElementById("view-ai-providers");
views["add-provider"] = document.getElementById("view-add-provider");
views.devsettings = document.getElementById("view-devsettings");
views.dashboard = document.getElementById("view-dashboard");

// ── Init modules ──

initAuth();
initDashboard();
initSettings();
initEditor();

// ── Auth state → routing ──

// One-time cleanup of pre-uid-scoped vault keys (ALPHA, no migration).
localStorage.removeItem("mono_vault_pp");
localStorage.removeItem("mono_vault_save_local");

let lastUid = null;
onAuthStateChanged(state.auth, async (user) => {
  const newUid = user?.uid || null;
  if (newUid !== lastUid) {
    state.vaultPp = null;
    state.aiProviders = [];
    state.hasOnlineProviders = false;
  }
  lastUid = newUid;

  if (user) {
    renderDashboard(user);
    listenGames(user.uid);

    const hash = location.hash;
    const editorMatch = hash.match(/^#editor\/([^/]+)(?:\/(files|ai|play|game))?(?:\/(view|edit)\/(.+))?$/);
    if (editorMatch) {
      const snap = await getDoc(doc(state.db, "games", editorMatch[1]));
      if (snap.exists() && snap.data().uid === user.uid) {
        await openEditor(editorMatch[1], snap.data().title, snap.data().description);
        if (editorMatch[2]) switchTab(editorMatch[2]);
        // Restore file view/edit state
        if (editorMatch[3] && editorMatch[4]) {
          const fileName = decodeURIComponent(editorMatch[4]);
          const { openFileSheet, openEditMode } = window._editorFiles || {};
          if (editorMatch[3] === "edit" && openEditMode) openEditMode(fileName);
          else if (editorMatch[3] === "view" && openFileSheet) openFileSheet(fileName);
        }
      } else {
        showView("dashboard");
      }
    } else if (hash === "#settings/ai") {
      openDevSettings();
      openAIProviders();
    } else if (hash === "#settings") {
      openDevSettings();
    } else {
      showView("dashboard");
    }
  } else {
    if (state.unsubGames) { state.unsubGames(); state.unsubGames = null; }
    showView("login");
  }
});
