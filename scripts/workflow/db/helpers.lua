-- Database Helper Functions
-- Provides transaction management and common query patterns

local M = {}

-- Execute a function within a transaction
-- Returns (success, result_or_error)
function M.with_transaction(db_handle, fn)
    local success, error = db_handle:execute("BEGIN TRANSACTION")
    if not success then
        return false, "Error beginning transaction: " .. error
    end

    local ok, result = pcall(fn)

    if ok and result ~= false then
        success, error = db_handle:execute("COMMIT")
        if not success then
            db_handle:execute("ROLLBACK")
            return false, "Error committing transaction: " .. error
        end
        return true, result
    else
        db_handle:execute("ROLLBACK")
        return false, result or "Transaction failed"
    end
end

-- Update workflow timestamp helper
function M.touch_workflow(db_handle, workflow_id)
    local success, error = db_handle:execute(
        "UPDATE workflows SET updated_at = CURRENT_TIMESTAMP WHERE id = ?",
        workflow_id
    )
    if not success then
        print("helpers.touch_workflow: Error updating workflow timestamp: " .. error)
    end
    return success
end

-- Get next sequence number for a table
function M.get_next_sequence(db_handle, table_name, sequence_col, filter_col, filter_value)
    local sql = string.format(
        "SELECT COALESCE(MAX(%s), 0) + 1 as next_seq FROM %s WHERE %s = ?",
        sequence_col, table_name, filter_col
    )

    local results, error = db_handle:query(sql, filter_value)
    if error ~= "" then
        return nil, error
    end

    if results and #results > 0 then
        return results[1].next_seq, ""
    end

    return 1, ""
end

-- Check if record exists
function M.record_exists(db_handle, table_name, where_clause, ...)
    local sql = string.format("SELECT 1 FROM %s WHERE %s LIMIT 1", table_name, where_clause)
    local results, error = db_handle:query(sql, ...)

    if error ~= "" then
        return false, error
    end

    return results and #results > 0, ""
end

-- Standardized error message formatting
function M.error_msg(context, message)
    return string.format("%s: %s", context, message)
end

return M
