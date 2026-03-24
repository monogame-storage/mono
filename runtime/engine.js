/**
 * Mono Runtime Engine v1.0 "Mono"
 *
 * 320×240, 4-color grayscale, 30fps, 2ch square wave
 * Standalone runtime — no game code included.
 *
 * Usage:
 *   <script src="runtime/engine.js"></script>
 *   <script>
 *     const { cls, spr, text, btn, ... } = Mono;
 *     Mono._update = function() { ... };
 *     Mono._draw = function() { ... };
 *     Mono.boot("screen");
 *   </script>
 */
const Mono = (() => {
  "use strict";

  const W = 320;
  const H = 240;
  const FPS = 30;
  const COLORS = ["#1a1a1a", "#6b6b6b", "#b0b0b0", "#e8e8e8"];

  let canvas, ctx, buf, buf32;

  function hexToABGR(hex) {
    const r = parseInt(hex.slice(1, 3), 16);
    const g = parseInt(hex.slice(3, 5), 16);
    const b = parseInt(hex.slice(5, 7), 16);
    return (255 << 24) | (b << 16) | (g << 8) | r;
  }
  const COLOR_U32 = COLORS.map(hexToABGR);

  const sprites = {};
  const tilemap = {};

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
  const keysPrev = {};
  let paused = false;
  let debugMode = false;   // 1: collision shapes
  let debugSprite = false;  // 2: sprite bounding boxes
  let debugFill = false;    // 3: rectf/circf bounding boxes
  const debugShapes = [];
  const debugSprBoxes = [];
  const debugFillBoxes = [];

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

  // --- Font (4×7 bitmap) ---
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
    " ":"0000000000000000000000000000",
    ".":"0000000000000000000001000100",
    ",":"0000000000000000001000101000",
    "!":"0100010001000100000000000100",
    "?":"0110100100010010000000000010",
    "-":"0000000000001110000000000000",
    "+":"0000001001001110010000100000",
    ":":"0000010001000000010001000000",
    "/":"0001000100100010010010001000",
    "*":"0000101001001110010010100000",
    "#":"0101111101011111010100000000",
    "(":"0010010010001000010001000010",
    ")":"0100001000010001000100100100",
    "=":"0000000011110000111100000000",
    "'":"0100010010000000000000000000",
    "\"":"1010101000000000000000000000",
    "<":"0010010010001000010000100010",
    ">":"1000010000100001001001001000",
    "_":"0000000000000000000000001111",
  };
  for (const [ch, bits] of Object.entries(fontData)) {
    FONT[ch] = [];
    for (let i = 0; i < bits.length; i++) FONT[ch].push(parseInt(bits[i]));
  }

  // --- API ---
  const API = {};
  API.frame = 0;
  API.WIDTH = W;
  API.HEIGHT = H;
  API.COLORS = COLORS;

  // --- Scene system ---
  const VALID_SCENES = ["title","play","clear","gameover","win"];
  const scenes = {};
  let currentScene = null;
  let currentSceneName = "";

  API.SCENE = { TITLE:"title", PLAY:"play", CLEAR:"clear", GAMEOVER:"gameover", WIN:"win" };

  API.scene = function(name, handlers) {
    if (VALID_SCENES.indexOf(name) === -1) {
      throw new Error('Mono: "' + name + '" is not a valid scene. Use: ' + VALID_SCENES.join("/"));
    }
    scenes[name] = handlers;
  };

  API.go = function(name) {
    if (VALID_SCENES.indexOf(name) === -1) {
      throw new Error('Mono: "' + name + '" is not a valid scene. Use: ' + VALID_SCENES.join("/"));
    }
    // Attract mode hooks
    if (name === "play" && demoState !== "playback") {
      // Start recording when entering play
      demoState = "recording";
      demoRecording = [];
      demoRecFrame = 0;
      demoLastBits = 0;
      demoRecSeed = _seed;
    }
    if ((name === "gameover" || name === "win") && demoState === "recording") {
      // Stop recording & save when leaving play
      demoRecording.push([demoRecFrame, 0]);
      saveDemoToStorage();
      demoState = "idle";
      demoIdleFrames = 0;
    }
    // Auto-stop BGM on scene change (game can restart it in init)
    if (bgmPlaying) API.bgmStop();
    paused = false;
    currentSceneName = name;
    currentScene = scenes[name] || null;
    if (currentScene && currentScene.init) currentScene.init();
  };

  API.currentScene = function() { return currentSceneName; };
  API.paused = function() { return paused; };

  // Legacy support: _update/_draw still work for simple games
  API._init = null;
  API._update = null;
  API._draw = null;

  // Graphics
  API.cls = function(c) { buf32.fill(COLOR_U32[c || 0]); };
  API.pix = function(x, y, c) {
    x = Math.floor(x); y = Math.floor(y);
    if (x < 0 || x >= W || y < 0 || y >= H) return;
    buf32[y * W + x] = COLOR_U32[c] || COLOR_U32[0];
  };
  API.line = function(x0, y0, x1, y1, c) {
    x0=Math.floor(x0); y0=Math.floor(y0); x1=Math.floor(x1); y1=Math.floor(y1);
    const dx=Math.abs(x1-x0), dy=Math.abs(y1-y0);
    const sx=x0<x1?1:-1, sy=y0<y1?1:-1;
    let err=dx-dy;
    while(true) {
      API.pix(x0,y0,c);
      if(x0===x1&&y0===y1) break;
      const e2=2*err;
      if(e2>-dy){err-=dy;x0+=sx;}
      if(e2<dx){err+=dx;y0+=sy;}
    }
  };
  API.rect = function(x,y,w,h,c) {
    API.line(x,y,x+w-1,y,c); API.line(x+w-1,y,x+w-1,y+h-1,c);
    API.line(x+w-1,y+h-1,x,y+h-1,c); API.line(x,y+h-1,x,y,c);
  };
  API.rectf = function(x,y,w,h,c) {
    x=Math.floor(x); y=Math.floor(y);
    const col=COLOR_U32[c]||COLOR_U32[0];
    for(let py=Math.max(0,y);py<Math.min(H,y+h);py++)
      for(let px=Math.max(0,x);px<Math.min(W,x+w);px++)
        buf32[py*W+px]=col;
    if(debugFill) debugFillBoxes.push({t:"r",x:x,y:y,w:w,h:h});
  };
  API.circ = function(cx,cy,r,c) {
    let x=r,y=0,d=1-r; cx=Math.floor(cx); cy=Math.floor(cy);
    while(x>=y){
      API.pix(cx+x,cy+y,c);API.pix(cx-x,cy+y,c);
      API.pix(cx+x,cy-y,c);API.pix(cx-x,cy-y,c);
      API.pix(cx+y,cy+x,c);API.pix(cx-y,cy+x,c);
      API.pix(cx+y,cy-x,c);API.pix(cx-y,cy-x,c);
      y++; if(d<0){d+=2*y+1;}else{x--;d+=2*(y-x)+1;}
    }
  };
  API.circf = function(cx,cy,r,c) {
    cx=Math.floor(cx); cy=Math.floor(cy);
    const col=COLOR_U32[c]||COLOR_U32[0]; const r2=r*r;
    for(let py=-r;py<=r;py++) for(let px=-r;px<=r;px++)
      if(px*px+py*py<=r2){ const sx=cx+px,sy=cy+py;
        if(sx>=0&&sx<W&&sy>=0&&sy<H) buf32[sy*W+sx]=col; }
    if(debugFill) debugFillBoxes.push({t:"c",x:cx,y:cy,r:r});
  };

  // Sprites
  API.sprite = function(id, data) {
    const arr = new Uint8Array(256); let i = 0;
    for (const ch of data) { if (ch>='0'&&ch<='3') { arr[i++]=parseInt(ch); if(i>=256) break; } }
    sprites[id] = arr;
  };
  API.spr = function(id, x, y, flipX, flipY) {
    const s=sprites[id]; if(!s) return;
    x=Math.floor(x); y=Math.floor(y);
    for(let py=0;py<16;py++) for(let px=0;px<16;px++){
      const sx=flipX?15-px:px, sy=flipY?15-py:py;
      const c=s[sy*16+sx], dx=x+px, dy=y+py;
      if(dx>=0&&dx<W&&dy>=0&&dy<H) buf32[dy*W+dx]=COLOR_U32[c];
    }
    if(debugSprite) debugSprBoxes.push({x:x,y:y});
  };
  // Transparent sprite (color 0 = skip)
  API.sprT = function(id, x, y, flipX, flipY) {
    const s=sprites[id]; if(!s) return;
    x=Math.floor(x); y=Math.floor(y);
    for(let py=0;py<16;py++) for(let px=0;px<16;px++){
      const sx=flipX?15-px:px, sy=flipY?15-py:py;
      const c=s[sy*16+sx]; if(c===0) continue;
      const dx=x+px, dy=y+py;
      if(dx>=0&&dx<W&&dy>=0&&dy<H) buf32[dy*W+dx]=COLOR_U32[c];
    }
    if(debugSprite) debugSprBoxes.push({x:x,y:y});
  };
  // Rotated sprite (draws 16x16 sprite rotated by angle in radians)
  API.sprRot = function(id, cx, cy, angle) {
    const s = sprites[id]; if (!s) return;
    const cosA = Math.cos(angle), sinA = Math.sin(angle);
    for (let py = -10; py <= 10; py++) {
      for (let px = -10; px <= 10; px++) {
        const srcX = Math.floor(cosA * px + sinA * py + 7.5);
        const srcY = Math.floor(-sinA * px + cosA * py + 7.5);
        if (srcX < 0 || srcX >= 16 || srcY < 0 || srcY >= 16) continue;
        const c = s[srcY * 16 + srcX];
        const dx = Math.floor(cx + px), dy = Math.floor(cy + py);
        if (dx >= 0 && dx < W && dy >= 0 && dy < H) buf32[dy * W + dx] = COLOR_U32[c];
      }
    }
    if(debugSprite) debugSprBoxes.push({x:Math.floor(cx)-8,y:Math.floor(cy)-8});
  };
  // Read pixel color index from buffer
  API.gpix = function(x, y) {
    x = Math.floor(x); y = Math.floor(y);
    if (x < 0 || x >= W || y < 0 || y >= H) return -1;
    const v = buf32[y * W + x];
    for (let i = 0; i < 4; i++) if (COLOR_U32[i] === v) return i;
    return -1;
  };

  // Text
  API.text = function(str, x, y, c) {
    str=String(str).toUpperCase(); let cx=Math.floor(x); const cy=Math.floor(y);
    const col=COLOR_U32[c]||COLOR_U32[3];
    for(const ch of str){
      const glyph=FONT[ch];
      if(glyph) for(let py=0;py<FONT_H;py++) for(let px=0;px<FONT_W;px++)
        if(glyph[py*FONT_W+px]){ const dx=cx+px,dy=cy+py;
          if(dx>=0&&dx<W&&dy>=0&&dy<H) buf32[dy*W+dx]=col; }
      cx+=FONT_W+1;
    }
  };

  // Tilemap
  API.mget = function(cx,cy) { return tilemap[cx+","+cy]||0; };
  API.mset = function(cx,cy,id) { tilemap[cx+","+cy]=id; };
  API.map = function(mx,my,mw,mh,sx,sy) {
    for(let ty=0;ty<mh;ty++) for(let tx=0;tx<mw;tx++){
      const id=API.mget(mx+tx,my+ty); if(id>0) API.spr(id,sx+tx*16,sy+ty*16); }
  };

  // Input
  const VALID_KEYS = {up:1,down:1,left:1,right:1,a:1,b:1,start:1,select:1};
  API.btn = function(k) {
    if(!VALID_KEYS[k]) console.warn("Mono: invalid key \""+k+"\". Use: up/down/left/right/a/b/start/select");
    return !!keys[k];
  };
  API.btnp = function(k) {
    if(!VALID_KEYS[k]) console.warn("Mono: invalid key \""+k+"\". Use: up/down/left/right/a/b/start/select");
    return !!keys[k] && !keysPrev[k];
  };

  // Debug overlay
  API.dbg = function(x, y, w, h) {
    if (debugMode) debugShapes.push({ t: "r", x: Math.floor(x), y: Math.floor(y), w: Math.floor(w), h: Math.floor(h) });
  };
  API.dbgC = function(x, y, r) {
    if (debugMode) debugShapes.push({ t: "c", x: Math.floor(x), y: Math.floor(y), r: Math.floor(r) });
  };
  API.dbgPt = function(x, y) {
    if (debugMode) debugShapes.push({ t: "p", x: Math.floor(x), y: Math.floor(y) });
  };

  // Sound
  API.note = function(ch, noteStr, dur) {
    ensureAudio(); if(ch<0||ch>1) return; API.stop(ch);
    const osc=audioCtx.createOscillator(); osc.type="square";
    osc.frequency.value=noteToFreq(noteStr);
    osc.connect(channelGains[ch]); osc.start();
    osc.stop(audioCtx.currentTime+dur); channels[ch]=osc;
  };
  API.stop = function(ch) {
    if(ch===undefined){API.stop(0);API.stop(1);return;}
    if(channels[ch]){try{channels[ch].stop();}catch(e){} channels[ch]=null;}
  };

  // --- BGM Sequencer (2 dedicated channels: melody + bass) ---
  const bgmOsc = [null, null];
  const bgmGain = [null, null];
  let bgmData = null;       // { tracks: [[note,dur], ...], bpm, loop }
  let bgmPlaying = false;
  let bgmBeat = 0;          // current beat index
  let bgmTimer = 0;         // frames until next beat
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

  // Count how many beats a note sustains (including following "-" ties)
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

    const beatDur = 60 / bgmBPM; // seconds per beat
    const framesPerBeat = Math.round((60 / bgmBPM) * FPS);

    // Play each track's current note
    for (let t = 0; t < bgmData.tracks.length && t < 2; t++) {
      const track = bgmData.tracks[t];
      if (bgmBeat < track.length) {
        const entry = track[bgmBeat];
        if (entry === ".") {
          // Explicit rest: silence this channel
          bgmNoteOff(t);
        } else if (entry === "-") {
          // Sustain: do nothing, let previous note ring
        } else if (entry) {
          // New note: calculate duration including tied beats
          var beats = bgmNoteDuration(track, bgmBeat);
          bgmNoteOn(t, entry, beatDur * beats);
        }
      }
    }

    bgmBeat++;
    bgmTimer = framesPerBeat;

    // Check if all tracks finished
    const maxLen = Math.max(...bgmData.tracks.map(t => t.length));
    if (bgmBeat >= maxLen) {
      if (bgmLoop) {
        bgmBeat = 0;
      } else {
        bgmPlaying = false;
      }
    }
  }

  // Parse track string: "C4 E4 G4 - C5 | D4 F4 A4 . D5"
  // Notes separated by spaces, "|" = bar line (visual only, ignored)
  // "-" = sustain (hold previous note), "." = rest (silence)
  function parseTrack(str) {
    return str.split(/\s+/).filter(s => s !== "|" && s !== "");
  }

  /**
   * Play background music.
   * @param {string[]} tracks - Array of 1-2 track strings (melody, bass)
   *   Each track: space-separated notes like "C4 E4 G4 - C5"
   *   "-" = rest (silence), "|" = bar line (visual only, ignored)
   * @param {number} bpm - Beats per minute (default 120)
   * @param {boolean} loop - Loop when finished (default true)
   */
  API.bgm = function(tracks, bpm, loop) {
    bgmEnsureChannels();
    bgmData = { tracks: tracks.map(parseTrack) };
    bgmBPM = bpm || 120;
    bgmLoop = loop !== false;
    bgmBeat = 0;
    bgmTimer = 1; // start on next tick
    bgmPlaying = true;
  };

  API.bgmStop = function() {
    bgmPlaying = false;
    bgmNoteOff(0);
    bgmNoteOff(1);
    bgmBeat = 0;
  };

  API.bgmVol = function(vol) {
    bgmEnsureChannels();
    for (let i = 0; i < 2; i++) bgmGain[i].gain.value = Math.max(0, Math.min(1, vol));
  };

  // Seeded PRNG (Lehmer / Park-Miller)
  let _seed = (Date.now() & 0x7FFFFFFF) || 1;
  function _nextRand() {
    _seed = (_seed * 16807) % 2147483647;
    return (_seed - 1) / 2147483646;
  }

  // Utilities
  API.rnd = function(max) { return _nextRand() * max; };
  API.seed = function(s) { _seed = (s & 0x7FFFFFFF) || 1; };
  API.getSeed = function() { return _seed; };
  API.flr = Math.floor;
  API.abs = Math.abs;
  API.min = Math.min;
  API.max = Math.max;
  API.sin = Math.sin;
  API.cos = Math.cos;
  API.atan2 = Math.atan2;
  API.sqrt = Math.sqrt;
  API.PI = Math.PI;

  // Collision helper (AABB overlap)
  API.overlap = function(x1,y1,w1,h1, x2,y2,w2,h2) {
    return x1+w1>x2 && x1<x2+w2 && y1+h1>y2 && y1<y2+h2;
  };

  // --- Attract Mode (action-based input recording & playback) ---
  // Format: [[frame, bitmask], ...] — only stores when key state changes
  // 6 keys packed as bitmask: up=1 down=2 left=4 right=8 a=16 b=32
  const KEY_BITS = ["up","down","left","right","a","b"];
  let demoState = "idle";       // idle | recording | playback
  let demoRecording = [];       // [[frame, bits], ...] action-based
  let demoRecFrame = 0;         // frame counter during recording
  let demoLastBits = 0;         // last recorded bitmask
  let demoPlaybackData = null;  // loaded recording for playback
  let demoPlayIdx = 0;          // current index in playback data
  let demoPlayFrame = 0;        // frame counter during playback
  let demoPlayBits = 0;         // current key state during playback
  let demoIdleFrames = 0;       // frames since last real input
  const DEMO_IDLE_THRESHOLD = 150; // 5 seconds at 30fps
  // No time limit — recording runs until go("gameover") or go("win")
  let gameId = "";              // derived from URL path

  function getDemoKey() { return "mono_demo_" + gameId; }

  function packKeys() {
    let bits = 0;
    for (let i = 0; i < 6; i++) if (keys[KEY_BITS[i]]) bits |= (1 << i);
    return bits;
  }

  function unpackKeys(bits) {
    for (let i = 0; i < 6; i++) keys[KEY_BITS[i]] = !!(bits & (1 << i));
  }

  function demoTotalFrames(rec) {
    return rec.length > 0 ? rec[rec.length - 1][0] : 0;
  }

  let demoRecSeed = 1; // seed captured at recording start

  function saveDemoToStorage() {
    if (demoRecording.length < 3) return;
    try {
      const payload = { seed: demoRecSeed, actions: demoRecording };
      const existing = localStorage.getItem(getDemoKey());
      if (existing) {
        const old = JSON.parse(existing);
        if (demoTotalFrames(old.actions || old) >= demoTotalFrames(demoRecording)) return;
      }
      localStorage.setItem(getDemoKey(), JSON.stringify(payload));
    } catch(e) {}
  }

  function loadDemoFromStorage() {
    try {
      const raw = localStorage.getItem(getDemoKey());
      if (!raw) return null;
      const data = JSON.parse(raw);
      // Support new format {seed, actions} and legacy [actions]
      if (data.actions) return data;
      return { seed: 1, actions: data };
    } catch(e) {}
    return null;
  }

  function startDemoPlayback() {
    const loaded = loadDemoFromStorage();
    if (!loaded || !loaded.actions || loaded.actions.length < 3) return false;
    demoPlaybackData = loaded.actions;
    demoState = "playback";
    demoPlayIdx = 0;
    demoPlayFrame = 0;
    demoPlayBits = 0;
    API.frame = 0;
    // Restore seed for deterministic replay
    _seed = loaded.seed || 1;
    for (const k of KEY_BITS) { keys[k] = false; keysPrev[k] = false; }
    return true;
  }

  function stopDemoPlayback() {
    demoState = "idle";
    demoPlaybackData = null;
    demoPlayIdx = 0;
    demoPlayFrame = 0;
    demoIdleFrames = 0;
    for (const k of KEY_BITS) { keys[k] = false; keysPrev[k] = false; }
  }

  // --- Game loop ---
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

  function drawDebugOverlays() {
    let labelX = 2;
    // --- Collision overlay (key 1) ---
    if (debugMode && debugShapes.length > 0) {
      const dcol = 0xFF00FF00; // green (ABGR)
      for (const s of debugShapes) {
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
    debugShapes.length = 0;

    // --- Sprite bounding box overlay (key 2) ---
    if (debugSprite && debugSprBoxes.length > 0) {
      const scol = 0xFFFF00FF; // magenta (ABGR)
      for (const s of debugSprBoxes) {
        for (let px = s.x; px < s.x + 16; px++) {
          if (px >= 0 && px < W) {
            if (s.y >= 0 && s.y < H) buf32[s.y * W + px] = scol;
            const by = s.y + 15;
            if (by >= 0 && by < H) buf32[by * W + px] = scol;
          }
        }
        for (let py = s.y; py < s.y + 16; py++) {
          if (py >= 0 && py < H) {
            if (s.x >= 0 && s.x < W) buf32[py * W + s.x] = scol;
            const bx = s.x + 15;
            if (bx >= 0 && bx < W) buf32[py * W + bx] = scol;
          }
        }
      }
      labelX = drawDebugLabel("2:SPRITE", labelX, scol) + 6;
    }
    debugSprBoxes.length = 0;

    // --- Fill overlay (key 3) ---
    if (debugFill && debugFillBoxes.length > 0) {
      const fcol = 0xFFFF8800; // cyan (ABGR)
      for (const s of debugFillBoxes) {
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
    debugFillBoxes.length = 0;
  }

  function tick() {
    // --- Attract mode: playback ---
    if (demoState === "playback") {
      while (demoPlayIdx < demoPlaybackData.length &&
             demoPlaybackData[demoPlayIdx][0] <= demoPlayFrame) {
        demoPlayBits = demoPlaybackData[demoPlayIdx][1];
        demoPlayIdx++;
      }
      unpackKeys(demoPlayBits);
      demoPlayFrame++;
      // Loop when recording ends
      if (demoPlayIdx >= demoPlaybackData.length &&
          demoPlayFrame > demoTotalFrames(demoPlaybackData) + 30) {
        const loaded = loadDemoFromStorage();
        demoPlayIdx = 0;
        demoPlayFrame = 0;
        demoPlayBits = 0;
        API.frame = 0;
        _seed = (loaded && loaded.seed) || 1;
        unpackKeys(0);
        // Re-enter title scene for clean loop
        if (scenes["title"]) {
          currentSceneName = "title";
          currentScene = scenes["title"];
          if (currentScene.init) currentScene.init();
        }
      }
    } else {
      // --- Attract mode: idle detection & recording ---
      let realKeyActive = false;
      for (const k of KEY_BITS) if (keys[k]) { realKeyActive = true; break; }
      if (realKeyActive) demoIdleFrames = 0; else demoIdleFrames++;

      // Record key changes until go("gameover") or go("win") saves it
      if (demoState === "recording") {
        const bits = packKeys();
        if (bits !== demoLastBits) {
          demoRecording.push([demoRecFrame, bits]);
          demoLastBits = bits;
        }
        demoRecFrame++;
      }

      // Start playback on title scene after idle threshold
      if (demoState === "idle" && currentSceneName === "title" &&
          demoIdleFrames >= DEMO_IDLE_THRESHOLD) {
        startDemoPlayback();
      }
    }

    // --- Start button: title → play ---
    if (keys["start"] && !keysPrev["start"] && currentSceneName === "title") {
      API.go("play");
    }

    // --- Pause toggle (select button during play) ---
    if (keys["select"] && !keysPrev["select"] && currentSceneName === "play") {
      paused = !paused;
    }

    if (paused) {
      // Still draw the current frame but skip update
      if (currentScene && currentScene.draw) currentScene.draw();
      else if (API._draw) API._draw();
      // Draw PAUSE overlay
      const pauseStr = "PAUSE";
      const pw = pauseStr.length * (FONT_W + 1);
      const px = (W - pw) >> 1;
      const py = (H - FONT_H) >> 1;
      // Draw black background box
      for (let by = py - 3; by < py + FONT_H + 3; by++)
        for (let bx = px - 4; bx < px + pw + 4; bx++)
          if (bx >= 0 && bx < W && by >= 0 && by < H) buf32[by * W + bx] = COLOR_U32[0];
      const blink = API.frame % 30 < 20;
      if (blink) {
        const col = COLOR_U32[3];
        let cx = px;
        for (const ch of pauseStr) {
          const glyph = FONT[ch];
          if (glyph) for (let ppy = 0; ppy < FONT_H; ppy++) for (let ppx = 0; ppx < FONT_W; ppx++)
            if (glyph[ppy * FONT_W + ppx]) {
              const sx = cx + ppx, sy = py + ppy;
              if (sx >= 0 && sx < W && sy >= 0 && sy < H) buf32[sy * W + sx] = col;
            }
          cx += FONT_W + 1;
        }
      }
      drawDebugOverlays();
      ctx.putImageData(buf, 0, 0);
      for (const k in keys) keysPrev[k] = keys[k];
      API.frame++;
      return;
    }

    // --- BGM sequencer tick ---
    bgmTick();

    // --- Update & Draw (scene-based or legacy) ---
    if (currentScene) {
      if (currentScene.update) currentScene.update();
      if (currentScene.draw) currentScene.draw();
    } else {
      // Legacy: _update/_draw for non-scene games
      if (API._update) API._update();
      if (API._draw) API._draw();
    }

    // --- DEMO indicator overlay ---
    if (demoState === "playback") {
      const col = COLOR_U32[API.frame % 40 < 20 ? 3 : 2];
      let cx = W - 26;
      for (const ch of "DEMO") {
        const glyph = FONT[ch];
        if (glyph) for (let py = 0; py < FONT_H; py++) for (let px = 0; px < FONT_W; px++)
          if (glyph[py * FONT_W + px]) {
            const sx = cx + px, sy = 2 + py;
            if (sx >= 0 && sx < W && sy >= 0 && sy < H) buf32[sy * W + sx] = col;
          }
        cx += FONT_W + 1;
      }
    }

    drawDebugOverlays();

    ctx.putImageData(buf, 0, 0);
    for (const k in keys) keysPrev[k] = keys[k];
    API.frame++;
  }

  // --- Boot ---
  API.boot = function(canvasId) {
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

    document.addEventListener("keydown", e => {
      // Debug toggles
      if (e.key === "1") { debugMode = !debugMode; e.preventDefault(); return; }
      if (e.key === "2") { debugSprite = !debugSprite; e.preventDefault(); return; }
      if (e.key === "3") { debugFill = !debugFill; e.preventDefault(); return; }
      const k = keyMap[e.key];
      if (k) {
        // If in playback mode, stop it on real input
        if (demoState === "playback") {
          stopDemoPlayback();
          API.frame = 0;
        }
        keys[k] = true;
        e.preventDefault();
      }
    });
    document.addEventListener("keyup", e => {
      const k = keyMap[e.key];
      if (k) { keys[k] = false; e.preventDefault(); }
    });
    document.addEventListener("keydown", ensureAudio, { once: true });
    document.addEventListener("click", e => {
      ensureAudio();
      // Touch/click also stops playback
      if (demoState === "playback") {
        stopDemoPlayback();
        API.frame = 0;
      }
    }, { once: false });

    if (API._init) API._init();
    setInterval(tick, 1000 / FPS);
  };

  // Low-level access for games needing custom rendering
  API._sprites = sprites;
  API._COLOR_U32 = COLOR_U32;
  Object.defineProperty(API, '_buf32', { get() { return buf32; } });

  return API;
})();
