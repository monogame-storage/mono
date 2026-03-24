/**
 * Mono Runtime Engine v2.0 "Mono"
 *
 * 320x240, 4-color grayscale, 30fps, 2ch square wave
 * Lua scripting via Wasmoon, 4KB RAM, rAF fixed timestep
 * Input record/playback, savestate, postMessage IPC
 */
const Mono = (() => {
  "use strict";

  const W = 320;
  const H = 240;
  const FPS = 30;
  const FRAME_MS = 1000 / FPS;
  let SPR_SIZE = 16; // configurable via boot({ spriteSize: N })
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

  // --- Font (4x7 bitmap) ---
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
  API.speed = 1; // multiplier for game speed
  API.WIDTH = W;
  API.HEIGHT = H;
  API.COLORS = COLORS;

  // --- RAM ---
  const RAM_SIZE = 4096;
  const ram = new Uint8Array(RAM_SIZE);
  API.ram = ram;

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

  API.go = function(name, opts) {
    if (VALID_SCENES.indexOf(name) === -1) {
      console.warn('Mono: invalid scene "' + name + '"');
      return;
    }
    if (bgmPlaying) API.bgmStop();
    paused = false;
    currentSceneName = name;
    currentScene = scenes[name] || null;
    if (currentScene && currentScene.init && (!opts || !opts.skipInit)) {
      currentScene.init();
    }
  };

  API.currentScene = function() { return currentSceneName; };
  API.paused = function() { return paused; };

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
    const SS=SPR_SIZE, SM=SS-1;
    x=Math.floor(x); y=Math.floor(y);
    for(let py=0;py<SS;py++) for(let px=0;px<SS;px++){
      const sx=flipX?SM-px:px, sy=flipY?SM-py:py;
      const c=s[sy*SS+sx], dx=x+px, dy=y+py;
      if(dx>=0&&dx<W&&dy>=0&&dy<H) buf32[dy*W+dx]=COLOR_U32[c];
    }
    if(debugSprite) debugSprBoxes.push({x:x,y:y});
  };
  // Transparent sprite (color 0 = skip)
  API.sprT = function(id, x, y, flipX, flipY) {
    const s=sprites[id]; if(!s) return;
    const SS=SPR_SIZE, SM=SS-1;
    x=Math.floor(x); y=Math.floor(y);
    for(let py=0;py<SS;py++) for(let px=0;px<SS;px++){
      const sx=flipX?SM-px:px, sy=flipY?SM-py:py;
      const c=s[sy*SS+sx]; if(c===0) continue;
      const dx=x+px, dy=y+py;
      if(dx>=0&&dx<W&&dy>=0&&dy<H) buf32[dy*W+dx]=COLOR_U32[c];
    }
    if(debugSprite) debugSprBoxes.push({x:x,y:y});
  };
  // Rotated sprite (draws sprite rotated by angle in radians)
  API.sprRot = function(id, cx, cy, angle) {
    const s = sprites[id]; if (!s) return;
    const SS=SPR_SIZE, half=SS/2, range=Math.ceil(half*1.42);
    const cosA = Math.cos(angle), sinA = Math.sin(angle);
    for (let py = -range; py <= range; py++) {
      for (let px = -range; px <= range; px++) {
        const srcX = Math.floor(cosA * px + sinA * py + half - 0.5);
        const srcY = Math.floor(-sinA * px + cosA * py + half - 0.5);
        if (srcX < 0 || srcX >= SS || srcY < 0 || srcY >= SS) continue;
        const c = s[srcY * SS + srcX];
        const dx = Math.floor(cx + px), dy = Math.floor(cy + py);
        if (dx >= 0 && dx < W && dy >= 0 && dy < H) buf32[dy * W + dx] = COLOR_U32[c];
      }
    }
    if(debugSprite) debugSprBoxes.push({x:Math.floor(cx)-Math.floor(SS/2),y:Math.floor(cy)-Math.floor(SS/2)});
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
      const id=API.mget(mx+tx,my+ty); if(id>0) API.spr(id,sx+tx*SPR_SIZE,sy+ty*SPR_SIZE); }
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

  // --- Demo Record/Playback (frame-level, scene-independent) ---
  const KEY_BITS = ["up","down","left","right","a","b","start","select"];
  let demoState = "idle";       // idle | recording | playback
  let demoRecording = [];       // [[frame, bits], ...] action-based
  let demoRecFrame = 0;         // frame counter during recording
  let demoLastBits = 0;         // last recorded bitmask
  let demoRecSeed = 1;          // seed captured at recording start
  let demoPlaybackData = null;  // loaded recording for playback
  let demoPlayIdx = 0;          // current index in playback data
  let demoPlayFrame = 0;        // frame counter during playback
  let demoPlayBits = 0;         // current key state during playback
  let gameId = "";              // derived from URL path

  function getDemoKey() { return "mono_demo_" + gameId; }

  function packKeys() {
    let bits = 0;
    for (let i = 0; i < KEY_BITS.length; i++) if (keys[KEY_BITS[i]]) bits |= (1 << i);
    return bits;
  }

  function unpackKeys(bits) {
    for (let i = 0; i < KEY_BITS.length; i++) keys[KEY_BITS[i]] = !!(bits & (1 << i));
  }

  function loadDemoFromStorage() {
    try {
      const raw = localStorage.getItem(getDemoKey());
      if (!raw) return null;
      const data = JSON.parse(raw);
      if (data.actions) return data;
      return { seed: 1, actions: data };
    } catch(e) {}
    return null;
  }

  function notifyParent(event, data) {
    if (window.parent !== window) {
      window.parent.postMessage({ type: "mono", event, ...data }, "*");
    }
  }

  API.demoRec = function() {
    demoState = "recording";
    demoRecording = [];
    demoRecFrame = 0;
    demoLastBits = 0;
    demoRecSeed = _seed;
    API.frame = 0;
    notifyParent("state", { state: "recording" });
  };

  API.demoPlay = function() {
    const loaded = loadDemoFromStorage();
    if (!loaded) return false;
    demoPlaybackData = loaded.actions;
    demoState = "playback";
    demoPlayIdx = 0;
    demoPlayFrame = 0;
    demoPlayBits = 0;
    API.frame = 0;
    _seed = loaded.seed || 1;
    for (const k of KEY_BITS) { keys[k] = false; keysPrev[k] = false; }
    if (scenes["title"]) {
      currentSceneName = "title";
      currentScene = scenes["title"];
      if (currentScene.init) currentScene.init();
    }
    notifyParent("state", { state: "playback" });
    return true;
  };

  API.demoStop = function() {
    demoState = "idle";
    demoPlaybackData = null;
    notifyParent("state", { state: "idle" });
  };

  API.demoSave = function() {
    if (demoState === "recording" && demoRecording.length >= 1) {
      demoRecording.push([demoRecFrame, 0]);
      try {
        localStorage.setItem(getDemoKey(), JSON.stringify({ seed: demoRecSeed, actions: demoRecording }));
      } catch(e) {}
    }
    API.demoStop();
  };

  // --- Savestate ---
  API.save = function() {
    return { ram: ram.slice(), frame: API.frame, seed: _seed, scene: currentSceneName };
  };
  API.load = function(state) {
    ram.set(state.ram);
    API.frame = state.frame;
    _seed = state.seed;
    currentSceneName = state.scene;
    currentScene = scenes[state.scene] || null;
    // No init call - state restored from RAM
  };

  // --- Visual Sprite Parser ---
  function parseVisualSprite(str) {
    const lines = str.trim().split('\n').map(l => l.trim()).filter(l => l.length > 0);
    const h = lines.length;
    const w = lines[0].length;
    const data = new Uint8Array(w * h);
    for (let y = 0; y < h; y++)
      for (let x = 0; x < w; x++) {
        const ch = lines[y][x] || '0';
        data[y * w + x] = ch === '.' ? 0 : parseInt(ch) || 0;
      }
    return data;
  }

  // --- Debug overlays ---
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

  function drawOverlayText(str, x, y, c) {
    const col = COLOR_U32[c] || COLOR_U32[3];
    let cx = x;
    for (const ch of str) {
      const glyph = FONT[ch];
      if (glyph) for (let py = 0; py < FONT_H; py++) for (let px = 0; px < FONT_W; px++)
        if (glyph[py * FONT_W + px]) {
          const sx = cx + px, sy = y + py;
          if (sx >= 0 && sx < W && sy >= 0 && sy < H) buf32[sy * W + sx] = col;
        }
      cx += FONT_W + 1;
    }
  }

  function drawPauseOverlay() {
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
  }

  // --- Lua VM (module-scoped) ---
  let lua = null;

  // --- Lua API Bridge ---
  function registerLuaAPI() {
    // Graphics
    lua.global.set('cls', (c) => API.cls(c || 0));
    lua.global.set('pix', API.pix);
    lua.global.set('line', API.line);
    lua.global.set('rect', API.rect);
    lua.global.set('rectf', API.rectf);
    lua.global.set('circ', API.circ);
    lua.global.set('circf', API.circf);
    lua.global.set('spr', API.spr);
    lua.global.set('sprT', API.sprT);
    lua.global.set('sprRot', API.sprRot);
    lua.global.set('gpix', API.gpix);
    lua.global.set('text', API.text);

    // Tilemap
    lua.global.set('mget', API.mget);
    lua.global.set('mset', API.mset);
    lua.global.set('map', API.map);

    // Input
    lua.global.set('btn', API.btn);
    lua.global.set('btnp', API.btnp);

    // Sound
    lua.global.set('note', API.note);
    lua.global.set('sfx_stop', API.stop);
    lua.global.set('bgm', (tracks, bpm, loop) => {
      // tracks comes as Lua table, convert to JS array
      const arr = [];
      for (let i = 1; ; i++) {
        const t = tracks.get(i); // Lua 1-indexed
        if (t === undefined || t === null) break;
        arr.push(t);
      }
      API.bgm(arr, bpm, loop);
    });
    lua.global.set('bgm_stop', API.bgmStop);

    // Scene
    lua.global.set('go', (name) => API.go(name));
    lua.global.set('scene_name', () => API.currentScene());

    // Math
    lua.global.set('rnd', API.rnd);
    lua.global.set('flr', Math.floor);
    lua.global.set('abs', Math.abs);
    lua.global.set('seed', API.seed);

    // Debug
    lua.global.set('dbg', API.dbg);
    lua.global.set('dbgC', API.dbgC);
    lua.global.set('dbgPt', API.dbgPt);

    // Frame (as function since it changes)
    lua.global.set('frame', () => API.frame);

    // Overlap
    lua.global.set('overlap', API.overlap);

    // Sprite definition (supports visual format and classic)
    lua.global.set('defSprite', (id, data) => {
      if (typeof data === 'string' && data.includes('\n')) {
        sprites[id] = parseVisualSprite(data);
      } else {
        API.sprite(id, data);
      }
    });

    // RAM peek/poke
    lua.global.set('peek', (addr) => ram[addr & 0xFFF]);
    lua.global.set('poke', (addr, val) => { ram[addr & 0xFFF] = val & 0xFF; });
    lua.global.set('peek16', (addr) => { addr &= 0xFFF; return ram[addr] | (ram[addr+1] << 8); });
    lua.global.set('poke16', (addr, val) => { addr &= 0xFFF; ram[addr] = val & 0xFF; ram[addr+1] = (val >> 8) & 0xFF; });
  }

  // --- Declarative Game Table Parser ---
  let spriteIdCounter = 1;
  const spriteNames = {};

  function parseVisualSprites(spritesTable) {
    for (const [name, data] of spritesTable) {
      const pixels = parseVisualSprite(data);
      sprites[spriteIdCounter] = pixels;
      spriteNames[name] = spriteIdCounter;
      spriteIdCounter++;
    }
    // Expose sprite name lookup to Lua
    lua.global.set('sprite_id', (name) => spriteNames[name] || 0);
  }

  function buildStateAccessors(stateTable) {
    let offset = 0;
    const layout = {};

    for (const [name, type] of stateTable) {
      if (typeof type === 'string') {
        layout[name] = { offset, type };
        if (type === 'u8' || type === 'i8') offset += 1;
        else if (type === 'u16' || type === 'i16') offset += 2;
        else if (type === 'u32' || type === 'i32') offset += 4;
      }
    }

    lua.global.set('S_get', (name) => {
      const l = layout[name]; if (!l) return 0;
      if (l.type === 'u8') return ram[l.offset];
      if (l.type === 'u16') return ram[l.offset] | (ram[l.offset+1] << 8);
      if (l.type === 'i8') { const v = ram[l.offset]; return v > 127 ? v - 256 : v; }
      if (l.type === 'i16') { const v = ram[l.offset] | (ram[l.offset+1] << 8); return v > 32767 ? v - 65536 : v; }
      if (l.type === 'u32') return ram[l.offset] | (ram[l.offset+1] << 8) | (ram[l.offset+2] << 16) | (ram[l.offset+3] << 24);
      if (l.type === 'i32') { const v = ram[l.offset] | (ram[l.offset+1] << 8) | (ram[l.offset+2] << 16) | (ram[l.offset+3] << 24); return v; }
      return 0;
    });
    lua.global.set('S_set', (name, val) => {
      const l = layout[name]; if (!l) return;
      if (l.type === 'u8' || l.type === 'i8') { ram[l.offset] = val & 0xFF; }
      else if (l.type === 'u16' || l.type === 'i16') { ram[l.offset] = val & 0xFF; ram[l.offset+1] = (val >> 8) & 0xFF; }
      else if (l.type === 'u32' || l.type === 'i32') { ram[l.offset] = val & 0xFF; ram[l.offset+1] = (val >> 8) & 0xFF; ram[l.offset+2] = (val >> 16) & 0xFF; ram[l.offset+3] = (val >> 24) & 0xFF; }
    });

    // Create S as a proxy table in Lua
    lua.doString(`
      S = setmetatable({}, {
        __index = function(_, k) return S_get(k) end,
        __newindex = function(_, k, v) S_set(k, v) end,
      })
    `);
  }

  function registerSounds(soundsTable) {
    // Sounds table: name → { note, dur } or similar
    // Expose as Lua functions
    for (const [name, def] of soundsTable) {
      lua.global.set('sfx_' + name, () => {
        if (typeof def === 'object' && def.get) {
          const n = def.get('note') || def.get(1);
          const d = def.get('dur') || def.get(2) || 0.1;
          const ch = def.get('ch') || def.get(3) || 0;
          API.note(ch, n, d);
        }
      });
    }
  }

  function parseGameTable() {
    const gameTable = lua.global.get('game');
    if (!gameTable) return;

    // Parse sprites (visual format)
    const spritesT = gameTable.get('sprites');
    if (spritesT) parseVisualSprites(spritesT);

    // Parse state -> RAM layout
    const stateT = gameTable.get('state');
    if (stateT) buildStateAccessors(stateT);

    // Parse sounds
    const soundsT = gameTable.get('sounds');
    if (soundsT) registerSounds(soundsT);
  }

  // --- Scene auto-detection from Lua globals ---
  function autoDetectScenes() {
    for (const name of VALID_SCENES) {
      const initFn = lua.global.get(name + "_init");
      const updateFn = lua.global.get(name + "_update");
      const drawFn = lua.global.get(name + "_draw");
      if (updateFn || drawFn) {
        scenes[name] = {
          init: typeof initFn === 'function' ? initFn : null,
          update: typeof updateFn === 'function' ? updateFn : null,
          draw: typeof drawFn === 'function' ? drawFn : null,
        };
      }
    }
  }

  // --- Game Loop (rAF + fixed timestep) ---
  let lastTime = 0;
  let accumulated = 0;

  function stepInput() {
    // Demo recording
    if (demoState === "recording") {
      const bits = packKeys();
      if (bits !== demoLastBits) {
        demoRecording.push([demoRecFrame, bits]);
        demoLastBits = bits;
      }
      demoRecFrame++;
    }

    // Demo playback (merge with real input)
    if (demoState === "playback") {
      while (demoPlayIdx < demoPlaybackData.length &&
             demoPlaybackData[demoPlayIdx][0] <= demoPlayFrame) {
        demoPlayBits = demoPlaybackData[demoPlayIdx][1];
        demoPlayIdx++;
      }
      // Merge: playback bits OR real input
      const realBits = packKeys();
      const merged = demoPlayBits | realBits;
      unpackKeys(merged);
      demoPlayFrame++;

      // Check if playback exhausted
      if (demoPlayIdx >= demoPlaybackData.length &&
          demoPlayFrame > (demoPlaybackData.length > 0 ? demoPlaybackData[demoPlaybackData.length-1][0] : 0) + 30) {
        API.demoStop();
      }
    }

    // Start button: title -> play
    if (keys["start"] && !keysPrev["start"] && currentSceneName === "title") {
      API.go("play");
    }

    // Pause toggle
    if (keys["select"] && !keysPrev["select"] && currentSceneName === "play") {
      paused = !paused;
    }

    // Copy prev (must be at end so btnp works within this frame)
    for (const k in keys) keysPrev[k] = keys[k];
  }

  function stepUpdate() {
    if (paused) return;
    bgmTick();
    if (currentScene && currentScene.update) {
      currentScene.update();
    }
  }

  function stepRender() {
    if (currentScene && currentScene.draw) {
      currentScene.draw();
    }

    // Pause overlay
    if (paused) {
      drawPauseOverlay();
    }

    // Demo indicators
    if (demoState === "playback") {
      drawOverlayText("DEMO", W - 26, 2, API.frame % 40 < 20 ? 3 : 2);
    }
    if (demoState === "recording") {
      drawOverlayText("REC", W - 20, 2, API.frame % 30 < 20 ? 3 : 1);
    }

    drawDebugOverlays();
    ctx.putImageData(buf, 0, 0);
  }

  function loop(timestamp) {
    if (!lastTime) lastTime = timestamp;
    accumulated += (timestamp - lastTime) * API.speed;
    lastTime = timestamp;
    if (accumulated > FRAME_MS * 5) accumulated = FRAME_MS * 5; // cap
    while (accumulated >= FRAME_MS) {
      stepInput();
      stepUpdate();
      accumulated -= FRAME_MS;
      API.frame++;
    }
    stepRender();
    requestAnimationFrame(loop);
  }

  // --- Boot ---
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

    document.addEventListener("keydown", e => {
      // Debug toggles
      if (e.key === "1") { debugMode = !debugMode; e.preventDefault(); return; }
      if (e.key === "2") { debugSprite = !debugSprite; e.preventDefault(); return; }
      if (e.key === "3") { debugFill = !debugFill; e.preventDefault(); return; }
      const k = keyMap[e.key];
      if (k) {
        keys[k] = true;
        e.preventDefault();
      }
    });
    document.addEventListener("keyup", e => {
      const k = keyMap[e.key];
      if (k) { keys[k] = false; e.preventDefault(); }
    });
    document.addEventListener("keydown", ensureAudio, { once: true });
    document.addEventListener("click", ensureAudio, { once: true });

    // postMessage IPC
    window.addEventListener("message", (e) => {
      if (e.data && e.data.type === "mono") {
        switch(e.data.cmd) {
          case "rec": API.demoRec(); break;
          case "play": API.demoPlay(); break;
          case "stop": API.demoStop(); break;
          case "save": API.demoSave(); break;
        }
      }
    });

    // --- Lua VM init ---
    // Resolve wasm path relative to engine.js location
    const scripts = document.getElementsByTagName('script');
    let engineBase = '';
    for (const s of scripts) {
      if (s.src && s.src.includes('engine.js')) {
        engineBase = s.src.substring(0, s.src.lastIndexOf('/') + 1);
        break;
      }
    }
    const wasmUri = engineBase + 'wasmoon/glue.wasm';
    const factory = new wasmoon.LuaFactory(wasmUri);
    lua = await factory.createEngine();

    // Register all API functions as Lua globals
    registerLuaAPI();

    // Fetch and run game.lua
    if (opts && opts.game) {
      const src = await fetch(opts.game).then(r => r.text());
      await lua.doString(src);
    }

    // Parse declarative game table (sprites, state, sounds)
    parseGameTable();

    // Auto-detect scenes from Lua globals
    autoDetectScenes();

    // Start first scene if title exists
    if (scenes["title"]) {
      API.go("title");
    }

    // Start game loop
    requestAnimationFrame(loop);
  };

  // Low-level access for games needing custom rendering
  API._sprites = sprites;
  API._COLOR_U32 = COLOR_U32;
  Object.defineProperty(API, '_buf32', { get() { return buf32; } });
  Object.defineProperty(API, 'spriteSize', { get() { return SPR_SIZE; } });

  return API;
})();
