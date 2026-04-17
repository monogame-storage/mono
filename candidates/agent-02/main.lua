-- THE DARK ROOM - Agent #02
-- Top-down visual map mystery adventure
-- 160x120, 2-bit (0-3), single-file

----------------------------------------------------------------
-- CONSTANTS
----------------------------------------------------------------
W = 160
H = 120
TILE = 8
COLS = W / TILE      -- 20
ROWS = H / TILE      -- 15

-- Button IDs
B_LEFT  = "left"
B_RIGHT = "right"
B_UP    = "up"
B_DOWN  = "down"
B_Z     = "a"  -- interact
B_X     = "b"  -- inventory

-- Game states
ST_TITLE   = 0
ST_PLAY    = 1
ST_INV     = 2
ST_MSG     = 3
ST_WIN     = 4
ST_DEMO    = 5

-- Tile types
T_EMPTY  = 0
T_WALL   = 1
T_DOOR   = 2  -- locked door
T_DOOR_O = 3  -- open door
T_FURN   = 4  -- furniture (collidable)
T_ITEM   = 5  -- interactable item spot
T_EXIT   = 6  -- final exit

----------------------------------------------------------------
-- ROOM DATA
-- Each room: 20x13 grid (top 2 rows reserved for HUD)
-- Characters: #=wall .=floor D=locked door O=open door
-- F=furniture I=item spot E=exit X=transition
----------------------------------------------------------------
rooms = {}

-- Room 0: Bedroom (start)
rooms[0] = {
  name = "BEDROOM",
  map = {
    "####################",
    "#......#...........#",
    "#.FF...#...........#",
    "#.FF...#.......FF..#",
    "#......#........F..#",
    "#......D...........#",
    "#......#.......I...#",
    "#......#...........#",
    "#..I...#.....FF....#",
    "#......#.....FF....#",
    "#......#...........#",
    "#......#.........I.#",
    "####################",
  },
  items = {
    {x=3, y=8, id="flashlight", name="FLASHLIGHT", found=false,
     desc="A small flashlight. It works!"},
    {x=15, y=6, id="note1", name="TORN NOTE", found=false,
     desc="'Look behind the painting...'"},
    {x=17, y=11, id="bedroom_key", name="SMALL KEY", found=false,
     desc="A small brass key."},
  },
  furniture = {
    {x=2,y=2,w=2,h=2, name="BED", desc="Your bed. Sheets are messy."},
    {x=15,y=3,w=2,h=1, name="DRESSER", desc="An old wooden dresser."},
    {x=16,y=4,w=1,h=1, name="MIRROR", desc="A cracked mirror on the dresser."},
    {x=13,y=8,w=2,h=2, name="DESK", desc="A cluttered writing desk."},
  },
  doors = {
    {x=7, y=5, to_room=1, to_x=1, to_y=5, need_key=nil},
  },
  transitions = {},
  dark = true,
}

-- Room 1: Hallway
rooms[1] = {
  name = "HALLWAY",
  map = {
    "####################",
    "#..................#",
    "#..I...............#",
    "#..................#",
    "#..................#",
    "D..................D",
    "#..................#",
    "#..................#",
    "#..........F.......#",
    "#..........F.......#",
    "#...............I..#",
    "#..................#",
    "####################",
  },
  items = {
    {x=3, y=2, id="painting_clue", name="PAINTING", found=false,
     desc="Behind the painting: '3-7-1'"},
    {x=16, y=10, id="hallway_key", name="RUSTY KEY", found=false,
     desc="A rusty old key. Looks important."},
  },
  furniture = {
    {x=11,y=8,w=1,h=2, name="CABINET", desc="A tall locked cabinet."},
  },
  doors = {
    {x=0, y=5, to_room=0, to_x=6, to_y=5, need_key=nil},
    {x=19, y=5, to_room=2, to_x=1, to_y=6, need_key="bedroom_key"},
  },
  transitions = {},
  dark = false,
}

-- Room 2: Study
rooms[2] = {
  name = "STUDY",
  map = {
    "####################",
    "#.FFF..............#",
    "#..................#",
    "#..............FF..#",
    "#..............FF..#",
    "#..................#",
    "D..........I.......#",
    "#..................#",
    "#..................#",
    "#.......F..........#",
    "#..................#",
    "#...........I......#",
    "####################",
  },
  items = {
    {x=12, y=6, id="journal", name="JOURNAL", found=false,
     desc="'The safe combo is on the painting.'"},
    {x=12, y=11, id="master_key", name="MASTER KEY", found=false,
     desc="A heavy master key. Opens the exit!",
     need_puzzle="safe"},
  },
  furniture = {
    {x=2,y=1,w=3,h=1, name="BOOKSHELF", desc="Dusty old books line the shelf."},
    {x=15,y=3,w=2,h=2, name="SAFE", desc="A heavy safe. Needs a 3-digit code.",
     is_safe=true},
    {x=8,y=9,w=1,h=1, name="CHAIR", desc="A worn leather chair."},
  },
  doors = {
    {x=0, y=6, to_room=1, to_x=18, to_y=5, need_key=nil},
  },
  transitions = {
    {x=19, y=6, to_room=3, to_x=1, to_y=6},
  },
  dark = false,
}

-- Room 3: Kitchen (final room)
rooms[3] = {
  name = "KITCHEN",
  map = {
    "####################",
    "#.FFFF.............#",
    "#..................#",
    "#..................#",
    "#..........FF......#",
    "#..........FF......#",
    "D...............I..#",
    "#..................#",
    "#.....I............#",
    "#..................#",
    "#..................#",
    "#...........E......#",
    "####################",
  },
  items = {
    {x=16, y=6, id="knife", name="KNIFE", found=false,
     desc="A kitchen knife. Might be useful."},
    {x=6, y=8, id="fridge_note", name="FRIDGE NOTE", found=false,
     desc="'You can never leave... or can you?'"},
  },
  furniture = {
    {x=2,y=1,w=4,h=1, name="COUNTER", desc="Kitchen counter with dirty dishes."},
    {x=11,y=4,w=2,h=2, name="TABLE", desc="A dining table."},
  },
  doors = {
    {x=0, y=6, to_room=2, to_x=18, to_y=6, need_key="hallway_key"},
  },
  transitions = {},
  exits = {
    {x=12, y=11, need_key="master_key"},
  },
  dark = false,
}

----------------------------------------------------------------
-- GAME STATE
----------------------------------------------------------------
state = ST_TITLE
player = {x=4, y=4, dir=3, anim=0}
cur_room = 0
inventory = {}
msg_text = ""
msg_lines = {}
msg_timer = 0
safe_solved = false
has_flashlight = false
title_timer = 0
demo_timer = 0
demo_dir = 0
demo_change = 0
inv_sel = 0
light_radius = 3  -- in tiles
blink_t = 0

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------
function has_item(id)
  for _, v in ipairs(inventory) do
    if v.id == id then return true end
  end
  return false
end

function remove_item(id)
  for i, v in ipairs(inventory) do
    if v.id == id then
      table.remove(inventory, i)
      return true
    end
  end
  return false
end

function get_tile(room, gx, gy)
  local r = rooms[room]
  if not r then return T_WALL end
  if gy < 0 or gy > 12 or gx < 0 or gx > 19 then return T_WALL end
  local row = r.map[gy + 1]
  if not row then return T_WALL end
  local ch = row:sub(gx + 1, gx + 1)
  if ch == "#" then return T_WALL
  elseif ch == "D" then return T_DOOR
  elseif ch == "O" then return T_DOOR_O
  elseif ch == "F" then return T_FURN
  elseif ch == "I" then return T_ITEM
  elseif ch == "E" then return T_EXIT
  else return T_EMPTY end
end

function is_blocked(room, px, py)
  -- px, py in pixel coords; check all 4 corners of 6x6 player hitbox
  local offsets = {{0,0},{5,0},{0,5},{5,5},{2,2}}
  for _, o in ipairs(offsets) do
    local gx = math.floor((px + o[1]) / TILE)
    local gy = math.floor((py + o[2]) / TILE)
    local t = get_tile(room, gx, gy)
    if t == T_WALL or t == T_FURN then return true end
    if t == T_DOOR then
      -- check if we have the key
      local r = rooms[room]
      for _, d in ipairs(r.doors) do
        if d.x == gx and d.y == gy then
          if d.need_key and not has_item(d.need_key) then
            return true
          end
        end
      end
    end
  end
  return false
end

function show_msg(txt)
  msg_text = txt
  msg_lines = {}
  -- word wrap at ~28 chars
  local line = ""
  for word in txt:gmatch("%S+") do
    if #line + #word + 1 > 28 then
      table.insert(msg_lines, line)
      line = word
    else
      if #line > 0 then line = line .. " " end
      line = line .. word
    end
  end
  if #line > 0 then table.insert(msg_lines, line) end
  msg_timer = 90
  state = ST_MSG
end

function sfx_step()
  noise(0, 0.02)
end

function sfx_pickup()
  tone(0, 600, 900, 0.08)
end

function sfx_door()
  tone(0, 200, 100, 0.1)
  noise(1, 0.05)
end

function sfx_locked()
  tone(0, 100, 80, 0.1)
  noise(1, 0.08)
end

function sfx_puzzle()
  tone(0, 400, 800, 0.15)
  tone(1, 600, 1200, 0.15)
end

function sfx_win()
  tone(0, 400, 800, 0.2)
  tone(1, 500, 1000, 0.2)
end

function sfx_ambient()
  if frame() % 120 == 0 then
    tone(0, 40, 50, 0.3)
  end
end

----------------------------------------------------------------
-- INIT
----------------------------------------------------------------
function _init()
  mode(2)
end

function _start()
  state = ST_TITLE
  title_timer = 0
  demo_timer = 0
end

----------------------------------------------------------------
-- TITLE SCREEN
----------------------------------------------------------------
function update_title()
  title_timer = title_timer + 1

  -- Start demo after 180 frames (6 seconds)
  if title_timer > 180 then
    state = ST_DEMO
    demo_timer = 0
    demo_change = 0
    demo_dir = 1
    cur_room = 0
    player.x = 4 * TILE + 1
    player.y = 4 * TILE + 1
    inventory = {}
    safe_solved = false
    has_flashlight = false
    light_radius = 3
    -- Reset all items
    for ri = 0, 3 do
      local r = rooms[ri]
      if r.items then
        for _, it in ipairs(r.items) do it.found = false end
      end
    end
    return
  end

  if btnp(B_Z) or btnp(B_X) then
    -- Start game
    state = ST_PLAY
    cur_room = 0
    player.x = 4 * TILE + 1
    player.y = 4 * TILE + 1
    player.dir = 3
    inventory = {}
    safe_solved = false
    has_flashlight = false
    light_radius = 3
    for ri = 0, 3 do
      local r = rooms[ri]
      if r.items then
        for _, it in ipairs(r.items) do it.found = false end
      end
    end
    sfx_door()
  end
end

function draw_title()
  local s = screen()
  cls(s, 0)

  -- Flickering title
  local flk = math.floor(frame() / 15) % 2
  local tc = flk == 0 and 3 or 2

  text(s, "THE DARK ROOM", 30, 25, tc)

  -- Subtitle
  text(s, "A Mystery Adventure", 22, 40, 1)

  -- Blinking prompt
  if math.floor(frame() / 20) % 2 == 0 then
    text(s, "PRESS Z TO START", 26, 70, 2)
  end

  -- Draw a small room preview
  rect(s, 50, 85, 60, 30, 1)
  -- Little figure
  local fy = 97 + math.floor(math.sin(frame() * 0.05) * 2)
  rectf(s, 78, fy, 4, 5, 2)
  circf(s, 80, fy - 2, 2, 3)

  -- Door
  rectf(s, 107, 93, 3, 8, 1)

  text(s, "Agent #02", 52, 112, 1)
end

----------------------------------------------------------------
-- DEMO MODE
----------------------------------------------------------------
function update_demo()
  demo_timer = demo_timer + 1
  demo_change = demo_change + 1

  -- Change direction periodically
  if demo_change > 30 then
    demo_change = 0
    demo_dir = math.random(0, 3)
  end

  -- Move player in demo
  local dx, dy = 0, 0
  if demo_dir == 0 then dx = -1
  elseif demo_dir == 1 then dx = 1
  elseif demo_dir == 2 then dy = -1
  elseif demo_dir == 3 then dy = 1 end

  local nx = player.x + dx
  local ny = player.y + dy
  if not is_blocked(cur_room, nx, ny) then
    player.x = nx
    player.y = ny
    player.dir = demo_dir
  else
    demo_change = 30  -- force direction change
  end

  player.anim = player.anim + 1

  -- Exit demo on button press
  if btnp(B_Z) or btnp(B_X) then
    state = ST_TITLE
    title_timer = 0
  end

  -- Loop demo after a while
  if demo_timer > 300 then
    state = ST_TITLE
    title_timer = 0
  end
end

----------------------------------------------------------------
-- GAMEPLAY UPDATE
----------------------------------------------------------------
function update_play()
  local dx, dy = 0, 0
  local moved = false
  local spd = 1

  if btn(B_LEFT)  then dx = -spd; player.dir = 0; moved = true end
  if btn(B_RIGHT) then dx =  spd; player.dir = 1; moved = true end
  if btn(B_UP)    then dy = -spd; player.dir = 2; moved = true end
  if btn(B_DOWN)  then dy =  spd; player.dir = 3; moved = true end

  -- Try move X then Y separately
  if dx ~= 0 then
    local nx = player.x + dx
    if not is_blocked(cur_room, nx, player.y) then
      player.x = nx
    end
  end
  if dy ~= 0 then
    local ny = player.y + dy
    if not is_blocked(cur_room, player.x, ny) then
      player.y = ny
    end
  end

  if moved then
    player.anim = player.anim + 1
    if player.anim % 10 == 0 then sfx_step() end
  end

  -- Ambient
  sfx_ambient()
  blink_t = blink_t + 1

  -- Check door/transition proximity
  check_doors()
  check_transitions()
  check_exit()

  -- Interact button
  if btnp(B_Z) then
    interact()
  end

  -- Inventory button
  if btnp(B_X) then
    if #inventory > 0 then
      state = ST_INV
      inv_sel = 0
    else
      show_msg("Inventory is empty.")
    end
  end
end

function check_doors()
  local r = rooms[cur_room]
  if not r.doors then return end
  local pgx = math.floor((player.x + 3) / TILE)
  local pgy = math.floor((player.y + 3) / TILE)

  for _, d in ipairs(r.doors) do
    if math.abs(pgx - d.x) <= 1 and math.abs(pgy - d.y) <= 1 then
      if d.need_key then
        if has_item(d.need_key) then
          -- Auto-use key and go through
          if math.abs(pgx - d.x) == 0 and math.abs(pgy - d.y) == 0 then
            remove_item(d.need_key)
            sfx_door()
            cur_room = d.to_room
            player.x = d.to_x * TILE + 1
            player.y = d.to_y * TILE + 1
            show_msg("Used key. Door opened!")
            return
          end
        end
      else
        -- No key needed, walk through
        if math.abs(pgx - d.x) == 0 and math.abs(pgy - d.y) == 0 then
          sfx_door()
          cur_room = d.to_room
          player.x = d.to_x * TILE + 1
          player.y = d.to_y * TILE + 1
          return
        end
      end
    end
  end
end

function check_transitions()
  local r = rooms[cur_room]
  if not r.transitions then return end
  local pgx = math.floor((player.x + 3) / TILE)
  local pgy = math.floor((player.y + 3) / TILE)

  for _, t in ipairs(r.transitions) do
    if pgx == t.x and pgy == t.y then
      cur_room = t.to_room
      player.x = t.to_x * TILE + 1
      player.y = t.to_y * TILE + 1
      sfx_door()
      return
    end
  end
end

function check_exit()
  local r = rooms[cur_room]
  if not r.exits then return end
  local pgx = math.floor((player.x + 3) / TILE)
  local pgy = math.floor((player.y + 3) / TILE)

  for _, e in ipairs(r.exits) do
    if pgx == e.x and pgy == e.y then
      if has_item(e.need_key) then
        state = ST_WIN
        sfx_win()
      end
    end
  end
end

function interact()
  local r = rooms[cur_room]
  local pgx = math.floor((player.x + 3) / TILE)
  local pgy = math.floor((player.y + 3) / TILE)

  -- Check items nearby
  if r.items then
    for _, it in ipairs(r.items) do
      if not it.found then
        if math.abs(pgx - it.x) <= 1 and math.abs(pgy - it.y) <= 1 then
          -- Check if item needs puzzle solved
          if it.need_puzzle == "safe" and not safe_solved then
            show_msg("The safe is locked. Need the code.")
            return
          end
          it.found = true
          table.insert(inventory, {id=it.id, name=it.name, desc=it.desc})
          sfx_pickup()
          show_msg("Found: " .. it.name .. "! " .. it.desc)
          if it.id == "flashlight" then
            has_flashlight = true
            light_radius = 8
          end
          return
        end
      end
    end
  end

  -- Check furniture nearby
  if r.furniture then
    for _, f in ipairs(r.furniture) do
      local fx2 = f.x + (f.w or 1) - 1
      local fy2 = f.y + (f.h or 1) - 1
      if pgx >= f.x - 1 and pgx <= fx2 + 1 and pgy >= f.y - 1 and pgy <= fy2 + 1 then
        if f.is_safe then
          -- Safe interaction
          if safe_solved then
            show_msg("The safe is already open.")
          elseif has_item("painting_clue") then
            safe_solved = true
            sfx_puzzle()
            show_msg("You enter 3-7-1... Click! The safe opens!")
          else
            show_msg("A heavy safe. The code has 3 digits.")
            sfx_locked()
          end
          return
        end
        show_msg(f.desc)
        return
      end
    end
  end

  -- Check doors that need keys
  if r.doors then
    for _, d in ipairs(r.doors) do
      if math.abs(pgx - d.x) <= 1 and math.abs(pgy - d.y) <= 1 then
        if d.need_key and not has_item(d.need_key) then
          show_msg("This door is locked. You need a key.")
          sfx_locked()
          return
        end
      end
    end
  end

  -- Check exit
  if r.exits then
    for _, e in ipairs(r.exits) do
      if math.abs(pgx - e.x) <= 1 and math.abs(pgy - e.y) <= 1 then
        if not has_item(e.need_key) then
          show_msg("The exit! But it's locked tight.")
          sfx_locked()
        end
        return
      end
    end
  end

  show_msg("Nothing interesting here.")
end

----------------------------------------------------------------
-- INVENTORY SCREEN
----------------------------------------------------------------
function update_inv()
  if btnp(B_UP) then
    inv_sel = inv_sel - 1
    if inv_sel < 0 then inv_sel = #inventory - 1 end
  end
  if btnp(B_DOWN) then
    inv_sel = inv_sel + 1
    if inv_sel >= #inventory then inv_sel = 0 end
  end
  if btnp(B_X) or btnp(B_Z) then
    state = ST_PLAY
  end
end

function draw_inv()
  local s = screen()
  -- Overlay
  rectf(s, 10, 8, 140, 104, 0)
  rect(s, 10, 8, 140, 104, 2)
  text(s, "INVENTORY", 52, 12, 3)
  line(s, 12, 20, 148, 20, 1)

  if #inventory == 0 then
    text(s, "Empty", 60, 50, 1)
    return
  end

  for i, it in ipairs(inventory) do
    local y = 24 + (i - 1) * 12
    local c = 1
    if i - 1 == inv_sel then
      c = 3
      rectf(s, 12, y - 1, 136, 11, 1)
    end
    text(s, it.name, 16, y, c)
  end

  -- Description of selected
  if inv_sel >= 0 and inv_sel < #inventory then
    local it = inventory[inv_sel + 1]
    if it then
      line(s, 12, 92, 148, 92, 1)
      text(s, it.desc, 14, 96, 2)
    end
  end

  text(s, "X:CLOSE", 56, 105, 1)
end

----------------------------------------------------------------
-- MESSAGE BOX
----------------------------------------------------------------
function update_msg()
  msg_timer = msg_timer - 1
  if msg_timer <= 0 or btnp(B_Z) or btnp(B_X) then
    state = ST_PLAY
  end
end

function draw_msg()
  local s = screen()
  -- Message box at bottom
  rectf(s, 4, 84, 152, 32, 0)
  rect(s, 4, 84, 152, 32, 2)

  for i, ln in ipairs(msg_lines) do
    text(s, ln, 8, 86 + (i - 1) * 10, 3)
  end
end

----------------------------------------------------------------
-- WIN SCREEN
----------------------------------------------------------------
function update_win()
  if btnp(B_Z) then
    state = ST_TITLE
    title_timer = 0
  end
end

function draw_win()
  local s = screen()
  cls(s, 0)

  text(s, "YOU ESCAPED!", 40, 30, 3)
  text(s, "The door swings open.", 18, 48, 2)
  text(s, "Fresh air fills your lungs.", 8, 58, 2)
  text(s, "You are free.", 42, 68, 3)

  -- Animate light expanding
  local r = math.min(40, math.floor(frame() * 0.3))
  circf(s, 80, 95, r, 1)
  circf(s, 80, 95, math.max(0, r - 5), 2)
  circf(s, 80, 95, math.max(0, r - 10), 3)

  if math.floor(frame() / 20) % 2 == 0 then
    text(s, "PRESS Z", 56, 112, 2)
  end
end

----------------------------------------------------------------
-- DRAWING - ROOM RENDERER
----------------------------------------------------------------
function draw_room()
  local s = screen()
  cls(s, 0)

  local r = rooms[cur_room]
  if not r then return end

  local pcx = math.floor((player.x + 3) / TILE)
  local pcy = math.floor((player.y + 3) / TILE)
  local lr = light_radius
  local is_dark = r.dark and not has_flashlight

  -- Draw tiles
  for gy = 0, 12 do
    for gx = 0, 19 do
      local px = gx * TILE
      local py = gy * TILE

      -- Visibility check
      local dist = math.sqrt((gx - pcx)^2 + (gy - pcy)^2)
      local visible = true
      local dim = false

      if is_dark then
        if dist > 4 then
          visible = false
        elseif dist > 2 then
          dim = true
        end
      elseif r.dark and has_flashlight then
        if dist > lr then
          visible = false
        elseif dist > lr - 2 then
          dim = true
        end
      end

      if not visible then
        -- Leave black
      else
        local t = get_tile(cur_room, gx, gy)
        local c = 0

        if t == T_WALL then
          -- Wall with texture
          if dim then
            rectf(s, px, py, TILE, TILE, 1)
          else
            rectf(s, px, py, TILE, TILE, 2)
            -- Brick pattern
            if (gx + gy) % 2 == 0 then
              line(s, px, py + 3, px + TILE - 1, py + 3, 1)
              line(s, px + 4, py, px + 4, py + 3, 1)
            else
              line(s, px, py + 4, px + TILE - 1, py + 4, 1)
              line(s, px + 2, py, px + 2, py + 4, 1)
            end
          end
        elseif t == T_EMPTY then
          -- Floor
          c = dim and 0 or 1
          if c > 0 then
            rectf(s, px, py, TILE, TILE, c)
            -- Floor pattern
            if (gx + gy) % 4 == 0 then
              pix(s, px + 3, py + 3, 0)
            end
          end
        elseif t == T_DOOR then
          -- Door (locked or open depending on key)
          rectf(s, px, py, TILE, TILE, 1)
          rectf(s, px + 2, py + 1, 4, 6, dim and 1 or 2)
          -- Doorknob
          if not dim then
            pix(s, px + 5, py + 4, 3)
          end
        elseif t == T_DOOR_O then
          rectf(s, px, py, TILE, TILE, 1)
          rectf(s, px + 1, py + 1, 2, 6, dim and 0 or 1)
        elseif t == T_FURN then
          -- Furniture
          rectf(s, px, py, TILE, TILE, 1)
          rectf(s, px + 1, py + 1, TILE - 2, TILE - 2, dim and 1 or 2)
        elseif t == T_ITEM then
          -- Floor with item sparkle
          rectf(s, px, py, TILE, TILE, dim and 0 or 1)
          -- Check if item still exists here
          local item_here = false
          if r.items then
            for _, it in ipairs(r.items) do
              if it.x == gx and it.y == gy and not it.found then
                item_here = true
              end
            end
          end
          if item_here and not dim then
            -- Sparkle effect
            local sp = math.floor(blink_t / 8) % 4
            local sx = px + 3 + sp
            local sy = py + 2
            pix(s, sx, sy, 3)
            pix(s, sx - 1, sy, 2)
            pix(s, sx + 1, sy, 2)
            pix(s, sx, sy - 1, 2)
            pix(s, sx, sy + 1, 2)
          end
        elseif t == T_EXIT then
          -- Exit door (special)
          rectf(s, px, py, TILE, TILE, 1)
          if math.floor(blink_t / 10) % 2 == 0 then
            rectf(s, px + 1, py + 1, TILE - 2, TILE - 2, 3)
          else
            rectf(s, px + 1, py + 1, TILE - 2, TILE - 2, 2)
          end
          -- Arrow
          pix(s, px + 3, py + 2, 0)
          pix(s, px + 4, py + 2, 0)
          pix(s, px + 2, py + 3, 0)
          pix(s, px + 5, py + 3, 0)
          pix(s, px + 3, py + 4, 0)
          pix(s, px + 4, py + 4, 0)
        end
      end
    end
  end

  -- Draw furniture details on top
  if r.furniture then
    for _, f in ipairs(r.furniture) do
      local fx = f.x * TILE
      local fy = f.y * TILE
      local fw = (f.w or 1) * TILE
      local fh = (f.h or 1) * TILE
      local dist = math.sqrt((f.x - pcx)^2 + (f.y - pcy)^2)

      local vis = true
      local dim = false
      if is_dark then
        if dist > 4 then vis = false
        elseif dist > 2 then dim = true end
      elseif r.dark and has_flashlight then
        if dist > lr then vis = false
        elseif dist > lr - 2 then dim = true end
      end

      if vis then
        local c1 = dim and 1 or 2
        local c2 = dim and 1 or 3
        rectf(s, fx, fy, fw, fh, c1)
        rect(s, fx, fy, fw, fh, c2)

        -- Draw specific furniture types
        if f.is_safe then
          -- Safe dial
          circf(s, fx + fw/2, fy + fh/2, 3, dim and 1 or 3)
          circ(s, fx + fw/2, fy + fh/2, 3, dim and 0 or 1)
          pix(s, fx + fw/2, fy + fh/2 - 2, dim and 0 or 1)
        end
      end
    end
  end

  -- Draw player
  draw_player_sprite()

  -- Draw darkness overlay (vignette effect for dark rooms)
  if r.dark then
    draw_darkness(pcx, pcy, lr)
  end

  -- HUD at very top
  draw_hud()
end

function draw_player_sprite()
  local s = screen()
  local px = math.floor(player.x)
  local py = math.floor(player.y)

  -- Body (6x6)
  rectf(s, px, py + 2, 6, 4, 3)
  -- Head
  circf(s, px + 3, py + 1, 2, 3)

  -- Eyes based on direction
  if player.dir == 0 then -- left
    pix(s, px + 1, py + 1, 0)
  elseif player.dir == 1 then -- right
    pix(s, px + 4, py + 1, 0)
  elseif player.dir == 2 then -- up
    pix(s, px + 2, py, 0)
    pix(s, px + 4, py, 0)
  else -- down
    pix(s, px + 2, py + 2, 0)
    pix(s, px + 4, py + 2, 0)
  end

  -- Walking animation - legs
  if player.anim % 10 < 5 then
    pix(s, px + 1, py + 6, 2)
    pix(s, px + 4, py + 6, 2)
  else
    pix(s, px + 2, py + 6, 2)
    pix(s, px + 3, py + 6, 2)
  end

  -- Flashlight beam if equipped
  if has_flashlight then
    local bx, by = px + 3, py + 3
    if player.dir == 0 then
      line(s, bx, by, bx - 12, by - 3, 1)
      line(s, bx, by, bx - 12, by + 3, 1)
    elseif player.dir == 1 then
      line(s, bx, by, bx + 12, by - 3, 1)
      line(s, bx, by, bx + 12, by + 3, 1)
    elseif player.dir == 2 then
      line(s, bx, by, bx - 3, by - 12, 1)
      line(s, bx, by, bx + 3, by - 12, 1)
    else
      line(s, bx, by, bx - 3, by + 12, 1)
      line(s, bx, by, bx + 3, by + 12, 1)
    end
  end
end

function draw_darkness(pcx, pcy, lr)
  local s = screen()
  -- Draw black pixels for areas outside light radius (sparse approach)
  -- Only do outer ring to save perf
  for gy = 0, 12 do
    for gx = 0, 19 do
      local dist = math.sqrt((gx - pcx)^2 + (gy - pcy)^2)
      if dist > lr then
        rectf(s, gx * TILE, gy * TILE, TILE, TILE, 0)
      elseif dist > lr - 1 then
        -- Dithered darkness
        local px = gx * TILE
        local py = gy * TILE
        for dy = 0, TILE - 1, 2 do
          for dx = 0, TILE - 1, 2 do
            if (dx + dy) % 4 == 0 then
              pix(s, px + dx, py + dy, 0)
            end
          end
        end
      end
    end
  end
end

function draw_hud()
  local s = screen()
  -- Top bar
  rectf(s, 0, 0, W, 8, 0)

  local r = rooms[cur_room]
  if r then
    text(s, r.name, 2, 1, 2)
  end

  -- Item count
  local ic = #inventory
  text(s, "ITEMS:" .. ic, 100, 1, 1)

  -- Z hint
  if math.floor(blink_t / 30) % 2 == 0 then
    text(s, "Z:ACT X:INV", 2, 113, 1)
  end
end

----------------------------------------------------------------
-- MAIN UPDATE/DRAW
----------------------------------------------------------------
function _update()
  if state == ST_TITLE then
    update_title()
  elseif state == ST_PLAY then
    update_play()
  elseif state == ST_INV then
    update_inv()
  elseif state == ST_MSG then
    update_msg()
  elseif state == ST_WIN then
    update_win()
  elseif state == ST_DEMO then
    update_demo()
  end
end

function _draw()
  if state == ST_TITLE then
    draw_title()
  elseif state == ST_PLAY then
    draw_room()
  elseif state == ST_INV then
    draw_room()
    draw_inv()
  elseif state == ST_MSG then
    draw_room()
    draw_msg()
  elseif state == ST_WIN then
    draw_win()
  elseif state == ST_DEMO then
    draw_room()
    -- Demo label
    local s = screen()
    rectf(s, 50, 0, 60, 8, 0)
    text(s, "- DEMO -", 54, 1, 2)
  end
end
