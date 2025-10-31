-- Execution API Implementation
-- Provides execution context functions for workflow nodes
-- This replaces the hardcoded SQL from WorkflowExecutionBindings.cpp

local M = {}

-- Create the execution API table for a specific execution_id
function M.create_execution_api(execution_id)
    local api = {}

    -- Store the execution ID
    local exec_id = execution_id

    -- Get execution ID
    function api.id()
        return exec_id
    end

    -- Get workflow ID for this execution
    function api.workflow_id()
        local db_handle, err = db.open("data/workflow.db")
        if err ~= "" then
            return nil
        end

        local row, query_err = db_handle:query_single(
            "SELECT workflow_id FROM workflow_executions WHERE id = ?",
            exec_id
        )
        db_handle:close()

        if query_err ~= "" or not row then
            return nil
        end

        return row.workflow_id
    end

    -- Set a value in execution state
    -- Stores value as JSON in the exec_X_state table
    function api.set(key, value)
        if not key or key == "" then
            return nil, "Key cannot be empty"
        end

        -- Serialize value to JSON
        local json_value = json.encode(value)

        -- Open database
        local db_handle, err = db.open("data/workflow.db")
        if err ~= "" then
            return nil, "Failed to open database: " .. err
        end

        -- Build table name
        local table_name = "exec_" .. exec_id .. "_state"

        -- Execute INSERT OR REPLACE
        local sql = string.format(
            "INSERT OR REPLACE INTO %s (key, value, updated_at) VALUES (?, ?, CURRENT_TIMESTAMP)",
            table_name
        )

        local success, exec_err = db_handle:execute(sql, key, json_value)
        db_handle:close()

        if not success then
            return nil, "Failed to set value: " .. exec_err
        end

        return true
    end

    -- Get a value from execution state
    -- Returns deserialized value from JSON
    function api.get(key)
        if not key or key == "" then
            return nil
        end

        -- Open database
        local db_handle, err = db.open("data/workflow.db")
        if err ~= "" then
            return nil
        end

        -- Build table name
        local table_name = "exec_" .. exec_id .. "_state"

        -- Query for the value
        local sql = string.format("SELECT value FROM %s WHERE key = ?", table_name)
        local row, query_err = db_handle:query_single(sql, key)
        db_handle:close()

        if query_err ~= "" or not row or not row.value then
            return nil
        end

        -- Deserialize from JSON
        local value = json.decode(row.value)
        return value
    end

    -- Log a message to the execution log
    function api.log(level, message, node_id)
        if not level or not message then
            return nil, "Level and message are required"
        end

        -- Open database
        local db_handle, err = db.open("data/workflow.db")
        if err ~= "" then
            return nil, "Failed to open database: " .. err
        end

        -- Build table name
        local table_name = "exec_" .. exec_id .. "_log"

        -- Insert log entry
        local sql = string.format(
            "INSERT INTO %s (timestamp, level, message, node_id) VALUES (CURRENT_TIMESTAMP, ?, ?, ?)",
            table_name
        )

        local success, exec_err = db_handle:execute(sql, level, message, node_id or nil)
        db_handle:close()

        if not success then
            return nil, "Failed to log message: " .. exec_err
        end

        return true
    end

    return api
end

return M
