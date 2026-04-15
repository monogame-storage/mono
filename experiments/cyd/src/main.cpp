// CYD Mono runtime — hangman cart, 160x120 @ 2x, scene system + audio
// ------------------------------------------------------------------
// Target: ESP32-2432S028R (CYD dual-USB, ST7789)
// Canvas: 160x120 pushed at 2x via pushRotateZoom = 320x240 full screen
// Audio:  4-voice I2S+DAC mixer on GPIO 26 (see audio.h/cpp)
// Touch:  XPT2046, Y-flip + ÷2 for 2x scale mapping
//
// Engine API coverage:
//   Drawing:  cls pix rect rectf circ circf line text
//   Camera:   cam cam_reset cam_shake cam_get
//   Input:    touch touch_start touch_end touch_count touch_pos btn btnp
//   Audio:    tone note noise wave sfx_stop (real I2S mixer)
//   Scenes:   go scene_name (table-return pattern from engine.js)
//   Modules:  require (custom searcher for embedded cart files)
//   Lifecycle: _init _start _ready → go("scenes/title")
//   Meta:     screen mode frame time print use_pause
// ------------------------------------------------------------------

#include <Arduino.h>
#include <string.h>
#define LGFX_USE_V1
#include <LovyanGFX.hpp>

extern "C" {
  #include "lua.h"
  #include "lauxlib.h"
  #include "lualib.h"
}

#include "audio.h"

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

// ---- Game state -------------------------------------------------
static int       g_cam_x = 0, g_cam_y = 0;
static int       g_shake_frames = 0;
static uint32_t  g_frame = 0;
static uint32_t  g_boot_ms = 0;
static uint16_t  g_palette[16];

// Touch
static int       g_touch_x = 0, g_touch_y = 0;
static bool      g_touch_active  = false;
static bool      g_touch_prev    = false;
static bool      g_touch_started = false;
static bool      g_touch_ended   = false;

// 2x scale blit: pivot at canvas center → screen center.
static int16_t   g_dstCx = 160;
static int16_t   g_dstCy = 120;

// Scene system (mirrors engine.js go/scene_name/sceneObj pattern).
static char      g_scene_pending[64]  = "";
static char      g_scene_current[64]  = "";
static bool      g_scene_active       = false;

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

// mode(bits): rebuild palette. mode(1)=2 colors, mode(2)=4, mode(4)=16.
static int l_mode(lua_State* L) {
  int bits = argi(L, 1);
  int n = 1 << bits;
  if (n < 2)  n = 2;
  if (n > 16) n = 16;
  for (int i = 0; i < n; i++) {
    int g = (int)((float)i / (float)(n - 1) * 255.0f + 0.5f);
    g_palette[i] = canvas.color565(g, g, g);
  }
  for (int i = n; i < 16; i++) g_palette[i] = g_palette[n - 1];
  lua_pushinteger(L, n); lua_setglobal(L, "COLORS");
  return 0;
}

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

// ---- Audio bindings (real I2S mixer, not stubs) -----------------
static int l_tone(lua_State* L) {
  int ch = argi(L, 1);
  float startHz = (float)lua_tonumber(L, 2);
  float endHz   = (float)lua_tonumber(L, 3);
  float dur     = lua_isnumber(L, 4) ? (float)lua_tonumber(L, 4) : 0.2f;
  if (ch < 0 || ch >= NUM_VOICES) return 0;
  if (startHz < 1) startHz = 200;
  if (endHz < 1) endHz = startHz;
  play_sweep(ch, channel_wave[ch], startHz, endHz, dur, 0, 20, 0.15f);
  return 0;
}

static int l_note(lua_State* L) {
  int ch = argi(L, 1);
  const char* name = lua_tostring(L, 2);
  float dur = lua_isnumber(L, 3) ? (float)lua_tonumber(L, 3) : 0.1f;
  if (ch < 0 || ch >= NUM_VOICES) return 0;
  float freq = note_freq(name);
  play_note(ch, channel_wave[ch], freq, dur, 0, 20, 0.15f);
  return 0;
}

static int l_noise(lua_State* L) {
  int ch = argi(L, 1);
  float dur = lua_isnumber(L, 2) ? (float)lua_tonumber(L, 2) : 0.2f;
  uint8_t ft = FILTER_NONE;
  float cutoff = 1000;
  if (lua_isstring(L, 3)) {
    const char* s = lua_tostring(L, 3);
    if (s[0] == 'l' || s[0] == 'L') ft = FILTER_LOW;
    else if (s[0] == 'h' || s[0] == 'H') ft = FILTER_HIGH;
  }
  if (lua_isnumber(L, 4)) cutoff = (float)lua_tonumber(L, 4);
  if (ch < 0 || ch >= NUM_VOICES) return 0;
  play_noise(ch, dur, ft, cutoff, 0, 20, 0.15f);
  return 0;
}

static int l_wave(lua_State* L) {
  int ch = argi(L, 1);
  if (ch < 0 || ch >= NUM_VOICES) return 0;
  const char* t = lua_tostring(L, 2);
  if (!t) return 0;
  if      (t[0] == 's' && t[1] == 'q') channel_wave[ch] = WAVE_SQUARE;
  else if (t[0] == 's' && t[1] == 'a') channel_wave[ch] = WAVE_SAW;
  else if (t[0] == 's' && t[1] == 'i') channel_wave[ch] = WAVE_SINE;
  else if (t[0] == 't')                channel_wave[ch] = WAVE_TRIANGLE;
  return 0;
}

static int l_sfx_stop(lua_State* L) {
  if (lua_isnumber(L, 1)) stop_voice(argi(L, 1));
  else stop_all();
  return 0;
}

static int l_noop(lua_State*) { return 0; }

// ---- Lua prelude (mirrors engine.js wrappers) -------------------
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

// ---- Embedded cart files ----------------------------------------
#include "hangman_cart.h"

// Map module names used by require() to embedded source strings.
struct EmbedMod { const char* name; const char* src; };
static const EmbedMod embedded_modules[] = {
  { "game",   GAME_LUA },
  { "state",  STATE_LUA },
  { "words",  WORDS_LUA },
  { nullptr,  nullptr },
};

// Scene files (loaded via go()).
struct EmbedScene { const char* name; const char* src; };
static const EmbedScene embedded_scenes[] = {
  { "scenes/title",  SCENE_TITLE_LUA },
  { "scenes/play",   SCENE_PLAY_LUA },
  { "scenes/ending", SCENE_ENDING_LUA },
  { nullptr, nullptr },
};

// ---- Custom require searcher ------------------------------------
static int custom_searcher(lua_State* L) {
  const char* name = luaL_checkstring(L, 1);
  for (auto* m = embedded_modules; m->name; m++) {
    if (strcmp(name, m->name) == 0) {
      if (luaL_loadstring(L, m->src) != LUA_OK) return lua_error(L);
      return 1;
    }
  }
  lua_pushfstring(L, "\n\tno embedded module '%s'", name);
  return 1;
}

static void register_searcher() {
  lua_getglobal(L, "package");
  lua_getfield(L, -1, "searchers");
  lua_Integer n = luaL_len(L, -1);
  lua_pushcfunction(L, custom_searcher);
  lua_seti(L, -2, n + 1);
  lua_pop(L, 2);
}

// ---- Scene system -----------------------------------------------
static int l_go(lua_State* L) {
  const char* name = luaL_checkstring(L, 1);
  strncpy(g_scene_pending, name, sizeof(g_scene_pending) - 1);
  return 0;
}

static int l_scene_name(lua_State* L) {
  if (g_scene_active) lua_pushstring(L, g_scene_current);
  else                lua_pushboolean(L, 0);
  return 1;
}

// Find the embedded source for a scene name.
static const char* find_scene_src(const char* name) {
  for (auto* s = embedded_scenes; s->name; s++)
    if (strcmp(name, s->name) == 0) return s->src;
  return nullptr;
}

// Process pending go() at the end of each tick.
static void process_scene_transition() {
  if (g_scene_pending[0] == '\0') return;

  const char* src = find_scene_src(g_scene_pending);
  if (!src) {
    Serial.printf("scene '%s' not found\n", g_scene_pending);
    g_scene_pending[0] = '\0';
    return;
  }

  // Load file; if it returns a table, use it as the scene object.
  if (luaL_loadstring(L, src) != LUA_OK) {
    Serial.printf("scene load err: %s\n", lua_tostring(L, -1));
    lua_pop(L, 1);
    g_scene_pending[0] = '\0';
    return;
  }
  if (lua_pcall(L, 0, 1, 0) != LUA_OK) {
    Serial.printf("scene exec err: %s\n", lua_tostring(L, -1));
    lua_pop(L, 1);
    g_scene_pending[0] = '\0';
    return;
  }

  if (lua_istable(L, -1)) {
    lua_setglobal(L, "_scene_obj");
  } else {
    lua_pop(L, 1);
    lua_pushnil(L); lua_setglobal(L, "_scene_obj");
  }

  // Call scene.init() if present.
  lua_getglobal(L, "_scene_obj");
  if (lua_istable(L, -1)) {
    lua_getfield(L, -1, "init");
    if (lua_isfunction(L, -1)) {
      if (lua_pcall(L, 0, 0, 0) != LUA_OK) {
        Serial.printf("scene.init err: %s\n", lua_tostring(L, -1));
        lua_pop(L, 1);
      }
    } else {
      lua_pop(L, 1);
    }
  }
  lua_pop(L, 1);

  strncpy(g_scene_current, g_scene_pending, sizeof(g_scene_current) - 1);
  g_scene_active = true;
  g_scene_pending[0] = '\0';
  Serial.printf(">> scene: %s\n", g_scene_current);
}

// Call a method on the active scene table, or fall back to a global.
static void callSceneOrGlobal(const char* method, const char* global_fn) {
  if (g_scene_active) {
    lua_getglobal(L, "_scene_obj");
    if (lua_istable(L, -1)) {
      lua_getfield(L, -1, method);
      if (lua_isfunction(L, -1)) {
        if (lua_pcall(L, 0, 0, 0) != LUA_OK) {
          Serial.printf("%s.%s err: %s\n", g_scene_current, method,
                        lua_tostring(L, -1));
          lua_pop(L, 1);
        }
        lua_pop(L, 1);
        return;
      }
      lua_pop(L, 1);
    }
    lua_pop(L, 1);
  }
  // Fallback to global _update / _draw.
  lua_getglobal(L, global_fn);
  if (lua_isfunction(L, -1)) {
    if (lua_pcall(L, 0, 0, 0) != LUA_OK) {
      Serial.printf("%s err: %s\n", global_fn, lua_tostring(L, -1));
      lua_pop(L, 1);
    }
  } else {
    lua_pop(L, 1);
  }
}

// ---- Lua fatal + helpers ----------------------------------------
static void lua_fatal(const char* where) {
  const char* msg = lua_tostring(L, -1);
  Serial.printf("LUA FATAL @ %s: %s\n", where, msg ? msg : "(no msg)");
  while (true) delay(1000);
}

static void callLua(const char* fn) {
  lua_getglobal(L, fn);
  if (!lua_isfunction(L, -1)) { lua_pop(L, 1); return; }
  if (lua_pcall(L, 0, 0, 0) != LUA_OK) {
    Serial.printf("%s err: %s\n", fn, lua_tostring(L, -1));
    lua_pop(L, 1);
  }
}

// ---- Lua init ---------------------------------------------------
static void registerAPI() {
  #define REG(n, fn) lua_pushcfunction(L, fn); lua_setglobal(L, n)
  REG("screen",       l_screen);
  REG("mode",         l_mode);
  REG("cls",          l_cls);
  REG("pix",          l_pix);
  REG("rect",         l_rect);
  REG("rectf",        l_rectf);
  REG("circ",         l_circ);
  REG("circf",        l_circf);
  REG("line",         l_line);
  REG("text",         l_text);
  REG("cam",          l_cam);
  REG("cam_reset",    l_cam_reset);
  REG("cam_shake",    l_cam_shake);
  REG("_cam_get_x",   l_cam_get_x);
  REG("_cam_get_y",   l_cam_get_y);
  REG("frame",        l_frame);
  REG("time",         l_time);
  REG("_touch",       l_touch);
  REG("_touch_start", l_touch_start);
  REG("_touch_end",   l_touch_end);
  REG("touch_count",  l_touch_count);
  REG("_touch_pos_x", l_touch_pos_x);
  REG("_touch_pos_y", l_touch_pos_y);
  REG("_touch_posf_x",l_touch_pos_x);
  REG("_touch_posf_y",l_touch_pos_y);
  REG("_btn",         l_btn);
  REG("_btnp",        l_btnp);
  REG("print",        l_print);
  // Audio (real mixer)
  REG("tone",         l_tone);
  REG("note",         l_note);
  REG("noise",        l_noise);
  REG("wave",         l_wave);
  REG("sfx_stop",     l_sfx_stop);
  // Scenes
  REG("go",           l_go);
  REG("scene_name",   l_scene_name);
  // Misc stubs
  REG("use_pause",    l_noop);
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
  register_searcher();

  // Load prelude.
  if (luaL_loadstring(L, PRELUDE) != LUA_OK) lua_fatal("prelude load");
  if (lua_pcall(L, 0, 0, 0) != LUA_OK)       lua_fatal("prelude run");

  // Load main.lua (defines _init, _start, _ready).
  if (luaL_loadstring(L, MAIN_LUA) != LUA_OK) lua_fatal("main load");
  if (lua_pcall(L, 0, 0, 0) != LUA_OK)        lua_fatal("main chunk");

  // Lifecycle: _init → _start → _ready (engine.js order).
  callLua("_init");
  callLua("_start");
  callLua("_ready");   // typically calls go("scenes/title")

  // Process the initial go() so the first tick is already in a scene.
  process_scene_transition();

  unsigned memKB = (unsigned)lua_gc(L, LUA_GCCOUNT, 0);
  Serial.printf("Lua init OK. mem=%u KB\n", memKB);
}

// ---- Touch sampling (2x scale: screen ÷ 2 = canvas) ------------
static void sampleTouch() {
  int32_t tx, ty;
  bool touched = tft.getTouch(&tx, &ty);

  // Y-axis flip (CYD dual-USB ST7789 @ rotation 3).
  if (touched) ty = (tft.height() - 1) - ty;

  // 2x scale: screen pixel → canvas pixel = ÷ 2.
  int cx = touched ? (int)(tx / 2) : 0;
  int cy = touched ? (int)(ty / 2) : 0;
  bool in = touched && (unsigned)cx < (unsigned)MONO_W && (unsigned)cy < (unsigned)MONO_H;

  g_touch_started = in && !g_touch_prev;
  g_touch_ended   = !in && g_touch_prev;
  g_touch_active  = in;
  if (in) { g_touch_x = cx; g_touch_y = cy; }
  g_touch_prev = in;
}

// ---- setup / loop -----------------------------------------------
void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println();
  Serial.println("=== CYD Mono — hangman 160x120 @2x ===");
  Serial.printf("Panel:  %s  SPI=%d Hz\n", PANEL_NAME, CYD_SPI_FREQ);

  tft.init();
  tft.invertDisplay(PANEL_INVERT);
  tft.setRotation(3);
  tft.setBrightness(255);
  tft.fillScreen(TFT_BLACK);

  canvas.setColorDepth(16);
  if (!canvas.createSprite(MONO_W, MONO_H)) {
    Serial.println("FATAL: createSprite"); while (true) delay(1000);
  }
  canvas.setPivot(MONO_W * 0.5f, MONO_H * 0.5f);
  g_dstCx = tft.width()  / 2;
  g_dstCy = tft.height() / 2;

  // Default 16-level palette (overridden by mode(1) in hangman's _init).
  for (int i = 0; i < 16; i++) {
    int g = (int)((i / 15.0f) * 255.0f + 0.5f);
    g_palette[i] = canvas.color565(g, g, g);
  }

  Serial.printf("Canvas: %dx%d @2x = 320x240 full screen\n", MONO_W, MONO_H);

  audio_init();
  g_boot_ms = millis();
  initLua();
  Serial.println("Entering main loop.");
}

static constexpr uint32_t UPDATE_US = 1000000 / 30;
static uint32_t g_nextUpdateUs = 0;

void loop() {
  static uint32_t statsMs     = millis();
  static uint32_t statsRender = 0;
  static uint32_t statsUpdate = 0;
  static uint32_t statsMin    = 0xFFFFFFFFu;
  static uint32_t statsMax    = 0;
  static uint32_t statsWork   = 0;

  uint32_t frameStart = micros();

  // Logic tick at fixed 30 Hz.
  if ((int32_t)(frameStart - g_nextUpdateUs) >= 0) {
    sampleTouch();
    callSceneOrGlobal("update", "_update");
    process_scene_transition();
    statsUpdate++;
    g_nextUpdateUs += UPDATE_US;
    if ((int32_t)(frameStart - g_nextUpdateUs) > (int32_t)(UPDATE_US * 4))
      g_nextUpdateUs = frameStart + UPDATE_US;
  }

  // Render (free-running).
  callSceneOrGlobal("draw", "_draw");

  // 2x blit via pushRotateZoom (pivot at canvas center → screen center).
  int dx = g_dstCx, dy = g_dstCy;
  if (g_shake_frames > 0) {
    dx += (int)(esp_random() % 7) - 3;
    dy += (int)(esp_random() % 7) - 3;
    g_shake_frames--;
  }
  canvas.pushRotateZoom(&tft, dx, dy, 0.0f, 2.0f, 2.0f);

  g_frame++;
  uint32_t workUs = micros() - frameStart;

  statsRender++;
  statsWork += workUs;
  if (workUs < statsMin) statsMin = workUs;
  if (workUs > statsMax) statsMax = workUs;

  uint32_t nowMs = millis();
  if (nowMs - statsMs >= 2000) {
    float fps    = statsRender * 1000.0f / (float)(nowMs - statsMs);
    float tickHz = statsUpdate * 1000.0f / (float)(nowMs - statsMs);
    float avgMs  = (statsWork / (float)statsRender) / 1000.0f;
    unsigned mem = (unsigned)lua_gc(L, LUA_GCCOUNT, 0);
    Serial.printf("[hangman] fps=%5.1f  tick=%4.1fHz  work %4.1f..%4.1f avg %4.1fms  lua=%uKB\n",
                  fps, tickHz, statsMin/1000.0f, statsMax/1000.0f, avgMs, mem);
    statsMs = nowMs; statsRender = statsUpdate = statsWork = 0;
    statsMin = 0xFFFFFFFFu; statsMax = 0;
  }
}
