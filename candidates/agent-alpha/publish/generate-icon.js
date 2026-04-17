const { PNG } = require("/Users/ssk/work/mono/node_modules/pngjs");
const fs = require("fs");

const W = 512, H = 512;
const png = new PNG({ width: W, height: H });

// --- Utility functions (GRAYSCALE ONLY) ---
function setPixel(x, y, v, a = 255) {
  x = Math.round(x); y = Math.round(y);
  if (x < 0 || x >= W || y < 0 || y >= H) return;
  const idx = (y * W + x) * 4;
  if (a < 255) {
    const aa = a / 255;
    const inv = 1 - aa;
    const old = png.data[idx];
    const blended = Math.round(old * inv + v * aa);
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

function getPixelV(x, y) {
  x = Math.round(x); y = Math.round(y);
  if (x < 0 || x >= W || y < 0 || y >= H) return 0;
  const idx = (y * W + x) * 4;
  return png.data[idx];
}

function fillRect(x, y, w, h, v, a = 255) {
  for (let dy = 0; dy < h; dy++)
    for (let dx = 0; dx < w; dx++)
      setPixel(x + dx, y + dy, v, a);
}

function fillCircle(cx, cy, radius, v, a = 255) {
  for (let dy = -radius; dy <= radius; dy++)
    for (let dx = -radius; dx <= radius; dx++)
      if (dx * dx + dy * dy <= radius * radius)
        setPixel(cx + dx, cy + dy, v, a);
}

// Draw anti-aliased arc
function fillArcAA(cx, cy, outerR, innerR, startA, endA, v) {
  for (let dy = -outerR - 2; dy <= outerR + 2; dy++)
    for (let dx = -outerR - 2; dx <= outerR + 2; dx++) {
      const d = Math.sqrt(dx * dx + dy * dy);
      let angle = Math.atan2(dy, dx);
      while (angle < startA) angle += Math.PI * 2;
      while (angle > startA + Math.PI * 2) angle -= Math.PI * 2;
      if (angle > endA) continue;

      let alpha = 0;
      if (d >= innerR && d <= outerR) {
        alpha = 1;
      } else if (d > outerR && d < outerR + 1.5) {
        alpha = 1 - (d - outerR) / 1.5;
      } else if (d < innerR && d > innerR - 1.5) {
        alpha = 1 - (innerR - d) / 1.5;
      }
      const fadeAngle = 0.05;
      const fromStart = angle - startA;
      const fromEnd = endA - angle;
      if (fromStart < fadeAngle) alpha *= fromStart / fadeAngle;
      if (fromEnd < fadeAngle) alpha *= fromEnd / fadeAngle;

      if (alpha > 0) setPixel(cx + dx, cy + dy, v, Math.round(alpha * 255));
    }
}

// Draw a filled triangle
function fillTriangle(x1, y1, x2, y2, x3, y3, v, a = 255) {
  const minX = Math.floor(Math.min(x1, x2, x3));
  const maxX = Math.ceil(Math.max(x1, x2, x3));
  const minY = Math.floor(Math.min(y1, y2, y3));
  const maxY = Math.ceil(Math.max(y1, y2, y3));
  for (let y = minY; y <= maxY; y++)
    for (let x = minX; x <= maxX; x++) {
      const d1 = (x - x2) * (y1 - y2) - (x1 - x2) * (y - y2);
      const d2 = (x - x3) * (y2 - y3) - (x2 - x3) * (y - y3);
      const d3 = (x - x1) * (y3 - y1) - (x3 - x1) * (y - y1);
      const hasNeg = (d1 < 0) || (d2 < 0) || (d3 < 0);
      const hasPos = (d1 > 0) || (d2 > 0) || (d3 > 0);
      if (!(hasNeg && hasPos)) setPixel(x, y, v, a);
    }
}

// Draw arrowhead at angle position on a circle
function drawArrowhead(cx, cy, radius, angle, v, size = 18) {
  const tipX = cx + radius * Math.cos(angle);
  const tipY = cy + radius * Math.sin(angle);
  const tangentAngle = angle + Math.PI / 2;
  const backAngle1 = tangentAngle + 2.5;
  const backAngle2 = tangentAngle - 2.5;
  const bx1 = tipX + size * Math.cos(backAngle1);
  const by1 = tipY + size * Math.sin(backAngle1);
  const bx2 = tipX + size * Math.cos(backAngle2);
  const by2 = tipY + size * Math.sin(backAngle2);
  fillTriangle(tipX, tipY, bx1, by1, bx2, by2, v);
}

// Pixel font data for GRAVITON letters (5x7 grid each)
const FONT = {
  G: [
    "01110",
    "10001",
    "10000",
    "10110",
    "10001",
    "10001",
    "01110",
  ],
  R: [
    "11110",
    "10001",
    "10001",
    "11110",
    "10010",
    "10001",
    "10001",
  ],
  A: [
    "01110",
    "10001",
    "10001",
    "11111",
    "10001",
    "10001",
    "10001",
  ],
  V: [
    "10001",
    "10001",
    "10001",
    "10001",
    "01010",
    "01010",
    "00100",
  ],
  I: [
    "11111",
    "00100",
    "00100",
    "00100",
    "00100",
    "00100",
    "11111",
  ],
  T: [
    "11111",
    "00100",
    "00100",
    "00100",
    "00100",
    "00100",
    "00100",
  ],
  O: [
    "01110",
    "10001",
    "10001",
    "10001",
    "10001",
    "10001",
    "01110",
  ],
  N: [
    "10001",
    "11001",
    "10101",
    "10011",
    "10001",
    "10001",
    "10001",
  ],
};

// Big "G" font (11x14 grid for center display)
const BIG_G = [
  "00111111100",
  "01111111110",
  "11100000111",
  "11100000011",
  "11100000000",
  "11100000000",
  "11100000000",
  "11100111111",
  "11100111111",
  "11100000111",
  "11100000111",
  "01110000111",
  "01111111110",
  "00111111100",
];

function drawChar(ch, startX, startY, scale, v, a = 255) {
  const data = FONT[ch];
  if (!data) return;
  for (let row = 0; row < data.length; row++)
    for (let col = 0; col < data[row].length; col++)
      if (data[row][col] === "1")
        fillRect(startX + col * scale, startY + row * scale, scale, scale, v, a);
}

function drawText(text, startX, startY, scale, spacing, v, a = 255) {
  let x = startX;
  for (const ch of text) {
    drawChar(ch, x, startY, scale, v, a);
    x += (5 * scale) + spacing;
  }
}

function drawBigG(startX, startY, scale, v) {
  for (let row = 0; row < BIG_G.length; row++)
    for (let col = 0; col < BIG_G[row].length; col++)
      if (BIG_G[row][col] === "1")
        fillRect(startX + col * scale, startY + row * scale, scale, scale, v);
}

// === RENDER ===

// --- Step 1: Dark background gradient (grayscale) ---
for (let y = 0; y < H; y++) {
  const t = y / H;
  const v = Math.round(28 * (1 - t) + 14 * t);
  for (let x = 0; x < W; x++) {
    setPixel(x, y, v);
  }
}

// Subtle radial vignette / glow from center
const vcx = 256, vcy = 210;
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    const dx = x - vcx, dy = y - vcy;
    const d = Math.sqrt(dx * dx + dy * dy);
    const glow = Math.max(0, 1 - d / 320) * 0.15;
    const cv = getPixelV(x, y);
    setPixel(x, y, Math.min(255, Math.round(cv + 60 * glow)));
  }
}

// --- Step 2: Circular rotation arrow ---
const arrowCX = 256, arrowCY = 195;
const outerR = 105, innerR = 80;
const arcVal = 190; // light gray

const startAngle = -0.6;
const endAngle = 4.8;

fillArcAA(arrowCX, arrowCY, outerR, innerR, startAngle, endAngle, arcVal);

// Arrowhead at end of arc
const midR = (outerR + innerR) / 2;
drawArrowhead(arrowCX, arrowCY, midR, endAngle, arcVal, 22);

// Subtle glow behind the ring
for (let dy = -outerR - 15; dy <= outerR + 15; dy++)
  for (let dx = -outerR - 15; dx <= outerR + 15; dx++) {
    const d = Math.sqrt(dx * dx + dy * dy);
    const ringMid = (outerR + innerR) / 2;
    const ringW = (outerR - innerR) / 2;
    const distFromRing = Math.abs(d - ringMid) - ringW;
    if (distFromRing > 0 && distFromRing < 12) {
      const glowA = Math.round((1 - distFromRing / 12) * 30);
      setPixel(arrowCX + dx, arrowCY + dy, 150, glowA);
    }
  }

// --- Step 3: Big "G" in center ---
const gScale = 5;
const gW = 11 * gScale, gH = 14 * gScale;
const gX = arrowCX - gW / 2, gY = arrowCY - gH / 2 - 5;
// Shadow
drawBigG(gX + 2, gY + 2, gScale, 10);
// Main G - bright white
drawBigG(gX, gY, gScale, 240);

// --- Step 4: Small down-arrow below G (gravity indicator) ---
const arrowTipX = 256, arrowTipY = arrowCY + gH / 2 + 28;
// Shaft
fillRect(arrowTipX - 3, arrowCY + gH / 2 - 2, 7, 22, arcVal);
// Arrowhead pointing down
fillTriangle(
  arrowTipX, arrowTipY + 10,
  arrowTipX - 12, arrowTipY - 4,
  arrowTipX + 12, arrowTipY - 4,
  arcVal
);

// --- Step 5: Tetromino blocks scattered in lower area ---
const blockSize = 26;
const blockGap = 2;

const tetrominoes = [
  // T-piece
  { blocks: [[0,0],[1,0],[2,0],[1,1]], val: 140, x: 80, y: 340 },
  // L-piece
  { blocks: [[0,0],[0,1],[0,2],[1,2]], val: 170, x: 180, y: 350 },
  // S-piece
  { blocks: [[1,0],[2,0],[0,1],[1,1]], val: 120, x: 290, y: 345 },
  // Square
  { blocks: [[0,0],[1,0],[0,1],[1,1]], val: 200, x: 370, y: 355 },
  // I-piece (vertical, partial)
  { blocks: [[0,0],[0,1],[0,2]], val: 100, x: 135, y: 370 },
  // Z-piece
  { blocks: [[0,0],[1,0],[1,1],[2,1]], val: 155, x: 240, y: 375 },
  // Another L
  { blocks: [[0,0],[1,0],[1,1],[1,2]], val: 130, x: 345, y: 380 },
  // Scattered individual blocks
  { blocks: [[0,0]], val: 90, x: 65, y: 385 },
  { blocks: [[0,0]], val: 110, x: 420, y: 370 },
  { blocks: [[0,0],[1,0]], val: 160, x: 440, y: 395 },
];

function drawBlock(bx, by, size, v) {
  // Main block face
  fillRect(bx, by, size, size, v);
  // Highlight top edge
  fillRect(bx, by, size, 3, Math.min(255, v + 40));
  // Highlight left edge
  fillRect(bx, by, 3, size, Math.min(255, v + 30));
  // Shadow bottom edge
  fillRect(bx, by + size - 3, size, 3, Math.max(0, v - 35));
  // Shadow right edge
  fillRect(bx + size - 3, by, 3, size, Math.max(0, v - 25));
  // Inner border (1px dark line)
  const border = Math.max(0, v - 50);
  for (let i = 0; i < size; i++) {
    setPixel(bx + i, by, border);
    setPixel(bx + i, by + size - 1, border);
    setPixel(bx, by + i, border);
    setPixel(bx + size - 1, by + i, border);
  }
}

for (const t of tetrominoes) {
  for (const [bx, by] of t.blocks) {
    drawBlock(
      t.x + bx * (blockSize + blockGap),
      t.y + by * (blockSize + blockGap),
      blockSize,
      t.val
    );
  }
}

// --- Step 6: Subtle grid lines in block area ---
for (let y = 335; y < 430; y += (blockSize + blockGap)) {
  for (let x = 60; x < 460; x++) {
    setPixel(x, y, 40, 25);
  }
}
for (let x = 60; x < 460; x += (blockSize + blockGap)) {
  for (let y = 335; y < 430; y++) {
    setPixel(x, y, 40, 25);
  }
}

// --- Step 7: "GRAVITON" text at bottom ---
const text = "GRAVITON";
const charScale = 5;
const charSpacing = 6;
const textWidth = text.length * (5 * charScale + charSpacing) - charSpacing;
const textX = Math.round((W - textWidth) / 2);
const textY = 448;

// Text shadow
drawText(text, textX + 2, textY + 2, charScale, charSpacing, 10);
// Main text - bright white
drawText(text, textX, textY, charScale, charSpacing, 220);

// --- Step 8: Subtle horizontal line separator above text ---
for (let x = 120; x < 392; x++) {
  const dist = Math.min(x - 120, 392 - x);
  const a = Math.min(60, dist);
  setPixel(x, 438, 105, a);
}

// --- Step 9: Rounded corners (make outside transparent) ---
const cornerR = 64;
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    let dx = 0, dy = 0;
    if (x < cornerR && y < cornerR) { dx = cornerR - x; dy = cornerR - y; }
    else if (x >= W - cornerR && y < cornerR) { dx = x - (W - cornerR - 1); dy = cornerR - y; }
    else if (x < cornerR && y >= H - cornerR) { dx = cornerR - x; dy = y - (H - cornerR - 1); }
    else if (x >= W - cornerR && y >= H - cornerR) { dx = x - (W - cornerR - 1); dy = y - (H - cornerR - 1); }

    if (dx > 0 || dy > 0) {
      const d = Math.sqrt(dx * dx + dy * dy);
      if (d > cornerR) {
        const idx = (y * W + x) * 4;
        png.data[idx] = 0;
        png.data[idx + 1] = 0;
        png.data[idx + 2] = 0;
        png.data[idx + 3] = 0;
      } else if (d > cornerR - 1.5) {
        const alpha = (cornerR - d) / 1.5;
        const idx = (y * W + x) * 4;
        png.data[idx + 3] = Math.round(png.data[idx + 3] * alpha);
      }
    }
  }
}

// --- Step 10: Thin border along the rounded rect edge ---
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    let onEdge = false;
    if (x <= 2 || x >= W - 3 || y <= 2 || y >= H - 3) onEdge = true;

    let dx = 0, dy = 0;
    if (x < cornerR && y < cornerR) { dx = cornerR - x; dy = cornerR - y; }
    else if (x >= W - cornerR && y < cornerR) { dx = x - (W - cornerR - 1); dy = cornerR - y; }
    else if (x < cornerR && y >= H - cornerR) { dx = cornerR - x; dy = y - (H - cornerR - 1); }
    else if (x >= W - cornerR && y >= H - cornerR) { dx = x - (W - cornerR - 1); dy = y - (H - cornerR - 1); }

    if (dx > 0 || dy > 0) {
      const d = Math.sqrt(dx * dx + dy * dy);
      if (d >= cornerR - 3 && d <= cornerR) {
        setPixel(x, y, 85, Math.round(80 * (1 - (cornerR - d) / 3)));
      }
    } else if (onEdge) {
      const idx = (y * W + x) * 4;
      if (png.data[idx + 3] > 0) {
        const edgeDist = Math.min(x, y, W - 1 - x, H - 1 - y);
        const a = Math.round(60 * (1 - edgeDist / 3));
        if (a > 0) setPixel(x, y, 85, a);
      }
    }
  }
}

// --- Write output ---
const outPath = "/Users/ssk/mono/contest/entries/agent-alpha/publish/icon-512.png";
const buffer = PNG.sync.write(png);
fs.writeFileSync(outPath, buffer);
console.log(`Icon written to ${outPath} (${buffer.length} bytes)`);
