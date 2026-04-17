-- KNOCKOUT! - A Mono Boxing Game
-- Agent Theta Entry for the Mono Game Contest
----------------------------------------------

-- Game constants
local RING_LEFT = 20
local RING_RIGHT = 140
local RING_Y = 85       -- ground line for feet
local RING_TOP_ROPE = 40
local GRAVITY = 0.5
local ROUND_TIME = 60   -- seconds per round
local MAX_ROUNDS = 3
local KNOCKDOWN_COUNT = 10

-- Colors (grayscale 0-15)
local C_BLACK = 0
local C_DARK3 = 2
local C_DARK2 = 3
local C_DARK1 = 4
local C_MID2 = 5
local C_MID1 = 6
local C_GRAY = 7
local C_LIGHT3 = 8
local C_LIGHT2 = 9
local C_LIGHT1 = 10
local C_PALE2 = 11
local C_PALE1 = 12
local C_BRIGHT2 = 13
local C_BRIGHT1 = 14
local C_WHITE = 15

-- 7-segment clock display for attract mode
-- Segment layout:  _a_
--                 |   |
--                 f   b
--                 |_g_|
--                 |   |
--                 e   c
--                 |_d_|
local seg_digits = {
    --        a     b     c     d     e     f     g
    [0] = { true, true, true, true, true, true, false },
    [1] = { false,true, true, false,false,false,false },
    [2] = { true, true, false,true, true, false,true  },
    [3] = { true, true, true, true, false,false,true  },
    [4] = { false,true, true, false,false,true, true  },
    [5] = { true, false,true, true, false,true, true  },
    [6] = { true, false,true, true, true, true, true  },
    [7] = { true, true, true, false,false,false,false },
    [8] = { true, true, true, true, true, true, true  },
    [9] = { true, true, true, true, false,true, true  },
}

local function draw_seg_digit(s, ox, oy, digit, color)
    local segs = seg_digits[digit]
    if not segs then return end
    -- a: top horizontal
    if segs[1] then rectf(s, ox+1, oy, 5, 2, color) end
    -- b: top-right vertical
    if segs[2] then rectf(s, ox+5, oy+1, 2, 5, color) end
    -- c: bottom-right vertical
    if segs[3] then rectf(s, ox+5, oy+6, 2, 5, color) end
    -- d: bottom horizontal
    if segs[4] then rectf(s, ox+1, oy+9, 5, 2, color) end
    -- e: bottom-left vertical
    if segs[5] then rectf(s, ox, oy+6, 2, 5, color) end
    -- f: top-left vertical
    if segs[6] then rectf(s, ox, oy+1, 2, 5, color) end
    -- g: middle horizontal
    if segs[7] then rectf(s, ox+1, oy+5, 5, 1, color) end
end

local function draw_clock(s, x, y, color)
    local t = date()
    local h = t.hour
    local m = t.min
    local h1 = math.floor(h / 10)
    local h2 = h % 10
    local m1 = math.floor(m / 10)
    local m2 = m % 10
    draw_seg_digit(s, x, y, h1, color)
    draw_seg_digit(s, x + 9, y, h2, color)
    -- colon: blink every 30 frames
    if frame() % 60 < 30 then
        rectf(s, x + 17, y + 3, 2, 2, color)
        rectf(s, x + 17, y + 7, 2, 2, color)
    end
    draw_seg_digit(s, x + 21, y, m1, color)
    draw_seg_digit(s, x + 30, y, m2, color)
end

-- Particles system
local particles = {}

local function spawn_particle(x, y, vx, vy, life, color, size)
    table.insert(particles, {
        x = x, y = y, vx = vx, vy = vy,
        life = life, max_life = life, color = color, size = size or 1
    })
end

local function spawn_hit_particles(x, y, count, intensity)
    for i = 1, count do
        local angle = math.random() * 6.28
        local speed = 0.5 + math.random() * intensity
        local c = (math.random() > 0.5) and C_WHITE or C_BRIGHT1
        spawn_particle(x, y, math.cos(angle)*speed, math.sin(angle)*speed, 8 + math.random(6), c, 1)
    end
end

local function spawn_sweat(x, y, dir)
    for i = 1, 3 do
        spawn_particle(x, y - 10 - math.random(6),
            dir * (0.3 + math.random() * 0.8), -0.5 - math.random() * 0.5,
            12 + math.random(8), C_LIGHT2, 1)
    end
end

local function update_particles()
    local i = 1
    while i <= #particles do
        local p = particles[i]
        p.x = p.x + p.vx
        p.y = p.y + p.vy
        p.vy = p.vy + 0.03
        p.vx = p.vx * 0.95
        p.life = p.life - 1
        if p.life <= 0 then
            table.remove(particles, i)
        else
            i = i + 1
        end
    end
end

local function draw_particles(s)
    for _, p in ipairs(particles) do
        local alpha = p.life / p.max_life
        local c = p.color
        if alpha < 0.3 then c = C_DARK2 end
        if p.size <= 1 then
            pix(s, math.floor(p.x), math.floor(p.y), c)
        else
            circf(s, math.floor(p.x), math.floor(p.y), p.size, c)
        end
    end
end

-- Hitstop system
local hitstop = { active = false, frames = 0 }

local function do_hitstop(frames)
    hitstop.active = true
    hitstop.frames = frames
end

-- Game state
local game = {
    mode = "title",         -- title, fight, between_rounds, gameover, tournament, ko_replay
    round = 1,
    round_timer = 0,
    round_start_time = 0,
    pause = false,
    tournament_fight = 1,
    tournament_wins = 0,
    ko_replay_timer = 0,
    ko_replay_frames = {},
    flash_timer = 0,
    crowd_energy = 0,       -- 0-100
    crowd_timer = 0,
    shake_amount = 0,
    shake_timer = 0,
    decision_scores = {},   -- {p1_score, p2_score} per round
    -- Attract mode
    attract_mode = false,
    attract_timer = 0,
    idle_timer = 0,         -- frames idle on title
    ATTRACT_IDLE_THRESHOLD = 90,
    -- attract mode runs indefinitely until a key is pressed
}

-- Fighter prototype
local function new_fighter(x, facing, is_player)
    return {
        x = x,
        y = RING_Y,
        facing = facing,        -- 1=right, -1=left
        is_player = is_player,
        -- Health & stamina
        health = 100,
        max_health = 100,
        stamina = 100,
        max_stamina = 100,
        -- State: idle, walk_fwd, walk_back, jab, hook, uppercut, power_cross,
        --        block, hit_stun, knockdown, getting_up, ko, dodge_back
        state = "idle",
        state_timer = 0,
        -- Animation
        anim_frame = 0,
        bob_timer = 0,
        lean = 0,           -- body lean for punches (-1 to 1)
        target_lean = 0,
        foot_anim = 0,      -- foot stepping animation
        -- Combat
        punch_damage = 0,
        punch_hit = false,
        combo_count = 0,
        combo_timer = 0,
        last_punch = "",
        -- Knockdown
        knockdown_count = 0,  -- per round
        total_knockdowns = 0,
        count_timer = 0,
        current_count = 0,
        -- Stats
        punches_thrown = 0,
        punches_landed = 0,
        damage_dealt = 0,
        -- AI specific
        ai_state = "approach",
        ai_timer = 0,
        ai_aggression = 0.5,
        ai_defense = 0.5,
        ai_speed = 1.0,
        ai_pattern = 1,
        ai_react_time = 15,   -- frames before reacting
        ai_name = "CPU",
        ai_retreat_timer = 0,
        ai_feint_timer = 0,
        -- Body dimensions for drawing
        body_w = 8,
        body_h = 16,
        -- Velocity for knockback
        vx = 0,
        vy = 0,
        on_ground = true,
        -- Hit flash
        hit_flash = 0,
    }
end

local p1 = {}  -- player
local p2 = {}  -- opponent

-- Tournament opponents
local opponents = {
    { name = "JOEY", aggression = 0.3, defense = 0.3, speed = 0.8, react = 20, health = 80, pattern = 1 },
    { name = "RICO", aggression = 0.5, defense = 0.5, speed = 1.0, react = 15, health = 90, pattern = 2 },
    { name = "BULL", aggression = 0.7, defense = 0.4, speed = 0.9, react = 12, health = 110, pattern = 3 },
    { name = "IRON", aggression = 0.8, defense = 0.7, speed = 1.2, react = 8,  health = 120, pattern = 4 },
}

-- Forward declarations
local draw_fighter, update_fighter, update_ai, check_punch_hit
local draw_health_bar, draw_ring, draw_crowd, draw_hud
local start_round, end_round, start_fight, reset_fighters
local play_hit_sound, play_crowd_sound, play_bell
local play_whoosh_sound

----------------------------------------------
-- SOUND
----------------------------------------------
function play_hit_sound(punch_type, is_blocked)
    if is_blocked then
        noise(2, 0.04)
        note(3, "A2", 0.03)
        return
    end
    if punch_type == "jab" then
        noise(1, 0.06)
        note(2, "G3", 0.05)
    elseif punch_type == "hook" then
        noise(1, 0.1)
        note(2, "E3", 0.08)
        noise(3, 0.04)
    elseif punch_type == "power_cross" then
        noise(1, 0.14)
        note(2, "C3", 0.1)
        noise(3, 0.07)
        tone(0, 120, 80, 0.06)
    elseif punch_type == "uppercut" then
        noise(1, 0.18)
        tone(2, 150, 450, 0.12)
        noise(3, 0.1)
        tone(0, 100, 60, 0.08)
    end
end

function play_whoosh_sound()
    tone(3, 400, 200, 0.03)
end

function play_crowd_sound()
    noise(0, 0.3)
    if game.crowd_energy > 70 then
        noise(3, 0.2)
        tone(0, 300, 500, 0.15)
    end
end

function play_bell()
    note(0, "E5", 0.3)
    note(1, "E5", 0.15)
end

----------------------------------------------
-- TITLE SCENE
----------------------------------------------
function title_init()
    game.mode = "title"
    game.flash_timer = 0
    game.tournament_fight = 1
    game.tournament_wins = 0
    game.idle_timer = 0
    game.attract_mode = false
    game.attract_timer = 0
    particles = {}
end

-- Attract mode fighters
local attract_p1 = {}
local attract_p2 = {}

function title_update()
    game.flash_timer = game.flash_timer + 1

    -- Attract mode logic
    if game.attract_mode then
        game.attract_timer = game.attract_timer + 1
        -- Update attract mode fighters
        update_attract_mode()
        if btnp("start") or btnp("a") then
            game.attract_mode = false
            game.idle_timer = 0
            game.attract_timer = 0
            return
        end
        -- If a fighter somehow reaches KO, restart a new attract fight
        if attract_p1.state == "ko" or attract_p2.state == "ko" then
            start_attract_mode()
            return
        end
        return
    end

    -- Track idle time
    if btnp("start") then
        game.mode = "tournament_intro"
        game.idle_timer = 0
        go("tournament")
        return
    end

    -- Check any button to reset idle
    if btn("left") or btn("right") or btn("up") or btn("down") or btn("a") or btn("b") then
        game.idle_timer = 0
    else
        game.idle_timer = game.idle_timer + 1
    end

    -- Enter attract mode after idle threshold
    if game.idle_timer >= game.ATTRACT_IDLE_THRESHOLD then
        start_attract_mode()
    end
end

function start_attract_mode()
    game.attract_mode = true
    game.attract_timer = 0
    particles = {}

    attract_p1 = new_fighter(55, 1, false)
    attract_p1.ai_aggression = 0.5
    attract_p1.ai_defense = 0.4
    attract_p1.ai_speed = 1.0
    attract_p1.ai_react_time = 10
    attract_p1.ai_pattern = 1
    attract_p1.ai_name = "RED"
    attract_p1.is_player = true  -- for coloring only

    attract_p2 = new_fighter(105, -1, false)
    attract_p2.ai_aggression = 0.5
    attract_p2.ai_defense = 0.4
    attract_p2.ai_speed = 1.0
    attract_p2.ai_react_time = 12
    attract_p2.ai_pattern = 2
    attract_p2.ai_name = "BLU"
end

function update_attract_mode()
    -- Hitstop in attract
    if hitstop.active then
        hitstop.frames = hitstop.frames - 1
        if hitstop.frames <= 0 then hitstop.active = false end
        return
    end

    update_fighter(attract_p1)
    update_fighter(attract_p2)
    update_particles()

    -- Both controlled by AI
    if attract_p1.state ~= "knockdown" and attract_p1.state ~= "getting_up" and attract_p1.state ~= "ko" then
        update_ai(attract_p1, attract_p2)
    end
    if attract_p2.state ~= "knockdown" and attract_p2.state ~= "getting_up" and attract_p2.state ~= "ko" then
        update_ai(attract_p2, attract_p1)
    end

    -- Facing
    if attract_p1.state ~= "knockdown" and attract_p1.state ~= "ko" then
        attract_p1.facing = (attract_p2.x > attract_p1.x) and 1 or -1
    end
    if attract_p2.state ~= "knockdown" and attract_p2.state ~= "ko" then
        attract_p2.facing = (attract_p1.x > attract_p2.x) and 1 or -1
    end

    check_punch_hit(attract_p1, attract_p2)
    check_punch_hit(attract_p2, attract_p1)

    clamp_fighter(attract_p1)
    clamp_fighter(attract_p2)

    -- Handle knockdowns simply - just get up after a bit
    handle_attract_knockdown(attract_p1)
    handle_attract_knockdown(attract_p2)
end

function handle_attract_knockdown(f)
    if f.state == "knockdown" then
        f.count_timer = f.count_timer + 1
        if f.count_timer > 80 then
            f.state = "getting_up"
            f.state_timer = 20
            f.health = math.max(40, f.health)
        end
    end
    if f.state == "getting_up" and f.state_timer <= 0 then
        f.state = "idle"
    end
end

function title_draw()
    local s = screen()
    cls(s, C_BLACK)

    if game.attract_mode then
        -- Draw attract mode fight
        draw_ring(s)
        draw_crowd(s)

        -- Draw attract fighters
        if attract_p1.x < attract_p2.x then
            draw_fighter(s, attract_p2)
            draw_fighter(s, attract_p1)
        else
            draw_fighter(s, attract_p1)
            draw_fighter(s, attract_p2)
        end

        draw_particles(s)

        -- Overlay: darken top and bottom
        rectf(s, 0, 0, 160, 14, C_BLACK)
        rectf(s, 0, 108, 160, 12, C_BLACK)

        -- Title overlay
        text(s, "K N O C K O U T !", 80, 3, C_WHITE, ALIGN_CENTER)
        line(s, 30, 11, 130, 11, C_BRIGHT1)

        -- PRESS START flashing
        if game.flash_timer % 30 < 20 then
            text(s, "PRESS START", 80, 112, C_WHITE, ALIGN_CENTER)
        end

        -- DEMO label
        text(s, "DEMO", 2, 3, C_GRAY)

        -- 7-segment clock (HH:MM) top-right, dim
        draw_clock(s, 118, 2, C_DARK2)
        return
    end

    -- Normal title screen
    -- Ring background
    rectf(s, 0, 70, 160, 50, C_DARK3)
    line(s, 0, 70, 160, 70, C_MID1)
    line(s, 0, 68, 160, 68, C_GRAY)

    -- Title
    text(s, "K N O C K O U T !", 80, 15, C_WHITE, ALIGN_CENTER)
    -- Underline
    line(s, 30, 24, 130, 24, C_BRIGHT1)

    -- Silhouette boxers
    -- Left boxer
    rectf(s, 45, 40, 10, 20, C_LIGHT1)
    circf(s, 50, 36, 5, C_LIGHT1)
    line(s, 55, 45, 62, 40, C_LIGHT1) -- extended punch
    -- Right boxer
    rectf(s, 105, 42, 10, 18, C_DARK1)
    circf(s, 110, 38, 5, C_DARK1)
    line(s, 105, 47, 98, 42, C_DARK1)

    -- Impact star
    if game.flash_timer % 30 < 15 then
        local sx, sy = 80, 41
        for a = 0, 5 do
            local angle = a * 1.047 + game.flash_timer * 0.05
            local ex = sx + math.cos(angle) * 6
            local ey = sy + math.sin(angle) * 6
            line(s, sx, sy, ex, ey, C_WHITE)
        end
    end

    -- Instructions
    if game.flash_timer % 40 < 25 then
        text(s, "PRESS START", 80, 90, C_BRIGHT1, ALIGN_CENTER)
    end

    text(s, "D-PAD:MOVE  A:JAB  B:POWER", 80, 103, C_GRAY, ALIGN_CENTER)
    text(s, "UP+A:HOOK  UP+B:UPPERCUT", 80, 112, C_GRAY, ALIGN_CENTER)
end

----------------------------------------------
-- TOURNAMENT SCENE
----------------------------------------------
function tournament_init()
    game.flash_timer = 0
end

function tournament_update()
    game.flash_timer = game.flash_timer + 1
    if btnp("start") or btnp("a") then
        start_fight()
        go("fight")
    end
end

function tournament_draw()
    local s = screen()
    cls(s, C_BLACK)

    text(s, "TOURNAMENT", 80, 5, C_WHITE, ALIGN_CENTER)
    line(s, 30, 13, 130, 13, C_GRAY)

    -- Bracket
    for i = 1, 4 do
        local y = 20 + (i - 1) * 22
        local c = C_DARK2
        local tc = C_GRAY
        if i < game.tournament_fight then
            c = C_DARK3
            tc = C_MID1
            text(s, "W", 15, y + 2, C_BRIGHT1)
        elseif i == game.tournament_fight then
            c = C_MID2
            tc = C_WHITE
            if game.flash_timer % 30 < 20 then
                text(s, ">", 15, y + 2, C_WHITE)
            end
        end
        rectf(s, 25, y, 110, 18, c)
        rect(s, 25, y, 110, 18, C_GRAY)
        text(s, "FIGHT " .. i .. ": " .. opponents[i].name, 80, y + 6, tc, ALIGN_CENTER)
    end

    if game.flash_timer % 40 < 25 then
        text(s, "PRESS A TO FIGHT", 80, 110, C_BRIGHT1, ALIGN_CENTER)
    end
end

----------------------------------------------
-- FIGHT SCENE
----------------------------------------------
function fight_init()
    -- Already set up by start_fight
    particles = {}
end

function fight_update()
    if game.pause then
        if btnp("select") then
            game.pause = false
        end
        return
    end
    if btnp("select") then
        game.pause = true
        return
    end

    -- Hitstop freeze
    if hitstop.active then
        hitstop.frames = hitstop.frames - 1
        if hitstop.frames <= 0 then
            hitstop.active = false
        end
        -- Still decay shake during hitstop for visual feel
        if game.shake_timer > 0 then
            game.shake_timer = game.shake_timer - 1
            if game.shake_timer <= 0 then game.shake_amount = 0 end
        end
        return
    end

    -- Screen shake decay
    if game.shake_timer > 0 then
        game.shake_timer = game.shake_timer - 1
        if game.shake_timer <= 0 then
            game.shake_amount = 0
        end
    end

    game.flash_timer = game.flash_timer + 1

    -- Update particles
    update_particles()

    -- Crowd energy decay
    if game.crowd_energy > 0 then
        game.crowd_energy = game.crowd_energy - 0.1
    end
    game.crowd_timer = game.crowd_timer + 1

    -- Round timer
    if p1.state ~= "knockdown" and p1.state ~= "getting_up" and p1.state ~= "ko"
       and p2.state ~= "knockdown" and p2.state ~= "getting_up" and p2.state ~= "ko"
       and game.mode == "fighting" then
        game.round_timer = game.round_timer - (1/60)
        if game.round_timer <= 0 then
            game.round_timer = 0
            end_round("time")
            return
        end
    end

    -- Update fighters
    update_fighter(p1)
    update_fighter(p2)

    -- AI for p2
    if p2.state ~= "knockdown" and p2.state ~= "getting_up" and p2.state ~= "ko" then
        update_ai(p2, p1)
    end

    -- Player input
    if p1.state ~= "knockdown" and p1.state ~= "getting_up" and p1.state ~= "ko"
       and game.mode == "fighting" then
        handle_player_input()
    end

    -- Knockdown count logic
    handle_knockdown(p1)
    handle_knockdown(p2)

    -- Check punch collisions
    check_punch_hit(p1, p2)
    check_punch_hit(p2, p1)

    -- Keep fighters in ring
    clamp_fighter(p1)
    clamp_fighter(p2)

    -- Facing logic
    if p1.state ~= "knockdown" and p1.state ~= "ko" then
        p1.facing = (p2.x > p1.x) and 1 or -1
    end
    if p2.state ~= "knockdown" and p2.state ~= "ko" then
        p2.facing = (p1.x > p2.x) and 1 or -1
    end

    -- Crowd sounds
    if game.crowd_timer % 120 == 0 and game.crowd_energy > 50 then
        play_crowd_sound()
    end
end

function fight_draw()
    local s = screen()
    cls(s, C_BLACK)

    -- Apply screen shake
    local sx, sy = 0, 0
    if game.shake_amount > 0 then
        sx = math.random(-game.shake_amount, game.shake_amount)
        sy = math.random(-game.shake_amount, game.shake_amount)
        cam(sx, sy)
    else
        cam(0, 0)
    end

    -- Draw ring
    draw_ring(s)

    -- Draw crowd
    draw_crowd(s)

    -- Draw fighters (back one first)
    if p1.x < p2.x then
        draw_fighter(s, p2)
        draw_fighter(s, p1)
    else
        draw_fighter(s, p1)
        draw_fighter(s, p2)
    end

    -- Draw particles
    draw_particles(s)

    -- Reset camera for HUD
    cam(0, 0)

    -- Draw HUD
    draw_hud(s)

    -- Pause overlay
    if game.pause then
        rectf(s, 40, 45, 80, 30, C_BLACK)
        rect(s, 40, 45, 80, 30, C_WHITE)
        text(s, "PAUSED", 80, 52, C_WHITE, ALIGN_CENTER)
        text(s, "SELECT TO RESUME", 80, 62, C_GRAY, ALIGN_CENTER)
    end

    -- Knockdown count display
    if p1.state == "knockdown" or p2.state == "knockdown" then
        local knocked = (p1.state == "knockdown") and p1 or p2
        if knocked.current_count > 0 then
            -- Large count with shadow
            local count_str = tostring(knocked.current_count)
            text(s, count_str, 81, 48, C_BLACK, ALIGN_CENTER)
            text(s, count_str, 80, 47, C_WHITE, ALIGN_CENTER)
        end
    end

    -- Round start countdown
    if game.mode == "round_start" then
        local t = game.flash_timer
        local fade_c = C_WHITE
        if t < 60 then
            -- "ROUND X" with dramatic entrance
            local label = "ROUND " .. game.round
            text(s, label, 81, 43, C_BLACK, ALIGN_CENTER)
            text(s, label, 80, 42, fade_c, ALIGN_CENTER)
            -- Decorative lines
            local lw = math.min(40, t)
            line(s, 80 - lw, 50, 80 + lw, 50, C_GRAY)
        elseif t < 90 then
            text(s, "FIGHT!", 81, 43, C_BLACK, ALIGN_CENTER)
            text(s, "FIGHT!", 80, 42, C_WHITE, ALIGN_CENTER)
            -- Flash burst
            if t < 65 then
                for a = 0, 7 do
                    local angle = a * 0.785 + t * 0.2
                    local r = (t - 60) * 2
                    line(s, 80, 45, 80 + math.cos(angle)*r, 45 + math.sin(angle)*r, C_BRIGHT1)
                end
            end
        end
    end

    -- KO text
    if game.mode == "ko_finish" then
        if game.flash_timer % 8 < 5 then
            -- Dramatic KO with shadow
            text(s, "K.O.!", 81, 38, C_BLACK, ALIGN_CENTER)
            text(s, "K.O.!", 80, 37, C_WHITE, ALIGN_CENTER)
        end
        -- Star burst around KO text
        if game.flash_timer < 20 then
            for a = 0, 5 do
                local angle = a * 1.047 + game.flash_timer * 0.3
                local r = game.flash_timer * 0.8
                line(s, 80, 40, 80 + math.cos(angle)*r, 40 + math.sin(angle)*r, C_BRIGHT1)
            end
        end
    end
end

----------------------------------------------
-- BETWEEN ROUNDS SCENE
----------------------------------------------
function between_init()
    game.flash_timer = 0
end

function between_update()
    game.flash_timer = game.flash_timer + 1
    if btnp("start") or btnp("a") then
        game.round = game.round + 1
        start_round()
        go("fight")
    end
end

function between_draw()
    local s = screen()
    cls(s, C_BLACK)

    text(s, "END OF ROUND " .. game.round, 80, 8, C_WHITE, ALIGN_CENTER)
    line(s, 25, 16, 135, 16, C_GRAY)

    -- Stats
    text(s, "YOU", 45, 24, C_LIGHT1, ALIGN_CENTER)
    text(s, opponents[game.tournament_fight].name, 115, 24, C_LIGHT2, ALIGN_CENTER)

    local stats = {
        { "HEALTH", string.format("%d%%", p1.health), string.format("%d%%", p2.health) },
        { "PUNCHES", string.format("%d/%d", p1.punches_landed, p1.punches_thrown),
                     string.format("%d/%d", p2.punches_landed, p2.punches_thrown) },
        { "DAMAGE", tostring(math.floor(p1.damage_dealt)), tostring(math.floor(p2.damage_dealt)) },
        { "K-DOWNS", tostring(p1.total_knockdowns), tostring(p2.total_knockdowns) },
    }
    for i, st in ipairs(stats) do
        local y = 34 + (i-1) * 14
        text(s, st[1], 80, y, C_GRAY, ALIGN_CENTER)
        text(s, st[2], 45, y + 7, C_BRIGHT1, ALIGN_CENTER)
        text(s, st[3], 115, y + 7, C_BRIGHT1, ALIGN_CENTER)
    end

    -- Scores
    text(s, "SCORECARD", 80, 92, C_WHITE, ALIGN_CENTER)
    local p1_total, p2_total = 0, 0
    for i, sc in ipairs(game.decision_scores) do
        p1_total = p1_total + sc[1]
        p2_total = p2_total + sc[2]
        text(s, string.format("R%d: %d-%d", i, sc[1], sc[2]), 80, 98 + (i-1)*8, C_GRAY, ALIGN_CENTER)
    end

    if game.flash_timer % 40 < 25 then
        text(s, "PRESS A FOR NEXT ROUND", 80, 112, C_BRIGHT1, ALIGN_CENTER)
    end
end

----------------------------------------------
-- GAME OVER SCENE
----------------------------------------------
function gameover_init()
    game.flash_timer = 0
end

function gameover_update()
    game.flash_timer = game.flash_timer + 1
    if btnp("start") then
        go("title")
    end
end

function gameover_draw()
    local s = screen()
    cls(s, C_BLACK)

    local won = game.mode == "player_wins"

    if won then
        text(s, "VICTORY!", 80, 20, C_WHITE, ALIGN_CENTER)
        -- Trophy
        rectf(s, 72, 38, 16, 12, C_BRIGHT1)
        rectf(s, 76, 50, 8, 4, C_BRIGHT2)
        rectf(s, 70, 54, 20, 3, C_BRIGHT1)
        -- Handles
        line(s, 71, 40, 67, 44, C_BRIGHT1)
        line(s, 67, 44, 71, 48, C_BRIGHT1)
        line(s, 89, 40, 93, 44, C_BRIGHT1)
        line(s, 93, 44, 89, 48, C_BRIGHT1)

        if game.tournament_fight >= 4 then
            text(s, "CHAMPION!", 80, 65, C_WHITE, ALIGN_CENTER)
            text(s, "YOU BEAT ALL OPPONENTS", 80, 76, C_GRAY, ALIGN_CENTER)
        else
            text(s, "YOU DEFEATED " .. opponents[game.tournament_fight].name, 80, 65, C_GRAY, ALIGN_CENTER)
        end
    else
        text(s, "DEFEAT", 80, 25, C_GRAY, ALIGN_CENTER)
        text(s, opponents[game.tournament_fight].name .. " WINS", 80, 40, C_WHITE, ALIGN_CENTER)

        -- Down fighter silhouette
        rectf(s, 55, 65, 20, 6, C_LIGHT1)
        circf(s, 52, 67, 4, C_LIGHT1)
    end

    -- Result text
    if game.ko_type then
        text(s, game.ko_type, 80, 88, C_BRIGHT1, ALIGN_CENTER)
    end

    if game.flash_timer % 40 < 25 then
        text(s, "PRESS START", 80, 108, C_BRIGHT1, ALIGN_CENTER)
    end
end

----------------------------------------------
-- FIGHTER LOGIC
----------------------------------------------
function handle_player_input()
    if p1.state == "hit_stun" or p1.state == "knockdown" or p1.state == "getting_up" or p1.state == "ko" then
        return
    end

    local moving = false

    -- Block: hold down
    if btn("down") and p1.state ~= "jab" and p1.state ~= "hook" and p1.state ~= "uppercut" and p1.state ~= "power_cross" then
        p1.state = "block"
        p1.state_timer = 0
    else
        if p1.state == "block" then
            p1.state = "idle"
        end

        -- Movement
        if p1.state == "idle" or p1.state == "walk_fwd" or p1.state == "walk_back" then
            if btn("right") then
                p1.x = p1.x + 1.2
                p1.state = (p1.facing == 1) and "walk_fwd" or "walk_back"
                p1.foot_anim = p1.foot_anim + 0.2
                moving = true
            elseif btn("left") then
                p1.x = p1.x - 1.2
                p1.state = (p1.facing == -1) and "walk_fwd" or "walk_back"
                p1.foot_anim = p1.foot_anim + 0.2
                moving = true
            end

            if not moving and p1.state ~= "jab" and p1.state ~= "hook"
               and p1.state ~= "uppercut" and p1.state ~= "power_cross" then
                p1.state = "idle"
            end
        end

        -- Punches
        if p1.state == "idle" or p1.state == "walk_fwd" or p1.state == "walk_back" then
            if btnp("a") then
                if btn("up") then
                    start_punch(p1, "hook")
                else
                    start_punch(p1, "jab")
                end
            elseif btnp("b") then
                if btn("up") then
                    start_punch(p1, "uppercut")
                else
                    start_punch(p1, "power_cross")
                end
            end
        end
    end

    -- Stamina regen
    if p1.state == "idle" or p1.state == "block" then
        p1.stamina = math.min(p1.max_stamina, p1.stamina + 0.15)
    end
end

function start_punch(fighter, punch_type)
    local cost = 0
    local damage = 0
    local duration = 0

    if punch_type == "jab" then
        cost = 5
        damage = 5
        duration = 10  -- Slightly faster jab
    elseif punch_type == "hook" then
        cost = 12
        damage = 10
        duration = 16
    elseif punch_type == "power_cross" then
        cost = 15
        damage = 12
        duration = 18
    elseif punch_type == "uppercut" then
        cost = 20
        damage = 18
        duration = 22
    end

    if fighter.stamina < cost then return end

    fighter.stamina = fighter.stamina - cost
    fighter.state = punch_type
    fighter.state_timer = duration
    fighter.punch_damage = damage
    fighter.punch_hit = false
    fighter.punches_thrown = fighter.punches_thrown + 1
    fighter.anim_frame = 0

    -- Body lean into punch
    if punch_type == "jab" then
        fighter.target_lean = fighter.facing * 0.3
    elseif punch_type == "hook" then
        fighter.target_lean = fighter.facing * 0.5
    elseif punch_type == "power_cross" then
        fighter.target_lean = fighter.facing * 0.7
    elseif punch_type == "uppercut" then
        fighter.target_lean = fighter.facing * 0.4
    end

    -- Whoosh sound on swing
    play_whoosh_sound()

    -- Combo tracking
    if fighter.combo_timer > 0 then
        fighter.combo_count = fighter.combo_count + 1
        if fighter.combo_count >= 3 then
            fighter.punch_damage = damage * 1.5
        end
    else
        fighter.combo_count = 1
    end
    fighter.combo_timer = 30
    fighter.last_punch = punch_type
end

function update_fighter(f)
    f.bob_timer = f.bob_timer + 1

    -- Smooth lean interpolation
    f.lean = f.lean + (f.target_lean - f.lean) * 0.2
    if f.state == "idle" or f.state == "walk_fwd" or f.state == "walk_back" or f.state == "block" then
        f.target_lean = 0
    end

    -- Hit flash decay
    if f.hit_flash > 0 then
        f.hit_flash = f.hit_flash - 1
    end

    -- Combo timer
    if f.combo_timer > 0 then
        f.combo_timer = f.combo_timer - 1
        if f.combo_timer <= 0 then
            f.combo_count = 0
        end
    end

    -- State timer
    if f.state_timer > 0 then
        f.state_timer = f.state_timer - 1
        f.anim_frame = f.anim_frame + 1
        if f.state_timer <= 0 then
            if f.state == "jab" or f.state == "hook" or f.state == "power_cross" or f.state == "uppercut" then
                f.state = "idle"
                f.target_lean = 0
            elseif f.state == "hit_stun" then
                f.state = "idle"
            elseif f.state == "dodge_back" then
                f.state = "idle"
            end
        end
    end

    -- Velocity / knockback
    if f.vx ~= 0 then
        f.x = f.x + f.vx
        f.vx = f.vx * 0.82
        if math.abs(f.vx) < 0.1 then f.vx = 0 end
    end

    -- Gravity for knockdown
    if not f.on_ground then
        f.vy = f.vy + GRAVITY
        f.y = f.y + f.vy
        if f.y >= RING_Y then
            f.y = RING_Y
            f.on_ground = true
            f.vy = 0
            -- Impact sound and particles when hitting ground
            noise(2, 0.08)
            spawn_hit_particles(f.x, RING_Y, 4, 1)
        end
    end

    -- Stamina regen for AI when idle
    if not f.is_player and (f.state == "idle" or f.state == "block") then
        f.stamina = math.min(f.max_stamina, f.stamina + 0.12)
    end

    -- AI retreat timer
    if f.ai_retreat_timer > 0 then
        f.ai_retreat_timer = f.ai_retreat_timer - 1
    end
end

function handle_knockdown(f)
    if f.state == "knockdown" then
        f.count_timer = f.count_timer + 1
        if f.count_timer % 40 == 0 then
            f.current_count = f.current_count + 1
            note(3, "C3", 0.1)

            if f.current_count >= KNOCKDOWN_COUNT then
                f.state = "ko"
                game.mode = "ko_finish"
                game.flash_timer = 0
                game.ko_type = "K.O.!"
                cam_shake(5)
                note(0, "C5", 0.3)
                note(1, "E5", 0.3)
                note(2, "G5", 0.3)
            end
        end

        -- Player can mash A to get up faster
        if f.is_player and f.current_count < 9 then
            if btnp("a") then
                f.count_timer = f.count_timer + 8
                if f.health > 0 and f.current_count < 8 then
                    f.state = "getting_up"
                    f.state_timer = 30
                    f.health = math.max(f.health, 10)
                end
            end
        end

        -- AI gets up based on health
        if not f.is_player and f.current_count >= 4 and f.health > 15 then
            if math.random() < 0.15 then
                f.state = "getting_up"
                f.state_timer = 30
            end
        end
    end

    if f.state == "getting_up" and f.state_timer <= 0 then
        f.state = "idle"
        f.knockdown_count = f.knockdown_count + 1
        f.total_knockdowns = f.total_knockdowns + 1
        if f.knockdown_count >= 3 then
            f.state = "ko"
            game.mode = "ko_finish"
            game.flash_timer = 0
            game.ko_type = "T.K.O.!"
        end
    end

    -- KO finish transition
    if game.mode == "ko_finish" then
        game.flash_timer = game.flash_timer + 1
        if game.flash_timer > 120 then
            local player_won = (p2.state == "ko")
            game.mode = player_won and "player_wins" or "player_loses"

            if player_won then
                game.tournament_wins = game.tournament_wins + 1
                if game.tournament_fight >= 4 then
                    go("gameover")
                else
                    game.tournament_fight = game.tournament_fight + 1
                    go("gameover")
                end
            else
                go("gameover")
            end
        end
    end
end

function check_punch_hit(attacker, defender)
    if attacker.state ~= "jab" and attacker.state ~= "hook"
       and attacker.state ~= "power_cross" and attacker.state ~= "uppercut" then
        return
    end
    if attacker.punch_hit then return end

    -- Hitbox timing: tighter active windows
    local total = 0
    if attacker.state == "jab" then total = 10
    elseif attacker.state == "hook" then total = 16
    elseif attacker.state == "power_cross" then total = 18
    elseif attacker.state == "uppercut" then total = 22
    end

    local progress = attacker.anim_frame
    -- Tighter active window: only middle 60% of animation
    local start_frame = math.floor(total * 0.2)
    local end_frame = math.floor(total * 0.7)
    if progress < start_frame or progress > end_frame then return end

    -- Range check with per-punch reach
    local dist = math.abs(attacker.x - defender.x)
    local reach = 22
    if attacker.state == "jab" then reach = 20
    elseif attacker.state == "hook" then reach = 21
    elseif attacker.state == "power_cross" then reach = 23
    elseif attacker.state == "uppercut" then reach = 18 end

    if dist > reach then return end

    attacker.punch_hit = true
    attacker.punches_landed = attacker.punches_landed + 1

    -- Blocked?
    if defender.state == "block" then
        local reduced = attacker.punch_damage * 0.2
        defender.health = math.max(0, defender.health - reduced)
        defender.stamina = math.max(0, defender.stamina - attacker.punch_damage * 0.5)
        play_hit_sound(attacker.state, true)
        defender.vx = attacker.facing * 1.2
        game.crowd_energy = math.min(100, game.crowd_energy + 2)
        -- Small block spark
        local bx = (attacker.x + defender.x) / 2
        spawn_hit_particles(bx, RING_Y - 14, 2, 0.5)
        return
    end

    -- Hit!
    local dmg = attacker.punch_damage
    if attacker.combo_count >= 3 then
        dmg = dmg * 1.3
    end

    defender.health = math.max(0, defender.health - dmg)
    attacker.damage_dealt = attacker.damage_dealt + dmg

    -- Hit stun with variable duration based on punch
    local stun_dur = 8
    if attacker.state == "hook" then stun_dur = 10
    elseif attacker.state == "power_cross" then stun_dur = 12
    elseif attacker.state == "uppercut" then stun_dur = 14 end

    defender.state = "hit_stun"
    defender.state_timer = stun_dur
    defender.anim_frame = 0
    defender.hit_flash = 4

    -- Knockback varies by punch type
    local kb = 2
    if attacker.state == "hook" then kb = 2.5
    elseif attacker.state == "power_cross" then kb = 3
    elseif attacker.state == "uppercut" then kb = 1.5 end
    defender.vx = attacker.facing * kb

    -- Sound
    play_hit_sound(attacker.state, false)

    -- Impact particles
    local hit_x = (attacker.x + defender.x) / 2
    local hit_y = RING_Y - 14
    local pcount = 3
    local pintensity = 1.0
    if attacker.state == "power_cross" then pcount = 5; pintensity = 1.5 end
    if attacker.state == "uppercut" then pcount = 6; pintensity = 2.0; hit_y = RING_Y - 18 end
    if attacker.state == "hook" then pcount = 4; pintensity = 1.2 end
    spawn_hit_particles(hit_x, hit_y, pcount, pintensity)

    -- Sweat on big hits
    if attacker.state == "uppercut" or attacker.state == "power_cross" or attacker.combo_count >= 3 then
        spawn_sweat(defender.x, defender.y, attacker.facing)
    end

    -- Hitstop on power punches
    if attacker.state == "uppercut" then
        do_hitstop(4)
    elseif attacker.state == "power_cross" then
        do_hitstop(3)
    elseif attacker.state == "hook" then
        do_hitstop(2)
    end

    -- Crowd energy
    game.crowd_energy = math.min(100, game.crowd_energy + dmg * 0.5)

    -- Screen shake on power hits
    if attacker.state == "uppercut" or attacker.state == "power_cross" then
        game.shake_amount = 3
        game.shake_timer = 8
        cam_shake(3)
    end
    if attacker.combo_count >= 3 then
        game.shake_amount = 2
        game.shake_timer = 5
        cam_shake(2)
    end

    -- Knockdown check
    if defender.health <= 0 or
       (attacker.state == "uppercut" and defender.health < 25) or
       (attacker.combo_count >= 3 and defender.health < 30) then
        defender.state = "knockdown"
        defender.state_timer = 0
        defender.count_timer = 0
        defender.current_count = 0
        defender.vx = attacker.facing * 4
        defender.vy = -3
        defender.on_ground = false

        game.shake_amount = 5
        game.shake_timer = 15
        cam_shake(5)
        do_hitstop(6)

        -- Big crowd reaction
        game.crowd_energy = 100
        play_crowd_sound()

        -- Knockdown particles burst
        spawn_hit_particles(hit_x, hit_y, 10, 2.5)

        note(0, "G5", 0.2)
        note(1, "C5", 0.2)
    end
end

function clamp_fighter(f)
    if f.x < RING_LEFT + 5 then f.x = RING_LEFT + 5 end
    if f.x > RING_RIGHT - 5 then f.x = RING_RIGHT - 5 end
end

----------------------------------------------
-- AI SYSTEM
----------------------------------------------
function update_ai(ai, target)
    ai.ai_timer = ai.ai_timer + 1

    local dist = math.abs(ai.x - target.x)
    local in_range = dist < 24
    local close = dist < 16
    local far = dist > 35

    -- Spacing awareness: maintain optimal distance
    local optimal_dist = 22
    local too_close = dist < 14

    -- React time gate
    if ai.ai_timer % math.max(1, ai.ai_react_time) ~= 0 and ai.state == "idle" then
        -- Approach if far
        if far then
            ai.x = ai.x + ai.facing * 0.8 * ai.ai_speed
            ai.state = "walk_fwd"
            ai.foot_anim = ai.foot_anim + 0.15
        elseif too_close and ai.ai_retreat_timer <= 0 then
            -- Back away if too close
            ai.x = ai.x - ai.facing * 0.4 * ai.ai_speed
            ai.state = "walk_back"
        end
        return
    end

    -- Retreat after getting hit
    if ai.ai_retreat_timer > 0 and ai.state == "idle" then
        ai.x = ai.x - ai.facing * 0.5 * ai.ai_speed
        ai.state = "walk_back"
        return
    end

    -- AI patterns
    if ai.ai_pattern == 1 then
        -- JOEY: Basic, approaches and jabs
        if in_range then
            if math.random() < ai.ai_aggression then
                if math.random() < 0.7 then
                    start_punch(ai, "jab")
                else
                    start_punch(ai, "hook")
                end
            elseif math.random() < ai.ai_defense then
                ai.state = "block"
                ai.state_timer = 20
            end
        else
            ai.x = ai.x + ai.facing * 0.7 * ai.ai_speed
            ai.foot_anim = ai.foot_anim + 0.15
        end

    elseif ai.ai_pattern == 2 then
        -- RICO: Counter-puncher, blocks then strikes
        if target.state == "jab" or target.state == "hook" or target.state == "power_cross" or target.state == "uppercut" then
            if in_range and math.random() < ai.ai_defense then
                ai.state = "block"
                ai.state_timer = 15
            end
        elseif target.state == "hit_stun" or (target.state_timer ~= nil and target.state_timer > 0 and target.state_timer < 4) then
            if in_range and math.random() < 0.6 then
                start_punch(ai, "power_cross")
            end
        elseif in_range then
            if math.random() < ai.ai_aggression * 0.7 then
                start_punch(ai, "jab")
            end
        else
            ai.x = ai.x + ai.facing * 0.6 * ai.ai_speed
            ai.foot_anim = ai.foot_anim + 0.12
        end

    elseif ai.ai_pattern == 3 then
        -- BULL: Aggressive, rushes in with combos
        if in_range then
            local r = math.random()
            if r < ai.ai_aggression * 0.5 then
                start_punch(ai, "jab")
            elseif r < ai.ai_aggression * 0.8 then
                start_punch(ai, "hook")
            elseif r < ai.ai_aggression then
                start_punch(ai, "uppercut")
            end
        else
            ai.x = ai.x + ai.facing * 1.1 * ai.ai_speed
            ai.foot_anim = ai.foot_anim + 0.2
        end
        if close and target.state == "uppercut" and math.random() < 0.3 then
            ai.state = "block"
            ai.state_timer = 10
        end

    elseif ai.ai_pattern == 4 then
        -- IRON: Smart, mixes everything, punishes mistakes
        if target.state == "hit_stun" then
            if in_range then
                if math.random() < 0.5 then
                    start_punch(ai, "uppercut")
                else
                    start_punch(ai, "power_cross")
                end
            end
        elseif target.state == "jab" or target.state == "hook" or target.state == "power_cross" or target.state == "uppercut" then
            if math.random() < ai.ai_defense then
                ai.state = "block"
                ai.state_timer = 12
            end
        elseif in_range then
            local r = math.random()
            if r < 0.25 then
                start_punch(ai, "jab")
            elseif r < 0.45 then
                start_punch(ai, "hook")
            elseif r < 0.6 then
                start_punch(ai, "power_cross")
            elseif r < 0.7 then
                start_punch(ai, "uppercut")
            else
                ai.state = "block"
                ai.state_timer = 15
            end
        else
            ai.x = ai.x + ai.facing * 0.9 * ai.ai_speed
            ai.foot_anim = ai.foot_anim + 0.15
            -- Smart feinting approach
            if math.random() < 0.1 then
                ai.state = "block"
                ai.state_timer = 8
            end
        end
    end

    -- Retreat after being hit (set in check_punch_hit via hit_stun transition)
    if ai.state == "hit_stun" then
        ai.ai_retreat_timer = 20 + math.random(15)
    end

    -- Fallback approach
    if ai.state == "idle" and dist > 25 then
        ai.x = ai.x + ai.facing * 0.6 * ai.ai_speed
        ai.foot_anim = ai.foot_anim + 0.12
    end
end

----------------------------------------------
-- DRAWING FUNCTIONS
----------------------------------------------
function draw_ring(s)
    -- Floor
    rectf(s, 0, RING_Y + 10, 160, 30, C_DARK3)

    -- Ring mat with subtle gradient
    rectf(s, RING_LEFT - 5, RING_Y - 2, RING_RIGHT - RING_LEFT + 10, 14, C_DARK2)
    -- Center circle on mat
    circ(s, 80, RING_Y + 5, 15, C_DARK3)

    -- Ring mat highlight
    line(s, RING_LEFT - 5, RING_Y - 2, RING_RIGHT + 5, RING_Y - 2, C_MID2)

    -- Corner posts
    rectf(s, RING_LEFT - 3, RING_TOP_ROPE - 5, 4, RING_Y - RING_TOP_ROPE + 10, C_MID1)
    rectf(s, RING_RIGHT - 1, RING_TOP_ROPE - 5, 4, RING_Y - RING_TOP_ROPE + 10, C_MID1)

    -- Ropes (3)
    for i = 0, 2 do
        local ry = RING_TOP_ROPE + i * 12
        line(s, RING_LEFT - 2, ry, RING_RIGHT + 2, ry, C_GRAY)
        -- Rope slight sag in middle
        pix(s, 80, ry + 1, C_GRAY)
    end

    -- Turnbuckle pads
    rectf(s, RING_LEFT - 4, RING_TOP_ROPE - 6, 6, 6, C_LIGHT1)
    rectf(s, RING_RIGHT - 2, RING_TOP_ROPE - 6, 6, 6, C_LIGHT1)
end

function draw_crowd(s)
    -- Simple crowd silhouettes in background
    for i = 0, 20 do
        local cx = i * 8
        local cy = 6 + math.sin(i * 1.3 + game.flash_timer * 0.03) * 2
        local shade = C_DARK3
        if game.crowd_energy > 50 then
            cy = cy + math.sin(game.flash_timer * 0.2 + i) * 2
            shade = C_DARK2
        end
        if game.crowd_energy > 80 then
            cy = cy + math.sin(game.flash_timer * 0.35 + i * 0.7) * 1
        end
        circf(s, cx, cy + 10, 2, shade)
        rectf(s, cx - 1, cy + 12, 3, 5, shade)
    end

    -- Second row
    for i = 0, 15 do
        local cx = i * 10 + 5
        local cy = 2 + math.sin(i * 0.9 + game.flash_timer * 0.02) * 1
        circf(s, cx, cy + 4, 2, C_DARK3)
        rectf(s, cx - 1, cy + 6, 3, 4, C_DARK3)
    end
end

function draw_fighter(s, f)
    local px = math.floor(f.x)
    local py = math.floor(f.y)
    local fac = f.facing
    local bob = math.sin(f.bob_timer * 0.1) * 1.5

    -- Color: player is lighter, opponent darker
    local body_c = f.is_player and C_LIGHT1 or C_MID2
    local skin_c = f.is_player and C_PALE1 or C_LIGHT3
    local shorts_c = f.is_player and C_BRIGHT1 or C_DARK1
    local glove_c = f.is_player and C_WHITE or C_MID1

    -- Hit flash override
    if f.hit_flash > 0 then
        body_c = C_WHITE
        skin_c = C_WHITE
    end

    -- Shadow on ground
    local shadow_w = 6
    if f.state == "knockdown" or f.state == "ko" then shadow_w = 8 end
    rectf(s, px - shadow_w, RING_Y + 3, shadow_w * 2, 2, C_DARK3)

    if f.state == "ko" then
        -- Lying on ground
        rectf(s, px - 8, py + 2, 16, 5, body_c)
        circf(s, px - 8 * fac, py + 3, 3, skin_c)
        pix(s, px - 8 * fac - 1, py + 2, C_BLACK)
        pix(s, px - 8 * fac + 1, py + 2, C_BLACK)
        return
    end

    if f.state == "knockdown" then
        local fall_prog = math.min(1, f.anim_frame / 15)
        local tilt = fall_prog * 1.5
        local bx = px + fac * tilt * 4
        local by = py - 14 + fall_prog * 10
        if f.on_ground then
            rectf(s, px - 6, py + 2, 12, 5, body_c)
            circf(s, px - 5 * fac, py + 3, 3, skin_c)
        else
            rectf(s, bx - 3, by, 6, 10, body_c)
            circf(s, bx, by - 3, 3, skin_c)
        end
        return
    end

    if f.state == "getting_up" then
        local prog = 1 - (f.state_timer / 30)
        local by = py - 14 * prog
        rectf(s, px - 3, by, 6, math.max(1, math.floor(14 * prog)), body_c)
        circf(s, px, by - 3, 3, skin_c)
        return
    end

    -- Body lean offset
    local lean_offset = math.floor(f.lean * 3)

    -- Normal standing pose
    local head_y = py - 18 + bob
    local body_top = py - 14 + bob
    local body_bot = py - 4

    -- Legs with foot animation
    local foot_off = math.sin(f.foot_anim) * 1.5
    if f.state == "idle" or f.state == "block" then foot_off = 0 end
    line(s, px, body_bot, px - 2 + foot_off, py + 2, body_c)
    line(s, px, body_bot, px + 2 - foot_off, py + 2, body_c)
    -- Shoes
    pix(s, px - 2 + math.floor(foot_off), py + 2, C_DARK1)
    pix(s, px + 2 - math.floor(foot_off), py + 2, C_DARK1)

    -- Shorts
    rectf(s, px - 3, body_bot - 2, 6, 4, shorts_c)

    -- Body (torso) with lean
    rectf(s, px - 3 + lean_offset, body_top, 6, body_bot - body_top, body_c)

    -- Head with lean
    circf(s, px + lean_offset, head_y, 3, skin_c)
    -- Eyes
    pix(s, px + lean_offset + fac, head_y - 1, C_BLACK)

    -- Headband/hair detail
    line(s, px + lean_offset - 2, head_y - 3, px + lean_offset + 2, head_y - 3, body_c)

    -- Arms based on state
    local lead_hand_x, lead_hand_y
    local rear_hand_x, rear_hand_y

    if f.state == "idle" or f.state == "walk_fwd" or f.state == "walk_back" then
        -- Guard position with subtle bob
        lead_hand_x = px + fac * 7
        lead_hand_y = body_top + 2 + bob
        rear_hand_x = px + fac * 3
        rear_hand_y = body_top + bob

    elseif f.state == "jab" then
        local total = 10
        local ext = 0
        if f.anim_frame < 3 then
            ext = f.anim_frame / 3
        elseif f.anim_frame < 6 then
            ext = 1
        else
            ext = math.max(0, 1 - ((f.anim_frame - 6) / 4))
        end
        lead_hand_x = px + lean_offset + fac * (7 + ext * 10)
        lead_hand_y = body_top + 2 + bob
        rear_hand_x = px + fac * 3
        rear_hand_y = body_top + bob

    elseif f.state == "hook" then
        local total = 16
        local ext = 0
        if f.anim_frame < 4 then
            ext = f.anim_frame / 4
        elseif f.anim_frame < 10 then
            ext = 1
        else
            ext = math.max(0, 1 - ((f.anim_frame - 10) / 6))
        end
        lead_hand_x = px + lean_offset + fac * (5 + ext * 8)
        lead_hand_y = body_top - 2 + ext * 4 + bob
        rear_hand_x = px + fac * 3
        rear_hand_y = body_top + bob

    elseif f.state == "power_cross" then
        local total = 18
        local ext = 0
        if f.anim_frame < 5 then
            ext = f.anim_frame / 5
        elseif f.anim_frame < 12 then
            ext = 1
        else
            ext = math.max(0, 1 - ((f.anim_frame - 12) / 6))
        end
        rear_hand_x = px + lean_offset + fac * (3 + ext * 14)
        rear_hand_y = body_top + 1 + bob
        lead_hand_x = px + fac * 5
        lead_hand_y = body_top + 2 + bob

    elseif f.state == "uppercut" then
        local total = 22
        local ext = 0
        if f.anim_frame < 5 then
            ext = f.anim_frame / 5
        elseif f.anim_frame < 14 then
            ext = 1
        else
            ext = math.max(0, 1 - ((f.anim_frame - 14) / 8))
        end
        rear_hand_x = px + lean_offset + fac * (4 + ext * 8)
        rear_hand_y = body_top + 6 - ext * 14 + bob
        lead_hand_x = px + fac * 5
        lead_hand_y = body_top + 2 + bob

    elseif f.state == "block" then
        lead_hand_x = px + fac * 4
        lead_hand_y = head_y + 1
        rear_hand_x = px + fac * 2
        rear_hand_y = head_y + 3

    elseif f.state == "hit_stun" then
        lead_hand_x = px - fac * 2
        lead_hand_y = body_top + 4 + bob
        rear_hand_x = px - fac * 1
        rear_hand_y = body_top + 6 + bob
    else
        lead_hand_x = px + fac * 7
        lead_hand_y = body_top + 2 + bob
        rear_hand_x = px + fac * 3
        rear_hand_y = body_top + bob
    end

    -- Draw arms
    line(s, px + lean_offset + fac * 3, body_top + 2, lead_hand_x, lead_hand_y, body_c)
    line(s, px + lean_offset + fac * 2, body_top + 1, rear_hand_x, rear_hand_y, body_c)

    -- Gloves (slightly larger for power punches)
    local glove_size = 2
    if (f.state == "power_cross" or f.state == "uppercut") and f.anim_frame > 3 and f.anim_frame < 14 then
        glove_size = 3
    end
    circf(s, math.floor(lead_hand_x), math.floor(lead_hand_y), 2, glove_c)
    circf(s, math.floor(rear_hand_x), math.floor(rear_hand_y), glove_size, glove_c)

    -- Hit effect: impact burst at contact point
    if f.state == "jab" or f.state == "hook" or f.state == "power_cross" or f.state == "uppercut" then
        if f.punch_hit and f.anim_frame < 8 then
            local hx = (f.state == "power_cross" or f.state == "uppercut") and rear_hand_x or lead_hand_x
            local hy = (f.state == "power_cross" or f.state == "uppercut") and rear_hand_y or lead_hand_y
            local num_rays = (f.state == "uppercut" or f.state == "power_cross") and 6 or 4
            for a = 0, num_rays - 1 do
                local angle = a * (6.28 / num_rays) + f.anim_frame * 0.4
                local r = math.max(0, 5 - f.anim_frame * 0.6)
                line(s, hx, hy, hx + math.cos(angle) * r, hy + math.sin(angle) * r, C_WHITE)
            end
        end
    end

    -- Combo indicator above head
    if f.combo_count >= 3 and f.combo_timer > 0 then
        -- Small stars above head
        for i = 1, math.min(f.combo_count - 2, 3) do
            local sx = px - 4 + i * 3
            local sy = head_y - 8 + math.sin(f.bob_timer * 0.3 + i) * 1
            pix(s, sx, sy, C_WHITE)
        end
    end
end

function draw_hud(s)
    -- Health bars
    -- Player (left)
    rectf(s, 5, 2, 52, 6, C_BLACK)
    rect(s, 5, 2, 52, 6, C_GRAY)
    local hw = math.floor(50 * p1.health / p1.max_health)
    if hw > 0 then
        rectf(s, 6, 3, hw, 4, C_BRIGHT1)
        -- Health bar shine
        if hw > 2 then
            line(s, 6, 3, 6 + hw - 1, 3, C_WHITE)
        end
    end
    if p1.health < 25 and game.flash_timer % 20 < 10 then
        rectf(s, 6, 3, hw, 4, C_WHITE)
    end

    -- Opponent (right)
    rectf(s, 103, 2, 52, 6, C_BLACK)
    rect(s, 103, 2, 52, 6, C_GRAY)
    hw = math.floor(50 * p2.health / p2.max_health)
    if hw > 0 then
        rectf(s, 104 + (50 - hw), 3, hw, 4, C_LIGHT2)
        if hw > 2 then
            line(s, 104 + (50 - hw), 3, 104 + 50 - 1, 3, C_WHITE)
        end
    end
    if p2.health < 25 and game.flash_timer % 20 < 10 then
        rectf(s, 104 + (50 - hw), 3, hw, 4, C_WHITE)
    end

    -- Names
    text(s, "YOU", 6, 9, C_LIGHT1)
    local opp_name = opponents[game.tournament_fight] and opponents[game.tournament_fight].name or "CPU"
    text(s, opp_name, 154, 9, C_LIGHT2, 3)

    -- Stamina bars (smaller, under health)
    rectf(s, 5, 16, 32, 3, C_BLACK)
    local sw = math.floor(30 * p1.stamina / p1.max_stamina)
    if sw > 0 then
        rectf(s, 6, 17, sw, 1, C_MID1)
    end

    rectf(s, 123, 16, 32, 3, C_BLACK)
    sw = math.floor(30 * p2.stamina / p2.max_stamina)
    if sw > 0 then
        rectf(s, 124 + (30 - sw), 17, sw, 1, C_MID1)
    end

    -- Round & Timer (center)
    local timer_display = math.max(0, math.floor(game.round_timer))
    text(s, "R" .. game.round, 80, 2, C_WHITE, ALIGN_CENTER)
    text(s, tostring(timer_display), 80, 10, C_BRIGHT1, ALIGN_CENTER)

    -- Combo display
    if p1.combo_count >= 2 and p1.combo_timer > 0 then
        local combo_c = (p1.combo_count >= 3) and C_WHITE or C_BRIGHT1
        text(s, p1.combo_count .. " HIT!", 30, 24, combo_c, ALIGN_CENTER)
    end
    if p2.combo_count >= 2 and p2.combo_timer > 0 then
        local combo_c = (p2.combo_count >= 3) and C_WHITE or C_BRIGHT1
        text(s, p2.combo_count .. " HIT!", 130, 24, combo_c, ALIGN_CENTER)
    end
end

----------------------------------------------
-- MATCH FLOW
----------------------------------------------
function start_fight()
    game.round = 1
    game.decision_scores = {}
    game.ko_type = nil
    particles = {}

    p1 = new_fighter(60, 1, true)
    p2 = new_fighter(100, -1, false)

    local opp = opponents[game.tournament_fight]
    if opp then
        p2.ai_aggression = opp.aggression
        p2.ai_defense = opp.defense
        p2.ai_speed = opp.speed
        p2.ai_react_time = opp.react
        p2.max_health = opp.health
        p2.health = opp.health
        p2.ai_pattern = opp.pattern
        p2.ai_name = opp.name
    end

    start_round()
end

function start_round()
    game.round_timer = ROUND_TIME
    game.mode = "round_start"
    game.flash_timer = 0
    game.crowd_energy = 20
    game.shake_amount = 0
    particles = {}

    p1.x = 55
    p2.x = 105
    p1.state = "idle"
    p2.state = "idle"
    p1.state_timer = 0
    p2.state_timer = 0
    p1.vx = 0
    p2.vx = 0
    p1.knockdown_count = 0
    p2.knockdown_count = 0

    if game.round > 1 then
        p1.health = math.min(p1.max_health, p1.health + 15)
        p2.health = math.min(p2.max_health, p2.health + 15)
        p1.stamina = p1.max_stamina
        p2.stamina = p2.max_stamina
    end

    p1.punches_thrown = 0
    p1.punches_landed = 0
    p1.damage_dealt = 0
    p2.punches_thrown = 0
    p2.punches_landed = 0
    p2.damage_dealt = 0

    play_bell()
end

function end_round(reason)
    local p1_score = 10
    local p2_score = 10

    if p1.damage_dealt > p2.damage_dealt then
        p2_score = p2_score - 1
    elseif p2.damage_dealt > p1.damage_dealt then
        p1_score = p1_score - 1
    end

    p1_score = p1_score - p2.total_knockdowns
    p2_score = p2_score - p1.total_knockdowns

    table.insert(game.decision_scores, {p1_score, p2_score})

    play_bell()

    if game.round >= MAX_ROUNDS then
        local p1_total, p2_total = 0, 0
        for _, sc in ipairs(game.decision_scores) do
            p1_total = p1_total + sc[1]
            p2_total = p2_total + sc[2]
        end

        if p1_total > p2_total then
            game.mode = "player_wins"
            game.ko_type = "DECISION (" .. p1_total .. "-" .. p2_total .. ")"
            game.tournament_wins = game.tournament_wins + 1
            if game.tournament_fight >= 4 then
                go("gameover")
            else
                game.tournament_fight = game.tournament_fight + 1
                go("gameover")
            end
        elseif p2_total > p1_total then
            game.mode = "player_loses"
            game.ko_type = "DECISION (" .. p2_total .. "-" .. p1_total .. ")"
            go("gameover")
        else
            if p1.punches_landed >= p2.punches_landed then
                game.mode = "player_wins"
                game.ko_type = "SPLIT DECISION"
                game.tournament_wins = game.tournament_wins + 1
                if game.tournament_fight >= 4 then
                    go("gameover")
                else
                    game.tournament_fight = game.tournament_fight + 1
                    go("gameover")
                end
            else
                game.mode = "player_loses"
                game.ko_type = "SPLIT DECISION"
                go("gameover")
            end
        end
    else
        go("between")
    end
end

----------------------------------------------
-- UPDATE ROUND START -> FIGHTING transition
----------------------------------------------
local base_fight_update = fight_update
fight_update = function()
    if game.mode == "round_start" then
        game.flash_timer = game.flash_timer + 1
        if game.flash_timer >= 90 then
            game.mode = "fighting"
        end
        if game.shake_timer > 0 then
            game.shake_timer = game.shake_timer - 1
        end
        return
    end
    base_fight_update()
end

----------------------------------------------
-- ENGINE HOOKS
----------------------------------------------
function _init()
    mode(4)
end

function _start()
    go("title")
end
