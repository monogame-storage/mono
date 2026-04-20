/**
 * Mono Engine Drawing — shared pixel algorithms
 *
 * Line, rect, rectf, circ, circf, and drawText (with the 4x7 bitmap font)
 * live here so runtime/engine.js, dev/test-worker.js, and
 * editor/templates/mono/mono-test.js can't drift on pixel output.
 *
 * Runners call MonoDraw.create(ctx) with a setPix closure that knows how
 * to write into their own surface representation (RGBA buf32 + colorBuf
 * for the real engine, color-index-only Uint8Array for the headless
 * worker). Camera offsets and optional debug-shape hooks also come in
 * through ctx so this module stays pure.
 */
(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else if (typeof self !== "undefined") self.MonoDraw = api;
  else if (typeof globalThis !== "undefined") globalThis.MonoDraw = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  const FONT_W = 4, FONT_H = 7;
  const FONT = {};
  const fontData = {
    "A":"0110100110011111100110011001","B":"1110100110101110100110011110",
    "C":"0110100110001000100001100110","D":"1100101010011001100110101100",
    "E":"1111100010001110100010001111","F":"1111100010001110100010001000",
    "G":"0111100010001011100101100111","H":"1001100110011111100110011001",
    "I":"1110010001000100010001001110","J":"0111001000100010001010100100",
    "K":"1001101011001100101010011001","L":"1000100010001000100010001111",
    "M":"1001111111011001100110011001","N":"1001110110111011101110011001",
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
    FONT[ch] = new Uint8Array(FONT_W * FONT_H);
    for (let i = 0; i < bits.length; i++) FONT[ch][i] = bits[i] === "1" ? 1 : 0;
  }

  // Alignment bit flags — duplicated here (and in engine-bindings.js) so
  // drawText can be called from JS without dragging bindings in.
  const ALIGN_HCENTER = 1, ALIGN_RIGHT = 2, ALIGN_VCENTER = 4;

  /**
   * Build a drawing API bound to a runner's surface representation.
   *
   * @param {object} ctx
   *   setPix(s, x, y, c)  — required, writes one color-index pixel with clipping
   *   getCam()            — optional, returns [camX, camY]. Defaults to [0, 0].
   *   onShape(box)        — optional, called after rect/rectf/circ/circf with
   *                         { x, y, w, h } of the drawn region for debug overlays.
   * @returns {{ line, rect, rectf, circ, circf, drawText,
   *             FONT, FONT_W, FONT_H }}
   */
  function create(ctx) {
    const setPix = ctx.setPix;
    const getCam = ctx.getCam || (() => [0, 0]);
    const onShape = ctx.onShape;

    function line(s, x0, y0, x1, y1, c) {
      const [camX, camY] = getCam();
      x0 = Math.floor(x0) - camX; y0 = Math.floor(y0) - camY;
      x1 = Math.floor(x1) - camX; y1 = Math.floor(y1) - camY;
      let dx = Math.abs(x1 - x0), dy = Math.abs(y1 - y0);
      let sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
      let err = dx - dy;
      while (true) {
        setPix(s, x0, y0, c);
        if (x0 === x1 && y0 === y1) break;
        const e2 = 2 * err;
        if (e2 > -dy) { err -= dy; x0 += sx; }
        if (e2 <  dx) { err += dx; y0 += sy; }
      }
    }

    function rect(s, x, y, w, h, c) {
      const [camX, camY] = getCam();
      x = Math.floor(x) - camX; y = Math.floor(y) - camY;
      w = Math.floor(w); h = Math.floor(h);
      for (let i = 0; i < w; i++) { setPix(s, x + i, y, c); setPix(s, x + i, y + h - 1, c); }
      for (let i = 0; i < h; i++) { setPix(s, x, y + i, c); setPix(s, x + w - 1, y + i, c); }
      if (onShape) onShape({ x, y, w, h });
    }

    function rectf(s, x, y, w, h, c) {
      const [camX, camY] = getCam();
      x = Math.floor(x) - camX; y = Math.floor(y) - camY;
      w = Math.floor(w); h = Math.floor(h);
      for (let py = y; py < y + h; py++)
        for (let px = x; px < x + w; px++)
          setPix(s, px, py, c);
      if (onShape) onShape({ x, y, w, h });
    }

    function circ(s, cx, cy, r, c) {
      const [camX, camY] = getCam();
      cx = Math.floor(cx) - camX; cy = Math.floor(cy) - camY; r = Math.floor(r);
      let x = r, y = 0, d = 1 - r;
      while (x >= y) {
        setPix(s, cx + x, cy + y, c); setPix(s, cx - x, cy + y, c);
        setPix(s, cx + x, cy - y, c); setPix(s, cx - x, cy - y, c);
        setPix(s, cx + y, cy + x, c); setPix(s, cx - y, cy + x, c);
        setPix(s, cx + y, cy - x, c); setPix(s, cx - y, cy - x, c);
        y++;
        if (d < 0) { d += 2 * y + 1; }
        else { x--; d += 2 * (y - x) + 1; }
      }
      if (onShape) onShape({ x: cx - r, y: cy - r, w: r * 2 + 1, h: r * 2 + 1 });
    }

    function circf(s, cx, cy, r, c) {
      const [camX, camY] = getCam();
      cx = Math.floor(cx) - camX; cy = Math.floor(cy) - camY; r = Math.floor(r);
      let x = r, y = 0, d = 1 - r;
      while (x >= y) {
        for (let i = cx - x; i <= cx + x; i++) { setPix(s, i, cy + y, c); setPix(s, i, cy - y, c); }
        for (let i = cx - y; i <= cx + y; i++) { setPix(s, i, cy + x, c); setPix(s, i, cy - x, c); }
        y++;
        if (d < 0) { d += 2 * y + 1; }
        else { x--; d += 2 * (y - x) + 1; }
      }
      if (onShape) onShape({ x: cx - r, y: cy - r, w: r * 2 + 1, h: r * 2 + 1 });
    }

    // drawText is intentionally camera-independent — text is always a HUD
    // element drawn in screen coordinates.
    function drawText(s, str, x, y, c, align) {
      str = String(str).toUpperCase();
      align = align || 0;
      const textW = str.length * (FONT_W + 1) - 1;
      if (align & ALIGN_HCENTER)     x = x - textW / 2;
      else if (align & ALIGN_RIGHT)  x = x - textW;
      if (align & ALIGN_VCENTER)     y = y - FONT_H / 2;
      let cx = Math.floor(x);
      const cy = Math.floor(y);
      for (const ch of str) {
        const glyph = FONT[ch];
        if (glyph) {
          for (let py = 0; py < FONT_H; py++)
            for (let px = 0; px < FONT_W; px++)
              if (glyph[py * FONT_W + px]) setPix(s, cx + px, cy + py, c);
        }
        cx += FONT_W + 1;
      }
    }

    return { line, rect, rectf, circ, circf, drawText, FONT, FONT_W, FONT_H };
  }

  return { create, FONT, FONT_W, FONT_H };
});
