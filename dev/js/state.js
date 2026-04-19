// ── Shared mutable state ──
// All modules import this single object. Firebase instances injected by app.js.

export const state = {
  // Firebase (set by app.js)
  auth: null,
  db: null,
  googleProvider: null,
  appleProvider: null,

  // Current editor session
  currentGameId: null,
  currentGameTitle: "",
  currentGameDesc: "",
  currentGameStatus: "draft",
  currentPublishedVersion: 0,
  currentFiles: [],
  currentAssets: {},     // { "images/bg.png": "blob:..." }
  chatHistory: [],
  gameRunning: false,
  sessionTokens: { prompt: 0, completion: 0, total: 0 },

  // AI providers
  aiProviders: [],       // { id, alias, model, key, url, isDefault }
  hasOnlineProviders: false,
  editingProviderIdx: -1,

  // Local sync
  linkedDirHandle: null,
  syncBusy: false,

  // Auto-fix (runs headless test only; fix request requires user confirmation)
  autoFixEnabled: true,

  // Engine
  lastEngineError: null,

  // Realtime listener cleanup
  unsubGames: null,
};

export const API_URL = "https://api.monogame.cc";

// ── Utilities ──

export function esc(s) {
  const d = document.createElement("div");
  d.textContent = s;
  return d.innerHTML.replace(/"/g, "&quot;");
}

export function chatTime() {
  const d = new Date();
  return d.getHours().toString().padStart(2, "0") + ":" + d.getMinutes().toString().padStart(2, "0");
}

export function firebaseErrorMessage(code) {
  const messages = {
    "auth/invalid-email": "Invalid email address.",
    "auth/user-disabled": "This account has been disabled.",
    "auth/user-not-found": "No account with this email.",
    "auth/wrong-password": "Incorrect password.",
    "auth/invalid-credential": "Invalid email or password.",
    "auth/email-already-in-use": "This email is already registered.",
    "auth/weak-password": "Password must be at least 6 characters.",
    "auth/too-many-requests": "Too many attempts. Try again later.",
  };
  return messages[code] || "Something went wrong. Please try again.";
}

// ── Views ──
export const views = {};

export function showView(name) {
  Object.values(views).forEach(v => v.classList.remove("active"));
  views[name].classList.add("active");
}
