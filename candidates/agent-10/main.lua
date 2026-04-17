-- THE DARK ROOM (Procedural)
-- A procedurally generated mystery adventure
-- Every playthrough is different. Seed-based for shareability.
-- 160x120 | 2-bit (4 grayscale) | mode(2)
-- D-Pad: Navigate/Select | A: Interact/Confirm | B: Inventory/Back
-- START: New game | SELECT: Pause

----------------------------------------------------------------
-- CONSTANTS
----------------------------------------------------------------
local W = 160
local H = 120
local S -- screen surface

-- 2-bit palette (0=black, 1=dark, 2=light, 3=white)
local C_BLK = 0
local C_DRK = 1
local C_LIT = 2
local C_WHT = 3

-- Game timing
local ATTRACT_IDLE = 300 -- frames before demo mode
local TEXT_SPEED = 2     -- frames per character for typewriter
local TRANS_FRAMES = 20  -- room transition frames

----------------------------------------------------------------
-- SEEDED PRNG (xorshift32)
----------------------------------------------------------------
local seed_val = 0
local rng_state = 1

local function rng_seed(s)
  seed_val = s
  rng_state = (s == 0) and 1 or s
end

local function rng()
  local x = rng_state
  x = x ~ (x << 13)
  x = x ~ (x >> 17)
  x = x ~ (x << 5)
  -- keep in 32-bit integer range
  x = x & 0xFFFFFFFF
  if x == 0 then x = 1 end
  rng_state = x
  return x
end

local function rng_int(lo, hi)
  return lo + (rng() % (hi - lo + 1))
end

local function rng_pick(t)
  return t[rng_int(1, #t)]
end

local function rng_shuffle(t)
  for i = #t, 2, -1 do
    local j = rng_int(1, i)
    t[i], t[j] = t[j], t[i]
  end
end

----------------------------------------------------------------
-- SAFE AUDIO
----------------------------------------------------------------
local function sfx_note(ch, n, dur)
  if note then note(ch, n, dur) end
end

local function sfx_noise(ch, dur)
  if noise then noise(ch, dur) end
end

----------------------------------------------------------------
-- UTILITY
----------------------------------------------------------------
local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

----------------------------------------------------------------
-- DATA POOLS (for procedural content)
----------------------------------------------------------------
local ROOM_NAMES = {
  "CELLAR", "STUDY", "HALLWAY", "ATTIC",
  "KITCHEN", "BEDROOM", "LIBRARY", "BATHROOM",
  "CLOSET", "PANTRY", "VAULT", "CHAPEL",
  "BOILER RM", "NURSERY", "OFFICE", "GALLERY",
  "WINE CELLAR", "GARAGE", "WORKSHOP", "PARLOR"
}

local ITEM_NAMES = {
  "RUSTY KEY", "BRASS KEY", "IRON KEY", "GOLD KEY",
  "SILVER KEY", "SKELETON KEY", "OLD KEY", "SMALL KEY",
  "BENT NAIL", "WIRE", "CANDLE", "MATCHES",
  "CROWBAR", "HAMMER", "SCREWDRIVER", "PLIERS",
  "NOTE", "LETTER", "DIARY PAGE", "PHOTOGRAPH",
  "BATTERY", "FLASHLIGHT", "FUSE", "LEVER",
  "GEM", "COIN", "RING", "LOCKET"
}

local LOCK_NAMES = {
  "LOCKED DOOR", "SEALED HATCH", "IRON GATE",
  "PADLOCKED CHEST", "BARRED WINDOW", "BOLTED PANEL",
  "STUCK DRAWER", "CHAINED EXIT", "HEAVY DOOR"
}

local EXAMINE_FLAVOR = {
  "DUST COATS EVERYTHING.",
  "A FAINT DRAFT BLOWS.",
  "COBWEBS IN THE CORNERS.",
  "SCRATCHES ON THE WALL.",
  "SOMETHING MOVED...",
  "THE AIR FEELS HEAVY.",
  "YOU HEAR DRIPPING.",
  "OLD STAINS ON FLOOR.",
  "FADED WALLPAPER PEELS.",
  "A CLOCK TICKS SOMEWHERE.",
  "MOLD CREEPS UP THE WALLS.",
  "A FAINT ODOR LINGERS.",
  "THE FLOOR CREAKS.",
  "SHADOWS SEEM TO SHIFT.",
  "SILENCE PRESSES IN."
}

local CLUE_FRAGMENTS = {
  "I CANT STAY HERE...",
  "THE DOOR WONT OPEN.",
  "THEY LOCKED ME IN.",
  "FIND THE WAY OUT.",
  "DONT TRUST THE DARK.",
  "THE WALLS ARE CLOSING.",
  "I LEFT A KEY BEHIND.",
  "CHECK THE OLD ROOM.",
  "THE ANSWER IS HIDDEN.",
  "SOMEONE WAS HERE BEFORE.",
  "LISTEN TO THE SILENCE.",
  "TIME IS RUNNING OUT.",
  "THE EXIT IS CLOSE.",
  "REMEMBER THE ORDER.",
  "LOOK MORE CAREFULLY."
}

-- Room visual templates (simple patterns for 2-bit)
local ROOM_STYLES = {
  "bare", "furnished", "ruined", "ornate",
  "cramped", "flooded", "dusty", "dark"
}

----------------------------------------------------------------
-- GENERATION: BUILD A COMPLETE MYSTERY
----------------------------------------------------------------
local rooms = {}
local items = {}
local locks = {}
local puzzle_chain = {}
local exit_room = 0
local num_rooms = 0
local clues = {}

local function generate_world(s)
  rng_seed(s)
  rooms = {}
  items = {}
  locks = {}
  puzzle_chain = {}
  clues = {}

  -- Decide room count (6-9)
  num_rooms = rng_int(6, 9)

  -- Shuffle and pick room names
  local name_pool = {}
  for i = 1, #ROOM_NAMES do name_pool[i] = ROOM_NAMES[i] end
  rng_shuffle(name_pool)

  -- Create rooms
  for i = 1, num_rooms do
    rooms[i] = {
      id = i,
      name = name_pool[i],
      style = rng_pick(ROOM_STYLES),
      flavor = rng_pick(EXAMINE_FLAVOR),
      exits = {},       -- {dir=direction, to=room_id, lock_id=nil or lock}
      items_here = {},   -- item indices
      examined = false,
      visited = false,
      clue = nil
    }
  end

  -- Build a spanning tree for connectivity (ensures all rooms reachable)
  local dirs = {"NORTH", "SOUTH", "EAST", "WEST"}
  local opp = {NORTH="SOUTH", SOUTH="NORTH", EAST="WEST", WEST="EAST"}
  local connected = {true}
  for i = 2, num_rooms do connected[i] = false end

  local conn_list = {1}
  for i = 2, num_rooms do
    -- Pick a connected room and link to room i
    local from = conn_list[rng_int(1, #conn_list)]
    -- Pick available direction from 'from'
    local avail_dirs = {}
    local used = {}
    for _, ex in ipairs(rooms[from].exits) do used[ex.dir] = true end
    for _, d in ipairs(dirs) do
      if not used[d] then avail_dirs[#avail_dirs+1] = d end
    end
    if #avail_dirs == 0 then
      -- fallback: just pick any dir (override)
      avail_dirs = {rng_pick(dirs)}
    end
    local dir = rng_pick(avail_dirs)

    -- Create bidirectional exit
    rooms[from].exits[#rooms[from].exits+1] = {dir=dir, to=i, lock_id=nil}
    rooms[i].exits[#rooms[i].exits+1] = {dir=opp[dir], to=from, lock_id=nil}

    connected[i] = true
    conn_list[#conn_list+1] = i
  end

  -- Add a few extra connections for interesting topology
  local extra = rng_int(1, 3)
  for _ = 1, extra do
    local a = rng_int(1, num_rooms)
    local b = rng_int(1, num_rooms)
    if a ~= b then
      -- Check not already connected directly
      local already = false
      for _, ex in ipairs(rooms[a].exits) do
        if ex.to == b then already = true; break end
      end
      if not already and #rooms[a].exits < 4 and #rooms[b].exits < 4 then
        local dir = rng_pick(dirs)
        local avail = true
        for _, ex in ipairs(rooms[a].exits) do
          if ex.dir == dir then avail = false; break end
        end
        if avail then
          rooms[a].exits[#rooms[a].exits+1] = {dir=dir, to=b, lock_id=nil}
          rooms[b].exits[#rooms[b].exits+1] = {dir=opp[dir], to=a, lock_id=nil}
        end
      end
    end
  end

  -- Determine exit room (furthest from room 1 by BFS)
  local dist = {}
  for i = 1, num_rooms do dist[i] = -1 end
  dist[1] = 0
  local queue = {1}
  local qi = 1
  while qi <= #queue do
    local cur = queue[qi]; qi = qi + 1
    for _, ex in ipairs(rooms[cur].exits) do
      if dist[ex.to] == -1 then
        dist[ex.to] = dist[cur] + 1
        queue[#queue+1] = ex.to
      end
    end
  end
  exit_room = 1
  local max_dist = 0
  for i = 1, num_rooms do
    if dist[i] > max_dist then
      max_dist = dist[i]
      exit_room = i
    end
  end

  -- Generate puzzle chain: locks on the path to exit
  -- Find shortest path from 1 to exit_room
  local prev = {}
  for i = 1, num_rooms do prev[i] = -1 end
  prev[1] = 0
  queue = {1}; qi = 1
  while qi <= #queue do
    local cur = queue[qi]; qi = qi + 1
    if cur == exit_room then break end
    for _, ex in ipairs(rooms[cur].exits) do
      if prev[ex.to] == -1 then
        prev[ex.to] = cur
        queue[#queue+1] = ex.to
      end
    end
  end

  -- Build path
  local path = {}
  local cur = exit_room
  while cur ~= 0 do
    path[#path+1] = cur
    cur = prev[cur]
  end
  -- Reverse path
  for i = 1, math.floor(#path/2) do
    path[i], path[#path+1-i] = path[#path+1-i], path[i]
  end

  -- Place 2-4 locks along the path
  local lock_name_pool = {}
  for i = 1, #LOCK_NAMES do lock_name_pool[i] = LOCK_NAMES[i] end
  rng_shuffle(lock_name_pool)

  local item_name_pool = {}
  for i = 1, #ITEM_NAMES do item_name_pool[i] = ITEM_NAMES[i] end
  rng_shuffle(item_name_pool)
  local item_idx = 0

  local num_locks = clamp(rng_int(2, 4), 2, math.max(2, #path - 2))

  -- Pick edges along path to lock
  local lockable_edges = {}
  for i = 1, #path - 1 do
    lockable_edges[#lockable_edges+1] = {from=path[i], to=path[i+1], path_pos=i}
  end
  rng_shuffle(lockable_edges)

  for li = 1, math.min(num_locks, #lockable_edges) do
    local edge = lockable_edges[li]
    item_idx = item_idx + 1
    local key_name = item_name_pool[item_idx] or ("KEY #"..item_idx)

    -- Create lock
    local lock = {
      id = li,
      name = lock_name_pool[li] or ("LOCK #"..li),
      key_item = item_idx,
      from_room = edge.from,
      to_room = edge.to,
      unlocked = false
    }
    locks[#locks+1] = lock

    -- Apply lock to the exit
    for _, ex in ipairs(rooms[edge.from].exits) do
      if ex.to == edge.to then ex.lock_id = li; break end
    end
    for _, ex in ipairs(rooms[edge.to].exits) do
      if ex.to == edge.from then ex.lock_id = li; break end
    end

    -- Create key item, place in a reachable room BEFORE the lock
    -- (rooms accessible from room 1 without crossing this lock)
    local reachable = {}
    local visited_gen = {}
    for i = 1, num_rooms do visited_gen[i] = false end
    local rq = {1}; visited_gen[1] = true; local rqi = 1
    while rqi <= #rq do
      local r = rq[rqi]; rqi = rqi + 1
      reachable[#reachable+1] = r
      for _, ex in ipairs(rooms[r].exits) do
        if not visited_gen[ex.to] and (not ex.lock_id or locks[ex.lock_id] and locks[ex.lock_id].unlocked) then
          -- Check if this edge is blocked by any existing lock
          local blocked = false
          if ex.lock_id then
            for _, lk in ipairs(locks) do
              if lk.id == ex.lock_id and not lk.unlocked then
                blocked = true; break
              end
            end
          end
          if not blocked then
            visited_gen[ex.to] = true
            rq[#rq+1] = ex.to
          end
        end
      end
    end

    -- Pick a room from reachable (not the lock room itself)
    local place_room = reachable[rng_int(1, #reachable)]
    if #reachable > 1 then
      -- Try to avoid placing in room 1 if possible
      for _ = 1, 5 do
        place_room = reachable[rng_int(1, #reachable)]
        if place_room ~= edge.from then break end
      end
    end

    -- Create item
    items[item_idx] = {
      id = item_idx,
      name = key_name,
      room = place_room,
      collected = false,
      is_key = true,
      unlocks = li,
      desc = "USED TO OPEN "..lock.name
    }
    rooms[place_room].items_here[#rooms[place_room].items_here+1] = item_idx
  end

  -- Place extra flavor items (notes, clues)
  for _ = 1, rng_int(2, 4) do
    item_idx = item_idx + 1
    local r = rng_int(1, num_rooms)
    local fname = item_name_pool[item_idx] or ("ITEM #"..item_idx)
    local clue_text = rng_pick(CLUE_FRAGMENTS)
    items[item_idx] = {
      id = item_idx,
      name = fname,
      room = r,
      collected = false,
      is_key = false,
      unlocks = nil,
      desc = clue_text
    }
    rooms[r].items_here[#rooms[r].items_here+1] = item_idx
  end

  -- Place clues in some rooms
  for i = 1, num_rooms do
    if rng_int(1, 3) == 1 then
      rooms[i].clue = rng_pick(CLUE_FRAGMENTS)
    end
  end

  -- Place final exit item in exit room
  item_idx = item_idx + 1
  items[item_idx] = {
    id = item_idx,
    name = "EXIT DOOR",
    room = exit_room,
    collected = false,
    is_key = false,
    unlocks = nil,
    desc = "THE WAY OUT! USE TO ESCAPE.",
    is_exit = true
  }
  rooms[exit_room].items_here[#rooms[exit_room].items_here+1] = item_idx
end

----------------------------------------------------------------
-- GAME STATE
----------------------------------------------------------------
local scene = "title"     -- title, play, inventory, examine, transition, win, gameover, paused, demo
local cur_room = 1
local inventory = {}       -- list of item ids
local msg_text = ""
local msg_timer = 0
local msg_queue = {}
local type_pos = 0
local type_timer = 0

-- UI state
local menu_sel = 0         -- current menu selection
local menu_items = {}       -- current menu options
local menu_callback = nil   -- function to call on select
local idle_timer = 0
local trans_timer = 0
local trans_target = 0
local flash_timer = 0
local tension = 0          -- ambient tension level (affects visuals/audio)
local steps = 0
local title_sel = 0
local title_seed_str = ""
local title_editing_seed = false
local demo_active = false
local demo_timer = 0
local demo_action_timer = 0
local pause_active = false
local examine_text = ""
local examine_item = nil
local win_timer = 0

-- Ambient sound
local amb_timer = 0
local amb_interval = 60

----------------------------------------------------------------
-- MESSAGES
----------------------------------------------------------------
local function show_msg(txt)
  msg_text = txt
  msg_timer = 90
  type_pos = 0
  type_timer = 0
end

local function queue_msg(txt)
  msg_queue[#msg_queue+1] = txt
end

----------------------------------------------------------------
-- ROOM DRAWING
----------------------------------------------------------------
local function draw_room_bg(room)
  -- Draw room based on style
  local st = room.style

  -- Floor
  rectf(S, 0, 0, W, H, C_BLK)

  -- Room frame
  local mx, my = 10, 16
  local mw, mh = W - 20, H - 40

  -- Perspective floor/ceiling
  -- Back wall
  rectf(S, mx, my, mw, mh, C_DRK)

  -- Floor gradient
  for y = my + mh - 10, my + mh do
    local shade = C_BLK
    if (y + frame()) % 4 < 2 then shade = C_DRK end
    line(S, mx, y, mx + mw - 1, y, shade)
  end

  -- Style-specific details
  if st == "bare" then
    -- Simple empty room
    rect(S, mx + 1, my + 1, mw - 2, mh - 2, C_LIT)
  elseif st == "furnished" then
    -- Table/chair shapes
    rectf(S, mx + 20, my + mh - 20, 30, 12, C_LIT)
    rectf(S, mx + 22, my + mh - 8, 2, 8, C_DRK)
    rectf(S, mx + 46, my + mh - 8, 2, 8, C_DRK)
    -- Chair
    rectf(S, mx + 60, my + mh - 16, 12, 8, C_LIT)
    rectf(S, mx + 60, my + mh - 24, 2, 8, C_DRK)
  elseif st == "ruined" then
    -- Cracks and debris
    line(S, mx + 10, my + 5, mx + 30, my + 20, C_LIT)
    line(S, mx + 30, my + 20, mx + 25, my + 35, C_LIT)
    -- Debris on floor
    for i = 0, 5 do
      local dx = mx + 15 + ((rng_state + i * 17) % (mw - 30))
      local dy = my + mh - 15 + ((rng_state + i * 7) % 10)
      rectf(S, dx, dy, 3, 2, C_LIT)
    end
  elseif st == "ornate" then
    -- Frame on wall
    rect(S, mx + 25, my + 8, 30, 20, C_WHT)
    rect(S, mx + 27, my + 10, 26, 16, C_LIT)
    -- Columns
    rectf(S, mx + 3, my + 5, 4, mh - 10, C_LIT)
    rectf(S, mx + mw - 7, my + 5, 4, mh - 10, C_LIT)
  elseif st == "cramped" then
    -- Boxes stacked
    rectf(S, mx + 5, my + mh - 25, 18, 18, C_LIT)
    rectf(S, mx + 8, my + mh - 35, 12, 10, C_DRK)
    rectf(S, mx + mw - 25, my + mh - 20, 16, 14, C_LIT)
  elseif st == "flooded" then
    -- Water lines on floor
    for y = my + mh - 8, my + mh do
      local off = math.floor(frame() / 8 + y) % 6
      if off < 3 then
        line(S, mx + 2, y, mx + mw - 2, y, C_LIT)
      end
    end
  elseif st == "dusty" then
    -- Dust particles
    for i = 0, 8 do
      local dx = (frame() / 3 + i * 19) % (mw - 4) + mx + 2
      local dy = (frame() / 5 + i * 13) % (mh - 4) + my + 2
      pset(S, math.floor(dx), math.floor(dy), C_LIT)
    end
  elseif st == "dark" then
    -- Extra dark, barely visible walls
    rect(S, mx + 1, my + 1, mw - 2, mh - 2, C_DRK)
    -- Faint light source
    local lx = mx + mw / 2
    local ly = my + mh / 2
    for i = 0, 3 do
      circ(S, lx, ly, 4 + i * 3, i < 2 and C_DRK or C_BLK)
    end
  end

  -- Draw exits as doorways
  for _, ex in ipairs(room.exits) do
    local locked = false
    if ex.lock_id then
      for _, lk in ipairs(locks) do
        if lk.id == ex.lock_id and not lk.unlocked then locked = true; break end
      end
    end
    local dc = locked and C_DRK or C_LIT
    if ex.dir == "NORTH" then
      rectf(S, mx + mw/2 - 8, my, 16, 6, dc)
      if locked then
        -- Lock symbol
        rectf(S, mx + mw/2 - 2, my + 1, 4, 3, C_WHT)
      end
    elseif ex.dir == "SOUTH" then
      rectf(S, mx + mw/2 - 8, my + mh - 6, 16, 6, dc)
      if locked then
        rectf(S, mx + mw/2 - 2, my + mh - 5, 4, 3, C_WHT)
      end
    elseif ex.dir == "EAST" then
      rectf(S, mx + mw - 6, my + mh/2 - 8, 6, 16, dc)
      if locked then
        rectf(S, mx + mw - 5, my + mh/2 - 2, 3, 4, C_WHT)
      end
    elseif ex.dir == "WEST" then
      rectf(S, mx, my + mh/2 - 8, 6, 16, dc)
      if locked then
        rectf(S, mx + 1, my + mh/2 - 2, 3, 4, C_WHT)
      end
    end
  end

  -- Draw items on ground
  local ix = mx + mw/2 - 15
  for _, item_id in ipairs(room.items_here) do
    local it = items[item_id]
    if it and not it.collected then
      -- Small item icon
      if it.is_exit then
        -- Exit door special
        rectf(S, ix, my + mh/2 - 10, 10, 20, C_WHT)
        rectf(S, ix + 2, my + mh/2 - 8, 6, 16, C_LIT)
        -- Doorknob
        pset(S, ix + 7, my + mh/2, C_WHT)
      elseif it.is_key then
        -- Key icon
        rectf(S, ix, my + mh - 18, 6, 3, C_WHT)
        rectf(S, ix + 6, my + mh - 17, 4, 1, C_WHT)
      else
        -- Generic item (small square)
        rectf(S, ix, my + mh - 18, 5, 5, C_LIT)
        rect(S, ix, my + mh - 18, 5, 5, C_WHT)
      end
      ix = ix + 14
    end
  end
end

----------------------------------------------------------------
-- HUD
----------------------------------------------------------------
local function draw_hud(room)
  -- Room name at top
  rectf(S, 0, 0, W, 12, C_BLK)
  text(S, room.name, W/2, 2, C_WHT, ALIGN_CENTER)

  -- Bottom bar
  rectf(S, 0, H - 18, W, 18, C_BLK)
  line(S, 0, H - 18, W, H - 18, C_DRK)

  -- Exit indicators
  local arrow_y = H - 12
  for _, ex in ipairs(room.exits) do
    local locked = false
    if ex.lock_id then
      for _, lk in ipairs(locks) do
        if lk.id == ex.lock_id and not lk.unlocked then locked = true; break end
      end
    end
    local ac = locked and C_DRK or C_LIT
    if ex.dir == "NORTH" then text(S, "^N", W/2, H - 16, ac, ALIGN_CENTER)
    elseif ex.dir == "SOUTH" then text(S, "vS", W/2, H - 9, ac, ALIGN_CENTER)
    elseif ex.dir == "EAST" then text(S, "E>", W - 12, arrow_y, ac)
    elseif ex.dir == "WEST" then text(S, "<W", 2, arrow_y, ac)
    end
  end

  -- Inventory count
  text(S, "B:INV("..#inventory..")", 2, H - 16, C_DRK)

  -- Seed display
  text(S, "S:"..seed_val, W - 2, 2, C_DRK, ALIGN_RIGHT)
end

----------------------------------------------------------------
-- MESSAGE DISPLAY
----------------------------------------------------------------
local function draw_msg()
  if msg_timer > 0 then
    local shown = msg_text
    if type_pos < #msg_text then
      type_timer = type_timer + 1
      if type_timer >= TEXT_SPEED then
        type_timer = 0
        type_pos = type_pos + 1
        -- Typewriter click
        if type_pos % 3 == 0 then sfx_noise(1, 0.01) end
      end
      shown = string.sub(msg_text, 1, type_pos)
    end

    -- Message box
    local bx, by = 8, H/2 - 12
    local bw, bh = W - 16, 24
    rectf(S, bx, by, bw, bh, C_BLK)
    rect(S, bx, by, bw, bh, C_WHT)
    rect(S, bx + 1, by + 1, bw - 2, bh - 2, C_DRK)

    -- Word wrap the text
    local max_chars = 26
    local y = by + 4
    local remaining = shown
    while #remaining > 0 and y < by + bh - 4 do
      local chunk = string.sub(remaining, 1, max_chars)
      if #remaining > max_chars then
        -- Find last space in chunk
        local sp = max_chars
        for ci = max_chars, 1, -1 do
          if string.sub(remaining, ci, ci) == " " then sp = ci; break end
        end
        chunk = string.sub(remaining, 1, sp)
        remaining = string.sub(remaining, sp + 1)
      else
        remaining = ""
      end
      text(S, chunk, bx + 4, y, C_WHT)
      y = y + 8
    end
  end
end

----------------------------------------------------------------
-- MENU SYSTEM
----------------------------------------------------------------
local function draw_menu()
  if #menu_items == 0 then return end

  local bw = 80
  local bh = #menu_items * 10 + 8
  local bx = W/2 - bw/2
  local by = H/2 - bh/2

  rectf(S, bx, by, bw, bh, C_BLK)
  rect(S, bx, by, bw, bh, C_WHT)

  for i, item in ipairs(menu_items) do
    local y = by + 4 + (i-1) * 10
    local c = C_LIT
    if i - 1 == menu_sel then
      c = C_WHT
      rectf(S, bx + 2, y - 1, bw - 4, 9, C_DRK)
      text(S, ">", bx + 4, y, C_WHT)
    end
    text(S, item.label, bx + 12, y, c)
  end
end

local function set_menu(items_list, callback)
  menu_items = items_list
  menu_sel = 0
  menu_callback = callback
end

local function clear_menu()
  menu_items = {}
  menu_sel = 0
  menu_callback = nil
end

----------------------------------------------------------------
-- ROOM INTERACTION
----------------------------------------------------------------
local function get_room_actions(room)
  local actions = {}

  -- Examine room
  actions[#actions+1] = {label="EXAMINE ROOM", action="examine"}

  -- Pick up items
  for _, item_id in ipairs(room.items_here) do
    local it = items[item_id]
    if it and not it.collected then
      if it.is_exit then
        -- Check if all locks unlocked
        local all_open = true
        for _, lk in ipairs(locks) do
          if not lk.unlocked then all_open = false; break end
        end
        if all_open then
          actions[#actions+1] = {label="OPEN EXIT", action="exit", item=item_id}
        else
          actions[#actions+1] = {label="EXIT (LOCKED)", action="exit_locked"}
        end
      else
        actions[#actions+1] = {label="TAKE "..it.name, action="take", item=item_id}
      end
    end
  end

  -- Navigate exits
  for _, ex in ipairs(room.exits) do
    local locked = false
    local lock = nil
    if ex.lock_id then
      for _, lk in ipairs(locks) do
        if lk.id == ex.lock_id and not lk.unlocked then locked = true; lock = lk; break end
      end
    end
    if locked then
      actions[#actions+1] = {label="GO "..ex.dir.." [LOCKED]", action="go_locked", exit=ex, lock=lock}
    else
      actions[#actions+1] = {label="GO "..ex.dir, action="go", exit=ex}
    end
  end

  return actions
end

local function do_action(act)
  if act.action == "examine" then
    local room = rooms[cur_room]
    local txt = room.flavor
    if room.clue and not room.examined then
      txt = txt .. " " .. room.clue
    end
    room.examined = true
    show_msg(txt)
    sfx_note(0, "C3", 0.1)
  elseif act.action == "take" then
    local it = items[act.item]
    if it then
      it.collected = true
      inventory[#inventory+1] = act.item
      -- Remove from room
      local room = rooms[cur_room]
      for i, iid in ipairs(room.items_here) do
        if iid == act.item then table.remove(room.items_here, i); break end
      end
      show_msg("TOOK " .. it.name .. ".")
      sfx_note(0, "E4", 0.08)
      sfx_note(1, "G4", 0.08)
    end
  elseif act.action == "go" then
    trans_target = act.exit.to
    trans_timer = TRANS_FRAMES
    scene = "transition"
    sfx_note(0, "C2", 0.15)
    sfx_noise(1, 0.1)
    steps = steps + 1
  elseif act.action == "go_locked" then
    -- Check if player has the key
    local lock = act.lock
    local has_key = false
    local key_inv_idx = nil
    for i, inv_id in ipairs(inventory) do
      local it = items[inv_id]
      if it and it.is_key and it.unlocks == lock.id then
        has_key = true
        key_inv_idx = i
        break
      end
    end
    if has_key then
      -- Unlock!
      lock.unlocked = true
      -- Remove key from inventory
      if key_inv_idx then table.remove(inventory, key_inv_idx) end
      show_msg("UNLOCKED " .. lock.name .. "!")
      sfx_note(0, "C4", 0.1)
      sfx_note(1, "E4", 0.1)
      sfx_note(0, "G4", 0.15)
    else
      show_msg(lock.name .. ". NEED A KEY.")
      sfx_note(0, "C2", 0.2)
    end
  elseif act.action == "exit" then
    scene = "win"
    win_timer = 0
    sfx_note(0, "C4", 0.2)
    sfx_note(1, "E4", 0.2)
  elseif act.action == "exit_locked" then
    show_msg("THE EXIT IS LOCKED. EXPLORE MORE.")
    sfx_note(0, "E2", 0.15)
  end
end

----------------------------------------------------------------
-- AMBIENT SOUND
----------------------------------------------------------------
local function update_ambient()
  amb_timer = amb_timer + 1
  if amb_timer >= amb_interval then
    amb_timer = 0
    amb_interval = 45 + (rng() % 90)
    -- Creepy ambient note
    local notes_pool = {"C2", "D2", "E2", "F2", "G2", "A2", "B2"}
    local n = notes_pool[(frame() % #notes_pool) + 1]
    sfx_note(0, n, 0.3)
    if tension > 3 then
      sfx_noise(1, 0.15)
    end
  end

  -- Tension increases with steps
  tension = math.floor(steps / 5)
end

----------------------------------------------------------------
-- TITLE SCREEN
----------------------------------------------------------------
local function draw_title()
  rectf(S, 0, 0, W, H, C_BLK)

  -- Flickering title
  local flick = math.floor(frame() / 4) % 8
  local tc = flick < 6 and C_WHT or C_LIT

  text(S, "THE DARK ROOM", W/2, 20, tc, ALIGN_CENTER)
  text(S, "-------------", W/2, 28, C_DRK, ALIGN_CENTER)

  -- Subtitle
  text(S, "A PROCEDURAL MYSTERY", W/2, 40, C_LIT, ALIGN_CENTER)

  -- Seed display
  local seed_str = "SEED: " .. seed_val
  if title_editing_seed then
    seed_str = "SEED: " .. title_seed_str
    if math.floor(frame() / 15) % 2 == 0 then
      seed_str = seed_str .. "_"
    end
  end
  text(S, seed_str, W/2, 56, C_WHT, ALIGN_CENTER)

  -- Menu options
  local opts = {"START GAME", "RANDOM SEED", "ENTER SEED"}
  for i, opt in ipairs(opts) do
    local y = 72 + (i-1) * 12
    local c = C_DRK
    if i - 1 == title_sel then
      c = C_WHT
      text(S, ">", W/2 - 42, y, C_WHT)
    end
    text(S, opt, W/2, y, c, ALIGN_CENTER)
  end

  -- Controls hint
  if math.floor(frame() / 30) % 2 == 0 then
    text(S, "PRESS A TO SELECT", W/2, H - 10, C_DRK, ALIGN_CENTER)
  end

  -- Ambient flicker
  if flick == 7 then
    rectf(S, 0, 0, W, H, C_DRK)
  end
end

local function update_title()
  idle_timer = idle_timer + 1

  if title_editing_seed then
    -- Number input for seed
    if btnp("up") then
      local n = tonumber(title_seed_str) or 0
      title_seed_str = tostring(n + 1)
      sfx_noise(0, 0.02)
    elseif btnp("down") then
      local n = tonumber(title_seed_str) or 0
      if n > 0 then title_seed_str = tostring(n - 1) end
      sfx_noise(0, 0.02)
    elseif btnp("right") then
      local n = tonumber(title_seed_str) or 0
      title_seed_str = tostring(n + 10)
      sfx_noise(0, 0.02)
    elseif btnp("left") then
      local n = tonumber(title_seed_str) or 0
      if n >= 10 then title_seed_str = tostring(n - 10) end
      sfx_noise(0, 0.02)
    elseif btnp("a") then
      seed_val = tonumber(title_seed_str) or 1
      if seed_val == 0 then seed_val = 1 end
      title_editing_seed = false
      sfx_note(0, "G4", 0.08)
    elseif btnp("b") then
      title_editing_seed = false
      sfx_note(0, "C3", 0.05)
    end
    idle_timer = 0
    return
  end

  if btnp("up") then
    title_sel = (title_sel - 1) % 3
    sfx_noise(0, 0.02)
    idle_timer = 0
  elseif btnp("down") then
    title_sel = (title_sel + 1) % 3
    sfx_noise(0, 0.02)
    idle_timer = 0
  elseif btnp("a") or btnp("start") then
    idle_timer = 0
    if title_sel == 0 then
      -- Start game
      generate_world(seed_val)
      cur_room = 1
      inventory = {}
      steps = 0
      tension = 0
      rooms[1].visited = true
      scene = "play"
      show_msg("YOU WAKE IN DARKNESS...")
      sfx_note(0, "C2", 0.4)
      sfx_noise(1, 0.3)
      clear_menu()
    elseif title_sel == 1 then
      -- Random seed
      seed_val = (frame() * 31337 + 12345) & 0xFFFF
      if seed_val == 0 then seed_val = 1 end
      sfx_note(0, "E4", 0.05)
    elseif title_sel == 2 then
      -- Enter seed
      title_editing_seed = true
      title_seed_str = tostring(seed_val)
      sfx_note(0, "G3", 0.05)
    end
  end

  -- Demo mode after idle
  if idle_timer >= ATTRACT_IDLE then
    idle_timer = 0
    demo_active = true
    seed_val = (frame() * 7919 + 42) & 0xFFFF
    if seed_val == 0 then seed_val = 1 end
    generate_world(seed_val)
    cur_room = 1
    inventory = {}
    steps = 0
    tension = 0
    rooms[1].visited = true
    scene = "demo"
    demo_timer = 0
    demo_action_timer = 0
    clear_menu()
  end
end

----------------------------------------------------------------
-- PLAY STATE
----------------------------------------------------------------
local function update_play()
  update_ambient()

  -- Handle message display
  if msg_timer > 0 then
    msg_timer = msg_timer - 1
    if btnp("a") or btnp("b") then
      if type_pos < #msg_text then
        type_pos = #msg_text  -- skip to end
      else
        msg_timer = 0
      end
    end
    if msg_timer == 0 then
      -- Check message queue
      if #msg_queue > 0 then
        show_msg(msg_queue[1])
        table.remove(msg_queue, 1)
      end
    end
    return
  end

  -- Handle menu
  if #menu_items > 0 then
    if btnp("up") then
      menu_sel = (menu_sel - 1) % #menu_items
      sfx_noise(0, 0.02)
    elseif btnp("down") then
      menu_sel = (menu_sel + 1) % #menu_items
      sfx_noise(0, 0.02)
    elseif btnp("a") then
      local selected = menu_items[menu_sel + 1]
      clear_menu()
      if selected and selected.callback then
        selected.callback()
      end
      sfx_note(0, "C4", 0.05)
    elseif btnp("b") then
      clear_menu()
      sfx_note(0, "C3", 0.03)
    end
    return
  end

  -- Direction shortcuts for navigation
  local room = rooms[cur_room]
  local moved = false
  local dir_pressed = nil

  if btnp("up") then dir_pressed = "NORTH"
  elseif btnp("down") then dir_pressed = "SOUTH"
  elseif btnp("right") then dir_pressed = "EAST"
  elseif btnp("left") then dir_pressed = "WEST"
  end

  if dir_pressed then
    for _, ex in ipairs(room.exits) do
      if ex.dir == dir_pressed then
        local locked = false
        local lock = nil
        if ex.lock_id then
          for _, lk in ipairs(locks) do
            if lk.id == ex.lock_id and not lk.unlocked then locked = true; lock = lk; break end
          end
        end
        if locked then
          do_action({action="go_locked", exit=ex, lock=lock})
        else
          do_action({action="go", exit=ex})
        end
        moved = true
        break
      end
    end
    if not moved then
      show_msg("NO EXIT THAT WAY.")
      sfx_noise(0, 0.05)
    end
  end

  -- A button: open action menu
  if btnp("a") then
    local actions = get_room_actions(room)
    local mitems = {}
    for _, act in ipairs(actions) do
      local a = act -- capture
      mitems[#mitems+1] = {
        label = act.label,
        callback = function() do_action(a) end
      }
    end
    set_menu(mitems)
    sfx_noise(0, 0.02)
  end

  -- B button: open inventory
  if btnp("b") then
    if #inventory > 0 then
      scene = "inventory"
      menu_sel = 0
      sfx_note(0, "G3", 0.05)
    else
      show_msg("INVENTORY IS EMPTY.")
      sfx_noise(0, 0.03)
    end
  end

  -- SELECT: pause
  if btnp("select") then
    pause_active = true
    scene = "paused"
    sfx_noise(0, 0.03)
  end
end

local function draw_play()
  local room = rooms[cur_room]
  draw_room_bg(room)
  draw_hud(room)
  draw_menu()
  draw_msg()

  -- Tension-based screen effects
  if tension >= 2 then
    -- Subtle flicker
    if frame() % (30 - tension * 3) == 0 then
      rectf(S, 0, 0, W, H, C_DRK)
    end
  end

  -- Flash effect
  if flash_timer > 0 then
    flash_timer = flash_timer - 1
    if flash_timer % 2 == 0 then
      rectf(S, 0, 0, W, H, C_WHT)
    end
  end
end

----------------------------------------------------------------
-- INVENTORY SCREEN
----------------------------------------------------------------
local function update_inventory()
  if btnp("up") then
    menu_sel = (menu_sel - 1)
    if menu_sel < 0 then menu_sel = math.max(0, #inventory - 1) end
    sfx_noise(0, 0.02)
  elseif btnp("down") then
    menu_sel = (menu_sel + 1) % math.max(1, #inventory)
    sfx_noise(0, 0.02)
  elseif btnp("a") then
    -- Examine item
    if #inventory > 0 then
      local it = items[inventory[menu_sel + 1]]
      if it then
        examine_text = it.name .. ": " .. it.desc
        scene = "examine"
        sfx_note(0, "E3", 0.08)
      end
    end
  elseif btnp("b") then
    scene = "play"
    sfx_note(0, "C3", 0.03)
  end
end

local function draw_inventory()
  rectf(S, 0, 0, W, H, C_BLK)
  text(S, "INVENTORY", W/2, 4, C_WHT, ALIGN_CENTER)
  line(S, 10, 12, W - 10, 12, C_DRK)

  if #inventory == 0 then
    text(S, "EMPTY", W/2, H/2, C_DRK, ALIGN_CENTER)
  else
    for i, inv_id in ipairs(inventory) do
      local it = items[inv_id]
      if it then
        local y = 16 + (i-1) * 10
        local c = C_LIT
        if i - 1 == menu_sel then
          c = C_WHT
          rectf(S, 4, y - 1, W - 8, 9, C_DRK)
          text(S, ">", 6, y, C_WHT)
        end
        text(S, it.name, 14, y, c)
        if it.is_key then
          text(S, "[KEY]", W - 6, y, C_DRK, ALIGN_RIGHT)
        end
      end
    end
  end

  text(S, "A:EXAMINE  B:BACK", W/2, H - 10, C_DRK, ALIGN_CENTER)
end

----------------------------------------------------------------
-- EXAMINE SCREEN
----------------------------------------------------------------
local function update_examine()
  if btnp("a") or btnp("b") then
    scene = "inventory"
    sfx_note(0, "C3", 0.03)
  end
end

local function draw_examine()
  rectf(S, 0, 0, W, H, C_BLK)
  rect(S, 6, 6, W - 12, H - 12, C_WHT)
  rect(S, 8, 8, W - 16, H - 16, C_DRK)

  -- Word-wrap examine text
  local max_chars = 24
  local y = 16
  local remaining = examine_text
  while #remaining > 0 and y < H - 20 do
    local chunk = string.sub(remaining, 1, max_chars)
    if #remaining > max_chars then
      local sp = max_chars
      for ci = max_chars, 1, -1 do
        if string.sub(remaining, ci, ci) == " " then sp = ci; break end
      end
      chunk = string.sub(remaining, 1, sp)
      remaining = string.sub(remaining, sp + 1)
    else
      remaining = ""
    end
    text(S, chunk, 14, y, C_WHT)
    y = y + 9
  end

  if math.floor(frame() / 20) % 2 == 0 then
    text(S, "PRESS ANY BUTTON", W/2, H - 14, C_LIT, ALIGN_CENTER)
  end
end

----------------------------------------------------------------
-- TRANSITION
----------------------------------------------------------------
local function update_transition()
  trans_timer = trans_timer - 1
  if trans_timer <= 0 then
    cur_room = trans_target
    rooms[cur_room].visited = true
    scene = demo_active and "demo" or "play"
    if not rooms[cur_room].visited then
      show_msg("YOU ENTER " .. rooms[cur_room].name .. ".")
    end
  end
end

local function draw_transition()
  rectf(S, 0, 0, W, H, C_BLK)
  -- Closing/opening iris effect
  local progress = trans_timer / TRANS_FRAMES
  local r
  if progress > 0.5 then
    -- Closing
    r = math.floor((1.0 - progress) * 2 * 80)
  else
    -- Opening
    r = math.floor(progress * 2 * 80)
  end
  if r > 0 then
    circ(S, W/2, H/2, r, C_DRK)
  end

  -- Room name flash at midpoint
  if progress < 0.6 and progress > 0.4 then
    text(S, rooms[trans_target].name, W/2, H/2 - 4, C_WHT, ALIGN_CENTER)
  end
end

----------------------------------------------------------------
-- WIN SCREEN
----------------------------------------------------------------
local function update_win()
  win_timer = win_timer + 1

  -- Victory music
  if win_timer == 1 then
    sfx_note(0, "C4", 0.15)
    sfx_note(1, "E4", 0.15)
  elseif win_timer == 10 then
    sfx_note(0, "E4", 0.15)
    sfx_note(1, "G4", 0.15)
  elseif win_timer == 20 then
    sfx_note(0, "G4", 0.15)
    sfx_note(1, "C5", 0.3)
  end

  if win_timer > 60 and (btnp("a") or btnp("start")) then
    scene = "title"
    idle_timer = 0
  end
end

local function draw_win()
  rectf(S, 0, 0, W, H, C_BLK)

  -- Light expanding from center
  local r = clamp(win_timer * 2, 0, 80)
  if r > 0 then
    circ(S, W/2, H/2, r, C_DRK)
    if r > 20 then circ(S, W/2, H/2, r - 20, C_LIT) end
    if r > 40 then circ(S, W/2, H/2, r - 40, C_WHT) end
  end

  if win_timer > 15 then
    text(S, "YOU ESCAPED!", W/2, 30, C_WHT, ALIGN_CENTER)
  end
  if win_timer > 30 then
    text(S, "THE DARK ROOM", W/2, 44, C_LIT, ALIGN_CENTER)
  end
  if win_timer > 45 then
    text(S, "SEED: "..seed_val, W/2, 60, C_DRK, ALIGN_CENTER)
    text(S, "STEPS: "..steps, W/2, 72, C_DRK, ALIGN_CENTER)
    text(S, "ROOMS: "..num_rooms, W/2, 82, C_DRK, ALIGN_CENTER)
  end
  if win_timer > 60 and math.floor(frame() / 20) % 2 == 0 then
    text(S, "PRESS START", W/2, H - 14, C_LIT, ALIGN_CENTER)
  end
end

----------------------------------------------------------------
-- PAUSE
----------------------------------------------------------------
local function update_paused()
  if btnp("select") or btnp("start") or btnp("a") then
    scene = "play"
    pause_active = false
    sfx_noise(0, 0.03)
  end
end

local function draw_paused()
  -- Draw play state underneath (dimmed)
  draw_play()

  -- Overlay
  rectf(S, 30, 40, 100, 40, C_BLK)
  rect(S, 30, 40, 100, 40, C_WHT)
  text(S, "PAUSED", W/2, 48, C_WHT, ALIGN_CENTER)
  text(S, "SEED: "..seed_val, W/2, 60, C_LIT, ALIGN_CENTER)
  if math.floor(frame() / 20) % 2 == 0 then
    text(S, "PRESS START", W/2, 72, C_DRK, ALIGN_CENTER)
  end
end

----------------------------------------------------------------
-- DEMO / ATTRACT MODE
----------------------------------------------------------------
local function update_demo()
  demo_timer = demo_timer + 1
  demo_action_timer = demo_action_timer + 1

  update_ambient()

  -- Auto-play: perform actions periodically
  if demo_action_timer >= 45 then
    demo_action_timer = 0

    local room = rooms[cur_room]

    -- Try to move to an unvisited room, or random exit
    local unvisited_exits = {}
    local all_exits = {}
    for _, ex in ipairs(room.exits) do
      local locked = false
      if ex.lock_id then
        for _, lk in ipairs(locks) do
          if lk.id == ex.lock_id and not lk.unlocked then locked = true; break end
        end
      end
      if not locked then
        all_exits[#all_exits+1] = ex
        if not rooms[ex.to].visited then
          unvisited_exits[#unvisited_exits+1] = ex
        end
      end
    end

    -- Pick up items first
    local picked = false
    for _, item_id in ipairs(room.items_here) do
      local it = items[item_id]
      if it and not it.collected and not it.is_exit then
        do_action({action="take", item=item_id})
        picked = true
        break
      end
    end

    if not picked then
      -- Try to unlock a locked exit
      local unlocked_something = false
      for _, ex in ipairs(room.exits) do
        if ex.lock_id then
          for _, lk in ipairs(locks) do
            if lk.id == ex.lock_id and not lk.unlocked then
              -- Check if we have the key
              for i, inv_id in ipairs(inventory) do
                local it = items[inv_id]
                if it and it.is_key and it.unlocks == lk.id then
                  do_action({action="go_locked", exit=ex, lock=lk})
                  unlocked_something = true
                  break
                end
              end
              if unlocked_something then break end
            end
          end
          if unlocked_something then break end
        end
      end

      if not unlocked_something then
        -- Move to a room
        local target_exit = nil
        if #unvisited_exits > 0 then
          target_exit = unvisited_exits[(demo_timer % #unvisited_exits) + 1]
        elseif #all_exits > 0 then
          target_exit = all_exits[(demo_timer % #all_exits) + 1]
        end

        if target_exit then
          do_action({action="go", exit=target_exit})
        end
      end
    end
  end

  -- Handle transitions in demo
  if msg_timer > 0 then
    msg_timer = msg_timer - 1
    if msg_timer <= 0 and #msg_queue > 0 then
      show_msg(msg_queue[1])
      table.remove(msg_queue, 1)
    end
  end

  -- Exit demo on any input
  if btnp("start") or btnp("a") or btnp("b") then
    demo_active = false
    scene = "title"
    idle_timer = 0
    clear_menu()
    sfx_note(0, "C4", 0.05)
  end

  -- End demo after a while
  if demo_timer > 600 then
    demo_active = false
    scene = "title"
    idle_timer = 0
  end
end

local function draw_demo()
  local room = rooms[cur_room]
  draw_room_bg(room)
  draw_hud(room)
  draw_msg()

  -- Demo label
  if math.floor(frame() / 20) % 2 == 0 then
    text(S, "- DEMO -", W/2, H - 6, C_DRK, ALIGN_CENTER)
  end
end

----------------------------------------------------------------
-- ENGINE CALLBACKS
----------------------------------------------------------------
function _init()
  mode(2)
end

function _start()
  seed_val = math.floor((time and time() or frame() or 42) * 31337) & 0xFFFF
  if seed_val == 0 then seed_val = 1 end
  scene = "title"
  title_sel = 0
  idle_timer = 0
  demo_active = false
  msg_timer = 0
  msg_queue = {}
  clear_menu()
end

function _update()
  if scene == "title" then
    update_title()
  elseif scene == "play" then
    update_play()
  elseif scene == "inventory" then
    update_inventory()
  elseif scene == "examine" then
    update_examine()
  elseif scene == "transition" then
    update_transition()
  elseif scene == "win" then
    update_win()
  elseif scene == "paused" then
    update_paused()
  elseif scene == "demo" then
    update_demo()
    -- Also handle transition within demo
    if scene == "transition" then
      -- stay in transition
    end
  end
end

function _draw()
  S = screen()

  if scene == "title" then
    draw_title()
  elseif scene == "play" then
    draw_play()
  elseif scene == "inventory" then
    draw_inventory()
  elseif scene == "examine" then
    draw_examine()
  elseif scene == "transition" then
    draw_transition()
  elseif scene == "win" then
    draw_win()
  elseif scene == "paused" then
    draw_paused()
  elseif scene == "demo" then
    draw_demo()
  end
end
