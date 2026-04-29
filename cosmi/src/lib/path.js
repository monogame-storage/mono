// Reject any agent-tool path that would escape the caller's game
// directory after string concatenation with the R2 key prefix. The
// agent is untrusted input — without this, `{ "path": "../../other-
// game/secret.lua" }` would reach other games under the same user
// (and other users depending on prefix structure).
export function validateAgentPath(p) {
  if (typeof p !== "string" || !p) return "path required";
  if (p.includes("..")) return "path must not contain '..'";
  if (p.startsWith("/") || p.includes("\\")) return "path must be a relative POSIX path";
  if (p.includes("\0")) return "path must not contain NUL";
  return null;
}

// Reject malformed gameId values before they hit R2 as a key prefix.
// Client-supplied — without this, `gameId: "../foo"`, `""`, or
// `"_admin"` would create weird keys, collide with internal admin
// prefixes, or split a single uid's namespace into hard-to-clean
// shards. Pattern matches the Firestore auto-id shape (alphanumeric
// + dash/underscore) without imposing an exact length so legacy ids
// still validate. Returns null for ok, error string otherwise.
export function validateGameId(g) {
  if (typeof g !== "string" || !g) return "gameId required";
  if (!/^[a-zA-Z0-9_-]{1,64}$/.test(g)) {
    return "gameId must match /^[a-zA-Z0-9_-]{1,64}$/";
  }
  return null;
}
