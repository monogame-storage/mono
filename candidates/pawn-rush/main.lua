-- PAWN RUSH
-- Race your pawn to the 8th rank! Dodge enemies, promote, survive!
-- 1-bit chess racing/evolution game

----------------------------------------------------------------
-- GLOBALS
----------------------------------------------------------------
local SCR_W = 160
local SCR_H = 120

local high_score = 0

function _init()
  mode(1)
  high_score = 0
end

function _start()
  go("title")
end

----------------------------------------------------------------
-- TITLE SCENE
----------------------------------------------------------------
local title_blink = 0
local title_intro_y = -20
local title_intro_done = false
local title_idle = 0
local IDLE_THRESHOLD = 90
local demo_active = false

-- Demo state
local demo_player_x = 0
local demo_lanes = {}
local demo_enemies = {}
local demo_timer = 0
local demo_scroll = 0

-- 7-segment patterns: {a,b,c,d,e,f,g}
local SEG = {
  {1,1,1,1,1,1,0}, -- 0
  {0,1,1,0,0,0,0}, -- 1
  {1,1,0,1,1,0,1}, -- 2
  {1,1,1,1,0,0,1}, -- 3
  {0,1,1,0,0,1,1}, -- 4
  {1,0,1,1,0,1,1}, -- 5
  {1,0,1,1,1,1,1}, -- 6
  {1,1,1,0,0,0,0}, -- 7
  {1,1,1,1,1,1,1}, -- 8
  {1,1,1,1,0,1,1}, -- 9
}

local function draw_seg_digit(s, x, y, digit, c)
  local p = SEG[digit + 1]
  if not p then return end
  if p[1]==1 then rectf(s, x+1, y,   4, 1, c) end
  if p[2]==1 then rectf(s, x+4, y+1, 1, 3, c) end
  if p[3]==1 then rectf(s, x+4, y+5, 1, 3, c) end
  if p[4]==1 then rectf(s, x+1, y+8, 4, 1, c) end
  if p[5]==1 then rectf(s, x,   y+5, 1, 3, c) end
  if p[6]==1 then rectf(s, x,   y+1, 1, 3, c) end
  if p[7]==1 then rectf(s, x+1, y+4, 4, 1, c) end
end

local function draw_clock(s)
  local d = date()
  local h = d.hour
  local m = d.min
  local cx = SCR_W - 32
  local cy = 2
  draw_seg_digit(s, cx, cy, math.floor(h/10), 1)
  draw_seg_digit(s, cx+7, cy, h%10, 1)
  if math.floor(frame()/30)%2==0 then
    pix(s, cx+13, cy+2, 1)
    pix(s, cx+13, cy+6, 1)
  end
  draw_seg_digit(s, cx+16, cy, math.floor(m/10), 1)
  draw_seg_digit(s, cx+23, cy, m%10, 1)
end

local function demo_init()
  demo_active = true
  demo_player_x = 80
  demo_enemies = {}
  demo_timer = 0
  demo_scroll = 0
end

local function demo_update_tick()
  demo_timer = demo_timer + 1
  demo_scroll = demo_scroll + 1

  -- AI: wobble player
  if demo_timer % 8 == 0 then
    local r = math.random(1,3)
    if r == 1 and demo_player_x > 20 then demo_player_x = demo_player_x - 16
    elseif r == 2 and demo_player_x < 140 then demo_player_x = demo_player_x + 16
    end
  end

  -- Spawn enemies
  if demo_timer % 12 == 0 then
    table.insert(demo_enemies, {
      x = math.random(2, 9) * 16,
      y = -8,
      t = math.random(1,4)
    })
  end

  -- Move enemies
  for i = #demo_enemies, 1, -1 do
    demo_enemies[i].y = demo_enemies[i].y + 2
    if demo_enemies[i].y > 130 then
      table.remove(demo_enemies, i)
    end
  end
end

local function draw_mini_pawn(s, x, y, c)
  -- Tiny pawn shape
  pix(s, x, y-3, c)
  pix(s, x-1, y-2, c)
  pix(s, x+1, y-2, c)
  pix(s, x, y-2, c)
  pix(s, x-1, y-1, c)
  pix(s, x+1, y-1, c)
  pix(s, x, y-1, c)
  pix(s, x, y, c)
  pix(s, x-1, y+1, c)
  pix(s, x, y+1, c)
  pix(s, x+1, y+1, c)
end

local function demo_draw_frame(s)
  cls(s, 0)

  -- Scrolling board pattern: dotted checkerboard
  local offset = demo_scroll % 16
  for row = -1, 8 do
    for col = 0, 9 do
      local ry = row*16 + offset
      if (row+col+math.floor(demo_scroll/16))%2==0 then
        for dy=0,15,4 do
          for dx=0,15,4 do
            if ry+dy >= 0 and ry+dy < 120 then
              pix(s, col*16+dx, ry+dy, 1)
            end
          end
        end
      end
    end
  end

  -- Enemies
  for _, e in ipairs(demo_enemies) do
    rectf(s, e.x-3, e.y-3, 7, 7, 1)
    rectf(s, e.x-2, e.y-2, 5, 5, 0)
    pix(s, e.x, e.y, 1)
  end

  -- Player pawn
  draw_mini_pawn(s, demo_player_x, 100, 1)

  -- Labels
  text(s, "DEMO", 80, 2, 1, ALIGN_CENTER)
  if math.floor(frame()/20)%2==0 then
    text(s, "PRESS START", 80, 112, 1, ALIGN_CENTER)
  end

  draw_clock(s)
end

-- Bitmap font for title: each letter is 5 wide x 7 tall, stored as 7 row-bytes
local LOGO_FONT = {
  P={0x1E,0x11,0x11,0x1E,0x10,0x10,0x10},
  A={0x0E,0x11,0x11,0x1F,0x11,0x11,0x11},
  W={0x11,0x11,0x11,0x15,0x15,0x0A,0x0A},
  N={0x11,0x19,0x15,0x13,0x11,0x11,0x11},
  R={0x1E,0x11,0x11,0x1E,0x14,0x12,0x11},
  U={0x11,0x11,0x11,0x11,0x11,0x11,0x0E},
  S={0x0E,0x11,0x10,0x0E,0x01,0x11,0x0E},
  H={0x11,0x11,0x11,0x1F,0x11,0x11,0x11},
}

local function draw_title_logo(s, y)
  local words = {"PAWN", "RUSH"}
  local word_x = {20, 72}
  for wi, word in ipairs(words) do
    local cx = word_x[wi]
    for ci = 1, #word do
      local ch = word:sub(ci, ci)
      local bmp = LOGO_FONT[ch]
      if bmp then
        for row = 0, 6 do
          local bits = bmp[row + 1]
          for col = 0, 4 do
            if bits and math.floor(bits / 2^(4-col)) % 2 == 1 then
              rectf(s, cx + col*2, y + row*2, 2, 2, 1)
            end
          end
        end
      end
      cx = cx + 12
    end
  end
end

function title_init()
  title_blink = 0
  title_intro_y = -20
  title_intro_done = false
  title_idle = 0
  demo_active = false
  demo_timer = 0
end

function title_update()
  title_blink = title_blink + 1

  -- Any input exits demo
  if demo_active then
    if btnp("start") or btnp("a") or btnp("b") or touch_start() then
      demo_active = false
      title_idle = 0
      note(0, "C5", 0.08)
      return
    end
    demo_update_tick()
    return
  end

  -- Intro slide
  if not title_intro_done then
    title_intro_y = title_intro_y + 2
    if title_intro_y >= 20 then
      title_intro_y = 20
      title_intro_done = true
    end
  end

  -- Start game
  if title_intro_done and (btnp("start") or touch_start()) then
    note(0, "C5", 0.1)
    go("game")
    return
  end

  -- Idle → demo
  if title_intro_done then
    title_idle = title_idle + 1
    if btn("left") or btn("right") or btn("a") or btn("b") then
      title_idle = 0
    end
    if title_idle >= IDLE_THRESHOLD then
      demo_init()
      title_idle = 0
    end
  end
end

function title_draw()
  local s = screen()
  cls(s, 0)

  if demo_active then
    demo_draw_frame(s)
    return
  end

  -- Border
  rect(s, 1, 1, SCR_W-2, SCR_H-2, 1)

  -- Title
  draw_title_logo(s, title_intro_y)

  if title_intro_done then
    -- Chess pawn icon centered
    local cx = 80
    local cy = 52
    -- Draw a bigger pawn
    circf(s, cx, cy-6, 3, 1)
    rectf(s, cx-2, cy-3, 5, 4, 1)
    rectf(s, cx-3, cy+1, 7, 2, 1)
    rectf(s, cx-1, cy-1, 3, 5, 1)
    rectf(s, cx-4, cy+3, 9, 2, 1)

    -- Subtitle
    text(s, "RACE TO PROMOTE!", 80, 68, 1, ALIGN_CENTER)

    -- Blink start
    if math.floor(title_blink/15)%2==0 then
      text(s, "PRESS START", 80, 82, 1, ALIGN_CENTER)
    end

    -- Controls
    text(s, "LEFT/RIGHT:DODGE  A:EN PASSANT", 80, 96, 1, ALIGN_CENTER)

    -- High score
    if high_score > 0 then
      text(s, "HI:" .. high_score, 80, 110, 1, ALIGN_CENTER)
    end
  end
end

----------------------------------------------------------------
-- GAME SCENE
----------------------------------------------------------------

-- Board / layout
local BOARD_X = 16        -- left margin for the 8-column board
local BOARD_W = 128       -- 8 cols * 16px
local LANE_W = 16         -- width per lane
local NUM_LANES = 8
local RANK_H = 14         -- pixel height per rank row visible

-- Player state
local player = {}
local PLAYER_SPEED = 2

-- Promotion tiers
local PROMO_NAMES = {"PAWN", "KNIGHT", "BISHOP", "ROOK", "QUEEN"}
local PROMO_RANK = 0      -- how many times promoted (0-4)

-- Scrolling
local scroll_y = 0
local scroll_speed = 1.0
local rank_counter = 0    -- how many ranks scrolled (tracks progress to 8th rank)
local ranks_to_promote = 24  -- ranks needed for next promotion (gets harder)

-- Enemies
local enemies = {}
local enemy_spawn_timer = 0
local enemy_spawn_rate = 20   -- frames between spawns (decreases)

-- En passant
local en_passant_active = false
local en_passant_timer = 0
local EN_PASSANT_DURATION = 12
local en_passant_cooldown = 0
local EN_PASSANT_COOLDOWN = 30

-- Score / state
local game_score = 0
local game_alive = true
local distance = 0
local rank_progress = 0   -- 0.0 to 1.0 progress to next promotion
local promo_flash = 0     -- animation timer when promoting
local hit_flash = 0       -- invincibility frames after getting hit
local lives = 3
local game_over_timer = 0

-- Particles (simple)
local particles = {}

-- Touch
local touch_cd = 0

-- Bass line
local bass_tick = 0
local BASS_NOTES = {"C2","D2","E2","G2","C3","D3","E3","G3"}

local function reset_game()
  player = {
    x = 80,
    y = 90,
    lane = 4,
    w = 8,
    h = 10
  }
  PROMO_RANK = 0
  scroll_y = 0
  scroll_speed = 1.0
  rank_counter = 0
  ranks_to_promote = 24
  enemies = {}
  enemy_spawn_timer = 0
  enemy_spawn_rate = 20
  en_passant_active = false
  en_passant_timer = 0
  en_passant_cooldown = 0
  game_score = 0
  game_alive = true
  distance = 0
  rank_progress = 0
  promo_flash = 0
  hit_flash = 0
  lives = 3
  game_over_timer = 0
  particles = {}
  touch_cd = 0
  bass_tick = 0
  wave(0, "square")
end

-- Enemy types with different behaviors
local ENEMY_TYPES = {
  -- pawn: moves straight down
  {name="pawn", w=6, h=8, speed=1.5},
  -- knight: moves down + jumps sideways
  {name="knight", w=8, h=8, speed=1.2},
  -- bishop: moves diagonally
  {name="bishop", w=8, h=8, speed=1.8},
  -- rook: moves straight down fast
  {name="rook", w=10, h=8, speed=2.5},
  -- queen: tracks player somewhat
  {name="queen", w=10, h=10, speed=1.6},
}

local function spawn_enemy()
  -- Choose enemy type based on distance/promotions
  local max_type = math.min(1 + math.floor(distance / 200), 5)
  local etype = math.random(1, max_type)
  local et = ENEMY_TYPES[etype]

  local lane = math.random(0, NUM_LANES - 1)
  local ex = BOARD_X + lane * LANE_W + LANE_W/2

  local e = {
    x = ex,
    y = -10,
    vx = 0,
    vy = et.speed + scroll_speed * 0.3,
    w = et.w,
    h = et.h,
    etype = etype,
    name = et.name,
    timer = 0,
    alive = true
  }

  -- Knight: random sideways velocity
  if etype == 2 then
    e.vx = (math.random(0,1)*2-1) * 0.8
  end
  -- Bishop: diagonal
  if etype == 3 then
    e.vx = (math.random(0,1)*2-1) * 1.2
  end

  table.insert(enemies, e)
end

local function spawn_particle(x, y, count)
  for i = 1, count do
    table.insert(particles, {
      x = x,
      y = y,
      vx = (math.random()-0.5)*4,
      vy = (math.random()-0.5)*4,
      life = math.random(8, 16)
    })
  end
end

local function aabb(ax,ay,aw,ah, bx,by,bw,bh)
  return ax < bx+bw and ax+aw > bx and ay < by+bh and ay+ah > by
end

local function do_promotion()
  if PROMO_RANK < 4 then
    PROMO_RANK = PROMO_RANK + 1
    promo_flash = 30
    rank_counter = 0
    ranks_to_promote = math.floor(ranks_to_promote * 1.3)
    -- Effects
    note(0, "C5", 0.12)
    note(1, "E5", 0.12)
    cam_shake(4)
    spawn_particle(player.x, player.y, 12)
    -- Bonus
    game_score = game_score + PROMO_RANK * 500
    -- Promotion benefits
    if PROMO_RANK == 1 then
      -- Knight: wider dodge
      player.w = 6
    elseif PROMO_RANK == 2 then
      -- Bishop: faster movement
      PLAYER_SPEED = 3
    elseif PROMO_RANK == 3 then
      -- Rook: extra life
      lives = math.min(lives + 1, 5)
    elseif PROMO_RANK == 4 then
      -- Queen: all bonuses enhanced
      PLAYER_SPEED = 4
      player.w = 5
    end
  end
end

local function player_hit()
  if hit_flash > 0 then return end
  if en_passant_active then return end

  lives = lives - 1
  hit_flash = 45
  cam_shake(3)
  noise(0, 0.3)
  spawn_particle(player.x, player.y, 8)

  if lives <= 0 then
    game_alive = false
    game_over_timer = 0
    if game_score > high_score then
      high_score = game_score
    end
    noise(0, 0.5)
    cam_shake(6)
  end
end

-- Draw chess piece shapes (1-bit)
local function draw_pawn(s, x, y, c)
  -- Small pawn silhouette
  circf(s, x, y-4, 2, c)
  rectf(s, x-2, y-2, 5, 3, c)
  rectf(s, x-1, y+1, 3, 2, c)
  rectf(s, x-3, y+3, 7, 2, c)
end

local function draw_knight(s, x, y, c)
  -- Knight (L-shape head)
  rectf(s, x-2, y-4, 3, 3, c)
  rectf(s, x-1, y-5, 4, 2, c)
  rectf(s, x-2, y-1, 5, 3, c)
  rectf(s, x-3, y+2, 7, 2, c)
end

local function draw_bishop(s, x, y, c)
  -- Bishop (pointed top)
  pix(s, x, y-5, c)
  rectf(s, x-1, y-4, 3, 2, c)
  rectf(s, x-2, y-2, 5, 3, c)
  rectf(s, x-1, y+1, 3, 2, c)
  rectf(s, x-3, y+3, 7, 2, c)
end

local function draw_rook(s, x, y, c)
  -- Rook (battlements on top)
  pix(s, x-3, y-5, c)
  pix(s, x-1, y-5, c)
  pix(s, x+1, y-5, c)
  pix(s, x+3, y-5, c)
  rectf(s, x-3, y-4, 7, 2, c)
  rectf(s, x-2, y-2, 5, 4, c)
  rectf(s, x-3, y+2, 7, 3, c)
end

local function draw_queen(s, x, y, c)
  -- Queen (crown points)
  pix(s, x-3, y-6, c)
  pix(s, x, y-6, c)
  pix(s, x+3, y-6, c)
  pix(s, x-2, y-5, c)
  pix(s, x+2, y-5, c)
  rectf(s, x-3, y-4, 7, 2, c)
  rectf(s, x-2, y-2, 5, 4, c)
  rectf(s, x-3, y+2, 7, 3, c)
end

local PIECE_DRAW = {draw_pawn, draw_knight, draw_bishop, draw_rook, draw_queen}

local function draw_player_piece(s, x, y)
  local c = 1
  -- Flash white/black during invincibility
  if hit_flash > 0 and math.floor(hit_flash/3)%2==1 then
    c = 0
  end
  -- Promo flash
  if promo_flash > 0 and math.floor(promo_flash/2)%2==1 then
    c = 0
  end
  local fn = PIECE_DRAW[PROMO_RANK + 1]
  if fn then fn(s, x, y, c) end
end

local function draw_enemy_piece(s, x, y, etype)
  local fn = PIECE_DRAW[etype]
  if fn then fn(s, math.floor(x), math.floor(y), 1) end
end

function game_init()
  reset_game()
  PLAYER_SPEED = 2
end

function game_update()
  if not game_alive then
    game_over_timer = game_over_timer + 1
    if game_over_timer > 30 and (btnp("start") or touch_start()) then
      go("title")
    end
    return
  end

  -- Timers
  if hit_flash > 0 then hit_flash = hit_flash - 1 end
  if promo_flash > 0 then promo_flash = promo_flash - 1 end
  if en_passant_cooldown > 0 then en_passant_cooldown = en_passant_cooldown - 1 end
  if touch_cd > 0 then touch_cd = touch_cd - 1 end

  -- En passant timer
  if en_passant_active then
    en_passant_timer = en_passant_timer - 1
    if en_passant_timer <= 0 then
      en_passant_active = false
    end
  end

  -- Scrolling (board moves down = player moves up)
  scroll_y = scroll_y + scroll_speed
  distance = distance + scroll_speed

  -- Rank tracking for promotion
  rank_counter = rank_counter + scroll_speed
  rank_progress = rank_counter / ranks_to_promote
  if rank_counter >= ranks_to_promote then
    do_promotion()
  end

  -- Gradually increase speed
  scroll_speed = 1.0 + distance / 800
  if scroll_speed > 4.0 then scroll_speed = 4.0 end

  -- Decrease spawn rate as speed increases
  enemy_spawn_rate = math.max(8, 20 - math.floor(distance / 150))

  -- Player input
  local moved = false

  -- Swipe support
  local sw = swipe()
  if sw then
    touch_cd = 6
    if sw == "left" then
      player.x = player.x - LANE_W
      moved = true
    elseif sw == "right" then
      player.x = player.x + LANE_W
      moved = true
    elseif sw == "up" then
      -- En passant on swipe up
      if not en_passant_active and en_passant_cooldown <= 0 then
        en_passant_active = true
        en_passant_timer = EN_PASSANT_DURATION
        en_passant_cooldown = EN_PASSANT_COOLDOWN
        -- Diagonal dash
        player.x = player.x + (math.random(0,1)*2-1) * LANE_W
        player.y = player.y - 8
        tone(0, 400, 800, 0.08)
        spawn_particle(player.x, player.y+8, 4)
      end
    end
  end

  -- D-pad
  if btnp("left") then
    player.x = player.x - LANE_W
    moved = true
  end
  if btnp("right") then
    player.x = player.x + LANE_W
    moved = true
  end

  -- Held movement (smooth)
  if btn("left") and not btnp("left") then
    player.x = player.x - PLAYER_SPEED
    moved = true
  end
  if btn("right") and not btnp("right") then
    player.x = player.x + PLAYER_SPEED
    moved = true
  end

  -- En passant button
  if (btnp("a") or btnp("b")) and not en_passant_active and en_passant_cooldown <= 0 then
    en_passant_active = true
    en_passant_timer = EN_PASSANT_DURATION
    en_passant_cooldown = EN_PASSANT_COOLDOWN
    -- Diagonal dodge
    local dir = 1
    if btn("left") then dir = -1 end
    player.x = player.x + dir * LANE_W
    player.y = player.y - 8
    tone(0, 400, 800, 0.08)
    spawn_particle(player.x, player.y+8, 4)
  end

  -- Clamp player position
  if player.x < BOARD_X + 4 then player.x = BOARD_X + 4 end
  if player.x > BOARD_X + BOARD_W - 4 then player.x = BOARD_X + BOARD_W - 4 end

  -- Return player y to home row smoothly
  if player.y < 90 then
    player.y = player.y + 1
  end

  if moved then
    note(1, "A4", 0.02)
  end

  -- Spawn enemies
  enemy_spawn_timer = enemy_spawn_timer + 1
  if enemy_spawn_timer >= enemy_spawn_rate then
    enemy_spawn_timer = 0
    spawn_enemy()
  end

  -- Update enemies
  for i = #enemies, 1, -1 do
    local e = enemies[i]
    e.x = e.x + e.vx
    e.y = e.y + e.vy + scroll_speed * 0.5
    e.timer = e.timer + 1

    -- Knight jump behavior
    if e.etype == 2 and e.timer % 20 == 0 then
      e.vx = -e.vx
    end

    -- Queen tracking
    if e.etype == 5 then
      if player.x < e.x then e.vx = e.vx - 0.05
      else e.vx = e.vx + 0.05 end
      e.vx = math.max(-1.5, math.min(1.5, e.vx))
    end

    -- Bounce off walls
    if e.x < BOARD_X + 4 then e.x = BOARD_X + 4; e.vx = math.abs(e.vx) end
    if e.x > BOARD_X + BOARD_W - 4 then e.x = BOARD_X + BOARD_W - 4; e.vx = -math.abs(e.vx) end

    -- Off-screen removal
    if e.y > SCR_H + 20 then
      table.remove(enemies, i)
      -- Score for dodged enemy
      game_score = game_score + 10
    end
  end

  -- Collision check
  for i = #enemies, 1, -1 do
    local e = enemies[i]
    if e.alive then
      local pw = player.w or 8
      local ph = player.h or 10
      if aabb(player.x - pw/2, player.y - ph/2, pw, ph,
              e.x - e.w/2, e.y - e.h/2, e.w, e.h) then
        if en_passant_active then
          -- En passant destroys enemy!
          e.alive = false
          table.remove(enemies, i)
          game_score = game_score + 50 * (PROMO_RANK + 1)
          spawn_particle(e.x, e.y, 6)
          note(0, "E5", 0.06)
        else
          player_hit()
          -- Remove enemy that hit us
          table.remove(enemies, i)
        end
      end
    end
  end

  -- Update particles
  for i = #particles, 1, -1 do
    local p = particles[i]
    p.x = p.x + p.vx
    p.y = p.y + p.vy
    p.life = p.life - 1
    if p.life <= 0 then
      table.remove(particles, i)
    end
  end

  -- Driving bass line synced to scroll speed
  local bass_interval = math.max(4, math.floor(16 - scroll_speed * 3))
  bass_tick = bass_tick + 1
  if bass_tick >= bass_interval then
    bass_tick = 0
    -- Pick note from sequence; climb higher as speed increases
    local idx = 1 + math.floor(distance / 100) % #BASS_NOTES
    -- Faster speed = higher octave reach
    if scroll_speed > 2.5 then
      idx = math.min(idx + 2, #BASS_NOTES)
    end
    note(0, BASS_NOTES[idx], 0.04)
  end

  -- Score ticks up with distance
  game_score = game_score + math.floor(scroll_speed)
end

function game_draw()
  local s = screen()
  cls(s, 0)

  -- Draw scrolling checkerboard
  local board_offset = math.floor(scroll_y) % (RANK_H * 2)
  for row = -2, 10 do
    for col = 0, NUM_LANES - 1 do
      local rx = BOARD_X + col * LANE_W
      local ry = row * RANK_H + board_offset - RANK_H
      if (row + col) % 2 == 0 then
        rectf(s, rx, ry, LANE_W, RANK_H, 1)
      end
    end
  end

  -- Board border
  rect(s, BOARD_X-1, 0, BOARD_W+2, SCR_H, 1)

  -- Draw promotion progress bar on left
  local bar_x = 2
  local bar_y = 20
  local bar_h = 80
  rect(s, bar_x, bar_y, 8, bar_h, 1)
  local fill_h = math.floor(rank_progress * (bar_h - 2))
  if fill_h > 0 then
    rectf(s, bar_x+1, bar_y + bar_h - 1 - fill_h, 6, fill_h, 1)
  end
  -- Rank markers
  for i = 1, 8 do
    local my = bar_y + bar_h - math.floor(i/8 * bar_h)
    pix(s, bar_x-1, my, 1)
  end
  text(s, "8", bar_x+2, bar_y-8, 1, ALIGN_CENTER)

  -- Draw enemies
  for _, e in ipairs(enemies) do
    if e.alive and e.y > -10 and e.y < SCR_H + 10 then
      draw_enemy_piece(s, e.x, e.y, e.etype)
    end
  end

  -- Draw player
  draw_player_piece(s, math.floor(player.x), math.floor(player.y))

  -- En passant trail effect
  if en_passant_active then
    -- Draw diagonal trail
    local trail_c = 1
    if math.floor(en_passant_timer/2)%2==0 then trail_c = 0 end
    line(s, player.x-4, player.y+6, player.x+4, player.y+6, trail_c)
    line(s, player.x-3, player.y+8, player.x+3, player.y+8, trail_c)
  end

  -- Draw particles
  for _, p in ipairs(particles) do
    pix(s, math.floor(p.x), math.floor(p.y), 1)
  end

  -- UI: right panel
  local ux = BOARD_X + BOARD_W + 4

  -- Score
  text(s, "SCR", ux, 2, 1)
  text(s, tostring(game_score), ux, 10, 1)

  -- Lives
  text(s, "x" .. lives, ux, 22, 1)

  -- Current piece name
  text(s, PROMO_NAMES[PROMO_RANK + 1], ux, 34, 1)

  -- En passant cooldown indicator
  if en_passant_cooldown > 0 then
    text(s, "EP", ux, 46, 1)
    local cd_w = math.floor((1 - en_passant_cooldown / EN_PASSANT_COOLDOWN) * 12)
    rect(s, ux, 54, 12, 4, 1)
    if cd_w > 0 then
      rectf(s, ux, 54, cd_w, 4, 1)
    end
  else
    text(s, "EP", ux, 46, 1)
    rectf(s, ux, 54, 12, 4, 1)
  end

  -- Speed indicator
  text(s, "SPD", ux, 64, 1)
  local spd_bar = math.floor(scroll_speed / 4.0 * 12)
  rect(s, ux, 72, 12, 4, 1)
  if spd_bar > 0 then
    rectf(s, ux, 72, spd_bar, 4, 1)
  end

  -- Distance / rank
  text(s, "DST", ux, 84, 1)
  text(s, tostring(math.floor(distance)), ux, 92, 1)

  -- Promotion flash overlay
  if promo_flash > 0 then
    if math.floor(promo_flash/3)%2==0 then
      rectf(s, 0, 50, SCR_W, 20, 1)
      text(s, "PROMOTED TO", 80, 52, 0, ALIGN_CENTER)
      text(s, PROMO_NAMES[PROMO_RANK + 1] .. "!", 80, 60, 0, ALIGN_CENTER)
    else
      rectf(s, 0, 50, SCR_W, 20, 0)
      text(s, "PROMOTED TO", 80, 52, 1, ALIGN_CENTER)
      text(s, PROMO_NAMES[PROMO_RANK + 1] .. "!", 80, 60, 1, ALIGN_CENTER)
    end
  end

  -- Game over overlay
  if not game_alive then
    rectf(s, 20, 35, 120, 50, 0)
    rect(s, 20, 35, 120, 50, 1)
    text(s, "GAME OVER", 80, 40, 1, ALIGN_CENTER)
    text(s, "SCORE: " .. game_score, 80, 52, 1, ALIGN_CENTER)
    text(s, "RANK: " .. PROMO_NAMES[PROMO_RANK + 1], 80, 62, 1, ALIGN_CENTER)
    if high_score == game_score then
      text(s, "NEW HIGH SCORE!", 80, 72, 1, ALIGN_CENTER)
    end
    if game_over_timer > 30 and math.floor(frame()/15)%2==0 then
      text(s, "PRESS START", 80, 80, 1, ALIGN_CENTER)
    end
  end
end
