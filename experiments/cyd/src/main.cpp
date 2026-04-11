// CYD Mono blit probe
// ------------------------------------------------------------------
// Target: ESP32-2432S028R (Cheap Yellow Display, dual-USB variant)
// Goal:   measure achievable FPS for a 160x120 framebuffer pushed to
//         the 320x240 ILI9341 at 2x integer scale via LovyanGFX.
//
// Four benchmark modes cycle every BENCH_SECONDS:
//   A  FLUSH_ONLY        — re-flush a static pattern (raw blit ceiling)
//   B  CLEAR+FLUSH       — full-screen clear + flush
//   C  CLEAR+64+FLUSH    — clear + 64 moving 8x8 rects + flush (typical)
//   D  CLEAR+256+FLUSH   — clear + 256 moving 8x8 rects + flush (stress)
//
// Each mode reports avg fps, min/max frame time, and frame count over
// Serial. The currently-active mode and its live fps are drawn in the
// top-left of the canvas so you can read it off the physical display.
// ------------------------------------------------------------------

#include <Arduino.h>
#define LGFX_USE_V1
#include <LovyanGFX.hpp>

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

// ---- Workload ---------------------------------------------------
struct Rect { float x, y, vx, vy; uint16_t color; };
static constexpr int MAX_RECTS = 256;
static Rect rects[MAX_RECTS];

static void initRects() {
  randomSeed(0xC0FFEE);
  for (int i = 0; i < MAX_RECTS; i++) {
    rects[i].x  = random(MONO_W - 8);
    rects[i].y  = random(MONO_H - 8);
    rects[i].vx = (random(200) - 100) / 50.0f;
    rects[i].vy = (random(200) - 100) / 50.0f;
    // 16-level grayscale, matching Mono's palette range.
    uint8_t g = (uint8_t)(random(16) * 17);
    rects[i].color = canvas.color565(g, g, g);
  }
}

static void stepAndDrawRects(int n) {
  for (int i = 0; i < n; i++) {
    rects[i].x += rects[i].vx;
    rects[i].y += rects[i].vy;
    if (rects[i].x < 0)           { rects[i].x = 0;           rects[i].vx = -rects[i].vx; }
    if (rects[i].x > MONO_W - 8)  { rects[i].x = MONO_W - 8;  rects[i].vx = -rects[i].vx; }
    if (rects[i].y < 0)           { rects[i].y = 0;           rects[i].vy = -rects[i].vy; }
    if (rects[i].y > MONO_H - 8)  { rects[i].y = MONO_H - 8;  rects[i].vy = -rects[i].vy; }
    canvas.fillRect((int)rects[i].x, (int)rects[i].y, 8, 8, rects[i].color);
  }
}

// ---- Bench driver -----------------------------------------------
enum Mode { M_FLUSH, M_CLEAR, M_64, M_256, NUM_MODES };
static const char* MODE_NAME[] = {
  "A FLUSH",
  "B CLEAR",
  "C 64 RECT",
  "D 256 RECT",
};
static const int MODE_RECTS[] = { 0, 0, 64, 256 };

// Start on the stress case — worst thermals + load hit the operator first.
static int g_mode = M_256;

// All-time stats since the current mode was entered.
static uint32_t g_modeStartMs = 0;
static uint32_t g_framesAll   = 0;
static uint32_t g_minDtAll    = 0xFFFFFFFFu;
static uint32_t g_maxDtAll    = 0;
static uint64_t g_sumDtAll    = 0;

// Rolling 1-second window.
static uint32_t g_rollStartMs   = 0;
static uint32_t g_rollFrames    = 0;
static uint32_t g_rollMaxDt     = 0;
static float    g_rollFps       = 0.0f;
static uint32_t g_rollMaxDtLast = 0;   // frozen peak dt from the last closed window

// Touch edge detect (rising edge = tap).
static bool g_touchPrev = false;

// Screen-center cache, filled in setup().
static int16_t g_dstCx = 160;
static int16_t g_dstCy = 120;

static inline void flush2x() {
  canvas.pushRotateZoom(&tft, g_dstCx, g_dstCy, 0.0f, 2.0f, 2.0f);
}

static void paintHUD() {
  // Background strip so text stays readable over moving rects.
  canvas.fillRect(0, 0, MONO_W, 46, TFT_BLACK);
  canvas.setTextColor(TFT_WHITE, TFT_BLACK);
  canvas.setTextSize(1);

  uint32_t nowMs    = millis();
  uint32_t elapsed  = nowMs - g_modeStartMs;
  uint32_t elapsedS = elapsed / 1000;
  float    avgFps   = g_framesAll > 0
                    ? (g_framesAll * 1000.0f / (float)(elapsed == 0 ? 1 : elapsed))
                    : 0.0f;
  float    avgMs    = g_framesAll > 0
                    ? (float)(g_sumDtAll / (uint64_t)g_framesAll) / 1000.0f
                    : 0.0f;

  canvas.setCursor(2, 1);
  canvas.printf("%-10s %02lu:%02lu",
                MODE_NAME[g_mode],
                (unsigned long)(elapsedS / 60),
                (unsigned long)(elapsedS % 60));

  canvas.setCursor(2, 10);
  canvas.printf("now %5.1f  avg %5.1f", g_rollFps, avgFps);

  canvas.setCursor(2, 19);
  canvas.printf("dt %4.1f-%4.1f ms",
                g_minDtAll / 1000.0f, g_maxDtAll / 1000.0f);

  canvas.setCursor(2, 28);
  canvas.printf("win-max %4.1f avg %4.1f",
                g_rollMaxDtLast / 1000.0f, avgMs);

  canvas.setCursor(2, 37);
  canvas.printf("TAP=next  frm=%lu",
                (unsigned long)g_framesAll);
}

static void prepareFlushOnlyCanvas() {
  canvas.fillSprite(TFT_BLACK);
  for (int y = 0; y < MONO_H; y += 8) {
    for (int x = 0; x < MONO_W; x += 8) {
      uint8_t g = ((x ^ y) & 0xF) * 17;
      canvas.fillRect(x, y, 8, 8, canvas.color565(g, g, g));
    }
  }
  paintHUD();
}

static void drawFrameFor(int m) {
  if (m == M_FLUSH) {
    // Static pattern — don't touch the canvas so the number stays pure.
    return;
  }
  canvas.fillSprite(TFT_BLACK);
  stepAndDrawRects(MODE_RECTS[m]);
  paintHUD();
}

static void resetStatsForMode() {
  g_modeStartMs   = millis();
  g_framesAll     = 0;
  g_minDtAll      = 0xFFFFFFFFu;
  g_maxDtAll      = 0;
  g_sumDtAll      = 0;
  g_rollStartMs   = g_modeStartMs;
  g_rollFrames    = 0;
  g_rollMaxDt     = 0;
  g_rollFps       = 0.0f;
  g_rollMaxDtLast = 0;
}

static void enterMode(int m) {
  g_mode = m;
  resetStatsForMode();
  if (m == M_FLUSH) prepareFlushOnlyCanvas();
  Serial.printf(">> enter %s\n", MODE_NAME[m]);
}

// ---- setup / loop -----------------------------------------------
void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println();
  Serial.println("=== CYD Mono Blit Probe ===");
  Serial.printf("Panel:    %s\n", PANEL_NAME);
  Serial.printf("SPI freq: %d Hz\n", CYD_SPI_FREQ);
  Serial.printf("Canvas:   %dx%d -> 320x240 (2x)\n", MONO_W, MONO_H);

  tft.init();
  // Panel_ST7789's compile-time invert flag doesn't take effect during
  // init() — INVON must be asserted explicitly.
  tft.invertDisplay(PANEL_INVERT);
  tft.setRotation(3);
  tft.setBrightness(255);
  tft.fillScreen(TFT_BLACK);

  Serial.printf("Screen:   %dx%d\n", tft.width(), tft.height());

  canvas.setColorDepth(16);
  if (!canvas.createSprite(MONO_W, MONO_H)) {
    Serial.println("FATAL: createSprite failed (no RAM)");
    while (true) { delay(1000); }
  }
  canvas.setPivot(MONO_W * 0.5f, MONO_H * 0.5f);
  g_dstCx = tft.width()  / 2;
  g_dstCy = tft.height() / 2;

  initRects();
  enterMode(g_mode);
}

void loop() {
  static uint32_t lastUs = micros();

  drawFrameFor(g_mode);
  flush2x();

  // ---- Frame timing ---------------------------------------------
  uint32_t now = micros();
  uint32_t dt  = now - lastUs;
  lastUs = now;

  g_framesAll++;
  g_sumDtAll += dt;
  if (dt < g_minDtAll) g_minDtAll = dt;
  if (dt > g_maxDtAll) g_maxDtAll = dt;

  g_rollFrames++;
  if (dt > g_rollMaxDt) g_rollMaxDt = dt;

  // Close the 1-second rolling window.
  uint32_t nowMs   = millis();
  uint32_t rollMs  = nowMs - g_rollStartMs;
  if (rollMs >= 1000) {
    g_rollFps       = g_rollFrames * 1000.0f / (float)rollMs;
    g_rollMaxDtLast = g_rollMaxDt;
    Serial.printf("[%-9s] t=%5lus  now=%5.1f  avg=%5.1f  dt=%4.1f..%4.1fms  win-max=%4.1fms  frm=%lu\n",
                  MODE_NAME[g_mode],
                  (unsigned long)((nowMs - g_modeStartMs) / 1000),
                  g_rollFps,
                  g_framesAll * 1000.0f
                    / (float)((nowMs - g_modeStartMs) == 0 ? 1 : (nowMs - g_modeStartMs)),
                  g_minDtAll / 1000.0f,
                  g_maxDtAll / 1000.0f,
                  g_rollMaxDtLast / 1000.0f,
                  (unsigned long)g_framesAll);
    g_rollStartMs = nowMs;
    g_rollFrames  = 0;
    g_rollMaxDt   = 0;
  }

  // ---- Touch edge → advance mode --------------------------------
  // Poll touch once per frame. Rising edge = tap.
  int32_t tx, ty;
  bool touched = tft.getTouch(&tx, &ty);
  if (touched && !g_touchPrev) {
    enterMode((g_mode + 1) % NUM_MODES);
  }
  g_touchPrev = touched;
}
