const { PNG } = require("/Users/ssk/work/mono/node_modules/pngjs");
const fs = require("fs");

const W = 512, H = 512, R = 64;
const png = new PNG({ width: W, height: H });

function setPixel(x, y, gray, alpha) {
  if (x < 0 || x >= W || y < 0 || y >= H) return;
  const i = (y * W + x) * 4;
  const a = alpha / 255;
  const existing_a = png.data[i + 3] / 255;
  const out_a = a + existing_a * (1 - a);
  if (out_a === 0) return;
  const blended = (gray * a + png.data[i] * existing_a * (1 - a)) / out_a;
  png.data[i] = png.data[i + 1] = png.data[i + 2] = Math.round(blended);
  png.data[i + 3] = Math.round(out_a * 255);
}

function fillRect(x1, y1, w, h, gray, alpha = 255) {
  for (let y = y1; y < y1 + h; y++)
    for (let x = x1; x < x1 + w; x++)
      setPixel(x, y, gray, alpha);
}

function fillCircle(cx, cy, r, gray, alpha = 255) {
  for (let y = cy - r; y <= cy + r; y++)
    for (let x = cx - r; x <= cx + r; x++)
      if ((x - cx) ** 2 + (y - cy) ** 2 <= r * r)
        setPixel(x, y, gray, alpha);
}

function fillEllipse(cx, cy, rx, ry, gray, alpha = 255) {
  for (let y = cy - ry; y <= cy + ry; y++)
    for (let x = cx - rx; x <= cx + rx; x++)
      if (((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1)
        setPixel(x, y, gray, alpha);
}

function drawLine(x1, y1, x2, y2, thickness, gray, alpha = 255) {
  const dx = x2 - x1, dy = y2 - y1;
  const len = Math.sqrt(dx * dx + dy * dy);
  const steps = Math.ceil(len * 2);
  for (let s = 0; s <= steps; s++) {
    const t = s / steps;
    const cx = x1 + dx * t, cy = y1 + dy * t;
    fillCircle(Math.round(cx), Math.round(cy), thickness, gray, alpha);
  }
}

function inRoundedRect(x, y, w, h, r) {
  if (x < 0 || x >= w || y < 0 || y >= h) return false;
  if (x < r && y < r && (x - r) ** 2 + (y - r) ** 2 > r * r) return false;
  if (x >= w - r && y < r && (x - (w - r - 1)) ** 2 + (y - r) ** 2 > r * r) return false;
  if (x < r && y >= h - r && (x - r) ** 2 + (y - (h - r - 1)) ** 2 > r * r) return false;
  if (x >= w - r && y >= h - r && (x - (w - r - 1)) ** 2 + (y - (h - r - 1)) ** 2 > r * r) return false;
  return true;
}

// Initialize all pixels transparent
for (let i = 0; i < W * H * 4; i++) png.data[i] = 0;

// Fill background with dark gray, respecting rounded corners
for (let y = 0; y < H; y++)
  for (let x = 0; x < W; x++)
    if (inRoundedRect(x, y, W, H, R))
      setPixel(x, y, 18, 255);

// Subtle radial gradient overlay (lighter center)
for (let y = 0; y < H; y++)
  for (let x = 0; x < W; x++) {
    if (!inRoundedRect(x, y, W, H, R)) continue;
    const dist = Math.sqrt((x - 256) ** 2 + (y - 220) ** 2);
    const glow = Math.max(0, 1 - dist / 350) * 25;
    if (glow > 0) setPixel(x, y, 18 + glow, 255);
  }

// Stars in background
const starSeed = [
  [45, 30], [120, 55], [380, 40], [450, 70], [90, 100], [310, 25],
  [200, 60], [470, 110], [60, 150], [420, 150], [150, 20], [350, 80],
  [250, 35], [480, 50], [30, 90], [170, 110], [290, 15], [410, 95],
  [75, 45], [330, 65], [190, 85], [440, 35], [260, 105], [100, 135],
  [360, 120], [220, 140], [50, 170], [390, 160], [140, 160], [470, 175],
  [280, 55], [130, 75], [320, 145], [460, 130], [85, 115], [230, 50],
  [400, 105], [160, 140], [340, 30], [500, 90]
];
for (const [sx, sy] of starSeed) {
  const brightness = 100 + Math.floor(Math.abs(Math.sin(sx * sy)) * 155);
  const size = Math.abs(Math.sin(sx + sy)) > 0.7 ? 2 : 1;
  fillCircle(sx, sy, size, brightness, 180 + Math.floor(Math.abs(Math.sin(sx)) * 75));
}

// Larger accent stars with cross pattern
const bigStars = [[80, 60], [430, 45], [350, 100], [180, 130], [470, 155]];
for (const [sx, sy] of bigStars) {
  fillCircle(sx, sy, 2, 220, 255);
  for (let d = -5; d <= 5; d++) {
    const a = Math.max(0, 255 - Math.abs(d) * 60);
    setPixel(sx + d, sy, 200, a);
    setPixel(sx, sy + d, 200, a);
  }
}

// --- PLATFORMS ---
// Main platform (character leaps from here)
fillRect(60, 300, 160, 16, 90, 255);
fillRect(60, 316, 160, 4, 60, 255);
fillRect(60, 298, 160, 2, 130, 200);

// Target platform (upper right)
fillRect(310, 230, 140, 16, 90, 255);
fillRect(310, 246, 140, 4, 60, 255);
fillRect(310, 228, 140, 2, 130, 200);

// Small floating platform (middle)
fillRect(230, 270, 70, 12, 80, 255);
fillRect(230, 282, 70, 3, 55, 255);
fillRect(230, 268, 70, 2, 120, 200);

// Lower platform (bottom right)
fillRect(370, 350, 120, 14, 85, 255);
fillRect(370, 364, 120, 3, 55, 255);
fillRect(370, 348, 120, 2, 120, 200);

// Small high platform (top left)
fillRect(150, 195, 80, 10, 75, 255);
fillRect(150, 205, 80, 3, 50, 255);
fillRect(150, 193, 80, 2, 115, 200);

// --- CHARACTER (white silhouette mid-dash/leap) ---
const charX = 210, charY = 250;

// Head
fillCircle(charX + 5, charY - 28, 12, 245, 255);

// Torso (angled forward)
for (let t = 0; t < 30; t++) {
  const tx = charX + t * 0.4;
  const ty = charY - 20 + t * 0.7;
  fillCircle(Math.round(tx), Math.round(ty), 7, 240, 255);
}

// Leading arm (stretched forward)
drawLine(charX + 8, charY - 12, charX + 35, charY - 25, 4, 240, 255);

// Trailing arm (back)
drawLine(charX - 2, charY - 10, charX - 22, charY + 5, 4, 235, 255);

// Leading leg (stretched forward)
drawLine(charX + 8, charY + 8, charX + 32, charY - 2, 5, 240, 255);
fillEllipse(charX + 35, charY - 3, 7, 4, 235, 255);

// Trailing leg (kicked back)
drawLine(charX - 2, charY + 8, charX - 25, charY + 18, 5, 235, 255);
fillEllipse(charX - 28, charY + 19, 7, 4, 230, 255);

// --- SPEED/DASH TRAIL LINES ---
const trailLines = [
  { y: charY - 20, len: 80, gray: 200, alpha: 180 },
  { y: charY - 10, len: 100, gray: 180, alpha: 150 },
  { y: charY, len: 90, gray: 160, alpha: 130 },
  { y: charY + 10, len: 70, gray: 140, alpha: 110 },
  { y: charY - 30, len: 50, gray: 170, alpha: 120 },
];

for (const trail of trailLines) {
  const startX = charX - 30;
  for (let i = 0; i < trail.len; i++) {
    const fade = 1 - (i / trail.len);
    const x = startX - i;
    const thickness = Math.max(1, Math.floor(3 * fade));
    const a = Math.floor(trail.alpha * fade * fade);
    for (let dy = -thickness; dy <= thickness; dy++) {
      setPixel(x, trail.y + dy, trail.gray, a);
    }
  }
}

// Dash particles
const particles = [
  [charX - 40, charY - 15, 3], [charX - 55, charY - 5, 2],
  [charX - 50, charY + 5, 2], [charX - 65, charY - 20, 2],
  [charX - 70, charY + 10, 1], [charX - 35, charY + 15, 2],
  [charX - 80, charY - 8, 1], [charX - 45, charY - 25, 2],
];
for (const [px, py, pr] of particles) {
  fillCircle(px, py, pr, 180, 120);
}

// Character glow effect
for (let y = charY - 45; y < charY + 30; y++)
  for (let x = charX - 20; x < charX + 45; x++) {
    if (!inRoundedRect(x, y, W, H, R)) continue;
    const dist = Math.sqrt((x - charX - 10) ** 2 + (y - charY - 5) ** 2);
    if (dist < 55 && dist > 25) {
      const glow = Math.max(0, (1 - (dist - 25) / 30)) * 40;
      setPixel(x, y, 80, Math.floor(glow));
    }
  }

// Wall jump marks on left edge
for (let i = 0; i < 3; i++) {
  const wy = 220 + i * 25;
  for (let j = 0; j < 8; j++) {
    const fade = 1 - j / 8;
    setPixel(55 + j, wy, 150, Math.floor(fade * 120));
    setPixel(55 + j, wy + 1, 130, Math.floor(fade * 100));
  }
}

// --- TITLE "SHADOW LEAP" ---
const font = {
  S: ["01110","10001","10000","01110","00001","10001","01110"],
  H: ["10001","10001","10001","11111","10001","10001","10001"],
  A: ["01110","10001","10001","11111","10001","10001","10001"],
  D: ["11100","10010","10001","10001","10001","10010","11100"],
  O: ["01110","10001","10001","10001","10001","10001","01110"],
  W: ["10001","10001","10001","10101","10101","11011","10001"],
  L: ["10000","10000","10000","10000","10000","10000","11111"],
  E: ["11111","10000","10000","11110","10000","10000","11111"],
  P: ["11110","10001","10001","11110","10000","10000","10000"],
  " ": ["00000","00000","00000","00000","00000","00000","00000"]
};

const title = "SHADOW LEAP";
const scale = 4;
const charWidth = 5 * scale + scale;
const totalWidth = title.length * charWidth - scale;
const titleX = Math.floor((W - totalWidth) / 2);
const titleY = 430;

// Title shadow
for (let ci = 0; ci < title.length; ci++) {
  const ch = title[ci];
  const glyph = font[ch];
  if (!glyph) continue;
  for (let row = 0; row < 7; row++)
    for (let col = 0; col < 5; col++)
      if (glyph[row][col] === "1")
        fillRect(titleX + ci * charWidth + col * scale + 2, titleY + row * scale + 2, scale, scale, 0, 120);
}

// Title text
for (let ci = 0; ci < title.length; ci++) {
  const ch = title[ci];
  const glyph = font[ch];
  if (!glyph) continue;
  for (let row = 0; row < 7; row++)
    for (let col = 0; col < 5; col++)
      if (glyph[row][col] === "1") {
        const brightness = 230 + Math.floor((row / 7) * 25);
        fillRect(titleX + ci * charWidth + col * scale, titleY + row * scale, scale, scale, brightness, 255);
      }
}

// Underline accent below title
const lineY = titleY + 7 * scale + 8;
for (let x = titleX + 20; x < titleX + totalWidth - 20; x++) {
  const dist = Math.abs(x - (titleX + totalWidth / 2));
  const maxDist = (totalWidth - 40) / 2;
  const fade = 1 - dist / maxDist;
  setPixel(x, lineY, 160, Math.floor(fade * 180));
  setPixel(x, lineY + 1, 120, Math.floor(fade * 100));
}

// Final: ensure pixels outside rounded rect are transparent
for (let y = 0; y < H; y++)
  for (let x = 0; x < W; x++)
    if (!inRoundedRect(x, y, W, H, R)) {
      const i = (y * W + x) * 4;
      png.data[i] = png.data[i + 1] = png.data[i + 2] = png.data[i + 3] = 0;
    }

// Write output
const outPath = "/Users/ssk/mono/contest/entries/agent-beta/publish/icon-512.png";
const buffer = PNG.sync.write(png);
fs.writeFileSync(outPath, buffer);
console.log("Icon written to", outPath, "(" + buffer.length + " bytes)");
