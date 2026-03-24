/**
 * Mono Platform API Type Definitions
 * 320x240 | 4-color grayscale | 30fps | 16x16 sprites | 2ch square wave
 */

// ── Strict Types ──
type Color = 0 | 1 | 2 | 3;
type Key = "up" | "down" | "left" | "right" | "a" | "b" | "start" | "select";
type Channel = 0 | 1;

// ── Lifecycle (game must export these) ──
declare function init(): void;
declare function update(): void;
declare function draw(): void;

// ── Graphics ──
declare function cls(color?: Color): void;
declare function pix(x: number, y: number, color: Color): void;
declare function line(x0: number, y0: number, x1: number, y1: number, color: Color): void;
declare function rect(x: number, y: number, w: number, h: number, color: Color): void;
declare function rectf(x: number, y: number, w: number, h: number, color: Color): void;
declare function circ(cx: number, cy: number, r: number, color: Color): void;
declare function circf(cx: number, cy: number, r: number, color: Color): void;
declare function text(str: string, x: number, y: number, color: Color): void;

// ── Sprites ──
declare function sprite(id: number, data: string): void;
declare function spr(id: number, x: number, y: number, flipX?: boolean, flipY?: boolean): void;

// ── Tilemap ──
declare function mget(cx: number, cy: number): number;
declare function mset(cx: number, cy: number, id: number): void;
declare function map(mx: number, my: number, mw: number, mh: number, sx: number, sy: number): void;

// ── Input ──
declare function btn(key: Key): boolean;
declare function btnp(key: Key): boolean;

// ── Sound ──
declare function note(channel: Channel, note: string, duration: number): void;
declare function stop(channel?: Channel): void;

// ── Utility ──
declare function rnd(max: number): number;
declare function flr(n: number): number;
declare function abs(n: number): number;
declare function min(a: number, b: number): number;
declare function max(a: number, b: number): number;
declare function sin(n: number): number;
declare function cos(n: number): number;

// ── Debug ──
declare function dbg(x: number, y: number, w: number, h: number): void;
declare function dbgC(x: number, y: number, r: number): void;
declare function dbgPt(x: number, y: number): void;

// ── Constants ──
declare const frame: number;

// ── Screen ──
declare const W: 320;
declare const H: 240;
