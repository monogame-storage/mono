-- THE DARK ROOM: SURVIVAL CRAFT
-- Horror + Crafting | Agent #12 | 160x120 | 2-bit (0-3) | mode(2)
-- Wake in darkness. Find objects. Combine them. Survive. Escape.
-- D-Pad:Move | A:Interact | B:Inventory/Craft | START:Start | SELECT:Pause

---------- CONSTANTS ----------
local W = SCREEN_W or 160
local H = SCREEN_H or 120
local S -- screen surface

-- Colors: 0=black, 1=dark, 2=dim, 3=bright
local BLACK = 0
local DARK = 1
local DIM = 2
local BRIGHT = 3

local TILE = 8
local MAP_W = 20  -- tiles across (160/8)
local MAP_H = 15  -- tiles down (120/8)

-- Inventory grid
local INV_COLS = 4
local INV_ROWS = 2
local INV_MAX = INV_COLS * INV_ROWS
local SLOT_W = 32
local SLOT_H = 24
local INV_X = (W - INV_COLS * SLOT_W) / 2
local INV_Y = 20

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

---------- ITEM DATABASE ----------
local ITEMS = {
  flashlight  = { id="flashlight",  name="Flashlight",   desc="Dead. Needs batteries.", icon="F" },
  batteries   = { id="batteries",   name="Batteries",    desc="Two AA batteries.",      icon="B" },
  lit_flash   = { id="lit_flash",   name="Flashlight*",  desc="Bright beam! Saves power.", icon="L" },
  wire        = { id="wire",        name="Wire",         desc="Thin copper wire.",       icon="W" },
  nail        = { id="nail",        name="Rusty Nail",   desc="Bent rusty nail.",        icon="N" },
  lockpick    = { id="lockpick",    name="Lockpick",     desc="Wire + nail pick.",       icon="P" },
  note_a      = { id="note_a",      name="Note (left)",  desc="Torn... 'THE EXIT'",      icon="1" },
  note_b      = { id="note_b",      name="Note (right)", desc="Torn... 'IS ABOVE'",      icon="2" },
  full_note   = { id="full_note",   name="Full Note",    desc="THE EXIT IS ABOVE",       icon="!" },
  red_key     = { id="red_key",     name="Red Key",      desc="Dull red key.",           icon="R" },
  blue_key    = { id="blue_key",    name="Blue Key",     desc="Cold blue key.",          icon="K" },
}

-- Crafting recipes: combine a+b -> result
local RECIPES = {
  { a="flashlight", b="batteries", result="lit_flash" },
  { a="wire",       b="nail",      result="lockpick" },
  { a="note_a",     b="note_b",    result="full_note" },
}

---------- FORWARD DECLARATIONS ----------
local init_game, init_rooms, reset_entity
local update_play, draw_play, draw_hud
local draw_room, draw_entity
local check_interact, entity_ai
local trigger_scare, apply_shake

---------- STATE ----------
local state       -- "title","play","inv","paused","gameover","win","demo"
local frame_count = 0

-- Player
local px, py              -- pixel position
local pdir = 1            -- 0=up,1=right,2=down,3=left
local p_speed = 1.2
local p_step_timer = 0
local p_alive = true

-- Flashlight
local fl_on = true
local fl_battery = 100
local fl_flicker = 0
local fl_range = 50
local fl_angle = 0.5
local fl_boosted = false  -- true when lit_flash crafted (better battery life)

-- Entity (stalker)
local ex, ey
local e_speed = 0.4
local e_room = -1
local e_active = false
local e_chase = false
local e_patrol_x, e_patrol_y
local e_timer = 0

-- Scare system
local scare_flash = 0
local shake_timer = 0
local shake_amt = 0

-- Crafting inventory (replaces old inv_keys/batteries/notes)
local inventory = {}       -- list of item ids, max INV_MAX
local inv_cursor = 1
local combine_first = nil  -- index of first selected item for combining

-- Rooms
local rooms = {}
local current_room = 1
local room_transition = 0

-- Ambient
local amb_drip_timer = 0
local amb_creak_timer = 0
local heartbeat_rate = 0
local heartbeat_timer = 0

-- Demo mode
local demo_mode = false
local demo_timer = 0
local demo_dir = 0
local demo_dir_timer = 0
local idle_timer = 0
local IDLE_THRESHOLD = 150
local DEMO_DURATION = 450

-- Messages
local msg_text = ""
local msg_timer = 0

-- Particles
local particles = {}

---------- INVENTORY MANAGEMENT ----------
local function has_item(id)
  for _, v in ipairs(inventory) do
    if v == id then return true end
  end
  return false
end

local function add_item(id)
  if #inventory < INV_MAX and not has_item(id) then
    table.insert(inventory, id)
    sfx_note(0, "E5", 4)
    sfx_note(1, "G5", 4)
    return true
  end
  return false
end

local function remove_item(id)
  for i, v in ipairs(inventory) do
    if v == id then
      table.remove(inventory, i)
      return true
    end
  end
  return false
end

local function try_combine(id_a, id_b)
  for _, r in ipairs(RECIPES) do
    if (id_a == r.a and id_b == r.b) or (id_a == r.b and id_b == r.a) then
      remove_item(id_a)
      remove_item(id_b)
      add_item(r.result)
      -- Side effects
      if r.result == "lit_flash" then
        fl_boosted = true
        fl_battery = math.min(fl_battery + 40, 100)
      end
      return ITEMS[r.result].name
    end
  end
  return nil
end

local function show_msg(msg, dur)
  msg_text = msg or ""
  msg_timer = dur or 45
end

---------- ROOM DEFINITIONS ----------
local function make_room(id, name)
  local r = {
    id = id, name = name, tiles = {},
    doors = {}, items = {}, explored = false,
  }
  for y = 0, MAP_H - 1 do
    r.tiles[y] = {}
    for x = 0, MAP_W - 1 do
      r.tiles[y][x] = 1
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

local function add_room_item(r, tx, ty, itype, iid)
  r.items[#r.items + 1] = {
    tx = tx, ty = ty, type = itype, id = iid or "", collected = false,
  }
end

init_rooms = function()
  rooms = {}

  -- Room 1: Starting cell
  local r1 = make_room(1, "Cell")
  carve(r1, 2, 2, 17, 12)
  r1.tiles[5][5] = 1; r1.tiles[5][14] = 1
  r1.tiles[9][5] = 1; r1.tiles[9][14] = 1
  add_door(r1, 17, 7, 2, 2, 7, false)
  -- Craftable items: flashlight + batteries scattered
  add_room_item(r1, 10, 10, "craft", "flashlight")
  add_room_item(r1, 4, 3, "craft", "note_a")
  add_room_item(r1, 15, 5, "craft", "wire")
  rooms[1] = r1

  -- Room 2: Corridor
  local r2 = make_room(2, "Corridor")
  carve(r2, 1, 5, 18, 9)
  carve(r2, 6, 3, 8, 5)
  carve(r2, 12, 9, 14, 11)
  add_door(r2, 1, 7, 1, 16, 7, false)
  add_door(r2, 18, 7, 3, 2, 7, true, "red_key")
  add_door(r2, 10, 9, 4, 10, 2, false)
  add_room_item(r2, 13, 10, "craft", "red_key")
  add_room_item(r2, 7, 4, "craft", "batteries")
  add_room_item(r2, 3, 7, "craft", "nail")
  rooms[2] = r2

  -- Room 3: Library
  local r3 = make_room(3, "Library")
  carve(r3, 1, 1, 18, 13)
  for x = 3, 16, 3 do
    for y = 3, 5 do r3.tiles[y][x] = 1 end
    for y = 8, 10 do r3.tiles[y][x] = 1 end
  end
  add_door(r3, 1, 7, 2, 17, 7, false)
  add_door(r3, 10, 1, 5, 10, 12, true, "blue_key")
  add_room_item(r3, 16, 12, "craft", "blue_key")
  add_room_item(r3, 5, 6, "craft", "note_b")
  rooms[3] = r3

  -- Room 4: Storage (locked grate, lockpick or key needed)
  local r4 = make_room(4, "Storage")
  carve(r4, 2, 1, 17, 13)
  r4.tiles[4][5] = 1; r4.tiles[4][6] = 1
  r4.tiles[5][5] = 1; r4.tiles[5][6] = 1
  r4.tiles[8][10] = 1; r4.tiles[8][11] = 1
  r4.tiles[9][10] = 1; r4.tiles[9][11] = 1
  r4.tiles[6][15] = 1; r4.tiles[7][15] = 1
  add_door(r4, 10, 1, 2, 10, 8, false)
  rooms[4] = r4

  -- Room 5: Exit
  local r5 = make_room(5, "Exit")
  carve(r5, 3, 3, 16, 11)
  r5.tiles[7][9] = 1; r5.tiles[7][10] = 1
  r5.tiles[8][9] = 1; r5.tiles[8][10] = 1
  add_door(r5, 10, 11, 3, 10, 2, false)
  add_room_item(r5, 10, 4, "exit")
  rooms[5] = r5
end

---------- COLLISION ----------
local function solid_at(rm, px_x, px_y)
  local tx = math.floor(px_x / TILE)
  local ty = math.floor(px_y / TILE)
  if tx < 0 or tx >= MAP_W or ty < 0 or ty >= MAP_H then return true end
  local r = rooms[rm]
  if not r then return true end
  return r.tiles[ty][tx] == 1
end

local function can_move(rm, cx, cy, dx, dy, radius)
  radius = radius or 3
  local nx, ny = cx + dx, cy + dy
  if solid_at(rm, nx - radius, ny - radius) then return false end
  if solid_at(rm, nx + radius, ny - radius) then return false end
  if solid_at(rm, nx - radius, ny + radius) then return false end
  if solid_at(rm, nx + radius, ny + radius) then return false end
  return true
end

---------- GAME INIT ----------
init_game = function()
  init_rooms()
  px = 10 * TILE + 4
  py = 7 * TILE + 4
  pdir = 1
  p_alive = true
  fl_on = true
  fl_battery = 100
  fl_flicker = 0
  fl_boosted = false
  current_room = 1
  rooms[1].explored = true

  inventory = {}
  inv_cursor = 1
  combine_first = nil

  particles = {}
  scare_flash = 0
  shake_timer = 0
  shake_amt = 0
  heartbeat_rate = 0
  msg_text = ""
  msg_timer = 0

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
  amb_drip_timer = amb_drip_timer - 1
  if amb_drip_timer <= 0 then
    amb_drip_timer = 40 + math.random(80)
    sfx_note(3, "E6", 0.02)
  end

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
      if heartbeat_rate > 0.4 then
        sfx_note(0, "C3", 0.04)
      end
    end
  end

  -- Entity footsteps
  if e_active then
    local audible = (e_room == current_room)
    if not audible then
      local r = rooms[current_room]
      for _, door in ipairs(r.doors) do
        if door.target_room == e_room then audible = true; break end
      end
    end
    if audible then
      e_timer = e_timer + 1
      local step_interval = e_chase and 7 or 12
      if e_timer % step_interval == 0 then
        if e_room == current_room or math.random(3) == 1 then
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

  if same_room then
    e_chase = true
    e_speed = lerp(e_speed, 0.7, 0.01)
    local dx = px - ex
    local dy = py - ey
    local d = dist(px, py, ex, ey)

    if d > 2 then
      local mx = (dx / d) * e_speed
      local my = (dy / d) * e_speed
      if can_move(e_room, ex, ey, mx, 0, 3) then ex = ex + mx end
      if can_move(e_room, ex, ey, 0, my, 3) then ey = ey + my end
    end

    if d < 8 then
      trigger_scare(3)
      p_alive = false
      sfx_note(0, "C2", 0.4)
      sfx_note(1, "F#2", 0.4)
      sfx_noise(2, 0.4)
    end

    if d < 30 and math.random(100) < 3 then
      trigger_scare(1)
    end
  else
    e_chase = false
    e_speed = 0.4
    e_timer = e_timer + 1
    if e_timer % 60 == 0 then
      local r = rooms[e_room]
      if r and #r.doors > 0 then
        local door = r.doors[math.random(#r.doors)]
        e_patrol_x = door.tx * TILE + 4
        e_patrol_y = door.ty * TILE + 4
        if math.random(100) < 40 then
          if door.target_room == current_room or math.random(100) < 25 then
            e_room = door.target_room
            ex = door.target_x * TILE + 4
            ey = door.target_y * TILE + 4
            if door.target_room == current_room then
              sfx_note(2, "G2", 0.1)
              show_msg("...a door creaks...", 60)
            end
          end
        end
      end
    end

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
        if has_item(door.key_id) then
          remove_item(door.key_id)
          door.locked = false
          show_msg("Unlocked!", 45)
          sfx_note(0, "C5", 0.08)
          sfx_note(0, "E5", 0.06)
        elseif has_item("lockpick") then
          -- Lockpick works on any lock!
          remove_item("lockpick")
          door.locked = false
          show_msg("Picked the lock!", 45)
          sfx_note(0, "A4", 0.06)
          sfx_note(1, "C5", 0.06)
        else
          show_msg("Locked. Need " .. (door.key_id or "?"), 60)
          sfx_note(0, "E3", 0.1)
        end
      else
        current_room = door.target_room
        px = door.target_x * TILE + 4
        py = door.target_y * TILE + 4
        rooms[current_room].explored = true
        room_transition = 15
        show_msg(rooms[current_room].name, 45)
        sfx_note(2, "A3", 0.08)
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
        if item.type == "craft" then
          if add_item(item.id) then
            show_msg("Got: " .. ITEMS[item.id].name, 60)
          else
            show_msg("Inventory full!", 60)
            sfx_noise(1, 4)
            item.collected = false -- put it back
          end
        elseif item.type == "exit" then
          if has_item("full_note") then
            state = "win"
            sfx_note(0, "C5", 0.15)
            sfx_note(1, "E5", 0.15)
            sfx_note(2, "G5", 0.15)
          else
            show_msg("Something is missing...", 60)
            sfx_note(0, "E3", 0.1)
            item.collected = false
          end
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

---------- LIGHTING ----------
local function in_light(wx, wy)
  if not fl_on then return false end
  local dx = wx - px
  local dy = wy - py
  local d = math.sqrt(dx * dx + dy * dy)
  if d > fl_range then return false end
  local dir_x = ({0, 1, 0, -1})[pdir + 1]
  local dir_y = ({-1, 0, 1, 0})[pdir + 1]
  if d < 8 then return true end
  local dot = (dx * dir_x + dy * dir_y) / d
  return dot > math.cos(fl_angle + 0.2)
end

local function light_level(wx, wy)
  if not fl_on then
    local d = dist(wx, wy, px, py)
    if d < 12 then return DARK end
    return BLACK
  end

  local d = dist(wx, wy, px, py)
  if d < 10 then return DIM end

  if not in_light(wx, wy) then
    if d < 16 then return DARK end
    return BLACK
  end

  local flick = 0
  if fl_flicker > 0 then flick = math.random(0, 1) end

  if d < 20 then return BRIGHT - flick end
  if d < 35 then return DIM end
  if d < fl_range then return DARK end
  return BLACK
end

---------- DRAWING ----------
draw_room = function()
  local r = rooms[current_room]
  if not r then return end

  for ty = 0, MAP_H - 1 do
    for tx = 0, MAP_W - 1 do
      local wx = tx * TILE + 4
      local wy = ty * TILE + 4
      local ll = light_level(wx, wy)

      if ll > BLACK then
        local x = tx * TILE
        local y = ty * TILE
        if r.tiles[ty][tx] == 1 then
          if ll >= DIM then
            rect(S, x, y, TILE, TILE, DIM)
            if (tx + ty) % 3 == 0 then
              line(S, x + 1, y + 1, x + TILE - 2, y + 1, DARK)
            end
          else
            rect(S, x, y, TILE, TILE, DARK)
          end
        else
          if ll >= BRIGHT then
            if (tx + ty) % 2 == 0 then
              pix(S, x + 3, y + 3, DARK)
            end
          elseif ll >= DIM then
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
        if ll >= DIM then
          pix(S, x + 4, y + 3, BRIGHT)
          rect(S, x + 3, y + 4, 3, 2, BRIGHT)
        end
      else
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

        if item.type == "craft" then
          -- Item glyph with pulse
          local ic = ITEMS[item.id] and ITEMS[item.id].icon or "?"
          if ll >= DIM then
            pix(S, x + 3, y + 3, BRIGHT)
            pix(S, x + 4, y + 4, DIM + pulse)
          else
            pix(S, x + 3, y + 3, DIM)
          end
        elseif item.type == "exit" then
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

  if d < 25 and ll == BLACK then ll = DARK end

  if ll > BLACK then
    local blink = math.floor(frame() / 4) % 2

    if ll >= DIM then
      circ(S, math.floor(ex), math.floor(ey), 4, DARK)
      pix(S, math.floor(ex) - 1, math.floor(ey) - 1, BRIGHT * blink)
      pix(S, math.floor(ex) + 1, math.floor(ey) - 1, BRIGHT * blink)
    elseif ll >= DARK then
      if blink == 1 then
        pix(S, math.floor(ex) - 1, math.floor(ey) - 1, DIM)
        pix(S, math.floor(ex) + 1, math.floor(ey) - 1, DIM)
      end
    end
  end
end

local function draw_player()
  local bx = math.floor(px)
  local by = math.floor(py)

  circ(S, bx, by, 3, DIM)
  pix(S, bx, by, BRIGHT)

  local dir_x = ({0, 1, 0, -1})[pdir + 1]
  local dir_y = ({-1, 0, 1, 0})[pdir + 1]
  pix(S, bx + dir_x * 3, by + dir_y * 3, BRIGHT)

  if fl_on and fl_flicker <= 0 then
    local blen = 6
    line(S, bx + dir_x * 4, by + dir_y * 4,
         bx + dir_x * blen, by + dir_y * blen, DIM)
  end
end

local function draw_flashlight_fx()
  if not fl_on then return end
  if fl_flicker > 0 and math.random(3) == 1 then return end

  local dir_x = ({0, 1, 0, -1})[pdir + 1]
  local dir_y = ({-1, 0, 1, 0})[pdir + 1]

  if frame() % 3 == 0 then
    local spread = 8
    local fx = px + dir_x * fl_range * 0.6 + (math.random() - 0.5) * spread
    local fy = py + dir_y * fl_range * 0.6 + (math.random() - 0.5) * spread
    if fx >= 0 and fx < W and fy >= 0 and fy < H then
      pix(S, math.floor(fx), math.floor(fy), DARK)
    end
  end
end

---------- DRAW INVENTORY UI ----------
local function draw_inventory()
  cls(S, BLACK)

  text(S, "INVENTORY", W / 2, 4, BRIGHT, ALIGN_CENTER)
  text(S, "Craft & Survive", W / 2, 13, DARK, ALIGN_CENTER)

  for i = 1, INV_MAX do
    local col = ((i - 1) % INV_COLS)
    local row = math.floor((i - 1) / INV_COLS)
    local sx = INV_X + col * SLOT_W
    local sy = INV_Y + row * SLOT_H

    local border_c = DARK
    if i == inv_cursor then
      border_c = BRIGHT
    elseif combine_first and combine_first == i then
      border_c = DIM
    end
    rect(S, sx, sy, SLOT_W - 2, SLOT_H - 2, BLACK)
    line(S, sx, sy, sx + SLOT_W - 3, sy, border_c)
    line(S, sx, sy, sx, sy + SLOT_H - 3, border_c)
    line(S, sx + SLOT_W - 3, sy, sx + SLOT_W - 3, sy + SLOT_H - 3, border_c)
    line(S, sx, sy + SLOT_H - 3, sx + SLOT_W - 3, sy + SLOT_H - 3, border_c)

    if inventory[i] then
      local item = ITEMS[inventory[i]]
      if item then
        text(S, item.icon, sx + SLOT_W / 2 - 1, sy + 4, DIM, ALIGN_CENTER)
        local label = item.name
        if #label > 6 then label = string.sub(label, 1, 5) .. "." end
        text(S, label, sx + SLOT_W / 2 - 1, sy + 14, DARK, ALIGN_CENTER)
      end
    end
  end

  -- Description
  local sel_id = inventory[inv_cursor]
  if sel_id and ITEMS[sel_id] then
    local item = ITEMS[sel_id]
    text(S, item.name, W / 2, 74, DIM, ALIGN_CENTER)
    text(S, item.desc, W / 2, 84, DARK, ALIGN_CENTER)
  end

  -- Instructions
  if combine_first then
    text(S, "Select 2nd item (A)", W / 2, 98, DIM, ALIGN_CENTER)
  else
    text(S, "A=Select  B=Close", W / 2, 98, DARK, ALIGN_CENTER)
    text(S, "A+A=Combine two items", W / 2, 108, DARK, ALIGN_CENTER)
  end

  -- Message overlay
  if msg_timer > 0 then
    rect(S, 10, H - 16, W - 20, 12, BLACK)
    text(S, msg_text, W / 2, H - 14, BRIGHT, ALIGN_CENTER)
  end
end

---------- HUD ----------
draw_hud = function()
  -- Battery meter
  local bat_w = 20
  local bat_fill = math.floor(bat_w * fl_battery / 100)

  rect(S, 2, 1, bat_w + 2, 5, DIM)
  if bat_fill > 0 then
    local bat_c = fl_battery < 20 and (frame() % 6 < 3 and BRIGHT or DARK) or BRIGHT
    rect(S, 3, 2, bat_fill, 3, bat_c)
  end

  -- Boosted flashlight indicator
  if fl_boosted then
    pix(S, bat_w + 5, 3, BRIGHT)
  end

  -- Inventory count
  text(S, #inventory .. "/" .. INV_MAX, W - 2, 1, DARK, ALIGN_RIGHT)

  -- Room name / message
  if msg_timer > 0 then
    local alpha = msg_timer > 10 and BRIGHT or DIM
    text(S, msg_text, W / 2, H - 12, alpha, ALIGN_CENTER)
  end

  -- Craft hint when near items
  local r = rooms[current_room]
  if r then
    for _, item in ipairs(r.items) do
      if not item.collected then
        local dx = item.tx * TILE + 4 - px
        local dy = item.ty * TILE + 4 - py
        if math.abs(dx) < 12 and math.abs(dy) < 12 then
          text(S, "[A]", W / 2, H - 20, DIM, ALIGN_CENTER)
          break
        end
      end
    end
  end
end

---------- TITLE SCREEN ----------
local title_timer = 0
local title_flicker = 0

local function draw_title()
  cls(S, BLACK)
  title_timer = title_timer + 1

  local flick = math.random(100)
  local title_c = BRIGHT
  if flick < 8 then title_c = DARK
  elseif flick < 15 then title_c = DIM end

  if title_flicker > 0 then
    title_flicker = title_flicker - 1
    if title_flicker > 3 then title_c = BLACK end
  elseif math.random(200) < 3 then
    title_flicker = 6
  end

  if title_c > BLACK then
    text(S, "THE DARK ROOM", W / 2, 25, title_c, ALIGN_CENTER)
  end

  if title_timer > 20 then
    text(S, "survival craft", W / 2, 38, DARK, ALIGN_CENTER)
  end
  if title_timer > 40 then
    text(S, "you wake in darkness.", W / 2, 52, DIM, ALIGN_CENTER)
  end
  if title_timer > 60 then
    text(S, "find. combine. escape.", W / 2, 62, DARK, ALIGN_CENTER)
  end
  if title_timer > 80 then
    text(S, "you are not alone.", W / 2, 72, DARK, ALIGN_CENTER)
  end

  if title_timer > 100 then
    local blink = math.floor(frame() / 20) % 2
    if blink == 0 then
      text(S, "PRESS START", W / 2, 92, DIM, ALIGN_CENTER)
    end
  end

  -- Ambient eyes
  if title_timer > 60 and math.random(100) < 5 then
    local rx = math.random(20, W - 20)
    local ry = math.random(80, H - 20)
    pix(S, rx, ry, DARK)
    pix(S, rx + 2, ry, DARK)
  end
end

---------- GAME OVER SCREEN ----------
local gameover_timer = 0

local function draw_gameover()
  cls(S, BLACK)
  gameover_timer = gameover_timer + 1

  if gameover_timer < 15 then
    for i = 1, 80 do
      pix(S, math.random(0, W - 1), math.random(0, H - 1), math.random(0, BRIGHT))
    end
    return
  end

  local flick = math.random(100)
  if flick > 10 then
    text(S, "IT GOT YOU", W / 2, 40, BRIGHT, ALIGN_CENTER)
  end

  if gameover_timer > 45 then
    local rooms_explored = 0
    for _, r in ipairs(rooms) do
      if r.explored then rooms_explored = rooms_explored + 1 end
    end
    text(S, "Rooms: " .. rooms_explored .. "/5", W / 2, 60, DIM, ALIGN_CENTER)
    text(S, "Items: " .. #inventory, W / 2, 70, DIM, ALIGN_CENTER)
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
    local c = win_timer < 10 and BRIGHT or DIM
    cls(S, c)
    return
  end

  text(S, "YOU ESCAPED", W / 2, 30, BRIGHT, ALIGN_CENTER)

  if win_timer > 30 then
    text(S, "The light outside", W / 2, 48, DIM, ALIGN_CENTER)
    text(S, "has never felt", W / 2, 58, DIM, ALIGN_CENTER)
    text(S, "so warm.", W / 2, 68, DIM, ALIGN_CENTER)
  end

  if win_timer > 60 then
    if has_item("full_note") then
      text(S, "THE EXIT IS ABOVE", W / 2, 82, BRIGHT, ALIGN_CENTER)
    end
    local blink = math.floor(frame() / 20) % 2
    if blink == 0 then
      text(S, "START to play again", W / 2, 100, DIM, ALIGN_CENTER)
    end
  end
end

---------- PAUSE SCREEN ----------
local function draw_pause()
  rect(S, 30, 30, 100, 60, BLACK)
  rect(S, 31, 31, 98, 58, DARK)
  text(S, "PAUSED", W / 2, 38, BRIGHT, ALIGN_CENTER)
  text(S, "SELECT to resume", W / 2, 55, DIM, ALIGN_CENTER)
  text(S, "START to quit", W / 2, 68, DIM, ALIGN_CENTER)
end

---------- DEMO MODE ----------
local function update_demo()
  demo_timer = demo_timer + 1

  demo_dir_timer = demo_dir_timer - 1
  if demo_dir_timer <= 0 then
    demo_dir = math.random(0, 3)
    demo_dir_timer = 20 + math.random(40)
  end

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
    demo_dir_timer = 0
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

  -- Auto-craft if possible in demo
  if demo_timer % 120 == 0 then
    for _, r in ipairs(RECIPES) do
      if has_item(r.a) and has_item(r.b) then
        local result_name = try_combine(r.a, r.b)
        if result_name then
          show_msg("Crafted: " .. result_name, 60)
        end
        break
      end
    end
  end

  -- Exit demo on input
  if btnp("start") or btnp("a") or btnp("b") or
     btnp("up") or btnp("down") or btnp("left") or btnp("right") then
    state = "title"
    title_timer = 0
    idle_timer = 0
    return
  end

  if demo_timer >= DEMO_DURATION then
    state = "title"
    title_timer = 0
    idle_timer = 0
  end
end

---------- UPDATE PLAY ----------
update_play = function()
  if not p_alive then
    state = "gameover"
    gameover_timer = 0
    return
  end

  if room_transition > 0 then
    room_transition = room_transition - 1
    return
  end

  -- Movement
  local dx, dy = 0, 0
  if btn("up")    then dy = -p_speed; pdir = 0 end
  if btn("down")  then dy =  p_speed; pdir = 2 end
  if btn("left")  then dx = -p_speed; pdir = 3 end
  if btn("right") then dx =  p_speed; pdir = 1 end

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
  if btnp("a") then
    check_interact()
  end

  -- Open inventory with B
  if btnp("b") then
    state = "inv"
    inv_cursor = 1
    combine_first = nil
    sfx_note(0, "C4", 0.04)
    return
  end

  -- Battery drain (slower if boosted)
  if fl_on then
    local drain = fl_boosted and 0.03 or 0.06
    fl_battery = fl_battery - drain
    if fl_battery < 30 then
      if math.random(100) < (30 - fl_battery) then
        fl_flicker = 2 + math.random(3)
      end
    end
    if math.random(500) < 2 then
      fl_flicker = 1 + math.random(2)
    end
  end

  if fl_flicker > 0 then fl_flicker = fl_flicker - 1 end

  -- Battery dies
  if fl_battery <= 0 and fl_on then
    fl_on = false
    fl_battery = 0
    show_msg("Light dies...", 60)
    sfx_note(0, "C2", 0.15)
  end

  entity_ai()
  update_ambient()
  update_particles()
  apply_shake()

  if scare_flash > 0 then scare_flash = scare_flash - 1 end
  if msg_timer > 0 then msg_timer = msg_timer - 1 end

  -- Pause
  if btnp("select") then
    state = "paused"
  end
end

---------- MAIN DRAW ----------
draw_play = function()
  cls(S, BLACK)

  if room_transition > 0 then
    if room_transition > 10 then
      cls(S, BLACK)
    else
      draw_room()
      draw_entity()
      draw_player()
      draw_flashlight_fx()
    end
    draw_hud()
    return
  end

  if scare_flash > 0 then
    if scare_flash > 4 then
      cls(S, BRIGHT)
      text(S, "!", W / 2, H / 2, BLACK, ALIGN_CENTER)
      return
    end
  end

  draw_room()
  draw_entity()
  draw_player()
  draw_flashlight_fx()
  draw_hud()

  for _, p in ipairs(particles) do
    if p.x >= 0 and p.x < W and p.y >= 0 and p.y < H then
      pix(S, math.floor(p.x), math.floor(p.y), p.c)
    end
  end

  -- Vignette
  for i = 0, W - 1, 2 do
    pix(S, i, 0, BLACK); pix(S, i, 1, BLACK)
    pix(S, i, H - 1, BLACK); pix(S, i, H - 2, BLACK)
  end
  for i = 0, H - 1, 2 do
    pix(S, 0, i, BLACK); pix(S, 1, i, BLACK)
    pix(S, W - 1, i, BLACK); pix(S, W - 2, i, BLACK)
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
  frame_count = frame_count + 1

  if state == "title" then
    idle_timer = idle_timer + 1
    if btnp("start") then
      state = "play"
      init_game()
      show_msg("Cell", 60)
      idle_timer = 0
    end
    if idle_timer >= IDLE_THRESHOLD then
      state = "demo"
      demo_timer = 0
      demo_dir_timer = 0
      init_game()
      e_speed = 0.2
    end

  elseif state == "demo" then
    update_demo()
    update_play()

  elseif state == "play" then
    update_play()

  elseif state == "inv" then
    -- Close
    if btnp("b") or btnp("select") then
      state = "play"
      combine_first = nil
      sfx_note(0, "C4", 0.04)
      return
    end
    -- Navigate
    if btnp("left") then
      inv_cursor = inv_cursor - 1
      if inv_cursor < 1 then inv_cursor = INV_MAX end
      sfx_note(0, "E4", 0.02)
    end
    if btnp("right") then
      inv_cursor = inv_cursor + 1
      if inv_cursor > INV_MAX then inv_cursor = 1 end
      sfx_note(0, "E4", 0.02)
    end
    if btnp("up") then
      inv_cursor = inv_cursor - INV_COLS
      if inv_cursor < 1 then inv_cursor = inv_cursor + INV_MAX end
      sfx_note(0, "E4", 0.02)
    end
    if btnp("down") then
      inv_cursor = inv_cursor + INV_COLS
      if inv_cursor > INV_MAX then inv_cursor = inv_cursor - INV_MAX end
      sfx_note(0, "E4", 0.02)
    end
    -- Select / combine
    if btnp("a") then
      if inventory[inv_cursor] then
        if combine_first == nil then
          combine_first = inv_cursor
          sfx_note(0, "G4", 0.04)
          show_msg("Select 2nd item...", 40)
        elseif combine_first == inv_cursor then
          combine_first = nil
          sfx_noise(0, 0.04)
        else
          local id_a = inventory[combine_first]
          local id_b = inventory[inv_cursor]
          if id_a and id_b then
            local result = try_combine(id_a, id_b)
            if result then
              show_msg("Crafted: " .. result .. "!", 80)
              sfx_note(0, "C5", 0.06)
              sfx_note(1, "E5", 0.06)
              sfx_note(2, "G5", 0.08)
            else
              show_msg("Can't combine those.", 50)
              sfx_noise(0, 0.06)
            end
          end
          combine_first = nil
          inv_cursor = 1
        end
      end
    end
    if msg_timer > 0 then msg_timer = msg_timer - 1 end

    -- Entity still moves while you craft (tension!)
    entity_ai()
    update_ambient()

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
    if gameover_timer > 60 and btnp("start") then
      state = "play"
      init_game()
    end

  elseif state == "win" then
    win_timer = win_timer + 1
    if win_timer > 90 and btnp("start") then
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
    local blink = math.floor(frame() / 30) % 2
    if blink == 0 then
      text(S, "DEMO", 3, H - 8, DARK)
    end
  elseif state == "play" then
    draw_play()
  elseif state == "inv" then
    draw_inventory()
  elseif state == "paused" then
    draw_play()
    draw_pause()
  elseif state == "gameover" then
    draw_gameover()
  elseif state == "win" then
    draw_win()
  end
end
