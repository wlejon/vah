-- Workflow Database Manager
-- Refactored modular version with improved error handling and fixed schema

local node_types = require("scripts.workflow.db.node_types")
local workflows = require("scripts.workflow.db.workflows")
local executions = require("scripts.workflow.db.executions")
local approvals = require("scripts.workflow.db.approvals")
local library_registry = require("scripts.workflow.db.library_registry")

local M = {}

-- Database handle (exposed for direct queries if needed)
M.db_handle = nil

-- Initialize database and create tables
function M.init()
    -- Open/create database
    local db, error = db.open("data/workflow.db")
    if error ~= "" then
        print("db.init: Error opening workflow database: " .. error)
        return false
    end

    M.db_handle = db
    print("Workflow database opened successfully")

    -- Set db_handle in all modules
    node_types.db_handle = db
    workflows.db_handle = db
    executions.db_handle = db
    approvals.db_handle = db
    library_registry.db_handle = db

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

    -- Add new columns to workflows table (if they don't exist)
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

    -- Create execution_state table (replaces dynamic exec_{id}_state tables)
    success, exec_error = M.db_handle:execute([[
        CREATE TABLE IF NOT EXISTS execution_state (
            execution_id INTEGER NOT NULL,
            key TEXT NOT NULL,
            value TEXT,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (execution_id, key),
            FOREIGN KEY (execution_id) REFERENCES workflow_executions(id) ON DELETE CASCADE
        )
    ]])

    if not success then
        print("Error creating execution_state table: " .. exec_error)
        return false
    end

    -- Create execution_logs table (replaces dynamic exec_{id}_log tables)
    success, exec_error = M.db_handle:execute([[
        CREATE TABLE IF NOT EXISTS execution_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            execution_id INTEGER NOT NULL,
            timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            level TEXT,
            node_id INTEGER,
            message TEXT,
            FOREIGN KEY (execution_id) REFERENCES workflow_executions(id) ON DELETE CASCADE
        )
    ]])

    if not success then
        print("Error creating execution_logs table: " .. exec_error)
        return false
    end

    -- Check if we need to populate library_registry
    local lib_count_result, lib_count_error = M.db_handle:query("SELECT COUNT(*) as count FROM library_registry")
    if lib_count_error == "" and lib_count_result and #lib_count_result > 0 and lib_count_result[1].count == 0 then
        print("Populating library registry with default C++ libraries...")
        library_registry.populate_library_registry()
    end

    -- Check if we need to add sample data
    local count_result, count_error = M.db_handle:query("SELECT COUNT(*) as count FROM node_types")
    if count_error ~= "" then
        print("Error checking node_types count: " .. count_error)
        return false
    end

    if count_result and #count_result > 0 and count_result[1].count == 0 then
        print("Adding default node types...")
        node_types.add_default_node_types()
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

    -- Indexes for new fixed schema tables
    M.db_handle:execute([[
        CREATE INDEX IF NOT EXISTS idx_execution_state_execution
        ON execution_state(execution_id)
    ]])
    M.db_handle:execute([[
        CREATE INDEX IF NOT EXISTS idx_execution_logs_execution
        ON execution_logs(execution_id)
    ]])
    M.db_handle:execute([[
        CREATE INDEX IF NOT EXISTS idx_execution_logs_level
        ON execution_logs(execution_id, level)
    ]])

    print("Database indexes created")

    return true
end

-- Close database
function M.close()
    if M.db_handle then
        M.db_handle:close()
        M.db_handle = nil

        -- Clear module handles
        node_types.db_handle = nil
        workflows.db_handle = nil
        executions.db_handle = nil
        approvals.db_handle = nil
        library_registry.db_handle = nil
    end
end

-- ============================================
-- Expose module functions (backward compatibility)
-- ============================================

-- Node Types
M.add_default_node_types = node_types.add_default_node_types
M.create_node_type = node_types.create_node_type
M.add_port = node_types.add_port
M.load_node_types = node_types.load_node_types
M.update_node_type = node_types.update_node_type
M.delete_node_type = node_types.delete_node_type
M.delete_ports = node_types.delete_ports

-- Workflows
M.create_workflow = workflows.create_workflow
M.get_workflows = workflows.get_workflows
M.update_workflow = workflows.update_workflow
M.delete_workflow = workflows.delete_workflow
M.save_workflow = workflows.save_workflow
M.add_node = workflows.add_node
M.update_node_position = workflows.update_node_position
M.delete_node = workflows.delete_node
M.add_connection = workflows.add_connection
M.load_workflow = workflows.load_workflow
M.save_workflow_config = workflows.save_workflow_config
M.load_workflow_config = workflows.load_workflow_config
M.save_node_config = workflows.save_node_config
M.load_node_config = workflows.load_node_config

-- Executions
M.create_execution_record = executions.create_execution_record
M.update_execution_status = executions.update_execution_status
M.update_node_execution = executions.update_node_execution
M.add_execution_trace = executions.add_execution_trace
M.set_execution_state = executions.set_execution_state
M.get_execution_state = executions.get_execution_state
M.add_execution_log = executions.add_execution_log
M.get_execution_logs = executions.get_execution_logs
M.set_execution_control = executions.set_execution_control
M.get_execution_control = executions.get_execution_control
M.get_execution = executions.get_execution
M.get_workflow_executions = executions.get_workflow_executions
M.cleanup_old_executions = executions.cleanup_old_executions
M.mark_execution_keep = executions.mark_execution_keep

-- Approvals
M.check_workflow_approval = approvals.check_workflow_approval
M.save_workflow_approval = approvals.save_workflow_approval
M.get_workflow_approval = approvals.get_workflow_approval
M.revoke_workflow_approval = approvals.revoke_workflow_approval

-- Library Registry
M.populate_library_registry = library_registry.populate_library_registry
M.get_library_definitions = library_registry.get_library_definitions
M.get_enabled_libraries = library_registry.get_enabled_libraries
M.set_library_enabled = library_registry.set_library_enabled
M.register_library = library_registry.register_library
M.unregister_library = library_registry.unregister_library

return M
