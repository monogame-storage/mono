-- Bubble Bobble Fan Game
-- Pop bubbles to rescue trapped creatures!
-- Skull whale = danger, costs a life

local scr = screen()
local CX = math.floor(SCREEN_W / 2)
local CY = math.floor(SCREEN_H / 2)

-- constants
local LIVES_MAX = 3
local SPAWN_INIT = 28
local SPAWN_MIN = 10
local SPEED_INIT = 0.4
local SPEED_MAX = 1.8
local BUBBLE_R = 11
local HIT_R = BUBBLE_R + 3

-- mob types
local MOB_FISH = 1
local MOB_CRAB = 2
local MOB_BIRD = 3
local MOB_SKULL = 4
local MOB_GOLD  = 5

local MOB_POINTS = { 10, 20, 30, 0, 100 }

-- ascending combo notes (pop SFX)
local COMBO_NOTES = { "C5", "E5", "G5", "B5", "C6", "E6", "G6", "B6" }

-- state machine
local STATE_TITLE = 0
local STATE_PLAY = 1
local STATE_OVER = 2
local state

local bubbles, particles, freed_mobs
local score, best, lives
local spawn_timer, spawn_rate, bubble_speed
local combo_text, combo_timer, combo_count
local title_bubbles
local over_cooldown
local cursor                 -- {x,y} keyboard crosshair
local keyboard_mode          -- becomes true once an arrow key has been pressed
local kb_virtual_touch       -- transient flag: when true, treat A press as a touch at cursor

-- pixel art mob sprites (scaled up ~7x7)

local function draw_fish(x, y, c)
  -- body (7x5 fish facing right)
  rectf(scr, x - 2, y - 2, 5, 5, c)
  -- tail
  pix(scr, x - 3, y - 2, c)
  pix(scr, x - 4, y - 3, c)
  pix(scr, x - 3, y + 2, c)
  pix(scr, x - 4, y + 3, c)
  pix(scr, x - 3, y, c)
  -- nose
  pix(scr, x + 3, y - 1, c)
  pix(scr, x + 3, y, c)
  pix(scr, x + 3, y + 1, c)
  pix(scr, x + 4, y, c)
  -- fin top
  pix(scr, x - 1, y - 3, c)
  pix(scr, x, y - 3, c)
  -- fin bottom
  pix(scr, x, y + 3, c)
  -- eye
  rectf(scr, x + 1, y - 1, 2, 2, 0)
  pix(scr, x + 2, y - 1, 15)
end

local function draw_crab(x, y, c)
  -- body
  rectf(scr, x - 3, y - 1, 7, 4, c)
  rectf(scr, x - 2, y - 2, 5, 1, c)
  -- claws (left)
  pix(scr, x - 4, y - 2, c)
  pix(scr, x - 5, y - 3, c)
  pix(scr, x - 4, y - 3, c)
  pix(scr, x - 5, y - 2, c)
  -- claws (right)
  pix(scr, x + 4, y - 2, c)
  pix(scr, x + 5, y - 3, c)
  pix(scr, x + 4, y - 3, c)
  pix(scr, x + 5, y - 2, c)
  -- legs
  pix(scr, x - 3, y + 3, c)
  pix(scr, x - 1, y + 3, c)
  pix(scr, x + 1, y + 3, c)
  pix(scr, x + 3, y + 3, c)
  pix(scr, x - 3, y + 4, c)
  pix(scr, x + 3, y + 4, c)
  -- eyes
  rectf(scr, x - 2, y - 1, 2, 2, 0)
  pix(scr, x - 1, y - 1, 15)
  rectf(scr, x + 1, y - 1, 2, 2, 0)
  pix(scr, x + 2, y - 1, 15)
end

local function draw_bird(x, y, c)
  -- body
  rectf(scr, x - 2, y - 1, 5, 3, c)
  -- head
  rectf(scr, x + 2, y - 2, 3, 3, c)
  -- beak
  pix(scr, x + 5, y - 1, 12)
  pix(scr, x + 5, y, 12)
  -- wings (spread)
  pix(scr, x - 3, y - 2, c)
  pix(scr, x - 4, y - 3, c)
  pix(scr, x - 5, y - 4, c)
  pix(scr, x + 1, y - 2, c)
  -- tail
  pix(scr, x - 3, y, c)
  pix(scr, x - 4, y + 1, c)
  -- eye
  pix(scr, x + 3, y - 1, 0)
  pix(scr, x + 3, y - 2, 15)
end

local function draw_skull(x, y, c)
  -- skull (wider)
  rectf(scr, x - 3, y - 3, 7, 5, c)
  rectf(scr, x - 2, y + 2, 5, 2, c)
  -- jaw
  pix(scr, x - 2, y + 4, c)
  pix(scr, x + 2, y + 4, c)
  pix(scr, x, y + 4, c)
  -- eye sockets
  rectf(scr, x - 2, y - 2, 2, 2, 0)
  rectf(scr, x + 1, y - 2, 2, 2, 0)
  -- nose
  pix(scr, x, y, 0)
  -- teeth
  pix(scr, x - 1, y + 2, 0)
  pix(scr, x + 1, y + 2, 0)
  pix(scr, x, y + 3, 0)
end

local function draw_gold(x, y, c)
  -- bright golden body
  circf(scr, x, y, 4, 14)
  -- 4 cross sparkle pixels around it
  pix(scr, x - 6, y, 15)
  pix(scr, x + 6, y, 15)
  pix(scr, x, y - 6, 15)
  pix(scr, x, y + 6, 15)
  -- inner glint
  pix(scr, x - 1, y - 1, 15)
end

local mob_drawers = { draw_fish, draw_crab, draw_bird, draw_skull, draw_gold }

-- init

function _init()
  mode(4)
  best = data_load("bubble_best") or 0
  state = STATE_TITLE
  title_bubbles = {}
  for i = 1, 5 do
    table.insert(title_bubbles, {
      x = math.random(16, SCREEN_W - 16),
      y = math.random(20, SCREEN_H - 20),
      speed = 0.2 + math.random() * 0.3,
      mob = math.random(1, 3),
      wobble = math.random() * 6.283,
    })
  end
  cursor = { x = math.floor(SCREEN_W / 2), y = math.floor(SCREEN_H / 2) }
  keyboard_mode = false
  kb_virtual_touch = false
end

local function start_game()
  bubbles = {}
  particles = {}
  freed_mobs = {}
  score = 0
  lives = LIVES_MAX
  spawn_timer = 0
  spawn_rate = SPAWN_INIT
  bubble_speed = SPEED_INIT
  combo_text = nil
  combo_timer = 0
  combo_count = 0
  state = STATE_PLAY
end

local function spawn_bubble()
  local mob = MOB_FISH
  local roll = math.random(1, 100)
  -- difficulty ramp: at score > 100, skulls become more common and
  -- golden bubbles (rare +100pt) start appearing.
  local hard = score and score > 100
  if hard then
    -- skull 25%, gold 5%, bird 20%, crab 25%, else fish
    if roll <= 25 then
      mob = MOB_SKULL
    elseif roll <= 30 then
      mob = MOB_GOLD
    elseif roll <= 50 then
      mob = MOB_BIRD
    elseif roll <= 75 then
      mob = MOB_CRAB
    end
  else
    if roll <= 15 then
      mob = MOB_SKULL
    elseif roll <= 35 then
      mob = MOB_BIRD
    elseif roll <= 60 then
      mob = MOB_CRAB
    end
  end
  table.insert(bubbles, {
    x = math.random(BUBBLE_R + 4, SCREEN_W - BUBBLE_R - 4),
    y = SCREEN_H + BUBBLE_R + 4,
    speed = bubble_speed + math.random() * 0.3,
    mob = mob,
    alive = true,
    wobble = math.random() * 6.283,
  })
end

local function spawn_freed_mob(x, y, mob)
  table.insert(freed_mobs, {
    x = x,
    y = y,
    dy = -1.5,  -- small upward pop
    mob = mob,
    life = 60,
  })
end

local function spawn_particles(x, y, color, is_skull)
  -- ring burst
  local ring_n = 10
  for i = 1, ring_n do
    local angle = (i / ring_n) * 6.283
    local spd = 1.2 + math.random() * 0.8
    table.insert(particles, {
      x = x + math.cos(angle) * BUBBLE_R * 0.5,
      y = y + math.sin(angle) * BUBBLE_R * 0.5,
      dx = math.cos(angle) * spd,
      dy = math.sin(angle) * spd,
      life = math.random(8, 14),
      color = color,
      kind = "dot",
    })
  end
  -- sparkles
  for i = 1, 5 do
    local angle = math.random() * 6.283
    local spd = 0.3 + math.random() * 0.6
    table.insert(particles, {
      x = x, y = y,
      dx = math.cos(angle) * spd,
      dy = math.sin(angle) * spd - 0.5,
      life = math.random(12, 22),
      color = is_skull and 8 or 15,
      kind = "spark",
    })
  end
  -- bubble remnants
  for i = 1, 3 do
    table.insert(particles, {
      x = x + math.random(-4, 4),
      y = y + math.random(-3, 3),
      dx = (math.random() - 0.5) * 0.4,
      dy = -0.3 - math.random() * 0.5,
      life = math.random(16, 26),
      color = is_skull and 4 or 5,
      kind = "bubble",
      r = math.random(1, 2),
    })
  end
end

-- update

local function update_title()
  for _, b in ipairs(title_bubbles) do
    b.y = b.y - b.speed
    b.wobble = b.wobble + 0.05
    if b.y + BUBBLE_R < 0 then
      b.y = SCREEN_H + BUBBLE_R
      b.x = math.random(16, SCREEN_W - 16)
      b.mob = math.random(1, 3)
    end
  end
  -- detect keyboard input for cursor fallback
  if btnp("up") or btnp("down") or btnp("left") or btnp("right") then
    keyboard_mode = true
  end
  if touch_end() or btnr("start") or btnr("a") then
    start_game()
  end
end

local function update_play()
  -- spawn
  spawn_timer = spawn_timer + 1
  if spawn_timer >= spawn_rate then
    spawn_timer = 0
    spawn_bubble()
  end

  -- keyboard cursor: arrow keys move at 2 px/frame, A pops at cursor
  local kb_arrow_held = btn("up") or btn("down") or btn("left") or btn("right")
  if kb_arrow_held or btnp("a") then
    keyboard_mode = true
  end
  if btn("left")  then cursor.x = math.max(0, cursor.x - 2) end
  if btn("right") then cursor.x = math.min(SCREEN_W - 1, cursor.x + 2) end
  if btn("up")    then cursor.y = math.max(0, cursor.y - 2) end
  if btn("down")  then cursor.y = math.min(SCREEN_H - 1, cursor.y + 2) end
  kb_virtual_touch = btnp("a")

  -- move bubbles
  for i = #bubbles, 1, -1 do
    local b = bubbles[i]
    b.y = b.y - b.speed
    b.wobble = b.wobble + 0.06
    if b.y + BUBBLE_R < -4 then
      if b.mob ~= MOB_SKULL then
        tone(0, 400, 80, 0.5)  -- life-lost SFX
        lives = lives - 1
        if lives <= 0 then
          if score > best then
            best = score
            data_save("bubble_best", best)
          end
          state = STATE_OVER
          over_cooldown = 30
          return
        end
      end
      table.remove(bubbles, i)
    end
  end

  -- touch → pop (only on touch start, not drag). Keyboard A press is
  -- treated as a virtual touch at cursor position.
  local popped = 0
  local popped_pts = 0
  local hit_skull = false
  local any_pop_input = touch_start() or kb_virtual_touch
  if not any_pop_input then goto skip_pop end

  -- collect all input points (real touches + virtual cursor) into one list
  do
    local pts = {}
    if touch_start() then
      for i = 1, touch_count() do
        local tx, ty = touch_pos(i)
        if tx then pts[#pts + 1] = { x = tx, y = ty } end
      end
    end
    if kb_virtual_touch then
      pts[#pts + 1] = { x = cursor.x, y = cursor.y }
    end

    for _, pt in ipairs(pts) do
      local tx, ty = pt.x, pt.y
      local best_b = nil
      local best_y = 99999
      for _, b in ipairs(bubbles) do
        if b.alive then
          local dx = tx - b.x
          local dy = ty - b.y
          if dx * dx + dy * dy <= HIT_R * HIT_R then
            if b.y < best_y then
              best_y = b.y
              best_b = b
            end
          end
        end
      end
      if best_b then
        best_b.alive = false
        if best_b.mob == MOB_SKULL then
          hit_skull = true
          spawn_particles(best_b.x, best_b.y, 5, true)
        else
          popped = popped + 1
          popped_pts = popped_pts + MOB_POINTS[best_b.mob]
          spawn_particles(best_b.x, best_b.y, 12, false)
          spawn_freed_mob(best_b.x, best_b.y, best_b.mob)
        end
      else
        -- empty tap: small splash particles
        local SPLASH_N = 6
        local SPLASH_SPD_MIN = 0.4
        local SPLASH_SPD_RNG = 0.6
        for j = 1, SPLASH_N do
          local angle = math.random() * 6.283
          local spd = SPLASH_SPD_MIN + math.random() * SPLASH_SPD_RNG
          table.insert(particles, {
            x = tx, y = ty,
            dx = math.cos(angle) * spd,
            dy = math.sin(angle) * spd,
            life = math.random(6, 12),
            color = 5,
            kind = "spark",
          })
        end
      end
    end
  end

  ::skip_pop::
  -- remove popped bubbles
  for i = #bubbles, 1, -1 do
    if not bubbles[i].alive then
      table.remove(bubbles, i)
    end
  end

  -- skull penalty
  if hit_skull then
    cam_shake(6)
    noise(1, 0.3, "low", 200)
    lives = lives - 1
    combo_count = 0
    if lives <= 0 then
      if score > best then
        best = score
        data_save("bubble_best", best)
      end
      state = STATE_OVER
      over_cooldown = 30
      return
    end
  end

  -- scoring + pop SFX (ascending by combo chain length)
  if popped > 0 then
    combo_count = combo_count + popped
    local note_idx = math.min(combo_count, 8)
    note(0, COMBO_NOTES[note_idx], 0.05)

    local pts = popped_pts
    if popped >= 2 then
      pts = pts * popped
      combo_text = "x" .. popped .. "!"
      combo_timer = 24
    end
    score = score + pts
  else
    -- no pop this frame → reset combo chain
    combo_count = 0
  end

  -- combo text fade
  if combo_timer > 0 then
    combo_timer = combo_timer - 1
    if combo_timer <= 0 then combo_text = nil end
  end

  -- update freed mobs (fall with gravity)
  for i = #freed_mobs, 1, -1 do
    local m = freed_mobs[i]
    m.dy = m.dy + 0.12  -- gravity
    m.y = m.y + m.dy
    m.life = m.life - 1
    if m.y > SCREEN_H + 10 or m.life <= 0 then
      table.remove(freed_mobs, i)
    end
  end

  -- update particles
  for i = #particles, 1, -1 do
    local p = particles[i]
    p.x = p.x + p.dx
    p.y = p.y + p.dy
    p.dy = p.dy + 0.05
    p.life = p.life - 1
    if p.life <= 0 then
      table.remove(particles, i)
    end
  end

  -- difficulty ramp
  spawn_rate = math.max(SPAWN_MIN, SPAWN_INIT - math.floor(score / 30))
  bubble_speed = math.min(SPEED_MAX, SPEED_INIT + score * 0.002)
end

local function update_over()
  for i = #particles, 1, -1 do
    local p = particles[i]
    p.x = p.x + p.dx
    p.y = p.y + p.dy
    p.life = p.life - 1
    if p.life <= 0 then
      table.remove(particles, i)
    end
  end
  for i = #freed_mobs, 1, -1 do
    local m = freed_mobs[i]
    m.dy = m.dy + 0.12
    m.y = m.y + m.dy
    m.life = m.life - 1
    if m.y > SCREEN_H + 10 or m.life <= 0 then
      table.remove(freed_mobs, i)
    end
  end
  if over_cooldown > 0 then
    over_cooldown = over_cooldown - 1
  elseif touch_end() or btnr("start") or btnr("a") then
    start_game()
  end
end

function _update()
  if state == STATE_TITLE then
    update_title()
  elseif state == STATE_PLAY then
    update_play()
  elseif state == STATE_OVER then
    update_over()
  end
end

-- draw

local function draw_particle(p)
  local px = math.floor(p.x)
  local py = math.floor(p.y)
  if p.kind == "spark" then
    pix(scr, px, py, p.color)
    pix(scr, px - 1, py, p.color)
    pix(scr, px + 1, py, p.color)
    pix(scr, px, py - 1, p.color)
    pix(scr, px, py + 1, p.color)
  elseif p.kind == "bubble" then
    circ(scr, px, py, p.r or 1, p.color)
  else
    pix(scr, px, py, p.color)
  end
end

local function draw_bubble(bx, by, mob, wobble)
  local wx = math.floor(bx + math.sin(wobble) * 2)
  local wy = math.floor(by)
  -- bubble sphere
  circf(scr, wx, wy, BUBBLE_R, 3)
  circ(scr, wx, wy, BUBBLE_R, 5)
  -- highlight
  pix(scr, wx - 4, wy - 5, 7)
  pix(scr, wx - 3, wy - 6, 7)
  pix(scr, wx - 3, wy - 5, 6)
  -- mob inside
  local mc = 15
  if mob == MOB_SKULL then mc = 10 end
  mob_drawers[mob](wx, wy, mc)
end

local function draw_lives_hud()
  for i = 1, LIVES_MAX do
    local lx = SCREEN_W - 2 - i * 8
    if i <= lives then
      circf(scr, lx, 5, 3, 15)
      circ(scr, lx, 5, 3, 12)
    else
      circ(scr, lx, 5, 3, 4)
    end
  end
end

local function draw_title()
  cls(scr, 0)
  -- bubbles drawn first → they drift BEHIND the title card
  for _, b in ipairs(title_bubbles) do
    draw_bubble(b.x, b.y, b.mob, b.wobble)
  end
  -- title card sits at y=44, leaving the upper screen free for bubbles
  rectf(scr, 20, 44, 120, 38, 0)
  rect(scr, 20, 44, 120, 38, 8)
  text(scr, "BUBBLE BOBBLE", CX, 52, 15, ALIGN_HCENTER)
  text(scr, "Pop to rescue!", CX, 64, 10, ALIGN_HCENTER)
  text(scr, "Avoid skull!", CX, 72, 8, ALIGN_HCENTER)
  if math.floor(frame() / 15) % 2 == 0 then
    text(scr, "TOUCH OR PRESS A", CX, 92, 12, ALIGN_HCENTER)
  end
  if best and best > 0 then
    text(scr, "BEST " .. best, CX, 102, 6, ALIGN_HCENTER)
  end
  text(scr, "A MONO DEMO", CX, SCREEN_H - 8, 4, ALIGN_HCENTER)
end

local function draw_play()
  cls(scr, 1)

  -- particles
  for _, p in ipairs(particles) do
    draw_particle(p)
  end

  -- freed mobs falling
  for _, m in ipairs(freed_mobs) do
    local mx = math.floor(m.x)
    local my = math.floor(m.y)
    mob_drawers[m.mob](mx, my, 15)
  end

  -- bubbles
  for _, b in ipairs(bubbles) do
    draw_bubble(b.x, b.y, b.mob, b.wobble)
  end

  -- HUD bar (camera-independent)
  local cx, cy = cam_get()
  cam(0, 0)
  rectf(scr, 0, 0, SCREEN_W, 11, 0)
  line(scr, 0, 11, SCREEN_W - 1, 11, 3)
  text(scr, tostring(score), 2, 2, 12)
  draw_lives_hud()

  -- combo text
  if combo_text and combo_timer then
    local cc = combo_timer > 12 and 15 or 10
    text(scr, combo_text, CX, CY, cc, ALIGN_CENTER)
  end

  -- keyboard crosshair cursor (only when keyboard input was detected)
  if keyboard_mode then
    local kx = cursor.x
    local ky = cursor.y
    circ(scr, kx, ky, 4, 15)
    pix(scr, kx, ky, 15)
  end
  cam(cx, cy)
end

local function draw_over()
  -- draw_play() leaves the camera at (cx, cy); this overlay is pure HUD
  -- so reset the camera before drawing anything.
  cam(0, 0)
  cls(scr, 0)
  for _, p in ipairs(particles) do
    draw_particle(p)
  end
  for _, m in ipairs(freed_mobs) do
    mob_drawers[m.mob](math.floor(m.x), math.floor(m.y), 15)
  end
  rectf(scr, 25, 25, 110, 62, 0)
  rect(scr, 25, 25, 110, 62, 15)
  text(scr, "GAME OVER", CX, 34, 15, ALIGN_HCENTER)
  text(scr, "SCORE", CX, 48, 8, ALIGN_HCENTER)
  text(scr, tostring(score), CX, 58, 12, ALIGN_HCENTER)
  text(scr, "BEST " .. best, CX, 70, 6, ALIGN_HCENTER)
  if math.floor(frame() / 15) % 2 == 0 then
    text(scr, "TOUCH TO RETRY", CX, 98, 10, ALIGN_HCENTER)
  end
end

function _draw()
  if state == STATE_TITLE then
    draw_title()
  elseif state == STATE_PLAY then
    draw_play()
  elseif state == STATE_OVER then
    draw_over()
  end
end
