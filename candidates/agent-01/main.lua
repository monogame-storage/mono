-- THE DARK ROOM
-- Agent 01 — Text-heavy narrative mystery adventure
-- Wake up. No memory. Find clues. Escape. Uncover the truth.
------------------------------------------------------

-- Constants
local SW, SH = 160, 120
local C_BLK, C_DGR, C_LGR, C_WHT = 0, 1, 2, 3
local LINE_H = 8      -- text line height
local MAX_LINES = 12  -- max visible text lines
local TEXT_X = 4
local TEXT_Y = 4
local INV_Y = 104     -- inventory bar y position

------------------------------------------------------
-- 7-segment clock for demo/attract mode
------------------------------------------------------
local seg_digits = {
    [0] = {true,true,true,true,true,true,false},
    [1] = {false,true,true,false,false,false,false},
    [2] = {true,true,false,true,true,false,true},
    [3] = {true,true,true,true,false,false,true},
    [4] = {false,true,true,false,false,true,true},
    [5] = {true,false,true,true,false,true,true},
    [6] = {true,false,true,true,true,true,true},
    [7] = {true,true,true,false,false,false,false},
    [8] = {true,true,true,true,true,true,true},
    [9] = {true,true,true,true,false,true,true},
}

local function draw_7seg(s, x, y, digit, col)
    local segs = seg_digits[digit]
    if not segs then return end
    local w, h, t = 8, 12, 2
    -- a (top horizontal)
    if segs[1] then rectf(s, x+t, y, w-t*2, t, col) end
    -- b (top-right vertical)
    if segs[2] then rectf(s, x+w-t, y+t, t, h/2-t, col) end
    -- c (bot-right vertical)
    if segs[3] then rectf(s, x+w-t, y+h/2, t, h/2-t, col) end
    -- d (bottom horizontal)
    if segs[4] then rectf(s, x+t, y+h-t, w-t*2, t, col) end
    -- e (bot-left vertical)
    if segs[5] then rectf(s, x, y+h/2, t, h/2-t, col) end
    -- f (top-left vertical)
    if segs[6] then rectf(s, x, y+t, t, h/2-t, col) end
    -- g (middle horizontal)
    if segs[7] then rectf(s, x+t, y+h/2-1, w-t*2, t, col) end
end

local function draw_clock(s, x, y, col)
    local d = date()
    local hh = d.hour or 0
    local mm = d.min or 0
    draw_7seg(s, x, y, math.floor(hh/10), col)
    draw_7seg(s, x+12, y, hh%10, col)
    -- colon blinks
    if math.floor(frame()/30) % 2 == 0 then
        rectf(s, x+23, y+3, 2, 2, col)
        rectf(s, x+23, y+8, 2, 2, col)
    end
    draw_7seg(s, x+28, y, math.floor(mm/10), col)
    draw_7seg(s, x+40, y, mm%10, col)
end

------------------------------------------------------
-- Text utilities
------------------------------------------------------
local function word_wrap(str, max_chars)
    local lines = {}
    for paragraph in str:gmatch("[^\n]+") do
        local line = ""
        for word in paragraph:gmatch("%S+") do
            if #line + #word + 1 > max_chars then
                lines[#lines+1] = line
                line = word
            else
                if #line > 0 then line = line .. " " end
                line = line .. word
            end
        end
        if #line > 0 then lines[#lines+1] = line end
    end
    if #lines == 0 then lines[1] = "" end
    return lines
end

------------------------------------------------------
-- Game data
------------------------------------------------------

-- Room definitions
local rooms = {}
local items = {}
local inventory = {}
local current_room = ""
local text_lines = {}
local text_scroll = 0
local menu_items = {}
local menu_sel = 1
local typewriter_pos = 0
local typewriter_timer = 0
local game_won = false
local paused = false
local pause_sel = 1
local msg_queue = {}
local inv_sel = 1
local show_inv = false
local use_mode = false
local use_item = ""

local function has_item(name)
    for i, v in ipairs(inventory) do
        if v == name then return true, i end
    end
    return false
end

local function add_item(name)
    if not has_item(name) then
        inventory[#inventory+1] = name
        return true
    end
    return false
end

local function remove_item(name)
    local found, idx = has_item(name)
    if found then table.remove(inventory, idx) end
end

local function set_text(str)
    text_lines = word_wrap(str, 28)
    text_scroll = 0
    typewriter_pos = 0
    typewriter_timer = 0
end

local function append_text(str)
    local new_lines = word_wrap(str, 28)
    for _, l in ipairs(new_lines) do
        text_lines[#text_lines+1] = l
    end
end

local function build_menu()
    menu_items = {}
    menu_sel = 1
    local room = rooms[current_room]
    if not room then return end

    -- Room-specific actions
    if room.actions then
        for _, act in ipairs(room.actions) do
            if not act.cond or act.cond() then
                menu_items[#menu_items+1] = act
            end
        end
    end

    -- Exits
    if room.exits then
        for _, ex in ipairs(room.exits) do
            if not ex.cond or ex.cond() then
                menu_items[#menu_items+1] = {
                    label = "Go: " .. ex.label,
                    action = function()
                        enter_room(ex.target)
                    end
                }
            end
        end
    end

    -- Inventory option
    if #inventory > 0 then
        menu_items[#menu_items+1] = {
            label = "Inventory",
            action = function()
                show_inv = true
                inv_sel = 1
            end
        }
    end
end

function enter_room(name)
    current_room = name
    local room = rooms[name]
    if not room then
        set_text("You stand in an empty void.")
        return
    end
    if room.on_enter then
        room.on_enter()
    else
        set_text(room.desc)
    end
    build_menu()
    -- ambient sound
    noise(0, 0.05, 20, 1)
end

------------------------------------------------------
-- Define rooms
------------------------------------------------------
local function define_rooms()
    -- Flags
    local flags = {
        match_lit = false,
        cell_searched = false,
        corridor_power = false,
        storage_open = false,
        lab_accessed = false,
        code_found = false,
        evidence_found = false,
        journal1 = false,
        journal2 = false,
        journal3 = false,
    }

    -- Make flags accessible
    _G.flags = flags

    rooms["cell"] = {
        desc = "Pitch black. Cold concrete beneath your hands. Your head throbs. You remember nothing. The air smells of rust and damp. You feel the edges of a narrow cot, and something small on the floor.",
        actions = {
            {
                label = "Feel around floor",
                cond = function() return not flags.match_lit end,
                action = function()
                    set_text("Your fingers close around a small box. Matches. Three left. You strike one. A sickly yellow glow reveals a concrete cell, 3 meters square. A steel door. A cot. Scratches on the wall — tally marks. Hundreds of them.")
                    flags.match_lit = true
                    add_item("Matches")
                    note(3, 0.2, 40, 2)
                    build_menu()
                end
            },
            {
                label = "Search cot",
                cond = function() return flags.match_lit and not flags.cell_searched end,
                action = function()
                    set_text("Under the thin mattress you find a crumpled journal page. The handwriting is yours. It reads: 'Day 1. They moved me to sublevel 4 after I found the files. Dr. Wren says it is for my safety. I do not believe him.'")
                    flags.cell_searched = true
                    flags.journal1 = true
                    add_item("Journal Pg.1")
                    note(5, 0.15, 30, 2)
                    build_menu()
                end
            },
            {
                label = "Examine wall",
                cond = function() return flags.match_lit end,
                action = function()
                    set_text("The tally marks cover an entire wall. At the bottom, scratched deep: 'THEY ERASE YOU. DO NOT FORGET.' Below that, barely legible: 'Keycard taped behind pipe, corridor.'")
                    build_menu()
                end
            },
            {
                label = "Examine door",
                cond = function() return flags.match_lit end,
                action = function()
                    set_text("A heavy steel door. No handle on this side, but the latch mechanism is corroded. With enough force it might give. You throw your shoulder against it. It groans... and swings open into darkness.")
                    rooms["cell"].exits = {
                        {label = "Corridor", target = "corridor"}
                    }
                    note(1, 0.3, 15, 3)
                    build_menu()
                end
            },
        },
        exits = nil  -- locked until door is forced
    }

    rooms["corridor"] = {
        desc = "A long corridor stretches in both directions. Emergency lighting casts dim red pools every few meters. The walls are institutional green tile, cracked and water-stained. Pipes run along the ceiling. Doors line the left wall. A sign reads: 'SUBLEVEL 4 — RESTRICTED'.",
        on_enter = function()
            if flags.match_lit then
                set_text("A long corridor stretches in both directions. Emergency lighting casts dim red pools every few meters. The walls are institutional green tile, cracked and water-stained. Pipes run along the ceiling. Doors line the left wall. A sign reads: 'SUBLEVEL 4 — RESTRICTED'.")
            else
                set_text("You stumble into a corridor. Faint red light. You can barely see. Shapes loom in the shadows.")
            end
        end,
        actions = {
            {
                label = "Search pipes",
                cond = function() return not has_item("Keycard") end,
                action = function()
                    set_text("You run your hand along the overhead pipes. Behind a junction box, taped with electrical tape — a keycard. The label reads 'WREN, H. — LEVEL 4 ACCESS'.")
                    add_item("Keycard")
                    note(5, 0.2, 40, 2)
                    build_menu()
                end
            },
            {
                label = "Read notice board",
                action = function()
                    set_text("A faded notice board. Most papers are illegible from water damage. One memo survives: 'REMINDER: All Project LETHE test subjects must be sedated before memory wipe. Unsedated wipes cause permanent damage. — Dr. H. Wren'")
                    build_menu()
                end
            },
        },
        exits = {
            {label = "Cell", target = "cell"},
            {label = "Lab", target = "lab",
             cond = function() return has_item("Keycard") end},
            {label = "Storage", target = "storage"},
            {label = "Office", target = "office",
             cond = function() return has_item("Keycard") end},
        }
    }

    rooms["storage"] = {
        desc = "A supply closet. Shelves of rusted medical equipment, stacked boxes, a chemical smell. The door hangs on one hinge. Something glints on a high shelf.",
        actions = {
            {
                label = "Search shelves",
                cond = function() return not has_item("Crowbar") end,
                action = function()
                    set_text("Behind a box of expired syringes, you find a short crowbar. Heavy. Useful. You also notice a second journal page tucked into a supply ledger.")
                    add_item("Crowbar")
                    if not flags.journal2 then
                        flags.journal2 = true
                        add_item("Journal Pg.2")
                        append_text("\nThe page reads: 'Day 15. The other subjects do not remember their names. I have been hiding my journal pages. If I forget, perhaps I will find them again.'")
                    end
                    note(2, 0.2, 25, 2)
                    build_menu()
                end
            },
            {
                label = "Search boxes",
                cond = function() return not has_item("Fuse") end,
                action = function()
                    set_text("Most boxes contain decayed supplies. In one, wrapped in cloth — an electrical fuse. 30-amp. Could be useful if something needs power.")
                    add_item("Fuse")
                    note(4, 0.15, 35, 2)
                    build_menu()
                end
            },
            {
                label = "Examine chemical shelf",
                action = function()
                    set_text("Rows of unlabeled vials. One rack is labeled 'LETHE COMPOUND — BATCH 7'. The liquid inside is pale and opalescent. This is what they used to erase memories.")
                    build_menu()
                end
            },
        },
        exits = {
            {label = "Corridor", target = "corridor"},
        }
    }

    rooms["lab"] = {
        desc = "A research laboratory. Banks of monitors, most dark. An examination chair with leather restraints. The air hums with residual electricity. A terminal in the corner has a blinking cursor. The fuse box on the wall is open — one fuse is missing.",
        actions = {
            {
                label = "Insert fuse",
                cond = function() return has_item("Fuse") and not flags.corridor_power end,
                action = function()
                    set_text("You slot the fuse into the box. A deep hum fills the room. Monitors flicker to life. The terminal screen glows green. Fluorescent lights stutter on, revealing dark stains on the examination chair.")
                    remove_item("Fuse")
                    flags.corridor_power = true
                    note(1, 0.5, 10, 3)
                    noise(0, 0.3, 5, 3)
                    build_menu()
                end
            },
            {
                label = "Use terminal",
                cond = function() return flags.corridor_power end,
                action = function()
                    set_text("The terminal displays: 'PROJECT LETHE — Subject Database'. You search for your name but cannot remember it. You search for 'Wren'. Hundreds of results. One file is flagged: 'EXIT OVERRIDE CODE: 7439'. You memorize it.")
                    flags.code_found = true
                    note(6, 0.1, 50, 1)
                    build_menu()
                end
            },
            {
                label = "Examine chair",
                action = function()
                    set_text("The restraints are worn smooth from use. Electrodes are attached to a headpiece. A placard reads: 'LETHE ADMINISTRATION STATION 3'. You feel a cold recognition. You have sat in this chair. Many times.")
                    cam_shake(0.3)
                    note(1, 0.4, 8, 3)
                    build_menu()
                end
            },
            {
                label = "Search desk",
                cond = function() return not flags.journal3 end,
                action = function()
                    set_text("In a locked drawer you pry open with the crowbar — if you have it — a final journal page.")
                    if has_item("Crowbar") then
                        flags.journal3 = true
                        add_item("Journal Pg.3")
                        set_text("The drawer yields to the crowbar. Inside, your final journal page: 'Day 31. I know now. I am not a researcher. I am Subject 17. They gave me false memories of being staff. The real Dr. Wren died months ago. I must escape with the evidence.'")
                        note(5, 0.25, 40, 2)
                    else
                        set_text("The drawer is locked tight. You would need a tool to pry it open.")
                    end
                    build_menu()
                end
            },
        },
        exits = {
            {label = "Corridor", target = "corridor"},
        }
    }

    rooms["office"] = {
        desc = "Dr. Wren's office. A mahogany desk, overturned chair. Papers scattered everywhere. A framed diploma on the wall — the glass is cracked. A filing cabinet stands in the corner, one drawer slightly ajar.",
        actions = {
            {
                label = "Search filing cabinet",
                cond = function() return not flags.evidence_found end,
                action = function()
                    set_text("The drawer contains folders labeled with numbers, not names. Subject 1 through Subject 23. You find Subject 17 — your file. Inside: photographs of you, strapped to the chair. Medical notes documenting 31 memory wipes. This is the evidence.")
                    flags.evidence_found = true
                    add_item("Evidence")
                    note(3, 0.3, 30, 3)
                    cam_shake(0.5)
                    build_menu()
                end
            },
            {
                label = "Read papers on desk",
                action = function()
                    set_text("Memos between Wren and someone called 'DIRECTOR'. 'The board is asking questions. We need Subject 17 wiped again before the audit. Use maximum dosage.' The date is three days ago.")
                    build_menu()
                end
            },
            {
                label = "Examine diploma",
                action = function()
                    set_text("'Harold Wren, MD, PhD — Neurology.' The photograph shows a gaunt man with hollow eyes. Below the frame, scratched into the wall: 'LIAR'.")
                    build_menu()
                end
            },
        },
        exits = {
            {label = "Corridor", target = "corridor"},
            {label = "Exit Hall", target = "exit_hall",
             cond = function() return has_item("Crowbar") end},
        }
    }

    rooms["exit_hall"] = {
        desc = "A short hallway ending in a heavy blast door. A keypad glows beside it. Above the door: 'EMERGENCY EXIT — AUTHORIZED PERSONNEL ONLY'. Freedom is on the other side. If you know the code.",
        actions = {
            {
                label = "Enter code (7439)",
                cond = function() return flags.code_found and not game_won end,
                action = function()
                    if flags.evidence_found then
                        set_text("You punch in 7-4-3-9. The blast door groans open. Cold night air rushes in. Stars. You clutch the evidence file to your chest. They will not silence you. Not this time. You step into the darkness — free.\n\n--- THE END ---\nYou escaped with the evidence.")
                        game_won = true
                        note(7, 0.5, 50, 3)
                        wave(0, 0.8, 20, 3)
                    else
                        set_text("You punch in 7-4-3-9. The blast door groans open. Cold night air. Stars. You step out — but without evidence, who will believe you? You are just another amnesiac on the street.\n\n--- THE END ---\nYou escaped, but without proof.")
                        game_won = true
                        note(7, 0.3, 40, 2)
                    end
                    build_menu()
                end
            },
            {
                label = "Try random code",
                cond = function() return not flags.code_found end,
                action = function()
                    set_text("You press buttons at random. The keypad buzzes angrily. 'ACCESS DENIED' flashes in red. An alarm begins to sound somewhere deep in the facility. You should find the correct code first.")
                    noise(0, 0.4, 3, 3)
                    cam_shake(0.2)
                    build_menu()
                end
            },
            {
                label = "Examine door",
                action = function()
                    set_text("Reinforced steel. No amount of force will open this. The keypad requires a 4-digit code. There must be a record of it somewhere in this facility.")
                    build_menu()
                end
            },
        },
        exits = {
            {label = "Office", target = "office"},
        }
    }
end

------------------------------------------------------
-- Item descriptions (for inventory examine)
------------------------------------------------------
local item_descs = {
    ["Matches"] = "A box of matches. Two remain. Enough to light your way.",
    ["Keycard"] = "Dr. H. Wren — Level 4 Access. The photo shows a man you do not recognize. Or do you?",
    ["Journal Pg.1"] = "'Day 1. They moved me to sublevel 4 after I found the files. Dr. Wren says it is for my safety. I do not believe him.'",
    ["Journal Pg.2"] = "'Day 15. The other subjects do not remember their names. I have been hiding my journal pages.'",
    ["Journal Pg.3"] = "'Day 31. I am not a researcher. I am Subject 17. The real Dr. Wren died months ago.'",
    ["Crowbar"] = "A short, heavy crowbar. Cold iron. Could pry open stuck doors or locked drawers.",
    ["Fuse"] = "A 30-amp electrical fuse. Standard industrial type. Could restore power to equipment.",
    ["Evidence"] = "Your file. Subject 17. Photographs, medical records, 31 documented memory wipes. Proof of everything.",
}

------------------------------------------------------
-- TITLE STATE
------------------------------------------------------
local title_timer = 0
local title_blink = 0
local attract_active = false
local attract_timer = 0
local ATTRACT_THRESHOLD = 300  -- 10 seconds at 30fps

function title_init()
    title_timer = 0
    title_blink = 0
    attract_active = false
    attract_timer = 0
end

function title_update()
    title_timer = title_timer + 1
    title_blink = title_blink + 1

    if attract_active then
        attract_timer = attract_timer + 1
        if btnp("start") or btnp("a") or touch_start() then
            attract_active = false
            attract_timer = 0
            go("game")
            return
        end
        return
    end

    if btnp("start") or btnp("a") or touch_start() then
        note(5, 0.2, 40, 2)
        go("game")
        return
    end

    -- Enter attract/demo mode after idle
    if title_timer > ATTRACT_THRESHOLD then
        attract_active = true
        attract_timer = 0
    end
end

function title_draw()
    local s = screen()
    cls(s, C_BLK)

    -- Title
    text(s, "THE DARK ROOM", SW/2, 20, C_WHT, ALIGN_CENTER)

    -- Subtitle with fade effect
    local sub_col = C_LGR
    if title_timer > 30 then
        text(s, "A Mystery", SW/2, 32, sub_col, ALIGN_CENTER)
    end
    if title_timer > 60 then
        text(s, "You wake in darkness.", SW/2, 48, C_DGR, ALIGN_CENTER)
        text(s, "No memory. No name.", SW/2, 58, C_DGR, ALIGN_CENTER)
        text(s, "Only questions.", SW/2, 68, C_DGR, ALIGN_CENTER)
    end

    if attract_active then
        -- Demo mode: show clock and scrolling story text
        draw_clock(s, 50, 50, C_DGR)

        local demo_texts = {
            "Subject 17...",
            "31 memory wipes...",
            "Project LETHE...",
            "Find the truth...",
        }
        local idx = math.floor(attract_timer / 90) % #demo_texts + 1
        text(s, demo_texts[idx], SW/2, 85, C_LGR, ALIGN_CENTER)
    else
        -- Blink prompt
        if math.floor(title_blink / 20) % 2 == 0 then
            text(s, "PRESS START", SW/2, 100, C_WHT, ALIGN_CENTER)
        end
    end
end

------------------------------------------------------
-- GAME STATE
------------------------------------------------------
function game_init()
    inventory = {}
    game_won = false
    paused = false
    show_inv = false
    use_mode = false
    use_item = ""
    define_rooms()
    enter_room("cell")
end

function game_update()
    -- Pause
    if btnp("select") then
        if paused then
            paused = false
        else
            paused = true
            pause_sel = 1
        end
        return
    end

    if paused then
        if btnp("up") then pause_sel = pause_sel - 1 end
        if btnp("down") then pause_sel = pause_sel + 1 end
        if pause_sel < 1 then pause_sel = 2 end
        if pause_sel > 2 then pause_sel = 1 end
        if btnp("a") or btnp("start") then
            if pause_sel == 1 then
                paused = false
            elseif pause_sel == 2 then
                go("title")
                return
            end
        end
        return
    end

    -- Inventory view
    if show_inv then
        if btnp("up") then inv_sel = inv_sel - 1 end
        if btnp("down") then inv_sel = inv_sel + 1 end
        if inv_sel < 1 then inv_sel = #inventory end
        if inv_sel > #inventory then inv_sel = 1 end
        if btnp("b") then
            show_inv = false
            use_mode = false
            build_menu()
        end
        if btnp("a") then
            -- Examine item
            local item_name = inventory[inv_sel]
            if item_name and item_descs[item_name] then
                set_text(item_descs[item_name])
            end
            show_inv = false
            build_menu()
        end
        return
    end

    -- Typewriter effect
    local total_chars = 0
    for _, l in ipairs(text_lines) do total_chars = total_chars + #l end
    if typewriter_pos < total_chars then
        typewriter_timer = typewriter_timer + 1
        if typewriter_timer >= 1 then
            typewriter_timer = 0
            typewriter_pos = typewriter_pos + 2
        end
        -- Skip ahead on button press
        if btnp("a") or btnp("b") then
            typewriter_pos = total_chars
        end
        return
    end

    -- Menu navigation
    if #menu_items > 0 then
        if btnp("up") then
            menu_sel = menu_sel - 1
            note(7, 0.05, 50, 1)
        end
        if btnp("down") then
            menu_sel = menu_sel + 1
            note(7, 0.05, 50, 1)
        end
        if menu_sel < 1 then menu_sel = #menu_items end
        if menu_sel > #menu_items then menu_sel = 1 end
        if btnp("a") or touch_start() then
            local act = menu_items[menu_sel]
            if act and act.action then
                note(4, 0.1, 40, 1)
                act.action()
            end
        end
    end

    -- Scroll text if needed
    local visible = 7
    local max_scroll = math.max(0, #text_lines - visible)
    if btnp("left") and text_scroll > 0 then
        text_scroll = text_scroll - 1
    end
    if btnp("right") and text_scroll < max_scroll then
        text_scroll = text_scroll + 1
    end
end

function game_draw()
    local s = screen()
    cls(s, C_BLK)

    if paused then
        -- Pause overlay
        rectf(s, 30, 30, 100, 60, C_BLK)
        rect(s, 30, 30, 100, 60, C_WHT)
        text(s, "PAUSED", SW/2, 38, C_WHT, ALIGN_CENTER)
        local opts = {"Resume", "Quit to Title"}
        for i, opt in ipairs(opts) do
            local col = (i == pause_sel) and C_WHT or C_DGR
            local prefix = (i == pause_sel) and "> " or "  "
            text(s, prefix .. opt, 42, 50 + (i-1)*12, col)
        end
        return
    end

    if show_inv then
        -- Inventory screen
        rect(s, 2, 2, SW-4, SH-4, C_LGR)
        text(s, "INVENTORY", SW/2, 5, C_WHT, ALIGN_CENTER)
        line(s, 4, 13, SW-4, 13, C_DGR)
        for i, item_name in ipairs(inventory) do
            local col = (i == inv_sel) and C_WHT or C_LGR
            local prefix = (i == inv_sel) and "> " or "  "
            text(s, prefix .. item_name, 8, 16 + (i-1)*10, col)
        end
        text(s, "A:Examine  B:Back", SW/2, SH-10, C_DGR, ALIGN_CENTER)
        return
    end

    -- Room name
    local room = rooms[current_room]
    local room_names = {
        cell = "THE CELL",
        corridor = "CORRIDOR",
        lab = "LABORATORY",
        office = "DR. WREN'S OFFICE",
        storage = "STORAGE ROOM",
        exit_hall = "EXIT HALL",
    }
    local rname = room_names[current_room] or current_room
    rectf(s, 0, 0, SW, 10, C_DGR)
    text(s, rname, SW/2, 2, C_WHT, ALIGN_CENTER)

    -- Text area with typewriter effect
    local visible = 7
    local char_count = 0
    local lines_shown = 0
    for i = 1 + text_scroll, math.min(#text_lines, text_scroll + visible) do
        local l = text_lines[i]
        local display_line = ""
        for c = 1, #l do
            char_count = char_count + 1
            if char_count <= typewriter_pos then
                display_line = display_line .. l:sub(c, c)
            end
        end
        local y = 14 + lines_shown * LINE_H
        text(s, display_line, TEXT_X, y, C_LGR)
        lines_shown = lines_shown + 1
    end

    -- Scroll indicator
    local max_scroll = math.max(0, #text_lines - visible)
    if max_scroll > 0 then
        if text_scroll > 0 then
            text(s, "<", 0, 14, C_DGR)
        end
        if text_scroll < max_scroll then
            text(s, ">", SW - 6, 14, C_DGR)
        end
    end

    -- Menu area (bottom)
    local menu_y = 72
    rectf(s, 0, menu_y - 2, SW, SH - menu_y + 2, C_BLK)
    line(s, 0, menu_y - 2, SW, menu_y - 2, C_DGR)

    -- Only show menu when typewriter is done
    local total_chars = 0
    for _, l in ipairs(text_lines) do total_chars = total_chars + #l end
    if typewriter_pos >= total_chars then
        for i, item in ipairs(menu_items) do
            local col = (i == menu_sel) and C_WHT or C_DGR
            local prefix = (i == menu_sel) and "> " or "  "
            local y = menu_y + (i-1) * 9
            if y < SH - 6 then
                text(s, prefix .. item.label, TEXT_X, y, col)
            end
        end
    end

    -- Inventory bar at bottom
    if #inventory > 0 then
        rectf(s, 0, INV_Y, SW, SH - INV_Y, C_BLK)
        line(s, 0, INV_Y, SW, INV_Y, C_DGR)
        local ix = 2
        for i, inv_item in ipairs(inventory) do
            -- Show first 3 chars of each item
            local short = inv_item:sub(1, 4)
            text(s, short, ix, INV_Y + 3, C_DGR)
            ix = ix + 26
            if ix > SW - 20 then break end
        end
    end

    -- Game won overlay
    if game_won then
        if math.floor(frame() / 40) % 2 == 0 then
            text(s, "PRESS START", SW/2, SH - 8, C_WHT, ALIGN_CENTER)
        end
    end
end

------------------------------------------------------
-- INIT / START
------------------------------------------------------
function _init()
    mode(2)
end

function _start()
    go("title")
end
