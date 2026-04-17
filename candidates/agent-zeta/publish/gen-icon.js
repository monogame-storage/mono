const { PNG } = require("/Users/ssk/work/mono/node_modules/pngjs");
const fs = require("fs");

const W = 512, H = 512;
const png = new PNG({ width: W, height: H });

// Helper: set pixel grayscale
function setPixel(x, y, gray, alpha = 255) {
  if (x < 0 || x >= W || y < 0 || y >= H) return;
  const idx = (y * W + x) * 4;
  png.data[idx] = gray;
  png.data[idx + 1] = gray;
  png.data[idx + 2] = gray;
  png.data[idx + 3] = alpha;
}

function getPixel(x, y) {
  if (x < 0 || x >= W || y < 0 || y >= H) return 0;
  return png.data[(y * W + x) * 4];
}

// Blend a gray value onto existing pixel
function blendPixel(x, y, gray, alpha) {
  if (x < 0 || x >= W || y < 0 || y >= H) return;
  const idx = (y * W + x) * 4;
  const a = alpha / 255;
  const existing = png.data[idx];
  const blended = Math.round(existing * (1 - a) + gray * a);
  png.data[idx] = blended;
  png.data[idx + 1] = blended;
  png.data[idx + 2] = blended;
  png.data[idx + 3] = 255;
}

// Distance helper
function dist(x1, y1, x2, y2) {
  return Math.sqrt((x1 - x2) ** 2 + (y1 - y2) ** 2);
}

// Rounded rect mask (64px corners)
const RADIUS = 64;
function inRoundedRect(x, y) {
  if (x < RADIUS && y < RADIUS) return dist(x, y, RADIUS, RADIUS) <= RADIUS;
  if (x >= W - RADIUS && y < RADIUS) return dist(x, y, W - RADIUS - 1, RADIUS) <= RADIUS;
  if (x < RADIUS && y >= H - RADIUS) return dist(x, y, RADIUS, H - RADIUS - 1) <= RADIUS;
  if (x >= W - RADIUS && y >= H - RADIUS) return dist(x, y, W - RADIUS - 1, H - RADIUS - 1) <= RADIUS;
  return true;
}

// ---- Step 1: Fill background (very dark) ----
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    if (inRoundedRect(x, y)) {
      setPixel(x, y, 12);
    } else {
      setPixel(x, y, 0, 0); // transparent outside
    }
  }
}

// ---- Step 2: Draw dungeon room structure ----
// Main chamber centered
const room = { x: 80, y: 100, w: 352, h: 300 };
// Walls: medium gray ~90
const WALL_GRAY = 85;
const FLOOR_GRAY = 25;
const WALL_T = 8; // wall thickness

// Floor
for (let y = room.y; y < room.y + room.h; y++) {
  for (let x = room.x; x < room.x + room.w; x++) {
    if (inRoundedRect(x, y)) {
      // subtle floor tile pattern
      const tileSize = 32;
      const onGrid = (x % tileSize < 1) || (y % tileSize < 1);
      setPixel(x, y, onGrid ? 20 : FLOOR_GRAY);
    }
  }
}

// Walls (top, bottom, left, right)
function drawWallH(sx, sy, len, thickness) {
  for (let y = sy; y < sy + thickness; y++) {
    for (let x = sx; x < sx + len; x++) {
      if (inRoundedRect(x, y)) {
        // brick texture
        const brickW = 20, brickH = thickness;
        const bx = x - sx, by = y - sy;
        const row = Math.floor(by / brickH);
        const offset = row % 2 === 0 ? 0 : brickW / 2;
        const onMortar = ((bx + offset) % brickW < 1) || (by % brickH < 1);
        setPixel(x, y, onMortar ? WALL_GRAY - 20 : WALL_GRAY);
      }
    }
  }
}

function drawWallV(sx, sy, len, thickness) {
  for (let y = sy; y < sy + len; y++) {
    for (let x = sx; x < sx + thickness; x++) {
      if (inRoundedRect(x, y)) {
        const brickH = 12;
        const by = y - sy;
        const onMortar = (by % brickH < 1) || ((x - sx) % 8 < 1);
        setPixel(x, y, onMortar ? WALL_GRAY - 20 : WALL_GRAY);
      }
    }
  }
}

// Main room walls
drawWallH(room.x, room.y, room.w, WALL_T); // top
drawWallH(room.x, room.y + room.h - WALL_T, room.w, WALL_T); // bottom
drawWallV(room.x, room.y, room.h, WALL_T); // left
drawWallV(room.x + room.w - WALL_T, room.y, room.h, WALL_T); // right

// Side corridor (left)
const corr1 = { x: 30, y: 210, w: 58, h: 80 };
for (let y = corr1.y; y < corr1.y + corr1.h; y++) {
  for (let x = corr1.x; x < corr1.x + corr1.w; x++) {
    if (inRoundedRect(x, y)) setPixel(x, y, FLOOR_GRAY - 3);
  }
}
drawWallH(corr1.x, corr1.y, corr1.w, 5);
drawWallH(corr1.x, corr1.y + corr1.h - 5, corr1.w, 5);

// Side corridor (right)
const corr2 = { x: 424, y: 180, w: 58, h: 80 };
for (let y = corr2.y; y < corr2.y + corr2.h; y++) {
  for (let x = corr2.x; x < corr2.x + corr2.w; x++) {
    if (inRoundedRect(x, y)) setPixel(x, y, FLOOR_GRAY - 3);
  }
}
drawWallH(corr2.x, corr2.y, corr2.w, 5);
drawWallH(corr2.x, corr2.y + corr2.h - 5, corr2.w, 5);

// Door openings (gaps in walls)
// Left door
for (let y = 220; y < 280; y++) {
  for (let x = room.x; x < room.x + WALL_T; x++) {
    if (inRoundedRect(x, y)) setPixel(x, y, FLOOR_GRAY);
  }
}
// Right door
for (let y = 190; y < 250; y++) {
  for (let x = room.x + room.w - WALL_T; x < room.x + room.w; x++) {
    if (inRoundedRect(x, y)) setPixel(x, y, FLOOR_GRAY);
  }
}

// ---- Step 3: FOV light cone around hero center ----
const heroX = 256, heroY = 270;
const fovRadius = 140;

for (let y = room.y + WALL_T; y < room.y + room.h - WALL_T; y++) {
  for (let x = room.x + WALL_T; x < room.x + room.w - WALL_T; x++) {
    if (!inRoundedRect(x, y)) continue;
    const d = dist(x, y, heroX, heroY);
    if (d < fovRadius) {
      const intensity = 1.0 - (d / fovRadius);
      const boost = Math.floor(intensity * intensity * 45);
      const current = getPixel(x, y);
      setPixel(x, y, Math.min(255, current + boost));
    }
  }
}

// Also light the corridors slightly near doors
for (let y = corr1.y + 5; y < corr1.y + corr1.h - 5; y++) {
  for (let x = corr1.x; x < corr1.x + corr1.w; x++) {
    const d = dist(x, y, heroX, heroY);
    if (d < fovRadius + 40) {
      const intensity = Math.max(0, 1.0 - d / (fovRadius + 40));
      const boost = Math.floor(intensity * 15);
      const current = getPixel(x, y);
      setPixel(x, y, Math.min(255, current + boost));
    }
  }
}

// ---- Step 4: Central hero character (bright white @ with sword) ----
// Draw a bright figure at center

// Hero body - bright white figure
function drawFilledCircle(cx, cy, r, gray) {
  for (let y = cy - r; y <= cy + r; y++) {
    for (let x = cx - r; x <= cx + r; x++) {
      if (dist(x, y, cx, cy) <= r && inRoundedRect(x, y)) {
        setPixel(x, y, gray);
      }
    }
  }
}

// Hero glow
for (let y = heroY - 40; y <= heroY + 40; y++) {
  for (let x = heroX - 40; x <= heroX + 40; x++) {
    const d = dist(x, y, heroX, heroY);
    if (d < 35 && inRoundedRect(x, y)) {
      const intensity = 1.0 - (d / 35);
      blendPixel(x, y, 200, Math.floor(intensity * 80));
    }
  }
}

// Draw @ symbol for the hero (pixel art style, large)
const atPixels = [
  // Outer ring of @
  "  XXXXXXXX  ",
  " XX      XX ",
  "XX        XX",
  "XX  XXXX  XX",
  "XX XX  XX XX",
  "XX XX  XX XX",
  "XX XX XXX XX",
  "XX  XXX X XX",
  "XX        XX",
  " XX      XX ",
  "  XXXXXXXX  ",
];

const atScale = 3;
const atW = 12 * atScale;
const atH = atPixels.length * atScale;
const atStartX = heroX - Math.floor(atW / 2);
const atStartY = heroY - Math.floor(atH / 2) - 5;

for (let row = 0; row < atPixels.length; row++) {
  for (let col = 0; col < atPixels[row].length; col++) {
    if (atPixels[row][col] === 'X') {
      for (let dy = 0; dy < atScale; dy++) {
        for (let dx = 0; dx < atScale; dx++) {
          const px = atStartX + col * atScale + dx;
          const py = atStartY + row * atScale + dy;
          if (inRoundedRect(px, py)) setPixel(px, py, 245);
        }
      }
    }
  }
}

// Sword to the right of hero
const swordX = heroX + 24;
const swordBaseY = heroY - 20;
// Blade (vertical line, bright)
for (let y = swordBaseY - 30; y < swordBaseY + 5; y++) {
  for (let dx = -1; dx <= 1; dx++) {
    if (inRoundedRect(swordX + dx, y)) setPixel(swordX + dx, y, 230);
  }
}
// Crossguard
for (let x = swordX - 6; x <= swordX + 6; x++) {
  for (let dy = -1; dy <= 1; dy++) {
    if (inRoundedRect(x, swordBaseY + 5 + dy)) setPixel(x, swordBaseY + 5 + dy, 200);
  }
}
// Handle
for (let y = swordBaseY + 7; y < swordBaseY + 16; y++) {
  for (let dx = -1; dx <= 1; dx++) {
    if (inRoundedRect(swordX + dx, y)) setPixel(swordX + dx, y, 160);
  }
}

// ---- Step 5: Enemy shapes in shadows ----
const enemies = [
  { x: 150, y: 170, size: 8 },  // top-left in room
  { x: 370, y: 340, size: 9 },  // bottom-right
  { x: 120, y: 330, size: 7 },  // bottom-left
  { x: 380, y: 160, size: 8 },  // top-right
  { x: 50, y: 240, size: 6 },   // in left corridor
];

enemies.forEach(e => {
  // Enemy as menacing diamond/dot shape
  const gray = 55 + Math.floor(Math.random() * 20); // dark gray
  for (let y = e.y - e.size; y <= e.y + e.size; y++) {
    for (let x = e.x - e.size; x <= e.x + e.size; x++) {
      const manhattan = Math.abs(x - e.x) + Math.abs(y - e.y);
      if (manhattan <= e.size && inRoundedRect(x, y)) {
        setPixel(x, y, gray);
      }
    }
  }
  // Eyes (two bright dots)
  setPixel(e.x - 2, e.y - 2, 170);
  setPixel(e.x + 2, e.y - 2, 170);
  setPixel(e.x - 3, e.y - 2, 170);
  setPixel(e.x + 3, e.y - 2, 170);
});

// ---- Step 6: Item pickups ----
// Potion (small circle)
function drawItemCircle(cx, cy, r, gray) {
  for (let y = cy - r; y <= cy + r; y++) {
    for (let x = cx - r; x <= cx + r; x++) {
      if (dist(x, y, cx, cy) <= r && dist(x, y, cx, cy) > r - 2 && inRoundedRect(x, y)) {
        setPixel(x, y, gray);
      }
    }
  }
  // fill inside slightly
  for (let y = cy - r + 2; y <= cy + r - 2; y++) {
    for (let x = cx - r + 2; x <= cx + r - 2; x++) {
      if (dist(x, y, cx, cy) <= r - 2 && inRoundedRect(x, y)) {
        setPixel(x, y, gray - 30);
      }
    }
  }
}

// Potion near hero
drawItemCircle(220, 310, 6, 180);
// Star/key shape
const starX = 310, starY = 200;
for (let a = 0; a < 5; a++) {
  const angle = (a * 72 - 90) * Math.PI / 180;
  for (let r = 0; r < 8; r++) {
    const px = Math.round(starX + Math.cos(angle) * r);
    const py = Math.round(starY + Math.sin(angle) * r);
    setPixel(px, py, 180);
    setPixel(px + 1, py, 160);
    setPixel(px, py + 1, 160);
  }
}

// Chest shape
const chestX = 180, chestY = 195;
for (let y = chestY; y < chestY + 10; y++) {
  for (let x = chestX; x < chestX + 14; x++) {
    if (inRoundedRect(x, y)) {
      const isBorder = x === chestX || x === chestX + 13 || y === chestY || y === chestY + 9 || y === chestY + 4;
      setPixel(x, y, isBorder ? 160 : 120);
    }
  }
}
// Chest clasp
setPixel(chestX + 6, chestY + 4, 200);
setPixel(chestX + 7, chestY + 4, 200);

// ---- Step 7: Title "DUSKHOLD" at top ----
// Large pixel font for DUSKHOLD
const font = {
  D: [
    "XXXX ",
    "X   X",
    "X   X",
    "X   X",
    "X   X",
    "X   X",
    "XXXX ",
  ],
  U: [
    "X   X",
    "X   X",
    "X   X",
    "X   X",
    "X   X",
    "X   X",
    " XXX ",
  ],
  S: [
    " XXXX",
    "X    ",
    "X    ",
    " XXX ",
    "    X",
    "    X",
    "XXXX ",
  ],
  K: [
    "X   X",
    "X  X ",
    "X X  ",
    "XX   ",
    "X X  ",
    "X  X ",
    "X   X",
  ],
  H: [
    "X   X",
    "X   X",
    "X   X",
    "XXXXX",
    "X   X",
    "X   X",
    "X   X",
  ],
  O: [
    " XXX ",
    "X   X",
    "X   X",
    "X   X",
    "X   X",
    "X   X",
    " XXX ",
  ],
  L: [
    "X    ",
    "X    ",
    "X    ",
    "X    ",
    "X    ",
    "X    ",
    "XXXXX",
  ],
};

const title = "DUSKHOLD";
const charScale = 4;
const charW = 5 * charScale;
const charH = 7 * charScale;
const spacing = 4;
const totalW = title.length * (charW + spacing) - spacing;
const titleStartX = Math.floor((W - totalW) / 2);
const titleStartY = 30;

// Dark banner behind title
for (let y = titleStartY - 8; y < titleStartY + charH + 8; y++) {
  for (let x = 40; x < W - 40; x++) {
    if (inRoundedRect(x, y)) {
      blendPixel(x, y, 8, 200);
    }
  }
}

// Draw each character
for (let ci = 0; ci < title.length; ci++) {
  const ch = title[ci];
  const pattern = font[ch];
  if (!pattern) continue;
  const ox = titleStartX + ci * (charW + spacing);

  for (let row = 0; row < pattern.length; row++) {
    for (let col = 0; col < pattern[row].length; col++) {
      if (pattern[row][col] === 'X') {
        for (let dy = 0; dy < charScale; dy++) {
          for (let dx = 0; dx < charScale; dx++) {
            const px = ox + col * charScale + dx;
            const py = titleStartY + row * charScale + dy;
            if (inRoundedRect(px, py)) {
              setPixel(px, py, 220);
            }
          }
        }
      }
    }
  }
}

// Subtle underline below title
for (let x = titleStartX - 10; x < titleStartX + totalW + 10; x++) {
  const lineY = titleStartY + charH + 4;
  if (inRoundedRect(x, lineY)) setPixel(x, lineY, 100);
  if (inRoundedRect(x, lineY + 1)) setPixel(x, lineY + 1, 60);
}

// ---- Step 8: Vignette effect (darken edges) ----
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    if (!inRoundedRect(x, y)) continue;
    const d = dist(x, y, W / 2, H / 2) / (W / 2);
    if (d > 0.5) {
      const darken = Math.min(1, (d - 0.5) * 1.2);
      const idx = (y * W + x) * 4;
      const current = png.data[idx];
      const darkened = Math.floor(current * (1 - darken * 0.6));
      png.data[idx] = darkened;
      png.data[idx + 1] = darkened;
      png.data[idx + 2] = darkened;
    }
  }
}

// ---- Step 9: Subtle fog/particle effect ----
// Scattered faint dots for atmosphere
for (let i = 0; i < 200; i++) {
  const x = Math.floor(Math.random() * (room.w - 2 * WALL_T)) + room.x + WALL_T;
  const y = Math.floor(Math.random() * (room.h - 2 * WALL_T)) + room.y + WALL_T;
  if (inRoundedRect(x, y)) {
    blendPixel(x, y, 120, 30);
  }
}

// ---- Write PNG ----
const outPath = "/Users/ssk/mono/contest/entries/agent-zeta/publish/icon-512.png";
const buffer = PNG.sync.write(png);
fs.writeFileSync(outPath, buffer);
console.log(`Written ${outPath} (${buffer.length} bytes)`);
