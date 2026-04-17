const { PNG } = require("/Users/ssk/work/mono/node_modules/pngjs");
const fs = require("fs");

const W = 512, H = 512;
const png = new PNG({ width: W, height: H });

function setPixel(x, y, v, a = 255) {
  x = Math.round(x); y = Math.round(y);
  if (x < 0 || x >= W || y < 0 || y >= H) return;
  const idx = (y * W + x) * 4;
  const srcA = a / 255;
  const dstA = png.data[idx + 3] / 255;
  const outA = srcA + dstA * (1 - srcA);
  if (outA === 0) return;
  const blended = Math.round((v * srcA + png.data[idx] * dstA * (1 - srcA)) / outA);
  png.data[idx]     = blended;
  png.data[idx + 1] = blended;
  png.data[idx + 2] = blended;
  png.data[idx + 3] = Math.round(outA * 255);
}

function fillRect(x1, y1, w, h, v, a = 255) {
  for (let dy = 0; dy < h; dy++)
    for (let dx = 0; dx < w; dx++)
      setPixel(x1 + dx, y1 + dy, v, a);
}

function isInsideRoundedRect(x, y, radius) {
  if (x < radius && y < radius) {
    const dx = x - radius, dy = y - radius;
    return dx * dx + dy * dy <= radius * radius;
  }
  if (x >= W - radius && y < radius) {
    const dx = x - (W - radius - 1), dy = y - radius;
    return dx * dx + dy * dy <= radius * radius;
  }
  if (x < radius && y >= H - radius) {
    const dx = x - radius, dy = y - (H - radius - 1);
    return dx * dx + dy * dy <= radius * radius;
  }
  if (x >= W - radius && y >= H - radius) {
    const dx = x - (W - radius - 1), dy = y - (H - radius - 1);
    return dx * dx + dy * dy <= radius * radius;
  }
  return true;
}

// --- Fill background black with rounded corners ---
const CORNER = 64;
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    const idx = (y * W + x) * 4;
    if (isInsideRoundedRect(x, y, CORNER)) {
      png.data[idx] = 0;
      png.data[idx + 1] = 0;
      png.data[idx + 2] = 0;
      png.data[idx + 3] = 255;
    } else {
      png.data[idx] = 0;
      png.data[idx + 1] = 0;
      png.data[idx + 2] = 0;
      png.data[idx + 3] = 0;
    }
  }
}

// --- Stars ---
const rng = (seed) => {
  let s = seed;
  return () => { s = (s * 1103515245 + 12345) & 0x7fffffff; return s / 0x7fffffff; };
};
const rand = rng(42);
for (let i = 0; i < 220; i++) {
  const sx = Math.floor(rand() * W);
  const sy = Math.floor(rand() * H);
  if (!isInsideRoundedRect(sx, sy, CORNER)) continue;
  const brightness = 90 + Math.floor(rand() * 165);
  const size = rand() > 0.85 ? 2 : 1;
  for (let dy = 0; dy < size; dy++)
    for (let dx = 0; dx < size; dx++)
      setPixel(sx + dx, sy + dy, brightness);
}

// --- Nebula glow (subtle gray patches for depth) ---
function drawGlow(cx, cy, radius, v, maxAlpha) {
  for (let dy = -radius; dy <= radius; dy++) {
    for (let dx = -radius; dx <= radius; dx++) {
      const dist = Math.sqrt(dx * dx + dy * dy);
      if (dist > radius) continue;
      const alpha = Math.floor(maxAlpha * (1 - dist / radius) ** 2);
      if (alpha > 0) setPixel(cx + dx, cy + dy, v, alpha);
    }
  }
}
drawGlow(140, 200, 80, 40, 25);
drawGlow(380, 150, 60, 35, 20);
drawGlow(256, 420, 100, 30, 18);

// --- Filled triangle helper ---
function fillTriangle(x0, y0, x1, y1, x2, y2, v, a = 255) {
  const minY = Math.floor(Math.min(y0, y1, y2));
  const maxY = Math.ceil(Math.max(y0, y1, y2));
  for (let y = minY; y <= maxY; y++) {
    let minX = W, maxX = 0;
    const edges = [[x0,y0,x1,y1],[x1,y1,x2,y2],[x2,y2,x0,y0]];
    for (const [ax,ay,bx,by] of edges) {
      if ((y >= Math.min(ay, by)) && (y <= Math.max(ay, by))) {
        const t = (ay === by) ? 0.5 : (y - ay) / (by - ay);
        const ix = ax + t * (bx - ax);
        minX = Math.min(minX, ix);
        maxX = Math.max(maxX, ix);
      }
    }
    for (let x = Math.floor(minX); x <= Math.ceil(maxX); x++) {
      setPixel(x, y, v, a);
    }
  }
}

// --- Player ship (bottom center) ---
const shipCX = 256, shipTipY = 340, shipBaseY = 410;
const shipHalfW = 30;

// Ship main body (bright white)
fillTriangle(shipCX, shipTipY, shipCX - shipHalfW, shipBaseY, shipCX + shipHalfW, shipBaseY, 230);
// Ship inner detail (darker gray stripe)
fillTriangle(shipCX, shipTipY + 15, shipCX - 12, shipBaseY - 5, shipCX + 12, shipBaseY - 5, 120);
// Ship cockpit (bright white dot)
drawGlow(shipCX, shipTipY + 25, 6, 255, 255);

// Wings
fillTriangle(shipCX - shipHalfW, shipBaseY - 15, shipCX - shipHalfW - 22, shipBaseY + 5, shipCX - shipHalfW + 5, shipBaseY + 5, 190);
fillTriangle(shipCX + shipHalfW, shipBaseY - 15, shipCX + shipHalfW + 22, shipBaseY + 5, shipCX + shipHalfW - 5, shipBaseY + 5, 190);

// Engine glow (light gray at bottom of ship)
drawGlow(shipCX - 10, shipBaseY + 8, 12, 200, 200);
drawGlow(shipCX + 10, shipBaseY + 8, 12, 200, 200);
drawGlow(shipCX, shipBaseY + 12, 16, 160, 150);

// Engine exhaust trail
for (let i = 0; i < 35; i++) {
  const ey = shipBaseY + 12 + i * 2;
  const spread = i * 0.8;
  const alpha = Math.max(0, 180 - i * 5);
  const v = Math.max(60, 220 - i * 5);
  for (let dx = -3 - Math.floor(spread); dx <= 3 + Math.floor(spread); dx++) {
    const dist = Math.abs(dx) / (3 + spread);
    const pa = Math.floor(alpha * (1 - dist));
    if (pa > 0) setPixel(shipCX + dx, ey, v, pa);
  }
}

// --- Bullet streams (3 streams going upward, white/light gray) ---
function drawBulletStream(x, startY, endY) {
  for (let y = startY; y >= endY; y -= 1) {
    const progress = (startY - y) / (startY - endY);
    const alpha = Math.max(40, Math.floor(255 * (1 - progress * 0.5)));
    const v = 240;
    // Core bright line
    setPixel(x, y, v, alpha);
    setPixel(x + 1, y, v, alpha);
    // Side glow
    setPixel(x - 1, y, v, Math.floor(alpha * 0.4));
    setPixel(x + 2, y, v, Math.floor(alpha * 0.4));
  }
  // Bullet tip (brighter dots at intervals)
  for (let y = startY; y >= endY; y -= 28) {
    drawGlow(x, y, 5, 255, 200);
  }
}

drawBulletStream(shipCX, shipTipY - 5, 80);       // Center stream
drawBulletStream(shipCX - 20, shipTipY + 5, 100);  // Left stream
drawBulletStream(shipCX + 20, shipTipY + 5, 100);  // Right stream

// --- Enemy ships (medium gray inverted triangles in upper area) ---
function drawEnemy(cx, cy, size, bodyGray) {
  // Inverted triangle (pointing down)
  fillTriangle(cx, cy + size, cx - size * 0.7, cy - size * 0.5, cx + size * 0.7, cy - size * 0.5, bodyGray);
  // Eye/cockpit (white dot)
  drawGlow(cx, cy, 3, 255, 220);
  // Engine glow at top
  drawGlow(cx, cy - size * 0.5 - 2, 4, Math.min(255, bodyGray + 60), 150);
}

drawEnemy(160, 140, 18, 140);   // Enemy left
drawEnemy(320, 110, 18, 140);   // Enemy right
drawEnemy(256, 180, 20, 160);   // Enemy center (bigger, slightly lighter)
drawEnemy(400, 170, 16, 130);   // Enemy far right

// --- Enemy bullet streams coming down (dark gray) ---
function drawEnemyBullets(x, startY, endY) {
  for (let y = startY; y <= endY; y += 2) {
    const alpha = Math.max(30, 200 - (y - startY) * 2);
    setPixel(x, y, 180, alpha);
    setPixel(x + 1, y, 180, Math.floor(alpha * 0.5));
  }
}
drawEnemyBullets(160, 158, 260);
drawEnemyBullets(320, 128, 240);
drawEnemyBullets(256, 200, 300);

// --- Explosions (radiating gray pixel bursts) ---
function drawExplosion(cx, cy, maxRadius) {
  // Core white
  drawGlow(cx, cy, 6, 255, 255);
  // Bright gray ring
  drawGlow(cx, cy, maxRadius * 0.5, 220, 180);
  // Dimmer outer ring
  drawGlow(cx, cy, maxRadius * 0.8, 150, 100);
  // Sparks/rays
  const sparkCount = 12;
  for (let i = 0; i < sparkCount; i++) {
    const angle = (i / sparkCount) * Math.PI * 2 + 0.3;
    for (let d = 4; d < maxRadius; d += 2) {
      const sx = cx + Math.cos(angle) * d;
      const sy = cy + Math.sin(angle) * d;
      const alpha = Math.max(0, 220 - d * 8);
      const v = Math.max(100, 240 - d * 5);
      if (alpha > 0) {
        setPixel(sx, sy, v, alpha);
        setPixel(sx + 1, sy, v, Math.floor(alpha * 0.5));
      }
    }
  }
  // Debris particles
  for (let i = 0; i < 16; i++) {
    const angle = (rand() * Math.PI * 2);
    const dist = 5 + rand() * maxRadius * 1.2;
    const px = cx + Math.cos(angle) * dist;
    const py = cy + Math.sin(angle) * dist;
    setPixel(px, py, 220, 200);
    setPixel(px + 1, py, 220, 150);
  }
}

drawExplosion(120, 100, 22);
drawExplosion(380, 200, 18);

// --- "VOID STORM" title at top ---
const FONT = {
  V: [
    "1...1",
    "1...1",
    "1...1",
    ".1.1.",
    "..1..",
  ],
  O: [
    ".111.",
    "1...1",
    "1...1",
    "1...1",
    ".111.",
  ],
  I: [
    "11111",
    "..1..",
    "..1..",
    "..1..",
    "11111",
  ],
  D: [
    "1111.",
    "1...1",
    "1...1",
    "1...1",
    "1111.",
  ],
  S: [
    ".1111",
    "1....",
    ".111.",
    "....1",
    "1111.",
  ],
  T: [
    "11111",
    "..1..",
    "..1..",
    "..1..",
    "..1..",
  ],
  R: [
    "1111.",
    "1...1",
    "1111.",
    "1..1.",
    "1...1",
  ],
  M: [
    "1...1",
    "11.11",
    "1.1.1",
    "1...1",
    "1...1",
  ],
  " ": [
    ".....",
    ".....",
    ".....",
    ".....",
    ".....",
  ],
};

function drawChar(ch, startX, startY, scale, v) {
  const grid = FONT[ch];
  if (!grid) return;
  for (let row = 0; row < grid.length; row++) {
    for (let col = 0; col < grid[row].length; col++) {
      if (grid[row][col] === "1") {
        for (let sy = 0; sy < scale; sy++) {
          for (let sx = 0; sx < scale; sx++) {
            setPixel(startX + col * scale + sx, startY + row * scale + sy, v);
          }
        }
      }
    }
  }
}

function drawText(text, centerX, topY, scale, v) {
  const charW = 5 * scale + scale;
  const totalW = text.length * charW - scale;
  let x = centerX - Math.floor(totalW / 2);
  for (const ch of text) {
    drawChar(ch, x, topY, scale, v);
    x += charW;
  }
}

// Title glow behind text
const titleY = 30;
const titleScale = 5;
drawGlow(256, titleY + 14, 120, 60, 35);

// Title shadow
drawText("VOID STORM", 258, titleY + 2, titleScale, 50);
// Title main text (bright white)
drawText("VOID STORM", 256, titleY, titleScale, 245);

// Title underline accent (white gradient)
for (let x = 100; x < 412; x++) {
  const dist = Math.abs(x - 256) / 156;
  const alpha = Math.floor(200 * (1 - dist));
  if (alpha > 0) {
    setPixel(x, titleY + titleScale * 5 + 6, 200, alpha);
    setPixel(x, titleY + titleScale * 5 + 7, 140, Math.floor(alpha * 0.5));
  }
}

// --- Border glow (subtle gray edge highlight) ---
for (let x = 0; x < W; x++) {
  for (let y = 0; y < H; y++) {
    if (!isInsideRoundedRect(x, y, CORNER)) continue;
    const distL = x, distR = W - 1 - x, distT = y, distB = H - 1 - y;
    const minDist = Math.min(distL, distR, distT, distB);
    if (minDist < 3) {
      const alpha = Math.floor(80 * (1 - minDist / 3));
      setPixel(x, y, 120, alpha);
    }
  }
}

// --- Save ---
const outPath = "/Users/ssk/mono/contest/entries/agent-gamma/publish/icon-512.png";
const buffer = PNG.sync.write(png);
fs.writeFileSync(outPath, buffer);
console.log("Icon written to", outPath, "(" + buffer.length + " bytes)");
