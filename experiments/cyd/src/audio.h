#pragma once
// 4-voice 22050 Hz 8-bit mono software mixer + I2S DAC output (GPIO 26).
// Ported from experiments/cyd-audio with the LEFT_EN fix.

#include <stdint.h>

enum WaveType : uint8_t {
  WAVE_SQUARE = 0, WAVE_TRIANGLE, WAVE_SAW, WAVE_SINE, WAVE_NOISE,
};
enum FilterType : uint8_t { FILTER_NONE = 0, FILTER_LOW, FILTER_HIGH };

static constexpr int AUDIO_SAMPLE_RATE = 22050;
static constexpr int NUM_VOICES        = 4;

// Channel default waveform (set via wave(ch, type)).
extern uint8_t channel_wave[NUM_VOICES];

void audio_init();                       // call once from setup()
float note_freq(const char* name);       // "C4" → Hz

void play_note (int ch, uint8_t wave, float freq, float dur_sec,
                float attack_ms, float decay_ms, float vol);
void play_sweep(int ch, uint8_t wave, float f_start, float f_end,
                float dur_sec, float attack_ms, float decay_ms, float vol);
void play_noise(int ch, float dur_sec, uint8_t filter, float cutoff_hz,
                float attack_ms, float decay_ms, float vol);
void stop_voice(int ch);
void stop_all();
