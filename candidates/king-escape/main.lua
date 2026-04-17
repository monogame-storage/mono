-- KING ESCAPE
-- Action/Survival: You ARE the king. Survive the chess onslaught.
-- 1-BIT MODE | Mono Chess Wars Contest 2
-- D-Pad: move one square | START: begin | SELECT: pause | Swipe: move

------------------------------------------------------------
-- POLYFILLS
------------------------------------------------------------
if not frame then
    local _fc = 0
    frame = function() _fc = _fc + 1; return _fc end
end
if not touch_start then touch_start = function() return false end end
if not touch_pos then touch_pos = function() return 0, 0 end end
if not swipe then swipe = function() return nil end end

------------------------------------------------------------
-- CONSTANTS
------------------------------------------------------------
local W = SCREEN_W or 160
local H = SCREEN_H or 120
local COLS = 10
local ROWS = 8
local CELL = 12
local BOARD_X = math.floor((W - COLS * CELL) / 2)  -- 20
local BOARD_Y = 14
local HUD_H = 13

local scr  -- screen surface handle

------------------------------------------------------------
-- STATE
------------------------------------------------------------
local high_score = 0

-- Game
local kx, ky              -- king grid position (0-indexed)
local alive
local shield              -- absorb one hit
local freeze_turns        -- enemies skip turns
local score, wave, turn_count
local enemies, powerups
local danger_map          -- [col][row] = true
local flash_t             -- global frame ticker
local wave_clear_t        -- countdown after wave clear
local move_anim           -- {fx,fy,tx,ty,t}
local hit_flash           -- white-screen frames
local paused, pause_sel
local particles

-- Title / attract
local title_timer
local attract_active, attract_timer, attract_blink

local MAX_PARTICLES = 40

------------------------------------------------------------
-- SAFE AUDIO
------------------------------------------------------------
local function sfx_note(ch, n, dur) if note then note(ch, n, dur) end end
local function sfx_noise(ch, dur) if noise then noise(ch, dur) end end
local function sfx_wave(ch, wtype) if wave then wave(ch, wtype) end end

------------------------------------------------------------
-- DYNAMIC SOUNDTRACK
------------------------------------------------------------
-- Tracks board tension and plays ambient music that
-- intensifies as the danger map fills up.
local music_tick = 0
local music_threat_level = 0  -- 0..1 how dangerous the board is

local function count_danger_squares()
    if not danger_map then return 0 end
    local n = 0
    for cx = 0, COLS-1 do
        if danger_map[cx] then
            for cy = 0, ROWS-1 do
                if danger_map[cx][cy] then n = n + 1 end
            end
        end
    end
    return n
end

-- Pentatonic scale notes for calm (low) and tense (high) moods
local CALM_NOTES  = {36, 38, 40, 43, 45, 48}    -- C2 pentatonic
local TENSE_NOTES = {60, 63, 65, 67, 70, 72, 75} -- C4 pentatonic higher

local function update_music()
    if not note then return end
    music_tick = music_tick + 1

    -- Calculate threat level: ratio of attacked squares to total
    local total_sq = COLS * ROWS
    local danger_count = count_danger_squares()
    local enemy_count = enemies and #enemies or 0
    local target = clamp((danger_count / total_sq) + (enemy_count * 0.03), 0, 1)
    -- Smooth approach
    music_threat_level = music_threat_level + (target - music_threat_level) * 0.08

    local threat = music_threat_level
    -- Tempo: calm = every 20 frames, tense = every 6 frames
    local tempo = math.floor(20 - 14 * threat)
    if tempo < 6 then tempo = 6 end

    if music_tick % tempo ~= 0 then return end

    -- Channel 3: bass drone / melody
    -- Channel 2: higher arpeggios when tense
    if threat < 0.3 then
        -- Calm: slow bass notes, triangle wave
        sfx_wave(3, 2) -- triangle
        local pool = CALM_NOTES
        local n = pool[math.random(1, #pool)]
        sfx_note(3, n, math.floor(tempo * 0.8))
    elseif threat < 0.6 then
        -- Medium: bass + occasional mid note
        sfx_wave(3, 2) -- triangle
        local pool = CALM_NOTES
        local n = pool[math.random(1, #pool)]
        sfx_note(3, n, math.floor(tempo * 0.7))
        -- Add mid accent every other beat
        if music_tick % (tempo * 2) == 0 then
            sfx_wave(2, 1) -- square
            local mid = TENSE_NOTES[math.random(1, 4)]
            sfx_note(2, mid, math.floor(tempo * 0.5))
        end
    else
        -- Tense: driving pulse + high staccato arpeggios
        sfx_wave(3, 1) -- square bass
        local pool = CALM_NOTES
        local n = pool[math.random(1, #pool)]
        sfx_note(3, n, math.floor(tempo * 0.5))
        -- Fast arpeggios on ch2
        sfx_wave(2, 0) -- pulse
        local hi = TENSE_NOTES[math.random(1, #TENSE_NOTES)]
        sfx_note(2, hi, math.floor(tempo * 0.4))
        -- Percussive noise hits at high tension
        if music_tick % (tempo * 3) == 0 then
            sfx_noise(1, 2)
        end
    end
end

------------------------------------------------------------
-- UTILITY
------------------------------------------------------------
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function in_bounds(cx, cy)
    return cx >= 0 and cx < COLS and cy >= 0 and cy < ROWS
end

local function grid_px(gx, gy)
    return BOARD_X + gx * CELL, BOARD_Y + gy * CELL
end

local function abs(x) return x < 0 and -x or x end

------------------------------------------------------------
-- 7-SEGMENT CLOCK (compact: 5w x 7h digits)
------------------------------------------------------------
local SEG = {
    [0]=1+2+4+8+16+32,  [1]=2+4,            [2]=1+2+8+16+64,
    [3]=1+2+4+8+64,     [4]=2+4+32+64,      [5]=1+4+8+32+64,
    [6]=1+4+8+16+32+64, [7]=1+2+4,          [8]=1+2+4+8+16+32+64,
    [9]=1+2+4+8+32+64,
}

local function draw_seg_digit(x, y, d, c)
    local s = SEG[d] or 0
    if s % 2 >= 1           then rectf(scr, x+1, y,   3, 1, c) end
    if math.floor(s/2)%2==1 then rectf(scr, x+4, y+1, 1, 2, c) end
    if math.floor(s/4)%2==1 then rectf(scr, x+4, y+4, 1, 2, c) end
    if math.floor(s/8)%2==1 then rectf(scr, x+1, y+6, 3, 1, c) end
    if math.floor(s/16)%2==1 then rectf(scr,x,   y+4, 1, 2, c) end
    if math.floor(s/32)%2==1 then rectf(scr,x,   y+1, 1, 2, c) end
    if math.floor(s/64)%2==1 then rectf(scr,x+1, y+3, 3, 1, c) end
end

local function draw_clock(x, y, col, blink)
    local t = date()
    draw_seg_digit(x,    y, math.floor(t.hour/10), col)
    draw_seg_digit(x+6,  y, t.hour%10, col)
    if blink then
        rectf(scr, x+12, y+2, 1, 1, col)
        rectf(scr, x+12, y+5, 1, 1, col)
    end
    draw_seg_digit(x+14, y, math.floor(t.min/10), col)
    draw_seg_digit(x+20, y, t.min%10, col)
end

------------------------------------------------------------
-- PARTICLES
------------------------------------------------------------
local function add_burst(bx, by, count)
    if not particles then particles = {} end
    for i = 1, count do
        if #particles >= MAX_PARTICLES then return end
        local a = math.random() * 6.2832
        local sp = 0.5 + math.random() * 2
        particles[#particles+1] = {
            x=bx, y=by,
            vx=math.cos(a)*sp, vy=math.sin(a)*sp,
            life=8+math.random(0,8)
        }
    end
end

local function update_particles_list()
    if not particles then return end
    local i = 1
    while i <= #particles do
        local p = particles[i]
        p.x = p.x + p.vx; p.y = p.y + p.vy
        p.vx = p.vx * 0.88; p.vy = p.vy * 0.88
        p.life = p.life - 1
        if p.life <= 0 then table.remove(particles, i) else i = i + 1 end
    end
end

local function draw_particles_list()
    if not particles then return end
    for i = 1, #particles do
        local p = particles[i]
        local ix, iy = math.floor(p.x), math.floor(p.y)
        if ix >= 0 and ix < W and iy >= 0 and iy < H then
            pix(scr, ix, iy, 1)
        end
    end
end

------------------------------------------------------------
-- PIECE DRAWING (12x12 cell)
------------------------------------------------------------
local function draw_pawn(px, py, c)
    circf(scr, px+6, py+4, 2, c)
    rectf(scr, px+4, py+7, 5, 2, c)
    rectf(scr, px+3, py+9, 7, 2, c)
end

local function draw_knight(px, py, c)
    rectf(scr, px+3, py+2, 3, 5, c)
    rectf(scr, px+5, py+1, 4, 3, c)
    rectf(scr, px+7, py+2, 2, 2, c)
    rectf(scr, px+2, py+8, 8, 2, c)
    pix(scr, px+3, py+7, c)
end

local function draw_bishop(px, py, c)
    pix(scr, px+6, py+1, c)
    rectf(scr, px+5, py+2, 3, 2, c)
    rectf(scr, px+4, py+4, 5, 3, c)
    rectf(scr, px+3, py+7, 7, 1, c)
    rectf(scr, px+3, py+9, 7, 2, c)
end

local function draw_rook(px, py, c)
    rectf(scr, px+2, py+1, 2, 2, c)
    rectf(scr, px+5, py+1, 2, 2, c)
    rectf(scr, px+8, py+1, 2, 2, c)
    rectf(scr, px+3, py+3, 6, 4, c)
    rectf(scr, px+2, py+7, 8, 1, c)
    rectf(scr, px+2, py+9, 8, 2, c)
end

local function draw_queen(px, py, c)
    pix(scr, px+3, py+1, c)
    pix(scr, px+6, py+0, c)
    pix(scr, px+9, py+1, c)
    rectf(scr, px+3, py+2, 7, 2, c)
    rectf(scr, px+4, py+4, 5, 3, c)
    rectf(scr, px+3, py+7, 7, 1, c)
    rectf(scr, px+2, py+9, 8, 2, c)
end

local function draw_king_piece(px, py, c)
    -- Cross
    rectf(scr, px+5, py+0, 2, 1, c)
    rectf(scr, px+4, py+1, 4, 1, c)
    rectf(scr, px+5, py+2, 2, 1, c)
    -- Body
    rectf(scr, px+3, py+3, 6, 4, c)
    rectf(scr, px+2, py+7, 8, 1, c)
    rectf(scr, px+2, py+9, 8, 2, c)
end

local PIECE_DRAW = {
    pawn   = draw_pawn,
    knight = draw_knight,
    bishop = draw_bishop,
    rook   = draw_rook,
    queen  = draw_queen,
}

------------------------------------------------------------
-- CHESS MOVEMENT RULES
------------------------------------------------------------
local function get_attack_squares(etype, ex, ey)
    local moves = {}
    if etype == "pawn" then
        -- Pawns attack diagonally (all 4 diags for fairness)
        local ds = {{-1,-1},{1,-1},{-1,1},{1,1}}
        for _, d in ipairs(ds) do
            local nx, ny = ex+d[1], ey+d[2]
            if in_bounds(nx, ny) then moves[#moves+1] = {nx, ny} end
        end
    elseif etype == "knight" then
        local ks = {{-2,-1},{-2,1},{-1,-2},{-1,2},{1,-2},{1,2},{2,-1},{2,1}}
        for _, d in ipairs(ks) do
            local nx, ny = ex+d[1], ey+d[2]
            if in_bounds(nx, ny) then moves[#moves+1] = {nx, ny} end
        end
    elseif etype == "bishop" then
        local dirs = {{-1,-1},{-1,1},{1,-1},{1,1}}
        for _, d in ipairs(dirs) do
            for dist = 1, 10 do
                local nx, ny = ex+d[1]*dist, ey+d[2]*dist
                if not in_bounds(nx, ny) then break end
                moves[#moves+1] = {nx, ny}
                -- Blocked by other enemies
                local blocked = false
                if enemies then
                    for _, e in ipairs(enemies) do
                        if e.x == nx and e.y == ny and not (e.x == ex and e.y == ey) then
                            blocked = true; break
                        end
                    end
                end
                if blocked then break end
            end
        end
    elseif etype == "rook" then
        local dirs = {{0,-1},{0,1},{-1,0},{1,0}}
        for _, d in ipairs(dirs) do
            for dist = 1, 10 do
                local nx, ny = ex+d[1]*dist, ey+d[2]*dist
                if not in_bounds(nx, ny) then break end
                moves[#moves+1] = {nx, ny}
                local blocked = false
                if enemies then
                    for _, e in ipairs(enemies) do
                        if e.x == nx and e.y == ny and not (e.x == ex and e.y == ey) then
                            blocked = true; break
                        end
                    end
                end
                if blocked then break end
            end
        end
    elseif etype == "queen" then
        local dirs = {{0,-1},{0,1},{-1,0},{1,0},{-1,-1},{-1,1},{1,-1},{1,1}}
        for _, d in ipairs(dirs) do
            for dist = 1, 10 do
                local nx, ny = ex+d[1]*dist, ey+d[2]*dist
                if not in_bounds(nx, ny) then break end
                moves[#moves+1] = {nx, ny}
                local blocked = false
                if enemies then
                    for _, e in ipairs(enemies) do
                        if e.x == nx and e.y == ny and not (e.x == ex and e.y == ey) then
                            blocked = true; break
                        end
                    end
                end
                if blocked then break end
            end
        end
    end
    return moves
end

local function get_valid_moves(etype, ex, ey)
    if etype == "pawn" then
        -- Pawns move 1 square any direction (simplified)
        local moves = {}
        local dirs = {{0,-1},{0,1},{-1,0},{1,0},{-1,-1},{-1,1},{1,-1},{1,1}}
        for _, d in ipairs(dirs) do
            local nx, ny = ex+d[1], ey+d[2]
            if in_bounds(nx, ny) then
                local occ = false
                for _, e in ipairs(enemies) do
                    if e.x == nx and e.y == ny then occ = true; break end
                end
                if not occ then moves[#moves+1] = {nx, ny} end
            end
        end
        return moves
    else
        local atk = get_attack_squares(etype, ex, ey)
        local moves = {}
        for _, sq in ipairs(atk) do
            local occ = false
            for _, e in ipairs(enemies) do
                if e.x == sq[1] and e.y == sq[2] then occ = true; break end
            end
            if not occ then moves[#moves+1] = sq end
        end
        return moves
    end
end

------------------------------------------------------------
-- DANGER MAP
------------------------------------------------------------
local function build_danger_map()
    danger_map = {}
    for c = 0, COLS-1 do danger_map[c] = {} end
    if not enemies then return end
    for _, e in ipairs(enemies) do
        local atk = get_attack_squares(e.type, e.x, e.y)
        for _, sq in ipairs(atk) do
            danger_map[sq[1]][sq[2]] = true
        end
    end
end

------------------------------------------------------------
-- WAVE DEFINITIONS
------------------------------------------------------------
local WAVE_DEFS = {
    {2,0,0,0,0}, {3,0,0,0,0}, {2,1,0,0,0}, {3,1,0,0,0},
    {2,1,1,0,0}, {3,1,1,0,0}, {2,2,1,0,0}, {2,1,1,1,0},
    {3,2,1,1,0}, {2,2,2,1,0}, {3,2,1,1,1}, {3,2,2,1,1},
}

local function spawn_wave(w)
    local def
    if w <= #WAVE_DEFS then
        def = WAVE_DEFS[w]
    else
        local b = WAVE_DEFS[#WAVE_DEFS]
        local ex = w - #WAVE_DEFS
        def = {b[1]+math.floor(ex*0.5), b[2]+math.floor(ex*0.3),
               b[3]+math.floor(ex*0.3), b[4]+math.floor(ex*0.2),
               b[5]+math.floor(ex*0.1)}
    end
    local types = {"pawn","knight","bishop","rook","queen"}
    for i = 1, 5 do
        for j = 1, def[i] do
            for attempt = 1, 100 do
                local ex = math.random(0, COLS-1)
                local ey = math.random(0, ROWS-1)
                if abs(ex-kx) + abs(ey-ky) >= 3 then
                    local occ = false
                    for _, e in ipairs(enemies) do
                        if e.x == ex and e.y == ey then occ = true; break end
                    end
                    if not occ then
                        enemies[#enemies+1] = {type=types[i], x=ex, y=ey, spawn_flash=10}
                        break
                    end
                end
            end
        end
    end
    build_danger_map()
end

------------------------------------------------------------
-- POWER-UPS
------------------------------------------------------------
local function maybe_spawn_powerup()
    if #powerups >= 2 then return end
    if math.random() > 0.35 then return end
    local ptype = math.random() < 0.5 and "shield" or "freeze"
    for attempt = 1, 50 do
        local px = math.random(0, COLS-1)
        local py = math.random(0, ROWS-1)
        if (px ~= kx or py ~= ky) then
            local occ = false
            for _, e in ipairs(enemies) do
                if e.x == px and e.y == py then occ = true; break end
            end
            for _, p in ipairs(powerups) do
                if p.x == px and p.y == py then occ = true; break end
            end
            if not occ then
                powerups[#powerups+1] = {type=ptype, x=px, y=py}
                return
            end
        end
    end
end

------------------------------------------------------------
-- ENEMY AI
------------------------------------------------------------
local function move_enemies()
    if freeze_turns > 0 then
        freeze_turns = freeze_turns - 1
        sfx_note(2, 40, 4)
        return
    end
    for _, e in ipairs(enemies) do
        local moves = get_valid_moves(e.type, e.x, e.y)
        if #moves > 0 then
            -- Pick move closest to king (Manhattan)
            local best, best_d = nil, 9999
            for _, m in ipairs(moves) do
                local d = abs(m[1]-kx) + abs(m[2]-ky)
                if d < best_d then best_d = d; best = m end
            end
            -- Pawns: occasional random move to avoid clumping
            if e.type == "pawn" and math.random() < 0.25 and #moves > 1 then
                best = moves[math.random(1, #moves)]
            end
            if best then e.x = best[1]; e.y = best[2] end
        end
    end
    build_danger_map()
end

------------------------------------------------------------
-- KING COLLISION LOGIC
------------------------------------------------------------
local function check_king_on_square()
    -- Try to capture enemies on king's square
    local i = 1
    while i <= #enemies do
        local e = enemies[i]
        if e.x == kx and e.y == ky then
            -- Safe capture only if no OTHER enemy attacks this square
            local attacked = false
            for _, e2 in ipairs(enemies) do
                if e2 ~= e then
                    local atk = get_attack_squares(e2.type, e2.x, e2.y)
                    for _, sq in ipairs(atk) do
                        if sq[1] == kx and sq[2] == ky then attacked = true; break end
                    end
                    if attacked then break end
                end
            end
            if not attacked then
                -- Capture!
                score = score + 25
                sfx_note(0, 60, 6); sfx_note(1, 64, 6)
                local cpx, cpy = grid_px(e.x, e.y)
                add_burst(cpx+CELL/2, cpy+CELL/2, 12)
                table.remove(enemies, i)
                -- Don't increment i
            else
                return true  -- walked into guarded square = hit
            end
        else
            i = i + 1
        end
    end
    -- Check if king stands on danger square
    if danger_map[kx] and danger_map[kx][ky] then
        return true
    end
    -- Pickup powerups
    local pi = 1
    while pi <= #powerups do
        local p = powerups[pi]
        if p.x == kx and p.y == ky then
            if p.type == "shield" then
                shield = true
                sfx_note(0, 50, 4); sfx_note(1, 55, 4)
            elseif p.type == "freeze" then
                freeze_turns = freeze_turns + 2
                sfx_note(0, 45, 4); sfx_note(1, 48, 4)
            end
            table.remove(powerups, pi)
        else
            pi = pi + 1
        end
    end
    return false
end

local function king_die()
    alive = false
    sfx_noise(0, 12); sfx_note(1, 30, 10); sfx_note(2, 25, 10)
    if cam_shake then cam_shake(4) end
    local px, py = grid_px(kx, ky)
    add_burst(px+CELL/2, py+CELL/2, 20)
    hit_flash = 10
    if score > high_score then high_score = score end
end

------------------------------------------------------------
-- PROCESS A KING MOVE
------------------------------------------------------------
local function try_move_king(dx, dy)
    if not alive or wave_clear_t > 0 then return end
    local nx, ny = kx+dx, ky+dy
    if not in_bounds(nx, ny) then sfx_noise(3, 3); return end

    sfx_note(0, 50, 2)
    move_anim = {fx=kx, fy=ky, tx=nx, ty=ny, t=0}
    kx = nx; ky = ny
    turn_count = turn_count + 1

    -- Check landing
    if check_king_on_square() then
        if shield then
            shield = false; sfx_noise(2, 6); hit_flash = 6
            if cam_shake then cam_shake(2) end
        else
            king_die(); return
        end
    end

    -- Enemies respond
    move_enemies()

    -- Check if enemies stepped onto king
    for _, e in ipairs(enemies) do
        if e.x == kx and e.y == ky then
            if shield then
                shield = false; sfx_noise(2, 6); hit_flash = 6
            else
                king_die(); return
            end
        end
    end

    build_danger_map()

    -- Wave clear?
    if #enemies == 0 then
        wave_clear_t = 30
        score = score + 10 * wave
        sfx_note(0, 55, 6); sfx_note(1, 59, 6); sfx_note(2, 62, 6)
    end
end

------------------------------------------------------------
-- INIT GAME
------------------------------------------------------------
local function init_game()
    kx = math.floor(COLS/2)
    ky = math.floor(ROWS/2)
    alive = true; shield = false; freeze_turns = 0
    score = 0; wave = 1; turn_count = 0
    enemies = {}; powerups = {}; particles = {}
    flash_t = 0; wave_clear_t = 0; hit_flash = 0
    move_anim = nil; paused = false; pause_sel = 1
    spawn_wave(1)
end

------------------------------------------------------------
-- DRAW: BOARD + PIECES
------------------------------------------------------------
local function draw_board()
    -- Checkerboard
    for cy = 0, ROWS-1 do
        for cx = 0, COLS-1 do
            local px, py = grid_px(cx, cy)
            if (cx+cy) % 2 == 0 then
                rectf(scr, px, py, CELL, CELL, 1)
            else
                rectf(scr, px, py, CELL, CELL, 0)
                -- Corner dots for dark squares (clean, readable)
                pix(scr, px+1,      py+1,      1)
                pix(scr, px+CELL-2, py+1,      1)
                pix(scr, px+1,      py+CELL-2, 1)
                pix(scr, px+CELL-2, py+CELL-2, 1)
            end
        end
    end

    -- Danger overlay (flashing)
    if danger_map and alive and flash_t % 10 < 5 then
        for cx = 0, COLS-1 do
            if danger_map[cx] then
                for cy = 0, ROWS-1 do
                    if danger_map[cx][cy] then
                        local px, py = grid_px(cx, cy)
                        -- Draw X pattern for danger
                        for dd = 0, CELL-1, 3 do
                            if px+dd < W and py+dd < H then pix(scr, px+dd, py+dd, 0) end
                            if px+CELL-1-dd >= 0 and py+dd < H then pix(scr, px+CELL-1-dd, py+dd, 0) end
                        end
                    end
                end
            end
        end
    end

    -- Power-ups
    for _, p in ipairs(powerups) do
        local px, py = grid_px(p.x, p.y)
        local cx, cy = px+CELL/2, py+CELL/2
        if p.type == "shield" then
            circ(scr, cx, cy, 3, 1)
            pix(scr, cx, cy, 1)
        elseif p.type == "freeze" then
            line(scr, cx-3, cy, cx+3, cy, 1)
            line(scr, cx, cy-3, cx, cy+3, 1)
            pix(scr, cx-2, cy-2, 1)
            pix(scr, cx+2, cy+2, 1)
            pix(scr, cx+2, cy-2, 1)
            pix(scr, cx-2, cy+2, 1)
        end
    end

    -- Enemies
    for _, e in ipairs(enemies) do
        local epx, epy = grid_px(e.x, e.y)
        local col = 1
        if e.spawn_flash and e.spawn_flash > 0 then
            e.spawn_flash = e.spawn_flash - 1
            if e.spawn_flash % 4 < 2 then col = 0 end
        end
        local fn = PIECE_DRAW[e.type]
        if fn then fn(epx, epy, col) end
    end

    -- King
    if alive then
        local kpx, kpy = grid_px(kx, ky)
        if move_anim then
            local t = move_anim.t
            local fpx, fpy = grid_px(move_anim.fx, move_anim.fy)
            local tpx, tpy = grid_px(move_anim.tx, move_anim.ty)
            kpx = math.floor(fpx + (tpx-fpx)*t)
            kpy = math.floor(fpy + (tpy-fpy)*t)
        end
        -- Clear area then draw king
        rectf(scr, kpx+1, kpy+1, CELL-2, CELL-2, 0)
        draw_king_piece(kpx, kpy, 1)
        if shield then
            rect(scr, kpx, kpy, CELL, CELL, 1)
        end
    end
end

local function draw_hud()
    rectf(scr, 0, 0, W, HUD_H, 0)
    line(scr, 0, HUD_H-1, W, HUD_H-1, 1)
    text(scr, "W"..wave, 2, 3, 1)
    text(scr, "SC:"..score, 32, 3, 1)
    if freeze_turns > 0 then text(scr, "FRZ"..freeze_turns, 78, 3, 1) end
    if shield then text(scr, "SHD", 108, 3, 1) end
    text(scr, "HI:"..high_score, W-35, 3, 1)
    -- Bottom info
    local by = BOARD_Y + ROWS*CELL + 1
    if by < H - 6 then
        text(scr, "TURNS:"..turn_count, 2, by, 1)
        text(scr, "ENEMIES:"..#enemies, W/2, by, 1)
    end
end

------------------------------------------------------------
-- PLAY SCENE
------------------------------------------------------------
function play_init()
    scr = screen()
    music_tick = 0
    music_threat_level = 0
    init_game()
end

function play_update()
    flash_t = (flash_t or 0) + 1
    if hit_flash > 0 then hit_flash = hit_flash - 1 end
    update_music()

    -- Animate king slide
    if move_anim then
        move_anim.t = move_anim.t + 0.3
        if move_anim.t >= 1 then move_anim = nil end
    end
    update_particles_list()

    -- Pause toggle
    if btnp("select") then
        paused = not paused; pause_sel = 1; return
    end
    if paused then
        if btnp("up") then pause_sel = 1 end
        if btnp("down") then pause_sel = 2 end
        if btnp("a") or btnp("start") then
            if pause_sel == 1 then paused = false
            elseif pause_sel == 2 then go("title") end
        end
        if touch_start() then
            local tx, ty = touch_pos()
            if ty < H/2 then paused = false else go("title") end
        end
        return
    end

    -- Game over input
    if not alive then
        if btnp("start") or btnp("a") or touch_start() then go("title") end
        return
    end

    -- Wave clear countdown
    if wave_clear_t > 0 then
        wave_clear_t = wave_clear_t - 1
        if wave_clear_t == 0 then
            wave = wave + 1
            spawn_wave(wave)
            maybe_spawn_powerup()
        end
        return
    end

    -- D-pad input
    local moved = false
    if btnp("left")  then try_move_king(-1, 0); moved = true end
    if not moved and btnp("right") then try_move_king(1, 0);  moved = true end
    if not moved and btnp("up")    then try_move_king(0,-1);  moved = true end
    if not moved and btnp("down")  then try_move_king(0, 1);  moved = true end

    -- Swipe input
    if not moved then
        local sw = swipe()
        if     sw == "left"  then try_move_king(-1, 0)
        elseif sw == "right" then try_move_king(1, 0)
        elseif sw == "up"    then try_move_king(0,-1)
        elseif sw == "down"  then try_move_king(0, 1)
        end
    end
end

function play_draw()
    scr = screen()
    cls(scr, 0)

    if hit_flash > 0 and hit_flash % 2 == 0 then cls(scr, 1) end

    draw_board()
    draw_particles_list()
    draw_hud()

    -- Wave clear banner
    if wave_clear_t > 0 then
        rectf(scr, 20, 46, 120, 20, 0)
        rect(scr, 20, 46, 120, 20, 1)
        text(scr, "WAVE "..wave.." CLEAR!", W/2, 52, 1, ALIGN_CENTER)
    end

    -- Pause overlay
    if paused then
        rectf(scr, 35, 30, 90, 52, 0)
        rect(scr, 35, 30, 90, 52, 1)
        text(scr, "PAUSED", W/2, 35, 1, ALIGN_CENTER)
        text(scr, (pause_sel==1 and "> " or "  ").."RESUME", 45, 50, 1)
        text(scr, (pause_sel==2 and "> " or "  ").."QUIT",   45, 62, 1)
    end

    -- Game over overlay
    if not alive then
        rectf(scr, 25, 25, 110, 68, 0)
        rect(scr, 25, 25, 110, 68, 1)
        rect(scr, 27, 27, 106, 64, 1)
        text(scr, "CHECKMATE!", W/2, 32, 1, ALIGN_CENTER)
        text(scr, "SCORE: "..score, W/2, 46, 1, ALIGN_CENTER)
        text(scr, "WAVE: "..wave, W/2, 56, 1, ALIGN_CENTER)
        text(scr, "TURNS: "..turn_count, W/2, 66, 1, ALIGN_CENTER)
        if score >= high_score and score > 0 then
            text(scr, "NEW BEST!", W/2, 76, 1, ALIGN_CENTER)
        end
        if flash_t % 40 < 20 then
            text(scr, "PRESS START", W/2, 86, 1, ALIGN_CENTER)
        end
    end
end

------------------------------------------------------------
-- TITLE SCENE
------------------------------------------------------------
function title_init()
    scr = screen()
    title_timer = 0
    attract_active = false
    attract_timer = 0
    attract_blink = 0
    flash_t = 0
    -- Reset game state for attract
    enemies = {}
    powerups = {}
    particles = {}
    danger_map = {}
    for c = 0, COLS-1 do danger_map[c] = {} end
end

function title_update()
    title_timer = title_timer + 1

    -- Start game
    if btnp("start") or btnp("a") or touch_start() then
        attract_active = false
        go("play")
        return
    end

    -- Enter attract mode after idle
    if not attract_active and title_timer > 120 then
        attract_active = true
        attract_timer = 0
        kx = math.floor(COLS/2); ky = math.floor(ROWS/2)
        alive = true; shield = false; freeze_turns = 0
        enemies = {}; powerups = {}; particles = {}
        danger_map = {}
        for c = 0, COLS-1 do danger_map[c] = {} end
        wave = 1
        spawn_wave(1)
    end

    if attract_active then
        attract_timer = attract_timer + 1
        attract_blink = (attract_blink or 0) + 1
        update_music()

        -- AI king: move every 10 frames
        if attract_timer % 10 == 0 and alive then
            local dirs = {{0,0},{-1,0},{1,0},{0,-1},{0,1},{-1,-1},{-1,1},{1,-1},{1,1}}
            local best, best_s = nil, -9999
            for _, d in ipairs(dirs) do
                local nx, ny = kx+d[1], ky+d[2]
                if in_bounds(nx, ny) then
                    local sc = 0
                    if danger_map[nx] and danger_map[nx][ny] then sc = sc - 100 end
                    sc = sc - abs(nx-COLS/2) - abs(ny-ROWS/2)
                    -- Bonus for safe captures
                    for _, e in ipairs(enemies) do
                        if e.x == nx and e.y == ny then
                            local safe = true
                            for _, e2 in ipairs(enemies) do
                                if e2 ~= e then
                                    local atk = get_attack_squares(e2.type, e2.x, e2.y)
                                    for _, sq in ipairs(atk) do
                                        if sq[1]==nx and sq[2]==ny then safe=false; break end
                                    end
                                    if not safe then break end
                                end
                            end
                            if safe then sc = sc + 50 end
                        end
                    end
                    sc = sc + math.random() * 3
                    if sc > best_s then best_s = sc; best = {nx, ny} end
                end
            end
            if best and (best[1] ~= kx or best[2] ~= ky) then
                kx = best[1]; ky = best[2]
                -- Remove captured enemies
                local i = 1
                while i <= #enemies do
                    if enemies[i].x == kx and enemies[i].y == ky then
                        table.remove(enemies, i)
                    else i = i + 1 end
                end
                move_enemies()
                -- Check if enemy landed on king (demo: just respawn)
                for _, e in ipairs(enemies) do
                    if e.x == kx and e.y == ky then
                        -- Reset demo
                        kx = math.floor(COLS/2); ky = math.floor(ROWS/2)
                        enemies = {}
                        spawn_wave(1)
                        break
                    end
                end
                if #enemies == 0 then spawn_wave(1) end
            end
        end

        update_particles_list()

        -- Cycle attract
        if attract_timer > 500 then
            attract_active = false
            title_timer = 0
        end
    end
end

function title_draw()
    scr = screen()
    cls(scr, 0)

    if attract_active then
        -- Draw live demo
        draw_board()
        draw_particles_list()

        -- Clock
        draw_clock(2, 2, 1, attract_blink % 30 < 15)

        -- Overlay
        rectf(scr, 0, H-22, W, 22, 0)
        line(scr, 0, H-22, W, H-22, 1)
        text(scr, "KING ESCAPE", W/2, H-20, 1, ALIGN_CENTER)
        if attract_blink % 40 < 20 then
            text(scr, "PRESS START", W/2, H-10, 1, ALIGN_CENTER)
        end
    else
        -- Decorative board background
        for cy = 0, 9 do
            for cx = 0, 13 do
                if (cx+cy) % 2 == 0 then
                    rectf(scr, cx*12, cy*12, 12, 12, 1)
                end
            end
        end

        -- Title panel
        rectf(scr, 20, 16, 120, 88, 0)
        rect(scr, 20, 16, 120, 88, 1)
        rect(scr, 22, 18, 116, 84, 1)

        -- King icon
        draw_king_piece(72, 22, 1)

        text(scr, "KING ESCAPE", W/2, 38, 1, ALIGN_CENTER)
        line(scr, 35, 46, 125, 46, 1)

        text(scr, "YOU ARE THE KING", W/2, 52, 1, ALIGN_CENTER)
        text(scr, "SURVIVE THE BOARD", W/2, 62, 1, ALIGN_CENTER)
        text(scr, "CAPTURE WHEN SAFE", W/2, 72, 1, ALIGN_CENTER)

        if title_timer % 40 < 20 then
            text(scr, "PRESS START", W/2, 88, 1, ALIGN_CENTER)
        end

        -- Clock
        draw_clock(2, 2, 1, title_timer % 30 < 15)

        -- High score
        if high_score > 0 then
            text(scr, "HI:"..high_score, W/2, H-6, 1, ALIGN_CENTER)
        end
    end
end

------------------------------------------------------------
-- ENGINE HOOKS
------------------------------------------------------------
function _init()
    mode(1)
    math.randomseed(os.clock() * 10000 + 42)
end

function _start()
    go("title")
end
