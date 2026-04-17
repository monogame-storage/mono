-- THE DARK ROOM: FRACTURED MEMORIES (Puzzle Edition)
-- Agent 15 = Agent 07 (multi-ending mystery) + Agent 03 (puzzle mechanics)
-- 160x120 | 2-bit (0-3) | mode(2) | surface-first
-- D-Pad: Navigate/Cursor | A: Confirm/Interact | B: Cancel/Submit

---------- CONSTANTS ----------
local W = 160
local H = 120
local S -- screen surface

local BLK = 0
local DRK = 1
local LIT = 2
local WHT = 3

---------- SAFE AUDIO ----------
local function snd_note(ch, n, dur)
  if note then pcall(note, ch, n, dur) end
end
local function snd_noise(ch, dur)
  if noise then pcall(noise, ch, dur) end
end
local function snd_click() snd_noise(0, 0.02) end
local function snd_ok()
  snd_note(0, "E5", 0.08)
  snd_note(1, "G5", 0.08)
end
local function snd_fail()
  snd_note(0, "C2", 0.1)
  snd_noise(1, 0.08)
end
local function snd_solve()
  snd_note(0, "C5", 0.12)
  snd_note(1, "E5", 0.12)
end
local function snd_tone(idx)
  local notes = {"C4","E4","G4","C5"}
  snd_note(0, notes[idx] or "A4", 0.1)
end
local function snd_step() snd_noise(0, 0.04) end
local function snd_danger()
  snd_note(0, "C2", 0.15)
  snd_noise(1, 0.1)
end
local function snd_ambient(n)
  snd_note(2, n, 0.8)
end

---------- UTILITIES ----------
local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function text_c(str, y, c)
  text(S, str, W / 2, y, c or WHT, ALIGN_CENTER)
end

local function text_l(str, x, y, c)
  text(S, str, x, y, c or WHT)
end

local function draw_box(x, y, w, h, border, bg)
  rectf(S, x, y, w, h, bg or BLK)
  rect(S, x, y, w, h, border or WHT)
end

---------- FORWARD DECLARATIONS ----------
local init_game, change_room

---------- STATE ----------
local state       -- "title","play","paused","ending","demo","puzzle"
local tick = 0
local idle_timer = 0
local IDLE_MAX = 300
local flash_t = 0

-- Game state
local room         -- current room id string
local menu_cursor  -- menu cursor index (0-based)
local inv = {}     -- inventory
local flags = {}   -- boolean flags
local msg = ""
local msg_timer = 0
local fade = 0
local fade_dir = 0
local fade_target_room = nil
local ending_id = nil
local ending_timer = 0

-- Puzzle state
local puzzle_id = nil      -- which puzzle is active
local puzzle_cursor = {}   -- {x,y} cursor for puzzles
local puzzle_data = {}     -- puzzle-specific data

-- Demo
local demo_step = 0
local demo_timer = 0

---------- INVENTORY ----------
local function has_item(id)
  for _, v in ipairs(inv) do if v == id then return true end end
  return false
end
local function add_item(id)
  if not has_item(id) and #inv < 6 then
    inv[#inv + 1] = id
    snd_ok()
    return true
  end
  return false
end
local function remove_item(id)
  for i, v in ipairs(inv) do
    if v == id then table.remove(inv, i) return true end
  end
  return false
end

local ITEM_NAMES = {
  key = "Key", badge = "ID Badge", evidence = "Evidence",
  flashlight = "Flashlight", note1 = "Memo", fuse = "Fuse",
}

---------- PUZZLE: PATTERN MATCH (Dark Room) ----------
local function init_puzzle_pattern()
  puzzle_id = "pattern"
  puzzle_cursor = {x=1, y=1}
  local d = {}
  d.sz = 4
  d.target = {}
  d.player = {}
  for y=1,d.sz do
    d.target[y] = {}
    d.player[y] = {}
    for x=1,d.sz do
      d.target[y][x] = math.random() < 0.4 and 1 or 0
      d.player[y][x] = 0
    end
  end
  d.showing = true
  d.timer = 90
  puzzle_data = d
  state = "puzzle"
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
  if btnp("b") then
    local ok = true
    for y=1,d.sz do
      for x=1,d.sz do
        if d.target[y][x] ~= d.player[y][x] then ok=false end
      end
    end
    if ok then return true
    else
      snd_fail(); flash_t = 10
      d.showing = true; d.timer = 45
    end
  end
  return false
end

local function draw_puzzle_pattern()
  local d = puzzle_data
  local ox, oy = 46, 18
  local cs = 14
  local grid = d.showing and d.target or d.player

  if d.showing then
    text_c("MEMORIZE THE PATTERN", 4, WHT)
    if tick%10<5 then rect(S, 0,0,W-1,H-1,WHT) end
  else
    text_c("REPRODUCE IT", 4, LIT)
  end

  for y=1,d.sz do
    for x=1,d.sz do
      local px = ox+(x-1)*cs
      local py = oy+(y-1)*cs
      local on = grid[y][x] == 1
      rectf(S, px, py, cs-2, cs-2, on and WHT or DRK)
      rect(S, px, py, cs-2, cs-2, LIT)
    end
  end
  if not d.showing then
    local cx = ox+(puzzle_cursor.x-1)*cs
    local cy = oy+(puzzle_cursor.y-1)*cs
    rect(S, cx-1, cy-1, cs, cs, WHT)
    text_c("A:Toggle  B:Submit", 80, LIT)
  else
    text_c("Watch carefully...", 80, LIT)
  end
end

---------- PUZZLE: COMBINATION LOCK (Lab / Vault) ----------
local function init_puzzle_combo(target_override)
  puzzle_id = "combo"
  puzzle_cursor = {x=1, y=1}
  local d = {}
  d.cols = 4
  d.digits = {0,0,0,0}
  d.target = target_override or {}
  if #d.target == 0 then
    for i=1,d.cols do d.target[i] = math.random(0,9) end
  end
  puzzle_data = d
  state = "puzzle"
end

local function update_puzzle_combo()
  local d = puzzle_data
  if btnp("left") then puzzle_cursor.x = math.max(1, puzzle_cursor.x-1); snd_click() end
  if btnp("right") then puzzle_cursor.x = math.min(d.cols, puzzle_cursor.x+1); snd_click() end
  if btnp("up") then d.digits[puzzle_cursor.x] = (d.digits[puzzle_cursor.x]+1)%10; snd_click() end
  if btnp("down") then d.digits[puzzle_cursor.x] = (d.digits[puzzle_cursor.x]-1)%10; snd_click() end
  if btnp("a") then
    local ok = true
    for i=1,d.cols do
      if d.digits[i] ~= d.target[i] then ok=false; break end
    end
    if ok then return true
    else snd_fail(); flash_t = 10 end
  end
  return false
end

local function draw_puzzle_combo()
  local d = puzzle_data
  local s = 0
  for i=1,d.cols do s = s + d.target[i] end
  text_l("HINT: SUM="..s, 4, 4, LIT)
  local hint2 = ""
  for i=1,d.cols do
    hint2 = hint2 .. (d.target[i]%2==0 and "E" or "O")
  end
  text_l("PARITY: "..hint2, 4, 14, LIT)

  local ox, oy = 40, 40
  for i=1,d.cols do
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
  text_c("Up/Down:Digit  A:Check", 80, LIT)
end

---------- PUZZLE: WIRE CONNECT (Office) ----------
local function init_puzzle_wires()
  puzzle_id = "wires"
  puzzle_cursor = {x=1, y=1}
  local d = {}
  d.sz = 5
  d.grid = {}
  for y=1,d.sz do
    d.grid[y] = {}
    for x=1,d.sz do d.grid[y][x] = {kind=0} end
  end
  d.pairs = {}
  local spots = {}
  for y=1,d.sz do for x=1,d.sz do spots[#spots+1]={x=x,y=y} end end
  for i=#spots,2,-1 do
    local j=math.random(1,i)
    spots[i], spots[j] = spots[j], spots[i]
  end
  for i=1,4 do
    local a = spots[i*2-1]
    local b = spots[i*2]
    d.grid[a.y][a.x].kind = i
    d.grid[b.y][b.x].kind = i
    d.pairs[i] = {a=a, b=b, done=false}
  end
  d.sel = nil
  puzzle_data = d
  state = "puzzle"
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
        if cell.kind == d.sel.kind and (puzzle_cursor.x~=d.sel.x or puzzle_cursor.y~=d.sel.y) then
          d.pairs[cell.kind].done = true
          snd_ok()
          d.sel = nil
          local ok = true
          for _, p in ipairs(d.pairs) do if not p.done then ok=false; break end end
          if ok then return true end
        else
          snd_fail(); d.sel = nil
        end
      end
    end
  end
  if btnp("b") then d.sel = nil end
  return false
end

local function draw_puzzle_wires()
  local d = puzzle_data
  text_c("MATCH THE WIRE PAIRS", 2, LIT)
  local ox, oy = 40, 16
  local cs = 15
  for y=1,d.sz do
    for x=1,d.sz do
      local px = ox+(x-1)*cs
      local py = oy+(y-1)*cs
      rect(S, px, py, cs-2, cs-2, DRK)
      local cell = d.grid[y][x]
      if cell.kind > 0 then
        local col = d.pairs[cell.kind].done and DRK or (cell.kind <= 2 and LIT or WHT)
        circf(S, px+cs/2-1, py+cs/2-1, 4, col)
        text_l(tostring(cell.kind), px+cs/2-3, py+cs/2-3, BLK)
      end
    end
  end
  for _, p in ipairs(d.pairs) do
    if p.done then
      local ax = ox+(p.a.x-1)*cs+cs/2-1
      local ay = oy+(p.a.y-1)*cs+cs/2-1
      local bx = ox+(p.b.x-1)*cs+cs/2-1
      local by = oy+(p.b.y-1)*cs+cs/2-1
      line(S, ax, ay, bx, by, LIT)
    end
  end
  local cx = ox+(puzzle_cursor.x-1)*cs
  local cy = oy+(puzzle_cursor.y-1)*cs
  rect(S, cx-1, cy-1, cs, cs, WHT)
  if d.sel then
    local sx = ox+(d.sel.x-1)*cs
    local sy = oy+(d.sel.y-1)*cs
    rect(S, sx-1, sy-1, cs, cs, WHT)
  end
  text_c("A:Select  B:Cancel", 94, LIT)
end

---------- PUZZLE: SLIDING TILES (Basement) ----------
local function init_puzzle_tiles()
  puzzle_id = "tiles"
  puzzle_cursor = {x=2, y=2}
  local d = {}
  d.tiles = {}
  for i=1,8 do
    d.tiles[i] = {val=i, x=((i-1)%3)+1, y=math.floor((i-1)/3)+1}
  end
  d.empty = {x=3, y=3}
  -- shuffle with valid moves
  for i=1,60 do
    local dirs = {{-1,0},{1,0},{0,-1},{0,1}}
    local dd = dirs[math.random(1,4)]
    local nx, ny = d.empty.x+dd[1], d.empty.y+dd[2]
    if nx>=1 and nx<=3 and ny>=1 and ny<=3 then
      for _, t in ipairs(d.tiles) do
        if t.x==nx and t.y==ny then
          t.x, t.y = d.empty.x, d.empty.y
          d.empty.x, d.empty.y = nx, ny
          break
        end
      end
    end
  end
  puzzle_data = d
  state = "puzzle"
end

local function update_puzzle_tiles()
  local d = puzzle_data
  if btnp("left") then puzzle_cursor.x = math.max(1, puzzle_cursor.x-1); snd_click() end
  if btnp("right") then puzzle_cursor.x = math.min(3, puzzle_cursor.x+1); snd_click() end
  if btnp("up") then puzzle_cursor.y = math.max(1, puzzle_cursor.y-1); snd_click() end
  if btnp("down") then puzzle_cursor.y = math.min(3, puzzle_cursor.y+1); snd_click() end
  if btnp("a") then
    local dx = math.abs(puzzle_cursor.x - d.empty.x)
    local dy = math.abs(puzzle_cursor.y - d.empty.y)
    if (dx+dy)==1 then
      for _, t in ipairs(d.tiles) do
        if t.x==puzzle_cursor.x and t.y==puzzle_cursor.y then
          t.x, t.y = d.empty.x, d.empty.y
          d.empty.x, d.empty.y = puzzle_cursor.x, puzzle_cursor.y
          snd_click()
          break
        end
      end
    end
    -- check solved
    local ok = true
    for i=1,8 do
      local gx = ((i-1)%3)+1
      local gy = math.floor((i-1)/3)+1
      if d.tiles[i].x~=gx or d.tiles[i].y~=gy then ok=false; break end
    end
    if ok then return true end
  end
  return false
end

local function draw_puzzle_tiles()
  local d = puzzle_data
  text_c("RESTORE POWER GRID", 2, LIT)
  text_c("Arrange 1-8 in order", 12, DRK)
  local ox, oy = 44, 24
  local sz = 22
  for gy=1,3 do
    for gx=1,3 do
      local px = ox+(gx-1)*sz
      local py = oy+(gy-1)*sz
      rectf(S, px, py, sz-2, sz-2, DRK)
      rect(S, px, py, sz-2, sz-2, LIT)
    end
  end
  for _, t in ipairs(d.tiles) do
    local px = ox+(t.x-1)*sz
    local py = oy+(t.y-1)*sz
    rectf(S, px+1, py+1, sz-4, sz-4, LIT)
    text_l(tostring(t.val), px+7, py+7, WHT)
  end
  local cx = ox+(puzzle_cursor.x-1)*sz
  local cy = oy+(puzzle_cursor.y-1)*sz
  rect(S, cx-1, cy-1, sz, sz, WHT)
  text_c("A:Slide tile", 94, LIT)
end

---------- PUZZLE: SEQUENCE MEMORY (Rooftop) ----------
local function init_puzzle_sequence()
  puzzle_id = "sequence"
  puzzle_cursor = {x=1, y=1}
  local d = {}
  d.seq = {}
  d.max = 5
  d.len = 3
  for i=1,d.max do d.seq[i] = math.random(1,4) end
  d.input = {}
  d.phase = "show"
  d.idx = 1
  d.show_timer = 30
  d.active = 0
  puzzle_data = d
  state = "puzzle"
end

local function update_puzzle_sequence()
  local d = puzzle_data
  if d.phase == "show" then
    d.show_timer = d.show_timer - 1
    if d.show_timer <= 0 then
      d.idx = d.idx + 1
      if d.idx > d.len then
        d.phase = "input"
        d.input = {}
        puzzle_cursor.x = 1
        d.active = 0
      else
        snd_tone(d.seq[d.idx])
        d.active = d.seq[d.idx]
        d.show_timer = 20
      end
    elseif d.show_timer == 20 and d.idx == 1 then
      snd_tone(d.seq[1])
      d.active = d.seq[1]
    end
    if d.show_timer < 5 then d.active = 0 end
    return false
  end

  if d.phase == "input" then
    if btnp("left") then puzzle_cursor.x = math.max(1, puzzle_cursor.x-1); snd_click() end
    if btnp("right") then puzzle_cursor.x = math.min(4, puzzle_cursor.x+1); snd_click() end
    if btnp("a") then
      d.input[#d.input+1] = puzzle_cursor.x
      snd_tone(puzzle_cursor.x)
      d.active = puzzle_cursor.x
      local idx = #d.input
      if d.input[idx] ~= d.seq[idx] then
        snd_fail()
        d.phase = "show"
        d.input = {}
        d.idx = 1
        d.show_timer = 40
        d.active = 0
        return false
      end
      if #d.input == d.len then
        if d.len >= d.max then
          return true
        else
          d.len = d.len + 1
          snd_ok()
          d.phase = "show"
          d.input = {}
          d.idx = 1
          d.show_timer = 40
          d.active = 0
        end
      end
    end
  end
  return false
end

local function draw_puzzle_sequence()
  local d = puzzle_data
  text_c("ANTENNA FREQUENCY", 2, LIT)
  text_c("Round "..(d.len-2).."/"..(d.max-2), 12, DRK)

  local ox = 24
  local oy = 30
  local bw, bh = 26, 26
  local gap = 4
  for i=1,4 do
    local px = ox + (i-1)*(bw+gap)
    local lit = (d.active == i)
    local col = lit and WHT or DRK
    rectf(S, px, oy, bw, bh, col)
    rect(S, px, oy, bw, bh, LIT)
    text_l(tostring(i), px+10, oy+9, lit and BLK or LIT)
    if d.phase == "input" and puzzle_cursor.x == i then
      rect(S, px-1, oy-1, bw+2, bh+2, WHT)
    end
  end

  if d.phase == "show" then
    text_c("Watch...", 68, LIT)
  else
    text_c("A:Press", 68, LIT)
  end
  -- progress dots
  for i=1,d.len do
    local done = i <= #d.input
    circf(S, 50 + i*8, 82, 2, done and WHT or DRK)
  end
end

---------- PUZZLE DISPATCH ----------
local puzzle_updates = {
  pattern = update_puzzle_pattern,
  combo = update_puzzle_combo,
  wires = update_puzzle_wires,
  tiles = update_puzzle_tiles,
  sequence = update_puzzle_sequence,
}
local puzzle_draws = {
  pattern = draw_puzzle_pattern,
  combo = draw_puzzle_combo,
  wires = draw_puzzle_wires,
  tiles = draw_puzzle_tiles,
  sequence = draw_puzzle_sequence,
}

---------- ROOM DEFINITIONS ----------
local rooms = {}

rooms.dark_room = {
  name = "Dark Room",
  ambient = "C2",
  actions = function()
    local a = {}
    if not flags.solved_pattern then
      a[#a+1] = {label="Examine wall panel", id="dark_puzzle"}
    else
      if not flags.has_light then
        a[#a+1] = {label="Take flashlight", id="dark_take"}
      end
      a[#a+1] = {label="Go to Hallway", id="go_hallway"}
    end
    a[#a+1] = {label="Examine walls", id="walls"}
    return a
  end,
}

rooms.hallway = {
  name = "Hallway",
  ambient = "D2",
  actions = function()
    local a = {}
    a[#a+1] = {label="Go to Dark Room", id="go_dark_room"}
    a[#a+1] = {label="Go to Lab", id="go_lab"}
    a[#a+1] = {label="Go to Office", id="go_office"}
    if flags.solved_combo_lab or has_item("fuse") then
      a[#a+1] = {label="Go to Basement", id="go_basement"}
    end
    if flags.solved_wires or has_item("badge") then
      a[#a+1] = {label="Go to Roof", id="go_roof"}
    end
    if flags.solved_sequence and has_item("evidence") then
      a[#a+1] = {label="Go to Vault", id="go_vault"}
    end
    a[#a+1] = {label="Try front door", id="front_door"}
    return a
  end,
}

rooms.lab = {
  name = "Laboratory",
  ambient = "E2",
  actions = function()
    local a = {}
    if not flags.solved_combo_lab then
      a[#a+1] = {label="Crack equipment lock", id="lab_puzzle"}
    else
      if not has_item("evidence") then
        a[#a+1] = {label="Take test results", id="lab_take_ev"}
      end
      if not has_item("fuse") then
        a[#a+1] = {label="Take spare fuse", id="lab_take_fuse"}
      end
    end
    a[#a+1] = {label="Read whiteboard", id="lab_board"}
    a[#a+1] = {label="Go to Hallway", id="go_hallway"}
    return a
  end,
}

rooms.office = {
  name = "Office",
  ambient = "F2",
  actions = function()
    local a = {}
    if not flags.solved_wires then
      a[#a+1] = {label="Fix circuit board", id="off_puzzle"}
    else
      if not has_item("badge") then
        a[#a+1] = {label="Take ID badge", id="off_take_badge"}
      end
      a[#a+1] = {label="Read unlocked files", id="off_files"}
    end
    a[#a+1] = {label="Look at computer", id="off_computer"}
    a[#a+1] = {label="Go to Hallway", id="go_hallway"}
    return a
  end,
}

rooms.basement = {
  name = "Basement",
  ambient = "A1",
  actions = function()
    local a = {}
    if not flags.solved_tiles and has_item("fuse") then
      a[#a+1] = {label="Restore power grid", id="bas_puzzle"}
    elseif not has_item("fuse") and not flags.solved_tiles then
      a[#a+1] = {label="Examine generator", id="bas_gen"}
    end
    if flags.solved_tiles then
      a[#a+1] = {label="Override lockdown", id="bas_override"}
      a[#a+1] = {label="Activate lockdown", id="bas_lockdown"}
    end
    a[#a+1] = {label="Search shelves", id="bas_shelves"}
    a[#a+1] = {label="Go to Hallway", id="go_hallway"}
    return a
  end,
}

rooms.roof = {
  name = "Rooftop",
  ambient = "G2",
  actions = function()
    local a = {}
    if not flags.solved_sequence then
      a[#a+1] = {label="Tune antenna freq", id="roof_puzzle"}
    else
      if not has_item("note1") then
        a[#a+1] = {label="Take decoded memo", id="roof_take_memo"}
      end
    end
    a[#a+1] = {label="Look at city", id="roof_city"}
    a[#a+1] = {label="Go to Hallway", id="go_hallway"}
    return a
  end,
}

rooms.vault = {
  name = "The Vault",
  ambient = "C1",
  actions = function()
    local a = {}
    if not flags.read_vault then
      a[#a+1] = {label="Read classified docs", id="vault_docs"}
    end
    a[#a+1] = {label="Access terminal", id="vault_terminal"}
    a[#a+1] = {label="Go to Hallway", id="go_hallway"}
    return a
  end,
}

---------- ACTION HANDLER ----------
local function do_action(action_id)
  -- Navigation
  if action_id:sub(1,3) == "go_" then
    local target = action_id:sub(4)
    change_room(target)
    return
  end

  -- Puzzle triggers
  if action_id == "dark_puzzle" then
    init_puzzle_pattern()
    return
  elseif action_id == "lab_puzzle" then
    init_puzzle_combo()
    return
  elseif action_id == "off_puzzle" then
    init_puzzle_wires()
    return
  elseif action_id == "bas_puzzle" then
    remove_item("fuse")
    init_puzzle_tiles()
    return
  elseif action_id == "roof_puzzle" then
    init_puzzle_sequence()
    return

  -- Dark Room
  elseif action_id == "dark_take" then
    add_item("flashlight"); add_item("key")
    flags.has_light = true
    msg = "Flashlight and a brass key\nfound behind the panel!"
  elseif action_id == "walls" then
    msg = "Scratches on the wall:\n\"THEY ARE WATCHING. DON'T TRUST.\""
    snd_danger()

  -- Hallway
  elseif action_id == "front_door" then
    if has_item("key") and not flags.lockdown_triggered then
      ending_id = "escape"
      state = "ending"
      ending_timer = 0
      snd_solve()
      return
    elseif flags.lockdown_triggered then
      msg = "The door is sealed. Steel\nbolts engaged. No way out."
      snd_danger()
    else
      msg = "Locked. Needs a key.\nSolve the Dark Room puzzle."
    end

  -- Lab
  elseif action_id == "lab_take_ev" then
    add_item("evidence")
    flags.found_evidence = true
    msg = "Test results with YOUR name.\nSubject 7: Memory Wipe Protocol."
  elseif action_id == "lab_take_fuse" then
    add_item("fuse")
    msg = "Spare fuse from the panel.\nMight restore basement power."
  elseif action_id == "lab_board" then
    msg = "Formulas... diagrams of a\nbrain. \"Phase 3: Permanent.\""
    snd_danger()

  -- Office
  elseif action_id == "off_take_badge" then
    add_item("badge")
    msg = "ID badge unlocked!\n\"Dr. Null - Level 5 Access\""
  elseif action_id == "off_files" then
    flags.saw_files = true
    msg = "Classified files! A conspiracy\nspanning years. A hidden vault..."
    snd_ok()
  elseif action_id == "off_computer" then
    if flags.saw_files then
      msg = "Terminal shows active subjects.\nYou are Subject 07."
    else
      msg = "Password protected. Fix the\ncircuit board first."
    end

  -- Basement
  elseif action_id == "bas_gen" then
    msg = "Dead generator. Fuse slot\nis empty. Find a fuse."
  elseif action_id == "bas_override" then
    msg = "Lockdown DISENGAGED.\nAll doors unlocked."
    flags.lockdown_triggered = false
    snd_note(0, "E4", 0.15)
  elseif action_id == "bas_lockdown" then
    flags.lockdown_triggered = true
    ending_id = "trapped"
    state = "ending"
    ending_timer = 0
    snd_noise(0, 0.5)
    snd_noise(1, 0.5)
    return
  elseif action_id == "bas_shelves" then
    msg = "Old supplies. Dust everywhere.\nA label reads: \"SUBJECT HOLDING\""

  -- Roof
  elseif action_id == "roof_take_memo" then
    add_item("note1")
    msg = "Decoded memo: \"Broadcast\nfrequency controls subjects.\""
  elseif action_id == "roof_city" then
    msg = "A sprawling city below. You\ndon't recognize anything."

  -- Vault
  elseif action_id == "vault_docs" then
    flags.read_vault = true
    msg = "Full records of the program.\nNames, dates, methods. Proof."
    snd_ok()
  elseif action_id == "vault_terminal" then
    if flags.read_vault and has_item("evidence") and has_item("note1") then
      ending_id = "truth"
      state = "ending"
      ending_timer = 0
      snd_note(0, "C5", 0.4)
      snd_note(1, "E5", 0.4)
      snd_note(0, "G5", 0.4)
      return
    elseif flags.read_vault then
      msg = "Need more evidence to\ntransmit a credible report."
    else
      msg = "Terminal active. Read the\ndocuments first."
    end
  end

  msg_timer = 180
end

---------- PUZZLE COMPLETION CALLBACKS ----------
local function on_puzzle_solved()
  snd_solve()
  if puzzle_id == "pattern" then
    flags.solved_pattern = true
    msg = "Panel opens! A flashlight\nand key hidden behind it."
    msg_timer = 120
  elseif puzzle_id == "combo" then
    flags.solved_combo_lab = true
    msg = "Lock cracked! Cabinet open.\nEvidence and fuse inside."
    msg_timer = 120
  elseif puzzle_id == "wires" then
    flags.solved_wires = true
    msg = "Circuit restored! Filing\ncabinet and badge unlocked."
    msg_timer = 120
  elseif puzzle_id == "tiles" then
    flags.solved_tiles = true
    flags.power_on = true
    msg = "Power grid restored!\nGenerator humming. Controls live."
    msg_timer = 120
  elseif puzzle_id == "sequence" then
    flags.solved_sequence = true
    msg = "Frequency decoded! Antenna\ntransmitting. Memo available."
    msg_timer = 120
  end
  puzzle_id = nil
  state = "play"
end

---------- ROOM TRANSITIONS ----------
change_room = function(target)
  fade_target_room = target
  fade = 10
  fade_dir = 1
  snd_step()
end

local function finish_room_change()
  room = fade_target_room
  fade_target_room = nil
  menu_cursor = 0
  fade = 10
  fade_dir = -1
  msg = rooms[room].name
  msg_timer = 90
  snd_ambient(rooms[room].ambient or "C2")
end

---------- ROOM ART ----------
local function draw_dark_room()
  rectf(S, 0, 0, W, 68, BLK)
  if flags.has_light then
    for i = 0, 30 do
      local spread = i * 0.8
      local bright = i < 15 and LIT or DRK
      line(S, 80, 10, 60 - spread, 10 + i * 2, bright)
      line(S, 80, 10, 100 + spread, 10 + i * 2, bright)
    end
    rectf(S, 50, 40, 60, 20, DRK)
    rect(S, 50, 40, 60, 20, LIT)
  else
    local flicker = tick % 60 < 30 and DRK or BLK
    rect(S, 50, 40, 60, 20, flicker)
    text_c("...darkness...", 30, DRK)
  end
  if flags.solved_pattern then
    rectf(S, 20, 15, 16, 16, LIT)
    rect(S, 20, 15, 16, 16, WHT)
    text_l("OK", 24, 20, WHT)
  end
end

local function draw_hallway()
  rectf(S, 0, 0, W, 68, BLK)
  rectf(S, 40, 10, 80, 50, DRK)
  for i = 0, 4 do
    line(S, 30 + i * 5, 60, 60 + i * 4, 10, DRK)
    line(S, 130 - i * 5, 60, 100 - i * 4, 10, DRK)
  end
  rect(S, 20, 25, 18, 35, LIT)
  rect(S, 122, 25, 18, 35, LIT)
  rectf(S, 65, 15, 30, 40, DRK)
  rect(S, 65, 15, 30, 40, LIT)
  pix(S, 35, 42, WHT)
  pix(S, 125, 42, WHT)
  pix(S, 92, 35, WHT)
  rectf(S, 72, 18, 16, 25, LIT)
  rect(S, 72, 18, 16, 25, WHT)
end

local function draw_lab()
  rectf(S, 0, 0, W, 68, BLK)
  rectf(S, 10, 35, 60, 8, DRK); rectf(S, 90, 35, 60, 8, DRK)
  rect(S, 10, 35, 60, 8, LIT); rect(S, 90, 35, 60, 8, LIT)
  rectf(S, 15, 20, 12, 15, DRK); rect(S, 15, 20, 12, 15, LIT)
  rectf(S, 35, 22, 8, 13, DRK); rect(S, 35, 22, 8, 13, LIT)
  rectf(S, 100, 15, 20, 18, DRK); rect(S, 100, 15, 20, 18, LIT)
  if tick % 40 < 20 then pix(S, 110, 28, WHT) end
  rectf(S, 50, 5, 40, 25, LIT); rect(S, 50, 5, 40, 25, WHT)
  if flags.solved_combo_lab then
    text_l("OPEN", 55, 10, WHT)
  end
end

local function draw_office()
  rectf(S, 0, 0, W, 68, BLK)
  rectf(S, 30, 38, 70, 14, DRK); rect(S, 30, 38, 70, 14, LIT)
  rectf(S, 55, 20, 25, 18, DRK); rect(S, 55, 20, 25, 18, LIT)
  if flags.saw_files then
    rectf(S, 57, 22, 21, 14, LIT)
    text(S, "DATA", 60, 26, WHT)
  end
  rectf(S, 130, 20, 20, 40, DRK); rect(S, 130, 20, 20, 40, LIT)
  rect(S, 132, 22, 16, 10, LIT); rect(S, 132, 34, 16, 10, LIT)
  line(S, 15, 15, 15, 58, LIT); line(S, 10, 15, 20, 15, LIT)
  if flags.solved_wires then
    rectf(S, 8, 8, 16, 8, LIT)
    text_l("OK", 11, 9, WHT)
  end
end

local function draw_basement()
  rectf(S, 0, 0, W, 68, BLK)
  rectf(S, 50, 25, 40, 30, DRK); rect(S, 50, 25, 40, 30, LIT)
  line(S, 55, 25, 55, 8, LIT); line(S, 85, 25, 85, 8, LIT)
  line(S, 55, 8, 85, 8, LIT)
  if flags.power_on then
    rectf(S, 65, 35, 10, 10, LIT); pix(S, 70, 40, WHT)
  else
    rectf(S, 65, 35, 10, 10, BLK); rect(S, 65, 35, 10, 10, DRK)
  end
  for i = 0, 2 do rectf(S, 5, 20 + i * 16, 35, 3, DRK) end
  rectf(S, 120, 20, 35, 3, DRK); rectf(S, 120, 36, 35, 3, DRK)
end

local function draw_roof()
  rectf(S, 0, 0, W, 68, BLK)
  for i = 1, 12 do
    local sx = (i * 37 + tick) % W
    local sy = (i * 13) % 30
    pix(S, sx, sy, (i % 2 == 0) and WHT or LIT)
  end
  rectf(S, 0, 40, 25, 28, DRK); rectf(S, 28, 45, 15, 23, DRK)
  rectf(S, 46, 35, 20, 33, DRK); rectf(S, 70, 48, 18, 20, DRK)
  rectf(S, 92, 38, 22, 30, DRK); rectf(S, 118, 42, 15, 26, DRK)
  rectf(S, 136, 50, 24, 18, DRK)
  for i = 0, 3 do
    for j = 0, 2 do
      if (i + j + tick / 30) % 3 < 2 then pix(S, 50 + i * 4, 38 + j * 6, LIT) end
    end
  end
  line(S, 80, 10, 80, 48, LIT); line(S, 75, 15, 85, 15, LIT)
  if tick % 30 < 15 then pix(S, 80, 10, WHT) end
  line(S, 0, 60, W, 60, LIT)
  for i = 0, 10 do line(S, i * 16, 60, i * 16, 67, DRK) end
end

local function draw_vault()
  rectf(S, 0, 0, W, 68, BLK)
  rect(S, 5, 5, 150, 58, LIT)
  for i = 0, 4 do
    rectf(S, 15 + i * 28, 12, 20, 40, DRK)
    rect(S, 15 + i * 28, 12, 20, 40, LIT)
    for j = 0, 3 do rect(S, 17 + i * 28, 14 + j * 10, 16, 8, DRK) end
  end
  rectf(S, 60, 55, 30, 10, DRK); rect(S, 60, 55, 30, 10, LIT)
  if tick % 20 < 10 then pix(S, 75, 59, WHT) end
end

local room_art = {
  dark_room = draw_dark_room, hallway = draw_hallway, lab = draw_lab,
  office = draw_office, basement = draw_basement, roof = draw_roof,
  vault = draw_vault,
}

---------- DRAWING HELPERS ----------
local function draw_inventory()
  local iy = H - 11
  rectf(S, 0, iy, W, 11, BLK)
  line(S, 0, iy, W, iy, DRK)
  for i = 1, 6 do
    local ix = (i - 1) * 26 + 3
    rect(S, ix, iy + 1, 24, 9, DRK)
    if inv[i] then
      text(S, ITEM_NAMES[inv[i]] or inv[i], ix + 2, iy + 2, LIT)
    end
  end
end

local function draw_message()
  if msg_timer > 0 and msg ~= "" then
    local bx, by = 4, 68
    local bw, bh = W - 8, 20
    draw_box(bx, by, bw, bh, LIT, BLK)
    local y = by + 3
    for line_str in msg:gmatch("[^\n]+") do
      text(S, line_str, bx + 4, y, WHT)
      y = y + 8
    end
  end
end

local function draw_action_menu()
  local actions = rooms[room].actions()
  local ax, ay = 4, 68
  local aw = W - 8
  if msg_timer > 0 then ay = 88 end
  local menu_h = #actions * 9 + 4
  local max_y = H - 12
  if ay + menu_h > max_y then ay = max_y - menu_h end
  for i, a in ipairs(actions) do
    local y = ay + (i - 1) * 9
    local sel = (menu_cursor == i - 1)
    if sel then rectf(S, ax, y, aw, 9, DRK) end
    local prefix = sel and "> " or "  "
    text(S, prefix .. a.label, ax + 2, y + 1, sel and WHT or LIT)
  end
end

local function apply_fade()
  if fade <= 0 then return end
  local alpha = fade / 10
  if alpha > 0.7 then
    rectf(S, 0, 0, W, H, BLK)
  elseif alpha > 0.3 then
    for y = 0, H - 1, 2 do
      for x = 0, W - 1, 2 do pix(S, x, y, BLK) end
    end
  end
end

---------- TITLE SCREEN ----------
local function draw_title()
  rectf(S, 0, 0, W, H, BLK)
  local flick = tick % 90
  if flick < 70 or flick > 80 then text_c("THE DARK ROOM", 16, WHT) end
  text_c("FRACTURED MEMORIES", 28, LIT)
  text_c("- Puzzle Edition -", 38, DRK)
  if flick < 60 then rect(S, 10, 10, 140, 36, DRK) end
  -- eye
  circ(S, 80, 58, 12, LIT); circ(S, 80, 58, 8, DRK)
  rectf(S, 76, 56, 8, 4, WHT); pix(S, 80, 58, BLK)
  text_c("PRESS START", 82, (tick % 40 < 25) and WHT or DRK)
  text_c("A:Act  B:Submit  D-Pad:Move", 96, DRK)
  -- puzzle count hint
  text_c("5 puzzles. 3 endings.", 108, DRK)
end

---------- ENDING SCREENS ----------
local function draw_ending_escape()
  rectf(S, 0, 0, W, H, BLK)
  for i = 0, 30 do
    local c = i < 10 and WHT or (i < 20 and LIT or DRK)
    line(S, 0, 40 + i, W, 40 + i, c)
  end
  rectf(S, 0, 71, W, H - 71, DRK)
  text_c("ENDING: ESCAPE", 10, WHT)
  text_c("You step into the dawn.", 25, LIT)
  text_c("Free, but memories lost.", 80, LIT)
  text_c("The truth remains buried.", 90, DRK)
  if ending_timer > 120 then
    text_c("PRESS START", 108, (tick % 40 < 25) and WHT or BLK)
  end
end

local function draw_ending_trapped()
  rectf(S, 0, 0, W, H, BLK)
  local door_y = clamp(ending_timer * 2, 0, 60)
  rectf(S, 30, 0, 100, door_y, LIT)
  rect(S, 30, 0, 100, door_y, WHT)
  if door_y > 30 then
    for i = 0, 3 do
      rectf(S, 28, 10 + i * 14, 6, 4, WHT)
      rectf(S, 126, 10 + i * 14, 6, 4, WHT)
    end
  end
  text_c("ENDING: TRAPPED", 65, WHT)
  text_c("Lockdown engaged.", 78, LIT)
  text_c("The steel seals forever.", 88, LIT)
  text_c("You are Subject 07. Again.", 98, DRK)
  if ending_timer > 120 then
    text_c("PRESS START", 108, (tick % 40 < 25) and WHT or BLK)
  end
end

local function draw_ending_truth()
  rectf(S, 0, 0, W, H, BLK)
  for i = 1, 20 do
    local sx = (i * 19 + tick * 2) % W
    local sy = (i * 7 + tick) % H
    local ch = string.char(48 + (tick + i) % 26)
    text(S, ch, sx, sy, DRK)
  end
  if ending_timer > 30 then
    draw_box(20, 20, 120, 60, WHT, BLK)
    text_c("ENDING: THE TRUTH", 25, WHT)
    text_c("Transmission sent.", 38, LIT)
    text_c("Evidence broadcast to", 48, LIT)
    text_c("every screen in the city.", 56, LIT)
    text_c("Project DARK ROOM exposed.", 68, WHT)
  end
  if ending_timer > 60 then
    text_c("You remember everything.", 85, LIT)
    text_c("You are free.", 95, WHT)
  end
  if ending_timer > 150 then
    text_c("PRESS START", 108, (tick % 40 < 25) and WHT or BLK)
  end
end

---------- DEMO MODE ----------
local demo_actions = {
  {wait=30, room="dark_room", puzzle="pattern"},
  {wait=60, auto_solve="pattern"},
  {wait=30, room="dark_room", act="dark_take"},
  {wait=45, room="lab", puzzle="combo"},
  {wait=60, auto_solve="combo"},
  {wait=90},
}

local function update_demo()
  demo_timer = demo_timer + 1
  if demo_step > #demo_actions then
    state = "title"; idle_timer = 0; return
  end
  local da = demo_actions[demo_step]
  if demo_timer >= da.wait then
    if da.room and room ~= da.room then
      room = da.room
      menu_cursor = 0
      msg = rooms[room].name
      msg_timer = 60
    end
    if da.puzzle then
      -- show puzzle briefly
      if da.puzzle == "pattern" then init_puzzle_pattern()
      elseif da.puzzle == "combo" then init_puzzle_combo()
      end
      state = "demo" -- stay in demo
    end
    if da.auto_solve then
      -- auto-solve for demo
      if da.auto_solve == "pattern" then flags.solved_pattern = true end
      if da.auto_solve == "combo" then flags.solved_combo_lab = true end
      puzzle_id = nil
      msg = "PUZZLE SOLVED!"; msg_timer = 60
    end
    if da.act then
      do_action(da.act)
    end
    demo_step = demo_step + 1
    demo_timer = 0
  end
end

---------- GAME INIT ----------
init_game = function()
  room = "dark_room"
  menu_cursor = 0
  inv = {}
  flags = {}
  msg = "You wake in darkness.\nHead pounding. No memories."
  msg_timer = 180
  fade = 10
  fade_dir = -1
  ending_id = nil
  ending_timer = 0
  puzzle_id = nil
  puzzle_data = {}
  puzzle_cursor = {}
  flash_t = 0
end

---------- MAIN CALLBACKS ----------
function _init()
  mode(2)
end

function _start()
  state = "title"
  tick = 0
  idle_timer = 0
  init_game()
end

function _update()
  tick = tick + 1
  flash_t = math.max(0, flash_t - 1)

  -- Fade logic
  if fade > 0 then
    if fade_dir > 0 then
      fade = fade - 1
      if fade <= 0 and fade_target_room then finish_room_change() end
    elseif fade_dir < 0 then
      fade = fade - 1
    end
  end

  if state == "title" then
    idle_timer = idle_timer + 1
    if btnp("start") or btnp("a") then
      init_game()
      state = "play"
      idle_timer = 0
      snd_ambient(rooms[room].ambient or "C2")
      return
    end
    if idle_timer >= IDLE_MAX then
      state = "demo"
      demo_step = 1
      demo_timer = 0
      init_game()
      return
    end

  elseif state == "demo" then
    update_demo()
    if btnp("start") or btnp("a") then
      state = "title"; idle_timer = 0; init_game()
    end

  elseif state == "puzzle" then
    -- B cancels puzzle in demo, but in play we use B for submit
    if puzzle_id and puzzle_updates[puzzle_id] then
      local solved = puzzle_updates[puzzle_id]()
      if solved then on_puzzle_solved() end
    end

  elseif state == "play" then
    if fade > 0 then return end
    if btnp("start") or btnp("select") then state = "paused"; return end

    if msg_timer > 0 then
      msg_timer = msg_timer - 1
      if btnp("a") then msg_timer = 0 end
      return
    end

    local actions = rooms[room].actions()
    local num = #actions
    if num > 0 then
      if btnp("up") then menu_cursor = (menu_cursor - 1) % num; snd_click() end
      if btnp("down") then menu_cursor = (menu_cursor + 1) % num; snd_click() end
      if btnp("a") then
        menu_cursor = clamp(menu_cursor, 0, num - 1)
        do_action(actions[menu_cursor + 1].id)
        snd_note(0, "A4", 0.03)
      end
    end

    if tick % 300 == 0 then snd_ambient(rooms[room].ambient or "C2") end

  elseif state == "paused" then
    if btnp("start") or btnp("select") then state = "play" end

  elseif state == "ending" then
    ending_timer = ending_timer + 1
    local threshold = ending_id == "truth" and 150 or 120
    if ending_timer > threshold and (btnp("start") or btnp("a")) then
      state = "title"; idle_timer = 0; init_game()
    end
  end
end

function _draw()
  S = screen()

  if state == "title" then
    draw_title()
    return
  end

  if state == "ending" then
    if ending_id == "escape" then draw_ending_escape()
    elseif ending_id == "trapped" then draw_ending_trapped()
    elseif ending_id == "truth" then draw_ending_truth()
    end
    return
  end

  -- Puzzle screen
  if state == "puzzle" then
    rectf(S, 0, 0, W, H, BLK)
    if puzzle_id and puzzle_draws[puzzle_id] then
      puzzle_draws[puzzle_id]()
    end
    -- flash on error
    if flash_t > 0 and flash_t%4 < 2 then rect(S, 0, 0, W-1, H-1, WHT) end
    -- solved count
    local sc = 0
    if flags.solved_pattern then sc=sc+1 end
    if flags.solved_combo_lab then sc=sc+1 end
    if flags.solved_wires then sc=sc+1 end
    if flags.solved_tiles then sc=sc+1 end
    if flags.solved_sequence then sc=sc+1 end
    text_l("Puzzles:"..sc.."/5", 2, H-8, DRK)
    return
  end

  -- Game / Demo / Paused
  rectf(S, 0, 0, W, H, BLK)
  local art_fn = room_art[room]
  if art_fn then art_fn() end

  -- HUD
  text(S, rooms[room].name, 2, 0, LIT)

  draw_message()
  if msg_timer <= 0 and state ~= "demo" then draw_action_menu() end
  draw_inventory()
  apply_fade()

  if state == "paused" then
    rectf(S, 0, 0, W, H, BLK)
    draw_box(30, 35, 100, 50, WHT, BLK)
    text_c("PAUSED", 42, WHT)
    text_c("START to resume", 55, LIT)
    local sc = 0
    if flags.solved_pattern then sc=sc+1 end
    if flags.solved_combo_lab then sc=sc+1 end
    if flags.solved_wires then sc=sc+1 end
    if flags.solved_tiles then sc=sc+1 end
    if flags.solved_sequence then sc=sc+1 end
    text_c("Puzzles: "..sc.."/5  Items: "..#inv.."/6", 68, DRK)
  end

  if state == "demo" then
    rectf(S, 0, 0, W, 10, BLK)
    text_c("DEMO - PRESS START", 1, (tick % 40 < 25) and WHT or DRK)
  end
end
