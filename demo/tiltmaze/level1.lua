-- Level 1: first maze
-- Demonstrates canvas prerendering + blit per frame
local scr = screen()

-- Maze layout: 20x15 grid of 8px tiles (160x120)
-- # = wall, . = floor, S = start, G = goal
local MAZE = {
  "####################",
  "#S.................#",
  "#.####.#######.#####",
  "#....#.#.....#.....#",
  "####.#.#.###.#####.#",
  "#....#...#.#.....#.#",
  "#.####.###.###.#.#.#",
  "#.#.......#...##.#.#",
  "#.#.#####.#.####.#.#",
  "#...#.....#....#.#.#",
  "#.#.#.....#..#.#...#",
  "#.#.#####.####.#####",
  "#.###.#.##.#####.#.#",
  "#...#.#....#.....#.#",
  "###################G",
}

local TILE = 8
local maze_canvas  -- prerendered maze background
local ball_x, ball_y
local ball_vx, ball_vy
local level1_t          -- per-level timer (frames)
local transition_t      -- post-goal white-flash fade countdown
local goal_x, goal_y    -- pixel center of the goal tile (for arrow indicator)

local function tile_at(tx, ty)
  if ty < 1 or ty > #MAZE then return "#" end
  local row = MAZE[ty]
  if tx < 1 or tx > #row then return "#" end
  return row:sub(tx, tx)
end

local function is_wall(px, py)
  local tx = math.floor(px / TILE) + 1
  local ty = math.floor(py / TILE) + 1
  return tile_at(tx, ty) == "#"
end

local function find_tile(ch)
  for ty = 1, #MAZE do
    for tx = 1, #MAZE[ty] do
      if MAZE[ty]:sub(tx, tx) == ch then
        return (tx - 1) * TILE + TILE / 2,
               (ty - 1) * TILE + TILE / 2
      end
    end
  end
end

function level1_init()
  -- Prerender maze to an offscreen canvas once (coverage: canvas, canvas_w/h)
  maze_canvas = canvas(SCREEN_W, SCREEN_H)
  local mw = canvas_w(maze_canvas)
  local mh = canvas_h(maze_canvas)
  cls(maze_canvas, 0)
  for ty = 1, #MAZE do
    for tx = 1, #MAZE[ty] do
      local ch = MAZE[ty]:sub(tx, tx)
      local px = (tx - 1) * TILE
      local py = (ty - 1) * TILE
      if ch == "#" then
        rectf(maze_canvas, px, py, TILE, TILE, 7)
        rect(maze_canvas, px, py, TILE, TILE, 8)
      elseif ch == "G" then
        rectf(maze_canvas, px, py, TILE, TILE, 11)
        circf(maze_canvas, px + TILE/2, py + TILE/2, 2, 14)
      end
    end
  end

  ball_x, ball_y = find_tile("S")
  ball_vx = 0
  ball_vy = 0
  level1_t = 0
  transition_t = 0
  goal_x, goal_y = find_tile("G")
end

function level1_update()
  -- Mid-transition: just count down. No input, no physics.
  if transition_t > 0 then
    transition_t = transition_t - 1
    if transition_t <= 0 then
      canvas_del(maze_canvas)
      maze_canvas = nil
      go("level2")
    end
    return
  end

  level1_t = level1_t + 1

  -- SELECT = skip level (useful for testing + accessibility)
  if btnp("select") then
    canvas_del(maze_canvas)
    maze_canvas = nil
    go("level2")
    return
  end

  -- Analog tilt input (keyboard fallback via arrow keys)
  local ax = axis_x()
  local ay = axis_y()
  if btn("left")  then ax = ax - 1 end
  if btn("right") then ax = ax + 1 end
  if btn("up")    then ay = ay - 1 end
  if btn("down")  then ay = ay + 1 end

  ball_vx = ball_vx + ax * 0.2
  ball_vy = ball_vy + ay * 0.2
  ball_vx = ball_vx * 0.92
  ball_vy = ball_vy * 0.92

  -- Move X with wall collision (bounce sound only on meaningful impact)
  local prev_vx = ball_vx
  local new_x = ball_x + ball_vx
  if not is_wall(new_x, ball_y) then
    ball_x = new_x
  else
    ball_vx = 0
    if math.abs(prev_vx) > 0.5 then
      note(0, "C4", 0.02)
    end
  end

  local prev_vy = ball_vy
  local new_y = ball_y + ball_vy
  if not is_wall(ball_x, new_y) then
    ball_y = new_y
  else
    ball_vy = 0
    if math.abs(prev_vy) > 0.5 then
      note(0, "C4", 0.02)
    end
  end

  -- Check goal
  local tx = math.floor(ball_x / TILE) + 1
  local ty = math.floor(ball_y / TILE) + 1
  if tile_at(tx, ty) == "G" then
    -- Persist this level's time for the clear screen
    data_save("tiltmaze_level1_t", level1_t)
    tone(0, 600, 1200, 0.3)
    transition_t = 60
  end
end

function level1_draw()
  cls(scr, 0)

  -- Blit the prerendered maze (covers blit)
  blit(maze_canvas, scr, 0, 0)

  -- Goal arrow indicator (pulses every 30 frames)
  if goal_x and math.floor(frame() / 15) % 2 == 0 then
    text(scr, "->", goal_x - 6, goal_y - 3, 12)
  end

  -- Draw ball
  circf(scr, math.floor(ball_x), math.floor(ball_y), 2, 15)

  -- HUD
  cam(0, 0)
  text(scr, scene_name(), 2, 2, 14)
  text(scr, string.format("TIME %.1f", level1_t / 30),
       SCREEN_W - 2, 2, 14, ALIGN_RIGHT)

  -- Transition: white flash fading to gameplay
  if transition_t > 0 then
    local elapsed = 60 - transition_t
    local color = 15 - math.floor(elapsed / 4)
    if color < 0 then color = 0 end
    rectf(scr, 0, 0, SCREEN_W, SCREEN_H, color)
    text(scr, "LEVEL 1 CLEAR", 0, 50, 0, ALIGN_HCENTER)
  end
end
