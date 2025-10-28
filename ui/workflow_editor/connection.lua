-- Workflow Editor Connection Operations
-- Manages connections between nodes

local M = {}
local node_module = require("ui.workflow_editor.node")

-- Add a connection between ports
function M.add(editor, from_node_id, from_port, to_node_id, to_port)
    -- Validate nodes exist
    local from_node = node_module.find_by_id(editor, from_node_id)
    local to_node = node_module.find_by_id(editor, to_node_id)
    if not from_node or not to_node then
        print("[Workflow] Cannot create connection: node not found")
        return false
    end

    -- Validate port indices
    if from_port < 1 or from_port > #from_node.outputs then
        print("[Workflow] Cannot create connection: invalid output port " .. from_port)
        return false
    end
    if to_port < 1 or to_port > #to_node.inputs then
        print("[Workflow] Cannot create connection: invalid input port " .. to_port)
        return false
    end

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

-- Remove all connections involving a node
function M.remove_for_node(editor, node_id)
    for i = #editor.connections, 1, -1 do
        local conn = editor.connections[i]
        if conn.from_node == node_id or conn.to_node == node_id then
            table.remove(editor.connections, i)
        end
    end
end

return M
