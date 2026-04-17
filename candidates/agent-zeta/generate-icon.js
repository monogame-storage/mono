const { PNG } = require("/Users/ssk/work/mono/node_modules/pngjs");
const fs = require("fs");

const W = 512, H = 512;
const png = new PNG({ width: W, height: H });

// Helper: set pixel with alpha blending
function setPixel(x, y, r, g, b, a = 255) {
  if (x < 0 || x >= W || y < 0 || y >= H) return;
  const idx = (y * W + x) * 4;
  if (a === 255) {
    png.data[idx] = r;
    png.data[idx + 1] = g;
    png.data[idx + 2] = b;
    png.data[idx + 3] = 255;
  } else {
    const srcA = a / 255;
    const dstA = png.data[idx + 3] / 255;
    const outA = srcA + dstA * (1 - srcA);
    if (outA > 0) {
      png.data[idx] = Math.round((r * srcA + png.data[idx] * dstA * (1 - srcA)) / outA);
      png.data[idx + 1] = Math.round((g * srcA + png.data[idx + 1] * dstA * (1 - srcA)) / outA);
      png.data[idx + 2] = Math.round((b * srcA + png.data[idx + 2] * dstA * (1 - srcA)) / outA);
      png.data[idx + 3] = Math.round(outA * 255);
    }
  }
}

function fillRect(x, y, w, h, r, g, b, a = 255) {
  for (let dy = 0; dy < h; dy++)
    for (let dx = 0; dx < w; dx++)
      setPixel(x + dx, y + dy, r, g, b, a);
}

function dist(x1, y1, x2, y2) {
  return Math.sqrt((x1 - x2) ** 2 + (y1 - y2) ** 2);
}

function fillCircle(cx, cy, radius, r, g, b, a = 255) {
  for (let dy = -radius; dy <= radius; dy++)
    for (let dx = -radius; dx <= radius; dx++)
      if (dx * dx + dy * dy <= radius * radius)
        setPixel(cx + dx, cy + dy, r, g, b, a);
}

// Rounded corner mask check
function inRoundedRect(x, y, w, h, radius) {
  if (x < radius && y < radius) return dist(x, y, radius, radius) <= radius;
  if (x >= w - radius && y < radius) return dist(x, y, w - radius, radius) <= radius;
  if (x < radius && y >= h - radius) return dist(x, y, radius, h - radius) <= radius;
  if (x >= w - radius && y >= h - radius) return dist(x, y, w - radius, h - radius) <= radius;
  return true;
}

// Step 1: Fill background (very dark blue-black)
for (let y = 0; y < H; y++)
  for (let x = 0; x < W; x++) {
    const idx = (y * W + x) * 4;
    // Subtle gradient - darker at edges
    const edgeDist = Math.min(x, y, W - x, H - y) / 256;
    const base = Math.floor(8 + edgeDist * 6);
    png.data[idx] = base;
    png.data[idx + 1] = base;
    png.data[idx + 2] = Math.floor(base * 1.3);
    png.data[idx + 3] = 255;
  }

// Step 2: Draw dungeon room structure (walls)
const wallColor = [45, 40, 50]; // dark purple-gray walls

// Main central room
fillRect(140, 170, 230, 180, wallColor[0], wallColor[1], wallColor[2]);
// Room interior (darker floor)
fillRect(148, 178, 214, 164, 18, 16, 22);

// Corridor going up from room
fillRect(230, 100, 50, 78, wallColor[0], wallColor[1], wallColor[2]);
fillRect(236, 106, 38, 72, 18, 16, 22);

// Corridor going right
fillRect(362, 230, 90, 50, wallColor[0], wallColor[1], wallColor[2]);
fillRect(362, 236, 84, 38, 18, 16, 22);

// Corridor going left
fillRect(60, 240, 88, 46, wallColor[0], wallColor[1], wallColor[2]);
fillRect(66, 246, 76, 34, 18, 16, 22);

// Corridor going down
fillRect(220, 342, 56, 80, wallColor[0], wallColor[1], wallColor[2]);
fillRect(226, 342, 44, 74, 18, 16, 22);

// Small side room top-right
fillRect(320, 100, 90, 80, wallColor[0], wallColor[1], wallColor[2]);
fillRect(326, 106, 78, 68, 18, 16, 22);
// Connection corridor
fillRect(310, 140, 18, 40, wallColor[0], wallColor[1], wallColor[2]);
fillRect(312, 146, 14, 28, 18, 16, 22);

// Small room bottom-left
fillRect(80, 320, 80, 70, wallColor[0], wallColor[1], wallColor[2]);
fillRect(86, 326, 68, 58, 18, 16, 22);

// Step 3: FOV light cone from hero position
const heroCX = 255, heroCY = 260;
const fovRadius = 140;

for (let y = 100; y < 420; y++) {
  for (let x = 60; x < 460; x++) {
    const d = dist(x, y, heroCX, heroCY);
    if (d < fovRadius) {
      // Warm torch light falloff
      const intensity = 1.0 - (d / fovRadius);
      const glow = intensity * intensity; // quadratic falloff
      const r = Math.floor(45 * glow);
      const g = Math.floor(35 * glow);
      const b = Math.floor(15 * glow);
      if (r > 0 || g > 0 || b > 0) {
        const idx = (y * W + x) * 4;
        png.data[idx] = Math.min(255, png.data[idx] + r);
        png.data[idx + 1] = Math.min(255, png.data[idx + 1] + g);
        png.data[idx + 2] = Math.min(255, png.data[idx + 2] + b);
      }
    }
  }
}

// Secondary inner glow (brighter near hero)
for (let y = heroCY - 60; y < heroCY + 60; y++) {
  for (let x = heroCX - 60; x < heroCX + 60; x++) {
    const d = dist(x, y, heroCX, heroCY);
    if (d < 50) {
      const intensity = 1.0 - (d / 50);
      const glow = intensity * intensity * intensity;
      const r = Math.floor(60 * glow);
      const g = Math.floor(50 * glow);
      const b = Math.floor(25 * glow);
      const idx = (y * W + x) * 4;
      png.data[idx] = Math.min(255, png.data[idx] + r);
      png.data[idx + 1] = Math.min(255, png.data[idx + 1] + g);
      png.data[idx + 2] = Math.min(255, png.data[idx + 2] + b);
    }
  }
}

// Step 4: Draw the @ hero character (large, bright)
const atSign = [
  "  ######  ",
  " ##    ## ",
  "##  ### ##",
  "## ## # ##",
  "## ## # ##",
  "## #### ##",
  "##  ##  ##",
  " ##    ## ",
  "  ######  ",
  "         #",
  "  ###### #",
  "   ####   ",
];

const atScale = 3;
const atStartX = heroCX - 15;
const atStartY = heroCY - 20;

for (let row = 0; row < atSign.length; row++) {
  for (let col = 0; col < atSign[row].length; col++) {
    if (atSign[row][col] === '#') {
      for (let sy = 0; sy < atScale; sy++)
        for (let sx = 0; sx < atScale; sx++)
          setPixel(atStartX + col * atScale + sx, atStartY + row * atScale + sy, 240, 230, 210);
    }
  }
}

// Tiny sword next to hero (right side)
const swordX = heroCX + 20, swordY = heroCY - 14;
// Blade (vertical line)
for (let i = 0; i < 18; i++) setPixel(swordX, swordY + i, 200, 210, 220);
for (let i = 0; i < 18; i++) setPixel(swordX + 1, swordY + i, 180, 190, 200);
// Crossguard
fillRect(swordX - 4, swordY + 14, 10, 3, 160, 140, 80);
// Handle
fillRect(swordX - 1, swordY + 17, 4, 6, 120, 80, 40);

// Step 5: Enemy shapes lurking in shadows
// Red enemy (top corridor)
fillCircle(253, 118, 5, 180, 40, 40);
fillCircle(253, 118, 3, 220, 50, 50);
// Two small red eyes
setPixel(251, 117, 255, 80, 80);
setPixel(255, 117, 255, 80, 80);

// Green enemy (left corridor)
fillCircle(90, 260, 5, 40, 140, 40);
fillCircle(90, 260, 3, 50, 180, 50);
setPixel(88, 259, 200, 255, 80);
setPixel(92, 259, 200, 255, 80);

// Purple enemy (right corridor)
fillCircle(410, 250, 6, 120, 40, 160);
fillCircle(410, 250, 4, 150, 50, 200);
setPixel(408, 249, 220, 100, 255);
setPixel(412, 249, 220, 100, 255);

// Skull enemy (bottom)
fillCircle(244, 390, 5, 140, 130, 120);
setPixel(242, 389, 200, 50, 50);
setPixel(246, 389, 200, 50, 50);

// Enemy in side room
fillCircle(360, 140, 5, 180, 100, 40);
fillCircle(360, 140, 3, 220, 120, 50);
setPixel(358, 139, 255, 160, 40);
setPixel(362, 139, 255, 160, 40);

// Step 6: Item pickups
// Potion (blue, in room)
const potX = 200, potY = 220;
// Bottle body
fillRect(potX - 3, potY, 8, 10, 40, 80, 200);
fillRect(potX - 2, potY - 2, 6, 3, 40, 80, 200);
// Neck
fillRect(potX - 1, potY - 5, 4, 4, 60, 100, 180);
// Cork
fillRect(potX - 1, potY - 7, 4, 3, 140, 100, 60);
// Shine
setPixel(potX - 2, potY + 1, 100, 150, 255);
setPixel(potX - 2, potY + 2, 80, 130, 255);

// Gold coin
const coinX = 300, coinY = 300;
fillCircle(coinX, coinY, 5, 200, 180, 40);
fillCircle(coinX, coinY, 3, 240, 210, 60);
setPixel(coinX, coinY, 255, 240, 100);

// Key item (yellow, in side room)
const keyX = 340, keyY = 150;
fillCircle(keyX, keyY, 4, 200, 180, 40);
fillCircle(keyX, keyY, 2, 18, 16, 22);
fillRect(keyX + 3, keyY - 1, 10, 3, 200, 180, 40);
fillRect(keyX + 10, keyY + 1, 3, 4, 200, 180, 40);
fillRect(keyX + 7, keyY + 1, 3, 3, 200, 180, 40);

// Step 7: "DUSKHOLD" title at top
// Pixel font - each letter is 7 wide x 9 tall
const font = {
  D: [
    "##### ",
    "##  ##",
    "##  ##",
    "##  ##",
    "##  ##",
    "##  ##",
    "##  ##",
    "##  ##",
    "##### ",
  ],
  U: [
    "##  ##",
    "##  ##",
    "##  ##",
    "##  ##",
    "##  ##",
    "##  ##",
    "##  ##",
    "##  ##",
    " #### ",
  ],
  S: [
    " #####",
    "##    ",
    "##    ",
    " #### ",
    "    ##",
    "    ##",
    "    ##",
    "    ##",
    "##### ",
  ],
  K: [
    "##  ##",
    "## ## ",
    "####  ",
    "###   ",
    "###   ",
    "####  ",
    "## ## ",
    "##  ##",
    "##  ##",
  ],
  H: [
    "##  ##",
    "##  ##",
    "##  ##",
    "######",
    "######",
    "##  ##",
    "##  ##",
    "##  ##",
    "##  ##",
  ],
  O: [
    " #### ",
    "##  ##",
    "##  ##",
    "##  ##",
    "##  ##",
    "##  ##",
    "##  ##",
    "##  ##",
    " #### ",
  ],
  L: [
    "##    ",
    "##    ",
    "##    ",
    "##    ",
    "##    ",
    "##    ",
    "##    ",
    "##    ",
    "######",
  ],
};

const title = "DUSKHOLD";
const letterW = 6;
const letterH = 9;
const scale = 4;
const totalW = title.length * (letterW + 1) * scale;
const titleStartX = Math.floor((W - totalW) / 2);
const titleStartY = 38;

// Title glow/shadow
for (let ci = 0; ci < title.length; ci++) {
  const ch = title[ci];
  const glyph = font[ch];
  if (!glyph) continue;
  const ox = titleStartX + ci * (letterW + 1) * scale;
  for (let row = 0; row < letterH; row++) {
    for (let col = 0; col < glyph[row].length; col++) {
      if (glyph[row][col] === '#') {
        // Glow behind letters
        for (let gy = -3; gy <= 3; gy++)
          for (let gx = -3; gx <= 3; gx++) {
            const d = Math.sqrt(gx * gx + gy * gy);
            if (d <= 3) {
              const alpha = Math.floor(40 * (1 - d / 3));
              for (let sy = 0; sy < scale; sy++)
                for (let sx = 0; sx < scale; sx++)
                  setPixel(ox + col * scale + sx + gx, titleStartY + row * scale + sy + gy, 180, 140, 60, alpha);
            }
          }
      }
    }
  }
}

// Title text
for (let ci = 0; ci < title.length; ci++) {
  const ch = title[ci];
  const glyph = font[ch];
  if (!glyph) continue;
  const ox = titleStartX + ci * (letterW + 1) * scale;
  for (let row = 0; row < letterH; row++) {
    for (let col = 0; col < glyph[row].length; col++) {
      if (glyph[row][col] === '#') {
        for (let sy = 0; sy < scale; sy++)
          for (let sx = 0; sx < scale; sx++)
            setPixel(ox + col * scale + sx, titleStartY + row * scale + sy, 230, 210, 170);
      }
    }
  }
}

// Decorative line under title
const lineY = titleStartY + letterH * scale + 8;
for (let x = titleStartX - 10; x < titleStartX + totalW + 10; x++) {
  const dFromCenter = Math.abs(x - W / 2);
  const alpha = Math.max(0, 180 - dFromCenter);
  setPixel(x, lineY, 180, 140, 60, alpha);
  setPixel(x, lineY + 1, 140, 100, 40, Math.floor(alpha * 0.5));
}

// Step 8: Subtle vignette overlay
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    const d = dist(x, y, W / 2, H / 2) / (W / 2);
    if (d > 0.5) {
      const darken = Math.min(1, (d - 0.5) * 1.2);
      const idx = (y * W + x) * 4;
      png.data[idx] = Math.floor(png.data[idx] * (1 - darken * 0.6));
      png.data[idx + 1] = Math.floor(png.data[idx + 1] * (1 - darken * 0.6));
      png.data[idx + 2] = Math.floor(png.data[idx + 2] * (1 - darken * 0.6));
    }
  }
}

// Step 9: Apply rounded corners (64px radius)
const cornerR = 64;
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    if (!inRoundedRect(x, y, W, H, cornerR)) {
      const idx = (y * W + x) * 4;
      png.data[idx] = 0;
      png.data[idx + 1] = 0;
      png.data[idx + 2] = 0;
      png.data[idx + 3] = 0;
    }
  }
}

// Step 10: Add a subtle border
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    if (inRoundedRect(x, y, W, H, cornerR)) {
      // Check if near edge
      const isEdge = !inRoundedRect(x - 2, y, W - 0, H - 0, cornerR) ||
                     !inRoundedRect(x + 2, y, W - 0, H - 0, cornerR) ||
                     !inRoundedRect(x, y - 2, W - 0, H - 0, cornerR) ||
                     !inRoundedRect(x, y + 2, W - 0, H - 0, cornerR) ||
                     x <= 2 || x >= W - 3 || y <= 2 || y >= H - 3;
      if (isEdge) {
        setPixel(x, y, 80, 60, 40, 160);
      }
    }
  }
}

// Write output
const outPath = "/Users/ssk/mono/contest/entries/agent-zeta/publish/icon-512.png";
const buffer = PNG.sync.write(png);
fs.writeFileSync(outPath, buffer);
console.log("Icon written to", outPath, "- size:", buffer.length, "bytes");
