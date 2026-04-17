-- Grey Bastion - Tower Defense for Mono
-- Agent Eta Contest Entry

-- frame() polyfill for headless test environments
if not frame then
    local _fc = 0
    frame = function()
        _fc = _fc + 1
        return _fc
    end
end

-- touch API polyfills for headless test environments
if not touch then
    touch = function() return false end
end
if not touch_pos then
    touch_pos = function() return 0, 0 end
end
if not touch_start then
    touch_start = function() return false end
end
if not touch_end then
    touch_end = function() return false end
end

------------------------------------------------------------
-- GLOBALS
------------------------------------------------------------
local s            -- screen handle
local cx, cy       -- cursor grid position
local gold, lives, score, wave_num
local towers, enemies, bullets, particles, floats
local wave_timer, wave_active, wave_spawned, wave_total
local spawn_timer, spawn_delay
local game_over, victory
local paused, pause_sel
local shop_open, shop_sel
local selected_tower  -- tower under cursor for upgrade UI
local tower_menu_sel

-- grid: 20 cols x 13 rows  (cell = 8x8, top 2 rows = HUD area, grid rows 0-12 map to y 8..112)
local COLS, ROWS = 20, 13
local CELL = 8
local HUD_H = 8  -- pixels reserved for top HUD
local grid = {}   -- 0=buildable, 1=path, 2=tower

-- path waypoints (grid coords) - serpentine path
local waypoints = {
    {x=0,  y=1},
    {x=4,  y=1},
    {x=4,  y=4},
    {x=1,  y=4},
    {x=1,  y=7},
    {x=6,  y=7},
    {x=6,  y=2},
    {x=10, y=2},
    {x=10, y=6},
    {x=7,  y=6},
    {x=7,  y=10},
    {x=12, y=10},
    {x=12, y=4},
    {x=16, y=4},
    {x=16, y=8},
    {x=13, y=8},
    {x=13, y=11},
    {x=19, y=11},
}

-- path cells (filled during init)
local path_cells = {}

-- tower definitions (balanced: arrow=cheap DPS, cannon=AoE, frost=utility, tesla=premium)
local TOWER_DEFS = {
    arrow = {
        name="Arrow", cost=10, range=3, rate=18, dmg=1, color=15,
        upgrades={{cost=15,dmg=2,range=3.5,rate=15},{cost=25,dmg=4,range=4,rate=12}},
        desc="Fast attack",
    },
    cannon = {
        name="Cannon", cost=18, range=2.5, rate=45, dmg=3, color=12, aoe=1.2,
        upgrades={{cost=22,dmg=5,range=3,rate=40,aoe=1.5},{cost=38,dmg=8,range=3.5,rate=34,aoe=2}},
        desc="Area damage",
    },
    frost = {
        name="Frost", cost=15, range=2.5, rate=28, dmg=1, color=10, slow=0.5,
        upgrades={{cost=20,dmg=1,range=3,rate=22,slow=0.35},{cost=35,dmg=2,range=3.5,rate=18,slow=0.2}},
        desc="Slows foes",
    },
    tesla = {
        name="Tesla", cost=28, range=3, rate=38, dmg=2, color=13, chain=2,
        upgrades={{cost=28,dmg=3,range=3.5,rate=32,chain=3},{cost=45,dmg=5,range=4,rate=26,chain=4}},
        desc="Chain zap",
    },
}
local TOWER_ORDER = {"arrow","cannon","frost","tesla"}

-- enemy definitions
local ENEMY_DEFS = {
    runner = {hp=4,  speed=0.8, reward=3,  color=8,  radius=2},
    brute  = {hp=15, speed=0.35,reward=6,  color=6,  radius=3},
    swarm  = {hp=2,  speed=1.0, reward=2,  color=9,  radius=1.5},
    boss   = {hp=60, speed=0.25,reward=25, color=4,  radius=4},
}

-- wave definitions
local WAVES = {}

local flash_timer = 0

-- touch state
local touch_last_gx, touch_last_gy = -1, -1  -- last tapped grid cell
local touch_double_tap_timer = 0              -- frames since last tap on same cell
local TOUCH_DOUBLE_TAP_WINDOW = 20           -- frames to register double-tap

-- convert screen pixel coords to grid coords, returns nil if out of grid
local function px_to_grid(px, py)
    local gx = math.floor(px / CELL)
    local gy = math.floor((py - HUD_H) / CELL)
    if gx >= 0 and gx < COLS and gy >= 0 and gy < ROWS then
        return gx, gy
    end
    return nil, nil
end

-- attract mode state
local attract_active = false
local attract_timer = 0
local attract_towers = {}
local attract_enemies = {}
local attract_particles = {}
local attract_spawn_t = 0
local attract_spawn_count = 0
local ATTRACT_WAVE_SIZE = 12
local attract_wp_idx = 1
local ATTRACT_IDLE_FRAMES = 90
local attract_elapsed = 0
local attract_blink = 0

------------------------------------------------------------
-- 7-SEGMENT CLOCK DISPLAY
------------------------------------------------------------
-- Segment map: a=1,b=2,c=4,d=8,e=16,f=32,g=64
local SEG_DIGITS = {
    [0]=1+2+4+8+16+32,    -- abcdef
    [1]=2+4,               -- bc
    [2]=1+2+8+16+64,       -- abdeg
    [3]=1+2+4+8+64,        -- abcdg
    [4]=2+4+32+64,         -- bcfg
    [5]=1+4+8+32+64,       -- acdfg
    [6]=1+4+8+16+32+64,    -- acdefg
    [7]=1+2+4,             -- abc
    [8]=1+2+4+8+16+32+64,  -- abcdefg
    [9]=1+2+4+8+32+64,     -- abcdfg
}

-- Draw a single 7-segment digit at (x,y), 7px wide x 11px tall, seg thickness 2px
local function draw_seg_digit(x, y, digit, col)
    local segs = SEG_DIGITS[digit] or 0
    -- a: top horizontal
    if segs % 2 >= 1 then rectf(s, x+2, y, 3, 2, col) end
    -- b: top-right vertical
    if math.floor(segs/2) % 2 == 1 then rectf(s, x+5, y+2, 2, 3, col) end
    -- c: bottom-right vertical
    if math.floor(segs/4) % 2 == 1 then rectf(s, x+5, y+6, 2, 3, col) end
    -- d: bottom horizontal
    if math.floor(segs/8) % 2 == 1 then rectf(s, x+2, y+9, 3, 2, col) end
    -- e: bottom-left vertical
    if math.floor(segs/16) % 2 == 1 then rectf(s, x, y+6, 2, 3, col) end
    -- f: top-left vertical
    if math.floor(segs/32) % 2 == 1 then rectf(s, x, y+2, 2, 3, col) end
    -- g: middle horizontal
    if math.floor(segs/64) % 2 == 1 then rectf(s, x+2, y+5, 3, 2, col) end
end

-- Draw HH:MM clock at (x,y) with blinking colon
local function draw_clock_7seg(x, y, col, show_colon)
    local t = date()
    local h = t.hour
    local m = t.min
    local h1 = math.floor(h / 10)
    local h2 = h % 10
    local m1 = math.floor(m / 10)
    local m2 = m % 10
    draw_seg_digit(x, y, h1, col)
    draw_seg_digit(x + 9, y, h2, col)
    -- colon: two small squares
    if show_colon then
        rectf(s, x + 17, y + 3, 2, 2, col)
        rectf(s, x + 17, y + 7, 2, 2, col)
    end
    draw_seg_digit(x + 21, y, m1, col)
    draw_seg_digit(x + 30, y, m2, col)
end

------------------------------------------------------------
-- UTILITY
------------------------------------------------------------
local function dist(ax,ay,bx,by)
    local dx,dy = ax-bx, ay-by
    return math.sqrt(dx*dx+dy*dy)
end

local function grid_to_px(gx,gy)
    return gx*CELL + CELL/2, gy*CELL + HUD_H + CELL/2
end

local function lerp(a,b,t)
    return a + (b-a)*t
end

local function clamp(v,lo,hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

------------------------------------------------------------
-- PATH BUILDING
------------------------------------------------------------
local function build_path()
    -- mark grid cells along waypoints (straight lines between consecutive waypoints)
    path_cells = {}
    for i=1,#waypoints-1 do
        local a,b = waypoints[i], waypoints[i+1]
        local sx = a.x < b.x and 1 or (a.x > b.x and -1 or 0)
        local sy = a.y < b.y and 1 or (a.y > b.y and -1 or 0)
        local px,py = a.x, a.y
        while true do
            local key = px..","..py
            if not path_cells[key] then
                path_cells[key] = true
                grid[px][py] = 1
            end
            if px == b.x and py == b.y then break end
            px = px + sx
            py = py + sy
        end
    end
end

-- build ordered path list for enemy movement
local path_list = {}
local function build_path_list()
    path_list = {}
    for i=1,#waypoints do
        local wp = waypoints[i]
        path_list[#path_list+1] = {x=wp.x, y=wp.y}
    end
end

------------------------------------------------------------
-- WAVE GENERATION
------------------------------------------------------------
local function generate_waves()
    WAVES = {}
    for w=1,20 do
        local wave = {}
        -- base enemies scale with wave
        local n_runners = math.floor(3 + w * 1.2)
        local n_brutes = 0
        local n_swarm = 0
        local n_boss = 0
        if w >= 3 then n_brutes = math.floor(w * 0.5) end
        if w >= 5 then n_swarm = math.floor(w * 0.8) end
        if w >= 7 and w % 3 == 1 then n_boss = math.floor(w / 7) end
        if w == 20 then n_boss = 3 end

        -- interleave enemies for variety
        for _=1,n_swarm do wave[#wave+1] = "swarm" end
        for _=1,n_runners do wave[#wave+1] = "runner" end
        for _=1,n_brutes do wave[#wave+1] = "brute" end
        for _=1,n_boss do wave[#wave+1] = "boss" end

        -- shuffle
        for i=#wave,2,-1 do
            local j = math.random(1,i)
            wave[i],wave[j] = wave[j],wave[i]
        end

        WAVES[w] = wave
    end
end

------------------------------------------------------------
-- PARTICLE / FLOAT SYSTEM
------------------------------------------------------------
local function add_particle(px,py,col,life,vx,vy)
    particles[#particles+1] = {x=px,y=py,col=col,life=life,max_life=life,vx=vx or 0,vy=vy or 0}
end

local function add_float(px,py,txt,col)
    floats[#floats+1] = {x=px,y=py,txt=txt,col=col or 15,life=40}
end

local function explosion_particles(px,py,col,n)
    for _=1,n do
        local a = math.random()*6.28
        local sp = math.random()*1.5 + 0.5
        add_particle(px,py,col,math.random(10,20), math.cos(a)*sp, math.sin(a)*sp)
    end
end

------------------------------------------------------------
-- TOWER LOGIC
------------------------------------------------------------
local function create_tower(kind, gx, gy)
    local def = TOWER_DEFS[kind]
    local t = {
        kind=kind, gx=gx, gy=gy, level=1,
        range=def.range, rate=def.rate, dmg=def.dmg,
        color=def.color, cooldown=0,
        aoe=def.aoe, slow=def.slow, chain=def.chain,
        fire_flash=0,  -- visual feedback when shooting
    }
    return t
end

local function upgrade_tower(t)
    local def = TOWER_DEFS[t.kind]
    if t.level >= 3 then return false end
    local upg = def.upgrades[t.level]
    if gold < upg.cost then return false end
    gold = gold - upg.cost
    t.level = t.level + 1
    t.dmg = upg.dmg or t.dmg
    t.range = upg.range or t.range
    t.rate = upg.rate or t.rate
    if upg.aoe then t.aoe = upg.aoe end
    if upg.slow then t.slow = upg.slow end
    if upg.chain then t.chain = upg.chain end
    -- upgrade sparkle
    local px, py = grid_to_px(t.gx, t.gy)
    explosion_particles(px, py, 15, 5)
    add_float(px, py - 6, "LVL "..t.level, 14)
    note(2,"E5",4)
    note(2,"G5",4)
    return true
end

local function tower_upgrade_cost(t)
    if t.level >= 3 then return nil end
    return TOWER_DEFS[t.kind].upgrades[t.level].cost
end

local function sell_tower(t)
    local def = TOWER_DEFS[t.kind]
    local spent = def.cost
    for i=1,t.level-1 do
        spent = spent + (def.upgrades[i].cost or 0)
    end
    local refund = math.floor(spent * 0.6)
    gold = gold + refund
    local px, py = grid_to_px(t.gx, t.gy)
    add_float(px, py - 6, "+"..refund.."g", 14)
    grid[t.gx][t.gy] = 0
    for i=#towers,1,-1 do
        if towers[i] == t then
            table.remove(towers, i)
            break
        end
    end
    noise(1,6)
end

local function find_target(t)
    local best, best_d = nil, 9999
    local tx, ty = grid_to_px(t.gx, t.gy)
    for _,e in ipairs(enemies) do
        if e.hp > 0 then
            local d = dist(tx,ty,e.px,e.py) / CELL
            if d <= t.range and d < best_d then
                best = e
                best_d = d
            end
        end
    end
    return best
end

local function tower_shoot(t, target)
    local tx, ty = grid_to_px(t.gx, t.gy)
    t.fire_flash = 4  -- visual flash for 4 frames
    if t.kind == "cannon" then
        bullets[#bullets+1] = {
            x=tx,y=ty, tx=target.px, ty=target.py,
            dmg=t.dmg, aoe=t.aoe, speed=2, col=t.color, kind="cannon",
        }
        noise(0,4)
    elseif t.kind == "frost" then
        bullets[#bullets+1] = {
            x=tx,y=ty, tx=target.px, ty=target.py,
            dmg=t.dmg, slow=t.slow, speed=3, col=t.color, kind="frost",
        }
        note(0,"C6",2)
    elseif t.kind == "tesla" then
        -- instant chain lightning
        local hit = {}
        local cur = target
        local remaining_chain = (t.chain or 2)
        while cur and remaining_chain > 0 do
            cur.hp = cur.hp - t.dmg
            if t.slow then cur.slow_timer = 60 ; cur.slow_factor = 0.5 end
            hit[cur] = true
            add_particle(cur.px, cur.py, 15, 8)
            add_particle(cur.px, cur.py, 13, 6)
            remaining_chain = remaining_chain - 1
            -- find next closest unhit enemy
            local nx, best_nd = nil, 9999
            for _,e2 in ipairs(enemies) do
                if e2.hp > 0 and not hit[e2] then
                    local nd = dist(cur.px,cur.py,e2.px,e2.py) / CELL
                    if nd <= t.range and nd < best_nd then
                        nx = e2
                        best_nd = nd
                    end
                end
            end
            cur = nx
        end
        tone(1,800,200,4)
    else
        -- arrow
        bullets[#bullets+1] = {
            x=tx,y=ty, tx=target.px, ty=target.py,
            dmg=t.dmg, speed=4, col=15, kind="arrow",
        }
        note(0,"A5",1)
    end
end

------------------------------------------------------------
-- ENEMY LOGIC
------------------------------------------------------------
local function create_enemy(kind)
    local def = ENEMY_DEFS[kind]
    local sp = path_list[1]
    local px,py = grid_to_px(sp.x, sp.y)
    return {
        kind=kind, hp=def.hp, max_hp=def.hp, speed=def.speed,
        reward=def.reward, color=def.color, radius=def.radius,
        px=px, py=py, wp_idx=2,  -- heading toward waypoint 2
        slow_timer=0, slow_factor=1,
    }
end

local function move_enemy(e)
    if e.wp_idx > #path_list then
        -- reached end
        lives = lives - 1
        e.hp = 0
        flash_timer = 8
        cam_shake(3)
        noise(1,10)
        return
    end
    local wp = path_list[e.wp_idx]
    local tx, ty = grid_to_px(wp.x, wp.y)
    local spd = e.speed
    if e.slow_timer > 0 then
        spd = spd * (e.slow_factor or 0.5)
        e.slow_timer = e.slow_timer - 1
    end
    local dx, dy = tx - e.px, ty - e.py
    local d = math.sqrt(dx*dx + dy*dy)
    if d < spd + 0.5 then
        e.px, e.py = tx, ty
        e.wp_idx = e.wp_idx + 1
    else
        e.px = e.px + dx/d * spd
        e.py = e.py + dy/d * spd
    end
end

local function kill_enemy(e)
    gold = gold + e.reward
    score = score + e.reward * 10
    explosion_particles(e.px, e.py, e.color, 8)
    add_float(e.px, e.py - 4, "+"..e.reward, 15)
    noise(0,3)
end

------------------------------------------------------------
-- SCENES
------------------------------------------------------------

-- ============ TITLE ============
function title_init()
    s = screen()
    attract_active = false
    attract_timer = 0
    attract_elapsed = 0
    attract_blink = 0
end

local title_blink = 0

-- attract mode: set up demo state
local function attract_init_demo()
    attract_active = true
    attract_elapsed = 0
    attract_towers = {}
    attract_enemies = {}
    attract_particles = {}
    attract_spawn_t = 0
    attract_spawn_count = 0

    -- init grid for attract mode path rendering
    for gx=0,COLS-1 do
        if not grid[gx] then grid[gx] = {} end
        for gy=0,ROWS-1 do
            grid[gx][gy] = 0
        end
    end
    build_path()
    build_path_list()

    -- place some demo towers along the path
    local demo_spots = {
        {kind="arrow",  gx=5, gy=0},
        {kind="frost",  gx=2, gy=3},
        {kind="cannon", gx=5, gy=5},
        {kind="arrow",  gx=8, gy=1},
        {kind="tesla",  gx=11,gy=5},
        {kind="arrow",  gx=13,gy=3},
        {kind="frost",  gx=14,gy=9},
        {kind="cannon", gx=11,gy=9},
    }
    for _,ds in ipairs(demo_spots) do
        local def = TOWER_DEFS[ds.kind]
        local t = {
            kind=ds.kind, gx=ds.gx, gy=ds.gy, level=math.random(1,3),
            range=def.range, rate=def.rate, dmg=def.dmg,
            color=def.color, cooldown=0,
            aoe=def.aoe, slow=def.slow, chain=def.chain,
            fire_flash=0,
        }
        attract_towers[#attract_towers+1] = t
    end
end

local function attract_create_enemy()
    local kinds = {"runner","swarm","brute","runner","swarm"}
    local kind = kinds[math.random(1,#kinds)]
    local def = ENEMY_DEFS[kind]
    local sp = path_list[1]
    local px,py = grid_to_px(sp.x, sp.y)
    return {
        kind=kind, hp=def.hp*3, max_hp=def.hp*3, speed=def.speed*0.7,
        reward=0, color=def.color, radius=def.radius,
        px=px, py=py, wp_idx=2,
        slow_timer=0, slow_factor=1,
    }
end

local function attract_update()
    attract_elapsed = attract_elapsed + 1

    -- spawn enemies periodically (up to one wave)
    if attract_spawn_count < ATTRACT_WAVE_SIZE then
        attract_spawn_t = attract_spawn_t + 1
        if attract_spawn_t >= 25 then
            attract_spawn_t = 0
            attract_spawn_count = attract_spawn_count + 1
            attract_enemies[#attract_enemies+1] = attract_create_enemy()
        end
    end

    -- move enemies
    for _,e in ipairs(attract_enemies) do
        if e.hp > 0 then
            if e.wp_idx > #path_list then
                e.hp = 0
            else
                local wp = path_list[e.wp_idx]
                local tx, ty = grid_to_px(wp.x, wp.y)
                local spd = e.speed
                if e.slow_timer > 0 then
                    spd = spd * (e.slow_factor or 0.5)
                    e.slow_timer = e.slow_timer - 1
                end
                local dx, dy = tx - e.px, ty - e.py
                local d = math.sqrt(dx*dx + dy*dy)
                if d < spd + 0.5 then
                    e.px, e.py = tx, ty
                    e.wp_idx = e.wp_idx + 1
                else
                    e.px = e.px + dx/d * spd
                    e.py = e.py + dy/d * spd
                end
            end
        end
    end

    -- towers shoot
    for _,t in ipairs(attract_towers) do
        if t.fire_flash > 0 then t.fire_flash = t.fire_flash - 1 end
        t.cooldown = t.cooldown - 1
        if t.cooldown <= 0 then
            local tx, ty = grid_to_px(t.gx, t.gy)
            local best, best_d = nil, 9999
            for _,e in ipairs(attract_enemies) do
                if e.hp > 0 then
                    local d = dist(tx,ty,e.px,e.py) / CELL
                    if d <= t.range and d < best_d then
                        best = e
                        best_d = d
                    end
                end
            end
            if best then
                t.cooldown = t.rate
                t.fire_flash = 4
                best.hp = best.hp - t.dmg
                if t.slow then
                    best.slow_timer = 30
                    best.slow_factor = t.slow or 0.5
                end
                -- particle for hit
                attract_particles[#attract_particles+1] = {
                    x=best.px, y=best.py, col=t.color,
                    life=6, max_life=6, vx=0, vy=-0.5,
                }
            end
        end
    end

    -- kill dead enemies
    for i=#attract_enemies,1,-1 do
        local e = attract_enemies[i]
        if e.hp <= 0 then
            -- death particles
            for _=1,4 do
                local a = math.random()*6.28
                attract_particles[#attract_particles+1] = {
                    x=e.px, y=e.py, col=e.color,
                    life=math.random(8,14), max_life=14,
                    vx=math.cos(a)*1, vy=math.sin(a)*1,
                }
            end
            table.remove(attract_enemies, i)
        end
    end

    -- update particles
    for i=#attract_particles,1,-1 do
        local p = attract_particles[i]
        p.x = p.x + (p.vx or 0)
        p.y = p.y + (p.vy or 0)
        p.life = p.life - 1
        if p.life <= 0 then table.remove(attract_particles, i) end
    end

    -- restart demo loop when wave is done and field is clear
    if attract_spawn_count >= ATTRACT_WAVE_SIZE and #attract_enemies == 0 and #attract_particles == 0 then
        attract_init_demo()
    end
end

local function attract_draw()
    cls(s, 0)

    -- draw path
    for gx=0,COLS-1 do
        for gy=0,ROWS-1 do
            if grid[gx] and grid[gx][gy] == 1 then
                local px, py = gx*CELL, gy*CELL + HUD_H
                rectf(s, px, py, CELL, CELL, 2)
                rect(s, px, py, CELL, CELL, 3)
            end
        end
    end

    -- draw entry/exit markers
    local sp = waypoints[1]
    local ep = waypoints[#waypoints]
    local spx, spy = grid_to_px(sp.x, sp.y)
    local epx, epy = grid_to_px(ep.x, ep.y)
    circf(s, spx, spy, 3, 11)
    text(s, "IN", spx, spy-8, 11, ALIGN_CENTER)
    circf(s, epx, epy, 3, 8)
    text(s, "OUT", epx, epy-8, 8, ALIGN_CENTER)

    -- draw towers
    for _,t in ipairs(attract_towers) do
        local px, py = grid_to_px(t.gx, t.gy)
        local c = t.color
        -- firing flash
        if t.fire_flash > 0 then
            circf(s, px, py, 5, 15)
        end
        if t.kind == "arrow" then
            line(s, px, py-3, px-3, py+3, c)
            line(s, px-3, py+3, px+3, py+3, c)
            line(s, px+3, py+3, px, py-3, c)
        elseif t.kind == "cannon" then
            rectf(s, px-3, py-3, 7, 7, c)
        elseif t.kind == "frost" then
            line(s, px, py-3, px+3, py, c)
            line(s, px+3, py, px, py+3, c)
            line(s, px, py+3, px-3, py, c)
            line(s, px-3, py, px, py-3, c)
        elseif t.kind == "tesla" then
            circ(s, px, py, 3, c)
            pix(s, px, py, 15)
        end
        -- range circle
        circ(s, px, py, math.floor(t.range * CELL), 1)
    end

    -- draw enemies
    for _,e in ipairs(attract_enemies) do
        if e.hp > 0 then
            local c = e.color
            if e.slow_timer > 0 then c = 10 end
            circf(s, math.floor(e.px), math.floor(e.py), math.floor(e.radius), c)
            -- HP bar
            if e.hp < e.max_hp then
                local bw = 8
                local bx = math.floor(e.px) - 4
                local by = math.floor(e.py) - e.radius - 3
                rectf(s, bx, by, bw, 2, 1)
                local hw = math.floor(bw * e.hp / e.max_hp)
                if hw > 0 then rectf(s, bx, by, hw, 2, 11) end
            end
        end
    end

    -- draw particles
    for _,p in ipairs(attract_particles) do
        pix(s, math.floor(p.x), math.floor(p.y), p.col)
    end

    -- overlay
    rectf(s, 0, 0, 160, 12, 0)
    text(s, "GREY BASTION", 80, 2, 15, ALIGN_CENTER)

    -- "PRESS START" blinking overlay
    attract_blink = attract_blink + 1
    if math.floor(attract_blink / 15) % 2 == 0 then
        rectf(s, 30, 105, 100, 12, 0)
        text(s, "PRESS START", 80, 107, 12, ALIGN_CENTER)
    end

    -- 7-segment clock display (HH:MM), colon blinks every 30 frames
    local clock_col = 4
    local show_colon = math.floor(frame() / 30) % 2 == 0
    draw_clock_7seg(122, 1, clock_col, show_colon)
end

function title_update()
    title_blink = title_blink + 1

    -- check for start press (button or touch)
    if btnp("start") or touch_start() then
        attract_active = false
        go("game")
        return
    end

    if attract_active then
        -- any button exits attract
        if btnp("a") or btnp("b") or btnp("up") or btnp("down") then
            attract_active = false
            attract_timer = 0
            return
        end
        attract_update()
    else
        -- count idle frames
        attract_timer = attract_timer + 1
        if attract_timer >= ATTRACT_IDLE_FRAMES then
            attract_init_demo()
        end
    end
end

function title_draw()
    if attract_active then
        attract_draw()
        return
    end

    cls(s,0)
    -- castle silhouette
    rectf(s, 55, 30, 50, 35, 3)
    rectf(s, 60, 22, 10, 12, 4)
    rectf(s, 90, 22, 10, 12, 4)
    rectf(s, 72, 18, 16, 16, 5)
    -- battlements
    for i=0,4 do
        rectf(s, 56+i*10, 26, 5, 4, 3)
    end
    -- flag on center tower
    local flag_wave = math.floor(title_blink / 10) % 2
    line(s, 80, 18, 80, 12, 7)
    rectf(s, 81, 12, 4 + flag_wave, 3, 8)

    -- title
    text(s, "GREY BASTION", 80, 10, 15, ALIGN_CENTER)
    text(s, "Tower Defense", 80, 72, 10, ALIGN_CENTER)

    if math.floor(title_blink/20) % 2 == 0 then
        text(s, "PRESS START", 80, 90, 12, ALIGN_CENTER)
    end
    text(s, "D-PAD:Move A:Build B:Cancel", 80, 108, 7, ALIGN_CENTER)
end

-- ============ GAME ============
function game_init()
    s = screen()
    cx, cy = 10, 6
    gold = 40
    lives = 10
    score = 0
    wave_num = 0
    towers = {}
    enemies = {}
    bullets = {}
    particles = {}
    floats = {}
    wave_active = false
    wave_spawned = 0
    wave_total = 0
    spawn_timer = 0
    spawn_delay = 30
    game_over = false
    victory = false
    paused = false
    pause_sel = 1
    shop_open = false
    shop_sel = 1
    selected_tower = nil
    tower_menu_sel = 1
    flash_timer = 0
    wave_timer = 0

    -- init grid
    for gx=0,COLS-1 do
        grid[gx] = {}
        for gy=0,ROWS-1 do
            grid[gx][gy] = 0
        end
    end

    build_path()
    build_path_list()
    generate_waves()

    -- start first wave countdown
    wave_timer = 90
end

local function start_wave()
    wave_num = wave_num + 1
    if wave_num > 20 then
        victory = true
        game_over = true
        return
    end
    wave_active = true
    wave_spawned = 0
    wave_total = #WAVES[wave_num]
    spawn_timer = 0
    spawn_delay = math.max(12, 35 - wave_num)
    -- wave start sound
    tone(2, 200, 400, 8)
    note(2, "C4", 4)
end

local function can_build(gx, gy)
    return gx >= 0 and gx < COLS and gy >= 0 and gy < ROWS and grid[gx][gy] == 0
end

local function tower_at(gx, gy)
    for _,t in ipairs(towers) do
        if t.gx == gx and t.gy == gy then return t end
    end
    return nil
end

function game_update()
    if game_over then
        if btnp("start") or touch_start() then go("title") end
        return
    end

    -- pause
    if btnp("select") then
        paused = not paused
        pause_sel = 1
    end
    if paused then
        if btnp("up") then pause_sel = clamp(pause_sel-1,1,2) end
        if btnp("down") then pause_sel = clamp(pause_sel+1,1,2) end
        -- touch: tap on pause menu options (box at 40,40 size 80x40, options at y=55 + (i-1)*10)
        if touch_start() then
            local tx, ty = touch_pos()
            if tx >= 40 and tx <= 120 and ty >= 40 and ty <= 80 then
                for i=1,2 do
                    local item_y = 55 + (i-1)*10
                    if ty >= item_y and ty < item_y + 10 then
                        if i == 1 then paused = false
                        elseif i == 2 then go("title") end
                        return
                    end
                end
            else
                -- tap outside = resume
                paused = false
            end
        end
        if btnp("a") then
            if pause_sel == 1 then paused = false
            elseif pause_sel == 2 then go("title") end
        end
        return
    end

    -- tower context menu (upgrade/sell when cursor is on own tower)
    if selected_tower then
        if btnp("up") then tower_menu_sel = clamp(tower_menu_sel-1,1,3) end
        if btnp("down") then tower_menu_sel = clamp(tower_menu_sel+1,1,3) end
        -- touch: tap on tower menu options (menu box at 35,25 size 90x70, options at y=55 + (i-1)*11)
        if touch_start() then
            local tx, ty = touch_pos()
            local bx, by = 35, 25
            local bw, bh = 90, 70
            if tx >= bx and tx <= bx+bw and ty >= by and ty <= by+bh then
                for i=1,3 do
                    local item_y = by + 30 + (i-1)*11
                    if ty >= item_y and ty < item_y + 11 then
                        if i == 1 then
                            upgrade_tower(selected_tower)
                            selected_tower = nil
                        elseif i == 2 then
                            sell_tower(selected_tower)
                            selected_tower = nil
                        else
                            selected_tower = nil
                        end
                        return
                    end
                end
            else
                -- tap outside menu = cancel
                selected_tower = nil
                return
            end
        end
        if btnp("a") then
            if tower_menu_sel == 1 then
                upgrade_tower(selected_tower)
                selected_tower = nil
            elseif tower_menu_sel == 2 then
                sell_tower(selected_tower)
                selected_tower = nil
            else
                selected_tower = nil
            end
        end
        if btnp("b") then selected_tower = nil end
        return
    end

    -- shop
    if shop_open then
        if btnp("up") then shop_sel = clamp(shop_sel-1,1,4) end
        if btnp("down") then shop_sel = clamp(shop_sel+1,1,4) end
        -- touch: tap on shop items (shop box at 30,20 size 100x80, items at y=32 + (i-1)*15)
        if touch_start() then
            local tx, ty = touch_pos()
            local bx, by = 30, 20
            local bw, bh = 100, 80
            if tx >= bx and tx <= bx+bw and ty >= by and ty <= by+bh then
                -- check which item was tapped
                for i=1,4 do
                    local item_y = by + 12 + (i-1)*15
                    if ty >= item_y and ty < item_y + 15 then
                        shop_sel = i
                        -- also confirm purchase
                        local kind = TOWER_ORDER[shop_sel]
                        local def = TOWER_DEFS[kind]
                        if gold >= def.cost and can_build(cx,cy) then
                            gold = gold - def.cost
                            grid[cx][cy] = 2
                            towers[#towers+1] = create_tower(kind, cx, cy)
                            note(2,"C5",3)
                            note(2,"E5",3)
                            local px, py = grid_to_px(cx, cy)
                            explosion_particles(px, py, def.color, 4)
                        else
                            noise(1,4)
                        end
                        shop_open = false
                        return
                    end
                end
            else
                -- tap outside shop = cancel
                shop_open = false
                return
            end
        end
        if btnp("a") then
            local kind = TOWER_ORDER[shop_sel]
            local def = TOWER_DEFS[kind]
            if gold >= def.cost and can_build(cx,cy) then
                gold = gold - def.cost
                grid[cx][cy] = 2
                towers[#towers+1] = create_tower(kind, cx, cy)
                note(2,"C5",3)
                note(2,"E5",3)
                -- placement particles
                local px, py = grid_to_px(cx, cy)
                explosion_particles(px, py, def.color, 4)
            else
                noise(1,4)
            end
            shop_open = false
        end
        if btnp("b") then shop_open = false end
        return
    end

    -- cursor movement
    if btnp("left")  then cx = clamp(cx-1, 0, COLS-1) end
    if btnp("right") then cx = clamp(cx+1, 0, COLS-1) end
    if btnp("up")    then cy = clamp(cy-1, 0, ROWS-1) end
    if btnp("down")  then cy = clamp(cy+1, 0, ROWS-1) end

    -- A button: build or inspect tower
    if btnp("a") then
        local t = tower_at(cx, cy)
        if t then
            selected_tower = t
            tower_menu_sel = 1
        elseif can_build(cx, cy) then
            shop_open = true
            shop_sel = 1
        end
    end

    -- B button: quick-start wave if between waves
    if btnp("b") and not wave_active and wave_timer > 0 then
        wave_timer = 0
    end

    -- Touch input handling
    if touch_double_tap_timer > 0 then
        touch_double_tap_timer = touch_double_tap_timer - 1
    end

    if touch_start() then
        local tx, ty = touch_pos()
        local gx, gy = px_to_grid(tx, ty)
        if gx then
            -- Check if tapping same cell as cursor (double-tap = action)
            local same_cell = (gx == cx and gy == cy)

            if same_cell and touch_double_tap_timer > 0 then
                -- Double-tap on same cell: act like pressing A
                local t = tower_at(cx, cy)
                if t then
                    selected_tower = t
                    tower_menu_sel = 1
                elseif can_build(cx, cy) then
                    shop_open = true
                    shop_sel = 1
                end
                touch_double_tap_timer = 0
                touch_last_gx, touch_last_gy = -1, -1
            else
                -- First tap or new cell: move cursor there
                cx = gx
                cy = gy
                touch_last_gx = gx
                touch_last_gy = gy
                touch_double_tap_timer = TOUCH_DOUBLE_TAP_WINDOW
            end
        end
    end

    -- wave countdown between waves
    if not wave_active then
        if wave_timer > 0 then
            wave_timer = wave_timer - 1
        else
            start_wave()
        end
    end

    -- spawn enemies
    if wave_active then
        spawn_timer = spawn_timer + 1
        if spawn_timer >= spawn_delay and wave_spawned < wave_total then
            spawn_timer = 0
            wave_spawned = wave_spawned + 1
            local kind = WAVES[wave_num][wave_spawned]
            local e = create_enemy(kind)
            -- scale HP with wave
            e.hp = math.floor(e.hp * (1 + (wave_num-1)*0.15))
            e.max_hp = e.hp
            enemies[#enemies+1] = e
        end
        -- check wave complete
        if wave_spawned >= wave_total then
            local all_dead = true
            for _,e in ipairs(enemies) do
                if e.hp > 0 then all_dead = false; break end
            end
            if all_dead then
                wave_active = false
                -- bonus gold
                local bonus = 5 + wave_num * 2
                gold = gold + bonus
                score = score + bonus * 5
                add_float(80, 60, "WAVE CLEAR! +"..bonus.."g", 15)
                note(2,"C4",4) note(2,"E4",4) note(2,"G4",4)
                wave_timer = 120
            end
        end
    end

    -- move enemies
    for _,e in ipairs(enemies) do
        if e.hp > 0 then
            move_enemy(e)
        end
    end

    -- tower shooting
    for _,t in ipairs(towers) do
        if t.fire_flash > 0 then t.fire_flash = t.fire_flash - 1 end
        t.cooldown = t.cooldown - 1
        if t.cooldown <= 0 then
            local tgt = find_target(t)
            if tgt then
                tower_shoot(t, tgt)
                t.cooldown = t.rate
            end
        end
    end

    -- update bullets
    for i=#bullets,1,-1 do
        local b = bullets[i]
        local dx, dy = b.tx - b.x, b.ty - b.y
        local d = math.sqrt(dx*dx + dy*dy)
        if d < b.speed + 1 then
            -- hit
            if b.aoe and b.aoe > 0 then
                -- AoE damage
                for _,e in ipairs(enemies) do
                    if e.hp > 0 then
                        local ed = dist(b.tx,b.ty,e.px,e.py) / CELL
                        if ed <= b.aoe then
                            e.hp = e.hp - b.dmg
                            if b.slow then
                                e.slow_timer = 60
                                e.slow_factor = b.slow
                            end
                        end
                    end
                end
                explosion_particles(b.tx, b.ty, b.col, 6)
                cam_shake(2)
            else
                -- single target: find closest enemy to target point
                local best_e, best_d2 = nil, 9999
                for _,e in ipairs(enemies) do
                    if e.hp > 0 then
                        local ed = dist(b.tx,b.ty,e.px,e.py)
                        if ed < 8 and ed < best_d2 then
                            best_e = e
                            best_d2 = ed
                        end
                    end
                end
                if best_e then
                    best_e.hp = best_e.hp - b.dmg
                    if b.slow then
                        best_e.slow_timer = 60
                        best_e.slow_factor = b.slow
                    end
                    add_particle(best_e.px, best_e.py, b.col, 6)
                end
            end
            table.remove(bullets, i)
        else
            b.x = b.x + dx/d * b.speed
            b.y = b.y + dy/d * b.speed
        end
    end

    -- check enemy deaths
    for _,e in ipairs(enemies) do
        if e.hp <= 0 and not e.dead then
            e.dead = true
            kill_enemy(e)
        end
    end

    -- clean up dead enemies
    for i=#enemies,1,-1 do
        if enemies[i].dead then
            table.remove(enemies, i)
        end
    end

    -- update particles
    for i=#particles,1,-1 do
        local p = particles[i]
        p.x = p.x + p.vx
        p.y = p.y + p.vy
        p.vy = p.vy + 0.05
        p.life = p.life - 1
        if p.life <= 0 then table.remove(particles, i) end
    end

    -- update floats
    for i=#floats,1,-1 do
        local f = floats[i]
        f.y = f.y - 0.4
        f.life = f.life - 1
        if f.life <= 0 then table.remove(floats, i) end
    end

    -- flash
    if flash_timer > 0 then flash_timer = flash_timer - 1 end

    -- check game over
    if lives <= 0 then
        game_over = true
        victory = false
        cam_shake(6)
    end
end

-- ============ DRAWING ============
local function draw_path()
    for gx=0,COLS-1 do
        for gy=0,ROWS-1 do
            if grid[gx][gy] == 1 then
                local px, py = gx*CELL, gy*CELL + HUD_H
                rectf(s, px, py, CELL, CELL, 2)
                -- subtle border
                rect(s, px, py, CELL, CELL, 3)
            end
        end
    end
    -- draw direction arrows on path every few cells
    for i=1,#waypoints-1 do
        local a, b = waypoints[i], waypoints[i+1]
        local mx = math.floor((a.x+b.x)/2)
        local my = math.floor((a.y+b.y)/2)
        local px, py = grid_to_px(mx, my)
        local dx = b.x > a.x and 1 or (b.x < a.x and -1 or 0)
        local dy = b.y > a.y and 1 or (b.y < a.y and -1 or 0)
        -- small arrow
        pix(s, px + dx*2, py + dy*2, 5)
        pix(s, px + dx, py + dy, 5)
        pix(s, px, py, 5)
    end

    -- entry/exit markers
    local sp = waypoints[1]
    local ep = waypoints[#waypoints]
    local spx, spy = grid_to_px(sp.x, sp.y)
    local epx, epy = grid_to_px(ep.x, ep.y)
    circ(s, spx, spy, 4, 11)
    circ(s, epx, epy, 4, 8)
end

local function draw_tower(t)
    local px, py = grid_to_px(t.gx, t.gy)
    local c = t.color

    -- firing flash glow
    if t.fire_flash > 0 then
        circf(s, px, py, 4, 1)
        circ(s, px, py, 5, c)
    end

    if t.kind == "arrow" then
        -- triangle
        line(s, px, py-3, px-3, py+3, c)
        line(s, px-3, py+3, px+3, py+3, c)
        line(s, px+3, py+3, px, py-3, c)
        if t.level >= 2 then pix(s, px, py, 15) end
        if t.level >= 3 then pix(s, px-1, py+1, 15); pix(s, px+1, py+1, 15) end
    elseif t.kind == "cannon" then
        -- square/fort
        rectf(s, px-3, py-3, 7, 7, c)
        rect(s, px-3, py-3, 7, 7, c+1)
        if t.level >= 2 then rectf(s, px-1, py-3, 3, 2, 15) end
        if t.level >= 3 then
            pix(s, px-3, py-3, 15)
            pix(s, px+3, py-3, 15)
        end
    elseif t.kind == "frost" then
        -- diamond
        line(s, px, py-3, px+3, py, c)
        line(s, px+3, py, px, py+3, c)
        line(s, px, py+3, px-3, py, c)
        line(s, px-3, py, px, py-3, c)
        pix(s, px, py, 15)
        if t.level >= 2 then pix(s, px-1, py-1, 15); pix(s, px+1, py-1, 15) end
        if t.level >= 3 then circf(s, px, py, 1, 15) end
    elseif t.kind == "tesla" then
        -- circle with dot
        circ(s, px, py, 3, c)
        pix(s, px, py, 15)
        if t.level >= 2 then
            pix(s, px-1, py, 15); pix(s, px+1, py, 15)
        end
        if t.level >= 3 then circ(s, px, py, 2, 15) end
    end
    -- range indicator when cursor is on this tower
    if cx == t.gx and cy == t.gy then
        circ(s, px, py, math.floor(t.range * CELL), 4)
    end
end

local function draw_enemy(e)
    if e.hp <= 0 then return end
    local c = e.color
    if e.slow_timer > 0 then c = 10 end  -- tinted when slowed
    circf(s, math.floor(e.px), math.floor(e.py), math.floor(e.radius), c)
    -- boss: extra ring
    if e.kind == "boss" then
        circ(s, math.floor(e.px), math.floor(e.py), math.floor(e.radius)+1, 15)
    end
    -- HP bar
    if e.hp < e.max_hp then
        local bw = 8
        local bx = math.floor(e.px) - 4
        local by = math.floor(e.py) - e.radius - 3
        rectf(s, bx, by, bw, 2, 1)
        local hw = math.floor(bw * e.hp / e.max_hp)
        if hw > 0 then
            local hc = 11
            if e.hp < e.max_hp * 0.3 then hc = 8 end  -- red when low
            rectf(s, bx, by, hw, 2, hc)
        end
    end
end

local function draw_bullets()
    for _,b in ipairs(bullets) do
        pix(s, math.floor(b.x), math.floor(b.y), b.col)
        if b.kind == "cannon" then
            pix(s, math.floor(b.x)+1, math.floor(b.y), b.col)
            pix(s, math.floor(b.x), math.floor(b.y)+1, b.col)
        elseif b.kind == "frost" then
            -- frost bullet trail
            pix(s, math.floor(b.x)-1, math.floor(b.y), 10)
        end
    end
end

local function draw_particles()
    for _,p in ipairs(particles) do
        local alpha = p.life / p.max_life
        local c = math.floor(p.col * alpha)
        if c < 1 then c = 1 end
        pix(s, math.floor(p.x), math.floor(p.y), c)
    end
end

local function draw_floats()
    for _,f in ipairs(floats) do
        local c = f.col
        if f.life < 10 then c = math.floor(c * f.life / 10) end
        if c < 1 then c = 1 end
        text(s, f.txt, math.floor(f.x), math.floor(f.y), c, ALIGN_CENTER)
    end
end

local function draw_cursor()
    local px, py = cx*CELL, cy*CELL + HUD_H
    local f = frame()
    local blink = math.floor(f / 4) % 2

    -- color-coded cursor: green=buildable, yellow=tower, red=path
    local cell_type = grid[cx][cy]
    local c1, c2
    if cell_type == 0 then
        c1 = 11  -- green: can build
        c2 = 3
    elseif cell_type == 2 then
        c1 = 14  -- yellow: tower (can manage)
        c2 = 6
    else
        c1 = 8   -- red: path (cannot build)
        c2 = 4
    end
    local c = blink == 0 and c1 or c2

    -- corners
    line(s, px, py, px+2, py, c)
    line(s, px, py, px, py+2, c)
    line(s, px+CELL, py, px+CELL-2, py, c)
    line(s, px+CELL, py, px+CELL, py+2, c)
    line(s, px, py+CELL, px+2, py+CELL, c)
    line(s, px, py+CELL, px, py+CELL-2, c)
    line(s, px+CELL, py+CELL, px+CELL-2, py+CELL, c)
    line(s, px+CELL, py+CELL, px+CELL, py+CELL-2, c)
end

local function draw_hud()
    -- top bar
    rectf(s, 0, 0, 160, HUD_H, 1)
    text(s, "G:"..gold, 2, 1, 14)
    text(s, "W:"..wave_num.."/20", 45, 1, 12)
    local heart_c = lives <= 3 and 8 or 11
    text(s, "HP:"..lives, 90, 1, heart_c)
    text(s, "S:"..score, 120, 1, 10)

    -- bottom info bar
    if not shop_open and not selected_tower then
        local info = ""
        local t = tower_at(cx, cy)
        if t then
            local def = TOWER_DEFS[t.kind]
            info = def.name.." L"..t.level.." DMG:"..t.dmg.." [A]Manage"
        elseif grid[cx][cy] == 0 then
            info = "[A]Build [B]NextWave"
        elseif grid[cx][cy] == 1 then
            info = "Path - enemies walk here"
        end
        if info ~= "" then
            rectf(s, 0, 112, 160, 8, 1)
            text(s, info, 80, 113, 10, ALIGN_CENTER)
        end
    end

    -- wave incoming
    if not wave_active and wave_timer > 0 and not game_over then
        local sec = math.ceil(wave_timer / 30)
        rectf(s, 20, 97, 120, 10, 1)
        rect(s, 20, 97, 120, 10, 3)
        text(s, "Wave "..(wave_num+1).." in "..sec.."s [B]Skip", 80, 99, 8, ALIGN_CENTER)
    end
end

local function draw_shop()
    if not shop_open then return end
    local bx, by = 10, 16
    local bw, bh = 140, 88
    rectf(s, bx, by, bw, bh, 1)
    rect(s, bx, by, bw, bh, 10)
    text(s, "BUILD TOWER", bx + bw/2, by+3, 15, ALIGN_CENTER)
    for i, kind in ipairs(TOWER_ORDER) do
        local def = TOWER_DEFS[kind]
        local yy = by + 14 + (i-1)*16
        local c = 8
        if i == shop_sel then c = 15 end
        if gold < def.cost then c = 5 end
        if i == shop_sel then
            rectf(s, bx+2, yy-1, bw-4, 14, 3)
            text(s, ">", bx+3, yy, 15)
        end
        text(s, def.name, bx+10, yy, c)
        text(s, def.cost.."g", bx+55, yy, c)
        text(s, def.desc, bx+80, yy, 7)
    end
    text(s, "[A]Buy [B]Cancel", bx + bw/2, by+bh-8, 7, ALIGN_CENTER)
end

local function draw_tower_menu()
    if not selected_tower then return end
    local t = selected_tower
    local def = TOWER_DEFS[t.kind]
    local bx, by = 20, 20
    local bw, bh = 120, 80
    rectf(s, bx, by, bw, bh, 1)
    rect(s, bx, by, bw, bh, 10)
    text(s, def.name.." L"..t.level, bx+bw/2, by+4, t.color, ALIGN_CENTER)
    -- stats line 1
    text(s, "DMG:"..t.dmg, bx+5, by+15, 8)
    text(s, "RNG:"..string.format("%.1f",t.range), bx+50, by+15, 8)
    -- stats line 2: special ability
    local spec = ""
    if t.aoe then spec = "AoE:"..string.format("%.1f",t.aoe) end
    if t.slow then spec = "Slow:"..math.floor((1-t.slow)*100).."%" end
    if t.chain then spec = "Chain:"..t.chain end
    if spec ~= "" then text(s, spec, bx+5, by+24, 7) end
    -- options
    local opts = {}
    local ucost = tower_upgrade_cost(t)
    if ucost then
        opts[1] = "Upgrade ("..ucost.."g)"
    else
        opts[1] = "MAX LEVEL"
    end
    local sell_val = math.floor((def.cost + (t.level > 1 and def.upgrades[1].cost or 0) + (t.level > 2 and def.upgrades[2].cost or 0)) * 0.6)
    opts[2] = "Sell ("..sell_val.."g)"
    opts[3] = "Cancel"
    for i=1,3 do
        local yy = by + 36 + (i-1)*13
        local c = 8
        if i == tower_menu_sel then c = 15 end
        if i == 1 and (not ucost or gold < ucost) then c = 5 end
        if i == tower_menu_sel then
            rectf(s, bx+2, yy-1, bw-4, 11, 3)
            text(s, ">", bx+3, yy, 15)
        end
        text(s, opts[i], bx+12, yy, c)
    end
end

local function draw_pause()
    rectf(s, 40, 40, 80, 40, 1)
    rect(s, 40, 40, 80, 40, 12)
    text(s, "PAUSED", 80, 45, 15, ALIGN_CENTER)
    local opts = {"Resume", "Quit"}
    for i=1,2 do
        local c = i == pause_sel and 15 or 7
        text(s, opts[i], 80, 55 + (i-1)*10, c, ALIGN_CENTER)
        if i == pause_sel then
            text(s, ">", 55, 55+(i-1)*10, 15)
        end
    end
end

local function draw_game_over()
    rectf(s, 20, 30, 120, 60, 1)
    rect(s, 20, 30, 120, 60, 12)
    if victory then
        text(s, "VICTORY!", 80, 38, 15, ALIGN_CENTER)
        text(s, "All 20 waves defeated!", 80, 50, 11, ALIGN_CENTER)
    else
        text(s, "GAME OVER", 80, 38, 8, ALIGN_CENTER)
        text(s, "Wave: "..wave_num, 80, 50, 10, ALIGN_CENTER)
    end
    text(s, "Score: "..score, 80, 62, 14, ALIGN_CENTER)
    if math.floor(frame()/20) % 2 == 0 then
        text(s, "PRESS START", 80, 78, 12, ALIGN_CENTER)
    end
end

function game_draw()
    -- flash on damage
    if flash_timer > 0 and flash_timer % 2 == 0 then
        cls(s, 4)
    else
        cls(s, 0)
    end

    -- draw buildable grid (subtle dots)
    for gx=0,COLS-1 do
        for gy=0,ROWS-1 do
            if grid[gx][gy] == 0 then
                local px, py = gx*CELL + CELL/2, gy*CELL + HUD_H + CELL/2
                pix(s, px, py, 1)
            end
        end
    end

    draw_path()

    -- draw towers
    for _,t in ipairs(towers) do
        draw_tower(t)
    end

    -- draw enemies
    for _,e in ipairs(enemies) do
        draw_enemy(e)
    end

    draw_bullets()
    draw_particles()
    draw_floats()
    draw_cursor()
    draw_hud()

    if shop_open then draw_shop() end
    if selected_tower then draw_tower_menu() end
    if paused then draw_pause() end
    if game_over then draw_game_over() end
end

------------------------------------------------------------
-- ENTRY POINT
------------------------------------------------------------
function _init()
    mode(4)
end

function _start()
    go("title")
end
