-- Mono Battleship 2P (lockstep netplay)
-- Classic battleship. Open the cart in two browser windows.
--   Active player only:
--     ARROW KEYS : move crosshair on opponent's grid
--     A (Z key)  : fire
--
-- Lockstep note: every peer renders identical pixels (VRAM hashes must
-- match), so ship positions are visually hidden from BOTH peers — only
-- hits/misses are drawn. Ship layouts are seeded from the shared session
-- seed so both peers compute the same board state.

local scr = screen()

local GRID_N    = 6                   -- 6x6 cells per side
local CELL      = 10                  -- 10px per cell
local BOARD_W   = GRID_N * CELL       -- 60
local BOARD_GAP = 12
local BOARD_Y   = 32
local BOARD_X0  = (SCREEN_W - (BOARD_W * 2 + BOARD_GAP)) // 2
local BOARD_X1  = BOARD_X0 + BOARD_W + BOARD_GAP

local SHIPS       = { 2, 3, 3 }
local TOTAL_CELLS = 8                 -- 2 + 3 + 3

local boards       -- boards[p][i][j] = true if ship cell on player p's grid
local shots        -- shots[p][i][j]  = "hit" | "miss" | nil  (incoming on player p)
local hits_taken   -- hits_taken[p]   = total hit cells against player p
local cursor       -- {i, j} on the active player's TARGET (opponent's) grid
local turn         -- 0 or 1 — who is shooting this frame
local phase        -- "play" | "over"
local winner
local game_started

local function place_ships(board, ships)
  for _, len in ipairs(ships) do
    while true do
      local horiz = math.random() < 0.5
      local i, j
      if horiz then
        i = math.random(0, GRID_N - len)
        j = math.random(0, GRID_N - 1)
      else
        i = math.random(0, GRID_N - 1)
        j = math.random(0, GRID_N - len)
      end
      local ok = true
      for k = 0, len - 1 do
        local ci = horiz and (i + k) or i
        local cj = horiz and j or (j + k)
        if board[ci] and board[ci][cj] then ok = false; break end
      end
      if ok then
        for k = 0, len - 1 do
          local ci = horiz and (i + k) or i
          local cj = horiz and j or (j + k)
          board[ci] = board[ci] or {}
          board[ci][cj] = true
        end
        break
      end
    end
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
    place_ships(boards[p], SHIPS)
  end
  hits_taken = { [0] = 0, [1] = 0 }
  cursor     = { i = GRID_N // 2, j = GRID_N // 2 }
  turn       = 0
  phase      = "play"
  winner     = nil
end

function _init()
  mode(4)
  use_pause(false)
end

function _start()
  net.start()
  game_started = false
end

local function fire()
  local opp = 1 - turn
  local i, j = cursor.i, cursor.j
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
  cursor.i = GRID_N // 2
  cursor.j = GRID_N // 2
end

local function update_play()
  local t = turn
  if btnp("left",  t) and cursor.i > 0          then cursor.i = cursor.i - 1 end
  if btnp("right", t) and cursor.i < GRID_N - 1 then cursor.i = cursor.i + 1 end
  if btnp("up",    t) and cursor.j > 0          then cursor.j = cursor.j - 1 end
  if btnp("down",  t) and cursor.j < GRID_N - 1 then cursor.j = cursor.j + 1 end
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
  if phase == "play" then update_play() end
end

local function draw_board(bx, by, owner)
  rect(scr, bx - 1, by - 1, BOARD_W + 2, BOARD_W + 2, 6)
  for k = 0, GRID_N do
    line(scr, bx, by + k * CELL, bx + BOARD_W, by + k * CELL, 3)
    line(scr, bx + k * CELL, by, bx + k * CELL, by + BOARD_W, 3)
  end
  for i = 0, GRID_N - 1 do
    for j = 0, GRID_N - 1 do
      local s = shots[owner][i][j]
      if s then
        local cx = bx + i * CELL + CELL // 2
        local cy = by + j * CELL + CELL // 2
        if s == "hit" then
          circf(scr, cx, cy, 3, 8)
        else
          circf(scr, cx, cy, 1, 15)
        end
      end
    end
  end
end

local function draw_cursor()
  if phase ~= "play" then return end
  local opp = 1 - turn
  local bx  = (opp == 0) and BOARD_X0 or BOARD_X1
  local x   = bx + cursor.i * CELL
  local y   = BOARD_Y + cursor.j * CELL
  rect(scr, x, y, CELL, CELL, 15)
  rect(scr, x - 1, y - 1, CELL + 2, CELL + 2, 15)
end

function _draw()
  cls(scr, 0)

  if not game_started then
    text(scr, "BATTLESHIP 2P", 80, 50, 12, ALIGN_HCENTER)
    return
  end

  text(scr, "P1", BOARD_X0 + BOARD_W // 2, BOARD_Y - 10, 12, ALIGN_HCENTER)
  text(scr, "P2", BOARD_X1 + BOARD_W // 2, BOARD_Y - 10, 8,  ALIGN_HCENTER)

  draw_board(BOARD_X0, BOARD_Y, 0)
  draw_board(BOARD_X1, BOARD_Y, 1)
  draw_cursor()

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
