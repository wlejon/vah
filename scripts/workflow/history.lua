-- Workflow Execution History
-- Handles viewing execution history and details

local state = require("workflow.state")
local workflow_db = require("workflow.db")
local views = require("workflow.views")

local history = {}

-- ============================================
-- History Functions
-- ============================================

-- Show execution history
local function handle_show_execution_history(payload)
    if not state.active_workflow.id then
        print("ERROR: No active workflow")
        event.trigger_global("notification_error", {
            title = "History Error",
            message = "No active workflow to show history for"
        })
        return
    end

    -- Load execution history
    local executions = workflow_db.get_workflow_executions(state.active_workflow.id, 50)

    -- Add formatted data for each execution
    for _, exec in ipairs(executions) do
        -- Format duration
        if exec.started_at and exec.ended_at then
            exec.duration = "0.0s"  -- Placeholder - proper parsing needed
        else
            exec.duration = "N/A"
        end

        -- Add node counts (query from execution_nodes table)
        local count_sql = [[
            SELECT
                COUNT(*) as total,
                SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed
            FROM execution_nodes
            WHERE execution_id = ?
        ]]
        local counts, err = workflow_db.db_handle:query(count_sql, exec.id)
        if counts and #counts > 0 then
            exec.total_nodes = counts[1].total or 0
            exec.completed_nodes = counts[1].completed or 0
        else
            exec.total_nodes = 0
            exec.completed_nodes = 0
        end

        -- Store execution_id for click handlers
        exec.execution_id = exec.id
    end

    -- Bind to UI
    datamodel.bind_table("execution_history", executions)

    -- Switch to history view
    views.switch_to_view("execution_history")

    print("Loaded " .. #executions .. " execution records")
end

-- View execution details
local function handle_view_execution(payload)
    if not payload.execution_id then
        print("ERROR: No execution_id in view_execution payload")
        return
    end

    local execution_id = payload.execution_id

    -- Load execution from database
    local exec_sql = "SELECT * FROM workflow_executions WHERE id = ?"
    local exec_results, err = workflow_db.db_handle:query(exec_sql, execution_id)
    if not exec_results or #exec_results == 0 then
        print("ERROR: Execution not found: " .. execution_id)
        return
    end

    local execution = exec_results[1]

    -- Format duration
    execution.duration = execution.started_at and execution.ended_at and "0.0s" or "N/A"
    execution.execution_id = execution.id

    -- Get workflow name
    local wf_sql = "SELECT name FROM workflows WHERE id = ?"
    local wf_results = workflow_db.db_handle:query(wf_sql, execution.workflow_id)
    execution.workflow_name = (wf_results and #wf_results > 0) and wf_results[1].name or "Unknown"

    -- Query execution nodes
    local nodes_sql = [[
        SELECT node_id, status, inputs, outputs, error_message, started_at, completed_at
        FROM execution_nodes
        WHERE execution_id = ?
        ORDER BY execution_order
    ]]
    local node_results, node_error = workflow_db.db_handle:query(nodes_sql, execution_id)

    if node_error ~= "" then
        print("ERROR: Failed to query execution nodes: " .. node_error)
        return
    end

    -- Add node names to results
    local nodes = {}
    for _, node in ipairs(node_results or {}) do
        -- Get node type name (would need to join with workflow_nodes table)
        node.node_name = "Node " .. node.node_id
        table.insert(nodes, node)
    end

    -- Bind detailed data to UI
    datamodel.bind_table("execution_details", {{
        execution_id = execution.id,
        status = execution.status,
        workflow_name = execution.workflow_name,
        started_at = execution.started_at or "N/A",
        duration = execution.duration,
        error_message = execution.error_message or "",
        nodes = nodes
    }})

    -- Log error for debugging
    if execution.error_message and execution.error_message ~= "" then
        print("Execution error: " .. execution.error_message)
    end

    print("Loaded execution details for execution " .. execution_id)
end

-- ============================================
-- Event Registration
-- ============================================

function history.register_events()
    -- Register history event handlers
    event.register("show_execution_history", handle_show_execution_history)
    event.register_global("show_execution_history", handle_show_execution_history)  -- Also register as global for menu
    event.register("view_execution", handle_view_execution)
end

return history
