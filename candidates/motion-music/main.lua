-- MOTION MUSIC
-- Play music by moving your phone
-- Tilt=pitch, Forward/Back=intensity, Shake=drums, Rotate=waveform
-- 160x120, 1-bit, Motion + Audio

----------------------------------------------------------------
-- CONSTANTS
----------------------------------------------------------------
local W = 160
local H = 120

-- Note table: chromatic C3 to C5 (25 notes)
local NOTES = {
  "C3","C#3","D3","D#3","E3","F3","F#3","G3","G#3","A3","A#3","B3",
  "C4","C#4","D4","D#4","E4","F4","F#4","G4","G#4","A4","A#4","B4",
  "C5"
}
local NOTE_NAMES_SHORT = {
  "C","C#","D","D#","E","F","F#","G","G#","A","A#","B",
  "C","C#","D","D#","E","F","F#","G","G#","A","A#","B",
  "C"
}
local NOTE_OCTAVES = {
  3,3,3,3,3,3,3,3,3,3,3,3,
  4,4,4,4,4,4,4,4,4,4,4,4,
  5
}

-- Waveform types
local WAVES = {"square", "sine", "triangle", "sawtooth"}
local WAVE_LABELS = {"SQR", "SIN", "TRI", "SAW"}

-- Frequencies for waveform visualization
local NOTE_FREQS = {
  130.81,138.59,146.83,155.56,164.81,174.61,185.00,196.00,207.65,220.00,233.08,246.94,
  261.63,277.18,293.66,311.13,329.63,349.23,369.99,392.00,415.30,440.00,466.16,493.88,
  523.25
}

-- Recording constants
local MAX_REC_FRAMES = 300  -- ~10 seconds at 30fps
local MAX_TRACKS = 4

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local scene = "title"
local scr

-- Instrument state
local cur_note_idx = 13       -- default to C4
local cur_wave_idx = 1        -- square
local cur_intensity = 0.5     -- 0..1
local playing_note = false
local last_note_frame = 0
local note_cooldown = 4       -- frames between notes

-- Shake detection
local shake_threshold = 2.5
local last_shake_frame = -30
local shake_magnitude = 0

-- Smoothed motion values
local smooth_x = 0
local smooth_y = 0

-- Demo mode
local demo_active = false
local demo_timer = 0
local demo_melody_idx = 1
local idle_timer = 0
local IDLE_TIMEOUT = 180  -- 6 seconds to enter demo

-- Demo melody: {note_idx, wave_idx, duration_frames}
local demo_melody = {
  {13,2,8},{15,2,8},{17,2,8},{18,2,12},{17,2,8},{15,2,8},{13,2,16},
  {13,1,6},{13,1,6},{15,1,6},{17,1,8},{20,1,12},{17,1,8},{13,1,16},
  {8,3,10},{10,3,10},{12,3,10},{13,3,16},{12,3,8},{10,3,8},{8,3,16},
  {1,4,6},{5,4,6},{8,4,6},{13,4,12},{8,4,6},{5,4,8},{1,4,16},
}

-- Recording / looping
local tracks = {}        -- up to 4 recorded tracks
local rec_active = false
local rec_buffer = {}    -- {frame, note_idx, wave_idx, dur}
local rec_frame = 0
local rec_length = 0
local loop_frame = 0
local loop_playing = false

-- Particles
local particles = {}
local MAX_PARTICLES = 40

-- Waveform display buffer
local wave_buf = {}
for i = 1, W do wave_buf[i] = 0 end
local wave_phase = 0

-- Keyboard fallback state
local kb_note_offset = 0  -- arrow left/right adjusts
local kb_wave_idx = 1
local kb_playing = false

-- Visual state
local beat_pulse = 0
local title_pulse = 0

----------------------------------------------------------------
-- UTILITIES
----------------------------------------------------------------
local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function safe_note(ch, n, dur)
  if note then note(ch, n, dur) end
end

local function safe_wave(ch, w)
  if wave then wave(ch, w) end
end

local function safe_noise(ch, dur)
  if noise then noise(ch, dur) end
end

local function safe_tone(ch, hz1, hz2, dur)
  if tone then tone(ch, hz1, hz2, dur) end
end

local function has_motion()
  if motion_enabled then return motion_enabled() end
  return false
end

local function get_motion_x()
  if motion_x then return motion_x() end
  return 0
end

local function get_motion_y()
  if motion_y then return motion_y() end
  return 0
end

local function get_motion_z()
  if motion_z then return motion_z() end
  return 0
end

local function get_gyro_alpha()
  if gyro_alpha then return gyro_alpha() end
  return 0
end

----------------------------------------------------------------
-- PARTICLES
----------------------------------------------------------------
local function spawn_particles(x, y, count, speed_mult)
  speed_mult = speed_mult or 1
  for i = 1, count do
    if #particles >= MAX_PARTICLES then return end
    local angle = math.random() * 6.2832
    local spd = (0.5 + math.random() * 2) * speed_mult
    particles[#particles + 1] = {
      x = x, y = y,
      vx = math.cos(angle) * spd,
      vy = math.sin(angle) * spd,
      life = 10 + math.random(0, 15),
      max_life = 10 + math.random(0, 15)
    }
  end
end

local function update_particles()
  local i = 1
  while i <= #particles do
    local p = particles[i]
    p.x = p.x + p.vx
    p.y = p.y + p.vy
    p.vx = p.vx * 0.95
    p.vy = p.vy * 0.95
    p.life = p.life - 1
    if p.life <= 0 then
      particles[i] = particles[#particles]
      particles[#particles] = nil
    else
      i = i + 1
    end
  end
end

local function draw_particles()
  for i = 1, #particles do
    local p = particles[i]
    local px = math.floor(p.x)
    local py = math.floor(p.y)
    if px >= 0 and px < W and py >= 0 and py < H then
      pix(scr, px, py, 1)
    end
  end
end

----------------------------------------------------------------
-- WAVEFORM VISUALIZATION
----------------------------------------------------------------
local function update_waveform()
  if not playing_note and not demo_active then
    -- Decay waveform to flat
    for i = 1, W do
      wave_buf[i] = wave_buf[i] * 0.85
    end
    wave_phase = wave_phase + 0.05
  else
    local freq = NOTE_FREQS[cur_note_idx] or 261.63
    -- Scale frequency to pixel period
    local period = W / (freq / 40)
    local amp = 15 * cur_intensity
    wave_phase = wave_phase + 0.15

    for i = 1, W do
      local t = ((i - 1) / period + wave_phase) % 1.0
      local val = 0

      if cur_wave_idx == 1 then
        -- Square
        val = t < 0.5 and amp or -amp
      elseif cur_wave_idx == 2 then
        -- Sine
        val = math.sin(t * 6.2832) * amp
      elseif cur_wave_idx == 3 then
        -- Triangle
        val = (2 * math.abs(2 * t - 1) - 1) * amp
      elseif cur_wave_idx == 4 then
        -- Sawtooth
        val = (2 * t - 1) * amp
      end

      wave_buf[i] = lerp(wave_buf[i], val, 0.3)
    end
  end
end

local function draw_waveform()
  local cy = 60  -- center y for waveform
  local prev_y = cy + math.floor(wave_buf[1])

  for i = 2, W do
    local y = cy + math.floor(wave_buf[i])
    y = clamp(y, 30, 90)
    local py = clamp(prev_y, 30, 90)
    line(scr, i - 2, py, i - 1, y, 1)
    prev_y = y
  end
end

----------------------------------------------------------------
-- SHAKE DETECTION
----------------------------------------------------------------
local function detect_shake()
  local ax = get_motion_x()
  local ay = get_motion_y()
  local az = get_motion_z()
  shake_magnitude = math.sqrt(ax * ax + ay * ay + az * az)

  local f = frame()
  if shake_magnitude > shake_threshold and (f - last_shake_frame) > 8 then
    last_shake_frame = f
    return true
  end
  return false
end

----------------------------------------------------------------
-- INSTRUMENT LOGIC
----------------------------------------------------------------
local function play_instrument_note()
  local f = frame()
  if (f - last_note_frame) < note_cooldown then return end

  safe_wave(0, WAVES[cur_wave_idx])
  local dur = 0.05 + cur_intensity * 0.15
  safe_note(0, NOTES[cur_note_idx], dur)
  last_note_frame = f
  playing_note = true
  beat_pulse = 8

  -- Spawn particles at note position
  local nx = math.floor((cur_note_idx - 1) / 24 * (W - 20)) + 10
  spawn_particles(nx, 60, 3 + math.floor(cur_intensity * 5), cur_intensity)

  -- Record if recording
  if rec_active and rec_frame < MAX_REC_FRAMES then
    rec_buffer[#rec_buffer + 1] = {
      frame = rec_frame,
      note_idx = cur_note_idx,
      wave_idx = cur_wave_idx,
      dur = dur
    }
  end
end

local function play_drum_hit()
  safe_noise(1, 0.06 + cur_intensity * 0.08)
  beat_pulse = 12
  spawn_particles(W / 2, 60, 8, 1.5)

  -- Also record drum hits
  if rec_active and rec_frame < MAX_REC_FRAMES then
    rec_buffer[#rec_buffer + 1] = {
      frame = rec_frame,
      note_idx = 0,  -- 0 = drum
      wave_idx = 0,
      dur = 0.06 + cur_intensity * 0.08
    }
  end
end

----------------------------------------------------------------
-- MOTION INPUT PROCESSING
----------------------------------------------------------------
local function process_motion_input()
  if has_motion() then
    -- Tilt left/right -> pitch (motion_x: -1 left to +1 right roughly)
    local mx = get_motion_x()
    smooth_x = lerp(smooth_x, mx, 0.3)
    -- Map -1..+1 to note indices 1..25
    local mapped = clamp((smooth_x + 1) / 2, 0, 1)
    cur_note_idx = math.floor(mapped * 24) + 1
    cur_note_idx = clamp(cur_note_idx, 1, 25)

    -- Tilt forward/back -> intensity
    local my = get_motion_y()
    smooth_y = lerp(smooth_y, my, 0.3)
    cur_intensity = clamp((smooth_y + 1) / 2, 0.1, 1.0)

    -- Gyro alpha -> waveform selection (0..360 mapped to 4 zones)
    local alpha = get_gyro_alpha()
    local norm = (alpha % 360) / 360
    cur_wave_idx = math.floor(norm * 4) + 1
    cur_wave_idx = clamp(cur_wave_idx, 1, 4)

    -- Shake -> drum
    if detect_shake() then
      play_drum_hit()
    end

    -- Play continuous note when tilted enough
    local tilt_mag = math.abs(smooth_x) + math.abs(smooth_y)
    if tilt_mag > 0.15 then
      play_instrument_note()
      idle_timer = 0
    else
      playing_note = false
      idle_timer = idle_timer + 1
    end
  else
    -- Keyboard fallback
    process_keyboard_input()
  end
end

local function process_keyboard_input()
  local moved = false

  if btn and btn("left") then
    kb_note_offset = kb_note_offset - 0.4
    moved = true
  end
  if btn and btn("right") then
    kb_note_offset = kb_note_offset + 0.4
    moved = true
  end

  kb_note_offset = clamp(kb_note_offset, -12, 12)
  cur_note_idx = clamp(13 + math.floor(kb_note_offset), 1, 25)

  if btn and btn("up") then
    cur_intensity = clamp(cur_intensity + 0.03, 0.1, 1.0)
    moved = true
  end
  if btn and btn("down") then
    cur_intensity = clamp(cur_intensity - 0.03, 0.1, 1.0)
    moved = true
  end

  -- A button = play note
  if btn and btn("a") then
    play_instrument_note()
    kb_playing = true
    idle_timer = 0
    moved = true
  else
    kb_playing = false
    playing_note = false
  end

  -- B button = drum hit
  if btnp and btnp("b") then
    play_drum_hit()
    idle_timer = 0
    moved = true
  end

  -- Select = cycle waveform
  if btnp and btnp("select") then
    cur_wave_idx = (cur_wave_idx % 4) + 1
    idle_timer = 0
    moved = true
  end

  if not moved then
    idle_timer = idle_timer + 1
    kb_note_offset = kb_note_offset * 0.98  -- slowly drift back
  end
end

----------------------------------------------------------------
-- RECORDING / LOOPING
----------------------------------------------------------------
local function start_recording()
  rec_active = true
  rec_buffer = {}
  rec_frame = 0
end

local function stop_recording()
  rec_active = false
  rec_length = rec_frame
  if #rec_buffer > 0 and #tracks < MAX_TRACKS then
    tracks[#tracks + 1] = {
      events = rec_buffer,
      length = rec_length
    }
  end
  rec_buffer = {}
end

local function update_loops()
  if not loop_playing or #tracks == 0 then return end

  for t = 1, #tracks do
    local track = tracks[t]
    local lf = loop_frame % track.length

    for e = 1, #track.events do
      local ev = track.events[e]
      if ev.frame == lf then
        if ev.note_idx == 0 then
          -- Drum
          safe_noise(1, ev.dur)
        else
          -- Use channel 1 for loop playback
          safe_wave(1, WAVES[ev.wave_idx] or "sine")
          safe_note(1, NOTES[ev.note_idx], ev.dur)
        end
      end
    end
  end

  loop_frame = loop_frame + 1
end

----------------------------------------------------------------
-- DEMO MODE
----------------------------------------------------------------
local function start_demo()
  demo_active = true
  demo_timer = 0
  demo_melody_idx = 1
end

local function stop_demo()
  demo_active = false
  demo_timer = 0
  idle_timer = 0
end

local function update_demo()
  if not demo_active then return end

  demo_timer = demo_timer + 1

  local entry = demo_melody[demo_melody_idx]
  if not entry then
    demo_melody_idx = 1
    entry = demo_melody[1]
  end

  local note_idx = entry[1]
  local wave_idx = entry[2]
  local dur_frames = entry[3]

  -- Simulate smooth motion
  cur_note_idx = note_idx
  cur_wave_idx = wave_idx
  cur_intensity = 0.5 + 0.3 * math.sin(demo_timer * 0.08)

  -- Play note at start of each entry
  if demo_timer == 1 or (demo_timer % dur_frames == 1) then
    safe_wave(0, WAVES[wave_idx])
    local dur = 0.05 + cur_intensity * 0.15
    safe_note(0, NOTES[note_idx], dur)
    playing_note = true
    beat_pulse = 8

    local nx = math.floor((note_idx - 1) / 24 * (W - 20)) + 10
    spawn_particles(nx, 60, 4, 0.8)
  end

  -- Advance melody
  if demo_timer % dur_frames == 0 then
    demo_melody_idx = demo_melody_idx + 1
    if demo_melody_idx > #demo_melody then
      demo_melody_idx = 1
    end
  end

  -- Occasional drum hits
  if demo_timer % 15 == 0 then
    safe_noise(1, 0.05)
    spawn_particles(W / 2, 80, 3, 1.0)
  end

  -- Exit demo on any input
  if btnp then
    if btnp("start") or btnp("a") or btnp("b") then
      stop_demo()
      scene = "play"
      return
    end
  end
  if touch_start and touch_start() then
    stop_demo()
    scene = "play"
    return
  end
end

----------------------------------------------------------------
-- DRAW: HUD ELEMENTS
----------------------------------------------------------------
local function draw_note_indicator()
  -- Current note name, large display
  local name = NOTE_NAMES_SHORT[cur_note_idx] or "?"
  local oct = NOTE_OCTAVES[cur_note_idx] or 4
  local label = name .. oct

  text(scr, label, 68, 3, 1)

  -- Waveform type label
  text(scr, WAVE_LABELS[cur_wave_idx] or "?", 130, 3, 1)

  -- Intensity bar
  local bar_w = math.floor(cur_intensity * 30)
  rect(scr, 3, 3, 32, 5, 1)
  if bar_w > 1 then
    rect(scr, 4, 4, bar_w, 3, 0)
    -- Invert: draw filled portion
    for bx = 4, 3 + bar_w do
      pix(scr, bx, 5, 1)
    end
  end
  text(scr, "VOL", 3, 10, 1)
end

local function draw_keyboard_strip()
  -- Draw a piano-style strip at the bottom showing current position
  local strip_y = H - 12
  local key_w = math.floor(W / 25)

  -- Draw all keys
  for i = 1, 25 do
    local kx = (i - 1) * key_w
    local is_sharp = false
    local name = NOTE_NAMES_SHORT[i]
    if #name > 1 then is_sharp = true end

    if i == cur_note_idx then
      -- Current note: filled
      rect(scr, kx, strip_y, key_w - 1, 10, 1)
    else
      -- Other notes: outline only for naturals
      if not is_sharp then
        line(scr, kx, strip_y, kx, strip_y + 9, 1)
      else
        -- Sharp keys: small mark
        pix(scr, kx + 1, strip_y + 2, 1)
        pix(scr, kx + 1, strip_y + 3, 1)
      end
    end
  end

  -- Bottom border
  line(scr, 0, strip_y + 10, W - 1, strip_y + 10, 1)
end

local function draw_track_indicators()
  -- Show recording state and track count
  local ty = H - 22

  if rec_active then
    -- Blinking REC indicator
    if math.floor(frame() / 10) % 2 == 0 then
      text(scr, "REC", 2, ty, 1)
    end
    -- Progress bar
    local prog = rec_frame / MAX_REC_FRAMES
    rect(scr, 22, ty, 40, 5, 1)
    if prog > 0.01 then
      for px = 23, 22 + math.floor(prog * 38) do
        pix(scr, px, ty + 2, 1)
      end
    end
  else
    -- Track count
    for t = 1, MAX_TRACKS do
      local tx = 2 + (t - 1) * 10
      if t <= #tracks then
        rect(scr, tx, ty, 8, 5, 1)
        text(scr, tostring(t), tx + 2, ty, 0)
      else
        rect(scr, tx, ty + 1, 6, 3, 1)
      end
    end

    if loop_playing and #tracks > 0 then
      -- Loop indicator
      if math.floor(frame() / 15) % 2 == 0 then
        text(scr, "LOOP", 45, ty, 1)
      end
    end
  end
end

----------------------------------------------------------------
-- SCENE: TITLE
----------------------------------------------------------------
local function title_update()
  title_pulse = title_pulse + 1
  idle_timer = idle_timer + 1

  if idle_timer > IDLE_TIMEOUT and not demo_active then
    start_demo()
  end

  if demo_active then
    update_demo()
    return
  end

  if btnp and (btnp("start") or btnp("a")) then
    scene = "play"
    idle_timer = 0
  end
  if touch_start and touch_start() then
    scene = "play"
    idle_timer = 0
  end
end

local function title_draw()
  cls(scr, 0)

  -- Title text with pulse
  local ty = 20 + math.floor(math.sin(title_pulse * 0.06) * 3)
  text(scr, "MOTION", 48, ty, 1)
  text(scr, "MUSIC", 54, ty + 12, 1)

  -- Decorative waveform
  local wy = 55
  for x = 0, W - 1 do
    local v = math.sin((x + title_pulse) * 0.1) * 8
    v = v + math.sin((x - title_pulse * 0.7) * 0.07) * 5
    local py = wy + math.floor(v)
    pix(scr, x, clamp(py, 0, H - 1), 1)
  end

  -- Instructions
  text(scr, "TILT = PITCH", 42, 76, 1)
  text(scr, "SHAKE = DRUMS", 38, 86, 1)
  text(scr, "ROTATE = WAVE", 38, 96, 1)

  if math.floor(title_pulse / 20) % 2 == 0 then
    text(scr, "PRESS START", 44, 108, 1)
  end

  if demo_active then
    -- Draw demo overlay
    update_waveform()
    draw_waveform()
    draw_particles()
    if math.floor(frame() / 20) % 2 == 0 then
      rect(scr, 30, 52, 100, 14, 0)
      rect(scr, 31, 53, 98, 12, 1)
      text(scr, "TILT TO PLAY", 43, 56, 0)
    end
  end
end

----------------------------------------------------------------
-- SCENE: PLAY (Main Instrument)
----------------------------------------------------------------
local function play_update()
  idle_timer = idle_timer + 1

  -- Process input (motion or keyboard)
  process_motion_input()

  -- Update recording frame counter
  if rec_active then
    rec_frame = rec_frame + 1
    if rec_frame >= MAX_REC_FRAMES then
      stop_recording()
    end
  end

  -- Update loop playback
  update_loops()

  -- Update waveform viz
  update_waveform()

  -- Update particles
  update_particles()

  -- Beat pulse decay
  if beat_pulse > 0 then
    beat_pulse = beat_pulse - 1
  end

  -- START button: toggle recording
  if btnp and btnp("start") then
    if rec_active then
      stop_recording()
      if #tracks > 0 then
        loop_playing = true
        loop_frame = 0
      end
    else
      if #tracks >= MAX_TRACKS then
        -- Clear all tracks and start fresh
        tracks = {}
        loop_playing = false
      end
      start_recording()
    end
    idle_timer = 0
  end

  -- SELECT button: toggle loop playback / clear tracks
  if btnp and btnp("select") then
    if not has_motion() then
      -- In keyboard mode, select cycles waveform (handled in process_keyboard_input)
    else
      if loop_playing then
        loop_playing = false
      elseif #tracks > 0 then
        loop_playing = true
        loop_frame = 0
      end
    end
    idle_timer = 0
  end

  -- Demo mode after long idle
  if idle_timer > IDLE_TIMEOUT * 2 then
    scene = "title"
    start_demo()
  end
end

local function play_draw()
  cls(scr, 0)

  -- Beat pulse border flash
  if beat_pulse > 4 then
    rect(scr, 0, 0, W, H, 1)
    rect(scr, 2, 2, W - 4, H - 4, 0)
  elseif beat_pulse > 0 then
    -- Subtle corner dots
    pix(scr, 0, 0, 1)
    pix(scr, W - 1, 0, 1)
    pix(scr, 0, H - 1, 1)
    pix(scr, W - 1, H - 1, 1)
  end

  -- Draw waveform
  draw_waveform()

  -- Draw note indicator / HUD
  draw_note_indicator()

  -- Draw keyboard strip
  draw_keyboard_strip()

  -- Draw track indicators
  draw_track_indicators()

  -- Draw particles
  draw_particles()

  -- Draw pitch position marker
  local marker_x = math.floor((cur_note_idx - 1) / 24 * (W - 20)) + 10
  -- Vertical line at note position
  for y = 45, 75 do
    if y % 3 == 0 then
      pix(scr, marker_x, y, 1)
    end
  end

  -- Small crosshair at center of waveform area
  local cy = 60 + math.floor(wave_buf[marker_x] or 0)
  cy = clamp(cy, 30, 90)
  line(scr, marker_x - 2, cy, marker_x + 2, cy, 1)
  line(scr, marker_x, cy - 2, marker_x, cy + 2, 1)

  -- Motion status indicator
  if has_motion() then
    pix(scr, W - 3, 3, 1)
    pix(scr, W - 2, 3, 1)
    pix(scr, W - 3, 4, 1)
    pix(scr, W - 2, 4, 1)
  else
    -- Show keyboard hint
    text(scr, "KEYS", 126, 12, 1)
  end

  -- Instructions overlay for first few seconds
  local f = frame()
  if f < 120 and scene == "play" then
    if f < 90 or math.floor(f / 8) % 2 == 0 then
      if has_motion() then
        text(scr, "TILT TO PLAY", 43, 25, 1)
      else
        text(scr, "A=NOTE B=DRUM", 36, 20, 1)
        text(scr, "SEL=WAVE", 52, 28, 1)
      end
    end
  end
end

----------------------------------------------------------------
-- ENGINE CALLBACKS
----------------------------------------------------------------
function _init()
  mode(1)
end

function _start()
  scene = "title"
  title_pulse = 0
  idle_timer = 0
  demo_active = false
  tracks = {}
  particles = {}
  rec_active = false
  loop_playing = false
  cur_note_idx = 13
  cur_wave_idx = 1
  cur_intensity = 0.5
end

function _update()
  if scene == "title" then
    title_update()
  elseif scene == "play" then
    play_update()
  end
end

function _draw()
  scr = screen()

  if scene == "title" then
    title_draw()
  elseif scene == "play" then
    play_draw()
  end
end
