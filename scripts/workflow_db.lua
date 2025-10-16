-- Workflow Database Manager
-- Handles SQLite persistence for workflow node types

local M = {}

-- Database handle (exposed for queries)
M.db_handle = nil
local db_handle = nil

-- Initialize database and create tables
function M.init()
    -- Open/create database
    local db, error = db.open("data/workflow.db")
    if error ~= "" then
        print("Error opening workflow database: " .. error)
        return false
    end

    db_handle = db
    M.db_handle = db
    print("Workflow database opened successfully")

    -- Create node_types table
    local success, exec_error = db_handle:execute([[
        CREATE TABLE IF NOT EXISTS node_types (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            color_r INTEGER NOT NULL,
            color_g INTEGER NOT NULL,
            color_b INTEGER NOT NULL,
            color_a INTEGER NOT NULL DEFAULT 255,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ]])

    if not success then
        print("Error creating node_types table: " .. exec_error)
        return false
    end

    -- Create node_type_ports table (for inputs and outputs)
    success, exec_error = db_handle:execute([[
        CREATE TABLE IF NOT EXISTS node_type_ports (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            node_type_id INTEGER NOT NULL,
            port_name TEXT NOT NULL,
            port_type TEXT NOT NULL CHECK(port_type IN ('input', 'output')),
            port_order INTEGER NOT NULL,
            FOREIGN KEY (node_type_id) REFERENCES node_types(id) ON DELETE CASCADE
        )
    ]])

    if not success then
        print("Error creating node_type_ports table: " .. exec_error)
        return false
    end

    -- Check if we need to add sample data
    local count_result, count_error = db_handle:query("SELECT COUNT(*) as count FROM node_types")
    if count_error ~= "" then
        print("Error checking node_types count: " .. count_error)
        return false
    end

    if count_result and #count_result > 0 and count_result[1].count == 0 then
        print("Adding default node types...")
        M.add_default_node_types()
    end

    return true
end

-- Add default node types (matching the original hardcoded types)
function M.add_default_node_types()
    -- Number node
    local node_id = M.create_node_type("Number", 80, 120, 180, 255)
    if node_id then
        M.add_port(node_id, "Value", "output", 1)
    end

    -- Math node
    node_id = M.create_node_type("Math", 120, 180, 120, 255)
    if node_id then
        M.add_port(node_id, "A", "input", 1)
        M.add_port(node_id, "B", "input", 2)
        M.add_port(node_id, "Result", "output", 1)
    end

    -- Compare node
    node_id = M.create_node_type("Compare", 180, 120, 180, 255)
    if node_id then
        M.add_port(node_id, "A", "input", 1)
        M.add_port(node_id, "B", "input", 2)
        M.add_port(node_id, "Greater", "output", 1)
        M.add_port(node_id, "Equal", "output", 2)
        M.add_port(node_id, "Less", "output", 3)
    end

    -- Branch node
    node_id = M.create_node_type("Branch", 200, 140, 80, 255)
    if node_id then
        M.add_port(node_id, "Condition", "input", 1)
        M.add_port(node_id, "True", "input", 2)
        M.add_port(node_id, "False", "input", 3)
        M.add_port(node_id, "Result", "output", 1)
    end

    -- Print node
    node_id = M.create_node_type("Print", 160, 80, 80, 255)
    if node_id then
        M.add_port(node_id, "Value", "input", 1)
    end

    -- Time node
    node_id = M.create_node_type("Time", 100, 160, 200, 255)
    if node_id then
        M.add_port(node_id, "Seconds", "output", 1)
        M.add_port(node_id, "Delta", "output", 2)
    end

    -- Event node
    node_id = M.create_node_type("Event", 220, 180, 80, 255)
    if node_id then
        M.add_port(node_id, "Trigger", "input", 1)
        M.add_port(node_id, "On Event", "output", 1)
    end

    print("Added default node types")
end

-- Create a new node type
function M.create_node_type(name, r, g, b, a)
    if not db_handle then
        print("Database not initialized")
        return nil
    end

    -- Escape single quotes
    local escaped_name = name:gsub("'", "''")

    local sql = string.format([[
        INSERT INTO node_types (name, color_r, color_g, color_b, color_a)
        VALUES ('%s', %d, %d, %d, %d)
    ]], escaped_name, r, g, b, a or 255)

    local success, error = db_handle:execute(sql)
    if not success then
        print("Error creating node type: " .. error)
        return nil
    end

    return db_handle:last_insert_rowid()
end

-- Add a port to a node type
function M.add_port(node_type_id, port_name, port_type, port_order)
    if not db_handle then
        print("Database not initialized")
        return false
    end

    -- Escape single quotes
    local escaped_name = port_name:gsub("'", "''")

    local sql = string.format([[
        INSERT INTO node_type_ports (node_type_id, port_name, port_type, port_order)
        VALUES (%d, '%s', '%s', %d)
    ]], node_type_id, escaped_name, port_type, port_order)

    local success, error = db_handle:execute(sql)
    if not success then
        print("Error adding port: " .. error)
        return false
    end

    return true
end

-- Load all node types from database
function M.load_node_types()
    if not db_handle then
        print("Database not initialized")
        return {}
    end

    -- Query all node types
    local results, error = db_handle:query([[
        SELECT id, name, color_r, color_g, color_b, color_a
        FROM node_types
        ORDER BY name
    ]])

    if error ~= "" then
        print("Error loading node types: " .. error)
        return {}
    end

    if not results then
        return {}
    end

    -- Build node type array
    local node_types = {}

    for _, node_type_row in ipairs(results) do
        local node_type = {
            id = node_type_row.id,
            name = node_type_row.name,
            color_r = node_type_row.color_r,
            color_g = node_type_row.color_g,
            color_b = node_type_row.color_b,
            color_a = node_type_row.color_a,
            inputs = {},
            outputs = {}
        }

        -- Load ports for this node type
        local ports, port_error = db_handle:query(string.format([[
            SELECT port_name, port_type, port_order
            FROM node_type_ports
            WHERE node_type_id = %d
            ORDER BY port_order
        ]], node_type_row.id))

        if port_error == "" and ports then
            for _, port in ipairs(ports) do
                if port.port_type == "input" then
                    table.insert(node_type.inputs, port.port_name)
                elseif port.port_type == "output" then
                    table.insert(node_type.outputs, port.port_name)
                end
            end
        end

        table.insert(node_types, node_type)
    end

    print("Loaded " .. #node_types .. " node types from database")
    return node_types
end

-- Update a node type
function M.update_node_type(id, name, r, g, b, a)
    if not db_handle then
        print("Database not initialized")
        return false
    end

    local escaped_name = name:gsub("'", "''")

    local sql = string.format([[
        UPDATE node_types
        SET name = '%s', color_r = %d, color_g = %d, color_b = %d, color_a = %d
        WHERE id = %d
    ]], escaped_name, r, g, b, a or 255, id)

    local success, error = db_handle:execute(sql)
    if not success then
        print("Error updating node type: " .. error)
        return false
    end

    return true
end

-- Delete a node type and its ports
function M.delete_node_type(id)
    if not db_handle then
        print("Database not initialized")
        return false
    end

    local sql = string.format("DELETE FROM node_types WHERE id = %d", id)
    local success, error = db_handle:execute(sql)

    if not success then
        print("Error deleting node type: " .. error)
        return false
    end

    return true
end

-- Delete all ports for a node type
function M.delete_ports(node_type_id)
    if not db_handle then
        print("Database not initialized")
        return false
    end

    local sql = string.format("DELETE FROM node_type_ports WHERE node_type_id = %d", node_type_id)
    local success, error = db_handle:execute(sql)

    if not success then
        print("Error deleting ports: " .. error)
        return false
    end

    return true
end

-- Close database
function M.close()
    if db_handle then
        db_handle:close()
        db_handle = nil
        M.db_handle = nil
    end
end

return M
