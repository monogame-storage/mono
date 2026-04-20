// ── cart.json helpers ──
// cart.json mirrors the Firestore-backed metadata so offline consumers
// (packaged Android carts, static deploys without Firestore) can still
// read a game's manifest. The online editor treats Firestore as the
// source of truth and syncs cart.json best-effort after every write.

import { apiFetch } from './api.js';

export async function loadCart(gameId) {
  try {
    const res = await apiFetch(`/games/${gameId}/files/cart.json`);
    if (!res.ok) return null;
    const { content } = await res.json();
    return JSON.parse(content);
  } catch {
    return null;
  }
}

export function serializeCart(cart) {
  return JSON.stringify(cart, null, 2) + "\n";
}

export async function saveCart(gameId, cart) {
  await apiFetch(`/games/${gameId}/files/cart.json`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ content: serializeCart(cart) }),
  });
}

export async function fetchCartTemplate() {
  const res = await fetch(`/templates/game/cart.json`);
  if (!res.ok) throw new Error(`cart.json template fetch failed (${res.status})`);
  return await res.json();
}

let cachedEngineVersion = null;
async function getEngineVersion() {
  if (cachedEngineVersion) return cachedEngineVersion;
  const res = await fetch(`/VERSION`);
  if (!res.ok) throw new Error(`VERSION fetch failed (${res.status})`);
  cachedEngineVersion = (await res.text()).trim();
  return cachedEngineVersion;
}

export async function buildCart(title, description) {
  const [cart, engine] = await Promise.all([fetchCartTemplate(), getEngineVersion()]);
  cart.engine = engine;
  cart.title = title;
  if (description) cart.description = description;
  return cart;
}
