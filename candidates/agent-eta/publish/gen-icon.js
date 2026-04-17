const { PNG } = require("/Users/ssk/work/mono/node_modules/pngjs");
const fs = require("fs");

const W = 512, H = 512;
const png = new PNG({ width: W, height: H });

// GRAYSCALE ONLY helpers - all colors are single gray value
function setPixel(x, y, v, a = 255) {
  x = Math.round(x); y = Math.round(y);
  if (x < 0 || x >= W || y < 0 || y >= H) return;
  const idx = (y * W + x) * 4;
  if (a < 255) {
    const af = a / 255;
    const existing = png.data[idx];
    const blended = Math.round(existing * (1 - af) + v * af);
    png.data[idx] = blended;
    png.data[idx + 1] = blended;
    png.data[idx + 2] = blended;
    png.data[idx + 3] = Math.max(png.data[idx + 3], a);
  } else {
    png.data[idx] = v;
    png.data[idx + 1] = v;
    png.data[idx + 2] = v;
    png.data[idx + 3] = a;
  }
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

function fillCircleAA(cx, cy, radius, v) {
  const r2 = radius * radius;
  for (let dy = -radius - 1; dy <= radius + 1; dy++) {
    for (let dx = -radius - 1; dx <= radius + 1; dx++) {
      const d2 = dx * dx + dy * dy;
      if (d2 <= (radius - 1) * (radius - 1)) {
        setPixel(cx + dx, cy + dy, v);
      } else if (d2 <= (radius + 1) * (radius + 1)) {
        const dist = Math.sqrt(d2);
        const alpha = Math.max(0, Math.min(1, radius - dist + 0.5));
        setPixel(cx + dx, cy + dy, v, Math.round(alpha * 255));
      }
    }
  }
}

function drawLine(x0, y0, x1, y1, v, a = 255, thickness = 1) {
  const dx = x1 - x0, dy = y1 - y0;
  const len = Math.sqrt(dx * dx + dy * dy);
  if (len === 0) return;
  const steps = Math.ceil(len * 2);
  for (let i = 0; i <= steps; i++) {
    const t = i / steps;
    const x = x0 + dx * t;
    const y = y0 + dy * t;
    if (thickness <= 1) {
      setPixel(x, y, v, a);
    } else {
      fillCircle(x, y, thickness / 2, v, a);
    }
  }
}

function fillTriangle(cx, cy, size, v) {
  const h = size * Math.sqrt(3) / 2;
  const x0 = cx, y0 = cy - h * 0.67;
  const x1 = cx - size / 2, y1 = cy + h * 0.33;
  const x2 = cx + size / 2, y2 = cy + h * 0.33;
  const minY = Math.floor(Math.min(y0, y1, y2));
  const maxY = Math.ceil(Math.max(y0, y1, y2));
  const minX = Math.floor(Math.min(x0, x1, x2));
  const maxX = Math.ceil(Math.max(x0, x1, x2));
  for (let py = minY; py <= maxY; py++) {
    for (let px = minX; px <= maxX; px++) {
      const d1 = (px - x1) * (y0 - y1) - (x0 - x1) * (py - y1);
      const d2 = (px - x2) * (y1 - y2) - (x1 - x2) * (py - y2);
      const d3 = (px - x0) * (y2 - y0) - (x2 - x0) * (py - y0);
      const hasNeg = (d1 < 0) || (d2 < 0) || (d3 < 0);
      const hasPos = (d1 > 0) || (d2 > 0) || (d3 > 0);
      if (!(hasNeg && hasPos)) {
        setPixel(px, py, v);
      }
    }
  }
}

function fillDiamond(cx, cy, size, v) {
  for (let dy = -size; dy <= size; dy++)
    for (let dx = -size; dx <= size; dx++)
      if (Math.abs(dx) + Math.abs(dy) <= size)
        setPixel(cx + dx, cy + dy, v);
}

// Bitmap font for title - each char is 5x7
const FONT = {
  'G': ["01110","10001","10000","10111","10001","10001","01110"],
  'R': ["11110","10001","10001","11110","10100","10010","10001"],
  'E': ["11111","10000","10000","11110","10000","10000","11111"],
  'Y': ["10001","10001","01010","00100","00100","00100","00100"],
  ' ': ["00000","00000","00000","00000","00000","00000","00000"],
  'B': ["11110","10001","10001","11110","10001","10001","11110"],
  'A': ["01110","10001","10001","11111","10001","10001","10001"],
  'S': ["01111","10000","10000","01110","00001","00001","11110"],
  'T': ["11111","00100","00100","00100","00100","00100","00100"],
  'I': ["11111","00100","00100","00100","00100","00100","11111"],
  'O': ["01110","10001","10001","10001","10001","10001","01110"],
  'N': ["10001","11001","10101","10011","10001","10001","10001"],
  'D': ["11100","10010","10001","10001","10001","10010","11100"],
  'F': ["11111","10000","10000","11110","10000","10000","10000"],
  'W': ["10001","10001","10001","10101","10101","11011","10001"],
};

function drawText(text, startX, startY, scale, v) {
  let curX = startX;
  for (const ch of text) {
    const glyph = FONT[ch];
    if (!glyph) { curX += 6 * scale; continue; }
    for (let row = 0; row < 7; row++) {
      for (let col = 0; col < 5; col++) {
        if (glyph[row][col] === '1') {
          fillRect(curX + col * scale, startY + row * scale, scale, scale, v);
        }
      }
    }
    curX += 6 * scale;
  }
}

function textWidth(text, scale) {
  return text.length * 6 * scale - scale;
}

// ===== DRAW THE ICON =====

// 1. Fill background - dark gray
fillRect(0, 0, W, H, 30);

// 2. Subtle grid
const GRID_SIZE = 32;
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    if (x % GRID_SIZE === 0 || y % GRID_SIZE === 0) {
      setPixel(x, y, 42);
    }
  }
}

// 3. Define serpentine path waypoints
const pathPoints = [
  { x: -10, y: 200 },
  { x: 80, y: 200 },
  { x: 130, y: 200 },
  { x: 180, y: 200 },
  { x: 220, y: 200 },
  { x: 260, y: 250 },
  { x: 260, y: 300 },
  { x: 260, y: 340 },
  { x: 220, y: 380 },
  { x: 170, y: 380 },
  { x: 120, y: 380 },
  { x: 80, y: 340 },
  { x: 80, y: 290 },
  { x: 80, y: 260 },
  { x: 120, y: 240 },
  { x: 170, y: 240 },
  { x: 340, y: 240 },
  { x: 380, y: 240 },
  { x: 420, y: 280 },
  { x: 420, y: 330 },
  { x: 420, y: 370 },
  { x: 380, y: 410 },
  { x: 330, y: 410 },
  { x: 270, y: 410 },
  { x: 230, y: 440 },
  { x: 230, y: 470 },
  { x: 270, y: 490 },
  { x: 522, y: 490 },
];

// Draw path with thickness
const PATH_THICK = 28;

function drawThickLine(x0, y0, x1, y1, thickness, v) {
  const dx = x1 - x0, dy = y1 - y0;
  const len = Math.sqrt(dx * dx + dy * dy);
  if (len === 0) return;
  const steps = Math.ceil(len);
  for (let i = 0; i <= steps; i++) {
    const t = i / steps;
    const cx = x0 + dx * t;
    const cy = y0 + dy * t;
    fillCircle(cx, cy, thickness / 2, v);
  }
}

// Path fill - lighter gray
for (let i = 0; i < pathPoints.length - 1; i++) {
  drawThickLine(
    pathPoints[i].x, pathPoints[i].y,
    pathPoints[i + 1].x, pathPoints[i + 1].y,
    PATH_THICK, 80
  );
}

// Path border edges - slightly darker
for (let i = 0; i < pathPoints.length - 1; i++) {
  const p0 = pathPoints[i], p1 = pathPoints[i + 1];
  const dx = p1.x - p0.x, dy = p1.y - p0.y;
  const len = Math.sqrt(dx * dx + dy * dy);
  if (len === 0) continue;
  const nx = -dy / len, ny = dx / len;
  drawLine(
    p0.x + nx * PATH_THICK / 2, p0.y + ny * PATH_THICK / 2,
    p1.x + nx * PATH_THICK / 2, p1.y + ny * PATH_THICK / 2,
    60, 255, 2
  );
  drawLine(
    p0.x - nx * PATH_THICK / 2, p0.y - ny * PATH_THICK / 2,
    p1.x - nx * PATH_THICK / 2, p1.y - ny * PATH_THICK / 2,
    60, 255, 2
  );
}

// 4. Tower definitions with positions
const towers = [
  { type: 'arrow',  x: 160, y: 170, targetX: 180, targetY: 200 },
  { type: 'cannon', x: 300, y: 300, targetX: 260, targetY: 310 },
  { type: 'frost',  x: 140, y: 420, targetX: 160, targetY: 390 },
  { type: 'tesla',  x: 370, y: 330, targetX: 420, targetY: 340 },
  { type: 'arrow',  x: 320, y: 210, targetX: 340, targetY: 240 },
  { type: 'cannon', x: 50,  y: 330, targetX: 80,  targetY: 310 },
  { type: 'frost',  x: 470, y: 410, targetX: 420, targetY: 400 },
  { type: 'tesla',  x: 200, y: 460, targetX: 230, targetY: 470 },
];

// Draw tower platforms
for (const t of towers) {
  fillRect(t.x - 18, t.y - 18, 36, 36, 48);
  fillRect(t.x - 15, t.y - 15, 30, 30, 55);
}

// 5. Draw towers - each type a distinct gray shade for contrast
// Arrow = Triangle (light gray ~170)
// Cannon = Square (medium gray ~130)
// Frost = Diamond (bright ~200)
// Tesla = Circle (white ~240)
for (const t of towers) {
  switch (t.type) {
    case 'arrow':
      // Triangle tower - outline then fill
      fillTriangle(t.x, t.y, 26, 130);
      fillTriangle(t.x, t.y, 22, 170);
      break;
    case 'cannon':
      // Square tower
      fillRect(t.x - 10, t.y - 10, 20, 20, 110);
      fillRect(t.x - 8, t.y - 8, 16, 16, 140);
      break;
    case 'frost':
      // Diamond tower
      fillDiamond(t.x, t.y, 13, 165);
      fillDiamond(t.x, t.y, 11, 200);
      break;
    case 'tesla':
      // Circle tower
      fillCircleAA(t.x, t.y, 13, 200);
      fillCircleAA(t.x, t.y, 11, 235);
      fillCircleAA(t.x, t.y, 5, 255);
      break;
  }
}

// 6. Draw projectile lines from towers to targets
for (const t of towers) {
  let pv, pa;
  switch (t.type) {
    case 'arrow':
      pv = 180; pa = 180;
      break;
    case 'cannon':
      pv = 160; pa = 160;
      break;
    case 'frost':
      pv = 190; pa = 180;
      break;
    case 'tesla':
      pv = 240; pa = 200;
      // Lightning-style jagged line
      const mx = (t.x + t.targetX) / 2 + (15 * ((t.x % 3) - 1));
      const my = (t.y + t.targetY) / 2 + (10 * ((t.y % 3) - 1));
      drawLine(t.x, t.y, mx, my, pv, pa, 2);
      drawLine(mx, my, t.targetX, t.targetY, pv, pa, 2);
      continue;
  }
  drawLine(t.x, t.y, t.targetX, t.targetY, pv, pa, 2);
}

// 7. Draw enemy dots along path (medium gray)
function getPointOnPath(t) {
  const totalSegments = pathPoints.length - 1;
  const segIdx = Math.min(Math.floor(t * totalSegments), totalSegments - 1);
  const segT = (t * totalSegments) - segIdx;
  const p0 = pathPoints[segIdx], p1 = pathPoints[segIdx + 1];
  return {
    x: p0.x + (p1.x - p0.x) * segT,
    y: p0.y + (p1.y - p0.y) * segT
  };
}

const enemyPositions = [0.08, 0.12, 0.16, 0.30, 0.34, 0.50, 0.54, 0.58, 0.72, 0.76, 0.88, 0.92];
for (const t of enemyPositions) {
  const p = getPointOnPath(t);
  // Enemy dots - medium gray with lighter center
  fillCircleAA(p.x, p.y, 6, 100);
  fillCircleAA(p.x, p.y, 4, 130);
}

// 8. Draw "GREY BASTION" title
// Dark banner behind title
fillRect(0, 28, W, 65, 20, 210);

const title = "GREY BASTION";
const scale = 5;
const tw = textWidth(title, scale);
const tx = Math.floor((W - tw) / 2);
const ty = 38;

// Shadow
drawText(title, tx + 2, ty + 2, scale, 10);
// Main text - bright white
drawText(title, tx, ty, scale, 225);

// 9. Subtitle "TOWER DEFENSE"
const subtitle = "TOWER DEFENSE";
const sscale = 3;
const stw = textWidth(subtitle, sscale);
const stx = Math.floor((W - stw) / 2);
const sty = 80;
drawText(subtitle, stx + 1, sty + 1, sscale, 10);
drawText(subtitle, stx, sty, sscale, 145);

// 10. Decorative border
for (let x = 0; x < W; x++) {
  for (let t = 0; t < 3; t++) {
    setPixel(x, t, 100);
    setPixel(x, H - 1 - t, 100);
  }
}
for (let y = 0; y < H; y++) {
  for (let t = 0; t < 3; t++) {
    setPixel(t, y, 100);
    setPixel(W - 1 - t, y, 100);
  }
}

// 11. Round corners (64px radius)
const CORNER_R = 64;
for (let y = 0; y < CORNER_R; y++) {
  for (let x = 0; x < CORNER_R; x++) {
    const dx = CORNER_R - 1 - x;
    const dy = CORNER_R - 1 - y;
    const dist = Math.sqrt(dx * dx + dy * dy);
    if (dist > CORNER_R) {
      // Outside corner - fully transparent
      const corners = [
        [x, y], [W - 1 - x, y],
        [x, H - 1 - y], [W - 1 - x, H - 1 - y]
      ];
      for (const [cx, cy] of corners) {
        const idx = (cy * W + cx) * 4;
        png.data[idx] = 0;
        png.data[idx + 1] = 0;
        png.data[idx + 2] = 0;
        png.data[idx + 3] = 0;
      }
    } else if (dist > CORNER_R - 1.5) {
      // Anti-alias edge
      const alpha = Math.max(0, Math.min(1, CORNER_R - dist));
      const a = Math.round(alpha * 255);
      const corners = [
        [x, y], [W - 1 - x, y],
        [x, H - 1 - y], [W - 1 - x, H - 1 - y]
      ];
      for (const [cx, cy] of corners) {
        const idx = (cy * W + cx) * 4;
        png.data[idx + 3] = Math.min(png.data[idx + 3], a);
      }
    }
  }
}

// 12. Subtle vignette effect
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    const dx2 = (x - W / 2) / (W / 2);
    const dy2 = (y - H / 2) / (H / 2);
    const dist = Math.sqrt(dx2 * dx2 + dy2 * dy2);
    if (dist > 0.7) {
      const darken = Math.min(1, (dist - 0.7) * 0.6);
      const idx = (y * W + x) * 4;
      const v = Math.round(png.data[idx] * (1 - darken));
      png.data[idx] = v;
      png.data[idx + 1] = v;
      png.data[idx + 2] = v;
    }
  }
}

// Save
const outPath = "/Users/ssk/mono/contest/entries/agent-eta/publish/icon-512.png";
const buffer = PNG.sync.write(png);
fs.writeFileSync(outPath, buffer);
console.log(`Icon saved to ${outPath} (${buffer.length} bytes)`);
