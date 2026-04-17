const { PNG } = require("/Users/ssk/work/mono/node_modules/pngjs");
const fs = require("fs");

const W = 512, H = 512, R = 64;
const png = new PNG({ width: W, height: H });

function setPixel(x, y, gray, alpha = 255) {
  if (x < 0 || x >= W || y < 0 || y >= H) return;
  const i = (y * W + x) * 4;
  const a = alpha / 255;
  const existing = png.data[i];
  const existingA = png.data[i + 3] / 255;
  const blended = Math.round(existing * existingA * (1 - a) / Math.max(0.001, existingA * (1 - a) + a) + gray * a / Math.max(0.001, existingA * (1 - a) + a));
  const newA = Math.min(255, Math.round((existingA * (1 - a) + a) * 255));
  png.data[i] = Math.min(255, blended);
  png.data[i + 1] = Math.min(255, blended);
  png.data[i + 2] = Math.min(255, blended);
  png.data[i + 3] = newA;
}

function fillRect(x0, y0, w, h, gray, alpha = 255) {
  for (let y = y0; y < y0 + h; y++)
    for (let x = x0; x < x0 + w; x++)
      setPixel(x, y, gray, alpha);
}

function isInsideRoundedRect(x, y, r) {
  if (x < r && y < r) {
    const dx = r - x, dy = r - y;
    return dx * dx + dy * dy <= r * r;
  }
  if (x >= W - r && y < r) {
    const dx = x - (W - r - 1), dy = r - y;
    return dx * dx + dy * dy <= r * r;
  }
  if (x < r && y >= H - r) {
    const dx = r - x, dy = y - (H - r - 1);
    return dx * dx + dy * dy <= r * r;
  }
  if (x >= W - r && y >= H - r) {
    const dx = x - (W - r - 1), dy = y - (H - r - 1);
    return dx * dx + dy * dy <= r * r;
  }
  return true;
}

// Fill background dark gray with rounded corners
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    const i = (y * W + x) * 4;
    if (isInsideRoundedRect(x, y, R)) {
      const g = Math.round(12 + (y / H) * 18);
      png.data[i] = g;
      png.data[i + 1] = g;
      png.data[i + 2] = g;
      png.data[i + 3] = 255;
    } else {
      png.data[i] = 0;
      png.data[i + 1] = 0;
      png.data[i + 2] = 0;
      png.data[i + 3] = 0;
    }
  }
}

// --- Radiating burst lines from center ---
const cx = W / 2, cy = H / 2 - 20;
const numRays = 24;
for (let r = 0; r < numRays; r++) {
  const angle = (r / numRays) * Math.PI * 2;
  const length = 220;
  for (let d = 40; d < length; d++) {
    const x = Math.round(cx + Math.cos(angle) * d);
    const y = Math.round(cy + Math.sin(angle) * d);
    const fade = Math.max(0, 1 - d / length);
    const gray = Math.round(50 * fade);
    setPixel(x, y, gray, Math.round(180 * fade));
    setPixel(x + 1, y, gray, Math.round(120 * fade));
    setPixel(x, y + 1, gray, Math.round(120 * fade));
  }
}

// --- 4 vertical lane lines ---
const laneXs = [153, 217, 281, 345];
const laneTop = 60, laneBot = 400;
for (const lx of laneXs) {
  for (let y = laneTop; y < laneBot; y++) {
    let fade = 1;
    if (y < laneTop + 40) fade = (y - laneTop) / 40;
    if (y > laneBot - 40) fade = (laneBot - y) / 40;
    const g = Math.round(55 * fade);
    setPixel(lx, y, g, Math.round(200 * fade));
    setPixel(lx + 1, y, g, Math.round(140 * fade));
  }
}

// --- Lane separator lines (between lanes) ---
const sepXs = [185, 249, 313];
for (const sx of sepXs) {
  for (let y = laneTop + 20; y < laneBot - 10; y++) {
    let fade = 1;
    if (y < laneTop + 60) fade = (y - laneTop - 20) / 40;
    if (y > laneBot - 50) fade = (laneBot - 10 - y) / 40;
    setPixel(sx, y, 35, Math.round(100 * fade));
  }
}

// --- Note markers (bright white/light gray rectangles) ---
const notes = [
  { lane: 0, y: 110, gray: 240 },
  { lane: 2, y: 130, gray: 220 },
  { lane: 1, y: 185, gray: 255 },
  { lane: 3, y: 200, gray: 200 },
  { lane: 0, y: 260, gray: 230 },
  { lane: 3, y: 270, gray: 255 },
  { lane: 1, y: 310, gray: 210 },
  { lane: 2, y: 325, gray: 245 },
  { lane: 0, y: 355, gray: 255 },
  { lane: 2, y: 365, gray: 235 },
];

const noteW = 42, noteH = 14;
for (const note of notes) {
  const nx = laneXs[note.lane] - noteW / 2 + 1;
  const ny = note.y;
  fillRect(nx, ny, noteW, noteH, note.gray, 230);
  // Glow border
  fillRect(nx - 1, ny - 1, noteW + 2, 1, note.gray, 60);
  fillRect(nx - 1, ny + noteH, noteW + 2, 1, note.gray, 60);
  fillRect(nx - 1, ny, 1, noteH, note.gray, 60);
  fillRect(nx + noteW, ny, 1, noteH, note.gray, 60);
}

// --- Bright horizontal hit-zone line near bottom ---
const hitY = 385;
for (let x = 130; x < 370; x++) {
  const distFromCenter = Math.abs(x - 250) / 120;
  const brightness = Math.round(255 - distFromCenter * 30);
  setPixel(x, hitY, brightness, 255);
  setPixel(x, hitY + 1, brightness, 255);
  setPixel(x, hitY + 2, Math.round(brightness * 0.7), 200);
  setPixel(x, hitY - 1, Math.round(brightness * 0.7), 200);
  setPixel(x, hitY + 3, Math.round(brightness * 0.3), 120);
  setPixel(x, hitY - 2, Math.round(brightness * 0.3), 120);
  setPixel(x, hitY + 4, Math.round(brightness * 0.15), 60);
  setPixel(x, hitY - 3, Math.round(brightness * 0.15), 60);
}

// Hit zone diamond markers at each lane
for (const lx of laneXs) {
  const size = 8;
  for (let dy = -size; dy <= size; dy++) {
    for (let dx = -size; dx <= size; dx++) {
      if (Math.abs(dx) + Math.abs(dy) <= size) {
        const dist = (Math.abs(dx) + Math.abs(dy)) / size;
        const g = Math.round(255 * (1 - dist * 0.5));
        setPixel(lx + dx, hitY + dy, g, Math.round(200 * (1 - dist * 0.6)));
      }
    }
  }
}

// --- Musical note symbols ---
function drawMusicalNote(ox, oy, scale, gray) {
  const hw = Math.round(6 * scale), hh = Math.round(4 * scale);
  for (let dy = -hh; dy <= hh; dy++) {
    for (let dx = -hw; dx <= hw; dx++) {
      const rx = dx * 0.9 + dy * 0.4;
      const ry = -dx * 0.4 + dy * 0.9;
      if ((rx * rx) / (hw * hw) + (ry * ry) / (hh * hh) <= 1) {
        setPixel(ox + dx, oy + dy, gray, 200);
      }
    }
  }
  const stemH = Math.round(22 * scale);
  for (let dy = 0; dy < stemH; dy++) {
    setPixel(ox + hw - 1, oy - dy, gray, 200);
    setPixel(ox + hw, oy - dy, gray, 200);
  }
  const flagTop = oy - stemH + 1;
  for (let i = 0; i < Math.round(10 * scale); i++) {
    const fx = ox + hw + Math.round(i * 0.8);
    const fy = flagTop + Math.round(i * 0.6);
    setPixel(fx, fy, gray, 180);
    setPixel(fx, fy + 1, gray, 140);
    setPixel(fx + 1, fy, gray, 120);
  }
}

drawMusicalNote(80, 140, 1.1, 110);
drawMusicalNote(430, 120, 0.9, 90);
drawMusicalNote(65, 300, 0.8, 80);
drawMusicalNote(445, 280, 1.0, 100);
drawMusicalNote(95, 220, 0.7, 70);
drawMusicalNote(415, 210, 0.75, 85);

// --- Title "MONO BEAT" ---
const font = {
  'M': [
    "X...X",
    "XX.XX",
    "X.X.X",
    "X...X",
    "X...X",
    "X...X",
    "X...X",
  ],
  'O': [
    ".XXX.",
    "X...X",
    "X...X",
    "X...X",
    "X...X",
    "X...X",
    ".XXX.",
  ],
  'N': [
    "X...X",
    "XX..X",
    "XX..X",
    "X.X.X",
    "X..XX",
    "X..XX",
    "X...X",
  ],
  'B': [
    "XXXX.",
    "X...X",
    "X...X",
    "XXXX.",
    "X...X",
    "X...X",
    "XXXX.",
  ],
  'E': [
    "XXXXX",
    "X....",
    "X....",
    "XXXX.",
    "X....",
    "X....",
    "XXXXX",
  ],
  'A': [
    ".XXX.",
    "X...X",
    "X...X",
    "XXXXX",
    "X...X",
    "X...X",
    "X...X",
  ],
  'T': [
    "XXXXX",
    "..X..",
    "..X..",
    "..X..",
    "..X..",
    "..X..",
    "..X..",
  ],
  ' ': [
    "...",
    "...",
    "...",
    "...",
    "...",
    "...",
    "...",
  ],
};

function drawText(text, startX, startY, pixelSize, gray, alpha = 255) {
  let curX = startX;
  for (const ch of text) {
    const glyph = font[ch];
    if (!glyph) { curX += 4 * pixelSize; continue; }
    for (let row = 0; row < glyph.length; row++) {
      for (let col = 0; col < glyph[row].length; col++) {
        if (glyph[row][col] === 'X') {
          fillRect(curX + col * pixelSize, startY + row * pixelSize, pixelSize, pixelSize, gray, alpha);
        }
      }
    }
    curX += (glyph[0].length + 1) * pixelSize;
  }
}

function measureText(text, pixelSize) {
  let w = 0;
  for (const ch of text) {
    const glyph = font[ch];
    if (!glyph) { w += 4 * pixelSize; continue; }
    w += (glyph[0].length + 1) * pixelSize;
  }
  return w - pixelSize;
}

const titleText = "MONO BEAT";
const pxSize = 5;
const textW = measureText(titleText, pxSize);
const textX = Math.round((W - textW) / 2);
const textY = 440;

// Shadow
drawText(titleText, textX + 2, textY + 2, pxSize, 30, 180);
// Main text
drawText(titleText, textX, textY, pxSize, 235, 255);
// Highlight top edge
drawText(titleText, textX, textY - 1, pxSize, 255, 140);

// --- Vignette effect ---
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    if (!isInsideRoundedRect(x, y, R)) continue;
    const dx = (x - W / 2) / (W / 2);
    const dy = (y - H / 2) / (H / 2);
    const dist = Math.sqrt(dx * dx + dy * dy);
    if (dist > 0.6) {
      const darken = Math.min(1, (dist - 0.6) / 0.8);
      const i = (y * W + x) * 4;
      png.data[i] = Math.round(png.data[i] * (1 - darken * 0.4));
      png.data[i + 1] = Math.round(png.data[i + 1] * (1 - darken * 0.4));
      png.data[i + 2] = Math.round(png.data[i + 2] * (1 - darken * 0.4));
    }
  }
}

// --- Thin border ---
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    if (!isInsideRoundedRect(x, y, R)) continue;
    const isEdge = !isInsideRoundedRect(x - 2, y, R) || !isInsideRoundedRect(x + 2, y, R) ||
      !isInsideRoundedRect(x, y - 2, R) || !isInsideRoundedRect(x, y + 2, R) ||
      x <= 1 || x >= W - 2 || y <= 1 || y >= H - 2;
    if (isEdge) {
      const i = (y * W + x) * 4;
      png.data[i] = 60;
      png.data[i + 1] = 60;
      png.data[i + 2] = 60;
      png.data[i + 3] = 255;
    }
  }
}

// Write output
const outPath = "/Users/ssk/mono/contest/entries/agent-epsilon/publish/icon-512.png";
const buffer = PNG.sync.write(png);
fs.writeFileSync(outPath, buffer);
console.log(`Icon written to ${outPath} (${buffer.length} bytes)`);
