-- Workflow Editor Coordinate Transformations
-- Handles conversions between screen and world coordinates

local M = {}

-- Transform screen coordinates to world coordinates
-- Screen coordinates are relative to the canvas (already subtracted canvas offset in mouse handler)
function M.screen_to_world(editor, screen_x, screen_y)
    return (screen_x - editor.pan_x) / editor.zoom,
           (screen_y - editor.pan_y) / editor.zoom
end

-- Transform world coordinates to screen coordinates
-- Returns coordinates relative to the canvas
function M.world_to_screen(editor, world_x, world_y)
    return world_x * editor.zoom + editor.pan_x,
           world_y * editor.zoom + editor.pan_y
end

return M
