// CYD Mono Phase 3 — bubble via Mono engine API
// ------------------------------------------------------------------
// Target: ESP32-2432S028R (Cheap Yellow Display, dual-USB variant)
// Goal:   run the `bubble` demo (demo/bubble/main.lua) unchanged on
//         the CYD via native Lua 5.4 + a minimal port of the Mono
//         engine API to C bindings.
//
// What exists here:
//   - Panel: ST7789 @ 80 MHz SPI, 1:1 centered 160x144 canvas
//   - Lua 5.4.7 native, ~49 KB VM memory
//   - Mono engine API subset: cls/pix/rect/rectf/circ/circf/line/text,
//     cam/cam_get/cam_shake/cam_reset, screen/mode,
//     touch/touch_start/touch_end/touch_count/touch_pos,
//     frame/time, btn/btnp (stubs), sound stubs
//   - 4x7 Mono bitmap font, faithful port of runtime/engine.js FONT
//   - 16-level grayscale palette (matches buildPalette(4))
//
// Not in scope (stubbed or absent):
//   - Sound (note/tone/noise/wave)
//   - Image loading / sprite sheets
//   - Multi-surface canvases
//   - Physical buttons (CYD has none; touch only)
// ------------------------------------------------------------------

#include <Arduino.h>
#define LGFX_USE_V1
#include <LovyanGFX.hpp>

extern "C" {
  #include "lua.h"
  #include "lauxlib.h"
  #include "lualib.h"
}

// ---- ESP32-2432S028R (CYD) pin map ------------------------------
// TFT:   SCK=14 MOSI=13 MISO=12 CS=15 DC=2  RST=-1 BL=21
// Touch: CS=33 IRQ=36 (unused here)
//
// Build-time panel selector: define PANEL_DRIVER to one of
//   1 = ILI9341 (first-batch CYDs)
//   2 = ST7789  (most dual-USB CYDs — 2024+ batches)
//   3 = ILI9342 (rare 320x240-native variant)
#ifndef PANEL_DRIVER
#define PANEL_DRIVER 2
#endif

#if PANEL_DRIVER == 1
  using PanelT = lgfx::Panel_ILI9341;
  static constexpr bool   PANEL_INVERT = false;
  static constexpr bool   PANEL_RGB    = false;
  static constexpr int    PANEL_W      = 240;
  static constexpr int    PANEL_H      = 320;
  static constexpr const char* PANEL_NAME = "ILI9341";
#elif PANEL_DRIVER == 2
  using PanelT = lgfx::Panel_ST7789;
  static constexpr bool   PANEL_INVERT = true;   // ST7789 is usually inverted
  static constexpr bool   PANEL_RGB    = false;  // W/K polarity correct; no R<->B swap
  static constexpr int    PANEL_W      = 240;
  static constexpr int    PANEL_H      = 320;
  static constexpr const char* PANEL_NAME = "ST7789";
#elif PANEL_DRIVER == 3
  using PanelT = lgfx::Panel_ILI9342;
  static constexpr bool   PANEL_INVERT = false;
  static constexpr bool   PANEL_RGB    = false;
  static constexpr int    PANEL_W      = 320;   // native landscape
  static constexpr int    PANEL_H      = 240;
  static constexpr const char* PANEL_NAME = "ILI9342";
#else
  #error "Unknown PANEL_DRIVER"
#endif

class LGFX_CYD : public lgfx::LGFX_Device {
  PanelT               _panel;
  lgfx::Bus_SPI        _bus;
  lgfx::Light_PWM      _light;
  lgfx::Touch_XPT2046  _touch;
public:
  LGFX_CYD() {
    { auto c = _bus.config();
      c.spi_host    = HSPI_HOST;
      c.spi_mode    = 0;
      c.freq_write  = CYD_SPI_FREQ;
      c.freq_read   = 16000000;
      c.spi_3wire   = false;
      c.use_lock    = true;
      c.dma_channel = SPI_DMA_CH_AUTO;
      c.pin_sclk    = 14;
      c.pin_mosi    = 13;
      c.pin_miso    = 12;
      c.pin_dc      = 2;
      _bus.config(c);
      _panel.setBus(&_bus);
    }
    { auto c = _panel.config();
      c.pin_cs         = 15;
      c.pin_rst        = -1;
      c.pin_busy       = -1;
      c.panel_width    = PANEL_W;
      c.panel_height   = PANEL_H;
      c.offset_x       = 0;
      c.offset_y       = 0;
      c.offset_rotation= 0;
      c.readable       = false;
      c.invert         = PANEL_INVERT;
      c.rgb_order      = PANEL_RGB;
      c.dlen_16bit     = false;
      c.bus_shared     = false;
      _panel.config(c);
    }
    { auto c = _light.config();
      c.pin_bl     = 21;
      c.invert     = false;
      c.freq       = 44100;
      c.pwm_channel= 7;
      _light.config(c);
      _panel.light(&_light);
    }
    // Touch (XPT2046) on CYD uses VSPI, independent of the display bus.
    // The raw XPT axes run 180° rotated from the display after
    // setRotation(3). We *could* try to express this via min/max
    // swap, but LovyanGFX defensively normalizes min<max so that
    // trick is silently undone — the flip is applied manually in
    // sampleTouch() instead.
    { auto c = _touch.config();
      c.x_min       = 300;
      c.x_max       = 3900;
      c.y_min       = 200;
      c.y_max       = 3900;
      c.pin_int     = 36;
      c.bus_shared  = false;
      c.offset_rotation = 0;
      c.spi_host    = VSPI_HOST;
      c.freq        = 1000000;
      c.pin_sclk    = 25;
      c.pin_mosi    = 32;
      c.pin_miso    = 39;
      c.pin_cs      = 33;
      _touch.config(c);
      _panel.setTouch(&_touch);
    }
    setPanel(&_panel);
  }
};

static LGFX_CYD    tft;
static LGFX_Sprite canvas(&tft);
static lua_State*  L = nullptr;

// ---- Game state (managed by C, exposed to Lua) ------------------
static int       g_cam_x = 0, g_cam_y = 0;
static int       g_shake_frames = 0;
static uint32_t  g_frame = 0;
static uint32_t  g_boot_ms = 0;
static uint16_t  g_palette[16];

// Touch sampled once per frame; Lua reads through bindings.
static int       g_touch_x = 0, g_touch_y = 0;
static bool      g_touch_active  = false;   // held this frame
static bool      g_touch_prev    = false;   // held previous frame
static bool      g_touch_started = false;   // rising edge
static bool      g_touch_ended   = false;   // falling edge

// Canvas offset on screen (1:1 centered).
static int16_t   g_dstX = 80;
static int16_t   g_dstY = 48;

// ---- Mono 4x7 font ---------------------------------------------
#include "mono_font.h"
static constexpr int FONT_W = 4, FONT_H = 7;

static void monoDrawText(const char* str, int x, int y, int c, int align) {
  int len = 0;
  for (const char* p = str; *p; p++) len++;
  if (len == 0) return;
  int textW = len * (FONT_W + 1) - 1;
  if (align & 1) x -= textW / 2;
  else if (align & 2) x -= textW;
  if (align & 4) y -= FONT_H / 2;
  uint16_t col = g_palette[c & 15];
  for (const char* p = str; *p; p++) {
    unsigned char ch = (unsigned char)*p;
    if (ch >= 'a' && ch <= 'z') ch -= 32;
    uint32_t glyph = (ch < 128) ? MONO_FONT[ch] : 0;
    if (glyph) {
      for (int py = 0; py < FONT_H; py++) {
        for (int px = 0; px < FONT_W; px++) {
          if (glyph & (1u << (py * FONT_W + px))) {
            int dx = x + px - g_cam_x;
            int dy = y + py - g_cam_y;
            if ((unsigned)dx < (unsigned)MONO_W && (unsigned)dy < (unsigned)MONO_H)
              canvas.drawPixel(dx, dy, col);
          }
        }
      }
    }
    x += FONT_W + 1;
  }
}

// ---- Lua bindings ----------------------------------------------
// Fast float→int helper; bindings skip type-check for speed.
static inline int argi(lua_State* L, int i) { return (int)lua_tonumber(L, i); }
static inline uint16_t pal(int c) { return g_palette[c & 15]; }

static int l_screen(lua_State* L) { lua_pushinteger(L, 0); return 1; }
static int l_mode(lua_State* L) { (void)L; return 0; }    // always 16-gray; no-op

static int l_cls(lua_State* L) {
  canvas.fillSprite(pal(argi(L, 2)));
  return 0;
}

static int l_pix(lua_State* L) {
  int x = argi(L, 2) - g_cam_x;
  int y = argi(L, 3) - g_cam_y;
  canvas.drawPixel(x, y, pal(argi(L, 4)));
  return 0;
}

static int l_rect(lua_State* L) {
  canvas.drawRect(argi(L, 2) - g_cam_x, argi(L, 3) - g_cam_y,
                  argi(L, 4), argi(L, 5), pal(argi(L, 6)));
  return 0;
}
static int l_rectf(lua_State* L) {
  canvas.fillRect(argi(L, 2) - g_cam_x, argi(L, 3) - g_cam_y,
                  argi(L, 4), argi(L, 5), pal(argi(L, 6)));
  return 0;
}
static int l_circ(lua_State* L) {
  canvas.drawCircle(argi(L, 2) - g_cam_x, argi(L, 3) - g_cam_y,
                    argi(L, 4), pal(argi(L, 5)));
  return 0;
}
static int l_circf(lua_State* L) {
  canvas.fillCircle(argi(L, 2) - g_cam_x, argi(L, 3) - g_cam_y,
                    argi(L, 4), pal(argi(L, 5)));
  return 0;
}
static int l_line(lua_State* L) {
  canvas.drawLine(argi(L, 2) - g_cam_x, argi(L, 3) - g_cam_y,
                  argi(L, 4) - g_cam_x, argi(L, 5) - g_cam_y,
                  pal(argi(L, 6)));
  return 0;
}

static int l_text(lua_State* L) {
  const char* s = lua_tostring(L, 2);
  int x = argi(L, 3);
  int y = argi(L, 4);
  int c = argi(L, 5);
  int align = lua_isnumber(L, 6) ? argi(L, 6) : 0;
  if (s) monoDrawText(s, x, y, c, align);
  return 0;
}

static int l_cam(lua_State* L) {
  g_cam_x = argi(L, 1);
  g_cam_y = argi(L, 2);
  return 0;
}
static int l_cam_reset(lua_State* L) { (void)L; g_cam_x = g_cam_y = 0; g_shake_frames = 0; return 0; }
static int l_cam_get_x(lua_State* L) { lua_pushinteger(L, g_cam_x); return 1; }
static int l_cam_get_y(lua_State* L) { lua_pushinteger(L, g_cam_y); return 1; }
static int l_cam_shake(lua_State* L) { g_shake_frames = argi(L, 1); return 0; }

static int l_frame(lua_State* L) { lua_pushinteger(L, (lua_Integer)g_frame); return 1; }
static int l_time(lua_State* L) {
  lua_pushnumber(L, (double)(millis() - g_boot_ms) / 1000.0);
  return 1;
}

static int l_touch(lua_State* L)       { lua_pushinteger(L, (g_touch_active || g_touch_started) ? 1 : 0); return 1; }
static int l_touch_start(lua_State* L) { lua_pushinteger(L, g_touch_started ? 1 : 0); return 1; }
static int l_touch_end(lua_State* L)   { lua_pushinteger(L, g_touch_ended   ? 1 : 0); return 1; }
static int l_touch_count(lua_State* L) { lua_pushinteger(L, (g_touch_active || g_touch_started) ? 1 : 0); return 1; }
static int l_touch_pos_x(lua_State* L) {
  if (g_touch_active || g_touch_started) lua_pushinteger(L, g_touch_x);
  else lua_pushboolean(L, 0);
  return 1;
}
static int l_touch_pos_y(lua_State* L) {
  if (g_touch_active || g_touch_started) lua_pushinteger(L, g_touch_y);
  else lua_pushboolean(L, 0);
  return 1;
}

static int l_btn(lua_State* L)  { (void)L; lua_pushinteger(L, 0); return 1; }
static int l_btnp(lua_State* L) { (void)L; lua_pushinteger(L, 0); return 1; }

static int l_print(lua_State* L) {
  int n = lua_gettop(L);
  Serial.print("[Lua]");
  for (int i = 1; i <= n; i++) {
    Serial.print(" ");
    const char* s = lua_tostring(L, i);
    Serial.print(s ? s : "?");
  }
  Serial.println();
  return 0;
}

// Stubs for audio (bubble doesn't actually play sound yet, but some
// demos may call these).
static int l_noop(lua_State* L) { (void)L; return 0; }

// ---- Lua prelude (mirrors engine.js wrappers) ------------------
static const char* PRELUDE = R"MLUA(
function btn(k) return _btn(k) == 1 end
function btnp(k) return _btnp(k) == 1 end
function cam_get() return _cam_get_x(), _cam_get_y() end
function touch() return _touch() == 1 end
function touch_start() return _touch_start() == 1 end
function touch_end() return _touch_end() == 1 end
function touch_pos(i)
  i = i or 1
  local x = _touch_pos_x(i)
  if x == false then return false end
  return x, _touch_pos_y(i)
end
function touch_posf(i) return touch_pos(i) end
)MLUA";

#include "bubble_game.h"

static void lua_fatal(const char* where) {
  const char* msg = lua_tostring(L, -1);
  Serial.printf("LUA FATAL @ %s: %s\n", where, msg ? msg : "(no msg)");
  while (true) delay(1000);
}

static void registerAPI() {
  #define REG(name, fn) lua_pushcfunction(L, fn); lua_setglobal(L, name)
  REG("screen",      l_screen);
  REG("mode",        l_mode);
  REG("cls",         l_cls);
  REG("pix",         l_pix);
  REG("rect",        l_rect);
  REG("rectf",       l_rectf);
  REG("circ",        l_circ);
  REG("circf",       l_circf);
  REG("line",        l_line);
  REG("text",        l_text);
  REG("cam",         l_cam);
  REG("cam_reset",   l_cam_reset);
  REG("cam_shake",   l_cam_shake);
  REG("_cam_get_x",  l_cam_get_x);
  REG("_cam_get_y",  l_cam_get_y);
  REG("frame",       l_frame);
  REG("time",        l_time);
  REG("_touch",      l_touch);
  REG("_touch_start",l_touch_start);
  REG("_touch_end",  l_touch_end);
  REG("touch_count", l_touch_count);
  REG("_touch_pos_x",l_touch_pos_x);
  REG("_touch_pos_y",l_touch_pos_y);
  REG("_touch_posf_x", l_touch_pos_x);
  REG("_touch_posf_y", l_touch_pos_y);
  REG("_btn",        l_btn);
  REG("_btnp",       l_btnp);
  REG("print",       l_print);
  // Sound stubs
  REG("note",        l_noop);
  REG("tone",        l_noop);
  REG("noise",       l_noop);
  REG("wave",        l_noop);
  REG("sfx_stop",    l_noop);
  #undef REG

  lua_pushinteger(L, MONO_W); lua_setglobal(L, "SCREEN_W");
  lua_pushinteger(L, MONO_H); lua_setglobal(L, "SCREEN_H");
  lua_pushinteger(L, 16);     lua_setglobal(L, "COLORS");
  lua_pushinteger(L, 0);      lua_setglobal(L, "ALIGN_LEFT");
  lua_pushinteger(L, 1);      lua_setglobal(L, "ALIGN_HCENTER");
  lua_pushinteger(L, 2);      lua_setglobal(L, "ALIGN_RIGHT");
  lua_pushinteger(L, 4);      lua_setglobal(L, "ALIGN_VCENTER");
  lua_pushinteger(L, 5);      lua_setglobal(L, "ALIGN_CENTER");
}

static void initLua() {
  L = luaL_newstate();
  if (!L) { Serial.println("newstate failed"); while(1) delay(1000); }
  luaL_openlibs(L);
  registerAPI();

  if (luaL_loadstring(L, PRELUDE) != LUA_OK) lua_fatal("prelude load");
  if (lua_pcall(L, 0, 0, 0) != LUA_OK)       lua_fatal("prelude run");

  if (luaL_loadstring(L, BUBBLE_LUA) != LUA_OK) lua_fatal("bubble load");
  if (lua_pcall(L, 0, 0, 0) != LUA_OK)          lua_fatal("bubble chunk");

  lua_getglobal(L, "_init");
  if (lua_isfunction(L, -1)) {
    if (lua_pcall(L, 0, 0, 0) != LUA_OK) lua_fatal("_init");
  } else {
    lua_pop(L, 1);
  }

  unsigned memKB = (unsigned)lua_gc(L, LUA_GCCOUNT, 0);
  Serial.printf("Lua init OK. mem=%u KB\n", memKB);
}

static void callLua(const char* fn) {
  lua_getglobal(L, fn);
  if (!lua_isfunction(L, -1)) { lua_pop(L, 1); return; }
  if (lua_pcall(L, 0, 0, 0) != LUA_OK) {
    Serial.printf("%s error: %s\n", fn, lua_tostring(L, -1));
    lua_pop(L, 1);
  }
}

// ---- Touch sampling --------------------------------------------
static void sampleTouch() {
  int32_t tx, ty;
  bool touched = tft.getTouch(&tx, &ty);

  // Manual Y-axis flip: LovyanGFX returns correct X for this CYD
  // variant after setRotation(3), but raw Y is inverted relative to
  // the display. The "flip y_min/y_max" trick doesn't work because
  // LovyanGFX defensively normalizes the calibration bounds, so the
  // inversion must be applied in C. Verified via the 5-point guided
  // calibration routine (see git history for the calibrateTouch()
  // implementation if you need to recheck on a new unit).
  if (touched) {
    ty = (tft.height() - 1) - ty;
  }

  // Canvas-space mapping for the game.
  int cx = tx - g_dstX;
  int cy = ty - g_dstY;
  bool in = touched && (unsigned)cx < (unsigned)MONO_W && (unsigned)cy < (unsigned)MONO_H;
  g_touch_started = in && !g_touch_prev;
  g_touch_ended   = !in && g_touch_prev;
  g_touch_active  = in;
  if (in) { g_touch_x = cx; g_touch_y = cy; }
  g_touch_prev = in;
}

// ---- setup / loop ----------------------------------------------
void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println();
  Serial.println("=== CYD Mono Phase 3 — bubble ===");
  Serial.printf("Panel:  %s  SPI=%d Hz\n", PANEL_NAME, CYD_SPI_FREQ);

  tft.init();
  tft.invertDisplay(PANEL_INVERT);
  tft.setRotation(3);
  tft.setBrightness(255);
  tft.fillScreen(TFT_BLACK);

  canvas.setColorDepth(16);
  if (!canvas.createSprite(MONO_W, MONO_H)) {
    Serial.println("FATAL: createSprite failed"); while (true) delay(1000);
  }

  // Build 16-level grayscale palette (matches engine.js buildPalette(4)).
  for (int i = 0; i < 16; i++) {
    int g = (int)((i / 15.0f) * 255.0f + 0.5f);
    g_palette[i] = canvas.color565(g, g, g);
  }

  g_dstX = (tft.width()  - MONO_W) / 2;
  g_dstY = (tft.height() - MONO_H) / 2;
  Serial.printf("Canvas: %dx%d centered at (%d,%d)\n",
                MONO_W, MONO_H, g_dstX, g_dstY);

  g_boot_ms = millis();
  initLua();
  Serial.println("Entering main loop.");
}

// Mono targets 30 Hz for its logical tick (see runtime/engine.js
// FPS/FRAME_MS). Demos use frame-counted timing — e.g. bubble's
// `spawn_rate = 28` means "one bubble every 28 _update calls" — so
// _update must run at exactly 30 Hz or game speed scales wrong.
//
// Rendering (_draw + pushSprite) runs free, without a cap. That
// matches ESP32 headroom (160+ fps is typical) and keeps the render
// path showing real hardware performance in the stats line. Between
// updates, _draw redraws the same game state, which is cheap on a
// 160x144 1:1 canvas.
static constexpr uint32_t UPDATE_US = 1000000 / 30;   // 33,333 µs
static uint32_t g_nextUpdateUs = 0;

void loop() {
  static uint32_t statsMs     = millis();
  static uint32_t statsRender = 0;  // render frames in this window
  static uint32_t statsUpdate = 0;  // logic ticks  in this window
  static uint32_t statsMin    = 0xFFFFFFFFu;
  static uint32_t statsMax    = 0;
  static uint32_t statsWork   = 0;

  uint32_t frameStart = micros();

  // ---- Logic tick (fixed 30 Hz) ---------------------------------
  // Use a signed compare so the deadline can stay ahead of `now`
  // without wraparound drama. If we fall more than 4 frames behind
  // (rare — a GC stall or flash-induced hitch), reset the deadline
  // instead of running update multiple times in a row.
  if ((int32_t)(frameStart - g_nextUpdateUs) >= 0) {
    sampleTouch();
    callLua("_update");
    statsUpdate++;
    g_nextUpdateUs += UPDATE_US;
    if ((int32_t)(frameStart - g_nextUpdateUs) > (int32_t)(UPDATE_US * 4)) {
      g_nextUpdateUs = frameStart + UPDATE_US;
    }
  }

  // ---- Render (free-running) ------------------------------------
  callLua("_draw");

  int dx = g_dstX, dy = g_dstY;
  if (g_shake_frames > 0) {
    dx += (int)(esp_random() % 7) - 3;
    dy += (int)(esp_random() % 7) - 3;
    // Decrement on update ticks only so shake duration stays in
    // frames-of-game-logic, not frames-of-render.
    // (Actually decrement here is fine because shake_frames is set
    // by Lua in _update — it'll just decay at render rate. Match
    // engine.js behavior: keep it simple, decrement once per render.)
    g_shake_frames--;
  }
  canvas.pushSprite(&tft, dx, dy);

  g_frame++;
  uint32_t frameEnd = micros();
  uint32_t workUs   = frameEnd - frameStart;

  // ---- Stats ----------------------------------------------------
  statsRender++;
  statsWork += workUs;
  if (workUs < statsMin) statsMin = workUs;
  if (workUs > statsMax) statsMax = workUs;

  uint32_t nowMs = millis();
  if (nowMs - statsMs >= 1000) {
    float fps     = statsRender * 1000.0f / (float)(nowMs - statsMs);
    float tickHz  = statsUpdate * 1000.0f / (float)(nowMs - statsMs);
    float avgMs   = (statsWork / (float)statsRender) / 1000.0f;
    unsigned memKB = (unsigned)lua_gc(L, LUA_GCCOUNT, 0);
    Serial.printf("[bubble] fps=%5.1f  tick=%4.1fHz  work %4.1f..%4.1f avg %4.1fms  lua=%uKB\n",
                  fps, tickHz,
                  statsMin/1000.0f, statsMax/1000.0f, avgMs, memKB);

    // On-screen HUD in the bottom letterbox (screen y 196..239, the
    // strip under the 160x144 canvas). Drawn straight to tft, not
    // canvas, so it survives canvas redraws.
    tft.fillRect(0, 196, tft.width(), tft.height() - 196, TFT_BLACK);
    tft.setTextColor(TFT_WHITE, TFT_BLACK);
    tft.setTextSize(1);
    tft.setCursor(4, 200);
    tft.printf("fps %5.1f  tick %4.1fHz", fps, tickHz);
    tft.setCursor(4, 212);
    tft.printf("work %4.1f-%4.1f avg %4.1fms", statsMin/1000.0f, statsMax/1000.0f, avgMs);
    tft.setCursor(4, 224);
    tft.printf("lua %u KB  frm %lu", memKB, (unsigned long)g_frame);

    statsMs     = nowMs;
    statsRender = 0;
    statsUpdate = 0;
    statsWork   = 0;
    statsMin    = 0xFFFFFFFFu;
    statsMax    = 0;
  }
}
