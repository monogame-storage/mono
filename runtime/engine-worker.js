/**
 * Mono Engine Worker — Luau VM + game loop + rendering
 *
 * Runs in a Web Worker. Owns: Luau VM, frame buffer, ECS,
 * sprites, tilemap, PRNG, scene management, demo record/playback.
 * Sends frame buffers + audio commands to main thread via postMessage.
 */

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

// Frame buffer (no ImageData in workers, just raw Uint32Array)
let buf32 = new Uint32Array(W * H);

const sprites = {};
const tilemap = {};

// --- Input state (received from main thread) ---
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

// --- API (internal, not exposed to outside — used by Lua bindings) ---
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

function sceneGo(name, opts) {
  if (VALID_SCENES.indexOf(name) === -1) {
    console.warn('Mono: invalid scene "' + name + '"');
    return;
  }
  // Notify main thread to stop BGM
  postMessage({ type: "audio", cmd: "bgmStop" });
  paused = false;
  camReset();
  ecsClear();
  currentSceneName = name;
  currentScene = scenes[name] || null;
  postMessage({ type: "scene", name: name });
  // init is called by the caller (async)
}

// --- Camera ---
let camX = 0, camY = 0;
let camShake = 0;
let camOX = 0, camOY = 0; // per-frame offset (computed once)

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
  const dx=Math.abs(x1-x0), dy=Math.abs(y1-y0);
  const sx=x0<x1?1:-1, sy=y0<y1?1:-1;
  let err=dx-dy;
  while(true) {
    pix(x0,y0,c);
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
  while(x>=y){
    pix(cx+x,cy+y,c);pix(cx-x,cy+y,c);
    pix(cx+x,cy-y,c);pix(cx-x,cy-y,c);
    pix(cx+y,cy+x,c);pix(cx-y,cy+x,c);
    pix(cx+y,cy-x,c);pix(cx-y,cy-x,c);
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

// Sprites
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
  if(debugSprite) debugSprBoxes.push({x:x,y:y});
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
  if(debugSprite) debugSprBoxes.push({x:x,y:y});
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
  if (debugSprite) debugSprBoxes.push({x: cx - Math.floor(scaledHalf), y: cy - Math.floor(scaledHalf)});
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
  if(debugSprite) debugSprBoxes.push({x:Math.floor(cx+camOX)-Math.floor(SS/2),y:Math.floor(cy+camOY)-Math.floor(SS/2)});
}
function gpix(x, y) {
  x = Math.floor(x); y = Math.floor(y);
  if (x < 0 || x >= W || y < 0 || y >= H) return -1;
  const v = buf32[y * W + x];
  for (let i = 0; i < 4; i++) if (COLOR_U32[i] === v) return i;
  return -1;
}

// Text
function text(str, x, y, c) {
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

// Tilemap
function mget(cx,cy) { return tilemap[cx+","+cy]||0; }
function mset(cx,cy,id) { tilemap[cx+","+cy]=id; }
function mapDraw(mx,my,mw,mh,sx,sy) {
  for(let ty=0;ty<mh;ty++) for(let tx=0;tx<mw;tx++){
    const id=mget(mx+tx,my+ty); if(id>0) spr(id,sx+tx*SPR_SIZE,sy+ty*SPR_SIZE); }
}

// Input
const VALID_KEYS = {up:1,down:1,left:1,right:1,a:1,b:1,start:1,select:1};
function btn(k) {
  if(!VALID_KEYS[k]) console.warn("Mono: invalid key \""+k+"\". Use: up/down/left/right/a/b/start/select");
  return !!keys[k];
}
function btnp(k) {
  if(!VALID_KEYS[k]) console.warn("Mono: invalid key \""+k+"\". Use: up/down/left/right/a/b/start/select");
  return !!keys[k] && !keysPrev[k];
}

// Debug overlay
function dbg(x, y, w, h) {
  if (debugMode) debugShapes.push({ t: "r", x: Math.floor(x), y: Math.floor(y), w: Math.floor(w), h: Math.floor(h) });
}
function dbgC(x, y, r) {
  if (debugMode) debugShapes.push({ t: "c", x: Math.floor(x), y: Math.floor(y), r: Math.floor(r) });
}
function dbgPt(x, y) {
  if (debugMode) debugShapes.push({ t: "p", x: Math.floor(x), y: Math.floor(y) });
}

// Sound (proxy to main thread)
function notePlay(ch, noteStr, dur) {
  postMessage({ type: "audio", cmd: "note", ch: ch, note: noteStr, dur: dur });
}
function noteStop(ch) {
  if (ch === undefined) { noteStop(0); noteStop(1); return; }
  postMessage({ type: "audio", cmd: "noteStop", ch: ch });
}
function bgm(tracks, bpm, loop) {
  // tracks comes as Luau table — normalize to array of strings
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
  postMessage({ type: "audio", cmd: "bgm", tracks: arr, bpm: bpm || 120, loop: loop !== false });
}
function bgmStop() {
  postMessage({ type: "audio", cmd: "bgmStop" });
}
function bgmVol(vol) {
  postMessage({ type: "audio", cmd: "bgmVol", vol: vol });
}

// Seeded PRNG (Lehmer / Park-Miller)
let _seed = (Date.now() & 0x7FFFFFFF) || 1;
function _nextRand() {
  _seed = (_seed * 16807) % 2147483647;
  return (_seed - 1) / 2147483646;
}
function rnd(max) { return _nextRand() * max; }
function seedSet(s) { _seed = (s & 0x7FFFFFFF) || 1; }
function getSeed() { return _seed; }

// Collision helper (AABB overlap)
function overlap(x1,y1,w1,h1, x2,y2,w2,h2) {
  return x1+w1>x2 && x1<x2+w2 && y1+h1>y2 && y1<y2+h2;
}

// --- ECS ---
const entities = [];
let entityIdCounter = 0;
const collisionHandlers = [];

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

function ecsKill(e) { if (e) e._alive = false; }

function ecsKillAll(group) {
  for (let i = entities.length - 1; i >= 0; i--) {
    if (!group || entities[i].group === group) entities[i]._alive = false;
  }
}

function ecsEach(group, fn) {
  for (let i = 0; i < entities.length; i++) {
    const e = entities[i];
    if (e._alive && (!group || e.group === group)) fn(e);
  }
}

function ecsCount(group) {
  let n = 0;
  for (let i = 0; i < entities.length; i++) {
    if (entities[i]._alive && (!group || entities[i].group === group)) n++;
  }
  return n;
}

function ecsOnCollide(groupA, groupB, fn) {
  collisionHandlers.push({ groupA, groupB, fn });
}
function ecsClearCollisions() { collisionHandlers.length = 0; }

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
          handler.fn(a, b);
        }
      }
    }
  }
}

function ecsRender() {
  for (let i = 0; i < entities.length; i++) {
    const e = entities[i];
    if (!e._alive || !e.pos) continue;
    if (e.sprite !== undefined) {
      const x = Math.floor(e.pos.x), y = Math.floor(e.pos.y);
      const flipX = e.flipX || false, flipY = e.flipY || false;
      sprT(e.sprite, x, y, flipX, flipY);
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

function ecsClear() {
  entities.length = 0;
  collisionHandlers.length = 0;
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
  postMessage({ type: "parentNotify", event, ...data });
}

function demoRec() {
  demoState = "recording";
  demoRecording = [];
  demoRecFrame = 0;
  demoLastBits = 0;
  demoRecSeed = _seed;
  frameCount = 0;
  notifyParent("state", { state: "recording" });
  postMessage({ type: "demo", state: "recording" });
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
  postMessage({ type: "demo", state: "playback" });
  return true;
}

function demoStop() {
  demoState = "idle";
  demoPlaybackData = null;
  notifyParent("state", { state: "idle" });
  postMessage({ type: "demo", state: "idle" });
}

function demoSave() {
  if (demoState === "recording" && demoRecording.length >= 1) {
    demoRecording.push([demoRecFrame, 0]);
    // Send recording data to main thread for localStorage save
    postMessage({ type: "demoSave", key: getDemoKey(), data: JSON.stringify({ seed: demoRecSeed, actions: demoRecording }) });
  }
  demoStop();
}

// --- Overlay text helpers (drawn into buf32, used for DEMO/REC/PAUSE indicators) ---
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

async function buildStateAccessors(stateTable) {
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
  await luauExec(`
    S = setmetatable({}, {
      __index = function(_, k) return S_get(k) end,
      __newindex = function(_, k, v) S_set(k, v) end,
    })
  `, "S_proxy");
}

async function registerSounds(soundsTable) {
  for (const [name, def] of soundsTable) {
    const sfxName = 'sfx_' + name;
    if (typeof def === 'object') {
      const n = def.note || def[1];
      const d = def.dur || def[2] || 0.1;
      const ch = def.ch || def[3] || 0;
      await luauExec("function " + sfxName + "() note(" + ch + ", \"" + n + "\", " + d + ") end", sfxName);
    }
  }
}

async function parseGameTable() {
  const gameTable = await luauGet('game');
  // postMessage({type:"log", msg:"gameTable: " + typeof gameTable});
  if (!gameTable) return;
  const spritesT = gameTable.sprites || gameTable['sprites'];
  postMessage({type:"log", msg:"spritesT: " + typeof spritesT + " keys:" + JSON.stringify(spritesT && Object.keys(spritesT))});
  if (spritesT) parseVisualSprites(Object.entries(spritesT));
  const stateT = gameTable.state || gameTable['state'];
  if (stateT) await buildStateAccessors(Object.entries(stateT));
  const soundsT = gameTable.sounds || gameTable['sounds'];
  if (soundsT) await registerSounds(Object.entries(soundsT));
}

// --- Luau VM ---
let luau = null;

async function luauGet(name) {
  try {
    const result = await luau.loadstring("return " + name, "get")();
    return Array.isArray(result) ? result[0] : result;
  } catch(e) { return undefined; }
}

async function luauExec(code, chunkName) {
  await luau.loadstring(code, chunkName || "chunk")();
}

function buildLuaGlobals() {
  return {
    cls: (c) => cls(c || 0),
    pix, line, rect, rectf, circ, circf,
    spr, sprT, sprRot, sprScale, gpix,
    text,
    mget, mset, map: mapDraw,
    btn, btnp,
    note: notePlay,
    sfx_stop: noteStop,
    bgm, bgm_stop: bgmStop,
    go: (name) => {
      sceneGo(name);
      // Return a value; the async init is handled in the game loop
      // We need to call init immediately for scene transitions
      const sc = scenes[name];
      if (sc && sc.init) return sc.init();
    },
    scene_name: () => currentSceneName,
    rnd, flr: Math.floor, abs: Math.abs, seed: seedSet,
    dbg, dbgC, dbgPt,
    cam: camSet, cam_get: camGet, cam_shake: camShakeSet, cam_reset: camReset,
    frame: () => frameCount,
    overlap,
    spawn: (components) => {
      // Deep clone luau proxy → plain JS object
      let obj;
      try {
        obj = JSON.parse(JSON.stringify(components));
      } catch(e) {
        obj = {};
        try {
          for (const k in components) {
            const v = components[k];
            if (v && typeof v === 'object') {
              const inner = {};
              for (const ik in v) inner[ik] = v[ik];
              obj[k] = inner;
            } else {
              obj[k] = v;
            }
          }
        } catch(e2) { /* fallback failed */ }
      }
      return ecsSpawn(obj);
    },
    kill: ecsKill,
    killAll: ecsKillAll,
    each: (group, fn) => ecsEach(group, fn),
    ecount: ecsCount,
    onCollide: ecsOnCollide,
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
    print: (...args) => console.log("[Luau]", ...args),
  };
}

// --- Scene auto-detection ---
async function autoDetectScenes() {
  for (const name of VALID_SCENES) {
    const hasInit = (await luauGet("type(" + name + "_init)")) === "function";
    const hasUpdate = (await luauGet("type(" + name + "_update)")) === "function";
    const hasDraw = (await luauGet("type(" + name + "_draw)")) === "function";
    if (hasUpdate || hasDraw) {
      scenes[name] = {
        init: hasInit ? async () => { try { await luau.loadstring(name + "_init()", name + "_init")(); } catch(e) { postMessage({type:"log", msg:"init err: " + e.message}); } } : null,
        update: hasUpdate ? async () => { try { await luau.loadstring(name + "_update()", name + "_update")(); } catch(e) { postMessage({type:"log", msg:"update err[" + name + "]: " + e.message}); } } : null,
        draw: hasDraw ? async () => { try { await luau.loadstring(name + "_draw()", name + "_draw")(); } catch(e) { postMessage({type:"log", msg:"draw err[" + name + "]: " + e.message}); } } : null,
      };
    }
  }
}

// --- Game Loop (setInterval, async-friendly) ---
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

  // NOTE: title→play auto-transition removed. Games handle start button themselves.

  if (keys["select"] && !keysPrev["select"] && currentSceneName === "play") {
    paused = !paused;
  }
  // NOTE: keysPrev updated at END of frame (after stepUpdate + stepRender)
}

async function stepUpdate() {
  if (paused) return;
  // BGM ticking is done on the main thread now (it owns AudioContext)
  if (currentScene && currentScene.update) {
    try { await currentScene.update(); } catch(e) { postMessage({type:"log", msg:"update err: " + e.message}); }
  }
  ecsUpdate();
}

async function stepRender() {
  camUpdateFrame();
  if (currentScene && currentScene.draw) {
    try { await currentScene.draw(); } catch(e) { postMessage({type:"log", msg:"draw err: " + e.message}); }
  }
  ecsRender();

  if (paused) drawPauseOverlay();

  if (demoState === "playback") {
    drawOverlayText("DEMO", W - 26, 2, frameCount % 40 < 20 ? 3 : 2);
  }
  if (demoState === "recording") {
    drawOverlayText("REC", W - 20, 2, frameCount % 30 < 20 ? 3 : 1);
  }

  // Send frame to main thread (debug overlays drawn on main thread)
  const copy = new Uint32Array(buf32);
  postMessage({
    type: "frame",
    buffer: copy.buffer,
    frame: frameCount,
    debugShapes: debugShapes.length > 0 ? debugShapes.slice() : null,
    debugSprBoxes: debugSprBoxes.length > 0 ? debugSprBoxes.slice() : null,
    debugFillBoxes: debugFillBoxes.length > 0 ? debugFillBoxes.slice() : null,
  }, [copy.buffer]);

  debugShapes.length = 0;
  debugSprBoxes.length = 0;
  debugFillBoxes.length = 0;
}

let loopRunning = false;

async function gameLoop() {
  if (loopRunning) return;
  loopRunning = true;

  while (loopRunning) {
    const t0 = performance.now();

    for (let s = 0; s < speed; s++) {
      stepInput();
      await stepUpdate();
      frameCount++;
      // Update keysPrev AFTER update so btnp() works in Lua
      for (const k in keys) keysPrev[k] = keys[k];
    }
    await stepRender();

    const elapsed = performance.now() - t0;
    const wait = Math.max(0, FRAME_MS - elapsed);
    if (wait > 0) {
      await new Promise(r => setTimeout(r, wait));
    }
  }
}

// --- Message handler (from main thread) ---
self.onmessage = async function(e) {
  const msg = e.data;
  if (!msg || !msg.type) return;

  switch (msg.type) {
    case "boot": {
      if (msg.spriteSize) SPR_SIZE = msg.spriteSize;
      if (msg.gameId) gameId = msg.gameId;

      // Import luau-web inside the worker
      const mod = await import(msg.luauWebUrl);
      const LuauState = mod.LuauState;
      luau = await LuauState.createAsync(buildLuaGlobals());

      // Run the game source
      try {
        await luau.loadstring(msg.gameSrc, msg.game)();
      } catch(e) {
        console.error("Mono: Luau script error:", e);
      }

      // Parse game table
      await parseGameTable();

      // Auto-detect scenes
      await autoDetectScenes();

      // Start first scene
      if (scenes["title"]) {
        sceneGo("title");
        const sc = scenes["title"];
        if (sc && sc.init) await sc.init();
      }

      postMessage({ type: "ready" });

      // Start the game loop
      gameLoop();
      break;
    }

    case "input": {
      // Update key state from main thread
      const k = msg.keys;
      for (const key in k) {
        keys[key] = k[key];
      }
      break;
    }

    case "debug": {
      if (msg.key === "debugMode") debugMode = msg.value;
      if (msg.key === "debugSprite") debugSprite = msg.value;
      if (msg.key === "debugFill") debugFill = msg.value;
      break;
    }

    case "demo": {
      switch (msg.cmd) {
        case "rec": demoRec(); break;
        case "play": demoPlay(msg.savedDemo); break;
        case "stop": demoStop(); break;
        case "save": demoSave(); break;
      }
      break;
    }

    case "speed": {
      speed = msg.value || 1;
      break;
    }

    case "pause": {
      paused = msg.value;
      break;
    }
  }
};
