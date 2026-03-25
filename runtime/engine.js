/**
 * Mono Runtime Engine v4.0 "Mono"
 *
 * Single-file, main-thread engine using Wasmoon (Lua 5.4).
 * No Worker, no postMessage for game logic.
 * 320x240, 4-color grayscale, 30fps, 2ch square wave.
 *
 * Mono.boot("screen", { game: "game.lua" })
 */
const Mono = (() => {
  "use strict";

  const W = 320;
  const H = 240;
  const FPS = 30;
  const FRAME_MS = 1000 / FPS;
  let SPR_SIZE = 16;
  const COLORS = ["#1a1a1a", "#6b6b6b", "#b0b0b0", "#e8e8e8"];

  function hexToABGR(hex) {
    const r = parseInt(hex.slice(1, 3), 16);
    const g = parseInt(hex.slice(3, 5), 16);
    const b = parseInt(hex.slice(5, 7), 16);
    return (255 << 24) | (b << 16) | (g << 8) | r;
  }
  const COLOR_U32 = COLORS.map(hexToABGR);

  let canvas, ctx, buf, buf32;

  // --- Input ---
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
  let debugMode = false;
  let debugSprite = false;
  let debugFill = false;
  const debugShapes = [];
  const debugSprBoxes = [];
  const debugFillBoxes = [];

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

  // --- Sprites & Tilemap ---
  const sprites = {};
  const tilemap = {};

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

  // --- BGM Sequencer ---
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

  // --- Frame state ---
  let frameCount = 0;
  let speed = 1;

  // --- RAM ---
  const RAM_SIZE = 4096;
  const ram = new Uint8Array(RAM_SIZE);

  // --- Scene system ---
  const VALID_SCENES = ["title","play","clear","gameover","win"];
  const scenes = {};
  let currentScene = null;
  let currentSceneName = "";

  // --- Lua VM ---
  let lua = null;

  function sceneGo(name, opts) {
    if (VALID_SCENES.indexOf(name) === -1) {
      console.warn('Mono: invalid scene "' + name + '"');
      return;
    }
    stopBgm();
    paused = false;
    camReset();
    ecsClear();
    currentSceneName = name;
    currentScene = scenes[name] || null;
  }

  // --- Camera ---
  let camX = 0, camY = 0;
  let camShake = 0;
  let camOX = 0, camOY = 0;

  function camSet(x, y) { camX = x; camY = y; }
  function camGet() { return [camX, camY]; }
  function camShakeSet(amt) { camShake = amt; }
  function camReset() { camX = 0; camY = 0; camShake = 0; }

  function camUpdateFrame() {
    let sx = 0, sy = 0;
    if (camShake > 0) {
      sx = (Math.random() - 0.5) * camShake * 2;
      sy = (Math.random() - 0.5) * camShake * 2;
      camShake *= 0.9;
      if (camShake < 0.5) camShake = 0;
    }
    camOX = Math.floor(-camX + sx);
    camOY = Math.floor(-camY + sy);
  }

  // --- Graphics ---
  function cls(c) { buf32.fill(COLOR_U32[c || 0]); }
  function pix(x, y, c) {
    x = Math.floor(x + camOX); y = Math.floor(y + camOY);
    if (x < 0 || x >= W || y < 0 || y >= H) return;
    buf32[y * W + x] = COLOR_U32[c] || COLOR_U32[0];
  }
  function line(x0, y0, x1, y1, c) {
    x0=Math.floor(x0+camOX); y0=Math.floor(y0+camOY); x1=Math.floor(x1+camOX); y1=Math.floor(y1+camOY);
    const col=COLOR_U32[c]||COLOR_U32[0];
    const dx=Math.abs(x1-x0), dy=Math.abs(y1-y0);
    const sx=x0<x1?1:-1, sy=y0<y1?1:-1;
    let err=dx-dy;
    while(true) {
      if(x0>=0&&x0<W&&y0>=0&&y0<H) buf32[y0*W+x0]=col;
      if(x0===x1&&y0===y1) break;
      const e2=2*err;
      if(e2>-dy){err-=dy;x0+=sx;}
      if(e2<dx){err+=dx;y0+=sy;}
    }
  }
  function rect(x,y,w,h,c) {
    line(x,y,x+w-1,y,c); line(x+w-1,y,x+w-1,y+h-1,c);
    line(x+w-1,y+h-1,x,y+h-1,c); line(x,y+h-1,x,y,c);
  }
  function rectf(x,y,w,h,c) {
    x=Math.floor(x+camOX); y=Math.floor(y+camOY);
    const col=COLOR_U32[c]||COLOR_U32[0];
    for(let py=Math.max(0,y);py<Math.min(H,y+h);py++)
      for(let px=Math.max(0,x);px<Math.min(W,x+w);px++)
        buf32[py*W+px]=col;
    if(debugFill) debugFillBoxes.push({t:"r",x:x,y:y,w:w,h:h});
  }
  function circ(cx,cy,r,c) {
    let x=r,y=0,d=1-r; cx=Math.floor(cx+camOX); cy=Math.floor(cy+camOY);
    const col=COLOR_U32[c]||COLOR_U32[0];
    while(x>=y){
      const pts=[[cx+x,cy+y],[cx-x,cy+y],[cx+x,cy-y],[cx-x,cy-y],[cx+y,cy+x],[cx-y,cy+x],[cx+y,cy-x],[cx-y,cy-x]];
      for(const[px,py] of pts) if(px>=0&&px<W&&py>=0&&py<H) buf32[py*W+px]=col;
      y++; if(d<0){d+=2*y+1;}else{x--;d+=2*(y-x)+1;}
    }
  }
  function circf(cx,cy,r,c) {
    cx=Math.floor(cx+camOX); cy=Math.floor(cy+camOY);
    const col=COLOR_U32[c]||COLOR_U32[0]; const r2=r*r;
    for(let py=-r;py<=r;py++) for(let px=-r;px<=r;px++)
      if(px*px+py*py<=r2){ const sx=cx+px,sy=cy+py;
        if(sx>=0&&sx<W&&sy>=0&&sy<H) buf32[sy*W+sx]=col; }
    if(debugFill) debugFillBoxes.push({t:"c",x:cx,y:cy,r:r});
  }

  // --- Sprites ---
  function spriteDefine(id, data) {
    const arr = new Uint8Array(256); let i = 0;
    for (const ch of data) { if (ch>='0'&&ch<='3') { arr[i++]=parseInt(ch); if(i>=256) break; } }
    sprites[id] = arr;
  }
  function spr(id, x, y, flipX, flipY) {
    const s=sprites[id]; if(!s) return;
    const SS=SPR_SIZE, SM=SS-1;
    x=Math.floor(x+camOX); y=Math.floor(y+camOY);
    for(let py=0;py<SS;py++) for(let px=0;px<SS;px++){
      const sx=flipX?SM-px:px, sy=flipY?SM-py:py;
      const c=s[sy*SS+sx], dx=x+px, dy=y+py;
      if(dx>=0&&dx<W&&dy>=0&&dy<H) buf32[dy*W+dx]=COLOR_U32[c];
    }
    if(debugSprite) debugSprBoxes.push({x:x,y:y,w:SPR_SIZE,h:SPR_SIZE});
  }
  function sprT(id, x, y, flipX, flipY) {
    const s=sprites[id]; if(!s) return;
    const SS=SPR_SIZE, SM=SS-1;
    x=Math.floor(x+camOX); y=Math.floor(y+camOY);
    for(let py=0;py<SS;py++) for(let px=0;px<SS;px++){
      const sx=flipX?SM-px:px, sy=flipY?SM-py:py;
      const c=s[sy*SS+sx]; if(c===0) continue;
      const dx=x+px, dy=y+py;
      if(dx>=0&&dx<W&&dy>=0&&dy<H) buf32[dy*W+dx]=COLOR_U32[c];
    }
    if(debugSprite) debugSprBoxes.push({x:x,y:y,w:SPR_SIZE,h:SPR_SIZE});
  }
  function sprScale(id, cx, cy, scale, flipX, flipY) {
    const s = sprites[id]; if (!s) return;
    const SS = SPR_SIZE, half = SS / 2;
    cx = Math.floor(cx + camOX); cy = Math.floor(cy + camOY);
    const scaledHalf = half * scale;
    const invScale = 1 / scale;
    const imin = Math.floor(-scaledHalf), imax = Math.ceil(scaledHalf);
    for (let py = imin; py < imax; py++) {
      for (let px = imin; px < imax; px++) {
        let srcX = Math.floor(px * invScale + half);
        let srcY = Math.floor(py * invScale + half);
        if (flipX) srcX = SS - 1 - srcX;
        if (flipY) srcY = SS - 1 - srcY;
        if (srcX < 0 || srcX >= SS || srcY < 0 || srcY >= SS) continue;
        const c = s[srcY * SS + srcX];
        if (c === 0) continue;
        const dx = cx + px, dy = cy + py;
        if (dx >= 0 && dx < W && dy >= 0 && dy < H) buf32[dy * W + dx] = COLOR_U32[c];
      }
    }
    if (debugSprite) { const bsz = Math.ceil(scaledHalf * 2); debugSprBoxes.push({x: cx - Math.floor(scaledHalf), y: cy - Math.floor(scaledHalf), w: bsz, h: bsz}); }
  }
  function sprRot(id, cx, cy, angle) {
    const s = sprites[id]; if (!s) return;
    const SS=SPR_SIZE, half=SS/2, range=Math.ceil(half*1.42);
    const cosA = Math.cos(angle), sinA = Math.sin(angle);
    for (let py = -range; py <= range; py++) {
      for (let px = -range; px <= range; px++) {
        const srcX = Math.floor(cosA * px + sinA * py + half - 0.5);
        const srcY = Math.floor(-sinA * px + cosA * py + half - 0.5);
        if (srcX < 0 || srcX >= SS || srcY < 0 || srcY >= SS) continue;
        const c = s[srcY * SS + srcX];
        const dx = Math.floor(cx + px + camOX), dy = Math.floor(cy + py + camOY);
        if (dx >= 0 && dx < W && dy >= 0 && dy < H) buf32[dy * W + dx] = COLOR_U32[c];
      }
    }
    if(debugSprite) debugSprBoxes.push({x:Math.floor(cx+camOX)-Math.floor(SS/2),y:Math.floor(cy+camOY)-Math.floor(SS/2),w:SS,h:SS});
  }
  function gpix(x, y) {
    x = Math.floor(x); y = Math.floor(y);
    if (x < 0 || x >= W || y < 0 || y >= H) return -1;
    const v = buf32[y * W + x];
    for (let i = 0; i < 4; i++) if (COLOR_U32[i] === v) return i;
    return -1;
  }

  // Unified draw: draw(id, x, y, [r], [sx], [sy], [ox], [oy])
  // Like LÖVE2D: rotation, scale, origin offset — all in one call
  // ox,oy = origin offset (default: 0,0 = topleft; SPR_SIZE/2 = center)
  function drawSprite(id, x, y, r, sx, sy, ox, oy) {
    const s = sprites[id]; if (!s) return;
    const SS = SPR_SIZE;
    r = r || 0;
    sx = (sx !== undefined && sx !== null) ? sx : 1;
    sy = (sy !== undefined && sy !== null) ? sy : 1;
    ox = ox || 0;
    oy = oy || 0;

    x = x + camOX;
    y = y + camOY;

    if (r === 0 && sx === 1 && sy === 1) {
      // Fast path: simple draw with offset
      const dx = Math.floor(x - ox), dy = Math.floor(y - oy);
      for (let py = 0; py < SS; py++) for (let px = 0; px < SS; px++) {
        const c = s[py * SS + px]; if (c === 0) continue;
        const fx = dx + px, fy = dy + py;
        if (fx >= 0 && fx < W && fy >= 0 && fy < H) buf32[fy * W + fx] = COLOR_U32[c];
      }
      if (debugSprite) debugSprBoxes.push({x: dx, y: dy, w: SS, h: SS});
    } else {
      // Full path: rotation + scale
      const cosA = Math.cos(r), sinA = Math.sin(r);
      const range = Math.ceil(Math.max(Math.abs(sx), Math.abs(sy)) * SS * 0.72);
      for (let py = -range; py <= range; py++) {
        for (let px = -range; px <= range; px++) {
          // Inverse transform: screen → source
          const srcX = Math.floor((cosA * px + sinA * py) / sx + ox);
          const srcY = Math.floor((-sinA * px + cosA * py) / sy + oy);
          if (srcX < 0 || srcX >= SS || srcY < 0 || srcY >= SS) continue;
          const c = s[srcY * SS + srcX]; if (c === 0) continue;
          const fx = Math.floor(x + px), fy = Math.floor(y + py);
          if (fx >= 0 && fx < W && fy >= 0 && fy < H) buf32[fy * W + fx] = COLOR_U32[c];
        }
      }
      if (debugSprite) {
        const bw = Math.ceil(SS * Math.abs(sx));
        const bh = Math.ceil(SS * Math.abs(sy));
        debugSprBoxes.push({x: Math.floor(x - ox * sx), y: Math.floor(y - oy * sy), w: bw, h: bh});
      }
    }
  }

  // --- Text ---
  function drawText(str, x, y, c) {
    str=String(str).toUpperCase(); let cx=Math.floor(x); const cy=Math.floor(y);
    const col=COLOR_U32[c]||COLOR_U32[3];
    for(const ch of str){
      const glyph=FONT[ch];
      if(glyph) for(let py=0;py<FONT_H;py++) for(let px=0;px<FONT_W;px++)
        if(glyph[py*FONT_W+px]){ const dx=cx+px,dy=cy+py;
          if(dx>=0&&dx<W&&dy>=0&&dy<H) buf32[dy*W+dx]=col; }
      cx+=FONT_W+1;
    }
  }

  // --- Tilemap ---
  function mget(cx,cy) { return tilemap[cx+","+cy]||0; }
  function mset(cx,cy,id) { tilemap[cx+","+cy]=id; }
  function mapDraw(mx,my,mw,mh,sx,sy) {
    for(let ty=0;ty<mh;ty++) for(let tx=0;tx<mw;tx++){
      const id=mget(mx+tx,my+ty); if(id>0) spr(id,sx+tx*SPR_SIZE,sy+ty*SPR_SIZE); }
  }

  // --- Input ---
  const VALID_KEYS = {up:1,down:1,left:1,right:1,a:1,b:1,start:1,select:1};
  function btn(k) {
    if(!VALID_KEYS[k]) console.error("Mono: invalid key \""+k+"\". Use: up/down/left/right/a/b/start/select");
    return !!keys[k];
  }
  function btnp(k) {
    if(!VALID_KEYS[k]) console.error("Mono: invalid key \""+k+"\". Use: up/down/left/right/a/b/start/select");
    return !!keys[k] && !keysPrev[k];
  }

  // --- Debug overlay ---
  function dbg(x, y, w, h) {
    if (debugMode) debugShapes.push({ t: "r", x: Math.floor(x), y: Math.floor(y), w: Math.floor(w), h: Math.floor(h) });
  }
  function dbgC(x, y, r) {
    if (debugMode) debugShapes.push({ t: "c", x: Math.floor(x), y: Math.floor(y), r: Math.floor(r) });
  }
  function dbgPt(x, y) {
    if (debugMode) debugShapes.push({ t: "p", x: Math.floor(x), y: Math.floor(y) });
  }

  // --- Sound (direct, no postMessage) ---
  function notePlay(ch, noteStr, dur) {
    playNote(ch, noteStr, dur);
  }
  function noteStop(ch) {
    stopNote(ch);
  }
  function bgm(tracks, bpm, loop) {
    const arr = [];
    if (Array.isArray(tracks)) {
      for (let i = 0; i < tracks.length; i++) arr.push(tracks[i]);
    } else if (tracks && typeof tracks === 'object') {
      for (let i = 1; ; i++) {
        const t = tracks[i];
        if (t === undefined || t === null) break;
        arr.push(t);
      }
    }
    startBgm(arr, bpm || 120, loop !== false);
  }
  function bgmVolSet(vol) {
    bgmEnsureChannels();
    for (let i = 0; i < 2; i++) bgmGain[i].gain.value = Math.max(0, Math.min(1, vol));
  }

  // --- PRNG (Lehmer / Park-Miller) ---
  let _seed = (Date.now() & 0x7FFFFFFF) || 1;
  function _nextRand() {
    _seed = (_seed * 16807) % 2147483647;
    return (_seed - 1) / 2147483646;
  }
  function rnd(max) { return _nextRand() * max; }
  function seedSet(s) { _seed = (s & 0x7FFFFFFF) || 1; }
  function getSeed() { return _seed; }

  // --- Overlap (AABB) ---
  function overlap(x1,y1,w1,h1, x2,y2,w2,h2) {
    return x1+w1>x2 && x1<x2+w2 && y1+h1>y2 && y1<y2+h2;
  }

  // --- ECS ---
  const entities = [];
  let entityIdCounter = 0;
  const collisionHandlers = [];
  const collisionQueue = [];

  function ecsSpawn(components) {
    const e = Object.assign({ _id: ++entityIdCounter, _alive: true }, components);
    if (e.hitbox && e.hitbox.r !== undefined && e.hitbox.w === undefined) {
      e.hitbox.type = "circle";
    } else if (e.hitbox && e.hitbox.w !== undefined) {
      e.hitbox.type = "rect";
      if (e.hitbox.ox === undefined) e.hitbox.ox = 0;
      if (e.hitbox.oy === undefined) e.hitbox.oy = 0;
    }
    entities.push(e);
    return e;
  }

  function ecsKill(e) {
    if (!e) return;
    const id = e._id;
    if (id) {
      for (let i = 0; i < entities.length; i++) {
        if (entities[i]._id === id) { entities[i]._alive = false; return; }
      }
    }
    if (e._alive !== undefined) e._alive = false;
  }

  function ecsKillAll(group) {
    for (let i = entities.length - 1; i >= 0; i--) {
      if (!group || entities[i].group === group) entities[i]._alive = false;
    }
  }

  function ecsEach(group, fn) {
    for (let i = 0; i < entities.length; i++) {
      const e = entities[i];
      if (e._alive && (!group || e.group === group)) {
        try { fn(e); } catch(err) { console.error("Mono: each() callback error:", err); }
      }
    }
  }

  function ecsCount(group) {
    let n = 0;
    for (let i = 0; i < entities.length; i++) {
      if (entities[i]._alive && (!group || entities[i].group === group)) n++;
    }
    return n;
  }

  function ecsOnCollide(groupA, groupB, tagOrFn) {
    // tagOrFn can be a string tag (poll mode) or a function (callback mode)
    if (typeof tagOrFn === 'function') {
      collisionHandlers.push({ groupA, groupB, callback: tagOrFn, tag: null });
    } else {
      collisionHandlers.push({ groupA, groupB, tag: tagOrFn || (groupA + "_" + groupB), callback: null });
    }
  }
  function ecsClearCollisions() { collisionHandlers.length = 0; collisionQueue.length = 0; }

  function ecsPopCollision() {
    if (collisionQueue.length === 0) return false;
    return collisionQueue.shift();
  }

  function ecsPopAllCollisions(tag) {
    const result = [];
    for (let i = collisionQueue.length - 1; i >= 0; i--) {
      if (!tag || collisionQueue[i].tag === tag) {
        result.push(collisionQueue[i]);
        collisionQueue.splice(i, 1);
      }
    }
    return result;
  }

  function ecsHitbox(e) {
    if (!e.pos || !e.hitbox) return null;
    const hb = e.hitbox;
    if (hb.type === "circle") {
      return { type: "c", cx: e.pos.x + (hb.ox || 0), cy: e.pos.y + (hb.oy || 0), r: hb.r };
    } else {
      const ox = hb.ox || 0, oy = hb.oy || 0;
      return { type: "r", x: e.pos.x + ox, y: e.pos.y + oy, w: hb.w, h: hb.h };
    }
  }

  function ecsOverlap(a, b) {
    if (!a || !b) return false;
    if (a.type === "c" && b.type === "c") {
      const dx = a.cx - b.cx, dy = a.cy - b.cy, dr = a.r + b.r;
      return dx * dx + dy * dy < dr * dr;
    }
    if (a.type === "r" && b.type === "r") {
      return a.x + a.w > b.x && a.x < b.x + b.w && a.y + a.h > b.y && a.y < b.y + b.h;
    }
    const c = a.type === "c" ? a : b;
    const r = a.type === "r" ? a : b;
    const cx = Math.max(r.x, Math.min(c.cx, r.x + r.w));
    const cy = Math.max(r.y, Math.min(c.cy, r.y + r.h));
    const dx = c.cx - cx, dy = c.cy - cy;
    return dx * dx + dy * dy < c.r * c.r;
  }

  function ecsUpdate() {
    for (let i = entities.length - 1; i >= 0; i--) {
      if (!entities[i]._alive) entities.splice(i, 1);
    }
    const margin = SPR_SIZE * 2;
    for (let i = 0; i < entities.length; i++) {
      const e = entities[i];
      if (e._alive && e.offscreen && e.pos) {
        if (e.pos.x < -margin || e.pos.x > W + margin || e.pos.y < -margin || e.pos.y > H + margin) {
          e._alive = false;
        }
      }
    }
    for (let i = 0; i < entities.length; i++) {
      const e = entities[i];
      if (e._alive && e.pos && e.vel) {
        e.pos.x += e.vel.x || 0;
        e.pos.y += e.vel.y || 0;
      }
    }
    for (let i = 0; i < entities.length; i++) {
      const e = entities[i];
      if (e._alive && e.vel && e.gravity) {
        e.vel.y += e.gravity;
      }
    }
    for (let i = 0; i < entities.length; i++) {
      const e = entities[i];
      if (e._alive && e.lifetime !== undefined) {
        e.lifetime--;
        if (e.lifetime <= 0) e._alive = false;
      }
    }
    for (let i = 0; i < entities.length; i++) {
      const e = entities[i];
      if (e._alive && e.anim) {
        e.anim.timer = (e.anim.timer || 0) + 1;
        if (e.anim.timer >= (e.anim.speed || 8)) {
          e.anim.timer = 0;
          e.anim.index = ((e.anim.index || 0) + 1) % e.anim.frames.length;
          e.sprite = e.anim.frames[e.anim.index];
        }
      }
    }
    // Detect collisions
    for (let h = 0; h < collisionHandlers.length; h++) {
      const handler = collisionHandlers[h];
      for (let i = 0; i < entities.length; i++) {
        const a = entities[i];
        if (!a._alive || a.group !== handler.groupA) continue;
        const ha = ecsHitbox(a);
        for (let j = 0; j < entities.length; j++) {
          const b = entities[j];
          if (!b._alive || b.group !== handler.groupB || a === b) continue;
          const hb = ecsHitbox(b);
          if (ecsOverlap(ha, hb)) {
            if (handler.callback) {
              // Callback mode: call directly, do NOT auto-kill
              try { handler.callback(a, b); } catch(err) { console.error("Mono: onCollide callback error:", err); }
            } else {
              // Poll mode: queue collision, auto-kill both
              collisionQueue.push({
                tag: handler.tag,
                aId: a._id, bId: b._id,
                ax: a.pos ? a.pos.x : 0, ay: a.pos ? a.pos.y : 0,
                bx: b.pos ? b.pos.x : 0, by: b.pos ? b.pos.y : 0,
                aGroup: a.group, bGroup: b.group,
              });
              a._alive = false;
              b._alive = false;
            }
          }
        }
      }
    }
  }

  function ecsRender() {
    // Sort by z-order (lower z drawn first = behind)
    // Only sort if any entity has z defined (avoid unnecessary work)
    let needSort = false;
    for (let i = 0; i < entities.length; i++) {
      if (entities[i].z !== undefined) { needSort = true; break; }
    }
    if (needSort) {
      entities.sort((a, b) => (a.z || 0) - (b.z || 0));
    }

    for (let i = 0; i < entities.length; i++) {
      const e = entities[i];
      if (!e._alive || !e.pos) continue;
      // anchor: 0,0=topleft (default), 0.5,0.5=center, 1,1=bottomright
      const ax = e.anchor_x !== undefined ? e.anchor_x : 0;
      const ay = e.anchor_y !== undefined ? e.anchor_y : 0;
      if (e.sprite !== undefined) {
        const drawX = Math.floor(e.pos.x - SPR_SIZE * ax);
        const drawY = Math.floor(e.pos.y - SPR_SIZE * ay);
        const flipX = e.flipX || false, flipY = e.flipY || false;
        sprT(e.sprite, drawX, drawY, flipX, flipY);
      }
      if (e.hitbox) {
        const hb = ecsHitbox(e);
        if (hb) {
          if (hb.type === "c") dbgC(hb.cx, hb.cy, hb.r);
          else dbg(hb.x, hb.y, hb.w, hb.h);
        }
      }
    }
  }

  // --- Tween system ---
  const tweens = [];

  // tween(target, prop, from, to, duration, [ease])
  // target: object (e.g. entity.pos), prop: string key
  // ease: "linear" (default), "in", "out", "inout"
  function tweenAdd(target, prop, from, to, duration, ease) {
    if (!target || !prop) return;
    tweens.push({ target, prop, from, to, duration, elapsed: 0, ease: ease || "linear" });
  }

  function tweenEase(t, ease) {
    if (ease === "in") return t * t;
    if (ease === "out") return 1 - (1 - t) * (1 - t);
    if (ease === "inout") return t < 0.5 ? 2 * t * t : 1 - 2 * (1 - t) * (1 - t);
    return t; // linear
  }

  function tweenUpdate() {
    for (let i = tweens.length - 1; i >= 0; i--) {
      const tw = tweens[i];
      tw.elapsed++;
      const t = Math.min(1, tw.elapsed / tw.duration);
      const v = tw.from + (tw.to - tw.from) * tweenEase(t, tw.ease);
      tw.target[tw.prop] = v;
      if (t >= 1) tweens.splice(i, 1);
    }
  }

  function tweenClear() { tweens.length = 0; }

  // Lua-friendly: tween_to(entity_id, prop_path, to, duration, ease)
  // prop_path: "pos.x", "pos.y", or flat prop name
  function tweenTo(targetId, propPath, to, duration, ease) {
    // Find entity by id
    let target = null;
    for (let i = 0; i < entities.length; i++) {
      if (entities[i]._id === targetId) { target = entities[i]; break; }
    }
    if (!target) return;

    const parts = propPath.split(".");
    let obj = target;
    for (let i = 0; i < parts.length - 1; i++) {
      obj = obj[parts[i]];
      if (!obj) return;
    }
    const prop = parts[parts.length - 1];
    const from = obj[prop] || 0;
    tweenAdd(obj, prop, from, to, duration, ease);
  }

  function ecsClear() {
    entities.length = 0;
    collisionHandlers.length = 0;
    collisionQueue.length = 0;
    tweens.length = 0;
    entityIdCounter = 0;
  }

  // --- Demo Record/Playback ---
  const KEY_BITS = ["up","down","left","right","a","b","start","select"];
  let demoState = "idle";
  let demoRecording = [];
  let demoRecFrame = 0;
  let demoLastBits = 0;
  let demoRecSeed = 1;
  let demoPlaybackData = null;
  let demoPlayIdx = 0;
  let demoPlayFrame = 0;
  let demoPlayBits = 0;
  let gameId = "";

  function getDemoKey() { return "mono_demo_" + gameId; }

  function packKeys() {
    let bits = 0;
    for (let i = 0; i < KEY_BITS.length; i++) if (keys[KEY_BITS[i]]) bits |= (1 << i);
    return bits;
  }

  function unpackKeys(bits) {
    for (let i = 0; i < KEY_BITS.length; i++) keys[KEY_BITS[i]] = !!(bits & (1 << i));
  }

  function notifyParent(event, data) {
    if (window.parent !== window) {
      window.parent.postMessage({ type: "mono", event, ...data }, "*");
    }
  }

  function demoRec() {
    demoState = "recording";
    demoRecording = [];
    demoRecFrame = 0;
    demoLastBits = 0;
    demoRecSeed = _seed;
    frameCount = 0;
    notifyParent("state", { state: "recording" });
  }

  function demoPlay(savedDemo) {
    if (!savedDemo) return false;
    demoPlaybackData = savedDemo.actions;
    demoState = "playback";
    demoPlayIdx = 0;
    demoPlayFrame = 0;
    demoPlayBits = 0;
    frameCount = 0;
    _seed = savedDemo.seed || 1;
    for (const k of KEY_BITS) { keys[k] = false; keysPrev[k] = false; }
    if (scenes["title"]) {
      currentSceneName = "title";
      currentScene = scenes["title"];
      if (currentScene.init) currentScene.init();
    }
    notifyParent("state", { state: "playback" });
    return true;
  }

  function demoStop() {
    demoState = "idle";
    demoPlaybackData = null;
    notifyParent("state", { state: "idle" });
  }

  function demoSave() {
    if (demoState === "recording" && demoRecording.length >= 1) {
      demoRecording.push([demoRecFrame, 0]);
      try {
        localStorage.setItem(getDemoKey(), JSON.stringify({ seed: demoRecSeed, actions: demoRecording }));
      } catch(e) {}
    }
    demoStop();
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

  // --- Overlay text helpers ---
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
    for (let by = py - 3; by < py + FONT_H + 3; by++)
      for (let bx = px - 4; bx < px + pw + 4; bx++)
        if (bx >= 0 && bx < W && by >= 0 && by < H) buf32[by * W + bx] = COLOR_U32[0];
    const blink = frameCount % 30 < 20;
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

  // --- Debug overlays ---
  function blendPixel(idx, r, g, b, a) {
    // Alpha blend onto buf32 (ABGR format)
    const dst = buf32[idx];
    const dr = dst & 0xFF;
    const dg = (dst >> 8) & 0xFF;
    const db = (dst >> 16) & 0xFF;
    const inv = 1 - a;
    const or_ = Math.floor(dr * inv + r * a);
    const og = Math.floor(dg * inv + g * a);
    const ob = Math.floor(db * inv + b * a);
    buf32[idx] = 0xFF000000 | (ob << 16) | (og << 8) | or_;
  }

  function debugPix(x, y, r, g, b, a) {
    if (x >= 0 && x < W && y >= 0 && y < H) blendPixel(y * W + x, r, g, b, a);
  }

  function drawDebugOverlays() {
    let labelX = 2;

    // Draw order: 1 → 2 → 3

    // Collision overlay (key 1) — green, 70% alpha, 2px thick
    if (debugMode) {
      const cr = 0, cg = 255, cb = 0, ca = 0.7;
      const TH = 2;
      for (const s of debugShapes) {
        if (s.t === "r") {
          for (let t = 0; t < TH; t++) {
            for (let px = s.x; px < s.x + s.w; px++) {
              debugPix(px, s.y + t, cr, cg, cb, ca);
              debugPix(px, s.y + s.h - 1 - t, cr, cg, cb, ca);
            }
            for (let py = s.y; py < s.y + s.h; py++) {
              debugPix(s.x + t, py, cr, cg, cb, ca);
              debugPix(s.x + s.w - 1 - t, py, cr, cg, cb, ca);
            }
          }
        } else if (s.t === "c") {
          for (let ri = 0; ri < TH; ri++) {
            const r = Math.max(0, s.r - ri);
            let cx = r, cy = 0, d = 1 - r;
            while (cx >= cy) {
              debugPix(s.x+cx,s.y+cy,cr,cg,cb,ca); debugPix(s.x-cx,s.y+cy,cr,cg,cb,ca);
              debugPix(s.x+cx,s.y-cy,cr,cg,cb,ca); debugPix(s.x-cx,s.y-cy,cr,cg,cb,ca);
              debugPix(s.x+cy,s.y+cx,cr,cg,cb,ca); debugPix(s.x-cy,s.y+cx,cr,cg,cb,ca);
              debugPix(s.x+cy,s.y-cx,cr,cg,cb,ca); debugPix(s.x-cy,s.y-cx,cr,cg,cb,ca);
              cy++;
              if (d < 0) { d += 2 * cy + 1; } else { cx--; d += 2 * (cy - cx) + 1; }
            }
          }
        } else if (s.t === "p") {
          for (let d = -2; d <= 2; d++) {
            debugPix(s.x+d, s.y, cr, cg, cb, ca);
            debugPix(s.x, s.y+d, cr, cg, cb, ca);
          }
        }
      }
      labelX = drawDebugLabel("1:HITBOX", labelX, 0xFF00FF00) + 6;
    }

    // Sprite bounding box overlay (key 2) — magenta, 70% alpha
    if (debugSprite) {
      const sr = 255, sg = 0, sb = 255, sa = 0.7;
      for (const s of debugSprBoxes) {
        const sw = s.w || SPR_SIZE, sh = s.h || SPR_SIZE;
        for (let px = s.x; px < s.x + sw; px++) {
          debugPix(px, s.y, sr, sg, sb, sa);
          debugPix(px, s.y + sh - 1, sr, sg, sb, sa);
        }
        for (let py = s.y; py < s.y + sh; py++) {
          debugPix(s.x, py, sr, sg, sb, sa);
          debugPix(s.x + sw - 1, py, sr, sg, sb, sa);
        }
      }
      labelX = drawDebugLabel("2:SPRITE", labelX, 0xFFFF00FF) + 6;
    }

    // Fill overlay (key 3) — orange, 70% alpha
    if (debugFill) {
      const fr = 255, fg = 136, fb = 0, fa = 0.7;
      for (const s of debugFillBoxes) {
        if (s.t === "r") {
          for (let px = s.x; px < s.x + s.w; px++) {
            debugPix(px, s.y, fr, fg, fb, fa);
            debugPix(px, s.y + s.h - 1, fr, fg, fb, fa);
          }
          for (let py = s.y; py < s.y + s.h; py++) {
            debugPix(s.x, py, fr, fg, fb, fa);
            debugPix(s.x + s.w - 1, py, fr, fg, fb, fa);
          }
        } else if (s.t === "c") {
          let cx = s.r, cy = 0, d = 1 - s.r;
          while (cx >= cy) {
            debugPix(s.x+cx,s.y+cy,fr,fg,fb,fa); debugPix(s.x-cx,s.y+cy,fr,fg,fb,fa);
            debugPix(s.x+cx,s.y-cy,fr,fg,fb,fa); debugPix(s.x-cx,s.y-cy,fr,fg,fb,fa);
            debugPix(s.x+cy,s.y+cx,fr,fg,fb,fa); debugPix(s.x-cy,s.y+cx,fr,fg,fb,fa);
            debugPix(s.x+cy,s.y-cx,fr,fg,fb,fa); debugPix(s.x-cy,s.y-cx,fr,fg,fb,fa);
            cy++;
            if (d < 0) { d += 2 * cy + 1; } else { cx--; d += 2 * (cy - cx) + 1; }
          }
        }
      }
      labelX = drawDebugLabel("3:FILL", labelX, 0xFF0088FF) + 6;
    }

  }

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

  // --- Declarative Game Table ---
  let spriteIdCounter = 1;
  const spriteNames = {};
  let _stateLayout = {};

  function parseVisualSprites(spritesTable) {
    for (const [name, data] of spritesTable) {
      const pixels = parseVisualSprite(data);
      sprites[spriteIdCounter] = pixels;
      spriteNames[name] = spriteIdCounter;
      spriteIdCounter++;
    }
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
    _stateLayout = layout;
    lua.doString(`
      S = setmetatable({}, {
        __index = function(_, k) return S_get(k) end,
        __newindex = function(_, k, v) S_set(k, v) end,
      })
    `);
  }

  function registerSounds(soundsTable) {
    for (const [name, def] of soundsTable) {
      const sfxName = 'sfx_' + name;
      if (typeof def === 'object') {
        const n = def.note || def[1];
        const d = def.dur || def[2] || 0.1;
        const ch = def.ch || def[3] || 0;
        lua.doString("function " + sfxName + "() note(" + ch + ", \"" + n + "\", " + d + ") end");
      }
    }
  }

  function parseGameTable() {
    let gameTable;
    try { gameTable = lua.global.get("game"); } catch(e) { return; }
    if (!gameTable) return;
    const spritesT = gameTable.sprites || gameTable['sprites'];
    if (spritesT) parseVisualSprites(Object.entries(spritesT));
    const stateT = gameTable.state || gameTable['state'];
    if (stateT) buildStateAccessors(Object.entries(stateT));
    const soundsT = gameTable.sounds || gameTable['sounds'];
    if (soundsT) registerSounds(Object.entries(soundsT));
  }

  // --- Scene auto-detection (SYNCHRONOUS) ---
  function luaIsFunction(name) {
    try {
      lua.doString("_mono_tmp = type(" + name + ")");
      return lua.global.get("_mono_tmp") === "function";
    } catch(e) { return false; }
  }

  function autoDetectScenes() {
    for (const name of VALID_SCENES) {
      const hasInit = luaIsFunction(name + "_init");
      const hasUpdate = luaIsFunction(name + "_update");
      const hasDraw = luaIsFunction(name + "_draw");
      if (hasUpdate || hasDraw) {
        scenes[name] = {
          init: hasInit ? () => { try { lua.doString(name + "_init()"); } catch(e) { if(!window._merr)window._merr=[]; window._merr.push("init["+name+"]:"+e.message); } } : null,
          update: hasUpdate ? () => { try { lua.doString(name + "_update()"); } catch(e) { if(!window._merr)window._merr=[]; if(window._merr.length<100)window._merr.push("upd["+name+"]:"+e.message); } } : null,
          draw: hasDraw ? () => { try { lua.doString(name + "_draw()"); } catch(e) { if(!window._merr)window._merr=[]; if(window._merr.length<100)window._merr.push("draw["+name+"]:"+e.message); } } : null,
        };
      }
    }
  }

  // --- Game Loop ---
  function stepInput() {
    if (demoState === "recording") {
      const bits = packKeys();
      if (bits !== demoLastBits) {
        demoRecording.push([demoRecFrame, bits]);
        demoLastBits = bits;
      }
      demoRecFrame++;
    }

    if (demoState === "playback") {
      while (demoPlayIdx < demoPlaybackData.length &&
             demoPlaybackData[demoPlayIdx][0] <= demoPlayFrame) {
        demoPlayBits = demoPlaybackData[demoPlayIdx][1];
        demoPlayIdx++;
      }
      const realBits = packKeys();
      const merged = demoPlayBits | realBits;
      unpackKeys(merged);
      demoPlayFrame++;
      if (demoPlayIdx >= demoPlaybackData.length &&
          demoPlayFrame > (demoPlaybackData.length > 0 ? demoPlaybackData[demoPlaybackData.length-1][0] : 0) + 30) {
        demoStop();
      }
    }

    if (keys["select"] && !keysPrev["select"] && currentSceneName === "play") {
      paused = !paused;
    }
  }

  function stepUpdate() {
    if (paused) return;
    bgmTick();
    if (currentScene && currentScene.update) {
      currentScene.update();
    }
    ecsUpdate();
    tweenUpdate();
  }

  function stepRender() {
    camUpdateFrame();
    if (currentScene && currentScene.draw) {
      currentScene.draw();
    }
    ecsRender();

    if (paused) drawPauseOverlay();

    if (demoState === "playback") {
      drawOverlayText("DEMO", W - 26, 2, frameCount % 40 < 20 ? 3 : 2);
    }
    if (demoState === "recording") {
      drawOverlayText("REC", W - 20, 2, frameCount % 30 < 20 ? 3 : 1);
    }

    // Debug overlays
    drawDebugOverlays();

    debugShapes.length = 0;
    debugSprBoxes.length = 0;
    debugFillBoxes.length = 0;
  }

  function tick() {
    for (let s = 0; s < speed; s++) {
      stepInput();
      stepUpdate();
      frameCount++;
      API.frame = frameCount;
      for (const k in keys) keysPrev[k] = keys[k];
    }
    stepRender();
    ctx.putImageData(buf, 0, 0);
  }

  // --- Build Lua globals ---
  function buildLuaGlobals() {
    return {
      cls: (c) => cls(c || 0),
      pix, line, rect, rectf, circ, circf,
      spr, sprT, sprRot, sprScale, gpix, draw: drawSprite,
      text: drawText,
      mget, mset, map: mapDraw,
      btn, btnp,
      note: notePlay,
      sfx_stop: noteStop,
      bgm, bgm_stop: stopBgm,
      bgm_vol: bgmVolSet,
      go: (name) => {
        sceneGo(name);
        const sc = scenes[name];
        if (sc && sc.init) sc.init();
      },
      scene_name: () => currentSceneName,
      rnd, flr: Math.floor, abs: Math.abs, seed: seedSet,
      dbg, dbgC, dbgPt,
      cam: camSet, cam_get: camGet, cam_shake: camShakeSet, cam_reset: camReset,
      tween: tweenTo, tween_clear: tweenClear,
      frame: () => frameCount,
      overlap,
      _spawnRaw: (group, px, py, vx, vy, sprId, hbType, hbA, hbB, hbC, hbD, grav, life, offscr, anchorX, anchorY, extra) => {
        const obj = { group: group };
        if (px !== undefined && px !== null) obj.pos = { x: px, y: py || 0 };
        if (vx !== undefined && vx !== null) obj.vel = { x: vx, y: vy || 0 };
        if (sprId !== undefined && sprId !== null && sprId > 0) obj.sprite = sprId;
        if (hbType === "r") obj.hitbox = { w: hbA, h: hbB, ox: hbC || 0, oy: hbD || 0 };
        else if (hbType === "c") obj.hitbox = { r: hbA, ox: hbB || 0, oy: hbC || 0 };
        if (grav) obj.gravity = grav;
        if (life) obj.lifetime = life;
        if (offscr) obj.offscreen = true;
        if (anchorX) obj.anchor_x = anchorX;
        if (anchorY) obj.anchor_y = anchorY;
        if (extra) {
          try {
            const ex = JSON.parse(extra);
            for (const k in ex) obj[k] = ex[k];
          } catch(e) {}
        }
        return ecsSpawn(obj);
      },
      kill: ecsKill,
      killAll: ecsKillAll,
      each: (group, fn) => ecsEach(group, fn),
      ecount: ecsCount,
      onCollide: (a, b, tagOrFn) => ecsOnCollide(a, b, tagOrFn),
      pollCollision: ecsPopCollision,
      clearCollisions: ecsClearCollisions,
      defSprite: (id, data) => {
        if (typeof data === 'string' && data.includes('\n')) {
          sprites[id] = parseVisualSprite(data);
        } else {
          spriteDefine(id, data);
        }
      },
      peek: (addr) => ram[addr & 0xFFF],
      poke: (addr, val) => { ram[addr & 0xFFF] = val & 0xFF; },
      peek16: (addr) => { const a = addr & 0xFFF; return ram[a] | (ram[a+1] << 8); },
      poke16: (addr, val) => { const a = addr & 0xFFF; ram[a] = val & 0xFF; ram[a+1] = (val >> 8) & 0xFF; },
      sprite_id: (name) => spriteNames[name] || 0,
      S_get: (name) => {
        const l = _stateLayout[name]; if (!l) return 0;
        if (l.type === 'u8') return ram[l.offset];
        if (l.type === 'u16') return ram[l.offset] | (ram[l.offset+1] << 8);
        if (l.type === 'i8') { const v = ram[l.offset]; return v > 127 ? v - 256 : v; }
        if (l.type === 'i16') { const v = ram[l.offset] | (ram[l.offset+1] << 8); return v > 32767 ? v - 65536 : v; }
        if (l.type === 'u32') return ram[l.offset] | (ram[l.offset+1] << 8) | (ram[l.offset+2] << 16) | (ram[l.offset+3] << 24);
        if (l.type === 'i32') { const v = ram[l.offset] | (ram[l.offset+1] << 8) | (ram[l.offset+2] << 16) | (ram[l.offset+3] << 24); return v; }
        return 0;
      },
      S_set: (name, val) => {
        const l = _stateLayout[name]; if (!l) return;
        if (l.type === 'u8' || l.type === 'i8') { ram[l.offset] = val & 0xFF; }
        else if (l.type === 'u16' || l.type === 'i16') { ram[l.offset] = val & 0xFF; ram[l.offset+1] = (val >> 8) & 0xFF; }
        else if (l.type === 'u32' || l.type === 'i32') { ram[l.offset] = val & 0xFF; ram[l.offset+1] = (val >> 8) & 0xFF; ram[l.offset+2] = (val >> 16) & 0xFF; ram[l.offset+3] = (val >> 24) & 0xFF; }
      },
      print: (...args) => console.log("[Lua]", ...args),
    };
  }

  // Lua-side spawn wrapper code (injected after boot)
  const SPAWN_WRAPPER_LUA = `
    function spawn(t)
      local hbType, hbA, hbB, hbC, hbD = nil, nil, nil, nil, nil
      if t.hitbox then
        if t.hitbox.r then
          hbType = "c"
          hbA = t.hitbox.r
          hbB = t.hitbox.ox
          hbC = t.hitbox.oy
        else
          hbType = "r"
          hbA = t.hitbox.w
          hbB = t.hitbox.h
          hbC = t.hitbox.ox
          hbD = t.hitbox.oy
        end
      end
      local px, py = nil, nil
      if t.pos then px = t.pos.x; py = t.pos.y end
      local vx, vy = nil, nil
      if t.vel then vx = t.vel.x; vy = t.vel.y end
      local extra = nil
      local customs = {}
      local known = {group=1,pos=1,vel=1,sprite=1,hitbox=1,gravity=1,lifetime=1,offscreen=1}
      for k, v in pairs(t) do
        if not known[k] then
          if type(v) == "boolean" then customs[k] = v
          elseif type(v) == "number" then customs[k] = v
          elseif type(v) == "string" then customs[k] = v
          end
        end
      end
      local parts = {}
      for k, v in pairs(customs) do
        if type(v) == "string" then
          table.insert(parts, '"' .. k .. '":"' .. v .. '"')
        elseif type(v) == "boolean" then
          table.insert(parts, '"' .. k .. '":' .. tostring(v))
        else
          table.insert(parts, '"' .. k .. '":' .. tostring(v))
        end
      end
      if #parts > 0 then extra = "{" .. table.concat(parts, ",") .. "}" end
      return _spawnRaw(t.group, px, py, vx, vy, t.sprite, hbType, hbA, hbB, hbC, hbD, t.gravity, t.lifetime, t.offscreen, t.anchor_x, t.anchor_y, extra)
    end
  `;

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
      if (e.key === "1") { debugMode = !debugMode; e.preventDefault(); return; }
      if (e.key === "2") { debugSprite = !debugSprite; e.preventDefault(); return; }
      if (e.key === "3") { debugFill = !debugFill; e.preventDefault(); return; }
      const k = keyMap[e.key];
      if (k) { keys[k] = true; e.preventDefault(); }
    });
    document.addEventListener("keyup", e => {
      const k = keyMap[e.key];
      if (k) { keys[k] = false; e.preventDefault(); }
    });
    document.addEventListener("keydown", ensureAudio, { once: true });
    document.addEventListener("click", ensureAudio, { once: true });

    // postMessage IPC (from parent iframe -- demo controls)
    window.addEventListener("message", (e) => {
      if (e.data && e.data.type === "mono") {
        switch(e.data.cmd) {
          case "rec": demoRec(); break;
          case "play": {
            const savedDemo = loadDemoFromStorage();
            if (savedDemo) demoPlay(savedDemo);
            break;
          }
          case "stop": demoStop(); break;
          case "save": demoSave(); break;
        }
      }
    });

    // --- Boot Wasmoon + game ---
    if (opts && opts.game) {
      // Fetch game source
      const gameSrc = await fetch(opts.game).then(r => r.text());

      // Load Wasmoon via dynamic import from CDN
      const { LuaFactory } = await import('https://cdn.jsdelivr.net/npm/wasmoon@1.16.0/+esm');
      const factory = new LuaFactory();
      lua = await factory.createEngine();

      // Expose all JS globals to Lua
      const globals = buildLuaGlobals();
      for (const [name, fn] of Object.entries(globals)) {
        lua.global.set(name, fn);
      }

      // Inject Lua-side spawn wrapper
      try { lua.doString(SPAWN_WRAPPER_LUA); } catch(e) { console.error("Mono: spawn wrapper error:", e); }

      // Run the game source
      try { lua.doString(gameSrc); } catch(e) { console.error("Mono: Lua script error:", e); }

      // Parse game table (declarative API)
      parseGameTable();

      // Auto-detect scenes
      autoDetectScenes();

      // Start first scene
      if (scenes["title"]) {
        sceneGo("title");
        const sc = scenes["title"];
        if (sc && sc.init) sc.init();
      }

      // Start game loop
      setInterval(tick, FRAME_MS);
    }
  };

  // Low-level access
  API._COLOR_U32 = COLOR_U32;
  Object.defineProperty(API, '_buf32', { get() { return buf32; } });
  Object.defineProperty(API, 'spriteSize', { get() { return SPR_SIZE; } });

  return API;
})();
