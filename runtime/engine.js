/**
 * Mono Runtime Engine v3.0 "Mono"
 *
 * Main-thread coordinator: canvas, input, audio, debug overlays.
 * Game logic + Luau VM run in a Web Worker (engine-worker.js).
 * 320x240, 4-color grayscale, 30fps, 2ch square wave.
 */
const Mono = (() => {
  "use strict";

  const W = 320;
  const H = 240;
  const FPS = 30;
  let SPR_SIZE = 16;
  const COLORS = ["#1a1a1a", "#6b6b6b", "#b0b0b0", "#e8e8e8"];

  let canvas, ctx, buf, buf32;

  function hexToABGR(hex) {
    const r = parseInt(hex.slice(1, 3), 16);
    const g = parseInt(hex.slice(3, 5), 16);
    const b = parseInt(hex.slice(5, 7), 16);
    return (255 << 24) | (b << 16) | (g << 8) | r;
  }
  const COLOR_U32 = COLORS.map(hexToABGR);

  const keyMap = {
    "ArrowUp": "up", "ArrowDown": "down", "ArrowLeft": "left", "ArrowRight": "right",
    "w": "up", "s": "down", "a": "left", "d": "right",
    "p": "up", ";": "down", "l": "left", "'": "right",
    "ㅈ": "up", "ㄴ": "down", "ㅁ": "left", "ㅇ": "right",
    "ㅔ": "up", "ㅂ": "left", "ㅎ": "down", "ㄹ": "right",
    "z": "a", "Z": "a", "x": "b", "X": "b", "ㅋ": "a", "ㅌ": "b",
    "Enter": "start", " ": "select"
  };
  const keys = {};
  let debugMode = false;
  let debugSprite = false;
  let debugFill = false;

  // Latest frame data from worker
  let latestFrame = null;

  // --- Audio ---
  let audioCtx = null;
  const channels = [null, null];
  const channelGains = [null, null];
  function ensureAudio() {
    if (!audioCtx) {
      audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      for (let i = 0; i < 2; i++) {
        channelGains[i] = audioCtx.createGain();
        channelGains[i].gain.value = 0.15;
        channelGains[i].connect(audioCtx.destination);
      }
    }
  }
  const NOTE_NAMES = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"];
  function noteToFreq(noteStr) {
    const match = noteStr.match(/^([A-G]#?)(\d)$/);
    if (!match) return 440;
    const name = match[1];
    const octave = parseInt(match[2]);
    const semitone = NOTE_NAMES.indexOf(name);
    if (semitone === -1) return 440;
    const midi = (octave + 1) * 12 + semitone;
    return 440 * Math.pow(2, (midi - 69) / 12);
  }

  function playNote(ch, noteStr, dur) {
    ensureAudio();
    if (ch < 0 || ch > 1) return;
    stopNote(ch);
    const osc = audioCtx.createOscillator();
    osc.type = "square";
    osc.frequency.value = noteToFreq(noteStr);
    osc.connect(channelGains[ch]);
    osc.start();
    osc.stop(audioCtx.currentTime + dur);
    channels[ch] = osc;
  }

  function stopNote(ch) {
    if (ch === undefined) { stopNote(0); stopNote(1); return; }
    if (channels[ch]) { try { channels[ch].stop(); } catch(e) {} channels[ch] = null; }
  }

  // --- BGM Sequencer (main thread, since it needs AudioContext) ---
  const bgmOsc = [null, null];
  const bgmGain = [null, null];
  let bgmData = null;
  let bgmPlaying = false;
  let bgmBeat = 0;
  let bgmTimer = 0;
  let bgmBPM = 120;
  let bgmLoop = true;

  function bgmEnsureChannels() {
    ensureAudio();
    for (let i = 0; i < 2; i++) {
      if (!bgmGain[i]) {
        bgmGain[i] = audioCtx.createGain();
        bgmGain[i].gain.value = 0.08;
        bgmGain[i].connect(audioCtx.destination);
      }
    }
  }

  function bgmNoteOn(ch, noteStr, dur) {
    if (ch < 0 || ch > 1) return;
    bgmNoteOff(ch);
    if (!noteStr || noteStr === "-" || noteStr === ".") return;
    const osc = audioCtx.createOscillator();
    osc.type = "square";
    osc.frequency.value = noteToFreq(noteStr);
    osc.connect(bgmGain[ch]);
    osc.start();
    osc.stop(audioCtx.currentTime + dur);
    bgmOsc[ch] = osc;
  }

  function bgmNoteOff(ch) {
    if (bgmOsc[ch]) { try { bgmOsc[ch].stop(); } catch(e) {} bgmOsc[ch] = null; }
  }

  function bgmNoteDuration(track, beatIdx) {
    var count = 1;
    for (var i = beatIdx + 1; i < track.length; i++) {
      if (track[i] === "-") count++;
      else break;
    }
    return count;
  }

  function bgmTick() {
    if (!bgmPlaying || !bgmData) return;
    bgmTimer--;
    if (bgmTimer > 0) return;

    const beatDur = 60 / bgmBPM;
    const framesPerBeat = Math.round((60 / bgmBPM) * FPS);

    for (let t = 0; t < bgmData.tracks.length && t < 2; t++) {
      const track = bgmData.tracks[t];
      if (bgmBeat < track.length) {
        const entry = track[bgmBeat];
        if (entry === ".") {
          bgmNoteOff(t);
        } else if (entry === "-") {
          // sustain
        } else if (entry) {
          var beats = bgmNoteDuration(track, bgmBeat);
          bgmNoteOn(t, entry, beatDur * beats);
        }
      }
    }

    bgmBeat++;
    bgmTimer = framesPerBeat;

    const maxLen = Math.max(...bgmData.tracks.map(t => t.length));
    if (bgmBeat >= maxLen) {
      if (bgmLoop) {
        bgmBeat = 0;
      } else {
        bgmPlaying = false;
      }
    }
  }

  function parseTrack(str) {
    return str.split(/\s+/).filter(s => s !== "|" && s !== "");
  }

  function startBgm(tracks, bpm, loop) {
    bgmEnsureChannels();
    bgmData = { tracks: tracks.map(parseTrack) };
    bgmBPM = bpm || 120;
    bgmLoop = loop !== false;
    bgmBeat = 0;
    bgmTimer = 1;
    bgmPlaying = true;
  }

  function stopBgm() {
    bgmPlaying = false;
    bgmNoteOff(0);
    bgmNoteOff(1);
    bgmBeat = 0;
  }

  // --- Font (for debug overlays on main thread) ---
  const FONT_W = 4;
  const FONT_H = 7;
  const FONT = {};
  const fontData = {
    "A":"0110100110011111100110011001","B":"1110100110101110100110011110",
    "C":"0110100110001000100001100110","D":"1100101010011001100110101100",
    "E":"1111100010001110100010001111","F":"1111100010001110100010001000",
    "G":"0111100010001011100101100111","H":"1001100110011111100110011001",
    "I":"1110010001000100010001001110","J":"0111001000100010001010100100",
    "K":"1001101011001100101010011001","L":"1000100010001000100010001111",
    "M":"1001111111011001100110011001","N":"1001110111011001100110011001",
    "O":"0110100110011001100110010110","P":"1110100110011110100010001000",
    "Q":"0110100110011001101101100001","R":"1110100110011110101010011001",
    "S":"0111100010000110000110001110","T":"1111001000100010001000100010",
    "U":"1001100110011001100110010110","V":"1001100110011001100101100110",
    "W":"1001100110011001101111011001","X":"1001100101100110011010011001",
    "Y":"1001100101100010001000100010","Z":"1111000100100100100010001111",
    "0":"0110100111011011101110010110","1":"0100110001000100010001001110",
    "2":"0110100100010010010010001111","3":"1110000100010110000110011110",
    "4":"1001100110011111000100010001","5":"1111100010001110000100011110",
    "6":"0110100010001110100110010110","7":"1111000100010010010001001000",
    "8":"0110100110010110100110010110","9":"0110100110010111000100010110",
  };
  for (const [ch, bits] of Object.entries(fontData)) {
    FONT[ch] = [];
    for (let i = 0; i < bits.length; i++) FONT[ch].push(parseInt(bits[i]));
  }

  // --- Debug overlays (drawn on main thread into buf32 after receiving frame) ---
  function drawDebugLabel(str, x, col) {
    let cx = x;
    for (const ch of str) {
      const glyph = FONT[ch];
      if (glyph) for (let py = 0; py < FONT_H; py++) for (let px = 0; px < FONT_W; px++)
        if (glyph[py * FONT_W + px]) {
          const sx = cx + px, sy = H - FONT_H - 2 + py;
          if (sx >= 0 && sx < W && sy >= 0 && sy < H) buf32[sy * W + sx] = col;
        }
      cx += FONT_W + 1;
    }
    return cx;
  }

  function drawDebugOverlays(dShapes, dSprBoxes, dFillBoxes) {
    let labelX = 2;

    // --- Collision overlay (key 1) ---
    if (debugMode && dShapes && dShapes.length > 0) {
      const dcol = 0xFF00FF00;
      for (const s of dShapes) {
        if (s.t === "r") {
          for (let px = s.x; px < s.x + s.w; px++) {
            if (px >= 0 && px < W) {
              if (s.y >= 0 && s.y < H) buf32[s.y * W + px] = dcol;
              const by = s.y + s.h - 1;
              if (by >= 0 && by < H) buf32[by * W + px] = dcol;
            }
          }
          for (let py = s.y; py < s.y + s.h; py++) {
            if (py >= 0 && py < H) {
              if (s.x >= 0 && s.x < W) buf32[py * W + s.x] = dcol;
              const bx = s.x + s.w - 1;
              if (bx >= 0 && bx < W) buf32[py * W + bx] = dcol;
            }
          }
        } else if (s.t === "c") {
          let cx = s.r, cy = 0, d = 1 - s.r;
          while (cx >= cy) {
            const pts = [
              [s.x+cx,s.y+cy],[s.x-cx,s.y+cy],[s.x+cx,s.y-cy],[s.x-cx,s.y-cy],
              [s.x+cy,s.y+cx],[s.x-cy,s.y+cx],[s.x+cy,s.y-cx],[s.x-cy,s.y-cx]
            ];
            for (const [px,py] of pts)
              if (px >= 0 && px < W && py >= 0 && py < H) buf32[py * W + px] = dcol;
            cy++;
            if (d < 0) { d += 2 * cy + 1; } else { cx--; d += 2 * (cy - cx) + 1; }
          }
        } else if (s.t === "p") {
          for (let d = -2; d <= 2; d++) {
            if (s.x+d >= 0 && s.x+d < W && s.y >= 0 && s.y < H) buf32[s.y * W + (s.x+d)] = dcol;
            if (s.x >= 0 && s.x < W && s.y+d >= 0 && s.y+d < H) buf32[(s.y+d) * W + s.x] = dcol;
          }
        }
      }
      labelX = drawDebugLabel("1:HITBOX", labelX, dcol) + 6;
    }

    // --- Sprite bounding box overlay (key 2) ---
    if (debugSprite && dSprBoxes && dSprBoxes.length > 0) {
      const scol = 0xFFFF00FF;
      for (const s of dSprBoxes) {
        const ss = SPR_SIZE;
        for (let px = s.x; px < s.x + ss; px++) {
          if (px >= 0 && px < W) {
            if (s.y >= 0 && s.y < H) buf32[s.y * W + px] = scol;
            const by = s.y + ss - 1;
            if (by >= 0 && by < H) buf32[by * W + px] = scol;
          }
        }
        for (let py = s.y; py < s.y + ss; py++) {
          if (py >= 0 && py < H) {
            if (s.x >= 0 && s.x < W) buf32[py * W + s.x] = scol;
            const bx = s.x + ss - 1;
            if (bx >= 0 && bx < W) buf32[py * W + bx] = scol;
          }
        }
      }
      labelX = drawDebugLabel("2:SPRITE", labelX, scol) + 6;
    }

    // --- Fill overlay (key 3) ---
    if (debugFill && dFillBoxes && dFillBoxes.length > 0) {
      const fcol = 0xFFFF8800;
      for (const s of dFillBoxes) {
        if (s.t === "r") {
          for (let px = s.x; px < s.x + s.w; px++) {
            if (px >= 0 && px < W) {
              if (s.y >= 0 && s.y < H) buf32[s.y * W + px] = fcol;
              const by = s.y + s.h - 1;
              if (by >= 0 && by < H) buf32[by * W + px] = fcol;
            }
          }
          for (let py = s.y; py < s.y + s.h; py++) {
            if (py >= 0 && py < H) {
              if (s.x >= 0 && s.x < W) buf32[py * W + s.x] = fcol;
              const bx = s.x + s.w - 1;
              if (bx >= 0 && bx < W) buf32[py * W + bx] = fcol;
            }
          }
        } else if (s.t === "c") {
          let cx = s.r, cy = 0, d = 1 - s.r;
          while (cx >= cy) {
            const pts = [
              [s.x+cx,s.y+cy],[s.x-cx,s.y+cy],[s.x+cx,s.y-cy],[s.x-cx,s.y-cy],
              [s.x+cy,s.y+cx],[s.x-cy,s.y+cx],[s.x+cy,s.y-cx],[s.x-cy,s.y-cx]
            ];
            for (const [px,py] of pts)
              if (px >= 0 && px < W && py >= 0 && py < H) buf32[py * W + px] = fcol;
            cy++;
            if (d < 0) { d += 2 * cy + 1; } else { cx--; d += 2 * (cy - cx) + 1; }
          }
        }
      }
      labelX = drawDebugLabel("3:FILL", labelX, fcol) + 6;
    }
  }

  // --- Worker ---
  let worker = null;
  let currentFrame = 0;
  let gameId = "";

  // BGM tick interval (runs at ~30fps to match game timing)
  let bgmTickInterval = null;

  // --- Public API ---
  const API = {};
  API.frame = 0;
  API.speed = 1;
  API.WIDTH = W;
  API.HEIGHT = H;
  API.COLORS = COLORS;

  API.boot = async function(canvasId, opts) {
    if (opts && opts.spriteSize) SPR_SIZE = opts.spriteSize;
    canvas = document.getElementById(canvasId || "screen");
    canvas.width = W;
    canvas.height = H;

    function fitCanvas() {
      var maxW = window.innerWidth - 40;
      var maxH = window.innerHeight - 60;
      var s = Math.min(maxW / W, maxH / H);
      canvas.style.width = (W * s) + "px";
      canvas.style.height = (H * s) + "px";
    }
    fitCanvas();
    window.addEventListener("resize", fitCanvas);

    ctx = canvas.getContext("2d");
    ctx.imageSmoothingEnabled = false;
    buf = ctx.createImageData(W, H);
    buf32 = new Uint32Array(buf.data.buffer);

    // Derive gameId from URL path
    const pathParts = window.location.pathname.split("/").filter(Boolean);
    gameId = pathParts[pathParts.length - 2] || pathParts[pathParts.length - 1] || "unknown";

    // --- Input handling ---
    document.addEventListener("keydown", e => {
      // Debug toggles (main-thread only, forwarded to worker)
      if (e.key === "1") {
        debugMode = !debugMode;
        if (worker) worker.postMessage({ type: "debug", key: "debugMode", value: debugMode });
        e.preventDefault(); return;
      }
      if (e.key === "2") {
        debugSprite = !debugSprite;
        if (worker) worker.postMessage({ type: "debug", key: "debugSprite", value: debugSprite });
        e.preventDefault(); return;
      }
      if (e.key === "3") {
        debugFill = !debugFill;
        if (worker) worker.postMessage({ type: "debug", key: "debugFill", value: debugFill });
        e.preventDefault(); return;
      }
      const k = keyMap[e.key];
      if (k) {
        keys[k] = true;
        if (worker) worker.postMessage({ type: "input", keys: Object.assign({}, keys) });
        e.preventDefault();
      }
    });
    document.addEventListener("keyup", e => {
      const k = keyMap[e.key];
      if (k) {
        keys[k] = false;
        if (worker) worker.postMessage({ type: "input", keys: Object.assign({}, keys) });
        e.preventDefault();
      }
    });
    document.addEventListener("keydown", ensureAudio, { once: true });
    document.addEventListener("click", ensureAudio, { once: true });

    // postMessage IPC (from parent iframe — demo controls)
    window.addEventListener("message", (e) => {
      if (e.data && e.data.type === "mono") {
        switch(e.data.cmd) {
          case "rec":
            if (worker) worker.postMessage({ type: "demo", cmd: "rec" });
            break;
          case "play": {
            // Load demo from localStorage and send to worker
            const savedDemo = loadDemoFromStorage();
            if (worker && savedDemo) worker.postMessage({ type: "demo", cmd: "play", savedDemo });
            break;
          }
          case "stop":
            if (worker) worker.postMessage({ type: "demo", cmd: "stop" });
            break;
          case "save":
            if (worker) worker.postMessage({ type: "demo", cmd: "save" });
            break;
        }
      }
    });

    // --- Create Worker & boot game ---
    if (opts && opts.game) {
      // Resolve engine.js base path for locating worker + luau-web
      const scripts = document.getElementsByTagName('script');
      let engineBase = '';
      for (const s of scripts) {
        if (s.src && s.src.includes('engine.js')) {
          engineBase = s.src.substring(0, s.src.lastIndexOf('/') + 1);
          break;
        }
      }
      // If engineBase is empty (e.g. relative script tag), compute from location
      if (!engineBase) {
        engineBase = window.location.href.substring(0, window.location.href.lastIndexOf('/') + 1) + '../../runtime/';
      }

      const workerUrl = engineBase + 'engine-worker.js';
      const luauWebUrl = engineBase + 'luau-web/luau-web.js';

      // Fetch the game source on main thread (Workers can't fetch relative URLs easily)
      const gameSrc = await fetch(opts.game).then(r => r.text());

      // Create the worker as module type (for dynamic import inside)
      worker = new Worker(workerUrl, { type: "module" });

      // Handle messages from worker
      worker.onmessage = (e) => {
        const msg = e.data;
        if (!msg || !msg.type) return;

        switch (msg.type) {
          case "frame": {
            // Blit frame buffer
            buf32.set(new Uint32Array(msg.buffer));
            currentFrame = msg.frame;
            API.frame = msg.frame;

            // Draw debug overlays on main thread
            drawDebugOverlays(msg.debugShapes, msg.debugSprBoxes, msg.debugFillBoxes);

            ctx.putImageData(buf, 0, 0);
            break;
          }

          case "audio": {
            handleAudioCommand(msg);
            break;
          }

          case "scene": {
            // Scene changed in worker — we might want to track it
            break;
          }

          case "demo": {
            // Forward demo state to parent
            if (window.parent !== window) {
              window.parent.postMessage({ type: "mono", event: "state", state: msg.state }, "*");
            }
            break;
          }

          case "parentNotify": {
            // Forward to parent iframe
            if (window.parent !== window) {
              window.parent.postMessage({ type: "mono", event: msg.event, state: msg.state }, "*");
            }
            break;
          }

          case "demoSave": {
            // Worker wants to save demo data to localStorage
            try {
              localStorage.setItem(msg.key, msg.data);
            } catch(e) {}
            break;
          }

          case "log": {
            console.log("[Worker]", msg.msg);
            break;
          }

          case "ready": {
            // Worker is initialized and game loop started
            // Start BGM tick on main thread
            bgmTickInterval = setInterval(bgmTick, 1000 / FPS);
            break;
          }
        }
      };

      worker.onerror = (e) => {
        console.error("Mono Worker error:", e);
      };

      // Boot the worker
      worker.postMessage({
        type: "boot",
        game: opts.game,
        gameSrc: gameSrc,
        luauWebUrl: luauWebUrl,
        spriteSize: SPR_SIZE,
        gameId: gameId,
      });
    }
  };

  function handleAudioCommand(msg) {
    switch (msg.cmd) {
      case "note":
        playNote(msg.ch, msg.note, msg.dur);
        break;
      case "noteStop":
        stopNote(msg.ch);
        break;
      case "bgm":
        startBgm(msg.tracks, msg.bpm, msg.loop);
        break;
      case "bgmStop":
        stopBgm();
        break;
      case "bgmVol":
        bgmEnsureChannels();
        for (let i = 0; i < 2; i++) bgmGain[i].gain.value = Math.max(0, Math.min(1, msg.vol));
        break;
    }
  }

  function loadDemoFromStorage() {
    try {
      const raw = localStorage.getItem("mono_demo_" + gameId);
      if (!raw) return null;
      const data = JSON.parse(raw);
      if (data.actions) return data;
      return { seed: 1, actions: data };
    } catch(e) {}
    return null;
  }

  // Low-level access (retained for compatibility)
  API._COLOR_U32 = COLOR_U32;
  Object.defineProperty(API, '_buf32', { get() { return buf32; } });
  Object.defineProperty(API, 'spriteSize', { get() { return SPR_SIZE; } });

  return API;
})();
