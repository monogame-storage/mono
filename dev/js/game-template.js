// ── Default files seeded into every new game ──
// Minimal runnable skeleton that demonstrates scene transitions (btnr),
// sound (note / tone), and text anchors.

const mainLua = `-- Entry point. Boot into the title scene.
function _init()
  mode(4)  -- 16-color grayscale
end

function _ready()
  go("title")
end
`;

const titleLua = `-- Title scene. Press START to begin.
local scr = screen()
local scene = {}
local blink = 0

function scene.init()
  blink = 0
end

function scene.update()
  blink = blink + 1
  if btnr("start") then
    note(0, "E5", 0.08)
    go("game")
  end
end

function scene.draw()
  cls(scr, 1)
  text(scr, "MY GAME", 80, 40, 15, ALIGN_CENTER)
  if math.floor(blink / 20) % 2 == 0 then
    text(scr, "PRESS START", 80, 80, 10, ALIGN_CENTER)
  end
  text(scr, "V1.0", 158, 116, 5, ALIGN_RIGHT + ALIGN_VCENTER)
end

return scene
`;

const gameLua = `-- Gameplay scene. A to score, B to end.
local scr = screen()
local scene = {}
local score = 0

function scene.init()
  score = 0
end

function scene.update()
  if btnp("a") then
    score = score + 1
    note(0, "C5", 0.05)
  end
  if btnr("b") then
    go("gameover")
  end
end

function scene.draw()
  cls(scr, 2)
  text(scr, "SCORE " .. score, 4, 4, 15)
  text(scr, "A = SCORE   B = END", 80, 110, 7, ALIGN_HCENTER)
end

return scene
`;

const gameoverLua = `-- Game over. Press START to return to title.
local scr = screen()
local scene = {}
local blink = 0

function scene.init()
  blink = 0
  tone(0, 800, 200, 0.4)
end

function scene.update()
  blink = blink + 1
  if btnr("start") then
    go("title")
  end
end

function scene.draw()
  cls(scr, 0)
  text(scr, "GAME OVER", 80, 50, 15, ALIGN_CENTER)
  if math.floor(blink / 20) % 2 == 0 then
    text(scr, "PRESS START", 80, 80, 8, ALIGN_CENTER)
  end
end

return scene
`;

export const DEFAULT_GAME_FILES = [
  { name: "main.lua", content: mainLua },
  { name: "title.lua", content: titleLua },
  { name: "game.lua", content: gameLua },
  { name: "gameover.lua", content: gameoverLua },
];
