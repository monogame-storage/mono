-- Space Invaders (1-bit, 160x144)
-- Original-style: 5 rows x 11 cols of aliens, shields, UFO

local scr = screen()
local W = SCREEN_W
local H = SCREEN_H
local t = 0

-- ===== SPRITES (pixel art, drawn per frame) =====

-- Alien type 1 (squid) - 8x8, 2 frames
local alien1 = {
  {
    "..1..1..",
    "...11...",
    "..1111..",
    ".11..11.",
    "11111111",
    "1.1111.1",
    "1......1",
    "..1..1..",
  },
  {
    "..1..1..",
    "...11...",
    "..1111..",
    ".11..11.",
    "11111111",
    "1.1111.1",
    "1......1",
    ".1....1.",
  }
}

-- Alien type 2 (crab) - 11x8, 2 frames
local alien2 = {
  {
    "..1.....1..",
    "...1...1...",
    "..1111111..",
    ".11.111.11.",
    "11111111111",
    "1.1111111.1",
    "1.1.....1.1",
    "...11.11...",
  },
  {
    "..1.....1..",
    "1..1...1..1",
    "1.1111111.1",
    "111.111.111",
    "11111111111",
    ".1111111.1.",
    "..1.....1..",
    ".1.......1.",
  }
}

-- Alien type 3 (octopus) - 12x8, 2 frames
local alien3 = {
  {
    "...1111.....",
    ".11111111...",
    "111111111111",
    "111..11..111",
    "111111111111",
    "..111..111..",
    ".11..11..11.",
    "..11....11..",
  },
  {
    "...1111.....",
    ".11111111...",
    "111111111111",
    "111..11..111",
    "111111111111",
    "...11..11...",
    "..11.11.11..",
    "11........11",
  }
}

-- Player cannon - 13x8
local player_spr = {
  ".....11......",
  "....1111.....",
  "....1111.....",
  ".111111111...",
  "1111111111111",
  "1111111111111",
  "1111111111111",
  "1111111111111",
}

-- UFO - 16x7
local ufo_spr = {
  ".....111111.....",
  "...1111111111...",
  "..111111111111..",
  ".11.11.11.11.11.",
  "1111111111111111",
  "..111..111..111.",
  "...1....1....1..",
}

-- Shield - 22x16
local shield_spr = {
  "....11111111111111....",
  "..1111111111111111111.",
  ".111111111111111111111",
  "1111111111111111111111",
  "1111111111111111111111",
  "1111111111111111111111",
  "1111111111111111111111",
  "1111111111111111111111",
  "1111111111111111111111",
  "1111111111111111111111",
  "1111111111111111111111",
  "1111111111111111111111",
  "1111111111111111111111",
  "11111111....1111111111",
  "1111111......111111111",
  "1111111......111111111",
}

-- Draw sprite helper
local function draw_spr(spr, sx, sy, c)
  for row = 1, #spr do
    local line_str = spr[row]
    for col = 1, #line_str do
      if line_str:sub(col, col) == "1" then
        pix(scr, sx + col - 1, sy + row - 1, c)
      end
    end
  end
end

-- ===== GAME STATE =====

local STATE_PLAY = 0
local STATE_DEAD = 1
local STATE_WIN  = 2
local STATE_TITLE = 3
local state = STATE_TITLE

-- Player
local px, py
local plives
local pbullet  -- {x, y} or nil
local pscore
local phiscore = 0

-- Aliens
local aliens = {}      -- {x, y, type, alive}
local alien_dir        -- 1 or -1
local alien_speed
local alien_move_timer
local alien_move_interval
local alien_frame      -- animation frame (0 or 1)
local alien_bullets = {} -- {x, y}
local alien_shoot_timer

-- UFO
local ufo = nil  -- {x, dir} or nil
local ufo_timer

-- Shields
local shield_hp = {}  -- shield_hp[i][row][col] = true/false

-- Explosion
local explosions = {} -- {x, y, timer}

local function init_shields()
  shield_hp = {}
  for i = 1, 4 do
    shield_hp[i] = {}
    for row = 1, #shield_spr do
      shield_hp[i][row] = {}
      for col = 1, #shield_spr[1] do
        shield_hp[i][row][col] = (shield_spr[row]:sub(col, col) == "1")
      end
    end
  end
end

local function init_aliens()
  aliens = {}
  for row = 0, 4 do
    for col = 0, 10 do
      local atype
      if row == 0 then atype = 1
      elseif row <= 2 then atype = 2
      else atype = 3 end
      aliens[#aliens + 1] = {
        x = 10 + col * 13,
        y = 20 + row * 12,
        type = atype,
        alive = true
      }
    end
  end
  alien_dir = 1
  alien_speed = 1
  alien_move_timer = 0
  alien_move_interval = 20
  alien_frame = 0
  alien_bullets = {}
  alien_shoot_timer = 0
end

local function reset_game()
  px = (W - 13) / 2
  py = H - 16
  plives = 3
  pbullet = nil
  pscore = 0
  ufo = nil
  ufo_timer = 0
  explosions = {}
  init_aliens()
  init_shields()
  state = STATE_PLAY
end

-- ===== UPDATE =====

local function count_alive()
  local n = 0
  for i = 1, #aliens do
    if aliens[i].alive then n = n + 1 end
  end
  return n
end

local function update_play()
  t = t + 1

  -- Player movement
  if btn("left") and px > 2 then px = px - 1.5 end
  if btn("right") and px < W - 15 then px = px + 1.5 end

  -- Player shoot
  if btnp("a") and pbullet == nil then
    pbullet = { x = px + 6, y = py - 1 }
  end

  -- Player bullet
  if pbullet then
    pbullet.y = pbullet.y - 3
    if pbullet.y < 0 then pbullet = nil end
  end

  -- Alien movement
  alien_move_timer = alien_move_timer + 1
  if alien_move_timer >= alien_move_interval then
    alien_move_timer = 0
    alien_frame = 1 - alien_frame

    -- Check bounds
    local min_x, max_x = 999, -999
    for i = 1, #aliens do
      local a = aliens[i]
      if a.alive then
        if a.x < min_x then min_x = a.x end
        local aw = (a.type == 1) and 8 or ((a.type == 2) and 11 or 12)
        if a.x + aw > max_x then max_x = a.x + aw end
      end
    end

    local drop = false
    if alien_dir == 1 and max_x >= W - 4 then drop = true end
    if alien_dir == -1 and min_x <= 4 then drop = true end

    if drop then
      alien_dir = -alien_dir
      for i = 1, #aliens do
        if aliens[i].alive then aliens[i].y = aliens[i].y + 4 end
      end
    else
      for i = 1, #aliens do
        if aliens[i].alive then
          aliens[i].x = aliens[i].x + alien_dir * 2
        end
      end
    end

    -- Speed up as fewer aliens remain
    local alive = count_alive()
    if alive <= 5 then alien_move_interval = 3
    elseif alive <= 10 then alien_move_interval = 6
    elseif alive <= 20 then alien_move_interval = 10
    elseif alive <= 35 then alien_move_interval = 15
    else alien_move_interval = 20 end
  end

  -- Player bullet vs aliens
  if pbullet then
    for i = 1, #aliens do
      local a = aliens[i]
      if a.alive then
        local aw = (a.type == 1) and 8 or ((a.type == 2) and 11 or 12)
        if pbullet.x >= a.x and pbullet.x <= a.x + aw
          and pbullet.y >= a.y and pbullet.y <= a.y + 8 then
          a.alive = false
          explosions[#explosions + 1] = { x = a.x, y = a.y, timer = 10 }
          if a.type == 1 then pscore = pscore + 30
          elseif a.type == 2 then pscore = pscore + 20
          else pscore = pscore + 10 end
          pbullet = nil
          break
        end
      end
    end
  end

  -- Alien shooting
  alien_shoot_timer = alien_shoot_timer + 1
  if alien_shoot_timer >= 30 then
    alien_shoot_timer = 0
    -- Pick a random alive alien from bottom rows
    local shooters = {}
    for i = 1, #aliens do
      if aliens[i].alive then
        -- Check if this is the bottommost in its column
        local col = math.floor((aliens[i].x - 10) / 13 + 0.5)
        local dominated = false
        for j = 1, #aliens do
          if aliens[j].alive and j ~= i then
            local jcol = math.floor((aliens[j].x - 10) / 13 + 0.5)
            if jcol == col and aliens[j].y > aliens[i].y then
              dominated = true
              break
            end
          end
        end
        if not dominated then shooters[#shooters + 1] = aliens[i] end
      end
    end
    if #shooters > 0 then
      local s = shooters[math.random(#shooters)]
      local aw = (s.type == 1) and 4 or ((s.type == 2) and 5 or 6)
      alien_bullets[#alien_bullets + 1] = { x = s.x + aw, y = s.y + 8 }
    end
  end

  -- Alien bullets
  for i = #alien_bullets, 1, -1 do
    local b = alien_bullets[i]
    b.y = b.y + 1.5
    if b.y > H then
      table.remove(alien_bullets, i)
    -- Hit player
    elseif b.x >= px and b.x <= px + 13 and b.y >= py and b.y <= py + 8 then
      table.remove(alien_bullets, i)
      plives = plives - 1
      explosions[#explosions + 1] = { x = px, y = py, timer = 20 }
      if plives <= 0 then
        if pscore > phiscore then phiscore = pscore end
        state = STATE_DEAD
      end
    end
  end

  -- Player bullet vs shields
  if pbullet then
    for si = 1, 4 do
      local sx = 8 + (si - 1) * 38
      local sy = H - 32
      local lx = math.floor(pbullet.x - sx + 1)
      local ly = math.floor(pbullet.y - sy + 1)
      if lx >= 1 and lx <= #shield_spr[1] and ly >= 1 and ly <= #shield_spr then
        if shield_hp[si][ly][lx] then
          shield_hp[si][ly][lx] = false
          pbullet = nil
          break
        end
      end
    end
  end

  -- Alien bullets vs shields
  for bi = #alien_bullets, 1, -1 do
    local b = alien_bullets[bi]
    local hit = false
    for si = 1, 4 do
      local sx = 8 + (si - 1) * 38
      local sy = H - 32
      local lx = math.floor(b.x - sx + 1)
      local ly = math.floor(b.y - sy + 1)
      if lx >= 1 and lx <= #shield_spr[1] and ly >= 1 and ly <= #shield_spr then
        if shield_hp[si][ly][lx] then
          -- Destroy a small area
          for dy = -1, 1 do
            for dx = -1, 1 do
              local ry, rx = ly + dy, lx + dx
              if ry >= 1 and ry <= #shield_spr and rx >= 1 and rx <= #shield_spr[1] then
                shield_hp[si][ry][rx] = false
              end
            end
          end
          hit = true
          break
        end
      end
    end
    if hit then table.remove(alien_bullets, bi) end
  end

  -- UFO
  ufo_timer = ufo_timer + 1
  if ufo == nil and ufo_timer > 600 then
    ufo_timer = 0
    local dir = (math.random(2) == 1) and 1 or -1
    ufo = { x = (dir == 1) and -16 or W, dir = dir }
  end
  if ufo then
    ufo.x = ufo.x + ufo.dir * 0.8
    if ufo.x < -20 or ufo.x > W + 20 then ufo = nil end
    -- Player bullet vs UFO
    if pbullet and ufo then
      if pbullet.x >= ufo.x and pbullet.x <= ufo.x + 16
        and pbullet.y >= 10 and pbullet.y <= 17 then
        pscore = pscore + 100
        explosions[#explosions + 1] = { x = ufo.x, y = 10, timer = 15 }
        ufo = nil
        pbullet = nil
      end
    end
  end

  -- Explosions
  for i = #explosions, 1, -1 do
    explosions[i].timer = explosions[i].timer - 1
    if explosions[i].timer <= 0 then table.remove(explosions, i) end
  end

  -- Aliens reached bottom
  for i = 1, #aliens do
    if aliens[i].alive and aliens[i].y + 8 >= py then
      if pscore > phiscore then phiscore = pscore end
      state = STATE_DEAD
    end
  end

  -- Win check
  if count_alive() == 0 then
    state = STATE_WIN
  end
end

-- ===== DRAW =====

local function draw_play()
  cls(scr, 0)

  -- Score
  text(scr, "SCORE " .. pscore, 2, 2, 1)
  text(scr, "HI " .. phiscore, W - 45, 2, 1)

  -- Lives
  for i = 1, plives - 1 do
    draw_spr(player_spr, 2 + (i - 1) * 16, H - 8, 1)
  end

  -- Aliens
  for i = 1, #aliens do
    local a = aliens[i]
    if a.alive then
      local spr
      local f = alien_frame + 1
      if a.type == 1 then spr = alien1[f]
      elseif a.type == 2 then spr = alien2[f]
      else spr = alien3[f] end
      draw_spr(spr, a.x, a.y, 1)
    end
  end

  -- Player
  draw_spr(player_spr, math.floor(px), math.floor(py), 1)

  -- Player bullet
  if pbullet then
    rectf(scr, math.floor(pbullet.x), math.floor(pbullet.y), 1, 4, 1)
  end

  -- Alien bullets
  for i = 1, #alien_bullets do
    local b = alien_bullets[i]
    -- Zigzag bullet pattern
    local bx = math.floor(b.x)
    local by = math.floor(b.y)
    pix(scr, bx, by, 1)
    pix(scr, bx, by + 1, 1)
    pix(scr, bx + ((by % 4 < 2) and 1 or -1), by + 2, 1)
    pix(scr, bx, by + 3, 1)
  end

  -- Shields
  for si = 1, 4 do
    local sx = 8 + (si - 1) * 38
    local sy = H - 32
    for row = 1, #shield_spr do
      for col = 1, #shield_spr[1] do
        if shield_hp[si][row][col] then
          pix(scr, sx + col - 1, sy + row - 1, 1)
        end
      end
    end
  end

  -- UFO
  if ufo then
    draw_spr(ufo_spr, math.floor(ufo.x), 10, 1)
  end

  -- Explosions
  for i = 1, #explosions do
    local e = explosions[i]
    local ex = math.floor(e.x)
    local ey = math.floor(e.y)
    -- Pixel burst
    for j = 1, 6 do
      local dx = math.random(-5, 5)
      local dy = math.random(-5, 5)
      pix(scr, ex + 4 + dx, ey + 4 + dy, 1)
    end
  end

  -- Ground line
  line(scr, 0, H - 9, W - 1, H - 9, 1)
end

-- ===== TITLE / GAME OVER =====

local title_blink = 0

local function draw_title()
  cls(scr, 0)
  title_blink = title_blink + 1

  text(scr, "SPACE INVADERS", 20, 20, 1)

  -- Show alien types with scores
  draw_spr(ufo_spr, 40, 45, 1)
  text(scr, "= ?  PTS", 60, 47, 1)
  draw_spr(alien1[1], 44, 60, 1)
  text(scr, "= 30 PTS", 60, 62, 1)
  draw_spr(alien2[1], 42, 75, 1)
  text(scr, "= 20 PTS", 60, 77, 1)
  draw_spr(alien3[1], 41, 90, 1)
  text(scr, "= 10 PTS", 60, 92, 1)

  if title_blink % 40 < 28 then
    text(scr, "PRESS START", 30, 120, 1)
  end
end

local function draw_dead()
  cls(scr, 0)
  text(scr, "GAME OVER", 40, 50, 1)
  text(scr, "SCORE " .. pscore, 40, 65, 1)
  text(scr, "HI " .. phiscore, 40, 80, 1)
  title_blink = title_blink + 1
  if title_blink % 40 < 28 then
    text(scr, "PRESS START", 30, 110, 1)
  end
end

local function draw_win()
  cls(scr, 0)
  text(scr, "YOU WIN!", 45, 50, 1)
  text(scr, "SCORE " .. pscore, 40, 65, 1)
  title_blink = title_blink + 1
  if title_blink % 40 < 28 then
    text(scr, "PRESS START", 30, 110, 1)
  end
end

-- ===== CALLBACKS =====

function _init()
  state = STATE_TITLE
  title_blink = 0
end

function _update()
  if state == STATE_TITLE or state == STATE_DEAD or state == STATE_WIN then
    if btnp("start") then
      reset_game()
    end
  elseif state == STATE_PLAY then
    update_play()
  end
end

function _draw()
  if state == STATE_TITLE then draw_title()
  elseif state == STATE_PLAY then draw_play()
  elseif state == STATE_DEAD then draw_dead()
  elseif state == STATE_WIN then draw_win()
  end
end
