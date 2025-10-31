-- Node Types Module
-- Handles CRUD operations for workflow node types

local validation = require("scripts.workflow.db.validation")
local helpers = require("scripts.workflow.db.helpers")

local M = {}

-- Reference to database handle (set by init.lua)
M.db_handle = nil

-- Add default node types (matching the original hardcoded types)
function M.add_default_node_types()
    -- Number node
    local node_id, err = M.create_node_type("Number", 80, 120, 180, 255)
    if node_id then
        M.add_port(node_id, "Value", "output", 1)
    end

    -- Math node
    node_id, err = M.create_node_type("Math", 120, 180, 120, 255)
    if node_id then
        M.add_port(node_id, "A", "input", 1)
        M.add_port(node_id, "B", "input", 2)
        M.add_port(node_id, "Result", "output", 1)
    end

    -- Compare node
    node_id, err = M.create_node_type("Compare", 180, 120, 180, 255)
    if node_id then
        M.add_port(node_id, "A", "input", 1)
        M.add_port(node_id, "B", "input", 2)
        M.add_port(node_id, "Greater", "output", 1)
        M.add_port(node_id, "Equal", "output", 2)
        M.add_port(node_id, "Less", "output", 3)
    end

    -- Branch node
    node_id, err = M.create_node_type("Branch", 200, 140, 80, 255)
    if node_id then
        M.add_port(node_id, "Condition", "input", 1)
        M.add_port(node_id, "True", "input", 2)
        M.add_port(node_id, "False", "input", 3)
        M.add_port(node_id, "Result", "output", 1)
    end

    -- Print node
    node_id, err = M.create_node_type("Print", 160, 80, 80, 255)
    if node_id then
        M.add_port(node_id, "Value", "input", 1)
    end

    -- Time node
    node_id, err = M.create_node_type("Time", 100, 160, 200, 255)
    if node_id then
        M.add_port(node_id, "Seconds", "output", 1)
        M.add_port(node_id, "Delta", "output", 2)
    end

    -- Event node
    node_id, err = M.create_node_type("Event", 220, 180, 80, 255)
    if node_id then
        M.add_port(node_id, "Trigger", "input", 1)
        M.add_port(node_id, "On Event", "output", 1)
    end

    print("Added default node types")
end

-- Create a new node type
-- Returns (node_type_id, error) or (nil, error)
function M.create_node_type(name, r, g, b, a)
    if not M.db_handle then
        return nil, "Database not initialized"
    end

    a = a or 255

    -- Validate inputs
    local valid, err = validation.validate("node_type", {
        name = name,
        color_r = r,
        color_g = g,
        color_b = b,
        color_a = a
    })

    if not valid then
        return nil, err
    end

    local sql = [[
        INSERT INTO node_types (name, color_r, color_g, color_b, color_a)
        VALUES (?, ?, ?, ?, ?)
    ]]

    local success, error = M.db_handle:execute(sql, name, r, g, b, a)
    if not success then
        return nil, helpers.error_msg("create_node_type", "Error creating node type '" .. tostring(name) .. "': " .. error)
    end

    return M.db_handle:last_insert_rowid(), nil
end

-- Add a port to a node type
-- Returns (success, error)
function M.add_port(node_type_id, port_name, port_type, port_order)
    if not M.db_handle then
        return false, "Database not initialized"
    end

    -- Validate inputs
    local valid, err = validation.validate_port_data(node_type_id, port_name, port_type, port_order)
    if not valid then
        return false, err
    end

    local sql = [[
        INSERT INTO node_type_ports (node_type_id, port_name, port_type, port_order)
        VALUES (?, ?, ?, ?)
    ]]

    local success, error = M.db_handle:execute(sql, node_type_id, port_name, port_type, port_order)
    if not success then
        return false, helpers.error_msg("add_port", "Error adding port '" .. tostring(port_name) .. "' to node type " .. tostring(node_type_id) .. ": " .. error)
    end

    return true, nil
end

-- Load all node types from database
-- Returns array of node types
function M.load_node_types()
    if not M.db_handle then
        print("node_types.load_node_types: Database not initialized")
        return {}
    end

    -- Query all node types with ports in a single JOIN query to avoid N+1 pattern
    local results, error = M.db_handle:query([[
        SELECT nt.id, nt.name, nt.color_r, nt.color_g, nt.color_b, nt.color_a,
               p.port_name, p.port_type, p.port_order
        FROM node_types nt
        LEFT JOIN node_type_ports p ON p.node_type_id = nt.id
        ORDER BY nt.name, p.port_type, p.port_order
    ]])

    if error ~= "" then
        print("node_types.load_node_types: Error loading node types: " .. error)
        return {}
    end

    if not results then
        return {}
    end

    -- Build node type array from joined results
    local node_types = {}
    local node_type_map = {}

    for _, row in ipairs(results) do
        -- Create or find the node type entry
        local node_type = node_type_map[row.id]
        if not node_type then
            node_type = {
                id = row.id,
                name = row.name,
                color_r = row.color_r,
                color_g = row.color_g,
                color_b = row.color_b,
                color_a = row.color_a,
                inputs = {},
                outputs = {}
            }
            node_type_map[row.id] = node_type
            table.insert(node_types, node_type)
        end

        -- Add port if present (LEFT JOIN may have null port data)
        if row.port_name then
            if row.port_type == "input" then
                table.insert(node_type.inputs, row.port_name)
            elseif row.port_type == "output" then
                table.insert(node_type.outputs, row.port_name)
            end
        end
    end

    return node_types
end

-- Update a node type
-- Returns (success, error)
function M.update_node_type(id, name, r, g, b, a)
    if not M.db_handle then
        return false, "Database not initialized"
    end

    a = a or 255

    -- Validate ID
    local valid, err = validation.validate_positive_integer(id, "id")
    if not valid then
        return false, err
    end

    -- Validate other inputs
    valid, err = validation.validate("node_type", {
        name = name,
        color_r = r,
        color_g = g,
        color_b = b,
        color_a = a
    })

    if not valid then
        return false, err
    end

    local sql = [[
        UPDATE node_types
        SET name = ?, color_r = ?, color_g = ?, color_b = ?, color_a = ?
        WHERE id = ?
    ]]

    local success, error = M.db_handle:execute(sql, name, r, g, b, a, id)
    if not success then
        return false, helpers.error_msg("update_node_type", "Error updating node type " .. tostring(id) .. ": " .. error)
    end

    return true, nil
end

-- Delete a node type and its ports
-- Returns (success, error)
function M.delete_node_type(id)
    if not M.db_handle then
        return false, "Database not initialized"
    end

    -- Validate input
    local valid, err = validation.validate_positive_integer(id, "id")
    if not valid then
        return false, err
    end

    local sql = "DELETE FROM node_types WHERE id = ?"
    local success, error = M.db_handle:execute(sql, id)

    if not success then
        return false, helpers.error_msg("delete_node_type", "Error deleting node type " .. tostring(id) .. ": " .. error)
    end

    return true, nil
end

-- Delete all ports for a node type
-- Returns (success, error)
function M.delete_ports(node_type_id)
    if not M.db_handle then
        return false, "Database not initialized"
    end

    -- Validate input
    local valid, err = validation.validate_positive_integer(node_type_id, "node_type_id")
    if not valid then
        return false, err
    end

    local sql = "DELETE FROM node_type_ports WHERE node_type_id = ?"
    local success, error = M.db_handle:execute(sql, node_type_id)

    if not success then
        return false, helpers.error_msg("delete_ports", "Error deleting ports for node type " .. tostring(node_type_id) .. ": " .. error)
    end

    return true, nil
end

return M
