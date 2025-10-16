-- Workflow Editor State Management
-- Contains all editor state variables

local M = {}

-- Create and return a new editor state
function M.create()
    return {
        -- Canvas transform
        pan_x = 0,
        pan_y = 0,
        zoom = 1.0,

        -- Mouse state
        mouse_x = 0,
        mouse_y = 0,
        mouse_buttons = {false, false, false}, -- left, right, middle
        mouse_drag_start_x = 0,
        mouse_drag_start_y = 0,

        -- Interaction state
        dragging_node = nil,
        dragging_canvas = false,
        panning_canvas = false,
        dragging_connection = nil, -- {node_id, port_index, is_output}
        hovered_node = nil,
        hovered_port = nil, -- {node_id, port_index, is_output}
        selected_node = nil,

        -- Node data
        nodes = {},
        next_node_id = 1,

        -- Connections
        connections = {}, -- {from_node, from_port, to_node, to_port}

        -- UI state
        show_node_menu = false,
        node_menu_x = 0,
        node_menu_y = 0,

        -- Canvas position (for coordinate conversion)
        canvas_x = 0,
        canvas_y = 0,

        -- UI Constants
        grid_size = 20,
        node_width = 180,
        node_header_height = 30,
        node_port_height = 24,
        node_port_radius = 6,
        node_padding = 10,
        node_rounding = 8,
    }
end

return M
