-- CASTLE DEFENSE - A Castling-Based Defense Game
-- Mono Chess Wars Contest Entry
-- Evolved: scene system, fixed audio, rook-to-queen upgrade
----------------------------------------------

-- Polyfills for headless environments
if not frame then
    local _fc = 0
    frame = function() _fc = _fc + 1; return _fc end
end
if not touch_start then touch_start = function() return false end end
if not touch_pos then touch_pos = function() return 0, 0 end end
if not touch_end then touch_end = function() return false end end
if not cam_shake then cam_shake = function() end end
if not go then go = function() end end

------------------------------------------------------------
-- CONSTANTS
------------------------------------------------------------
local SW, SH = 160, 120
local COLS, ROWS = 20, 14
local CELL = 8
local HUD_H = 8
local GRID_Y = HUD_H

-- Colors (1-bit mode)
local BLK = 0
local WHT = 1

-- Directions
local DIR_LEFT = -1
local DIR_RIGHT = 1

-- Queen upgrade
local QUEEN_UPGRADE_COST = 3   -- moves to upgrade a rook to queen
local QUEEN_DMG_RANGE = 14     -- queen attacks at greater range
local QUEEN_DMG = 2            -- queen does double damage

------------------------------------------------------------
-- GLOBALS
------------------------------------------------------------
local s              -- screen surface
local f              -- frame counter

-- King
local king = {}      -- {gx, gy, side} side: -1=left, 1=right
local king_flash = 0
local king_danger = 0

-- Rooks (walls) - now can be queens too
local rooks = {}     -- {gx, gy, hp, max_hp, is_queen}
local ROOK_MAX_HP = 3

-- Cursor
local cx, cy = 10, 7
local cursor_mode = 0  -- 0=place, 1=selected rook to move, 2=upgrade prompt
local selected_rook = nil

-- Enemies
local enemies = {}
local particles = {}
local floats = {}    -- floating text

-- Wave system
local wave_num = 0
local wave_timer = 0
local wave_active = false
local wave_enemies_left = 0
local spawn_timer = 0
local spawn_side = 1  -- which side enemies come from

-- Resources
local moves = 5       -- currency: rook placements cost moves
local score = 0
local lives = 3

-- Castle mechanic
local castle_ready = true
local castle_cooldown = 0
local CASTLE_CD_MAX = 300  -- frames between castles
local castle_anim = 0
local castle_anim_max = 30

-- Pause
local pause_sel = 0

-- Demo mode
local demo_timer = 0
local demo_phase = 0
local demo_cx, demo_cy = 10, 7
local demo_action_timer = 0

-- Grid: 0=empty, 1=rook, 2=king, 3=queen
local grid = {}

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
    if segs % 2 >= 1 then rectf(s, x+2, y, 3, 2, col) end
    if math.floor(segs/2) % 2 == 1 then rectf(s, x+5, y+2, 2, 3, col) end
    if math.floor(segs/4) % 2 == 1 then rectf(s, x+5, y+6, 2, 3, col) end
    if math.floor(segs/8) % 2 == 1 then rectf(s, x+2, y+9, 3, 2, col) end
    if math.floor(segs/16) % 2 == 1 then rectf(s, x, y+6, 2, 3, col) end
    if math.floor(segs/32) % 2 == 1 then rectf(s, x, y+2, 2, 3, col) end
    if math.floor(segs/64) % 2 == 1 then rectf(s, x+2, y+5, 3, 2, col) end
end

local function draw_clock(x, y, col)
    local t = date()
    local h = t.hour
    local m = t.min
    draw_seg_digit(x, y, math.floor(h/10), col)
    draw_seg_digit(x+9, y, h%10, col)
    if frame() % 60 < 30 then
        rectf(s, x+17, y+3, 2, 2, col)
        rectf(s, x+17, y+7, 2, 2, col)
    end
    draw_seg_digit(x+21, y, math.floor(m/10), col)
    draw_seg_digit(x+30, y, m%10, col)
end

------------------------------------------------------------
-- UTILITY
------------------------------------------------------------
local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx*dx + dy*dy)
end

local function grid_to_px(gx, gy)
    return gx * CELL, GRID_Y + gy * CELL
end

local function px_to_grid(px, py)
    local gx = math.floor(px / CELL)
    local gy = math.floor((py - GRID_Y) / CELL)
    if gx >= 0 and gx < COLS and gy >= 0 and gy < ROWS then
        return gx, gy
    end
    return nil, nil
end

local function grid_get(gx, gy)
    if gx < 0 or gx >= COLS or gy < 0 or gy >= ROWS then return -1 end
    return grid[gy * COLS + gx] or 0
end

local function grid_set(gx, gy, val)
    if gx >= 0 and gx < COLS and gy >= 0 and gy < ROWS then
        grid[gy * COLS + gx] = val
    end
end

local function spawn_particle(x, y, vx, vy, life, col, sz)
    table.insert(particles, {
        x=x, y=y, vx=vx, vy=vy,
        life=life, max_life=life, col=col, sz=sz or 1
    })
end

local function spawn_burst(x, y, count, speed, col)
    for i = 1, count do
        local a = math.random() * 6.28
        local sp = 0.3 + math.random() * speed
        spawn_particle(x, y, math.cos(a)*sp, math.sin(a)*sp,
            10 + math.random(10), col, 1)
    end
end

local function add_float(x, y, txt, col)
    table.insert(floats, {x=x, y=y, txt=txt, col=col, life=40})
end

local function find_rook_at(gx, gy)
    for i, r in ipairs(rooks) do
        if r.gx == gx and r.gy == gy then return i, r end
    end
    return nil, nil
end

------------------------------------------------------------
-- SOUND EFFECTS (fixed: channel, noteStr, duration)
------------------------------------------------------------
local function sfx_place()
    note(0, "C3", 0.08)
end

local function sfx_castle()
    note(0, "C5", 0.1)
    note(1, "E5", 0.1)
end

local function sfx_hit()
    noise(1, 0.08)
end

local function sfx_kill()
    note(0, "C6", 0.06)
end

local function sfx_wave()
    note(0, "G4", 0.15)
    note(1, "C5", 0.15)
end

local function sfx_danger()
    noise(0, 0.06)
end

local function sfx_gameover()
    note(0, "E3", 0.2)
    note(1, "C3", 0.2)
end

local function sfx_upgrade()
    note(0, "E5", 0.08)
    note(1, "G5", 0.08)
end

------------------------------------------------------------
-- DRAWING: CHESS PIECES
------------------------------------------------------------
local function draw_king(px, py, col)
    -- Crown shape: base + cross on top
    rectf(s, px+1, py+5, 6, 3, col)    -- base
    rectf(s, px+2, py+3, 4, 2, col)    -- body
    rectf(s, px+3, py+1, 2, 2, col)    -- head
    pix(s, px+4, py, col)              -- cross top
    pix(s, px+3, py+1, col)            -- cross left
    pix(s, px+5, py+1, col)            -- cross right
end

local function draw_rook_piece(px, py, col)
    -- Rook/tower shape: crenellated top
    rectf(s, px+1, py+4, 6, 4, col)    -- base
    rectf(s, px+2, py+2, 4, 2, col)    -- body
    -- Crenellations (battlements)
    pix(s, px+1, py+1, col)
    pix(s, px+3, py+1, col)
    pix(s, px+5, py+1, col)
    pix(s, px+7, py+1, col)
    rectf(s, px+1, py+2, 1, 1, col)
    rectf(s, px+3, py+2, 1, 1, col)
    rectf(s, px+5, py+2, 1, 1, col)
    rectf(s, px+7, py+2, 1, 1, col)
end

local function draw_queen_piece(px, py, col)
    -- Queen: crowned rook with wider body and crown points
    rectf(s, px+1, py+5, 6, 3, col)    -- base
    rectf(s, px+2, py+3, 4, 2, col)    -- body
    -- Crown points (3 prongs)
    pix(s, px+1, py+1, col)
    pix(s, px+4, py, col)
    pix(s, px+7, py+1, col)
    rectf(s, px+1, py+2, 7, 1, col)    -- crown band
end

local function draw_enemy_pawn(px, py, col)
    -- Simple pawn: round head + triangular body
    circf(s, px+4, py+2, 2, col)
    rectf(s, px+2, py+4, 4, 3, col)
    rectf(s, px+1, py+6, 6, 2, col)
end

local function draw_enemy_knight(px, py, col)
    -- Knight: L-shape head
    rectf(s, px+2, py+1, 4, 3, col)
    rectf(s, px+4, py+0, 2, 2, col)
    rectf(s, px+1, py+4, 6, 4, col)
end

local function draw_enemy_bishop(px, py, col)
    -- Bishop: pointed top
    pix(s, px+4, py, col)
    rectf(s, px+3, py+1, 3, 2, col)
    rectf(s, px+2, py+3, 4, 2, col)
    rectf(s, px+1, py+5, 6, 3, col)
end

------------------------------------------------------------
-- INIT
------------------------------------------------------------
local function init_grid()
    grid = {}
    for i = 0, COLS * ROWS - 1 do
        grid[i] = 0
    end
end

local function reset_game()
    init_grid()
    rooks = {}
    enemies = {}
    particles = {}
    floats = {}

    -- Place king on right side (kingside)
    king = {gx=16, gy=7, side=DIR_RIGHT}
    grid_set(king.gx, king.gy, 2)
    king_flash = 0
    king_danger = 0

    -- Place initial rook walls near king
    local init_rooks = {
        {15, 6}, {15, 7}, {15, 8},  -- left wall
        {17, 6}, {17, 7}, {17, 8},  -- right wall
        {16, 6}, {16, 8},           -- top/bottom
    }
    for _, pos in ipairs(init_rooks) do
        local r = {gx=pos[1], gy=pos[2], hp=ROOK_MAX_HP, max_hp=ROOK_MAX_HP, is_queen=false}
        table.insert(rooks, r)
        grid_set(pos[1], pos[2], 1)
    end

    moves = 5
    score = 0
    lives = 3
    wave_num = 0
    wave_timer = 120  -- short delay before first wave
    wave_active = false
    wave_enemies_left = 0
    spawn_timer = 0
    spawn_side = DIR_LEFT
    castle_ready = true
    castle_cooldown = 0
    castle_anim = 0
    cursor_mode = 0
    selected_rook = nil
    cx, cy = 10, 7
    pause_sel = 0
end

------------------------------------------------------------
-- ENEMY SPAWNING
------------------------------------------------------------
local function spawn_enemy(etype, side)
    local e = {
        type = etype,
        side = side,
        hp = 0, max_hp = 0,
        speed = 0, dmg = 1,
        x = 0, y = 0,
        target_gx = king.gx, target_gy = king.gy,
        stun = 0,
    }

    -- Stats by type
    if etype == "pawn" then
        e.max_hp = 1 + math.floor(wave_num / 3)
        e.speed = 0.3 + wave_num * 0.01
        e.dmg = 1
    elseif etype == "knight" then
        e.max_hp = 3 + math.floor(wave_num / 2)
        e.speed = 0.5 + wave_num * 0.01
        e.dmg = 2
    elseif etype == "bishop" then
        e.max_hp = 2 + math.floor(wave_num / 2)
        e.speed = 0.4 + wave_num * 0.015
        e.dmg = 1
    end
    e.hp = e.max_hp

    -- Spawn position at edge
    local gy = math.random(1, ROWS - 2)
    if side == DIR_LEFT then
        e.x = -4
    else
        e.x = SW + 4
    end
    e.y = GRID_Y + gy * CELL + 4

    table.insert(enemies, e)
end

local function start_wave()
    wave_num = wave_num + 1
    wave_active = true
    spawn_timer = 0

    -- Determine spawn count and types
    local base = 3 + wave_num * 2
    wave_enemies_left = base

    -- Alternate spawn sides, sometimes both
    if wave_num % 3 == 0 then
        spawn_side = 0  -- both sides
    elseif wave_num % 2 == 0 then
        spawn_side = DIR_RIGHT
    else
        spawn_side = DIR_LEFT
    end

    sfx_wave()
    add_float(SW/2, SH/2, "WAVE "..wave_num, WHT)

    -- Bonus moves each wave
    moves = moves + 2 + math.floor(wave_num / 2)
end

------------------------------------------------------------
-- CASTLE MECHANIC
------------------------------------------------------------
local function perform_castle()
    if not castle_ready then return false end

    -- Find a rook on the opposite side to swap with
    local new_side = -king.side
    local best_rook = nil
    local best_dist = 999

    for i, r in ipairs(rooks) do
        -- Check if rook is on the target side
        local is_target_side = false
        if new_side == DIR_LEFT and r.gx < COLS/2 then
            is_target_side = true
        elseif new_side == DIR_RIGHT and r.gx >= COLS/2 then
            is_target_side = true
        end

        if is_target_side then
            local d = dist(r.gx, r.gy, COLS/2, ROWS/2)
            if d < best_dist then
                best_dist = d
                best_rook = i
            end
        end
    end

    if not best_rook then
        add_float(king.gx*CELL+4, GRID_Y+king.gy*CELL, "NO ROOK!", WHT)
        return false
    end

    local r = rooks[best_rook]

    -- Swap positions
    local old_kgx, old_kgy = king.gx, king.gy
    grid_set(old_kgx, old_kgy, 0)
    grid_set(r.gx, r.gy, 0)

    king.gx, king.gy = r.gx, r.gy
    r.gx, r.gy = old_kgx, old_kgy
    king.side = new_side

    grid_set(king.gx, king.gy, 2)
    grid_set(r.gx, r.gy, r.is_queen and 3 or 1)

    -- Update enemy targets
    for _, e in ipairs(enemies) do
        e.target_gx = king.gx
        e.target_gy = king.gy
    end

    castle_ready = false
    castle_cooldown = CASTLE_CD_MAX
    castle_anim = castle_anim_max

    sfx_castle()
    spawn_burst(king.gx*CELL+4, GRID_Y+king.gy*CELL+4, 12, 2, WHT)
    spawn_burst(r.gx*CELL+4, GRID_Y+r.gy*CELL+4, 8, 1.5, WHT)
    add_float(king.gx*CELL, GRID_Y+king.gy*CELL-4, "CASTLE!", WHT)
    cam_shake(4)

    return true
end

------------------------------------------------------------
-- ROOK PLACEMENT / MOVEMENT / UPGRADE
------------------------------------------------------------
local function can_place_rook(gx, gy)
    if gx < 0 or gx >= COLS or gy < 0 or gy >= ROWS then return false end
    return grid_get(gx, gy) == 0
end

local function place_rook(gx, gy)
    if not can_place_rook(gx, gy) then return false end
    if moves < 1 then
        add_float(gx*CELL, GRID_Y+gy*CELL, "NO MOVES", WHT)
        return false
    end

    local r = {gx=gx, gy=gy, hp=ROOK_MAX_HP, max_hp=ROOK_MAX_HP, is_queen=false}
    table.insert(rooks, r)
    grid_set(gx, gy, 1)
    moves = moves - 1
    sfx_place()
    spawn_burst(gx*CELL+4, GRID_Y+gy*CELL+4, 4, 1, WHT)
    return true
end

local function upgrade_rook_to_queen(ri)
    local r = rooks[ri]
    if not r or r.is_queen then
        add_float(r.gx*CELL, GRID_Y+r.gy*CELL, "ALREADY QUEEN", WHT)
        return false
    end
    if moves < QUEEN_UPGRADE_COST then
        add_float(r.gx*CELL, GRID_Y+r.gy*CELL, "NEED "..QUEEN_UPGRADE_COST.."M", WHT)
        return false
    end

    moves = moves - QUEEN_UPGRADE_COST
    r.is_queen = true
    r.hp = r.max_hp  -- full heal on upgrade
    grid_set(r.gx, r.gy, 3)
    sfx_upgrade()
    spawn_burst(r.gx*CELL+4, GRID_Y+r.gy*CELL+4, 8, 1.5, WHT)
    add_float(r.gx*CELL, GRID_Y+r.gy*CELL-4, "QUEEN!", WHT)
    return true
end

local function can_move_rook(r, gx, gy)
    -- Rooks move in straight lines (like chess rooks)
    -- Queens can also move diagonally
    if r.is_queen then
        -- Queen: rank, file, or diagonal
        local dx = math.abs(gx - r.gx)
        local dy = math.abs(gy - r.gy)
        if r.gx ~= gx and r.gy ~= gy and dx ~= dy then return false end
        if r.gx == gx and r.gy == gy then return false end
    else
        if r.gx ~= gx and r.gy ~= gy then return false end
        if r.gx == gx and r.gy == gy then return false end
    end

    -- Check path is clear
    local dx = gx > r.gx and 1 or (gx < r.gx and -1 or 0)
    local dy = gy > r.gy and 1 or (gy < r.gy and -1 or 0)
    local cx2, cy2 = r.gx + dx, r.gy + dy
    while cx2 ~= gx or cy2 ~= gy do
        if grid_get(cx2, cy2) ~= 0 then return false end
        cx2 = cx2 + dx
        cy2 = cy2 + dy
    end
    return grid_get(gx, gy) == 0
end

local function move_rook(ri, gx, gy)
    local r = rooks[ri]
    if not can_move_rook(r, gx, gy) then
        add_float(gx*CELL, GRID_Y+gy*CELL, "BLOCKED", WHT)
        return false
    end

    grid_set(r.gx, r.gy, 0)
    r.gx, r.gy = gx, gy
    grid_set(gx, gy, r.is_queen and 3 or 1)
    sfx_place()
    return true
end

------------------------------------------------------------
-- UPDATE
------------------------------------------------------------
local function update_enemies()
    local i = 1
    while i <= #enemies do
        local e = enemies[i]
        local removed = false

        if e.stun > 0 then
            e.stun = e.stun - 1
        else
            -- Move toward king
            local tx = king.gx * CELL + 4
            local ty = GRID_Y + king.gy * CELL + 4
            local dx, dy = tx - e.x, ty - e.y
            local d = math.sqrt(dx*dx + dy*dy)

            if d > 1 then
                local nx, ny = dx/d, dy/d
                local move_x = nx * e.speed
                local move_y = ny * e.speed

                local hit_rook = false
                for ri, r in ipairs(rooks) do
                    local rpx, rpy = grid_to_px(r.gx, r.gy)
                    if dist(e.x + move_x, e.y + move_y, rpx + 4, rpy + 4) < 6 then
                        -- Attack rook
                        r.hp = r.hp - 1
                        e.stun = 15
                        sfx_hit()
                        spawn_burst(e.x, e.y, 3, 0.8, WHT)

                        if r.hp <= 0 then
                            grid_set(r.gx, r.gy, 0)
                            spawn_burst(rpx+4, rpy+4, 8, 1.5, WHT)
                            table.remove(rooks, ri)
                        end
                        hit_rook = true
                        break
                    end
                end

                if not hit_rook then
                    e.x = e.x + move_x
                    e.y = e.y + move_y
                end
            end

            -- Check if reached king
            local kpx, kpy = grid_to_px(king.gx, king.gy)
            if dist(e.x, e.y, kpx+4, kpy+4) < 5 then
                lives = lives - e.dmg
                king_danger = 30
                sfx_danger()
                cam_shake(3)
                spawn_burst(kpx+4, kpy+4, 6, 1.2, WHT)
                add_float(kpx, kpy-8, "-"..e.dmg, WHT)
                table.remove(enemies, i)
                removed = true
            end
        end

        if not removed then i = i + 1 end
    end
end

local function update_rook_defense()
    -- Rooks damage adjacent enemies each second; queens have more range and damage
    if f % 30 == 0 then
        for _, r in ipairs(rooks) do
            local rpx, rpy = grid_to_px(r.gx, r.gy)
            local atk_range = r.is_queen and QUEEN_DMG_RANGE or 10
            local atk_dmg = r.is_queen and QUEEN_DMG or 1
            for ei = #enemies, 1, -1 do
                local e = enemies[ei]
                if dist(e.x, e.y, rpx+4, rpy+4) < atk_range then
                    e.hp = e.hp - atk_dmg
                    if e.hp <= 0 then
                        local pts = r.is_queen and 15 or 10
                        score = score + pts
                        sfx_kill()
                        spawn_burst(e.x, e.y, 6, 1.5, WHT)
                        add_float(e.x, e.y-4, "+"..pts, WHT)
                        table.remove(enemies, ei)
                    end
                end
            end
        end
    end
end

local function update_particles()
    local i = 1
    while i <= #particles do
        local p = particles[i]
        p.x = p.x + p.vx
        p.y = p.y + p.vy
        p.vy = p.vy + 0.02
        p.life = p.life - 1
        if p.life <= 0 then
            table.remove(particles, i)
        else
            i = i + 1
        end
    end
end

local function update_floats()
    local i = 1
    while i <= #floats do
        local fl = floats[i]
        fl.y = fl.y - 0.4
        fl.life = fl.life - 1
        if fl.life <= 0 then
            table.remove(floats, i)
        else
            i = i + 1
        end
    end
end

local function update_waves()
    if wave_active then
        spawn_timer = spawn_timer - 1
        if spawn_timer <= 0 and wave_enemies_left > 0 then
            -- Spawn an enemy
            local etype = "pawn"
            if wave_num >= 3 and math.random() < 0.3 then etype = "knight" end
            if wave_num >= 5 and math.random() < 0.2 then etype = "bishop" end

            local side = spawn_side
            if side == 0 then
                side = math.random() < 0.5 and DIR_LEFT or DIR_RIGHT
            end

            spawn_enemy(etype, side)
            wave_enemies_left = wave_enemies_left - 1
            spawn_timer = 30 + math.random(20)
        end

        -- Wave complete when all spawned and all dead
        if wave_enemies_left <= 0 and #enemies == 0 then
            wave_active = false
            wave_timer = 180  -- pause between waves
            score = score + wave_num * 25
            add_float(SW/2, SH/2, "WAVE CLEAR! +"..wave_num*25, WHT)
        end
    else
        wave_timer = wave_timer - 1
        if wave_timer <= 0 then
            start_wave()
        end
    end
end

local function update_castle_cd()
    if not castle_ready then
        castle_cooldown = castle_cooldown - 1
        if castle_cooldown <= 0 then
            castle_ready = true
            add_float(SW/2, SH/2-10, "CASTLE READY", WHT)
        end
    end
    if castle_anim > 0 then castle_anim = castle_anim - 1 end
    if king_danger > 0 then king_danger = king_danger - 1 end
    if king_flash > 0 then king_flash = king_flash - 1 end
end

------------------------------------------------------------
-- PLAY INPUT
------------------------------------------------------------
local function handle_play_input()
    -- D-pad movement
    if btnp("left") and cx > 0 then cx = cx - 1 end
    if btnp("right") and cx < COLS-1 then cx = cx + 1 end
    if btnp("up") and cy > 0 then cy = cy - 1 end
    if btnp("down") and cy < ROWS-1 then cy = cy + 1 end

    -- A button: place or select/move rook
    if btnp("a") then
        if cursor_mode == 0 then
            -- Check if there's a rook here to select
            local ri, r = find_rook_at(cx, cy)
            if ri then
                cursor_mode = 1
                selected_rook = ri
            else
                -- Try to place new rook
                place_rook(cx, cy)
            end
        elseif cursor_mode == 1 then
            -- Move selected rook to cursor
            if selected_rook and selected_rook <= #rooks then
                move_rook(selected_rook, cx, cy)
            end
            cursor_mode = 0
            selected_rook = nil
        end
    end

    -- B button: Castle! or upgrade if rook selected
    if btnp("b") then
        if cursor_mode == 1 and selected_rook and selected_rook <= #rooks then
            -- If rook is selected, B upgrades to queen
            upgrade_rook_to_queen(selected_rook)
            cursor_mode = 0
            selected_rook = nil
        elseif cursor_mode == 0 then
            perform_castle()
        end
    end

    -- SELECT button: cancel selection
    if btnp("select") then
        if cursor_mode == 1 then
            cursor_mode = 0
            selected_rook = nil
        end
    end

    -- START: pause
    if btnp("start") then
        go("pause")
    end

    -- Touch input
    if touch_start() then
        local tx, ty = touch_pos()
        local gx, gy = px_to_grid(tx, ty)
        if gx then
            cx, cy = gx, gy
            local ri, r = find_rook_at(gx, gy)
            if ri then
                cursor_mode = 1
                selected_rook = ri
            elseif cursor_mode == 1 and selected_rook then
                if selected_rook <= #rooks then
                    move_rook(selected_rook, gx, gy)
                end
                cursor_mode = 0
                selected_rook = nil
            else
                place_rook(gx, gy)
            end
        end
    end
end

------------------------------------------------------------
-- DRAWING
------------------------------------------------------------
local function draw_grid()
    -- Draw subtle grid dots
    for gx = 0, COLS-1 do
        for gy = 0, ROWS-1 do
            local px, py = grid_to_px(gx, gy)
            if (gx + gy) % 4 == 0 then
                pix(s, px, py, WHT)
            end
        end
    end

    -- Draw board border
    rect(s, 0, GRID_Y, SW, SH - GRID_Y, WHT)
end

local function draw_rooks()
    for _, r in ipairs(rooks) do
        local px, py = grid_to_px(r.gx, r.gy)
        if r.is_queen then
            draw_queen_piece(px, py, WHT)
        else
            draw_rook_piece(px, py, WHT)
        end

        -- HP indicator: dots below
        if r.hp < r.max_hp then
            for h = 0, r.max_hp - 1 do
                local hcol = h < r.hp and WHT or BLK
                pix(s, px + 2 + h * 2, py + 7, hcol)
            end
        end
    end
end

local function draw_king_sprite()
    local px, py = grid_to_px(king.gx, king.gy)

    -- Danger flash
    if king_danger > 0 and f % 6 < 3 then
        rect(s, px-1, py-1, CELL+2, CELL+2, WHT)
    end

    draw_king(px, py, WHT)

    -- Castle animation ring
    if castle_anim > 0 then
        local r = (castle_anim_max - castle_anim) * 0.8
        circ(s, px+4, py+4, math.floor(r), WHT)
    end
end

local function draw_enemies()
    for _, e in ipairs(enemies) do
        local col = WHT
        if e.stun > 0 and f % 4 < 2 then col = BLK end

        if e.type == "pawn" then
            draw_enemy_pawn(math.floor(e.x)-4, math.floor(e.y)-4, col)
        elseif e.type == "knight" then
            draw_enemy_knight(math.floor(e.x)-4, math.floor(e.y)-4, col)
        elseif e.type == "bishop" then
            draw_enemy_bishop(math.floor(e.x)-4, math.floor(e.y)-4, col)
        end

        -- HP bar for tough enemies
        if e.max_hp > 2 then
            local bx = math.floor(e.x) - 3
            local by = math.floor(e.y) - 6
            local bw = 6
            rectf(s, bx, by, bw, 1, BLK)
            local hw = math.floor(bw * e.hp / e.max_hp)
            if hw > 0 then
                rectf(s, bx, by, hw, 1, WHT)
            end
        end
    end
end

local function draw_particles()
    for _, p in ipairs(particles) do
        if p.life > 0 then
            local alpha = p.life / p.max_life
            if alpha > 0.3 then
                pix(s, math.floor(p.x), math.floor(p.y), p.col)
            end
        end
    end
end

local function draw_floats()
    for _, fl in ipairs(floats) do
        if fl.life > 20 or f % 4 < 3 then
            text(s, fl.txt, math.floor(fl.x), math.floor(fl.y), fl.col)
        end
    end
end

local function draw_cursor()
    local px, py = grid_to_px(cx, cy)
    -- Blinking cursor corners
    if f % 20 < 14 then
        local c = WHT
        -- Top-left
        line(s, px, py, px+2, py, c)
        line(s, px, py, px, py+2, c)
        -- Top-right
        line(s, px+7, py, px+5, py, c)
        line(s, px+7, py, px+7, py+2, c)
        -- Bottom-left
        line(s, px, py+7, px+2, py+7, c)
        line(s, px, py+7, px, py+5, c)
        -- Bottom-right
        line(s, px+7, py+7, px+5, py+7, c)
        line(s, px+7, py+7, px+7, py+5, c)
    end

    -- Selected rook indicator
    if cursor_mode == 1 and selected_rook and selected_rook <= #rooks then
        local r = rooks[selected_rook]
        local rpx, rpy = grid_to_px(r.gx, r.gy)
        if f % 10 < 7 then
            rect(s, rpx-1, rpy-1, CELL+2, CELL+2, WHT)
        end
        -- Draw valid move lines (rank/file for rook, +diagonals for queen)
        line(s, rpx+4, GRID_Y, rpx+4, GRID_Y + ROWS*CELL, WHT)
        line(s, 0, rpy+4, COLS*CELL, rpy+4, WHT)
        if r.is_queen then
            -- Diagonal indicators
            for d = 1, math.max(COLS, ROWS) do
                local dx1, dy1 = rpx + 4 + d*CELL, rpy + 4 + d*CELL
                local dx2, dy2 = rpx + 4 - d*CELL, rpy + 4 - d*CELL
                local dx3, dy3 = rpx + 4 + d*CELL, rpy + 4 - d*CELL
                local dx4, dy4 = rpx + 4 - d*CELL, rpy + 4 + d*CELL
                if dx1 < SW and dy1 < SH then pix(s, dx1, dy1, WHT) end
                if dx2 >= 0 and dy2 >= GRID_Y then pix(s, dx2, dy2, WHT) end
                if dx3 < SW and dy3 >= GRID_Y then pix(s, dx3, dy3, WHT) end
                if dx4 >= 0 and dy4 < SH then pix(s, dx4, dy4, WHT) end
            end
        end
        -- Show upgrade hint if rook (not queen)
        if not r.is_queen then
            text(s, "B:QUEEN("..QUEEN_UPGRADE_COST.."M)", rpx-16, rpy-8, WHT)
        end
    end
end

local function draw_hud()
    -- Background bar
    rectf(s, 0, 0, SW, HUD_H, BLK)

    -- Wave info
    text(s, "W"..wave_num, 1, 1, WHT)

    -- Score
    text(s, tostring(score), 30, 1, WHT)

    -- Lives (hearts/crowns)
    for i = 1, lives do
        pix(s, 60 + i*4, 2, WHT)
        pix(s, 61 + i*4, 1, WHT)
        pix(s, 60 + i*4, 3, WHT)
    end

    -- Moves remaining
    text(s, "M:"..moves, 85, 1, WHT)

    -- Castle cooldown
    if castle_ready then
        text(s, "CASTLE", 115, 1, WHT)
    else
        local pct = math.floor((CASTLE_CD_MAX - castle_cooldown) / CASTLE_CD_MAX * 100)
        text(s, pct.."%", 125, 1, WHT)
    end

    -- Separator line
    line(s, 0, HUD_H-1, SW, HUD_H-1, WHT)
end

------------------------------------------------------------
-- TITLE SCENE (was DEMO)
------------------------------------------------------------
function title_update()
    f = frame()
    demo_timer = demo_timer + 1

    -- Auto-play logic
    demo_action_timer = demo_action_timer - 1
    if demo_action_timer <= 0 then
        demo_action_timer = 30 + math.random(30)
        demo_phase = (demo_phase + 1) % 8

        if demo_phase < 3 then
            demo_cx = math.random(2, COLS-3)
            demo_cy = math.random(2, ROWS-3)
        end
    end

    -- Spawn demo enemies
    if demo_timer % 60 == 0 then
        local e = {
            type = "pawn", side = DIR_LEFT,
            hp = 2, max_hp = 2,
            speed = 0.4, dmg = 1,
            x = -4,
            y = GRID_Y + math.random(2, ROWS-3) * CELL + 4,
            target_gx = 16, target_gy = 7,
            stun = 0,
        }
        table.insert(enemies, e)
    end

    -- Update demo enemies
    local i = 1
    while i <= #enemies do
        local e = enemies[i]
        local tx = e.target_gx * CELL + 4
        local ty = GRID_Y + e.target_gy * CELL + 4
        local dx, dy = tx - e.x, ty - e.y
        local d = math.sqrt(dx*dx + dy*dy)
        if d > 1 then
            e.x = e.x + (dx/d) * e.speed
            e.y = e.y + (dy/d) * e.speed
        end
        -- Remove if past right edge or reached target
        if e.x > SW + 10 or d < 5 then
            spawn_burst(e.x, e.y, 4, 1, WHT)
            table.remove(enemies, i)
        else
            i = i + 1
        end
    end

    update_particles()
    update_floats()

    -- Any button press starts game
    for _, b in ipairs({"up","down","left","right","a","b","start","select"}) do
        if btnp(b) then
            enemies = {}
            particles = {}
            floats = {}
            reset_game()
            go("play")
            return
        end
    end
    if touch_start() then
        enemies = {}
        particles = {}
        floats = {}
        reset_game()
        go("play")
        return
    end
end

function title_draw()
    s = screen()
    cls(s, BLK)

    -- Title
    text(s, "CASTLE DEFENSE", 30, 15, WHT, ALIGN_CENTER)

    -- Subtitle
    if f % 90 < 60 then
        text(s, "PRESS START", 42, 28, WHT)
    end

    -- Draw decorative castle
    -- Left tower
    draw_rook_piece(30, 45, WHT)
    draw_rook_piece(30, 55, WHT)
    draw_rook_piece(30, 65, WHT)
    -- Right tower (show queen upgrade)
    draw_queen_piece(120, 45, WHT)
    draw_queen_piece(120, 55, WHT)
    draw_queen_piece(120, 65, WHT)
    -- King in center
    draw_king(76, 55, WHT)

    -- Draw demo enemies
    for _, e in ipairs(enemies) do
        draw_enemy_pawn(math.floor(e.x)-4, math.floor(e.y)-4, WHT)
    end

    -- Particles
    draw_particles()

    -- Walls connecting towers
    line(s, 38, 49, 120, 49, WHT)
    line(s, 38, 73, 120, 73, WHT)

    -- Clock
    draw_clock(55, 85, WHT)

    -- Bottom info
    text(s, "A:PLACE  B:CASTLE/QUEEN", 10, 102, WHT)
    text(s, "CHESS WARS 2026", 32, 112, WHT)
end

------------------------------------------------------------
-- PLAY SCENE
------------------------------------------------------------
function play_update()
    f = frame()
    handle_play_input()
    update_enemies()
    update_rook_defense()
    update_waves()
    update_castle_cd()
    update_particles()
    update_floats()

    -- Check game over
    if lives <= 0 then
        sfx_gameover()
        cam_shake(6)
        go("gameover")
    end
end

function play_draw()
    s = screen()
    cls(s, BLK)
    draw_grid()
    draw_rooks()
    draw_king_sprite()
    draw_enemies()
    draw_particles()
    draw_floats()
    draw_cursor()
    draw_hud()
end

------------------------------------------------------------
-- PAUSE SCENE
------------------------------------------------------------
function pause_update()
    f = frame()
    if btnp("up") and pause_sel > 0 then pause_sel = pause_sel - 1 end
    if btnp("down") and pause_sel < 1 then pause_sel = pause_sel + 1 end

    if btnp("a") or btnp("start") then
        if pause_sel == 0 then
            go("play")
        else
            enemies = {}
            particles = {}
            floats = {}
            demo_timer = 0
            go("title")
        end
    end
end

function pause_draw()
    s = screen()
    cls(s, BLK)

    -- Border panel
    rect(s, 30, 25, 100, 70, WHT)
    rectf(s, 31, 26, 98, 68, BLK)

    text(s, "PAUSED", 55, 32, WHT)
    line(s, 40, 40, 120, 40, WHT)

    text(s, "WAVE: "..wave_num, 50, 48, WHT)
    text(s, "SCORE: "..score, 45, 58, WHT)

    -- Menu options
    local opts = {"RESUME", "QUIT"}
    for i, opt in ipairs(opts) do
        local y = 72 + (i-1) * 12
        if pause_sel == i-1 then
            text(s, "> "..opt, 50, y, WHT)
        else
            text(s, "  "..opt, 50, y, WHT)
        end
    end
end

------------------------------------------------------------
-- GAME OVER SCENE
------------------------------------------------------------
function gameover_update()
    f = frame()
    update_particles()
    update_floats()

    -- Any button to go back to title
    for _, b in ipairs({"up","down","left","right","a","b","start","select"}) do
        if btnp(b) then
            enemies = {}
            particles = {}
            floats = {}
            demo_timer = 0
            go("title")
            return
        end
    end
    if touch_start() then
        enemies = {}
        particles = {}
        floats = {}
        demo_timer = 0
        go("title")
    end
end

function gameover_draw()
    s = screen()
    cls(s, BLK)

    -- Border
    rect(s, 20, 15, 120, 90, WHT)
    rectf(s, 21, 16, 118, 88, BLK)

    text(s, "GAME OVER", 48, 24, WHT)
    line(s, 30, 33, 130, 33, WHT)

    -- Draw fallen king
    draw_king(74, 42, WHT)
    line(s, 70, 52, 90, 52, WHT)  -- ground

    text(s, "WAVES: "..wave_num, 50, 60, WHT)
    text(s, "SCORE: "..score, 48, 72, WHT)

    if f % 60 < 40 then
        text(s, "PRESS START", 42, 90, WHT)
    end
end

------------------------------------------------------------
-- MAIN ENTRY
------------------------------------------------------------
function _init()
    mode(1)
    enemies = {}
    particles = {}
    floats = {}
    demo_timer = 0
    demo_action_timer = 30
    go("title")
end

function _update()
    -- Scene system handles updates via go()
end

function _draw()
    -- Scene system handles draws via go()
end
