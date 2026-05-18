-- Mono Battleship 2P (lockstep netplay)
-- Classic battleship with hidden placement. Open the cart in two windows.
--
-- Phases:
--   placing — each player places 3 ships on their own board.
--             Rendering is per-peer (you see only YOUR board) so the
--             VRAM hash check is suspended (net.sync(false)). State stays
--             in sync because all button inputs are still exchanged.
--             ARROWS move cursor, A places, B rotates current ship.
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

local boards         -- boards[p][i][j] = true if ship cell
local shots          -- shots[p][i][j]  = "hit" | "miss" | nil  (incoming on player p)
local hits_taken     -- hits_taken[p]
local cursors        -- per-player {i, j} (used in placing for own board; in play, active uses opponent's)
local placing_idx    -- per-player index into SHIP_LENS (1..#SHIP_LENS+1)
local placing_horiz  -- per-player rotation flag
local turn           -- active shooter in play phase
local phase          -- "placing" | "play" | "over"
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

local function ship_place(board, i, j, len, horiz)
  for k = 0, len - 1 do
    local ci = horiz and (i + k) or i
    local cj = horiz and j or (j + k)
    board[ci][cj] = true
  end
end

local function init_match()
  boards = { [0] = {}, [1] = {} }
  shots  = { [0] = {}, [1] = {} }
  for p = 0, 1 do
    for i = 0, GRID_N - 1 do
      boards[p][i] = {}
      shots[p][i]  = {}
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

local function update_placing_for(p)
  if placing_done(p) then return end
  local c   = cursors[p]
  local len = SHIP_LENS[placing_idx[p]]
  local h   = placing_horiz[p]

  if btnp("left",  p) and c.i > 0          then c.i = c.i - 1 end
  if btnp("right", p) and c.i < GRID_N - 1 then c.i = c.i + 1 end
  if btnp("up",    p) and c.j > 0          then c.j = c.j - 1 end
  if btnp("down",  p) and c.j < GRID_N - 1 then c.j = c.j + 1 end
  if btnp("b",     p) then placing_horiz[p] = not h; h = placing_horiz[p] end

  -- Keep ghost in bounds after rotation/movement.
  if h then
    if c.i + len > GRID_N then c.i = GRID_N - len end
  else
    if c.j + len > GRID_N then c.j = GRID_N - len end
  end

  if btnp("a", p) then
    if ship_fits(boards[p], c.i, c.j, len, h) then
      ship_place(boards[p], c.i, c.j, len, h)
      placing_idx[p] = placing_idx[p] + 1
      c.i, c.j = 0, 0
      placing_horiz[p] = true
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
    shots[opp][i][j] = "hit"
    hits_taken[opp] = hits_taken[opp] + 1
    if hits_taken[opp] >= TOTAL_CELLS then
      winner = turn
      phase  = "over"
      return
    end
  else
    shots[opp][i][j] = "miss"
  end
  turn = 1 - turn
  cursors[turn] = { i = GRID_N // 2, j = GRID_N // 2 }
end

local function update_play()
  local t = turn
  local c = cursors[t]
  if btnp("left",  t) and c.i > 0          then c.i = c.i - 1 end
  if btnp("right", t) and c.i < GRID_N - 1 then c.i = c.i + 1 end
  if btnp("up",    t) and c.j > 0          then c.j = c.j - 1 end
  if btnp("down",  t) and c.j < GRID_N - 1 then c.j = c.j + 1 end
  if btnp("a",     t) then fire() end
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

local function draw_shots_on(bx, by, owner)
  for i = 0, GRID_N - 1 do
    for j = 0, GRID_N - 1 do
      local s = shots[owner][i][j]
      if s then
        local cx = bx + i * CELL + CELL // 2
        local cy = by + j * CELL + CELL // 2
        if s == "hit" then circf(scr, cx, cy, 3, 8)
        else              circf(scr, cx, cy, 1, 15) end
      end
    end
  end
end

local function draw_box(bx, by, i, j, w, h, color)
  rect(scr, bx + i * CELL - 1, by + j * CELL - 1, w * CELL + 2, h * CELL + 2, color)
end

local function draw_placing()
  local me = net.local_player()
  if me ~= 0 and me ~= 1 then me = 0 end  -- headless / pre-match fallback
  local bx = (me == 0) and BOARD_X0 or BOARD_X1
  local color = (me == 0) and 12 or 8

  text(scr, "PLACE YOUR SHIPS", 80, 6, 7, ALIGN_HCENTER)
  text(scr, "A place  B rotate", 80, SCREEN_H - 9, 6, ALIGN_HCENTER)

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
  draw_shots_on(BOARD_X0, BOARD_Y, 0)
  draw_shots_on(BOARD_X1, BOARD_Y, 1)

  -- Crosshair on the player-being-shot-at's board (= active player's target).
  if phase == "play" then
    local opp = 1 - turn
    local bx  = (opp == 0) and BOARD_X0 or BOARD_X1
    local c   = cursors[turn]
    draw_box(bx, BOARD_Y, c.i, c.j, 1, 1, 15)
  end

  text(scr, hits_taken[0] .. "/" .. TOTAL_CELLS,
       BOARD_X0 + BOARD_W // 2, BOARD_Y + BOARD_W + 4, 12, ALIGN_HCENTER)
  text(scr, hits_taken[1] .. "/" .. TOTAL_CELLS,
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
