-- THE DARK ROOM: Inventory & Crafting
-- Agent #05 | 160x120 | 2-bit (0-3) | mode(2)
-- Wake in darkness. Find objects. Combine them. Escape.
-- D-Pad:Move/Select | Z(A):Interact/Confirm | X(B):Inventory | START:Start | SELECT:Pause

------------------------------------------------------------------------
-- CONSTANTS
------------------------------------------------------------------------
local W = 160
local H = 120
local S -- screen surface

-- 2-bit palette: 0=black, 1=dark gray, 2=light gray, 3=white
local BG    = 0
local DARK  = 1
local LIGHT = 2
local WHITE = 3

-- Inventory
local INV_COLS = 4
local INV_ROWS = 2
local INV_MAX  = INV_COLS * INV_ROWS
local SLOT_W   = 32
local SLOT_H   = 24
local INV_X    = (W - INV_COLS * SLOT_W) / 2
local INV_Y    = 20

------------------------------------------------------------------------
-- SAFE AUDIO
------------------------------------------------------------------------
local function sfx_note(ch, n, dur)
    if note then note(ch, n, dur) end
end
local function sfx_noise(ch, dur)
    if noise then noise(ch, dur) end
end

------------------------------------------------------------------------
-- UTILITY
------------------------------------------------------------------------
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function text_center(str, y, c)
    text(S, str, W/2, y, c, ALIGN_CENTER)
end

local function text_left(str, x, y, c)
    text(S, str, x, y, c)
end

local frame_count = 0

------------------------------------------------------------------------
-- ITEM DATABASE
------------------------------------------------------------------------
-- Each item: { id, name, desc, icon (char), combinable_with={} }
local ITEMS = {
    flashlight  = { id="flashlight",  name="Flashlight",   desc="Dead. Needs batteries.", icon="F" },
    batteries   = { id="batteries",   name="Batteries",    desc="Two AA batteries.",      icon="B" },
    lit_flash   = { id="lit_flash",   name="Flashlight*",  desc="Shines bright!",         icon="L" },
    key_head    = { id="key_head",    name="Key Head",     desc="Broken key top half.",    icon="K" },
    key_shaft   = { id="key_shaft",   name="Key Shaft",    desc="Broken key bottom.",     icon="S" },
    full_key    = { id="full_key",    name="Full Key",     desc="A repaired key.",         icon="Q" },
    note_a      = { id="note_a",      name="Note (left)",  desc="Torn paper... 'HEL'",    icon="1" },
    note_b      = { id="note_b",      name="Note (right)", desc="Torn paper... 'P ME'",   icon="2" },
    full_note   = { id="full_note",   name="Note",         desc="HELP ME - I'M TRAPPED",  icon="N" },
    crowbar     = { id="crowbar",     name="Crowbar",      desc="Heavy iron bar.",         icon="C" },
    rusty_lock  = { id="rusty_lock",  name="Rusty Lock",   desc="Found on the door.",     icon="R" },
    wire        = { id="wire",        name="Wire",         desc="Thin copper wire.",       icon="W" },
    lockpick    = { id="lockpick",    name="Lockpick",     desc="Bent wire pick.",         icon="P" },
}

-- Crafting recipes: {item_a, item_b} -> result_id
local RECIPES = {
    { a="flashlight", b="batteries", result="lit_flash" },
    { a="key_head",   b="key_shaft", result="full_key" },
    { a="note_a",     b="note_b",    result="full_note" },
    { a="wire",       b="crowbar",   result="lockpick" },
}

------------------------------------------------------------------------
-- GAME STATE
------------------------------------------------------------------------
local state = "title"        -- title, play, inv, combine, paused, win, attract
local room = 1               -- 1=cell, 2=hallway, 3=exit
local inventory = {}         -- list of item ids
local inv_cursor = 1         -- cursor position in inventory
local combine_first = nil    -- first item selected for combining
local player_x, player_y = 80, 80
local interact_msg = ""
local msg_timer = 0
local has_light = false       -- flashlight active
local door_unlocked = false   -- exit door
local grate_open = false      -- hallway grate
local found_items = {}        -- track which hotspots have been looted
local title_pulse = 0
local attract_timer = 0
local ATTRACT_IDLE = 150      -- frames before demo
local demo_mode = false
local demo_step = 0
local demo_timer = 0
local demo_actions = {}
local pause_sel = 1

-- Ambient sound timers
local drip_timer = 0
local creak_timer = 0

------------------------------------------------------------------------
-- HOTSPOTS (interactive objects in each room)
------------------------------------------------------------------------
-- {x, y, w, h, item_id or nil, action, description, requires, visible_without_light}
local hotspots = {}

local function build_hotspots()
    hotspots = {
        -- ROOM 1: Cell
        [1] = {
            { x=10, y=30, w=20, h=20, item="flashlight", desc="A shape on the floor...", req=nil, vis=true, room_vis=true },
            { x=130,y=20, w=20, h=15, item="batteries",  desc="Something on the shelf.", req=nil, vis=true, room_vis=true },
            { x=60, y=15, w=40, h=10, item="note_a",     desc="Paper on the wall.",      req=nil, vis=false, room_vis=false },
            { x=110,y=70, w=20, h=20, item="key_head",   desc="Glint under the bed.",    req=nil, vis=false, room_vis=false },
            { x=70, y=90, w=24, h=16, item=nil,          desc="Door to hallway.",         req=nil, vis=true, room_vis=true, action="door1" },
        },
        -- ROOM 2: Hallway
        [2] = {
            { x=20, y=40, w=20, h=20, item="key_shaft",  desc="Metal piece in rubble.",  req=nil, vis=false, room_vis=false },
            { x=120,y=25, w=20, h=20, item="note_b",     desc="Paper scrap on pipe.",    req=nil, vis=true, room_vis=true },
            { x=60, y=50, w=30, h=15, item="wire",       desc="Wire hanging from wall.", req=nil, vis=true, room_vis=true },
            { x=130,y=60, w=20, h=20, item="crowbar",    desc="Crowbar behind crate.",   req=nil, vis=false, room_vis=false },
            { x=10, y=90, w=24, h=16, item=nil,          desc="Back to cell.",            req=nil, vis=true, room_vis=true, action="door_back1" },
            { x=120,y=90, w=24, h=16, item=nil,          desc="Grate blocks the way.",   req=nil, vis=true, room_vis=true, action="grate" },
        },
        -- ROOM 3: Exit
        [3] = {
            { x=60, y=30, w=40, h=30, item=nil,          desc="Heavy locked door.",       req=nil, vis=true, room_vis=true, action="exit_door" },
            { x=10, y=90, w=24, h=16, item=nil,          desc="Back to hallway.",         req=nil, vis=true, room_vis=true, action="door_back2" },
        },
    }
end

------------------------------------------------------------------------
-- INVENTORY MANAGEMENT
------------------------------------------------------------------------
local function has_item(id)
    for i, v in ipairs(inventory) do
        if v == id then return true end
    end
    return false
end

local function add_item(id)
    if #inventory < INV_MAX and not has_item(id) then
        table.insert(inventory, id)
        sfx_note(0, "E5", 4)
        sfx_note(1, "G5", 4)
        return true
    end
    return false
end

local function remove_item(id)
    for i, v in ipairs(inventory) do
        if v == id then
            table.remove(inventory, i)
            return true
        end
    end
    return false
end

local function try_combine(id_a, id_b)
    for _, r in ipairs(RECIPES) do
        if (id_a == r.a and id_b == r.b) or (id_a == r.b and id_b == r.a) then
            remove_item(id_a)
            remove_item(id_b)
            add_item(r.result)
            -- Special side effects
            if r.result == "lit_flash" then
                has_light = true
            end
            return ITEMS[r.result].name
        end
    end
    return nil
end

------------------------------------------------------------------------
-- SHOW MESSAGE
------------------------------------------------------------------------
local function show_msg(msg, duration)
    interact_msg = msg or ""
    msg_timer = duration or 60
end

------------------------------------------------------------------------
-- ROOM DRAWING
------------------------------------------------------------------------
local function draw_room_cell()
    -- Walls
    rect(S, 0, 0, W, H, BG)
    -- Floor line
    line(S, 0, 95, W, 95, DARK)
    -- Bed frame
    rect(S, 100, 65, 50, 30, DARK)
    line(S, 100, 65, 150, 65, LIGHT)
    line(S, 100, 65, 100, 95, LIGHT)
    -- Shelf
    line(S, 125, 20, 155, 20, LIGHT)
    line(S, 125, 20, 125, 18, DARK)
    line(S, 155, 20, 155, 18, DARK)
    -- Door outline
    rect(S, 70, 78, 24, 17, DARK)
    line(S, 70, 78, 94, 78, LIGHT)
    line(S, 70, 78, 70, 95, LIGHT)
    line(S, 94, 78, 94, 95, LIGHT)
    -- Door handle
    pix(S, 90, 87, LIGHT)
    -- Wall cracks
    if has_light then
        line(S, 30, 10, 35, 25, DARK)
        line(S, 35, 25, 32, 40, DARK)
        pix(S, 65, 18, LIGHT) -- note glint
        pix(S, 112, 72, LIGHT) -- key glint
    end
end

local function draw_room_hallway()
    rect(S, 0, 0, W, H, BG)
    -- Ceiling pipes
    line(S, 0, 10, W, 10, DARK)
    line(S, 0, 12, W, 12, DARK)
    -- Floor
    line(S, 0, 95, W, 95, DARK)
    -- Crate
    rect(S, 120, 50, 25, 25, DARK)
    line(S, 120, 50, 145, 50, LIGHT)
    line(S, 132, 50, 132, 75, DARK)
    -- Rubble
    pix(S, 22, 55, DARK)
    pix(S, 28, 52, DARK)
    pix(S, 25, 58, LIGHT)
    -- Back door
    rect(S, 10, 78, 24, 17, DARK)
    line(S, 10, 78, 34, 78, LIGHT)
    pix(S, 30, 87, LIGHT)
    -- Grate/forward door
    rect(S, 120, 78, 24, 17, DARK)
    if grate_open then
        line(S, 120, 78, 144, 78, LIGHT)
    else
        -- Draw grate bars
        for gx = 122, 142, 4 do
            line(S, gx, 78, gx, 95, LIGHT)
        end
    end
    -- Hanging wire
    if not found_items["wire_2"] then
        line(S, 65, 12, 70, 55, LIGHT)
        line(S, 70, 55, 72, 58, DARK)
    end
    -- Hidden items visible with light
    if has_light then
        pix(S, 25, 45, LIGHT) -- key shaft glint
        pix(S, 135, 62, LIGHT) -- crowbar glint
    end
end

local function draw_room_exit()
    rect(S, 0, 0, W, H, BG)
    -- Big door
    rect(S, 55, 20, 50, 55, DARK)
    line(S, 55, 20, 105, 20, LIGHT)
    line(S, 55, 20, 55, 75, LIGHT)
    line(S, 105, 20, 105, 75, LIGHT)
    -- Lock
    if not door_unlocked then
        rect(S, 76, 45, 8, 8, LIGHT)
        pix(S, 80, 49, WHITE)
    else
        -- Open door crack
        rect(S, 58, 22, 6, 50, WHITE)
    end
    -- Floor
    line(S, 0, 95, W, 95, DARK)
    -- Back door
    rect(S, 10, 78, 24, 17, DARK)
    line(S, 10, 78, 34, 78, LIGHT)
    pix(S, 30, 87, LIGHT)
    -- Light from door if unlocked
    if door_unlocked then
        for i = 0, 3 do
            line(S, 61, 25 + i*12, 80 - i*5, 75, DARK)
            line(S, 61, 25 + i*12, 80 + i*5, 75, DARK)
        end
    end
end

------------------------------------------------------------------------
-- DRAW PLAYER CURSOR
------------------------------------------------------------------------
local function draw_player()
    -- Small arrow/hand cursor
    local blink = (frame_count % 20) < 14
    local c = blink and WHITE or LIGHT
    -- Hand icon
    pix(S, player_x, player_y - 2, c)
    pix(S, player_x - 1, player_y - 1, c)
    pix(S, player_x + 1, player_y - 1, c)
    pix(S, player_x, player_y, c)
    pix(S, player_x, player_y + 1, c)
    pix(S, player_x - 1, player_y + 2, c)
    pix(S, player_x + 1, player_y + 2, c)
end

------------------------------------------------------------------------
-- NEARBY HOTSPOT
------------------------------------------------------------------------
local function get_nearby_hotspot()
    local spots = hotspots[room]
    if not spots then return nil end
    for _, hs in ipairs(spots) do
        local visible = hs.vis or (has_light and not hs.vis)
        -- Check if item already picked up
        local looted = hs.item and found_items[hs.item .. "_" .. room]
        if visible and not looted then
            if player_x >= hs.x and player_x <= hs.x + hs.w and
               player_y >= hs.y and player_y <= hs.y + hs.h then
                return hs
            end
        end
    end
    return nil
end

------------------------------------------------------------------------
-- INTERACT
------------------------------------------------------------------------
local function do_interact()
    local hs = get_nearby_hotspot()
    if not hs then
        show_msg("Nothing here.", 40)
        sfx_noise(0, 2)
        return
    end

    -- Item pickup
    if hs.item and not found_items[hs.item .. "_" .. room] then
        if add_item(hs.item) then
            found_items[hs.item .. "_" .. room] = true
            show_msg("Got: " .. ITEMS[hs.item].name, 60)
        else
            show_msg("Inventory full!", 60)
            sfx_noise(1, 4)
        end
        return
    end

    -- Actions
    if hs.action == "door1" then
        room = 2
        player_x, player_y = 20, 90
        show_msg("A damp hallway...", 60)
        sfx_note(0, "C3", 8)
        sfx_noise(1, 6)
    elseif hs.action == "door_back1" then
        room = 1
        player_x, player_y = 80, 85
        show_msg("Back in the cell.", 50)
        sfx_note(0, "C3", 6)
    elseif hs.action == "door_back2" then
        room = 2
        player_x, player_y = 130, 85
        show_msg("The hallway.", 50)
        sfx_note(0, "C3", 6)
    elseif hs.action == "grate" then
        if grate_open then
            room = 3
            player_x, player_y = 20, 90
            show_msg("A heavy door ahead...", 60)
            sfx_note(0, "D3", 8)
        elseif has_item("crowbar") then
            grate_open = true
            remove_item("crowbar")
            show_msg("Pried the grate open!", 80)
            sfx_noise(0, 10)
            sfx_note(1, "G3", 6)
        elseif has_item("lockpick") then
            grate_open = true
            remove_item("lockpick")
            show_msg("Picked the grate lock!", 80)
            sfx_note(0, "A4", 4)
            sfx_note(1, "C5", 4)
        else
            show_msg("Grate is locked tight.", 60)
            sfx_noise(0, 4)
        end
    elseif hs.action == "exit_door" then
        if door_unlocked then
            state = "win"
            sfx_note(0, "C5", 8)
            sfx_note(1, "E5", 8)
            sfx_note(2, "G5", 8)
        elseif has_item("full_key") then
            door_unlocked = true
            remove_item("full_key")
            show_msg("The key fits! Door unlocked!", 90)
            sfx_note(0, "C4", 6)
            sfx_note(1, "E4", 6)
            sfx_note(2, "G4", 8)
        else
            show_msg("Locked. Need a key.", 60)
            sfx_noise(0, 4)
        end
    else
        show_msg(hs.desc or "...", 50)
    end
end

------------------------------------------------------------------------
-- DRAW INVENTORY UI
------------------------------------------------------------------------
local function draw_inventory()
    -- Full screen overlay
    cls(S, BG)

    text_center("INVENTORY", 4, WHITE)

    -- Draw slots
    for i = 1, INV_MAX do
        local col = ((i - 1) % INV_COLS)
        local row = math.floor((i - 1) / INV_COLS)
        local sx = INV_X + col * SLOT_W
        local sy = INV_Y + row * SLOT_H

        -- Slot border
        local border_c = DARK
        if i == inv_cursor then
            border_c = WHITE
        elseif combine_first and combine_first == i then
            border_c = LIGHT
        end
        rect(S, sx, sy, SLOT_W - 2, SLOT_H - 2, BG)
        line(S, sx, sy, sx + SLOT_W - 3, sy, border_c)
        line(S, sx, sy, sx, sy + SLOT_H - 3, border_c)
        line(S, sx + SLOT_W - 3, sy, sx + SLOT_W - 3, sy + SLOT_H - 3, border_c)
        line(S, sx, sy + SLOT_H - 3, sx + SLOT_W - 3, sy + SLOT_H - 3, border_c)

        -- Item icon
        if inventory[i] then
            local item = ITEMS[inventory[i]]
            if item then
                text(S, item.icon, sx + SLOT_W/2 - 1, sy + 4, LIGHT, ALIGN_CENTER)
                -- Small label
                local label = item.name
                if #label > 6 then label = string.sub(label, 1, 5) .. "." end
                text(S, label, sx + SLOT_W/2 - 1, sy + 14, DARK, ALIGN_CENTER)
            end
        end
    end

    -- Description of selected item
    local sel_id = inventory[inv_cursor]
    if sel_id and ITEMS[sel_id] then
        local item = ITEMS[sel_id]
        text_center(item.name, 74, LIGHT)
        text_center(item.desc, 84, DARK)
    end

    -- Instructions
    if combine_first then
        text_center("Select 2nd item (A=combine)", 98, LIGHT)
    else
        text_center("A=Select  B=Close", 98, DARK)
        text_center("A+A=Combine two items", 108, DARK)
    end
end

------------------------------------------------------------------------
-- DRAW HUD
------------------------------------------------------------------------
local function draw_hud()
    -- Room name
    local room_names = { "Cell", "Hallway", "Exit Chamber" }
    text_left(room_names[room] or "?", 2, 2, DARK)

    -- Item count
    text(S, #inventory .. "/" .. INV_MAX, W - 2, 2, DARK, ALIGN_RIGHT)

    -- Interaction prompt
    local hs = get_nearby_hotspot()
    if hs then
        local prompt = hs.desc or "Something here."
        text_center(prompt, H - 16, LIGHT)
        if (frame_count % 30) < 20 then
            text_center("[A] Interact", H - 8, WHITE)
        end
    end

    -- Message
    if msg_timer > 0 then
        -- Message background
        rect(S, 10, H/2 - 8, W - 20, 16, BG)
        line(S, 10, H/2 - 8, W - 10, H/2 - 8, LIGHT)
        line(S, 10, H/2 + 8, W - 10, H/2 + 8, LIGHT)
        text_center(interact_msg, H/2 - 3, WHITE)
    end

    -- Light indicator
    if has_light then
        pix(S, W - 6, 10, WHITE)
        pix(S, W - 7, 11, LIGHT)
        pix(S, W - 5, 11, LIGHT)
    end
end

------------------------------------------------------------------------
-- DRAW HOTSPOT HINTS
------------------------------------------------------------------------
local function draw_hotspot_hints()
    local spots = hotspots[room]
    if not spots then return end
    for _, hs in ipairs(spots) do
        local visible = hs.room_vis or (has_light and not hs.room_vis)
        local looted = hs.item and found_items[hs.item .. "_" .. room]
        if visible and not looted then
            -- Small sparkle/dot to hint at interactable
            local cx = hs.x + hs.w / 2
            local cy = hs.y + hs.h / 2
            if (frame_count + math.floor(cx)) % 40 < 8 then
                pix(S, cx, cy, LIGHT)
            end
        end
    end
end

------------------------------------------------------------------------
-- AMBIENT SOUNDS
------------------------------------------------------------------------
local function ambient_sounds()
    drip_timer = drip_timer + 1
    creak_timer = creak_timer + 1
    if drip_timer > 90 then
        drip_timer = 0
        sfx_note(2, "B6", 1)
    end
    if creak_timer > 200 then
        creak_timer = 0
        sfx_noise(3, 3)
    end
end

------------------------------------------------------------------------
-- DARKNESS OVERLAY (if no flashlight)
------------------------------------------------------------------------
local function draw_darkness()
    if has_light then return end
    -- Darken edges: draw black pixels around border to simulate limited vision
    for x = 0, W - 1 do
        for y = 0, 6 do
            pix(S, x, y, BG)
        end
        for y = H - 6, H - 1 do
            pix(S, x, y, BG)
        end
    end
    for y = 6, H - 7 do
        for x = 0, 5 do
            pix(S, x, y, BG)
        end
        for x = W - 5, W - 1 do
            pix(S, x, y, BG)
        end
    end
end

------------------------------------------------------------------------
-- TITLE SCREEN
------------------------------------------------------------------------
local function draw_title()
    cls(S, BG)
    title_pulse = title_pulse + 1

    -- Title text
    text_center("THE DARK ROOM", 20, WHITE)
    text_center("Inventory & Crafting", 32, DARK)

    -- Flickering effect
    if (title_pulse % 50) < 40 then
        text_center("PRESS START", 70, LIGHT)
    end

    -- Controls hint
    text_center("A=Interact  B=Inventory", 95, DARK)
    text_center("Find. Combine. Escape.", 105, DARK)

    -- Decorative dots
    for i = 0, 7 do
        local dx = 40 + i * 10
        local bright = ((title_pulse + i * 5) % 30) < 10 and LIGHT or DARK
        pix(S, dx, 55, bright)
    end
end

------------------------------------------------------------------------
-- WIN SCREEN
------------------------------------------------------------------------
local function draw_win()
    cls(S, BG)
    text_center("ESCAPED!", 25, WHITE)

    -- Light rays from center
    for i = 0, 5 do
        local ang = (frame_count * 0.02) + i * 1.047
        local ex = 80 + math.cos(ang) * 30
        local ey = 55 + math.sin(ang) * 20
        line(S, 80, 55, math.floor(ex), math.floor(ey), DARK)
    end

    text_center("You found the way out.", 75, LIGHT)

    if has_item("full_note") then
        text_center("The note read:", 88, DARK)
        text_center("HELP ME - I'M TRAPPED", 96, WHITE)
    end

    if (frame_count % 60) < 40 then
        text_center("START to play again", 112, DARK)
    end
end

------------------------------------------------------------------------
-- PAUSE MENU
------------------------------------------------------------------------
local function draw_pause()
    -- Overlay
    rect(S, 30, 30, 100, 60, BG)
    line(S, 30, 30, 130, 30, LIGHT)
    line(S, 30, 90, 130, 90, LIGHT)
    line(S, 30, 30, 30, 90, LIGHT)
    line(S, 130, 30, 130, 90, LIGHT)

    text_center("PAUSED", 38, WHITE)

    local items_text = { "Resume", "Restart" }
    for i, label in ipairs(items_text) do
        local c = (pause_sel == i) and WHITE or DARK
        local prefix = (pause_sel == i) and "> " or "  "
        text_center(prefix .. label, 50 + i * 12, c)
    end
end

------------------------------------------------------------------------
-- DEMO MODE (attract)
------------------------------------------------------------------------
local function init_demo()
    demo_mode = true
    demo_step = 0
    demo_timer = 0
    -- Reset game state for demo
    room = 1
    inventory = {}
    found_items = {}
    has_light = false
    door_unlocked = false
    grate_open = false
    player_x, player_y = 80, 80
    build_hotspots()

    -- Script: sequence of {target_x, target_y, action, duration}
    demo_actions = {
        { tx=10+10, ty=30+10, act="pickup", dur=40, msg="Find objects..." },
        { tx=130+10, ty=20+8, act="pickup", dur=40, msg="Search everywhere..." },
        { tx=80, ty=60, act="open_inv", dur=60, msg="Open inventory [B]" },
        { tx=80, ty=60, act="combine", dur=60, msg="Combine items!" },
        { tx=80, ty=85, act="move", dur=40, msg="Use items to progress." },
    }
end

local function update_demo()
    demo_timer = demo_timer + 1
    local action = demo_actions[demo_step + 1]
    if not action then
        -- Restart demo
        demo_step = 0
        demo_timer = 0
        init_demo()
        return
    end

    -- Move toward target
    if action.tx then
        local dx = action.tx - player_x
        local dy = action.ty - player_y
        local spd = 1.5
        if math.abs(dx) > spd then
            player_x = player_x + (dx > 0 and spd or -spd)
        end
        if math.abs(dy) > spd then
            player_y = player_y + (dy > 0 and spd or -spd)
        end
    end

    show_msg(action.msg or "", 10)

    if demo_timer >= action.dur then
        -- Execute action
        if action.act == "pickup" then
            do_interact()
        elseif action.act == "open_inv" then
            -- Simulate showing inventory briefly
        elseif action.act == "combine" then
            -- Auto combine if possible
            if has_item("flashlight") and has_item("batteries") then
                try_combine("flashlight", "batteries")
                show_msg("Flashlight + Batteries = Light!", 40)
            end
        end
        demo_step = demo_step + 1
        demo_timer = 0
    end
end

------------------------------------------------------------------------
-- GAME RESET
------------------------------------------------------------------------
local function reset_game()
    room = 1
    inventory = {}
    found_items = {}
    has_light = false
    door_unlocked = false
    grate_open = false
    player_x, player_y = 80, 80
    interact_msg = ""
    msg_timer = 0
    inv_cursor = 1
    combine_first = nil
    pause_sel = 1
    demo_mode = false
    drip_timer = 0
    creak_timer = 0
    build_hotspots()
    show_msg("Darkness... Where am I?", 90)
end

------------------------------------------------------------------------
-- TOUCH HELPERS
------------------------------------------------------------------------
local function touch_start()
    if touch and touch then
        local t = touch()
        if t and t.state == "began" then return true end
    end
    return false
end

------------------------------------------------------------------------
-- ENGINE CALLBACKS
------------------------------------------------------------------------
function _init()
    mode(2)
    build_hotspots()
end

function _start()
    state = "title"
    title_pulse = 0
    attract_timer = 0
end

function _update()
    frame_count = frame_count + 1

    if state == "title" then
        attract_timer = attract_timer + 1
        if btnp("start") or touch_start() then
            state = "play"
            attract_timer = 0
            demo_mode = false
            reset_game()
            return
        end
        -- Enter attract/demo after idle
        if attract_timer >= ATTRACT_IDLE then
            state = "attract"
            init_demo()
            return
        end

    elseif state == "attract" then
        -- Exit demo on any input
        if btnp("start") or btnp("a") or btnp("b") or btnp("up") or btnp("down") or btnp("left") or btnp("right") or btnp("select") or touch_start() then
            state = "title"
            attract_timer = 0
            demo_mode = false
            return
        end
        update_demo()

    elseif state == "play" then
        -- Pause
        if btnp("select") or btnp("start") then
            state = "paused"
            pause_sel = 1
            return
        end
        -- Open inventory
        if btnp("b") then
            state = "inv"
            inv_cursor = 1
            combine_first = nil
            sfx_note(0, "C4", 2)
            return
        end
        -- Interact
        if btnp("a") then
            do_interact()
        end
        -- Movement
        local spd = 2
        if btn("left")  then player_x = clamp(player_x - spd, 4, W - 4) end
        if btn("right") then player_x = clamp(player_x + spd, 4, W - 4) end
        if btn("up")    then player_y = clamp(player_y - spd, 4, H - 4) end
        if btn("down")  then player_y = clamp(player_y + spd, 4, H - 4) end

        -- Message timer
        if msg_timer > 0 then msg_timer = msg_timer - 1 end

        -- Ambient
        ambient_sounds()

    elseif state == "inv" then
        -- Close inventory
        if btnp("b") or btnp("select") then
            state = "play"
            combine_first = nil
            sfx_note(0, "C4", 2)
            return
        end
        -- Navigate
        if btnp("left") then
            inv_cursor = inv_cursor - 1
            if inv_cursor < 1 then inv_cursor = INV_MAX end
            sfx_note(0, "E4", 1)
        end
        if btnp("right") then
            inv_cursor = inv_cursor + 1
            if inv_cursor > INV_MAX then inv_cursor = 1 end
            sfx_note(0, "E4", 1)
        end
        if btnp("up") then
            inv_cursor = inv_cursor - INV_COLS
            if inv_cursor < 1 then inv_cursor = inv_cursor + INV_MAX end
            sfx_note(0, "E4", 1)
        end
        if btnp("down") then
            inv_cursor = inv_cursor + INV_COLS
            if inv_cursor > INV_MAX then inv_cursor = inv_cursor - INV_MAX end
            sfx_note(0, "E4", 1)
        end
        -- Select for combining
        if btnp("a") then
            if inventory[inv_cursor] then
                if combine_first == nil then
                    combine_first = inv_cursor
                    sfx_note(0, "G4", 2)
                    show_msg("Select 2nd item...", 40)
                elseif combine_first == inv_cursor then
                    -- Deselect
                    combine_first = nil
                    sfx_noise(0, 2)
                else
                    -- Try combine
                    local id_a = inventory[combine_first]
                    local id_b = inventory[inv_cursor]
                    if id_a and id_b then
                        local result = try_combine(id_a, id_b)
                        if result then
                            show_msg("Made: " .. result .. "!", 80)
                            sfx_note(0, "C5", 4)
                            sfx_note(1, "E5", 4)
                            sfx_note(2, "G5", 6)
                        else
                            show_msg("Can't combine those.", 50)
                            sfx_noise(0, 4)
                        end
                    end
                    combine_first = nil
                    inv_cursor = 1
                end
            end
        end

        if msg_timer > 0 then msg_timer = msg_timer - 1 end

    elseif state == "paused" then
        if btnp("select") or btnp("start") then
            state = "play"
            return
        end
        if btnp("up") then pause_sel = clamp(pause_sel - 1, 1, 2) end
        if btnp("down") then pause_sel = clamp(pause_sel + 1, 1, 2) end
        if btnp("a") then
            if pause_sel == 1 then
                state = "play"
            elseif pause_sel == 2 then
                state = "title"
                attract_timer = 0
            end
        end

    elseif state == "win" then
        if btnp("start") or touch_start() then
            state = "title"
            attract_timer = 0
        end
    end
end

function _draw()
    S = screen()

    if state == "title" then
        draw_title()

    elseif state == "attract" then
        cls(S, BG)
        if room == 1 then draw_room_cell()
        elseif room == 2 then draw_room_hallway()
        elseif room == 3 then draw_room_exit()
        end
        draw_hotspot_hints()
        draw_player()
        draw_hud()
        draw_darkness()
        -- Demo overlay
        rect(S, 20, 0, 120, 10, BG)
        text_center("DEMO", 2, DARK)

    elseif state == "play" then
        cls(S, BG)
        if room == 1 then draw_room_cell()
        elseif room == 2 then draw_room_hallway()
        elseif room == 3 then draw_room_exit()
        end
        draw_hotspot_hints()
        draw_player()
        draw_hud()
        draw_darkness()

    elseif state == "inv" then
        draw_inventory()
        -- Show message on inventory screen too
        if msg_timer > 0 then
            rect(S, 10, H - 16, W - 20, 12, BG)
            text_center(interact_msg, H - 14, WHITE)
        end

    elseif state == "paused" then
        cls(S, BG)
        if room == 1 then draw_room_cell()
        elseif room == 2 then draw_room_hallway()
        elseif room == 3 then draw_room_exit()
        end
        draw_pause()

    elseif state == "win" then
        draw_win()
    end
end
