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

    -- Add new columns to workflows table
    M.db_handle:execute("ALTER TABLE workflows ADD COLUMN script TEXT")
    M.db_handle:execute("ALTER TABLE workflows ADD COLUMN config TEXT")

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

    -- Add config column to workflow_nodes table
    M.db_handle:execute("ALTER TABLE workflow_nodes ADD COLUMN config TEXT")

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

    -- Create library_registry table
    success, exec_error = M.db_handle:execute([[
        CREATE TABLE IF NOT EXISTS library_registry (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT NOT NULL,
            access_description TEXT NOT NULL,
            is_builtin BOOLEAN DEFAULT 0,
            enabled BOOLEAN DEFAULT 1,
            lua_module_path TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ]])

    if not success then
        print("Error creating library_registry table: " .. exec_error)
        return false
    end

    -- Create workflow_approvals table
    success, exec_error = M.db_handle:execute([[
        CREATE TABLE IF NOT EXISTS workflow_approvals (
            workflow_id INTEGER PRIMARY KEY,
            approved BOOLEAN DEFAULT 0,
            requires_hash TEXT,
            approved_at TIMESTAMP,
            FOREIGN KEY (workflow_id) REFERENCES workflows(id) ON DELETE CASCADE
        )
    ]])

    if not success then
        print("Error creating workflow_approvals table: " .. exec_error)
        return false
    end

    -- Create workflow_executions table
    success, exec_error = M.db_handle:execute([[
        CREATE TABLE IF NOT EXISTS workflow_executions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            workflow_id INTEGER NOT NULL,
            status TEXT NOT NULL,
            thread_id INTEGER,
            started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            ended_at TIMESTAMP,
            error_message TEXT,
            FOREIGN KEY (workflow_id) REFERENCES workflows(id) ON DELETE CASCADE
        )
    ]])

    if not success then
        print("Error creating workflow_executions table: " .. exec_error)
        return false
    end

    -- Create execution_nodes table
    success, exec_error = M.db_handle:execute([[
        CREATE TABLE IF NOT EXISTS execution_nodes (
            execution_id INTEGER NOT NULL,
            node_id INTEGER NOT NULL,
            status TEXT NOT NULL,
            inputs TEXT,
            outputs TEXT,
            error_message TEXT,
            execution_order INTEGER,
            started_at TIMESTAMP,
            completed_at TIMESTAMP,
            PRIMARY KEY (execution_id, node_id),
            FOREIGN KEY (execution_id) REFERENCES workflow_executions(id) ON DELETE CASCADE
        )
    ]])

    if not success then
        print("Error creating execution_nodes table: " .. exec_error)
        return false
    end

    -- Create execution_trace table
    success, exec_error = M.db_handle:execute([[
        CREATE TABLE IF NOT EXISTS execution_trace (
            execution_id INTEGER NOT NULL,
            sequence INTEGER NOT NULL,
            node_id INTEGER NOT NULL,
            timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (execution_id, sequence),
            FOREIGN KEY (execution_id) REFERENCES workflow_executions(id) ON DELETE CASCADE
        )
    ]])

    if not success then
        print("Error creating execution_trace table: " .. exec_error)
        return false
    end

    -- Create execution_control table
    success, exec_error = M.db_handle:execute([[
        CREATE TABLE IF NOT EXISTS execution_control (
            execution_id INTEGER PRIMARY KEY,
            command TEXT NOT NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (execution_id) REFERENCES workflow_executions(id) ON DELETE CASCADE
        )
    ]])

    if not success then
        print("Error creating execution_control table: " .. exec_error)
        return false
    end

    -- Create execution_cleanup table
    success, exec_error = M.db_handle:execute([[
        CREATE TABLE IF NOT EXISTS execution_cleanup (
            execution_id INTEGER PRIMARY KEY,
            cleanup_after TIMESTAMP,
            keep_indefinitely BOOLEAN DEFAULT 0,
            FOREIGN KEY (execution_id) REFERENCES workflow_executions(id) ON DELETE CASCADE
        )
    ]])

    if not success then
        print("Error creating execution_cleanup table: " .. exec_error)
        return false
    end

    -- Check if we need to populate library_registry
    local lib_count_result, lib_count_error = M.db_handle:query("SELECT COUNT(*) as count FROM library_registry")
    if lib_count_error == "" and lib_count_result and #lib_count_result > 0 and lib_count_result[1].count == 0 then
        print("Populating library registry with default C++ libraries...")
        M.populate_library_registry()
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

    -- Execution-related indexes
    M.db_handle:execute([[
        CREATE INDEX IF NOT EXISTS idx_executions_workflow
        ON workflow_executions(workflow_id)
    ]])
    M.db_handle:execute([[
        CREATE INDEX IF NOT EXISTS idx_executions_status
        ON workflow_executions(status)
    ]])
    M.db_handle:execute([[
        CREATE INDEX IF NOT EXISTS idx_executions_status_date
        ON workflow_executions(status, started_at DESC)
    ]])
    M.db_handle:execute([[
        CREATE INDEX IF NOT EXISTS idx_execution_nodes_execution
        ON execution_nodes(execution_id)
    ]])
    M.db_handle:execute([[
        CREATE INDEX IF NOT EXISTS idx_execution_nodes_status
        ON execution_nodes(execution_id, status)
    ]])
    M.db_handle:execute([[
        CREATE INDEX IF NOT EXISTS idx_trace_sequence
        ON execution_trace(execution_id, sequence)
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

-- Populate library registry with default C++ libraries
function M.populate_library_registry()
    if not M.db_handle then
        print("M.populate_library_registry: Database not initialized")
        return false
    end

    local libraries = {
        {id = "math", name = "Math Operations",
         description = "Standard mathematical functions and constants",
         access_description = "No data access - pure computation"},
        {id = "string", name = "String Operations",
         description = "String manipulation and pattern matching",
         access_description = "No data access - pure computation"},
        {id = "table", name = "Table Operations",
         description = "Table manipulation utilities",
         access_description = "No data access - pure computation"},
        {id = "db", name = "Database Access",
         description = "Query and modify SQLite databases",
         access_description = "Read/write access to execution-specific tables"},
        {id = "fs", name = "File System Access",
         description = "Read and write files on disk",
         access_description = "Full file system access (current user permissions)"},
        {id = "http", name = "Network Access",
         description = "Make HTTP/HTTPS requests",
         access_description = "Can send data to external services"},
        {id = "ui", name = "User Interface",
         description = "Create UI windows using RmlUI",
         access_description = "Can display content and capture user input"},
        {id = "thread", name = "Threading Utilities",
         description = "Thread management and querying",
         access_description = "Limited to thread queries and sleep"},
        {id = "event", name = "Event System",
         description = "Trigger and listen for events",
         access_description = "Can communicate with other application components"}
    }

    local sql = [[
        INSERT INTO library_registry (id, name, description, access_description, is_builtin)
        VALUES (?, ?, ?, ?, 1)
    ]]

    for _, lib in ipairs(libraries) do
        local success, error = M.db_handle:execute(sql, lib.id, lib.name, lib.description, lib.access_description)
        if not success then
            print("M.populate_library_registry: Error adding library '" .. lib.id .. "': " .. error)
        end
    end

    print("Library registry populated with default libraries")
    return true
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
        SELECT node_id, node_type_id, x, y, config
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

-- ============================================
-- Workflow Configuration Functions
-- ============================================

-- Save workflow configuration
function M.save_workflow_config(workflow_id, config)
    if not M.db_handle then
        print("M.save_workflow_config: Database not initialized")
        return false
    end

    local sql = [[
        UPDATE workflows
        SET config = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
    ]]

    local success, error = M.db_handle:execute(sql, config, workflow_id)
    if not success then
        print("M.save_workflow_config: Error saving workflow config: " .. error)
        return false
    end

    return true
end

-- Load workflow configuration
function M.load_workflow_config(workflow_id)
    if not M.db_handle then
        print("M.load_workflow_config: Database not initialized")
        return nil
    end

    local results, error = M.db_handle:query([[
        SELECT config FROM workflows WHERE id = ?
    ]], workflow_id)

    if error ~= "" then
        print("M.load_workflow_config: Error loading workflow config: " .. error)
        return nil
    end

    if results and #results > 0 then
        return results[1].config
    end

    return nil
end

-- Save node configuration
function M.save_node_config(workflow_id, node_id, config)
    if not M.db_handle then
        print("M.save_node_config: Database not initialized")
        return false
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
        print("M.save_node_config: Error saving node config: " .. error)
        return false
    end

    -- Update workflow timestamp
    M.db_handle:execute("UPDATE workflows SET updated_at = CURRENT_TIMESTAMP WHERE id = ?", workflow_id)

    return true
end

-- Load node configuration
function M.load_node_config(workflow_id, node_id)
    if not M.db_handle then
        print("M.load_node_config: Database not initialized")
        return nil
    end

    local results, error = M.db_handle:query([[
        SELECT config FROM workflow_nodes WHERE workflow_id = ? AND node_id = ?
    ]], workflow_id, node_id)

    if error ~= "" then
        print("M.load_node_config: Error loading node config: " .. error)
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
                print("M.load_node_config: Error decoding JSON config: " .. tostring(decoded))
                return nil
            end
        end
    end

    return nil
end

-- ============================================
-- Execution Management Functions
-- ============================================

-- Create a new execution record
function M.create_execution_record(workflow_id, thread_id)
    if not M.db_handle then
        print("M.create_execution_record: Database not initialized")
        return nil
    end

    local sql = [[
        INSERT INTO workflow_executions (workflow_id, status, thread_id)
        VALUES (?, 'running', ?)
    ]]

    local success, error = M.db_handle:execute(sql, workflow_id, thread_id)
    if not success then
        print("M.create_execution_record: Error creating execution record: " .. error)
        return nil
    end

    return M.db_handle:last_insert_rowid()
end

-- Update execution status
function M.update_execution_status(execution_id, status, error_message)
    if not M.db_handle then
        print("M.update_execution_status: Database not initialized")
        return false
    end

    local sql
    if error_message then
        sql = [[
            UPDATE workflow_executions
            SET status = ?, error_message = ?, ended_at = CURRENT_TIMESTAMP
            WHERE id = ?
        ]]
    else
        sql = [[
            UPDATE workflow_executions
            SET status = ?, ended_at = CURRENT_TIMESTAMP
            WHERE id = ?
        ]]
    end

    local success, exec_error
    if error_message then
        success, exec_error = M.db_handle:execute(sql, status, error_message, execution_id)
    else
        success, exec_error = M.db_handle:execute(sql, status, execution_id)
    end

    if not success then
        print("M.update_execution_status: Error updating execution status: " .. exec_error)
        return false
    end

    return true
end

-- Update or insert node execution status
function M.update_node_execution(execution_id, node_id, status, inputs, outputs, error_message)
    if not M.db_handle then
        print("M.update_node_execution: Database not initialized")
        return false
    end

    -- Check if node execution already exists
    local check_sql = [[
        SELECT execution_order FROM execution_nodes
        WHERE execution_id = ? AND node_id = ?
    ]]

    local results, query_error = M.db_handle:query(check_sql, execution_id, node_id)
    if query_error ~= "" then
        print("M.update_node_execution: Error checking node execution: " .. query_error)
        return false
    end

    local sql
    local success, exec_error

    if results and #results > 0 then
        -- Update existing record
        sql = [[
            UPDATE execution_nodes
            SET status = ?, inputs = ?, outputs = ?, error_message = ?,
                completed_at = CASE WHEN ? IN ('completed', 'error', 'skipped') THEN CURRENT_TIMESTAMP ELSE completed_at END
            WHERE execution_id = ? AND node_id = ?
        ]]
        success, exec_error = M.db_handle:execute(sql, status, inputs, outputs, error_message, status, execution_id, node_id)
    else
        -- Insert new record
        -- Get next execution order
        local order_sql = [[
            SELECT COALESCE(MAX(execution_order), 0) + 1 as next_order
            FROM execution_nodes WHERE execution_id = ?
        ]]
        local order_results, order_error = M.db_handle:query(order_sql, execution_id)
        if order_error ~= "" then
            print("M.update_node_execution: Error getting execution order: " .. order_error)
            return false
        end

        local execution_order = 1
        if order_results and #order_results > 0 then
            execution_order = order_results[1].next_order
        end

        sql = [[
            INSERT INTO execution_nodes (execution_id, node_id, status, inputs, outputs, error_message, execution_order, started_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        ]]
        success, exec_error = M.db_handle:execute(sql, execution_id, node_id, status, inputs, outputs, error_message, execution_order)
    end

    if not success then
        print("M.update_node_execution: Error updating node execution: " .. exec_error)
        return false
    end

    return true
end

-- Add entry to execution trace
function M.add_execution_trace(execution_id, node_id)
    if not M.db_handle then
        print("M.add_execution_trace: Database not initialized")
        return false
    end

    -- Get next sequence number
    local seq_sql = [[
        SELECT COALESCE(MAX(sequence), 0) + 1 as next_seq
        FROM execution_trace WHERE execution_id = ?
    ]]
    local results, error = M.db_handle:query(seq_sql, execution_id)
    if error ~= "" then
        print("M.add_execution_trace: Error getting sequence: " .. error)
        return false
    end

    local sequence = 1
    if results and #results > 0 then
        sequence = results[1].next_seq
    end

    local sql = [[
        INSERT INTO execution_trace (execution_id, sequence, node_id)
        VALUES (?, ?, ?)
    ]]

    local success, exec_error = M.db_handle:execute(sql, execution_id, sequence, node_id)
    if not success then
        print("M.add_execution_trace: Error adding trace entry: " .. exec_error)
        return false
    end

    return true
end

-- Create per-execution state and log tables
function M.create_execution_tables(execution_id)
    if not M.db_handle then
        print("M.create_execution_tables: Database not initialized")
        return false
    end

    -- Create state table
    local state_sql = string.format([[
        CREATE TABLE IF NOT EXISTS exec_%d_state (
            key TEXT PRIMARY KEY,
            value TEXT,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ]], execution_id)

    local success, error = M.db_handle:execute(state_sql)
    if not success then
        print("M.create_execution_tables: Error creating state table: " .. error)
        return false
    end

    -- Create log table
    local log_sql = string.format([[
        CREATE TABLE IF NOT EXISTS exec_%d_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            level TEXT,
            node_id INTEGER,
            message TEXT
        )
    ]], execution_id)

    success, error = M.db_handle:execute(log_sql)
    if not success then
        print("M.create_execution_tables: Error creating log table: " .. error)
        return false
    end

    return true
end

-- Delete per-execution tables (for cleanup)
function M.delete_execution_tables(execution_id)
    if not M.db_handle then
        print("M.delete_execution_tables: Database not initialized")
        return false
    end

    local state_sql = string.format("DROP TABLE IF EXISTS exec_%d_state", execution_id)
    local log_sql = string.format("DROP TABLE IF EXISTS exec_%d_log", execution_id)

    M.db_handle:execute(state_sql)
    M.db_handle:execute(log_sql)

    return true
end

-- Set execution state value
function M.set_execution_state(execution_id, key, value)
    if not M.db_handle then
        print("M.set_execution_state: Database not initialized")
        return false
    end

    local sql = string.format([[
        INSERT OR REPLACE INTO exec_%d_state (key, value, updated_at)
        VALUES (?, ?, CURRENT_TIMESTAMP)
    ]], execution_id)

    local success, error = M.db_handle:execute(sql, key, value)
    if not success then
        print("M.set_execution_state: Error setting state: " .. error)
        return false
    end

    return true
end

-- Get execution state value
function M.get_execution_state(execution_id, key)
    if not M.db_handle then
        print("M.get_execution_state: Database not initialized")
        return nil
    end

    local sql = string.format([[
        SELECT value FROM exec_%d_state WHERE key = ?
    ]], execution_id)

    local results, error = M.db_handle:query(sql, key)
    if error ~= "" then
        print("M.get_execution_state: Error getting state: " .. error)
        return nil
    end

    if results and #results > 0 then
        return results[1].value
    end

    return nil
end

-- Add execution log entry
function M.add_execution_log(execution_id, level, message, node_id)
    if not M.db_handle then
        print("M.add_execution_log: Database not initialized")
        return false
    end

    local sql = string.format([[
        INSERT INTO exec_%d_log (level, message, node_id)
        VALUES (?, ?, ?)
    ]], execution_id)

    local success, error = M.db_handle:execute(sql, level, message, node_id)
    if not success then
        print("M.add_execution_log: Error adding log entry: " .. error)
        return false
    end

    return true
end

-- Get execution logs
function M.get_execution_logs(execution_id, level_filter)
    if not M.db_handle then
        print("M.get_execution_logs: Database not initialized")
        return {}
    end

    local sql
    if level_filter then
        sql = string.format([[
            SELECT timestamp, level, node_id, message
            FROM exec_%d_log
            WHERE level = ?
            ORDER BY id
        ]], execution_id)
    else
        sql = string.format([[
            SELECT timestamp, level, node_id, message
            FROM exec_%d_log
            ORDER BY id
        ]], execution_id)
    end

    local results, error
    if level_filter then
        results, error = M.db_handle:query(sql, level_filter)
    else
        results, error = M.db_handle:query(sql)
    end

    if error ~= "" then
        print("M.get_execution_logs: Error getting logs: " .. error)
        return {}
    end

    return results or {}
end

-- ============================================
-- Workflow Approval Functions
-- ============================================

-- Check if workflow has valid approval
function M.check_workflow_approval(workflow_id, requires_hash)
    if not M.db_handle then
        print("M.check_workflow_approval: Database not initialized")
        return false
    end

    local sql = [[
        SELECT approved, requires_hash
        FROM workflow_approvals
        WHERE workflow_id = ?
    ]]

    local results, error = M.db_handle:query(sql, workflow_id)
    if error ~= "" then
        print("M.check_workflow_approval: Error checking approval: " .. error)
        return false
    end

    if not results or #results == 0 then
        return false  -- No approval record
    end

    local approval = results[1]
    if approval.approved == 0 then
        return false  -- Not approved
    end

    if approval.requires_hash ~= requires_hash then
        return false  -- Hash mismatch, requires re-approval
    end

    return true
end

-- Save workflow approval
function M.save_workflow_approval(workflow_id, requires_hash, approved)
    if not M.db_handle then
        print("M.save_workflow_approval: Database not initialized")
        return false
    end

    local sql = [[
        INSERT OR REPLACE INTO workflow_approvals (workflow_id, approved, requires_hash, approved_at)
        VALUES (?, ?, ?, CURRENT_TIMESTAMP)
    ]]

    local success, error = M.db_handle:execute(sql, workflow_id, approved and 1 or 0, requires_hash)
    if not success then
        print("M.save_workflow_approval: Error saving approval: " .. error)
        return false
    end

    return true
end

-- ============================================
-- Library Registry Functions
-- ============================================

-- Get all library definitions
function M.get_library_definitions()
    if not M.db_handle then
        print("M.get_library_definitions: Database not initialized")
        return {}
    end

    local results, error = M.db_handle:query([[
        SELECT id, name, description, access_description, is_builtin, enabled, lua_module_path
        FROM library_registry
        ORDER BY is_builtin DESC, name
    ]])

    if error ~= "" then
        print("M.get_library_definitions: Error loading libraries: " .. error)
        return {}
    end

    return results or {}
end

-- Get enabled libraries
function M.get_enabled_libraries()
    if not M.db_handle then
        print("M.get_enabled_libraries: Database not initialized")
        return {}
    end

    local results, error = M.db_handle:query([[
        SELECT id, name, description, access_description, is_builtin, lua_module_path
        FROM library_registry
        WHERE enabled = 1
        ORDER BY is_builtin DESC, name
    ]])

    if error ~= "" then
        print("M.get_enabled_libraries: Error loading enabled libraries: " .. error)
        return {}
    end

    return results or {}
end

-- Enable/disable a library
function M.set_library_enabled(library_id, enabled)
    if not M.db_handle then
        print("M.set_library_enabled: Database not initialized")
        return false
    end

    local sql = [[
        UPDATE library_registry
        SET enabled = ?
        WHERE id = ?
    ]]

    local success, error = M.db_handle:execute(sql, enabled and 1 or 0, library_id)
    if not success then
        print("M.set_library_enabled: Error updating library: " .. error)
        return false
    end

    return true
end

-- ============================================
-- Execution Control Functions
-- ============================================

-- Set execution control command
function M.set_execution_control(execution_id, command)
    if not M.db_handle then
        print("M.set_execution_control: Database not initialized")
        return false
    end

    local sql = [[
        INSERT OR REPLACE INTO execution_control (execution_id, command, updated_at)
        VALUES (?, ?, CURRENT_TIMESTAMP)
    ]]

    local success, error = M.db_handle:execute(sql, execution_id, command)
    if not success then
        print("M.set_execution_control: Error setting control command: " .. error)
        return false
    end

    return true
end

-- Get execution control command
function M.get_execution_control(execution_id)
    if not M.db_handle then
        print("M.get_execution_control: Database not initialized")
        return nil
    end

    local sql = [[
        SELECT command FROM execution_control WHERE execution_id = ?
    ]]

    local results, error = M.db_handle:query(sql, execution_id)
    if error ~= "" then
        print("M.get_execution_control: Error getting control command: " .. error)
        return nil
    end

    if results and #results > 0 then
        return results[1].command
    end

    return nil
end

-- Get execution by ID
function M.get_execution(execution_id)
    if not M.db_handle then
        print("M.get_execution: Database not initialized")
        return nil
    end

    local sql = [[
        SELECT id, workflow_id, status, thread_id, started_at, ended_at, error_message
        FROM workflow_executions
        WHERE id = ?
    ]]

    local results, error = M.db_handle:query(sql, execution_id)
    if error ~= "" then
        print("M.get_execution: Error getting execution: " .. error)
        return nil
    end

    if results and #results > 0 then
        return results[1]
    end

    return nil
end

-- Get executions for a workflow
function M.get_workflow_executions(workflow_id, limit)
    if not M.db_handle then
        print("M.get_workflow_executions: Database not initialized")
        return {}
    end

    local sql = [[
        SELECT id, workflow_id, status, thread_id, started_at, ended_at, error_message
        FROM workflow_executions
        WHERE workflow_id = ?
        ORDER BY started_at DESC
    ]]

    if limit then
        sql = sql .. " LIMIT " .. tonumber(limit)
    end

    local results, error = M.db_handle:query(sql, workflow_id)
    if error ~= "" then
        print("M.get_workflow_executions: Error getting executions: " .. error)
        return {}
    end

    return results or {}
end

return M
