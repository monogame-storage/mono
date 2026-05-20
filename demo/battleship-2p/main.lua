-- Mono Battleship 2P (lockstep netplay)
-- Classic battleship with hidden placement. Open the cart in two windows.
--
-- Phases:
--   placing — each player places 3 ships on their own board.
--             Rendering is per-peer (you see only YOUR board) so the
--             VRAM hash check is suspended (net.sync(false)). State stays
--             in sync because all button inputs are still exchanged.
--             ARROWS move cursor, A places, SELECT rotates current ship,
--             B undoes the last placed ship.
--   play    — symmetric rendering of both target grids resumes. Hash
--             check is back on (net.sync(true)). Active player fires.
--             ARROWS move crosshair, A fires.
--   over    — winner banner.

local scr = screen()

local GRID_N    = 6
local CELL      = 10
local BOARD_W   = GRID_N * CELL
local BOARD_GAP = 12
local BOARD_Y   = 28
local BOARD_X0  = (SCREEN_W - (BOARD_W * 2 + BOARD_GAP)) // 2
local BOARD_X1  = BOARD_X0 + BOARD_W + BOARD_GAP

local SHIP_LENS   = { 3, 3, 2 }   -- placed in order
local TOTAL_CELLS = 8
local SHOT_ANIM_FRAMES = 15

local boards            -- boards[p][i][j] = true if ship cell
local ship_id           -- ship_id[p][i][j] = 1..#SHIP_LENS (which ship occupies the cell)
local ship_cells_remaining  -- ship_cells_remaining[p][sid] = unhit cells in ship sid
local ship_sunk         -- ship_sunk[p][sid] = true once fully hit
local placement_log     -- placement_log[p] = stack of {sid, cells={{i,j},...}}
local shots             -- shots[p][i][j]  = { kind="hit"|"miss", anim=N }
local hits_taken        -- hits_taken[p]
local cursors           -- per-player {i, j}
local placing_idx       -- per-player index into SHIP_LENS (1..#SHIP_LENS+1)
local placing_horiz     -- per-player rotation flag
local turn              -- active shooter in play phase
local phase             -- "placing" | "play" | "over"
local winner
local game_started

local function in_bounds(i, j) return i >= 0 and i < GRID_N and j >= 0 and j < GRID_N end

local function ship_fits(board, i, j, len, horiz)
  for k = 0, len - 1 do
    local ci = horiz and (i + k) or i
    local cj = horiz and j or (j + k)
    if not in_bounds(ci, cj) then return false end
    if board[ci][cj] then return false end
  end
  return true
end

-- Place ship and record cells in placement_log so undo can pop them.
local function ship_place(p, i, j, len, horiz, sid)
  local cells = {}
  for k = 0, len - 1 do
    local ci = horiz and (i + k) or i
    local cj = horiz and j or (j + k)
    boards[p][ci][cj] = true
    ship_id[p][ci][cj] = sid
    cells[#cells + 1] = { ci, cj }
  end
  ship_cells_remaining[p][sid] = len
  ship_sunk[p][sid] = false
  placement_log[p][#placement_log[p] + 1] = { sid = sid, cells = cells }
end

-- Pop the most recent ship placement off the log; clears boards/ship_id cells.
local function ship_undo(p)
  local log = placement_log[p]
  if #log == 0 then return false end
  local entry = log[#log]
  log[#log] = nil
  for _, cell in ipairs(entry.cells) do
    local ci, cj = cell[1], cell[2]
    boards[p][ci][cj] = nil
    ship_id[p][ci][cj] = nil
  end
  ship_cells_remaining[p][entry.sid] = nil
  ship_sunk[p][entry.sid] = nil
  placing_idx[p] = placing_idx[p] - 1
  return true
end

local function init_match()
  boards               = { [0] = {}, [1] = {} }
  ship_id              = { [0] = {}, [1] = {} }
  shots                = { [0] = {}, [1] = {} }
  ship_cells_remaining = { [0] = {}, [1] = {} }
  ship_sunk            = { [0] = {}, [1] = {} }
  placement_log        = { [0] = {}, [1] = {} }
  for p = 0, 1 do
    for i = 0, GRID_N - 1 do
      boards[p][i]  = {}
      ship_id[p][i] = {}
      shots[p][i]   = {}
    end
  end
  hits_taken    = { [0] = 0, [1] = 0 }
  cursors       = { [0] = { i = 0, j = 0 }, [1] = { i = 0, j = 0 } }
  placing_idx   = { [0] = 1, [1] = 1 }
  placing_horiz = { [0] = true, [1] = true }
  turn          = 0
  phase         = "placing"
  winner        = nil
  -- Per-peer rendering during placement; resume hash check on entry to "play".
  net.sync(false)
end

function _init()
  mode(4)
  use_pause(false)
end

function _start()
  net.start()
  game_started = false
end

local function placing_done(p)
  return placing_idx[p] > #SHIP_LENS
end

-- Count ships still afloat (cells remaining > 0) for player p.
local function ships_afloat(p)
  local n = 0
  for sid = 1, #SHIP_LENS do
    if ship_cells_remaining[p][sid] and ship_cells_remaining[p][sid] > 0 then
      n = n + 1
    end
  end
  return n
end

local function update_placing_for(p)
  -- B undoes the last placed ship even after placing_done(p).
  -- (Allows a player to revise after committing all 3 ships, as long as
  -- their opponent hasn't started yet — phase still == "placing".)
  if btnp("b", p) then
    if ship_undo(p) then
      note(0, "A4", 0.06)
    end
    return
  end

  if placing_done(p) then return end
  local c   = cursors[p]
  local len = SHIP_LENS[placing_idx[p]]
  local h   = placing_horiz[p]

  local moved = false
  if btnp("left",  p) and c.i > 0          then c.i = c.i - 1; moved = true end
  if btnp("right", p) and c.i < GRID_N - 1 then c.i = c.i + 1; moved = true end
  if btnp("up",    p) and c.j > 0          then c.j = c.j - 1; moved = true end
  if btnp("down",  p) and c.j < GRID_N - 1 then c.j = c.j + 1; moved = true end
  if moved then note(0, "E5", 0.02) end

  if btnp("select", p) then
    placing_horiz[p] = not h
    h = placing_horiz[p]
    note(0, "A4", 0.03)
  end

  -- Keep ghost in bounds after rotation/movement.
  if h then
    if c.i + len > GRID_N then c.i = GRID_N - len end
  else
    if c.j + len > GRID_N then c.j = GRID_N - len end
  end

  if btnp("a", p) then
    if ship_fits(boards[p], c.i, c.j, len, h) then
      local sid = placing_idx[p]
      ship_place(p, c.i, c.j, len, h, sid)
      placing_idx[p] = placing_idx[p] + 1
      c.i, c.j = 0, 0
      placing_horiz[p] = true
      note(0, "G4", 0.06)
    end
  end
end

local function start_play()
  phase    = "play"
  turn     = 0
  cursors[0] = { i = GRID_N // 2, j = GRID_N // 2 }
  cursors[1] = { i = GRID_N // 2, j = GRID_N // 2 }
  net.sync(true)
end

local function fire()
  local opp = 1 - turn
  local c   = cursors[turn]
  local i, j = c.i, c.j
  if shots[opp][i][j] then return end
  if boards[opp][i][j] then
    shots[opp][i][j] = { kind = "hit", anim = SHOT_ANIM_FRAMES }
    hits_taken[opp] = hits_taken[opp] + 1
    -- Decrement that ship's remaining cells; mark sunk + play sink SFX if last.
    local sid = ship_id[opp][i][j]
    if sid then
      ship_cells_remaining[opp][sid] = ship_cells_remaining[opp][sid] - 1
      if ship_cells_remaining[opp][sid] <= 0 and not ship_sunk[opp][sid] then
        ship_sunk[opp][sid] = true
        tone(0, 300, 150, 0.4)
      end
    end
    tone(0, 600, 1500, 0.35)
    cam_shake(5)
    if hits_taken[opp] >= TOTAL_CELLS then
      winner = turn
      phase  = "over"
      tone(0, 200, 1200, 0.8)
      return
    end
  else
    shots[opp][i][j] = { kind = "miss", anim = SHOT_ANIM_FRAMES }
    note(0, "C4", 0.05)
  end
  turn = 1 - turn
  cursors[turn] = { i = GRID_N // 2, j = GRID_N // 2 }
end

local function update_play()
  local t = turn
  local c = cursors[t]
  local moved = false
  if btnp("left",  t) and c.i > 0          then c.i = c.i - 1; moved = true end
  if btnp("right", t) and c.i < GRID_N - 1 then c.i = c.i + 1; moved = true end
  if btnp("up",    t) and c.j > 0          then c.j = c.j - 1; moved = true end
  if btnp("down",  t) and c.j < GRID_N - 1 then c.j = c.j + 1; moved = true end
  if moved then note(0, "E5", 0.02) end
  if btnp("a", t) then fire() end
end

-- Tick all in-flight shot animations toward 0. Deterministic — both peers
-- run the same code path during the "play" phase (hash check is on).
local function tick_shot_anims()
  for p = 0, 1 do
    for i = 0, GRID_N - 1 do
      for j = 0, GRID_N - 1 do
        local s = shots[p][i][j]
        if s and s.anim > 0 then s.anim = s.anim - 1 end
      end
    end
  end
end

function _update()
  if not game_started then
    if net.status() ~= "playing" then return end
    math.randomseed(net.seed())
    init_match()
    game_started = true
    return
  end

  if phase == "placing" then
    update_placing_for(0)
    update_placing_for(1)
    if placing_done(0) and placing_done(1) then start_play() end
  elseif phase == "play" then
    update_play()
    tick_shot_anims()
  elseif phase == "over" then
    tick_shot_anims()
  end
end

-- ── drawing ──────────────────────────────────────────────────────────

local function draw_grid(bx, by, color)
  rect(scr, bx - 1, by - 1, BOARD_W + 2, BOARD_W + 2, color)
  for k = 0, GRID_N do
    line(scr, bx, by + k * CELL, bx + BOARD_W, by + k * CELL, 3)
    line(scr, bx + k * CELL, by, bx + k * CELL, by + BOARD_W, 3)
  end
end

local function draw_ships(bx, by, board, color)
  for i = 0, GRID_N - 1 do
    for j = 0, GRID_N - 1 do
      if board[i][j] then
        rectf(scr, bx + i * CELL + 2, by + j * CELL + 2, CELL - 4, CELL - 4, color)
      end
    end
  end
end

-- Draw sunk-ship contours on opponent's grid: filled rectangles in color 8
-- so the silhouette of revealed ships is visible.
local function draw_sunk_contours(bx, by, owner)
  for i = 0, GRID_N - 1 do
    for j = 0, GRID_N - 1 do
      local sid = ship_id[owner][i][j]
      if sid and ship_sunk[owner][sid] then
        rectf(scr, bx + i * CELL + 1, by + j * CELL + 1, CELL - 2, CELL - 2, 8)
      end
    end
  end
end

local function draw_shots_on(bx, by, owner)
  for i = 0, GRID_N - 1 do
    for j = 0, GRID_N - 1 do
      local s = shots[owner][i][j]
      if s then
        local cx = bx + i * CELL + CELL // 2
        local cy = by + j * CELL + CELL // 2
        local kind = s.kind
        local color = (kind == "hit") and 8 or 15
        if s.anim > 0 then
          -- Expanding ring animation: r grows from 0 to SHOT_ANIM_FRAMES.
          local r = SHOT_ANIM_FRAMES - s.anim
          circ(scr, cx, cy, r, color)
        else
          if kind == "hit" then circf(scr, cx, cy, 3, 8)
          else                  circf(scr, cx, cy, 1, 15) end
        end
      end
    end
  end
end

local function draw_box(bx, by, i, j, w, h, color)
  rect(scr, bx + i * CELL - 1, by + j * CELL - 1, w * CELL + 2, h * CELL + 2, color)
end

-- The placement phase is the ONLY part of this cart that branches on
-- net.local_player() — and that's legal because we call net.sync(false)
-- on entry to placing (suspending the VRAM hash check). All gameplay
-- state still syncs via input exchange.
local function draw_placing()
  local me = net.local_player()
  if me ~= 0 and me ~= 1 then me = 0 end  -- headless / pre-match fallback
  local bx = (me == 0) and BOARD_X0 or BOARD_X1
  local color = (me == 0) and 12 or 8

  text(scr, "PLACE YOUR SHIPS", 80, 6, 7, ALIGN_HCENTER)
  text(scr, "A place SEL rotate B undo", 80, SCREEN_H - 9, 6, ALIGN_HCENTER)

  draw_grid(bx, BOARD_Y, color)
  draw_ships(bx, BOARD_Y, boards[me], color)

  if not placing_done(me) then
    local c   = cursors[me]
    local len = SHIP_LENS[placing_idx[me]]
    local h   = placing_horiz[me]
    local w, ht = h and len or 1, h and 1 or len
    local fits = ship_fits(boards[me], c.i, c.j, len, h)
    draw_box(bx, BOARD_Y, c.i, c.j, w, ht, fits and 15 or 8)
    text(scr, "ship " .. placing_idx[me] .. "/" .. #SHIP_LENS .. "  len " .. len,
         80, BOARD_Y + BOARD_W + 6, color, ALIGN_HCENTER)
  else
    text(scr, "WAITING FOR OPPONENT", 80, BOARD_Y + BOARD_W + 6, 7, ALIGN_HCENTER)
  end
end

local function draw_play()
  text(scr, "P1", BOARD_X0 + BOARD_W // 2, BOARD_Y - 10, 12, ALIGN_HCENTER)
  text(scr, "P2", BOARD_X1 + BOARD_W // 2, BOARD_Y - 10, 8,  ALIGN_HCENTER)

  draw_grid(BOARD_X0, BOARD_Y, 6)
  draw_grid(BOARD_X1, BOARD_Y, 6)
  -- Sunk contours render UNDER shot markers so the hit ring still sits on top.
  draw_sunk_contours(BOARD_X0, BOARD_Y, 0)
  draw_sunk_contours(BOARD_X1, BOARD_Y, 1)
  draw_shots_on(BOARD_X0, BOARD_Y, 0)
  draw_shots_on(BOARD_X1, BOARD_Y, 1)

  -- Crosshair on the player-being-shot-at's board (= active player's target).
  if phase == "play" then
    local opp = 1 - turn
    local bx  = (opp == 0) and BOARD_X0 or BOARD_X1
    local c   = cursors[turn]
    draw_box(bx, BOARD_Y, c.i, c.j, 1, 1, 15)
  end

  text(scr, "SHIPS: " .. ships_afloat(0),
       BOARD_X0 + BOARD_W // 2, BOARD_Y + BOARD_W + 4, 12, ALIGN_HCENTER)
  text(scr, "SHIPS: " .. ships_afloat(1),
       BOARD_X1 + BOARD_W // 2, BOARD_Y + BOARD_W + 4, 8, ALIGN_HCENTER)

  if phase == "play" then
    local col = turn == 0 and 12 or 8
    text(scr, "P" .. (turn+1) .. " FIRE", 80, SCREEN_H - 9, col, ALIGN_HCENTER)
  elseif phase == "over" then
    text(scr, "P" .. (winner+1) .. " WINS!", 80, SCREEN_H - 9, 15, ALIGN_HCENTER)
  end
end

function _draw()
  cls(scr, 0)
  if not game_started then
    text(scr, "BATTLESHIP 2P", 80, 50, 12, ALIGN_HCENTER)
    return
  end
  if phase == "placing" then draw_placing()
  else                       draw_play() end
end
