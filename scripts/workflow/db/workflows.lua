-- Workflows Module
-- Handles CRUD operations for workflows, nodes, and connections

local helpers = require("scripts.workflow.db.helpers")

local M = {}

-- Reference to database handle (set by init.lua)
M.db_handle = nil

-- Create a new workflow
-- Returns (workflow_id, error) or (nil, error)
function M.create_workflow(name)
    if not M.db_handle then
        return nil, "Database not initialized"
    end

    local sql = [[
        INSERT INTO workflows (name)
        VALUES (?)
    ]]

    local success, error = M.db_handle:execute(sql, name)
    if not success then
        return nil, helpers.error_msg("create_workflow", "Error creating workflow '" .. tostring(name) .. "': " .. error)
    end

    return M.db_handle:last_insert_rowid(), nil
end

-- Get all workflows
-- Returns array of workflows
function M.get_workflows()
    if not M.db_handle then
        print("workflows.get_workflows: Database not initialized")
        return {}
    end

    local results, error = M.db_handle:query([[
        SELECT id, name, created_at, updated_at
        FROM workflows
        ORDER BY updated_at DESC
    ]])

    if error ~= "" then
        print("workflows.get_workflows: Error loading workflows: " .. error)
        return {}
    end

    return results or {}
end

-- Update workflow name
-- Returns (success, error)
function M.update_workflow(id, name)
    if not M.db_handle then
        return false, "Database not initialized"
    end

    local sql = [[
        UPDATE workflows
        SET name = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
    ]]

    local success, error = M.db_handle:execute(sql, name, id)
    if not success then
        return false, helpers.error_msg("update_workflow", "Error updating workflow " .. tostring(id) .. ": " .. error)
    end

    return true, nil
end

-- Delete a workflow
-- Returns (success, error)
function M.delete_workflow(id)
    if not M.db_handle then
        return false, "Database not initialized"
    end

    local sql = "DELETE FROM workflows WHERE id = ?"
    local success, error = M.db_handle:execute(sql, id)

    if not success then
        return false, helpers.error_msg("delete_workflow", "Error deleting workflow " .. tostring(id) .. ": " .. error)
    end

    return true, nil
end

-- Save workflow state (nodes and connections)
-- Returns (success, error)
function M.save_workflow(workflow_id, nodes, connections)
    if not M.db_handle then
        return false, "Database not initialized"
    end

    return helpers.with_transaction(M.db_handle, function()
        -- Clear existing nodes and connections for this workflow
        local success, error = M.db_handle:execute("DELETE FROM workflow_nodes WHERE workflow_id = ?", workflow_id)
        if not success then
            print("workflows.save_workflow: Error deleting workflow nodes: " .. error)
            return false
        end

        success, error = M.db_handle:execute("DELETE FROM workflow_connections WHERE workflow_id = ?", workflow_id)
        if not success then
            print("workflows.save_workflow: Error deleting workflow connections: " .. error)
            return false
        end

        -- Save nodes
        for _, node in ipairs(nodes) do
            local sql = [[
                INSERT INTO workflow_nodes (workflow_id, node_id, node_type_id, x, y)
                VALUES (?, ?, ?, ?, ?)
            ]]

            success, error = M.db_handle:execute(sql, workflow_id, node.id, node.type_index, node.x, node.y)
            if not success then
                print("workflows.save_workflow: Error saving workflow node " .. tostring(node.id) .. ": " .. error)
                return false
            end
        end

        -- Save connections
        for _, conn in ipairs(connections) do
            local sql = [[
                INSERT INTO workflow_connections (workflow_id, from_node, from_port, to_node, to_port)
                VALUES (?, ?, ?, ?, ?)
            ]]

            success, error = M.db_handle:execute(sql, workflow_id, conn.from_node, conn.from_port, conn.to_node, conn.to_port)
            if not success then
                print("workflows.save_workflow: Error saving workflow connection: " .. error)
                return false
            end
        end

        -- Update timestamp
        success, error = M.db_handle:execute("UPDATE workflows SET updated_at = CURRENT_TIMESTAMP WHERE id = ?", workflow_id)
        if not success then
            print("workflows.save_workflow: Error updating workflow timestamp: " .. error)
            return false
        end

        return true
    end)
end

-- Add a single node to a workflow
-- Returns (success, error)
function M.add_node(workflow_id, node_id, node_type_id, x, y)
    if not M.db_handle then
        return false, "Database not initialized"
    end

    local sql = [[
        INSERT INTO workflow_nodes (workflow_id, node_id, node_type_id, x, y)
        VALUES (?, ?, ?, ?, ?)
    ]]

    local success, error = M.db_handle:execute(sql, workflow_id, node_id, node_type_id, x, y)
    if not success then
        return false, helpers.error_msg("add_node", "Error adding workflow node " .. tostring(node_id) .. ": " .. error)
    end

    -- Update workflow timestamp
    helpers.touch_workflow(M.db_handle, workflow_id)

    return true, nil
end

-- Update a node's position
-- Returns (success, error)
function M.update_node_position(workflow_id, node_id, x, y)
    if not M.db_handle then
        return false, "Database not initialized"
    end

    local sql = [[
        UPDATE workflow_nodes
        SET x = ?, y = ?
        WHERE workflow_id = ? AND node_id = ?
    ]]

    local success, error = M.db_handle:execute(sql, x, y, workflow_id, node_id)
    if not success then
        return false, helpers.error_msg("update_node_position", "Error updating node " .. tostring(node_id) .. " position: " .. error)
    end

    -- Update workflow timestamp
    helpers.touch_workflow(M.db_handle, workflow_id)

    return true, nil
end

-- Delete a node from a workflow
-- Returns (success, error)
function M.delete_node(workflow_id, node_id)
    if not M.db_handle then
        return false, "Database not initialized"
    end

    return helpers.with_transaction(M.db_handle, function()
        -- Delete the node
        local sql = "DELETE FROM workflow_nodes WHERE workflow_id = ? AND node_id = ?"
        local success, error = M.db_handle:execute(sql, workflow_id, node_id)
        if not success then
            print("workflows.delete_node: Error deleting workflow node " .. tostring(node_id) .. ": " .. error)
            return false
        end

        -- Delete connections involving this node
        success, error = M.db_handle:execute(
            "DELETE FROM workflow_connections WHERE workflow_id = ? AND (from_node = ? OR to_node = ?)",
            workflow_id, node_id, node_id
        )
        if not success then
            print("workflows.delete_node: Error deleting connections for node " .. tostring(node_id) .. ": " .. error)
            return false
        end

        -- Update workflow timestamp
        success, error = M.db_handle:execute("UPDATE workflows SET updated_at = CURRENT_TIMESTAMP WHERE id = ?", workflow_id)
        if not success then
            print("workflows.delete_node: Error updating workflow timestamp: " .. error)
            return false
        end

        return true
    end)
end

-- Add a connection to a workflow
-- Returns (success, error)
function M.add_connection(workflow_id, from_node, from_port, to_node, to_port)
    if not M.db_handle then
        return false, "Database not initialized"
    end

    local sql = [[
        INSERT INTO workflow_connections (workflow_id, from_node, from_port, to_node, to_port)
        VALUES (?, ?, ?, ?, ?)
    ]]

    local success, error = M.db_handle:execute(sql, workflow_id, from_node, from_port, to_node, to_port)
    if not success then
        return false, helpers.error_msg("add_connection", "Error adding workflow connection: " .. error)
    end

    -- Update workflow timestamp
    helpers.touch_workflow(M.db_handle, workflow_id)

    return true, nil
end

-- Load workflow state (nodes and connections)
-- Returns (nodes, connections) or (nil, nil)
function M.load_workflow(workflow_id)
    if not M.db_handle then
        print("workflows.load_workflow: Database not initialized")
        return nil, nil
    end

    -- Load nodes
    local nodes_result, nodes_error = M.db_handle:query([[
        SELECT node_id, node_type_id, x, y, config
        FROM workflow_nodes
        WHERE workflow_id = ?
        ORDER BY id
    ]], workflow_id)

    if nodes_error ~= "" then
        print("workflows.load_workflow: Error loading workflow nodes for workflow " .. tostring(workflow_id) .. ": " .. nodes_error)
        return nil, nil
    end

    -- Load connections
    local conns_result, conns_error = M.db_handle:query([[
        SELECT from_node, from_port, to_node, to_port
        FROM workflow_connections
        WHERE workflow_id = ?
        ORDER BY id
    ]], workflow_id)

    if conns_error ~= "" then
        print("workflows.load_workflow: Error loading workflow connections for workflow " .. tostring(workflow_id) .. ": " .. conns_error)
        return nil, nil
    end

    -- Transform nodes to match expected format
    local nodes = {}
    if nodes_result then
        for _, node in ipairs(nodes_result) do
            local node_data = {
                id = node.node_id,
                type_index = node.node_type_id,
                x = node.x,
                y = node.y
            }

            -- Parse config if it exists
            if node.config and node.config ~= "" then
                local parse_ok, config = pcall(json.decode, node.config)
                if parse_ok and config then
                    node_data.label = config.label
                    node_data.inputs = config.inputs or {}
                    node_data.outputs = config.outputs or {}
                    node_data.script = config.script
                end
            end

            table.insert(nodes, node_data)
        end
    end

    -- Transform connections to match expected format
    local connections = {}
    if conns_result then
        for _, conn in ipairs(conns_result) do
            table.insert(connections, {
                from_node = conn.from_node,
                from_port = conn.from_port,
                to_node = conn.to_node,
                to_port = conn.to_port
            })
        end
    end

    return nodes, connections
end

-- Save workflow configuration
-- Returns (success, error)
function M.save_workflow_config(workflow_id, config)
    if not M.db_handle then
        return false, "Database not initialized"
    end

    local sql = [[
        UPDATE workflows
        SET config = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
    ]]

    local success, error = M.db_handle:execute(sql, config, workflow_id)
    if not success then
        return false, helpers.error_msg("save_workflow_config", "Error saving workflow config: " .. error)
    end

    return true, nil
end

-- Load workflow configuration
-- Returns config string or nil
function M.load_workflow_config(workflow_id)
    if not M.db_handle then
        print("workflows.load_workflow_config: Database not initialized")
        return nil
    end

    local results, error = M.db_handle:query([[
        SELECT config FROM workflows WHERE id = ?
    ]], workflow_id)

    if error ~= "" then
        print("workflows.load_workflow_config: Error loading workflow config: " .. error)
        return nil
    end

    if results and #results > 0 then
        return results[1].config
    end

    return nil
end

-- Save node configuration
-- Returns (success, error)
function M.save_node_config(workflow_id, node_id, config)
    if not M.db_handle then
        return false, "Database not initialized"
    end

    -- Convert config to JSON string if it's a table
    local config_str = config
    if type(config) == "table" then
        config_str = json.encode(config)
    end

    local sql = [[
        UPDATE workflow_nodes
        SET config = ?
        WHERE workflow_id = ? AND node_id = ?
    ]]

    local success, error = M.db_handle:execute(sql, config_str, workflow_id, node_id)
    if not success then
        return false, helpers.error_msg("save_node_config", "Error saving node config: " .. error)
    end

    -- Update workflow timestamp
    helpers.touch_workflow(M.db_handle, workflow_id)

    return true, nil
end

-- Load node configuration
-- Returns config table or nil
function M.load_node_config(workflow_id, node_id)
    if not M.db_handle then
        print("workflows.load_node_config: Database not initialized")
        return nil
    end

    local results, error = M.db_handle:query([[
        SELECT config FROM workflow_nodes WHERE workflow_id = ? AND node_id = ?
    ]], workflow_id, node_id)

    if error ~= "" then
        print("workflows.load_node_config: Error loading node config: " .. error)
        return nil
    end

    if results and #results > 0 and results[1].config then
        local config_str = results[1].config
        -- Decode JSON if it's a string
        if type(config_str) == "string" and config_str ~= "" then
            local success, decoded = pcall(json.decode, config_str)
            if success then
                return decoded
            else
                print("workflows.load_node_config: Error decoding JSON config: " .. tostring(decoded))
                return nil
            end
        end
    end

    return nil
end

return M
