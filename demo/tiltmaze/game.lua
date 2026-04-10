-- Tilt Maze Demo (entry scene)
-- Covers: go, scene_name, axis_x, axis_y, canvas, canvas_w, canvas_h,
--         canvas_del, blit
--
-- Game structure:
--   title.lua  -- press A to start
--   level1.lua -- first maze
--   level2.lua -- second maze
--   clear.lua  -- win screen
--
-- This file only boots the title scene.

function _init()
  mode(4)
end

function _start()
  go("title")
end
