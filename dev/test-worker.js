/**
 * Headless Mono test runner — Web Worker
 * Runs Lua game code without DOM/canvas in a separate thread.
 * Posts back { success, errors, frames, output }.
 */

importScripts("https://cdn.jsdelivr.net/npm/wasmoon@1.16.0/dist/index.js");

const W = 160, H = 120;

function buildPalette(bits) {
  const n = 1 << bits;
  const p = [];
  for (let i = 0; i < n; i++) p.push(Math.round(i * 255 / (n - 1)));
  return p;
}

onmessage = async (e) => {
  const { files, frames = 30, colors = 4 } = e.data;
  const errors = [];
  const output = [];
  let palette = buildPalette(colors);

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

    // Constants
    lua.global.set("SCREEN_W", W);
    lua.global.set("SCREEN_H", H);
    lua.global.set("COLORS", palette.length);
    lua.global.set("ALIGN_LEFT", 0);
    lua.global.set("ALIGN_HCENTER", 1);
    lua.global.set("ALIGN_RIGHT", 2);
    lua.global.set("ALIGN_VCENTER", 4);
    lua.global.set("ALIGN_CENTER", 5);

    // Drawing stubs
    lua.global.set("cls", (id, c) => { const s = getSurf(id); if (s) cls(s, c); });
    lua.global.set("pix", (id, x, y, c) => {
      const s = getSurf(id); if (!s) return;
      const px = Math.floor(x) - camX, py = Math.floor(y) - camY;
      if (px >= 0 && px < s.w && py >= 0 && py < s.h) s.buf[py * s.w + px] = c;
    });
    lua.global.set("gpix", (id, x, y) => {
      const s = getSurf(id); if (!s) return 0;
      if (x >= 0 && x < s.w && y >= 0 && y < s.h) return s.buf[y * s.w + x];
      return 0;
    });
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
      if (typeof k !== "string" || !validKeys[k])
        throw new Error('btn() invalid key "' + k + '". Valid: "up","down","left","right","a","b","start","select"');
      return 0;
    });
    lua.global.set("_btnp", (k) => {
      if (typeof k !== "string" || !validKeys[k])
        throw new Error('btnp() invalid key "' + k + '"');
      return 0;
    });
    lua.global.set("_btnr", (k) => {
      if (typeof k !== "string" || !validKeys[k])
        throw new Error('btnr() invalid key "' + k + '"');
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

    // Lua wrappers — mirror runtime/engine.js so scripts see the same API.
    await lua.doString(`
function btn(k)  return _btn(k) == 1 end
function btnp(k) return _btnp(k) == 1 end
function btnr(k) return _btnr(k) == 1 end
function touch() return _touch() == 1 end
function touch_start() return _touch_start() == 1 end
function touch_end()   return _touch_end() == 1 end
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

    // Print
    lua.global.set("print", (...a) => { output.push(a.map(x => String(x)).join("\t")); });

    // Collision stubs
    lua.global.set("hitbox", () => {});
    lua.global.set("pollCollision", () => false);

    // Scene system
    let currentScene = null;
    let scenePending = null;
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

    // --- Run ---
    const mainFile = files.find(f => f.name === "main.lua");
    if (!mainFile) { postMessage({ success: false, errors: ["No main.lua"], output }); return; }

    // Preload non-entry .lua files as require()-able modules — mirrors
    // runtime/engine.js so "require('lib.terrain')" works the same way
    // in the headless test as it does in the real engine.
    for (const f of files) {
      if (f.name === "main.lua" || !f.name.endsWith(".lua")) continue;
      const modName = f.name.replace(/\.lua$/, "").replace(/\//g, ".").replace(/"/g, "");
      lua.global.set("_tmp_mod_src", f.content);
      lua.global.set("_tmp_mod_name", modName);
      await lua.doString(`package.preload[_tmp_mod_name] = load(_tmp_mod_src, "@" .. _tmp_mod_name .. ".lua")`);
    }
    await lua.doString("_tmp_mod_src = nil; _tmp_mod_name = nil");

    await lua.doString(mainFile.content);

    const initFn = lua.global.get("_init");
    if (initFn) initFn();
    const startFn = lua.global.get("_start");
    if (startFn) startFn();
    const readyFn = lua.global.get("_ready");
    if (readyFn) readyFn();

    if (scenePending) { await activateScene(scenePending); scenePending = null; }

    for (let i = 0; i < frames; i++) {
      if (scenePending) { await activateScene(scenePending); scenePending = null; }

      if (sceneObj?.update) { sceneObj.update(); }
      else {
        const uf = lua.global.get("_update"); if (uf) uf();
        if (currentScene) {
          const bn = currentScene.includes("/") ? currentScene.split("/").pop() : currentScene;
          const sf = lua.global.get(bn + "_update"); if (sf) sf();
        }
      }

      if (sceneObj?.draw) { sceneObj.draw(); }
      else {
        const df = lua.global.get("_draw"); if (df) df();
        if (currentScene) {
          const bn = currentScene.includes("/") ? currentScene.split("/").pop() : currentScene;
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
