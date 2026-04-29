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
