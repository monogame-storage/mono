-- Mono Scorch 2P (lockstep netplay)
-- Two-player artillery duel over the network. Open in two browsers
-- or two devices — Firestore auto-pairs you.
--
-- Adapted from the Mono Scorch cabinet game (cabinet/games/scorch).
-- Single-player (AI, difficulty, multi-stage progression, watch mode,
-- title menu, parallax backgrounds, motion sensor) is stripped out;
-- what remains is the polished terrain/physics/charge-fire/HUD core.
--
-- Active player only:
--   UP/DOWN    : aim angle (10..170°)
--   LEFT/RIGHT : drive (uses fuel; affects turn order)
--   A (Z key)  : hold to charge power, release to fire
--   B (X key)  : hold to scout (free-pan camera)

-- ── world constants ──────────────────────────────────────────────────
SCR_W, SCR_H      = 160, 120
TERRAIN_W         = 240
TANK_W, TANK_H    = 10, 5
BARREL_LEN        = 7
GRAVITY           = 0.15
WIND_MAX          = 0.04
EXPLOSION_R       = 14
FUEL_MAX          = 30
SLOPE_MAX         = 60
TURN_TIMEOUT      = 450     -- 15 sec at 30fps
ACCUM_BASE        = 100
ACCUM_MOVE_COST   = 3
ACCUM_TIME_COST   = 0.5
CAM_SMOOTH        = 0.1
GROUND_COLOR      = 10
SKY_COLOR         = 1

-- match-level: best-of-5, first to 3 wins
WINS_TO_TAKE_MATCH = 3
ROUND_END_PAUSE    = 90    -- frames between rounds (3 s)

local scr

-- ── runtime state ────────────────────────────────────────────────────
local terrain
local p                  -- p[1], p[2]
local turn               -- 1 or 2
local wind
local cam_x, cam_tx
local proj               -- {x, y, vx, vy, trail, power}
local state              -- "aim" | "fire" | "explode" | "collapse" | "gameover"
local charging
local aim_frames
local turn_timer
local turn_accum
local collapse_data
local explode_timer, explode_x, explode_y
local winner
local dmg_text, dmg_timer
local game_started
local scouting

-- match-level state (wraps the in-round `state` machine)
local match_phase        -- "title" | "playing" | "match_over"
local score              -- { p1_wins, p2_wins }
local ready              -- { p1_ready, p2_ready } — title / rematch consent
local current_round      -- 1-based; alternates starting player
local round_winner       -- set when a round ends (used for round_end overlay)
local match_winner       -- set when match_phase flips to "match_over"
local round_pause        -- frames left in state == "round_end"

-- aim-input hold counters (per-button) — for accel after 30 frames held
local aim_up_held, aim_dn_held = 0, 0

-- trajectory preview: list of {x,y} sample points generated while charging
local preview_pts = {}

-- wind audio: play once per turn when |wind| > 0.02
local wind_played_this_turn = false

-- apex tracking: highest point of last shot (used by round-end overlay)
local last_apex_x, last_apex_y
local last_shot_dmg        -- max damage dealt by the final shot

-- ── camera ───────────────────────────────────────────────────────────
local function cam_clamp(x) return math.max(0, math.min(TERRAIN_W - SCR_W, x)) end
local function cam_focus(wx) cam_tx = cam_clamp(wx - SCR_W / 2) end
local function world_to_screen(wx) return wx - math.floor(cam_x) end

-- ── terrain ──────────────────────────────────────────────────────────

-- Procedural deterministic generator. Both peers seed math.random from
-- net.seed() before calling, so terrain is identical across the wire.
local function gen_terrain()
  local s1 = math.random() * 1000
  local s2 = math.random() * 1000
  local s3 = math.random() * 1000
  terrain = {}
  for x = 0, TERRAIN_W - 1 do
    local h = 78
      + math.floor(math.sin(x * 0.045 + s1) * 14)
      + math.floor(math.sin(x * 0.11  + s2) * 6)
      + math.floor(math.sin(x * 0.28  + s3) * 3)
    if h < 50  then h = 50  end
    if h > 108 then h = 108 end
    terrain[x] = h
  end
end

local function flatten_under(cx, w)
  local half = math.floor(w / 2)
  local base_y = terrain[cx] or SCR_H
  for x = cx - half, cx + half do
    if x >= 0 and x <= TERRAIN_W - 1 then
      if terrain[x] < base_y then base_y = terrain[x] end
    end
  end
  for x = cx - half, cx + half do
    if x >= 0 and x <= TERRAIN_W - 1 then terrain[x] = base_y end
  end
end

local function carve_crater(ex, ey, radius)
  collapse_data = {}
  for dx = -radius, radius do
    local tx = ex + dx
    if tx >= 0 and tx <= TERRAIN_W - 1 then
      local r2 = radius * radius - dx * dx
      if r2 > 0 then
        local circle_bot = ey + math.floor(math.sqrt(r2))
        if terrain[tx] <= circle_bot then
          local new_y = math.max(terrain[tx], circle_bot + 1)
          if new_y > terrain[tx] then collapse_data[tx] = new_y end
        end
      end
    end
  end
end

local function update_collapse_frame()
  local done = true
  for x, target_y in pairs(collapse_data) do
    if terrain[x] < target_y then
      terrain[x] = math.min(terrain[x] + 3, target_y)
      done = false
    end
  end
  if done then collapse_data = {} end
  return done
end

local function settle_tank(t)
  local half = math.floor(TANK_W / 2)
  local old_y = t.y
  local min_y = SCR_H
  for x = t.x - half, t.x + half do
    if x >= 0 and x <= TERRAIN_W - 1 then
      if terrain[x] < min_y then min_y = terrain[x] end
    end
  end
  t.y = min_y - TANK_H
  if min_y >= SCR_H then
    t.hp = 0
    t.y = SCR_H + 10
    return
  end
  local fall = t.y - old_y
  if fall >= 25 then
    t.hp = math.max(0, t.hp - 5)
    dmg_text = "-5"
    dmg_timer = 30
  end
end

-- ── match flow ───────────────────────────────────────────────────────

-- One round: fresh terrain, full HP, alternating starting player.
local function init_round()
  gen_terrain()
  wind = (math.random() - 0.5) * WIND_MAX * 2
  local x1 = 20 + math.random(0, 30)
  local x2 = TERRAIN_W - 20 - math.random(0, 30)
  p = {}
  -- P1 → color 12 (light), P2 → color 6 (mid-grey) for better contrast
  -- against the explosion/dirt frames.
  p[1] = { x = x1, y = 0, angle = 45,  power = 0, hp = 100, color = 12,
           fuel = FUEL_MAX, last_power = -1, moved = 0 }
  p[2] = { x = x2, y = 0, angle = 135, power = 0, hp = 100, color = 6,
           fuel = FUEL_MAX, last_power = -1, moved = 0 }
  for i = 1, 2 do
    flatten_under(p[i].x, TANK_W)
    p[i].y = terrain[p[i].x] - TANK_H
  end
  -- Alternate who serves first each round to avoid first-mover advantage
  -- piling up over a 5-round match.
  turn          = (current_round % 2 == 1) and 1 or 2
  state         = "aim"
  charging      = false
  aim_frames    = 0
  turn_timer    = TURN_TIMEOUT
  collapse_data = {}
  explode_timer = 0
  turn_accum    = { 0, 0 }
  cam_x         = cam_clamp(p[turn].x - SCR_W / 2)
  cam_tx        = cam_x
  dmg_text      = ""
  dmg_timer     = 0
  scouting      = false
  match_phase   = "playing"
  aim_up_held   = 0
  aim_dn_held   = 0
  wind_played_this_turn = false
  last_apex_x   = nil
  last_apex_y   = nil
  last_shot_dmg = 0
end

-- Full match: best of 5 (first to 3). Sets score to 0 and shows title.
local function init_match()
  score         = { 0, 0 }
  ready         = { false, false }
  current_round = 1
  round_winner  = 0
  match_winner  = 0
  round_pause   = 0
  match_phase   = "title"
end

-- Title and rematch screens share input: both players press A to confirm.
local function update_ready_gate()
  if btnp("a", 0) and not ready[1] then
    ready[1] = true
    note(0, "C5", 0.06)
  end
  if btnp("a", 1) and not ready[2] then
    ready[2] = true
    note(1, "E5", 0.06)
  end
  if ready[1] and ready[2] then
    if match_phase == "match_over" then
      score         = { 0, 0 }
      current_round = 1
      match_winner  = 0
    end
    ready = { false, false }
    init_round()
    note(0, "C5", 0.1); note(1, "G5", 0.1)
  end
end

local function next_turn()
  local prev = turn
  local move_penalty = p[prev].moved * ACCUM_MOVE_COST
  local time_penalty = math.floor(aim_frames * ACCUM_TIME_COST)
  turn_accum[prev] = turn_accum[prev] + ACCUM_BASE + move_penalty + time_penalty
  if turn_accum[1] <= turn_accum[2] then turn = 1 else turn = 2 end
  p[turn].power = 0
  p[turn].fuel  = FUEL_MAX
  p[turn].moved = 0
  charging   = false
  aim_frames = 0
  turn_timer = TURN_TIMEOUT
  wind = wind + (math.random() - 0.5) * 0.015
  if wind >  WIND_MAX then wind =  WIND_MAX end
  if wind < -WIND_MAX then wind = -WIND_MAX end
  state = "aim"
  aim_up_held = 0
  aim_dn_held = 0
  wind_played_this_turn = false
end

local function fire()
  local t = p[turn]
  t.last_power = t.power
  local rad = t.angle * math.pi / 180
  local speed = t.power * 0.06
  proj = {
    x = t.x, y = t.y - 1,
    vx = math.cos(rad) * speed,
    vy = -math.sin(rad) * speed,
    trail = {}, power = t.power,
  }
  state = "fire"
  tone(0, 200, 80, 0.15)
end

local function start_explosion(ex, ey)
  explode_x = math.floor(ex)
  explode_y = math.floor(ey)
  explode_timer = 15
  state = "explode"
  noise(1, 0.3, "lowpass", 800)
  carve_crater(explode_x, explode_y, EXPLOSION_R)
  local power_bonus = 1.0
  if proj.power > 50 then power_bonus = 1.0 + (proj.power - 50) / 50 * 0.3 end
  local max_dmg = 0
  for i = 1, 2 do
    local t = p[i]
    local dx = t.x - explode_x
    local dy = (t.y + TANK_H / 2) - explode_y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < EXPLOSION_R + 5 then
      local dmg = math.floor(math.max(0, (1 - dist / (EXPLOSION_R + 8)) * 38) * power_bonus)
      t.hp = math.max(0, t.hp - dmg)
      if dmg > max_dmg then max_dmg = dmg end
      if dmg > 0 then
        dmg_text  = "-" .. dmg
        dmg_timer = 40
        noise(1, 0.4, "lowpass", 600)
        tone(0, 120, 40, 0.2)
      end
    end
  end
  -- remember this shot's apex + max damage for the round-end overlay
  if proj and proj.apex_x then
    last_apex_x = proj.apex_x
    last_apex_y = proj.apex_y
  end
  last_shot_dmg = max_dmg
end

local function post_explosion()
  for i = 1, 2 do
    if p[i].hp <= 0 or p[i].y > SCR_H then
      round_winner = 3 - i
      score[round_winner] = score[round_winner] + 1
      tone(0, 300, 200, 0.3)
      state       = "round_end"
      round_pause = ROUND_END_PAUSE
      return
    end
  end
  next_turn()
end

-- ── input / phase updates ────────────────────────────────────────────

local function can_move_to(nx)
  local half = math.floor(TANK_W / 2)
  if nx - half < 0 or nx + half > TERRAIN_W - 1 then return false end
  local t = p[turn]
  local new_min_y = SCR_H
  for x = nx - half, nx + half do
    if x >= 0 and x <= TERRAIN_W - 1 and terrain[x] < new_min_y then new_min_y = terrain[x] end
  end
  local cur_min_y = SCR_H
  for x = t.x - half, t.x + half do
    if x >= 0 and x <= TERRAIN_W - 1 and terrain[x] < cur_min_y then cur_min_y = terrain[x] end
  end
  local dy = cur_min_y - new_min_y
  if dy > 0 and math.atan(dy, 1) * 180 / math.pi > SLOPE_MAX then return false end
  return true
end

local function update_aim()
  local pi = turn - 1         -- 0 or 1 — input slot for active player
  local t  = p[turn]
  cam_focus(t.x)

  -- one-shot wind audio when this turn begins (any active wind)
  if not wind_played_this_turn and math.abs(wind) > 0.02 then
    noise(1, 0.08, "highpass", 200 + math.abs(wind) * 5000)
    wind_played_this_turn = true
  end

  -- aim accel: holding up/down for >30 frames doubles the rate.
  if btn("up", pi) then
    aim_up_held = aim_up_held + 1
    local step = aim_up_held > 30 and 2 or 1
    t.angle = math.min(170, t.angle + step)
  else
    aim_up_held = 0
  end
  if btn("down", pi) then
    aim_dn_held = aim_dn_held + 1
    local step = aim_dn_held > 30 and 2 or 1
    t.angle = math.max(10, t.angle - step)
  else
    aim_dn_held = 0
  end

  if not charging and t.fuel > 0 then
    local moved = false
    if btn("left", pi) then
      local nx = t.x - 1
      if can_move_to(nx) then
        t.x = nx; t.fuel = t.fuel - 1; t.moved = t.moved + 1
        settle_tank(t); moved = true
      end
    end
    if btn("right", pi) and not moved then
      local nx = t.x + 1
      if can_move_to(nx) then
        t.x = nx; t.fuel = t.fuel - 1; t.moved = t.moved + 1
        settle_tank(t)
      end
    end
  end

  if btn("a", pi) then
    if not charging then charging = true; t.power = 0 end
    t.power = t.power + 2
    if t.power >= 100 then
      t.power = 100
      charging = false
      preview_pts = {}
      fire(); return
    end
    if frame() % 3 == 0 then
      local hz = 100 + t.power * 4
      tone(0, hz, hz + 20, 0.05)
    end

    -- trajectory preview: simulate ~30 ticks forward, sample every 3rd
    -- tick (draw-only — no terrain check, no state mutation).
    preview_pts = {}
    local rad = t.angle * math.pi / 180
    local speed = t.power * 0.06
    local sx = t.x
    local sy = t.y - 1
    local svx = math.cos(rad) * speed
    local svy = -math.sin(rad) * speed
    for tick = 1, 30 do
      svy = svy + GRAVITY
      svx = svx + wind
      sx  = sx + svx
      sy  = sy + svy
      if sy > SCR_H or sx < -20 or sx > TERRAIN_W + 20 then break end
      if tick % 3 == 0 then
        preview_pts[#preview_pts + 1] = { x = sx, y = sy }
      end
    end
  else
    -- not holding A → no preview
    preview_pts = {}
  end
  if btnr("a", pi) and charging then
    charging = false
    preview_pts = {}
    fire()
  end
end

local function update_fire()
  cam_focus(proj.x)
  if #proj.trail < 200 then
    table.insert(proj.trail, { x = proj.x, y = proj.y })
  end
  proj.vy = proj.vy + GRAVITY
  proj.vx = proj.vx + wind
  proj.x  = proj.x + proj.vx
  proj.y  = proj.y + proj.vy

  -- track apex (highest point reached → smallest y)
  if not proj.apex_y or proj.y < proj.apex_y then
    proj.apex_x = proj.x
    proj.apex_y = proj.y
  end

  local px = math.floor(proj.x)
  local py = math.floor(proj.y)
  if px < -20 or px > TERRAIN_W + 20 or py > SCR_H + 30 then
    next_turn(); return
  end
  if px >= 0 and px <= TERRAIN_W - 1 and py >= terrain[px] then
    start_explosion(proj.x, proj.y)
    cam_shake(3); return
  end
  for i = 1, 2 do
    local t = p[i]
    local half = math.floor(TANK_W / 2)
    if px >= t.x - half and px <= t.x + half and py >= t.y and py <= t.y + TANK_H then
      start_explosion(proj.x, proj.y)
      cam_shake(6); return
    end
  end
end

local function update_explode()
  cam_focus(explode_x)
  explode_timer = explode_timer - 1
  if explode_timer <= 0 then
    if next(collapse_data) then state = "collapse"; return end
    post_explosion()
  end
end

local function update_collapse_state()
  cam_focus(explode_x)
  local done = update_collapse_frame()
  for i = 1, 2 do settle_tank(p[i]) end
  if done then post_explosion() end
end

local function update_scout()
  local pi = turn - 1
  if btn("left",  pi) then cam_tx = cam_clamp(cam_tx - 3) end
  if btn("right", pi) then cam_tx = cam_clamp(cam_tx + 3) end
end

-- ── lifecycle ────────────────────────────────────────────────────────

function _init()
  mode(4)
  wave(0, "square")
  wave(1, "triangle")
  use_pause(false)
end

function _start()
  net.start()
  scr = screen()
  game_started = false
end

function _update()
  -- Wait for the netplay match before doing anything.
  if not game_started then
    if net.status() ~= "playing" then return end
    math.randomseed(net.seed())
    init_match()
    game_started = true
    return
  end

  -- Title and match-over share the "press A to begin" gate.
  if match_phase == "title" or match_phase == "match_over" then
    update_ready_gate()
    return
  end

  -- Round-end pause: hold position, advance to next round or match_over.
  if state == "round_end" then
    round_pause = round_pause - 1
    if round_pause <= 0 then
      if score[1] >= WINS_TO_TAKE_MATCH or score[2] >= WINS_TO_TAKE_MATCH then
        match_winner = (score[1] >= WINS_TO_TAKE_MATCH) and 1 or 2
        match_phase  = "match_over"
        ready        = { false, false }
        tone(0, 500, 600, 0.5)
      else
        current_round = current_round + 1
        init_round()
      end
    end
    if dmg_timer > 0 then dmg_timer = dmg_timer - 1 end
    return
  end

  -- Scout mode: active player holds B to free-pan camera.
  local pi = turn - 1
  if state == "aim" and not charging then
    scouting = btn("b", pi)
    if not scouting then cam_focus(p[turn].x) end
  else
    scouting = false
  end
  if scouting then
    update_scout()
    cam_x = cam_x + (cam_tx - cam_x) * CAM_SMOOTH
    cam_x = cam_clamp(cam_x)
    return
  end

  if state == "aim" then
    aim_frames = aim_frames + 1
    if not charging then
      turn_timer = turn_timer - 1
      if turn_timer <= 0 then next_turn(); return end
    end
    update_aim()
  elseif state == "fire" then
    update_fire()
  elseif state == "explode" then
    update_explode()
  elseif state == "collapse" then
    update_collapse_state()
  end

  cam_x = cam_x + (cam_tx - cam_x) * CAM_SMOOTH
  cam_x = cam_clamp(cam_x)
  if dmg_timer > 0 then dmg_timer = dmg_timer - 1 end
end

-- ── drawing ──────────────────────────────────────────────────────────

local function draw_terrain()
  local cx = math.floor(cam_x)
  local x0 = math.max(0, cx)
  local x1 = math.min(TERRAIN_W - 1, cx + SCR_W - 1)
  for x = x0, x1 do
    local top = terrain[x]
    if top < SCR_H and top > 0 then pix(scr, x - cx, top - 1, 2) end
  end
  for x = x0, x1 do
    local top = terrain[x]
    if top < SCR_H then
      local sx = x - cx
      for y = top, SCR_H - 1 do
        local depth = y - top
        local c = GROUND_COLOR
        if     depth == 0   then c = GROUND_COLOR + 3
        elseif depth < 2    then c = GROUND_COLOR + 2
        elseif depth < 5    then c = GROUND_COLOR + 1
        elseif depth > 20   then c = GROUND_COLOR - 2 end
        if c < 1  then c = 1  end
        if c > 15 then c = 15 end
        pix(scr, sx, y, c)
      end
    end
  end
  -- falling dirt particles during collapse — offsets derived from
  -- position+frame so both peers render identically without touching RNG.
  if next(collapse_data) then
    local f = frame()
    for x, target_y in pairs(collapse_data) do
      local cur = terrain[x]
      if cur < target_y then
        local sx = x - cx
        if sx >= 0 and sx < SCR_W then
          for dy = 1, math.min(5, target_y - cur) do
            local py = cur + dy + ((x * 7 + dy * 3 + f) % 3)
            if py < SCR_H then
              local tint = ((x + dy + f) % 3) - 1
              pix(scr, sx, py, GROUND_COLOR + tint)
            end
          end
        end
      end
    end
  end
end

local function draw_tank(t, idx, sx)
  local half = math.floor(TANK_W / 2)
  local c = t.color
  rectf(scr, sx - half - 1, t.y + 1, TANK_W + 2, TANK_H - 1, 0)
  rectf(scr, sx - 3,        t.y - 1, 7, 5, 0)
  rectf(scr, sx - half,     t.y + 2, TANK_W, TANK_H - 2, c)
  rectf(scr, sx - 2,        t.y, 5, 3, c)
  local rad = t.angle * math.pi / 180
  local bx = sx + math.floor(math.cos(rad) * BARREL_LEN)
  local by = t.y - math.floor(math.sin(rad) * BARREL_LEN)
  line(scr, sx, t.y + 1, bx, by, c)

  local bar_w = TANK_W
  local hp_w  = math.floor(bar_w * t.hp / 100)
  local bar_y = t.y - 6
  rectf(scr, sx - half - 1, bar_y - 1, bar_w + 2, 4, 0)
  rectf(scr, sx - half,     bar_y,     bar_w,     2, 3)
  if hp_w > 0 then
    rectf(scr, sx - half, bar_y, hp_w, 2, t.hp > 30 and 15 or 8)
  end

  if idx == turn and state == "aim" then
    if math.floor(frame() / 10) % 2 == 0 then
      text(scr, "P" .. idx, sx - 4, t.y - 15, 0)
      text(scr, "P" .. idx, sx - 5, t.y - 16, 15)
    end
  end
end

local function draw_wind_indicator()
  local cx = math.floor(SCR_W / 2)
  local wy = 5
  local wind_len = math.floor(wind / WIND_MAX * 24)
  if math.abs(wind_len) > 1 then
    line(scr, cx, wy,     cx + wind_len, wy,     12)
    line(scr, cx, wy + 1, cx + wind_len, wy + 1, 10)
    local dir = wind_len > 0 and 1 or -1
    local tip = cx + wind_len
    pix(scr, tip,         wy - 1, 15)
    pix(scr, tip,         wy + 2, 15)
    pix(scr, tip + dir,   wy,     15)
    pix(scr, tip + dir,   wy + 1, 15)
  else
    pix(scr, cx, wy,     7)
    pix(scr, cx, wy + 1, 7)
  end
end

local function draw_hud()
  -- top corners: P1 / P2 HP bars
  local hp_bar_w, hp_bar_h = 24, 3
  rectf(scr, 0,          0, 30, 15, 0)
  rectf(scr, SCR_W - 30, 0, 30, 15, 0)
  text(scr, "P1", 2, 2, 15)
  rectf(scr, 2, 10, hp_bar_w, hp_bar_h, 2)
  local p1_fill = math.floor(hp_bar_w * p[1].hp / 100)
  if p1_fill > 0 then
    rectf(scr, 2, 10, p1_fill, hp_bar_h, p[1].hp > 30 and 15 or 8)
  end
  text(scr, "P2", SCR_W - 2, 2, 15, ALIGN_RIGHT)
  local p2_x = SCR_W - 2 - hp_bar_w
  rectf(scr, p2_x, 10, hp_bar_w, hp_bar_h, 2)
  local p2_fill = math.floor(hp_bar_w * p[2].hp / 100)
  if p2_fill > 0 then
    rectf(scr, p2_x + hp_bar_w - p2_fill, 10, p2_fill, hp_bar_h, p[2].hp > 30 and 15 or 8)
  end

  if state == "aim" then
    local secs = math.ceil(turn_timer / 30)
    if secs <= 5 then
      local tc = 15
      if secs <= 3 and math.floor(frame() / 4) % 2 == 0 then tc = 8 end
      text(scr, tostring(secs), math.floor(SCR_W / 2), 10, tc, ALIGN_HCENTER)
    end

    local t = p[turn]
    local hudY = SCR_H - 14
    rectf(scr, 0, hudY - 1, SCR_W, SCR_H - hudY + 1, 0)
    if t.fuel < FUEL_MAX or t.moved > 0 then
      local fw = 20
      local ff = math.floor(fw * t.fuel / FUEL_MAX)
      text(scr, "F", 2, hudY, 10)
      rectf(scr, 10, hudY + 1, fw, 3, 2)
      if ff > 0 then
        rectf(scr, 10, hudY + 1, ff, 3, t.fuel > FUEL_MAX * 0.3 and 12 or 8)
      end
    end
    text(scr, "A:" .. t.angle, 2, hudY + 6, 12)

    local bar_x = 70
    local bar_w = SCR_W - bar_x - 4
    local pw    = math.floor(bar_w * t.power / 100)
    rectf(scr, bar_x, hudY + 8, bar_w, 3, 2)
    if t.last_power >= 0 then
      local lp_x = bar_x + math.floor(bar_w * t.last_power / 100)
      line(scr, lp_x, hudY + 7, lp_x, hudY + 11, 15)
    end
    if charging then
      local bar_c = 15
      if t.power >= 90 then bar_c = (math.floor(frame() / 3) % 2 == 0) and 15 or 12 end
      if pw > 0 then rectf(scr, bar_x, hudY + 8, pw, 3, bar_c) end
    else
      if pw > 0 then rectf(scr, bar_x, hudY + 8, pw, 3, 10) end
    end

    -- aim guide
    local rad  = t.angle * math.pi / 180
    local tsx  = world_to_screen(t.x)
    local gx   = tsx + math.floor(math.cos(rad) * (BARREL_LEN + 4))
    local gy   = t.y - math.floor(math.sin(rad) * (BARREL_LEN + 4))
    local gx2  = tsx + math.floor(math.cos(rad) * (BARREL_LEN + 8))
    local gy2  = t.y - math.floor(math.sin(rad) * (BARREL_LEN + 8))
    if not charging then
      if math.floor(frame() / 5) % 2 == 0 then line(scr, gx, gy, gx2, gy2, 10) end
    else
      line(scr, gx, gy, gx2, gy2, 15)
    end
  end
end

local function draw_ready_panel(label_y, sub_y)
  local cx = math.floor(SCR_W / 2)
  local lx = math.floor(SCR_W / 2 - 32)
  local rx = math.floor(SCR_W / 2 + 32)
  text(scr, "P1", lx, label_y, 15, ALIGN_HCENTER)
  text(scr, "P2", rx, label_y, 15, ALIGN_HCENTER)
  local r1 = ready[1] and "READY" or "PRESS A"
  local r2 = ready[2] and "READY" or "PRESS A"
  text(scr, r1, lx, sub_y, ready[1] and 11 or 8, ALIGN_HCENTER)
  text(scr, r2, rx, sub_y, ready[2] and 11 or 8, ALIGN_HCENTER)
end

local function draw_title()
  local cx = math.floor(SCR_W / 2)
  text(scr, "SCORCH 2P",       cx, 22, 12, ALIGN_HCENTER)
  text(scr, "BEST OF 5",       cx, 38, 7,  ALIGN_HCENTER)
  text(scr, "FIRST TO 3 WINS", cx, 48, 7,  ALIGN_HCENTER)
  draw_ready_panel(70, 82)
  if math.floor(frame() / 30) % 2 == 0 then
    text(scr, "BOTH PRESS A TO START", cx, 102, 10, ALIGN_HCENTER)
  end
end

local function draw_match_over()
  local cx = math.floor(SCR_W / 2)
  rectf(scr, 8, 14, SCR_W - 16, SCR_H - 28, 0)
  rect(scr,  8, 14, SCR_W - 16, SCR_H - 28, 15)
  text(scr, "MATCH OVER", cx, 22, 15, ALIGN_HCENTER)
  text(scr, "P" .. match_winner .. " WINS",
       cx, 34, match_winner == 1 and 15 or 8, ALIGN_HCENTER)
  text(scr, score[1] .. " - " .. score[2], cx, 46, 12, ALIGN_HCENTER)
  text(scr, "REMATCH?", cx, 62, 7, ALIGN_HCENTER)
  draw_ready_panel(76, 88)
end

-- Score "balls" — 3 slots per side, filled per win. Drawn in the top
-- HUD bar next to the player label.
local function draw_score_dots()
  for i = 0, WINS_TO_TAKE_MATCH - 1 do
    local lx = 13 + i * 5
    local rx = SCR_W - 16 - i * 5
    if i < score[1] then rectf(scr, lx, 3, 3, 3, 11)
    else                  rect(scr, lx, 3, 3, 3, 4) end
    if i < score[2] then rectf(scr, rx, 3, 3, 3, 11)
    else                  rect(scr, rx, 3, 3, 3, 4) end
  end
end

local function draw_round_end_overlay()
  -- apex marker for the last shot (world-space, in-camera)
  if last_apex_x and last_apex_y then
    local ax = world_to_screen(math.floor(last_apex_x))
    local ay = math.floor(last_apex_y)
    if ax > -3 and ax < SCR_W + 3 then
      circ(scr, ax, ay, 2, 12)
      pix(scr, ax, ay, 15)
    end
  end

  local cx = math.floor(SCR_W / 2)
  local cy = math.floor(SCR_H / 2)
  rectf(scr, cx - 50, cy - 18, 100, 36, 0)
  rect(scr,  cx - 50, cy - 18, 100, 36, 15)
  text(scr, "ROUND TO P" .. round_winner,
       cx, cy - 10, round_winner == 1 and 15 or 8, ALIGN_HCENTER)
  -- badge: DIRECT HIT if final shot > 35 dmg, else KO
  local badge = (last_shot_dmg and last_shot_dmg > 35) and "DIRECT HIT" or "KO"
  local badge_c = (last_shot_dmg and last_shot_dmg > 35) and 15 or 10
  text(scr, badge, cx, cy, badge_c, ALIGN_HCENTER)
  text(scr, score[1] .. " - " .. score[2], cx, cy + 10, 12, ALIGN_HCENTER)
end

function _draw()
  cls(scr, SKY_COLOR)

  if not game_started then
    -- Engine paints its own CONNECTING / WAITING FOR PEER overlay; draw
    -- the title text underneath so the screen isn't blank.
    text(scr, "SCORCH 2P", math.floor(SCR_W / 2), 55, 12, ALIGN_HCENTER)
    return
  end

  if match_phase == "title" then
    draw_title(); return
  end

  if match_phase == "match_over" then
    draw_match_over(); return
  end

  draw_terrain()
  draw_wind_indicator()

  for i = 1, 2 do
    local t  = p[i]
    local sx = world_to_screen(t.x)
    if sx > -TANK_W and sx < SCR_W + TANK_W then
      draw_tank(t, i, sx)
    end
  end

  -- trajectory preview (while charging)
  if state == "aim" and charging and #preview_pts > 0 then
    for _, pt in ipairs(preview_pts) do
      local psx = world_to_screen(math.floor(pt.x))
      local psy = math.floor(pt.y)
      if psx >= 0 and psx < SCR_W and psy >= 0 and psy < SCR_H then
        pix(scr, psx, psy, 7)
      end
    end
  end

  if state == "fire" and proj then
    local tlen = #proj.trail
    for ti, pt in ipairs(proj.trail) do
      local sx = world_to_screen(math.floor(pt.x))
      local sy = math.floor(pt.y)
      if sx >= 0 and sx < SCR_W and sy >= 0 and sy < SCR_H then
        local age = tlen - ti
        local tc  = age < 5 and 15 or (age < 15 and 10 or (age < 40 and 7 or 4))
        pix(scr, sx, sy, tc)
      end
    end
    local psx = world_to_screen(math.floor(proj.x))
    local psy = math.floor(proj.y)
    if psx > -5 and psx < SCR_W + 5 then
      circf(scr, psx, psy, 3, 0)
      circf(scr, psx, psy, 2, 15)
    end
  end

  if state == "explode" then
    local esx = world_to_screen(explode_x)
    if esx > -EXPLOSION_R and esx < SCR_W + EXPLOSION_R then
      if explode_timer > 8 then
        local r = math.floor((15 - explode_timer) / 15 * EXPLOSION_R)
        circf(scr, esx, explode_y, r, 15)
      elseif explode_timer > 4 then
        circf(scr, esx, explode_y, EXPLOSION_R, 12)
        circf(scr, esx, explode_y, math.floor(EXPLOSION_R * 0.6), 15)
      else
        circ(scr, esx, explode_y, EXPLOSION_R, 8)
      end
    end
  end

  draw_hud()
  draw_score_dots()

  if dmg_timer > 0 then
    local dsx = world_to_screen(explode_x)
    text(scr, dmg_text, dsx - 5, explode_y - 15 - (40 - dmg_timer), 15)
  end

  if scouting then
    text(scr, "< SCOUT >", math.floor(SCR_W / 2), SCR_H - 8, 10, ALIGN_HCENTER)
  end

  if state == "round_end" then draw_round_end_overlay() end
end
