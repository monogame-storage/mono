-- CHECK RHYTHM
-- Chess attack patterns become rhythm beats
-- Match the direction when the beat hits the zone!

------------------------------------------------------------
-- CONSTANTS
------------------------------------------------------------
local W = 160
local H = 120
local STRIKE_X = 24          -- x position of the strike zone
local BEAT_SPEED = 1.2        -- pixels per frame a beat travels
local BEAT_START_X = 164      -- beats spawn off-screen right
local PERFECT_WIN = 4         -- pixels tolerance for perfect
local GOOD_WIN = 10           -- pixels tolerance for good
local HIT_WIN = 16            -- pixels tolerance for hit at all
local BPM = 120
local FRAMES_PER_BEAT = 30    -- at ~30fps, 120 BPM = 1 beat/0.5s
local IDLE_TO_DEMO = 150      -- frames before demo mode

-- direction constants
local DIR_UP = 1
local DIR_DOWN = 2
local DIR_LEFT = 3
local DIR_RIGHT = 4

-- direction names for display
local DIR_NAMES = { "UP", "DN", "LT", "RT" }

-- arrow offsets (dx, dy) for drawing
local DIR_DX = { 0, 0, -1, 1 }
local DIR_DY = { -1, 1, 0, 0 }

------------------------------------------------------------
-- CHESS PATTERNS
------------------------------------------------------------
-- Each pattern: name, sequence of {offset_in_beats, direction, is_check}
-- piece_type: 1=pawn, 2=knight, 3=bishop, 4=rook, 5=queen
local PATTERNS = {}

-- Pawn March: steady up beats
PATTERNS[1] = {
  name = "PAWN MARCH",
  notes = "C4",
  piece = 1,
  beats = {
    {0, DIR_UP, false},
    {1, DIR_UP, false},
    {2, DIR_UP, false},
    {3, DIR_UP, false},
  }
}

-- Knight Fork: syncopated L-shapes
PATTERNS[2] = {
  name = "KNIGHT FORK",
  notes = "E4",
  piece = 2,
  beats = {
    {0, DIR_UP, false},
    {0.5, DIR_RIGHT, false},
    {2, DIR_DOWN, false},
    {2.5, DIR_LEFT, false},
  }
}

-- Bishop Slide: diagonal sequences
PATTERNS[3] = {
  name = "BISHOP SLIDE",
  notes = "G4",
  piece = 3,
  beats = {
    {0, DIR_UP, false},
    {0.75, DIR_RIGHT, false},
    {1.5, DIR_DOWN, false},
    {2.25, DIR_LEFT, false},
  }
}

-- Rook Charge: rapid same-direction
PATTERNS[4] = {
  name = "ROOK CHARGE",
  notes = "A4",
  piece = 4,
  beats = {
    {0, DIR_RIGHT, false},
    {0.5, DIR_RIGHT, false},
    {1, DIR_RIGHT, false},
    {1.5, DIR_RIGHT, true},
  }
}

-- Queen Sweep: all four directions fast
PATTERNS[5] = {
  name = "QUEEN SWEEP",
  notes = "B4",
  piece = 5,
  beats = {
    {0, DIR_UP, false},
    {0.5, DIR_RIGHT, false},
    {1, DIR_DOWN, false},
    {1.5, DIR_LEFT, false},
    {2, DIR_UP, true},
  }
}

-- Double Check: pairs close together
PATTERNS[6] = {
  name = "DOUBLE CHECK",
  notes = "D5",
  piece = 2,
  beats = {
    {0, DIR_LEFT, false},
    {0.25, DIR_RIGHT, false},
    {1.5, DIR_UP, false},
    {1.75, DIR_DOWN, true},
    {3, DIR_LEFT, false},
    {3.25, DIR_RIGHT, true},
  }
}

-- Discovered Check: surprise beat after pause
PATTERNS[7] = {
  name = "DISCOVERED CHECK",
  notes = "F4",
  piece = 3,
  beats = {
    {0, DIR_UP, false},
    {1, DIR_RIGHT, false},
    {2, DIR_DOWN, false},
    {3.75, DIR_LEFT, true},  -- surprise late beat
  }
}

-- Checkmate Finale: intense
PATTERNS[8] = {
  name = "CHECKMATE",
  notes = "C5",
  piece = 5,
  beats = {
    {0, DIR_UP, false},
    {0.5, DIR_DOWN, false},
    {1, DIR_LEFT, false},
    {1.5, DIR_RIGHT, false},
    {2, DIR_UP, true},
    {2.5, DIR_DOWN, true},
    {3, DIR_LEFT, false},
    {3.25, DIR_RIGHT, false},
    {3.5, DIR_UP, true},
  }
}

------------------------------------------------------------
-- GLOBAL STATE
------------------------------------------------------------
local beats = {}          -- active beats on screen
local score = 0
local combo = 0
local max_combo = 0
local hi_score = 0
local perfect_count = 0
local good_count = 0
local miss_count = 0
local total_beats = 0
local beat_timer = 0      -- counts frames for rhythm
local pattern_idx = 1
local pattern_beat = 1    -- next beat index in current pattern
local pattern_start = 0   -- frame when current pattern started
local next_pattern_frame = 0
local level = 1
local game_over = false
local health = 10
local max_health = 10
local flash_timer = 0
local flash_type = 0      -- 0=none, 1=perfect, 2=good, 3=miss
local check_flash = 0
local feedback_text = ""
local feedback_timer = 0
local paused = false
local pattern_name_timer = 0
local current_pattern_name = ""

-- visual effects
local pulse = 0
local board_offset = 0
local particles = {}

-- demo/attract mode
local demo_mode = false
local demo_timer = 0
local idle_timer = 0
local title_anim = 0

-- music state
local music_tick = 0
local bass_pattern = {1, 0, 0, 1, 0, 1, 0, 0}
local bass_idx = 1
local melody_notes = {"C4", "E4", "G4", "C5", "G4", "E4", "C4", "E4"}
local melody_idx = 1

------------------------------------------------------------
-- 7-SEGMENT CLOCK
------------------------------------------------------------
local SEG7 = {
  [0] = 63, [1] = 6, [2] = 91, [3] = 79, [4] = 102,
  [5] = 109, [6] = 125, [7] = 7, [8] = 127, [9] = 111,
}

local function draw_seg7(s, digit, ox, oy, col)
  local segs = SEG7[digit] or 0
  if segs % 2 >= 1 then rectf(s, ox+1, oy, 4, 1, col) end
  if math.floor(segs/2) % 2 == 1 then rectf(s, ox+5, oy+1, 1, 3, col) end
  if math.floor(segs/4) % 2 == 1 then rectf(s, ox+5, oy+5, 1, 3, col) end
  if math.floor(segs/8) % 2 == 1 then rectf(s, ox+1, oy+8, 4, 1, col) end
  if math.floor(segs/16) % 2 == 1 then rectf(s, ox, oy+5, 1, 3, col) end
  if math.floor(segs/32) % 2 == 1 then rectf(s, ox, oy+1, 1, 3, col) end
  if math.floor(segs/64) % 2 == 1 then rectf(s, ox+1, oy+4, 4, 1, col) end
end

local function draw_clock7(s, ox, oy, col)
  local d = date()
  local h = d.hour
  local m = d.min
  draw_seg7(s, math.floor(h/10), ox, oy, col)
  draw_seg7(s, h%10, ox+8, oy, col)
  if math.floor(frame()/30) % 2 == 0 then
    rectf(s, ox+16, oy+2, 1, 1, col)
    rectf(s, ox+16, oy+6, 1, 1, col)
  end
  draw_seg7(s, math.floor(m/10), ox+19, oy, col)
  draw_seg7(s, m%10, ox+27, oy, col)
end

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function spawn_particle(x, y, typ)
  for i = 1, 6 do
    local angle = math.random() * 6.28
    local spd = 0.5 + math.random() * 2
    particles[#particles+1] = {
      x = x, y = y,
      vx = math.cos(angle) * spd,
      vy = math.sin(angle) * spd,
      life = 12 + math.random(8),
      typ = typ,
    }
  end
end

local function update_particles()
  local alive = {}
  for _, p in ipairs(particles) do
    p.x = p.x + p.vx
    p.y = p.y + p.vy
    p.life = p.life - 1
    if p.life > 0 then
      alive[#alive+1] = p
    end
  end
  particles = alive
end

------------------------------------------------------------
-- SOUND ENGINE
------------------------------------------------------------
local function play_bass_tick()
  music_tick = music_tick + 1
  if music_tick % math.floor(FRAMES_PER_BEAT * 0.5) == 0 then
    bass_idx = (bass_idx % #bass_pattern) + 1
    if bass_pattern[bass_idx] == 1 then
      wave(0, 2)  -- square wave bass
      note(0, "C2", 4)
    end
  end
end

local function play_melody_tick()
  if music_tick % FRAMES_PER_BEAT == 0 then
    melody_idx = (melody_idx % #melody_notes) + 1
    wave(1, 1)  -- triangle melody
    note(1, melody_notes[melody_idx], 3)
  end
end

local function play_hihat()
  if music_tick % math.floor(FRAMES_PER_BEAT * 0.25) == 0 then
    noise(2, 0.03)
  end
end

local function play_perfect_sound()
  wave(3, 0)  -- sine
  note(3, "C5", 2)
  note(3, "E5", 2)
  note(3, "G5", 2)
end

local function play_good_sound()
  wave(3, 1)  -- triangle
  note(3, "E4", 2)
end

local function play_miss_sound()
  tone(3, 150, 80, 0.15)
  noise(3, 0.1)
end

local function play_check_sound()
  wave(3, 2)  -- square
  note(3, "G5", 3)
  noise(2, 0.08)
  tone(2, 800, 1200, 0.15)
end

local function play_pattern_start_sound(pat_notes)
  wave(1, 0)
  note(1, pat_notes, 4)
end

------------------------------------------------------------
-- BEAT MANAGEMENT
------------------------------------------------------------
local function queue_pattern(pat_id)
  local pat = PATTERNS[pat_id]
  if not pat then return end
  current_pattern_name = pat.name
  pattern_name_timer = 60

  play_pattern_start_sound(pat.notes)

  local travel_frames = (BEAT_START_X - STRIKE_X) / BEAT_SPEED
  for _, b in ipairs(pat.beats) do
    local beat_frame = b[1] * FRAMES_PER_BEAT
    local spawn_delay = beat_frame  -- delay before spawning this beat
    beats[#beats+1] = {
      x = BEAT_START_X + spawn_delay * BEAT_SPEED,
      y = 60,  -- center lane
      dir = b[2],
      is_check = b[3],
      piece = b[3] and 6 or pat.piece,  -- check beats become king
      hit = false,
      missed = false,
      spawn_frame = frame() + spawn_delay,
      active = true,
    }
    total_beats = total_beats + 1
  end
end

local function choose_next_pattern()
  -- difficulty ramps up: early patterns are simpler
  local max_pat = clamp(math.floor(level / 2) + 2, 2, #PATTERNS)
  local choice = math.random(1, max_pat)
  -- occasionally force harder patterns at higher levels
  if level >= 4 and math.random() < 0.3 then
    choice = math.random(math.floor(max_pat * 0.6), max_pat)
  end
  return choice
end

------------------------------------------------------------
-- DRAWING HELPERS
------------------------------------------------------------
local function draw_arrow(s, cx, cy, dir, size, col)
  local sz = size or 4
  if dir == DIR_UP then
    line(s, cx, cy - sz, cx - sz, cy + sz, col)
    line(s, cx, cy - sz, cx + sz, cy + sz, col)
    line(s, cx - sz, cy + sz, cx + sz, cy + sz, col)
  elseif dir == DIR_DOWN then
    line(s, cx, cy + sz, cx - sz, cy - sz, col)
    line(s, cx, cy + sz, cx + sz, cy - sz, col)
    line(s, cx - sz, cy - sz, cx + sz, cy - sz, col)
  elseif dir == DIR_LEFT then
    line(s, cx - sz, cy, cx + sz, cy - sz, col)
    line(s, cx - sz, cy, cx + sz, cy + sz, col)
    line(s, cx + sz, cy - sz, cx + sz, cy + sz, col)
  elseif dir == DIR_RIGHT then
    line(s, cx + sz, cy, cx - sz, cy - sz, col)
    line(s, cx + sz, cy, cx - sz, cy + sz, col)
    line(s, cx - sz, cy - sz, cx - sz, cy + sz, col)
  end
end

local function draw_filled_arrow(s, cx, cy, dir, size, col)
  local sz = size or 4
  if dir == DIR_UP then
    for i = 0, sz do
      local w = math.floor(i * sz / sz)
      line(s, cx - w, cy - sz + i * 2, cx + w, cy - sz + i * 2, col)
    end
  elseif dir == DIR_DOWN then
    for i = 0, sz do
      local w = math.floor(i * sz / sz)
      line(s, cx - w, cy + sz - i * 2, cx + w, cy + sz - i * 2, col)
    end
  elseif dir == DIR_LEFT then
    for i = 0, sz do
      local h = math.floor(i * sz / sz)
      line(s, cx - sz + i * 2, cy - h, cx - sz + i * 2, cy + h, col)
    end
  elseif dir == DIR_RIGHT then
    for i = 0, sz do
      local h = math.floor(i * sz / sz)
      line(s, cx + sz - i * 2, cy - h, cx + sz - i * 2, cy + h, col)
    end
  end
end

-- Draw a small chess piece silhouette
local function draw_piece(s, cx, cy, piece_type, col)
  -- piece_type: 1=pawn, 2=knight, 3=bishop, 4=rook, 5=queen, 6=king
  if piece_type == 1 then -- pawn
    circf(s, cx, cy - 2, 2, col)
    rectf(s, cx - 2, cy + 1, 5, 2, col)
  elseif piece_type == 2 then -- knight
    rectf(s, cx - 1, cy - 3, 3, 6, col)
    rectf(s, cx, cy - 4, 3, 2, col)
    rectf(s, cx - 2, cy + 1, 5, 2, col)
  elseif piece_type == 3 then -- bishop
    pix(s, cx, cy - 4, col)
    circf(s, cx, cy - 2, 2, col)
    rectf(s, cx - 2, cy + 1, 5, 2, col)
  elseif piece_type == 4 then -- rook
    rectf(s, cx - 3, cy - 3, 2, 2, col)
    rectf(s, cx - 1, cy - 3, 3, 2, col)
    rectf(s, cx + 2, cy - 3, 2, 2, col)
    rectf(s, cx - 2, cy - 1, 5, 4, col)
    rectf(s, cx - 3, cy + 1, 7, 2, col)
  elseif piece_type == 5 then -- queen
    pix(s, cx, cy - 5, col)
    pix(s, cx - 2, cy - 4, col)
    pix(s, cx + 2, cy - 4, col)
    circf(s, cx, cy - 2, 2, col)
    rectf(s, cx - 2, cy, 5, 3, col)
  elseif piece_type == 6 then -- king
    rectf(s, cx - 1, cy - 5, 3, 1, col)
    rectf(s, cx, cy - 6, 1, 3, col)
    circf(s, cx, cy - 2, 2, col)
    rectf(s, cx - 2, cy, 5, 3, col)
  end
end

-- Chess board background scrolling - full chessboard feel
local function draw_board_bg(s)
  board_offset = (board_offset + 0.3) % 16
  local ox = -math.floor(board_offset)
  local sq = 8  -- square size
  for gx = ox, W + sq, sq do
    for gy = 0, H, sq do
      local cx = math.floor((gx - ox) / sq)
      local cy = math.floor(gy / sq)
      if (cx + cy) % 2 == 1 then
        -- light squares: dithered fill (1-bit friendly)
        for dx = 0, sq - 1 do
          for dy = 0, sq - 1 do
            local px = gx + dx
            local py = gy + dy
            if px >= 0 and px < W and py >= 0 and py < H then
              if (dx + dy) % 2 == 0 then
                pix(s, px, py, 1)
              end
            end
          end
        end
      end
      -- draw square borders for chess grid
      local bx = gx
      local by = gy
      if bx >= 0 and bx < W and by >= 0 and by < H then
        -- right edge
        if bx + sq - 1 < W then
          for dy = 0, sq - 1 do
            if by + dy < H and (cx + cy) % 2 == 0 then
              pix(s, bx + sq - 1, by + dy, 1)
            end
          end
        end
      end
    end
  end
  -- horizontal rank lines across full width
  for gy = 0, H, sq do
    if gy > 0 and gy < H then
      for lx = 0, W - 1, 2 do
        pix(s, lx, gy, 1)
      end
    end
  end
end

-- Strike zone visual - chess rank line
local function draw_strike_zone(s)
  local pulse_r = math.floor(math.sin(pulse) * 2)
  local y = 60
  -- vertical rank line spanning the play area
  for ly = 12, H - 12 do
    pix(s, STRIKE_X, ly, 1)
    pix(s, STRIKE_X + 1, ly, 1)
  end
  -- battlement/crenellation marks along the rank line (like a rook top)
  for ly = 12, H - 12, 6 do
    rectf(s, STRIKE_X - 2, ly, 6, 2, 1)
  end
  -- pulsing bracket at center
  local bh = 10 + pulse_r
  rectf(s, STRIKE_X - 3, y - bh, 2, bh * 2, 1)
  rectf(s, STRIKE_X + 3, y - bh, 2, bh * 2, 1)
  rectf(s, STRIKE_X - 3, y - bh, 8, 2, 1)
  rectf(s, STRIKE_X - 3, y + bh - 1, 8, 2, 1)
  -- direction arrows at the four lane positions
  draw_arrow(s, STRIKE_X, y - 14, DIR_UP, 3, 1)
  draw_arrow(s, STRIKE_X, y + 14, DIR_DOWN, 3, 1)
  draw_arrow(s, STRIKE_X - 8, y, DIR_LEFT, 3, 1)
  draw_arrow(s, STRIKE_X + 10, y, DIR_RIGHT, 3, 1)
end

-- Draw a single beat marker as a chess piece on a mini-square
local function draw_beat(s, b)
  if not b.active then return end
  if b.hit then return end

  local bx = b.x
  local by = 60
  -- offset vertically based on direction
  local dy_off = 0
  if b.dir == DIR_UP then dy_off = -14
  elseif b.dir == DIR_DOWN then dy_off = 14
  elseif b.dir == DIR_LEFT then dy_off = 0
  elseif b.dir == DIR_RIGHT then dy_off = 0
  end

  local col = 1
  if b.is_check then
    -- check beats flash
    if math.floor(frame() / 4) % 2 == 0 then
      col = 1
    else
      col = 0
    end
  end

  local mx = math.floor(bx)
  local my = by + dy_off

  -- draw a small chess square base under the piece
  rect(s, mx - 5, my - 5, 11, 11, col)

  -- draw connecting track line from piece to strike zone
  if bx < BEAT_START_X - 10 then
    for lx = math.max(STRIKE_X + 12, mx - 10), mx - 7 do
      if lx % 3 == 0 and lx >= 0 and lx < W then
        pix(s, lx, my, col)
      end
    end
  end

  -- draw the chess piece silhouette (piece type determines shape)
  local pt = b.piece or 1
  draw_piece(s, mx, my, pt, col)

  -- small direction indicator arrow below/beside the piece
  local ax, ay = mx, my + 7
  if b.dir == DIR_UP then ax, ay = mx, my - 7 end
  if b.dir == DIR_LEFT then ax, ay = mx - 7, my end
  if b.dir == DIR_RIGHT then ax, ay = mx + 7, my end
  draw_arrow(s, ax, ay, b.dir, 2, col)

  if b.missed then
    -- X mark over the piece
    line(s, mx - 4, my - 4, mx + 4, my + 4, 1)
    line(s, mx + 4, my - 4, mx - 4, my + 4, 1)
  end
end

------------------------------------------------------------
-- INPUT HELPERS
------------------------------------------------------------
local function get_touch_dir()
  local tx, ty = touch_pos()
  if tx == nil then return nil end
  -- divide screen into quadrants
  local cx, cy = W / 2, H / 2
  local dx = tx - cx
  local dy = ty - cy
  if math.abs(dx) > math.abs(dy) then
    if dx < 0 then return DIR_LEFT else return DIR_RIGHT end
  else
    if dy < 0 then return DIR_UP else return DIR_DOWN end
  end
end

local function get_input_dir()
  if btnp("up") then return DIR_UP end
  if btnp("down") then return DIR_DOWN end
  if btnp("left") then return DIR_LEFT end
  if btnp("right") then return DIR_RIGHT end
  -- check touch
  if touch_start() then
    return get_touch_dir()
  end
  return nil
end

local function any_press()
  return btnp("start") or btnp("a") or btnp("b") or
         btnp("up") or btnp("down") or btnp("left") or btnp("right") or
         touch_start()
end

------------------------------------------------------------
-- INIT
------------------------------------------------------------
function _init()
  mode(1)
  hi_score = 0
end

function _start()
  go("title")
end

------------------------------------------------------------
-- TITLE SCENE
------------------------------------------------------------
function title_init()
  title_anim = 0
  idle_timer = 0
  demo_mode = false
  demo_timer = 0
  beats = {}
  particles = {}
  music_tick = 0
end

function title_update()
  title_anim = title_anim + 1

  if any_press() then
    if demo_mode then
      demo_mode = false
      idle_timer = 0
      beats = {}
      particles = {}
      return
    end
    go("game")
    return
  end

  -- enter demo after idle
  if not demo_mode then
    idle_timer = idle_timer + 1
    if idle_timer >= IDLE_TO_DEMO then
      demo_mode = true
      demo_timer = 0
      -- set up demo beats
      beats = {}
      particles = {}
      score = 0
      combo = 0
      music_tick = 0
      pattern_idx = 1
      next_pattern_frame = frame() + 30
      total_beats = 0
    end
  else
    demo_timer = demo_timer + 1

    -- background music in demo
    play_bass_tick()
    play_melody_tick()
    play_hihat()

    -- spawn patterns
    if frame() >= next_pattern_frame then
      queue_pattern(((pattern_idx - 1) % #PATTERNS) + 1)
      pattern_idx = pattern_idx + 1
      next_pattern_frame = frame() + FRAMES_PER_BEAT * 5
    end

    -- move beats and auto-hit
    for _, b in ipairs(beats) do
      if b.active and not b.hit then
        b.x = b.x - BEAT_SPEED
        -- auto-hit in demo
        if math.abs(b.x - STRIKE_X) < PERFECT_WIN then
          b.hit = true
          b.active = false
          combo = combo + 1
          score = score + 100 * combo
          spawn_particle(STRIKE_X, 60, 1)
          play_perfect_sound()
        end
        if b.x < -20 then
          b.active = false
        end
      end
    end

    update_particles()
    pulse = pulse + 0.12
    board_offset = (board_offset + 0.3) % 8

    -- reset demo after a while
    if demo_timer > 600 then
      demo_mode = false
      idle_timer = 0
      beats = {}
      particles = {}
    end
  end
end

function title_draw()
  local s = screen()
  cls(s, 0)

  if demo_mode then
    -- draw demo gameplay
    draw_board_bg(s)
    draw_strike_zone(s)
    for _, b in ipairs(beats) do
      draw_beat(s, b)
    end
    -- particles
    for _, p in ipairs(particles) do
      if p.life > 0 then
        pix(s, math.floor(p.x), math.floor(p.y), 1)
      end
    end

    -- clock overlay
    rectf(s, W/2 - 20, 2, 40, 13, 0)
    rect(s, W/2 - 20, 2, 40, 13, 1)
    draw_clock7(s, math.floor(W/2) - 17, 4, 1)

    -- demo label
    text(s, "DEMO", 2, 2, 1)
    text(s, "SCORE:" .. score, 2, H - 8, 1)
    text(s, "PRESS ANY KEY", W/2, H - 8, 1, ALIGN_CENTER)
  else
    -- title screen
    draw_board_bg(s)

    -- title panel
    local ty = 15 + math.floor(math.sin(title_anim * 0.05) * 3)
    rectf(s, 10, ty, 140, 30, 0)
    rect(s, 10, ty, 140, 30, 1)

    -- title text
    text(s, "CHECK", W/2, ty + 5, 1, ALIGN_CENTER)
    text(s, "RHYTHM", W/2, ty + 14, 1, ALIGN_CENTER)

    -- chess pieces decoration
    local pieces_y = ty + 34
    draw_piece(s, 30, pieces_y, 1, 1)
    draw_piece(s, 50, pieces_y, 2, 1)
    draw_piece(s, 70, pieces_y, 3, 1)
    draw_piece(s, 90, pieces_y, 4, 1)
    draw_piece(s, 110, pieces_y, 5, 1)
    draw_piece(s, 130, pieces_y, 6, 1)

    -- instructions
    local blink = math.floor(title_anim / 20) % 2
    if blink == 0 then
      text(s, "PRESS START", W/2, 80, 1, ALIGN_CENTER)
    end

    -- arrows showing directions
    draw_arrow(s, 60, 95, DIR_LEFT, 3, 1)
    draw_arrow(s, 80, 88, DIR_UP, 3, 1)
    draw_arrow(s, 80, 102, DIR_DOWN, 3, 1)
    draw_arrow(s, 100, 95, DIR_RIGHT, 3, 1)

    text(s, "MATCH THE BEAT!", W/2, 110, 1, ALIGN_CENTER)

    if hi_score > 0 then
      text(s, "HI:" .. hi_score, W/2, ty - 6, 1, ALIGN_CENTER)
    end
  end
end

------------------------------------------------------------
-- GAME SCENE
------------------------------------------------------------
function game_init()
  beats = {}
  score = 0
  combo = 0
  max_combo = 0
  perfect_count = 0
  good_count = 0
  miss_count = 0
  total_beats = 0
  beat_timer = 0
  pattern_idx = 1
  pattern_beat = 1
  pattern_start = frame()
  next_pattern_frame = frame() + FRAMES_PER_BEAT * 2
  level = 1
  game_over = false
  health = max_health
  flash_timer = 0
  flash_type = 0
  check_flash = 0
  feedback_text = ""
  feedback_timer = 0
  paused = false
  pulse = 0
  board_offset = 0
  particles = {}
  music_tick = 0
  bass_idx = 1
  melody_idx = 1
  pattern_name_timer = 0
  current_pattern_name = ""

  -- set up wave types
  wave(0, 2)  -- square bass
  wave(1, 1)  -- triangle melody
  wave(2, 3)  -- saw percussion accent
  wave(3, 0)  -- sine SFX

  -- queue first pattern
  queue_pattern(1)
  next_pattern_frame = frame() + FRAMES_PER_BEAT * 5
end

function game_update()
  if game_over then
    if any_press() then
      if score > hi_score then
        hi_score = score
      end
      go("title")
    end
    return
  end

  if btnp("start") then
    paused = not paused
    return
  end
  if paused then return end

  beat_timer = beat_timer + 1
  music_tick = music_tick + 1
  pulse = pulse + 0.12

  -- background music
  play_bass_tick()
  play_melody_tick()
  play_hihat()

  -- spawn new patterns
  if frame() >= next_pattern_frame then
    local pat_choice = choose_next_pattern()
    queue_pattern(pat_choice)
    -- time until next pattern depends on current pattern length
    local pat = PATTERNS[pat_choice]
    local last_beat_offset = 0
    for _, b in ipairs(pat.beats) do
      if b[1] > last_beat_offset then last_beat_offset = b[1] end
    end
    next_pattern_frame = frame() + FRAMES_PER_BEAT * (last_beat_offset + 3)

    -- level up every 5 patterns
    if pattern_idx % 5 == 0 then
      level = level + 1
      -- speed up slightly
      BEAT_SPEED = math.min(2.5, 1.2 + level * 0.1)
    end
    pattern_idx = pattern_idx + 1
  end

  -- move beats
  for _, b in ipairs(beats) do
    if b.active and not b.hit then
      b.x = b.x - BEAT_SPEED

      -- check if missed (past strike zone)
      if b.x < STRIKE_X - HIT_WIN and not b.missed then
        b.missed = true
        b.active = false
        miss_count = miss_count + 1
        combo = 0
        health = health - 1
        flash_type = 3
        flash_timer = 8
        feedback_text = "MISS"
        feedback_timer = 20
        play_miss_sound()

        if health <= 0 then
          game_over = true
          -- game over sound
          tone(0, 200, 60, 0.5)
          tone(1, 150, 40, 0.5)
          noise(2, 0.3)
          cam_shake()
        end
      end

      -- remove if way off screen
      if b.x < -30 then
        b.active = false
      end
    end
  end

  -- check player input
  local input_dir = get_input_dir()
  if input_dir then
    -- find closest unhit beat matching this direction
    local best_beat = nil
    local best_dist = HIT_WIN + 1
    for _, b in ipairs(beats) do
      if b.active and not b.hit and not b.missed and b.dir == input_dir then
        local dist = math.abs(b.x - STRIKE_X)
        if dist < best_dist then
          best_dist = dist
          best_beat = b
        end
      end
    end

    if best_beat then
      best_beat.hit = true
      best_beat.active = false
      local dist = best_dist

      if dist <= PERFECT_WIN then
        perfect_count = perfect_count + 1
        combo = combo + 1
        if combo > max_combo then max_combo = combo end
        local mult = math.min(combo, 10)
        score = score + 100 * mult
        flash_type = 1
        flash_timer = 6
        feedback_text = "PERFECT!"
        feedback_timer = 20
        play_perfect_sound()
        spawn_particle(STRIKE_X, 60, 1)
        if best_beat.is_check then
          check_flash = 15
          play_check_sound()
          score = score + 200 * mult
        end
      elseif dist <= GOOD_WIN then
        good_count = good_count + 1
        combo = combo + 1
        if combo > max_combo then max_combo = combo end
        local mult = math.min(combo, 10)
        score = score + 50 * mult
        flash_type = 2
        flash_timer = 4
        feedback_text = "GOOD"
        feedback_timer = 15
        play_good_sound()
        spawn_particle(STRIKE_X, 60, 2)
        if best_beat.is_check then
          check_flash = 10
          play_check_sound()
          score = score + 100 * mult
        end
      else
        -- hit but poor timing
        combo = combo + 1
        score = score + 20
        feedback_text = "OK"
        feedback_timer = 10
        tone(3, 300, 350, 0.05)
      end
    else
      -- pressed direction with no matching beat nearby
      -- small penalty
      combo = 0
      feedback_text = "?"
      feedback_timer = 8
      noise(3, 0.03)
    end
  end

  -- timers
  if flash_timer > 0 then flash_timer = flash_timer - 1 end
  if check_flash > 0 then check_flash = check_flash - 1 end
  if feedback_timer > 0 then feedback_timer = feedback_timer - 1 end
  if pattern_name_timer > 0 then pattern_name_timer = pattern_name_timer - 1 end

  update_particles()

  -- clean up old beats
  local alive = {}
  for _, b in ipairs(beats) do
    if b.active or (b.hit and true) or (b.x > -30) then
      -- keep for a moment for visual
      if b.x > -30 then
        alive[#alive+1] = b
        -- dead beats still drift left
        if not b.active then
          b.x = b.x - BEAT_SPEED
        end
      end
    end
  end
  beats = alive
end

function game_draw()
  local s = screen()

  -- flash background on hits
  if flash_timer > 0 and flash_type == 1 then
    cls(s, 1)
  else
    cls(s, 0)
  end

  -- check flash - invert colors briefly
  local check_invert = check_flash > 0 and math.floor(check_flash / 2) % 2 == 0

  -- chess board background
  draw_board_bg(s)

  -- lane guides as chess file lines
  local lane_y = 60
  -- dashed center rank
  for lx = 0, W - 1, 4 do
    if lx % 8 < 4 then
      pix(s, lx, lane_y, 1)
    end
  end
  -- upper and lower lane rank lines
  for lx = STRIKE_X, W - 1, 4 do
    if lx % 8 < 4 then
      pix(s, lx, lane_y - 14, 1)
      pix(s, lx, lane_y + 14, 1)
    end
  end

  -- strike zone
  draw_strike_zone(s)

  -- draw beats
  for _, b in ipairs(beats) do
    draw_beat(s, b)
  end

  -- particles
  for _, p in ipairs(particles) do
    if p.life > 0 then
      pix(s, math.floor(p.x), math.floor(p.y), 1)
      if p.life > 6 then
        pix(s, math.floor(p.x + p.vx), math.floor(p.y + p.vy), 1)
      end
    end
  end

  -- HUD: top bar
  rectf(s, 0, 0, W, 9, 0)
  line(s, 0, 9, W, 9, 1)
  text(s, "SCORE:" .. score, 2, 2, 1)
  text(s, "x" .. combo, W/2, 2, 1, ALIGN_CENTER)

  -- health bar
  local hb_x = W - 32
  local hb_w = 30
  rect(s, hb_x, 2, hb_w, 5, 1)
  local fill = math.floor(hb_w * health / max_health)
  if fill > 0 then
    rectf(s, hb_x, 2, fill, 5, 1)
  end

  -- level indicator
  text(s, "L" .. level, hb_x - 15, 2, 1)

  -- pattern name announcement
  if pattern_name_timer > 0 then
    local nx = W / 2
    local ny = 18
    local alpha = pattern_name_timer > 40 and 1 or (pattern_name_timer > 20 and 1 or 1)
    rectf(s, nx - 40, ny - 1, 80, 9, 0)
    rect(s, nx - 40, ny - 1, 80, 9, 1)
    text(s, current_pattern_name, nx, ny, 1, ALIGN_CENTER)
  end

  -- CHECK! flash
  if check_flash > 0 then
    local cx = W / 2
    local cy = H / 2 - 10
    rectf(s, cx - 25, cy - 5, 50, 14, check_invert and 1 or 0)
    rect(s, cx - 25, cy - 5, 50, 14, check_invert and 0 or 1)
    text(s, "CHECK!", cx, cy, check_invert and 0 or 1, ALIGN_CENTER)
  end

  -- feedback text
  if feedback_timer > 0 then
    local fx = STRIKE_X
    local fy = 60 - 24 + (20 - feedback_timer)
    text(s, feedback_text, fx, fy, 1, ALIGN_CENTER)
  end

  -- bottom bar
  rectf(s, 0, H - 9, W, 9, 0)
  line(s, 0, H - 9, W, H - 9, 1)

  local total_hit = perfect_count + good_count
  local total_all = total_hit + miss_count
  local pct = total_all > 0 and math.floor(total_hit * 100 / total_all) or 100
  text(s, pct .. "%", 2, H - 7, 1)
  text(s, "BEST:" .. max_combo, W/2, H - 7, 1, ALIGN_CENTER)

  if hi_score > 0 then
    text(s, "HI:" .. hi_score, W - 2, H - 7, 1, 4) -- right align
  end

  -- paused overlay
  if paused then
    rectf(s, W/2 - 30, H/2 - 10, 60, 20, 0)
    rect(s, W/2 - 30, H/2 - 10, 60, 20, 1)
    text(s, "PAUSED", W/2, H/2 - 3, 1, ALIGN_CENTER)
  end

  -- game over overlay
  if game_over then
    rectf(s, 15, 20, 130, 80, 0)
    rect(s, 15, 20, 130, 80, 1)
    rect(s, 17, 22, 126, 76, 1)

    text(s, "GAME OVER", W/2, 28, 1, ALIGN_CENTER)

    -- chess piece decoration
    draw_piece(s, 30, 38, 6, 1)  -- fallen king
    draw_piece(s, 130, 38, 6, 1)

    text(s, "SCORE: " .. score, W/2, 46, 1, ALIGN_CENTER)
    text(s, "MAX COMBO: " .. max_combo, W/2, 56, 1, ALIGN_CENTER)

    local total_all2 = perfect_count + good_count + miss_count
    local pct2 = total_all2 > 0 and math.floor((perfect_count + good_count) * 100 / total_all2) or 0
    text(s, "ACCURACY: " .. pct2 .. "%", W/2, 66, 1, ALIGN_CENTER)
    text(s, "PERFECT:" .. perfect_count .. " GOOD:" .. good_count, W/2, 76, 1, ALIGN_CENTER)

    if score > hi_score then
      if math.floor(frame() / 10) % 2 == 0 then
        text(s, "NEW HIGH SCORE!", W/2, 88, 1, ALIGN_CENTER)
      end
    else
      text(s, "PRESS ANY KEY", W/2, 88, 1, ALIGN_CENTER)
    end
  end
end
