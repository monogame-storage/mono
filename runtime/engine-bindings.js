/**
 * Mono Engine Bindings — shared Lua API registration layer
 *
 * Used by three runners:
 *   - runtime/engine.js       (browser, full rendering)
 *   - dev/test-worker.js      (Web Worker, pre-publish smoke test)
 *   - dev/headless/mono-runner.js (Node CLI, CI + tools)
 *
 * This file is loaded as a **classic script** (not ESM) so it works as
 * <script src>, importScripts(), and require() without transpilation.
 *
 * API:
 *   MonoBindings.bind(lua, hooks) — registers all shared globals onto the
 *   given Wasmoon Lua instance. Each runner supplies `hooks` for the
 *   environment-specific parts (real canvas / in-memory surface / stubs).
 *
 * What this layer owns (single source of truth):
 *   - Valid key / align constants
 *   - Input primitive validation (_btn / _btnp / _btnr / _touch_*)
 *   - Lua wrappers (btn / btnp / btnr / touch / touch_start / touch_end /
 *                   touch_pos / touch_posf / cam_get)
 *   - package.preload loop for require() support
 *   - Scene glue (go / scene_name)
 *
 * What hooks own:
 *   - Drawing primitives (cls / pix / rect / text / ...)
 *   - Audio primitives (note / tone / noise / wave / sfx_stop)
 *   - Input state (hooks.input.btn(k) → bool)
 *   - Camera offsets (hooks.cam.getX() / getY())
 *   - Mode / frame / time
 *   - Image loading
 *   - Scene state (hooks.scene.current / pending; bindings set pending)
 */
(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else if (typeof self !== "undefined") self.MonoBindings = api;
  else if (typeof globalThis !== "undefined") globalThis.MonoBindings = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  const VALID_KEYS = { up:1, down:1, left:1, right:1, a:1, b:1, start:1, select:1 };

  const ALIGN = {
    LEFT: 0,
    HCENTER: 1,
    RIGHT: 2,
    VCENTER: 4,
    CENTER: 5,
  };

  function validateKey(fnName, k) {
    if (typeof k !== "string" || !VALID_KEYS[k]) {
      throw new Error(
        `${fnName}() invalid key "${k}". Valid: "up","down","left","right","a","b","start","select"`
      );
    }
  }

  /**
   * Register the shared API surface on a Lua instance.
   *
   * @param {object} lua   — Wasmoon Lua engine instance
   * @param {object} hooks — runner-specific callbacks
   *   hooks.input: {
   *     btn(k), btnp(k), btnr(k),          // bool
   *     touch(), touchStart(), touchEnd(), // bool
   *     touchCount(),                      // int
   *     touchPosX(i), touchPosY(i),        // int | false
   *     touchPosfX(i), touchPosfY(i),      // number | false
   *     swipe(),                           // "up"|"down"|"left"|"right"|false
   *     axisX(), axisY(),                  // number
   *   }
   *   hooks.cam: { getX(), getY() }
   *   hooks.scene: { current: string|null, pending: string|null }   // mutable
   *   hooks.modules: { "path/to.lua": "source", ... }               // optional
   *   hooks.save: { backend, cartId } | undefined                   // optional
   *     backend: MonoSave.MemoryBackend | MonoSave.WebBackend instance
   *     cartId:  non-empty string identifying the cart's save bucket
   *     If absent, data_* globals are installed as throwing stubs.
   */
  async function bind(lua, hooks) {
    // ── Constants ──
    lua.global.set("ALIGN_LEFT", ALIGN.LEFT);
    lua.global.set("ALIGN_HCENTER", ALIGN.HCENTER);
    lua.global.set("ALIGN_RIGHT", ALIGN.RIGHT);
    lua.global.set("ALIGN_VCENTER", ALIGN.VCENTER);
    lua.global.set("ALIGN_CENTER", ALIGN.CENTER);

    // ── Input primitives ──
    const input = hooks.input;
    lua.global.set("_btn",  (k) => { validateKey("btn",  k); return input.btn(k)  ? 1 : 0; });
    lua.global.set("_btnp", (k) => { validateKey("btnp", k); return input.btnp(k) ? 1 : 0; });
    lua.global.set("_btnr", (k) => { validateKey("btnr", k); return input.btnr(k) ? 1 : 0; });

    lua.global.set("_touch",       () => input.touch()       ? 1 : 0);
    lua.global.set("_touch_start", () => input.touchStart()  ? 1 : 0);
    lua.global.set("_touch_end",   () => input.touchEnd()    ? 1 : 0);
    lua.global.set("touch_count",  () => input.touchCount());
    lua.global.set("_touch_pos_x",  (i) => input.touchPosX(i));
    lua.global.set("_touch_pos_y",  (i) => input.touchPosY(i));
    lua.global.set("_touch_posf_x", (i) => input.touchPosfX(i));
    lua.global.set("_touch_posf_y", (i) => input.touchPosfY(i));

    lua.global.set("swipe",  () => input.swipe());
    lua.global.set("axis_x", () => input.axisX());
    lua.global.set("axis_y", () => input.axisY());

    // ── Camera accessors used by cam_get wrapper ──
    lua.global.set("_cam_get_x", () => hooks.cam.getX());
    lua.global.set("_cam_get_y", () => hooks.cam.getY());

    // ── package.preload (so require() works without a filesystem) ──
    const modules = hooks.modules || {};
    for (const [path, src] of Object.entries(modules)) {
      const modName = path.replace(/\.lua$/, "").replace(/\//g, ".").replace(/"/g, "");
      lua.global.set("_tmp_mod_src", src);
      lua.global.set("_tmp_mod_name", modName);
      await lua.doString(
        `package.preload[_tmp_mod_name] = load(_tmp_mod_src, "@" .. _tmp_mod_name .. ".lua")`
      );
    }
    await lua.doString("_tmp_mod_src = nil; _tmp_mod_name = nil");

    // ── Scene glue ──
    // bindings own `go()` and `scene_name()`. Runners inspect
    // hooks.scene.pending after each frame and call their own
    // activateScene(). hooks.scene.current is set by the runner.
    const scene = hooks.scene;
    lua.global.set("go",         (name) => { scene.pending = name; });
    lua.global.set("scene_name", () => scene.current || false);

    // ── Persistence (data_save / data_load / data_delete / data_has /
    // data_keys / data_clear). The runner supplies hooks.save with a
    // backend (read/write/clear) plus the cartId string. We hold the
    // bucket in JS-side memory so reads are zero-allocation and writes
    // are write-through. validateKey + serializeBucket throw on any
    // policy violation; those throws become Lua errors via Wasmoon.
    if (hooks.save) {
      const MonoSaveLib =
        (typeof globalThis !== "undefined" && globalThis.MonoSave) ? globalThis.MonoSave :
        (typeof self !== "undefined" && self.MonoSave) ? self.MonoSave :
        (typeof require === "function" ? require("./save.js") : null);
      if (!MonoSaveLib) throw new Error("MonoSave library not loaded");

      const backend = hooks.save.backend;
      const cartId = hooks.save.cartId;
      if (!backend) throw new Error("hooks.save.backend is required");
      if (typeof cartId !== "string" || !cartId) throw new Error("hooks.save.cartId must be a non-empty string");

      let bucket = backend.read(cartId);
      if (!bucket || typeof bucket !== "object" || Array.isArray(bucket)) bucket = {};

      /**
       * @lua data_save(key: string, value: any): void
       * @group Data
       * @desc Persist a value under a key in this cart's local save bucket. Value can be a number, string, boolean, or table (nested up to 16 levels). Passing `nil` deletes the key (matches Lua's `t[k] = nil` semantics — equivalent to `data_delete(key)`). Throws on invalid input or quota overflow.
       */
      lua.global.set("data_save", (key, value) => {
        MonoSaveLib.validateKey(key);
        // Lua `nil` arrives as JS `undefined` via Wasmoon. Mirror Lua table
        // semantics: `data_save(k, nil)` deletes the key. No-op if the key
        // wasn't there to begin with.
        if (value === undefined) {
          if (!Object.prototype.hasOwnProperty.call(bucket, key)) return;
          const next = Object.assign({}, bucket);
          delete next[key];
          backend.write(cartId, next);
          bucket = next;
          return;
        }
        // Wasmoon presents Lua tables to JS as plain objects; JSON.stringify
        // (called inside serializeBucket) walks them like any other object.
        // Take a defensive deep copy via JSON round-trip so later mutations
        // to the Lua table don't reach into our cache.
        const next = Object.assign({}, bucket);
        next[key] = JSON.parse(JSON.stringify(value));
        // serializeBucket runs validation on the candidate bucket; if it
        // throws (bad value, NaN, cycle, depth, quota), `bucket` is unchanged.
        MonoSaveLib.serializeBucket(next);
        // Commit cache only AFTER disk succeeds — otherwise a failed
        // backend.write would leave the in-memory cache ahead of storage,
        // and subsequent data_load would return data that won't survive
        // a reload.
        backend.write(cartId, next);
        bucket = next;
      });

      /**
       * @lua data_load(key: string): any
       * @group Data
       * @desc Returns the value previously stored under `key`, or `nil` if missing. Returns a fresh copy — mutating the returned table does not auto-persist.
       */
      lua.global.set("data_load", (key) => {
        MonoSaveLib.validateKey(key);
        const v = bucket[key];
        if (v === undefined) return null;
        // Return a fresh copy so Lua-side mutations don't reach into the cache.
        if (v !== null && typeof v === "object") return JSON.parse(JSON.stringify(v));
        return v;
      });

      /**
       * @lua data_delete(key: string): boolean
       * @group Data
       * @desc Remove `key` from the bucket. Returns `true` if the key existed, `false` otherwise.
       */
      lua.global.set("data_delete", (key) => {
        MonoSaveLib.validateKey(key);
        if (!Object.prototype.hasOwnProperty.call(bucket, key)) return false;
        const next = Object.assign({}, bucket);
        delete next[key];
        backend.write(cartId, next);
        bucket = next;
        return true;
      });

      /**
       * @lua data_has(key: string): boolean
       * @group Data
       * @desc Returns `true` if `key` is currently stored.
       */
      lua.global.set("data_has", (key) => {
        MonoSaveLib.validateKey(key);
        return Object.prototype.hasOwnProperty.call(bucket, key);
      });

      /**
       * @lua data_keys(): table
       * @group Data
       * @desc Returns a sorted array of currently-stored keys.
       */
      lua.global.set("data_keys", () => {
        // Lua tables don't differentiate array/dict — Wasmoon converts a
        // JS array into a 1-indexed Lua sequence. Sort for determinism.
        return Object.keys(bucket).sort();
      });

      /**
       * @lua data_clear(): void
       * @group Data
       * @desc Wipes the entire bucket for the current cart.
       */
      lua.global.set("data_clear", () => {
        backend.clear(cartId);
        bucket = {};
      });
    } else {
      // No save hook installed (legacy boot calls). Stub out the six
      // globals so a game's call surface fails loud instead of silent.
      const stub = () => { throw new Error("save: backend not configured"); };
      lua.global.set("data_save",   stub);
      lua.global.set("data_load",   stub);
      lua.global.set("data_delete", stub);
      lua.global.set("data_has",    stub);
      lua.global.set("data_keys",   stub);
      lua.global.set("data_clear",  stub);
    }

    // ── Doc stubs for Lua-side wrappers (btn/btnp/btnr live in doString below) ──
    // These stubs are immediately overwritten by the doString Lua definitions.
    // They exist only so the JSDoc parser can pick up the @lua annotations.
    /**
     * @lua btn(key: Key): boolean
     * @group Input
     * @desc Returns true while the given button is held. Key ∈ "up","down","left","right","a","b","start","select".
     */
    lua.global.set("btn", () => false);

    /**
     * @lua btnp(key: Key): boolean
     * @group Input
     * @desc Returns true on the frame the button was newly pressed (was not down on the previous frame).
     */
    lua.global.set("btnp", () => false);

    /**
     * @lua btnr(key: Key): boolean
     * @group Input
     * @desc Returns true on the frame the button was released. Use instead of btnp() for scene transitions and confirmations — acting on release feels more forgiving.
     */
    lua.global.set("btnr", () => false);

    /**
     * @lua touch(): boolean
     * @group Input
     * @desc Returns true while at least one finger is on the screen.
     */
    lua.global.set("touch", () => false);

    /**
     * @lua touch_start(): boolean
     * @group Input
     * @desc Returns true on the frame a touch began.
     */
    lua.global.set("touch_start", () => false);

    /**
     * @lua touch_end(): boolean
     * @group Input
     * @desc Returns true on the frame a touch was released.
     */
    lua.global.set("touch_end", () => false);

    /**
     * @lua touch_pos(i?: number): number, number | false
     * @group Input
     * @desc Integer pixel coordinates (x, y) of touch i (1-based, default 1). Returns false if no such touch.
     */
    lua.global.set("touch_pos", () => false);

    /**
     * @lua touch_posf(i?: number): number, number | false
     * @group Input
     * @desc Sub-pixel float coordinates (x, y) of touch i (1-based, default 1). Returns false if no such touch.
     */
    lua.global.set("touch_posf", () => false);

    /**
     * @lua cam_get(): number, number
     * @group Camera
     * @desc Returns the current camera offset (x, y) set by cam().
     */
    lua.global.set("cam_get", () => false);

    // ── Lua-side wrappers (single source of truth) ──
    // Wasmoon returns `false` for JS `false` but `nil` feels more natural
    // for the primitives that can return false — wrappers normalize.
    await lua.doString(`
function btn(k)          return _btn(k) == 1 end
function btnp(k)         return _btnp(k) == 1 end
function btnr(k)         return _btnr(k) == 1 end
function touch()         return _touch() == 1 end
function touch_start()   return _touch_start() == 1 end
function touch_end()     return _touch_end() == 1 end
function touch_pos(i)
  i = i or 1
  local x = _touch_pos_x(i)
  if x == false then return false end
  return x, _touch_pos_y(i)
end
function touch_posf(i)
  i = i or 1
  local x = _touch_posf_x(i)
  if x == false then return false end
  return x, _touch_posf_y(i)
end
function cam_get() return _cam_get_x(), _cam_get_y() end
`);
  }

  return {
    bind,
    VALID_KEYS,
    ALIGN,
  };
});
