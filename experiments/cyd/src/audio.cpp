// 4-voice software audio mixer for CYD (ESP32 internal DAC2, GPIO 26).
// Runs as a dedicated FreeRTOS task on core 0.

#include "audio.h"
#include <Arduino.h>
#include <math.h>
extern "C" {
  #include "driver/i2s.h"
}

static constexpr int BUFFER_SAMPLES = 256;

uint8_t channel_wave[NUM_VOICES] = {
  WAVE_SQUARE, WAVE_SQUARE, WAVE_SQUARE, WAVE_SQUARE
};

// ---- Waveform tables (256 entries each, int8_t) -----------------
static int8_t wave_table[4][256];

static void init_wave_tables() {
  for (int i = 0; i < 256; i++) {
    wave_table[WAVE_SQUARE][i]   = (i < 128) ? -128 : 127;
    wave_table[WAVE_TRIANGLE][i] = (i < 128)
        ? (int8_t)(i * 2 - 128)
        : (int8_t)(255 - (i - 128) * 2 - 128);
    wave_table[WAVE_SAW][i]      = (int8_t)(i - 128);
    wave_table[WAVE_SINE][i]     = (int8_t)(sinf((float)i / 256.0f * 2.0f * (float)M_PI) * 126.0f);
  }
}

// ---- Voice state ------------------------------------------------
struct Voice {
  volatile bool active;
  uint8_t  wave;
  float    phase, phase_inc, phase_inc_delta;
  uint32_t env_pos, env_total, env_attack, env_decay;
  float    volume;
  uint16_t lfsr;
  uint8_t  filter;
  float    filter_alpha, filter_state;
};

static Voice voices[NUM_VOICES];

static void voice_clear(Voice& v) {
  v.active = false;
  v.wave = WAVE_SQUARE; v.phase = 0; v.phase_inc = 0;
  v.phase_inc_delta = 0;
  v.env_pos = v.env_total = v.env_attack = v.env_decay = 0;
  v.volume = 0; v.lfsr = 0xACE1;
  v.filter = FILTER_NONE; v.filter_alpha = 0; v.filter_state = 0;
}

// ---- Per-sample mixer -------------------------------------------
static inline int16_t voice_sample(Voice& v) {
  if (!v.active) return 0;
  if (v.env_pos >= v.env_total) { v.active = false; return 0; }

  int16_t s;
  if (v.wave == WAVE_NOISE) {
    uint16_t lfsr = v.lfsr;
    uint16_t bit = ((lfsr >> 0) ^ (lfsr >> 2) ^ (lfsr >> 3) ^ (lfsr >> 5)) & 1;
    v.lfsr = (lfsr >> 1) | (bit << 15);
    s = (int8_t)((v.lfsr & 0xFF) - 128);
  } else {
    s = wave_table[v.wave][((int)(v.phase * 256.0f)) & 0xFF];
    v.phase += v.phase_inc;
    if (v.phase >= 1.0f) v.phase -= 1.0f;
  }

  if (v.phase_inc_delta != 0.0f) {
    v.phase_inc += v.phase_inc_delta;
    if (v.phase_inc < 0) v.phase_inc = 0;
  }

  if (v.filter != FILTER_NONE) {
    float fs = (float)s;
    v.filter_state += v.filter_alpha * (fs - v.filter_state);
    s = (int16_t)(v.filter == FILTER_LOW ? v.filter_state : fs - v.filter_state);
  }

  float env;
  if (v.env_pos < v.env_attack) {
    env = (float)v.env_pos / (float)v.env_attack;
  } else if (v.env_pos >= v.env_total - v.env_decay) {
    env = (float)(v.env_total - v.env_pos) / (float)v.env_decay;
  } else {
    env = 1.0f;
  }
  v.env_pos++;

  return (int16_t)(s * env * v.volume);
}

static int16_t mix_sample() {
  int32_t sum = 0;
  for (int i = 0; i < NUM_VOICES; i++) sum += voice_sample(voices[i]);
  sum /= NUM_VOICES;
  if (sum > 127) sum = 127;
  if (sum < -128) sum = -128;
  return (int16_t)sum;
}

// ---- I2S task ---------------------------------------------------
static void audio_task(void*) {
  uint16_t buf[BUFFER_SAMPLES];
  while (true) {
    for (int i = 0; i < BUFFER_SAMPLES; i++) {
      int16_t s = mix_sample();
      buf[i] = (uint16_t)((uint8_t)(s + 128)) << 8;
    }
    size_t written;
    i2s_write(I2S_NUM_0, buf, sizeof(buf), &written, portMAX_DELAY);
  }
}

// ---- Public API -------------------------------------------------
void audio_init() {
  init_wave_tables();
  for (int i = 0; i < NUM_VOICES; i++) voice_clear(voices[i]);

  i2s_config_t cfg = {};
  cfg.mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_TX | I2S_MODE_DAC_BUILT_IN);
  cfg.sample_rate = AUDIO_SAMPLE_RATE;
  cfg.bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT;
  cfg.channel_format = I2S_CHANNEL_FMT_ONLY_LEFT;
  cfg.communication_format = I2S_COMM_FORMAT_STAND_MSB;
  cfg.dma_buf_count = 4;
  cfg.dma_buf_len = BUFFER_SAMPLES;
  cfg.use_apll = false;
  cfg.tx_desc_auto_clear = true;
  i2s_driver_install(I2S_NUM_0, &cfg, 0, NULL);
  i2s_set_dac_mode(I2S_DAC_CHANNEL_LEFT_EN);   // DAC2 = GPIO 26
  i2s_zero_dma_buffer(I2S_NUM_0);

  xTaskCreatePinnedToCore(audio_task, "audio", 4096, nullptr,
                          configMAX_PRIORITIES - 2, nullptr, 0);
}

float note_freq(const char* name) {
  if (!name || !*name) return 440.0f;
  static const char base_name[] = "CDEFGAB";
  static const int  base_semi[] = { 0, 2, 4, 5, 7, 9, 11 };
  char c = name[0]; if (c >= 'a' && c <= 'z') c -= 32;
  int idx = -1;
  for (int i = 0; i < 7; i++) if (base_name[i] == c) { idx = i; break; }
  if (idx < 0) return 440.0f;
  int semi = base_semi[idx];
  const char* p = name + 1;
  if (*p == '#') { semi++; p++; } else if (*p == 'b') { semi--; p++; }
  int oct = (*p >= '0' && *p <= '9') ? (*p - '0') : 4;
  return 440.0f * powf(2.0f, ((oct - 4) * 12 + semi - 9) / 12.0f);
}

void play_note(int ch, uint8_t wave, float freq, float dur_sec,
               float attack_ms, float decay_ms, float vol) {
  if (ch < 0 || ch >= NUM_VOICES) return;
  Voice& v = voices[ch];
  v.active = false;
  voice_clear(v);
  v.wave = wave;
  v.phase_inc = freq / (float)AUDIO_SAMPLE_RATE;
  v.env_total   = (uint32_t)(dur_sec * AUDIO_SAMPLE_RATE);
  v.env_attack  = (uint32_t)(attack_ms * 0.001f * AUDIO_SAMPLE_RATE);
  v.env_decay   = (uint32_t)(decay_ms * 0.001f * AUDIO_SAMPLE_RATE);
  if (v.env_attack + v.env_decay > v.env_total) {
    v.env_attack = v.env_total / 3;
    v.env_decay  = v.env_total / 3;
  }
  v.volume = vol;
  v.active = true;
}

void play_sweep(int ch, uint8_t wave, float f_start, float f_end,
                float dur_sec, float attack_ms, float decay_ms, float vol) {
  play_note(ch, wave, f_start, dur_sec, attack_ms, decay_ms, vol);
  Voice& v = voices[ch];
  float inc_end = f_end / (float)AUDIO_SAMPLE_RATE;
  if (v.env_total > 0)
    v.phase_inc_delta = (inc_end - v.phase_inc) / (float)v.env_total;
}

void play_noise(int ch, float dur_sec, uint8_t filter, float cutoff_hz,
                float attack_ms, float decay_ms, float vol) {
  play_note(ch, WAVE_NOISE, 1000, dur_sec, attack_ms, decay_ms, vol);
  Voice& v = voices[ch];
  v.filter = filter;
  if (filter != FILTER_NONE && cutoff_hz > 0)
    v.filter_alpha = 1.0f - expf(-2.0f * (float)M_PI * cutoff_hz / (float)AUDIO_SAMPLE_RATE);
}

void stop_voice(int ch) {
  if (ch >= 0 && ch < NUM_VOICES) voices[ch].active = false;
}

void stop_all() {
  for (int i = 0; i < NUM_VOICES; i++) voices[i].active = false;
}
