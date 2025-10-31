-- Workflow Editor Color Scheme
-- Defines all colors used in the workflow editor

local M = {}

M.background = nvg.rgba(28, 30, 34, 255)
M.grid = nvg.rgba(50, 52, 56, 255)
M.grid_accent = nvg.rgba(60, 62, 66, 255)

M.node_bg = nvg.rgba(45, 47, 51, 255)
M.node_selected = nvg.rgba(100, 140, 255, 255)
M.node_shadow = nvg.rgba(0, 0, 0, 100)

M.port_input = nvg.rgba(120, 200, 120, 255)
M.port_output = nvg.rgba(200, 120, 120, 255)
M.port_hover = nvg.rgba(255, 255, 100, 255)

M.connection = nvg.rgba(150, 150, 150, 255)
M.connection_active = nvg.rgba(100, 200, 255, 255)

M.text = nvg.rgba(220, 220, 220, 255)
M.text_dim = nvg.rgba(160, 160, 160, 255)

M.menu_bg = nvg.rgba(40, 42, 46, 240)
M.menu_item_hover = nvg.rgba(60, 62, 66, 255)

return M
