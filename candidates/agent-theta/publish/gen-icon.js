const { PNG } = require("/Users/ssk/work/mono/node_modules/pngjs");
const fs = require("fs");

const W = 512, H = 512;
const png = new PNG({ width: W, height: H });

// All drawing uses grayscale: setGray(x, y, value, alpha)
// value 0=black, 255=white

function setPixel(x, y, v, a = 255) {
  x = Math.round(x); y = Math.round(y);
  if (x < 0 || x >= W || y < 0 || y >= H) return;
  const idx = (y * W + x) * 4;
  if (a < 255) {
    const aa = a / 255;
    const existing = png.data[idx];
    const blended = Math.round(existing * (1 - aa) + v * aa);
    png.data[idx] = blended;
    png.data[idx + 1] = blended;
    png.data[idx + 2] = blended;
    png.data[idx + 3] = Math.min(255, png.data[idx + 3] + a);
  } else {
    png.data[idx] = v;
    png.data[idx + 1] = v;
    png.data[idx + 2] = v;
    png.data[idx + 3] = 255;
  }
}

function fillRect(x1, y1, w, h, v, a = 255) {
  for (let yy = y1; yy < y1 + h; yy++)
    for (let xx = x1; xx < x1 + w; xx++)
      setPixel(xx, yy, v, a);
}

function drawLine(x0, y0, x1, y1, v, thickness = 1, a = 255) {
  const dx = x1 - x0, dy = y1 - y0;
  const steps = Math.max(Math.abs(dx), Math.abs(dy), 1);
  for (let i = 0; i <= steps; i++) {
    const t = i / steps;
    const cx = x0 + dx * t, cy = y0 + dy * t;
    for (let ty = -thickness / 2; ty <= thickness / 2; ty++)
      for (let tx = -thickness / 2; tx <= thickness / 2; tx++)
        setPixel(cx + tx, cy + ty, v, a);
  }
}

function drawCircle(cx, cy, radius, v, filled = true, a = 255) {
  for (let y = -radius; y <= radius; y++) {
    for (let x = -radius; x <= radius; x++) {
      const dist = Math.sqrt(x * x + y * y);
      if (filled ? dist <= radius : Math.abs(dist - radius) < 1.5) {
        setPixel(cx + x, cy + y, v, a);
      }
    }
  }
}

function drawEllipse(cx, cy, rx, ry, v, filled = true, a = 255) {
  for (let y = -ry; y <= ry; y++) {
    for (let x = -rx; x <= rx; x++) {
      const dist = (x * x) / (rx * rx) + (y * y) / (ry * ry);
      if (filled ? dist <= 1 : Math.abs(dist - 1) < 0.15) {
        setPixel(cx + x, cy + y, v, a);
      }
    }
  }
}

function isInRoundedRect(x, y, w, h, radius) {
  if (x < radius && y < radius)
    return Math.sqrt((x - radius) ** 2 + (y - radius) ** 2) <= radius;
  if (x >= w - radius && y < radius)
    return Math.sqrt((x - (w - radius)) ** 2 + (y - radius) ** 2) <= radius;
  if (x < radius && y >= h - radius)
    return Math.sqrt((x - radius) ** 2 + (y - (h - radius)) ** 2) <= radius;
  if (x >= w - radius && y >= h - radius)
    return Math.sqrt((x - (w - radius)) ** 2 + (y - (h - radius)) ** 2) <= radius;
  return true;
}

// Seed random for consistency
let seed = 42;
function srand() {
  seed = (seed * 16807 + 0) % 2147483647;
  return (seed - 1) / 2147483646;
}

// ===== BACKGROUND =====
// Dark gradient background
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    const t = y / H;
    const v = Math.round(12 + 18 * t);
    setPixel(x, y, v);
  }
}

// Radial vignette
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    const dx = (x - W / 2) / (W / 2);
    const dy = (y - H / 2) / (H / 2);
    const dist = Math.sqrt(dx * dx + dy * dy);
    if (dist > 0.5) {
      const dark = Math.min(1, (dist - 0.5) * 1.5);
      setPixel(x, y, 0, Math.round(dark * 140));
    }
  }
}

// Spotlight from above center
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    const dx = (x - W / 2) / (W / 2);
    const dy = (y - 200) / (H / 2);
    const dist = Math.sqrt(dx * dx + dy * dy);
    if (dist < 0.9) {
      const bright = Math.max(0, 1 - dist / 0.9) * 0.25;
      setPixel(x, y, 60, Math.round(bright * 120));
    }
  }
}

// ===== CROWD/ATMOSPHERE (subtle dots) =====
for (let i = 0; i < 400; i++) {
  const cx = 70 + srand() * 370;
  const cy = 130 + srand() * 110;
  const brightness = 25 + srand() * 35;
  setPixel(cx, cy, brightness, 50);
  setPixel(cx + 1, cy, brightness - 5, 40);
  setPixel(cx, cy + 1, brightness - 5, 40);
}

// ===== RING FLOOR =====
const floorY = 355;
// Ring canvas floor
for (let y = floorY; y < 435; y++) {
  for (let x = 55; x < 457; x++) {
    const shade = 40 + Math.round((435 - y) * 0.25);
    setPixel(x, y, shade);
  }
}
// Floor highlight stripe at top edge
for (let y = floorY; y < floorY + 3; y++) {
  for (let x = 60; x < 452; x++) {
    setPixel(x, y, 70);
  }
}
// Floor center highlight
for (let y = floorY + 5; y < floorY + 60; y++) {
  for (let x = 180; x < 340; x++) {
    const dx = (x - 260) / 80;
    const dy = (y - (floorY + 30)) / 30;
    const dist = dx * dx + dy * dy;
    if (dist < 1) {
      setPixel(x, y, 55, Math.round((1 - dist) * 40));
    }
  }
}

// ===== RING POSTS =====
// Near posts (gray metallic)
const nearPosts = [
  [60, floorY - 10, floorY + 50],
  [452, floorY - 10, floorY + 50],
];
for (const [px, py1, py2] of nearPosts) {
  for (let y = py1; y < py2; y++) {
    for (let x = px - 5; x <= px + 5; x++) {
      const highlight = (x < px) ? 15 : -15;
      setPixel(x, y, Math.min(255, 140 + highlight));
    }
  }
  // Post cap (bright)
  drawCircle(px, py1 - 3, 7, 200, true);
  drawCircle(px, py1 - 3, 4, 230, true);
}

// Far posts (smaller, perspective)
const farPosts = [
  [115, floorY - 85, floorY - 10],
  [397, floorY - 85, floorY - 10],
];
for (const [px, py1, py2] of farPosts) {
  for (let y = py1; y < py2; y++) {
    for (let x = px - 3; x <= px + 3; x++) {
      const highlight = (x < px) ? 10 : -10;
      setPixel(x, y, 110 + highlight);
    }
  }
  drawCircle(px, py1 - 2, 5, 170, true);
  drawCircle(px, py1 - 2, 3, 200, true);
}

// ===== ROPES =====
// Three ropes: white
const ropeYs = [floorY - 62, floorY - 38, floorY - 14];
const ropeBright = [240, 255, 240]; // top, middle (brightest), bottom

for (let ri = 0; ri < 3; ri++) {
  const ry = ropeYs[ri];
  const bright = ropeBright[ri];
  // Front ropes
  drawLine(60, ry + 50, 452, ry + 50, bright, 3);
  // Back ropes (dimmer)
  drawLine(115, ry, 397, ry, Math.round(bright * 0.4), 2);
  // Side ropes
  drawLine(60, ry + 50, 115, ry, Math.round(bright * 0.6), 2);
  drawLine(452, ry + 50, 397, ry, Math.round(bright * 0.6), 2);
}

// ===== LEFT FIGHTER (throwing punch) =====
const lx = 170, ly = 295;

const leftBody = 220;   // light gray figure
const leftGlove = 240;  // bright white glove
const leftTrunks = 80;  // dark gray trunks
const leftShoe = 50;

// Legs
drawLine(lx, ly + 32, lx - 14, ly + 58, leftBody, 6);
drawLine(lx, ly + 32, lx + 16, ly + 58, leftBody, 6);
// Shoes
fillRect(lx - 20, ly + 55, 14, 7, leftShoe);
fillRect(lx + 11, ly + 55, 14, 7, leftShoe);

// Trunks
fillRect(lx - 12, ly + 18, 26, 18, leftTrunks);
// Belt (white stripe)
fillRect(lx - 12, ly + 18, 26, 3, 200);

// Torso - leaning forward into punch
drawLine(lx + 2, ly + 18, lx + 10, ly - 5, leftBody, 10);

// Back arm (guard position)
drawLine(lx + 2, ly - 2, lx - 18, ly + 4, leftBody, 5);
drawLine(lx - 18, ly + 4, lx - 14, ly - 10, leftBody, 5);
drawCircle(lx - 14, ly - 10, 7, leftGlove, true);
// Glove shading
drawCircle(lx - 14, ly - 10, 4, 255, true);

// Punching arm (fully extended)
drawLine(lx + 12, ly - 4, lx + 48, ly - 10, leftBody, 6);
drawLine(lx + 48, ly - 10, lx + 78, ly - 7, leftBody, 6);
// Glove (big, impacting)
drawCircle(lx + 82, ly - 6, 12, leftGlove, true);
drawCircle(lx + 84, ly - 6, 8, 255, true);
// Glove highlight
drawCircle(lx + 82, ly - 9, 3, 255, true);

// Head
drawCircle(lx + 8, ly - 20, 16, leftBody, true);
// Hair/headband darker
for (let angle = -Math.PI; angle < -0.2; angle += 0.04) {
  for (let r = 14; r <= 17; r++) {
    const hx = lx + 8 + Math.cos(angle) * r;
    const hy = ly - 20 + Math.sin(angle) * r;
    setPixel(hx, hy, 100);
  }
}
// Eyes - determined
fillRect(lx + 12, ly - 23, 3, 2, 30);
fillRect(lx + 4, ly - 23, 3, 2, 30);
// Brow
drawLine(lx + 3, ly - 26, lx + 16, ly - 26, 160, 2);
// Mouth (determined grin)
drawLine(lx + 5, ly - 14, lx + 13, ly - 14, 120, 1);

// ===== RIGHT FIGHTER (recoiling from hit) =====
const rx = 335, ry_f = 300;

const rightBody = 190;   // slightly darker gray
const rightGlove = 230;
const rightTrunks = 60;
const rightShoe = 45;

// Legs - stumbling backward
drawLine(rx, ry_f + 32, rx + 18, ry_f + 55, rightBody, 6);
drawLine(rx, ry_f + 32, rx - 12, ry_f + 56, rightBody, 6);
// Shoes
fillRect(rx + 13, ry_f + 52, 14, 7, rightShoe);
fillRect(rx - 18, ry_f + 53, 14, 7, rightShoe);

// Trunks
fillRect(rx - 12, ry_f + 18, 26, 18, rightTrunks);
// Belt
fillRect(rx - 12, ry_f + 18, 26, 3, 180);

// Torso - leaning back from impact
drawLine(rx - 2, ry_f + 18, rx - 12, ry_f - 5, rightBody, 10);

// Arms - flailing from impact
drawLine(rx - 10, ry_f - 2, rx - 32, ry_f - 18, rightBody, 5);
drawLine(rx - 32, ry_f - 18, rx - 44, ry_f - 28, rightBody, 4);
drawCircle(rx - 46, ry_f - 30, 8, rightGlove, true);
drawCircle(rx - 46, ry_f - 30, 5, 255, true);

drawLine(rx - 6, ry_f - 1, rx + 22, ry_f - 22, rightBody, 5);
drawCircle(rx + 24, ry_f - 24, 8, rightGlove, true);
drawCircle(rx + 24, ry_f - 24, 5, 255, true);

// Head - snapping back
drawCircle(rx - 16, ry_f - 22, 16, rightBody, true);
// Hair/headband
for (let angle = -Math.PI; angle < -0.2; angle += 0.04) {
  for (let r = 14; r <= 17; r++) {
    const hx = rx - 16 + Math.cos(angle) * r;
    const hy = ry_f - 22 + Math.sin(angle) * r;
    setPixel(hx, hy, 80);
  }
}
// X eyes (dazed)
drawLine(rx - 21, ry_f - 26, rx - 17, ry_f - 21, 30, 2);
drawLine(rx - 17, ry_f - 26, rx - 21, ry_f - 21, 30, 2);
drawLine(rx - 13, ry_f - 26, rx - 9, ry_f - 21, 30, 2);
drawLine(rx - 9, ry_f - 26, rx - 13, ry_f - 21, 30, 2);
// Open mouth (shock)
drawCircle(rx - 14, ry_f - 12, 4, 60, true);
drawCircle(rx - 14, ry_f - 12, 2, 30, true);

// ===== IMPACT BURST =====
const impactX = 258, impactY = 290;
// Outer glow
drawCircle(impactX, impactY, 22, 100, true, 60);
// Star burst rays
const numRays = 20;
for (let i = 0; i < numRays; i++) {
  const angle = (i / numRays) * Math.PI * 2;
  const len = 20 + (i % 2) * 18;
  const brightness = (i % 2 === 0) ? 255 : 220;
  const ex = impactX + Math.cos(angle) * len;
  const ey = impactY + Math.sin(angle) * len;
  drawLine(impactX, impactY, ex, ey, brightness, 2);
}
// Center bright core
drawCircle(impactX, impactY, 10, 230, true);
drawCircle(impactX, impactY, 6, 255, true);

// Impact particles
const impactParticles = [
  [impactX + 28, impactY - 18], [impactX + 33, impactY + 12],
  [impactX - 22, impactY - 22], [impactX + 18, impactY + 22],
  [impactX - 18, impactY + 18], [impactX + 38, impactY - 8],
  [impactX - 30, impactY + 5], [impactX + 10, impactY - 30],
];
for (const [px, py] of impactParticles) {
  drawCircle(px, py, 2, 240, true);
}

// ===== SWEAT DROPS from right fighter =====
const sweatDrops = [
  [rx + 8, ry_f - 40], [rx + 18, ry_f - 34], [rx - 28, ry_f - 34],
  [rx + 24, ry_f - 18], [rx - 34, ry_f - 14], [rx + 2, ry_f - 42],
];
for (const [sx, sy] of sweatDrops) {
  // Teardrop: bright white
  setPixel(sx, sy - 3, 220);
  setPixel(sx, sy - 2, 240);
  setPixel(sx - 1, sy - 1, 200);
  setPixel(sx, sy - 1, 255);
  setPixel(sx + 1, sy - 1, 200);
  setPixel(sx - 1, sy, 220);
  setPixel(sx, sy, 255);
  setPixel(sx + 1, sy, 220);
  setPixel(sx, sy + 1, 200);
}

// ===== MOTION LINES (speed lines from punch) =====
for (let i = 0; i < 10; i++) {
  const my = ly - 15 + i * 4;
  const mx1 = lx + 35 + srand() * 12;
  const mx2 = mx1 + 20 + srand() * 18;
  drawLine(mx1, my, mx2, my, 255, 1, 110);
}

// Motion lines behind right fighter's head (recoil direction)
for (let i = 0; i < 6; i++) {
  const my = ry_f - 30 + i * 5;
  const mx1 = rx - 2;
  const mx2 = rx + 18 + srand() * 12;
  drawLine(mx1, my, mx2, my, 200, 1, 90);
}

// ===== TITLE "KNOCKOUT!" =====
const letterData = {
  'K': [
    "##...##",
    "##..##.",
    "##.##..",
    "####...",
    "##.##..",
    "##..##.",
    "##...##"
  ],
  'N': [
    "##...##",
    "###..##",
    "####.##",
    "##.####",
    "##..###",
    "##...##",
    "##...##"
  ],
  'O': [
    ".#####.",
    "##...##",
    "##...##",
    "##...##",
    "##...##",
    "##...##",
    ".#####."
  ],
  'C': [
    ".#####.",
    "##...##",
    "##.....",
    "##.....",
    "##.....",
    "##...##",
    ".#####."
  ],
  'U': [
    "##...##",
    "##...##",
    "##...##",
    "##...##",
    "##...##",
    "##...##",
    ".#####."
  ],
  'T': [
    "#######",
    "..##...",
    "..##...",
    "..##...",
    "..##...",
    "..##...",
    "..##..."
  ],
  '!': [
    "..##...",
    "..##...",
    "..##...",
    "..##...",
    "..##...",
    ".......",
    "..##..."
  ],
};

const title = "KNOCKOUT!";
const letterW = 7, letterH = 7, scale = 5, spacing = 3;
const totalW = title.length * (letterW * scale + spacing * scale) - spacing * scale;
let startX = Math.round((W - totalW) / 2);
const titleY = 50;

// Title shadow (dark, offset)
for (let ci = 0; ci < title.length; ci++) {
  const ch = title[ci];
  const data = letterData[ch];
  if (!data) continue;
  const ox = startX + ci * (letterW * scale + spacing * scale) + 4;
  const oy = titleY + 4;
  for (let row = 0; row < letterH; row++) {
    for (let col = 0; col < data[row].length; col++) {
      if (data[row][col] === '#') {
        fillRect(ox + col * scale, oy + row * scale, scale, scale, 0, 180);
      }
    }
  }
}

// Title outline (medium gray, thicker)
for (let ci = 0; ci < title.length; ci++) {
  const ch = title[ci];
  const data = letterData[ch];
  if (!data) continue;
  const ox = startX + ci * (letterW * scale + spacing * scale);
  const oy = titleY;
  for (let row = 0; row < letterH; row++) {
    for (let col = 0; col < data[row].length; col++) {
      if (data[row][col] === '#') {
        fillRect(ox + col * scale - 2, oy + row * scale - 2, scale + 4, scale + 4, 120);
      }
    }
  }
}

// Title main text - gradient from white to light gray
for (let ci = 0; ci < title.length; ci++) {
  const ch = title[ci];
  const data = letterData[ch];
  if (!data) continue;
  const ox = startX + ci * (letterW * scale + spacing * scale);
  const oy = titleY;
  for (let row = 0; row < letterH; row++) {
    const t = row / letterH;
    const v = Math.round(255 - t * 50); // white to light gray gradient
    for (let col = 0; col < data[row].length; col++) {
      if (data[row][col] === '#') {
        fillRect(ox + col * scale, oy + row * scale, scale, scale, v);
      }
    }
  }
}

// ===== DECORATIVE SPEED LINES around title =====
for (let i = 0; i < 6; i++) {
  const sx = 75 + i * 65;
  drawLine(sx, titleY - 12, sx - 18, titleY - 30, 180, 1, 70);
  drawLine(sx + 10, titleY + letterH * scale + 18, sx + 28, titleY + letterH * scale + 36, 180, 1, 70);
}

// ===== RING APRON (bottom) =====
for (let y = 435; y < 460; y++) {
  for (let x = 45; x < 467; x++) {
    const stripe = Math.floor((x - 45) / 22) % 2 === 0;
    setPixel(x, y, stripe ? 100 : 40);
  }
}
// Bottom shadow below apron
for (let y = 460; y < 480; y++) {
  for (let x = 45; x < 467; x++) {
    const fade = (y - 460) / 20;
    setPixel(x, y, Math.round(20 * (1 - fade)), Math.round(200 * (1 - fade)));
  }
}

// ===== ROUND CORNERS =====
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    if (!isInRoundedRect(x, y, W, H, 64)) {
      const idx = (y * W + x) * 4;
      png.data[idx] = 0;
      png.data[idx + 1] = 0;
      png.data[idx + 2] = 0;
      png.data[idx + 3] = 0;
    }
  }
}

// ===== SAVE =====
const outPath = "/Users/ssk/mono/contest/entries/agent-theta/publish/icon-512.png";
const buffer = PNG.sync.write(png);
fs.writeFileSync(outPath, buffer);
console.log("Icon saved to", outPath, "- size:", buffer.length, "bytes");
