-- Workflow Editor Connection Operations
-- Manages connections between nodes

local M = {}

-- Add a connection between ports
function M.add(editor, from_node_id, from_port, to_node_id, to_port)
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
