-- QUEEN CONQUEST
-- A strategy/territory game using the queen's power
-- 1-bit (mode 1): 0=black, 1=white | 160x120 | Touch+D-Pad

----------------------------------------------------------------
-- CONSTANTS
----------------------------------------------------------------
local W = 160
local H = 120
local CELL = 12          -- cell size in pixels
local BOARD_X = 14       -- board top-left x (centers 96px board in 160)
local BOARD_Y = 12       -- board top-left y (centers 96px board in 120)
local BOARD_SZ = 8       -- 8x8 grid
local HUD_X = 118        -- HUD panel x
local IDLE_LIMIT = 300   -- frames before attract mode (~10s at 30fps)
local CHAR_W = 5         -- character width for text
local TOTAL_CELLS = BOARD_SZ * BOARD_SZ  -- 64

-- Directions: queen moves in all 8 directions
local DIRS = {
    {0,-1},{0,1},{-1,0},{1,0},
    {-1,-1},{-1,1},{1,-1},{1,1}
}

-- Progression thresholds (territory % of total cells)
local EVOLVE_SPEED = 0.50    -- 2 moves per turn
local EVOLVE_JUMP  = 0.75    -- can jump over enemies
local EVOLVE_AREA  = 0.90    -- claims adjacent squares too
local GAMEOVER_THRESHOLD = 4 -- lose if territory drops below this many cells

----------------------------------------------------------------
-- GAME STATE
----------------------------------------------------------------
local scene = "title"
local high_score = 0

-- Board: 0=neutral, 1=player territory, 2=enemy territory
local board = {}
-- Pieces
local queen = {x=1, y=1}
local cursor = {x=1, y=1}
local enemies = {}
-- Turn counter
local turn = 0
local score = 0
local combo = 0
local game_over_reason = ""
local moves_this_turn = 0   -- track moves within a turn for speed evolution

-- Progression state
local queen_level = 0       -- 0=base, 1=speed, 2=jump, 3=area
local peak_territory_pct = 0

-- Title
local title_timer = 0
local idle_timer = 0
local attract_mode = false
local attract_ai_timer = 0

-- Game over
local go_timer = 0

-- Animation
local anim_timer = 0
local flash_cells = {}
local flash_timer = 0
local msg_text = ""
local msg_timer = 0
local evolve_msg = ""
local evolve_timer = 0

-- Touch
local touch_active = false
local touch_cx, touch_cy = -1, -1

----------------------------------------------------------------
-- UTILITY
----------------------------------------------------------------
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function in_bounds(x, y)
    return x >= 1 and x <= BOARD_SZ and y >= 1 and y <= BOARD_SZ
end

local function cell_screen(cx, cy)
    return BOARD_X + (cx - 1) * CELL, BOARD_Y + (cy - 1) * CELL
end

local function screen_to_cell(sx, sy)
    local cx = math.floor((sx - BOARD_X) / CELL) + 1
    local cy = math.floor((sy - BOARD_Y) / CELL) + 1
    if in_bounds(cx, cy) then return cx, cy end
    return nil, nil
end

local function board_get(x, y)
    if not in_bounds(x, y) then return -1 end
    return board[(y - 1) * BOARD_SZ + x]
end

local function board_set(x, y, v)
    if in_bounds(x, y) then
        board[(y - 1) * BOARD_SZ + x] = v
    end
end

local function count_territory(owner)
    local c = 0
    for i = 1, TOTAL_CELLS do
        if board[i] == owner then c = c + 1 end
    end
    return c
end

local function get_territory_pct()
    return count_territory(1) / TOTAL_CELLS
end

local function has_speed()
    return queen_level >= 1
end

local function has_jump()
    return queen_level >= 2
end

local function has_area()
    return queen_level >= 3
end

local function update_queen_level()
    local pct = get_territory_pct()
    if pct > peak_territory_pct then
        peak_territory_pct = pct
    end
    local old_level = queen_level
    if peak_territory_pct >= EVOLVE_AREA then
        queen_level = 3
    elseif peak_territory_pct >= EVOLVE_JUMP then
        queen_level = 2
    elseif peak_territory_pct >= EVOLVE_SPEED then
        queen_level = 1
    else
        queen_level = 0
    end
    -- Show evolution message
    if queen_level > old_level then
        if queen_level == 1 then
            evolve_msg = "SPEED!"
        elseif queen_level == 2 then
            evolve_msg = "JUMP!"
        elseif queen_level == 3 then
            evolve_msg = "AREA!"
        end
        evolve_timer = 60
        sfx_evolve()
    end
end

local function is_enemy_at(x, y)
    for _, e in ipairs(enemies) do
        if e.x == x and e.y == y then return true end
    end
    return false
end

local function is_valid_queen_move(fx, fy, tx, ty)
    if fx == tx and fy == ty then return false end
    local dx = tx - fx
    local dy = ty - fy
    -- Must be horizontal, vertical, or diagonal
    if dx ~= 0 and dy ~= 0 and math.abs(dx) ~= math.abs(dy) then
        return false
    end
    -- Check path is clear of enemies (unless queen has jump ability)
    local sx = dx == 0 and 0 or (dx > 0 and 1 or -1)
    local sy = dy == 0 and 0 or (dy > 0 and 1 or -1)
    local cx, cy = fx + sx, fy + sy
    if has_jump() then
        -- With jump: can pass over enemies, but can't land on a square
        -- that has an enemy UNLESS it's the target (capture)
        -- Path just needs to be in-bounds; enemies are skipped
        while cx ~= tx or cy ~= ty do
            cx = cx + sx
            cy = cy + sy
        end
        return true
    else
        -- Without jump: path must be clear of enemies
        while cx ~= tx or cy ~= ty do
            if is_enemy_at(cx, cy) then return false end
            cx = cx + sx
            cy = cy + sy
        end
        return true
    end
end

----------------------------------------------------------------
-- SOUND HELPERS
----------------------------------------------------------------
local function sfx_move()
    if note then note(0, "C4", 0.05) end
end

local function sfx_claim()
    if note then
        note(0, "E5", 0.08)
        note(1, "G5", 0.08)
    end
end

local function sfx_capture()
    if note then
        note(0, "C5", 0.1)
        note(1, "E5", 0.1)
        note(2, "G5", 0.15)
    end
end

local function sfx_enemy_spawn()
    if note then note(0, "C3", 0.15) end
end

local function sfx_gameover()
    if note then
        note(0, "E4", 0.2)
        note(1, "C4", 0.2)
        note(2, "A3", 0.3)
    end
end

local function sfx_start()
    if note then
        note(0, "C5", 0.1)
        note(1, "E5", 0.1)
    end
end

function sfx_evolve()
    if note then
        note(0, "C5", 0.1)
        note(1, "E5", 0.1)
        note(2, "G5", 0.1)
    end
end

----------------------------------------------------------------
-- BOARD LOGIC
----------------------------------------------------------------
local function init_board()
    board = {}
    for i = 1, TOTAL_CELLS do
        board[i] = 0
    end
    enemies = {}
    turn = 0
    score = 0
    combo = 0
    moves_this_turn = 0
    queen_level = 0
    peak_territory_pct = 0
    flash_cells = {}
    flash_timer = 0
    msg_text = ""
    msg_timer = 0
    evolve_msg = ""
    evolve_timer = 0
end

local function claim_adjacent(ox, oy)
    -- Area evolution: claim all 8 neighbors too
    local claimed = {}
    for _, d in ipairs(DIRS) do
        local nx, ny = ox + d[1], oy + d[2]
        if in_bounds(nx, ny) and not is_enemy_at(nx, ny) then
            if board_get(nx, ny) ~= 1 then
                board_set(nx, ny, 1)
                claimed[#claimed + 1] = {nx, ny}
            end
        end
    end
    return claimed
end

local function claim_line_of_sight(ox, oy)
    -- Claim all squares the queen can see from (ox, oy)
    local claimed = {}
    for _, d in ipairs(DIRS) do
        local cx, cy = ox + d[1], oy + d[2]
        while in_bounds(cx, cy) do
            -- Stop at enemy pieces
            local blocked = false
            for _, e in ipairs(enemies) do
                if e.x == cx and e.y == cy then blocked = true; break end
            end
            if blocked then break end
            if board_get(cx, cy) ~= 1 then
                board_set(cx, cy, 1)
                claimed[#claimed + 1] = {cx, cy}
            end
            -- If area evolution, claim adjacent squares along sight line
            if has_area() then
                local adj = claim_adjacent(cx, cy)
                for _, a in ipairs(adj) do
                    claimed[#claimed + 1] = a
                end
            end
            cx = cx + d[1]
            cy = cy + d[2]
        end
    end
    -- Also claim the queen's own square
    if board_get(ox, oy) ~= 1 then
        board_set(ox, oy, 1)
        claimed[#claimed + 1] = {ox, oy}
    end
    -- Area evolution on queen's position
    if has_area() then
        local adj = claim_adjacent(ox, oy)
        for _, a in ipairs(adj) do
            claimed[#claimed + 1] = a
        end
    end
    return claimed
end

local function claim_path(fx, fy, tx, ty)
    -- Claim squares along movement path
    local dx = tx - fx
    local dy = ty - fy
    local sx = dx == 0 and 0 or (dx > 0 and 1 or -1)
    local sy = dy == 0 and 0 or (dy > 0 and 1 or -1)
    local cx, cy = fx + sx, fy + sy
    while cx ~= tx or cy ~= ty do
        if not is_enemy_at(cx, cy) then
            board_set(cx, cy, 1)
        end
        cx = cx + sx
        cy = cy + sy
    end
end

local function spawn_enemy()
    -- Spawn on edge of board, prefer neutral or player territory
    local attempts = 0
    while attempts < 30 do
        local edge = math.random(1, 4)
        local x, y
        if edge == 1 then x, y = math.random(1, BOARD_SZ), 1
        elseif edge == 2 then x, y = math.random(1, BOARD_SZ), BOARD_SZ
        elseif edge == 3 then x, y = 1, math.random(1, BOARD_SZ)
        else x, y = BOARD_SZ, math.random(1, BOARD_SZ)
        end
        -- Don't spawn on queen or another enemy
        local ok = true
        if x == queen.x and y == queen.y then ok = false end
        for _, e in ipairs(enemies) do
            if e.x == x and e.y == y then ok = false; break end
        end
        if ok then
            -- Enemy type: rook or bishop
            local etype = math.random(1, 2) == 1 and "rook" or "bishop"
            enemies[#enemies + 1] = {x = x, y = y, etype = etype}
            board_set(x, y, 2)
            sfx_enemy_spawn()
            return
        end
        attempts = attempts + 1
    end
end

local function enemy_claim_sight(e)
    -- Enemies claim territory along their movement lines
    local dirs
    if e.etype == "rook" then
        dirs = {{0,-1},{0,1},{-1,0},{1,0}}
    else -- bishop
        dirs = {{-1,-1},{-1,1},{1,-1},{1,1}}
    end
    for _, d in ipairs(dirs) do
        local cx, cy = e.x + d[1], e.y + d[2]
        local range = 0
        while in_bounds(cx, cy) and range < 3 do
            if cx == queen.x and cy == queen.y then break end
            local blocked = false
            for _, oe in ipairs(enemies) do
                if oe ~= e and oe.x == cx and oe.y == cy then blocked = true; break end
            end
            if blocked then break end
            board_set(cx, cy, 2)
            cx = cx + d[1]
            cy = cy + d[2]
            range = range + 1
        end
    end
    board_set(e.x, e.y, 2)
end

local function move_enemies()
    for _, e in ipairs(enemies) do
        -- Move toward queen or toward largest player territory cluster
        local best_x, best_y = e.x, e.y
        local best_score = -999
        local dirs
        if e.etype == "rook" then
            dirs = {{0,-1},{0,1},{-1,0},{1,0}}
        else
            dirs = {{-1,-1},{-1,1},{1,-1},{1,1}}
        end
        for _, d in ipairs(dirs) do
            local nx, ny = e.x + d[1], e.y + d[2]
            if in_bounds(nx, ny) then
                local ok = true
                for _, oe in ipairs(enemies) do
                    if oe ~= e and oe.x == nx and oe.y == ny then ok = false; break end
                end
                if ok then
                    -- Score: prefer player territory, get closer to queen
                    local s = 0
                    if board_get(nx, ny) == 1 then s = s + 5 end
                    local dq = math.abs(nx - queen.x) + math.abs(ny - queen.y)
                    s = s + (14 - dq)
                    -- Add some randomness
                    s = s + math.random(0, 2)
                    if s > best_score then
                        best_score = s
                        best_x = nx
                        best_y = ny
                    end
                end
            end
        end
        e.x = best_x
        e.y = best_y
    end
    -- After moving, enemies claim territory
    for _, e in ipairs(enemies) do
        enemy_claim_sight(e)
    end
end

local function check_queen_captured()
    for _, e in ipairs(enemies) do
        if e.x == queen.x and e.y == queen.y then
            return true
        end
    end
    return false
end

local function do_player_move(tx, ty)
    if not is_valid_queen_move(queen.x, queen.y, tx, ty) then
        return false
    end

    -- Check if capturing an enemy
    local captured = false
    for i = #enemies, 1, -1 do
        if enemies[i].x == tx and enemies[i].y == ty then
            table.remove(enemies, i)
            captured = true
            combo = combo + 1
            -- Score: captures give points (score only goes UP)
            score = score + 10 * (1 + combo)
            sfx_capture()
            msg_text = "CAPTURE!"
            msg_timer = 40
        end
    end

    -- Claim path
    claim_path(queen.x, queen.y, tx, ty)
    -- Move queen
    queen.x = tx
    queen.y = ty
    -- Claim line of sight from new position
    local claimed = claim_line_of_sight(queen.x, queen.y)
    flash_cells = claimed
    flash_timer = 15

    if not captured then
        combo = 0
        sfx_claim()
    end

    -- Score: add points for newly claimed cells (score only goes UP)
    score = score + #claimed + 1

    -- Update evolution level
    update_queen_level()

    -- Track moves within this turn (for speed evolution)
    moves_this_turn = moves_this_turn + 1

    -- If speed evolution and this is only the first move, allow another
    if has_speed() and moves_this_turn < 2 then
        -- Don't advance turn yet; wait for second move
        return true
    end

    -- Advance turn
    turn = turn + 1
    moves_this_turn = 0

    -- Spawn enemies periodically (every 3 turns, increasing)
    local spawn_rate = math.max(2, 5 - math.floor(turn / 8))
    if turn % spawn_rate == 0 then
        spawn_enemy()
        if turn > 15 then spawn_enemy() end
    end

    -- Move enemies
    move_enemies()

    -- Check if queen is captured after enemies move
    if check_queen_captured() then
        game_over_reason = "CAPTURED!"
        if score > high_score then high_score = score end
        sfx_gameover()
        go_timer = 0
        go("gameover")
        return true
    end

    -- Check minimum territory threshold
    local player_terr = count_territory(1)
    if turn > 10 and player_terr < GAMEOVER_THRESHOLD then
        game_over_reason = "LAND LOST!"
        if score > high_score then high_score = score end
        sfx_gameover()
        go_timer = 0
        go("gameover")
        return true
    end

    sfx_move()
    return true
end

----------------------------------------------------------------
-- DRAWING HELPERS
----------------------------------------------------------------
local function draw_board(scr)
    for cy = 1, BOARD_SZ do
        for cx = 1, BOARD_SZ do
            local sx, sy = cell_screen(cx, cy)
            local dark_square = (cx + cy) % 2 == 0

            local terr = board_get(cx, cy)
            if terr == 1 then
                -- Player territory: white with pattern
                rectf(scr, sx, sy, CELL, CELL, 1)
                if dark_square then
                    -- Subtle dot pattern
                    pix(scr, sx + 3, sy + 3, 0)
                    pix(scr, sx + 8, sy + 8, 0)
                end
            elseif terr == 2 then
                -- Enemy territory: black with cross marks
                rectf(scr, sx, sy, CELL, CELL, 0)
                -- Small X marks
                pix(scr, sx + 3, sy + 3, 1)
                pix(scr, sx + 8, sy + 8, 1)
                pix(scr, sx + 3, sy + 8, 1)
                pix(scr, sx + 8, sy + 3, 1)
            else
                -- Neutral: checkerboard
                if dark_square then
                    rectf(scr, sx, sy, CELL, CELL, 0)
                else
                    rectf(scr, sx, sy, CELL, CELL, 1)
                    rect(scr, sx, sy, CELL, CELL, 0)
                end
            end
        end
    end

    -- Flash recently claimed cells
    if flash_timer > 0 then
        local show = math.floor(flash_timer / 3) % 2 == 0
        if show then
            for _, c in ipairs(flash_cells) do
                local sx, sy = cell_screen(c[1], c[2])
                rect(scr, sx + 1, sy + 1, CELL - 2, CELL - 2, 0)
            end
        end
    end

    -- Board border
    rect(scr, BOARD_X - 1, BOARD_Y - 1, BOARD_SZ * CELL + 2, BOARD_SZ * CELL + 2, 1)
end

local function draw_queen(scr, cx, cy, color)
    local sx, sy = cell_screen(cx, cy)
    local mx = sx + 6
    local my = sy + 2
    -- Crown shape: 5 points at top
    local bg = color == 1 and 0 or 1
    -- Body
    rectf(scr, mx - 3, my + 3, 7, 4, color)
    -- Crown points
    pix(scr, mx, my, color)
    pix(scr, mx - 3, my + 1, color)
    pix(scr, mx + 3, my + 1, color)
    pix(scr, mx - 2, my + 2, color)
    pix(scr, mx + 2, my + 2, color)
    pix(scr, mx - 1, my + 1, color)
    pix(scr, mx + 1, my + 1, color)
    -- Base
    rectf(scr, mx - 3, my + 7, 7, 2, color)
    -- Inner detail
    pix(scr, mx, my + 4, bg)
    pix(scr, mx - 1, my + 5, bg)
    pix(scr, mx + 1, my + 5, bg)

    -- Evolution indicators on queen sprite
    if queen_level >= 1 then
        -- Speed: small dots flanking the crown
        pix(scr, mx - 5, my + 2, color)
        pix(scr, mx + 5, my + 2, color)
    end
    if queen_level >= 2 then
        -- Jump: upward arrow above crown
        pix(scr, mx, my - 2, color)
        pix(scr, mx - 1, my - 1, color)
        pix(scr, mx + 1, my - 1, color)
    end
    if queen_level >= 3 then
        -- Area: small ring around base
        pix(scr, mx - 4, my + 8, color)
        pix(scr, mx + 4, my + 8, color)
        pix(scr, mx - 4, my + 7, color)
        pix(scr, mx + 4, my + 7, color)
    end
end

local function draw_rook(scr, cx, cy)
    local sx, sy = cell_screen(cx, cy)
    local mx = sx + 6
    local my = sy + 2
    -- Rook: castle shape
    rectf(scr, mx - 3, my + 3, 7, 5, 1)
    -- Battlements
    rectf(scr, mx - 3, my + 1, 2, 2, 1)
    rectf(scr, mx - 0, my + 1, 1, 2, 1)
    rectf(scr, mx + 2, my + 1, 2, 2, 1)
    -- Base
    rectf(scr, mx - 3, my + 8, 7, 1, 1)
    -- Inner
    pix(scr, mx, my + 5, 0)
end

local function draw_bishop(scr, cx, cy)
    local sx, sy = cell_screen(cx, cy)
    local mx = sx + 6
    local my = sy + 2
    -- Bishop: pointed hat
    pix(scr, mx, my, 1)
    pix(scr, mx - 1, my + 1, 1)
    pix(scr, mx + 1, my + 1, 1)
    rectf(scr, mx - 2, my + 2, 5, 3, 1)
    rectf(scr, mx - 2, my + 5, 5, 2, 1)
    -- Slash detail
    pix(scr, mx + 1, my + 3, 0)
    pix(scr, mx, my + 4, 0)
    -- Base
    rectf(scr, mx - 3, my + 7, 7, 2, 1)
end

local function draw_cursor(scr, cx, cy, t)
    local sx, sy = cell_screen(cx, cy)
    local blink = math.floor(t / 8) % 2 == 0
    if blink then
        -- Corner brackets
        -- Top-left
        line(scr, sx, sy, sx + 3, sy, 1)
        line(scr, sx, sy, sx, sy + 3, 1)
        -- Top-right
        line(scr, sx + CELL - 1, sy, sx + CELL - 4, sy, 1)
        line(scr, sx + CELL - 1, sy, sx + CELL - 1, sy + 3, 1)
        -- Bottom-left
        line(scr, sx, sy + CELL - 1, sx + 3, sy + CELL - 1, 1)
        line(scr, sx, sy + CELL - 1, sx, sy + CELL - 4, 1)
        -- Bottom-right
        line(scr, sx + CELL - 1, sy + CELL - 1, sx + CELL - 4, sy + CELL - 1, 1)
        line(scr, sx + CELL - 1, sy + CELL - 1, sx + CELL - 1, sy + CELL - 4, 1)
    end
end

local function draw_valid_moves(scr)
    for cy = 1, BOARD_SZ do
        for cx = 1, BOARD_SZ do
            if is_valid_queen_move(queen.x, queen.y, cx, cy) then
                local sx, sy = cell_screen(cx, cy)
                -- Small center dot to indicate valid move
                pix(scr, sx + 5, sy + 5, 1)
                pix(scr, sx + 6, sy + 5, 1)
                pix(scr, sx + 5, sy + 6, 1)
                pix(scr, sx + 6, sy + 6, 1)
            end
        end
    end
end

local function draw_hud(scr)
    local x = HUD_X
    text(scr, "SCORE", x, 12, 1)
    text(scr, tostring(score), x, 20, 1)

    text(scr, "TURN", x, 32, 1)
    text(scr, tostring(turn), x, 40, 1)

    -- Territory percentage
    local pct = math.floor(get_territory_pct() * 100)
    text(scr, "LAND", x, 52, 1)
    text(scr, pct .. "%", x, 60, 1)

    -- Evolution level indicator
    if queen_level >= 1 then
        text(scr, "SPD", x, 72, 1)
    end
    if queen_level >= 2 then
        text(scr, "JMP", x, 80, 1)
    end
    if queen_level >= 3 then
        text(scr, "ARA", x, 88, 1)
    end

    -- Speed: show moves remaining
    if has_speed() and moves_this_turn == 0 then
        text(scr, "x2", x, 98, 1)
    end

    if combo > 0 then
        text(scr, "x" .. tostring(combo + 1), x, 106, 1)
    end

    text(scr, "HI", x, 112, 1)
    text(scr, tostring(high_score), x + 14, 112, 1)
end

local function draw_clock(scr)
    local d = date()
    if d then
        local h = d.hour or 0
        local m = d.min or 0
        local time_str = string.format("%02d:%02d", h, m)
        text(scr, time_str, W - 30, 2, 1)
    end
end

----------------------------------------------------------------
-- TITLE SCENE
----------------------------------------------------------------
function title_init()
    title_timer = 0
    idle_timer = 0
    attract_mode = false
    attract_ai_timer = 0
    -- Reset board for attract
    init_board()
    queen.x = 4
    queen.y = 4
    cursor.x = 4
    cursor.y = 4
end

function title_update()
    title_timer = title_timer + 1
    anim_timer = anim_timer + 1

    if attract_mode then
        idle_timer = 0
        attract_ai_timer = attract_ai_timer + 1

        -- AI makes a move every 20 frames
        if attract_ai_timer % 20 == 0 then
            -- Pick a random valid move
            local moves = {}
            for cy = 1, BOARD_SZ do
                for cx = 1, BOARD_SZ do
                    if is_valid_queen_move(queen.x, queen.y, cx, cy) then
                        moves[#moves + 1] = {cx, cy}
                    end
                end
            end
            if #moves > 0 then
                -- Prefer moves that claim the most territory
                local best = moves[math.random(1, math.min(3, #moves))]
                do_player_move(best[1], best[2])
            end
        end

        -- Any button exits attract
        if btnp("start") or btnp("a") or btnp("b") then
            attract_mode = false
            idle_timer = 0
            return
        end

        -- Touch exits attract
        if touch_start then
            local tx, ty = touch_pos()
            if tx then
                attract_mode = false
                idle_timer = 0
                return
            end
        end

        -- Reset attract after 600 frames
        if attract_ai_timer > 600 then
            init_board()
            queen.x = 4
            queen.y = 4
            attract_ai_timer = 0
            enemies = {}
        end
        return
    end

    -- Idle detection
    local any_input = btnp("start") or btnp("a") or btnp("b") or
                      btnp("left") or btnp("right") or btnp("up") or btnp("down")

    if touch_start then
        local tx, ty = touch_pos()
        if tx then any_input = true end
    end

    if any_input then
        idle_timer = 0
    else
        idle_timer = idle_timer + 1
    end

    if idle_timer >= IDLE_LIMIT then
        attract_mode = true
        attract_ai_timer = 0
        init_board()
        queen.x = 4
        queen.y = 4
    end

    if btnp("start") or btnp("a") then
        sfx_start()
        go("game")
    end
end

function title_draw()
    local scr = screen()
    cls(scr, 0)

    if attract_mode then
        -- Draw the board with AI playing
        draw_board(scr)
        draw_queen(scr, queen.x, queen.y, 1)
        for _, e in ipairs(enemies) do
            if e.etype == "rook" then
                draw_rook(scr, e.x, e.y)
            else
                draw_bishop(scr, e.x, e.y)
            end
        end

        -- Overlay
        rectf(scr, 20, 2, 80, 11, 0)
        rect(scr, 20, 2, 80, 11, 1)
        local blink = math.floor(title_timer / 20) % 2 == 0
        if blink then
            text(scr, "PRESS START", 24, 4, 1)
        end

        -- Score display
        text(scr, "S:" .. score, HUD_X, 20, 1)
        text(scr, "T:" .. turn, HUD_X, 30, 1)

        -- Clock
        draw_clock(scr)
        return
    end

    -- Title screen
    -- Large title
    local ty_base = 20
    local bounce = math.floor(math.sin(title_timer * 0.05) * 3)
    text(scr, "QUEEN", W / 2, ty_base + bounce, 1, ALIGN_CENTER)
    text(scr, "CONQUEST", W / 2, ty_base + 10 + bounce, 1, ALIGN_CENTER)

    -- Queen icon
    local qx = W / 2 - 4
    local qy = 48
    -- Draw a larger decorative queen
    pix(scr, qx + 4, qy, 1)
    pix(scr, qx + 1, qy + 1, 1)
    pix(scr, qx + 4, qy + 1, 1)
    pix(scr, qx + 7, qy + 1, 1)
    pix(scr, qx + 2, qy + 2, 1)
    pix(scr, qx + 4, qy + 2, 1)
    pix(scr, qx + 6, qy + 2, 1)
    rectf(scr, qx + 1, qy + 3, 7, 5, 1)
    rectf(scr, qx, qy + 8, 9, 2, 1)
    pix(scr, qx + 4, qy + 5, 0)
    pix(scr, qx + 3, qy + 6, 0)
    pix(scr, qx + 5, qy + 6, 0)

    -- Mini chessboard preview
    local bx = W / 2 - 20
    local by = 65
    for r = 0, 4 do
        for c = 0, 4 do
            if (r + c) % 2 == 0 then
                rectf(scr, bx + c * 8, by + r * 5, 8, 5, 1)
            end
        end
    end
    rect(scr, bx - 1, by - 1, 42, 27, 1)

    -- Prompt
    local blink = math.floor(title_timer / 15) % 2 == 0
    if blink then
        text(scr, "PRESS START", W / 2, 100, 1, ALIGN_CENTER)
    end

    -- High score
    if high_score > 0 then
        text(scr, "HI:" .. high_score, W / 2, 112, 1, ALIGN_CENTER)
    end

    -- Clock
    draw_clock(scr)
end

----------------------------------------------------------------
-- GAME SCENE
----------------------------------------------------------------
function game_init()
    init_board()
    queen.x = 4
    queen.y = 4
    cursor.x = 4
    cursor.y = 4
    board_set(4, 4, 1)
    claim_line_of_sight(4, 4)
    -- Initial score from claimed territory
    score = count_territory(1)
    anim_timer = 0
    moves_this_turn = 0
end

function game_update()
    anim_timer = anim_timer + 1

    -- Update timers
    if flash_timer > 0 then flash_timer = flash_timer - 1 end
    if msg_timer > 0 then msg_timer = msg_timer - 1 end
    if evolve_timer > 0 then evolve_timer = evolve_timer - 1 end

    -- Touch input
    if touch_start then
        local tx, ty = touch_pos()
        if tx then
            local cx, cy = screen_to_cell(tx, ty)
            if cx and cy then
                if is_valid_queen_move(queen.x, queen.y, cx, cy) then
                    do_player_move(cx, cy)
                    cursor.x = cx
                    cursor.y = cy
                else
                    -- Just move cursor
                    cursor.x = cx
                    cursor.y = cy
                end
            end
        end
    end

    -- D-Pad movement for cursor
    if btnp("left") then cursor.x = clamp(cursor.x - 1, 1, BOARD_SZ) end
    if btnp("right") then cursor.x = clamp(cursor.x + 1, 1, BOARD_SZ) end
    if btnp("up") then cursor.y = clamp(cursor.y - 1, 1, BOARD_SZ) end
    if btnp("down") then cursor.y = clamp(cursor.y + 1, 1, BOARD_SZ) end

    -- A button: move queen to cursor
    if btnp("a") then
        do_player_move(cursor.x, cursor.y)
    end

    -- B button: end turn early (useful when you have speed but want to skip 2nd move)
    if btnp("b") then
        if has_speed() and moves_this_turn > 0 then
            -- End the turn without using 2nd move
            turn = turn + 1
            moves_this_turn = 0
            local spawn_rate = math.max(2, 5 - math.floor(turn / 8))
            if turn % spawn_rate == 0 then
                spawn_enemy()
                if turn > 15 then spawn_enemy() end
            end
            move_enemies()
            if check_queen_captured() then
                game_over_reason = "CAPTURED!"
                if score > high_score then high_score = score end
                sfx_gameover()
                go_timer = 0
                go("gameover")
            end
            -- Check territory threshold
            local player_terr = count_territory(1)
            if turn > 10 and player_terr < GAMEOVER_THRESHOLD then
                game_over_reason = "LAND LOST!"
                if score > high_score then high_score = score end
                sfx_gameover()
                go_timer = 0
                go("gameover")
            end
        else
            -- Skip turn entirely
            turn = turn + 1
            moves_this_turn = 0
            -- Score does NOT decrease
            local spawn_rate = math.max(2, 5 - math.floor(turn / 8))
            if turn % spawn_rate == 0 then
                spawn_enemy()
            end
            move_enemies()
            if check_queen_captured() then
                game_over_reason = "CAPTURED!"
                if score > high_score then high_score = score end
                sfx_gameover()
                go_timer = 0
                go("gameover")
            end
            -- Check territory threshold
            local player_terr = count_territory(1)
            if turn > 10 and player_terr < GAMEOVER_THRESHOLD then
                game_over_reason = "LAND LOST!"
                if score > high_score then high_score = score end
                sfx_gameover()
                go_timer = 0
                go("gameover")
            end
        end
    end
end

function game_draw()
    local scr = screen()
    cls(scr, 0)

    draw_board(scr)

    -- Draw valid moves (subtle dots)
    draw_valid_moves(scr)

    -- Draw enemies
    for _, e in ipairs(enemies) do
        if e.etype == "rook" then
            draw_rook(scr, e.x, e.y)
        else
            draw_bishop(scr, e.x, e.y)
        end
    end

    -- Draw queen
    local qcolor = 1
    -- Make queen blink if in danger
    local danger = false
    for _, e in ipairs(enemies) do
        local dist = math.abs(e.x - queen.x) + math.abs(e.y - queen.y)
        if dist <= 2 then danger = true; break end
    end
    if danger and math.floor(anim_timer / 4) % 2 == 0 then
        qcolor = 0
    end
    draw_queen(scr, queen.x, queen.y, qcolor)

    -- Draw cursor
    draw_cursor(scr, cursor.x, cursor.y, anim_timer)

    -- HUD
    draw_hud(scr)

    -- Message
    if msg_timer > 0 then
        local mx = BOARD_X + BOARD_SZ * CELL / 2
        local my = BOARD_Y - 10
        text(scr, msg_text, mx, my, 1, ALIGN_CENTER)
    end

    -- Evolution message
    if evolve_timer > 0 then
        local blink = math.floor(evolve_timer / 4) % 2 == 0
        if blink then
            local mx = BOARD_X + BOARD_SZ * CELL / 2
            local my = BOARD_Y + BOARD_SZ * CELL + 4
            text(scr, evolve_msg, mx, my, 1, ALIGN_CENTER)
        end
    end
end

----------------------------------------------------------------
-- GAME OVER SCENE
----------------------------------------------------------------
function gameover_init()
    go_timer = 0
end

function gameover_update()
    go_timer = go_timer + 1

    if go_timer > 30 then
        if btnp("start") or btnp("a") then
            go("title")
        end
        if touch_start then
            local tx, ty = touch_pos()
            if tx then go("title") end
        end
    end
end

function gameover_draw()
    local scr = screen()
    cls(scr, 0)

    -- Show final board state faded
    draw_board(scr)
    -- Draw enemies
    for _, e in ipairs(enemies) do
        if e.etype == "rook" then
            draw_rook(scr, e.x, e.y)
        else
            draw_bishop(scr, e.x, e.y)
        end
    end

    -- Overlay
    rectf(scr, 15, 25, 130, 70, 0)
    rect(scr, 15, 25, 130, 70, 1)

    text(scr, "GAME OVER", W / 2, 30, 1, ALIGN_CENTER)
    text(scr, game_over_reason, W / 2, 40, 1, ALIGN_CENTER)

    text(scr, "SCORE: " .. score, W / 2, 54, 1, ALIGN_CENTER)
    text(scr, "TURNS: " .. turn, W / 2, 64, 1, ALIGN_CENTER)

    local pct = math.floor(get_territory_pct() * 100)
    text(scr, "LAND: " .. pct .. "%", W / 2, 74, 1, ALIGN_CENTER)

    if high_score > 0 then
        text(scr, "BEST: " .. high_score, W / 2, 84, 1, ALIGN_CENTER)
    end

    if go_timer > 30 then
        local blink = math.floor(go_timer / 15) % 2 == 0
        if blink then
            text(scr, "PRESS START", W / 2, 108, 1, ALIGN_CENTER)
        end
    end

    draw_clock(scr)
end

----------------------------------------------------------------
-- ENGINE HOOKS
----------------------------------------------------------------
function _init()
    mode(1)
end

function _start()
    anim_timer = 0
    go("title")
end
