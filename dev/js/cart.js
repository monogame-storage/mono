// ── cart.json helpers ──
// cart.json is the authoritative game manifest. Firestore keeps a
// denormalized copy of title/description/engine/required so the
// dashboard can list games without N extra fetches.

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

export async function buildCart(title, description) {
  const cart = await fetchCartTemplate();
  cart.title = title;
  if (description) cart.description = description;
  return cart;
}
