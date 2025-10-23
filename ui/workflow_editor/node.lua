-- Workflow Editor Node Operations
-- Node creation, manipulation, and utility functions

local M = {}

-- Create a new node
function M.create(editor, node_types, x, y, node_type_index)
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

-- Calculate node height based on port count and label lines
-- Uses whichever is taller: port spacing or label text
function M.get_height(editor, node)
    local port_count = math.max(#node.inputs, #node.outputs)
    local port_height = port_count * editor.node_port_height

    -- Calculate label height if present
    local label_height = 0
    if node.label then
        local line_count = 1
        for _ in node.label:gmatch("\n") do
            line_count = line_count + 1
        end
        label_height = line_count * 18 + editor.node_padding  -- 18px per line
    end

    -- Body height is whichever is taller (ports are on sides, label in center)
    local body_height = math.max(port_height, label_height)

    return editor.node_header_height + body_height + editor.node_padding
end

-- Get port position in world coordinates
function M.get_port_position(editor, node, port_index, is_output)
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
function M.is_point_inside(editor, node, x, y)
    local height = M.get_height(editor, node)
    return x >= node.x and x <= node.x + editor.node_width and
           y >= node.y and y <= node.y + height
end

-- Check if point is on a port
function M.get_port_at_position(editor, node, x, y)
    -- Check input ports
    for i = 1, #node.inputs do
        local px, py = M.get_port_position(editor, node, i, false)
        local dx = x - px
        local dy = y - py
        if math.sqrt(dx * dx + dy * dy) <= editor.node_port_radius * 1.5 then
            return {node_id = node.id, port_index = i, is_output = false}
        end
    end

    -- Check output ports
    for i = 1, #node.outputs do
        local px, py = M.get_port_position(editor, node, i, true)
        local dx = x - px
        local dy = y - py
        if math.sqrt(dx * dx + dy * dy) <= editor.node_port_radius * 1.5 then
            return {node_id = node.id, port_index = i, is_output = true}
        end
    end

    return nil
end

-- Find node by ID
function M.find_by_id(editor, node_id)
    for _, node in ipairs(editor.nodes) do
        if node.id == node_id then
            return node
        end
    end
    return nil
end

-- Update existing nodes to match new type definitions
function M.update_from_types(editor, node_types)
    for _, node in ipairs(editor.nodes) do
        if node.type_index and node.type_index <= #node_types then
            local node_type = node_types[node.type_index]

            -- Update node name and color
            node.name = node_type.name
            node.color = nvg.rgba(
                node_type.color_r or 128,
                node_type.color_g or 128,
                node_type.color_b or 128,
                node_type.color_a or 255
            )

            -- Update inputs
            local old_input_count = #node.inputs
            node.inputs = {}
            for i, port_name in ipairs(node_type.inputs or {}) do
                table.insert(node.inputs, port_name)
            end

            -- If inputs were removed, remove affected connections
            if #node.inputs < old_input_count then
                for i = #editor.connections, 1, -1 do
                    local conn = editor.connections[i]
                    if conn.to_node == node.id and conn.to_port > #node.inputs then
                        table.remove(editor.connections, i)
                    end
                end
            end

            -- Update outputs
            local old_output_count = #node.outputs
            node.outputs = {}
            for i, port_name in ipairs(node_type.outputs or {}) do
                table.insert(node.outputs, port_name)
            end

            -- If outputs were removed, remove affected connections
            if #node.outputs < old_output_count then
                for i = #editor.connections, 1, -1 do
                    local conn = editor.connections[i]
                    if conn.from_node == node.id and conn.from_port > #node.outputs then
                        table.remove(editor.connections, i)
                    end
                end
            end
        end
    end
end

return M
