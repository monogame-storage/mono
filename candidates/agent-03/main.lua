-- THE DARK ROOM: PUZZLES
-- Five rooms, five puzzle mechanics. Solve to escape.

-- Compatibility shim: map PICO-8 style API to Mono API
local _scr
local _key_map = {[0]="left",[1]="right",[2]="up",[3]="down",[4]="a",[5]="b"}
local _orig_btnp = btnp
local _orig_btn = btn
btnp = function(k)
  if type(k) == "number" then k = _key_map[k] or "a" end
  return _orig_btnp(k)
end
btn = function(k)
  if type(k) == "number" then k = _key_map[k] or "a" end
  return _orig_btn(k)
end
local _orig_cls = cls
cls = function(c) _scr = _scr or screen(); _orig_cls(_scr, c) end
local _orig_rectf = rectf
rectfill = function(x1,y1,x2,y2,c) _scr = _scr or screen(); _orig_rectf(_scr,x1,y1,x2,y2,c) end
local _orig_rect = rect
rect = function(x1,y1,x2,y2,c) _scr = _scr or screen(); _orig_rect(_scr,x1,y1,x2,y2,c) end
local _orig_circf = circf
circfill = function(cx,cy,r,c) _scr = _scr or screen(); _orig_circf(_scr,cx,cy,r,c) end
local _orig_line = line
line = function(x1,y1,x2,y2,c) _scr = _scr or screen(); _orig_line(_scr,x1,y1,x2,y2,c) end
local _orig_text = text
print = function(str,x,y,c) _scr = _scr or screen(); _orig_text(_scr,tostring(str),x,y,c) end
poke = function() end  -- no-op: palette poke not supported

local W, H = 160, 120
local scene = "title"
local room = 1
local MAX_ROOMS = 5
local cursor = {x=1, y=1}
local flash_t = 0
local msg = ""
local msg_timer = 0
local solved = {false,false,false,false,false}
local paused = false
local demo_mode = false
local idle_timer = 0
local DEMO_IDLE = 300
local demo_step = 0
local demo_delay = 0
local frame = 0
local trans_timer = 0
local trans_from = ""
local sfx_queue = {}

-- clue fragments revealed per room
local clues = {
  "YOU WERE",
  "NEVER",
  "TRULY",
  "LOCKED",
  "IN."
}

------------------------------------------------------------
-- SOUND HELPERS (Picotron sfx synthesis)
------------------------------------------------------------
local function snd_click()
  sfx_queue[#sfx_queue+1] = {freq=800, dur=2, vol=0.3}
end
local function snd_ok()
  sfx_queue[#sfx_queue+1] = {freq=500, dur=4, vol=0.4}
  sfx_queue[#sfx_queue+1] = {freq=700, dur=4, vol=0.4}
end
local function snd_fail()
  sfx_queue[#sfx_queue+1] = {freq=300, dur=6, vol=0.3}
  sfx_queue[#sfx_queue+1] = {freq=200, dur=8, vol=0.3}
end
local function snd_solve()
  sfx_queue[#sfx_queue+1] = {freq=440, dur=4, vol=0.5}
  sfx_queue[#sfx_queue+1] = {freq=554, dur=4, vol=0.5}
  sfx_queue[#sfx_queue+1] = {freq=659, dur=4, vol=0.5}
  sfx_queue[#sfx_queue+1] = {freq=880, dur=8, vol=0.5}
end
local function snd_tone(idx)
  local freqs = {262, 330, 392, 523, 587}
  sfx_queue[#sfx_queue+1] = {freq=freqs[idx] or 440, dur=8, vol=0.4}
end

local function play_sounds()
  for i, s in ipairs(sfx_queue) do
    -- use poke-based beep if available, otherwise silent
    if synth then
      pcall(function()
        synth(0, {
          freq=s.freq,
          vol=s.vol,
          waveform=1,
          duration=s.dur/30
        })
      end)
    end
  end
  sfx_queue = {}
end

------------------------------------------------------------
-- ROOM 1: COMBINATION LOCK
------------------------------------------------------------
local combo = {}
local combo_target = {}
local combo_cols = 4

local function init_combo()
  combo = {0,0,0,0}
  combo_target = {}
  for i=1,combo_cols do
    combo_target[i] = math.random(0,9)
  end
  cursor.x = 1
  cursor.y = 1
end

local function update_combo()
  if btnp(0) then cursor.x = math.max(1, cursor.x-1); snd_click() end
  if btnp(1) then cursor.x = math.min(combo_cols, cursor.x+1); snd_click() end
  if btnp(2) then combo[cursor.x] = (combo[cursor.x]+1)%10; snd_click() end
  if btnp(3) then combo[cursor.x] = (combo[cursor.x]-1)%10; snd_click() end
  if btnp(4) then -- A: check
    local ok = true
    for i=1,combo_cols do
      if combo[i] ~= combo_target[i] then ok=false; break end
    end
    if ok then return true else snd_fail(); flash_t=10 end
  end
  return false
end

local function draw_combo()
  -- hint: show sum of digits on wall
  local s = 0
  for i=1,combo_cols do s = s + combo_target[i] end
  print("HINT: SUM="..s, 4, 4, 2)
  -- show even/odd pattern
  local hint2 = ""
  for i=1,combo_cols do
    hint2 = hint2 .. (combo_target[i]%2==0 and "E" or "O")
  end
  print("PARITY: "..hint2, 4, 14, 2)

  local ox = 40
  local oy = 50
  for i=1,combo_cols do
    local sel = (i == cursor.x)
    local c = sel and 3 or 2
    rectfill(ox+(i-1)*22, oy, ox+(i-1)*22+16, oy+20, 1)
    rect(ox+(i-1)*22, oy, ox+(i-1)*22+16, oy+20, c)
    -- digit
    print(tostring(combo[i]), ox+(i-1)*22+5, oy+7, 3)
    if sel then
      -- arrows
      print("\x18", ox+(i-1)*22+5, oy-8, 3)
      print("\x19", ox+(i-1)*22+5, oy+23, 3)
    end
  end
  print("\x97 CHECK", 58, 85, 2)
end

------------------------------------------------------------
-- ROOM 2: SLIDING TILES (3x3, position 1-8 + empty)
------------------------------------------------------------
local tiles = {}
local tile_empty = {x=3, y=3}

local function init_tiles()
  -- goal: tiles 1-8 in order, empty at 3,3
  tiles = {}
  for i=1,8 do
    tiles[i] = {val=i, x=((i-1)%3)+1, y=math.floor((i-1)/3)+1}
  end
  tile_empty = {x=3, y=3}
  -- shuffle with valid moves
  for i=1,60 do
    local dirs = {{-1,0},{1,0},{0,-1},{0,1}}
    local d = dirs[math.random(1,4)]
    local nx, ny = tile_empty.x+d[1], tile_empty.y+d[2]
    if nx>=1 and nx<=3 and ny>=1 and ny<=3 then
      for _, t in ipairs(tiles) do
        if t.x==nx and t.y==ny then
          t.x, t.y = tile_empty.x, tile_empty.y
          tile_empty.x, tile_empty.y = nx, ny
          break
        end
      end
    end
  end
  cursor.x, cursor.y = 2, 2
end

local function update_tiles()
  if btnp(0) then cursor.x = math.max(1, cursor.x-1); snd_click() end
  if btnp(1) then cursor.x = math.min(3, cursor.x+1); snd_click() end
  if btnp(2) then cursor.y = math.max(1, cursor.y-1); snd_click() end
  if btnp(3) then cursor.y = math.min(3, cursor.y+1); snd_click() end
  if btnp(4) then -- A: try to slide
    -- if cursor is adjacent to empty, swap
    local dx = math.abs(cursor.x - tile_empty.x)
    local dy = math.abs(cursor.y - tile_empty.y)
    if (dx+dy)==1 then
      for _, t in ipairs(tiles) do
        if t.x==cursor.x and t.y==cursor.y then
          t.x, t.y = tile_empty.x, tile_empty.y
          tile_empty.x, tile_empty.y = cursor.x, cursor.y
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
      if tiles[i].x~=gx or tiles[i].y~=gy then ok=false; break end
    end
    if ok then return true end
  end
  return false
end

local function draw_tiles()
  print("ARRANGE 1-8", 44, 4, 2)
  local ox, oy = 44, 20
  local sz = 22
  for gy=1,3 do
    for gx=1,3 do
      local px = ox+(gx-1)*sz
      local py = oy+(gy-1)*sz
      rectfill(px, py, px+sz-2, py+sz-2, 1)
      rect(px, py, px+sz-2, py+sz-2, 2)
    end
  end
  for _, t in ipairs(tiles) do
    local px = ox+(t.x-1)*sz
    local py = oy+(t.y-1)*sz
    rectfill(px+1, py+1, px+sz-3, py+sz-3, 2)
    print(tostring(t.val), px+7, py+7, 3)
  end
  -- cursor
  local cx = ox+(cursor.x-1)*sz
  local cy = oy+(cursor.y-1)*sz
  rect(cx-1, cy-1, cx+sz-1, cy+sz-1, 3)

  print("\x97 SLIDE", 58, 92, 2)
end

------------------------------------------------------------
-- ROOM 3: WIRE CONNECT (match pairs on a 5x5 grid)
------------------------------------------------------------
local wire_grid = {}
local wire_pairs = {}
local wire_sel = nil
local WIRE_SZ = 5

local function init_wires()
  wire_grid = {}
  for y=1,WIRE_SZ do
    wire_grid[y] = {}
    for x=1,WIRE_SZ do
      wire_grid[y][x] = {kind=0, connected=false}
    end
  end
  -- place 4 pairs of endpoints
  wire_pairs = {}
  local spots = {}
  for y=1,WIRE_SZ do for x=1,WIRE_SZ do spots[#spots+1]={x=x,y=y} end end
  for i=#spots,2,-1 do
    local j=math.random(1,i)
    spots[i], spots[j] = spots[j], spots[i]
  end
  for i=1,4 do
    local a = spots[i*2-1]
    local b = spots[i*2]
    wire_grid[a.y][a.x].kind = i
    wire_grid[b.y][b.x].kind = i
    wire_pairs[i] = {a=a, b=b, done=false}
  end
  wire_sel = nil
  cursor.x, cursor.y = 1, 1
end

local function update_wires()
  if btnp(0) then cursor.x = math.max(1, cursor.x-1); snd_click() end
  if btnp(1) then cursor.x = math.min(WIRE_SZ, cursor.x+1); snd_click() end
  if btnp(2) then cursor.y = math.max(1, cursor.y-1); snd_click() end
  if btnp(3) then cursor.y = math.min(WIRE_SZ, cursor.y+1); snd_click() end
  if btnp(4) then
    local cell = wire_grid[cursor.y][cursor.x]
    if cell.kind > 0 then
      if wire_sel == nil then
        wire_sel = {x=cursor.x, y=cursor.y, kind=cell.kind}
        snd_click()
      else
        if cell.kind == wire_sel.kind and (cursor.x~=wire_sel.x or cursor.y~=wire_sel.y) then
          wire_pairs[cell.kind].done = true
          snd_ok()
          wire_sel = nil
          -- check all done
          local ok = true
          for _, p in ipairs(wire_pairs) do
            if not p.done then ok=false; break end
          end
          if ok then return true end
        else
          snd_fail()
          wire_sel = nil
        end
      end
    end
  end
  if btnp(5) then wire_sel = nil end -- B cancel
  return false
end

local function draw_wires()
  print("MATCH THE PAIRS", 36, 4, 2)
  local ox, oy = 40, 18
  local cs = 16
  -- grid
  for y=1,WIRE_SZ do
    for x=1,WIRE_SZ do
      local px = ox+(x-1)*cs
      local py = oy+(y-1)*cs
      rect(px, py, px+cs-2, py+cs-2, 1)
      local cell = wire_grid[y][x]
      if cell.kind > 0 then
        local col = cell.kind <= 2 and 2 or 3
        if wire_pairs[cell.kind].done then col = 1 end
        circfill(px+cs/2-1, py+cs/2-1, 4, col)
        print(tostring(cell.kind), px+cs/2-2, py+cs/2-2, 0)
      end
    end
  end
  -- draw connections
  for _, p in ipairs(wire_pairs) do
    if p.done then
      local ax = ox+(p.a.x-1)*cs+cs/2-1
      local ay = oy+(p.a.y-1)*cs+cs/2-1
      local bx = ox+(p.b.x-1)*cs+cs/2-1
      local by = oy+(p.b.y-1)*cs+cs/2-1
      line(ax, ay, bx, by, 2)
    end
  end
  -- cursor
  local cx = ox+(cursor.x-1)*cs
  local cy = oy+(cursor.y-1)*cs
  rect(cx-1, cy-1, cx+cs-1, cy+cs-1, 3)
  -- selection indicator
  if wire_sel then
    local sx = ox+(wire_sel.x-1)*cs
    local sy = oy+(wire_sel.y-1)*cs
    rect(sx-1, sy-1, sx+cs-1, sy+cs-1, 3)
  end
  print("\x97 SELECT  \x8e CANCEL", 22, 102, 2)
end

------------------------------------------------------------
-- ROOM 4: PATTERN MATCH (reproduce a flashing grid pattern)
------------------------------------------------------------
local pat_target = {}
local pat_player = {}
local pat_show = true
local pat_timer = 0
local PAT_SZ = 4

local function init_pattern()
  pat_target = {}
  pat_player = {}
  for y=1,PAT_SZ do
    pat_target[y] = {}
    pat_player[y] = {}
    for x=1,PAT_SZ do
      pat_target[y][x] = math.random() < 0.4 and 1 or 0
      pat_player[y][x] = 0
    end
  end
  pat_show = true
  pat_timer = 90 -- show for 3 seconds
  cursor.x, cursor.y = 1, 1
end

local function update_pattern()
  if pat_show then
    pat_timer = pat_timer - 1
    if pat_timer <= 0 then
      pat_show = false
    end
    return false
  end
  if btnp(0) then cursor.x = math.max(1, cursor.x-1); snd_click() end
  if btnp(1) then cursor.x = math.min(PAT_SZ, cursor.x+1); snd_click() end
  if btnp(2) then cursor.y = math.max(1, cursor.y-1); snd_click() end
  if btnp(3) then cursor.y = math.min(PAT_SZ, cursor.y+1); snd_click() end
  if btnp(4) then
    pat_player[cursor.y][cursor.x] = 1 - pat_player[cursor.y][cursor.x]
    snd_click()
  end
  if btnp(5) then -- B: submit
    local ok = true
    for y=1,PAT_SZ do
      for x=1,PAT_SZ do
        if pat_target[y][x] ~= pat_player[y][x] then ok=false end
      end
    end
    if ok then return true
    else
      snd_fail(); flash_t = 10
      -- show again briefly
      pat_show = true; pat_timer = 45
    end
  end
  return false
end

local function draw_pattern()
  local ox, oy = 46, 20
  local cs = 16
  local grid = pat_show and pat_target or pat_player

  if pat_show then
    print("MEMORIZE THIS", 40, 4, 3)
    -- flash border
    if frame%10<5 then rect(0,0,W-1,H-1,3) end
  else
    print("REPRODUCE IT", 44, 4, 2)
  end

  for y=1,PAT_SZ do
    for x=1,PAT_SZ do
      local px = ox+(x-1)*cs
      local py = oy+(y-1)*cs
      local on = grid[y][x] == 1
      rectfill(px, py, px+cs-2, py+cs-2, on and 3 or 1)
      rect(px, py, px+cs-2, py+cs-2, 2)
    end
  end
  if not pat_show then
    local cx = ox+(cursor.x-1)*cs
    local cy = oy+(cursor.y-1)*cs
    rect(cx-1, cy-1, cx+cs-1, cy+cs-1, 3)
    print("\x97 TOGGLE  \x8e SUBMIT", 22, 92, 2)
  else
    print("WATCH CAREFULLY...", 32, 92, 2)
  end
end

------------------------------------------------------------
-- ROOM 5: SEQUENCE MEMORY (Simon-style)
------------------------------------------------------------
local seq = {}
local seq_len = 0
local seq_max = 6
local seq_input = {}
local seq_phase = "show" -- show, input, fail
local seq_idx = 1
local seq_show_timer = 0
local seq_active = 0

local function init_sequence()
  seq = {}
  seq_len = 3
  for i=1,seq_max do
    seq[i] = math.random(1,4)
  end
  seq_input = {}
  seq_phase = "show"
  seq_idx = 1
  seq_show_timer = 30
  seq_active = 0
  cursor.x = 1
end

local function update_sequence()
  if seq_phase == "show" then
    seq_show_timer = seq_show_timer - 1
    if seq_show_timer <= 0 then
      seq_idx = seq_idx + 1
      if seq_idx > seq_len then
        seq_phase = "input"
        seq_input = {}
        cursor.x = 1
        seq_active = 0
      else
        snd_tone(seq[seq_idx])
        seq_active = seq[seq_idx]
        seq_show_timer = 20
      end
    elseif seq_show_timer == 20 and seq_idx == 1 then
      snd_tone(seq[1])
      seq_active = seq[1]
    end
    if seq_show_timer < 5 then seq_active = 0 end
    return false
  end

  if seq_phase == "input" then
    if btnp(0) then cursor.x = math.max(1, cursor.x-1); snd_click() end
    if btnp(1) then cursor.x = math.min(4, cursor.x+1); snd_click() end
    if btnp(4) then -- A: press button
      seq_input[#seq_input+1] = cursor.x
      snd_tone(cursor.x)
      seq_active = cursor.x
      local idx = #seq_input
      if seq_input[idx] ~= seq[idx] then
        snd_fail()
        seq_phase = "show"
        seq_input = {}
        seq_idx = 1
        seq_show_timer = 40
        seq_active = 0
        return false
      end
      if #seq_input == seq_len then
        if seq_len >= seq_max then
          return true
        else
          seq_len = seq_len + 1
          snd_ok()
          seq_phase = "show"
          seq_input = {}
          seq_idx = 1
          seq_show_timer = 40
          seq_active = 0
        end
      end
    end
  end
  if seq_active > 0 and seq_phase == "input" then
    seq_show_timer = seq_show_timer - 1
    if seq_show_timer <= 0 then seq_active = 0 end
  end
  return false
end

local function draw_sequence()
  print("REPEAT THE SEQUENCE", 28, 4, 2)
  print("ROUND "..seq_len-2 .."/"..seq_max-2, 52, 14, 2)

  local ox = 24
  local oy = 36
  local bw, bh = 28, 28
  local gap = 4
  for i=1,4 do
    local px = ox + (i-1)*(bw+gap)
    local lit = (seq_active == i)
    local col = lit and 3 or 1
    rectfill(px, oy, px+bw, oy+bh, col)
    rect(px, oy, px+bw, oy+bh, 2)
    print(tostring(i), px+12, oy+10, lit and 0 or 2)
    if seq_phase == "input" and cursor.x == i then
      rect(px-1, oy-1, px+bw+1, oy+bh+1, 3)
    end
  end

  if seq_phase == "show" then
    print("WATCH...", 56, 78, 2)
  else
    print("\x97 PRESS", 60, 78, 2)
  end

  -- show progress dots
  for i=1,seq_len do
    local done = i <= #seq_input
    circfill(50 + i*6, 92, 2, done and 3 or 1)
  end
end

------------------------------------------------------------
-- ROOM DISPATCH
------------------------------------------------------------
local room_inits = {init_combo, init_tiles, init_wires, init_pattern, init_sequence}
local room_updates = {update_combo, update_tiles, update_wires, update_pattern, update_sequence}
local room_draws = {draw_combo, draw_tiles, draw_wires, draw_pattern, draw_sequence}
local room_names = {"COMBINATION LOCK","SLIDING TILES","WIRE CONNECT","PATTERN MATCH","SEQUENCE MEMORY"}

local function init_room(r)
  room = r
  room_inits[r]()
  msg = room_names[r]
  msg_timer = 60
end

------------------------------------------------------------
-- DEMO MODE
------------------------------------------------------------
local function demo_update()
  demo_delay = demo_delay - 1
  if demo_delay > 0 then return end
  demo_delay = 15
  demo_step = demo_step + 1
  -- just simulate random inputs on room 1
  if demo_step % 3 == 0 then
    combo[math.random(1,combo_cols)] = math.random(0,9)
  end
  if demo_step > 30 then
    demo_mode = false
    scene = "title"
  end
end

------------------------------------------------------------
-- MAIN INIT
------------------------------------------------------------
function _init()
  mode(2)
  -- 2-bit palette: 0=black, 1=dark gray, 2=light gray, 3=white
  poke(0x5000, 0)    -- color 0: black
  poke(0x5001, 0)
  poke(0x5002, 0)
  poke(0x5004, 85)   -- color 1: dark gray
  poke(0x5005, 85)
  poke(0x5006, 85)
  poke(0x5008, 170)  -- color 2: light gray
  poke(0x5009, 170)
  poke(0x500a, 170)
  poke(0x500c, 255)  -- color 3: white
  poke(0x500d, 255)
  poke(0x500e, 255)
  scene = "title"
  idle_timer = 0
  frame = 0
end

------------------------------------------------------------
-- MAIN UPDATE
------------------------------------------------------------
function _update()
  frame = frame + 1
  flash_t = math.max(0, flash_t - 1)
  if msg_timer > 0 then msg_timer = msg_timer - 1 end

  -- any input resets idle
  local any = false
  for i=0,5 do if btnp(i) then any=true end end

  if scene == "title" then
    if any then
      idle_timer = 0
      if demo_mode then
        demo_mode = false
        scene = "title"
        return
      end
      scene = "game"
      for i=1,MAX_ROOMS do solved[i]=false end
      init_room(1)
      return
    end
    idle_timer = idle_timer + 1
    if idle_timer > DEMO_IDLE then
      demo_mode = true
      init_room(1)
      scene = "demo"
      demo_step = 0
      demo_delay = 15
    end
    return
  end

  if scene == "demo" then
    if any then
      demo_mode = false
      scene = "title"
      idle_timer = 0
      return
    end
    demo_update()
    return
  end

  if paused then
    if btnp(4) then paused = false end
    return
  end

  if scene == "win" then
    if btnp(4) then scene = "title"; idle_timer = 0 end
    return
  end

  if scene == "transition" then
    trans_timer = trans_timer - 1
    if trans_timer <= 0 then
      scene = "game"
    end
    return
  end

  if scene == "game" then
    if btn(4) and btn(5) then -- A+B = pause (using start conceptually)
      paused = true
      return
    end
    local result = room_updates[room]()
    if result then
      solved[room] = true
      snd_solve()
      msg = clues[room]
      msg_timer = 90
      if room < MAX_ROOMS then
        trans_timer = 60
        trans_from = room_names[room]
        scene = "transition"
        -- init next room after transition
        init_room(room + 1)
        msg = clues[room-1] .. " -- " .. room_names[room]
        msg_timer = 90
      else
        scene = "win"
      end
    end
  end

  play_sounds()
end

------------------------------------------------------------
-- MAIN DRAW
------------------------------------------------------------
function _draw()
  cls(0)

  if scene == "title" then
    -- dark room title
    print("THE DARK ROOM", 34, 30, 3)
    print("- PUZZLES -", 42, 42, 2)
    if frame%60 < 40 then
      print("PRESS \x97 TO START", 30, 70, 2)
    end
    -- ambient flicker
    if frame%90 < 3 then
      rectfill(0,0,W-1,H-1,1)
    end
    return
  end

  if scene == "demo" then
    print("DEMO", 2, 2, 2)
    room_draws[1]()
    return
  end

  if scene == "transition" then
    -- fade effect
    local t = trans_timer
    if t > 30 then
      -- fading out
      local lvl = math.floor((60-t)/10)
      cls(math.min(lvl, 1))
    else
      -- fading in
      local lvl = math.floor(t/10)
      cls(math.min(lvl, 1))
    end
    print(room_names[room], 40, 55, 3)
    print("ROOM "..room.."/"..MAX_ROOMS, 52, 66, 2)
    return
  end

  if scene == "win" then
    -- final reveal
    local full = ""
    for i=1,MAX_ROOMS do full = full .. clues[i] .. " " end
    print("ESCAPED!", 52, 20, 3)
    print(full, 8, 45, 3)
    print("THE DOOR WAS", 40, 65, 2)
    print("ALWAYS OPEN.", 40, 75, 2)
    if frame%60 < 40 then
      print("PRESS \x97", 58, 100, 2)
    end
    return
  end

  -- game scene
  -- room header
  local hdr = "ROOM "..room.."/"..MAX_ROOMS
  print(hdr, W - #hdr*4 - 4, 2, 1)

  -- draw current room puzzle
  room_draws[room]()

  -- flash on error
  if flash_t > 0 and flash_t%4 < 2 then
    rect(0, 0, W-1, H-1, 3)
  end

  -- message overlay
  if msg_timer > 0 then
    local mw = #msg * 4 + 8
    local mx = (W - mw) / 2
    rectfill(mx, H-16, mx+mw, H-4, 1)
    rect(mx, H-16, mx+mw, H-4, 2)
    print(msg, mx+4, H-12, 3)
  end

  -- solved indicators
  for i=1,MAX_ROOMS do
    local c = solved[i] and 3 or 1
    circfill(4 + i*6, H-4, 2, c)
  end

  if paused then
    rectfill(50, 45, 110, 70, 0)
    rect(50, 45, 110, 70, 3)
    print("PAUSED", 60, 52, 3)
    print("\x97 RESUME", 56, 62, 2)
  end
end
