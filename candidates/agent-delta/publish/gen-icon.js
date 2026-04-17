const { PNG } = require("/Users/ssk/work/mono/node_modules/pngjs");
const fs = require("fs");

const W = 512, H = 512;
const png = new PNG({ width: W, height: H });

// Strict grayscale: all setPixel calls use same value for R, G, B
function setPixel(x, y, v, a = 255) {
  x = Math.floor(x); y = Math.floor(y);
  if (x < 0 || x >= W || y < 0 || y >= H) return;
  const idx = (y * W + x) * 4;
  const aa = a / 255;
  const old = png.data[idx];
  const blended = Math.floor(old * (1 - aa) + v * aa);
  png.data[idx]     = blended;
  png.data[idx + 1] = blended;
  png.data[idx + 2] = blended;
  png.data[idx + 3] = Math.max(png.data[idx + 3], a);
}

function fillRect(x1, y1, x2, y2, v, a = 255) {
  for (let y = Math.max(0, Math.floor(y1)); y < Math.min(H, Math.floor(y2)); y++) {
    for (let x = Math.max(0, Math.floor(x1)); x < Math.min(W, Math.floor(x2)); x++) {
      setPixel(x, y, v, a);
    }
  }
}

function fillCircle(cx, cy, radius, v, a = 255) {
  for (let y = cy - radius; y <= cy + radius; y++) {
    for (let x = cx - radius; x <= cx + radius; x++) {
      if ((x - cx) * (x - cx) + (y - cy) * (y - cy) <= radius * radius) {
        setPixel(Math.floor(x), Math.floor(y), v, a);
      }
    }
  }
}

// Rounded rect mask
const CR = 64;
function inRR(x, y) {
  if (x < CR && y < CR) {
    return (x - CR) * (x - CR) + (y - CR) * (y - CR) <= CR * CR;
  }
  if (x >= W - CR && y < CR) {
    return (x - (W - CR - 1)) * (x - (W - CR - 1)) + (y - CR) * (y - CR) <= CR * CR;
  }
  if (x < CR && y >= H - CR) {
    return (x - CR) * (x - CR) + (y - (H - CR - 1)) * (y - (H - CR - 1)) <= CR * CR;
  }
  if (x >= W - CR && y >= H - CR) {
    return (x - (W - CR - 1)) * (x - (W - CR - 1)) + (y - (H - CR - 1)) * (y - (H - CR - 1)) <= CR * CR;
  }
  return true;
}

// Use seeded random for reproducibility
let seed = 42;
function srand() {
  seed = (seed * 16807 + 0) % 2147483647;
  return (seed - 1) / 2147483646;
}

// ===================== BACKGROUND =====================
const horizonY = 200;

for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    const idx = (y * W + x) * 4;
    if (!inRR(x, y)) {
      png.data[idx] = 0; png.data[idx+1] = 0; png.data[idx+2] = 0; png.data[idx+3] = 0;
      continue;
    }
    // Sky: deep black at top fading to dark gray at horizon
    if (y < horizonY) {
      const t = y / horizonY;
      const v = Math.floor(8 + t * 30);
      png.data[idx] = v; png.data[idx+1] = v; png.data[idx+2] = v; png.data[idx+3] = 255;
    } else {
      // Ground: dark base
      const t = (y - horizonY) / (H - horizonY);
      const v = Math.floor(30 + t * 12);
      png.data[idx] = v; png.data[idx+1] = v; png.data[idx+2] = v; png.data[idx+3] = 255;
    }
  }
}

// ===================== STARS in sky =====================
for (let i = 0; i < 40; i++) {
  const sx = Math.floor(srand() * W);
  const sy = Math.floor(srand() * (horizonY - 30) + 10);
  const brightness = Math.floor(100 + srand() * 120);
  if (inRR(sx, sy)) setPixel(sx, sy, brightness);
  if (inRR(sx+1, sy)) setPixel(sx+1, sy, Math.floor(brightness * 0.6));
  if (inRR(sx, sy+1)) setPixel(sx, sy+1, Math.floor(brightness * 0.6));
}

// ===================== MOUNTAINS =====================
function drawMountainLayer(peaks, baseGray, deltaGray) {
  for (let x = 0; x < W; x++) {
    let minTop = horizonY;
    for (const p of peaks) {
      const dx = Math.abs(x - p.cx);
      if (dx < p.w / 2) {
        const t = dx / (p.w / 2);
        const top = p.top + t * t * (horizonY - p.top);
        minTop = Math.min(minTop, top);
      }
    }
    for (let y = Math.floor(minTop); y < horizonY; y++) {
      if (!inRR(x, y)) continue;
      const mt = (y - minTop) / (horizonY - minTop);
      const v = Math.floor(baseGray + mt * deltaGray);
      setPixel(x, y, v);
    }
  }
}

// Background mountains (lighter)
drawMountainLayer([
  { cx: 60,  top: 130, w: 160 },
  { cx: 170, top: 100, w: 150 },
  { cx: 256, top: 80,  w: 200 },
  { cx: 350, top: 95,  w: 160 },
  { cx: 460, top: 120, w: 180 },
], 50, 20);

// Foreground mountains (darker)
drawMountainLayer([
  { cx: 40,  top: 160, w: 130 },
  { cx: 150, top: 145, w: 140 },
  { cx: 290, top: 150, w: 170 },
  { cx: 410, top: 140, w: 150 },
  { cx: 500, top: 165, w: 110 },
], 38, 18);

// ===================== ROAD with perspective =====================
const vanishX = 256, vanishY = horizonY;
const roadBottomHalfW = 230;

for (let y = vanishY; y < H; y++) {
  const t = (y - vanishY) / (H - vanishY);
  const halfW = t * roadBottomHalfW;
  const leftEdge = vanishX - halfW;
  const rightEdge = vanishX + halfW;

  // Road surface
  for (let x = Math.max(0, Math.floor(leftEdge)); x < Math.min(W, Math.ceil(rightEdge)); x++) {
    if (!inRR(x, y)) continue;
    // Subtle variation - slightly lighter toward center
    const cx = (x - vanishX) / halfW; // -1 to 1
    const v = Math.floor(55 + (1 - Math.abs(cx)) * 8);
    setPixel(x, y, v);
  }

  // Edge lines (white)
  const edgeW = Math.max(1, t * 5);
  for (let dx = 0; dx < edgeW; dx++) {
    const lx = Math.floor(leftEdge + dx);
    const rx = Math.floor(rightEdge - dx);
    const fade = 1 - dx / edgeW;
    const ev = Math.floor(180 * fade);
    if (inRR(lx, y)) setPixel(lx, y, ev);
    if (inRR(rx, y)) setPixel(rx, y, ev);
  }

  // Dashed center line
  const dashLen = Math.max(3, t * 22);
  const dashGap = Math.max(3, t * 16);
  const cycle = dashLen + dashGap;
  const distH = y - vanishY;
  if ((distH % cycle) < dashLen) {
    const lineW = Math.max(1, t * 4);
    for (let dx = -lineW / 2; dx < lineW / 2; dx++) {
      const lx = Math.floor(vanishX + dx);
      if (inRR(lx, y)) setPixel(lx, y, 200);
    }
  }
}

// ===================== ROADSIDE TERRAIN =====================
for (let y = vanishY; y < H; y++) {
  const t = (y - vanishY) / (H - vanishY);
  const halfW = t * roadBottomHalfW;
  const leftEdge = vanishX - halfW;
  const rightEdge = vanishX + halfW;

  for (let x = 0; x < Math.floor(leftEdge); x++) {
    if (!inRR(x, y)) continue;
    const v = Math.floor(30 + t * 12);
    setPixel(x, y, v);
  }
  for (let x = Math.ceil(rightEdge); x < W; x++) {
    if (!inRR(x, y)) continue;
    const v = Math.floor(30 + t * 12);
    setPixel(x, y, v);
  }
}

// ===================== TRAFFIC (opponent cars) =====================
function drawTrafficCar(cx, cy, scale) {
  const w = Math.floor(18 * scale);
  const h = Math.floor(30 * scale);
  // Body
  fillRect(cx - w/2, cy - h/2, cx + w/2, cy + h/2, 80);
  // Roof
  fillRect(cx - w/2 + 2*scale, cy - h/2 - 2*scale, cx + w/2 - 2*scale, cy - h/2 + 8*scale, 65);
  // Tail lights
  fillRect(cx - w/2, cy + h/2 - 2*scale, cx - w/2 + 4*scale, cy + h/2, 170);
  fillRect(cx + w/2 - 4*scale, cy + h/2 - 2*scale, cx + w/2, cy + h/2, 170);
}

// Place traffic at various distances
drawTrafficCar(210, 290, 0.5);
drawTrafficCar(310, 260, 0.4);
drawTrafficCar(275, 330, 0.7);

// ===================== SPEED LINES =====================
function drawSpeedLines() {
  for (let i = 0; i < 16; i++) {
    const side = i < 8 ? -1 : 1;
    const startX = side < 0 ? (10 + srand() * 90) : (W - 10 - srand() * 90);
    const startY = 220 + srand() * 230;
    const len = 50 + srand() * 90;
    const brightness = 90 + Math.floor(srand() * 80);

    const dx = vanishX - startX;
    const dy = vanishY - startY;
    const dist = Math.sqrt(dx * dx + dy * dy);
    const nx = dx / dist;
    const ny = dy / dist;

    for (let j = 0; j < len; j++) {
      const alpha = Math.floor(brightness * (1 - j / len));
      const px = Math.floor(startX + nx * j);
      const py = Math.floor(startY + ny * j);
      if (inRR(px, py)) setPixel(px, py, 180, Math.floor(alpha * 0.8));
      if (inRR(px + 1, py)) setPixel(px + 1, py, 180, Math.floor(alpha * 0.5));
    }
  }
}
drawSpeedLines();

// ===================== PLAYER CAR =====================
function drawCar() {
  const cx = 256;
  const bottom = 468;
  const carW = 76;
  const carH = 110;
  const top = bottom - carH;

  // Shadow under car
  for (let sy = bottom - 5; sy < bottom + 12; sy++) {
    const sw = carW / 2 + 15 - (sy - bottom + 5);
    if (sw <= 0) continue;
    for (let sx = cx - sw; sx < cx + sw; sx++) {
      if (inRR(Math.floor(sx), sy)) setPixel(Math.floor(sx), sy, 15, 120);
    }
  }

  // Main body
  fillRect(cx - carW/2, top + 25, cx + carW/2, bottom, 145);

  // Body highlight (lighter strip on top of body)
  fillRect(cx - carW/2 + 4, top + 26, cx + carW/2 - 4, top + 35, 165);

  // Cabin / roof (narrower)
  fillRect(cx - carW/2 + 10, top, cx + carW/2 - 10, top + 50, 110);

  // Windshield (dark)
  fillRect(cx - carW/2 + 14, top + 4, cx + carW/2 - 14, top + 26, 55);
  // Windshield highlight
  fillRect(cx - carW/2 + 16, top + 6, cx - 4, top + 12, 75, 120);

  // Hood line
  for (let x = cx - carW/2 + 5; x < cx + carW/2 - 5; x++) {
    if (inRR(x, top + 50)) setPixel(x, top + 50, 120);
  }

  // Side panels
  fillRect(cx - carW/2, top + 52, cx - carW/2 + 7, bottom - 6, 100);
  fillRect(cx + carW/2 - 7, top + 52, cx + carW/2, bottom - 6, 100);

  // Wheels
  fillRect(cx - carW/2 - 6, top + 30, cx - carW/2 + 2, top + 55, 40);
  fillRect(cx + carW/2 - 2, top + 30, cx + carW/2 + 6, top + 55, 40);
  fillRect(cx - carW/2 - 6, bottom - 35, cx - carW/2 + 2, bottom - 10, 40);
  fillRect(cx + carW/2 - 2, bottom - 35, cx + carW/2 + 6, bottom - 10, 40);

  // Wheel highlights
  fillRect(cx - carW/2 - 4, top + 32, cx - carW/2, top + 36, 70);
  fillRect(cx + carW/2, top + 32, cx + carW/2 + 4, top + 36, 70);

  // Tail lights (bright white)
  fillRect(cx - carW/2 + 3, bottom - 6, cx - carW/2 + 16, bottom - 1, 230);
  fillRect(cx + carW/2 - 16, bottom - 6, cx + carW/2 - 3, bottom - 1, 230);

  // Racing stripe
  fillRect(cx - 5, top + 2, cx + 5, bottom, 180);

  // ---- NITRO EXHAUST / FLAME ----
  const flameBase = bottom + 2;

  // Outer glow (wide, faint)
  for (let fy = 0; fy < 60; fy++) {
    const t = fy / 60;
    const fw = (1 - t * t) * 40;
    const alpha = Math.floor(120 * (1 - t));
    const bv = Math.floor(200 * (1 - t * 0.5));
    for (let fx = -fw; fx < fw; fx++) {
      const px = Math.floor(cx + fx);
      const py = Math.floor(flameBase + fy);
      if (py >= H || !inRR(px, py)) continue;
      const edgeFade = 1 - Math.abs(fx) / fw;
      setPixel(px, py, bv, Math.floor(alpha * edgeFade));
    }
  }

  // Bright core
  for (let fy = 0; fy < 35; fy++) {
    const t = fy / 35;
    const fw = (1 - t) * 16;
    const bv = Math.floor(255 * (1 - t * 0.3));
    const alpha = Math.floor(255 * (1 - t * 0.7));
    for (let fx = -fw; fx < fw; fx++) {
      const px = Math.floor(cx + fx);
      const py = Math.floor(flameBase + fy);
      if (py >= H || !inRR(px, py)) continue;
      setPixel(px, py, bv, alpha);
    }
  }

  // Hot white center
  for (let fy = 0; fy < 15; fy++) {
    const t = fy / 15;
    const fw = (1 - t) * 7;
    for (let fx = -fw; fx < fw; fx++) {
      const px = Math.floor(cx + fx);
      const py = Math.floor(flameBase + fy);
      if (py >= H || !inRR(px, py)) continue;
      setPixel(px, py, 255);
    }
  }

  // Side exhaust sparks
  for (let i = 0; i < 8; i++) {
    const angle = -Math.PI/2 + (srand() - 0.5) * 1.2;
    const dist = 20 + srand() * 30;
    const sx = Math.floor(cx + Math.cos(angle) * dist * 0.8);
    const sy = Math.floor(flameBase + Math.sin(angle) * dist + dist * 0.5);
    const sv = Math.floor(180 + srand() * 75);
    if (sy < H && inRR(sx, sy)) {
      setPixel(sx, sy, sv);
      if (inRR(sx+1, sy)) setPixel(sx+1, sy, Math.floor(sv*0.6));
    }
  }
}
drawCar();

// ===================== TITLE "NITRO DASH" =====================
const FONT = {
  'N': [
    [1,0,0,0,1],
    [1,1,0,0,1],
    [1,0,1,0,1],
    [1,0,0,1,1],
    [1,0,0,0,1],
  ],
  'I': [
    [1,1,1],
    [0,1,0],
    [0,1,0],
    [0,1,0],
    [1,1,1],
  ],
  'T': [
    [1,1,1,1,1],
    [0,0,1,0,0],
    [0,0,1,0,0],
    [0,0,1,0,0],
    [0,0,1,0,0],
  ],
  'R': [
    [1,1,1,1,0],
    [1,0,0,0,1],
    [1,1,1,1,0],
    [1,0,0,1,0],
    [1,0,0,0,1],
  ],
  'O': [
    [0,1,1,1,0],
    [1,0,0,0,1],
    [1,0,0,0,1],
    [1,0,0,0,1],
    [0,1,1,1,0],
  ],
  'D': [
    [1,1,1,1,0],
    [1,0,0,0,1],
    [1,0,0,0,1],
    [1,0,0,0,1],
    [1,1,1,1,0],
  ],
  'A': [
    [0,1,1,1,0],
    [1,0,0,0,1],
    [1,1,1,1,1],
    [1,0,0,0,1],
    [1,0,0,0,1],
  ],
  'S': [
    [0,1,1,1,1],
    [1,0,0,0,0],
    [0,1,1,1,0],
    [0,0,0,0,1],
    [1,1,1,1,0],
  ],
  'H': [
    [1,0,0,0,1],
    [1,0,0,0,1],
    [1,1,1,1,1],
    [1,0,0,0,1],
    [1,0,0,0,1],
  ],
  ' ': [
    [0,0,0],
    [0,0,0],
    [0,0,0],
    [0,0,0],
    [0,0,0],
  ],
};

function measureText(text, scale) {
  let w = 0;
  for (const ch of text) {
    const g = FONT[ch];
    if (!g) continue;
    w += (g[0].length + 1) * scale;
  }
  return w - scale;
}

function drawText(text, startX, startY, scale, v, a = 255) {
  let cx = startX;
  for (const ch of text) {
    const g = FONT[ch];
    if (!g) continue;
    const gw = g[0].length;
    for (let gy = 0; gy < g.length; gy++) {
      for (let gx = 0; gx < gw; gx++) {
        if (g[gy][gx]) {
          fillRect(cx + gx * scale, startY + gy * scale,
                   cx + (gx + 1) * scale, startY + (gy + 1) * scale, v, a);
        }
      }
    }
    cx += (gw + 1) * scale;
  }
}

const scale = 8;
const titleY = 30;
const w1 = measureText("NITRO", scale);
const w2 = measureText("DASH", scale);
const lineGap = 14;
const line2Y = titleY + scale * 5 + lineGap;

// Glow behind text (spread)
for (let pass = 3; pass >= 1; pass--) {
  const offset = pass * 2;
  const glowA = Math.floor(40 / pass);
  drawText("NITRO", Math.floor((W - w1) / 2) - offset, titleY - offset, scale, 200, glowA);
  drawText("DASH", Math.floor((W - w2) / 2) - offset, line2Y - offset, scale, 200, glowA);
}

// Shadow
drawText("NITRO", Math.floor((W - w1) / 2) + 3, titleY + 3, scale, 25);
drawText("DASH", Math.floor((W - w2) / 2) + 3, line2Y + 3, scale, 25);

// Main text (bright white)
drawText("NITRO", Math.floor((W - w1) / 2), titleY, scale, 240);
drawText("DASH", Math.floor((W - w2) / 2), line2Y, scale, 240);

// ===================== VIGNETTE =====================
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    if (!inRR(x, y)) continue;
    const dx = (x - W/2) / (W/2);
    const dy = (y - H/2) / (H/2);
    const dist = Math.sqrt(dx*dx + dy*dy);
    if (dist > 0.6) {
      const factor = Math.min(1, (dist - 0.6) / 0.9);
      const darken = 1 - factor * 0.45;
      const idx = (y * W + x) * 4;
      png.data[idx]     = Math.floor(png.data[idx] * darken);
      png.data[idx + 1] = Math.floor(png.data[idx + 1] * darken);
      png.data[idx + 2] = Math.floor(png.data[idx + 2] * darken);
    }
  }
}

// ===================== FINAL: enforce strict grayscale =====================
// Safety pass: ensure R=G=B for every pixel
for (let i = 0; i < W * H * 4; i += 4) {
  const avg = Math.round((png.data[i] + png.data[i+1] + png.data[i+2]) / 3);
  png.data[i] = avg;
  png.data[i+1] = avg;
  png.data[i+2] = avg;
}

// ===================== WRITE =====================
const outPath = "/Users/ssk/mono/contest/entries/agent-delta/publish/icon-512.png";
const buffer = PNG.sync.write(png);
fs.writeFileSync(outPath, buffer);
console.log("Icon written to", outPath, `(${buffer.length} bytes)`);
