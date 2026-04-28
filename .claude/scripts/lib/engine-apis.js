// engine-apis.js — shared helper for mono tooling
//
// Centralizes knowledge of the Mono engine's public API surface and the
// mapping between internal `_`-prefixed glue helpers and their user-facing
// wrapper names. Consumed by:
//   - .claude/scripts/mono-lint.js          (defensive-api-check rule)
//   - .claude/scripts/mono-docs-sync.js     (DEV.md drift detection)
//   - dev/headless/mono-runner.js           (--coverage report)
//
// Keep this file minimal and zero-dependency (no third-party imports) so
// it can be required by both the repo-local scripts and the copied-into-
// project editor template.

"use strict";

const fs = require("fs");
const path = require("path");

// Map from internal glue name (as exposed via lua.global.set in engine.js
// and mono-runner.js) → the public name the user actually calls.
//
// Both halves of a pair (e.g., _touch_pos_x + _touch_pos_y → touch_pos)
// resolve to the same public name. Tools that need to count calls exactly
// once per public call should use `buildCoverageRename()` instead, which
// demotes all-but-one half of each pair to null.
const INTERNAL_TO_PUBLIC = Object.freeze({
  _btn: "btn",
  _btnp: "btnp",
  _cam_get_x: "cam_get",
  _cam_get_y: "cam_get",
  _touch: "touch",
  _touch_start: "touch_start",
  _touch_end: "touch_end",
  _touch_pos_x: "touch_pos",
  _touch_pos_y: "touch_pos",
  _touch_posf_x: "touch_posf",
  _touch_posf_y: "touch_posf",
});

// Default path to engine.js, resolved relative to the monorepo root.
// Scripts can override with an explicit path argument.
const DEFAULT_REPO_ROOT = path.resolve(__dirname, "../../..");
const DEFAULT_ENGINE_JS = path.join(DEFAULT_REPO_ROOT, "runtime/engine.js");

/**
 * Parse `runtime/engine.js` and return the set of public API names
 * exposed via `lua.global.set("name", ...)` calls.
 *
 * `_`-prefixed internals are either mapped to their public wrapper (if
 * present in INTERNAL_TO_PUBLIC) or skipped.
 *
 * @param {string} [enginePath] — absolute path to engine.js (defaults to
 *   runtime/engine.js under the repo root)
 * @returns {Set<string>}
 */
function loadPublicAPIs(enginePath) {
  const file = enginePath || DEFAULT_ENGINE_JS;
  const names = new Set();
  if (!fs.existsSync(file)) return names;
  const src = fs.readFileSync(file, "utf8");
  const setRe = /lua\.global\.set\(\s*"([^"]+)"/g;
  let m;
  while ((m = setRe.exec(src)) !== null) {
    const raw = m[1];
    if (raw in INTERNAL_TO_PUBLIC) {
      names.add(INTERNAL_TO_PUBLIC[raw]);
    } else if (!raw.startsWith("_")) {
      names.add(raw);
    }
  }
  return names;
}

/**
 * Build a rename map suitable for merging API call counts in a coverage
 * report: the first occurrence of each public name becomes the primary
 * (internal → public), subsequent occurrences are demoted to null so
 * the caller knows to drop them.
 *
 * Derived automatically from INTERNAL_TO_PUBLIC so new pairs added above
 * propagate everywhere without further edits.
 *
 * @returns {Record<string, string | null>}
 */
function buildCoverageRename() {
  const seen = new Set();
  const out = {};
  for (const [internal, pub] of Object.entries(INTERNAL_TO_PUBLIC)) {
    if (seen.has(pub)) {
      out[internal] = null;
    } else {
      out[internal] = pub;
      seen.add(pub);
    }
  }
  return out;
}

module.exports = {
  INTERNAL_TO_PUBLIC,
  loadPublicAPIs,
  buildCoverageRename,
  DEFAULT_ENGINE_JS,
};
