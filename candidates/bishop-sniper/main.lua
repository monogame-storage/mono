-- BISHOP SNIPER
-- Diagonal-only shooting & territory control on a chess grid
-- 1-bit black and white | 160x120 | 30fps

---------- CONSTANTS ----------
local W = 160
local H = 120
local BOARD_SIZE = 8
local CELL = 12            -- pixel size of each board cell
local BOARD_PX = BOARD_SIZE * CELL  -- 96 pixels
local BOARD_OX = math.floor((W - BOARD_PX) / 2)  -- board left offset
local BOARD_OY = 14        -- board top offset (leave room for HUD)
local HUD_Y = 2
local SHOT_SPEED = 4       -- pixels per frame
local ENEMY_BASE_SPEED = 0.3
local MAX_LIVES = 3
local COMBO_DISPLAY_TIME = 40
local ATTRACT_IDLE_FRAMES = 150  -- 5 seconds idle before attract
local ATTRACT_DURATION = 600     -- 20 seconds of demo
local TERRITORY_BONUS_INTERVAL = 90  -- frames between territory score ticks
local TERRITORY_BONUS_PER_CELL = 1   -- score per claimed cell per tick

---------- HELPERS ----------
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local abs = math.abs
local floor = math.floor
local random = math.random
local sqrt = math.sqrt

-- diagonal directions: {dx, dy}
local DIAGS = {
  {-1, -1},  -- up-left
  { 1, -1},  -- up-right
  {-1,  1},  -- down-left
  { 1,  1},  -- down-right
}

---------- SAFE AUDIO ----------
local function sfx_note(ch, n, dur)
  if note then note(ch, n, dur) end
end
local function sfx_noise(ch, dur)
  if noise then noise(ch, dur) end
end
local function sfx_tone(ch, freq, dur)
  if tone then tone(ch, freq, dur) end
end

---------- 7-SEGMENT CLOCK ----------
local SEG7 = {
  [0] = 1+2+4+8+16+32,
  [1] = 2+4,
  [2] = 1+2+8+16+64,
  [3] = 1+2+4+8+64,
  [4] = 2+4+32+64,
  [5] = 1+4+8+32+64,
  [6] = 1+4+8+16+32+64,
  [7] = 1+2+4,
  [8] = 1+2+4+8+16+32+64,
  [9] = 1+2+4+8+32+64,
}

local function draw_seg7(s, digit, ox, oy, col)
  local segs = SEG7[digit] or 0
  local t = 2
  if segs % 2 >= 1 then rectf(s, ox+t, oy, 3, t, col) end
  if floor(segs/2) % 2 == 1 then rectf(s, ox+t+3, oy+t, t, 4, col) end
  if floor(segs/4) % 2 == 1 then rectf(s, ox+t+3, oy+t+5, t, 4, col) end
  if floor(segs/8) % 2 == 1 then rectf(s, ox+t, oy+t+9, 3, t, col) end
  if floor(segs/16) % 2 == 1 then rectf(s, ox, oy+t+5, t, 4, col) end
  if floor(segs/32) % 2 == 1 then rectf(s, ox, oy+t, t, 4, col) end
  if floor(segs/64) % 2 == 1 then rectf(s, ox+t, oy+t+4, 3, 1, col) end
end

local function draw_clock7(s, ox, oy, col)
  local d = date()
  local h = d.hour
  local m = d.min
  draw_seg7(s, floor(h/10), ox, oy, col)
  draw_seg7(s, h%10, ox+9, oy, col)
  if floor(frame()/30) % 2 == 0 then
    rectf(s, ox+18, oy+3, 2, 2, col)
    rectf(s, ox+18, oy+8, 2, 2, col)
  end
  draw_seg7(s, floor(m/10), ox+21, oy, col)
  draw_seg7(s, m%10, ox+30, oy, col)
end

---------- GLOBAL STATE ----------
local state = "title"
local high_score = 0

-- Player (board coordinates 0-7)
local px, py           -- board position
local aim_dir          -- 1-4 index into DIAGS
local lives
local score
local wave_num
local wave_enemies_left
local wave_active

-- Game objects
local enemies = {}
local shots = {}
local particles = {}
local combo_texts = {}

-- Territory grid: territory[by*8+bx] = true if claimed
local territory = {}
local territory_count = 0
local territory_bonus_timer = 0

-- Movement direction index (1-4 into DIAGS) for d-pad cycling
local move_dir = 1

-- Attract mode
local idle_timer = 0
local attract_timer = 0
local attract_mode = false

-- Wave timing
local wave_spawn_timer = 0
local wave_spawn_interval = 60
local wave_total_spawned = 0
local wave_max_enemies = 4

-- Damage flash
local damage_flash = 0

---------- BOARD HELPERS ----------
local function board_to_px(bx, by)
  local sx = BOARD_OX + bx * CELL
  local sy = BOARD_OY + by * CELL
  return sx, sy
end

local function cell_color(bx, by)
  -- standard chess coloring: 0=black, 1=white
  return (bx + by) % 2 == 0 and 1 or 0
end

local function on_board(bx, by)
  return bx >= 0 and bx < BOARD_SIZE and by >= 0 and by < BOARD_SIZE
end

---------- TERRITORY SYSTEM ----------
local function territory_key(bx, by)
  return by * BOARD_SIZE + bx
end

local function claim_cell(bx, by)
  if on_board(bx, by) then
    local k = territory_key(bx, by)
    if not territory[k] then
      territory[k] = true
      territory_count = territory_count + 1
    end
  end
end

local function claim_diagonal(from_bx, from_by, dx, dy)
  -- Paint territory along a diagonal from a position
  local cx, cy = from_bx + dx, from_by + dy
  while on_board(cx, cy) do
    claim_cell(cx, cy)
    cx = cx + dx
    cy = cy + dy
  end
end

local function is_claimed(bx, by)
  return territory[territory_key(bx, by)] == true
end

---------- PARTICLE SYSTEM ----------
local function add_particles(x, y, count, col)
  for i = 1, count do
    local angle = random() * 6.2832
    local speed = 0.5 + random() * 2.5
    particles[#particles+1] = {
      x = x, y = y,
      vx = math.cos(angle) * speed,
      vy = math.sin(angle) * speed,
      life = 8 + random(0, 10),
      col = col or 1
    }
  end
end

local function update_particles()
  local i = 1
  while i <= #particles do
    local p = particles[i]
    p.x = p.x + p.vx
    p.y = p.y + p.vy
    p.life = p.life - 1
    if p.life <= 0 then
      particles[i] = particles[#particles]
      particles[#particles] = nil
    else
      i = i + 1
    end
  end
end

local function draw_particles(s)
  for i = 1, #particles do
    local p = particles[i]
    pix(s, floor(p.x), floor(p.y), p.col)
  end
end

---------- COMBO TEXT SYSTEM ----------
local function add_combo_text(x, y, combo_val)
  combo_texts[#combo_texts+1] = {
    x = x, y = y,
    txt = "x" .. combo_val .. "!",
    life = COMBO_DISPLAY_TIME
  }
end

local function update_combo_texts()
  local i = 1
  while i <= #combo_texts do
    local ct = combo_texts[i]
    ct.y = ct.y - 0.4
    ct.life = ct.life - 1
    if ct.life <= 0 then
      combo_texts[i] = combo_texts[#combo_texts]
      combo_texts[#combo_texts] = nil
    else
      i = i + 1
    end
  end
end

local function draw_combo_texts(s)
  for i = 1, #combo_texts do
    local ct = combo_texts[i]
    if ct.life % 4 < 3 then  -- blink effect
      text(s, ct.txt, floor(ct.x), floor(ct.y), 1)
    end
  end
end

---------- BISHOP DRAWING ----------
local function draw_bishop(s, sx, sy, col)
  -- stylized bishop: pointed top, wider base ~12x12 within a cell
  local cx = sx + 6  -- center x
  -- pointed top
  pix(s, cx, sy+1, col)
  pix(s, cx, sy+2, col)
  -- head ball
  rectf(s, cx-1, sy+3, 3, 2, col)
  -- neck
  pix(s, cx, sy+5, col)
  -- body (triangle widening)
  rectf(s, cx-1, sy+6, 3, 1, col)
  rectf(s, cx-2, sy+7, 5, 1, col)
  rectf(s, cx-2, sy+8, 5, 1, col)
  rectf(s, cx-3, sy+9, 7, 1, col)
  -- base
  rectf(s, cx-3, sy+10, 7, 2, col)
end

---------- ENEMY DRAWING ----------
local function draw_pawn(s, sx, sy, col)
  local cx = sx + 6
  -- round head
  rectf(s, cx-1, sy+3, 3, 3, col)
  pix(s, cx, sy+2, col)
  -- body
  rectf(s, cx-1, sy+6, 3, 2, col)
  rectf(s, cx-2, sy+8, 5, 2, col)
  -- base
  rectf(s, cx-3, sy+10, 7, 1, col)
end

local function draw_knight(s, sx, sy, col)
  local cx = sx + 6
  -- knight head (L-shape hint)
  rectf(s, cx-2, sy+2, 3, 2, col)
  rectf(s, cx+1, sy+2, 2, 4, col)
  rectf(s, cx-1, sy+4, 4, 1, col)
  -- body
  rectf(s, cx-1, sy+5, 3, 3, col)
  rectf(s, cx-2, sy+8, 5, 2, col)
  -- base
  rectf(s, cx-3, sy+10, 7, 1, col)
end

local function draw_rook(s, sx, sy, col)
  local cx = sx + 6
  -- crenellations
  pix(s, cx-3, sy+2, col)
  pix(s, cx-1, sy+2, col)
  pix(s, cx+1, sy+2, col)
  pix(s, cx+3, sy+2, col)
  rectf(s, cx-3, sy+3, 7, 2, col)
  -- body (column)
  rectf(s, cx-2, sy+5, 5, 4, col)
  -- base
  rectf(s, cx-3, sy+9, 7, 2, col)
end

local enemy_draw_fns = { draw_pawn, draw_knight, draw_rook }

---------- ENEMY SPAWNING ----------
local function spawn_enemy(etype)
  etype = etype or 1
  -- pick a random edge cell
  local side = random(1, 4)
  local bx, by
  if side == 1 then      -- top
    bx, by = random(0, 7), 0
  elseif side == 2 then  -- bottom
    bx, by = random(0, 7), 7
  elseif side == 3 then  -- left
    bx, by = 0, random(0, 7)
  else                   -- right
    bx, by = 7, random(0, 7)
  end

  local hp = 1
  if etype == 3 then hp = 2 end  -- rooks are tanky

  enemies[#enemies+1] = {
    bx = bx, by = by,
    -- pixel position for smooth movement
    x = bx, y = by,
    etype = etype,
    hp = hp,
    move_timer = 0,
    speed = ENEMY_BASE_SPEED + (wave_num - 1) * 0.05,
  }
end

local function move_enemy_toward_player(e)
  -- move one step closer to player (prefer diagonal, then cardinal)
  local dx = px - e.bx
  local dy = py - e.by
  local sx = dx > 0 and 1 or (dx < 0 and -1 or 0)
  local sy = dy > 0 and 1 or (dy < 0 and -1 or 0)

  local nbx = e.bx + sx
  local nby = e.by + sy
  if on_board(nbx, nby) then
    e.bx = nbx
    e.by = nby
  end
end

---------- SHOT SYSTEM ----------
local function fire_shot(dir_idx)
  local d = DIAGS[dir_idx]
  local sx, sy = board_to_px(px, py)
  sx = sx + CELL/2
  sy = sy + CELL/2

  shots[#shots+1] = {
    x = sx, y = sy,
    dx = d[1] * SHOT_SPEED,
    dy = d[2] * SHOT_SPEED,
    dir_dx = d[1],
    dir_dy = d[2],
    origin_bx = px,
    origin_by = py,
    bounced = false,
    combo = 0,
    alive = true,
  }

  -- Paint territory along the shot diagonal
  if not attract_mode then
    claim_diagonal(px, py, d[1], d[2])
  end

  sfx_tone(0, 800, 3)
  sfx_noise(1, 2)
end

local function shot_hit_enemy(shot, enemy)
  local ex, ey = board_to_px(enemy.bx, enemy.by)
  local ecx = ex + CELL/2
  local ecy = ey + CELL/2
  local dist = abs(shot.x - ecx) + abs(shot.y - ecy)
  return dist < CELL * 0.7
end

---------- WAVE / GAME INIT ----------
local function start_wave()
  wave_active = true
  wave_max_enemies = 3 + wave_num
  if wave_max_enemies > 12 then wave_max_enemies = 12 end
  wave_enemies_left = wave_max_enemies
  wave_total_spawned = 0
  wave_spawn_timer = 0
  wave_spawn_interval = clamp(60 - wave_num * 5, 15, 60)
end

local function init_game()
  px = 3
  py = 4
  aim_dir = 2  -- up-right
  lives = MAX_LIVES
  score = 0
  wave_num = 1
  wave_enemies_left = 0
  wave_active = false
  enemies = {}
  shots = {}
  particles = {}
  combo_texts = {}
  damage_flash = 0
  wave_spawn_timer = 0
  wave_total_spawned = 0
  territory = {}
  territory_count = 0
  territory_bonus_timer = 0
  move_dir = 1
  start_wave()
end

---------- DRAW BOARD ----------
local function draw_board(s)
  for by = 0, BOARD_SIZE - 1 do
    for bx = 0, BOARD_SIZE - 1 do
      local sx, sy = board_to_px(bx, by)
      local c = cell_color(bx, by)
      rectf(s, sx, sy, CELL, CELL, c)
      -- draw territory dot pattern on claimed cells
      if is_claimed(bx, by) then
        local dot_col = 1 - c  -- inverted against cell
        -- 3x3 dot pattern centered in cell
        for dy = 0, 2 do
          for dx = 0, 2 do
            pix(s, sx + 2 + dx * 4, sy + 2 + dy * 4, dot_col)
          end
        end
      end
    end
  end
  -- board border
  rect(s, BOARD_OX-1, BOARD_OY-1, BOARD_PX+2, BOARD_PX+2, 1)
end

---------- DRAW AIM INDICATOR ----------
local function draw_aim(s)
  local d = DIAGS[aim_dir]
  local sx, sy = board_to_px(px, py)
  local cx = sx + CELL/2
  local cy = sy + CELL/2

  -- draw blinking dots along the aim diagonal
  if floor(frame() / 4) % 2 == 0 then
    for i = 1, 7 do
      local ax = cx + d[1] * i * CELL
      local ay = cy + d[2] * i * CELL
      if ax >= BOARD_OX and ax < BOARD_OX + BOARD_PX and
         ay >= BOARD_OY and ay < BOARD_OY + BOARD_PX then
        -- draw dot, inverted against cell color
        local bx2 = floor((ax - BOARD_OX) / CELL)
        local by2 = floor((ay - BOARD_OY) / CELL)
        local col = 1 - cell_color(bx2, by2)
        pix(s, floor(ax), floor(ay), col)
        pix(s, floor(ax)+1, floor(ay), col)
        pix(s, floor(ax), floor(ay)+1, col)
      end
    end
  end
end

---------- DRAW HUD ----------
local function draw_hud(s)
  -- score
  text(s, "SC:" .. score, 2, HUD_Y, 1)
  -- lives (small bishop icons)
  for i = 1, lives do
    local lx = W/2 - (lives * 5)/2 + (i-1) * 7
    -- tiny bishop icon
    pix(s, lx+2, HUD_Y, 1)
    rectf(s, lx+1, HUD_Y+1, 3, 2, 1)
    rectf(s, lx, HUD_Y+3, 5, 1, 1)
  end
  -- territory count
  text(s, "T:" .. territory_count, W/2 + 20, HUD_Y, 1)
  -- wave
  text(s, "W:" .. wave_num, W - 25, HUD_Y, 1)
end

---------- TITLE SCREEN ----------
function title_init()
  idle_timer = 0
end

function title_draw()
  local scr = screen()
  cls(scr, 0)

  -- draw a decorative mini board in center
  local mini = 4
  local mox = W/2 - (8*mini)/2
  local moy = 25
  for by = 0, 7 do
    for bx = 0, 7 do
      local c = (bx+by) % 2 == 0 and 1 or 0
      rectf(scr, mox + bx*mini, moy + by*mini, mini, mini, c)
    end
  end

  -- title text
  text(scr, "BISHOP SNIPER", W/2, 10, 1, ALIGN_CENTER)

  -- draw bishop on the mini board
  local bcx = mox + 3*mini + mini/2
  local bcy = moy + 4*mini + mini/2
  pix(scr, bcx, bcy-3, 0)
  rectf(scr, bcx-1, bcy-2, 3, 2, 0)
  rectf(scr, bcx-2, bcy, 5, 2, 0)

  -- diagonal shot lines from bishop
  if floor(frame()/8) % 2 == 0 then
    for _, d in ipairs(DIAGS) do
      for i = 1, 10 do
        local dx = bcx + d[1] * i * 3
        local dy = bcy + d[2] * i * 3
        if dx >= mox and dx < mox+32 and dy >= moy and dy < moy+32 then
          pix(scr, dx, dy, 1)
        end
      end
    end
  end

  -- instructions
  local blink = floor(frame()/20) % 2 == 0
  if blink then
    text(scr, "PRESS START", W/2, 70, 1, ALIGN_CENTER)
  end

  text(scr, "DPAD:DIAG MOVE  A:FIRE  B:AIM", W/2, 82, 1, ALIGN_CENTER)
  text(scr, "CLAIM TERRITORY!", W/2, 92, 1, ALIGN_CENTER)

  if high_score > 0 then
    text(scr, "HI:" .. high_score, W/2, 105, 1, ALIGN_CENTER)
  end
end

function title_update()
  idle_timer = idle_timer + 1

  -- check for start
  if btnp("start") or btnp("a") then
    idle_timer = 0
    attract_mode = false
    go("game")
    return
  end

  -- touch to start
  if touch_start then
    local tx, ty = touch_start()
    if tx then
      idle_timer = 0
      attract_mode = false
      go("game")
      return
    end
  end

  -- enter attract mode after idle
  if idle_timer > ATTRACT_IDLE_FRAMES then
    attract_mode = true
    attract_timer = 0
    init_game()
    go("attract")
  end
end

---------- ATTRACT MODE ----------
local attract_ai_timer = 0
local attract_ai_fire_timer = 0

function attract_draw()
  local scr = screen()
  cls(scr, 0)

  draw_board(scr)

  -- draw enemies
  for i = 1, #enemies do
    local e = enemies[i]
    local ex, ey = board_to_px(e.bx, e.by)
    local col = 1 - cell_color(e.bx, e.by)
    local fn = enemy_draw_fns[e.etype] or draw_pawn
    fn(scr, ex, ey, col)
  end

  -- draw shots
  for i = 1, #shots do
    local sh = shots[i]
    if sh.alive then
      rectf(scr, floor(sh.x)-1, floor(sh.y)-1, 3, 3, 1)
      if sh.bounced then
        pix(scr, floor(sh.x), floor(sh.y), 0)
      end
    end
  end

  -- draw bishop
  local bsx, bsy = board_to_px(px, py)
  local bcol = 1 - cell_color(px, py)
  draw_bishop(scr, bsx, bsy, bcol)

  draw_particles(scr)
  draw_combo_texts(scr)

  -- draw aim
  draw_aim(scr)

  -- HUD
  draw_hud(scr)

  -- clock overlay
  draw_clock7(scr, W - 42, HUD_Y, 1)

  -- DEMO label
  local blink = floor(frame()/15) % 2 == 0
  if blink then
    text(scr, "DEMO", 2, H - 10, 1)
  end
end

function attract_update()
  attract_timer = attract_timer + 1

  -- exit attract on any input
  if btnp("start") or btnp("a") or btnp("b") then
    attract_mode = false
    idle_timer = 0
    go("title")
    return
  end
  if touch_start then
    local tx, ty = touch_start()
    if tx then
      attract_mode = false
      idle_timer = 0
      go("title")
      return
    end
  end

  -- back to title after duration
  if attract_timer > ATTRACT_DURATION then
    attract_mode = false
    idle_timer = 0
    go("title")
    return
  end

  -- AI movement: move toward center, avoid edges
  attract_ai_timer = attract_ai_timer + 1
  if attract_ai_timer > 20 then
    attract_ai_timer = 0
    -- move toward center-ish with some randomness
    local tx = random(2, 5)
    local ty = random(2, 5)
    local dx = tx - px
    local dy = ty - py
    local sx = dx > 0 and 1 or (dx < 0 and -1 or 0)
    local sy = dy > 0 and 1 or (dy < 0 and -1 or 0)
    -- bishop moves diagonally
    if sx ~= 0 and sy ~= 0 then
      local nbx = clamp(px + sx, 0, 7)
      local nby = clamp(py + sy, 0, 7)
      px = nbx
      py = nby
    end
  end

  -- AI firing
  attract_ai_fire_timer = attract_ai_fire_timer + 1
  if attract_ai_fire_timer > 15 then
    attract_ai_fire_timer = 0
    -- find best diagonal toward nearest enemy
    local best_dir = random(1, 4)
    local best_dist = 999
    for _, e in ipairs(enemies) do
      local edx = e.bx - px
      local edy = e.by - py
      for di = 1, 4 do
        local dd = DIAGS[di]
        -- check if enemy is roughly on this diagonal
        if (edx * dd[1] > 0 or edx == 0) and (edy * dd[2] > 0 or edy == 0) then
          if abs(edx) == abs(edy) and abs(edx) > 0 then
            -- perfect diagonal
            local d = abs(edx)
            if d < best_dist then
              best_dist = d
              best_dir = di
            end
          end
        end
      end
    end
    aim_dir = best_dir
    fire_shot(aim_dir)
  end

  -- spawn enemies continuously in attract
  wave_spawn_timer = wave_spawn_timer + 1
  if wave_spawn_timer > 40 then
    wave_spawn_timer = 0
    if #enemies < 6 then
      spawn_enemy(random(1, 3))
    end
  end

  -- update game logic (shared)
  update_game_logic()
end

---------- GAME UPDATE LOGIC (shared between game and attract) ----------
function update_game_logic()
  -- update enemy movement
  for i = 1, #enemies do
    local e = enemies[i]
    e.move_timer = e.move_timer + e.speed
    if e.move_timer >= 1 then
      e.move_timer = e.move_timer - 1
      move_enemy_toward_player(e)
    end
  end

  -- update shots
  local si = 1
  while si <= #shots do
    local sh = shots[si]
    if not sh.alive then
      shots[si] = shots[#shots]
      shots[#shots] = nil
    else
      sh.x = sh.x + sh.dx
      sh.y = sh.y + sh.dy

      -- check board bounds for ricochet
      local in_board = sh.x >= BOARD_OX and sh.x < BOARD_OX + BOARD_PX and
                       sh.y >= BOARD_OY and sh.y < BOARD_OY + BOARD_PX

      if not in_board then
        if not sh.bounced then
          -- ricochet: reflect off edge
          sh.bounced = true
          if sh.x < BOARD_OX or sh.x >= BOARD_OX + BOARD_PX then
            sh.dx = -sh.dx
          end
          if sh.y < BOARD_OY or sh.y >= BOARD_OY + BOARD_PX then
            sh.dy = -sh.dy
          end
          -- push back onto board
          sh.x = clamp(sh.x, BOARD_OX + 1, BOARD_OX + BOARD_PX - 2)
          sh.y = clamp(sh.y, BOARD_OY + 1, BOARD_OY + BOARD_PX - 2)
          -- ricochet sound
          sfx_tone(2, 1200, 2)

          -- Paint territory along the new bounce diagonal
          if not attract_mode then
            local bounce_bx = floor((sh.x - BOARD_OX) / CELL)
            local bounce_by = floor((sh.y - BOARD_OY) / CELL)
            local ndx = sh.dx > 0 and 1 or -1
            local ndy = sh.dy > 0 and 1 or -1
            claim_cell(bounce_bx, bounce_by)
            claim_diagonal(bounce_bx, bounce_by, ndx, ndy)
          end

          -- ricochet flash particles
          add_particles(sh.x, sh.y, 4, 1)
        else
          -- already bounced, destroy
          sh.alive = false
        end
      end

      -- check hit enemies
      if sh.alive then
        for ei = #enemies, 1, -1 do
          local e = enemies[ei]
          if shot_hit_enemy(sh, e) then
            e.hp = e.hp - 1
            if e.hp <= 0 then
              -- kill
              sh.combo = sh.combo + 1
              local pts = 10 * sh.combo
              if sh.bounced then pts = pts + 25 end
              score = pts + score

              -- Claim the killed enemy's cell as territory
              if not attract_mode then
                claim_cell(e.bx, e.by)
              end

              local kx, ky = board_to_px(e.bx, e.by)
              kx = kx + CELL/2
              ky = ky + CELL/2
              add_particles(kx, ky, 8, 1)

              if sh.combo >= 2 then
                add_combo_text(kx, ky - 6, sh.combo)
                -- combo sound: ascending
                sfx_tone(3, 400 + sh.combo * 200, 3)
              end

              -- kill sound
              sfx_noise(1, 4)

              -- remove enemy
              enemies[ei] = enemies[#enemies]
              enemies[#enemies] = nil

              if not attract_mode then
                wave_enemies_left = wave_enemies_left - 1
              end
            else
              -- hit but not dead (tanky)
              sfx_tone(2, 300, 2)
              -- don't destroy shot for tanky enemies - continue through
            end
            -- shot continues for chain kills (don't break)
          end
        end
      end

      si = si + 1
    end
  end

  -- check enemy reaching player
  local ei = 1
  while ei <= #enemies do
    local e = enemies[ei]
    if e.bx == px and e.by == py then
      -- player hit!
      if not attract_mode then
        lives = lives - 1
        damage_flash = 15
        sfx_tone(0, 100, 8)
        sfx_noise(1, 6)
        if cam_shake then cam_shake(8) end
      end
      -- remove enemy
      local kx, ky = board_to_px(e.bx, e.by)
      add_particles(kx + CELL/2, ky + CELL/2, 6, 1)
      enemies[ei] = enemies[#enemies]
      enemies[#enemies] = nil

      if not attract_mode and lives <= 0 then
        if score > high_score then high_score = score end
        go("gameover")
        return
      end
    else
      ei = ei + 1
    end
  end

  -- Territory score bonus over time
  if not attract_mode and territory_count > 0 then
    territory_bonus_timer = territory_bonus_timer + 1
    if territory_bonus_timer >= TERRITORY_BONUS_INTERVAL then
      territory_bonus_timer = 0
      local bonus = territory_count * TERRITORY_BONUS_PER_CELL
      score = score + bonus
    end
  end

  update_particles()
  update_combo_texts()
end

---------- GAME STATE ----------
function game_draw()
  local scr = screen()

  -- damage flash effect
  if damage_flash > 0 and damage_flash % 4 < 2 then
    cls(scr, 1)
  else
    cls(scr, 0)
  end

  draw_board(scr)

  -- draw aim indicator
  draw_aim(scr)

  -- draw enemies
  for i = 1, #enemies do
    local e = enemies[i]
    local ex, ey = board_to_px(e.bx, e.by)
    local col = 1 - cell_color(e.bx, e.by)
    local fn = enemy_draw_fns[e.etype] or draw_pawn
    fn(scr, ex, ey, col)
    -- draw hp indicator for tanky enemies
    if e.hp > 1 then
      rectf(scr, ex+CELL/2-1, ey, 3, 2, col)
    end
  end

  -- draw shots
  for i = 1, #shots do
    local sh = shots[i]
    if sh.alive then
      -- shot head
      rectf(scr, floor(sh.x)-1, floor(sh.y)-1, 3, 3, 1)
      -- trail dots
      local tdx = -sh.dx / SHOT_SPEED
      local tdy = -sh.dy / SHOT_SPEED
      for t = 1, 3 do
        local tx = sh.x + tdx * t * 3
        local ty = sh.y + tdy * t * 3
        pix(scr, floor(tx), floor(ty), 1)
      end
      -- bounced shots have hollow center
      if sh.bounced then
        pix(scr, floor(sh.x), floor(sh.y), 0)
      end
    end
  end

  -- draw bishop
  local bsx, bsy = board_to_px(px, py)
  local bcol = 1 - cell_color(px, py)
  draw_bishop(scr, bsx, bsy, bcol)

  -- cursor around bishop
  local f = floor(frame()/6) % 2
  if f == 0 then
    rect(scr, bsx-1, bsy-1, CELL+2, CELL+2, bcol)
  end

  draw_particles(scr)
  draw_combo_texts(scr)
  draw_hud(scr)

  -- wave clear message
  if wave_active == false and wave_enemies_left <= 0 then
    local blink = floor(frame()/10) % 2 == 0
    if blink then
      text(scr, "WAVE " .. (wave_num-1) .. " CLEAR!", W/2, H/2, 1, ALIGN_CENTER)
    end
  end
end

function game_update()
  idle_timer = 0
  attract_mode = false

  if damage_flash > 0 then
    damage_flash = damage_flash - 1
  end

  -- player movement: DIAGONAL ONLY (like a true bishop)
  -- D-pad maps directly to diagonals:
  --   up    = up-left (NW)        up+right or right = up-right (NE)
  --   down  = down-right (SE)     down+left or left = down-left (SW)
  -- Single d-pad presses map to diagonal directions
  local moved = false
  local dx, dy = 0, 0

  local l = btn("left")
  local r = btn("right")
  local u = btn("up")
  local d = btn("down")

  -- Two-button combos for explicit diagonals
  if l and u then dx, dy = -1, -1       -- up-left
  elseif r and u then dx, dy = 1, -1    -- up-right
  elseif l and d then dx, dy = -1, 1    -- down-left
  elseif r and d then dx, dy = 1, 1     -- down-right
  -- Single d-pad presses also move diagonally
  elseif u then dx, dy = -1, -1         -- up -> up-left
  elseif r then dx, dy = 1, -1          -- right -> up-right
  elseif d then dx, dy = 1, 1           -- down -> down-right
  elseif l then dx, dy = -1, 1          -- left -> down-left
  end

  if dx ~= 0 and dy ~= 0 then
    if btnp("left") or btnp("right") or btnp("up") or btnp("down") then
      moved = true
    end
  end

  if moved then
    local nbx = clamp(px + dx, 0, 7)
    local nby = clamp(py + dy, 0, 7)
    if nbx ~= px or nby ~= py then
      px = nbx
      py = nby
      sfx_tone(3, 500, 1)
    end
  end

  -- touch input: tap to aim and fire
  if touch_start then
    local tx, ty = touch_start()
    if tx then
      -- determine which diagonal the touch is in relative to bishop
      local bsx, bsy = board_to_px(px, py)
      local bcx = bsx + CELL/2
      local bcy = bsy + CELL/2
      local tdx = tx - bcx
      local tdy = ty - bcy
      if abs(tdx) > 4 or abs(tdy) > 4 then
        -- pick closest diagonal
        local best = 1
        local best_dot = -999
        for di = 1, 4 do
          local dd = DIAGS[di]
          local dot = tdx * dd[1] + tdy * dd[2]
          if dot > best_dot then
            best_dot = dot
            best = di
          end
        end
        aim_dir = best
        fire_shot(aim_dir)
      end
    end
  end

  -- cycle aim with B
  if btnp("b") then
    aim_dir = aim_dir % 4 + 1
    sfx_tone(3, 600, 1)
  end

  -- fire with A
  if btnp("a") then
    fire_shot(aim_dir)
  end

  -- wave spawning
  if wave_active then
    wave_spawn_timer = wave_spawn_timer + 1
    if wave_spawn_timer >= wave_spawn_interval and wave_total_spawned < wave_max_enemies then
      wave_spawn_timer = 0
      wave_total_spawned = wave_total_spawned + 1

      -- determine enemy type based on wave
      local etype = 1  -- pawn
      if wave_num >= 3 and random() < 0.3 then
        etype = 2  -- knight
      end
      if wave_num >= 5 and random() < 0.2 then
        etype = 3  -- rook
      end
      spawn_enemy(etype)
    end

    -- check wave complete
    if wave_total_spawned >= wave_max_enemies and #enemies == 0 then
      wave_active = false
      -- wave clear bonus
      score = score + 50 * wave_num
      sfx_note(0, 60, 4)
      sfx_note(1, 64, 4)
      sfx_note(2, 67, 4)
    end
  else
    -- between waves, brief pause then next
    wave_spawn_timer = wave_spawn_timer + 1
    if wave_spawn_timer > 60 then
      wave_num = wave_num + 1
      start_wave()
    end
  end

  -- shared game logic
  update_game_logic()
end

---------- GAME OVER ----------
function gameover_init()
  idle_timer = 0
end

function gameover_draw()
  local scr = screen()
  cls(scr, 0)

  text(scr, "GAME OVER", W/2, 30, 1, ALIGN_CENTER)
  text(scr, "SCORE: " .. score, W/2, 50, 1, ALIGN_CENTER)
  text(scr, "WAVE: " .. wave_num, W/2, 62, 1, ALIGN_CENTER)

  if score >= high_score and score > 0 then
    text(scr, "NEW HIGH SCORE!", W/2, 76, 1, ALIGN_CENTER)
  else
    text(scr, "HI: " .. high_score, W/2, 76, 1, ALIGN_CENTER)
  end

  local blink = floor(frame()/20) % 2 == 0
  if blink then
    text(scr, "PRESS START", W/2, 95, 1, ALIGN_CENTER)
  end
end

function gameover_update()
  idle_timer = idle_timer + 1

  if btnp("start") or btnp("a") then
    idle_timer = 0
    go("title")
    return
  end

  if touch_start then
    local tx, ty = touch_start()
    if tx then
      idle_timer = 0
      go("title")
      return
    end
  end

  -- attract mode after idle on gameover too
  if idle_timer > ATTRACT_IDLE_FRAMES then
    attract_mode = true
    attract_timer = 0
    init_game()
    go("attract")
  end
end

---------- ENGINE CALLBACKS ----------
function _init()
  mode(1)
  high_score = 0
end

function _start()
  go("title")
end

---------- STATE REGISTRATION ----------
-- go("title") expects title_init, title_update, title_draw
-- go("game") expects game_init, game_update, game_draw
-- go("gameover") expects gameover_init, gameover_update, gameover_draw
-- go("attract") expects attract_init, attract_update, attract_draw

-- game_init is called by go("game")
function game_init()
  init_game()
end

-- attract_init is called by go("attract")
function attract_init()
  attract_mode = true
  attract_timer = 0
  attract_ai_timer = 0
  attract_ai_fire_timer = 0
  init_game()
end
