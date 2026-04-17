-- SHADOW LEAP
-- A precision platformer for Mono fantasy console
-- 160x120, 16 grayscale, 30fps

----------------------------------------------------------------
-- CONSTANTS (global)
----------------------------------------------------------------
W = 160
H = 120
TILE = 8
COLS = W / TILE    -- 20
ROWS = H / TILE    -- 15

-- Physics constants
GRAV       = 0.35
MAX_FALL   = 4.0
RUN_ACCEL  = 0.6
RUN_DECEL  = 0.45
MAX_RUN    = 1.8
JUMP_VEL   = -3.6
JUMP_CUT   = -1.2
COYOTE     = 5
JUMP_BUF   = 6
DASH_VEL   = 4.0
DASH_DUR   = 6
DASH_CD    = 20
WALL_SLIDE = 0.6
WALL_JUMP_X = 2.5
WALL_JUMP_Y = -3.2

-- Enemy types
E_PATROL = 1
E_JUMPER = 2
E_FLYER  = 3

----------------------------------------------------------------
-- GLOBAL GAME STATE
----------------------------------------------------------------
G = {
  score = 0,
  lives = 3,
  cur_level = 1,
  coins_collected = 0,
  total_coins = 0,
  level_timer = 0,
  state_timer = 0,
}

-- Player
P = {}

-- Level data structures
tiles = {}
enemies = {}
coins = {}
springs = {}
exit_pos = {x=0, y=0}
spawn_x = 16
spawn_y = 96
particles = {}
bg_stars = {}

----------------------------------------------------------------
-- LEVEL DEFINITIONS
----------------------------------------------------------------
level_data = {}

level_data[1] = {
  name = "FIRST STEPS",
  map = {
    "####################",
    "#..................#",
    "#..................#",
    "#.......oo.........#",
    "#......####........#",
    "#..................#",
    "#..o...........o.E.#",
    "#.###.........######",
    "#..................#",
    "#..........o.......#",
    "#.....o...###..1...#",
    "#P...###...........#",
    "#.####.............#",
    "####..........######",
    "####################",
  }
}

level_data[2] = {
  name = "WALL RUNNER",
  map = {
    "####################",
    "#...........o..o.E.#",
    "#..........o..####.#",
    "#.........####.....#",
    "#..o...............#",
    "#.###..............#",
    "#.......#..........#",
    "#.......#...o......#",
    "#.......#..###..1..#",
    "#..o....#..........#",
    "#.###...#....###...#",
    "#.......#..........#",
    "#P......#....^^^^^.#",
    "#.####..##.#########",
    "####################",
  }
}

level_data[3] = {
  name = "DASH CANYON",
  map = {
    "####################",
    "#...............o.E#",
    "#................###",
    "#.....o............#",
    "#....###...........#",
    "#..........o.......#",
    "#.........###......#",
    "#...^..............#",
    "#..###....1........#",
    "#.........###..^^..#",
    "#.....o........##..#",
    "#....###.......2...#",
    "#P.............##..#",
    "#.####..############",
    "####################",
  }
}

level_data[4] = {
  name = "SKY GARDEN",
  map = {
    "####################",
    "#.o...........o.E..#",
    "#.##..........###..#",
    "#..................#",
    "#......3...........#",
    "#...........##.....#",
    "#....##............#",
    "#..........3.......#",
    "#.......##...##....#",
    "#.S..o.............#",
    "#.##..##..o..S.....#",
    "#.........##.##..1.#",
    "#P..^^.........^^..#",
    "#.####..############",
    "####################",
  }
}

level_data[5] = {
  name = "THE GAUNTLET",
  map = {
    "####################",
    "#...........o.o..E.#",
    "#............^.###.#",
    "#..3.......###.....#",
    "#..........^^......#",
    "#.......o..##......#",
    "#.....####.....3...#",
    "#..^...........##..#",
    "#.###..1...........#",
    "#.........^^^..o...#",
    "#..o......###.###..#",
    "#.###..2...........#",
    "#P...........^^..1.#",
    "#.####..############",
    "####################",
  }
}

----------------------------------------------------------------
-- PLAYER RESET
----------------------------------------------------------------
function reset_player(sx, sy)
  P.x = sx
  P.y = sy
  P.vx = 0
  P.vy = 0
  P.w = 5
  P.h = 7
  P.on_ground = false
  P.on_wall = 0
  P.coyote = 0
  P.jump_buf = 0
  P.facing = 1
  P.dashing = 0
  P.dash_cd = 0
  P.dash_dir = 1
  P.alive = true
  P.anim = 0
  P.squash = 0
  P.stretch = 0
  P.invuln = 0
end

----------------------------------------------------------------
-- PARTICLES
----------------------------------------------------------------
function spawn_particle(x, y, vx, vy, life, color)
  table.insert(particles, {
    x=x, y=y, vx=vx, vy=vy, life=life, max_life=life, c=color
  })
end

function spawn_burst(x, y, count, speed, color)
  for i = 1, count do
    local a = math.random() * math.pi * 2
    local s = math.random() * speed
    spawn_particle(x, y, math.cos(a)*s, math.sin(a)*s, 10 + math.random(10), color)
  end
end

function spawn_dust(x, y, dir)
  for i = 1, 3 do
    spawn_particle(x, y+2, dir * (0.3 + math.random() * 0.5), -(0.2 + math.random() * 0.5), 6 + math.random(4), 8)
  end
end

function update_particles()
  for i = #particles, 1, -1 do
    local p = particles[i]
    p.x = p.x + p.vx
    p.y = p.y + p.vy
    p.vy = p.vy + 0.05
    p.vx = p.vx * 0.95
    p.life = p.life - 1
    if p.life <= 0 then
      table.remove(particles, i)
    end
  end
end

function draw_particles()
  local scr = screen()
  for _, p in ipairs(particles) do
    local alpha = p.life / p.max_life
    local c = math.max(1, math.floor(p.c * alpha))
    pix(scr, math.floor(p.x), math.floor(p.y), c)
  end
end

----------------------------------------------------------------
-- SOUND EFFECTS
----------------------------------------------------------------
function sfx_jump()
  wave(0, "square")
  tone(0, 300, 500, 0.08)
end

function sfx_land()
  wave(1, "triangle")
  tone(1, 120, 60, 0.05)
end

function sfx_dash()
  wave(0, "sawtooth")
  tone(0, 200, 400, 0.06)
end

function sfx_coin()
  wave(0, "sine")
  tone(0, 600, 900, 0.06)
  wave(1, "sine")
  tone(1, 900, 1200, 0.06)
end

function sfx_spring()
  wave(0, "square")
  tone(0, 200, 800, 0.1)
end

function sfx_die()
  wave(0, "sawtooth")
  tone(0, 400, 80, 0.3)
  noise(1, 0.15)
end

function sfx_exit()
  wave(0, "sine")
  tone(0, 400, 800, 0.15)
  wave(1, "sine")
  tone(1, 600, 1200, 0.15)
end

function sfx_enemy_die()
  wave(0, "square")
  tone(0, 300, 100, 0.08)
  noise(1, 0.05)
end

function sfx_menu_select()
  wave(0, "sine")
  tone(0, 500, 700, 0.06)
end

function sfx_gameover()
  wave(0, "sawtooth")
  tone(0, 300, 60, 0.5)
  wave(1, "triangle")
  tone(1, 200, 40, 0.5)
end

function sfx_win_fanfare()
  wave(0, "square")
  tone(0, 400, 800, 0.2)
  wave(1, "sine")
  tone(1, 600, 1200, 0.2)
end

function sfx_wall_slide()
  noise(0, 0.03)
end

----------------------------------------------------------------
-- COLLISION HELPERS
----------------------------------------------------------------
function tile_at(px, py)
  local col = math.floor(px / TILE) + 1
  local row = math.floor(py / TILE) + 1
  if col < 1 or col > COLS or row < 1 or row > ROWS then return 1 end
  return tiles[row][col]
end

function solid_at(px, py)
  return tile_at(px, py) == 1
end

function spike_at(px, py)
  return tile_at(px, py) == 2
end

function check_solid(x, y, w, h)
  return solid_at(x, y) or solid_at(x+w-1, y) or
         solid_at(x, y+h-1) or solid_at(x+w-1, y+h-1) or
         solid_at(x+w/2, y) or solid_at(x+w/2, y+h-1) or
         solid_at(x, y+h/2) or solid_at(x+w-1, y+h/2)
end

function check_spikes(x, y, w, h)
  return spike_at(x+1, y+h-1) or spike_at(x+w-2, y+h-1) or
         spike_at(x+w/2, y+h-1) or
         spike_at(x+1, y) or spike_at(x+w-2, y) or
         spike_at(x, y+h/2) or spike_at(x+w-1, y+h/2)
end

----------------------------------------------------------------
-- LEVEL LOADING
----------------------------------------------------------------
function load_level(num)
  tiles = {}
  enemies = {}
  coins = {}
  springs = {}
  particles = {}
  G.coins_collected = 0
  G.total_coins = 0
  G.level_timer = 0

  local data = level_data[num]
  if not data then return end

  for row = 1, ROWS do
    tiles[row] = {}
    local line_str = data.map[row] or ""
    for col = 1, COLS do
      local ch = line_str:sub(col, col)
      local t = 0

      if ch == "#" then
        t = 1
      elseif ch == "^" then
        t = 2
      elseif ch == "o" then
        G.total_coins = G.total_coins + 1
        table.insert(coins, {
          x = (col-1)*TILE + TILE/2,
          y = (row-1)*TILE + TILE/2,
          collected = false,
          anim = math.random() * math.pi * 2
        })
      elseif ch == "S" then
        table.insert(springs, {
          x = (col-1)*TILE,
          y = (row-1)*TILE,
          anim = 0
        })
      elseif ch == "P" then
        spawn_x = (col-1)*TILE + 2
        spawn_y = (row-1)*TILE
      elseif ch == "E" then
        exit_pos.x = (col-1)*TILE
        exit_pos.y = (row-1)*TILE
      elseif ch == "1" then
        table.insert(enemies, {
          type = E_PATROL,
          x = (col-1)*TILE + 1,
          y = (row-1)*TILE + 1,
          vx = 0.5, vy = 0,
          w = 6, h = 7,
          alive = true, dir = 1, anim = 0,
          start_x = (col-1)*TILE + 1
        })
      elseif ch == "2" then
        table.insert(enemies, {
          type = E_JUMPER,
          x = (col-1)*TILE + 1,
          y = (row-1)*TILE + 1,
          vx = 0.3, vy = 0,
          w = 6, h = 7,
          alive = true, dir = 1, anim = 0,
          jump_timer = 0,
          start_x = (col-1)*TILE + 1
        })
      elseif ch == "3" then
        table.insert(enemies, {
          type = E_FLYER,
          x = (col-1)*TILE + 1,
          y = (row-1)*TILE + 2,
          vx = 0, vy = 0,
          w = 7, h = 5,
          alive = true, dir = 1, anim = 0,
          base_y = (row-1)*TILE + 2,
          start_x = (col-1)*TILE + 1
        })
      end

      tiles[row][col] = t
    end
  end

  reset_player(spawn_x, spawn_y)
end

----------------------------------------------------------------
-- BACKGROUND
----------------------------------------------------------------
function init_bg()
  bg_stars = {}
  for i = 1, 20 do
    table.insert(bg_stars, {
      x = math.random(0, W-1),
      y = math.random(10, H-1),
      c = math.random(2, 4),
      speed = math.random() * 0.3 + 0.05
    })
  end
end

function draw_bg()
  local scr = screen()
  for _, s in ipairs(bg_stars) do
    local blink = math.sin(frame() * s.speed + s.x) > 0
    if blink then
      pix(scr, s.x, s.y, s.c)
    end
  end
end

----------------------------------------------------------------
-- DRAWING HELPERS
----------------------------------------------------------------
function draw_tile(col, row, t)
  local scr = screen()
  local x = (col-1) * TILE
  local y = (row-1) * TILE

  if t == 1 then
    rectf(scr, x, y, TILE, TILE, 6)
    line(scr, x, y, x+TILE-1, y, 8)
    line(scr, x, y+TILE-1, x+TILE-1, y+TILE-1, 4)
    pix(scr, x, y+1, 7)
    pix(scr, x, y+2, 7)
    if (col + row) % 3 == 0 then
      pix(scr, x+3, y+3, 5)
      pix(scr, x+5, y+5, 5)
    end
  elseif t == 2 then
    for i = 0, 3 do
      local sx = x + i * 2
      pix(scr, sx+1, y+2, 15)
      pix(scr, sx, y+4, 12)
      pix(scr, sx+1, y+4, 12)
      pix(scr, sx+1, y+3, 14)
      line(scr, sx, y+5, sx+1, y+5, 10)
      if frame() % 20 < 10 then
        pix(scr, sx+1, y+1, 15)
      end
    end
    rectf(scr, x, y+6, TILE, 2, 6)
  end
end

function draw_player()
  if not P.alive then return end
  if P.invuln > 0 and P.anim % 4 < 2 then return end

  local scr = screen()
  local px = math.floor(P.x)
  local py = math.floor(P.y)
  local w = P.w
  local h = P.h

  if P.squash > 0 then
    h = h - 2; w = w + 2; py = py + 2; px = px - 1
  elseif P.stretch > 0 then
    h = h + 2; w = w - 1; py = py - 2
  end

  if P.dashing > 0 then
    rectf(scr, px, py, w, h, 15)
    rectf(scr, px - P.dash_dir * 4, py, w, h, 8)
    return
  end

  rectf(scr, px, py, w, h, 14)
  rectf(scr, px, py, w, 3, 15)
  local eye_x = P.facing > 0 and (px + w - 2) or (px + 1)
  pix(scr, eye_x, py + 1, 0)

  if P.on_ground and math.abs(P.vx) > 0.3 then
    local foot = math.floor(P.anim / 4) % 2
    if foot == 0 then
      pix(scr, px + 1, py + h, 10)
    else
      pix(scr, px + w - 2, py + h, 10)
    end
  end

  if P.on_wall ~= 0 then
    local wx = P.on_wall > 0 and (px + w) or (px - 1)
    for i = 0, 2 do
      pix(scr, wx, py + 2 + i, 10)
    end
  end
end

function draw_enemy(e)
  if not e.alive then return end
  local scr = screen()
  local ex = math.floor(e.x)
  local ey = math.floor(e.y)

  if e.type == E_PATROL then
    rectf(scr, ex, ey, e.w, e.h, 10)
    rectf(scr, ex+1, ey+1, e.w-2, 2, 12)
    local eye_off = e.dir > 0 and (e.w - 2) or 1
    pix(scr, ex + eye_off, ey + 2, 0)
    local f = math.floor(e.anim / 6) % 2
    pix(scr, ex + 1 + f, ey + e.h, 8)
    pix(scr, ex + e.w - 2 - f, ey + e.h, 8)
  elseif e.type == E_JUMPER then
    rectf(scr, ex, ey + 2, e.w, e.h - 2, 11)
    rectf(scr, ex + 1, ey, e.w - 2, 3, 13)
    pix(scr, ex + 3, ey - 1, 13)
    pix(scr, ex + 2, ey + 3, 0)
    pix(scr, ex + e.w - 3, ey + 3, 0)
  elseif e.type == E_FLYER then
    local bob = math.sin(e.anim * 0.15)
    ey = ey + math.floor(bob)
    rectf(scr, ex + 1, ey + 1, e.w - 2, e.h - 2, 9)
    local wing = math.floor(e.anim / 5) % 2
    pix(scr, ex, ey + 1 + wing, 11)
    pix(scr, ex + e.w - 1, ey + 1 + wing, 11)
    pix(scr, ex, ey + 2 + wing, 11)
    pix(scr, ex + e.w - 1, ey + 2 + wing, 11)
    pix(scr, ex + 3, ey + 2, 15)
  end
end

function draw_coin_obj(c)
  if c.collected then return end
  local scr = screen()
  c.anim = c.anim + 0.08
  local cx = math.floor(c.x)
  local cy = math.floor(c.y)
  local r = 2
  circf(scr, cx, cy, r + 1, 4)
  circf(scr, cx, cy, r, 13)
  pix(scr, cx, cy, 15)
  if math.floor(c.anim * 10) % 7 == 0 then
    pix(scr, cx + 2, cy - 2, 15)
  end
end

function draw_spring(s)
  local scr = screen()
  local x = s.x
  local y = s.y
  if s.anim > 0 then
    rectf(scr, x, y + 4, TILE, 4, 13)
    rectf(scr, x + 1, y + 3, TILE - 2, 2, 15)
  else
    rectf(scr, x, y + 2, TILE, 6, 10)
    rectf(scr, x + 1, y + 1, TILE - 2, 2, 13)
    rectf(scr, x + 2, y, TILE - 4, 2, 15)
    line(scr, x + 1, y + 4, x + 3, y + 6, 8)
    line(scr, x + 3, y + 4, x + 5, y + 6, 8)
    line(scr, x + 5, y + 4, x + 7, y + 6, 8)
  end
end

function draw_exit_obj()
  local scr = screen()
  local x = exit_pos.x
  local y = exit_pos.y
  local t = frame() * 0.1
  local c = 10 + math.floor(math.sin(t * 0.5) * 3)
  if c < 1 then c = 1 end
  if c > 15 then c = 15 end
  rectf(scr, x, y, TILE, TILE, c)
  rect(scr, x, y, TILE, TILE, 15)
  local ay = y - 3 + math.floor(math.sin(t * 2) * 2)
  pix(scr, x + 3, ay, 15)
  pix(scr, x + 4, ay, 15)
  pix(scr, x + 2, ay + 1, 15)
  pix(scr, x + 5, ay + 1, 15)
end

function draw_hud()
  local scr = screen()
  rectf(scr, 0, 0, W, 9, 1)
  text(scr, "SC:" .. G.score, 2, 1, 12)
  -- Lives shown as small character icons
  for i = 1, G.lives do
    rectf(scr, 58 + (i-1) * 7, 2, 4, 5, 14)
    rectf(scr, 58 + (i-1) * 7, 2, 4, 2, 15)
  end
  text(scr, G.coins_collected .. "/" .. G.total_coins, 90, 1, 13)
  text(scr, "L" .. G.cur_level, 130, 1, 10)
  -- Dash meter with ready indicator
  if P.dash_cd > 0 then
    local bar_w = math.floor((DASH_CD - P.dash_cd) / DASH_CD * 10)
    rectf(scr, 148, 2, 10, 3, 3)
    rectf(scr, 148, 2, bar_w, 3, 12)
  else
    local flash = math.floor(frame() / 8) % 2 == 0 and 15 or 12
    rectf(scr, 148, 2, 10, 3, flash)
  end
end

function draw_level()
  local scr = screen()
  cls(scr, 0)
  draw_bg()
  for row = 1, ROWS do
    for col = 1, COLS do
      local t = tiles[row] and tiles[row][col] or 0
      if t > 0 then
        draw_tile(col, row, t)
      end
    end
  end
  for _, s in ipairs(springs) do draw_spring(s) end
  draw_exit_obj()
  for _, c in ipairs(coins) do draw_coin_obj(c) end
  for _, e in ipairs(enemies) do draw_enemy(e) end
  draw_player()
  draw_particles()
  draw_hud()
end

----------------------------------------------------------------
-- ENGINE ENTRY POINTS
----------------------------------------------------------------
function _init()
  mode(4)
end

function _start()
  init_bg()
  G.score = 0
  G.lives = 3
  G.cur_level = 1
  go("title")
end

function _update()
end

function _draw()
  local scr = screen()
  cls(scr, 0)
end
