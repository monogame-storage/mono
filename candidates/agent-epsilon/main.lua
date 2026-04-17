-- MONO BEAT
-- A rhythm game for the Mono fantasy console
-- Hit notes in time with the music!

----------------------------------------------------------------
-- CONSTANTS
----------------------------------------------------------------
local W = 160
local H = 120
local LANE_COUNT = 4
local LANE_W = 20
local HIGHWAY_X = (W - LANE_COUNT * LANE_W) / 2  -- centered
local HIT_Y = 100        -- where notes should be hit
local NOTE_H = 6         -- note height
local SCROLL_SPEED = 1.2 -- pixels per frame base speed

-- Timing windows (in frames at 60fps)
local PERFECT_W = 3   -- +/- 3 frames
local GREAT_W = 6     -- +/- 6 frames
local GOOD_W = 10     -- +/- 10 frames

-- Lane keys mapped to d-pad
local LANE_KEYS = { "left", "down", "up", "right" }
local LANE_LABELS = { "<", "v", "^", ">" }

-- Touch helper: map touch x coordinate to lane index (1-4), or nil if outside highway
local function touch_to_lane(tx)
  if tx < HIGHWAY_X or tx >= HIGHWAY_X + LANE_COUNT * LANE_W then
    return nil
  end
  return math.floor((tx - HIGHWAY_X) / LANE_W) + 1
end

-- Colors (grayscale 0-15)
local C_BG = 0
local C_LANE_BG = 1
local C_LANE_LINE = 3
local C_HIT_ZONE = 6
local C_NOTE_DIM = 5
local C_NOTE_MID = 9
local C_NOTE_BRIGHT = 13
local C_NOTE_HIT = 15
local C_PERFECT = 15
local C_GREAT = 12
local C_GOOD = 9
local C_MISS = 5
local C_TEXT = 15
local C_TEXT_DIM = 7
local C_COMBO = 15

----------------------------------------------------------------
-- GAME STATE
----------------------------------------------------------------
local scene = "title"
local prev_scene = ""

-- Title screen
local title_pulse = 0
local title_sel = 0  -- 0 = start
local title_idle = 0  -- idle timer for attract mode

-- Song select
local song_idx = 1

-- Gameplay
local song = nil          -- current song data
local chart = {}          -- current chart (list of notes)
local active_notes = {}   -- notes currently on screen
local next_note_idx = 1   -- next note to spawn from chart
local song_time = 0       -- elapsed time in frames
local song_playing = false
local song_done = false

-- Scoring
local score = 0
local combo = 0
local max_combo = 0
local perfects = 0
local greats = 0
local goods = 0
local misses = 0
local total_notes = 0

-- Judgment display
local judgment_text = ""
local judgment_color = 0
local judgment_timer = 0

-- Lane flash
local lane_flash = {0, 0, 0, 0}

-- Particles
local particles = {}

-- Pause
local paused = false

-- Beat pulse
local beat_pulse = 0

-- Background visualization bars
local bg_bars = {0,0,0,0,0,0,0,0}

-- Results
local result_grade = ""
local result_timer = 0

-- Audio scheduling
local audio_events = {}
local next_audio_idx = 1

-- Drum scheduling
local drum_events = {}
local next_drum_idx = 1

-- Attract/demo mode
local attract_mode = false
local attract_timer = 0
local attract_overlay_blink = 0
local attract_ai_notes = {}  -- upcoming notes for AI to hit

----------------------------------------------------------------
-- SONGS DATA
-- Each song: name, bpm, difficulty, chart, audio_track
-- Chart entries: {frame, lane} (lane 1-4)
-- Audio entries: {frame, channel, note_name, duration}
----------------------------------------------------------------

local songs = {}

-- Helper: generate chart from beat pattern
local function make_chart(bpm, pattern)
  local frames_per_beat = math.floor(3600 / bpm)
  local subdivision = frames_per_beat / 2  -- 8th notes
  local chart_data = {}
  local t = 120  -- start after 2 seconds
  for i = 1, #pattern do
    local c = pattern:sub(i, i)
    if c == "|" or c == " " then
      -- separator, skip
    elseif c == "0" then
      t = t + subdivision
    elseif c >= "1" and c <= "4" then
      table.insert(chart_data, {frame = math.floor(t), lane = tonumber(c)})
      t = t + subdivision
    else
      t = t + subdivision
    end
  end
  return chart_data
end

-- Helper: generate audio track from melody pattern
local function make_audio(bpm, melody)
  local frames_per_beat = math.floor(3600 / bpm)
  local subdivision = frames_per_beat / 2
  local audio_data = {}
  local t = 120
  local dur = math.floor(subdivision * 0.8)
  for raw_token in melody:gmatch("[^,]+") do
    local token = raw_token:match("^%s*(.-)%s*$")
    if token ~= "0" and token ~= "" then
      table.insert(audio_data, {frame = math.floor(t), ch = 0, note_name = token, dur = dur})
    end
    t = t + subdivision
  end
  return audio_data
end

-- Helper: make bass audio track on channel 1
local function make_bass(bpm, melody)
  local frames_per_beat = math.floor(3600 / bpm)
  local subdivision = frames_per_beat / 2
  local audio_data = {}
  local t = 120
  local dur = math.floor(subdivision * 1.5)
  for raw_token in melody:gmatch("[^,]+") do
    local token = raw_token:match("^%s*(.-)%s*$")
    if token ~= "0" and token ~= "" then
      table.insert(audio_data, {frame = math.floor(t), ch = 1, note_name = token, dur = dur})
    end
    t = t + subdivision
  end
  return audio_data
end

-- Helper: make drum track using noise channel
local function make_drums(bpm, pattern)
  -- pattern: K=kick, S=snare, H=hihat, 0=rest
  local frames_per_beat = math.floor(3600 / bpm)
  local subdivision = frames_per_beat / 2
  local drum_data = {}
  local t = 120
  for i = 1, #pattern do
    local c = pattern:sub(i, i)
    if c == "|" or c == " " then
      -- skip
    elseif c == "K" then
      table.insert(drum_data, {frame = math.floor(t), dtype = "kick"})
      t = t + subdivision
    elseif c == "S" then
      table.insert(drum_data, {frame = math.floor(t), dtype = "snare"})
      t = t + subdivision
    elseif c == "H" then
      table.insert(drum_data, {frame = math.floor(t), dtype = "hat"})
      t = t + subdivision
    else
      t = t + subdivision
    end
  end
  return drum_data
end

-- SONG 1: "First Steps" - Easy, 100 BPM
local function build_song1()
  local bpm = 100
  local s = {
    name = "FIRST STEPS",
    bpm = bpm,
    difficulty = "EASY",
    stars = 1,
  }
  s.chart = make_chart(bpm,
    "1020|3040|1020|3040|" ..
    "2010|4030|2010|4030|" ..
    "1030|2040|1030|2040|" ..
    "1234|0000|1234|0000|" ..
    "1020|3040|1020|3040|" ..
    "2010|4030|2010|4030|" ..
    "1030|2040|3010|4020|" ..
    "1234|1234|0000|0000|" ..
    "1010|2020|3030|4040|" ..
    "4030|2010|4030|2010|" ..
    "1020|3040|2030|1040|" ..
    "1234|4321|1234|0000"
  )
  s.audio = make_audio(bpm,
    "C4,0,E4,0,C4,0,E4,0," ..
    "D4,0,F4,0,D4,0,F4,0," ..
    "C4,0,G4,0,C4,0,G4,0," ..
    "C4,D4,E4,F4,0,0,0,0," ..
    "G4,0,E4,0,G4,0,E4,0," ..
    "A4,0,F4,0,A4,0,F4,0," ..
    "G4,0,E4,0,C5,0,G4,0," ..
    "C4,D4,E4,F4,G4,A4,B4,C5," ..
    "C5,0,B4,0,A4,0,G4,0," ..
    "F4,0,E4,0,D4,0,C4,0," ..
    "E4,0,G4,0,E4,0,G4,0," ..
    "C4,D4,E4,G4,C5,0,0,0"
  )
  s.bass = make_bass(bpm,
    "C3,0,0,0,C3,0,0,0," ..
    "D3,0,0,0,D3,0,0,0," ..
    "C3,0,0,0,E3,0,0,0," ..
    "C3,0,0,0,0,0,0,0," ..
    "G2,0,0,0,G2,0,0,0," ..
    "A2,0,0,0,A2,0,0,0," ..
    "G2,0,0,0,C3,0,0,0," ..
    "C3,0,0,0,0,0,0,0," ..
    "C3,0,0,0,C3,0,0,0," ..
    "F2,0,0,0,F2,0,0,0," ..
    "E2,0,0,0,E2,0,0,0," ..
    "C3,0,0,0,0,0,0,0"
  )
  s.drums = make_drums(bpm,
    "K0H0|S0H0|K0H0|S0H0|" ..
    "K0H0|S0H0|K0H0|S0H0|" ..
    "K0H0|S0H0|K0H0|S0H0|" ..
    "KKKK|0000|KKKK|0000|" ..
    "K0H0|S0H0|K0H0|S0H0|" ..
    "K0H0|S0H0|K0H0|S0H0|" ..
    "K0H0|S0H0|K0H0|S0H0|" ..
    "KHKH|SHSH|0000|0000|" ..
    "K0H0|S0H0|K0H0|S0H0|" ..
    "K0H0|S0H0|K0H0|S0H0|" ..
    "K0H0|S0H0|K0H0|S0H0|" ..
    "KSKS|KSKS|KKKK|0000"
  )
  return s
end

-- SONG 2: "Pulse Drive" - Medium, 120 BPM
local function build_song2()
  local bpm = 120
  local s = {
    name = "PULSE DRIVE",
    bpm = bpm,
    difficulty = "MEDIUM",
    stars = 2,
  }
  s.chart = make_chart(bpm,
    "1030|2040|1030|2040|" ..
    "1230|0040|1230|0040|" ..
    "3010|4020|3010|4020|" ..
    "1234|1234|1234|1234|" ..
    "1020|1020|3040|3040|" ..
    "2040|2040|1030|1030|" ..
    "1324|2413|1324|2413|" ..
    "1234|4321|1234|4321|" ..
    "1100|2200|3300|4400|" ..
    "1032|0041|2031|0042|" ..
    "1234|1234|4321|4321|" ..
    "1324|2413|1324|2413|" ..
    "1020|3040|2010|4030|" ..
    "1234|1234|1234|0000"
  )
  s.audio = make_audio(bpm,
    "E4,0,G4,0,E4,0,G4,0," ..
    "E4,G4,A4,0,E4,G4,A4,0," ..
    "C5,0,B4,0,C5,0,B4,0," ..
    "E4,G4,A4,B4,E4,G4,A4,B4," ..
    "E4,0,E4,0,G4,0,G4,0," ..
    "A4,0,A4,0,E4,0,E4,0," ..
    "E4,G4,A4,B4,G4,B4,A4,E4," ..
    "E4,G4,A4,B4,B4,A4,G4,E4," ..
    "C5,C5,0,0,D5,D5,0,0," ..
    "E5,0,G4,A4,0,0,E5,0," ..
    "C5,B4,A4,G4,G4,A4,B4,C5," ..
    "E4,G4,A4,B4,E4,G4,A4,B4," ..
    "E4,0,G4,0,A4,0,B4,0," ..
    "E4,G4,A4,B4,C5,0,0,0"
  )
  s.bass = make_bass(bpm,
    "E2,0,0,0,E2,0,0,0," ..
    "E2,0,0,0,E2,0,0,0," ..
    "A2,0,0,0,A2,0,0,0," ..
    "E2,0,0,0,E2,0,0,0," ..
    "E2,0,E2,0,G2,0,G2,0," ..
    "A2,0,A2,0,E2,0,E2,0," ..
    "E2,0,0,0,G2,0,0,0," ..
    "E2,0,0,0,E2,0,0,0," ..
    "C3,0,0,0,D3,0,0,0," ..
    "E3,0,0,0,E3,0,0,0," ..
    "C3,0,0,0,C3,0,0,0," ..
    "E2,0,0,0,E2,0,0,0," ..
    "E2,0,G2,0,A2,0,B2,0," ..
    "E2,0,0,0,0,0,0,0"
  )
  s.drums = make_drums(bpm,
    "K0H0|S0H0|K0H0|S0H0|" ..
    "K0HH|S0H0|K0HH|S0H0|" ..
    "K0H0|S0H0|K0H0|S0H0|" ..
    "KHSH|KHSH|KHSH|KHSH|" ..
    "K0H0|K0H0|S0H0|S0H0|" ..
    "K0H0|K0H0|S0H0|S0H0|" ..
    "KHKH|SHSH|KHKH|SHSH|" ..
    "KHSH|KHSH|KHSH|KHSH|" ..
    "KK00|SS00|KK00|SS00|" ..
    "K0H0|S0H0|K0H0|S0H0|" ..
    "KHSH|KHSH|SHKS|SHKS|" ..
    "KHKH|SHSH|KHKH|SHSH|" ..
    "K0H0|S0H0|K0H0|S0H0|" ..
    "KHSH|KHSH|KHSH|0000"
  )
  return s
end

-- SONG 3: "Overclock" - Hard, 140 BPM
local function build_song3()
  local bpm = 140
  local s = {
    name = "OVERCLOCK",
    bpm = bpm,
    difficulty = "HARD",
    stars = 3,
  }
  s.chart = make_chart(bpm,
    "1234|1234|1234|1234|" ..
    "1324|2413|1324|2413|" ..
    "1212|3434|1212|3434|" ..
    "4321|1234|4321|1234|" ..
    "1234|1324|2413|4321|" ..
    "1132|2241|3314|4423|" ..
    "1234|4321|2143|3412|" ..
    "1111|2222|3333|4444|" ..
    "1234|1234|4321|4321|" ..
    "1324|1324|2413|2413|" ..
    "1213|2124|3231|4342|" ..
    "1234|2341|3412|4123|" ..
    "4321|3214|2143|1432|" ..
    "1234|1234|1234|1234|" ..
    "1324|2413|1234|0000"
  )
  s.audio = make_audio(bpm,
    "A4,B4,C5,D5,A4,B4,C5,D5," ..
    "A4,C5,B4,D5,B4,D5,A4,C5," ..
    "A4,B4,A4,B4,C5,D5,C5,D5," ..
    "D5,C5,B4,A4,A4,B4,C5,D5," ..
    "A4,B4,C5,D5,A4,C5,B4,D5," ..
    "A4,A4,C5,B4,B4,D5,C5,A4," ..
    "E5,D5,C5,B4,D5,C5,B4,A4," ..
    "A4,A4,A4,A4,B4,B4,B4,B4," ..
    "A4,B4,C5,D5,E5,D5,C5,B4," ..
    "A4,C5,A4,C5,B4,D5,B4,D5," ..
    "A4,B4,A4,C5,B4,A4,C5,D5," ..
    "E5,D5,C5,B4,D5,C5,B4,A4," ..
    "D5,C5,B4,A4,C5,B4,A4,G4," ..
    "A4,B4,C5,D5,A4,B4,C5,D5," ..
    "A4,C5,B4,D5,A4,B4,C5,0"
  )
  s.bass = make_bass(bpm,
    "A2,0,A2,0,A2,0,A2,0," ..
    "A2,0,A2,0,A2,0,A2,0," ..
    "A2,0,A2,0,C3,0,C3,0," ..
    "D3,0,A2,0,A2,0,A2,0," ..
    "A2,0,A2,0,A2,0,A2,0," ..
    "A2,0,A2,0,B2,0,B2,0," ..
    "E3,0,D3,0,C3,0,A2,0," ..
    "A2,0,A2,0,B2,0,B2,0," ..
    "A2,0,A2,0,E3,0,E3,0," ..
    "A2,0,A2,0,B2,0,B2,0," ..
    "A2,0,A2,0,A2,0,A2,0," ..
    "E3,0,D3,0,C3,0,A2,0," ..
    "D3,0,C3,0,A2,0,G2,0," ..
    "A2,0,A2,0,A2,0,A2,0," ..
    "A2,0,A2,0,A2,0,0,0"
  )
  s.drums = make_drums(bpm,
    "KHSH|KHSH|KHSH|KHSH|" ..
    "KHSH|KHSH|KHSH|KHSH|" ..
    "KHKH|SHSH|KHKH|SHSH|" ..
    "SKHS|KHSH|SKHS|KHSH|" ..
    "KHSH|KHSH|KHSH|KHSH|" ..
    "KKSH|KKSH|KKSH|KKSH|" ..
    "KHSH|SKHS|KHSH|SKHS|" ..
    "KKKK|SSSS|KKKK|SSSS|" ..
    "KHSH|KHSH|SKHS|SKHS|" ..
    "KHKH|KHKH|SHSH|SHSH|" ..
    "KHSH|KHSH|KHSH|KHSH|" ..
    "KHSH|SKHS|KHSH|SKHS|" ..
    "SKHS|SKHS|SKHS|SKHS|" ..
    "KHSH|KHSH|KHSH|KHSH|" ..
    "KHSH|KHSH|KHSH|0000"
  )
  return s
end

----------------------------------------------------------------
-- INIT
----------------------------------------------------------------
function _init()
  mode(4)
end

function _start()
  songs = { build_song1(), build_song2(), build_song3() }
  -- Set wave types for channels
  wave(0, 1)  -- pulse wave for melody
  wave(1, 2)  -- triangle for bass
  scene = "title"
  title_pulse = 0
  title_idle = 0
  attract_mode = false
end

----------------------------------------------------------------
-- SCENE: TITLE
----------------------------------------------------------------
local function title_update()
  title_pulse = title_pulse + 1
  title_idle = title_idle + 1

  if btnp("start") or btnp("a") or touch_start() then
    if attract_mode then
      -- Stop attract mode, return to title
      attract_mode = false
      song_playing = false
      title_idle = 0
      scene = "title"
      return
    end
    scene = "select"
    song_idx = 1
    title_idle = 0
    note(0, "C5", 2)
    note(1, "E5", 2)
    return
  end

  -- Enter attract mode after ~90 frames idle on title
  if not attract_mode and title_idle >= 90 then
    start_attract()
  end
end

local function title_draw()
  local scr = screen()
  cls(scr, 0)

  -- Animated background bars
  for i = 0, 7 do
    local bh = math.floor(math.sin(title_pulse * 0.05 + i * 0.8) * 15 + 20)
    local x = i * 20
    local c = math.floor(math.sin(title_pulse * 0.03 + i * 0.5) * 2 + 3)
    if c < 1 then c = 1 end
    rectf(scr, x, H - bh, 18, bh, c)
  end

  -- Title text with pulse effect
  local ty = 20 + math.floor(math.sin(title_pulse * 0.08) * 3)
  text(scr, "MONO", 55, ty, 15)
  text(scr, "BEAT", 87, ty, 12)

  -- Subtitle
  text(scr, "A RHYTHM GAME", 42, ty + 14, 7)

  -- Decorative line
  local lw = 60 + math.floor(math.sin(title_pulse * 0.1) * 10)
  local lx = (W - lw) / 2
  line(scr, lx, ty + 24, lx + lw, ty + 24, 5)

  -- Lane preview animation
  local preview_y = 55
  for lane = 1, 4 do
    local lx2 = HIGHWAY_X + (lane - 1) * LANE_W
    rectf(scr, lx2, preview_y, LANE_W - 1, 30, 1)
    for n = 0, 2 do
      local ny = preview_y + ((title_pulse * 0.8 + n * 12 + lane * 5) % 30)
      local nc = math.floor(ny - preview_y) / 30 * 8 + 4
      if nc > 12 then nc = 12 end
      rectf(scr, lx2 + 2, ny, LANE_W - 5, 4, math.floor(nc))
    end
    text(scr, LANE_LABELS[lane], lx2 + 7, preview_y + 32, 10)
  end

  -- Start prompt
  local blink = math.floor(title_pulse / 20) % 2
  if blink == 0 then
    text(scr, "PRESS START", 45, 100, 15)
  end

  -- Credit
  text(scr, "AGENT EPSILON", 44, 112, 4)
end

----------------------------------------------------------------
-- PARTICLES (shared by play and attract)
----------------------------------------------------------------
local function spawn_particles(lane, color, count)
  local cx = HIGHWAY_X + (lane - 1) * LANE_W + LANE_W / 2
  local cy = HIT_Y
  for i = 1, count do
    local angle = math.random() * math.pi * 2
    local spd = math.random() * 2 + 1
    table.insert(particles, {
      x = cx,
      y = cy,
      vx = math.cos(angle) * spd,
      vy = math.sin(angle) * spd - 1.5,
      life = math.random(10, 20),
      c = color
    })
  end
end

----------------------------------------------------------------
-- ATTRACT / DEMO MODE
----------------------------------------------------------------
function start_attract()
  attract_mode = true
  attract_timer = 0
  attract_overlay_blink = 0

  -- Start song 2 (medium difficulty - looks impressive)
  local idx = 2
  if idx > #songs then idx = 1 end
  song = songs[idx]

  -- Deep copy chart
  chart = {}
  for _, n in ipairs(song.chart) do
    table.insert(chart, {frame = n.frame, lane = n.lane})
  end

  -- Build combined audio events
  audio_events = {}
  if song.audio then
    for _, a in ipairs(song.audio) do
      table.insert(audio_events, {frame = a.frame, ch = a.ch, note_name = a.note_name, dur = a.dur})
    end
  end
  if song.bass then
    for _, a in ipairs(song.bass) do
      table.insert(audio_events, {frame = a.frame, ch = a.ch, note_name = a.note_name, dur = a.dur})
    end
  end
  table.sort(audio_events, function(a, b) return a.frame < b.frame end)
  next_audio_idx = 1

  -- Build drum events
  drum_events = {}
  if song.drums then
    for _, d in ipairs(song.drums) do
      table.insert(drum_events, {frame = d.frame, dtype = d.dtype})
    end
  end
  next_drum_idx = 1

  -- Build AI note list (sorted by frame) for perfect hits
  attract_ai_notes = {}
  for _, n in ipairs(chart) do
    table.insert(attract_ai_notes, {frame = n.frame, lane = n.lane, done = false})
  end

  active_notes = {}
  next_note_idx = 1
  song_time = 0
  song_playing = true
  song_done = false

  score = 0
  combo = 0
  max_combo = 0
  perfects = 0
  greats = 0
  goods = 0
  misses = 0
  total_notes = #chart

  judgment_text = ""
  judgment_timer = 0
  lane_flash = {0, 0, 0, 0}
  particles = {}
  paused = false
  beat_pulse = 0
  bg_bars = {0,0,0,0,0,0,0,0}

  scene = "attract"
end

local function attract_update()
  attract_timer = attract_timer + 1
  attract_overlay_blink = attract_overlay_blink + 1

  -- Press start or tap to exit attract mode
  if btnp("start") or btnp("a") or touch_start() then
    attract_mode = false
    song_playing = false
    scene = "title"
    title_idle = 0
    title_pulse = 0
    return
  end

  -- When demo song ends, restart it from the beginning to loop forever
  if next_note_idx > #chart and #active_notes == 0 and next_audio_idx > #audio_events then
    start_attract()
    return
  end

  song_time = song_time + 1

  -- Play scheduled audio
  while next_audio_idx <= #audio_events do
    local ae = audio_events[next_audio_idx]
    if ae.frame <= song_time then
      note(ae.ch, ae.note_name, ae.dur)
      local bar_idx = (ae.ch * 4 + (song_time % 4)) % 8 + 1
      bg_bars[bar_idx] = 12
      next_audio_idx = next_audio_idx + 1
    else
      break
    end
  end

  -- Play drums
  while next_drum_idx <= #drum_events do
    local de = drum_events[next_drum_idx]
    if de.frame <= song_time then
      if de.dtype == "kick" then
        noise(3, 2)
      elseif de.dtype == "snare" then
        noise(3, 1)
      elseif de.dtype == "hat" then
        tone(3, 8000, 9000, 1)
      end
      next_drum_idx = next_drum_idx + 1
    else
      break
    end
  end

  -- Beat pulse decay
  if beat_pulse > 0 then beat_pulse = beat_pulse - 0.5 end

  -- Spawn notes
  local lead_frames = math.floor(HIT_Y / SCROLL_SPEED)
  while next_note_idx <= #chart do
    local cn = chart[next_note_idx]
    if cn.frame <= song_time + lead_frames then
      local spawn_y = HIT_Y - (cn.frame - song_time) * SCROLL_SPEED
      table.insert(active_notes, {
        lane = cn.lane,
        target_frame = cn.frame,
        y = spawn_y,
        hit = false,
        hit_color = 0,
        missed = false
      })
      next_note_idx = next_note_idx + 1
    else
      break
    end
  end

  -- AI: auto-hit notes perfectly when they reach the hit zone
  for i, ai_n in ipairs(attract_ai_notes) do
    if not ai_n.done and ai_n.frame <= song_time then
      -- Find the matching active note and judge it
      for j, n in ipairs(active_notes) do
        if n.lane == ai_n.lane and not n.hit and not n.missed then
          local dist = math.abs(n.y - HIT_Y)
          if dist < GOOD_W * SCROLL_SPEED then
            -- Perfect hit!
            n.hit = true
            n.hit_color = 15
            lane_flash[n.lane] = 8
            beat_pulse = 6
            spawn_particles(n.lane, 15, 8)
            combo = combo + 1
            perfects = perfects + 1
            score = score + 300 * (1 + math.floor(combo / 10))
            if combo > max_combo then max_combo = combo end
            judgment_text = "PERFECT"
            judgment_color = C_PERFECT
            judgment_timer = 20
            note(2, "C6", 1)
            ai_n.done = true
            break
          end
        end
      end
      if not ai_n.done then
        ai_n.done = true  -- skip if note not found
      end
    end
  end

  -- Move active notes
  for i = #active_notes, 1, -1 do
    local n = active_notes[i]
    n.y = n.y + SCROLL_SPEED

    if n.hit then
      n.hit_color = n.hit_color - 1
      if n.hit_color <= 0 then
        table.remove(active_notes, i)
      end
    elseif n.y > HIT_Y + GOOD_W * SCROLL_SPEED + 10 then
      if not n.missed then
        n.missed = true
      end
      if n.y > H + 10 then
        table.remove(active_notes, i)
      end
    end
  end

  -- Update lane flash
  for i = 1, 4 do
    if lane_flash[i] > 0 then lane_flash[i] = lane_flash[i] - 1 end
  end

  -- Update judgment timer
  if judgment_timer > 0 then judgment_timer = judgment_timer - 1 end

  -- Update particles
  for i = #particles, 1, -1 do
    local p = particles[i]
    p.x = p.x + p.vx
    p.y = p.y + p.vy
    p.vy = p.vy + 0.1
    p.life = p.life - 1
    if p.life <= 0 then
      table.remove(particles, i)
    end
  end

  -- Update bg bars decay
  for i = 1, 8 do
    if bg_bars[i] > 0 then bg_bars[i] = bg_bars[i] - 0.3 end
  end
end

----------------------------------------------------------------
-- 7-SEGMENT CLOCK (for attract/demo mode)
----------------------------------------------------------------
-- Segment layout for a digit ~7px wide x 11px tall, thickness 2px:
--  _a_
-- |   |
-- f   b
-- |_g_|
-- |   |
-- e   c
-- |_d_|
-- Segments: a=1, b=2, c=3, d=4, e=5, f=6, g=7
local SEG_DIGITS = {
  [0] = {true,true,true,true,true,true,false},     -- abcdef
  [1] = {false,true,true,false,false,false,false},  -- bc
  [2] = {true,true,false,true,true,false,true},     -- abdeg
  [3] = {true,true,true,true,false,false,true},     -- abcdg
  [4] = {false,true,true,false,false,true,true},    -- bcfg
  [5] = {true,false,true,true,false,true,true},     -- acdfg
  [6] = {true,false,true,true,true,true,true},      -- acdefg
  [7] = {true,true,true,false,false,false,false},   -- abc
  [8] = {true,true,true,true,true,true,true},       -- abcdefg
  [9] = {true,true,true,true,false,true,true},      -- abcdfg
}

-- Draw a single 7-segment digit at (x,y), color c
-- Digit cell: 7px wide, 11px tall, segment thickness 2px
local function draw_seg_digit(scr, x, y, digit, c)
  local segs = SEG_DIGITS[digit]
  if not segs then return end
  local t = 2  -- thickness
  -- a: top horizontal
  if segs[1] then rectf(scr, x + t, y, 3, t, c) end
  -- b: upper-right vertical
  if segs[2] then rectf(scr, x + t + 3, y + t, t, 3, c) end
  -- c: lower-right vertical
  if segs[3] then rectf(scr, x + t + 3, y + t + 3 + t, t, 3, c) end
  -- d: bottom horizontal
  if segs[4] then rectf(scr, x + t, y + t + 3 + t + 3, 3, t, c) end
  -- e: lower-left vertical
  if segs[5] then rectf(scr, x, y + t + 3 + t, t, 3, c) end
  -- f: upper-left vertical
  if segs[6] then rectf(scr, x, y + t, t, 3, c) end
  -- g: middle horizontal
  if segs[7] then rectf(scr, x + t, y + t + 3, 3, t, c) end
end

-- Draw HH:MM clock at (x,y) with color c, colon blinks
local function draw_clock(scr, x, y, c, show_colon)
  local d = date()
  local h = d.hour or 0
  local m = d.min or 0
  local dw = 9  -- digit spacing (7px digit + 2px gap)
  -- Hour tens
  draw_seg_digit(scr, x, y, math.floor(h / 10), c)
  -- Hour ones
  draw_seg_digit(scr, x + dw, y, h % 10, c)
  -- Colon (two small squares)
  if show_colon then
    rectf(scr, x + dw * 2 + 1, y + 3, 2, 2, c)
    rectf(scr, x + dw * 2 + 1, y + 8, 2, 2, c)
  end
  -- Minute tens
  local mx = x + dw * 2 + 5
  draw_seg_digit(scr, mx, y, math.floor(m / 10), c)
  -- Minute ones
  draw_seg_digit(scr, mx + dw, y, m % 10, c)
end

local function attract_draw()
  local scr = screen()
  -- Draw the gameplay scene
  play_draw_inner()

  -- Overlay: "PRESS START" blinking
  local blink = math.floor(attract_overlay_blink / 25) % 2
  if blink == 0 then
    -- Dark background strip for readability
    rectf(scr, 30, 55, 100, 14, 0)
    rect(scr, 30, 55, 100, 14, 8)
    text(scr, "PRESS START", 45, 59, 15)
  end

  -- "DEMO PLAY" label at top
  text(scr, "DEMO", 2, 2, 10)

  -- 7-segment clock in top-right corner (dim color)
  local colon_on = math.floor(frame() / 30) % 2 == 0
  draw_clock(scr, W - 42, 2, 3, colon_on)
end

----------------------------------------------------------------
-- SCENE: SONG SELECT
----------------------------------------------------------------
local function select_update()
  title_pulse = title_pulse + 1
  if btnp("up") or btnp("left") then
    song_idx = song_idx - 1
    if song_idx < 1 then song_idx = #songs end
    note(0, "E4", 1)
  end
  if btnp("down") or btnp("right") then
    song_idx = song_idx + 1
    if song_idx > #songs then song_idx = 1 end
    note(0, "E4", 1)
  end
  if btnp("a") or btnp("start") then
    start_song(song_idx)
    note(0, "C5", 2)
    note(1, "G4", 2)
  end
  if btnp("b") then
    scene = "title"
    title_idle = 0
    note(0, "C4", 1)
  end
  -- Touch support for song select
  if touch_start() then
    local tx, ty = touch_pos()
    if ty < H / 3 then
      -- Tap top third: scroll up
      song_idx = song_idx - 1
      if song_idx < 1 then song_idx = #songs end
      note(0, "E4", 1)
    elseif ty > H * 2 / 3 then
      -- Tap bottom third: scroll down
      song_idx = song_idx + 1
      if song_idx > #songs then song_idx = 1 end
      note(0, "E4", 1)
    else
      -- Tap middle: confirm selection
      start_song(song_idx)
      note(0, "C5", 2)
      note(1, "G4", 2)
    end
  end
end

local function select_draw()
  local scr = screen()
  cls(scr, 0)

  text(scr, "SELECT SONG", 42, 5, 15)
  line(scr, 30, 14, 130, 14, 5)

  for i = 1, #songs do
    local s = songs[i]
    local y = 22 + (i - 1) * 30
    local sel = (i == song_idx)

    -- Selection box
    if sel then
      local pulse_c = math.floor(math.sin(title_pulse * 0.1) * 2 + 6)
      rectf(scr, 10, y - 2, 140, 26, 2)
      rect(scr, 10, y - 2, 140, 26, pulse_c)
    end

    -- Song name
    local nc = sel and 15 or 7
    text(scr, s.name, 16, y + 2, nc)

    -- Difficulty
    text(scr, s.difficulty, 16, y + 12, sel and 10 or 5)

    -- Stars
    local star_str = ""
    for st = 1, 3 do
      if st <= s.stars then
        star_str = star_str .. "*"
      else
        star_str = star_str .. "."
      end
    end
    text(scr, star_str, 120, y + 2, sel and 12 or 5)
  end

  -- Controls hint
  text(scr, "A:PLAY  B:BACK", 35, 110, 5)
end

----------------------------------------------------------------
-- START SONG
----------------------------------------------------------------
function start_song(idx)
  song = songs[idx]
  -- Deep copy chart
  chart = {}
  for _, n in ipairs(song.chart) do
    table.insert(chart, {frame = n.frame, lane = n.lane})
  end

  -- Build combined audio events
  audio_events = {}
  if song.audio then
    for _, a in ipairs(song.audio) do
      table.insert(audio_events, {frame = a.frame, ch = a.ch, note_name = a.note_name, dur = a.dur})
    end
  end
  if song.bass then
    for _, a in ipairs(song.bass) do
      table.insert(audio_events, {frame = a.frame, ch = a.ch, note_name = a.note_name, dur = a.dur})
    end
  end
  -- Sort by frame
  table.sort(audio_events, function(a, b) return a.frame < b.frame end)
  next_audio_idx = 1

  -- Build drum events
  drum_events = {}
  if song.drums then
    for _, d in ipairs(song.drums) do
      table.insert(drum_events, {frame = d.frame, dtype = d.dtype})
    end
  end
  next_drum_idx = 1

  active_notes = {}
  next_note_idx = 1
  song_time = 0
  song_playing = true
  song_done = false

  score = 0
  combo = 0
  max_combo = 0
  perfects = 0
  greats = 0
  goods = 0
  misses = 0
  total_notes = #chart

  judgment_text = ""
  judgment_timer = 0
  lane_flash = {0, 0, 0, 0}
  particles = {}
  paused = false
  beat_pulse = 0
  bg_bars = {0,0,0,0,0,0,0,0}

  -- Set wave types for channels
  wave(0, 1)  -- pulse for melody
  wave(1, 2)  -- triangle for bass

  scene = "play"
end

----------------------------------------------------------------
-- SCENE: PLAY
----------------------------------------------------------------

local function judge_hit(lane)
  -- Find closest note in this lane using frame-based timing
  local best_note = nil
  local best_dist = 9999
  local best_idx = -1

  for i, n in ipairs(active_notes) do
    if n.lane == lane and not n.hit and not n.missed then
      -- Use frame-based distance for accurate timing
      local frame_dist = math.abs(n.target_frame - song_time)
      if frame_dist < best_dist then
        best_dist = frame_dist
        best_note = n
        best_idx = i
      end
    end
  end

  if not best_note then return end

  if best_dist <= PERFECT_W then
    judgment_text = "PERFECT"
    judgment_color = C_PERFECT
    judgment_timer = 20
    score = score + 300 * (1 + math.floor(combo / 10))
    combo = combo + 1
    perfects = perfects + 1
    best_note.hit = true
    best_note.hit_color = 15
    lane_flash[lane] = 8
    beat_pulse = 6
    spawn_particles(lane, 15, 8)
    -- Play hit sound with pitch variation
    note(2, "C6", 1)
  elseif best_dist <= GREAT_W then
    judgment_text = "GREAT"
    judgment_color = C_GREAT
    judgment_timer = 18
    score = score + 200 * (1 + math.floor(combo / 10))
    combo = combo + 1
    greats = greats + 1
    best_note.hit = true
    best_note.hit_color = 12
    lane_flash[lane] = 6
    beat_pulse = 4
    spawn_particles(lane, 12, 5)
    note(2, "A5", 1)
  elseif best_dist <= GOOD_W then
    judgment_text = "GOOD"
    judgment_color = C_GOOD
    judgment_timer = 15
    score = score + 100 * (1 + math.floor(combo / 10))
    combo = combo + 1
    goods = goods + 1
    best_note.hit = true
    best_note.hit_color = 9
    lane_flash[lane] = 4
    spawn_particles(lane, 9, 3)
    note(2, "F5", 1)
  end

  if combo > max_combo then max_combo = combo end
end

local function play_update()
  if btnp("select") then
    paused = not paused
    if paused then return end
  end
  if paused then
    if btnp("b") then
      scene = "select"
      song_playing = false
    end
    return
  end

  song_time = song_time + 1

  -- Play scheduled audio
  while next_audio_idx <= #audio_events do
    local ae = audio_events[next_audio_idx]
    if ae.frame <= song_time then
      note(ae.ch, ae.note_name, ae.dur)
      local bar_idx = (ae.ch * 4 + (song_time % 4)) % 8 + 1
      bg_bars[bar_idx] = 12
      next_audio_idx = next_audio_idx + 1
    else
      break
    end
  end

  -- Play drums
  while next_drum_idx <= #drum_events do
    local de = drum_events[next_drum_idx]
    if de.frame <= song_time then
      if de.dtype == "kick" then
        noise(3, 2)
      elseif de.dtype == "snare" then
        noise(3, 1)
      elseif de.dtype == "hat" then
        tone(3, 8000, 9000, 1)
      end
      next_drum_idx = next_drum_idx + 1
    else
      break
    end
  end

  -- Beat pulse decay
  if beat_pulse > 0 then beat_pulse = beat_pulse - 0.5 end

  -- Spawn notes that should now be visible
  local lead_frames = math.floor(HIT_Y / SCROLL_SPEED)
  while next_note_idx <= #chart do
    local cn = chart[next_note_idx]
    if cn.frame <= song_time + lead_frames then
      local spawn_y = HIT_Y - (cn.frame - song_time) * SCROLL_SPEED
      table.insert(active_notes, {
        lane = cn.lane,
        target_frame = cn.frame,
        y = spawn_y,
        hit = false,
        hit_color = 0,
        missed = false
      })
      next_note_idx = next_note_idx + 1
    else
      break
    end
  end

  -- Move active notes down
  for i = #active_notes, 1, -1 do
    local n = active_notes[i]
    n.y = n.y + SCROLL_SPEED

    -- Hit notes fade out
    if n.hit then
      n.hit_color = n.hit_color - 1
      if n.hit_color <= 0 then
        table.remove(active_notes, i)
      end
    elseif n.y > HIT_Y + GOOD_W * SCROLL_SPEED + 10 then
      -- Missed!
      if not n.missed then
        n.missed = true
        misses = misses + 1
        combo = 0
        judgment_text = "MISS"
        judgment_color = C_MISS
        judgment_timer = 15
      end
      if n.y > H + 10 then
        table.remove(active_notes, i)
      end
    end
  end

  -- Check input (buttons)
  for lane = 1, 4 do
    if btnp(LANE_KEYS[lane]) then
      judge_hit(lane)
    end
  end

  -- Check input (touch)
  if touch_start() then
    local tx, ty = touch_pos()
    local tlane = touch_to_lane(tx)
    if tlane then
      judge_hit(tlane)
    end
  end

  -- Update lane flash
  for i = 1, 4 do
    if lane_flash[i] > 0 then lane_flash[i] = lane_flash[i] - 1 end
  end

  -- Update judgment timer
  if judgment_timer > 0 then judgment_timer = judgment_timer - 1 end

  -- Update particles
  for i = #particles, 1, -1 do
    local p = particles[i]
    p.x = p.x + p.vx
    p.y = p.y + p.vy
    p.vy = p.vy + 0.1
    p.life = p.life - 1
    if p.life <= 0 then
      table.remove(particles, i)
    end
  end

  -- Update bg bars decay
  for i = 1, 8 do
    if bg_bars[i] > 0 then bg_bars[i] = bg_bars[i] - 0.3 end
  end

  -- Check if song is done
  if next_note_idx > #chart and #active_notes == 0 and next_audio_idx > #audio_events then
    if not song_done then
      song_done = true
      result_timer = 60
    end
  end
  if song_done then
    result_timer = result_timer - 1
    if result_timer <= 0 then
      calculate_results()
      scene = "results"
    end
  end
end

-- Shared draw function used by both play and attract scenes
function play_draw_inner()
  local scr = screen()
  cls(scr, C_BG)

  -- Background beat visualization bars
  for i = 1, 8 do
    local bh = math.floor(bg_bars[i] * 3)
    if bh > 0 then
      local bx = (i - 1) * 20
      local bc = math.floor(bg_bars[i] / 4) + 1
      if bc > 3 then bc = 3 end
      rectf(scr, bx, H - bh, 18, bh, bc)
    end
  end

  -- Beat pulse background effect
  if beat_pulse > 0 then
    local pr = math.floor(beat_pulse)
    rect(scr, HIGHWAY_X - pr - 2, HIT_Y - pr - 5, LANE_COUNT * LANE_W + pr * 2 + 4, pr * 2 + 10, math.floor(beat_pulse) + 1)
  end

  -- Draw lane backgrounds
  for lane = 1, 4 do
    local lx = HIGHWAY_X + (lane - 1) * LANE_W

    local lane_bg = C_LANE_BG
    if lane_flash[lane] > 0 then
      lane_bg = lane_flash[lane] + 2
    end
    rectf(scr, lx, 0, LANE_W - 1, H, lane_bg)

    -- Lane divider lines
    if lane < 4 then
      line(scr, lx + LANE_W - 1, 0, lx + LANE_W - 1, H, C_LANE_LINE)
    end
  end

  -- Outer lane borders
  line(scr, HIGHWAY_X - 1, 0, HIGHWAY_X - 1, H, C_LANE_LINE + 1)
  line(scr, HIGHWAY_X + LANE_COUNT * LANE_W, 0, HIGHWAY_X + LANE_COUNT * LANE_W, H, C_LANE_LINE + 1)

  -- Hit zone line with glow effect
  local hz_c = C_HIT_ZONE
  if beat_pulse > 0 then hz_c = hz_c + math.floor(beat_pulse) end
  if hz_c > 15 then hz_c = 15 end
  line(scr, HIGHWAY_X - 1, HIT_Y, HIGHWAY_X + LANE_COUNT * LANE_W, HIT_Y, hz_c)
  line(scr, HIGHWAY_X - 1, HIT_Y + NOTE_H, HIGHWAY_X + LANE_COUNT * LANE_W, HIT_Y + NOTE_H, hz_c)
  -- Subtle glow lines above/below hit zone
  if hz_c > 4 then
    line(scr, HIGHWAY_X - 1, HIT_Y - 1, HIGHWAY_X + LANE_COUNT * LANE_W, HIT_Y - 1, math.floor(hz_c * 0.4))
    line(scr, HIGHWAY_X - 1, HIT_Y + NOTE_H + 1, HIGHWAY_X + LANE_COUNT * LANE_W, HIT_Y + NOTE_H + 1, math.floor(hz_c * 0.4))
  end

  -- Hit zone target markers
  for lane = 1, 4 do
    local lx = HIGHWAY_X + (lane - 1) * LANE_W
    local tc = 5
    if lane_flash[lane] > 0 then
      tc = 10 + lane_flash[lane]
      if tc > 15 then tc = 15 end
    end
    rect(scr, lx + 1, HIT_Y, LANE_W - 3, NOTE_H, tc)
    text(scr, LANE_LABELS[lane], lx + 7, HIT_Y + 1, tc)
  end

  -- Draw active notes
  for _, n in ipairs(active_notes) do
    if not n.hit then
      local lx = HIGHWAY_X + (n.lane - 1) * LANE_W
      local ny = math.floor(n.y)

      -- Brightness based on distance to hit zone
      local dist = math.abs(ny - HIT_Y)
      local brightness
      if dist < 15 then
        brightness = C_NOTE_BRIGHT
      elseif dist < 40 then
        brightness = C_NOTE_MID
      else
        brightness = C_NOTE_DIM
      end

      if n.missed then
        brightness = 3
      end

      -- Draw note body
      rectf(scr, lx + 1, ny, LANE_W - 3, NOTE_H, brightness)
      -- Note highlight (top edge brighter)
      line(scr, lx + 2, ny, lx + LANE_W - 4, ny, math.min(brightness + 2, 15))
      -- Bottom shadow
      line(scr, lx + 2, ny + NOTE_H - 1, lx + LANE_W - 4, ny + NOTE_H - 1, math.max(brightness - 3, 1))
    else
      -- Hit note: flash and fade
      local lx = HIGHWAY_X + (n.lane - 1) * LANE_W
      local ny = math.floor(n.y)
      if n.hit_color > 3 then
        -- Expanding flash effect
        local expand = math.floor((15 - n.hit_color) * 0.5)
        rectf(scr, lx + 1 - expand, ny - expand, LANE_W - 3 + expand * 2, NOTE_H + expand * 2, n.hit_color)
      end
    end
  end

  -- Draw particles
  for _, p in ipairs(particles) do
    local px = math.floor(p.x)
    local py = math.floor(p.y)
    if px >= 0 and px < W and py >= 0 and py < H then
      local pc = math.floor(p.c * p.life / 15)
      if pc < 1 then pc = 1 end
      if pc > 15 then pc = 15 end
      pix(scr, px, py, pc)
      if p.life > 10 then
        if px + 1 < W then pix(scr, px + 1, py, math.floor(pc * 0.7)) end
        if py + 1 < H then pix(scr, px, py + 1, math.floor(pc * 0.5)) end
      end
    end
  end

  -- HUD: Score (left side)
  text(scr, tostring(score), 1, 2, C_TEXT)

  -- Combo (right side)
  if combo >= 2 then
    local combo_c = C_COMBO
    if combo >= 50 then
      combo_c = math.floor(song_time / 3) % 2 == 0 and 15 or 12
    end
    text(scr, combo .. "x", W - 25, 2, combo_c)
  end

  -- Multiplier indicator
  local mult = 1 + math.floor(combo / 10)
  if mult > 1 then
    text(scr, "x" .. mult, W - 25, 10, 10)
  end

  -- Judgment text (center, below highway)
  if judgment_timer > 0 then
    local jx = W / 2
    local jy = HIT_Y + 10
    local bounce = 0
    if judgment_timer > 15 then
      bounce = (20 - judgment_timer) * 0.5
    end
    -- Shadow for readability
    text(scr, judgment_text, jx - #judgment_text * 2 + 1, jy + math.floor(bounce) + 1, math.floor(judgment_color * 0.3))
    text(scr, judgment_text, jx - #judgment_text * 2, jy + math.floor(bounce), judgment_color)
  end

  -- Song progress bar at very top
  local progress = 0
  if #chart > 0 then
    progress = math.min(1, song_time / (chart[#chart].frame + 60))
  end
  local prog_w = math.floor(W * progress)
  rectf(scr, 0, 0, prog_w, 1, 4)
end

local function play_draw()
  local scr = screen()
  play_draw_inner()

  -- Pause overlay
  if paused then
    rectf(scr, 30, 40, 100, 40, 0)
    rect(scr, 30, 40, 100, 40, 10)
    text(scr, "PAUSED", 56, 48, 15)
    text(scr, "SELECT:RESUME", 36, 60, 7)
    text(scr, "B:QUIT", 56, 70, 7)
  end
end

----------------------------------------------------------------
-- RESULTS
----------------------------------------------------------------
function calculate_results()
  local total = perfects + greats + goods + misses
  if total == 0 then total = 1 end
  local accuracy = (perfects * 3 + greats * 2 + goods * 1) / (total * 3)
  if accuracy >= 0.95 and misses == 0 then
    result_grade = "S"
  elseif accuracy >= 0.9 then
    result_grade = "A"
  elseif accuracy >= 0.75 then
    result_grade = "B"
  elseif accuracy >= 0.6 then
    result_grade = "C"
  else
    result_grade = "D"
  end
  result_timer = 0
  -- Play result sound
  if result_grade == "S" or result_grade == "A" then
    note(0, "C5", 4)
    note(1, "E5", 4)
    note(2, "G5", 4)
  else
    note(0, "C4", 4)
    note(1, "E4", 4)
  end
end

local function results_update()
  result_timer = result_timer + 1

  if result_timer > 30 then
    if btnp("a") or btnp("start") or touch_start() then
      scene = "select"
      note(0, "C5", 2)
      note(1, "E5", 2)
    end
    if btnp("b") then
      scene = "select"
      note(0, "C4", 1)
    end
  end
end

local function results_draw()
  local scr = screen()
  cls(scr, 0)

  -- Title
  text(scr, "RESULTS", 55, 4, 15)
  line(scr, 20, 12, 140, 12, 5)

  -- Song name
  text(scr, song.name, 10, 17, 10)

  -- Grade (big and centered)
  local grade_c = 15
  if result_grade == "S" then
    grade_c = math.floor(result_timer / 4) % 2 == 0 and 15 or 12
  elseif result_grade == "D" then
    grade_c = 6
  end

  -- Draw grade large
  local gx = 120
  local gy = 22
  text(scr, result_grade, gx, gy, grade_c)
  text(scr, result_grade, gx - 1, gy, grade_c)
  text(scr, result_grade, gx + 1, gy, grade_c)
  text(scr, result_grade, gx, gy - 1, grade_c)

  -- Score
  text(scr, "SCORE", 10, 35, 7)
  text(scr, tostring(score), 60, 35, 15)

  -- Max combo
  text(scr, "MAX COMBO", 10, 45, 7)
  text(scr, tostring(max_combo), 80, 45, 12)

  -- Judgment breakdown
  local by = 58
  text(scr, "PERFECT", 10, by, C_PERFECT)
  text(scr, tostring(perfects), 70, by, C_PERFECT)

  text(scr, "GREAT", 10, by + 10, C_GREAT)
  text(scr, tostring(greats), 70, by + 10, C_GREAT)

  text(scr, "GOOD", 10, by + 20, C_GOOD)
  text(scr, tostring(goods), 70, by + 20, C_GOOD)

  text(scr, "MISS", 10, by + 30, C_MISS)
  text(scr, tostring(misses), 70, by + 30, C_MISS)

  -- Accuracy bar
  local total = perfects + greats + goods + misses
  if total > 0 then
    local acc = math.floor((perfects + greats * 0.8 + goods * 0.5) / total * 100)
    text(scr, "ACCURACY", 10, by + 42, 7)
    text(scr, acc .. "%", 70, by + 42, 10)
    -- Visual bar
    rectf(scr, 10, by + 50, 100, 4, 3)
    local bar_w = math.floor(acc)
    if bar_w > 0 then
      rectf(scr, 10, by + 50, bar_w, 4, 10)
    end
  end

  -- Continue prompt
  if result_timer > 30 then
    local blink = math.floor(result_timer / 15) % 2
    if blink == 0 then
      text(scr, "PRESS A", 55, 113, 7)
    end
  end
end

----------------------------------------------------------------
-- MAIN UPDATE / DRAW DISPATCH
----------------------------------------------------------------
function _update()
  if scene == "title" then
    title_update()
  elseif scene == "select" then
    select_update()
  elseif scene == "play" then
    play_update()
  elseif scene == "results" then
    results_update()
  elseif scene == "attract" then
    attract_update()
  end
end

function _draw()
  if scene == "title" then
    title_draw()
  elseif scene == "select" then
    select_draw()
  elseif scene == "play" then
    play_draw()
  elseif scene == "results" then
    results_draw()
  elseif scene == "attract" then
    attract_draw()
  end
end
