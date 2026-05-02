// Engine-owned globals the runner binds onto the Lua instance (mirror
// of mono runtime/engine-bindings.js + runtime/engine.js). Redefining
// any of these from user code silently breaks the engine — the classic
// trap is `function touch_start(x, y) ... end`, which overwrites the
// polling primitive so touch input stops working entirely. Kept here
// so the write_file tool can reject offending patches before they land
// in R2 and the agent can self-correct from the returned error.
export const ENGINE_GLOBALS = [
  // input (polling)
  "btn", "btnp", "btnr",
  "touch", "touch_start", "touch_end", "touch_pos", "touch_posf", "touch_count",
  "swipe", "axis_x", "axis_y",
  // scene + camera
  "go", "scene_name", "cam", "cam_reset", "cam_shake", "cam_get",
  // drawing
  "cls", "pix", "gpix", "line", "rect", "rectf", "circ", "circf", "text",
  "spr", "sspr", "blit",
  // surfaces
  "screen", "canvas", "canvas_w", "canvas_h", "canvas_del",
  // audio
  "note", "tone", "noise", "wave", "sfx_stop",
  // runtime info
  "frame", "time", "date", "use_pause", "mode",
  // sensors
  "motion_x", "motion_y", "motion_z",
  "gyro_alpha", "gyro_beta", "gyro_gamma", "motion_enabled",
  // persistence
  "data_save", "data_load", "data_delete", "data_has", "data_keys", "data_clear",
];

// Scan Lua source for patterns that would overwrite an engine global:
//   function <name>(...)      ← global function decl
//   <name> = function(...)    ← global assignment
// `local function` and `local <name> =` are exempted (local scope).
// Returns the first violation as a human-readable string, or null.
export function lintEnginePrimitiveOverwrite(code) {
  if (typeof code !== "string" || !code) return null;
  // Strip Lua line comments so `-- function touch_start(...)` doesn't false-positive.
  const stripped = code.replace(/--[^\n]*/g, "");
  for (const name of ENGINE_GLOBALS) {
    // `function touch_start(...)` at line start (not preceded by `local`).
    const fnDecl = new RegExp(`(^|\\n)\\s*function\\s+${name}\\s*\\(`);
    if (fnDecl.test(stripped)) {
      return `redefines engine primitive '${name}' as a function — call it as polling inside _update instead (e.g. 'if ${name}() then ... end'), or rename with a scene prefix like 'game_${name}'.`;
    }
    // `touch_start = function(...)` or `touch_start = ...` at line start.
    const assign = new RegExp(`(^|\\n)\\s*${name}\\s*=`);
    if (assign.test(stripped)) {
      return `assigns to engine global '${name}' — choose a different name (e.g. 'my_${name}') and call the engine version directly.`;
    }
  }
  return null;
}
