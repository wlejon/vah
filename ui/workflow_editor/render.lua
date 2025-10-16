-- Workflow Editor Rendering
-- All drawing functions for the workflow editor

local M = {}

local node_module = require("workflow_editor.node")
local transform = require("workflow_editor.transform")

-- Draw grid background
function M.draw_grid(nvg_ctx, editor, colors, canvas_x, canvas_y, canvas_w, canvas_h)
    nvg.save(nvg_ctx)

    -- Apply canvas transform
    nvg.translate(nvg_ctx, canvas_x + editor.pan_x, canvas_y + editor.pan_y)
    nvg.scale(nvg_ctx, editor.zoom, editor.zoom)

    -- Calculate visible grid bounds (in world coordinates)
    local world_x1, world_y1 = transform.screen_to_world(editor, 0, 0)
    local world_x2, world_y2 = transform.screen_to_world(editor, canvas_w, canvas_h)

    local grid_spacing = editor.grid_size
    local accent_spacing = editor.grid_size * 5

    -- Draw fine grid
    nvg.strokeColor(nvg_ctx, colors.grid)
    nvg.strokeWidth(nvg_ctx, 1.0 / editor.zoom)

    local start_x = math.floor(world_x1 / grid_spacing) * grid_spacing
    local start_y = math.floor(world_y1 / grid_spacing) * grid_spacing

    local gx = start_x
    while gx <= world_x2 do
        if math.abs(gx % accent_spacing) > 0.1 then
            nvg.beginPath(nvg_ctx)
            nvg.moveTo(nvg_ctx, gx, world_y1)
            nvg.lineTo(nvg_ctx, gx, world_y2)
            nvg.stroke(nvg_ctx)
        end
        gx = gx + grid_spacing
    end

    local gy = start_y
    while gy <= world_y2 do
        if math.abs(gy % accent_spacing) > 0.1 then
            nvg.beginPath(nvg_ctx)
            nvg.moveTo(nvg_ctx, world_x1, gy)
            nvg.lineTo(nvg_ctx, world_x2, gy)
            nvg.stroke(nvg_ctx)
        end
        gy = gy + grid_spacing
    end

    -- Draw accent grid
    nvg.strokeColor(nvg_ctx, colors.grid_accent)
    nvg.strokeWidth(nvg_ctx, 1.5 / editor.zoom)

    gx = start_x
    while gx <= world_x2 do
        if math.abs(gx % accent_spacing) < 0.1 then
            nvg.beginPath(nvg_ctx)
            nvg.moveTo(nvg_ctx, gx, world_y1)
            nvg.lineTo(nvg_ctx, gx, world_y2)
            nvg.stroke(nvg_ctx)
        end
        gx = gx + grid_spacing
    end

    gy = start_y
    while gy <= world_y2 do
        if math.abs(gy % accent_spacing) < 0.1 then
            nvg.beginPath(nvg_ctx)
            nvg.moveTo(nvg_ctx, world_x1, gy)
            nvg.lineTo(nvg_ctx, world_x2, gy)
            nvg.stroke(nvg_ctx)
        end
        gy = gy + grid_spacing
    end

    nvg.restore(nvg_ctx)
end

-- Draw a bezier curve connection
local function draw_connection_curve(nvg_ctx, x1, y1, x2, y2, color, thickness)
    local dx = x2 - x1
    local control_distance = math.min(math.abs(dx) * 0.5, 100)

    nvg.beginPath(nvg_ctx)
    nvg.moveTo(nvg_ctx, x1, y1)
    nvg.bezierTo(nvg_ctx,
                 x1 + control_distance, y1,
                 x2 - control_distance, y2,
                 x2, y2)
    nvg.strokeWidth(nvg_ctx, thickness)
    nvg.strokeColor(nvg_ctx, color)
    nvg.stroke(nvg_ctx)
end

-- Draw all connections
function M.draw_connections(nvg_ctx, editor, colors)
    for _, conn in ipairs(editor.connections) do
        local from_node = node_module.find_by_id(editor, conn.from_node)
        local to_node = node_module.find_by_id(editor, conn.to_node)

        if from_node and to_node then
            local x1, y1 = node_module.get_port_position(editor, from_node, conn.from_port, true)
            local x2, y2 = node_module.get_port_position(editor, to_node, conn.to_port, false)

            draw_connection_curve(nvg_ctx, x1, y1, x2, y2, colors.connection, 3.0)
        end
    end

    -- Draw dragging connection
    if editor.dragging_connection then
        local node = node_module.find_by_id(editor, editor.dragging_connection.node_id)
        if node then
            local x1, y1 = node_module.get_port_position(editor,
                                            node,
                                            editor.dragging_connection.port_index,
                                            editor.dragging_connection.is_output)
            local world_mx, world_my = transform.screen_to_world(editor, editor.mouse_x, editor.mouse_y)

            if editor.dragging_connection.is_output then
                draw_connection_curve(nvg_ctx, x1, y1, world_mx, world_my,
                              colors.connection_active, 3.0)
            else
                draw_connection_curve(nvg_ctx, world_mx, world_my, x1, y1,
                              colors.connection_active, 3.0)
            end
        end
    end
end

-- Draw a single port
local function draw_port(nvg_ctx, editor, colors, x, y, is_output, is_hovered)
    local color = is_output and colors.port_output or colors.port_input
    if is_hovered then
        color = colors.port_hover
    end

    -- Outer circle
    nvg.beginPath(nvg_ctx)
    nvg.circle(nvg_ctx, x, y, editor.node_port_radius)
    nvg.fillColor(nvg_ctx, color)
    nvg.fill(nvg_ctx)

    -- Inner circle for depth
    nvg.beginPath(nvg_ctx)
    nvg.circle(nvg_ctx, x, y, editor.node_port_radius - 2)
    nvg.strokeWidth(nvg_ctx, 1.5)
    nvg.strokeColor(nvg_ctx, nvg.rgba(0, 0, 0, 100))
    nvg.stroke(nvg_ctx)
end

-- Draw a single node
local function draw_single_node(nvg_ctx, editor, colors, node)
    local height = node_module.get_height(editor, node)
    local is_selected = editor.selected_node == node.id
    local is_hovered = editor.hovered_node == node.id

    -- Shadow
    nvg.beginPath(nvg_ctx)
    nvg.roundedRect(nvg_ctx, node.x + 3, node.y + 3,
                    editor.node_width, height, editor.node_rounding)
    nvg.fillColor(nvg_ctx, colors.node_shadow)
    nvg.fill(nvg_ctx)

    -- Node body
    nvg.beginPath(nvg_ctx)
    nvg.roundedRect(nvg_ctx, node.x, node.y,
                    editor.node_width, height, editor.node_rounding)
    nvg.fillColor(nvg_ctx, colors.node_bg)
    nvg.fill(nvg_ctx)

    -- Header with node type color
    nvg.beginPath(nvg_ctx)
    nvg.roundedRect(nvg_ctx, node.x, node.y,
                    editor.node_width, editor.node_header_height,
                    editor.node_rounding)
    nvg.fillColor(nvg_ctx, node.color)
    nvg.fill(nvg_ctx)

    -- Fill in bottom corners of header
    nvg.beginPath(nvg_ctx)
    nvg.rect(nvg_ctx, node.x, node.y + editor.node_header_height - editor.node_rounding,
             editor.node_width, editor.node_rounding)
    nvg.fillColor(nvg_ctx, node.color)
    nvg.fill(nvg_ctx)

    -- Border
    local border_color = is_selected and colors.node_selected or node.color
    if is_hovered and not is_selected then
        border_color = nvg.rgba(100, 100, 120, 255)
    end

    nvg.beginPath(nvg_ctx)
    nvg.roundedRect(nvg_ctx, node.x, node.y,
                    editor.node_width, height, editor.node_rounding)
    nvg.strokeWidth(nvg_ctx, is_selected and 3.0 or 2.0)
    nvg.strokeColor(nvg_ctx, border_color)
    nvg.stroke(nvg_ctx)

    -- Node name
    nvg.fontSize(nvg_ctx, 14.0)
    nvg.fontFace(nvg_ctx, "roboto")
    nvg.textAlign(nvg_ctx, nvg.ALIGN_CENTER + nvg.ALIGN_MIDDLE)
    nvg.fillColor(nvg_ctx, colors.text)
    nvg.text(nvg_ctx, node.x + editor.node_width / 2,
             node.y + editor.node_header_height / 2, node.name)

    -- Input ports
    nvg.fontSize(nvg_ctx, 11.0)
    nvg.textAlign(nvg_ctx, nvg.ALIGN_LEFT + nvg.ALIGN_MIDDLE)
    for i, port_name in ipairs(node.inputs) do
        local px, py = node_module.get_port_position(editor, node, i, false)
        local is_hovered_port = editor.hovered_port and
                               editor.hovered_port.node_id == node.id and
                               editor.hovered_port.port_index == i and
                               not editor.hovered_port.is_output

        draw_port(nvg_ctx, editor, colors, px, py, false, is_hovered_port)

        nvg.fillColor(nvg_ctx, colors.text_dim)
        nvg.text(nvg_ctx, node.x + editor.node_port_radius + 8, py, port_name)
    end

    -- Output ports
    nvg.textAlign(nvg_ctx, nvg.ALIGN_RIGHT + nvg.ALIGN_MIDDLE)
    for i, port_name in ipairs(node.outputs) do
        local px, py = node_module.get_port_position(editor, node, i, true)
        local is_hovered_port = editor.hovered_port and
                               editor.hovered_port.node_id == node.id and
                               editor.hovered_port.port_index == i and
                               editor.hovered_port.is_output

        draw_port(nvg_ctx, editor, colors, px, py, true, is_hovered_port)

        nvg.fillColor(nvg_ctx, colors.text_dim)
        nvg.text(nvg_ctx, node.x + editor.node_width - editor.node_port_radius - 8,
                py, port_name)
    end
end

-- Draw all nodes
function M.draw_nodes(nvg_ctx, editor, colors)
    -- Draw non-selected nodes first
    for _, node in ipairs(editor.nodes) do
        if editor.selected_node ~= node.id then
            draw_single_node(nvg_ctx, editor, colors, node)
        end
    end

    -- Draw selected node last (on top)
    if editor.selected_node then
        local selected = node_module.find_by_id(editor, editor.selected_node)
        if selected then
            draw_single_node(nvg_ctx, editor, colors, selected)
        end
    end
end

-- Draw node creation menu
function M.draw_node_menu(nvg_ctx, editor, colors, node_types)
    if not editor.show_node_menu then
        return
    end

    local menu_width = 200
    local item_height = 30
    local menu_height = #node_types * item_height + 10

    -- Menu position is in canvas-relative coordinates
    local menu_x = editor.canvas_x + editor.node_menu_x
    local menu_y = editor.canvas_y + editor.node_menu_y

    -- Menu background
    nvg.beginPath(nvg_ctx)
    nvg.roundedRect(nvg_ctx, menu_x, menu_y,
                    menu_width, menu_height, 4)
    nvg.fillColor(nvg_ctx, colors.menu_bg)
    nvg.fill(nvg_ctx)

    nvg.beginPath(nvg_ctx)
    nvg.roundedRect(nvg_ctx, menu_x, menu_y,
                    menu_width, menu_height, 4)
    nvg.strokeWidth(nvg_ctx, 1.0)
    nvg.strokeColor(nvg_ctx, nvg.rgba(80, 80, 80, 255))
    nvg.stroke(nvg_ctx)

    -- Menu items
    nvg.fontSize(nvg_ctx, 13.0)
    nvg.fontFace(nvg_ctx, "roboto")
    nvg.textAlign(nvg_ctx, nvg.ALIGN_LEFT + nvg.ALIGN_MIDDLE)

    for i, node_type in ipairs(node_types) do
        local item_y = menu_y + 5 + (i - 1) * item_height

        -- Check if mouse is over this item (mouse is in canvas-relative coords)
        local mouse_abs_x = editor.canvas_x + editor.mouse_x
        local mouse_abs_y = editor.canvas_y + editor.mouse_y
        local is_hover = mouse_abs_x >= menu_x and
                        mouse_abs_x <= menu_x + menu_width and
                        mouse_abs_y >= item_y and
                        mouse_abs_y <= item_y + item_height

        if is_hover then
            nvg.beginPath(nvg_ctx)
            nvg.rect(nvg_ctx, menu_x + 2, item_y,
                    menu_width - 4, item_height)
            nvg.fillColor(nvg_ctx, colors.menu_item_hover)
            nvg.fill(nvg_ctx)
        end

        -- Color indicator
        local node_color = nvg.rgba(
            node_type.color_r or 128,
            node_type.color_g or 128,
            node_type.color_b or 128,
            node_type.color_a or 255
        )
        nvg.beginPath(nvg_ctx)
        nvg.circle(nvg_ctx, menu_x + 15, item_y + item_height / 2, 6)
        nvg.fillColor(nvg_ctx, node_color)
        nvg.fill(nvg_ctx)

        -- Node type name
        nvg.fillColor(nvg_ctx, colors.text)
        nvg.text(nvg_ctx, menu_x + 30, item_y + item_height / 2,
                node_type.name)

        -- Port count info
        local info = string.format("%d in, %d out",
                                  #node_type.inputs, #node_type.outputs)
        nvg.fontSize(nvg_ctx, 10.0)
        nvg.fillColor(nvg_ctx, colors.text_dim)
        nvg.textAlign(nvg_ctx, nvg.ALIGN_RIGHT + nvg.ALIGN_MIDDLE)
        nvg.text(nvg_ctx, menu_x + menu_width - 10,
                item_y + item_height / 2, info)
        nvg.textAlign(nvg_ctx, nvg.ALIGN_LEFT + nvg.ALIGN_MIDDLE)
        nvg.fontSize(nvg_ctx, 13.0)
    end
end

return M
