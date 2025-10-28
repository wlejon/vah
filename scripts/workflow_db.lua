-- Workflow Database Manager
-- Handles SQLite persistence for workflow node types

local M = {}

-- Database handle (exposed for queries)
M.db_handle = nil

-- Input validation helpers
local function validate_color_value(value, name)
    if type(value) ~= "number" then
        return false, name .. " must be a number"
    end
    if value < 0 or value > 255 then
        return false, name .. " must be between 0 and 255"
    end
    return true, ""
end

local function validate_positive_integer(value, name)
    if type(value) ~= "number" then
        return false, name .. " must be a number"
    end
    if value < 0 or value ~= math.floor(value) then
        return false, name .. " must be a positive integer"
    end
    return true, ""
end

local function validate_string(value, name)
    if type(value) ~= "string" then
        return false, name .. " must be a string"
    end
    if #value == 0 then
        return false, name .. " cannot be empty"
    end
    return true, ""
end

local function validate_port_type(value)
    if value ~= "input" and value ~= "output" then
        return false, "port_type must be 'input' or 'output'"
    end
    return true, ""
end

-- Initialize database and create tables
function M.init()
    -- Open/create database
    local db, error = db.open("data/workflow.db")
    if error ~= "" then
        print("M.init: Error opening workflow database: " .. error)
        return false
    end

    M.db_handle = db
    print("Workflow database opened successfully")

    -- Create node_types table
    local success, exec_error = M.db_handle:execute([[
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
    success, exec_error = M.db_handle:execute([[
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

    -- Create workflows table
    success, exec_error = M.db_handle:execute([[
        CREATE TABLE IF NOT EXISTS workflows (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ]])

    if not success then
        print("Error creating workflows table: " .. exec_error)
        return false
    end

    -- Create workflow_nodes table
    success, exec_error = M.db_handle:execute([[
        CREATE TABLE IF NOT EXISTS workflow_nodes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            workflow_id INTEGER NOT NULL,
            node_id INTEGER NOT NULL,
            node_type_id INTEGER NOT NULL,
            x REAL NOT NULL,
            y REAL NOT NULL,
            FOREIGN KEY (workflow_id) REFERENCES workflows(id) ON DELETE CASCADE,
            FOREIGN KEY (node_type_id) REFERENCES node_types(id)
        )
    ]])

    if not success then
        print("Error creating workflow_nodes table: " .. exec_error)
        return false
    end

    -- Create workflow_connections table
    success, exec_error = M.db_handle:execute([[
        CREATE TABLE IF NOT EXISTS workflow_connections (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            workflow_id INTEGER NOT NULL,
            from_node INTEGER NOT NULL,
            from_port INTEGER NOT NULL,
            to_node INTEGER NOT NULL,
            to_port INTEGER NOT NULL,
            FOREIGN KEY (workflow_id) REFERENCES workflows(id) ON DELETE CASCADE
        )
    ]])

    if not success then
        print("Error creating workflow_connections table: " .. exec_error)
        return false
    end

    -- Check if we need to add sample data
    local count_result, count_error = M.db_handle:query("SELECT COUNT(*) as count FROM node_types")
    if count_error ~= "" then
        print("Error checking node_types count: " .. count_error)
        return false
    end

    if count_result and #count_result > 0 and count_result[1].count == 0 then
        print("Adding default node types...")
        M.add_default_node_types()
    end

    -- Create indexes for performance optimization
    -- Index on node_type_ports for foreign key lookups
    M.db_handle:execute([[
        CREATE INDEX IF NOT EXISTS idx_node_type_ports_type_id
        ON node_type_ports(node_type_id)
    ]])

    -- Indexes on workflow_nodes for foreign key lookups
    M.db_handle:execute([[
        CREATE INDEX IF NOT EXISTS idx_workflow_nodes_workflow_id
        ON workflow_nodes(workflow_id)
    ]])
    M.db_handle:execute([[
        CREATE INDEX IF NOT EXISTS idx_workflow_nodes_type_id
        ON workflow_nodes(node_type_id)
    ]])

    -- Indexes on workflow_connections for foreign key lookups
    M.db_handle:execute([[
        CREATE INDEX IF NOT EXISTS idx_workflow_connections_workflow_id
        ON workflow_connections(workflow_id)
    ]])
    M.db_handle:execute([[
        CREATE INDEX IF NOT EXISTS idx_workflow_connections_from_node
        ON workflow_connections(from_node)
    ]])
    M.db_handle:execute([[
        CREATE INDEX IF NOT EXISTS idx_workflow_connections_to_node
        ON workflow_connections(to_node)
    ]])

    print("Database indexes created")

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
    if not M.db_handle then
        print("M.create_node_type: Database not initialized")
        return nil
    end

    -- Validate inputs
    local valid, err = validate_string(name, "name")
    if not valid then
        print("M.create_node_type: " .. err)
        return nil
    end

    valid, err = validate_color_value(r, "color_r")
    if not valid then
        print("M.create_node_type: " .. err)
        return nil
    end

    valid, err = validate_color_value(g, "color_g")
    if not valid then
        print("M.create_node_type: " .. err)
        return nil
    end

    valid, err = validate_color_value(b, "color_b")
    if not valid then
        print("M.create_node_type: " .. err)
        return nil
    end

    a = a or 255
    valid, err = validate_color_value(a, "color_a")
    if not valid then
        print("M.create_node_type: " .. err)
        return nil
    end

    local sql = [[
        INSERT INTO node_types (name, color_r, color_g, color_b, color_a)
        VALUES (?, ?, ?, ?, ?)
    ]]

    local success, error = M.db_handle:execute(sql, name, r, g, b, a)
    if not success then
        print("M.create_node_type: Error creating node type '" .. tostring(name) .. "': " .. error)
        return nil
    end

    return M.db_handle:last_insert_rowid()
end

-- Add a port to a node type
function M.add_port(node_type_id, port_name, port_type, port_order)
    if not M.db_handle then
        print("M.add_port: Database not initialized")
        return false
    end

    -- Validate inputs
    local valid, err = validate_positive_integer(node_type_id, "node_type_id")
    if not valid then
        print("M.add_port: " .. err)
        return false
    end

    valid, err = validate_string(port_name, "port_name")
    if not valid then
        print("M.add_port: " .. err)
        return false
    end

    valid, err = validate_port_type(port_type)
    if not valid then
        print("M.add_port: " .. err)
        return false
    end

    valid, err = validate_positive_integer(port_order, "port_order")
    if not valid then
        print("M.add_port: " .. err)
        return false
    end

    local sql = [[
        INSERT INTO node_type_ports (node_type_id, port_name, port_type, port_order)
        VALUES (?, ?, ?, ?)
    ]]

    local success, error = M.db_handle:execute(sql, node_type_id, port_name, port_type, port_order)
    if not success then
        print("M.add_port: Error adding port '" .. tostring(port_name) .. "' to node type " .. tostring(node_type_id) .. ": " .. error)
        return false
    end

    return true
end

-- Load all node types from database
function M.load_node_types()
    if not M.db_handle then
        print("M.load_node_types: Database not initialized")
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
        print("M.load_node_types: Error loading node types: " .. error)
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
function M.update_node_type(id, name, r, g, b, a)
    if not M.db_handle then
        print("M.update_node_type: Database not initialized")
        return false
    end

    -- Validate inputs
    local valid, err = validate_positive_integer(id, "id")
    if not valid then
        print("M.update_node_type: " .. err)
        return false
    end

    valid, err = validate_string(name, "name")
    if not valid then
        print("M.update_node_type: " .. err)
        return false
    end

    valid, err = validate_color_value(r, "color_r")
    if not valid then
        print("M.update_node_type: " .. err)
        return false
    end

    valid, err = validate_color_value(g, "color_g")
    if not valid then
        print("M.update_node_type: " .. err)
        return false
    end

    valid, err = validate_color_value(b, "color_b")
    if not valid then
        print("M.update_node_type: " .. err)
        return false
    end

    a = a or 255
    valid, err = validate_color_value(a, "color_a")
    if not valid then
        print("M.update_node_type: " .. err)
        return false
    end

    local sql = [[
        UPDATE node_types
        SET name = ?, color_r = ?, color_g = ?, color_b = ?, color_a = ?
        WHERE id = ?
    ]]

    local success, error = M.db_handle:execute(sql, name, r, g, b, a, id)
    if not success then
        print("M.update_node_type: Error updating node type " .. tostring(id) .. ": " .. error)
        return false
    end

    return true
end

-- Delete a node type and its ports
function M.delete_node_type(id)
    if not M.db_handle then
        print("M.delete_node_type: Database not initialized")
        return false
    end

    -- Validate input
    local valid, err = validate_positive_integer(id, "id")
    if not valid then
        print("M.delete_node_type: " .. err)
        return false
    end

    local sql = "DELETE FROM node_types WHERE id = ?"
    local success, error = M.db_handle:execute(sql, id)

    if not success then
        print("M.delete_node_type: Error deleting node type " .. tostring(id) .. ": " .. error)
        return false
    end

    return true
end

-- Delete all ports for a node type
function M.delete_ports(node_type_id)
    if not M.db_handle then
        print("M.delete_ports: Database not initialized")
        return false
    end

    -- Validate input
    local valid, err = validate_positive_integer(node_type_id, "node_type_id")
    if not valid then
        print("M.delete_ports: " .. err)
        return false
    end

    local sql = "DELETE FROM node_type_ports WHERE node_type_id = ?"
    local success, error = M.db_handle:execute(sql, node_type_id)

    if not success then
        print("M.delete_ports: Error deleting ports for node type " .. tostring(node_type_id) .. ": " .. error)
        return false
    end

    return true
end

-- Close database
function M.close()
    if M.db_handle then
        M.db_handle:close()
        M.db_handle = nil
        M.db_handle = nil
    end
end

-- ============================================
-- Workflow Management Functions
-- ============================================

-- Create a new workflow
function M.create_workflow(name)
    if not M.db_handle then
        print("M.create_workflow: Database not initialized")
        return nil
    end

    local sql = [[
        INSERT INTO workflows (name)
        VALUES (?)
    ]]

    local success, error = M.db_handle:execute(sql, name)
    if not success then
        print("M.create_workflow: Error creating workflow '" .. tostring(name) .. "': " .. error)
        return nil
    end

    return M.db_handle:last_insert_rowid()
end

-- Get all workflows
function M.get_workflows()
    if not M.db_handle then
        print("M.get_workflows: Database not initialized")
        return {}
    end

    local results, error = M.db_handle:query([[
        SELECT id, name, created_at, updated_at
        FROM workflows
        ORDER BY updated_at DESC
    ]])

    if error ~= "" then
        print("M.get_workflows: Error loading workflows: " .. error)
        return {}
    end

    return results or {}
end

-- Update workflow name
function M.update_workflow(id, name)
    if not M.db_handle then
        print("M.update_workflow: Database not initialized")
        return false
    end

    local sql = [[
        UPDATE workflows
        SET name = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
    ]]

    local success, error = M.db_handle:execute(sql, name, id)
    if not success then
        print("M.update_workflow: Error updating workflow " .. tostring(id) .. ": " .. error)
        return false
    end

    return true
end

-- Delete a workflow
function M.delete_workflow(id)
    if not M.db_handle then
        print("M.delete_workflow: Database not initialized")
        return false
    end

    local sql = "DELETE FROM workflows WHERE id = ?"
    local success, error = M.db_handle:execute(sql, id)

    if not success then
        print("M.delete_workflow: Error deleting workflow " .. tostring(id) .. ": " .. error)
        return false
    end

    return true
end

-- Save workflow state (nodes and connections)
function M.save_workflow(workflow_id, nodes, connections)
    if not M.db_handle then
        print("M.save_workflow: Database not initialized")
        return false
    end

    -- Use transaction for atomicity and performance
    local success, error = M.db_handle:execute("BEGIN TRANSACTION")
    if not success then
        print("M.save_workflow: Error beginning transaction: " .. error)
        return false
    end

    -- Clear existing nodes and connections for this workflow
    success, error = M.db_handle:execute("DELETE FROM workflow_nodes WHERE workflow_id = ?", workflow_id)
    if not success then
        print("M.save_workflow: Error deleting workflow nodes: " .. error)
        M.db_handle:execute("ROLLBACK")
        return false
    end

    success, error = M.db_handle:execute("DELETE FROM workflow_connections WHERE workflow_id = ?", workflow_id)
    if not success then
        print("M.save_workflow: Error deleting workflow connections: " .. error)
        M.db_handle:execute("ROLLBACK")
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
            print("M.save_workflow: Error saving workflow node " .. tostring(node.id) .. ": " .. error)
            M.db_handle:execute("ROLLBACK")
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
            print("M.save_workflow: Error saving workflow connection: " .. error)
            M.db_handle:execute("ROLLBACK")
            return false
        end
    end

    -- Update timestamp
    success, error = M.db_handle:execute("UPDATE workflows SET updated_at = CURRENT_TIMESTAMP WHERE id = ?", workflow_id)
    if not success then
        print("M.save_workflow: Error updating workflow timestamp: " .. error)
        M.db_handle:execute("ROLLBACK")
        return false
    end

    -- Commit transaction
    success, error = M.db_handle:execute("COMMIT")
    if not success then
        print("M.save_workflow: Error committing transaction: " .. error)
        M.db_handle:execute("ROLLBACK")
        return false
    end

    return true
end

-- Add a single node to a workflow
function M.add_node(workflow_id, node_id, node_type_id, x, y)
    if not M.db_handle then
        print("M.add_node: Database not initialized")
        return false
    end

    local sql = [[
        INSERT INTO workflow_nodes (workflow_id, node_id, node_type_id, x, y)
        VALUES (?, ?, ?, ?, ?)
    ]]

    local success, error = M.db_handle:execute(sql, workflow_id, node_id, node_type_id, x, y)
    if not success then
        print("M.add_node: Error adding workflow node " .. tostring(node_id) .. ": " .. error)
        return false
    end

    -- Update workflow timestamp
    success, error = M.db_handle:execute("UPDATE workflows SET updated_at = CURRENT_TIMESTAMP WHERE id = ?", workflow_id)
    if not success then
        print("M.add_node: Error updating workflow timestamp: " .. error)
    end

    return true
end

-- Update a node's position
function M.update_node_position(workflow_id, node_id, x, y)
    if not M.db_handle then
        print("M.update_node_position: Database not initialized")
        return false
    end

    local sql = [[
        UPDATE workflow_nodes
        SET x = ?, y = ?
        WHERE workflow_id = ? AND node_id = ?
    ]]

    local success, error = M.db_handle:execute(sql, x, y, workflow_id, node_id)
    if not success then
        print("M.update_node_position: Error updating node " .. tostring(node_id) .. " position: " .. error)
        return false
    end

    -- Update workflow timestamp
    success, error = M.db_handle:execute("UPDATE workflows SET updated_at = CURRENT_TIMESTAMP WHERE id = ?", workflow_id)
    if not success then
        print("M.update_node_position: Error updating workflow timestamp: " .. error)
    end

    return true
end

-- Delete a node from a workflow
function M.delete_node(workflow_id, node_id)
    if not M.db_handle then
        print("M.delete_node: Database not initialized")
        return false
    end

    -- Use transaction for atomicity
    local success, error = M.db_handle:execute("BEGIN TRANSACTION")
    if not success then
        print("M.delete_node: Error beginning transaction: " .. error)
        return false
    end

    -- Delete the node
    local sql = "DELETE FROM workflow_nodes WHERE workflow_id = ? AND node_id = ?"

    success, error = M.db_handle:execute(sql, workflow_id, node_id)
    if not success then
        print("M.delete_node: Error deleting workflow node " .. tostring(node_id) .. ": " .. error)
        M.db_handle:execute("ROLLBACK")
        return false
    end

    -- Delete connections involving this node
    success, error = M.db_handle:execute(
        "DELETE FROM workflow_connections WHERE workflow_id = ? AND (from_node = ? OR to_node = ?)",
        workflow_id, node_id, node_id
    )
    if not success then
        print("M.delete_node: Error deleting connections for node " .. tostring(node_id) .. ": " .. error)
        M.db_handle:execute("ROLLBACK")
        return false
    end

    -- Update workflow timestamp
    success, error = M.db_handle:execute("UPDATE workflows SET updated_at = CURRENT_TIMESTAMP WHERE id = ?", workflow_id)
    if not success then
        print("M.delete_node: Error updating workflow timestamp: " .. error)
        M.db_handle:execute("ROLLBACK")
        return false
    end

    -- Commit transaction
    success, error = M.db_handle:execute("COMMIT")
    if not success then
        print("M.delete_node: Error committing transaction: " .. error)
        M.db_handle:execute("ROLLBACK")
        return false
    end

    return true
end

-- Add a connection to a workflow
function M.add_connection(workflow_id, from_node, from_port, to_node, to_port)
    if not M.db_handle then
        print("M.add_connection: Database not initialized")
        return false
    end

    local sql = [[
        INSERT INTO workflow_connections (workflow_id, from_node, from_port, to_node, to_port)
        VALUES (?, ?, ?, ?, ?)
    ]]

    local success, error = M.db_handle:execute(sql, workflow_id, from_node, from_port, to_node, to_port)
    if not success then
        print("M.add_connection: Error adding workflow connection: " .. error)
        return false
    end

    -- Update workflow timestamp
    success, error = M.db_handle:execute("UPDATE workflows SET updated_at = CURRENT_TIMESTAMP WHERE id = ?", workflow_id)
    if not success then
        print("M.add_connection: Error updating workflow timestamp: " .. error)
    end

    return true
end

-- Load workflow state (nodes and connections)
function M.load_workflow(workflow_id)
    if not M.db_handle then
        print("M.load_workflow: Database not initialized")
        return nil, nil
    end

    -- Load nodes
    local nodes_result, nodes_error = M.db_handle:query([[
        SELECT node_id, node_type_id, x, y
        FROM workflow_nodes
        WHERE workflow_id = ?
        ORDER BY id
    ]], workflow_id)

    if nodes_error ~= "" then
        print("M.load_workflow: Error loading workflow nodes for workflow " .. tostring(workflow_id) .. ": " .. nodes_error)
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
        print("M.load_workflow: Error loading workflow connections for workflow " .. tostring(workflow_id) .. ": " .. conns_error)
        return nil, nil
    end

    -- Transform nodes to match expected format
    local nodes = {}
    if nodes_result then
        for _, node in ipairs(nodes_result) do
            table.insert(nodes, {
                id = node.node_id,
                type_index = node.node_type_id,
                x = node.x,
                y = node.y
            })
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

return M
