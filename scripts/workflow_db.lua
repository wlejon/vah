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

    -- Create workflows table
    success, exec_error = db_handle:execute([[
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
    success, exec_error = db_handle:execute([[
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
    success, exec_error = db_handle:execute([[
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

-- ============================================
-- Workflow Management Functions
-- ============================================

-- Create a new workflow
function M.create_workflow(name)
    if not db_handle then
        print("Database not initialized")
        return nil
    end

    local escaped_name = name:gsub("'", "''")

    local sql = string.format([[
        INSERT INTO workflows (name)
        VALUES ('%s')
    ]], escaped_name)

    local success, error = db_handle:execute(sql)
    if not success then
        print("Error creating workflow: " .. error)
        return nil
    end

    return db_handle:last_insert_rowid()
end

-- Get all workflows
function M.get_workflows()
    if not db_handle then
        print("Database not initialized")
        return {}
    end

    local results, error = db_handle:query([[
        SELECT id, name, created_at, updated_at
        FROM workflows
        ORDER BY updated_at DESC
    ]])

    if error ~= "" then
        print("Error loading workflows: " .. error)
        return {}
    end

    return results or {}
end

-- Update workflow name
function M.update_workflow(id, name)
    if not db_handle then
        print("Database not initialized")
        return false
    end

    local escaped_name = name:gsub("'", "''")

    local sql = string.format([[
        UPDATE workflows
        SET name = '%s', updated_at = CURRENT_TIMESTAMP
        WHERE id = %d
    ]], escaped_name, id)

    local success, error = db_handle:execute(sql)
    if not success then
        print("Error updating workflow: " .. error)
        return false
    end

    return true
end

-- Delete a workflow
function M.delete_workflow(id)
    if not db_handle then
        print("Database not initialized")
        return false
    end

    local sql = string.format("DELETE FROM workflows WHERE id = %d", id)
    local success, error = db_handle:execute(sql)

    if not success then
        print("Error deleting workflow: " .. error)
        return false
    end

    return true
end

-- Save workflow state (nodes and connections)
function M.save_workflow(workflow_id, nodes, connections)
    if not db_handle then
        print("Database not initialized")
        return false
    end

    -- Clear existing nodes and connections for this workflow
    db_handle:execute(string.format("DELETE FROM workflow_nodes WHERE workflow_id = %d", workflow_id))
    db_handle:execute(string.format("DELETE FROM workflow_connections WHERE workflow_id = %d", workflow_id))

    -- Save nodes
    for _, node in ipairs(nodes) do
        local sql = string.format([[
            INSERT INTO workflow_nodes (workflow_id, node_id, node_type_id, x, y)
            VALUES (%d, %d, %d, %f, %f)
        ]], workflow_id, node.id, node.type_index, node.x, node.y)

        local success, error = db_handle:execute(sql)
        if not success then
            print("Error saving workflow node: " .. error)
            return false
        end
    end

    -- Save connections
    for _, conn in ipairs(connections) do
        local sql = string.format([[
            INSERT INTO workflow_connections (workflow_id, from_node, from_port, to_node, to_port)
            VALUES (%d, %d, %d, %d, %d)
        ]], workflow_id, conn.from_node, conn.from_port, conn.to_node, conn.to_port)

        local success, error = db_handle:execute(sql)
        if not success then
            print("Error saving workflow connection: " .. error)
            return false
        end
    end

    -- Update timestamp
    db_handle:execute(string.format([[
        UPDATE workflows SET updated_at = CURRENT_TIMESTAMP WHERE id = %d
    ]], workflow_id))

    return true
end

-- Add a single node to a workflow
function M.add_node(workflow_id, node_id, node_type_id, x, y)
    if not db_handle then
        print("Database not initialized")
        return false
    end

    local sql = string.format([[
        INSERT INTO workflow_nodes (workflow_id, node_id, node_type_id, x, y)
        VALUES (%d, %d, %d, %f, %f)
    ]], workflow_id, node_id, node_type_id, x, y)

    local success, error = db_handle:execute(sql)
    if not success then
        print("Error adding workflow node: " .. error)
        return false
    end

    -- Update workflow timestamp
    db_handle:execute(string.format([[
        UPDATE workflows SET updated_at = CURRENT_TIMESTAMP WHERE id = %d
    ]], workflow_id))

    return true
end

-- Update a node's position
function M.update_node_position(workflow_id, node_id, x, y)
    if not db_handle then
        print("Database not initialized")
        return false
    end

    local sql = string.format([[
        UPDATE workflow_nodes
        SET x = %f, y = %f
        WHERE workflow_id = %d AND node_id = %d
    ]], x, y, workflow_id, node_id)

    local success, error = db_handle:execute(sql)
    if not success then
        print("Error updating node position: " .. error)
        return false
    end

    -- Update workflow timestamp
    db_handle:execute(string.format([[
        UPDATE workflows SET updated_at = CURRENT_TIMESTAMP WHERE id = %d
    ]], workflow_id))

    return true
end

-- Delete a node from a workflow
function M.delete_node(workflow_id, node_id)
    if not db_handle then
        print("Database not initialized")
        return false
    end

    -- Delete the node
    local sql = string.format([[
        DELETE FROM workflow_nodes WHERE workflow_id = %d AND node_id = %d
    ]], workflow_id, node_id)

    local success, error = db_handle:execute(sql)
    if not success then
        print("Error deleting workflow node: " .. error)
        return false
    end

    -- Delete connections involving this node
    db_handle:execute(string.format([[
        DELETE FROM workflow_connections WHERE workflow_id = %d AND (from_node = %d OR to_node = %d)
    ]], workflow_id, node_id, node_id))

    -- Update workflow timestamp
    db_handle:execute(string.format([[
        UPDATE workflows SET updated_at = CURRENT_TIMESTAMP WHERE id = %d
    ]], workflow_id))

    return true
end

-- Add a connection to a workflow
function M.add_connection(workflow_id, from_node, from_port, to_node, to_port)
    if not db_handle then
        print("Database not initialized")
        return false
    end

    local sql = string.format([[
        INSERT INTO workflow_connections (workflow_id, from_node, from_port, to_node, to_port)
        VALUES (%d, %d, %d, %d, %d)
    ]], workflow_id, from_node, from_port, to_node, to_port)

    local success, error = db_handle:execute(sql)
    if not success then
        print("Error adding workflow connection: " .. error)
        return false
    end

    -- Update workflow timestamp
    db_handle:execute(string.format([[
        UPDATE workflows SET updated_at = CURRENT_TIMESTAMP WHERE id = %d
    ]], workflow_id))

    return true
end

-- Load workflow state (nodes and connections)
function M.load_workflow(workflow_id)
    if not db_handle then
        print("Database not initialized")
        return nil, nil
    end

    -- Load nodes
    local nodes_result, nodes_error = db_handle:query(string.format([[
        SELECT node_id, node_type_id, x, y
        FROM workflow_nodes
        WHERE workflow_id = %d
        ORDER BY id
    ]], workflow_id))

    if nodes_error ~= "" then
        print("Error loading workflow nodes: " .. nodes_error)
        return nil, nil
    end

    -- Load connections
    local conns_result, conns_error = db_handle:query(string.format([[
        SELECT from_node, from_port, to_node, to_port
        FROM workflow_connections
        WHERE workflow_id = %d
        ORDER BY id
    ]], workflow_id))

    if conns_error ~= "" then
        print("Error loading workflow connections: " .. conns_error)
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
