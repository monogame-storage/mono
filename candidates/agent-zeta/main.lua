-- DUSKHOLD
-- A turn-based roguelike dungeon crawler
-- Descend into the dark. Survive. Escape.

----------------------------------------------
-- CONSTANTS
----------------------------------------------
local TILE = 6          -- tile size in pixels
local MAP_W = 40        -- dungeon width in tiles
local MAP_H = 30        -- dungeon height in tiles
local VIEW_W = 26       -- tiles visible horizontally
local VIEW_H = 18       -- tiles visible vertically
local FOV_RADIUS = 7    -- field of view radius

-- Tile types
local T_VOID = 0
local T_WALL = 1
local T_FLOOR = 2
local T_STAIR = 3
local T_DOOR = 4

-- Colors (grayscale 0-15)
local C_BLACK = 0
local C_DARK1 = 1
local C_DARK2 = 2
local C_DARK3 = 3
local C_MID1 = 4
local C_MID2 = 5
local C_MID3 = 6
local C_GRAY = 7
local C_LGRAY = 8
local C_LIGHT1 = 9
local C_LIGHT2 = 10
local C_LIGHT3 = 11
local C_BRIGHT1 = 12
local C_BRIGHT2 = 13
local C_BRIGHT3 = 14
local C_WHITE = 15

-- Item types
local ITEM_POTION = 1
local ITEM_WEAPON = 2
local ITEM_ARMOR = 3
local ITEM_SCROLL = 4
local ITEM_RING = 5

----------------------------------------------
-- GLOBAL STATE
----------------------------------------------
local player = {}
local enemies = {}
local items = {}
local particles = {}
local floats = {}  -- floating damage/heal numbers
local map = {}
local visible = {}
local explored = {}
local rooms = {}
local cam_x, cam_y = 0, 0
local floor_num = 1
local turn_count = 0
local msg_log = {}
local msg_timer = 0
local paused = false
local show_map = false
local game_over = false
local death_stats = {}
local kills_total = 0
local items_collected = 0
local shake_amt = 0
local shake_timer = 0
local flash_timer = 0
local flash_color = 0
local player_moved = false -- track if player took an action this frame

----------------------------------------------
-- TOUCH STATE
----------------------------------------------
local touch_last_tap_frame = -999   -- frame of last tap (for double-tap detection)
local touch_start_frame = 0         -- frame when finger first touched
local DOUBLE_TAP_WINDOW = 15        -- frames between taps for double-tap
local LONG_PRESS_FRAMES = 20        -- frames held to count as long press
local touch_long_fired = false      -- whether long press already fired this hold

----------------------------------------------
-- UTILITY
----------------------------------------------
local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function dist(x1, y1, x2, y2)
  local dx = x1 - x2
  local dy = y1 - y2
  return math.sqrt(dx * dx + dy * dy)
end

local function manhattan(x1, y1, x2, y2)
  return math.abs(x1 - x2) + math.abs(y1 - y2)
end

local function sign(x)
  if x > 0 then return 1 end
  if x < 0 then return -1 end
  return 0
end

local function log_msg(str, color)
  table.insert(msg_log, 1, {text = str, color = color or C_LGRAY, timer = 180})
  if #msg_log > 5 then
    table.remove(msg_log, 6)
  end
  msg_timer = 120
end

local function add_float(x, y, txt, c)
  table.insert(floats, {x = x * TILE, y = y * TILE, txt = txt, c = c or C_WHITE, life = 40, dy = -0.8})
end

local function add_particle(x, y, c, count)
  for i = 1, (count or 3) do
    table.insert(particles, {
      x = x * TILE + TILE / 2,
      y = y * TILE + TILE / 2,
      vx = (math.random() - 0.5) * 3,
      vy = (math.random() - 0.5) * 3,
      c = c,
      life = 10 + math.random(10)
    })
  end
end

----------------------------------------------
-- MAP GENERATION
----------------------------------------------
local function map_get(x, y)
  if x < 0 or x >= MAP_W or y < 0 or y >= MAP_H then return T_WALL end
  return map[y * MAP_W + x] or T_VOID
end

local function map_set(x, y, v)
  if x >= 0 and x < MAP_W and y >= 0 and y < MAP_H then
    map[y * MAP_W + x] = v
  end
end

local function is_walkable(x, y)
  local t = map_get(x, y)
  return t == T_FLOOR or t == T_STAIR or t == T_DOOR
end

local function carve_room(rx, ry, rw, rh)
  for y = ry, ry + rh - 1 do
    for x = rx, rx + rw - 1 do
      map_set(x, y, T_FLOOR)
    end
  end
end

local function carve_h_corridor(x1, x2, y)
  local sx = math.min(x1, x2)
  local ex = math.max(x1, x2)
  for x = sx, ex do
    if map_get(x, y) == T_WALL then
      map_set(x, y, T_FLOOR)
    end
  end
end

local function carve_v_corridor(y1, y2, x)
  local sy = math.min(y1, y2)
  local ey = math.max(y1, y2)
  for y = sy, ey do
    if map_get(x, y) == T_WALL then
      map_set(x, y, T_FLOOR)
    end
  end
end

local function rooms_overlap(r1, r2, pad)
  pad = pad or 1
  return r1.x - pad < r2.x + r2.w + pad and
         r1.x + r1.w + pad > r2.x - pad and
         r1.y - pad < r2.y + r2.h + pad and
         r1.y + r1.h + pad > r2.y - pad
end

-- Place doors at corridor-room transitions
local function place_doors()
  for y = 1, MAP_H - 2 do
    for x = 1, MAP_W - 2 do
      if map_get(x, y) == T_FLOOR then
        -- Horizontal doorway: walls above/below, floor left/right
        local wall_above = map_get(x, y - 1) == T_WALL
        local wall_below = map_get(x, y + 1) == T_WALL
        local floor_left = map_get(x - 1, y) == T_FLOOR
        local floor_right = map_get(x + 1, y) == T_FLOOR
        -- Vertical doorway: walls left/right, floor above/below
        local wall_left = map_get(x - 1, y) == T_WALL
        local wall_right = map_get(x + 1, y) == T_WALL
        local floor_above = map_get(x, y - 1) == T_FLOOR
        local floor_below = map_get(x, y + 1) == T_FLOOR

        if (wall_above and wall_below and floor_left and floor_right) or
           (wall_left and wall_right and floor_above and floor_below) then
          -- Only place some doors (not every chokepoint)
          if math.random() < 0.35 then
            map_set(x, y, T_DOOR)
          end
        end
      end
    end
  end
end

local function generate_dungeon()
  -- Clear map
  map = {}
  for i = 0, MAP_W * MAP_H - 1 do
    map[i] = T_WALL
  end

  rooms = {}
  local max_rooms = 8 + math.min(floor_num, 6)
  local attempts = 0

  while #rooms < max_rooms and attempts < 200 do
    attempts = attempts + 1
    local rw = math.random(4, 8)
    local rh = math.random(3, 6)
    local rx = math.random(1, MAP_W - rw - 2)
    local ry = math.random(1, MAP_H - rh - 2)

    local new_room = {x = rx, y = ry, w = rw, h = rh}
    local ok = true
    for _, r in ipairs(rooms) do
      if rooms_overlap(new_room, r, 2) then
        ok = false
        break
      end
    end

    if ok then
      carve_room(rx, ry, rw, rh)

      -- Connect to previous room
      if #rooms > 0 then
        local prev = rooms[#rooms]
        local cx1 = math.floor(prev.x + prev.w / 2)
        local cy1 = math.floor(prev.y + prev.h / 2)
        local cx2 = math.floor(rx + rw / 2)
        local cy2 = math.floor(ry + rh / 2)

        if math.random() < 0.5 then
          carve_h_corridor(cx1, cx2, cy1)
          carve_v_corridor(cy1, cy2, cx2)
        else
          carve_v_corridor(cy1, cy2, cx1)
          carve_h_corridor(cx1, cx2, cy2)
        end
      end

      table.insert(rooms, new_room)
    end
  end

  -- Guarantee at least 2 rooms for stair placement
  if #rooms < 2 then
    -- Force a second room
    local rw, rh = 4, 3
    local rx = math.random(1, MAP_W - rw - 2)
    local ry = math.random(1, MAP_H - rh - 2)
    carve_room(rx, ry, rw, rh)
    if #rooms >= 1 then
      local prev = rooms[1]
      local cx1 = math.floor(prev.x + prev.w / 2)
      local cy1 = math.floor(prev.y + prev.h / 2)
      carve_h_corridor(cx1, rx + 2, cy1)
      carve_v_corridor(cy1, ry + 1, rx + 2)
    end
    table.insert(rooms, {x = rx, y = ry, w = rw, h = rh})
  end

  -- Extra corridors for connectivity (loop connections)
  if #rooms > 3 then
    for i = 1, math.min(3, #rooms - 2) do
      local a = math.random(1, #rooms)
      local b = math.random(1, #rooms)
      if a ~= b then
        local r1 = rooms[a]
        local r2 = rooms[b]
        local cx1 = math.floor(r1.x + r1.w / 2)
        local cy1 = math.floor(r1.y + r1.h / 2)
        local cx2 = math.floor(r2.x + r2.w / 2)
        local cy2 = math.floor(r2.y + r2.h / 2)
        if math.random() < 0.5 then
          carve_h_corridor(cx1, cx2, cy1)
          carve_v_corridor(cy1, cy2, cx2)
        else
          carve_v_corridor(cy1, cy2, cx1)
          carve_h_corridor(cx1, cx2, cy2)
        end
      end
    end
  end

  -- Place doors at chokepoints
  place_doors()

  -- Place stairs in last room
  if #rooms >= 2 then
    local last = rooms[#rooms]
    local sx = math.floor(last.x + last.w / 2)
    local sy = math.floor(last.y + last.h / 2)
    map_set(sx, sy, T_STAIR)
  end
end

----------------------------------------------
-- VISIBILITY / FOV (improved ray count)
----------------------------------------------
local function clear_visible()
  visible = {}
end

local function set_visible(x, y)
  if x >= 0 and x < MAP_W and y >= 0 and y < MAP_H then
    visible[y * MAP_W + x] = true
    explored[y * MAP_W + x] = true
  end
end

local function is_visible(x, y)
  return visible[y * MAP_W + x] == true
end

local function is_explored(x, y)
  return explored[y * MAP_W + x] == true
end

-- Improved raycasting FOV with more rays for accuracy
local function compute_fov(ox, oy, radius)
  clear_visible()
  set_visible(ox, oy)

  local steps = 96  -- more rays = fewer blind spots
  for i = 0, steps - 1 do
    local angle = (i / steps) * math.pi * 2
    local dx = math.cos(angle)
    local dy = math.sin(angle)
    local x = ox + 0.5
    local y = oy + 0.5
    for d = 1, radius do
      x = x + dx
      y = y + dy
      local ix = math.floor(x)
      local iy = math.floor(y)
      if ix < 0 or ix >= MAP_W or iy < 0 or iy >= MAP_H then break end
      set_visible(ix, iy)
      if map_get(ix, iy) == T_WALL then break end
    end
  end
end

----------------------------------------------
-- ENEMY TYPES & AI
----------------------------------------------
-- Enemy definitions by type
local enemy_defs = {
  rat = {name = "Rat", hp = 3, atk = 1, def = 0, glyph = "r", color = C_MID2, xp = 1, ai = "wander"},
  snake = {name = "Snake", hp = 5, atk = 2, def = 0, glyph = "s", color = C_MID3, xp = 2, ai = "chase"},
  bat = {name = "Bat", hp = 4, atk = 2, def = 0, glyph = "b", color = C_MID1, xp = 2, ai = "wander"},
  skeleton = {name = "Skeleton", hp = 8, atk = 3, def = 1, glyph = "S", color = C_LGRAY, xp = 3, ai = "patrol"},
  ghost = {name = "Ghost", hp = 6, atk = 4, def = 0, glyph = "G", color = C_LIGHT2, xp = 4, ai = "phase"},
  ogre = {name = "Ogre", hp = 15, atk = 5, def = 2, glyph = "O", color = C_GRAY, xp = 5, ai = "chase"},
  wraith = {name = "Wraith", hp = 10, atk = 6, def = 1, glyph = "W", color = C_BRIGHT1, xp = 6, ai = "phase"},
}

local function make_enemy(etype, x, y)
  local def = enemy_defs[etype]
  local scale = 1 + (floor_num - 1) * 0.15
  return {
    type = etype,
    name = def.name,
    x = x,
    y = y,
    hp = math.floor(def.hp * scale),
    max_hp = math.floor(def.hp * scale),
    atk = math.floor(def.atk * scale),
    def = def.def,
    glyph = def.glyph,
    color = def.color,
    xp = def.xp,
    ai = def.ai,
    alert = false,
    patrol_dir = math.random(1, 4),
    patrol_steps = 0,
    hit_flash = 0,
  }
end

local function tile_has_enemy(x, y)
  for i, e in ipairs(enemies) do
    if e.x == x and e.y == y then return i end
  end
  return nil
end

local function tile_has_player(x, y)
  return player.x == x and player.y == y
end

local function find_empty_floor(avoid_player)
  for attempt = 0, 200 do
    local room = rooms[math.random(1, #rooms)]
    local x = room.x + math.random(0, room.w - 1)
    local y = room.y + math.random(0, room.h - 1)
    if is_walkable(x, y) and not tile_has_enemy(x, y) then
      if not avoid_player or (player.x ~= x or player.y ~= y) then
        return x, y
      end
    end
  end
  return nil, nil
end

----------------------------------------------
-- ITEMS (expanded with rings)
----------------------------------------------
local item_names = {
  [ITEM_POTION] = {"Potion", "Hi-Potion", "Elixir"},
  [ITEM_WEAPON] = {"Dagger", "Sword", "Axe", "Halberd"},
  [ITEM_ARMOR]  = {"Leather", "Chain", "Plate", "Dragonscale"},
  [ITEM_SCROLL] = {"Scrl:Smite", "Scrl:Shield", "Scrl:Sight"},
  [ITEM_RING]   = {"Ring:Might", "Ring:Ward", "Ring:Vigor"},
}

local function make_item(itype, tier, x, y)
  local names = item_names[itype]
  tier = clamp(tier, 1, #names)
  local item = {
    type = itype,
    tier = tier,
    name = names[tier],
    x = x,
    y = y,
    color = C_LIGHT3,
  }

  if itype == ITEM_POTION then
    item.heal = 5 + tier * 5
    item.glyph = "!"
    item.color = C_LIGHT1
  elseif itype == ITEM_WEAPON then
    item.atk_bonus = tier + math.floor(floor_num / 3)
    item.glyph = "/"
    item.color = C_BRIGHT2
  elseif itype == ITEM_ARMOR then
    item.def_bonus = tier + math.floor(floor_num / 4)
    item.glyph = "["
    item.color = C_BRIGHT1
  elseif itype == ITEM_SCROLL then
    item.glyph = "?"
    item.color = C_LIGHT3
  elseif itype == ITEM_RING then
    item.glyph = "o"
    item.color = C_BRIGHT3
  end

  return item
end

local function tile_has_item(x, y)
  for i, it in ipairs(items) do
    if it.x == x and it.y == y then return i end
  end
  return nil
end

----------------------------------------------
-- COMBAT (improved with crits and miss)
----------------------------------------------
local function calc_damage(atk, def)
  -- 10% miss chance
  if math.random(100) <= 10 then return 0 end
  local base = math.max(1, atk - def)
  local variance = math.random(-1, 1)
  -- 12% critical hit chance: double damage
  if math.random(100) <= 12 then
    return math.max(2, (base + variance) * 2)
  end
  return math.max(1, base + variance)
end

local function attack_enemy(eidx)
  local e = enemies[eidx]
  local dmg = calc_damage(player.atk, e.def)

  if dmg == 0 then
    add_float(e.x, e.y, "MISS", C_MID2)
    log_msg("Missed " .. e.name .. "!", C_MID2)
    tone(3, 100, 80, 0.03)
  else
    e.hp = e.hp - dmg
    e.hit_flash = 6

    local is_crit = dmg >= (math.max(1, player.atk - e.def)) * 2
    if is_crit then
      add_float(e.x, e.y, "-" .. dmg .. "!", C_WHITE)
      add_particle(e.x, e.y, C_WHITE, 6)
      cam_shake(3)
      noise(0, 0.08)
      note(1, "C4", 0.06)
    else
      add_float(e.x, e.y, "-" .. dmg, C_LGRAY)
      add_particle(e.x, e.y, C_LGRAY, 4)
      cam_shake(2)
      noise(0, 0.05)
      note(1, "A3", 0.05)
    end
    shake_timer = 4

    if e.hp <= 0 then
      log_msg("Slain " .. e.name .. "!", C_LIGHT2)
      add_particle(e.x, e.y, e.color, 8)
      kills_total = kills_total + 1
      player.xp = player.xp + e.xp

      -- XP level up check
      if player.xp >= player.next_xp then
        player.level = player.level + 1
        player.xp = player.xp - player.next_xp
        player.next_xp = math.floor(player.next_xp * 1.5)
        player.max_hp = player.max_hp + 3
        player.hp = math.min(player.hp + 5, player.max_hp)
        player.base_atk = player.base_atk + 1
        player.atk = player.base_atk + player.weapon_bonus
        log_msg("Level up! Lv" .. player.level, C_BRIGHT3)
        note(0, "C5", 0.1)
        note(1, "E5", 0.1)
        note(0, "G5", 0.15)
      end

      -- Death sound
      noise(2, 0.1)
      table.remove(enemies, eidx)
    else
      log_msg("Hit " .. e.name .. " for " .. dmg .. " dmg", C_LGRAY)
    end
  end
end

local function enemy_attacks_player(e)
  local dmg = calc_damage(e.atk, player.def)

  if dmg == 0 then
    add_float(player.x, player.y, "MISS", C_MID2)
    log_msg(e.name .. " missed!", C_MID2)
    tone(3, 80, 60, 0.02)
    return
  end

  player.hp = player.hp - dmg
  player.hit_flash = 8

  add_float(player.x, player.y, "-" .. dmg, C_BRIGHT2)
  add_particle(player.x, player.y, C_BRIGHT2, 3)
  cam_shake(3)
  shake_timer = 5

  -- Hit sound
  noise(1, 0.08)
  tone(2, 150, 80, 0.1)

  log_msg(e.name .. " hits for " .. dmg .. " dmg", C_BRIGHT1)

  if player.hp <= 0 then
    player.hp = 0
    game_over = true
    -- Death sound
    tone(0, 200, 50, 0.5)
    noise(1, 0.3)
  end
end

----------------------------------------------
-- ITEM PICKUP (expanded with rings)
----------------------------------------------
local function pickup_item(idx)
  local it = items[idx]
  items_collected = items_collected + 1

  if it.type == ITEM_POTION then
    local healed = math.min(it.heal, player.max_hp - player.hp)
    player.hp = player.hp + healed
    add_float(player.x, player.y, "+" .. healed, C_LIGHT1)
    log_msg("Drank " .. it.name .. " (+" .. healed .. " HP)", C_LIGHT1)
    note(0, "E4", 0.05)
    note(0, "G4", 0.08)

  elseif it.type == ITEM_WEAPON then
    if it.atk_bonus > player.weapon_bonus then
      player.weapon_bonus = it.atk_bonus
      player.atk = player.base_atk + player.weapon_bonus
      log_msg("Equipped " .. it.name .. " (ATK+" .. it.atk_bonus .. ")", C_BRIGHT2)
      note(0, "C4", 0.05)
      note(0, "E4", 0.05)
    else
      log_msg("Found " .. it.name .. " (weaker)", C_MID3)
    end

  elseif it.type == ITEM_ARMOR then
    if it.def_bonus > player.armor_bonus then
      player.armor_bonus = it.def_bonus
      player.def = player.base_def + player.armor_bonus
      log_msg("Equipped " .. it.name .. " (DEF+" .. it.def_bonus .. ")", C_BRIGHT1)
      note(0, "C4", 0.05)
      note(0, "G4", 0.05)
    else
      log_msg("Found " .. it.name .. " (weaker)", C_MID3)
    end

  elseif it.type == ITEM_SCROLL then
    if it.tier == 1 then
      -- Smite: damage all visible enemies
      for _, e in ipairs(enemies) do
        if is_visible(e.x, e.y) then
          local dmg = 5 + floor_num * 2
          e.hp = e.hp - dmg
          add_float(e.x, e.y, "-" .. dmg, C_WHITE)
          add_particle(e.x, e.y, C_WHITE, 5)
        end
      end
      -- Remove dead enemies
      for i = #enemies, 1, -1 do
        if enemies[i].hp <= 0 then
          kills_total = kills_total + 1
          table.remove(enemies, i)
        end
      end
      log_msg("Scroll of Smite!", C_WHITE)
      cam_shake(5)
      flash_timer = 8
      flash_color = C_WHITE
      noise(0, 0.15)
      tone(1, 400, 800, 0.2)
    elseif it.tier == 2 then
      -- Shield: temporary DEF boost
      player.def = player.def + 3
      log_msg("Scroll of Shield! DEF+" .. 3, C_LIGHT2)
      note(0, "D4", 0.1)
    elseif it.tier == 3 then
      -- Sight: reveal full map
      for y = 0, MAP_H - 1 do
        for x = 0, MAP_W - 1 do
          explored[y * MAP_W + x] = true
        end
      end
      log_msg("Scroll of Sight! Map revealed!", C_LIGHT3)
      note(0, "C5", 0.08)
      note(0, "E5", 0.08)
    end

  elseif it.type == ITEM_RING then
    if it.tier == 1 then
      -- Ring of Might: permanent +2 ATK
      player.base_atk = player.base_atk + 2
      player.atk = player.base_atk + player.weapon_bonus
      log_msg("Ring of Might! ATK+2", C_BRIGHT3)
    elseif it.tier == 2 then
      -- Ring of Ward: permanent +2 DEF
      player.base_def = player.base_def + 2
      player.def = player.base_def + player.armor_bonus
      log_msg("Ring of Ward! DEF+2", C_BRIGHT3)
    elseif it.tier == 3 then
      -- Ring of Vigor: permanent +8 max HP and heal
      player.max_hp = player.max_hp + 8
      player.hp = math.min(player.hp + 8, player.max_hp)
      log_msg("Ring of Vigor! HP+8", C_BRIGHT3)
    end
    note(0, "E5", 0.08)
    note(1, "G5", 0.1)
  end

  -- Pickup sparkle
  add_particle(it.x, it.y, it.color, 5)
  table.remove(items, idx)
end

----------------------------------------------
-- ENEMY AI (improved: flee at low HP)
----------------------------------------------
local function try_move_enemy(e, dx, dy)
  local nx, ny = e.x + dx, e.y + dy
  if tile_has_player(nx, ny) then
    enemy_attacks_player(e)
    return true
  end
  if is_walkable(nx, ny) and not tile_has_enemy(nx, ny) then
    e.x = nx
    e.y = ny
    return true
  end
  return false
end

local function ai_flee(e)
  -- Run away from player
  local dx = sign(e.x - player.x)
  local dy = sign(e.y - player.y)
  if not try_move_enemy(e, dx, 0) then
    if not try_move_enemy(e, 0, dy) then
      -- Cornered, random
      local dirs = {{1,0},{-1,0},{0,1},{0,-1}}
      local d = dirs[math.random(1,4)]
      try_move_enemy(e, d[1], d[2])
    end
  end
end

local function ai_wander(e)
  -- Wander randomly, chase if player nearby
  local d = dist(e.x, e.y, player.x, player.y)
  if d <= 5 then
    e.alert = true
  end

  -- Flee at low HP (except for mindless types)
  if e.alert and e.hp <= math.floor(e.max_hp * 0.25) and e.type ~= "skeleton" then
    ai_flee(e)
    return
  end

  if e.alert and d <= 8 then
    local dx = sign(player.x - e.x)
    local dy = sign(player.y - e.y)
    if math.random() < 0.5 then
      if not try_move_enemy(e, dx, 0) then
        try_move_enemy(e, 0, dy)
      end
    else
      if not try_move_enemy(e, 0, dy) then
        try_move_enemy(e, dx, 0)
      end
    end
  else
    -- Random wander
    if math.random() < 0.4 then
      local dirs = {{1,0},{-1,0},{0,1},{0,-1}}
      local d = dirs[math.random(1,4)]
      try_move_enemy(e, d[1], d[2])
    end
  end
end

local function ai_chase(e)
  -- Direct chase when player is close
  local d = dist(e.x, e.y, player.x, player.y)
  if d <= 8 then
    e.alert = true
  end
  if d > 12 then
    e.alert = false
  end

  -- Flee at low HP
  if e.alert and e.hp <= math.floor(e.max_hp * 0.25) then
    ai_flee(e)
    return
  end

  if e.alert then
    local dx = sign(player.x - e.x)
    local dy = sign(player.y - e.y)
    -- Prefer axis with greater distance
    if math.abs(player.x - e.x) >= math.abs(player.y - e.y) then
      if not try_move_enemy(e, dx, 0) then
        try_move_enemy(e, 0, dy)
      end
    else
      if not try_move_enemy(e, 0, dy) then
        try_move_enemy(e, dx, 0)
      end
    end
  else
    ai_wander(e)
  end
end

local function ai_patrol(e)
  -- Patrol in a direction, turn on wall, chase if sees player
  local d = dist(e.x, e.y, player.x, player.y)
  if d <= 6 and is_visible(e.x, e.y) then
    e.alert = true
  end
  if d > 10 then
    e.alert = false
  end

  if e.alert then
    ai_chase(e)
    return
  end

  -- Patrol
  local dirs = {{1,0},{-1,0},{0,1},{0,-1}}
  local dir = dirs[e.patrol_dir] or dirs[1]
  e.patrol_steps = e.patrol_steps + 1

  if e.patrol_steps > 4 + math.random(3) or not try_move_enemy(e, dir[1], dir[2]) then
    e.patrol_dir = math.random(1, 4)
    e.patrol_steps = 0
  end
end

local function ai_phase(e)
  -- Ghost: can move through walls occasionally, always chases
  local d = dist(e.x, e.y, player.x, player.y)
  if d <= 10 then
    e.alert = true
  end

  if e.alert then
    local dx = sign(player.x - e.x)
    local dy = sign(player.y - e.y)
    local nx, ny

    -- Try normal move first
    if math.abs(player.x - e.x) >= math.abs(player.y - e.y) then
      nx, ny = e.x + dx, e.y + dy
    else
      nx, ny = e.x, e.y + dy
      dx = 0
    end

    if tile_has_player(nx, ny) then
      enemy_attacks_player(e)
    elseif is_walkable(nx, ny) and not tile_has_enemy(nx, ny) then
      e.x = nx
      e.y = ny
    elseif math.random() < 0.3 then
      -- Phase through wall
      if not tile_has_enemy(nx, ny) and not tile_has_player(nx, ny) then
        e.x = nx
        e.y = ny
        add_particle(e.x, e.y, C_LIGHT2, 2)
      end
    end
  else
    if math.random() < 0.3 then
      local dirs = {{1,0},{-1,0},{0,1},{0,-1}}
      local d = dirs[math.random(1,4)]
      try_move_enemy(e, d[1], d[2])
    end
  end
end

local function update_enemy(e)
  if e.ai == "wander" then ai_wander(e)
  elseif e.ai == "chase" then ai_chase(e)
  elseif e.ai == "patrol" then ai_patrol(e)
  elseif e.ai == "phase" then ai_phase(e)
  end
end

----------------------------------------------
-- FLOOR POPULATION (expanded with rings + bat)
----------------------------------------------
local function populate_floor()
  enemies = {}
  items = {}

  -- Number of enemies scales with floor
  local num_enemies = 4 + floor_num * 2
  num_enemies = math.min(num_enemies, 20)

  -- Determine available enemy types by floor
  local available = {"rat"}
  if floor_num >= 2 then table.insert(available, "bat") end
  if floor_num >= 2 then table.insert(available, "snake") end
  if floor_num >= 3 then table.insert(available, "skeleton") end
  if floor_num >= 4 then table.insert(available, "ghost") end
  if floor_num >= 5 then table.insert(available, "ogre") end
  if floor_num >= 7 then table.insert(available, "wraith") end

  for i = 1, num_enemies do
    local x, y = find_empty_floor(true)
    if x then
      -- Weight towards harder enemies on deeper floors
      local etype = available[math.random(1, #available)]
      -- Higher chance of harder enemies deeper
      if floor_num >= 4 and math.random() < 0.3 then
        etype = available[#available]
      end
      table.insert(enemies, make_enemy(etype, x, y))
    end
  end

  -- Items: potions, weapons, armor, scrolls, rings
  local num_items = 3 + math.random(2)
  for i = 1, num_items do
    local x, y = find_empty_floor(true)
    if x then
      local roll = math.random(100)
      local itype, tier
      if roll <= 35 then
        itype = ITEM_POTION
        tier = math.min(3, 1 + math.floor(floor_num / 3))
      elseif roll <= 52 then
        itype = ITEM_WEAPON
        tier = math.min(4, 1 + math.floor(floor_num / 2))
      elseif roll <= 69 then
        itype = ITEM_ARMOR
        tier = math.min(4, 1 + math.floor(floor_num / 2))
      elseif roll <= 88 then
        itype = ITEM_SCROLL
        tier = math.random(1, 3)
      else
        itype = ITEM_RING
        tier = math.random(1, 3)
      end
      table.insert(items, make_item(itype, tier, x, y))
    end
  end
end

----------------------------------------------
-- NEW FLOOR
----------------------------------------------
local function start_new_floor()
  explored = {}
  generate_dungeon()

  -- Place player in first room
  if #rooms >= 1 then
    local first = rooms[1]
    player.x = math.floor(first.x + first.w / 2)
    player.y = math.floor(first.y + first.h / 2)
  end

  populate_floor()
  compute_fov(player.x, player.y, FOV_RADIUS)

  particles = {}
  floats = {}
  msg_log = {}

  log_msg("Floor " .. floor_num .. " of Duskhold", C_LIGHT3)
  if floor_num == 1 then
    log_msg("Find the stairs (>) to descend", C_MID3)
  end

  -- Ambient sound for new floor
  tone(0, 80, 40, 0.3)
end

----------------------------------------------
-- PLAYER TURN
----------------------------------------------
local function try_descend()
  if map_get(player.x, player.y) == T_STAIR then
    floor_num = floor_num + 1
    log_msg("Descending to floor " .. floor_num .. "...", C_LIGHT3)
    note(0, "G3", 0.1)
    note(0, "E3", 0.1)
    note(0, "C3", 0.2)
    start_new_floor()
    return true
  end
  return false
end

local function player_try_move(dx, dy)
  local nx, ny = player.x + dx, player.y + dy

  -- Check for enemy at target
  local eidx = tile_has_enemy(nx, ny)
  if eidx then
    attack_enemy(eidx)
    player_moved = true
    return
  end

  -- Check walkable
  if is_walkable(nx, ny) then
    player.x = nx
    player.y = ny
    player_moved = true

    -- Footstep sound (subtle)
    if math.random() < 0.4 then
      tone(3, 60, 50, 0.02)
    end
    -- Door creak sound
    if map_get(nx, ny) == T_DOOR then
      tone(2, 200, 120, 0.05)
    end

    -- Check for item pickup
    local iidx = tile_has_item(nx, ny)
    if iidx then
      pickup_item(iidx)
    end
  end
end

----------------------------------------------
-- GAME INIT
----------------------------------------------
local function init_player()
  player = {
    x = 0, y = 0,
    hp = 25, max_hp = 25,
    base_atk = 3, atk = 3,
    base_def = 1, def = 1,
    weapon_bonus = 0,
    armor_bonus = 0,
    xp = 0, next_xp = 10,
    level = 1,
    hit_flash = 0,
  }
end

local function new_game()
  floor_num = 1
  turn_count = 0
  kills_total = 0
  items_collected = 0
  game_over = false
  paused = false
  show_map = false
  shake_amt = 0
  shake_timer = 0
  flash_timer = 0

  init_player()
  start_new_floor()
end

----------------------------------------------
-- TITLE SCENE & ATTRACT MODE
----------------------------------------------
local title_blink = 0
local title_particles = {}
local title_intro_t = 0
local title_idle_timer = 0

-- Attract / demo mode state
local demo_active = false
local demo_timer = 0
local demo_map = {}
local demo_visible = {}
local demo_explored = {}
local demo_rooms = {}
local demo_player = {}
local demo_enemies = {}
local demo_items = {}
local demo_particles = {}
local demo_floats = {}
local demo_cam_x, demo_cam_y = 0, 0
local demo_turn = 0
local demo_move_timer = 0
local demo_target_x, demo_target_y = 0, 0
local demo_msg = {}

-- Miniature dungeon for demo
local function demo_map_get(x, y)
  if x < 0 or x >= MAP_W or y < 0 or y >= MAP_H then return T_WALL end
  return demo_map[y * MAP_W + x] or T_VOID
end

local function demo_map_set(x, y, v)
  if x >= 0 and x < MAP_W and y >= 0 and y < MAP_H then
    demo_map[y * MAP_W + x] = v
  end
end

local function demo_is_walkable(x, y)
  local t = demo_map_get(x, y)
  return t == T_FLOOR or t == T_STAIR or t == T_DOOR
end

local function demo_set_visible(x, y)
  if x >= 0 and x < MAP_W and y >= 0 and y < MAP_H then
    demo_visible[y * MAP_W + x] = true
    demo_explored[y * MAP_W + x] = true
  end
end

local function demo_is_visible(x, y)
  return demo_visible[y * MAP_W + x] == true
end

local function demo_is_explored(x, y)
  return demo_explored[y * MAP_W + x] == true
end

local function demo_compute_fov(ox, oy, radius)
  demo_visible = {}
  demo_set_visible(ox, oy)
  local steps = 72
  for i = 0, steps - 1 do
    local angle = (i / steps) * math.pi * 2
    local dx = math.cos(angle)
    local dy = math.sin(angle)
    local x = ox + 0.5
    local y = oy + 0.5
    for d = 1, radius do
      x = x + dx
      y = y + dy
      local ix = math.floor(x)
      local iy = math.floor(y)
      if ix < 0 or ix >= MAP_W or iy < 0 or iy >= MAP_H then break end
      demo_set_visible(ix, iy)
      if demo_map_get(ix, iy) == T_WALL then break end
    end
  end
end

local function demo_tile_has_enemy(x, y)
  for i, e in ipairs(demo_enemies) do
    if e.x == x and e.y == y then return i end
  end
  return nil
end

local function demo_init()
  demo_active = true
  demo_timer = 0
  demo_turn = 0
  demo_move_timer = 0
  demo_particles = {}
  demo_floats = {}
  demo_msg = {}

  -- Generate a small dungeon
  demo_map = {}
  for i = 0, MAP_W * MAP_H - 1 do
    demo_map[i] = T_WALL
  end
  demo_rooms = {}
  demo_visible = {}
  demo_explored = {}

  local attempts = 0
  while #demo_rooms < 6 and attempts < 150 do
    attempts = attempts + 1
    local rw = math.random(4, 7)
    local rh = math.random(3, 5)
    local rx = math.random(1, MAP_W - rw - 2)
    local ry = math.random(1, MAP_H - rh - 2)
    local new_room = {x = rx, y = ry, w = rw, h = rh}
    local ok = true
    for _, r in ipairs(demo_rooms) do
      if rooms_overlap(new_room, r, 2) then ok = false break end
    end
    if ok then
      for y = ry, ry + rh - 1 do
        for x = rx, rx + rw - 1 do
          demo_map_set(x, y, T_FLOOR)
        end
      end
      if #demo_rooms > 0 then
        local prev = demo_rooms[#demo_rooms]
        local cx1 = math.floor(prev.x + prev.w / 2)
        local cy1 = math.floor(prev.y + prev.h / 2)
        local cx2 = math.floor(rx + rw / 2)
        local cy2 = math.floor(ry + rh / 2)
        if math.random() < 0.5 then
          for x = math.min(cx1,cx2), math.max(cx1,cx2) do demo_map_set(x, cy1, T_FLOOR) end
          for y = math.min(cy1,cy2), math.max(cy1,cy2) do demo_map_set(cx2, y, T_FLOOR) end
        else
          for y = math.min(cy1,cy2), math.max(cy1,cy2) do demo_map_set(cx1, y, T_FLOOR) end
          for x = math.min(cx1,cx2), math.max(cx1,cx2) do demo_map_set(x, cy2, T_FLOOR) end
        end
      end
      table.insert(demo_rooms, new_room)
    end
  end

  -- Place stairs
  if #demo_rooms >= 2 then
    local last = demo_rooms[#demo_rooms]
    demo_map_set(math.floor(last.x + last.w/2), math.floor(last.y + last.h/2), T_STAIR)
  end

  -- Place demo player
  if #demo_rooms >= 1 then
    local first = demo_rooms[1]
    demo_player = {
      x = math.floor(first.x + first.w / 2),
      y = math.floor(first.y + first.h / 2),
      hp = 20, max_hp = 20, atk = 4, def = 2,
      hit_flash = 0,
    }
  end

  -- Place some enemies
  demo_enemies = {}
  for i = 1, 5 do
    if #demo_rooms >= 2 then
      local room = demo_rooms[math.random(2, #demo_rooms)]
      local ex = room.x + math.random(0, room.w - 1)
      local ey = room.y + math.random(0, room.h - 1)
      if demo_is_walkable(ex, ey) and not demo_tile_has_enemy(ex, ey) then
        local types = {"rat", "snake", "skeleton"}
        local et = types[math.random(1, #types)]
        local def = enemy_defs[et]
        table.insert(demo_enemies, {
          x = ex, y = ey,
          hp = def.hp, max_hp = def.hp,
          atk = def.atk, def_val = def.def,
          glyph = def.glyph, color = def.color,
          name = def.name, hit_flash = 0,
        })
      end
    end
  end

  -- Place some items
  demo_items = {}
  for i = 1, 3 do
    if #demo_rooms >= 1 then
      local room = demo_rooms[math.random(1, #demo_rooms)]
      local ix = room.x + math.random(0, room.w - 1)
      local iy = room.y + math.random(0, room.h - 1)
      if demo_is_walkable(ix, iy) then
        local glyphs = {"!", "/", "[", "?"}
        local colors = {C_LIGHT1, C_BRIGHT2, C_BRIGHT1, C_LIGHT3}
        local r = math.random(1, 4)
        table.insert(demo_items, {x = ix, y = iy, glyph = glyphs[r], color = colors[r]})
      end
    end
  end

  -- Pick a target room to walk toward
  if #demo_rooms >= 2 then
    local tgt = demo_rooms[2]
    demo_target_x = math.floor(tgt.x + tgt.w / 2)
    demo_target_y = math.floor(tgt.y + tgt.h / 2)
  end

  demo_compute_fov(demo_player.x, demo_player.y, FOV_RADIUS)
end

local function demo_pick_next_target()
  -- Pick a random room to explore
  if #demo_rooms >= 1 then
    local tgt = demo_rooms[math.random(1, #demo_rooms)]
    demo_target_x = math.floor(tgt.x + tgt.w / 2)
    demo_target_y = math.floor(tgt.y + tgt.h / 2)
  end
end

local function demo_update()
  demo_timer = demo_timer + 1
  demo_move_timer = demo_move_timer + 1

  -- Auto-move every 4 frames
  if demo_move_timer >= 4 then
    demo_move_timer = 0

    -- Move toward target
    local dx = sign(demo_target_x - demo_player.x)
    local dy = sign(demo_target_y - demo_player.y)

    -- Check for enemy adjacent - attack it
    local attacked = false
    for i, e in ipairs(demo_enemies) do
      if math.abs(e.x - demo_player.x) + math.abs(e.y - demo_player.y) == 1 then
        -- Attack
        local dmg = math.max(1, demo_player.atk - e.def_val + math.random(-1, 1))
        e.hp = e.hp - dmg
        e.hit_flash = 4
        table.insert(demo_floats, {x = e.x * TILE, y = e.y * TILE, txt = "-"..dmg, c = C_WHITE, life = 25, dy = -0.8})
        table.insert(demo_particles, {x = e.x*TILE+3, y = e.y*TILE+3, vx = (math.random()-0.5)*2, vy = (math.random()-0.5)*2, c = C_LGRAY, life = 8})
        noise(0, 0.04)
        if e.hp <= 0 then
          for j = 1, 4 do
            table.insert(demo_particles, {x = e.x*TILE+3, y = e.y*TILE+3, vx = (math.random()-0.5)*3, vy = (math.random()-0.5)*3, c = e.color, life = 12})
          end
          table.insert(demo_msg, {text = "Slain " .. e.name, timer = 40})
          table.remove(demo_enemies, i)
          noise(2, 0.06)
        end
        attacked = true
        break
      end
    end

    if not attacked then
      -- Try to move
      local moved = false
      -- Prefer horizontal then vertical, or random
      if math.abs(dx) >= math.abs(dy) then
        if dx ~= 0 and demo_is_walkable(demo_player.x + dx, demo_player.y) then
          demo_player.x = demo_player.x + dx
          moved = true
        elseif dy ~= 0 and demo_is_walkable(demo_player.x, demo_player.y + dy) then
          demo_player.y = demo_player.y + dy
          moved = true
        end
      else
        if dy ~= 0 and demo_is_walkable(demo_player.x, demo_player.y + dy) then
          demo_player.y = demo_player.y + dy
          moved = true
        elseif dx ~= 0 and demo_is_walkable(demo_player.x + dx, demo_player.y) then
          demo_player.x = demo_player.x + dx
          moved = true
        end
      end

      -- If stuck, pick new target
      if not moved then
        demo_pick_next_target()
      end

      -- Pick up items
      for i = #demo_items, 1, -1 do
        if demo_items[i].x == demo_player.x and demo_items[i].y == demo_player.y then
          table.insert(demo_particles, {x = demo_items[i].x*TILE+3, y = demo_items[i].y*TILE+3, vx = 0, vy = -1, c = demo_items[i].color, life = 10})
          table.insert(demo_msg, {text = "Picked up item", timer = 30})
          note(0, "E4", 0.04)
          table.remove(demo_items, i)
        end
      end
    end

    -- Reached target? pick new one
    if demo_player.x == demo_target_x and demo_player.y == demo_target_y then
      demo_pick_next_target()
    end

    demo_compute_fov(demo_player.x, demo_player.y, FOV_RADIUS)
    demo_turn = demo_turn + 1

    -- Enemy movement (simple chase)
    for _, e in ipairs(demo_enemies) do
      if e.hit_flash > 0 then e.hit_flash = e.hit_flash - 1 end
      local ed = dist(e.x, e.y, demo_player.x, demo_player.y)
      if ed <= 6 and math.random() < 0.6 then
        local edx = sign(demo_player.x - e.x)
        local edy = sign(demo_player.y - e.y)
        local enx, eny = e.x + edx, e.y + edy
        if enx == demo_player.x and eny == demo_player.y then
          -- Attack player
          local dmg = math.max(1, e.atk - demo_player.def + math.random(-1, 0))
          demo_player.hp = demo_player.hp - dmg
          demo_player.hit_flash = 4
          table.insert(demo_floats, {x = demo_player.x*TILE, y = demo_player.y*TILE, txt = "-"..dmg, c = C_BRIGHT2, life = 25, dy = -0.8})
          noise(1, 0.04)
          if demo_player.hp <= 0 then
            demo_player.hp = demo_player.max_hp  -- respawn for demo
            demo_pick_next_target()
          end
        elseif demo_is_walkable(enx, eny) and not demo_tile_has_enemy(enx, eny) then
          e.x = enx
          e.y = eny
        end
      end
    end
  end

  -- Update demo particles
  for i = #demo_particles, 1, -1 do
    local p = demo_particles[i]
    p.x = p.x + p.vx
    p.y = p.y + p.vy
    p.vx = p.vx * 0.9
    p.vy = p.vy * 0.9
    p.life = p.life - 1
    if p.life <= 0 then table.remove(demo_particles, i) end
  end

  -- Update demo floats
  for i = #demo_floats, 1, -1 do
    local f = demo_floats[i]
    f.y = f.y + f.dy
    f.life = f.life - 1
    if f.life <= 0 then table.remove(demo_floats, i) end
  end

  -- Update demo messages
  for i = #demo_msg, 1, -1 do
    demo_msg[i].timer = demo_msg[i].timer - 1
    if demo_msg[i].timer <= 0 then table.remove(demo_msg, i) end
  end

  -- Regenerate dungeon after ~600 frames to keep demo running indefinitely
  if demo_timer > 600 then
    demo_init()
  end

  -- Also regenerate when player reaches the stair
  if demo_map_get(demo_player.x, demo_player.y) == T_STAIR then
    demo_init()
  end
end

local function demo_draw(s)
  cls(s, 0)

  -- Camera follows demo player
  local dcx = demo_player.x * TILE - 80 + TILE / 2
  local dcy = demo_player.y * TILE - 54 + TILE / 2

  -- Draw tiles
  local start_tx = math.floor(dcx / TILE) - 1
  local start_ty = math.floor(dcy / TILE) - 1
  local end_tx = start_tx + VIEW_W + 2
  local end_ty = start_ty + VIEW_H + 2

  for ty = start_ty, end_ty do
    for tx = start_tx, end_tx do
      local sx = tx * TILE - dcx
      local sy = ty * TILE - dcy
      if sx > -TILE and sx < 160 and sy > -TILE and sy < 108 then
        local tile = demo_map_get(tx, ty)
        local vis = demo_is_visible(tx, ty)
        local exp = demo_is_explored(tx, ty)
        if not vis and not exp then
          rectf(s, sx, sy, TILE, TILE, C_BLACK)
        else
          local bmod = vis and 0 or -4
          if tile == T_WALL then
            local c = clamp(C_MID1 + bmod, 1, 15)
            rectf(s, sx, sy, TILE, TILE, c)
            if (tx + ty) % 3 == 0 then pix(s, sx+1, sy+1, clamp(c-1,0,15)) end
          elseif tile == T_FLOOR then
            local c = clamp(C_DARK2 + bmod, 0, 15)
            rectf(s, sx, sy, TILE, TILE, c)
            if (tx + ty) % 2 == 0 then pix(s, sx+2, sy+2, clamp(c+1,0,15)) end
          elseif tile == T_STAIR then
            local c = clamp(C_DARK2 + bmod, 0, 15)
            rectf(s, sx, sy, TILE, TILE, c)
            if vis then
              pix(s, sx+1, sy+1, C_BRIGHT3)
              pix(s, sx+2, sy+2, C_BRIGHT3)
              pix(s, sx+1, sy+3, C_BRIGHT3)
            end
          end
        end
      end
    end
  end

  -- Draw demo items
  for _, it in ipairs(demo_items) do
    if demo_is_visible(it.x, it.y) then
      local sx = it.x * TILE - dcx
      local sy = it.y * TILE - dcy
      if sx > -TILE and sx < 160 and sy > -TILE and sy < 108 then
        text(s, it.glyph, sx + 1, sy, it.color, 0)
      end
    end
  end

  -- Draw demo enemies
  for _, e in ipairs(demo_enemies) do
    if demo_is_visible(e.x, e.y) then
      local sx = e.x * TILE - dcx
      local sy = e.y * TILE - dcy
      if sx > -TILE and sx < 160 and sy > -TILE and sy < 108 then
        local c = e.color
        if e.hit_flash > 0 then c = C_WHITE end
        text(s, e.glyph, sx + 1, sy, c, 0)
      end
    end
  end

  -- Draw demo player
  local px = demo_player.x * TILE - dcx
  local py = demo_player.y * TILE - dcy
  local pc = C_WHITE
  if demo_player.hit_flash > 0 then
    demo_player.hit_flash = demo_player.hit_flash - 1
    pc = C_BRIGHT2
  end
  text(s, "@", px + 1, py, pc, 0)

  -- Draw demo particles
  for _, p in ipairs(demo_particles) do
    local sx = p.x - dcx
    local sy = p.y - dcy
    if sx >= 0 and sx < 160 and sy >= 0 and sy < 108 then
      pix(s, math.floor(sx), math.floor(sy), p.c)
    end
  end

  -- Draw demo floats
  for _, f in ipairs(demo_floats) do
    local sx = f.x - dcx + 2
    local sy = f.y - dcy
    if sx >= 0 and sx < 160 and sy >= 0 and sy < 108 then
      text(s, f.txt, math.floor(sx), math.floor(sy), f.c, 0)
    end
  end

  -- Demo messages at bottom
  if #demo_msg > 0 then
    local m = demo_msg[#demo_msg]
    text(s, m.text, 80, 100, C_LGRAY, ALIGN_HCENTER)
  end

  -- Dim overlay
  -- "PRESS START" overlay
  rectf(s, 0, 0, 160, 10, C_BLACK)
  text(s, "DUSKHOLD", 80, 1, C_LGRAY, ALIGN_HCENTER)

  if math.floor(demo_timer / 25) % 2 == 0 then
    rectf(s, 40, 110, 80, 10, C_BLACK)
    text(s, "PRESS START", 80, 111, C_WHITE, ALIGN_HCENTER)
  end

  -- 7-segment clock display (HH:MM) in top-right corner
  -- Segment layout per digit:
  --  _a_
  -- |   |
  -- f   b
  -- |_g_|
  -- |   |
  -- e   c
  -- |_d_|
  -- Segment bits: a=1, b=2, c=4, d=8, e=16, f=32, g=64
  local seg_digits = {
    [0] = 1+2+4+8+16+32,     -- abcdef
    [1] = 2+4,                -- bc
    [2] = 1+2+8+16+64,       -- abdeg
    [3] = 1+2+4+8+64,        -- abcdg
    [4] = 2+4+32+64,         -- bcfg
    [5] = 1+4+8+32+64,       -- acdfg
    [6] = 1+4+8+16+32+64,    -- acdefg
    [7] = 1+2+4,             -- abc
    [8] = 1+2+4+8+16+32+64,  -- abcdefg
    [9] = 1+2+4+8+32+64,     -- abcdfg
  }

  local function draw_seg_digit(surf, ox, oy, digit, col)
    local segs = seg_digits[digit] or 0
    local t = 2  -- segment thickness
    -- a: top horizontal
    if segs % 2 >= 1 then rectf(surf, ox+t, oy, 3, t, col) end
    -- b: top-right vertical
    if math.floor(segs/2) % 2 >= 1 then rectf(surf, ox+t+3, oy+t, t, 4, col) end
    -- c: bottom-right vertical
    if math.floor(segs/4) % 2 >= 1 then rectf(surf, ox+t+3, oy+t+4+1, t, 4, col) end
    -- d: bottom horizontal
    if math.floor(segs/8) % 2 >= 1 then rectf(surf, ox+t, oy+t+4+1+4, 3, t, col) end
    -- e: bottom-left vertical
    if math.floor(segs/16) % 2 >= 1 then rectf(surf, ox, oy+t+4+1, t, 4, col) end
    -- f: top-left vertical
    if math.floor(segs/32) % 2 >= 1 then rectf(surf, ox, oy+t, t, 4, col) end
    -- g: middle horizontal
    if math.floor(segs/64) % 2 >= 1 then rectf(surf, ox+t, oy+t+4, 3, 1, col) end
  end

  local t = date()
  local hh = t.hour or 0
  local mm = t.min or 0
  local h1 = math.floor(hh / 10)
  local h2 = hh % 10
  local m1 = math.floor(mm / 10)
  local m2 = mm % 10
  local clk_c = C_DARK3
  local cx = 160 - 4 * 9 - 4  -- 4 digits * 9px spacing, plus margin
  local cy = 1

  draw_seg_digit(s, cx, cy, h1, clk_c)
  draw_seg_digit(s, cx + 9, cy, h2, clk_c)

  -- Blinking colon (two dots) every 30 frames
  if math.floor(frame() / 30) % 2 == 0 then
    rectf(s, cx + 18, cy + 3, 2, 2, clk_c)
    rectf(s, cx + 18, cy + 8, 2, 2, clk_c)
  end

  draw_seg_digit(s, cx + 22, cy, m1, clk_c)
  draw_seg_digit(s, cx + 31, cy, m2, clk_c)
end

function title_init()
  title_blink = 0
  title_intro_t = 0
  title_idle_timer = 0
  demo_active = false
  title_particles = {}
  for i = 1, 50 do
    title_particles[i] = {
      x = math.random(0, 159),
      y = math.random(0, 119),
      speed = 0.1 + math.random() * 0.4,
      c = math.random(1, 4),
    }
  end
end

function title_update()
  title_blink = title_blink + 1
  title_intro_t = title_intro_t + 1
  title_idle_timer = title_idle_timer + 1

  for _, p in ipairs(title_particles) do
    p.y = p.y + p.speed
    if p.y > 120 then
      p.y = -1
      p.x = math.random(0, 159)
    end
  end

  -- Start button or tap: exit attract or start game
  local title_start = btnp("start") or touch_start()
  if title_intro_t > 30 and title_start then
    if demo_active then
      demo_active = false
      title_idle_timer = 0
      return
    end
    note(0, "C4", 0.08)
    note(1, "G4", 0.1)
    new_game()
    go("game")
    return
  end

  -- Any button or touch exits demo or resets idle timer
  if btnp("left") or btnp("right") or btnp("up") or btnp("down") or btnp("a") or btnp("b") or touch_start() then
    if demo_active then
      demo_active = false
      title_idle_timer = 0
      return
    end
    title_idle_timer = 0
  end

  -- Launch attract mode after ~90 idle frames
  if not demo_active and title_idle_timer > 90 and title_intro_t > 40 then
    demo_init()
  end

  -- Update attract mode
  if demo_active then
    demo_update()
  end
end

function title_draw()
  local s = screen()

  -- If attract mode is active, draw that instead
  if demo_active then
    demo_draw(s)
    return
  end

  cls(s, 0)

  -- Falling dust particles
  for _, p in ipairs(title_particles) do
    pix(s, math.floor(p.x), math.floor(p.y), p.c)
  end

  -- Border
  rect(s, 1, 1, 158, 118, C_DARK2)

  -- Title: DUSKHOLD
  local ty = 20
  if title_intro_t < 30 then
    ty = -20 + (title_intro_t / 30) * 40
  end

  -- Shadow
  text(s, "DUSKHOLD", 81, ty + 1, C_DARK3, ALIGN_HCENTER)
  -- Main
  text(s, "DUSKHOLD", 80, ty, C_WHITE, ALIGN_HCENTER)

  -- Subtitle
  if title_intro_t > 20 then
    text(s, "Into the Dark Below", 80, ty + 14, C_GRAY, ALIGN_HCENTER)
  end

  -- Decorative line
  if title_intro_t > 25 then
    line(s, 40, ty + 24, 120, ty + 24, C_DARK3)
  end

  -- Instructions
  if title_intro_t > 30 then
    if math.floor(title_blink / 20) % 2 == 0 then
      text(s, "PRESS START", 80, 68, C_WHITE, ALIGN_HCENTER)
    end

    text(s, "D-PAD: MOVE / ATTACK", 80, 85, C_MID2, ALIGN_HCENTER)
    text(s, "A: DESCEND STAIRS", 80, 93, C_MID2, ALIGN_HCENTER)
    text(s, "B: TOGGLE MAP", 80, 101, C_MID2, ALIGN_HCENTER)
    text(s, "SELECT: PAUSE", 80, 109, C_MID1, ALIGN_HCENTER)
  end
end

----------------------------------------------
-- GAME SCENE
----------------------------------------------
function game_init()
  -- Already initialized from title
end

function game_update()
  -- Pause toggle
  if btnp("select") then
    paused = not paused
    if paused then
      note(0, "E3", 0.05)
    else
      note(0, "E4", 0.05)
    end
  end
  if paused then return end

  -- Track touch timing for double-tap and long-press detection
  if touch_start() then
    touch_start_frame = frame()
    touch_long_fired = false
  end

  -- Detect long press (finger held down for LONG_PRESS_FRAMES)
  local touch_long_press = false
  if touch() and not touch_long_fired then
    if (frame() - touch_start_frame) >= LONG_PRESS_FRAMES then
      touch_long_press = true
      touch_long_fired = true
    end
  end

  -- Detect tap (short touch that just ended, not a long press)
  local touch_tap = false
  if touch_end() and not touch_long_fired then
    touch_tap = true
  end

  -- Detect double-tap
  local touch_double_tap = false
  if touch_tap then
    if (frame() - touch_last_tap_frame) <= DOUBLE_TAP_WINDOW then
      touch_double_tap = true
      touch_last_tap_frame = -999  -- reset so triple tap doesn't re-trigger
    else
      touch_last_tap_frame = frame()
    end
  end

  -- Read swipe direction (one swipe = one move, perfect for turn-based)
  local sw = swipe()

  -- Game over - wait for input to go to death screen
  if game_over then
    if btnp("start") or btnp("a") or touch_tap then
      death_stats = {
        floor = floor_num,
        level = player.level,
        kills = kills_total,
        items = items_collected,
        turns = turn_count,
      }
      go("death")
    end
    return
  end

  -- Map toggle (B button or double-tap or long-press)
  if btnp("b") or touch_double_tap or touch_long_press then
    show_map = not show_map
  end

  -- Descend stairs (A button or tap)
  if btnp("a") or touch_tap then
    if try_descend() then return end
  end

  -- Player movement (turn-based)
  player_moved = false

  if btnp("left") or sw == "left" then player_try_move(-1, 0) end
  if btnp("right") or sw == "right" then player_try_move(1, 0) end
  if btnp("up") or sw == "up" then player_try_move(0, -1) end
  if btnp("down") or sw == "down" then player_try_move(0, 1) end

  -- If player took action, enemies take turn
  if player_moved then
    turn_count = turn_count + 1
    compute_fov(player.x, player.y, FOV_RADIUS)

    -- Enemy turns
    for _, e in ipairs(enemies) do
      if not game_over then
        update_enemy(e)
      end
    end
  end

  -- Timers
  if player.hit_flash > 0 then player.hit_flash = player.hit_flash - 1 end
  for _, e in ipairs(enemies) do
    if e.hit_flash > 0 then e.hit_flash = e.hit_flash - 1 end
  end

  if shake_timer > 0 then
    shake_timer = shake_timer - 1
    if shake_timer <= 0 then
      cam(0, 0)
    end
  end

  if flash_timer > 0 then flash_timer = flash_timer - 1 end

  -- Update particles
  for i = #particles, 1, -1 do
    local p = particles[i]
    p.x = p.x + p.vx
    p.y = p.y + p.vy
    p.life = p.life - 1
    p.vx = p.vx * 0.9
    p.vy = p.vy * 0.9
    if p.life <= 0 then
      table.remove(particles, i)
    end
  end

  -- Update floating text
  for i = #floats, 1, -1 do
    local f = floats[i]
    f.y = f.y + f.dy
    f.life = f.life - 1
    if f.life <= 0 then
      table.remove(floats, i)
    end
  end

  -- Update message timers
  for i = #msg_log, 1, -1 do
    msg_log[i].timer = msg_log[i].timer - 1
    if msg_log[i].timer <= 0 then
      table.remove(msg_log, i)
    end
  end
end

----------------------------------------------
-- GAME DRAWING (improved tile visuals)
----------------------------------------------
local function draw_tile(s, tx, ty, sx, sy)
  local tile = map_get(tx, ty)
  local vis = is_visible(tx, ty)
  local exp = is_explored(tx, ty)

  if not vis and not exp then
    -- Unexplored: pitch black
    rectf(s, sx, sy, TILE, TILE, C_BLACK)
    return
  end

  -- Dim explored tiles, bright visible tiles
  local brightness_mod = vis and 0 or -4

  if tile == T_WALL then
    local c = clamp(C_MID1 + brightness_mod, 1, 15)
    rectf(s, sx, sy, TILE, TILE, c)
    -- Wall detail: top edge highlight
    if map_get(tx, ty - 1) ~= T_WALL then
      rectf(s, sx, sy, TILE, 1, clamp(c + 1, 0, 15))
    end
    -- Subtle texture variation
    if (tx + ty) % 3 == 0 then
      pix(s, sx + 1, sy + 1, clamp(c - 1, 0, 15))
    end
    if (tx * 7 + ty * 13) % 5 == 0 then
      pix(s, sx + 3, sy + 2, clamp(c + 1, 0, 15))
    end
  elseif tile == T_FLOOR then
    local c = clamp(C_DARK2 + brightness_mod, 0, 15)
    rectf(s, sx, sy, TILE, TILE, c)
    -- Floor texture: scattered dots
    if (tx + ty) % 2 == 0 then
      pix(s, sx + 2, sy + 2, clamp(c + 1, 0, 15))
    end
    if (tx * 3 + ty * 7) % 11 == 0 and vis then
      pix(s, sx + 4, sy + 1, clamp(c + 1, 0, 15))
    end
  elseif tile == T_STAIR then
    local c = clamp(C_DARK2 + brightness_mod, 0, 15)
    rectf(s, sx, sy, TILE, TILE, c)
    if vis then
      -- Draw > symbol for stairs (brighter, pulse)
      local sc = C_BRIGHT3
      if math.floor(frame() / 30) % 2 == 0 then sc = C_WHITE end
      pix(s, sx + 1, sy + 1, sc)
      pix(s, sx + 2, sy + 2, sc)
      pix(s, sx + 1, sy + 3, sc)
      pix(s, sx + 3, sy + 1, sc)
      pix(s, sx + 4, sy + 2, sc)
      pix(s, sx + 3, sy + 3, sc)
    elseif exp then
      pix(s, sx + 2, sy + 2, C_DARK3)
    end
  elseif tile == T_DOOR then
    local c = clamp(C_DARK2 + brightness_mod, 0, 15)
    rectf(s, sx, sy, TILE, TILE, c)
    -- Door frame: draw bracket-like shape
    if vis then
      pix(s, sx, sy, C_MID3)
      pix(s, sx, sy + TILE - 1, C_MID3)
      pix(s, sx + TILE - 1, sy, C_MID3)
      pix(s, sx + TILE - 1, sy + TILE - 1, C_MID3)
      pix(s, sx + 2, sy + 2, C_MID2)
      pix(s, sx + 3, sy + 2, C_MID2)
    else
      pix(s, sx + 2, sy + 2, clamp(c + 1, 0, 15))
    end
  end
end

local function draw_entity_glyph(s, sx, sy, glyph, color)
  text(s, glyph, sx + 1, sy, color, 0)
end

local function draw_hp_bar_mini(s, sx, sy, hp, max_hp, c)
  local bw = TILE - 2
  local filled = math.floor((hp / max_hp) * bw)
  rectf(s, sx + 1, sy + TILE - 1, bw, 1, C_DARK1)
  if filled > 0 then
    rectf(s, sx + 1, sy + TILE - 1, filled, 1, c)
  end
end

function game_draw()
  local s = screen()
  cls(s, 0)

  -- Camera follows player
  cam_x = player.x * TILE - 80 + TILE / 2
  cam_y = player.y * TILE - 54 + TILE / 2  -- slightly above center for HUD

  -- Apply camera shake
  local sx_off, sy_off = 0, 0
  if shake_timer > 0 then
    sx_off = math.random(-2, 2)
    sy_off = math.random(-2, 2)
  end

  -- Calculate visible tile range
  local start_tx = math.floor(cam_x / TILE) - 1
  local start_ty = math.floor(cam_y / TILE) - 1
  local end_tx = start_tx + VIEW_W + 2
  local end_ty = start_ty + VIEW_H + 2

  -- Draw tiles
  for ty = start_ty, end_ty do
    for tx = start_tx, end_tx do
      local sx = tx * TILE - cam_x + sx_off
      local sy = ty * TILE - cam_y + sy_off
      if sx > -TILE and sx < 160 and sy > -TILE and sy < 108 then
        draw_tile(s, tx, ty, sx, sy)
      end
    end
  end

  -- Draw items (only visible ones)
  for _, it in ipairs(items) do
    if is_visible(it.x, it.y) then
      local sx = it.x * TILE - cam_x + sx_off
      local sy = it.y * TILE - cam_y + sy_off
      if sx > -TILE and sx < 160 and sy > -TILE and sy < 108 then
        draw_entity_glyph(s, sx, sy, it.glyph, it.color)
      end
    end
  end

  -- Draw enemies (only visible ones)
  for _, e in ipairs(enemies) do
    if is_visible(e.x, e.y) then
      local sx = e.x * TILE - cam_x + sx_off
      local sy = e.y * TILE - cam_y + sy_off
      if sx > -TILE and sx < 160 and sy > -TILE and sy < 108 then
        local c = e.color
        if e.hit_flash > 0 then c = C_WHITE end
        draw_entity_glyph(s, sx, sy, e.glyph, c)
        if e.hp < e.max_hp then
          draw_hp_bar_mini(s, sx, sy, e.hp, e.max_hp, C_LGRAY)
        end
      end
    end
  end

  -- Draw player
  local px = player.x * TILE - cam_x + sx_off
  local py = player.y * TILE - cam_y + sy_off
  local pc = C_WHITE
  if player.hit_flash > 0 then
    pc = (player.hit_flash % 2 == 0) and C_BRIGHT2 or C_WHITE
  end
  draw_entity_glyph(s, px, py, "@", pc)

  -- Draw particles
  for _, p in ipairs(particles) do
    local sx = p.x - cam_x + sx_off
    local sy = p.y - cam_y + sy_off
    if sx >= 0 and sx < 160 and sy >= 0 and sy < 108 then
      local c = p.c
      if p.life < 5 then c = math.max(1, c - 2) end
      pix(s, math.floor(sx), math.floor(sy), c)
    end
  end

  -- Draw floating text
  for _, f in ipairs(floats) do
    local sx = f.x - cam_x + sx_off + 2
    local sy = f.y - cam_y + sy_off
    if sx >= 0 and sx < 160 and sy >= 0 and sy < 108 then
      local c = f.c
      if f.life < 10 then c = math.max(1, c - (10 - f.life)) end
      text(s, f.txt, math.floor(sx), math.floor(sy), c, 0)
    end
  end

  -- Flash effect
  if flash_timer > 0 then
    -- Draw scattered bright pixels
    for i = 1, flash_timer * 5 do
      pix(s, math.random(0, 159), math.random(0, 107), flash_color)
    end
  end

  -- ===== HUD =====
  -- Dark bar at bottom
  rectf(s, 0, 108, 160, 12, C_BLACK)
  line(s, 0, 108, 159, 108, C_DARK2)

  -- HP bar
  text(s, "HP", 1, 110, C_GRAY, 0)
  local hp_bar_w = 30
  local hp_filled = math.floor((player.hp / player.max_hp) * hp_bar_w)
  rectf(s, 12, 110, hp_bar_w, 5, C_DARK2)
  if hp_filled > 0 then
    local hp_c = C_LGRAY
    if player.hp <= player.max_hp * 0.3 then hp_c = C_MID3 end
    if player.hp <= player.max_hp * 0.15 then hp_c = C_MID1 end
    rectf(s, 12, 110, hp_filled, 5, hp_c)
  end
  text(s, player.hp .. "/" .. player.max_hp, 13, 111, C_WHITE, 0)

  -- Stats
  text(s, "A" .. player.atk, 46, 110, C_LIGHT1, 0)
  text(s, "D" .. player.def, 60, 110, C_LIGHT2, 0)
  text(s, "Lv" .. player.level, 74, 110, C_BRIGHT3, 0)

  -- Floor
  text(s, "F" .. floor_num, 145, 110, C_LIGHT3, 0)

  -- XP bar (tiny)
  local xp_w = 20
  local xp_filled = math.floor((player.xp / player.next_xp) * xp_w)
  rectf(s, 92, 113, xp_w, 2, C_DARK1)
  if xp_filled > 0 then
    rectf(s, 92, 113, xp_filled, 2, C_MID3)
  end
  text(s, "XP", 92, 110, C_MID2, 0)

  -- Messages (above HUD)
  for i, m in ipairs(msg_log) do
    if i <= 3 then
      local alpha = m.color
      if m.timer < 30 then
        alpha = math.max(1, alpha - math.floor((30 - m.timer) / 10))
      end
      local my = 108 - i * 8
      -- Shadow
      text(s, m.text, 2, my + 1, C_BLACK, 0)
      text(s, m.text, 1, my, alpha, 0)
    end
  end

  -- Stair indicator
  if map_get(player.x, player.y) == T_STAIR then
    text(s, "A:DESCEND", 80, 98, C_BRIGHT3, ALIGN_HCENTER)
  end

  -- Game over overlay
  if game_over then
    rectf(s, 30, 40, 100, 30, C_BLACK)
    rect(s, 30, 40, 100, 30, C_DARK3)
    text(s, "YOU DIED", 80, 46, C_WHITE, ALIGN_HCENTER)
    text(s, "Floor " .. floor_num .. "  Kills " .. kills_total, 80, 56, C_GRAY, ALIGN_HCENTER)
    if math.floor(frame() / 20) % 2 == 0 then
      text(s, "PRESS START", 80, 64, C_LGRAY, ALIGN_HCENTER)
    end
  end

  -- Pause overlay
  if paused then
    rectf(s, 40, 35, 80, 50, C_BLACK)
    rect(s, 40, 35, 80, 50, C_MID2)
    text(s, "PAUSED", 80, 40, C_WHITE, ALIGN_HCENTER)
    text(s, "HP: " .. player.hp .. "/" .. player.max_hp, 80, 52, C_LGRAY, ALIGN_HCENTER)
    text(s, "A:" .. player.atk .. " D:" .. player.def, 80, 60, C_LGRAY, ALIGN_HCENTER)
    text(s, "F:" .. floor_num .. " Lv:" .. player.level, 80, 68, C_LGRAY, ALIGN_HCENTER)
    text(s, "Kills: " .. kills_total, 80, 76, C_LGRAY, ALIGN_HCENTER)
  end

  -- Minimap overlay
  if show_map then
    draw_minimap(s)
  end
end

function draw_minimap(s)
  local mx_off = 110
  local my_off = 2
  local scale = 1  -- 1 pixel per tile

  -- Background
  rectf(s, mx_off - 1, my_off - 1, MAP_W + 2, MAP_H + 2, C_BLACK)
  rect(s, mx_off - 1, my_off - 1, MAP_W + 2, MAP_H + 2, C_DARK2)

  for y = 0, MAP_H - 1 do
    for x = 0, MAP_W - 1 do
      local px = mx_off + x
      local py = my_off + y
      if is_explored(x, y) then
        local t = map_get(x, y)
        if t == T_WALL then
          pix(s, px, py, C_DARK2)
        elseif t == T_FLOOR or t == T_DOOR then
          if is_visible(x, y) then
            pix(s, px, py, C_MID1)
          else
            pix(s, px, py, C_DARK1)
          end
        elseif t == T_STAIR then
          pix(s, px, py, C_BRIGHT3)
        end
      end
    end
  end

  -- Player on minimap
  pix(s, mx_off + player.x, my_off + player.y, C_WHITE)

  -- Visible enemies on minimap
  for _, e in ipairs(enemies) do
    if is_visible(e.x, e.y) then
      pix(s, mx_off + e.x, my_off + e.y, C_BRIGHT1)
    end
  end
end

----------------------------------------------
-- DEATH SCENE
----------------------------------------------
local death_timer = 0

function death_init()
  death_timer = 0
  -- Somber tone
  tone(0, 120, 60, 0.8)
end

function death_update()
  death_timer = death_timer + 1

  if death_timer > 60 and (btnp("start") or touch_start()) then
    note(0, "C4", 0.1)
    go("title")
  end
end

function death_draw()
  local s = screen()
  cls(s, 0)

  -- Skull/death decoration using pixels
  local cx = 80
  local cy = 20

  -- Simple skull shape
  if death_timer > 5 then
    rectf(s, cx - 6, cy - 4, 12, 10, C_LGRAY)
    rectf(s, cx - 4, cy + 6, 8, 3, C_LGRAY)
    -- Eye sockets
    rectf(s, cx - 4, cy - 1, 3, 3, C_BLACK)
    rectf(s, cx + 1, cy - 1, 3, 3, C_BLACK)
    -- Nose
    pix(s, cx - 1, cy + 3, C_DARK3)
    pix(s, cx, cy + 3, C_DARK3)
    -- Teeth
    for i = 0, 3 do
      pix(s, cx - 3 + i * 2, cy + 7, C_DARK3)
    end
  end

  -- Title
  if death_timer > 15 then
    text(s, "YOU HAVE PERISHED", 80, 38, C_WHITE, ALIGN_HCENTER)
    line(s, 30, 44, 130, 44, C_DARK3)
  end

  -- Stats
  if death_timer > 25 then
    local sy = 50
    text(s, "Reached Floor " .. (death_stats.floor or 1), 80, sy, C_LIGHT2, ALIGN_HCENTER)
    text(s, "Level " .. (death_stats.level or 1), 80, sy + 10, C_LIGHT1, ALIGN_HCENTER)
    text(s, "Enemies Slain: " .. (death_stats.kills or 0), 80, sy + 20, C_LGRAY, ALIGN_HCENTER)
    text(s, "Items Found: " .. (death_stats.items or 0), 80, sy + 30, C_LGRAY, ALIGN_HCENTER)
    text(s, "Turns Survived: " .. (death_stats.turns or 0), 80, sy + 40, C_LGRAY, ALIGN_HCENTER)
  end

  -- Epitaph
  if death_timer > 40 then
    local epitaphs = {
      "The darkness claims another...",
      "Lost in the depths forever...",
      "Duskhold endures. You did not.",
      "A hero forgotten in the deep.",
    }
    local epitaph = epitaphs[((death_stats.floor or 1) % #epitaphs) + 1]
    text(s, epitaph, 80, 100, C_MID2, ALIGN_HCENTER)
  end

  -- Prompt
  if death_timer > 60 and math.floor(death_timer / 20) % 2 == 0 then
    text(s, "PRESS START", 80, 112, C_GRAY, ALIGN_HCENTER)
  end
end

----------------------------------------------
-- ENGINE HOOKS
----------------------------------------------
function _init()
  mode(4)
  math.randomseed(os.clock() * 10000 + 42)
end

function _start()
  go("title")
end
