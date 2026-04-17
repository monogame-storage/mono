-- Game Over Screen for GRAVITON

local timer = 0
local stats_reveal = 0
local particles = {}

function gameover_init()
  timer = 0
  stats_reveal = 0

  -- Create explosion particles
  particles = {}
  for i = 1, 30 do
    local angle = math.random() * math.pi * 2
    local speed = math.random(10, 40) / 10
    particles[i] = {
      x = 80,
      y = 50,
      vx = math.cos(angle) * speed,
      vy = math.sin(angle) * speed,
      life = math.random(30, 90),
      max_life = 90,
      color = math.random(5, 15)
    }
  end
end

function gameover_update()
  timer = timer + 1

  -- Gradually reveal stats
  if stats_reveal < 4 and timer % 20 == 0 then
    stats_reveal = stats_reveal + 1
    note(0, "C4", 0.05)
  end

  -- Update particles
  for i = #particles, 1, -1 do
    local p = particles[i]
    p.x = p.x + p.vx
    p.y = p.y + p.vy
    p.vy = p.vy + 0.05  -- gravity on particles
    p.life = p.life - 1
    if p.life <= 0 then
      table.remove(particles, i)
    end
  end

  -- Restart (button or tap)
  if timer > 40 and (btnp("start") or touch_start()) then
    note(0, "C5", 0.1)
    go("game")
  end

  -- Back to title
  if timer > 40 and btnp("b") then
    note(0, "G3", 0.1)
    go("title")
  end
end

function gameover_draw()
  local s = screen()
  cls(s, 0)

  -- Draw particles
  for _, p in ipairs(particles) do
    local fade = math.floor(p.color * (p.life / p.max_life))
    if fade > 0 then
      pix(s, math.floor(p.x), math.floor(p.y), fade)
    end
  end

  -- Decorative border
  rect(s, 4, 4, 152, 112, 3)

  -- Title
  text(s, "GAME OVER", 80, 14, 15, ALIGN_HCENTER)
  line(s, 40, 22, 120, 22, 8)

  -- Score display (big)
  if stats_reveal >= 1 then
    text(s, "FINAL SCORE", 80, 30, 8, ALIGN_HCENTER)
    text(s, tostring(score), 80, 40, 15, ALIGN_HCENTER)
  end

  -- Stats
  if stats_reveal >= 2 then
    text(s, "LEVEL: " .. level, 80, 54, 10, ALIGN_HCENTER)
    text(s, "LINES: " .. lines_cleared, 80, 63, 10, ALIGN_HCENTER)
  end

  -- High score
  if stats_reveal >= 3 then
    if score >= high_score then
      -- New high score flash
      if math.floor(timer / 8) % 2 == 0 then
        text(s, "NEW HIGH SCORE!", 80, 76, 15, ALIGN_HCENTER)
      else
        text(s, "NEW HIGH SCORE!", 80, 76, 10, ALIGN_HCENTER)
      end
    else
      text(s, "HI-SCORE: " .. high_score, 80, 76, 8, ALIGN_HCENTER)
    end
  end

  -- Prompts
  if stats_reveal >= 4 then
    if math.floor(timer / 15) % 2 == 0 then
      text(s, "START: RETRY", 80, 92, 12, ALIGN_HCENTER)
    end
    text(s, "B: TITLE", 80, 102, 8, ALIGN_HCENTER)
  end
end
