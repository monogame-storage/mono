// ── Login / Signup logic ──

import { state, showView, firebaseErrorMessage } from './state.js';
import {
  signInWithEmailAndPassword,
  createUserWithEmailAndPassword,
  updateProfile,
  signInWithPopup,
} from "https://www.gstatic.com/firebasejs/11.7.1/firebase-auth.js";

function showError(id, msg) {
  const el = document.getElementById(id);
  el.textContent = msg;
  el.classList.add("show");
}

function clearError(id) {
  const el = document.getElementById(id);
  el.textContent = "";
  el.classList.remove("show");
}

async function socialLogin(provider) {
  try {
    await signInWithPopup(state.auth, provider);
  } catch (e) {
    if (e.code !== "auth/popup-closed-by-user") {
      showError("login-error", firebaseErrorMessage(e.code));
    }
  }
}

export function initAuth() {
  // Email login
  document.getElementById("btn-login").addEventListener("click", async () => {
    clearError("login-error");
    const email = document.getElementById("login-email").value.trim();
    const password = document.getElementById("login-password").value;
    if (!email || !password) return showError("login-error", "Enter email and password.");
    try {
      await signInWithEmailAndPassword(state.auth, email, password);
    } catch (e) {
      showError("login-error", firebaseErrorMessage(e.code));
    }
  });

  // Email signup
  document.getElementById("btn-signup").addEventListener("click", async () => {
    clearError("signup-error");
    const name = document.getElementById("signup-name").value.trim();
    const email = document.getElementById("signup-email").value.trim();
    const password = document.getElementById("signup-password").value;
    if (!name || !email || !password) return showError("signup-error", "Fill in all fields.");
    if (password.length < 6) return showError("signup-error", "Password must be at least 6 characters.");
    try {
      const cred = await createUserWithEmailAndPassword(state.auth, email, password);
      await updateProfile(cred.user, { displayName: name });
    } catch (e) {
      showError("signup-error", firebaseErrorMessage(e.code));
    }
  });

  // Social login
  document.getElementById("btn-google-login").addEventListener("click", () => socialLogin(state.googleProvider));
  document.getElementById("btn-apple-login").addEventListener("click", () => socialLogin(state.appleProvider));
  document.getElementById("btn-google-signup").addEventListener("click", () => socialLogin(state.googleProvider));
  document.getElementById("btn-apple-signup").addEventListener("click", () => socialLogin(state.appleProvider));

  // Navigation
  document.getElementById("link-signup").addEventListener("click", (e) => { e.preventDefault(); clearError("login-error"); showView("signup"); });
  document.getElementById("link-login").addEventListener("click", (e) => { e.preventDefault(); clearError("signup-error"); showView("login"); });
}
