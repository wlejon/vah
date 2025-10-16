-- Workflow Node Editor
-- A visual node-based editor built with NanoVG
-- Rendering code only - runs in RmlUI Lua state
-- Node types are provided via data binding from the workflow_editor thread

local node_types = {}

-- Editor state
local editor = {
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

    -- UI Constants
    grid_size = 20,
    node_width = 180,
    node_header_height = 30,
    node_port_height = 24,
    node_port_radius = 6,
    node_padding = 10,
    node_rounding = 8,
}

-- Color scheme
local colors = {
    background = nvg.rgba(28, 30, 34, 255),
    grid = nvg.rgba(50, 52, 56, 255),
    grid_accent = nvg.rgba(60, 62, 66, 255),

    node_bg = nvg.rgba(45, 47, 51, 255),
    node_selected = nvg.rgba(100, 140, 255, 255),
    node_shadow = nvg.rgba(0, 0, 0, 100),

    port_input = nvg.rgba(120, 200, 120, 255),
    port_output = nvg.rgba(200, 120, 120, 255),
    port_hover = nvg.rgba(255, 255, 100, 255),

    connection = nvg.rgba(150, 150, 150, 255),
    connection_active = nvg.rgba(100, 200, 255, 255),

    text = nvg.rgba(220, 220, 220, 255),
    text_dim = nvg.rgba(160, 160, 160, 255),

    menu_bg = nvg.rgba(40, 42, 46, 240),
    menu_item_hover = nvg.rgba(60, 62, 66, 255),
}

-- Transform screen coordinates to world coordinates
-- Screen coordinates are relative to the canvas (already subtracted canvas offset in mouse handler)
local function screen_to_world(screen_x, screen_y)
    return (screen_x - editor.pan_x) / editor.zoom,
           (screen_y - editor.pan_y) / editor.zoom
end

-- Transform world coordinates to screen coordinates
-- Returns coordinates relative to the canvas
local function world_to_screen(world_x, world_y)
    return world_x * editor.zoom + editor.pan_x,
           world_y * editor.zoom + editor.pan_y
end

-- Create a new node
local function create_node(x, y, node_type_index)
    local node_type = node_types[node_type_index]
    if not node_type then
        return nil
    end

    -- Convert color from r,g,b,a components to nvg.rgba
    local color = nvg.rgba(
        node_type.color_r or 128,
        node_type.color_g or 128,
        node_type.color_b or 128,
        node_type.color_a or 255
    )

    local node = {
        id = editor.next_node_id,
        x = x,
        y = y,
        type_index = node_type_index,
        name = node_type.name,
        color = color,
        inputs = node_type.inputs or {},
        outputs = node_type.outputs or {},
    }

    editor.next_node_id = editor.next_node_id + 1
    table.insert(editor.nodes, node)
    return node
end

-- Calculate node height based on port count
local function get_node_height(node)
    local port_count = math.max(#node.inputs, #node.outputs)
    return editor.node_header_height +
           (port_count * editor.node_port_height) +
           editor.node_padding
end

-- Get port position in world coordinates
local function get_port_position(node, port_index, is_output)
    local x = node.x
    local y = node.y + editor.node_header_height +
              (port_index - 1) * editor.node_port_height +
              editor.node_port_height / 2

    if is_output then
        x = x + editor.node_width
    end

    return x, y
end

-- Check if point is inside node
local function is_point_in_node(node, x, y)
    local height = get_node_height(node)
    return x >= node.x and x <= node.x + editor.node_width and
           y >= node.y and y <= node.y + height
end

-- Check if point is on a port
local function get_port_at_position(node, x, y)
    -- Check input ports
    for i = 1, #node.inputs do
        local px, py = get_port_position(node, i, false)
        local dx = x - px
        local dy = y - py
        if math.sqrt(dx * dx + dy * dy) <= editor.node_port_radius * 1.5 then
            return {node_id = node.id, port_index = i, is_output = false}
        end
    end

    -- Check output ports
    for i = 1, #node.outputs do
        local px, py = get_port_position(node, i, true)
        local dx = x - px
        local dy = y - py
        if math.sqrt(dx * dx + dy * dy) <= editor.node_port_radius * 1.5 then
            return {node_id = node.id, port_index = i, is_output = true}
        end
    end

    return nil
end

-- Find node by ID
local function find_node(node_id)
    for _, node in ipairs(editor.nodes) do
        if node.id == node_id then
            return node
        end
    end
    return nil
end

-- Add a connection between ports
local function add_connection(from_node_id, from_port, to_node_id, to_port)
    -- Check if connection already exists
    for _, conn in ipairs(editor.connections) do
        if conn.from_node == from_node_id and conn.from_port == from_port and
           conn.to_node == to_node_id and conn.to_port == to_port then
            return false
        end
    end

    table.insert(editor.connections, {
        from_node = from_node_id,
        from_port = from_port,
        to_node = to_node_id,
        to_port = to_port
    })
    return true
end

-- Draw grid background
local function draw_grid(nvg_ctx, canvas_x, canvas_y, canvas_w, canvas_h)
    nvg.save(nvg_ctx)

    -- Apply canvas transform
    nvg.translate(nvg_ctx, canvas_x + editor.pan_x, canvas_y + editor.pan_y)
    nvg.scale(nvg_ctx, editor.zoom, editor.zoom)

    -- Calculate visible grid bounds (in world coordinates)
    local world_x1, world_y1 = screen_to_world(0, 0)
    local world_x2, world_y2 = screen_to_world(canvas_w, canvas_h)

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
local function draw_connection(nvg_ctx, x1, y1, x2, y2, color, thickness)
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
local function draw_connections(nvg_ctx)
    for _, conn in ipairs(editor.connections) do
        local from_node = find_node(conn.from_node)
        local to_node = find_node(conn.to_node)

        if from_node and to_node then
            local x1, y1 = get_port_position(from_node, conn.from_port, true)
            local x2, y2 = get_port_position(to_node, conn.to_port, false)

            draw_connection(nvg_ctx, x1, y1, x2, y2, colors.connection, 3.0)
        end
    end

    -- Draw dragging connection
    if editor.dragging_connection then
        local node = find_node(editor.dragging_connection.node_id)
        if node then
            local x1, y1 = get_port_position(node,
                                            editor.dragging_connection.port_index,
                                            editor.dragging_connection.is_output)
            local world_mx, world_my = screen_to_world(editor.mouse_x, editor.mouse_y)

            if editor.dragging_connection.is_output then
                draw_connection(nvg_ctx, x1, y1, world_mx, world_my,
                              colors.connection_active, 3.0)
            else
                draw_connection(nvg_ctx, world_mx, world_my, x1, y1,
                              colors.connection_active, 3.0)
            end
        end
    end
end

-- Draw a single port
local function draw_port(nvg_ctx, x, y, is_output, is_hovered)
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
local function draw_node(nvg_ctx, node)
    local height = get_node_height(node)
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
        local px, py = get_port_position(node, i, false)
        local is_hovered_port = editor.hovered_port and
                               editor.hovered_port.node_id == node.id and
                               editor.hovered_port.port_index == i and
                               not editor.hovered_port.is_output

        draw_port(nvg_ctx, px, py, false, is_hovered_port)

        nvg.fillColor(nvg_ctx, colors.text_dim)
        nvg.text(nvg_ctx, node.x + editor.node_port_radius + 8, py, port_name)
    end

    -- Output ports
    nvg.textAlign(nvg_ctx, nvg.ALIGN_RIGHT + nvg.ALIGN_MIDDLE)
    for i, port_name in ipairs(node.outputs) do
        local px, py = get_port_position(node, i, true)
        local is_hovered_port = editor.hovered_port and
                               editor.hovered_port.node_id == node.id and
                               editor.hovered_port.port_index == i and
                               editor.hovered_port.is_output

        draw_port(nvg_ctx, px, py, true, is_hovered_port)

        nvg.fillColor(nvg_ctx, colors.text_dim)
        nvg.text(nvg_ctx, node.x + editor.node_width - editor.node_port_radius - 8,
                py, port_name)
    end
end

-- Draw all nodes
local function draw_nodes(nvg_ctx)
    -- Draw non-selected nodes first
    for _, node in ipairs(editor.nodes) do
        if editor.selected_node ~= node.id then
            draw_node(nvg_ctx, node)
        end
    end

    -- Draw selected node last (on top)
    if editor.selected_node then
        local selected = find_node(editor.selected_node)
        if selected then
            draw_node(nvg_ctx, selected)
        end
    end
end

-- Draw node creation menu
local function draw_node_menu(nvg_ctx)
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

-- Initialize with some example nodes
local function init_editor()
    -- Create example nodes if we have node types loaded
    if #node_types > 0 then
        -- Find node type indices by name for creating example nodes
        local time_idx, math_idx, number_idx, print_idx
        for i, nt in ipairs(node_types) do
            if nt.name == "Time" then time_idx = i end
            if nt.name == "Math" then math_idx = i end
            if nt.name == "Number" then number_idx = i end
            if nt.name == "Print" then print_idx = i end
        end

        if time_idx then create_node(100, 100, time_idx) end
        if math_idx then create_node(400, 80, math_idx) end
        if number_idx then create_node(400, 200, number_idx) end
        if print_idx then create_node(700, 120, print_idx) end

        -- Add some example connections
        add_connection(1, 1, 2, 1) -- Time.Seconds -> Math.A
        add_connection(3, 1, 2, 2) -- Number.Value -> Math.B
        add_connection(2, 1, 4, 1) -- Math.Result -> Print.Value
    end
end

-- Main render function
function render_workflow(nvg_ctx, canvas_x, canvas_y, canvas_w, canvas_h, time)
    -- Store canvas position for mouse coordinate conversion
    editor.canvas_x = canvas_x
    editor.canvas_y = canvas_y

    -- NanoVG renders in canvas-local coordinates, starting at (canvas_x, canvas_y)
    local x, y, w, h = canvas_x, canvas_y, canvas_w, canvas_h

    -- Draw background
    nvg.beginPath(nvg_ctx)
    nvg.rect(nvg_ctx, x, y, w, h)
    nvg.fillColor(nvg_ctx, colors.background)
    nvg.fill(nvg_ctx)

    -- Draw grid
    draw_grid(nvg_ctx, x, y, w, h)

    -- Apply canvas transform for nodes and connections
    nvg.save(nvg_ctx)
    nvg.translate(nvg_ctx, x + editor.pan_x, y + editor.pan_y)
    nvg.scale(nvg_ctx, editor.zoom, editor.zoom)

    -- Draw connections behind nodes
    draw_connections(nvg_ctx)

    -- Draw nodes
    draw_nodes(nvg_ctx)

    nvg.restore(nvg_ctx)

    -- Draw node creation menu (in screen space, but relative to canvas)
    draw_node_menu(nvg_ctx)

    -- Draw UI overlay (in screen space)
    nvg.fontSize(nvg_ctx, 12.0)
    nvg.fontFace(nvg_ctx, "roboto")
    nvg.textAlign(nvg_ctx, nvg.ALIGN_LEFT + nvg.ALIGN_TOP)
    nvg.fillColor(nvg_ctx, colors.text_dim)
    nvg.text(nvg_ctx, x + 10, y + 10,
            "Workflow Editor  |  Nodes: " .. #editor.nodes ..
            "  |  Zoom: " .. string.format("%.1f", editor.zoom * 100) .. "%")

    nvg.text(nvg_ctx, x + 10, y + 26,
            "Left: Select/Drag  |  Middle: Pan  |  Right: Create menu  |  Delete: Remove  |  1-7: Quick create")
end

-- Mouse click handler (called on button down/up events only)
-- Button: 0=left, 1=right, 2=middle
function handle_workflow_click(button, button_down, mouse_x, mouse_y, canvas_x, canvas_y)
    -- Update mouse position relative to canvas
    editor.mouse_x = mouse_x - canvas_x
    editor.mouse_y = mouse_y - canvas_y

    local world_x, world_y = screen_to_world(editor.mouse_x, editor.mouse_y)

    -- Track button state
    local was_down = editor.mouse_buttons[button + 1]
    editor.mouse_buttons[button + 1] = button_down

    -- LEFT MOUSE BUTTON - Node interaction, connections, selection
    if button == 0 then
        if button_down and not was_down then
            -- Left button press
            editor.mouse_drag_start_x = editor.mouse_x
            editor.mouse_drag_start_y = editor.mouse_y

            -- Check node menu click
            if editor.show_node_menu then
                local menu_width = 200
                local item_height = 30

                for i = 1, #node_types do
                    local item_y = editor.node_menu_y + 5 + (i - 1) * item_height
                    if editor.mouse_x >= editor.node_menu_x and
                       editor.mouse_x <= editor.node_menu_x + menu_width and
                       editor.mouse_y >= item_y and
                       editor.mouse_y <= item_y + item_height then
                        local create_world_x, create_world_y = screen_to_world(
                            editor.node_menu_x, editor.node_menu_y)
                        create_node(create_world_x, create_world_y, i)
                        editor.show_node_menu = false
                        return
                    end
                end
                editor.show_node_menu = false
                return
            end

            -- Check port interaction
            editor.hovered_port = nil
            for _, node in ipairs(editor.nodes) do
                local port = get_port_at_position(node, world_x, world_y)
                if port then
                    editor.hovered_port = port
                    editor.dragging_connection = port
                    return
                end
            end

            -- Check node interaction
            editor.dragging_node = nil
            for i = #editor.nodes, 1, -1 do
                local node = editor.nodes[i]
                if is_point_in_node(node, world_x, world_y) then
                    editor.dragging_node = node
                    editor.selected_node = node.id
                    editor.mouse_drag_start_x = world_x - node.x
                    editor.mouse_drag_start_y = world_y - node.y
                    return
                end
            end

            -- Nothing clicked - deselect
            editor.selected_node = nil

        elseif not button_down and was_down then
            -- Left button release
            if editor.dragging_connection then
                -- Complete connection
                for _, node in ipairs(editor.nodes) do
                    local target_port = get_port_at_position(node, world_x, world_y)
                    if target_port and target_port.node_id ~= editor.dragging_connection.node_id then
                        if target_port.is_output ~= editor.dragging_connection.is_output then
                            local from_node, from_port, to_node, to_port
                            if editor.dragging_connection.is_output then
                                from_node = editor.dragging_connection.node_id
                                from_port = editor.dragging_connection.port_index
                                to_node = target_port.node_id
                                to_port = target_port.port_index
                            else
                                from_node = target_port.node_id
                                from_port = target_port.port_index
                                to_node = editor.dragging_connection.node_id
                                to_port = editor.dragging_connection.port_index
                            end
                            add_connection(from_node, from_port, to_node, to_port)
                        end
                        break
                    end
                end
                editor.dragging_connection = nil
            end

            editor.dragging_node = nil
        end

    -- MIDDLE MOUSE BUTTON - Canvas panning
    elseif button == 1 then
        if button_down and not was_down then
            -- Middle button press
            editor.mouse_drag_start_x = editor.mouse_x
            editor.mouse_drag_start_y = editor.mouse_y
            editor.panning_canvas = true

        elseif not button_down and was_down then
            -- Middle button release
            editor.panning_canvas = false
        end

    -- RIGHT MOUSE BUTTON - Context menu
    elseif button == 2 then
        if button_down and not was_down then
            -- Right button press - open node creation menu
            editor.show_node_menu = true
            editor.node_menu_x = editor.mouse_x
            editor.node_menu_y = editor.mouse_y
        end
    end

    -- Update hover state (for any button/no button)
    if not editor.dragging_node and not editor.dragging_connection then
        editor.hovered_node = nil
        editor.hovered_port = nil

        for i = #editor.nodes, 1, -1 do
            local node = editor.nodes[i]
            if is_point_in_node(node, world_x, world_y) then
                editor.hovered_node = node.id
                local port = get_port_at_position(node, world_x, world_y)
                if port then
                    editor.hovered_port = port
                end
                break
            end
        end
    end
end

-- Mouse move handler (called on all mouse movement)
function handle_workflow_move(mouse_x, mouse_y, canvas_x, canvas_y, button_left, button_middle, button_right)
    -- Update mouse position relative to canvas
    editor.mouse_x = mouse_x - canvas_x
    editor.mouse_y = mouse_y - canvas_y

    local world_x, world_y = screen_to_world(editor.mouse_x, editor.mouse_y)

    -- Handle dragging if left button is pressed
    if button_left then
        if editor.dragging_node then
            editor.dragging_node.x = world_x - editor.mouse_drag_start_x
            editor.dragging_node.y = world_y - editor.mouse_drag_start_y
        end
    end

    -- Handle canvas panning if middle button is pressed
    if button_middle then
        if editor.panning_canvas then
            editor.pan_x = editor.pan_x + (editor.mouse_x - editor.mouse_drag_start_x)
            editor.pan_y = editor.pan_y + (editor.mouse_y - editor.mouse_drag_start_y)
            editor.mouse_drag_start_x = editor.mouse_x
            editor.mouse_drag_start_y = editor.mouse_y
        end
    end

    -- Update hover state when not dragging
    if not editor.dragging_node and not editor.dragging_connection then
        editor.hovered_node = nil
        editor.hovered_port = nil

        for i = #editor.nodes, 1, -1 do
            local node = editor.nodes[i]
            if is_point_in_node(node, world_x, world_y) then
                editor.hovered_node = node.id
                local port = get_port_at_position(node, world_x, world_y)
                if port then
                    editor.hovered_port = port
                end
                break
            end
        end
    end
end

-- Mouse scroll handler (mouse wheel zoom)
function handle_workflow_scroll(wheel_x, wheel_y)
    -- Zoom in/out with mouse wheel
    -- Negative wheel_y = scroll up = zoom in
    -- Positive wheel_y = scroll down = zoom out
    local zoom_factor = 1.1

    if wheel_y < 0 then
        -- Zoom in
        editor.zoom = math.min(editor.zoom * zoom_factor, 3.0)
    elseif wheel_y > 0 then
        -- Zoom out
        editor.zoom = math.max(editor.zoom / zoom_factor, 0.3)
    end
end

-- Keyboard handler
function handle_workflow_key(key, key_down)
    if not key_down then
        return
    end

    -- Delete selected node
    if key == "delete" or key == "backspace" then
        if editor.selected_node then
            -- Remove connections involving this node
            for i = #editor.connections, 1, -1 do
                local conn = editor.connections[i]
                if conn.from_node == editor.selected_node or
                   conn.to_node == editor.selected_node then
                    table.remove(editor.connections, i)
                end
            end

            -- Remove node
            for i, node in ipairs(editor.nodes) do
                if node.id == editor.selected_node then
                    table.remove(editor.nodes, i)
                    break
                end
            end

            editor.selected_node = nil
        end
    end

    -- Reset view
    if key == "r" then
        editor.pan_x = 0
        editor.pan_y = 0
        editor.zoom = 1.0
    end

    -- Zoom in/out
    if key == "=" or key == "equals" then
        editor.zoom = math.min(editor.zoom * 1.2, 3.0)
    elseif key == "minus" then
        editor.zoom = math.max(editor.zoom / 1.2, 0.3)
    end

    -- Open node creation menu
    if key == "tab" or key == "space" then
        editor.show_node_menu = not editor.show_node_menu
        if editor.show_node_menu then
            editor.node_menu_x = editor.mouse_x
            editor.node_menu_y = editor.mouse_y
        end
    end

    -- Quick create nodes with number keys
    local node_type_index = tonumber(key)
    if node_type_index and node_type_index >= 1 and node_type_index <= #node_types then
        local world_x, world_y = screen_to_world(editor.mouse_x, editor.mouse_y)
        local new_node = create_node(world_x, world_y, node_type_index)
        if new_node then
            editor.selected_node = new_node.id
        end
    end
end

-- Load node types from data store using data.get()
if data and data.get then
    node_types = data.get("node_types") or {}
    print("[Rendering] Loaded " .. #node_types .. " node types from data store")

    -- Initialize editor with example nodes
    if #node_types > 0 then
        init_editor()
    end
else
    print("[Rendering] data.get() not available")
end
