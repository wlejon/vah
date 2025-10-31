-- Approvals Module
-- Handles workflow approval system with hash-based validation

local helpers = require("scripts.workflow.db.helpers")

local M = {}

-- Reference to database handle (set by init.lua)
M.db_handle = nil

-- Check if workflow has valid approval
-- Returns true if approved and hash matches, false otherwise
function M.check_workflow_approval(workflow_id, requires_hash)
    if not M.db_handle then
        print("approvals.check_workflow_approval: Database not initialized")
        return false
    end

    local sql = [[
        SELECT approved, requires_hash
        FROM workflow_approvals
        WHERE workflow_id = ?
    ]]

    local results, error = M.db_handle:query(sql, workflow_id)
    if error ~= "" then
        print("approvals.check_workflow_approval: Error checking approval: " .. error)
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
-- Returns (success, error)
function M.save_workflow_approval(workflow_id, requires_hash, approved)
    if not M.db_handle then
        return false, "Database not initialized"
    end

    local sql = [[
        INSERT OR REPLACE INTO workflow_approvals (workflow_id, approved, requires_hash, approved_at)
        VALUES (?, ?, ?, CURRENT_TIMESTAMP)
    ]]

    local success, error = M.db_handle:execute(sql, workflow_id, approved and 1 or 0, requires_hash)
    if not success then
        return false, helpers.error_msg("save_workflow_approval", "Error saving approval: " .. error)
    end

    return true, nil
end

-- Get workflow approval status
-- Returns approval record or nil
function M.get_workflow_approval(workflow_id)
    if not M.db_handle then
        print("approvals.get_workflow_approval: Database not initialized")
        return nil
    end

    local sql = [[
        SELECT workflow_id, approved, requires_hash, approved_at
        FROM workflow_approvals
        WHERE workflow_id = ?
    ]]

    local results, error = M.db_handle:query(sql, workflow_id)
    if error ~= "" then
        print("approvals.get_workflow_approval: Error getting approval: " .. error)
        return nil
    end

    if results and #results > 0 then
        return results[1]
    end

    return nil
end

-- Revoke workflow approval
-- Returns (success, error)
function M.revoke_workflow_approval(workflow_id)
    if not M.db_handle then
        return false, "Database not initialized"
    end

    local sql = "DELETE FROM workflow_approvals WHERE workflow_id = ?"
    local success, error = M.db_handle:execute(sql, workflow_id)

    if not success then
        return false, helpers.error_msg("revoke_workflow_approval", "Error revoking approval: " .. error)
    end

    return true, nil
end

return M
