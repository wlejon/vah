-- Executions Module
-- Handles workflow execution tracking, state, and logging

local helpers = require("scripts.workflow.db.helpers")

local M = {}

-- Reference to database handle (set by init.lua)
M.db_handle = nil

-- Create a new execution record
-- Returns (execution_id, error) or (nil, error)
function M.create_execution_record(workflow_id, thread_id)
    if not M.db_handle then
        return nil, "Database not initialized"
    end

    local sql = [[
        INSERT INTO workflow_executions (workflow_id, status, thread_id)
        VALUES (?, 'running', ?)
    ]]

    local success, error = M.db_handle:execute(sql, workflow_id, thread_id)
    if not success then
        return nil, helpers.error_msg("create_execution_record", "Error creating execution record: " .. error)
    end

    return M.db_handle:last_insert_rowid(), nil
end

-- Update execution status
-- Returns (success, error)
function M.update_execution_status(execution_id, status, error_message)
    if not M.db_handle then
        return false, "Database not initialized"
    end

    local sql
    local success, exec_error

    if error_message then
        sql = [[
            UPDATE workflow_executions
            SET status = ?, error_message = ?, ended_at = CURRENT_TIMESTAMP
            WHERE id = ?
        ]]
        success, exec_error = M.db_handle:execute(sql, status, error_message, execution_id)
    else
        sql = [[
            UPDATE workflow_executions
            SET status = ?, ended_at = CURRENT_TIMESTAMP
            WHERE id = ?
        ]]
        success, exec_error = M.db_handle:execute(sql, status, execution_id)
    end

    if not success then
        return false, helpers.error_msg("update_execution_status", "Error updating execution status: " .. exec_error)
    end

    return true, nil
end

-- Update or insert node execution status
-- Returns (success, error)
function M.update_node_execution(execution_id, node_id, status, inputs, outputs, error_message)
    if not M.db_handle then
        return false, "Database not initialized"
    end

    -- Check if node execution already exists
    local check_sql = [[
        SELECT execution_order FROM execution_nodes
        WHERE execution_id = ? AND node_id = ?
    ]]

    local results, query_error = M.db_handle:query(check_sql, execution_id, node_id)
    if query_error ~= "" then
        return false, helpers.error_msg("update_node_execution", "Error checking node execution: " .. query_error)
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
        -- Insert new record - get next execution order
        local execution_order, order_err = helpers.get_next_sequence(
            M.db_handle,
            "execution_nodes",
            "execution_order",
            "execution_id",
            execution_id
        )

        if order_err ~= "" then
            return false, helpers.error_msg("update_node_execution", "Error getting execution order: " .. order_err)
        end

        sql = [[
            INSERT INTO execution_nodes (execution_id, node_id, status, inputs, outputs, error_message, execution_order, started_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        ]]
        success, exec_error = M.db_handle:execute(sql, execution_id, node_id, status, inputs, outputs, error_message, execution_order)
    end

    if not success then
        return false, helpers.error_msg("update_node_execution", "Error updating node execution: " .. exec_error)
    end

    return true, nil
end

-- Add entry to execution trace
-- Returns (success, error)
function M.add_execution_trace(execution_id, node_id)
    if not M.db_handle then
        return false, "Database not initialized"
    end

    -- Get next sequence number
    local sequence, err = helpers.get_next_sequence(
        M.db_handle,
        "execution_trace",
        "sequence",
        "execution_id",
        execution_id
    )

    if err ~= "" then
        return false, helpers.error_msg("add_execution_trace", "Error getting sequence: " .. err)
    end

    local sql = [[
        INSERT INTO execution_trace (execution_id, sequence, node_id)
        VALUES (?, ?, ?)
    ]]

    local success, exec_error = M.db_handle:execute(sql, execution_id, sequence, node_id)
    if not success then
        return false, helpers.error_msg("add_execution_trace", "Error adding trace entry: " .. exec_error)
    end

    return true, nil
end

-- Set execution state value (using fixed schema table)
-- Returns (success, error)
function M.set_execution_state(execution_id, key, value)
    if not M.db_handle then
        return false, "Database not initialized"
    end

    local sql = [[
        INSERT OR REPLACE INTO execution_state (execution_id, key, value, updated_at)
        VALUES (?, ?, ?, CURRENT_TIMESTAMP)
    ]]

    local success, error = M.db_handle:execute(sql, execution_id, key, value)
    if not success then
        return false, helpers.error_msg("set_execution_state", "Error setting state: " .. error)
    end

    return true, nil
end

-- Get execution state value (using fixed schema table)
-- Returns value or nil
function M.get_execution_state(execution_id, key)
    if not M.db_handle then
        print("executions.get_execution_state: Database not initialized")
        return nil
    end

    local sql = [[
        SELECT value FROM execution_state WHERE execution_id = ? AND key = ?
    ]]

    local results, error = M.db_handle:query(sql, execution_id, key)
    if error ~= "" then
        print("executions.get_execution_state: Error getting state: " .. error)
        return nil
    end

    if results and #results > 0 then
        return results[1].value
    end

    return nil
end

-- Add execution log entry (using fixed schema table)
-- Returns (success, error)
function M.add_execution_log(execution_id, level, message, node_id)
    if not M.db_handle then
        return false, "Database not initialized"
    end

    local sql = [[
        INSERT INTO execution_logs (execution_id, level, message, node_id)
        VALUES (?, ?, ?, ?)
    ]]

    local success, error = M.db_handle:execute(sql, execution_id, level, message, node_id)
    if not success then
        return false, helpers.error_msg("add_execution_log", "Error adding log entry: " .. error)
    end

    return true, nil
end

-- Get execution logs (using fixed schema table)
-- Returns array of log entries
function M.get_execution_logs(execution_id, level_filter)
    if not M.db_handle then
        print("executions.get_execution_logs: Database not initialized")
        return {}
    end

    local sql
    local results, error

    if level_filter then
        sql = [[
            SELECT timestamp, level, node_id, message
            FROM execution_logs
            WHERE execution_id = ? AND level = ?
            ORDER BY id
        ]]
        results, error = M.db_handle:query(sql, execution_id, level_filter)
    else
        sql = [[
            SELECT timestamp, level, node_id, message
            FROM execution_logs
            WHERE execution_id = ?
            ORDER BY id
        ]]
        results, error = M.db_handle:query(sql, execution_id)
    end

    if error ~= "" then
        print("executions.get_execution_logs: Error getting logs: " .. error)
        return {}
    end

    return results or {}
end

-- Set execution control command
-- Returns (success, error)
function M.set_execution_control(execution_id, command)
    if not M.db_handle then
        return false, "Database not initialized"
    end

    local sql = [[
        INSERT OR REPLACE INTO execution_control (execution_id, command, updated_at)
        VALUES (?, ?, CURRENT_TIMESTAMP)
    ]]

    local success, error = M.db_handle:execute(sql, execution_id, command)
    if not success then
        return false, helpers.error_msg("set_execution_control", "Error setting control command: " .. error)
    end

    return true, nil
end

-- Get execution control command
-- Returns command string or nil
function M.get_execution_control(execution_id)
    if not M.db_handle then
        print("executions.get_execution_control: Database not initialized")
        return nil
    end

    local sql = [[
        SELECT command FROM execution_control WHERE execution_id = ?
    ]]

    local results, error = M.db_handle:query(sql, execution_id)
    if error ~= "" then
        print("executions.get_execution_control: Error getting control command: " .. error)
        return nil
    end

    if results and #results > 0 then
        return results[1].command
    end

    return nil
end

-- Get execution by ID
-- Returns execution record or nil
function M.get_execution(execution_id)
    if not M.db_handle then
        print("executions.get_execution: Database not initialized")
        return nil
    end

    local sql = [[
        SELECT id, workflow_id, status, thread_id, started_at, ended_at, error_message
        FROM workflow_executions
        WHERE id = ?
    ]]

    local results, error = M.db_handle:query(sql, execution_id)
    if error ~= "" then
        print("executions.get_execution: Error getting execution: " .. error)
        return nil
    end

    if results and #results > 0 then
        return results[1]
    end

    return nil
end

-- Get executions for a workflow
-- Returns array of execution records
function M.get_workflow_executions(workflow_id, limit)
    if not M.db_handle then
        print("executions.get_workflow_executions: Database not initialized")
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
        print("executions.get_workflow_executions: Error getting executions: " .. error)
        return {}
    end

    return results or {}
end

-- Clean up old execution data (for completed/failed executions older than specified time)
-- Returns (success, error)
function M.cleanup_old_executions(days_to_keep)
    if not M.db_handle then
        return false, "Database not initialized"
    end

    days_to_keep = days_to_keep or 30  -- Default to 30 days

    return helpers.with_transaction(M.db_handle, function()
        -- Get IDs of executions to clean up
        local sql = [[
            SELECT id FROM workflow_executions
            WHERE status IN ('completed', 'error', 'cancelled')
            AND ended_at < datetime('now', '-' || ? || ' days')
            AND id NOT IN (SELECT execution_id FROM execution_cleanup WHERE keep_indefinitely = 1)
        ]]

        local results, error = M.db_handle:query(sql, days_to_keep)
        if error ~= "" then
            print("executions.cleanup_old_executions: Error finding old executions: " .. error)
            return false
        end

        if not results or #results == 0 then
            return true  -- Nothing to clean up
        end

        -- Delete old executions (CASCADE will handle related records)
        local delete_sql = [[
            DELETE FROM workflow_executions
            WHERE status IN ('completed', 'error', 'cancelled')
            AND ended_at < datetime('now', '-' || ? || ' days')
            AND id NOT IN (SELECT execution_id FROM execution_cleanup WHERE keep_indefinitely = 1)
        ]]

        local success, del_error = M.db_handle:execute(delete_sql, days_to_keep)
        if not success then
            print("executions.cleanup_old_executions: Error deleting old executions: " .. del_error)
            return false
        end

        print(string.format("Cleaned up %d old execution(s)", #results))
        return true
    end)
end

-- Mark execution to keep indefinitely
-- Returns (success, error)
function M.mark_execution_keep(execution_id, keep)
    if not M.db_handle then
        return false, "Database not initialized"
    end

    local sql = [[
        INSERT OR REPLACE INTO execution_cleanup (execution_id, keep_indefinitely)
        VALUES (?, ?)
    ]]

    local success, error = M.db_handle:execute(sql, execution_id, keep and 1 or 0)
    if not success then
        return false, helpers.error_msg("mark_execution_keep", "Error marking execution: " .. error)
    end

    return true, nil
end

return M
