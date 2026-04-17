-- ROOK TOWER
-- Tower defense on a chess board. Rooks fire along ranks/files.
-- Place rooks, defeat enemy chess pieces, protect your king.
-- Enemy types: pawns, knights, bishops, rooks, queens
-- 1-BIT ONLY (mode 1): 0=black, 1=white

------------------------------------------------------------
-- CONSTANTS
------------------------------------------------------------
local W = 160
local H = 120
local s -- screen surface

-- Board: 8x8 chess grid, each cell 12x12, offset to leave room for HUD
local COLS, ROWS = 8, 8
local CELL = 12
local BOARD_X = 4   -- left margin
local BOARD_Y = 8   -- top margin (HUD above)
local BOARD_W = COLS * CELL
local BOARD_H = ROWS * CELL

-- Game tuning
local ROOK_COST = 10
local QUEEN_COST = 20   -- upgrade cost
local ROOK_RATE = 30     -- frames between shots
local QUEEN_RATE = 25
local ROOK_DMG = 1
local QUEEN_DMG = 2
local KING_MAX_HP = 3
local BASE_GOLD = 15
local GOLD_PER_KILL = 3

-- Enemy types
local E_PAWN   = 1  -- basic, follows path
local E_KNIGHT = 2  -- jumps forward on path periodically
local E_BISHOP = 3  -- dodge: shifts off-axis briefly, harder to hit on rank/file
local E_ROOK   = 4  -- fast charger, straight-line speed
local E_QUEEN  = 5  -- tanky, fast, high reward

-- Attract / demo mode
local ATTRACT_IDLE_FRAMES = 120
local ATTRACT_DURATION = 360

------------------------------------------------------------
-- 7-SEGMENT CLOCK
------------------------------------------------------------
local SEG_DIGITS = {
    [0]=1+2+4+8+16+32,
    [1]=2+4,
    [2]=1+2+8+16+64,
    [3]=1+2+4+8+64,
    [4]=2+4+32+64,
    [5]=1+4+8+32+64,
    [6]=1+4+8+16+32+64,
    [7]=1+2+4,
    [8]=1+2+4+8+16+32+64,
    [9]=1+2+4+8+32+64,
}

local function draw_seg_digit(x, y, digit, col)
    local segs = SEG_DIGITS[digit] or 0
    if segs % 2 >= 1 then rectf(s, x+1, y, 3, 1, col) end
    if math.floor(segs/2) % 2 == 1 then rectf(s, x+4, y+1, 1, 3, col) end
    if math.floor(segs/4) % 2 == 1 then rectf(s, x+4, y+5, 1, 3, col) end
    if math.floor(segs/8) % 2 == 1 then rectf(s, x+1, y+8, 3, 1, col) end
    if math.floor(segs/16) % 2 == 1 then rectf(s, x, y+5, 1, 3, col) end
    if math.floor(segs/32) % 2 == 1 then rectf(s, x, y+1, 1, 3, col) end
    if math.floor(segs/64) % 2 == 1 then rectf(s, x+1, y+4, 3, 1, col) end
end

local function draw_clock(x, y, col, blink)
    local t = date()
    local hr = t.hour
    local mn = t.min
    draw_seg_digit(x, y, math.floor(hr/10), col)
    draw_seg_digit(x+7, y, hr%10, col)
    if blink then
        rectf(s, x+13, y+2, 1, 1, col)
        rectf(s, x+13, y+6, 1, 1, col)
    end
    draw_seg_digit(x+16, y, math.floor(mn/10), col)
    draw_seg_digit(x+23, y, mn%10, col)
end

------------------------------------------------------------
-- UTILITY
------------------------------------------------------------
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function sfx_note(ch, n, dur)
    if note then note(ch, n, dur) end
end
local function sfx_noise(ch, dur)
    if noise then noise(ch, dur) end
end

-- Chess notation for column (0-7 -> a-h)
local FILE_LETTERS = {"a","b","c","d","e","f","g","h"}

------------------------------------------------------------
-- PATH DEFINITION
-- Enemies march along this path (grid coords, 0-indexed)
-- Serpentine path across the board ending at king position
------------------------------------------------------------
local path_waypoints = {
    {x=0, y=0},  -- top-left entry
    {x=3, y=0},
    {x=3, y=2},
    {x=0, y=2},
    {x=0, y=4},
    {x=4, y=4},
    {x=4, y=6},
    {x=1, y=6},
    {x=1, y=7},
    {x=7, y=7},  -- king position (bottom-right area)
}

-- Expanded path: list of {x,y} pixel positions along path
local path_points = {}
local path_cells = {}  -- set of "cx,cy" strings that are path cells

local function build_path()
    path_points = {}
    path_cells = {}
    for i = 1, #path_waypoints - 1 do
        local a = path_waypoints[i]
        local b = path_waypoints[i+1]
        local steps = math.abs(b.x - a.x) + math.abs(b.y - a.y)
        local dx = b.x > a.x and 1 or (b.x < a.x and -1 or 0)
        local dy = b.y > a.y and 1 or (b.y < a.y and -1 or 0)
        local cx, cy = a.x, a.y
        for step = 0, steps - 1 do
            local px = BOARD_X + cx * CELL + CELL/2
            local py = BOARD_Y + cy * CELL + CELL/2
            path_points[#path_points+1] = {x=px, y=py}
            path_cells[cx..","..cy] = true
            if dx ~= 0 then
                cx = cx + dx
            else
                cy = cy + dy
            end
        end
    end
    -- add final waypoint
    local last = path_waypoints[#path_waypoints]
    local px = BOARD_X + last.x * CELL + CELL/2
    local py = BOARD_Y + last.y * CELL + CELL/2
    path_points[#path_points+1] = {x=px, y=py}
    path_cells[last.x..","..last.y] = true
end

------------------------------------------------------------
-- GAME STATE
------------------------------------------------------------
local state       -- "title", "play", "gameover"
local gold, score, wave_num, king_hp
local towers      -- list of {gx, gy, is_queen, rate, dmg, cooldown}
local enemies     -- list of {path_idx, path_frac, hp, max_hp, speed, reward, etype, ...}
local projectiles -- list of {x, y, tx, ty, timer}
local particles   -- list of {x, y, dx, dy, life}
local wave_timer, wave_spawned, wave_total, spawn_timer
local wave_active
local wave_queue  -- list of enemy type configs to spawn this wave
local cursor_x, cursor_y  -- grid cursor position
local paused
local game_frame
local high_score = 0

-- touch state
local touch_prev = false

-- attract mode
local attract_mode = false
local attract_timer = 0
local attract_elapsed = 0
local attract_place_timer = 0

------------------------------------------------------------
-- WAVE CONFIG - now with enemy variety
------------------------------------------------------------
local function wave_config(wn)
    local count = 4 + wn * 2
    if count > 20 then count = 20 end
    local base_hp = 1 + math.floor(wn / 2)
    local base_speed = 0.3 + wn * 0.02
    if base_speed > 0.8 then base_speed = 0.8 end
    local base_reward = 2 + math.floor(wn / 3)

    -- Build a queue of enemy types for this wave
    local queue = {}
    for i = 1, count do
        local etype = E_PAWN
        if wn >= 2 then
            -- Introduce knights from wave 2
            if i % 4 == 0 then etype = E_KNIGHT end
        end
        if wn >= 4 then
            -- Introduce bishops from wave 4
            if i % 5 == 1 then etype = E_BISHOP end
        end
        if wn >= 6 then
            -- Introduce enemy rooks from wave 6
            if i % 6 == 0 then etype = E_ROOK end
        end
        if wn >= 8 then
            -- Introduce enemy queens from wave 8 (rare)
            if i == count then etype = E_QUEEN end
        end

        local hp, speed, reward = base_hp, base_speed, base_reward
        if etype == E_KNIGHT then
            hp = base_hp
            speed = base_speed * 0.8
            reward = base_reward + 1
        elseif etype == E_BISHOP then
            hp = base_hp + 1
            speed = base_speed * 0.9
            reward = base_reward + 2
        elseif etype == E_ROOK then
            hp = base_hp
            speed = base_speed * 1.6
            reward = base_reward + 2
        elseif etype == E_QUEEN then
            hp = base_hp * 3
            speed = base_speed * 1.2
            reward = base_reward + 5
        end

        queue[#queue+1] = {etype=etype, hp=hp, speed=speed, reward=reward}
    end
    return count, queue
end

------------------------------------------------------------
-- DRAWING HELPERS
------------------------------------------------------------

-- Draw the chess board
local function draw_board()
    for row = 0, ROWS-1 do
        for col = 0, COLS-1 do
            local x = BOARD_X + col * CELL
            local y = BOARD_Y + row * CELL
            local is_light = (row + col) % 2 == 0
            if is_light then
                rectf(s, x, y, CELL, CELL, 1)
            else
                rectf(s, x, y, CELL, CELL, 0)
                rect(s, x, y, CELL, CELL, 1)
            end
        end
    end
    -- file letters along bottom
    for col = 0, COLS-1 do
        local x = BOARD_X + col * CELL + 4
        local y = BOARD_Y + ROWS * CELL + 1
        text(s, FILE_LETTERS[col+1], x, y, 1)
    end
    -- rank numbers along left
    for row = 0, ROWS-1 do
        local y = BOARD_Y + row * CELL + 3
        text(s, tostring(ROWS - row), BOARD_X - 5, y, 1)
    end
end

-- Draw path overlay (subtle dots on path cells)
local function draw_path()
    for i = 1, #path_points - 1 do
        local a = path_points[i]
        local b = path_points[i+1]
        -- draw dotted line segments
        if game_frame and game_frame % 2 == 0 then
            local mx = math.floor((a.x + b.x) / 2)
            local my = math.floor((a.y + b.y) / 2)
            pix(s, mx, my, 1)
        end
    end
    -- King at end of path
    local kp = path_points[#path_points]
    if kp then
        draw_king(kp.x, kp.y)
    end
end

-- Draw a rook tower piece (crenellated tower)
local function draw_rook(cx, cy)
    local x = BOARD_X + cx * CELL + 2
    local y = BOARD_Y + cy * CELL + 1
    -- base
    rectf(s, x+1, y+8, 6, 2, 1)
    -- body
    rectf(s, x+2, y+3, 4, 5, 1)
    -- crenellations (top)
    rectf(s, x+1, y+1, 2, 2, 1)
    rectf(s, x+5, y+1, 2, 2, 1)
    rectf(s, x+3, y+2, 2, 1, 1)
end

-- Draw a queen tower piece (crowned)
local function draw_queen_tower(cx, cy)
    local x = BOARD_X + cx * CELL + 2
    local y = BOARD_Y + cy * CELL + 1
    -- base
    rectf(s, x+1, y+8, 6, 2, 1)
    -- body
    rectf(s, x+2, y+4, 4, 4, 1)
    -- crown points
    pix(s, x+1, y+1, 1)
    pix(s, x+4, y+0, 1)
    pix(s, x+7, y+1, 1)
    rectf(s, x+1, y+2, 7, 2, 1)
end

-- Draw the king piece (at end of path)
function draw_king(px, py)
    -- cross on top
    rectf(s, px-1, py-5, 3, 1, 1)
    rectf(s, px, py-6, 1, 3, 1)
    -- body
    rectf(s, px-2, py-3, 5, 4, 1)
    -- base
    rectf(s, px-3, py+1, 7, 2, 1)
end

-- Draw a pawn enemy (circle)
local function draw_pawn(px, py, hp_frac)
    circf(s, px, py, 3, 1)
    if hp_frac < 1 then
        circf(s, px, py, 1, 0)
    end
end

-- Draw a knight enemy (L-shape head)
local function draw_knight_enemy(px, py, hp_frac)
    -- horse head shape: tall rectangle + snout
    rectf(s, px-1, py-4, 3, 6, 1)
    rectf(s, px+1, py-3, 2, 2, 1)  -- snout
    pix(s, px-1, py-3, 1)          -- ear
    -- base
    rectf(s, px-2, py+2, 5, 1, 1)
    if hp_frac < 1 then
        pix(s, px, py-1, 0)  -- damage mark
    end
end

-- Draw a bishop enemy (pointed hat)
local function draw_bishop_enemy(px, py, hp_frac)
    -- pointed top
    pix(s, px, py-4, 1)
    rectf(s, px-1, py-3, 3, 2, 1)
    -- body
    rectf(s, px-2, py-1, 5, 3, 1)
    -- base
    rectf(s, px-2, py+2, 5, 1, 1)
    -- diagonal slash mark
    pix(s, px-1, py-2, 0)
    pix(s, px+1, py, 0)
    if hp_frac < 1 then
        pix(s, px, py, 0)
    end
end

-- Draw an enemy rook (crenellated, inverted)
local function draw_rook_enemy(px, py, hp_frac)
    -- crenellations top
    pix(s, px-2, py-3, 1)
    pix(s, px, py-3, 1)
    pix(s, px+2, py-3, 1)
    rectf(s, px-2, py-2, 5, 2, 1)
    -- body
    rectf(s, px-1, py, 3, 3, 1)
    -- base
    rectf(s, px-2, py+3, 5, 1, 1)
    if hp_frac < 1 then
        pix(s, px, py+1, 0)
    end
end

-- Draw an enemy queen (crown + body)
local function draw_queen_enemy(px, py, hp_frac)
    -- crown points
    pix(s, px-2, py-4, 1)
    pix(s, px, py-5, 1)
    pix(s, px+2, py-4, 1)
    rectf(s, px-2, py-3, 5, 2, 1)
    -- body
    rectf(s, px-2, py-1, 5, 3, 1)
    -- base
    rectf(s, px-3, py+2, 7, 2, 1)
    if hp_frac < 1 then
        pix(s, px-1, py, 0)
        pix(s, px+1, py, 0)
    end
end

-- Draw any enemy by type
local function draw_enemy(e)
    local px = math.floor(e.x)
    local py = math.floor(e.y)
    local hp_frac = e.hp / e.max_hp
    if e.etype == E_KNIGHT then
        draw_knight_enemy(px, py, hp_frac)
    elseif e.etype == E_BISHOP then
        draw_bishop_enemy(px, py, hp_frac)
    elseif e.etype == E_ROOK then
        draw_rook_enemy(px, py, hp_frac)
    elseif e.etype == E_QUEEN then
        draw_queen_enemy(px, py, hp_frac)
    else
        draw_pawn(px, py, hp_frac)
    end
end

-- Draw cursor
local function draw_cursor()
    local x = BOARD_X + cursor_x * CELL
    local y = BOARD_Y + cursor_y * CELL
    local blink = game_frame % 20 < 14
    if blink then
        -- corner brackets
        local sz = 3
        -- top-left
        line(s, x, y, x+sz, y, 1)
        line(s, x, y, x, y+sz, 1)
        -- top-right
        line(s, x+CELL-1, y, x+CELL-1-sz, y, 1)
        line(s, x+CELL-1, y, x+CELL-1, y+sz, 1)
        -- bottom-left
        line(s, x, y+CELL-1, x+sz, y+CELL-1, 1)
        line(s, x, y+CELL-1, x, y+CELL-1-sz, 1)
        -- bottom-right
        line(s, x+CELL-1, y+CELL-1, x+CELL-1-sz, y+CELL-1, 1)
        line(s, x+CELL-1, y+CELL-1, x+CELL-1, y+CELL-1-sz, 1)
    end
end

-- Draw attack line (flash)
local function draw_attack_line(x1, y1, x2, y2)
    line(s, x1, y1, x2, y2, 1)
end

------------------------------------------------------------
-- PARTICLE SYSTEM
------------------------------------------------------------
local function add_particle(x, y, count)
    for i = 1, count do
        local angle = math.random() * math.pi * 2
        local spd = 0.5 + math.random() * 1.5
        particles[#particles+1] = {
            x = x, y = y,
            dx = math.cos(angle) * spd,
            dy = math.sin(angle) * spd,
            life = 8 + math.random(8)
        }
    end
end

local function update_particles()
    local i = 1
    while i <= #particles do
        local p = particles[i]
        p.x = p.x + p.dx
        p.y = p.y + p.dy
        p.life = p.life - 1
        if p.life <= 0 then
            particles[i] = particles[#particles]
            particles[#particles] = nil
        else
            i = i + 1
        end
    end
end

local function draw_particles()
    for _, p in ipairs(particles) do
        pix(s, math.floor(p.x), math.floor(p.y), 1)
    end
end

------------------------------------------------------------
-- TOWER LOGIC
------------------------------------------------------------
local function get_tower_at(gx, gy)
    for _, t in ipairs(towers) do
        if t.gx == gx and t.gy == gy then return t end
    end
    return nil
end

local function is_path_cell(gx, gy)
    return path_cells[gx..","..gy] == true
end

local function place_tower(gx, gy)
    if gx < 0 or gx >= COLS or gy < 0 or gy >= ROWS then return false end
    if is_path_cell(gx, gy) then return false end
    if get_tower_at(gx, gy) then return false end
    if gold < ROOK_COST then return false end
    gold = gold - ROOK_COST
    towers[#towers+1] = {
        gx = gx, gy = gy,
        is_queen = false,
        rate = ROOK_RATE,
        dmg = ROOK_DMG,
        cooldown = 0,
        flash = 0,
        target_x = nil, target_y = nil,
    }
    sfx_note(0, "C4", 4)
    return true
end

local function upgrade_tower(t)
    if t.is_queen then return false end
    if gold < QUEEN_COST then return false end
    gold = gold - QUEEN_COST
    t.is_queen = true
    t.rate = QUEEN_RATE
    t.dmg = QUEEN_DMG
    sfx_note(0, "E4", 4)
    sfx_note(1, "G4", 4)
    return true
end

-- Find enemy in line of fire (rank/file, and diagonals for queen)
-- Bishops have dodge: reduced chance to be hit on rank/file (only diag reliable)
local function find_target(t)
    local tx = BOARD_X + t.gx * CELL + CELL/2
    local ty = BOARD_Y + t.gy * CELL + CELL/2
    local best = nil
    local best_dist = 9999

    for _, e in ipairs(enemies) do
        if e.hp > 0 then
            local ex, ey = e.x, e.y
            local ey_grid = math.floor((ey - BOARD_Y) / CELL)
            local ex_grid = math.floor((ex - BOARD_X) / CELL)
            local on_rank = (ey_grid == t.gy)
            local on_file = (ex_grid == t.gx)

            local on_diag = false
            if t.is_queen then
                local ddx = math.abs(ex - tx)
                local ddy = math.abs(ey - ty)
                on_diag = math.abs(ddx - ddy) < CELL
            end

            local can_hit = on_rank or on_file or on_diag

            -- Bishop dodge: when on rank/file (not diagonal), 50% miss chance
            if can_hit and e.etype == E_BISHOP and not on_diag then
                if (game_frame + math.floor(e.x)) % 2 == 0 then
                    can_hit = false
                end
            end

            if can_hit then
                local d = math.abs(ex - tx) + math.abs(ey - ty)
                if d < best_dist then
                    best_dist = d
                    best = e
                end
            end
        end
    end
    return best
end

local function update_towers()
    for _, t in ipairs(towers) do
        if t.flash > 0 then t.flash = t.flash - 1 end
        t.cooldown = t.cooldown - 1
        if t.cooldown <= 0 then
            local target = find_target(t)
            if target then
                target.hp = target.hp - t.dmg
                t.cooldown = t.rate
                t.flash = 4
                t.target_x = target.x
                t.target_y = target.y

                -- Sound
                if t.is_queen then
                    sfx_note(2, "A4", 2)
                else
                    sfx_note(2, "E3", 2)
                end

                -- Hit particle
                add_particle(target.x, target.y, 3)

                if target.hp <= 0 then
                    score = score + target.reward
                    gold = gold + target.reward
                    add_particle(target.x, target.y, 6)
                    sfx_noise(3, 3)
                    -- Special death sounds per type
                    if target.etype == E_QUEEN then
                        sfx_note(0, "C3", 6)
                    elseif target.etype == E_KNIGHT then
                        sfx_note(0, "G3", 3)
                    end
                end
            end
        end
    end
end

------------------------------------------------------------
-- ENEMY LOGIC
------------------------------------------------------------
local function spawn_enemy_typed(hp, speed, reward, etype)
    enemies[#enemies+1] = {
        path_idx = 1,
        path_frac = 0,
        hp = hp,
        max_hp = hp,
        speed = speed,
        reward = reward,
        etype = etype or E_PAWN,
        x = path_points[1].x,
        y = path_points[1].y,
        -- Knight jump timer
        jump_timer = (etype == E_KNIGHT) and 40 or 0,
        -- Bishop lateral offset for visual wobble
        lateral = 0,
    }
end

-- Legacy spawn for demo compatibility
local function spawn_enemy(hp, speed, reward)
    spawn_enemy_typed(hp, speed, reward, E_PAWN)
end

local function update_enemies()
    local i = 1
    while i <= #enemies do
        local e = enemies[i]
        if e.hp <= 0 then
            enemies[i] = enemies[#enemies]
            enemies[#enemies] = nil
        else
            -- Knight: periodically jump forward on path
            if e.etype == E_KNIGHT then
                e.jump_timer = (e.jump_timer or 40) - 1
                if e.jump_timer <= 0 then
                    -- Jump 3 path steps forward
                    local jump = 3
                    e.path_idx = math.min(e.path_idx + jump, #path_points)
                    e.path_frac = 0
                    e.jump_timer = 50 + math.random(20)
                    sfx_note(3, "E5", 1)
                end
            end

            -- Bishop: wobble lateral offset for visual dodge effect
            if e.etype == E_BISHOP then
                e.lateral = math.sin((game_frame or 0) * 0.15 + e.path_idx) * 3
            else
                e.lateral = 0
            end

            -- Move along path
            e.path_frac = e.path_frac + e.speed
            while e.path_frac >= 1 and e.path_idx < #path_points do
                e.path_frac = e.path_frac - 1
                e.path_idx = e.path_idx + 1
            end
            if e.path_idx >= #path_points then
                -- Reached king!
                local dmg = 1
                if e.etype == E_QUEEN then dmg = 2 end
                king_hp = king_hp - dmg
                sfx_note(0, "C2", 8)
                sfx_noise(1, 6)
                if cam_shake then cam_shake(4) end
                add_particle(e.x, e.y, 8)
                enemies[i] = enemies[#enemies]
                enemies[#enemies] = nil
            else
                -- Interpolate position
                local a = path_points[e.path_idx]
                local b = path_points[e.path_idx + 1]
                if b then
                    e.x = a.x + (b.x - a.x) * e.path_frac
                    e.y = a.y + (b.y - a.y) * e.path_frac
                else
                    e.x = a.x
                    e.y = a.y
                end
                -- Apply bishop lateral offset perpendicular to movement
                if e.lateral and e.lateral ~= 0 and b then
                    local mdx = b.x - a.x
                    local mdy = b.y - a.y
                    -- perpendicular: (-dy, dx) normalized-ish
                    if mdx ~= 0 then
                        e.y = e.y + e.lateral
                    elseif mdy ~= 0 then
                        e.x = e.x + e.lateral
                    end
                end
                i = i + 1
            end
        end
    end
end

------------------------------------------------------------
-- WAVE MANAGEMENT
------------------------------------------------------------
local function start_wave()
    wave_num = wave_num + 1
    local count, queue = wave_config(wave_num)
    wave_total = count
    wave_queue = queue
    wave_spawned = 0
    spawn_timer = 0
    wave_active = true
end

local function update_waves()
    if not wave_active then
        wave_timer = wave_timer - 1
        if wave_timer <= 0 then
            start_wave()
        end
        return
    end

    spawn_timer = spawn_timer - 1
    if spawn_timer <= 0 and wave_spawned < wave_total then
        wave_spawned = wave_spawned + 1
        local cfg = wave_queue[wave_spawned]
        if cfg then
            spawn_enemy_typed(cfg.hp, cfg.speed, cfg.reward, cfg.etype)
        end
        -- Vary spawn timing: knights/rooks come in bursts
        local gap = 20
        if cfg and cfg.etype == E_ROOK then gap = 12 end
        if cfg and cfg.etype == E_KNIGHT then gap = 15 end
        spawn_timer = gap
    end

    -- Wave complete when all spawned and all dead
    if wave_spawned >= wave_total and #enemies == 0 then
        wave_active = false
        wave_timer = 90  -- pause between waves
        -- bonus gold
        gold = gold + 5
        sfx_note(0, "C5", 3)
        sfx_note(1, "E5", 3)
    end
end

------------------------------------------------------------
-- GAME INIT
------------------------------------------------------------
local function init_game()
    build_path()
    gold = BASE_GOLD
    score = 0
    wave_num = 0
    king_hp = KING_MAX_HP
    towers = {}
    enemies = {}
    projectiles = {}
    particles = {}
    cursor_x = 4
    cursor_y = 3
    wave_timer = 60
    wave_active = false
    wave_spawned = 0
    wave_total = 0
    wave_queue = {}
    spawn_timer = 0
    paused = false
    game_frame = 0
    attract_mode = false
end

------------------------------------------------------------
-- PLAY SCENE
------------------------------------------------------------
local function handle_input()
    -- D-pad movement
    if btnp("left") then cursor_x = clamp(cursor_x - 1, 0, COLS-1) end
    if btnp("right") then cursor_x = clamp(cursor_x + 1, 0, COLS-1) end
    if btnp("up") then cursor_y = clamp(cursor_y - 1, 0, ROWS-1) end
    if btnp("down") then cursor_y = clamp(cursor_y + 1, 0, ROWS-1) end

    -- A button: place or upgrade
    if btnp("a") then
        local t = get_tower_at(cursor_x, cursor_y)
        if t then
            upgrade_tower(t)
        else
            place_tower(cursor_x, cursor_y)
        end
    end

    -- SELECT: pause
    if btnp("select") then
        paused = not paused
    end

    -- Touch input
    if touch_start and touch_start() then
        local tx, ty = touch_pos()
        local gx = math.floor((tx - BOARD_X) / CELL)
        local gy = math.floor((ty - BOARD_Y) / CELL)
        if gx >= 0 and gx < COLS and gy >= 0 and gy < ROWS then
            cursor_x = gx
            cursor_y = gy
            local t = get_tower_at(gx, gy)
            if t then
                upgrade_tower(t)
            else
                place_tower(gx, gy)
            end
        end
    end
end

------------------------------------------------------------
-- HUD
------------------------------------------------------------
local function draw_hud()
    -- Top bar
    rectf(s, 0, 0, W, 7, 0)
    -- Gold
    text(s, "G:"..gold, 1, 1, 1)
    -- Score
    text(s, "S:"..score, 40, 1, 1)
    -- Wave
    local wt = "W:"..wave_num
    if not wave_active and wave_timer > 0 and wave_num > 0 then
        wt = wt.." NEXT"
    end
    text(s, wt, 75, 1, 1)
    -- King HP (hearts)
    local hp_str = ""
    for i = 1, KING_MAX_HP do
        if i <= king_hp then hp_str = hp_str .. "K" else hp_str = hp_str .. "." end
    end
    text(s, hp_str, 120, 1, 1)

    -- Right panel info (tower cost)
    local info_x = BOARD_X + BOARD_W + 3
    local info_y = BOARD_Y
    text(s, "ROOK", info_x, info_y, 1)
    text(s, "$"..ROOK_COST, info_x, info_y+7, 1)
    text(s, "QUEEN", info_x, info_y+18, 1)
    text(s, "$"..QUEEN_COST, info_x, info_y+25, 1)

    -- Cursor info
    local t = get_tower_at(cursor_x, cursor_y)
    if t then
        local name = t.is_queen and "QUEEN" or "ROOK"
        text(s, name, info_x, info_y+40, 1)
        if not t.is_queen then
            text(s, "[A]UP", info_x, info_y+48, 1)
        end
    elseif not is_path_cell(cursor_x, cursor_y) then
        text(s, "[A]BLD", info_x, info_y+40, 1)
    else
        text(s, "PATH", info_x, info_y+40, 1)
    end

    -- Chess notation for cursor
    local nota = FILE_LETTERS[cursor_x+1] .. tostring(ROWS - cursor_y)
    text(s, nota, info_x, info_y + 58, 1)

    -- Enemy type indicator during wave
    if wave_active and wave_num >= 2 then
        local types_str = ""
        if wave_num >= 2 then types_str = types_str .. "N" end
        if wave_num >= 4 then types_str = types_str .. "B" end
        if wave_num >= 6 then types_str = types_str .. "R" end
        if wave_num >= 8 then types_str = types_str .. "Q" end
        text(s, types_str, info_x, info_y + 68, 1)
    end
end

------------------------------------------------------------
-- PLAY UPDATE & DRAW
------------------------------------------------------------
function play_init()
    init_game()
end

function play_update()
    game_frame = game_frame + 1

    if paused then
        if btnp("select") or btnp("start") then
            paused = false
        end
        return
    end

    handle_input()
    update_towers()
    update_enemies()
    update_waves()
    update_particles()

    -- Check game over
    if king_hp <= 0 then
        if score > high_score then high_score = score end
        go("gameover")
    end
end

function play_draw()
    s = screen()
    cls(s, 0)

    draw_board()
    draw_path()

    -- Draw towers
    for _, t in ipairs(towers) do
        if t.is_queen then
            draw_queen_tower(t.gx, t.gy)
        else
            draw_rook(t.gx, t.gy)
        end
        -- Attack flash line
        if t.flash > 0 and t.target_x then
            local tx = BOARD_X + t.gx * CELL + CELL/2
            local ty = BOARD_Y + t.gy * CELL + CELL/2
            draw_attack_line(tx, ty, t.target_x, t.target_y)
        end
    end

    -- Draw enemies
    for _, e in ipairs(enemies) do
        if e.hp > 0 then
            draw_enemy(e)
        end
    end

    draw_particles()
    draw_cursor()
    draw_hud()

    -- Pause overlay
    if paused then
        rectf(s, 40, 50, 80, 20, 0)
        rect(s, 40, 50, 80, 20, 1)
        text(s, "PAUSED", 80, 57, 1, ALIGN_CENTER)
    end
end

------------------------------------------------------------
-- GAME OVER SCENE
------------------------------------------------------------
local gameover_timer = 0

function gameover_init()
    gameover_timer = 0
end

function gameover_update()
    gameover_timer = gameover_timer + 1
    if gameover_timer > 30 then
        if btnp("start") or btnp("a") then
            go("title")
        end
        -- Touch to restart
        if touch_start and touch_start() then
            go("title")
        end
    end
end

function gameover_draw()
    s = screen()
    cls(s, 0)

    text(s, "GAME OVER", 80, 30, 1, ALIGN_CENTER)
    text(s, "SCORE: "..score, 80, 45, 1, ALIGN_CENTER)
    text(s, "WAVE: "..wave_num, 80, 55, 1, ALIGN_CENTER)
    text(s, "BEST: "..high_score, 80, 65, 1, ALIGN_CENTER)

    if gameover_timer > 30 then
        local blink = gameover_timer % 30 < 20
        if blink then
            text(s, "PRESS START", 80, 85, 1, ALIGN_CENTER)
        end
    end
end

------------------------------------------------------------
-- TITLE SCENE (with attract/demo mode)
------------------------------------------------------------
local title_timer = 0
local title_attract = false
local demo_towers, demo_enemies, demo_particles, demo_frame
local demo_wave_timer, demo_spawn_timer, demo_spawned

local function demo_init()
    build_path()
    demo_towers = {}
    demo_enemies = {}
    demo_particles = {}
    demo_frame = 0
    demo_spawn_timer = 0
    demo_spawned = 0

    -- Pre-place some rooks and queens for demo
    local placements = {
        {gx=2, gy=1, q=false},
        {gx=5, gy=0, q=false},
        {gx=3, gy=3, q=true},
        {gx=0, gy=5, q=false},
        {gx=5, gy=5, q=true},
        {gx=2, gy=7, q=false},
        {gx=6, gy=6, q=false},
    }
    for _, p in ipairs(placements) do
        if not is_path_cell(p.gx, p.gy) then
            demo_towers[#demo_towers+1] = {
                gx = p.gx, gy = p.gy,
                is_queen = p.q,
                rate = p.q and QUEEN_RATE or ROOK_RATE,
                dmg = p.q and QUEEN_DMG or ROOK_DMG,
                cooldown = math.random(10, 30),
                flash = 0,
                target_x = nil, target_y = nil,
            }
        end
    end
end

local function demo_update()
    demo_frame = demo_frame + 1

    -- Spawn demo enemies periodically - cycle through types
    demo_spawn_timer = demo_spawn_timer - 1
    if demo_spawn_timer <= 0 then
        demo_spawned = demo_spawned + 1
        -- Cycle through enemy types for demo variety
        local types = {E_PAWN, E_PAWN, E_KNIGHT, E_PAWN, E_BISHOP, E_ROOK}
        local etype = types[((demo_spawned - 1) % #types) + 1]
        local hp = 3
        local spd = 0.4
        if etype == E_KNIGHT then spd = 0.32 end
        if etype == E_ROOK then spd = 0.64 end
        if etype == E_BISHOP then hp = 4; spd = 0.36 end
        demo_enemies[#demo_enemies+1] = {
            path_idx = 1,
            path_frac = 0,
            hp = hp,
            max_hp = hp,
            speed = spd,
            reward = 2,
            etype = etype,
            x = path_points[1].x,
            y = path_points[1].y,
            jump_timer = (etype == E_KNIGHT) and 40 or 0,
            lateral = 0,
        }
        demo_spawn_timer = 25
    end

    -- Update demo enemies
    local i = 1
    while i <= #demo_enemies do
        local e = demo_enemies[i]
        if e.hp <= 0 then
            demo_enemies[i] = demo_enemies[#demo_enemies]
            demo_enemies[#demo_enemies] = nil
        else
            -- Knight jump in demo
            if e.etype == E_KNIGHT then
                e.jump_timer = (e.jump_timer or 40) - 1
                if e.jump_timer <= 0 then
                    e.path_idx = math.min(e.path_idx + 3, #path_points)
                    e.path_frac = 0
                    e.jump_timer = 50 + math.random(20)
                end
            end

            -- Bishop wobble in demo
            if e.etype == E_BISHOP then
                e.lateral = math.sin(demo_frame * 0.15 + e.path_idx) * 3
            else
                e.lateral = 0
            end

            e.path_frac = e.path_frac + e.speed
            while e.path_frac >= 1 and e.path_idx < #path_points do
                e.path_frac = e.path_frac - 1
                e.path_idx = e.path_idx + 1
            end
            if e.path_idx >= #path_points then
                demo_enemies[i] = demo_enemies[#demo_enemies]
                demo_enemies[#demo_enemies] = nil
            else
                local a = path_points[e.path_idx]
                local b = path_points[e.path_idx + 1]
                if b then
                    e.x = a.x + (b.x - a.x) * e.path_frac
                    e.y = a.y + (b.y - a.y) * e.path_frac
                else
                    e.x = a.x
                    e.y = a.y
                end
                -- Bishop lateral offset in demo
                if e.lateral and e.lateral ~= 0 and b then
                    local mdx = b.x - a.x
                    local mdy = b.y - a.y
                    if mdx ~= 0 then
                        e.y = e.y + e.lateral
                    elseif mdy ~= 0 then
                        e.x = e.x + e.lateral
                    end
                end
                i = i + 1
            end
        end
    end

    -- Demo tower firing
    for _, t in ipairs(demo_towers) do
        if t.flash > 0 then t.flash = t.flash - 1 end
        t.cooldown = t.cooldown - 1
        if t.cooldown <= 0 then
            local tx = BOARD_X + t.gx * CELL + CELL/2
            local ty = BOARD_Y + t.gy * CELL + CELL/2
            local best, best_d = nil, 9999
            for _, e in ipairs(demo_enemies) do
                if e.hp > 0 then
                    local ey_grid = math.floor((e.y - BOARD_Y) / CELL)
                    local ex_grid = math.floor((e.x - BOARD_X) / CELL)
                    local hit = (ey_grid == t.gy) or (ex_grid == t.gx)
                    if t.is_queen then
                        local dx = math.abs(e.x - tx)
                        local dy = math.abs(e.y - ty)
                        if math.abs(dx - dy) < CELL then hit = true end
                    end
                    -- Bishop dodge in demo too
                    if hit and e.etype == E_BISHOP then
                        if (demo_frame + math.floor(e.x)) % 2 == 0 then
                            hit = false
                        end
                    end
                    if hit then
                        local d = math.abs(e.x - tx) + math.abs(e.y - ty)
                        if d < best_d then best_d = d; best = e end
                    end
                end
            end
            if best then
                best.hp = best.hp - t.dmg
                t.cooldown = t.rate
                t.flash = 4
                t.target_x = best.x
                t.target_y = best.y
                if best.hp <= 0 then
                    -- particle burst
                    for j = 1, 5 do
                        local ang = math.random() * math.pi * 2
                        local spd = 0.5 + math.random() * 1
                        demo_particles[#demo_particles+1] = {
                            x=best.x, y=best.y,
                            dx=math.cos(ang)*spd, dy=math.sin(ang)*spd,
                            life=8+math.random(6)
                        }
                    end
                end
            else
                t.cooldown = 5
            end
        end
    end

    -- Update demo particles
    local pi = 1
    while pi <= #demo_particles do
        local p = demo_particles[pi]
        p.x = p.x + p.dx
        p.y = p.y + p.dy
        p.life = p.life - 1
        if p.life <= 0 then
            demo_particles[pi] = demo_particles[#demo_particles]
            demo_particles[#demo_particles] = nil
        else
            pi = pi + 1
        end
    end
end

local function demo_draw()
    draw_board()

    -- Draw path dots
    for i = 1, #path_points - 1 do
        local a = path_points[i]
        local b = path_points[i+1]
        if demo_frame % 2 == 0 then
            local mx = math.floor((a.x + b.x) / 2)
            local my = math.floor((a.y + b.y) / 2)
            pix(s, mx, my, 1)
        end
    end

    -- King
    local kp = path_points[#path_points]
    if kp then draw_king(kp.x, kp.y) end

    -- Demo towers
    for _, t in ipairs(demo_towers) do
        if t.is_queen then
            draw_queen_tower(t.gx, t.gy)
        else
            draw_rook(t.gx, t.gy)
        end
        if t.flash > 0 and t.target_x then
            local tx = BOARD_X + t.gx * CELL + CELL/2
            local ty = BOARD_Y + t.gy * CELL + CELL/2
            line(s, tx, ty, t.target_x, t.target_y, 1)
        end
    end

    -- Demo enemies - using draw_enemy for type-specific rendering
    for _, e in ipairs(demo_enemies) do
        if e.hp > 0 then
            draw_enemy(e)
        end
    end

    -- Demo particles
    for _, p in ipairs(demo_particles) do
        pix(s, math.floor(p.x), math.floor(p.y), 1)
    end
end

function title_init()
    title_timer = 0
    title_attract = false
end

function title_update()
    title_timer = title_timer + 1

    -- Any button exits attract or starts game
    if btnp("start") or btnp("a") or btnp("b")
       or btnp("up") or btnp("down") or btnp("left") or btnp("right") then
        if title_attract then
            title_attract = false
            title_timer = 0
            return
        end
        go("play")
        return
    end

    -- Touch to start
    if touch_start and touch_start() then
        if title_attract then
            title_attract = false
            title_timer = 0
            return
        end
        go("play")
        return
    end

    -- Enter attract mode after idle
    if not title_attract and title_timer >= ATTRACT_IDLE_FRAMES then
        title_attract = true
        demo_init()
    end

    if title_attract then
        demo_update()
    end
end

function title_draw()
    s = screen()
    cls(s, 0)

    if title_attract then
        -- Demo mode: show gameplay + clock overlay
        demo_draw()

        -- Clock in top-right
        local blink = title_timer % 30 < 15
        draw_clock(120, 1, 1, blink)

        -- "DEMO" label
        text(s, "DEMO", 1, 1, 1)

        -- Scrolling title at bottom
        rectf(s, 0, 110, W, 10, 0)
        text(s, "ROOK TOWER - PRESS START", 80, 112, 1, ALIGN_CENTER)
    else
        -- Title screen
        -- Large title
        text(s, "ROOK TOWER", 80, 20, 1, ALIGN_CENTER)

        -- Draw decorative rook
        local rx, ry = 68, 38
        rectf(s, rx+4, ry+16, 12, 4, 1)
        rectf(s, rx+5, ry+6, 10, 10, 1)
        rectf(s, rx+4, ry+2, 4, 4, 1)
        rectf(s, rx+12, ry+2, 4, 4, 1)
        rectf(s, rx+8, ry+4, 4, 2, 1)

        -- Subtitle
        text(s, "CHESS TOWER DEFENSE", 80, 65, 1, ALIGN_CENTER)

        -- Instructions
        local blink = title_timer % 30 < 20
        if blink then
            text(s, "PRESS START", 80, 85, 1, ALIGN_CENTER)
        end

        -- High score
        if high_score > 0 then
            text(s, "BEST: "..high_score, 80, 100, 1, ALIGN_CENTER)
        end

        -- Clock at bottom
        local cblink = title_timer % 60 < 30
        draw_clock(62, 110, 1, cblink)
    end
end

------------------------------------------------------------
-- ENTRY POINTS
------------------------------------------------------------
function _init()
    mode(1)
    build_path()
end

function _start()
    go("title")
end
