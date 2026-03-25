-- Pac-Man for Mono Engine v2 (Lua) — ECS migration

local W = 320
local H = 240

-- 8->16 upscale helper (doubles each pixel in an 8x8 flat string to 16x16)
local function up(d)
  local o = ""
  for r = 0, 7 do
    local row = ""
    for c = 0, 7 do
      local ch = d:sub(r * 8 + c + 1, r * 8 + c + 1)
      row = row .. ch .. ch
    end
    o = o .. row .. row
  end
  return o
end

-- Sprites (16x16 via up())
-- Pac-Man open mouth right
defSprite(1, up(
  "00333000" ..
  "03333300" ..
  "33333000" ..
  "33330000" ..
  "33333000" ..
  "03333300" ..
  "00333000" ..
  "00000000"
))
-- Pac-Man closed (full circle)
defSprite(2, up(
  "00333000" ..
  "03333300" ..
  "33333300" ..
  "33333300" ..
  "33333300" ..
  "03333300" ..
  "00333000" ..
  "00000000"
))
-- Pac-Man open mouth up
defSprite(3, up(
  "00300300" ..
  "03003030" ..
  "03303330" ..
  "03333330" ..
  "33333330" ..
  "33333330" ..
  "03333300" ..
  "00333000"
))
-- Pac-Man open mouth down
defSprite(4, up(
  "00333000" ..
  "03333300" ..
  "33333330" ..
  "33333330" ..
  "03333330" ..
  "03303330" ..
  "03003030" ..
  "00300300"
))

-- Ghost 0 (Blinky) - brightest
defSprite(10, up(
  "00333300" ..
  "03333330" ..
  "30033003" ..
  "30033003" ..
  "33333333" ..
  "33333333" ..
  "33333333" ..
  "30300303"
))
-- Ghost 1 (Pinky) - medium-light
defSprite(11, up(
  "00222200" ..
  "02222220" ..
  "23022302" ..
  "23022302" ..
  "22222222" ..
  "22222222" ..
  "22222222" ..
  "20200202"
))
-- Ghost 2 (Inky) - medium
defSprite(12, up(
  "00222200" ..
  "02222220" ..
  "20022002" ..
  "20022002" ..
  "22222222" ..
  "22222222" ..
  "22222222" ..
  "20200202"
))
-- Ghost 3 (Clyde) - darkest
defSprite(13, up(
  "00111100" ..
  "01111110" ..
  "13011301" ..
  "13011301" ..
  "11111111" ..
  "11111111" ..
  "11111111" ..
  "10100101"
))
-- Vulnerable ghost
defSprite(14, up(
  "00111100" ..
  "01111110" ..
  "10011001" ..
  "11111111" ..
  "11111111" ..
  "10100101" ..
  "01011010" ..
  "10100101"
))
-- Ghost eyes (eaten)
defSprite(15, up(
  "00000000" ..
  "00000000" ..
  "03003000" ..
  "03003000" ..
  "00000000" ..
  "00000000" ..
  "00000000" ..
  "00000000"
))
-- Fruit (cherry)
defSprite(20, up(
  "00000300" ..
  "00003000" ..
  "00230200" ..
  "02302020" ..
  "02200220" ..
  "02200220" ..
  "00200020" ..
  "00000000"
))

-- Maze constants
local TILE = 8
local SS = 16

-- 0=empty 1=wall 2=dot 3=power 4=ghostdoor 5=tunnel
local M = {
  {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1},
  {1,2,2,2,2,1,2,2,2,2,2,2,2,2,2,1,2,2,2,2,1},
  {1,2,1,1,2,1,2,1,1,1,1,1,1,2,1,2,1,1,2,2,1},
  {1,3,1,1,2,2,2,2,2,2,2,2,2,2,2,2,1,1,2,3,1},
  {1,2,1,1,2,1,2,1,2,1,1,1,2,1,2,1,2,1,1,2,1},
  {1,2,2,2,2,1,2,1,2,2,1,2,2,1,2,1,2,2,2,2,1},
  {1,1,1,1,2,1,2,1,1,2,1,2,1,1,2,1,2,1,1,1,1},
  {0,0,0,1,2,1,2,2,2,2,2,2,2,2,2,1,2,1,0,0,0},
  {1,1,1,1,2,1,2,1,1,4,1,4,1,1,2,1,2,1,1,1,1},
  {5,0,0,0,2,0,2,1,0,0,0,0,0,1,2,0,2,0,0,0,5},
  {1,1,1,1,2,1,2,1,0,0,0,0,0,1,2,1,2,1,1,1,1},
  {0,0,0,1,2,1,2,1,1,1,1,1,1,1,2,1,2,1,0,0,0},
  {1,1,1,1,2,1,2,2,2,2,2,2,2,2,2,1,2,1,1,1,1},
  {1,2,2,2,2,2,2,1,1,2,1,2,1,1,2,2,2,2,2,2,1},
  {1,2,1,1,2,1,2,2,2,2,1,2,2,2,2,1,2,1,1,2,1},
  {1,2,2,1,2,1,1,1,1,2,1,2,1,1,1,1,2,1,2,2,1},
  {1,1,2,1,2,2,2,2,2,2,2,2,2,2,2,2,2,1,2,1,1},
  {1,2,2,1,2,1,2,1,1,1,1,1,1,1,2,1,2,1,2,2,1},
  {1,2,1,1,2,1,2,2,2,2,2,2,2,2,2,1,2,1,1,2,1},
  {1,3,2,2,2,2,2,1,1,2,1,2,1,1,2,2,2,2,2,3,1},
  {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1},
}

local ROWS = #M        -- 21
local COLS = #M[1]     -- 21
local MX = flr((W - COLS * TILE) / 2)
local MY = flr((H - ROWS * TILE) / 2) + 6

-- Collision radii
local PAC_R = 5
local GHOST_R = 5

-- Direction vectors: 0=right 1=down 2=left 3=up
local DX = {[0]=1, [1]=0, [2]=-1, [3]=0}
local DY = {[0]=0, [1]=1, [2]=0, [3]=-1}
local OPP = {[0]=2, [1]=3, [2]=0, [3]=1}

-- Sprite offset for centering 16x16 on 8x8 tile
local SPR_OFF = (SS - TILE) / 2  -- 4

-- Dot tracking
local dots = {}
local totalDots = 0
local dotsEaten = 0

-- Game state
local score = 0
local lives = 3
local level = 1
local hiScore = 0
local powerTimer = 0
local ghostEatCombo = 0
local fruit = nil
local fruitTimer = 0
local deathTimer = 0
local readyTimer = 0
local levelClearTimer = 0
local modeTimer = 0
local globalMode = "scatter"

-- Pac-Man game state (non-ECS fields)
local pac = {}

-- Ghost game state table (indexed 0-3, holds AI/movement data)
local ghosts = {}

-- ECS entity references
local pacEntity = nil

-- Helper: get maze value (0-indexed col/row)
local function mval(c, r)
  if r < 0 or r >= ROWS then return -1 end
  if c < 0 or c >= COLS then return -1 end
  return M[r + 1][c + 1]
end

local function isWall(c, r)
  if r < 0 or r >= ROWS then return true end
  if c < 0 or c >= COLS then return false end  -- tunnel
  return M[r + 1][c + 1] == 1
end

local function isWalkable(c, r)
  if r < 0 or r >= ROWS then return false end
  if c < 0 or c >= COLS then return true end  -- tunnel wrap
  return M[r + 1][c + 1] ~= 1
end

local function isGhostWalkable(c, r, canPassDoor)
  if r < 0 or r >= ROWS then return false end
  if c < 0 or c >= COLS then return true end
  local v = M[r + 1][c + 1]
  if v == 1 then return false end
  if v == 4 and not canPassDoor then return false end
  return true
end

local function wrapCol(c)
  if c < 0 then return COLS - 1 end
  if c >= COLS then return 0 end
  return c
end

local function dist2(c1, r1, c2, r2)
  return (c1 - c2) * (c1 - c2) + (r1 - r2) * (r1 - r2)
end

-- Sound helpers
local sndQueue = {}

local function sndDot() note(0, "E5", 0.02) end

local function sndPower()
  note(0, "C4", 0.08)
  sndQueue[#sndQueue + 1] = { t = frame() + 4, ch = 0, n = "E4", d = 0.08 }
end

local function sndGhost()
  note(0, "G5", 0.04)
  sndQueue[#sndQueue + 1] = { t = frame() + 3, ch = 0, n = "B5", d = 0.04 }
  sndQueue[#sndQueue + 1] = { t = frame() + 5, ch = 0, n = "D6", d = 0.06 }
end

local function sndDeath()
  note(0, "E4", 0.08)
  sndQueue[#sndQueue + 1] = { t = frame() + 5, ch = 0, n = "D4", d = 0.08 }
  sndQueue[#sndQueue + 1] = { t = frame() + 10, ch = 0, n = "C4", d = 0.08 }
  sndQueue[#sndQueue + 1] = { t = frame() + 15, ch = 0, n = "B3", d = 0.15 }
  sndQueue[#sndQueue + 1] = { t = frame() + 15, ch = 1, n = "E3", d = 0.2 }
end

local function sndFruit()
  note(0, "C5", 0.04)
  sndQueue[#sndQueue + 1] = { t = frame() + 3, ch = 0, n = "E5", d = 0.04 }
  sndQueue[#sndQueue + 1] = { t = frame() + 5, ch = 0, n = "G5", d = 0.06 }
end

local function sndClear()
  note(0, "C5", 0.06)
  sndQueue[#sndQueue + 1] = { t = frame() + 5, ch = 0, n = "E5", d = 0.06 }
  sndQueue[#sndQueue + 1] = { t = frame() + 10, ch = 0, n = "G5", d = 0.06 }
  sndQueue[#sndQueue + 1] = { t = frame() + 15, ch = 0, n = "C6", d = 0.12 }
end

local function processSndQueue()
  local f = frame()
  local i = 1
  while i <= #sndQueue do
    if f >= sndQueue[i].t then
      note(sndQueue[i].ch, sndQueue[i].n, sndQueue[i].d)
      table.remove(sndQueue, i)
    else
      i = i + 1
    end
  end
end

-- Parse maze dots
local function parseMaze()
  dots = {}
  totalDots = 0
  dotsEaten = 0
  for r = 0, ROWS - 1 do
    dots[r] = {}
    for c = 0, COLS - 1 do
      local v = M[r + 1][c + 1]
      if v == 2 or v == 3 then
        dots[r][c] = v
        totalDots = totalDots + 1
      else
        dots[r][c] = 0
      end
    end
  end
end

-- Compute the correct sprite for Pac-Man based on current state
local function pacSpriteId()
  if not pac.mouthOpen then
    return 2
  elseif pac.dir == 0 then
    return 1
  elseif pac.dir == 2 then
    return 1  -- flipX handled separately
  elseif pac.dir == 3 then
    return 3
  else
    return 4
  end
end

-- Compute the correct sprite for a ghost based on current state
local function ghostSpriteId(g)
  if g.eaten then
    return 15
  elseif powerTimer > 0 then
    if powerTimer < 90 and frame() % 10 < 5 then
      return g.sprId
    else
      return 14
    end
  else
    return g.sprId
  end
end

-- Screen coordinate helpers
local function screenX(px) return MX + px - SPR_OFF end
local function screenY(py) return MY + py - SPR_OFF end

-- Spawn ECS entities for pac-man and ghosts
local function spawnEntities()
  -- Spawn Pac-Man entity
  pacEntity = spawn({
    group = "pacman",
    pos = { x = screenX(pac.px), y = screenY(pac.py) },
    sprite = pacSpriteId(),
    hitbox = { r = PAC_R },
    flipX = (pac.dir == 2),
  })

  -- Spawn ghost entities
  for i = 0, 3 do
    local g = ghosts[i]
    g.entity = spawn({
      group = "ghost",
      pos = { x = screenX(g.px), y = screenY(g.py) },
      sprite = ghostSpriteId(g),
      hitbox = { r = GHOST_R },
      idx = i,
    })
  end

  -- Register collision handlers
  onCollide("pacman", "ghost", function(p, g)
    if not pac.alive then return end
    -- Find which ghost this entity belongs to
    local ghost = nil
    for i = 0, 3 do
      if ghosts[i].entity == g then
        ghost = ghosts[i]
        break
      end
    end
    if not ghost or ghost.eaten then return end

    if powerTimer > 0 then
      ghost.eaten = true
      ghostEatCombo = ghostEatCombo + 1
      score = score + 200 * (2 ^ (ghostEatCombo - 1))
      sndGhost()
    else
      pac.alive = false
      deathTimer = 60
      sndDeath()
    end
  end)

  onCollide("pacman", "fruit", function(p, f)
    score = score + 100
    fruit = nil
    kill(f)
    sndFruit()
  end)
end

local function resetPositions()
  powerTimer = 0
  ghostEatCombo = 0
  fruit = nil
  fruitTimer = 0

  pac = {
    col = 10, row = 16,
    px = 10 * TILE, py = 16 * TILE,
    dir = 2, nextDir = 2,
    moving = false,
    mouthOpen = true,
    mouthTimer = 0,
    alive = true
  }

  ghosts = {
    [0] = { col = 10, row = 7, px = 10*TILE, py = 7*TILE, dir = 2, sprId = 10, homeCol = 19, homeRow = 0, inPen = false, eaten = false, exitTimer = 0 },
    [1] = { col = 10, row = 9, px = 10*TILE, py = 9*TILE, dir = 0, sprId = 11, homeCol = 1, homeRow = 0, inPen = true, eaten = false, exitTimer = 90 },
    [2] = { col = 9, row = 9, px = 9*TILE, py = 9*TILE, dir = 0, sprId = 12, homeCol = 19, homeRow = 20, inPen = true, eaten = false, exitTimer = 180 },
    [3] = { col = 11, row = 9, px = 11*TILE, py = 9*TILE, dir = 0, sprId = 13, homeCol = 1, homeRow = 20, inPen = true, eaten = false, exitTimer = 250 },
  }

  -- Kill all existing ECS entities and respawn
  killAll("pacman")
  killAll("ghost")
  killAll("fruit")
  clearCollisions()
  spawnEntities()
end

local function pacSpeed()
  if powerTimer > 0 then return 2 else return 1 end
end

local function ghostSpd(g)
  if g.eaten then return 2 end
  if g.inPen then return 0 end
  if powerTimer > 0 then return 0.5 + level * 0.05 end
  return 0.6 + level * 0.06
end

local function getTarget(g, idx)
  if g.eaten then return 10, 9 end

  if powerTimer > 0 then
    return flr(rnd(COLS)), flr(rnd(ROWS))
  end

  if globalMode == "scatter" then
    return g.homeCol, g.homeRow
  end

  if idx == 0 then
    return pac.col, pac.row
  elseif idx == 1 then
    return pac.col + DX[pac.dir] * 4, pac.row + DY[pac.dir] * 4
  elseif idx == 2 then
    return flr(rnd(COLS)), flr(rnd(ROWS))
  elseif idx == 3 then
    if dist2(g.col, g.row, pac.col, pac.row) > 64 then
      return pac.col, pac.row
    end
    return g.homeCol, g.homeRow
  end
  return pac.col, pac.row
end

local function chooseDir(g, idx)
  local tc, tr = getTarget(g, idx)
  local canPass = g.eaten or g.inPen
  local bestDir = g.dir
  local bestDist = 999999
  local order = {3, 2, 1, 0}
  for _, d in ipairs(order) do
    if not (d == OPP[g.dir] and not g.eaten) then
      local nc = wrapCol(g.col + DX[d])
      local nr = g.row + DY[d]
      if isGhostWalkable(nc, nr, canPass) then
        local dd = dist2(nc, nr, tc, tr)
        if dd < bestDist then
          bestDist = dd
          bestDir = d
        end
      end
    end
  end
  return bestDir
end

local function resetGame()
  score = 0
  lives = 3
  level = 1
  parseMaze()
  resetPositions()
  readyTimer = 60
  levelClearTimer = 0
  deathTimer = 0
  modeTimer = 0
  globalMode = "scatter"
end

local function nextLevel()
  level = level + 1
  parseMaze()
  resetPositions()
  readyTimer = 60
  levelClearTimer = 0
  deathTimer = 0
  modeTimer = 0
  globalMode = "scatter"
end

-- Update Pac-Man
local function updatePac()
  if not pac.alive then return end

  if btn("left") then pac.nextDir = 2
  elseif btn("right") then pac.nextDir = 0
  elseif btn("up") then pac.nextDir = 3
  elseif btn("down") then pac.nextDir = 1 end

  local speed = pacSpeed()
  local atX = pac.px % TILE == 0
  local atY = pac.py % TILE == 0

  if atX and atY then
    pac.col = math.floor(pac.px / TILE + 0.5)
    pac.row = math.floor(pac.py / TILE + 0.5)

    -- Tunnel wrap
    if pac.col < 0 then pac.col = COLS - 1; pac.px = pac.col * TILE end
    if pac.col >= COLS then pac.col = 0; pac.px = 0 end

    -- Try desired direction
    local nc1 = wrapCol(pac.col + DX[pac.nextDir])
    local nr1 = pac.row + DY[pac.nextDir]
    if isWalkable(nc1, nr1) then
      pac.dir = pac.nextDir
      pac.moving = true
    else
      local nc2 = wrapCol(pac.col + DX[pac.dir])
      local nr2 = pac.row + DY[pac.dir]
      if not isWalkable(nc2, nr2) then
        pac.moving = false
      end
    end

    -- Eat dot
    if pac.row >= 0 and pac.row < ROWS and pac.col >= 0 and pac.col < COLS then
      local d = dots[pac.row][pac.col]
      if d == 2 then
        dots[pac.row][pac.col] = 0
        dotsEaten = dotsEaten + 1
        score = score + 10
        sndDot()
      elseif d == 3 then
        dots[pac.row][pac.col] = 0
        dotsEaten = dotsEaten + 1
        score = score + 50
        powerTimer = math.max(90, 300 - level * 30)
        ghostEatCombo = 0
        sndPower()
        for i = 0, 3 do
          local g = ghosts[i]
          if not g.eaten and not g.inPen then
            g.dir = OPP[g.dir]
          end
        end
      end
    end
  end

  if pac.moving then
    pac.px = pac.px + DX[pac.dir] * speed
    pac.py = pac.py + DY[pac.dir] * speed
    -- Tunnel
    if pac.px < -TILE then pac.px = COLS * TILE end
    if pac.px > COLS * TILE then pac.px = -TILE end
  end

  pac.mouthTimer = pac.mouthTimer + 1
  if pac.mouthTimer > 4 then
    pac.mouthTimer = 0
    pac.mouthOpen = not pac.mouthOpen
  end

  -- Update ECS entity position and sprite
  if pacEntity then
    pacEntity.pos.x = screenX(pac.px)
    pacEntity.pos.y = screenY(pac.py)
    pacEntity.sprite = pacSpriteId()
    pacEntity.flipX = (pac.dir == 2)
  end
end

-- Update ghosts
local function updateGhosts()
  modeTimer = modeTimer + 1
  if modeTimer < 210 then globalMode = "scatter"
  elseif modeTimer < 810 then globalMode = "chase"
  elseif modeTimer < 1020 then globalMode = "scatter"
  else globalMode = "chase" end
  if modeTimer > 1620 then modeTimer = 810 end

  for i = 0, 3 do
    local g = ghosts[i]
    local speed = ghostSpd(g)

    if g.inPen then
      g.exitTimer = g.exitTimer - 1
      if g.exitTimer <= 0 then
        g.inPen = false
        g.col = 10; g.row = 7
        g.px = g.col * TILE; g.py = g.row * TILE
        g.dir = 2
      else
        g.py = g.row * TILE + math.sin(frame() * 0.15) * 2
        -- Update ECS entity position and sprite
        if g.entity then
          g.entity.pos.x = screenX(g.px)
          g.entity.pos.y = screenY(g.py)
          g.entity.sprite = ghostSpriteId(g)
        end
        goto continue_ghost
      end
    end

    if speed <= 0 then
      -- Update ECS entity sprite even when not moving
      if g.entity then
        g.entity.sprite = ghostSpriteId(g)
      end
      goto continue_ghost
    end

    local atX = abs(g.px - g.col * TILE) < speed + 0.01
    local atY = abs(g.py - g.row * TILE) < speed + 0.01
    local skipMove = false

    if atX and atY then
      g.px = g.col * TILE
      g.py = g.row * TILE

      g.col = wrapCol(g.col)

      -- Eaten ghost returned to pen
      if g.eaten and g.row >= 8 and g.row <= 10 and g.col >= 9 and g.col <= 11 then
        g.eaten = false
        g.inPen = true
        g.exitTimer = 30
        g.col = 10; g.row = 9
        g.px = g.col * TILE; g.py = g.row * TILE
        -- Update ECS entity
        if g.entity then
          g.entity.pos.x = screenX(g.px)
          g.entity.pos.y = screenY(g.py)
          g.entity.sprite = ghostSpriteId(g)
        end
        skipMove = true
      end

      if not skipMove then
        g.dir = chooseDir(g, i)

        local nc = wrapCol(g.col + DX[g.dir])
        local nr = g.row + DY[g.dir]
        if isGhostWalkable(nc, nr, g.eaten or g.inPen) then
          g.col = nc
          g.row = nr
        end
      end
    end

    if not skipMove then
      -- Move toward target tile
      local tx = g.col * TILE
      local ty = g.row * TILE
      if g.px < tx then g.px = math.min(g.px + speed, tx)
      elseif g.px > tx then g.px = math.max(g.px - speed, tx) end
      if g.py < ty then g.py = math.min(g.py + speed, ty)
      elseif g.py > ty then g.py = math.max(g.py - speed, ty) end

      -- Update ECS entity position and sprite
      if g.entity then
        g.entity.pos.x = screenX(g.px)
        g.entity.pos.y = screenY(g.py)
        g.entity.sprite = ghostSpriteId(g)
      end
    end
    ::continue_ghost::
  end
end

-- Update play scene
local function updatePlay()
  processSndQueue()

  if readyTimer > 0 then readyTimer = readyTimer - 1; return end
  if levelClearTimer > 0 then
    levelClearTimer = levelClearTimer - 1
    if levelClearTimer == 0 then nextLevel() end
    return
  end
  if deathTimer > 0 then
    deathTimer = deathTimer - 1
    if deathTimer == 0 then
      lives = lives - 1
      if lives <= 0 then
        if score > hiScore then hiScore = score end
        go("gameover")
        return
      end
      resetPositions()
      readyTimer = 60
    end
    return
  end

  if powerTimer > 0 then powerTimer = powerTimer - 1 end

  updatePac()
  updateGhosts()

  -- Fruit spawning via ECS
  fruitTimer = fruitTimer + 1
  if not fruit and fruitTimer > 300 + flr(rnd(300)) then
    fruit = { col = 10, row = 13, timer = 300 }
    fruit.entity = spawn({
      group = "fruit",
      pos = { x = screenX(fruit.col * TILE), y = screenY(fruit.row * TILE) },
      sprite = 20,
      hitbox = { r = PAC_R },
    })
    fruitTimer = 0
  end
  if fruit then
    fruit.timer = fruit.timer - 1
    if fruit.timer <= 0 then
      if fruit.entity then kill(fruit.entity) end
      fruit = nil
    end
  end

  -- Level clear
  if dotsEaten >= totalDots then
    levelClearTimer = 90
    sndClear()
  end
end

-- Drawing functions
local function drawMaze()
  for r = 0, ROWS - 1 do
    for c = 0, COLS - 1 do
      local v = M[r + 1][c + 1]
      local x = MX + c * TILE
      local y = MY + r * TILE

      if v == 1 then
        rectf(x, y, TILE, TILE, 1)
        -- Draw edges where wall meets non-wall
        if c + 1 < COLS and M[r + 1][c + 2] ~= 1 then line(x + 7, y, x + 7, y + 7, 2) end
        if c - 1 >= 0 and M[r + 1][c] ~= 1 then line(x, y, x, y + 7, 2) end
        if r + 1 < ROWS and M[r + 2] and M[r + 2][c + 1] ~= 1 then line(x, y + 7, x + 7, y + 7, 2) end
        if r - 1 >= 0 and M[r] and M[r][c + 1] ~= 1 then line(x, y, x + 7, y, 2) end
      elseif v == 4 then
        rectf(x, y + 3, TILE, 2, 2)
      end
    end
  end
end

local function drawDots()
  for r = 0, ROWS - 1 do
    for c = 0, COLS - 1 do
      local d = dots[r][c]
      if d and d ~= 0 then
        local x = MX + c * TILE
        local y = MY + r * TILE
        if d == 2 then
          rectf(x + 3, y + 3, 2, 2, 3)
        elseif d == 3 then
          if frame() % 20 < 14 then
            circf(x + 4, y + 4, 3, 3)
          end
        end
      end
    end
  end
end

-- Death animation drawn manually (pac-man entity is hidden during death)
local function drawPacDeath()
  if not pac.alive and deathTimer > 0 then
    local f = 60 - deathTimer
    local r = math.max(0, 4 - flr(f / 8))
    if r > 0 then
      local cx = MX + pac.px + TILE / 2
      local cy = MY + pac.py + TILE / 2
      circf(cx, cy, r, 3)
    end
  end
end

local function drawHUD()
  text("SCORE " .. score, 3, 3, 3)
  text("HI " .. hiScore, W - 60, 3, 2)
  text("LV" .. level, flr(W / 2) - 12, 3, 2)
  local livesY = math.min(MY + ROWS * TILE + 4, H - 10)
  for i = 0, lives - 1 do
    circf(8 + i * 10, livesY, 3, 3)
    rectf(11 + i * 10, livesY - 2, 2, 2, 0)
  end
end

-- === TITLE SCENE ===

function title_update()
  processSndQueue()
  if btnp("a") or btnp("start") then
    go("play")
  end
end

function title_draw()
  cls(0)

  text("PAC-MAN", flr(W / 2) - 18, 30, 3)

  -- Big Pac-Man
  local cx = flr(W / 2)
  local cy = 90
  circf(cx, cy, 18, 3)
  if frame() % 30 < 18 then
    for y = -18, 18 do
      for x = 0, 18 do
        if x * x + y * y <= 324 and abs(y) < x * 0.55 then
          pix(cx + x, cy + y, 0)
        end
      end
    end
  end
  circf(cx + 5, cy - 9, 2, 0)

  -- Dots trail
  for i = 0, 5 do
    rectf(cx - 30 - i * 10, cy - 1, 2, 2, 3)
  end

  -- Ghosts chasing
  local gOff = flr(math.sin(frame() * 0.08) * 3)
  sprT(10, cx - 46 + gOff, cy - 8)
  sprT(11, cx - 62 + gOff, cy - 8)
  sprT(12, cx - 78 + gOff, cy - 8)
  sprT(13, cx - 94 + gOff, cy - 8)

  if frame() % 40 < 28 then
    text("PRESS START", flr(W / 2) - 50, 142, 3)
  end

  text("ARROW KEYS TO MOVE", flr(W / 2) - 45, 172, 2)
  text("EAT ALL DOTS TO WIN", flr(W / 2) - 48, 184, 2)
  text("POWER PELLETS LET", flr(W / 2) - 43, 196, 1)
  text("YOU EAT GHOSTS!", flr(W / 2) - 38, 206, 1)

  if hiScore > 0 then text("HI SCORE: " .. hiScore, flr(W / 2) - 35, 222, 2) end
end

-- === PLAY SCENE ===

function play_init()
  resetGame()
end

function play_update()
  -- Hide pac-man entity during death (ECS still draws it otherwise)
  if pacEntity then
    if not pac.alive then
      -- Move off-screen so ECS doesn't render it visibly
      pacEntity.pos.x = -100
      pacEntity.pos.y = -100
    end
  end

  updatePlay()
end

function play_draw()
  cls(0)
  drawMaze()
  drawDots()
  -- ECS auto-draws pacman, ghost, and fruit entities (via pos+sprite)
  -- Death animation is special-cased
  drawPacDeath()
  drawHUD()

  if readyTimer > 0 then
    text("READY!", flr(W / 2) - 15, MY + 13 * TILE, 3)
  end
  if levelClearTimer > 0 and frame() % 10 < 6 then
    text("LEVEL CLEAR!", flr(W / 2) - 30, MY + 13 * TILE, 3)
  end
end

-- === GAME OVER SCENE ===

function gameover_update()
  processSndQueue()
  if btnp("a") or btnp("start") then
    go("title")
  end
end

function gameover_draw()
  cls(0)
  text("GAME OVER", flr(W / 2) - 23, 82, 3)
  text("SCORE: " .. score, flr(W / 2) - 25, 109, 2)
  if score >= hiScore and score > 0 then
    text("NEW HIGH SCORE!", flr(W / 2) - 38, 126, 3)
  end
  if frame() % 40 < 28 then
    text("PRESS START", flr(W / 2) - 28, 158, 2)
  end
end
