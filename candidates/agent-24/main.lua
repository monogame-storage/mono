-- ECHO CHAMBERS
-- Agent 24 (Wave 3) — Sonar puzzles in darkness, endings by completeness
-- Merged: Agent 13 (sonar/entity) + Agent 15 (puzzles/endings) + Agent 18 (narrative/docs)
-- 160x120 | 2-bit | mode(2) | surface-first | single-file

----------------------------------------------------------------
-- CONSTANTS
----------------------------------------------------------------
local W, H = 160, 120
local TILE = 8
local COLS, ROWS = 20, 15
local SONAR_COOLDOWN = 22
local SONAR_MAX_RADIUS = 70
local SONAR_SPEED = 2.5
local MOVE_DELAY = 4
local IDLE_MAX = 300
local TOTAL_ROOMS = 5

-- Colors (2-bit)
local BLK = 0
local DRK = 1
local LIT = 2
local WHT = 3

-- Tile types
local T_EMPTY = 0
local T_WALL = 1
local T_TERMINAL = 2
local T_DOC = 3
local T_EXIT = 4

-- Sound channels
local CH_SONAR = 0
local CH_OBJ = 1
local CH_AMB = 2
local CH_FOOT = 3

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local S                   -- screen surface
local scene = "title"     -- title, game, puzzle, doc, ending, victory
local tick = 0
local frame_count = 0
local idle_timer = 0

-- Player
local px, py = 2, 7
local move_timer = 0
local sonar_timer = 0
local sonar_radius = 0
local sonar_active = false
local ping_objects = {}
local player_alive = true
local foot_alt = false

-- Sonar ring particles
local ring_particles = {}

-- Entity
local ex, ey = 15, 3
local e_speed = 0.025
local e_active = false
local e_chase = false
local e_alert_x, e_alert_y = -1, -1
local e_patrol_timer = 0
local e_target_x, e_target_y = 15, 3
local e_step_timer = 0
local e_move_accum_x = 0
local e_move_accum_y = 0
local ping_count = 0       -- pings in current room (danger escalation)

-- Scare / effects
local scare_flash = 0
local shake_timer = 0
local shake_x, shake_y = 0, 0
local death_timer = 0

-- Heartbeat / ambient
local heartbeat_rate = 0
local heartbeat_timer = 0
local amb_drip_timer = 30
local amb_creak_timer = 60
local ambient_timer = 0

-- Hint / message
local hint_text = ""
local hint_timer = 0
local msg_text = ""
local msg_timer = 0

-- Room
local current_room = 1
local room_map = {}
local room_objects = {}

-- Puzzle
local puzzle_id = nil
local puzzle_cursor = {}
local puzzle_data = {}
local puzzles_solved = {}   -- [room_num] = true

-- Documents
local doc_text = nil
local doc_lines = {}
local doc_scroll = 0

-- Ending
local ending_id = nil
local ending_timer = 0

-- Demo
local demo_mode = false
local demo_timer = 0
local demo_path = {}
local demo_step = 1

-- Title
local title_pulse = 0
local title_idle = 0
local title_timer = 0
local title_flicker = 0

-- Paused
local paused = false

----------------------------------------------------------------
-- SAFE AUDIO
----------------------------------------------------------------
local function sfx_note(ch, n, dur)
  if note then pcall(note, ch, n, dur) end
end
local function sfx_noise(ch, dur)
  if noise then pcall(noise, ch, dur) end
end
local function sfx_wave(ch, w)
  if wave then pcall(wave, ch, w) end
end
local function sfx_tone(ch, f1, f2, dur)
  if tone then pcall(tone, ch, f1, f2, dur) end
end

----------------------------------------------------------------
-- SOUND EFFECTS
----------------------------------------------------------------
local function snd_footstep()
  foot_alt = not foot_alt
  sfx_wave(CH_FOOT, "triangle")
  if foot_alt then sfx_tone(CH_FOOT, 80, 60, 0.03)
  else sfx_tone(CH_FOOT, 70, 50, 0.03) end
end

local function snd_wall_bump()
  sfx_noise(CH_FOOT, 0.04)
end

local function snd_sonar_ping()
  sfx_wave(CH_SONAR, "sine")
  sfx_tone(CH_SONAR, 1200, 400, 0.15)
end

local function snd_object_ping(obj_type, d)
  local max_d = 20
  local t = math.max(0, math.min(1, 1 - d / max_d))
  local dur = 0.02 + t * 0.08
  if dur < 0.02 then return end
  if obj_type == T_TERMINAL then
    local f = 600 + (2000 - 600) * t * t
    sfx_wave(CH_OBJ, "sine")
    sfx_tone(CH_OBJ, f, f * 1.2, dur)
  elseif obj_type == T_DOC then
    local f = 400 + (1200 - 400) * t * t
    sfx_wave(CH_OBJ, "triangle")
    sfx_tone(CH_OBJ, f, f * 0.9, dur)
  elseif obj_type == T_EXIT then
    local f = 300 + (1000 - 300) * t * t
    sfx_wave(CH_OBJ, "sine")
    sfx_tone(CH_OBJ, f, f * 1.5, dur)
    sfx_wave(CH_AMB, "triangle")
    sfx_tone(CH_AMB, f * 0.75, f * 1.1, dur)
  end
end

local function snd_terminal_open()
  sfx_wave(CH_OBJ, "sine")
  sfx_tone(CH_OBJ, 800, 1600, 0.1)
  sfx_wave(CH_SONAR, "sine")
  sfx_tone(CH_SONAR, 1000, 2000, 0.1)
end

local function snd_solve()
  sfx_wave(0, "sine")
  sfx_tone(0, 523, 1047, 0.12)
  sfx_wave(1, "sine")
  sfx_tone(1, 659, 1319, 0.12)
end

local function snd_fail()
  sfx_note(0, "C2", 0.1)
  sfx_noise(1, 0.08)
end

local function snd_click()
  sfx_noise(0, 0.02)
end

local function snd_heartbeat(intensity)
  sfx_wave(CH_AMB, "sine")
  local base = 50 + 20 * intensity
  sfx_tone(CH_AMB, base, base * 0.7, 0.06)
end

local function snd_heartbeat_double(intensity)
  sfx_wave(CH_AMB, "sine")
  local base = 55 + 20 * intensity
  sfx_tone(CH_AMB, base, base * 0.6, 0.04)
end

local function snd_entity_step(d)
  if d > 15 then return end
  local vol_t = math.max(0, math.min(1, 1 - d / 15))
  local freq = 200 - 100 * vol_t
  local dur = 0.01 + 0.03 * vol_t
  sfx_wave(CH_FOOT, "square")
  sfx_tone(CH_FOOT, freq, freq * 0.8, dur)
end

local function snd_entity_growl()
  sfx_wave(CH_AMB, "sawtooth")
  sfx_tone(CH_AMB, 45, 35, 0.12)
end

local function snd_jumpscare()
  sfx_noise(CH_SONAR, 0.2)
  sfx_wave(CH_OBJ, "sawtooth")
  sfx_tone(CH_OBJ, 80, 40, 0.3)
  sfx_noise(CH_FOOT, 0.15)
  sfx_wave(CH_AMB, "square")
  sfx_tone(CH_AMB, 100, 50, 0.25)
end

local function snd_ambient_drip()
  sfx_wave(CH_OBJ, "sine")
  local p = 1200 + math.random(800)
  sfx_tone(CH_OBJ, p, p * 0.5, 0.02)
end

local function snd_ambient_creak()
  sfx_wave(CH_AMB, "sawtooth")
  local creaks = {55, 62, 48, 70}
  local f = creaks[math.random(#creaks)]
  sfx_tone(CH_AMB, f, f * 0.8, 0.1)
end

local function snd_ambient_drone()
  sfx_wave(CH_AMB, "triangle")
  sfx_tone(CH_AMB, 45, 48, 0.5)
end

local function snd_alert_ping()
  sfx_wave(CH_OBJ, "square")
  sfx_tone(CH_OBJ, 120, 80, 0.08)
end

local function snd_victory()
  sfx_wave(0, "sine")
  sfx_tone(0, 400, 800, 0.2)
  sfx_wave(1, "sine")
  sfx_tone(1, 600, 1200, 0.2)
  sfx_wave(2, "triangle")
  sfx_tone(2, 300, 600, 0.2)
end

local function snd_title_ping()
  sfx_wave(CH_SONAR, "sine")
  sfx_tone(CH_SONAR, 800, 600, 0.1)
end

local function snd_doc_open()
  sfx_note(0, "D4", 0.06)
  sfx_note(1, "F4", 0.04)
end

local function snd_seq_tone(idx)
  local freqs = {523, 659, 784, 1047}
  sfx_wave(CH_SONAR, "sine")
  sfx_tone(CH_SONAR, freqs[idx] or 440, (freqs[idx] or 440) * 1.1, 0.15)
end

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------
local function dist(x1, y1, x2, y2)
  local dx = x1 - x2
  local dy = y1 - y2
  return math.sqrt(dx*dx + dy*dy)
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function text_c(str, y, c)
  text(S, str, W / 2, y, c or WHT, ALIGN_CENTER)
end

local function text_l(str, x, y, c)
  text(S, str, x, y, c or WHT)
end

local function draw_box(bx, by, bw, bh, border, bg)
  rectf(S, bx, by, bw, bh, bg or BLK)
  rect(S, bx, by, bw, bh, border or WHT)
end

local function get_tile(tx, ty)
  if ty < 0 or ty >= ROWS or tx < 0 or tx >= COLS then return T_WALL end
  return room_map[ty][tx]
end

local function find_objects()
  local objs = {}
  for y = 0, ROWS-1 do
    for x = 0, COLS-1 do
      local t = room_map[y][x]
      if t >= T_TERMINAL then
        objs[#objs+1] = {x=x, y=y, type=t}
      end
    end
  end
  return objs
end

local function show_hint(txt, dur)
  hint_text = txt
  hint_timer = dur or 40
end

local function show_msg(txt, dur)
  msg_text = txt
  msg_timer = dur or 90
end

local function word_wrap(str, max)
  local lines = {}
  for para in str:gmatch("[^\n]+") do
    local ln = ""
    for w in para:gmatch("%S+") do
      if #ln + #w + 1 > max then
        lines[#lines+1] = ln
        ln = w
      else
        ln = #ln > 0 and (ln .. " " .. w) or w
      end
    end
    if #ln > 0 then lines[#lines+1] = ln end
  end
  if #lines == 0 then lines[1] = "" end
  return lines
end

local function show_document(txt)
  doc_text = txt
  doc_lines = word_wrap(txt, 28)
  doc_scroll = 0
  scene = "doc"
  snd_doc_open()
end

local function close_document()
  doc_text = nil
  doc_lines = {}
  scene = "game"
end

local function count_solved()
  local n = 0
  for i = 1, TOTAL_ROOMS do
    if puzzles_solved[i] then n = n + 1 end
  end
  return n
end

----------------------------------------------------------------
-- ROOM LAYOUTS (5 rooms, each 20x15)
-- T=terminal, D=doc, X=exit
----------------------------------------------------------------

local ROOM_NAMES = {
  "COMBINATION VAULT",
  "PATTERN CHAMBER",
  "WIRE LABORATORY",
  "SEQUENCE HALL",
  "CIPHER ARCHIVE",
}

local ROOM_DOCS = {
  "INTAKE LOG Day 1:\nSubject transferred to Echo Wing sublevel 4. All external comm severed. Each chamber tests a different cognitive function. Combination vault uses a 4-digit lock. Personnel hint: the sum is always printed on the wall panel.",
  "OBSERVATION MEMO:\nPattern chamber records visual memory under stress. Grid shown briefly then hidden. Subjects must reproduce it from memory. Darkness amplifies recall in 43% of cases. The remaining 57% break.",
  "MAINTENANCE REPORT:\nWire lab circuitry requires matched pairs. Each numbered node connects to its twin. Four pairs total. Warning: incorrect connections trigger facility alert. Entity response time: 8 seconds.",
  "AUDIO RESEARCH NOTE:\nSequence hall tests auditory memory. Four tones play in order. Subject must repeat. Each correct round adds one tone. Three rounds required. Sound is the only truth in darkness.",
  "CIPHER KEY FRAGMENT:\nThe cipher shifts each letter forward by the room number (5). A becomes F, B becomes G. The encoded exit phrase unlocks the final door. Phrase: JHMMY (decode to solve).",
}

local function build_border()
  local m = {}
  for y = 0, ROWS-1 do
    m[y] = {}
    for x = 0, COLS-1 do
      if y == 0 or y == ROWS-1 or x == 0 or x == COLS-1 then
        m[y][x] = T_WALL
      else
        m[y][x] = T_EMPTY
      end
    end
  end
  return m
end

local function build_room(num)
  local m = build_border()

  if num == 1 then
    -- Combination Vault: L-shaped corridors
    for y = 1, 8 do m[y][10] = T_WALL end
    for x = 10, 14 do m[8][x] = T_WALL end
    m[4][4] = T_WALL; m[4][7] = T_WALL
    m[10][5] = T_WALL; m[10][15] = T_WALL
    m[3][15] = T_TERMINAL   -- puzzle terminal
    m[6][3] = T_DOC          -- document
    m[8][12] = T_EMPTY       -- passage
    m[13][18] = T_EXIT

  elseif num == 2 then
    -- Pattern Chamber: maze corridors
    for y = 0, 10 do m[y][5] = T_WALL end
    for y = 4, 14 do m[y][10] = T_WALL end
    for y = 0, 8 do m[y][15] = T_WALL end
    for x = 5, 10 do m[4][x] = T_WALL end
    for x = 10, 15 do m[10][x] = T_WALL end
    m[6][6] = T_EMPTY; m[6][7] = T_EMPTY
    m[12][12] = T_EMPTY; m[12][13] = T_EMPTY
    m[2][18] = T_TERMINAL
    m[8][3] = T_DOC
    m[10][13] = T_EMPTY
    m[13][17] = T_EXIT

  elseif num == 3 then
    -- Wire Laboratory: cross pattern
    for x = 3, 17 do m[7][x] = T_WALL end
    for y = 2, 12 do m[y][10] = T_WALL end
    m[7][6] = T_EMPTY; m[7][14] = T_EMPTY
    m[5][10] = T_EMPTY; m[10][10] = T_EMPTY
    m[3][4] = T_WALL; m[11][4] = T_WALL
    m[3][16] = T_WALL; m[11][16] = T_WALL
    m[3][17] = T_TERMINAL
    m[11][3] = T_DOC
    m[7][10] = T_EMPTY
    m[13][10] = T_EXIT

  elseif num == 4 then
    -- Sequence Hall: pillared hall
    for y = 3, 11 do
      if y % 3 == 0 then
        m[y][4] = T_WALL; m[y][8] = T_WALL
        m[y][12] = T_WALL; m[y][16] = T_WALL
      end
    end
    for x = 2, 18 do
      if x % 4 == 0 then m[7][x] = T_WALL end
    end
    m[7][10] = T_EMPTY
    m[2][16] = T_TERMINAL
    m[12][3] = T_DOC
    m[13][18] = T_EXIT

  elseif num == 5 then
    -- Cipher Archive: dense shelves
    for y = 2, 5 do m[y][4] = T_WALL; m[y][8] = T_WALL; m[y][14] = T_WALL end
    for y = 9, 12 do m[y][6] = T_WALL; m[y][10] = T_WALL; m[y][16] = T_WALL end
    for x = 3, 17 do
      if x % 5 == 0 then m[7][x] = T_WALL end
    end
    m[2][17] = T_TERMINAL
    m[12][2] = T_DOC
    m[13][10] = T_EXIT
  end

  return m
end

local ROOM_STARTS = {
  {x=2, y=7},
  {x=2, y=12},
  {x=2, y=4},
  {x=2, y=7},
  {x=2, y=7},
}

local ENTITY_STARTS = {
  {x=17, y=3,  tx=15, ty=7},
  {x=17, y=2,  tx=12, ty=6},
  {x=17, y=11, tx=10, ty=10},
  {x=17, y=3,  tx=14, ty=10},
  {x=17, y=11, tx=10, ty=5},
}

----------------------------------------------------------------
-- ROOM MANAGEMENT
----------------------------------------------------------------

local function load_room(num)
  room_map = build_room(num)
  local rs = ROOM_STARTS[num]
  px, py = rs.x, rs.y
  local es = ENTITY_STARTS[num]
  ex, ey = es.x, es.y
  e_target_x, e_target_y = es.tx, es.ty

  sonar_active = false
  sonar_radius = 0
  sonar_timer = 0
  ping_objects = {}
  ring_particles = {}
  player_alive = true
  scare_flash = 0
  shake_timer = 0
  death_timer = 0
  ping_count = 0
  hint_text = ""
  hint_timer = 0
  puzzle_id = nil

  e_active = true
  e_chase = false
  e_alert_x, e_alert_y = -1, -1
  e_speed = 0.02 + num * 0.006
  e_patrol_timer = 0
  e_step_timer = 0
  e_move_accum_x = 0
  e_move_accum_y = 0

  room_objects = find_objects()
end

----------------------------------------------------------------
-- ENTITY AI
----------------------------------------------------------------

local function entity_can_move(tx, ty)
  if ty < 0 or ty >= ROWS or tx < 0 or tx >= COLS then return false end
  local t = room_map[ty][tx]
  return t ~= T_WALL
end

local function update_entity()
  if not e_active or not player_alive then return end

  local d = dist(px, py, ex, ey)

  -- Ping danger: entity gets faster with more pings
  local danger_bonus = math.min(ping_count * 0.004, 0.03)

  if e_alert_x >= 0 then
    e_chase = true
    e_target_x = e_alert_x
    e_target_y = e_alert_y
    if dist(ex, ey, e_alert_x, e_alert_y) < 2 then
      e_alert_x, e_alert_y = -1, -1
      e_patrol_timer = 120
    end
  elseif d < 4 then
    e_chase = true
    e_target_x = px
    e_target_y = py
  elseif e_patrol_timer > 0 then
    e_patrol_timer = e_patrol_timer - 1
    if frame_count % 60 == 0 then
      e_target_x = clamp(math.floor(ex) + math.random(-4, 4), 1, COLS-2)
      e_target_y = clamp(math.floor(ey) + math.random(-4, 4), 1, ROWS-2)
    end
  else
    e_chase = false
    if frame_count % 90 == 0 then
      e_target_x = math.random(2, COLS-3)
      e_target_y = math.random(2, ROWS-3)
    end
  end

  local speed = (e_chase and (e_speed * 1.8) or e_speed) + danger_bonus
  local dx = e_target_x - ex
  local dy = e_target_y - ey
  local td = dist(ex, ey, e_target_x, e_target_y)

  if td > 0.5 then
    local mx = (dx / td) * speed
    local my = (dy / td) * speed
    e_move_accum_x = e_move_accum_x + mx
    e_move_accum_y = e_move_accum_y + my

    local step_x, step_y = 0, 0
    if math.abs(e_move_accum_x) >= 1 then
      step_x = e_move_accum_x > 0 and 1 or -1
      e_move_accum_x = e_move_accum_x - step_x
    end
    if math.abs(e_move_accum_y) >= 1 then
      step_y = e_move_accum_y > 0 and 1 or -1
      e_move_accum_y = e_move_accum_y - step_y
    end

    if step_x ~= 0 and entity_can_move(math.floor(ex + step_x), math.floor(ey)) then
      ex = ex + step_x
    end
    if step_y ~= 0 and entity_can_move(math.floor(ex), math.floor(ey + step_y)) then
      ey = ey + step_y
    end
  end

  -- Footstep sounds
  e_step_timer = e_step_timer + 1
  local step_interval = e_chase and 12 or 20
  if e_step_timer >= step_interval then
    e_step_timer = 0
    snd_entity_step(d)
  end

  -- Growl
  if e_chase and d < 6 and frame_count % 40 == 0 then
    snd_entity_growl()
  end

  -- CATCH
  if d < 1.5 then
    snd_jumpscare()
    scare_flash = 12
    shake_timer = 15
    player_alive = false
    death_timer = 0
    -- If caught in final room, trigger consumed ending
    if current_room == TOTAL_ROOMS then
      ending_id = "consumed"
      scene = "ending"
      ending_timer = 0
      return
    end
  end

  -- Random scare when close
  if d < 3 and math.random(100) < 4 and scare_flash <= 0 then
    scare_flash = 3
    shake_timer = 4
    sfx_noise(CH_SONAR, 0.06)
  end
end

----------------------------------------------------------------
-- SONAR SYSTEM
----------------------------------------------------------------

local function do_sonar_ping()
  if sonar_timer > 0 then return end
  sonar_active = true
  sonar_radius = 0
  sonar_timer = SONAR_COOLDOWN
  snd_sonar_ping()
  ring_particles = {}
  ping_count = ping_count + 1

  ping_objects = {}
  for _, obj in ipairs(room_objects) do
    local d = dist(px, py, obj.x, obj.y)
    if d < 18 then
      ping_objects[#ping_objects+1] = {x=obj.x, y=obj.y, type=obj.type, dist=d, pinged=false}
    end
  end
  table.sort(ping_objects, function(a, b) return a.dist < b.dist end)

  -- Alert entity
  if e_active and player_alive then
    e_alert_x = px
    e_alert_y = py
    e_chase = true
    snd_alert_ping()
    show_hint("...IT HEARD YOU", 40)
  end
end

local function update_sonar()
  if sonar_timer > 0 then sonar_timer = sonar_timer - 1 end
  if not sonar_active then return end

  sonar_radius = sonar_radius + SONAR_SPEED

  -- Ring particles
  if frame_count % 2 == 0 then
    local angle_count = 16
    for i = 0, angle_count - 1 do
      local a = (i / angle_count) * math.pi * 2
      local rx = px * TILE + 4 + math.cos(a) * sonar_radius
      local ry = py * TILE + 4 + math.sin(a) * sonar_radius
      if rx >= 0 and rx < W and ry >= 0 and ry < H then
        local tx = math.floor(rx / TILE)
        local ty = math.floor(ry / TILE)
        local tile = get_tile(tx, ty)
        if tile == T_WALL then
          ring_particles[#ring_particles+1] = {x=rx, y=ry, life=12, col=DRK}
        elseif tile >= T_TERMINAL then
          ring_particles[#ring_particles+1] = {x=rx, y=ry, life=16, col=WHT}
        else
          ring_particles[#ring_particles+1] = {x=rx, y=ry, life=4, col=DRK}
        end
      end
    end
  end

  -- Ping objects as wave reaches them
  for _, obj in ipairs(ping_objects) do
    if not obj.pinged and sonar_radius >= obj.dist * TILE then
      obj.pinged = true
      snd_object_ping(obj.type, obj.dist)
      ring_particles[#ring_particles+1] = {
        x = obj.x * TILE + 4,
        y = obj.y * TILE + 4,
        life = 22, col = WHT
      }
    end
  end

  -- Reveal entity
  if e_active then
    local ed = dist(px, py, ex, ey)
    if sonar_radius >= ed * TILE and sonar_radius < ed * TILE + SONAR_SPEED * 2 then
      ring_particles[#ring_particles+1] = {
        x = ex * TILE + 4, y = ey * TILE + 4,
        life = 15, col = WHT
      }
      sfx_wave(CH_OBJ, "sawtooth")
      sfx_tone(CH_OBJ, 150, 60, 0.1)
    end
  end

  if sonar_radius > SONAR_MAX_RADIUS then
    sonar_active = false
  end

  -- Particle life
  local alive = {}
  for _, p in ipairs(ring_particles) do
    p.life = p.life - 1
    if p.life > 0 then alive[#alive+1] = p end
  end
  ring_particles = alive
end

----------------------------------------------------------------
-- AMBIENT HORROR
----------------------------------------------------------------

local function update_ambient()
  amb_drip_timer = amb_drip_timer - 1
  if amb_drip_timer <= 0 then
    amb_drip_timer = 50 + math.random(80)
    snd_ambient_drip()
  end

  amb_creak_timer = amb_creak_timer - 1
  if amb_creak_timer <= 0 then
    amb_creak_timer = 100 + math.random(150)
    snd_ambient_creak()
  end

  ambient_timer = ambient_timer + 1
  if ambient_timer >= 90 then
    ambient_timer = 0
    snd_ambient_drone()
  end

  -- Heartbeat
  if e_active and player_alive then
    local d = dist(px, py, ex, ey)
    local target = clamp(1 - (d / 15), 0, 1)
    heartbeat_rate = lerp(heartbeat_rate, target, 0.05)
  else
    heartbeat_rate = math.max(heartbeat_rate - 0.01, 0)
  end

  if heartbeat_rate > 0.08 then
    heartbeat_timer = heartbeat_timer + 1
    local interval = math.floor(lerp(30, 6, heartbeat_rate))
    if heartbeat_timer >= interval then
      heartbeat_timer = 0
      snd_heartbeat(heartbeat_rate)
      if heartbeat_rate > 0.5 then
        snd_heartbeat_double(heartbeat_rate)
      end
    end
  else
    heartbeat_timer = 0
  end
end

local function update_proximity_sounds()
  if frame_count % 25 ~= 0 then return end
  local nearest, nearest_dist = nil, 999
  for _, obj in ipairs(room_objects) do
    local d = dist(px, py, obj.x, obj.y)
    if d < nearest_dist then nearest_dist = d; nearest = obj end
  end
  if nearest and nearest_dist < 12 then
    snd_object_ping(nearest.type, nearest_dist)
  end
end

----------------------------------------------------------------
-- PUZZLES
----------------------------------------------------------------

-- 1. COMBINATION (Room 1)
local function init_puzzle_combo()
  puzzle_id = "combo"
  puzzle_cursor = {x=1}
  local d = {}
  d.cols = 4
  d.digits = {0,0,0,0}
  d.target = {}
  for i = 1, d.cols do d.target[i] = math.random(0, 9) end
  puzzle_data = d
  scene = "puzzle"
end

local function update_puzzle_combo()
  local d = puzzle_data
  if btnp("left") then puzzle_cursor.x = math.max(1, puzzle_cursor.x-1); snd_click() end
  if btnp("right") then puzzle_cursor.x = math.min(d.cols, puzzle_cursor.x+1); snd_click() end
  if btnp("up") then d.digits[puzzle_cursor.x] = (d.digits[puzzle_cursor.x]+1)%10; snd_click() end
  if btnp("down") then d.digits[puzzle_cursor.x] = (d.digits[puzzle_cursor.x]-1)%10; snd_click() end
  if btnp("a") then
    local ok = true
    for i = 1, d.cols do
      if d.digits[i] ~= d.target[i] then ok = false; break end
    end
    if ok then return true
    else snd_fail(); scare_flash = 5 end
  end
  if btnp("b") then scene = "game"; puzzle_id = nil end
  return false
end

local function draw_puzzle_combo()
  local d = puzzle_data
  draw_box(10, 8, 140, 104, WHT, BLK)
  text_c("COMBINATION VAULT", 12, WHT)

  -- Hints
  local s_val = 0
  for i = 1, d.cols do s_val = s_val + d.target[i] end
  text_l("HINT: SUM=" .. s_val, 16, 26, LIT)
  local parity = ""
  for i = 1, d.cols do
    parity = parity .. (d.target[i] % 2 == 0 and "E" or "O")
  end
  text_l("PARITY: " .. parity, 16, 36, LIT)

  local ox, oy = 40, 52
  for i = 1, d.cols do
    local sel = (i == puzzle_cursor.x)
    local c = sel and WHT or LIT
    rectf(S, ox+(i-1)*22, oy, 16, 20, DRK)
    rect(S, ox+(i-1)*22, oy, 16, 20, c)
    text_l(tostring(d.digits[i]), ox+(i-1)*22+5, oy+7, WHT)
    if sel then
      text_l("^", ox+(i-1)*22+5, oy-8, WHT)
      text_l("v", ox+(i-1)*22+5, oy+22, WHT)
    end
  end
  text_c("Up/Down:Digit  A:Check", 82, LIT)
  text_c("B:Back", 92, DRK)
end

-- 2. PATTERN (Room 2)
local function init_puzzle_pattern()
  puzzle_id = "pattern"
  puzzle_cursor = {x=1, y=1}
  local d = {}
  d.sz = 4
  d.target = {}
  d.player = {}
  for y = 1, d.sz do
    d.target[y] = {}
    d.player[y] = {}
    for x = 1, d.sz do
      d.target[y][x] = math.random() < 0.4 and 1 or 0
      d.player[y][x] = 0
    end
  end
  d.showing = true
  d.timer = 90
  puzzle_data = d
  scene = "puzzle"
end

local function update_puzzle_pattern()
  local d = puzzle_data
  if d.showing then
    d.timer = d.timer - 1
    if d.timer <= 0 then d.showing = false end
    return false
  end
  if btnp("left") then puzzle_cursor.x = math.max(1, puzzle_cursor.x-1); snd_click() end
  if btnp("right") then puzzle_cursor.x = math.min(d.sz, puzzle_cursor.x+1); snd_click() end
  if btnp("up") then puzzle_cursor.y = math.max(1, puzzle_cursor.y-1); snd_click() end
  if btnp("down") then puzzle_cursor.y = math.min(d.sz, puzzle_cursor.y+1); snd_click() end
  if btnp("a") then
    d.player[puzzle_cursor.y][puzzle_cursor.x] = 1 - d.player[puzzle_cursor.y][puzzle_cursor.x]
    snd_click()
  end
  if btnp("b") and not d.showing then
    -- Check submission
    local ok = true
    for y = 1, d.sz do
      for x = 1, d.sz do
        if d.target[y][x] ~= d.player[y][x] then ok = false end
      end
    end
    if ok then return true
    else
      snd_fail(); scare_flash = 5
      d.showing = true; d.timer = 45
    end
  end
  if btnp("start") then scene = "game"; puzzle_id = nil end
  return false
end

local function draw_puzzle_pattern()
  local d = puzzle_data
  draw_box(10, 2, 140, 116, WHT, BLK)
  local ox, oy = 46, 20
  local cs = 14
  local grid = d.showing and d.target or d.player

  if d.showing then
    text_c("MEMORIZE THE PATTERN", 6, WHT)
    if tick % 10 < 5 then rect(S, 10, 2, 140, 116, WHT) end
  else
    text_c("REPRODUCE IT", 6, LIT)
  end

  for y = 1, d.sz do
    for x = 1, d.sz do
      local gx = ox + (x-1) * cs
      local gy = oy + (y-1) * cs
      local on = grid[y][x] == 1
      rectf(S, gx, gy, cs-2, cs-2, on and WHT or DRK)
      rect(S, gx, gy, cs-2, cs-2, LIT)
    end
  end

  if not d.showing then
    local cx = ox + (puzzle_cursor.x-1) * cs
    local cy = oy + (puzzle_cursor.y-1) * cs
    rect(S, cx-1, cy-1, cs, cs, WHT)
    text_c("A:Toggle  B:Submit", 82, LIT)
    text_c("START:Back", 92, DRK)
  else
    text_c("Watch carefully...", 82, LIT)
  end
end

-- 3. WIRES (Room 3)
local function init_puzzle_wires()
  puzzle_id = "wires"
  puzzle_cursor = {x=1, y=1}
  local d = {}
  d.sz = 5
  d.grid = {}
  for y = 1, d.sz do
    d.grid[y] = {}
    for x = 1, d.sz do d.grid[y][x] = {kind=0} end
  end
  d.pairs = {}
  local spots = {}
  for y = 1, d.sz do for x = 1, d.sz do spots[#spots+1] = {x=x, y=y} end end
  for i = #spots, 2, -1 do
    local j = math.random(1, i)
    spots[i], spots[j] = spots[j], spots[i]
  end
  for i = 1, 4 do
    local a = spots[i*2-1]
    local b = spots[i*2]
    d.grid[a.y][a.x].kind = i
    d.grid[b.y][b.x].kind = i
    d.pairs[i] = {a=a, b=b, done=false}
  end
  d.sel = nil
  puzzle_data = d
  scene = "puzzle"
end

local function update_puzzle_wires()
  local d = puzzle_data
  if btnp("left") then puzzle_cursor.x = math.max(1, puzzle_cursor.x-1); snd_click() end
  if btnp("right") then puzzle_cursor.x = math.min(d.sz, puzzle_cursor.x+1); snd_click() end
  if btnp("up") then puzzle_cursor.y = math.max(1, puzzle_cursor.y-1); snd_click() end
  if btnp("down") then puzzle_cursor.y = math.min(d.sz, puzzle_cursor.y+1); snd_click() end
  if btnp("a") then
    local cell = d.grid[puzzle_cursor.y][puzzle_cursor.x]
    if cell.kind > 0 then
      if d.sel == nil then
        d.sel = {x=puzzle_cursor.x, y=puzzle_cursor.y, kind=cell.kind}
        snd_click()
      else
        if cell.kind == d.sel.kind and (puzzle_cursor.x ~= d.sel.x or puzzle_cursor.y ~= d.sel.y) then
          d.pairs[cell.kind].done = true
          snd_solve()
          d.sel = nil
          local ok = true
          for _, p in ipairs(d.pairs) do if not p.done then ok = false; break end end
          if ok then return true end
        else
          snd_fail(); d.sel = nil
        end
      end
    end
  end
  if btnp("b") then
    if d.sel then d.sel = nil
    else scene = "game"; puzzle_id = nil end
  end
  return false
end

local function draw_puzzle_wires()
  local d = puzzle_data
  draw_box(10, 2, 140, 116, WHT, BLK)
  text_c("MATCH THE WIRE PAIRS", 6, LIT)
  local ox, oy = 40, 18
  local cs = 15
  for y = 1, d.sz do
    for x = 1, d.sz do
      local gx = ox + (x-1) * cs
      local gy = oy + (y-1) * cs
      rect(S, gx, gy, cs-2, cs-2, DRK)
      local cell = d.grid[y][x]
      if cell.kind > 0 then
        local col = d.pairs[cell.kind].done and DRK or (cell.kind <= 2 and LIT or WHT)
        circf(S, gx+cs/2-1, gy+cs/2-1, 4, col)
        text_l(tostring(cell.kind), gx+cs/2-3, gy+cs/2-3, BLK)
      end
    end
  end
  for _, p in ipairs(d.pairs) do
    if p.done then
      local ax = ox + (p.a.x-1)*cs + cs/2-1
      local ay = oy + (p.a.y-1)*cs + cs/2-1
      local bx = ox + (p.b.x-1)*cs + cs/2-1
      local by = oy + (p.b.y-1)*cs + cs/2-1
      line(S, ax, ay, bx, by, LIT)
    end
  end
  local cx = ox + (puzzle_cursor.x-1)*cs
  local cy = oy + (puzzle_cursor.y-1)*cs
  rect(S, cx-1, cy-1, cs, cs, WHT)
  if d.sel then
    local sx = ox + (d.sel.x-1)*cs
    local sy = oy + (d.sel.y-1)*cs
    rect(S, sx-1, sy-1, cs, cs, WHT)
  end
  text_c("A:Select  B:Cancel/Back", 98, LIT)
end

-- 4. SEQUENCE (Room 4) — audio memory
local function init_puzzle_sequence()
  puzzle_id = "sequence"
  puzzle_cursor = {x=1}
  local d = {}
  d.seq = {}
  for i = 1, 3 do d.seq[i] = math.random(1, 4) end
  d.round = 1
  d.input = {}
  d.playing = true
  d.play_idx = 0
  d.play_timer = 0
  d.rounds_needed = 3
  d.highlight = 0
  puzzle_data = d
  scene = "puzzle"
end

local function update_puzzle_sequence()
  local d = puzzle_data
  if d.playing then
    d.play_timer = d.play_timer + 1
    if d.play_timer >= 20 then
      d.play_timer = 0
      d.play_idx = d.play_idx + 1
      if d.play_idx <= d.round then
        snd_seq_tone(d.seq[d.play_idx])
        d.highlight = d.seq[d.play_idx]
      else
        d.playing = false
        d.highlight = 0
        d.input = {}
      end
    end
    if d.play_timer == 10 then d.highlight = 0 end
    return false
  end

  -- Input phase
  for i = 1, 4 do
    local btns = {"left", "up", "right", "down"}
    if btnp(btns[i]) then
      d.input[#d.input+1] = i
      snd_seq_tone(i)
      d.highlight = i

      local idx = #d.input
      if d.input[idx] ~= d.seq[idx] then
        snd_fail(); scare_flash = 5
        d.playing = true; d.play_idx = 0; d.play_timer = 0
        d.input = {}
        return false
      end

      if idx == d.round then
        if d.round >= d.rounds_needed then
          return true
        end
        d.round = d.round + 1
        if d.round > #d.seq then
          d.seq[#d.seq+1] = math.random(1, 4)
        end
        d.playing = true; d.play_idx = 0; d.play_timer = 0
        d.input = {}
        snd_solve()
      end
    end
  end

  if btnp("b") then scene = "game"; puzzle_id = nil end
  return false
end

local function draw_puzzle_sequence()
  local d = puzzle_data
  draw_box(10, 2, 140, 116, WHT, BLK)
  text_c("SEQUENCE HALL", 6, WHT)
  text_c("Round " .. d.round .. "/" .. d.rounds_needed, 18, LIT)

  -- Four directional buttons
  local cx, cy = 80, 58
  local r = 18
  local dirs = {{0,-1}, {-1,0}, {0,1}, {1,0}}
  local labels = {"^", "<", "v", ">"}
  for i = 1, 4 do
    local bx = cx + dirs[i][1] * r - 8
    local by = cy + dirs[i][2] * r - 5
    local col = (d.highlight == i) and WHT or DRK
    rectf(S, bx, by, 16, 10, col)
    rect(S, bx, by, 16, 10, LIT)
    text_l(labels[i], bx + 6, by + 2, col == WHT and BLK or LIT)
  end

  if d.playing then
    text_c("Listen...", 90, LIT)
  else
    text_c("Repeat: D-Pad", 86, LIT)
    text_c("Input: " .. #d.input .. "/" .. d.round, 96, DRK)
  end
  text_c("B:Back", 106, DRK)
end

-- 5. CIPHER (Room 5) — decode shifted text
local function init_puzzle_cipher()
  puzzle_id = "cipher"
  puzzle_cursor = {x=1}
  local d = {}
  d.answer = "HELLO"   -- encoded as JHMMY (shift +5 -- but doc says shift by room num 5)
  d.len = #d.answer
  d.input = {}
  for i = 1, d.len do d.input[i] = 1 end -- A=1
  puzzle_data = d
  scene = "puzzle"
end

local function update_puzzle_cipher()
  local d = puzzle_data
  if btnp("left") then puzzle_cursor.x = math.max(1, puzzle_cursor.x-1); snd_click() end
  if btnp("right") then puzzle_cursor.x = math.min(d.len, puzzle_cursor.x+1); snd_click() end
  if btnp("up") then d.input[puzzle_cursor.x] = (d.input[puzzle_cursor.x] % 26) + 1; snd_click() end
  if btnp("down") then d.input[puzzle_cursor.x] = ((d.input[puzzle_cursor.x] - 2) % 26) + 1; snd_click() end
  if btnp("a") then
    local ok = true
    for i = 1, d.len do
      local ch = string.char(64 + d.input[i])
      if ch ~= d.answer:sub(i, i) then ok = false; break end
    end
    if ok then return true
    else snd_fail(); scare_flash = 5 end
  end
  if btnp("b") then scene = "game"; puzzle_id = nil end
  return false
end

local function draw_puzzle_cipher()
  local d = puzzle_data
  draw_box(10, 2, 140, 116, WHT, BLK)
  text_c("CIPHER ARCHIVE", 6, WHT)
  text_c("Encoded: JHMMY", 20, LIT)
  text_c("Shift: -5 letters", 30, DRK)

  local ox, oy = 38, 50
  for i = 1, d.len do
    local sel = (i == puzzle_cursor.x)
    local c = sel and WHT or LIT
    local ch = string.char(64 + d.input[i])
    rectf(S, ox + (i-1)*18, oy, 14, 18, DRK)
    rect(S, ox + (i-1)*18, oy, 14, 18, c)
    text_l(ch, ox + (i-1)*18 + 4, oy + 5, WHT)
    if sel then
      text_l("^", ox + (i-1)*18 + 4, oy - 8, WHT)
      text_l("v", ox + (i-1)*18 + 4, oy + 20, WHT)
    end
  end

  text_c("Up/Down:Letter  A:Check", 82, LIT)
  text_c("B:Back", 92, DRK)
end

-- Puzzle dispatch tables
local puzzle_inits = {
  init_puzzle_combo,
  init_puzzle_pattern,
  init_puzzle_wires,
  init_puzzle_sequence,
  init_puzzle_cipher,
}

local puzzle_updates = {
  combo = update_puzzle_combo,
  pattern = update_puzzle_pattern,
  wires = update_puzzle_wires,
  sequence = update_puzzle_sequence,
  cipher = update_puzzle_cipher,
}

local puzzle_draws = {
  combo = draw_puzzle_combo,
  pattern = draw_puzzle_pattern,
  wires = draw_puzzle_wires,
  sequence = draw_puzzle_sequence,
  cipher = draw_puzzle_cipher,
}

local function on_puzzle_solved()
  puzzles_solved[current_room] = true
  snd_solve()
  show_hint("PUZZLE SOLVED: " .. count_solved() .. "/" .. TOTAL_ROOMS, 60)
  puzzle_id = nil
  scene = "game"
end

----------------------------------------------------------------
-- MOVEMENT & INTERACTION
----------------------------------------------------------------

local function try_move(dx, dy)
  if not player_alive then return end

  local nx = px + dx
  local ny = py + dy
  local tile = get_tile(nx, ny)

  if tile == T_WALL then
    snd_wall_bump()
    show_hint("WALL", 15)
    return
  end

  if tile == T_TERMINAL then
    if puzzles_solved[current_room] then
      show_hint("ALREADY SOLVED", 30)
    else
      snd_terminal_open()
      puzzle_inits[current_room]()
    end
    return
  end

  if tile == T_DOC then
    show_document(ROOM_DOCS[current_room])
    room_map[ny][nx] = T_EMPTY
    room_objects = find_objects()
    return
  end

  if tile == T_EXIT then
    if current_room < TOTAL_ROOMS then
      current_room = current_room + 1
      load_room(current_room)
      show_hint("CHAMBER " .. current_room .. ": " .. ROOM_NAMES[current_room], 80)
    else
      -- Final exit: ending based on puzzles solved
      local solved = count_solved()
      if solved == TOTAL_ROOMS then
        ending_id = "freedom"
      else
        ending_id = "escape"
      end
      scene = "ending"
      ending_timer = 0
      snd_victory()
    end
    return
  end

  -- Empty
  px, py = nx, ny
  snd_footstep()
end

----------------------------------------------------------------
-- GAME UPDATE
----------------------------------------------------------------

local function game_update()
  if not player_alive then
    death_timer = death_timer + 1
    if scare_flash > 0 then scare_flash = scare_flash - 1 end
    if shake_timer > 0 then shake_timer = shake_timer - 1 end
    if scene == "ending" then return end
    if death_timer > 90 and (btnp("start") or btnp("a")) then
      load_room(current_room)
      show_hint("TRY AGAIN... QUIETLY", 60)
    end
    return
  end

  if paused then
    if btnp("start") then paused = false end
    return
  end

  if btnp("start") then paused = true; return end

  -- Show solved count on select
  if btnp("select") then
    show_hint("SOLVED: " .. count_solved() .. "/" .. TOTAL_ROOMS, 60)
  end

  frame_count = frame_count + 1

  -- Movement
  if move_timer > 0 then move_timer = move_timer - 1 end
  if move_timer <= 0 then
    if btn("left") then try_move(-1, 0); move_timer = MOVE_DELAY
    elseif btn("right") then try_move(1, 0); move_timer = MOVE_DELAY
    elseif btn("up") then try_move(0, -1); move_timer = MOVE_DELAY
    elseif btn("down") then try_move(0, 1); move_timer = MOVE_DELAY
    end
  end

  -- Sonar on A
  if btnp("a") then do_sonar_ping() end

  -- Interact with B (adjacent terminal/doc)
  if btnp("b") then
    local dirs = {{-1,0},{1,0},{0,-1},{0,1}}
    for _, d in ipairs(dirs) do
      local nx, ny = px + d[1], py + d[2]
      local tile = get_tile(nx, ny)
      if tile == T_TERMINAL then
        if puzzles_solved[current_room] then
          show_hint("ALREADY SOLVED", 30)
        else
          snd_terminal_open()
          puzzle_inits[current_room]()
        end
        break
      elseif tile == T_DOC then
        show_document(ROOM_DOCS[current_room])
        room_map[ny][nx] = T_EMPTY
        room_objects = find_objects()
        break
      end
    end
  end

  update_sonar()
  update_entity()
  update_proximity_sounds()
  update_ambient()

  if scare_flash > 0 then scare_flash = scare_flash - 1 end
  if shake_timer > 0 then
    shake_timer = shake_timer - 1
    shake_x = math.random(-3, 3)
    shake_y = math.random(-2, 2)
  else
    shake_x, shake_y = 0, 0
  end

  if hint_timer > 0 then hint_timer = hint_timer - 1 end
  if msg_timer > 0 then msg_timer = msg_timer - 1 end
end

----------------------------------------------------------------
-- GAME DRAW
----------------------------------------------------------------

local function game_draw()
  S = screen()
  cls(S, BLK)

  -- Jump scare flash
  if scare_flash > 0 then
    cls(S, scare_flash > 6 and WHT or LIT)
    if not player_alive and scare_flash > 4 then
      local cx, cy = W/2, H/2
      rectf(S, cx-20, cy-10, 12, 8, BLK)
      pix(S, cx-15, cy-7, WHT); pix(S, cx-14, cy-7, WHT)
      rectf(S, cx+8, cy-10, 12, 8, BLK)
      pix(S, cx+13, cy-7, WHT); pix(S, cx+14, cy-7, WHT)
      line(S, cx-15, cy+5, cx+15, cy+5, BLK)
      return
    end
    if scare_flash > 3 then return end
  end

  local draw_px = px * TILE + 4 + shake_x
  local draw_py = py * TILE + 4 + shake_y

  -- Player dot
  if player_alive then
    pix(S, draw_px, draw_py, WHT)
    local breathe = math.sin(frame_count * 0.08)
    if breathe > 0 then
      pix(S, draw_px-1, draw_py, DRK)
      pix(S, draw_px+1, draw_py, DRK)
      pix(S, draw_px, draw_py-1, DRK)
      pix(S, draw_px, draw_py+1, DRK)
    end
  end

  -- Sonar particles
  for _, p in ipairs(ring_particles) do
    local rx = math.floor(p.x) + shake_x
    local ry = math.floor(p.y) + shake_y
    if rx >= 0 and rx < W and ry >= 0 and ry < H then
      local c = p.col
      if p.life < 4 then c = DRK end
      if p.life < 2 then c = BLK end
      if c > 0 then pix(S, rx, ry, c) end
    end
  end

  -- Active sonar ring
  if sonar_active then
    local segs = 32
    for i = 0, segs-1 do
      local a = (i / segs) * math.pi * 2
      local rx = draw_px + math.cos(a) * sonar_radius
      local ry = draw_py + math.sin(a) * sonar_radius
      if rx >= 0 and rx < W and ry >= 0 and ry < H then
        pix(S, math.floor(rx), math.floor(ry), DRK)
      end
    end
  end

  -- Entity eyes
  if e_active and player_alive then
    local ed = dist(px, py, ex, ey)
    if ed < 5 then
      local epx = math.floor(ex * TILE + 4) + shake_x
      local epy = math.floor(ey * TILE + 4) + shake_y
      local blink = math.floor(frame_count / 8) % 5
      if blink < 3 then
        local brightness = ed < 3 and WHT or LIT
        pix(S, epx-1, epy, brightness)
        pix(S, epx+1, epy, brightness)
      end
    end
  end

  -- HUD
  text_l(current_room .. "/" .. TOTAL_ROOMS, 4, 2, DRK)

  -- Solved indicator
  local solved = count_solved()
  if solved > 0 then
    text(S, solved .. "S", W-16, 2, DRK)
  end

  -- Heartbeat vignette
  if heartbeat_rate > 0.3 then
    local pulse = math.sin(frame_count * 0.3) * heartbeat_rate
    if pulse > 0.3 then
      local c = heartbeat_rate > 0.7 and LIT or DRK
      for i = 0, W-1, 4 do pix(S, i, 0, c); pix(S, i, H-1, c) end
      for i = 0, H-1, 4 do pix(S, 0, i, c); pix(S, W-1, i, c) end
    end
  end

  -- Sonar cooldown
  if sonar_timer > 0 then
    local bar_w = math.floor((sonar_timer / SONAR_COOLDOWN) * 16)
    rectf(S, W/2-8, H-5, bar_w, 2, DRK)
  else
    if frame_count % 40 < 30 then pix(S, W/2, H-4, LIT) end
  end

  -- Hint
  if hint_timer > 0 then
    local hcol = hint_timer > 15 and LIT or DRK
    text_c(hint_text, H-14, hcol)
  end

  -- Death overlay
  if not player_alive and scare_flash <= 0 and scene == "game" then
    text_c("IT GOT YOU", H/2-8, WHT)
    if death_timer > 30 then
      text_c("CHAMBER " .. current_room, H/2+4, DRK)
    end
    if death_timer > 60 and frame_count % 40 < 25 then
      text_c("PRESS START", H/2+16, LIT)
    end
  end

  -- Pause
  if paused then
    rectf(S, W/2-30, H/2-12, 60, 24, BLK)
    rect(S, W/2-30, H/2-12, 60, 24, WHT)
    text_c("PAUSED", H/2-8, WHT)
    text_c(count_solved() .. "/" .. TOTAL_ROOMS .. " SOLVED", H/2+2, LIT)
  end
end

----------------------------------------------------------------
-- PUZZLE SCENE
----------------------------------------------------------------

local function puzzle_update()
  tick = tick + 1
  if puzzle_id and puzzle_updates[puzzle_id] then
    local solved = puzzle_updates[puzzle_id]()
    if solved then on_puzzle_solved() end
  end
  -- Entity still moves during puzzles (tension!)
  update_entity()
  update_ambient()
end

local function puzzle_draw()
  S = screen()
  cls(S, BLK)
  if puzzle_id and puzzle_draws[puzzle_id] then
    puzzle_draws[puzzle_id]()
  end
  -- Scare flash overlay during puzzle
  if scare_flash > 0 then
    local c = scare_flash > 3 and WHT or LIT
    rect(S, 0, 0, W-1, H-1, c)
  end
end

----------------------------------------------------------------
-- DOCUMENT SCENE
----------------------------------------------------------------

local function doc_update()
  if btnp("up") then doc_scroll = math.max(0, doc_scroll - 1) end
  if btnp("down") then doc_scroll = math.min(math.max(0, #doc_lines - 10), doc_scroll + 1) end
  if btnp("b") or btnp("a") then close_document() end
  update_entity()
  update_ambient()
end

local function doc_draw()
  S = screen()
  cls(S, BLK)
  draw_box(4, 4, 152, 112, LIT, BLK)
  text_c("DOCUMENT", 8, WHT)
  for i = 1, math.min(10, #doc_lines - doc_scroll) do
    local li = doc_scroll + i
    if li <= #doc_lines then
      text_l(doc_lines[li], 10, 16 + (i-1) * 9, LIT)
    end
  end
  if #doc_lines > 10 then
    text_c("Up/Down:Scroll", 104, DRK)
  end
  text_c("A/B:Close", 112, DRK)
end

----------------------------------------------------------------
-- ENDINGS
----------------------------------------------------------------

local function draw_ending_freedom()
  cls(S, BLK)
  -- Light expanding from center
  local r = math.min(ending_timer * 0.8, 50)
  local cx, cy = W/2, H/2
  for ring = math.floor(r), 0, -4 do
    local col = DRK
    if ring < r * 0.3 then col = WHT
    elseif ring < r * 0.6 then col = LIT end
    local segs = 24
    for i = 0, segs-1 do
      local a = (i / segs) * math.pi * 2
      local rx = cx + math.cos(a) * ring
      local ry = cy + math.sin(a) * ring
      if rx >= 0 and rx < W and ry >= 0 and ry < H then
        pix(S, math.floor(rx), math.floor(ry), col)
      end
    end
  end
  if ending_timer > 30 then
    text_c("TRUE FREEDOM", H/2-16, WHT)
  end
  if ending_timer > 60 then
    text_c("All chambers unsealed.", H/2-4, LIT)
    text_c("You remember everything.", H/2+8, LIT)
  end
  if ending_timer > 90 then
    text_c("The Echo Wing is exposed.", H/2+20, DRK)
  end
  if ending_timer > 130 and (tick % 40 < 25) then
    text_c("PRESS START", H-12, LIT)
  end
end

local function draw_ending_escape()
  cls(S, BLK)
  -- Dawn horizon
  for i = 0, 30 do
    local c = i < 10 and WHT or (i < 20 and LIT or DRK)
    line(S, 0, 40+i, W, 40+i, c)
  end
  rectf(S, 0, 71, W, H-71, DRK)
  text_c("PARTIAL ESCAPE", 10, WHT)
  if ending_timer > 20 then
    local solved = count_solved()
    text_c(solved .. " of " .. TOTAL_ROOMS .. " chambers solved.", 25, LIT)
  end
  if ending_timer > 50 then
    text_c("Free, but memories fractured.", 80, LIT)
    text_c("The truth stays buried.", 90, DRK)
  end
  if ending_timer > 120 and (tick % 40 < 25) then
    text_c("PRESS START", H-12, LIT)
  end
end

local function draw_ending_consumed()
  cls(S, BLK)
  -- Entity eyes growing
  local eye_r = math.min(ending_timer * 0.3, 15)
  local cx, cy = W/2, H/2 - 10
  if eye_r > 2 then
    circf(S, cx-15, cy, math.floor(eye_r), WHT)
    circf(S, cx+15, cy, math.floor(eye_r), WHT)
    circf(S, cx-15, cy, math.floor(eye_r * 0.4), BLK)
    circf(S, cx+15, cy, math.floor(eye_r * 0.4), BLK)
  end
  if ending_timer > 40 then
    text_c("CONSUMED", cy + 25, WHT)
  end
  if ending_timer > 70 then
    text_c("The darkness takes you.", cy + 37, LIT)
    text_c("You become part of the", cy + 49, LIT)
    text_c("Echo Wing. Forever.", cy + 59, DRK)
  end
  if ending_timer > 130 and (tick % 40 < 25) then
    text_c("PRESS START", H-12, LIT)
  end
end

----------------------------------------------------------------
-- TITLE SCENE
----------------------------------------------------------------

local function title_update()
  tick = tick + 1
  title_pulse = title_pulse + 1
  title_idle = title_idle + 1
  title_timer = title_timer + 1

  if title_pulse % 60 == 0 then snd_title_ping() end

  if title_flicker > 0 then
    title_flicker = title_flicker - 1
  elseif math.random(200) < 3 then
    title_flicker = 5
  end

  -- Demo after idle
  if title_idle > IDLE_MAX and not demo_mode then
    demo_mode = true
    current_room = 1
    puzzles_solved = {}
    load_room(1)
    demo_path = {
      {dx=1,dy=0},{dx=1,dy=0},{dx=1,dy=0},{dx=1,dy=0},
      {dx=1,dy=0},{dx=0,dy=-1},{dx=0,dy=-1},{dx=0,dy=-1},
      {dx=0,dy=0,ping=true},
      {dx=1,dy=0},{dx=1,dy=0},{dx=1,dy=0},
      {dx=0,dy=1},{dx=0,dy=1},{dx=0,dy=1},{dx=0,dy=1},
      {dx=0,dy=0,ping=true},
      {dx=-1,dy=0},{dx=-1,dy=0},{dx=0,dy=1},{dx=0,dy=1},
      {dx=1,dy=0},{dx=1,dy=0},{dx=1,dy=0},{dx=1,dy=0},
      {dx=0,dy=1},{dx=0,dy=1},{dx=0,dy=1},
    }
    demo_step = 1
    demo_timer = 0
    title_idle = 0
  end

  if demo_mode then
    demo_timer = demo_timer + 1
    if demo_timer >= 8 then
      demo_timer = 0
      if demo_step > #demo_path then
        load_room(1)
        demo_step = 1
      else
        local step = demo_path[demo_step]
        if step.ping then
          do_sonar_ping()
        else
          local nx, ny = px + step.dx, py + step.dy
          local tile = get_tile(nx, ny)
          if tile == T_EMPTY then px, py = nx, ny; snd_footstep()
          elseif tile == T_WALL then snd_wall_bump() end
        end
        demo_step = demo_step + 1
      end
    end
    update_sonar()
    update_entity()
  end

  if btnp("start") or btnp("a") then
    demo_mode = false
    scene = "game"
    current_room = 1
    puzzles_solved = {}
    load_room(1)
    show_hint("PING TO SEE... BUT IT LISTENS", 120)
  end
end

local function title_draw()
  S = screen()
  cls(S, BLK)

  local title_c = WHT
  local flick = math.random(100)
  if flick < 6 then title_c = DRK
  elseif flick < 12 then title_c = LIT end
  if title_flicker > 0 and title_flicker > 3 then title_c = BLK end

  if title_c > BLK then
    text_c("ECHO CHAMBERS", 18, title_c)
  end

  if title_timer > 30 then
    text_c("five sealed rooms.", 36, DRK)
  end
  if title_timer > 60 then
    text_c("you navigate by sound.", 46, DRK)
  end
  if title_timer > 90 then
    text_c("every ping reveals", 56, DRK)
    text_c("and betrays.", 66, DRK)
  end

  -- Sonar ring on title
  local ring_r = (title_pulse % 60) * 1.5
  if ring_r < 80 then
    local cx, cy = W/2, 88
    local segs = 24
    for i = 0, segs-1 do
      local a = (i / segs) * math.pi * 2
      local rx = cx + math.cos(a) * ring_r
      local ry = cy + math.sin(a) * ring_r * 0.5
      if rx >= 0 and rx < W and ry >= 0 and ry < H then
        local c = ring_r < 40 and DRK or BLK
        if c > 0 then pix(S, math.floor(rx), math.floor(ry), c) end
      end
    end
    pix(S, cx, 88, WHT)
  end

  -- Entity eyes on title
  if title_timer > 100 then
    local blink = math.floor(title_pulse / 20) % 5
    if blink < 2 then
      local eye_x = W/2 + math.sin(title_pulse * 0.02) * 30
      local eye_y = 88 + math.cos(title_pulse * 0.015) * 8
      pix(S, math.floor(eye_x)-1, math.floor(eye_y), LIT)
      pix(S, math.floor(eye_x)+1, math.floor(eye_y), LIT)
    end
  end

  if demo_mode then
    local dpx = px * TILE + 4
    local dpy = py * TILE + 4
    pix(S, dpx, dpy, WHT)
    for _, p in ipairs(ring_particles) do
      if p.x >= 0 and p.x < W and p.y >= 0 and p.y < H then
        pix(S, math.floor(p.x), math.floor(p.y), p.col)
      end
    end
    text_c("- DEMO -", 4, DRK)
  end

  if title_pulse % 40 < 25 then
    text_c("PRESS START", 108, LIT)
  end
  text_c("5 puzzles. 3 endings.", 116, DRK)
end

----------------------------------------------------------------
-- ENDING SCENE
----------------------------------------------------------------

local function ending_update()
  tick = tick + 1
  ending_timer = ending_timer + 1
  local threshold = ending_id == "freedom" and 130 or 120
  if ending_timer > threshold and (btnp("start") or btnp("a")) then
    scene = "title"
    title_pulse = 0
    title_idle = 0
    title_timer = 0
    demo_mode = false
  end
end

local function ending_draw()
  S = screen()
  if ending_id == "freedom" then draw_ending_freedom()
  elseif ending_id == "escape" then draw_ending_escape()
  elseif ending_id == "consumed" then draw_ending_consumed()
  end
end

----------------------------------------------------------------
-- ENGINE CALLBACKS
----------------------------------------------------------------

function _init()
  mode(2)
end

function _start()
  scene = "title"
  title_pulse = 0
  title_idle = 0
  title_timer = 0
  demo_mode = false
  frame_count = 0
  puzzles_solved = {}
  amb_drip_timer = 30
  amb_creak_timer = 60
  sfx_wave(CH_SONAR, "sine")
  sfx_wave(CH_OBJ, "sine")
  sfx_wave(CH_AMB, "triangle")
  sfx_wave(CH_FOOT, "triangle")
end

function _update()
  idle_timer = idle_timer + 1
  if scene == "title" then
    title_update()
  elseif scene == "game" then
    tick = tick + 1
    game_update()
  elseif scene == "puzzle" then
    puzzle_update()
  elseif scene == "doc" then
    tick = tick + 1
    doc_update()
  elseif scene == "ending" then
    ending_update()
  end
end

function _draw()
  if scene == "title" then
    title_draw()
  elseif scene == "game" then
    game_draw()
  elseif scene == "puzzle" then
    puzzle_draw()
  elseif scene == "doc" then
    doc_draw()
  elseif scene == "ending" then
    ending_draw()
  end
end
