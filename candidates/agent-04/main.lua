-- THE DARK ROOM
-- A horror game for Mono Fantasy Console
-- 160x120 | 2-bit (4 shades: 0-3) | 30fps
-- D-Pad: Move | A: Interact | B: Toggle flashlight | START: Start | SELECT: Pause

---------- CONSTANTS ----------
local W = SCREEN_W or 160
local H = SCREEN_H or 120
local S -- screen surface

-- Colors in 2-bit mode: 0=black, 1=dark, 2=dim, 3=bright
local BLACK = 0
local DARK = 1
local DIM = 2
local BRIGHT = 3

local TILE = 8
local MAP_W = 20 -- tiles across (160/8)
local MAP_H = 15 -- tiles down (120/8)

---------- SAFE AUDIO ----------
local function sfx_note(ch, n, dur)
  if note then note(ch, n, dur) end
end
local function sfx_noise(ch, dur)
  if noise then noise(ch, dur) end
end

---------- UTILITY ----------
local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function dist(x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  return math.sqrt(dx * dx + dy * dy)
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

---------- FORWARD DECLARATIONS ----------
local init_game, init_rooms, reset_entity
local update_title, update_play, update_gameover, update_pause
local draw_title, draw_play, draw_gameover, draw_pause, draw_hud
local draw_flashlight, draw_room, draw_entity
local check_interact, move_entity, entity_ai
local trigger_scare, apply_shake

---------- STATE ----------
local state -- "title", "play", "paused", "gameover", "demo"
local paused = false
local pause_sel = 0

-- Player
local px, py           -- pixel position (center)
local pdir             -- facing direction: 0=up,1=right,2=down,3=left
local p_speed = 1.2
local p_step_timer = 0
local p_alive = true

-- Flashlight
local fl_on = true
local fl_battery = 100 -- percent
local fl_flicker = 0   -- flicker timer
local fl_range = 50    -- pixels
local fl_angle = 0.5   -- half-cone in radians (~28 degrees)

-- Entity (the stalker)
local ex, ey           -- entity pixel position
local e_speed = 0.4
local e_room = -1      -- which room entity is in
local e_active = false
local e_dist = 999     -- distance to player
local e_visible = false
local e_chase = false
local e_patrol_x, e_patrol_y
local e_timer = 0

-- Scare system
local scare_timer = 0
local scare_flash = 0
local shake_timer = 0
local shake_amt = 0

-- Inventory
local inv_keys = {}    -- list of key colors/ids collected
local inv_batteries = 0
local inv_notes = {}

-- Rooms
local rooms = {}
local current_room = 1
local room_transition = 0 -- >0 means transitioning

-- Ambient
local amb_drip_timer = 0
local amb_creak_timer = 0
local heartbeat_rate = 0  -- 0=calm, increases near entity
local heartbeat_timer = 0
local footstep_timer = 0  -- entity footsteps
local footstep_volume = 0

-- Demo mode
local demo_mode = false
local demo_timer = 0
local demo_dir = 0
local demo_dir_timer = 0
local idle_timer = 0
local IDLE_THRESHOLD = 150 -- 5 seconds at 30fps
local DEMO_DURATION = 450  -- 15 seconds

-- Messages
local msg_text = ""
local msg_timer = 0

-- Particles (dust, sparks)
local particles = {}

---------- ROOM DEFINITIONS ----------
-- Each room: walls (1=wall, 0=floor), doors, items, spawn points
-- Rooms are 20x15 tile grids

local function make_room(id, name)
  local r = {
    id = id,
    name = name,
    tiles = {},
    doors = {},  -- {tx,ty, target_room, target_x, target_y, locked, key_id}
    items = {},  -- {tx,ty, type, id, collected}
    explored = false,
  }
  -- Init all walls
  for y = 0, MAP_H - 1 do
    r.tiles[y] = {}
    for x = 0, MAP_W - 1 do
      r.tiles[y][x] = 1 -- wall by default
    end
  end
  return r
end

local function carve(r, x1, y1, x2, y2)
  for y = y1, y2 do
    for x = x1, x2 do
      if r.tiles[y] then r.tiles[y][x] = 0 end
    end
  end
end

local function add_door(r, tx, ty, target, ttx, tty, locked, key_id)
  r.doors[#r.doors + 1] = {
    tx = tx, ty = ty,
    target_room = target, target_x = ttx, target_y = tty,
    locked = locked or false, key_id = key_id or nil,
  }
end

local function add_item(r, tx, ty, itype, iid)
  r.items[#r.items + 1] = {
    tx = tx, ty = ty, type = itype, id = iid or "", collected = false,
  }
end

init_rooms = function()
  rooms = {}

  -- Room 1: Starting room (small, claustrophobic)
  local r1 = make_room(1, "Cell")
  carve(r1, 2, 2, 17, 12)
  -- pillars for atmosphere
  r1.tiles[5][5] = 1
  r1.tiles[5][14] = 1
  r1.tiles[9][5] = 1
  r1.tiles[9][14] = 1
  -- Door east
  add_door(r1, 17, 7, 2, 2, 7, false)
  -- Battery on floor
  add_item(r1, 10, 10, "battery")
  -- Note
  add_item(r1, 4, 3, "note", "note1")
  rooms[1] = r1

  -- Room 2: Hallway (long corridor)
  local r2 = make_room(2, "Corridor")
  carve(r2, 1, 5, 18, 9)
  -- alcoves
  carve(r2, 6, 3, 8, 5)
  carve(r2, 12, 9, 14, 11)
  -- Door west to room 1
  add_door(r2, 1, 7, 1, 16, 7, false)
  -- Door east to room 3
  add_door(r2, 18, 7, 3, 2, 7, true, "red")
  -- Door south to room 4
  add_door(r2, 10, 9, 4, 10, 2, false)
  -- Red key in alcove
  add_item(r2, 13, 10, "key", "red")
  -- Battery
  add_item(r2, 7, 4, "battery")
  rooms[2] = r2

  -- Room 3: Library (wide room with shelves)
  local r3 = make_room(3, "Library")
  carve(r3, 1, 1, 18, 13)
  -- shelf rows
  for x = 3, 16, 3 do
    for y = 3, 5 do r3.tiles[y][x] = 1 end
    for y = 8, 10 do r3.tiles[y][x] = 1 end
  end
  -- Door west to room 2
  add_door(r3, 1, 7, 2, 17, 7, false)
  -- Door north to room 5
  add_door(r3, 10, 1, 5, 10, 12, true, "blue")
  -- Blue key
  add_item(r3, 16, 12, "key", "blue")
  -- Note
  add_item(r3, 5, 6, "note", "note2")
  -- Battery
  add_item(r3, 14, 2, "battery")
  rooms[3] = r3

  -- Room 4: Storage (cluttered)
  local r4 = make_room(4, "Storage")
  carve(r4, 2, 1, 17, 13)
  -- crates/obstacles
  r4.tiles[4][5] = 1; r4.tiles[4][6] = 1
  r4.tiles[5][5] = 1; r4.tiles[5][6] = 1
  r4.tiles[8][10] = 1; r4.tiles[8][11] = 1
  r4.tiles[9][10] = 1; r4.tiles[9][11] = 1
  r4.tiles[6][15] = 1; r4.tiles[7][15] = 1
  r4.tiles[3][12] = 1; r4.tiles[3][13] = 1
  r4.tiles[10][4] = 1; r4.tiles[11][4] = 1
  -- Door north to room 2
  add_door(r4, 10, 1, 2, 10, 8, false)
  -- Battery
  add_item(r4, 15, 12, "battery")
  -- Note
  add_item(r4, 3, 8, "note", "note3")
  rooms[4] = r4

  -- Room 5: Exit room (final)
  local r5 = make_room(5, "Exit")
  carve(r5, 3, 3, 16, 11)
  -- central pillar
  r5.tiles[7][9] = 1; r5.tiles[7][10] = 1
  r5.tiles[8][9] = 1; r5.tiles[8][10] = 1
  -- Door south to room 3
  add_door(r5, 10, 11, 3, 10, 2, false)
  -- Exit door (special)
  add_item(r5, 10, 4, "exit")
  -- Final note
  add_item(r5, 6, 6, "note", "note4")
  rooms[5] = r5
end

---------- COLLISION ----------
local function solid_at(room, px_x, px_y)
  local tx = math.floor(px_x / TILE)
  local ty = math.floor(px_y / TILE)
  if tx < 0 or tx >= MAP_W or ty < 0 or ty >= MAP_H then return true end
  local r = rooms[room]
  if not r then return true end
  return r.tiles[ty][tx] == 1
end

local function can_move(room, cx, cy, dx, dy, radius)
  radius = radius or 3
  local nx, ny = cx + dx, cy + dy
  -- Check corners of bounding box
  if solid_at(room, nx - radius, ny - radius) then return false end
  if solid_at(room, nx + radius, ny - radius) then return false end
  if solid_at(room, nx - radius, ny + radius) then return false end
  if solid_at(room, nx + radius, ny + radius) then return false end
  return true
end

---------- GAME INIT ----------
init_game = function()
  init_rooms()
  px = 10 * TILE + 4
  py = 7 * TILE + 4
  pdir = 1  -- facing right
  p_alive = true
  fl_on = true
  fl_battery = 100
  fl_flicker = 0
  current_room = 1
  rooms[1].explored = true

  inv_keys = {}
  inv_batteries = 0
  inv_notes = {}

  particles = {}
  scare_timer = 0
  scare_flash = 0
  shake_timer = 0
  shake_amt = 0
  heartbeat_rate = 0
  msg_text = ""
  msg_timer = 0

  -- Entity starts in room 3
  reset_entity()
end

reset_entity = function()
  e_room = 3
  ex = 10 * TILE + 4
  ey = 7 * TILE + 4
  e_active = true
  e_chase = false
  e_timer = 0
  e_speed = 0.4
  e_patrol_x = ex
  e_patrol_y = ey
end

---------- SCARE SYSTEM ----------
trigger_scare = function(intensity)
  scare_flash = 4 + intensity * 2
  shake_timer = 8 + intensity * 4
  shake_amt = 2 + intensity * 2
  -- Harsh noise burst
  sfx_noise(0, 0.15 + intensity * 0.1)
  sfx_note(1, "C2", 0.2 + intensity * 0.1)
  sfx_note(2, "F#2", 0.15)
  if cam_shake then cam_shake(shake_amt) end
end

apply_shake = function()
  if shake_timer > 0 then
    shake_timer = shake_timer - 1
    if cam_shake then cam_shake(shake_amt * (shake_timer / 10)) end
  end
end

---------- AMBIENT SOUND ----------
local function update_ambient()
  -- Dripping water
  amb_drip_timer = amb_drip_timer - 1
  if amb_drip_timer <= 0 then
    amb_drip_timer = 40 + math.random(80)
    sfx_note(3, "E6", 0.02)
  end

  -- Random creak
  amb_creak_timer = amb_creak_timer - 1
  if amb_creak_timer <= 0 then
    amb_creak_timer = 90 + math.random(120)
    local creaks = {"A2", "B2", "G2", "D2"}
    sfx_note(2, creaks[math.random(#creaks)], 0.12)
  end

  -- Heartbeat based on entity distance
  if e_active and e_room == current_room then
    local d = dist(px, py, ex, ey)
    heartbeat_rate = clamp(1 - (d / 120), 0, 1)
  else
    heartbeat_rate = math.max(heartbeat_rate - 0.005, 0)
  end

  if heartbeat_rate > 0.1 then
    heartbeat_timer = heartbeat_timer - 1
    local interval = math.floor(lerp(30, 8, heartbeat_rate))
    if heartbeat_timer <= 0 then
      heartbeat_timer = interval
      sfx_note(0, "C3", 0.06)
      -- Double beat
      if heartbeat_rate > 0.4 then
        sfx_note(0, "C3", 0.04)
      end
    end
  end

  -- Entity footsteps (audible when in same or adjacent room)
  if e_active then
    local audible = (e_room == current_room)
    if not audible then
      -- Check if adjacent room
      local r = rooms[current_room]
      for _, door in ipairs(r.doors) do
        if door.target_room == e_room then audible = true; break end
      end
    end
    if audible then
      e_timer = e_timer + 1
      local step_interval = 12
      if e_chase then step_interval = 7 end
      if e_timer % step_interval == 0 then
        local vol_factor = 1
        if e_room ~= current_room then vol_factor = 0.3 end
        if vol_factor > 0.2 then
          local steps = {"D4", "E4", "D4", "C4"}
          sfx_note(3, steps[(e_timer / step_interval) % 4 + 1] or "D4", 0.03)
        end
      end
    end
  end
end

---------- ENTITY AI ----------
entity_ai = function()
  if not e_active then return end

  local same_room = (e_room == current_room)

  -- If in same room, chase player
  if same_room then
    e_chase = true
    e_speed = lerp(e_speed, 0.7, 0.01) -- gradually speed up

    local dx = px - ex
    local dy = py - ey
    local d = dist(px, py, ex, ey)
    e_dist = d

    if d > 2 then
      local mx = (dx / d) * e_speed
      local my = (dy / d) * e_speed

      if can_move(e_room, ex, ey, mx, 0, 3) then
        ex = ex + mx
      end
      if can_move(e_room, ex, ey, 0, my, 3) then
        ey = ey + my
      end
    end

    -- Check if caught player
    if d < 8 then
      trigger_scare(3)
      p_alive = false
      -- Death sound
      sfx_note(0, "C2", 0.4)
      sfx_note(1, "F#2", 0.4)
      sfx_noise(2, 0.4)
    end

    -- Random scare if close
    if d < 30 and math.random(100) < 3 then
      trigger_scare(1)
    end
  else
    -- Patrol / wander toward player's room
    e_chase = false
    e_speed = 0.4

    -- Slowly move toward doors that lead closer to player
    e_timer = e_timer + 1
    if e_timer % 60 == 0 then
      -- Pick a random door in current entity room
      local r = rooms[e_room]
      if r and #r.doors > 0 then
        local door = r.doors[math.random(#r.doors)]
        e_patrol_x = door.tx * TILE + 4
        e_patrol_y = door.ty * TILE + 4

        -- Chance to move through door
        if math.random(100) < 40 then
          -- Check if door leads toward player
          if door.target_room == current_room or math.random(100) < 25 then
            e_room = door.target_room
            ex = door.target_x * TILE + 4
            ey = door.target_y * TILE + 4
            -- Play distant door sound
            if door.target_room == current_room then
              sfx_note(2, "G2", 0.1)
              msg_text = "...a door creaks..."
              msg_timer = 60
            end
          end
        end
      end
    end

    -- Move toward patrol point
    local dx = e_patrol_x - ex
    local dy = e_patrol_y - ey
    local d = math.sqrt(dx * dx + dy * dy)
    if d > 2 then
      local mx = (dx / d) * e_speed
      local my = (dy / d) * e_speed
      if can_move(e_room, ex, ey, mx, 0, 3) then ex = ex + mx end
      if can_move(e_room, ex, ey, 0, my, 3) then ey = ey + my end
    end
  end
end

---------- INTERACTION ----------
check_interact = function()
  local r = rooms[current_room]
  if not r then return end

  -- Check doors
  for _, door in ipairs(r.doors) do
    local dx = door.tx * TILE + 4 - px
    local dy = door.ty * TILE + 4 - py
    if math.abs(dx) < 10 and math.abs(dy) < 10 then
      if door.locked then
        -- Check for key
        local has_key = false
        for i, k in ipairs(inv_keys) do
          if k == door.key_id then
            has_key = true
            table.remove(inv_keys, i)
            break
          end
        end
        if has_key then
          door.locked = false
          msg_text = "Unlocked!"
          msg_timer = 45
          sfx_note(0, "C5", 0.08)
          sfx_note(0, "E5", 0.06)
        else
          msg_text = "Locked. Need " .. (door.key_id or "?") .. " key"
          msg_timer = 60
          sfx_note(0, "E3", 0.1)
        end
      else
        -- Transition
        current_room = door.target_room
        px = door.target_x * TILE + 4
        py = door.target_y * TILE + 4
        rooms[current_room].explored = true
        room_transition = 15
        msg_text = rooms[current_room].name
        msg_timer = 45
        sfx_note(2, "A3", 0.08)
        -- Darkness flash on room enter
        scare_flash = 0
        return
      end
    end
  end

  -- Check items
  for _, item in ipairs(r.items) do
    if not item.collected then
      local dx = item.tx * TILE + 4 - px
      local dy = item.ty * TILE + 4 - py
      if math.abs(dx) < 10 and math.abs(dy) < 10 then
        item.collected = true
        if item.type == "key" then
          inv_keys[#inv_keys + 1] = item.id
          msg_text = "Found " .. item.id .. " key!"
          msg_timer = 60
          sfx_note(0, "C5", 0.06)
          sfx_note(0, "G5", 0.06)
        elseif item.type == "battery" then
          inv_batteries = inv_batteries + 1
          msg_text = "Found battery!"
          msg_timer = 45
          sfx_note(0, "E5", 0.05)
        elseif item.type == "note" then
          inv_notes[#inv_notes + 1] = item.id
          msg_text = "Found a note..."
          msg_timer = 60
          sfx_note(0, "A4", 0.08)
        elseif item.type == "exit" then
          -- WIN!
          state = "win"
          sfx_note(0, "C5", 0.15)
          sfx_note(1, "E5", 0.15)
          sfx_note(2, "G5", 0.15)
          return
        end
      end
    end
  end
end

---------- PARTICLES ----------
local function add_particle(x, y, c)
  if #particles > 30 then return end
  particles[#particles + 1] = {
    x = x, y = y,
    vx = (math.random() - 0.5) * 1.5,
    vy = (math.random() - 0.5) * 1.5,
    life = 10 + math.random(15),
    c = c or DIM,
  }
end

local function update_particles()
  local i = 1
  while i <= #particles do
    local p = particles[i]
    p.x = p.x + p.vx
    p.y = p.y + p.vy
    p.life = p.life - 1
    if p.life <= 0 then
      particles[i] = particles[#particles]
      particles[#particles] = nil
    else
      i = i + 1
    end
  end
end

---------- DRAWING ----------

-- Check if a point is within the flashlight cone
local function in_light(wx, wy)
  if not fl_on then return false end
  local dx = wx - px
  local dy = wy - py

  local d = math.sqrt(dx * dx + dy * dy)
  if d > fl_range then return false end

  -- Direction vectors
  local dir_x = ({0, 1, 0, -1})[pdir + 1]
  local dir_y = ({-1, 0, 1, 0})[pdir + 1]

  if d < 8 then return true end -- always lit right around player

  -- Angle check
  local dot = (dx * dir_x + dy * dir_y) / d
  return dot > math.cos(fl_angle + 0.2) -- slightly wider than stated
end

local function light_level(wx, wy)
  if not fl_on then
    -- Tiny ambient glow around player
    local d = dist(wx, wy, px, py)
    if d < 12 then return DARK end
    return BLACK
  end

  local d = dist(wx, wy, px, py)

  -- Always see immediate surroundings dimly
  if d < 10 then return DIM end

  if not in_light(wx, wy) then
    if d < 16 then return DARK end
    return BLACK
  end

  -- Flickering effect
  local flick = 0
  if fl_flicker > 0 then
    flick = math.random(0, 1)
  end

  if d < 20 then return BRIGHT - flick end
  if d < 35 then return DIM end
  if d < fl_range then return DARK end
  return BLACK
end

draw_room = function()
  local r = rooms[current_room]
  if not r then return end

  -- Draw tiles with lighting
  for ty = 0, MAP_H - 1 do
    for tx = 0, MAP_W - 1 do
      local wx = tx * TILE + 4
      local wy = ty * TILE + 4
      local ll = light_level(wx, wy)

      if ll > BLACK then
        local x = tx * TILE
        local y = ty * TILE
        if r.tiles[ty][tx] == 1 then
          -- Wall
          if ll >= DIM then
            rect(S, x, y, TILE, TILE, DIM)
            -- Wall detail
            if (tx + ty) % 3 == 0 then
              line(S, x + 1, y + 1, x + TILE - 2, y + 1, DARK)
            end
          else
            rect(S, x, y, TILE, TILE, DARK)
          end
        else
          -- Floor
          if ll >= BRIGHT then
            -- Bright floor with detail
            if (tx + ty) % 2 == 0 then
              pix(S, x + 3, y + 3, DARK)
            end
          elseif ll >= DIM then
            -- Subtle floor marks
            if (tx + ty) % 4 == 0 then
              pix(S, x + 4, y + 4, DARK)
            end
          end
        end
      end
    end
  end

  -- Draw doors
  for _, door in ipairs(r.doors) do
    local wx = door.tx * TILE + 4
    local wy = door.ty * TILE + 4
    local ll = light_level(wx, wy)
    if ll > BLACK then
      local x = door.tx * TILE
      local y = door.ty * TILE
      if door.locked then
        rect(S, x + 1, y + 1, TILE - 2, TILE - 2, ll)
        -- Lock symbol
        if ll >= DIM then
          pix(S, x + 4, y + 3, BRIGHT)
          rect(S, x + 3, y + 4, 3, 2, BRIGHT)
        end
      else
        -- Open doorway
        rect(S, x + 1, y + 1, TILE - 2, TILE - 2, ll)
        line(S, x + 2, y + 2, x + TILE - 3, y + TILE - 3, ll)
      end
    end
  end

  -- Draw items
  for _, item in ipairs(r.items) do
    if not item.collected then
      local wx = item.tx * TILE + 4
      local wy = item.ty * TILE + 4
      local ll = light_level(wx, wy)
      if ll > BLACK then
        local x = item.tx * TILE
        local y = item.ty * TILE
        local pulse = math.floor(frame() / 10) % 2

        if item.type == "key" then
          -- Key glyph
          pix(S, x + 3, y + 3, BRIGHT)
          pix(S, x + 4, y + 4, BRIGHT)
          pix(S, x + 5, y + 3, DIM + pulse)
        elseif item.type == "battery" then
          -- Battery shape
          rect(S, x + 2, y + 3, 4, 3, DIM + pulse)
          pix(S, x + 6, y + 4, DIM)
        elseif item.type == "note" then
          -- Paper
          rect(S, x + 2, y + 2, 4, 5, DIM + pulse)
          line(S, x + 3, y + 3, x + 5, y + 3, DARK)
          line(S, x + 3, y + 5, x + 4, y + 5, DARK)
        elseif item.type == "exit" then
          -- Exit marker
          rect(S, x + 1, y + 1, 6, 6, BRIGHT)
          pix(S, x + 4, y + 4, BLACK)
        end
      end
    end
  end
end

draw_entity = function()
  if not e_active or e_room ~= current_room then return end

  local ll = light_level(ex, ey)
  local d = dist(px, py, ex, ey)

  -- Entity is slightly visible even in darkness when very close
  if d < 25 and ll == BLACK then ll = DARK end

  if ll > BLACK then
    e_visible = true
    -- Draw entity: hunched figure
    local blink = math.floor(frame() / 4) % 2

    if ll >= DIM then
      -- Full visible: dark silhouette with bright eyes
      -- Body
      circ(S, math.floor(ex), math.floor(ey), 4, DARK)
      -- Eyes - two bright dots
      local eye_dx = ({0, 1, 0, -1})[pdir + 1] or 0
      local eye_dy = ({-1, 0, 1, 0})[pdir + 1] or 0
      pix(S, math.floor(ex) - 1, math.floor(ey) - 1, BRIGHT * blink)
      pix(S, math.floor(ex) + 1, math.floor(ey) - 1, BRIGHT * blink)
    elseif ll >= DARK then
      -- Barely visible: just eyes
      if blink == 1 then
        pix(S, math.floor(ex) - 1, math.floor(ey) - 1, DIM)
        pix(S, math.floor(ex) + 1, math.floor(ey) - 1, DIM)
      end
    end
  else
    e_visible = false
  end
end

local function draw_player()
  local bx = math.floor(px)
  local by = math.floor(py)

  -- Player body
  circ(S, bx, by, 3, DIM)
  pix(S, bx, by, BRIGHT)

  -- Direction indicator
  local dir_x = ({0, 1, 0, -1})[pdir + 1]
  local dir_y = ({-1, 0, 1, 0})[pdir + 1]
  pix(S, bx + dir_x * 3, by + dir_y * 3, BRIGHT)

  -- Flashlight beam hint
  if fl_on and fl_flicker <= 0 then
    local blen = 6
    line(S, bx + dir_x * 4, by + dir_y * 4,
         bx + dir_x * blen, by + dir_y * blen, DIM)
  end
end

draw_flashlight = function()
  -- The flashlight cone is handled by the light_level function
  -- This draws the cone edge effect
  if not fl_on then return end
  if fl_flicker > 0 and math.random(3) == 1 then return end

  local dir_x = ({0, 1, 0, -1})[pdir + 1]
  local dir_y = ({-1, 0, 1, 0})[pdir + 1]

  -- Subtle cone edge particles
  if frame() % 3 == 0 then
    local spread = 8
    local fx = px + dir_x * fl_range * 0.6 + (math.random() - 0.5) * spread
    local fy = py + dir_y * fl_range * 0.6 + (math.random() - 0.5) * spread
    if fx >= 0 and fx < W and fy >= 0 and fy < H then
      pix(S, math.floor(fx), math.floor(fy), DARK)
    end
  end
end

draw_hud = function()
  -- Battery meter (top-left)
  local bat_w = 20
  local bat_fill = math.floor(bat_w * fl_battery / 100)

  rect(S, 2, 1, bat_w + 2, 5, DIM)
  if bat_fill > 0 then
    rect(S, 3, 2, bat_fill, 3, fl_battery < 20 and (frame() % 6 < 3 and BRIGHT or DARK) or BRIGHT)
  end

  -- Key indicators (top-right)
  local kx = W - 3
  for i = #inv_keys, 1, -1 do
    pix(S, kx, 3, BRIGHT)
    pix(S, kx - 1, 2, DIM)
    kx = kx - 5
  end

  -- Room name during transition
  if msg_timer > 0 then
    local alpha = msg_timer > 10 and BRIGHT or DIM
    text(S, msg_text, W / 2, H - 12, alpha, ALIGN_CENTER)
  end

  -- Battery count
  if inv_batteries > 0 then
    text(S, "x" .. inv_batteries, 26, 1, DIM)
  end
end

---------- TITLE SCREEN ----------
local title_flicker = 0
local title_timer = 0

draw_title = function()
  cls(S, BLACK)
  title_timer = title_timer + 1

  -- Flickering title
  local flick = math.random(100)
  local title_c = BRIGHT
  if flick < 8 then title_c = DARK
  elseif flick < 15 then title_c = DIM end

  -- Occasional full blackout
  if title_flicker > 0 then
    title_flicker = title_flicker - 1
    if title_flicker > 3 then title_c = BLACK end
  elseif math.random(200) < 3 then
    title_flicker = 6
  end

  if title_c > BLACK then
    text(S, "THE DARK ROOM", W / 2, 30, title_c, ALIGN_CENTER)
  end

  -- Subtitle
  if title_timer > 30 then
    text(S, "you wake up.", W / 2, 48, DIM, ALIGN_CENTER)
  end
  if title_timer > 60 then
    text(S, "you can't see.", W / 2, 58, DARK, ALIGN_CENTER)
  end
  if title_timer > 90 then
    text(S, "you are not alone.", W / 2, 68, DARK, ALIGN_CENTER)
  end

  -- Start prompt
  if title_timer > 120 then
    local blink = math.floor(frame() / 20) % 2
    if blink == 0 then
      text(S, "PRESS START", W / 2, 95, DIM, ALIGN_CENTER)
    end
  end

  -- Ambient eyes in darkness
  if title_timer > 60 and math.random(100) < 5 then
    local ex2 = math.random(20, W - 20)
    local ey2 = math.random(80, H - 20)
    pix(S, ex2, ey2, DARK)
    pix(S, ex2 + 2, ey2, DARK)
  end
end

---------- GAME OVER SCREEN ----------
local gameover_timer = 0

draw_gameover = function()
  cls(S, BLACK)
  gameover_timer = gameover_timer + 1

  -- Static/noise effect
  if gameover_timer < 15 then
    for i = 1, 80 do
      pix(S, math.random(0, W - 1), math.random(0, H - 1), math.random(0, BRIGHT))
    end
    return
  end

  -- Flickering "YOU DIED"
  local flick = math.random(100)
  if flick > 10 then
    text(S, "IT GOT YOU", W / 2, 40, BRIGHT, ALIGN_CENTER)
  end

  if gameover_timer > 45 then
    -- Show stats
    local notes_found = #inv_notes
    local rooms_explored = 0
    for _, r in ipairs(rooms) do
      if r.explored then rooms_explored = rooms_explored + 1 end
    end
    text(S, "Rooms: " .. rooms_explored .. "/5", W / 2, 60, DIM, ALIGN_CENTER)
    text(S, "Notes: " .. notes_found .. "/4", W / 2, 70, DIM, ALIGN_CENTER)
  end

  if gameover_timer > 75 then
    local blink = math.floor(frame() / 20) % 2
    if blink == 0 then
      text(S, "START to retry", W / 2, 95, DIM, ALIGN_CENTER)
    end
  end
end

---------- WIN SCREEN ----------
local win_timer = 0

local function draw_win()
  cls(S, BLACK)
  win_timer = win_timer + 1

  if win_timer < 20 then
    -- Bright flash of escape
    local c = win_timer < 10 and BRIGHT or DIM
    cls(S, c)
    return
  end

  text(S, "YOU ESCAPED", W / 2, 35, BRIGHT, ALIGN_CENTER)

  if win_timer > 30 then
    text(S, "The light outside", W / 2, 52, DIM, ALIGN_CENTER)
    text(S, "has never felt", W / 2, 62, DIM, ALIGN_CENTER)
    text(S, "so warm.", W / 2, 72, DIM, ALIGN_CENTER)
  end

  if win_timer > 90 then
    local notes_found = #inv_notes
    text(S, "Notes: " .. notes_found .. "/4", W / 2, 88, DARK, ALIGN_CENTER)
    local blink = math.floor(frame() / 20) % 2
    if blink == 0 then
      text(S, "START to play again", W / 2, 105, DIM, ALIGN_CENTER)
    end
  end
end

---------- PAUSE SCREEN ----------
draw_pause = function()
  -- Darken screen
  -- Draw overlay
  rect(S, 30, 30, 100, 60, BLACK)
  rect(S, 31, 31, 98, 58, DARK)

  text(S, "PAUSED", W / 2, 38, BRIGHT, ALIGN_CENTER)
  text(S, "SELECT to resume", W / 2, 55, DIM, ALIGN_CENTER)
  text(S, "START to quit", W / 2, 68, DIM, ALIGN_CENTER)
end

---------- DEMO MODE ----------
local function update_demo()
  demo_timer = demo_timer + 1

  -- AI movement: wander randomly
  demo_dir_timer = demo_dir_timer - 1
  if demo_dir_timer <= 0 then
    demo_dir = math.random(0, 3)
    demo_dir_timer = 20 + math.random(40)
  end

  -- Move
  local dx, dy = 0, 0
  if demo_dir == 0 then dy = -p_speed
  elseif demo_dir == 1 then dx = p_speed
  elseif demo_dir == 2 then dy = p_speed
  elseif demo_dir == 3 then dx = -p_speed
  end

  pdir = demo_dir

  if can_move(current_room, px, py, dx, 0, 3) then
    px = px + dx
  else
    demo_dir_timer = 0  -- change direction on wall hit
  end
  if can_move(current_room, px, py, 0, dy, 3) then
    py = py + dy
  else
    demo_dir_timer = 0
  end

  -- Occasionally interact
  if demo_timer % 45 == 0 then
    check_interact()
  end

  -- Toggle flashlight occasionally
  if demo_timer % 90 == 0 and math.random(3) == 1 then
    fl_on = not fl_on
  end

  -- Battery management
  if fl_battery < 20 and inv_batteries > 0 then
    fl_battery = math.min(fl_battery + 40, 100)
    inv_batteries = inv_batteries - 1
  end

  -- Exit demo on input
  if btnp("start") or btnp("a") or btnp("b") or
     btnp("up") or btnp("down") or btnp("left") or btnp("right") or
     (touch_start and touch_start()) then
    state = "title"
    title_timer = 0
    idle_timer = 0
    return
  end

  -- End demo after duration
  if demo_timer >= DEMO_DURATION then
    state = "title"
    title_timer = 0
    idle_timer = 0
  end
end

---------- UPDATE ----------
update_play = function()
  if not p_alive then
    state = "gameover"
    gameover_timer = 0
    return
  end

  -- Room transition effect
  if room_transition > 0 then
    room_transition = room_transition - 1
    return -- freeze during transition
  end

  -- Movement
  local dx, dy = 0, 0
  if btn("up")    then dy = -p_speed; pdir = 0 end
  if btn("down")  then dy =  p_speed; pdir = 2 end
  if btn("left")  then dx = -p_speed; pdir = 3 end
  if btn("right") then dx =  p_speed; pdir = 1 end

  -- Touch movement
  if touch and touch() then
    local tx_pos, ty_pos = touch_pos()
    if tx_pos then
      local tdx = tx_pos - px
      local tdy = ty_pos - py
      local td = math.sqrt(tdx * tdx + tdy * tdy)
      if td > 5 then
        dx = (tdx / td) * p_speed
        dy = (tdy / td) * p_speed
        -- Set direction based on dominant axis
        if math.abs(tdx) > math.abs(tdy) then
          pdir = tdx > 0 and 1 or 3
        else
          pdir = tdy > 0 and 2 or 0
        end
      end
    end
  end

  if can_move(current_room, px, py, dx, 0, 3) then px = px + dx end
  if can_move(current_room, px, py, 0, dy, 3) then py = py + dy end

  -- Footstep sound
  if dx ~= 0 or dy ~= 0 then
    p_step_timer = p_step_timer + 1
    if p_step_timer % 10 == 0 then
      sfx_note(3, p_step_timer % 20 == 0 and "A5" or "G5", 0.02)
    end
    idle_timer = 0
  else
    idle_timer = idle_timer + 1
  end

  -- Interact
  if btnp("a") or (touch_start and touch_start()) then
    check_interact()
  end

  -- Toggle flashlight
  if btnp("b") then
    if fl_on then
      fl_on = false
      sfx_note(0, "E3", 0.03)
    else
      if fl_battery > 0 then
        fl_on = true
        sfx_note(0, "G4", 0.03)
      else
        msg_text = "No battery!"
        msg_timer = 30
        sfx_note(0, "C3", 0.06)
      end
    end
  end

  -- Use battery (auto when low, or when pressing A near empty)
  if fl_battery <= 0 and fl_on then
    if inv_batteries > 0 then
      inv_batteries = inv_batteries - 1
      fl_battery = 50
      msg_text = "Battery replaced"
      msg_timer = 30
      sfx_note(0, "E5", 0.05)
    else
      fl_on = false
      msg_text = "Light dies..."
      msg_timer = 60
      sfx_note(0, "C2", 0.15)
    end
  end

  -- Battery drain
  if fl_on then
    fl_battery = fl_battery - 0.06
    -- Random flicker when low
    if fl_battery < 30 then
      if math.random(100) < (30 - fl_battery) then
        fl_flicker = 2 + math.random(3)
      end
    end
    -- Normal occasional flicker for atmosphere
    if math.random(500) < 2 then
      fl_flicker = 1 + math.random(2)
    end
  end

  if fl_flicker > 0 then fl_flicker = fl_flicker - 1 end

  -- Entity AI
  entity_ai()

  -- Ambient sounds
  update_ambient()

  -- Particles
  update_particles()

  -- Shake
  apply_shake()

  -- Scare flash
  if scare_flash > 0 then scare_flash = scare_flash - 1 end

  -- Message timer
  if msg_timer > 0 then msg_timer = msg_timer - 1 end

  -- Pause
  if btnp("select") then
    state = "paused"
  end
end

---------- MAIN DRAW ----------
draw_play = function()
  cls(S, BLACK)

  -- Room transition: black flash
  if room_transition > 0 then
    if room_transition > 10 then
      cls(S, BLACK)
    else
      draw_room()
      draw_entity()
      draw_player()
      draw_flashlight()
    end
    draw_hud()
    return
  end

  -- Scare flash overlay
  if scare_flash > 0 then
    if scare_flash > 4 then
      cls(S, BRIGHT)
      -- Draw entity face close up during intense scare
      text(S, "!", W / 2, H / 2, BLACK, ALIGN_CENTER)
      return
    end
  end

  -- Normal render
  draw_room()
  draw_entity()
  draw_player()
  draw_flashlight()
  draw_hud()

  -- Draw particles
  for _, p in ipairs(particles) do
    if p.x >= 0 and p.x < W and p.y >= 0 and p.y < H then
      pix(S, math.floor(p.x), math.floor(p.y), p.c)
    end
  end

  -- Vignette effect: darken edges
  for i = 0, W - 1, 2 do
    pix(S, i, 0, BLACK)
    pix(S, i, 1, BLACK)
    pix(S, i, H - 1, BLACK)
    pix(S, i, H - 2, BLACK)
  end
  for i = 0, H - 1, 2 do
    pix(S, 0, i, BLACK)
    pix(S, 1, i, BLACK)
    pix(S, W - 1, i, BLACK)
    pix(S, W - 2, i, BLACK)
  end
end

---------- ENGINE CALLBACKS ----------
function _init()
  mode(2)
end

function _start()
  state = "title"
  title_timer = 0
  idle_timer = 0
  init_game()
end

function _update()
  if state == "title" then
    idle_timer = idle_timer + 1

    if btnp("start") or (touch_start and touch_start()) then
      state = "play"
      init_game()
      msg_text = "Cell"
      msg_timer = 60
      idle_timer = 0
    end

    -- Enter demo after idle
    if idle_timer >= IDLE_THRESHOLD then
      state = "demo"
      demo_timer = 0
      demo_dir_timer = 0
      init_game()
      -- Make entity less aggressive in demo
      e_speed = 0.2
    end

  elseif state == "demo" then
    update_demo()
    update_play()

  elseif state == "play" then
    update_play()

  elseif state == "paused" then
    if btnp("select") then
      state = "play"
    elseif btnp("start") then
      state = "title"
      title_timer = 0
      idle_timer = 0
    end

  elseif state == "gameover" then
    gameover_timer = gameover_timer + 1
    if gameover_timer > 60 and (btnp("start") or (touch_start and touch_start())) then
      state = "play"
      init_game()
    end

  elseif state == "win" then
    win_timer = win_timer + 1
    if win_timer > 90 and (btnp("start") or (touch_start and touch_start())) then
      state = "title"
      title_timer = 0
      idle_timer = 0
    end
  end
end

function _draw()
  S = screen()

  if state == "title" then
    draw_title()
  elseif state == "demo" then
    draw_play()
    -- Demo overlay
    local blink = math.floor(frame() / 30) % 2
    if blink == 0 then
      text(S, "DEMO", 3, H - 8, DARK)
    end
  elseif state == "play" then
    draw_play()
  elseif state == "paused" then
    draw_play()
    draw_pause()
  elseif state == "gameover" then
    draw_gameover()
  elseif state == "win" then
    draw_win()
  end
end
