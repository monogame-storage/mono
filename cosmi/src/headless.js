/**
 * Headless Mono test runner for Cloudflare Workers.
 * Stripped from mono-test.js — runs Lua game code without DOM/canvas.
 * Returns errors or success after N frames.
 */

import wasmModule from "../node_modules/wasmoon/dist/glue.wasm";

const W = 160, H = 120;

function buildPalette(bits) {
  const n = 1 << bits;
  const p = [];
  for (let i = 0; i < n; i++) p.push(Math.round(i * 255 / (n - 1)));
  return p;
}

export async function runHeadless(files, frames = 30, colors = 4) {
  const errors = [];
  const output = [];
  let palette = buildPalette(colors);

  // Surfaces
  const surfaces = {};
  let surfIdCounter = 1;
  const screenBuf = new Uint8Array(W * H);
  surfaces[0] = { buf: screenBuf, w: W, h: H };

  function getSurf(id) { return surfaces[id] || null; }

  // Camera
  let camX = 0, camY = 0;

  // Images (stub)
  const images = {};
  let imageIdCounter = 1;

  // Drawing stubs (minimal — just enough to not crash)
  function cls(s, c) { s.buf.fill(c || 0); }
  function setPix(s, x, y, c) {
    if (x >= 0 && x < s.w && y >= 0 && y < s.h) s.buf[y * s.w + x] = c;
  }
  function getPix(s, x, y) {
    if (x >= 0 && x < s.w && y >= 0 && y < s.h) return s.buf[y * s.w + x];
    return 0;
  }

  try {
    // Dynamic import of patched wasmoon (UMD → needs require shim)
    const wasmoon = await import("./wasmoon-patched.js");
    const LuaFactory = wasmoon.LuaFactory || wasmoon.default?.LuaFactory;
    const factory = new LuaFactory(wasmModule);
    const lua = await factory.createEngine();

    // Constants
    lua.global.set("SCREEN_W", W);
    lua.global.set("SCREEN_H", H);
    lua.global.set("COLORS", palette.length);
    lua.global.set("ALIGN_LEFT", 0);
    lua.global.set("ALIGN_HCENTER", 1);
    lua.global.set("ALIGN_RIGHT", 2);
    lua.global.set("ALIGN_VCENTER", 4);
    lua.global.set("ALIGN_CENTER", 5);

    // Drawing
    lua.global.set("cls", (id, c) => { const s = getSurf(id); if (s) cls(s, c); });
    lua.global.set("pix", (id, x, y, c) => { const s = getSurf(id); if (s) setPix(s, Math.floor(x) - camX, Math.floor(y) - camY, c); });
    lua.global.set("gpix", (id, x, y) => { const s = getSurf(id); return s ? getPix(s, x, y) : 0; });
    lua.global.set("line", () => {});
    lua.global.set("rect", () => {});
    lua.global.set("rectf", (id, x, y, w, h, c) => {
      const s = getSurf(id); if (!s) return;
      const x0 = Math.max(0, Math.floor(x) - camX);
      const y0 = Math.max(0, Math.floor(y) - camY);
      const x1 = Math.min(s.w, Math.floor(x + w) - camX);
      const y1 = Math.min(s.h, Math.floor(y + h) - camY);
      for (let py = y0; py < y1; py++)
        for (let px = x0; px < x1; px++) s.buf[py * s.w + px] = c;
    });
    lua.global.set("circ", () => {});
    lua.global.set("circf", () => {});
    lua.global.set("text", () => {});
    lua.global.set("spr", () => {});
    lua.global.set("sspr", () => {});
    lua.global.set("drawImage", () => {});
    lua.global.set("drawImageRegion", () => {});
    lua.global.set("vrow", () => "");
    lua.global.set("blit", () => {});

    // Camera
    lua.global.set("cam", (x, y) => { if (x !== undefined) { camX = x; camY = y || 0; } });
    lua.global.set("_cam_get_x", () => camX);
    lua.global.set("_cam_get_y", () => camY);
    lua.global.set("cam_shake", () => {});
    lua.global.set("cam_reset", () => { camX = 0; camY = 0; });

    // Surfaces
    lua.global.set("screen", () => 0);
    lua.global.set("canvas", (w, h) => {
      const id = surfIdCounter++;
      surfaces[id] = { buf: new Uint8Array(w * h), w, h };
      return id;
    });
    lua.global.set("canvas_w", (id) => { const s = getSurf(id); return s ? s.w : 0; });
    lua.global.set("canvas_h", (id) => { const s = getSurf(id); return s ? s.h : 0; });
    lua.global.set("canvas_del", (id) => { delete surfaces[id]; });

    // Audio stubs
    const NOTE_NAMES = new Set();
    for (const n of ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"])
      for (let o = 0; o <= 8; o++) NOTE_NAMES.add(n + o);
    lua.global.set("note", (ch, noteStr) => {
      if (!NOTE_NAMES.has(String(noteStr).toUpperCase()))
        throw new Error("note: invalid note '" + noteStr + "'");
    });
    lua.global.set("tone", () => {});
    lua.global.set("noise", () => {});
    lua.global.set("wave", () => {});
    lua.global.set("sfx_stop", () => {});

    // Input stubs
    const validKeys = { up:1, down:1, left:1, right:1, a:1, b:1, start:1, select:1 };
    lua.global.set("_btn", (k) => {
      if (typeof k !== "string" || !validKeys[k]) throw new Error('btn() invalid key "' + k + '". Valid: "up","down","left","right","a","b","start","select"');
      return 0;
    });
    lua.global.set("_btnp", (k) => {
      if (typeof k !== "string" || !validKeys[k]) throw new Error('btnp() invalid key "' + k + '"');
      return 0;
    });
    lua.global.set("_touch", () => 0);
    lua.global.set("_touch_start", () => 0);
    lua.global.set("_touch_end", () => 0);
    lua.global.set("touch_count", () => 0);
    lua.global.set("_touch_pos_x", () => false);
    lua.global.set("_touch_pos_y", () => false);
    lua.global.set("_touch_posf_x", () => false);
    lua.global.set("_touch_posf_y", () => false);
    lua.global.set("swipe", () => false);
    lua.global.set("axis_x", () => 0);
    lua.global.set("axis_y", () => 0);

    // Frame counter
    let frameNum = 0;
    lua.global.set("frame", () => frameNum);
    lua.global.set("use_pause", () => {});

    // Time
    const bootTime = Date.now();
    lua.global.set("time", () => (Date.now() - bootTime) / 1000);
    lua.global.set("date", () => {
      const d = new Date();
      return { year: d.getFullYear(), month: d.getMonth() + 1, day: d.getDate(),
        hour: d.getHours(), min: d.getMinutes(), sec: d.getSeconds(),
        wday: d.getDay() + 1, ms: d.getMilliseconds() };
    });

    // Mode
    lua.global.set("mode", (bits) => {
      if (bits !== 1 && bits !== 2 && bits !== 4) throw new Error("mode() invalid: " + bits);
      palette = buildPalette(bits);
      lua.global.set("COLORS", palette.length);
    });

    // Images (stub — no actual loading in Worker)
    lua.global.set("loadImage", () => {
      const id = imageIdCounter++;
      images[id] = { w: 1, h: 1 };
      return id;
    });
    lua.global.set("imageWidth", (id) => images[id]?.w || 0);
    lua.global.set("imageHeight", (id) => images[id]?.h || 0);

    // Print
    lua.global.set("print", (...a) => {
      output.push(a.map(x => String(x)).join("\t"));
    });

    // Scene system
    let currentScene = null;
    let scenePending = null;
    let sceneObj = null;
    const loadedScenes = {};

    // Build file map
    const fileMap = {};
    for (const f of files) fileMap[f.name] = f.content;

    async function activateScene(name) {
      if (!loadedScenes[name]) {
        const src = fileMap[name + ".lua"];
        if (src) {
          const result = await lua.doString(src);
          loadedScenes[name] = (result && typeof result === "object") ? result : true;
        } else {
          loadedScenes[name] = true;
        }
      }
      currentScene = name;
      const cached = loadedScenes[name];
      if (cached && typeof cached === "object") {
        sceneObj = cached;
        if (sceneObj.init) sceneObj.init();
      } else {
        sceneObj = null;
        const basename = name.includes("/") ? name.split("/").pop() : name;
        const initFn = lua.global.get(basename + "_init");
        if (initFn) initFn();
      }
    }

    lua.global.set("go", (name) => { scenePending = name; });
    lua.global.set("scene_name", () => currentScene || false);

    // Collision stubs
    lua.global.set("hitbox", () => {});
    lua.global.set("pollCollision", () => false);

    // Require support
    lua.global.set("require", (name) => {
      const src = fileMap[name + ".lua"] || fileMap[name];
      if (src) {
        // Synchronous doString for require
        return lua.doStringSync(src);
      }
      return null;
    });

    // --- Run game ---
    const mainFile = files.find(f => f.name === "main.lua");
    if (!mainFile) return { success: false, errors: ["No main.lua found"], output };

    await lua.doString(mainFile.content);

    // Lifecycle
    const initFn = lua.global.get("_init");
    if (initFn) initFn();

    const startFn = lua.global.get("_start");
    if (startFn) startFn();

    const readyFn = lua.global.get("_ready");
    if (readyFn) readyFn();

    // Activate pending scene
    if (scenePending) { await activateScene(scenePending); scenePending = null; }

    // Frame loop
    for (let i = 0; i < frames; i++) {
      if (scenePending) { await activateScene(scenePending); scenePending = null; }

      // Update
      if (sceneObj?.update) {
        sceneObj.update();
      } else {
        const updateFn = lua.global.get("_update");
        if (updateFn) updateFn();
        if (currentScene) {
          const basename = currentScene.includes("/") ? currentScene.split("/").pop() : currentScene;
          const sceneUpdate = lua.global.get(basename + "_update");
          if (sceneUpdate) sceneUpdate();
        }
      }

      // Draw
      if (sceneObj?.draw) {
        sceneObj.draw();
      } else {
        const drawFn = lua.global.get("_draw");
        if (drawFn) drawFn();
        if (currentScene) {
          const basename = currentScene.includes("/") ? currentScene.split("/").pop() : currentScene;
          const sceneDraw = lua.global.get(basename + "_draw");
          if (sceneDraw) sceneDraw();
        }
      }

      frameNum++;
    }

    lua.global.close();
    return { success: true, frames: frameNum, errors: [], output };

  } catch (e) {
    errors.push(e.message || String(e));
    return { success: false, errors, output };
  }
}
