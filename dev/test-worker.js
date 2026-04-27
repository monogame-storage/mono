/**
 * Headless Mono test runner — Web Worker
 * Runs Lua game code without DOM/canvas in a separate thread.
 * Posts back { success, errors, frames, output }.
 *
 * Shared Lua API surface comes from /runtime/engine-bindings.js
 * (see MonoBindings.bind). Everything else — drawing, audio, timing,
 * scene activation — is stubbed or minimally implemented here.
 */

importScripts("https://cdn.jsdelivr.net/npm/wasmoon@1.16.0/dist/index.js");
importScripts("/runtime/engine-bindings.js");
importScripts("/runtime/engine-draw.js");

const W = 160, H = 120;

function buildPalette(bits) {
  const n = 1 << bits;
  const p = [];
  for (let i = 0; i < n; i++) p.push(Math.round(i * 255 / (n - 1)));
  return p;
}

onmessage = async (e) => {
  const { files, frames = 30, colors = 4, inputScript = null } = e.data;
  const errors = [];
  const output = [];
  let palette = buildPalette(colors);

  // Mutable input state driven by `inputScript` events. Mirrors the
  // browser engine's edge-detected fields (touchStart / touchEnd) and
  // the release-snapshot semantics (endedTouches while touchEnd is true),
  // so scripted taps exercise the same code paths as real user input.
  // inputScript = [{ frame: N, touchStart?: true, touchEnd?: true, touches?: [{x,y}] }, ...]
  const inputState = {
    touches: [],
    endedTouches: [],
    touchStarted: false,
    touchEnded: false,
  };

  const surfaces = {};
  let surfIdCounter = 1;
  surfaces[0] = { buf: new Uint8Array(W * H), w: W, h: H };
  function getSurf(id) { return surfaces[id] || null; }

  let camX = 0, camY = 0;
  const images = {};
  let imageIdCounter = 1;

  function cls(s, c) { s.buf.fill(c || 0); }

  try {
    const factory = new wasmoon.LuaFactory();
    const lua = await factory.createEngine();

    // Shared Lua API via MonoBindings — handles constants, input primitives
    // with validation, Lua wrappers (btn/btnp/btnr/touch/touch_*/cam_get),
    // package.preload, and go()/scene_name().
    const sceneRef = { current: null, pending: null };
    const modules = {};
    for (const f of files) {
      if (f.name === "main.lua" || !f.name.endsWith(".lua")) continue;
      modules[f.name] = f.content;
    }
    const posLookup = (i) => {
      const idx = (i || 1) - 1;
      return inputState.touches[idx]
          || (inputState.touchEnded ? inputState.endedTouches[idx] : null);
    };
    await self.MonoBindings.bind(lua, {
      input: {
        btn: () => false, btnp: () => false, btnr: () => false,
        touch:      () => inputState.touches.length > 0 || inputState.touchStarted,
        touchStart: () => inputState.touchStarted,
        touchEnd:   () => inputState.touchEnded,
        touchCount: () => inputState.touches.length || (inputState.touchEnded ? inputState.endedTouches.length : 0),
        touchPosX:  (i) => { const t = posLookup(i); return t ? t.x : false; },
        touchPosY:  (i) => { const t = posLookup(i); return t ? t.y : false; },
        touchPosfX: (i) => { const t = posLookup(i); return t ? t.x : false; },
        touchPosfY: (i) => { const t = posLookup(i); return t ? t.y : false; },
        swipe: () => false,
        axisX: () => 0, axisY: () => 0,
      },
      cam: { getX: () => camX, getY: () => camY },
      scene: sceneRef,
      modules,
    });

    // Non-shared environment: runtime-only constants + stubs for drawing,
    // audio, mode, frame/time, images, print, collision.

    lua.global.set("SCREEN_W", W);
    lua.global.set("SCREEN_H", H);
    lua.global.set("COLORS", palette.length);

    // Shared drawing algorithms via MonoDraw. setPix writes color indices
    // into surfaces[*].buf — the worker doesn't need buf32/RGBA because the
    // snapshot returned to the main thread is a color-index buffer the
    // caller turns into a PNG thumbnail.
    function setPix(s, x, y, c) {
      x = Math.floor(x); y = Math.floor(y);
      if (x >= 0 && x < s.w && y >= 0 && y < s.h) s.buf[y * s.w + x] = c;
    }
    const draw = self.MonoDraw.create({ setPix, getCam: () => [camX, camY] });

    lua.global.set("cls", (id, c) => { const s = getSurf(id); if (s) s.buf.fill(c || 0); });
    lua.global.set("pix", (id, x, y, c) => { const s = getSurf(id); if (s) setPix(s, Math.floor(x) - camX, Math.floor(y) - camY, c); });
    lua.global.set("gpix", (id, x, y) => {
      const s = getSurf(id); if (!s) return 0;
      x = Math.floor(x); y = Math.floor(y);
      if (x >= 0 && x < s.w && y >= 0 && y < s.h) return s.buf[y * s.w + x];
      return 0;
    });
    lua.global.set("line",  (id, x0, y0, x1, y1, c) => { const s = getSurf(id); if (s) draw.line(s, x0, y0, x1, y1, c); });
    lua.global.set("rect",  (id, x, y, w, h, c) => { const s = getSurf(id); if (s) draw.rect(s, x, y, w, h, c); });
    lua.global.set("rectf", (id, x, y, w, h, c) => { const s = getSurf(id); if (s) draw.rectf(s, x, y, w, h, c); });
    lua.global.set("circ",  (id, cx, cy, r, c) => { const s = getSurf(id); if (s) draw.circ(s, cx, cy, r, c); });
    lua.global.set("circf", (id, cx, cy, r, c) => { const s = getSurf(id); if (s) draw.circf(s, cx, cy, r, c); });
    lua.global.set("text",  (id, str, x, y, c, align) => { const s = getSurf(id); if (s) draw.drawText(s, str, x, y, c, align); });
    lua.global.set("spr", () => {});
    lua.global.set("sspr", () => {});
    lua.global.set("drawImage", () => {});
    lua.global.set("drawImageRegion", () => {});
    lua.global.set("vrow", () => "");
    lua.global.set("blit", () => {});

    // Camera setters
    lua.global.set("cam", (x, y) => { if (x !== undefined) { camX = x; camY = y || 0; } });
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

    // Frame / time
    let frameNum = 0;
    lua.global.set("frame", () => frameNum);
    lua.global.set("use_pause", () => {});
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

    // Images (stub)
    lua.global.set("loadImage", () => { const id = imageIdCounter++; images[id] = { w: 1, h: 1 }; return id; });
    lua.global.set("imageWidth", (id) => images[id]?.w || 0);
    lua.global.set("imageHeight", (id) => images[id]?.h || 0);

    // Motion / gyro sensors (stub — headless tests don't simulate tilt)
    lua.global.set("motion_x", () => 0);
    lua.global.set("motion_y", () => 0);
    lua.global.set("motion_z", () => 0);
    lua.global.set("gyro_alpha", () => 0);
    lua.global.set("gyro_beta", () => 0);
    lua.global.set("gyro_gamma", () => 0);
    lua.global.set("motion_enabled", () => 0);

    // Print
    lua.global.set("print", (...a) => { output.push(a.map(x => String(x)).join("\t")); });

    // Collision stubs
    lua.global.set("hitbox", () => {});
    lua.global.set("pollCollision", () => false);

    // Scene activation — bindings set sceneRef.pending via go(); we activate
    // after each frame in the loop below.
    let sceneObj = null;
    const loadedScenes = {};
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
      sceneRef.current = name;
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

    // --- Run ---
    const mainFile = files.find(f => f.name === "main.lua");
    if (!mainFile) { postMessage({ success: false, errors: ["No main.lua"], output }); return; }

    await lua.doString(mainFile.content);

    const initFn = lua.global.get("_init");
    if (initFn) initFn();
    const startFn = lua.global.get("_start");
    if (startFn) startFn();
    const readyFn = lua.global.get("_ready");
    if (readyFn) readyFn();

    if (sceneRef.pending) { await activateScene(sceneRef.pending); sceneRef.pending = null; }

    // Index inputScript by frame for O(1) lookup.
    const scriptByFrame = {};
    if (Array.isArray(inputScript)) {
      for (const ev of inputScript) {
        if (typeof ev?.frame === "number") scriptByFrame[ev.frame] = ev;
      }
    }

    for (let i = 0; i < frames; i++) {
      if (sceneRef.pending) { await activateScene(sceneRef.pending); sceneRef.pending = null; }

      // Clear last-frame edges before applying this frame's event. Mirrors
      // the browser engine's `if (touchEnded) endedTouches = []` reset.
      if (inputState.touchEnded) inputState.endedTouches = [];
      inputState.touchStarted = false;
      inputState.touchEnded = false;

      const ev = scriptByFrame[i];
      if (ev) {
        if (Array.isArray(ev.touches)) inputState.touches = ev.touches.map(t => ({ ...t }));
        if (ev.touchStart) inputState.touchStarted = true;
        if (ev.touchEnd) {
          inputState.touchEnded = true;
          // Snapshot current touches into endedTouches, then clear (same
          // timing as the browser onTouchEnd handler).
          inputState.endedTouches = inputState.touches.map(t => ({ ...t }));
          if (ev.touches === undefined) inputState.touches = [];
        }
      }

      if (sceneObj?.update) { sceneObj.update(); }
      else {
        const uf = lua.global.get("_update"); if (uf) uf();
        if (sceneRef.current) {
          const bn = sceneRef.current.includes("/") ? sceneRef.current.split("/").pop() : sceneRef.current;
          const sf = lua.global.get(bn + "_update"); if (sf) sf();
        }
      }

      if (sceneObj?.draw) { sceneObj.draw(); }
      else {
        const df = lua.global.get("_draw"); if (df) df();
        if (sceneRef.current) {
          const bn = sceneRef.current.includes("/") ? sceneRef.current.split("/").pop() : sceneRef.current;
          const sf = lua.global.get(bn + "_draw"); if (sf) sf();
        }
      }
      frameNum++;
    }

    lua.global.close();

    // Return screen buffer for thumbnail generation
    const screenBuf = surfaces[0]?.buf;
    const screenData = screenBuf ? { buf: Array.from(screenBuf), w: W, h: H, palette } : null;

    postMessage({ success: true, frames: frameNum, errors: [], output, screen: screenData });
  } catch (e) {
    errors.push(e.message || String(e));
    postMessage({ success: false, errors, output });
  }
};
