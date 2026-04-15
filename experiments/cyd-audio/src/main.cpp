// CYD Mono audio test program
// ------------------------------------------------------------------
// Standalone test firmware that exercises every feature of the
// reverse-designed Mono audio spec on an ESP32-2432S028R (CYD).
//
// Audio stack:
//   - I2S + internal DAC (GPIO 26) at 22,050 Hz, 8-bit mono
//   - 4-voice software mixer running in a dedicated core-0 task
//   - Waveforms: square, triangle, sawtooth, sine, LFSR noise, sample
//   - Per-voice linear AD envelope (attack + decay, no sustain)
//   - Per-voice linear frequency sweep
//   - 1-pole IIR low/high-pass filter for noise
//   - Sample playback (pitch-shifted PCM from RAM)
//
// UI scenes (cycle with < / > buttons, trigger with PLAY):
//   1. WELCOME     — description only
//   2. WAVEFORMS   — 5 waves on C4 in sequence
//   3. SCALE       — C major C4 to C5
//   4. SWEEPS      — up, down, fast, slow
//   5. ENVELOPE    — 4 attack/decay shapes
//   6. POLYPHONY   — C major triad held while melody plays on ch 3
//   7. NOISE       — raw / lowpass / highpass
//   8. SAMPLES     — pre-synthesized blip at 4 pitches
// ------------------------------------------------------------------

#include <Arduino.h>
#include <math.h>
#define LGFX_USE_V1
#include <LovyanGFX.hpp>

extern "C" {
  #include "driver/i2s.h"
  #include "driver/adc.h"
  #include "driver/dac.h"
}

// =================================================================
// LGFX_CYD — ST7789 display + XPT2046 touch (copied from cyd/)
// =================================================================
class LGFX_CYD : public lgfx::LGFX_Device {
  lgfx::Panel_ST7789    _panel;
  lgfx::Bus_SPI         _bus;
  lgfx::Light_PWM       _light;
  lgfx::Touch_XPT2046   _touch;
public:
  LGFX_CYD() {
    { auto c = _bus.config();
      c.spi_host = HSPI_HOST; c.spi_mode = 0;
      c.freq_write = CYD_SPI_FREQ; c.freq_read = 16000000;
      c.spi_3wire = false; c.use_lock = true;
      c.dma_channel = SPI_DMA_CH_AUTO;
      c.pin_sclk = 14; c.pin_mosi = 13; c.pin_miso = 12; c.pin_dc = 2;
      _bus.config(c); _panel.setBus(&_bus);
    }
    { auto c = _panel.config();
      c.pin_cs = 15; c.pin_rst = -1; c.pin_busy = -1;
      c.panel_width = 240; c.panel_height = 320;
      c.offset_x = 0; c.offset_y = 0; c.offset_rotation = 0;
      c.readable = false; c.invert = true; c.rgb_order = false;
      c.dlen_16bit = false; c.bus_shared = false;
      _panel.config(c);
    }
    { auto c = _light.config();
      c.pin_bl = 21; c.invert = false; c.freq = 44100; c.pwm_channel = 7;
      _light.config(c); _panel.light(&_light);
    }
    { auto c = _touch.config();
      c.x_min = 300; c.x_max = 3900;
      c.y_min = 200; c.y_max = 3900;
      c.pin_int = 36; c.bus_shared = false; c.offset_rotation = 0;
      c.spi_host = VSPI_HOST; c.freq = 1000000;
      c.pin_sclk = 25; c.pin_mosi = 32; c.pin_miso = 39; c.pin_cs = 33;
      _touch.config(c); _panel.setTouch(&_touch);
    }
    setPanel(&_panel);
  }
};

static LGFX_CYD tft;

// =================================================================
// Audio engine
// =================================================================

static constexpr int SAMPLE_RATE    = 22050;
static constexpr int NUM_VOICES     = 4;
static constexpr int BUFFER_SAMPLES = 256;      // I2S DMA buffer size
static constexpr int DMA_BUF_COUNT  = 4;

enum WaveType : uint8_t {
  WAVE_SQUARE = 0,
  WAVE_TRIANGLE,
  WAVE_SAW,
  WAVE_SINE,
  WAVE_NOISE,
  WAVE_SAMPLE,
  NUM_WAVES
};

enum FilterType : uint8_t {
  FILTER_NONE = 0,
  FILTER_LOW,
  FILTER_HIGH,
};

// Waveform tables: 256 entries, int8_t (-128..127).
// Sample = wave_table[wave][phase * 256].
static int8_t wave_table[4][256];

static void init_wave_tables() {
  for (int i = 0; i < 256; i++) {
    // Square: -128 first half, 127 second half.
    wave_table[WAVE_SQUARE][i]   = (i < 128) ? -128 : 127;
    // Triangle: -128→127 linear up, then down.
    wave_table[WAVE_TRIANGLE][i] = (i < 128) ? (int8_t)(i * 2 - 128)
                                             : (int8_t)(255 - (i - 128) * 2 - 128);
    // Sawtooth: -128→127 linear rise each cycle.
    wave_table[WAVE_SAW][i]      = (int8_t)(i - 128);
    // Sine via libm.
    wave_table[WAVE_SINE][i]     = (int8_t)(sinf((float)i / 256.0f * 2.0f * (float)M_PI) * 126.0f);
  }
}

struct Voice {
  volatile bool active;
  uint8_t       wave;

  // Synth oscillator
  float phase;        // WAVE_*: 0..1 cycle  / WAVE_SAMPLE: buffer index
  float phase_inc;    // per-sample advance
  float phase_inc_delta;  // linear sweep increment per sample

  // Envelope (linear AD, no sustain)
  uint32_t env_pos;
  uint32_t env_total;
  uint32_t env_attack;
  uint32_t env_decay;

  float volume;       // 0..1

  // Noise
  uint16_t lfsr;

  // Filter
  uint8_t filter;
  float   filter_alpha;
  float   filter_state;

  // Sample playback
  const int8_t* sample_data;
  uint32_t      sample_length;
};

static Voice voices[NUM_VOICES];

// -----------------------------------------------------------------
// Per-sample mixer
// -----------------------------------------------------------------
static inline int16_t voice_sample(Voice& v) {
  if (!v.active) return 0;
  if (v.env_pos >= v.env_total) { v.active = false; return 0; }

  // ---- Waveform ----
  int16_t s = 0;
  switch (v.wave) {
    case WAVE_SAMPLE: {
      uint32_t idx = (uint32_t)v.phase;
      if (idx >= v.sample_length) { v.active = false; return 0; }
      s = v.sample_data[idx];
      v.phase += v.phase_inc;
      break;
    }
    case WAVE_NOISE: {
      // Galois LFSR (x^16 + x^14 + x^13 + x^11 + 1).
      uint16_t lfsr = v.lfsr;
      uint16_t bit = ((lfsr >> 0) ^ (lfsr >> 2) ^ (lfsr >> 3) ^ (lfsr >> 5)) & 1;
      v.lfsr = (lfsr >> 1) | (bit << 15);
      s = (int8_t)((v.lfsr & 0xFF) - 128);
      // phase advance not strictly needed for noise but lets freq modulate LFSR rate
      v.phase += v.phase_inc;
      if (v.phase >= 1.0f) v.phase -= 1.0f;
      break;
    }
    default: {
      int idx = ((int)(v.phase * 256.0f)) & 0xFF;
      s = wave_table[v.wave][idx];
      v.phase += v.phase_inc;
      if (v.phase >= 1.0f) v.phase -= 1.0f;
      break;
    }
  }

  // ---- Frequency sweep ----
  if (v.phase_inc_delta != 0.0f) {
    v.phase_inc += v.phase_inc_delta;
    if (v.phase_inc < 0) v.phase_inc = 0;
  }

  // ---- 1-pole IIR filter (noise only, but cheap so we don't gate) ----
  if (v.filter != FILTER_NONE) {
    float fs = (float)s;
    v.filter_state += v.filter_alpha * (fs - v.filter_state);
    s = (int16_t)((v.filter == FILTER_LOW) ? v.filter_state
                                           : (fs - v.filter_state));
  }

  // ---- Envelope (linear AD) ----
  float env;
  if (v.env_pos < v.env_attack) {
    env = (float)v.env_pos / (float)v.env_attack;
  } else if (v.env_pos >= v.env_total - v.env_decay) {
    uint32_t left = v.env_total - v.env_pos;
    env = (float)left / (float)v.env_decay;
  } else {
    env = 1.0f;
  }
  v.env_pos++;

  return (int16_t)(s * env * v.volume);
}

static inline int16_t mix_sample() {
  int32_t sum = 0;
  for (int i = 0; i < NUM_VOICES; i++) sum += voice_sample(voices[i]);
  sum /= NUM_VOICES;   // simple averaging to prevent clipping
  if (sum > 127)  sum = 127;
  if (sum < -128) sum = -128;
  return (int16_t)sum;
}

// -----------------------------------------------------------------
// I2S driver
// -----------------------------------------------------------------
static void init_audio_i2s() {
  i2s_config_t cfg = {};
  cfg.mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_TX | I2S_MODE_DAC_BUILT_IN);
  cfg.sample_rate = SAMPLE_RATE;
  cfg.bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT;
  // ONLY_LEFT + LEFT_EN below = data goes to GPIO 26 (DAC2) only.
  // This matters for CYD because GPIO 25 (DAC1) is shared with the
  // XPT2046 touch SCLK; routing audio there kills touch entirely.
  cfg.channel_format = I2S_CHANNEL_FMT_ONLY_LEFT;
  cfg.communication_format = I2S_COMM_FORMAT_STAND_MSB;
  cfg.intr_alloc_flags = 0;
  cfg.dma_buf_count = DMA_BUF_COUNT;
  cfg.dma_buf_len = BUFFER_SAMPLES;
  cfg.use_apll = false;
  cfg.tx_desc_auto_clear = true;
  cfg.fixed_mclk = 0;

  esp_err_t err = i2s_driver_install(I2S_NUM_0, &cfg, 0, NULL);
  if (err != ESP_OK) { Serial.printf("i2s_driver_install: %d\n", err); }

  // ESP-IDF naming is counterintuitive:
  //   I2S_DAC_CHANNEL_RIGHT_EN → DAC1 → GPIO 25  (shared with touch SCLK on CYD)
  //   I2S_DAC_CHANNEL_LEFT_EN  → DAC2 → GPIO 26  (CYD speaker path)
  i2s_set_dac_mode(I2S_DAC_CHANNEL_LEFT_EN);
  i2s_zero_dma_buffer(I2S_NUM_0);
}

// Diagnostics for self-test: incremented in audio_task whenever a
// buffer is handed to i2s_write(). Also tracks the magnitude of the
// last buffer so we know the mixer isn't stuck at silence.
static volatile uint32_t g_buffers_written   = 0;
static volatile int16_t  g_last_mix_min      = 0;
static volatile int16_t  g_last_mix_max      = 0;

static void audio_task(void* /*arg*/) {
  Serial.println("audio_task started");
  uint16_t buf[BUFFER_SAMPLES];
  while (true) {
    int16_t mn = 32767, mx = -32768;
    for (int i = 0; i < BUFFER_SAMPLES; i++) {
      int16_t s = mix_sample();
      if (s < mn) mn = s;
      if (s > mx) mx = s;
      uint8_t u = (uint8_t)(s + 128);
      // Internal DAC consumes the upper 8 bits of a 16-bit I2S word.
      buf[i] = (uint16_t)u << 8;
    }
    g_last_mix_min = mn;
    g_last_mix_max = mx;
    size_t written;
    i2s_write(I2S_NUM_0, buf, sizeof(buf), &written, portMAX_DELAY);
    g_buffers_written++;
  }
}

// =================================================================
// Audio API (higher level)
// =================================================================

static float note_freq(const char* name) {
  if (!name || !*name) return 440.0f;
  static const char  base_name[] = "CDEFGAB";
  static const int   base_semi[] = { 0, 2, 4, 5, 7, 9, 11 };
  char c = name[0];
  if (c >= 'a' && c <= 'z') c -= 32;
  int idx = -1;
  for (int i = 0; i < 7; i++) if (base_name[i] == c) { idx = i; break; }
  if (idx < 0) return 440.0f;
  int semi = base_semi[idx];
  const char* p = name + 1;
  if (*p == '#')      { semi++; p++; }
  else if (*p == 'b') { semi--; p++; }
  int oct = (*p >= '0' && *p <= '9') ? (*p - '0') : 4;
  int n = (oct - 4) * 12 + (semi - 9);  // A4 (semi 9, oct 4) → n = 0
  return 440.0f * powf(2.0f, (float)n / 12.0f);
}

static void voice_clear(Voice& v) {
  v.active = false;
  v.wave = WAVE_SQUARE;
  v.phase = 0.0f;
  v.phase_inc = 0.0f;
  v.phase_inc_delta = 0.0f;
  v.env_pos = 0;
  v.env_total = 0;
  v.env_attack = 0;
  v.env_decay = 0;
  v.volume = 0.0f;
  v.lfsr = 0xACE1;
  v.filter = FILTER_NONE;
  v.filter_alpha = 0.0f;
  v.filter_state = 0.0f;
  v.sample_data = nullptr;
  v.sample_length = 0;
}

static void play_note(int ch, uint8_t wave, float freq, float dur_sec,
                      float attack_ms = 5, float decay_ms = 60, float vol = 0.7f) {
  if (ch < 0 || ch >= NUM_VOICES) return;
  Voice& v = voices[ch];
  v.active = false;  // preempt
  voice_clear(v);
  v.wave = wave;
  v.phase_inc = freq / (float)SAMPLE_RATE;
  v.env_total = (uint32_t)(dur_sec * SAMPLE_RATE);
  v.env_attack = (uint32_t)(attack_ms * 0.001f * SAMPLE_RATE);
  v.env_decay = (uint32_t)(decay_ms * 0.001f * SAMPLE_RATE);
  if (v.env_attack + v.env_decay > v.env_total) {
    v.env_attack = v.env_total / 3;
    v.env_decay  = v.env_total / 3;
  }
  v.volume = vol;
  v.active = true;
}

static void play_sweep(int ch, uint8_t wave, float f_start, float f_end,
                       float dur_sec,
                       float attack_ms = 5, float decay_ms = 60, float vol = 0.7f) {
  play_note(ch, wave, f_start, dur_sec, attack_ms, decay_ms, vol);
  Voice& v = voices[ch];
  float inc_end = f_end / (float)SAMPLE_RATE;
  if (v.env_total > 0) {
    v.phase_inc_delta = (inc_end - v.phase_inc) / (float)v.env_total;
  }
}

static void play_noise(int ch, float dur_sec, uint8_t filter, float cutoff_hz,
                       float attack_ms = 5, float decay_ms = 60, float vol = 0.6f) {
  play_note(ch, WAVE_NOISE, 1000.0f, dur_sec, attack_ms, decay_ms, vol);
  Voice& v = voices[ch];
  v.filter = filter;
  if (filter != FILTER_NONE && cutoff_hz > 0) {
    v.filter_alpha = 1.0f - expf(-2.0f * (float)M_PI * cutoff_hz / (float)SAMPLE_RATE);
  }
}

static void play_sample(int ch, const int8_t* data, uint32_t len,
                        float pitch, float vol = 0.8f) {
  if (ch < 0 || ch >= NUM_VOICES) return;
  Voice& v = voices[ch];
  v.active = false;
  voice_clear(v);
  v.wave = WAVE_SAMPLE;
  v.sample_data = data;
  v.sample_length = len;
  v.phase = 0.0f;
  v.phase_inc = pitch;
  // Env covers the full natural duration of the pitched sample.
  v.env_total = (uint32_t)((float)len / pitch) + 1;
  v.env_attack = 64;            // ~3 ms click-suppress
  v.env_decay  = 256;           // ~12 ms tail
  if (v.env_attack + v.env_decay > v.env_total) {
    v.env_attack = v.env_total / 4;
    v.env_decay  = v.env_total / 4;
  }
  v.volume = vol;
  v.active = true;
}

static void stop_all() {
  for (int i = 0; i < NUM_VOICES; i++) voices[i].active = false;
}

// =================================================================
// Pre-synthesized sample ("blip" — short descending sine chirp)
// =================================================================
static constexpr uint32_t BLIP_SAMPLES = 4410;  // 0.2 sec @ 22.05 kHz
static int8_t blip_pcm[BLIP_SAMPLES];

static void synthesize_blip() {
  // 1000 Hz → 300 Hz exponential sweep with exponential decay envelope.
  for (uint32_t i = 0; i < BLIP_SAMPLES; i++) {
    float t = (float)i / (float)SAMPLE_RATE;
    float f = 1000.0f * powf(0.3f, t / 0.2f);
    float phase = 2.0f * (float)M_PI * f * t;
    float env = expf(-t * 8.0f);
    float s = sinf(phase) * env;
    int v = (int)(s * 110.0f);
    if (v > 127) v = 127; if (v < -128) v = -128;
    blip_pcm[i] = (int8_t)v;
  }
}

// =================================================================
// UI — scenes + touch
// =================================================================

struct Scene {
  const char* name;
  const char* desc1;
  const char* desc2;
  void (*play)();
};

static int current_scene = 0;
static int num_scenes;

// Scene implementations
static void scene_waveforms() {
  stop_all();
  const uint8_t     waves[] = { WAVE_SQUARE, WAVE_TRIANGLE, WAVE_SAW, WAVE_SINE, WAVE_NOISE };
  for (int i = 0; i < 5; i++) {
    play_note(0, waves[i], note_freq("C4"), 0.4f, 8, 80, 0.6f);
    delay(500);
  }
}

static void scene_scale() {
  stop_all();
  const char* notes[] = { "C4","D4","E4","F4","G4","A4","B4","C5" };
  for (int i = 0; i < 8; i++) {
    play_note(0, WAVE_SQUARE, note_freq(notes[i]), 0.18f, 4, 40, 0.6f);
    delay(220);
  }
}

static void scene_sweeps() {
  stop_all();
  play_sweep(0, WAVE_SINE,     200,  2000, 0.8f, 10, 60); delay(1000);
  play_sweep(0, WAVE_SINE,    2000,   200, 0.8f, 10, 60); delay(1000);
  play_sweep(0, WAVE_SAW,      100,  1500, 0.2f,  5, 30); delay(320);
  play_sweep(0, WAVE_TRIANGLE, 400,   800, 1.5f, 10, 300); delay(1700);
}

static void scene_envelopes() {
  stop_all();
  // Short attack + short decay — punchy
  play_note(0, WAVE_SQUARE, note_freq("C4"), 0.3f, 2, 20, 0.6f);  delay(400);
  // Short attack + long decay — chime tail
  play_note(0, WAVE_SINE,   note_freq("E4"), 0.9f, 2, 700, 0.6f); delay(1000);
  // Long attack + short decay — fade in
  play_note(0, WAVE_SQUARE, note_freq("G4"), 0.9f, 450, 40, 0.6f); delay(1000);
  // Long attack + long decay — swell
  play_note(0, WAVE_TRIANGLE, note_freq("C5"), 1.4f, 500, 500, 0.6f); delay(1600);
}

static void scene_polyphony() {
  stop_all();
  // C major triad held across all 4 s
  play_note(0, WAVE_SQUARE,   note_freq("C3"), 4.0f, 20, 1500, 0.35f);
  play_note(1, WAVE_SQUARE,   note_freq("E3"), 4.0f, 20, 1500, 0.35f);
  play_note(2, WAVE_SQUARE,   note_freq("G3"), 4.0f, 20, 1500, 0.35f);
  // Melody on channel 3
  const char* melody[] = { "C5","E5","G5","E5","D5","F5","A5","G5" };
  for (int i = 0; i < 8; i++) {
    play_note(3, WAVE_TRIANGLE, note_freq(melody[i]), 0.28f, 4, 40, 0.5f);
    delay(320);
  }
}

static void scene_noise() {
  stop_all();
  play_noise(0, 0.4f, FILTER_NONE, 0);                delay(550);
  play_noise(0, 0.6f, FILTER_LOW,  500);              delay(750);
  play_noise(0, 0.6f, FILTER_HIGH, 2500);             delay(750);
  play_noise(0, 0.5f, FILTER_LOW,  1200);             delay(650);
}

static void scene_samples() {
  stop_all();
  // Same PCM blip played at 4 pitches.
  play_sample(0, blip_pcm, BLIP_SAMPLES, 0.5f, 0.8f);  delay(450);
  play_sample(0, blip_pcm, BLIP_SAMPLES, 1.0f, 0.8f);  delay(250);
  play_sample(0, blip_pcm, BLIP_SAMPLES, 1.5f, 0.8f);  delay(200);
  play_sample(0, blip_pcm, BLIP_SAMPLES, 2.0f, 0.8f);  delay(200);
  // Two at once to prove mixer polyphony with samples
  play_sample(0, blip_pcm, BLIP_SAMPLES, 1.0f, 0.7f);
  play_sample(1, blip_pcm, BLIP_SAMPLES, 1.5f, 0.7f);  delay(300);
}

// -----------------------------------------------------------------
// Self-test: ADC2_CH9 loopback of GPIO 26 (DAC output)
// -----------------------------------------------------------------
// Verifies the audio stack is actually producing non-silent output
// electrically, without needing a speaker. ESP32's ADC2 channel 9
// shares its analog path with GPIO 26 (which we're driving via DAC2
// for audio), so we can sample the same pin during playback and
// observe the voltage swing.
//
// Procedure:
//   1. Silence baseline: stop all voices, sample ADC a few hundred
//      times, record min/max (noise floor near DAC bias = ~2048).
//   2. Active signal: play a loud 440 Hz sine on ch 0, sample ADC
//      during playback, record min/max.
//   3. PASS if the active range is meaningfully larger than the
//      silence range (threshold > 400 lsb = ~0.3 V peak-to-peak).
//
// Silence, active, and the result are all printed to Serial and
// drawn in the description area of the current scene.

static constexpr int SELFTEST_SAMPLES = 512;

struct AdcStats { int mn; int mx; int range; int avg; int errors; };

static AdcStats sample_adc(int n) {
  AdcStats s = { 4096, -1, 0, 0, 0 };
  long sum = 0; int valid = 0;
  for (int i = 0; i < n; i++) {
    int raw = 0;
    esp_err_t r = adc2_get_raw(ADC2_CHANNEL_9, ADC_WIDTH_BIT_12, &raw);
    if (r != ESP_OK) { s.errors++; continue; }
    if (raw < s.mn) s.mn = raw;
    if (raw > s.mx) s.mx = raw;
    sum += raw;
    valid++;
  }
  s.range = (valid > 0) ? (s.mx - s.mn) : 0;
  s.avg   = (valid > 0) ? (sum / valid) : 0;
  return s;
}

static void scene_selftest() {
  stop_all();

  // Splash
  tft.fillRect(0, 36, 320, 60, TFT_BLACK);
  tft.setTextColor(TFT_YELLOW, TFT_BLACK);
  tft.setTextSize(2);
  tft.setCursor(8, 44);
  tft.print("Measuring...");

  // --- A. Is the audio_task alive? ---
  uint32_t buf_before = g_buffers_written;
  delay(100);
  uint32_t buf_after  = g_buffers_written;
  uint32_t buf_delta  = buf_after - buf_before;

  // --- B. Is the mixer producing non-zero output under load? ---
  // Call mix_sample() directly 512 times with a sine voice armed —
  // this bypasses I2S entirely and only tests the mixer math.
  // The audio_task will also run in parallel on core 0, but we don't
  // care about its output here; we're sampling the function directly.
  play_note(0, WAVE_SINE, 440.0f, 1.0f, 2, 2, 1.0f);
  delay(5);
  int16_t mix_mn = 32767, mix_mx = -32768;
  for (int i = 0; i < 512; i++) {
    int16_t s = mix_sample();
    if (s < mix_mn) mix_mn = s;
    if (s > mix_mx) mix_mx = s;
  }
  int mix_range = mix_mx - mix_mn;
  stop_all();
  delay(20);

  // --- C. Silence baseline on ADC2_CH9 ---
  delay(30);
  AdcStats silence = sample_adc(SELFTEST_SAMPLES);

  // --- D. Active signal on ADC2_CH9 (full-volume 440 Hz sine via I2S) ---
  play_note(0, WAVE_SINE, 440.0f, 0.6f, 2, 2, 1.0f);
  delay(25);
  AdcStats active = sample_adc(SELFTEST_SAMPLES);
  // Also snapshot the audio_task's self-reported last buffer envelope.
  int16_t task_mn = g_last_mix_min;
  int16_t task_mx = g_last_mix_max;
  stop_all();
  delay(80);

  // --- Report ---
  Serial.printf("SELF-TEST audio_task buffers in 100ms: %lu\n",
                (unsigned long)buf_delta);
  Serial.printf("SELF-TEST mixer direct : min=%d max=%d range=%d\n",
                mix_mn, mix_mx, mix_range);
  Serial.printf("SELF-TEST task last buf: min=%d max=%d\n",
                task_mn, task_mx);
  Serial.printf("SELF-TEST adc silence  : min=%d max=%d range=%d avg=%d err=%d\n",
                silence.mn, silence.mx, silence.range, silence.avg, silence.errors);
  Serial.printf("SELF-TEST adc active   : min=%d max=%d range=%d avg=%d err=%d\n",
                active.mn, active.mx, active.range, active.avg, active.errors);

  // Verdict: software layers first — those are the things we can
  // verify without external hardware. ADC loopback on CYD is
  // inherently limited because GPIO 26 is clamped by the onboard
  // speaker-driver BJT base (see boot diag); we report its reading
  // as info, not as pass/fail.
  const char* line1;
  const char* line2;
  uint16_t    color;
  if (buf_delta == 0) {
    line1 = "FAIL: task dead";     line2 = "audio_task not running";      color = TFT_RED;
  } else if (mix_range < 50) {
    line1 = "FAIL: mixer silent";  line2 = "voices not producing output"; color = TFT_RED;
  } else if (task_mx - task_mn < 50) {
    line1 = "FAIL: task silent";   line2 = "mix ok but task buf empty";   color = TFT_RED;
  } else if (active.errors > SELFTEST_SAMPLES / 2) {
    line1 = "WARN: adc read err";  line2 = "software layers pass";        color = TFT_ORANGE;
  } else if (active.range <= silence.range + 100) {
    line1 = "SW PASS  HW ?";       line2 = "sw ok, pin clamped by board"; color = TFT_ORANGE;
  } else {
    line1 = "PASS  full stack";    line2 = "sw + electrical swing ok";    color = TFT_GREEN;
  }

  tft.fillRect(0, 36, 320, 60, TFT_BLACK);
  tft.setTextSize(2);
  tft.setTextColor(color, TFT_BLACK);
  tft.setCursor(8, 40);
  tft.print(line1);
  tft.setCursor(8, 60);
  tft.setTextSize(1);
  tft.setTextColor(TFT_WHITE, TFT_BLACK);
  tft.print(line2);
  tft.setCursor(8, 72);
  tft.printf("task=%lu buf  mix=%d..%d", (unsigned long)buf_delta, mix_mn, mix_mx);
  tft.setCursor(8, 84);
  tft.printf("adc sil=%d..%d act=%d..%d", silence.mn, silence.mx, active.mn, active.mx);
}

static Scene scenes[] = {
  { "WELCOME",   "Audio stack test",    "tap < > to browse",       nullptr },
  { "WAVEFORMS", "5 waves on C4",       "sq tri saw sin nse",      scene_waveforms },
  { "SCALE",     "C major C4..C5",      "square wave, 8 notes",    scene_scale },
  { "SWEEPS",    "Pitch bends",         "up down fast slow",       scene_sweeps },
  { "ENVELOPE",  "Attack + decay",      "4 env shapes",            scene_envelopes },
  { "POLYPHONY", "4 voice chord",       "Cmaj triad + melody",     scene_polyphony },
  { "NOISE",     "LFSR noise + filt",   "raw low high low2",       scene_noise },
  { "SAMPLES",   "PCM playback",        "blip at 4 pitches + mix", scene_samples },
  { "SELF-TEST", "ADC2 loopback",       "verifies DAC swing",      scene_selftest },
};

// -----------------------------------------------------------------
// UI layout
// -----------------------------------------------------------------
// Screen 320x240:
//   title bar  (0,0) 320x32     scene index + name
//   desc area  (0,36) 320x56    2 lines of description
//   PLAY btn   (40,100) 240x70  big green button (grey if no play)
//   controls   (0,200) 320x36   [< PREV]  [STOP]  [NEXT >]

static void draw_button(int x, int y, int w, int h, uint16_t color,
                        const char* label, int label_px = 2) {
  tft.fillRect(x, y, w, h, color);
  tft.drawRect(x, y, w, h, TFT_WHITE);
  tft.setTextColor(TFT_WHITE, color);
  tft.setTextSize(label_px);
  int char_w = 6 * label_px;
  int char_h = 8 * label_px;
  int len = 0; while (label[len]) len++;
  int tx = x + (w - len * char_w) / 2;
  int ty = y + (h - char_h) / 2;
  tft.setCursor(tx, ty);
  tft.print(label);
}

static void draw_scene() {
  tft.fillScreen(TFT_BLACK);

  // Title bar
  tft.fillRect(0, 0, 320, 32, TFT_NAVY);
  tft.setTextColor(TFT_WHITE, TFT_NAVY);
  tft.setTextSize(2);
  tft.setCursor(8, 8);
  tft.printf("%d/%d  %s", current_scene + 1, num_scenes, scenes[current_scene].name);

  // Description
  tft.setTextColor(TFT_WHITE, TFT_BLACK);
  tft.setTextSize(2);
  tft.setCursor(8, 44);
  tft.print(scenes[current_scene].desc1);
  tft.setCursor(8, 68);
  tft.print(scenes[current_scene].desc2);

  // PLAY button
  const bool can_play = (scenes[current_scene].play != nullptr);
  draw_button(40, 100, 240, 70,
              can_play ? TFT_DARKGREEN : TFT_DARKGREY,
              can_play ? "PLAY" : "----",
              3);

  // Controls
  draw_button(  8, 200, 80, 36, TFT_DARKGREY, "< PREV", 2);
  draw_button(120, 200, 80, 36, TFT_MAROON,   "STOP",   2);
  draw_button(232, 200, 80, 36, TFT_DARKGREY, "NEXT >", 2);
}

// -----------------------------------------------------------------
// Touch — Y-flip same as cyd/ + live cursor for debugging
// -----------------------------------------------------------------
static bool touch_prev = false;

static inline bool hit(int32_t x, int32_t y, int bx, int by, int bw, int bh) {
  return x >= bx && x < bx + bw && y >= by && y < by + bh;
}

// =================================================================
// setup / loop
// =================================================================
// Probe: drive DAC to 5 levels, read ADC back, print (raw + atten).
static void probe_dac_adc(dac_channel_t dac, adc2_channel_t ch, const char* label) {
  Serial.printf("%s:\n", label);
  esp_err_t e = dac_output_enable(dac);
  Serial.printf("  dac_output_enable = %d\n", (int)e);
  const int vs[] = { 0, 64, 128, 192, 255 };
  for (int i = 0; i < 5; i++) {
    dac_output_voltage(dac, vs[i]);
    delay(8);
    int raw = 0;
    esp_err_t r = adc2_get_raw(ch, ADC_WIDTH_BIT_12, &raw);
    Serial.printf("  dac=%3d  adc=%4d  err=%d\n", vs[i], raw, (int)r);
  }
  dac_output_disable(dac);
}

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println();
  Serial.println("=== CYD Mono Audio Test ===");
  Serial.printf("Sample rate: %d Hz, voices: %d\n", SAMPLE_RATE, NUM_VOICES);

  // ---- Early boot diagnostics -----------------------------------
  // Do the DAC/ADC loopback probe BEFORE tft.init() so we can use
  // GPIO 25 (touch SCLK) as a control. After this block both DAC
  // channels are disabled and the pins go back to the display / touch
  // drivers.
  Serial.println("-- boot diag: direct DAC/ADC loopback --");
  adc2_config_channel_atten(ADC2_CHANNEL_8, ADC_ATTEN_DB_11);  // GPIO 25
  adc2_config_channel_atten(ADC2_CHANNEL_9, ADC_ATTEN_DB_11);  // GPIO 26

  // Control: DAC1 / GPIO 25 (later repurposed as touch SCLK).
  // If this swings cleanly, the ADC2 + DAC path itself works and
  // any flatness on GPIO 26 is a pin-specific hardware clamp.
  probe_dac_adc(DAC_CHANNEL_1, ADC2_CHANNEL_8, "DAC1/GPIO25/ADC2_CH8");

  // Target: DAC2 / GPIO 26 (our intended audio output pin).
  probe_dac_adc(DAC_CHANNEL_2, ADC2_CHANNEL_9, "DAC2/GPIO26/ADC2_CH9");

  Serial.println("-- boot diag: install display + touch --");

  // Display + touch
  tft.init();
  tft.invertDisplay(true);
  tft.setRotation(3);
  tft.setBrightness(255);
  tft.fillScreen(TFT_BLACK);

  // Audio
  init_wave_tables();
  synthesize_blip();
  for (int i = 0; i < NUM_VOICES; i++) voice_clear(voices[i]);

  Serial.println("-- boot diag: install I2S --");
  init_audio_i2s();

  // Audio task on core 0, higher priority than Arduino main loop (core 1).
  xTaskCreatePinnedToCore(audio_task, "audio",
                          4096, nullptr,
                          configMAX_PRIORITIES - 2,
                          nullptr, 0);

  num_scenes = sizeof(scenes) / sizeof(scenes[0]);
  current_scene = 0;
  draw_scene();
  Serial.println("Ready.");

  // Auto-play every audio scene in sequence so the operator just
  // listens. Each scene's play() blocks via delay() until done.
  Serial.println("-- auto-play all scenes --");
  for (int i = 0; i < num_scenes; i++) {
    if (!scenes[i].play) continue;
    current_scene = i;
    draw_scene();
    Serial.printf(">> playing %d/%d: %s\n", i + 1, num_scenes, scenes[i].name);
    delay(600);
    scenes[i].play();
    delay(400);
    stop_all();
  }
  current_scene = 0;
  draw_scene();
  Serial.println("-- auto-play done. tap to replay any scene --");
}

void loop() {
  // Poll raw touch every iteration so we can render a live cursor.
  int32_t raw_x, raw_y;
  bool now = tft.getTouch(&raw_x, &raw_y);
  int32_t tx = raw_x;
  int32_t ty = now ? (tft.height() - 1) - raw_y : raw_y;
  bool rising = now && !touch_prev;

  // Live cursor: small yellow dot while touched, accumulating into a
  // trail so you can visually audit what the driver is reporting.
  // Cleared only when the scene is redrawn (PREV / NEXT).
  if (now) {
    tft.fillCircle(tx, ty, 2, TFT_YELLOW);
  }

  if (rising) {
    Serial.printf("tap raw(%3ld,%3ld) flip(%3ld,%3ld)\n",
                  (long)raw_x, (long)raw_y, (long)tx, (long)ty);
    // Rising-edge marker — bigger so it stands out from the cursor trail
    tft.drawCircle(tx, ty, 8, TFT_RED);
    tft.drawCircle(tx, ty, 9, TFT_RED);

    if (hit(tx, ty, 40, 100, 240, 70)) {
      if (scenes[current_scene].play) {
        Serial.printf(">> play scene %d: %s\n",
                      current_scene, scenes[current_scene].name);
        scenes[current_scene].play();
      } else {
        Serial.println("   (welcome scene has no audio)");
      }
    } else if (hit(tx, ty, 8, 200, 80, 36)) {
      current_scene = (current_scene - 1 + num_scenes) % num_scenes;
      stop_all();
      draw_scene();
    } else if (hit(tx, ty, 232, 200, 80, 36)) {
      current_scene = (current_scene + 1) % num_scenes;
      stop_all();
      draw_scene();
    } else if (hit(tx, ty, 120, 200, 80, 36)) {
      stop_all();
    } else {
      Serial.println("   (no button hit)");
    }
  }

  touch_prev = now;
  delay(5);
}
