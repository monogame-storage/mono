-- Synth Playground Demo
-- Covers: wave (+ reinforces note, tone, noise, sfx_stop)
--
-- Controls:
--   LEFT/RIGHT : select key (C, D, E, F, G, A, B, C+)
--   A          : play note on current waveform
--   B          : cycle waveform (square → sine → triangle → sawtooth)
--   UP         : play a short tone sweep
--   DOWN       : play a noise burst
--   START      : stop all audio

local scr = screen()

local WAVES = { "square", "sine", "triangle", "sawtooth" }
local NOTES = { "C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5" }
local KEY_LABELS = { "C", "D", "E", "F", "G", "A", "B", "C+" }

local selected = 1
local wave_idx = 1
local last_action_t = 0
local last_action_msg = ""

function _init()
  mode(4)
end

function _start()
  wave(0, WAVES[wave_idx])
  wave(1, WAVES[wave_idx])
end

local function set_action(msg)
  last_action_msg = msg
  last_action_t = 60
end

function _update()
  -- Attract mode: if no input for a while, auto-play a loop
  -- Cycles through note → tone → noise → wave change → sfx_stop
  if frame() == 5 then
    note(0, "C4", 0.15)
    set_action("AUTO NOTE")
  elseif frame() == 15 then
    tone(1, 400, 1800, 0.2)
    set_action("AUTO SWEEP")
  elseif frame() == 25 then
    noise(1, 0.15, "high", 1200)
    set_action("AUTO NOISE")
  elseif frame() == 35 then
    wave_idx = (wave_idx % #WAVES) + 1
    wave(0, WAVES[wave_idx])
    wave(1, WAVES[wave_idx])
    set_action("AUTO WAVE")
  elseif frame() == 45 then
    sfx_stop()
    set_action("AUTO STOP")
  end

  if btnp("left") then
    selected = selected - 1
    if selected < 1 then selected = #NOTES end
  elseif btnp("right") then
    selected = selected + 1
    if selected > #NOTES then selected = 1 end
  end

  if btnp("b") then
    wave_idx = wave_idx + 1
    if wave_idx > #WAVES then wave_idx = 1 end
    wave(0, WAVES[wave_idx])
    wave(1, WAVES[wave_idx])
    set_action("WAVE " .. WAVES[wave_idx])
  end

  if btnp("a") then
    note(0, NOTES[selected], 0.25)
    set_action("NOTE " .. KEY_LABELS[selected])
  end

  if btnp("up") then
    tone(1, 400, 2000, 0.3)
    set_action("SWEEP UP")
  elseif btnp("down") then
    noise(1, 0.2, "low", 600)
    set_action("NOISE")
  end

  if btnp("start") then
    sfx_stop()
    set_action("STOP ALL")
  end

  if last_action_t > 0 then last_action_t = last_action_t - 1 end
end

function _draw()
  cls(scr, 0)

  -- Title
  text(scr, "SYNTH", 0, 4, 15, ALIGN_HCENTER)

  -- Waveform label
  text(scr, WAVES[wave_idx], 0, 20, 11, ALIGN_HCENTER)

  -- Waveform visualization
  local vy = 30
  local vh = 20
  local vw = 140
  local vx = (SCREEN_W - vw) / 2
  rect(scr, vx, vy, vw, vh, 6)
  for i = 0, vw - 1 do
    local t = i / vw * math.pi * 4
    local v
    if WAVES[wave_idx] == "square" then
      v = math.sin(t) >= 0 and 1 or -1
    elseif WAVES[wave_idx] == "sine" then
      v = math.sin(t)
    elseif WAVES[wave_idx] == "triangle" then
      local p = (t / math.pi) % 2
      v = p < 1 and (p * 2 - 1) or (3 - p * 2)
    else  -- sawtooth
      v = ((t / math.pi) % 2) - 1
    end
    local py = vy + vh / 2 - v * (vh / 2 - 1)
    pix(scr, vx + i, math.floor(py), 14)
  end

  -- Piano keys
  local kw = 16
  local ky = 70
  local kh = 30
  for i = 1, #NOTES do
    local kx = (i - 1) * kw + 16
    local color = (i == selected) and 14 or 15
    rectf(scr, kx, ky, kw - 1, kh, color)
    rect(scr, kx, ky, kw - 1, kh, 8)
    text(scr, KEY_LABELS[i], kx + 2, ky + 10, 0)
  end

  -- Instructions
  text(scr, "A:PLAY  B:WAVE", 0, 110, 11, ALIGN_HCENTER)
  text(scr, "UP:SWEEP  DOWN:NOISE", 0, 120, 11, ALIGN_HCENTER)

  if last_action_t > 0 then
    text(scr, last_action_msg, 0, SCREEN_H - 8, 14, ALIGN_HCENTER)
  end
end
