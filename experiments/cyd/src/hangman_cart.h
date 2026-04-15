#pragma once
// Auto-generated from hangman cart

static const char* MAIN_LUA = R"ML(
-- 1-BIT HANGMAN
-- 160x144, Lua 5.4, mode 1 (black/white)

function _init()
  mode(1) -- 2 colors
end

function _start()
  math.randomseed(os.time())
end

function _ready()
  go("scenes/title")
end
)ML";

static const char* GAME_LUA = R"GL(
-- Hangman game logic + rendering (1-bit)

local M = {}
local scr = screen()

-- Word data loaded from external file for easy management.
local WORDS = require("words")

-- Deck-based shuffle so the same word doesn't repeat until all are used.
local deck = {}
local function refill_deck()
  deck = {}
  for i = 1, #WORDS do deck[i] = i end
  for i = #deck, 2, -1 do
    local j = math.random(i)
    deck[i], deck[j] = deck[j], deck[i]
  end
end
local function pop_word()
  if #deck == 0 then refill_deck() end
  local idx = table.remove(deck)
  return WORDS[idx]
end

-- Force the deck to refill on the next new_game call. Used on LOSE / full
-- reset so the player gets a fresh 50-word run.
function M.reset_deck()
  deck = {}
end

------------------------------------------------------------
-- difficulty config per level
------------------------------------------------------------
-- unmasked_total: number of alphabet letters visible/selectable; the rest
--                 are rendered as "masked" cells in the QWERTY grid.
-- No pre_guessed letters: the player always starts with every word letter
-- hidden. Difficulty comes from how much of the alphabet is masked.
--
-- Difficulty is controlled by the number of WRONG (decoy) keys shown.
-- More decoys = more chances to pick a wrong letter = harder.
-- This is independent of word length, so a 1-letter word and an 8-letter
-- word at the same level have the same number of traps.
-- Minimum 6 decoys so the player can always lose (6 wrong = death).
local DECOY_BY_LEVEL = {
  6, 6, 7, 7, 8,          -- LV 1-5
  8, 9, 9, 10, 10,        -- LV 6-10
  11, 11, 12, 12, 13,     -- LV 11-15
  13, 14, 14, 15, 16,     -- LV 16-20
  16, 17, 18, 19, 20,     -- LV 21-25
}

local function level_decoys(level)
  if level > 25 then return 99 end  -- LV26+: all remaining letters
  return DECOY_BY_LEVEL[level]
end

------------------------------------------------------------
-- QWERTY keyboard layout
------------------------------------------------------------
local QWERTY = {
  { "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P" },
  { "A", "S", "D", "F", "G", "H", "J", "K", "L" },
  { "Z", "X", "C", "V", "B", "N", "M" },
}
local ROW_OFFSET = { 0, 7, 21 }  -- px offset of each row relative to grid x0
local CELL_W, CELL_H = 14, 14
local GRID_X0 = 10
local GRID_Y0 = 68

function M.letter_at(col, row)
  local rd = QWERTY[row + 1]
  if not rd then return nil end
  return rd[col + 1]
end

function M.row_len(row)
  local rd = QWERTY[row + 1]
  return rd and #rd or 0
end

function M.cell_xy(col, row)
  return GRID_X0 + ROW_OFFSET[row + 1] + col * CELL_W, GRID_Y0 + row * CELL_H
end

------------------------------------------------------------
-- helpers
------------------------------------------------------------
local function shuffle(t)
  for i = #t, 2, -1 do
    local j = math.random(i)
    t[i], t[j] = t[j], t[i]
  end
end

local function unique_letters(word)
  local seen, list = {}, {}
  for i = 1, #word do
    local c = word:sub(i, i)
    if not seen[c] then
      seen[c] = true
      list[#list + 1] = c
    end
  end
  return list, seen
end

local function letter_is_selectable(g, letter)
  return g.selectable[letter] and not g.guessed[letter]
end

------------------------------------------------------------
-- cursor
------------------------------------------------------------
local function is_selectable_at(g, col, row)
  local l = M.letter_at(col, row)
  return l and letter_is_selectable(g, l)
end

-- Move cursor by direction. Masked/guessed cells are NOT skipped — movement
-- is simple wraparound. Pressing A on a masked cell is a no-op.
function M.move_cursor(g, dx, dy)
  if dx ~= 0 then
    local rl = M.row_len(g.cursor_r)
    g.cursor_c = g.cursor_c + dx
    if g.cursor_c < 0 then g.cursor_c = rl - 1 end
    if g.cursor_c >= rl then g.cursor_c = 0 end
  end
  if dy ~= 0 then
    local n = #QWERTY
    g.cursor_r = g.cursor_r + dy
    if g.cursor_r < 0 then g.cursor_r = n - 1 end
    if g.cursor_r >= n then g.cursor_r = 0 end
    local rl = M.row_len(g.cursor_r)
    if g.cursor_c >= rl then g.cursor_c = rl - 1 end
  end
end

-- Advance cursor to the next selectable cell in reading order (L→R, top→bottom,
-- wrapping back to start). Used after a successful selection.
function M.advance_cursor(g)
  local n_rows = #QWERTY
  for step = 1, 26 + 5 do
    -- advance one cell forward in reading order
    g.cursor_c = g.cursor_c + 1
    if g.cursor_c >= M.row_len(g.cursor_r) then
      g.cursor_c = 0
      g.cursor_r = (g.cursor_r + 1) % n_rows
    end
    if is_selectable_at(g, g.cursor_c, g.cursor_r) then return end
  end
end

-- Snap cursor to the first selectable cell in reading order.
local function snap_cursor_to_first(g)
  for r = 0, #QWERTY - 1 do
    for c = 0, M.row_len(r) - 1 do
      if is_selectable_at(g, c, r) then
        g.cursor_c, g.cursor_r = c, r
        return
      end
    end
  end
end

-- Map a touch point to a (col, row) cell, or return nil.
function M.cell_at_point(tx, ty)
  for r = 0, #QWERTY - 1 do
    local rl = M.row_len(r)
    for c = 0, rl - 1 do
      local x, y = M.cell_xy(c, r)
      if tx >= x and tx < x + CELL_W and ty >= y and ty < y + CELL_H then
        return c, r
      end
    end
  end
  return nil, nil
end

function M.current_letter(g)
  return M.letter_at(g.cursor_c, g.cursor_r)
end

------------------------------------------------------------
-- new game
------------------------------------------------------------
function M.new_game(level)
  level = level or 1
  local n_decoys = level_decoys(level)

  local entry = pop_word()
  local word      = entry[1]
  local hard_hint = entry[2]
  local clues     = entry[3]
  local _, word_set = unique_letters(word)

  -- Selectable set: all word letters + N decoy (wrong) letters.
  -- The decoy count is controlled by level, not by word length, so difficulty
  -- is consistent regardless of whether the word is 1 or 8 letters long.
  local selectable = {}
  for c, _ in pairs(word_set) do
    selectable[c] = true
  end

  local decoy_pool = {}
  for i = 0, 25 do
    local ch = string.char(65 + i)
    if not word_set[ch] then decoy_pool[#decoy_pool + 1] = ch end
  end
  shuffle(decoy_pool)

  local need = math.min(n_decoys, #decoy_pool)
  for i = 1, need do
    selectable[decoy_pool[i]] = true
  end

  local g = {
    word = word,
    clues = clues,
    hard_hint = hard_hint,
    hint_shown = 0,
    -- guessed[letter] = "right" | "wrong" | nil
    guessed = {},
    selectable = selectable,
    wrong = 0,
    state = "play",
    cursor_c = 0,
    cursor_r = 0,
    timer = 0,
    end_timer = 0,
    shake = 0,
    flash = 0,
    level = level,
    hints_at_start = 0,  -- set by caller, used for bonus on win
    score_gain = 0,      -- set on win, breakdown for display
    -- hint ticker
    hint_text = "",
    hint_x = 0,
  }

  snap_cursor_to_first(g)

  -- Auto-show the hard hint as a free ticker.
  g.hint_text = hard_hint
  g.hint_x = SCREEN_W + 4
  return g
end

------------------------------------------------------------
-- guessing
------------------------------------------------------------
local function has_letter(word, c)
  for i = 1, #word do
    if word:sub(i, i) == c then return true end
  end
  return false
end

local function check_win(g)
  for i = 1, #g.word do
    if g.guessed[g.word:sub(i, i)] ~= "right" then return false end
  end
  return true
end

-- Compute score breakdown for a win.
-- base = level * 100, perfect (no wrong guesses) = +500, remaining hints = *50
local function compute_score(g, hints_remaining)
  local base = g.level * 100
  local perfect = (g.wrong == 0) and 500 or 0
  local hint_bonus = hints_remaining * 50
  return base + perfect + hint_bonus, base, perfect, hint_bonus
end

-- `hints_remaining` is the player's current hint credit (used for win bonus).
function M.guess(g, letter, hints_remaining)
  if g.state ~= "play" then return false end
  if not letter or not g.selectable[letter] then return false end
  if g.guessed[letter] then return false end
  if has_letter(g.word, letter) then
    g.guessed[letter] = "right"
    g.flash = 6
    tone(0, 600, 900, 0.08)
    if check_win(g) then
      g.state = "win"
      tone(1, 400, 1200, 0.4)
      local total, base, perfect, hint_bonus = compute_score(g, hints_remaining or 0)
      g.score_gain = total
      g.score_base = base
      g.score_perfect = perfect
      g.score_hint = hint_bonus
    end
  else
    g.guessed[letter] = "wrong"
    g.wrong = g.wrong + 1
    g.shake = 5
    tone(0, 220, 90, 0.15)
    if g.wrong >= 6 then
      g.state = "lose"
      tone(1, 300, 80, 0.6)
    end
  end
  return true
end

-- Returns true if a hint was consumed. Caller decrements the credit.
function M.use_hint(g, credits)
  if g.state ~= "play" then return false end
  if g.hint_text ~= "" then return false end
  if credits <= 0 then return false end
  if g.hint_shown >= #g.clues then return false end
  g.hint_shown = g.hint_shown + 1
  g.hint_text = g.clues[g.hint_shown]
  g.hint_x = SCREEN_W + 4
  tone(0, 700, 1000, 0.05)
  return true
end

------------------------------------------------------------
-- drawing
------------------------------------------------------------

-- Gallows + word layout scaled for 160×120 resolution.
-- Gallows area: x=2-54, y=16-62.  Word area: x=58-155, y=34-48.
local function draw_gallows_frame()
  line(scr, 2, 62, 54, 62, 1)       -- ground
  for i = 0, 5 do pix(scr, 4 + i * 10, 64, 1) end  -- ticks
  line(scr, 14, 62, 14, 16, 1)      -- post
  line(scr, 14, 16, 44, 16, 1)      -- beam
  line(scr, 14, 22, 20, 16, 1)      -- brace
  line(scr, 44, 16, 44, 22, 1)      -- rope
end

local function draw_body_parts(wrong)
  if wrong >= 1 then
    circ(scr, 44, 26, 3, 1)         -- head
    if wrong >= 6 then
      pix(scr, 43, 25, 1); pix(scr, 45, 25, 1)  -- X eyes
      pix(scr, 43, 27, 1); pix(scr, 45, 27, 1)
    else
      pix(scr, 43, 25, 1); pix(scr, 45, 25, 1)  -- eyes
    end
  end
  if wrong >= 2 then line(scr, 44, 30, 44, 42, 1) end  -- body
  if wrong >= 3 then line(scr, 44, 33, 39, 38, 1) end  -- left arm
  if wrong >= 4 then line(scr, 44, 33, 49, 38, 1) end  -- right arm
  if wrong >= 5 then line(scr, 44, 42, 39, 50, 1) end  -- left leg
  if wrong >= 6 then line(scr, 44, 42, 49, 50, 1) end  -- right leg
end

local function draw_word(g)
  local reveal = (g.state ~= "play")
  local wlen = #g.word
  local slot_w = 8
  local total = wlen * slot_w
  local area_x, area_w = 58, 98
  local start_x = area_x + (area_w - total) // 2
  local y = 36
  for i = 1, wlen do
    local c = g.word:sub(i, i)
    local cx = start_x + (i - 1) * slot_w
    line(scr, cx, y + 9, cx + 5, y + 9, 1)
    if g.guessed[c] == "right" or reveal then
      text(scr, c, cx + 3, y + 1, 1, ALIGN_HCENTER)
    end
  end
end

local function draw_masked_cell(x, y)
  -- 50% inner dither so it reads as "blocked"
  for dy = 2, CELL_H - 3 do
    for dx = 2, CELL_W - 3 do
      if (dx + dy) % 2 == 0 then
        pix(scr, x + dx, y + dy, 1)
      end
    end
  end
end

local function draw_wrong_cell(x, y)
  -- wrong guess: fully hide the letter; dense dither so it's clearly different
  -- from both a plain masked cell and a "right" cell.
  rectf(scr, x + 1, y + 1, CELL_W - 2, CELL_H - 2, 1)
  -- carve out small holes so it reads as "crossed off"
  for dy = 2, CELL_H - 3, 2 do
    for dx = 2, CELL_W - 3, 2 do
      pix(scr, x + dx, y + dy, 0)
    end
  end
end

-- Custom 5x7 glyphs for letters that are hard to distinguish in the
-- engine's 4px-wide font (M and N look nearly identical at FONT_W=4).
-- Only used inside the QWERTY keyboard grid; everything else keeps
-- the engine font.
local CUSTOM_GLYPHS = {
  M = {
    {1,0,0,0,1},
    {1,1,0,1,1},
    {1,0,1,0,1},
    {1,0,0,0,1},
    {1,0,0,0,1},
    {1,0,0,0,1},
    {1,0,0,0,1},
  },
  N = {
    {1,0,0,0,1},
    {1,1,0,0,1},
    {1,0,1,0,1},
    {1,0,1,0,1},
    {1,0,1,0,1},
    {1,0,0,1,1},
    {1,0,0,0,1},
  },
}

-- Draw a keyboard letter — uses custom glyph when available, engine text otherwise.
local function draw_key_letter(x, y, letter, col)
  local glyph = CUSTOM_GLYPHS[letter]
  if glyph then
    local gw = #glyph[1]
    local gh = #glyph
    local gx = x + (CELL_W - gw) // 2
    local gy = y + (CELL_H - gh) // 2
    for py = 0, gh - 1 do
      local row = glyph[py + 1]
      for px = 0, gw - 1 do
        if row[px + 1] == 1 then pix(scr, gx + px, gy + py, col) end
      end
    end
  else
    local cx = x + CELL_W // 2
    local cy = y + CELL_H // 2
    text(scr, letter, cx, cy - 3, col, ALIGN_HCENTER)
  end
end

local function draw_alphabet(g)
  local blink = (g.timer // 8) % 2 == 0
  for r = 0, #QWERTY - 1 do
    local rl = M.row_len(r)
    for c = 0, rl - 1 do
      local letter = M.letter_at(c, r)
      local x, y = M.cell_xy(c, r)
      local status = g.guessed[letter]

      if not g.selectable[letter] then
        draw_masked_cell(x, y)
      elseif status == "right" then
        rectf(scr, x + 1, y + 1, CELL_W - 2, CELL_H - 2, 1)
        draw_key_letter(x, y, letter, 0)
      elseif status == "wrong" then
        draw_wrong_cell(x, y)
      else
        draw_key_letter(x, y, letter, 1)
      end

      if g.state == "play" and c == g.cursor_c and r == g.cursor_r then
        if blink then
          rect(scr, x, y, CELL_W - 1, CELL_H - 1, 1)
          pix(scr, x + 1, y + 1, 1)
          pix(scr, x + CELL_W - 3, y + 1, 1)
          pix(scr, x + 1, y + CELL_H - 3, 1)
          pix(scr, x + CELL_W - 3, y + CELL_H - 3, 1)
        end
      end
    end
  end
end

-- 5x5 sprites for header icons
local HEART_FILL = {
  {0,1,0,1,0},
  {1,1,1,1,1},
  {1,1,1,1,1},
  {0,1,1,1,0},
  {0,0,1,0,0},
}
local HEART_OUTLINE = {
  {0,1,0,1,0},
  {1,0,1,0,1},
  {1,0,0,0,1},
  {0,1,0,1,0},
  {0,0,1,0,0},
}
-- Horizontal key: round bow (left) + shaft + chunky tooth (right)
local KEY_ICON = {
  {0,1,1,0,0,0,0,0},
  {1,0,0,1,0,0,0,0},
  {1,0,0,1,1,1,1,1},
  {1,0,0,1,0,0,1,1},
  {0,1,1,0,0,0,0,0},
}

local function draw_sprite(sprite, x, y)
  for py = 0, #sprite - 1 do
    local row = sprite[py + 1]
    for px = 0, #row - 1 do
      if row[px + 1] == 1 then pix(scr, x + px, y + py, 1) end
    end
  end
end

local function text_width(s) return #s * 5 - 1 end

local function draw_header(g, hints, score, lives)
  if g.hint_text ~= "" then
    rectf(scr, 1, 1, SCREEN_W - 2, 11, 0)
    text(scr, "> " .. g.hint_text, g.hint_x, 4, 1)
    line(scr, 2, 12, 157, 12, 1)
    return
  end

  -- Hearts = lives (continues), filled only
  local n = lives or 0
  for i = 0, n - 1 do
    draw_sprite(HEART_FILL, 3 + i * 6, 3)
  end

  -- Right-aligned: LV<n>   [key]<hints>
  local right = 156
  local hint_str = tostring(hints)
  local hint_w = text_width(hint_str)
  text(scr, hint_str, right, 3, 1, ALIGN_RIGHT)
  local key_x = right - hint_w - 10
  draw_sprite(KEY_ICON, key_x, 3)
  local lv_right = key_x - 3
  text(scr, "LV" .. g.level, lv_right, 3, 1, ALIGN_RIGHT)

  line(scr, 2, 12, 157, 12, 1)

  if score and score > 0 then
    text(scr, tostring(score), 156, 14, 1, ALIGN_RIGHT)
  end
end

local function draw_end_overlay(g, lives)
  if g.state == "win" then
    local bx, by, bw, bh = 30, 22, 100, 38
    rectf(scr, bx, by, bw, bh, 0)
    rect(scr, bx, by, bw, bh, 1)
    for i = 0, bw // 4 do
      pix(scr, bx + i * 4, by + 2, 1)
      pix(scr, bx + i * 4, by + bh - 3, 1)
    end
    text(scr, "YOU WIN!", bx + bw // 2, by + 6, 1, ALIGN_HCENTER)
    if (g.timer // 15) % 2 == 0 then
      text(scr, g.word, bx + bw // 2, by + 15, 1, ALIGN_HCENTER)
    end
    local tag = "+" .. g.score_gain
    if g.score_perfect and g.score_perfect > 0 then tag = tag .. " PERFECT" end
    text(scr, tag, bx + bw // 2, by + 25, 1, ALIGN_HCENTER)
  elseif lives and lives > 1 then
    -- Word lost but lives remain: compact reveal, no GAME OVER text
    local bx, by, bw, bh = 50, 30, 60, 18
    rectf(scr, bx, by, bw, bh, 0)
    rect(scr, bx, by, bw, bh, 1)
    if (g.timer // 15) % 2 == 0 then
      text(scr, g.word, bx + bw // 2, by + 6, 1, ALIGN_HCENTER)
    end
  else
    -- Last life gone: actual game over
    local bx, by, bw, bh = 50, 26, 60, 28
    rectf(scr, bx, by, bw, bh, 0)
    rect(scr, bx, by, bw, bh, 1)
    for i = 0, bw // 4 do
      pix(scr, bx + i * 4, by + 2, 1)
      pix(scr, bx + i * 4, by + bh - 3, 1)
    end
    text(scr, "GAME OVER", bx + bw // 2, by + 7, 1, ALIGN_HCENTER)
    if (g.timer // 15) % 2 == 0 then
      text(scr, g.word, bx + bw // 2, by + 17, 1, ALIGN_HCENTER)
    end
  end
end

function M.draw(g, hints, score, lives)
  cls(scr, 0)

  if g.shake > 0 then
    local sx = ((g.timer % 2 == 0) and 1 or -1)
    local sy = ((g.timer % 3 == 0) and 1 or 0)
    cam(sx, sy)
  end

  draw_header(g, hints, score, lives)
  draw_gallows_frame()
  draw_body_parts(g.wrong)
  draw_word(g)
  draw_alphabet(g)

  cam(0, 0)

  if g.flash > 0 then
    rect(scr, 0, 0, SCREEN_W, SCREEN_H, 1)
    rect(scr, 1, 1, SCREEN_W - 2, SCREEN_H - 2, 1)
  else
    rect(scr, 0, 0, SCREEN_W, SCREEN_H, 1)
  end

  if g.state ~= "play" and g.end_timer > 8 then
    draw_end_overlay(g, lives)
  end
end

function M.tick(g)
  g.timer = g.timer + 1
  if g.shake > 0 then g.shake = g.shake - 1 end
  if g.flash > 0 then g.flash = g.flash - 1 end
  if g.state ~= "play" then g.end_timer = g.end_timer + 1 end
  if g.hint_text ~= "" then
    g.hint_x = g.hint_x - 2
    local tw = (#g.hint_text + 2) * 5
    if g.hint_x + tw < 0 then g.hint_text = "" end
  end
end

return M
)GL";

static const char* STATE_LUA = R"SL(
-- Shared state between scenes
local S = {
  level = 1,
  hints = 3,
  lives = 3,
  MAX_HINTS = 999,
  MAX_LEVEL = 50,
  score = 0,
  hi_score = 0,
  auto_start = false,
  demo = false,
}
return S
)SL";

static const char* WORDS_LUA = R"WL(
-- Word bank for hangman.
--
-- These are the 50 distinct words Dr. Seuss famously used to write
-- "Green Eggs and Ham" after being challenged by his editor Bennett Cerf
-- to write a book with only fifty words. Clearing all 50 levels means
-- guessing every word in the book.
--
-- Each entry: { WORD, HARD_HINT, { clue1..clue7 } }
-- Clues are ordered vague → decisive. The earlier ones barely help;
-- the later ones practically give it away.
return {
  { "A", "BEFORE A NOUN", {
    "PRECEDES A NOUN", "OPENS THE ALPHABET", "A COMMON VOWEL",
    "STARTS THE ALPHABET", "PAIRS WITH NOUNS", "AN ARTICLE",
    "INDEFINITE ARTICLE", } },
  { "AM", "A LINKING VERB", {
    "A GRAMMAR GLUE", "A FORM OF BE", "PRESENT TENSE",
    "I __ HAPPY", "FIRST PERSON", "PAIRS WITH I",
    "SAYS WHO YOU ARE", } },
  { "AND", "JOINING WORD", {
    "STITCHES IDEAS", "CONNECTS THINGS", "A CONJUNCTION",
    "VERY COMMON", "USED IN LISTS", "SALT ___ PEPPER",
    "PLUS SIGN IN WORDS", } },
  { "ANYWHERE", "A LOCATION WORD", {
    "A VAGUE SPOT", "ANY KIND OF PLACE", "NO SPECIFIC SPOT",
    "PICK ANY SPOT", "OPPOSITE OF NOWHERE", "STARTS WITH ANY",
    "ENDS WITH WHERE", } },
  { "ARE", "A VERB", {
    "A STATE OF BEING", "USED WITH YOU", "FORM OF BE",
    "PRESENT TENSE", "WE ___ HERE", "SECOND PERSON",
    "YOU ___", } },
  { "BE", "TO EXIST", {
    "ABOUT EXISTENCE", "AN INFINITIVE", "SIMPLY EXIST",
    "ROOT OF AM AND ARE", "TO __ OR NOT", "HAMLET SOLILOQUY",
    "STARTS WITH B", } },
  { "BOAT", "WATER VEHICLE", {
    "IT FLOATS", "CARRIES PEOPLE", "USED ON WATER",
    "DOCKED AT A HARBOR", "SMALLER THAN SHIP", "HAS A SAIL OR OARS",
    "ROWING CRAFT", } },
  { "BOX", "A CONTAINER", {
    "HOLDS STUFF", "SQUARE SHAPE", "HOLDS THINGS",
    "HAS CORNERS", "OFTEN CARDBOARD", "WHERE GIFTS GO",
    "A CUBE WITH A LID", } },
  { "CAR", "A VEHICLE", {
    "USED DAILY", "HAS WHEELS", "GOES ON ROADS",
    "PRIVATE TRANSPORT", "HAS AN ENGINE", "FOUR WHEELS",
    "YOU DRIVE IT", } },
  { "COULD", "MODAL VERB", {
    "ABOUT MAYBES", "PAST FORM", "ABOUT ABILITY",
    "HYPOTHETICAL", "PAST OF CAN", "I _____ IF I TRIED",
    "EXPRESSES POSSIBILITY", } },
  { "DARK", "ABSENCE OF LIGHT", {
    "A STATE", "AT NIGHT", "BLACKNESS",
    "NO LIGHT AROUND", "OPPOSITE OF BRIGHT", "WHEN LIGHTS GO OFF",
    "FEAR OF THE ____", } },
  { "DO", "AN ACTION", {
    "ABOUT DOING", "A BASIC VERB", "ACTION HELPER",
    "TASK RELATED", "PERFORM", "__ IT YOURSELF",
    "HOMEWORK VERB", } },
  { "EAT", "A VERB", {
    "BASIC NEED", "HAPPENS AT MEALS", "INVOLVES FOOD",
    "USING YOUR MOUTH", "CHEW AND SWALLOW", "MEAL TIME ACTION",
    "DINNER VERB", } },
  { "EGGS", "A FOOD", {
    "PLURAL NOUN", "OVAL SHAPED", "COMES FROM BIRDS",
    "HARD SHELL", "BREAKFAST CLASSIC", "LAID BY CHICKENS",
    "SCRAMBLED OR FRIED", } },
  { "FOX", "A MAMMAL", {
    "LIVES IN WOODS", "KNOWN FOR CUNNING", "RED COLORED",
    "BUSHY TAIL", "POINTY EARS", "IN CHILDRENS TALES",
    "QUICK BROWN ___", } },
  { "GOAT", "A MAMMAL", {
    "A FARM ANIMAL", "EATS GRASS", "HAS HORNS",
    "CLIMBS CLIFFS", "GIVES MILK", "SAYS MAA",
    "BILLY TYPE", } },
  { "GOOD", "AN ADJECTIVE", {
    "POSITIVE IDEA", "FEELS RIGHT", "WELL BEHAVED",
    "OPPOSITE OF BAD", "WHAT HEROES ARE", "A STAR IS ____",
    "MORAL VIRTUE", } },
  { "GREEN", "A COLOR", {
    "COOL TONE", "FOUND IN NATURE", "COLOR OF LEAVES",
    "COLOR OF GRASS", "LIGHT TRAFFIC SIGNAL", "ENVY COLOR",
    "MIX OF BLUE AND YELLOW", } },
  { "HAM", "A FOOD", {
    "PROTEIN", "FROM AN ANIMAL", "COMES FROM A PIG",
    "CURED MEAT", "SALTY MEAT", "SANDWICH FILLING",
    "EASTER DINNER STAPLE", } },
  { "HERE", "A LOCATION", {
    "A PLACE WORD", "CLOSE AT HAND", "WHERE YOU STAND",
    "THIS SPOT", "OPPOSITE OF THERE", "COME ____",
    "WHERE I AM", } },
  { "HOUSE", "A BUILDING", {
    "A STRUCTURE", "MADE OF WOOD OR BRICK", "HAS WALLS AND A ROOF",
    "YOU LIVE IN IT", "HAS ROOMS", "YOUR HOME",
    "RESIDENCE", } },
  { "I", "A PRONOUN", {
    "ABOUT YOURSELF", "VERY EGOCENTRIC", "STANDS FOR SELF",
    "NINTH LETTER", "A VOWEL", "FIRST PERSON",
    "ALWAYS CAPITAL", } },
  { "IF", "CONDITIONAL WORD", {
    "STARTS A MAYBE", "SETS UP A SUPPOSING", "A CONDITION",
    "HYPOTHETICAL START", "WHAT __", "OPENS POSSIBILITIES",
    "USED WITH THEN", } },
  { "IN", "A PREPOSITION", {
    "A PLACEMENT WORD", "TELLS YOU WHERE", "A LOCATION WORD",
    "INSIDE OF", "OPPOSITE OF OUT", "CONTAINED",
    "WITHIN SOMETHING", } },
  { "LET", "A VERB", {
    "PERMISSION IDEA", "DO NOT BLOCK", "GIVE LEAVE TO",
    "ALLOW", "PERMIT SOMETHING", "___ IT GO",
    "DONT STOP", } },
  { "LIKE", "A FEELING", {
    "POSITIVE", "A PREFERENCE", "ENJOY SOMETHING",
    "ENJOY OR SIMILAR TO", "FOUND ON SOCIAL MEDIA", "THUMBS UP BUTTON",
    "OPPOSITE OF DISLIKE", } },
  { "MAY", "A POSSIBILITY", {
    "SOFT PERMISSION", "PERMISSION WORD", "POLITE REQUEST",
    "A CALENDAR MONTH", "SPRING TIME", "AFTER APRIL",
    "BEFORE JUNE", } },
  { "ME", "OBJECT PRONOUN", {
    "ABOUT THE SPEAKER", "POINTS AT SPEAKER", "REFERS TO SELF",
    "FIRST PERSON", "GIVE IT TO __", "I TURNS INTO THIS",
    "RHYMES WITH BEE", } },
  { "MOUSE", "A RODENT", {
    "VERY SMALL", "TINY CRITTER", "LIKES CHEESE",
    "HAS A LONG TAIL", "CATS CHASE IT", "MINNIE FAMILY",
    "SQUEAKS", } },
  { "NOT", "NEGATION", {
    "FLIPS MEANING", "OPPOSITE MAKER", "DENIAL",
    "LOGIC INVERSION", "PAIRS WITH NO", "TURNS YES INTO NO",
    "A NEGATIVE", } },
  { "ON", "A PREPOSITION", {
    "A PLACEMENT WORD", "A POSITION", "RESTING ATOP",
    "OPPOSITE OF OFF", "SWITCH STATE", "ABOVE AND TOUCHING",
    "LIGHT IS __", } },
  { "OR", "A CONJUNCTION", {
    "PRESENTS OPTIONS", "OFFERS A CHOICE", "CHOICE WORD",
    "THIS OR THAT", "LOGIC OPERATOR", "ALTERNATIVE",
    "ONE OR THE OTHER", } },
  { "RAIN", "WEATHER", {
    "FALLS FROM ABOVE", "A LIQUID", "FROM THE SKY",
    "FALLS DOWN", "NEEDS AN UMBRELLA", "MAKES YOU WET",
    "CLOUD DROPS", } },
  { "SAM", "A NAME", {
    "A PROPER NOUN", "A PERSONS NAME", "A NICKNAME",
    "A MANS NAME", "NICKNAME FOR SAMUEL", "UNCLE ___",
    "STARS AND STRIPES GUY", } },
  { "SAY", "A VERB", {
    "A COMMUNICATION VERB", "TO COMMUNICATE", "USE YOUR MOUTH",
    "UTTER WORDS", "VOCALIZE", "PRONOUNCE",
    "SPEAK ALOUD", } },
  { "SEE", "A VERB", {
    "USES A SENSE", "A SENSE", "USE YOUR EYES",
    "OBSERVE", "PERCEIVE VISUALLY", "___ YOU LATER",
    "WATCH", } },
  { "SO", "AN INTENSIFIER", {
    "EMPHASIZES DEGREE", "A CONJUNCTION", "INTENSIFIER",
    "THEREFORE", "__ MUCH", "A MUSICAL NOTE",
    "AN ADVERB", } },
  { "THANK", "POLITE WORD", {
    "POLITE GESTURE", "EXPRESS FEELING", "POSITIVE WORD",
    "GRATITUDE", "_____ YOU", "AFTER A FAVOR",
    "POLITE PHRASE", } },
  { "THAT", "A DEMONSTRATIVE", {
    "A POINTING WORD", "POINTING WORD", "REFERS TO A THING",
    "OPPOSITE OF THIS", "____ ONE OVER THERE", "AT A DISTANCE",
    "NOT THIS ONE", } },
  { "THE", "AN ARTICLE", {
    "MOST COMMON WORD", "SEEN IN EVERY SENTENCE", "USED EVERYWHERE",
    "DEFINITE REFERENCE", "SPECIFIC ITEM", "BEFORE NOUNS",
    "DEFINITE ARTICLE", } },
  { "THEM", "A PRONOUN", {
    "THIRD PERSON", "PLURAL", "REFERS TO A GROUP",
    "OBJECT FORM", "US VERSUS ____", "REFERS TO OTHERS",
    "OBJECT OF THEY", } },
  { "THERE", "A LOCATION", {
    "A PLACE WORD", "NOT HERE", "AT THAT SPOT",
    "POINTING AT DISTANCE", "OVER _____", "FAR FROM YOU",
    "OPPOSITE OF HERE", } },
  { "THEY", "A PRONOUN", {
    "THIRD PERSON", "PLURAL", "OTHER FOLKS",
    "OTHER PEOPLE", "SUBJECT FORM", "____ SAY",
    "SOMEONE ELSE", } },
  { "TRAIN", "A VEHICLE", {
    "RUNS ON METAL", "TRANSPORT", "CARRIES MANY",
    "RUNS ON RAILS", "HAS MANY CARS", "CHOO CHOO",
    "RAIL TRANSPORT", } },
  { "TREE", "A PLANT", {
    "GROWING THING", "MADE OF WOOD", "HAS LEAVES",
    "HAS BARK", "VERY TALL PLANT", "OAK OR PINE",
    "WHERE BIRDS NEST", } },
  { "TRY", "A VERB", {
    "ABOUT EFFORT", "EFFORT WORD", "GIVE A SHOT",
    "MAKE AN ATTEMPT", "NOT GIVING UP", "DO YOUR BEST",
    "___ HARDER", } },
  { "WILL", "INTENT OR FUTURE", {
    "ABOUT THE FUTURE", "A MODAL VERB", "EXPRESSES FUTURE",
    "DETERMINATION", "GOING TO DO", "LEGAL DOCUMENT",
    "FREE ____", } },
  { "WITH", "A PREPOSITION", {
    "LINKING WORD", "TOGETHER IDEA", "ACCOMPANIED BY",
    "ALONGSIDE", "IN COMPANY OF", "PAIRED",
    "____ SALT AND PEPPER", } },
  { "WOULD", "MODAL VERB", {
    "ABOUT MAYBES", "POLITE FORM", "HYPOTHETICAL",
    "CONDITIONAL", "PAST OF WILL", "_____ YOU MIND",
    "A REQUEST OPENER", } },
  { "YOU", "A PRONOUN", {
    "POINTS OUTWARD", "SECOND PERSON", "THE LISTENER",
    "ME TALKS TO ___", "PERSONAL PRONOUN", "WHOM I ADDRESS",
    "NOT ME", } },
}
)WL";

static const char* SCENE_TITLE_LUA = R"TL(
-- Title screen
local scene = {}
local scr = screen()
local state = require("state")

local t = 0
local auto_delay = 0
local input_lock = false

local ALL_KEYS = { "a", "b", "start", "select", "up", "down", "left", "right" }

local function any_input_held()
  for _, k in ipairs(ALL_KEYS) do
    if btn(k) then return true end
  end
  -- Also block on latched touch edge events; a touch_end triggered in the
  -- previous scene is still reported as true on this frame until the
  -- engine clears the flag at the end of the tick.
  return touch() or touch_end() or touch_start()
end

function scene.init()
  t = 0
  input_lock = true
  if state.auto_start then
    state.auto_start = false
    auto_delay = 15
  else
    auto_delay = 0
    -- Short title jingle (descending three-note chord)
    wave(0, "square")
    note(0, "E5", 0.12)
    note(1, "C5", 0.12)
  end
end

function scene.update()
  t = t + 1
  if auto_delay > 0 then
    auto_delay = auto_delay - 1
    if auto_delay == 0 then
      go("scenes/play")
    end
    return
  end
  if input_lock then
    if any_input_held() then return end
    input_lock = false
  end
  if btnp("start") or touch_end() then
    state.demo = false
    go("scenes/play")
  elseif btnp("select") then
    state.demo = true
    go("scenes/play")
  end
end

-- Scrolling marquee stipple under the logo
local function stipple_row(y)
  local off = (t // 2) % 4
  for x = 0, SCREEN_W - 1 do
    if (x + off) % 4 == 0 then
      pix(scr, x, y, 1)
    end
  end
end

local function draw_mini_gallows(ox, oy)
  line(scr, ox, oy + 40, ox + 32, oy + 40, 1)
  line(scr, ox + 6, oy + 40, ox + 6, oy, 1)
  line(scr, ox + 6, oy, ox + 28, oy, 1)
  line(scr, ox + 6, oy + 6, ox + 12, oy, 1)
  line(scr, ox + 28, oy, ox + 28, oy + 6, 1)
  circ(scr, ox + 28, oy + 10, 3, 1)
  pix(scr, ox + 27, oy + 9, 1)
  pix(scr, ox + 29, oy + 9, 1)
  line(scr, ox + 28, oy + 13, ox + 28, oy + 26, 1)
  line(scr, ox + 28, oy + 16, ox + 23, oy + 22, 1)
  line(scr, ox + 28, oy + 16, ox + 33, oy + 22, 1)
  line(scr, ox + 28, oy + 26, ox + 23, oy + 34, 1)
  line(scr, ox + 28, oy + 26, ox + 33, oy + 34, 1)
end

function scene.draw()
  cls(scr, 0)

  stipple_row(4)
  stipple_row(5)

  -- Title header frame
  rect(scr, 6, 10, SCREEN_W - 12, 20, 1)
  rect(scr, 8, 12, SCREEN_W - 16, 16, 1)
  text(scr, "MONO  HANGMAN", SCREEN_W // 2, 17, 1, ALIGN_HCENTER)

  -- gallows illustration
  draw_mini_gallows(64, 34)

  -- Hi score
  if state.hi_score > 0 then
    text(scr, "HI SCORE", SCREEN_W // 2, 80, 1, ALIGN_HCENTER)
    text(scr, tostring(state.hi_score), SCREEN_W // 2, 88, 1, ALIGN_HCENTER)
  end

  -- blinking START button
  if (t // 15) % 2 == 0 then
    local bw, bh = 40, 14
    local bx = (SCREEN_W - bw) // 2
    local by = 100
    rect(scr, bx, by, bw, bh, 1)
    text(scr, "START", SCREEN_W // 2, by + 4, 1, ALIGN_HCENTER)
  end

  rect(scr, 0, 0, SCREEN_W, SCREEN_H, 1)
end

return scene
)TL";

static const char* SCENE_PLAY_LUA = R"PL(
-- Play scene (handles normal play and demo mode)
local scene = {}
local scr = screen()
local game = require("game")
local state = require("state")

local g
local paused = false
local last_tx, last_ty = nil, nil
local input_lock = false
local tutorial_shown = false  -- persists for the entire session (module cache)
local show_tutorial = false

local ALL_KEYS = { "a", "b", "start", "select", "up", "down", "left", "right" }

local function any_key_pressed()
  for _, k in ipairs(ALL_KEYS) do
    if btnp(k) then return true end
  end
  return false
end

local function any_input_held()
  for _, k in ipairs(ALL_KEYS) do
    if btn(k) then return true end
  end
  return touch() or touch_end() or touch_start()
end

function scene.init()
  local lvl = state.demo and 1 or state.level
  g = game.new_game(lvl)
  paused = false
  last_tx, last_ty = nil, nil
  input_lock = true
  if not tutorial_shown and not state.demo then
    show_tutorial = true
  end
end

------------------------------------------------------------
-- normal play helpers
------------------------------------------------------------
local function try_guess(letter)
  game.guess(g, letter, state.hints)
end

local function handle_touch()
  if touch() then
    local x, y = touch_pos()
    if x then
      last_tx, last_ty = x, y
      local c, r = game.cell_at_point(x, y)
      if c then
        g.cursor_c, g.cursor_r = c, r
      end
    end
  end
  if touch_end() and last_tx then
    local tx, ty = last_tx, last_ty
    last_tx, last_ty = nil, nil
    local c, r = game.cell_at_point(tx, ty)
    if not c then return end
    local letter = game.letter_at(c, r)
    if not letter then return end
    if not g.selectable[letter] or g.guessed[letter] then return end
    g.cursor_c, g.cursor_r = c, r
    try_guess(letter)
  end
end

local function handle_play_input()
  if btnp("select") then
    paused = not paused
    return
  end
  if paused then return end

  if btnp("left")  then game.move_cursor(g, -1, 0) end
  if btnp("right") then game.move_cursor(g,  1, 0) end
  if btnp("up")    then game.move_cursor(g,  0, -1) end
  if btnp("down")  then game.move_cursor(g,  0,  1) end
  if btnp("a") then
    local letter = game.current_letter(g)
    if letter then try_guess(letter) end
  end
  if btnp("b") then
    if game.use_hint(g, state.hints) then
      state.hints = state.hints - 1
    end
  end
  handle_touch()
end

local function handle_end_input()
  if g.end_timer <= 8 then return end
  if not (any_key_pressed() or touch_end()) then return end
  if g.state == "win" then
    state.score = state.score + (g.score_gain or 0)
    if state.score > state.hi_score then state.hi_score = state.score end
    state.hints = state.hints + 1
    -- Bonus life every 10 stages cleared
    if state.level % 10 == 0 then
      state.lives = state.lives + 1
    end
    if state.level >= state.MAX_LEVEL then
      go("scenes/ending")
      return
    end
    state.level = state.level + 1
    g = game.new_game(state.level)
    paused = false
    input_lock = true
  else
    -- Word lost: spend a life
    state.lives = state.lives - 1
    if state.lives > 0 then
      -- Still alive: next word, same level
      g = game.new_game(state.level)
      paused = false
      input_lock = true
    else
      -- All lives gone: game over → checkpoint or title
      if state.score > state.hi_score then state.hi_score = state.score end
      local checkpoint = ((state.level - 1) // 10) * 10 + 1
      if checkpoint <= 1 then
        state.level = 1
        state.hints = 3
        state.lives = 3
        state.score = 0
        state.auto_start = false
        game.reset_deck()
        go("scenes/title")
      else
        state.level = checkpoint
        state.hints = 3
        state.lives = 3
        g = game.new_game(state.level)
        paused = false
        input_lock = true
      end
    end
  end
end

------------------------------------------------------------
-- demo mode helpers
------------------------------------------------------------

-- AI picks a random available (selectable + unguessed) letter.
local function ai_pick()
  local avail = {}
  for r = 0, 2 do
    for c = 0, game.row_len(r) - 1 do
      local letter = game.letter_at(c, r)
      if letter and g.selectable[letter] and not g.guessed[letter] then
        avail[#avail + 1] = { c = c, r = r, letter = letter }
      end
    end
  end
  if #avail == 0 then return end
  local pick = avail[math.random(#avail)]
  g.cursor_c, g.cursor_r = pick.c, pick.r
  game.guess(g, pick.letter, 0)
end

local function handle_demo()
  -- Any key or touch exits demo
  if any_key_pressed() or touch_end() then
    state.demo = false
    go("scenes/title")
    return
  end

  if g.state == "play" then
    -- AI guesses after the hard-hint ticker finishes scrolling
    if g.hint_text == "" and g.timer % 25 == 0 then
      ai_pick()
    end
  else
    -- Win or lose: wait briefly then restart (stay in demo, never go to title)
    if g.end_timer > 60 then
      g = game.new_game(1)
    end
  end
end

------------------------------------------------------------
-- scene callbacks
------------------------------------------------------------
function scene.update()
  if not paused and not show_tutorial then game.tick(g) end
  if input_lock then
    if any_input_held() then return end
    input_lock = false
  end
  if show_tutorial then
    if any_key_pressed() or touch_end() then
      show_tutorial = false
      tutorial_shown = true
    end
    return
  end
  if state.demo then
    handle_demo()
  elseif g.state == "play" then
    handle_play_input()
  else
    handle_end_input()
  end
end

local function draw_pause_overlay()
  local bw, bh = 60, 18
  local bx, by = (SCREEN_W - bw) // 2, (SCREEN_H - bh) // 2
  rectf(scr, bx, by, bw, bh, 0)
  rect(scr, bx, by, bw, bh, 1)
  rect(scr, bx + 2, by + 2, bw - 4, bh - 4, 1)
  if (g.timer // 15) % 2 == 0 then
    text(scr, "PAUSED", bx + bw // 2, by + bh // 2 - 3, 1, ALIGN_HCENTER)
  end
end

-- 7-segment digit rendering (4×7 pixels per digit, font-sized)
local SEG = {
  [0] = { a=1,b=1,c=1,d=1,e=1,f=1 },
  [1] = { b=1,c=1 },
  [2] = { a=1,b=1,d=1,e=1,g=1 },
  [3] = { a=1,b=1,c=1,d=1,g=1 },
  [4] = { b=1,c=1,f=1,g=1 },
  [5] = { a=1,c=1,d=1,f=1,g=1 },
  [6] = { a=1,c=1,d=1,e=1,f=1,g=1 },
  [7] = { a=1,b=1,c=1 },
  [8] = { a=1,b=1,c=1,d=1,e=1,f=1,g=1 },
  [9] = { a=1,b=1,c=1,d=1,f=1,g=1 },
}

local function draw_seg_digit(x, y, d, col)
  local s = SEG[d]
  if s.a then pix(scr, x+1, y, col);   pix(scr, x+2, y, col) end
  if s.f then pix(scr, x, y+1, col);   pix(scr, x, y+2, col) end
  if s.b then pix(scr, x+3, y+1, col); pix(scr, x+3, y+2, col) end
  if s.g then pix(scr, x+1, y+3, col); pix(scr, x+2, y+3, col) end
  if s.e then pix(scr, x, y+4, col);   pix(scr, x, y+5, col) end
  if s.c then pix(scr, x+3, y+4, col); pix(scr, x+3, y+5, col) end
  if s.d then pix(scr, x+1, y+6, col); pix(scr, x+2, y+6, col) end
end

-- Digital clock (demo only): 7-seg HH:MM below the header, top-center of game area.
local function draw_clock()
  local h = tonumber(os.date("%H"))
  local m = tonumber(os.date("%M"))
  local blink = (g.timer // 15) % 2 == 0
  -- Layout: digit(4) gap(1) digit(4) gap(1) colon(1) gap(1) digit(4) gap(1) digit(4) = 21px
  local tw = 21
  local cx = (SCREEN_W - tw) // 2
  local cy = 14
  draw_seg_digit(cx, cy, h // 10, 1)
  draw_seg_digit(cx + 5, cy, h % 10, 1)
  if blink then
    pix(scr, cx + 10, cy + 2, 1)
    pix(scr, cx + 10, cy + 4, 1)
  end
  draw_seg_digit(cx + 12, cy, m // 10, 1)
  draw_seg_digit(cx + 17, cy, m % 10, 1)
end

local function draw_tutorial()
  -- Black out the entire game area so no keyboard/gallows bleeds through
  rectf(scr, 1, 1, SCREEN_W - 2, SCREEN_H - 2, 0)
  -- Compact info box, centered
  local bw, bh = 104, 57
  local bx = (SCREEN_W - bw) // 2
  local by = (SCREEN_H - bh) // 2
  rect(scr, bx, by, bw, bh, 1)
  rect(scr, bx + 2, by + 2, bw - 4, bh - 4, 1)
  text(scr, "TOUCH TO SELECT", bx + bw // 2, by + 10, 1, ALIGN_HCENTER)
  text(scr, "A = GUESS", bx + bw // 2, by + 20, 1, ALIGN_HCENTER)
  text(scr, "B = HINT", bx + bw // 2, by + 28, 1, ALIGN_HCENTER)
  if (g.timer // 15) % 2 == 0 then
    text(scr, "PRESS ANY KEY", bx + bw // 2, by + 40, 1, ALIGN_HCENTER)
  end
  -- Restore outer border
  rect(scr, 0, 0, SCREEN_W, SCREEN_H, 1)
end

function scene.draw()
  game.draw(g, state.demo and 0 or state.hints, state.demo and 0 or state.score, state.demo and 0 or state.lives)
  if show_tutorial then draw_tutorial() end
  if state.demo then draw_clock() end
  if paused then draw_pause_overlay() end
end

return scene
)PL";

static const char* SCENE_ENDING_LUA = R"EL(
-- Ending scene.
--
-- Two phases:
--   1. PHASE_SCROLL: Star Wars style credits crawl from bottom to top.
--      SELECT toggles pause (no on-screen indication). All other input
--      is ignored.
--   2. PHASE_FINALE: after the crawl finishes, show a simple celebration
--      with the final score and a blinking "PRESS ANY BUTTON" prompt.
--      Input only works in this phase.

local scene = {}
local scr = screen()
local state = require("state")
local game = require("game")

-- Empty strings insert blank vertical gaps in the crawl.
local CREDIT_LINES = {
  "",
  "",
  "THE 50 WORDS IN THIS GAME",
  "ARE FROM GREEN EGGS",
  "AND HAM BY DR SEUSS",
  "",
  "THE ENTIRE BOOK",
  "IS WRITTEN WITH",
  "ONLY THESE 50 WORDS",
  "",
  "SEUSS WROTE IT",
  "TO SETTLE A BET",
  "",
  "AND LEFT US A LESSON",
  "",
  "STRICT CONSTRAINTS",
  "MAXIMIZE CREATIVITY",
  "",
  "THE MONO ENGINE WAS",
  "BUILT ON THE SAME",
  "PHILOSOPHY",
  "",
  "",
}

local LINE_HEIGHT = 10
local SCROLL_SPEED = 0.5   -- pixels per frame

local PHASE_SCROLL = 1
local PHASE_FINALE = 2

local phase = PHASE_SCROLL
local scroll_y = 0
local paused = false
local t = 0
local finale_timer = 0
local input_lock = true

local ALL_KEYS = { "a", "b", "start", "select", "up", "down", "left", "right" }

local function any_key_pressed()
  for _, k in ipairs(ALL_KEYS) do
    if btnp(k) then return true end
  end
  return false
end

local function any_input_held()
  for _, k in ipairs(ALL_KEYS) do
    if btn(k) then return true end
  end
  return touch() or touch_end() or touch_start()
end

function scene.init()
  phase = PHASE_SCROLL
  scroll_y = SCREEN_H + 4   -- start just below the visible area
  paused = false
  t = 0
  finale_timer = 0
  input_lock = true
end

local function last_line_y()
  return scroll_y + (#CREDIT_LINES - 1) * LINE_HEIGHT
end

local function goto_title()
  if state.score > state.hi_score then state.hi_score = state.score end
  state.level = 1
  state.hints = 3
  state.score = 0
  state.auto_start = false
  game.reset_deck()
  go("scenes/title")
end

function scene.update()
  t = t + 1

  -- Require all inputs to release before the scene starts reacting.
  if input_lock then
    if not any_input_held() then input_lock = false end
    return
  end

  if phase == PHASE_SCROLL then
    -- SELECT silently pauses/resumes the crawl. No on-screen instruction.
    if btnp("select") then
      paused = not paused
    end
    if not paused then
      scroll_y = scroll_y - SCROLL_SPEED
      -- Crawl finished when the final line has moved above the top.
      if last_line_y() < -LINE_HEIGHT then
        phase = PHASE_FINALE
        finale_timer = 0
        input_lock = true
        -- Victory arpeggio
        wave(0, "triangle")
        wave(1, "triangle")
        note(0, "C5", 0.15)
        note(1, "E5", 0.15)
      end
    end
    return
  end

  -- PHASE_FINALE
  finale_timer = finale_timer + 1
  if finale_timer > 20 and (any_key_pressed() or touch_end()) then
    goto_title()
  end
end

local function draw_scroll()
  for i, line in ipairs(CREDIT_LINES) do
    if line ~= "" then
      local y = math.floor(scroll_y + (i - 1) * LINE_HEIGHT)
      if y > -8 and y < SCREEN_H then
        text(scr, line, SCREEN_W // 2, y, 1, ALIGN_HCENTER)
      end
    end
  end
end

local function draw_finale()
  -- Title
  text(scr, "CONGRATULATIONS", SCREEN_W // 2, 30, 1, ALIGN_HCENTER)

  -- Score label + value, generously spaced (no box — cleaner at this size)
  text(scr, "FINAL SCORE", SCREEN_W // 2, 60, 1, ALIGN_HCENTER)
  -- dashed underline
  for x = 40, SCREEN_W - 41, 3 do pix(scr, x, 70, 1) end
  text(scr, tostring(state.score), SCREEN_W // 2, 78, 1, ALIGN_HCENTER)

  -- Blinking prompt (only after a brief delay so it isn't missed)
  if finale_timer > 20 and (t // 15) % 2 == 0 then
    text(scr, "PRESS ANY BUTTON", SCREEN_W // 2, 118, 1, ALIGN_HCENTER)
  end
end

function scene.draw()
  cls(scr, 0)
  if phase == PHASE_SCROLL then
    draw_scroll()
  else
    draw_finale()
  end
  rect(scr, 0, 0, SCREEN_W, SCREEN_H, 1)
end

return scene
)EL";

