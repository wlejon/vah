-- Workflow Executor
-- Handles loading and executing workflows in isolated threads

local M = {}

-- Helper: Topological sort using Kahn's algorithm
local function topological_sort(nodes, connections)
    if #nodes == 0 then
        return {}
    end

    -- Build adjacency list and in-degree map
    local adj = {}
    local in_degree = {}
    local node_map = {}

    -- Initialize
    for _, node in ipairs(nodes) do
        node_map[node.id] = node
        adj[node.id] = {}
        in_degree[node.id] = 0
    end

    -- Build graph from connections (only between regular nodes)
    for _, conn in ipairs(connections) do
        if node_map[conn.from_node] and node_map[conn.to_node] then
            table.insert(adj[conn.from_node], conn.to_node)
            in_degree[conn.to_node] = in_degree[conn.to_node] + 1
        end
    end

    -- Kahn's algorithm
    local result = {}
    local queue = {}

    -- Find nodes with in-degree 0
    for node_id, degree in pairs(in_degree) do
        if degree == 0 then
            table.insert(queue, node_id)
        end
    end

    while #queue > 0 do
        local node_id = table.remove(queue)
        table.insert(result, node_id)

        -- Reduce in-degree for neighbors
        for _, neighbor in ipairs(adj[node_id]) do
            in_degree[neighbor] = in_degree[neighbor] - 1
            if in_degree[neighbor] == 0 then
                table.insert(queue, neighbor)
            end
        end
    end

    -- Check for cycles
    if #result ~= #nodes then
        execution.log("ERROR", "Workflow has a cycle - cannot execute")
        return nil
    end

    return result
end

-- Helper: Gather inputs for a node from connected node outputs
local function gather_node_inputs(node_id, connections, node_outputs)
    local inputs = {}

    for _, conn in ipairs(connections) do
        if conn.to_node == node_id then
            local outputs = node_outputs[conn.from_node]
            if outputs then
                local port_name = "input_" .. conn.to_port
                local output_key = "output_" .. conn.from_port
                if outputs[output_key] then
                    inputs[port_name] = outputs[output_key]
                end
            end
        end
    end

    return inputs
end

-- Helper: Execute a single node's script in sandboxed environment
local function execute_node(node, inputs, execution_id, workflow_id, node_outputs)
    if not node.config or not node.config.script then
        execution.log("ERROR", "Node " .. node.id .. " has no script", node.id)
        return false, "Node has no script"
    end

    -- Create sandboxed environment with access to globals
    local env = {}
    setmetatable(env, { __index = _G })

    -- Set inputs, config, context
    env.inputs = inputs
    env.config = node.config
    env.context = {
        execution_id = execution_id,
        workflow_id = workflow_id,
        node_id = node.id
    }

    -- Copy execution API into environment
    env.execution = execution

    -- Load the script
    local func, load_err = load(node.config.script, "node_" .. node.id, "t", env)
    if not func then
        execution.log("ERROR", "Node " .. node.id .. " script load error: " .. tostring(load_err), node.id)
        return false, "Script load error: " .. tostring(load_err)
    end

    -- Execute the script
    local success, result = pcall(func)
    if not success then
        execution.log("ERROR", "Node " .. node.id .. " execution error: " .. tostring(result), node.id)
        return false, "Script execution error: " .. tostring(result)
    end

    -- Store outputs
    local outputs = result or {}
    node_outputs[node.id] = outputs

    return true, nil, outputs
end

-- Helper: Execute callback nodes of a specific type
local function execute_callback_nodes(callback_nodes, callback_type, context, execution_id)
    for _, node in ipairs(callback_nodes) do
        if node.config and node.config.callback_type == callback_type then
            execution.log("INFO", "Executing callback node " .. node.id .. " (" .. callback_type .. ")", node.id)

            if not node.config.script then
                execution.log("WARN", "Callback node " .. node.id .. " has no script", node.id)
            else
                -- Create sandboxed environment
                local env = {}
                setmetatable(env, { __index = _G })

                -- Set context as both inputs and context for callbacks
                env.inputs = context
                env.config = node.config
                env.context = context
                env.execution = execution

                -- Load and execute
                local func, load_err = load(node.config.script, "callback_" .. node.id, "t", env)
                if func then
                    local success, err = pcall(func)
                    if not success then
                        execution.log("ERROR", "Callback node " .. node.id .. " execution error: " .. tostring(err), node.id)
                    end
                else
                    execution.log("ERROR", "Callback node " .. node.id .. " load error: " .. tostring(load_err), node.id)
                end
            end
        end
    end
end

-- Helper: Check for control commands (pause/stop)
local function check_control_command(execution_id)
    local db_handle, err = db.open("data/workflow.db")
    if err ~= "" then
        return true -- Continue if we can't check
    end

    local results = db_handle:query("SELECT command FROM execution_control WHERE execution_id = ?", execution_id)
    db_handle:close()

    if #results > 0 then
        local command = results[1].command

        if command == "stop" then
            execution.log("INFO", "Stop command received for execution " .. execution_id)
            return false
        elseif command == "pause" then
            execution.log("INFO", "Pause command received for execution " .. execution_id)

            -- Wait until command changes
            while command == "pause" do
                thread.sleep(0.1)

                db_handle, err = db.open("data/workflow.db")
                if err ~= "" then break end

                results = db_handle:query("SELECT command FROM execution_control WHERE execution_id = ?", execution_id)
                db_handle:close()

                if #results > 0 then
                    command = results[1].command
                else
                    break
                end
            end

            if command == "stop" then
                return false
            end
        end
    end

    return true
end

-- Helper: Update execution status in database
local function update_execution_status(execution_id, status, error_message)
    local db_handle, err = db.open("data/workflow.db")
    if err ~= "" then
        execution.log("ERROR", "Failed to update execution status - cannot open database")
        return
    end

    local sql
    if error_message then
        sql = "UPDATE workflow_executions SET status = ?, error_message = ?, ended_at = CURRENT_TIMESTAMP WHERE id = ?"
        db_handle:execute(sql, status, error_message, execution_id)
    else
        sql = "UPDATE workflow_executions SET status = ?, ended_at = CURRENT_TIMESTAMP WHERE id = ?"
        db_handle:execute(sql, status, execution_id)
    end

    db_handle:close()
    execution.log("INFO", "Execution " .. execution_id .. " status updated to: " .. status)
end

-- Helper: Update node status in database
local function update_node_status(execution_id, node_id, status, outputs, error_message)
    local db_handle, err = db.open("data/workflow.db")
    if err ~= "" then
        execution.log("ERROR", "Failed to update node status - cannot open database", node_id)
        return
    end

    -- Check if node record exists
    local check_results = db_handle:query(
        "SELECT execution_order FROM execution_nodes WHERE execution_id = ? AND node_id = ?",
        execution_id, node_id
    )

    local outputs_json = json.encode(outputs or {})
    local inputs_json = "{}"

    if #check_results > 0 then
        -- Update
        local sql = [[
            UPDATE execution_nodes
            SET status = ?, outputs = ?, error_message = ?,
                completed_at = CASE WHEN ? IN ('completed', 'error', 'skipped')
                                   THEN CURRENT_TIMESTAMP ELSE completed_at END
            WHERE execution_id = ? AND node_id = ?
        ]]
        db_handle:execute(sql, status, outputs_json, error_message, status, execution_id, node_id)
    else
        -- Insert
        local sql = [[
            INSERT INTO execution_nodes
            (execution_id, node_id, status, inputs, outputs, error_message, execution_order, started_at)
            SELECT ?, ?, ?, ?, ?, ?, COALESCE(MAX(execution_order), 0) + 1, CURRENT_TIMESTAMP
            FROM execution_nodes WHERE execution_id = ?
        ]]
        db_handle:execute(sql, execution_id, node_id, status, inputs_json, outputs_json, error_message, execution_id)
    end

    db_handle:close()
end

-- Helper: Add trace entry
local function add_trace_entry(execution_id, node_id)
    local db_handle, err = db.open("data/workflow.db")
    if err ~= "" then return end

    local sql = [[
        INSERT INTO execution_trace (execution_id, sequence, node_id)
        SELECT ?, COALESCE(MAX(sequence), 0) + 1, ?
        FROM execution_trace WHERE execution_id = ?
    ]]
    db_handle:execute(sql, execution_id, node_id, execution_id)
    db_handle:close()
end

-- Main execution function
function M.execute_workflow(execution_id)
    execution.log("INFO", "Starting execution " .. execution_id)

    -- Open database
    local db_handle, err = db.open("data/workflow.db")
    if err ~= "" then
        execution.log("ERROR", "Failed to open database: " .. err)
        update_execution_status(execution_id, "error", "Failed to open database")
        return false
    end

    -- Get workflow_id from execution record
    local exec_results = db_handle:query([[
        SELECT workflow_id FROM workflow_executions WHERE id = ?
    ]], execution_id)

    if #exec_results == 0 then
        execution.log("ERROR", "Execution " .. execution_id .. " not found in database")
        db_handle:close()
        return false
    end

    local workflow_id = exec_results[1].workflow_id
    execution.log("INFO", "Executing workflow " .. workflow_id .. " (execution " .. execution_id .. ")")

    -- Load workflow nodes
    local nodes = {}
    local callback_nodes = {}

    local node_results = db_handle:query([[
        SELECT node_id, node_type_id, x, y, config
        FROM workflow_nodes
        WHERE workflow_id = ?
        ORDER BY node_id
    ]], workflow_id)

    for _, row in ipairs(node_results) do
        local node = {
            id = row.node_id,
            type_id = row.node_type_id,
            x = row.x,
            y = row.y,
            config = row.config and json.decode(row.config) or {}
        }

        -- Check if this is a callback node
        if node.config.callback_type then
            table.insert(callback_nodes, node)
        else
            table.insert(nodes, node)
        end
    end

    -- Load connections
    local connections = {}
    local conn_results = db_handle:query([[
        SELECT from_node, from_port, to_node, to_port
        FROM workflow_connections
        WHERE workflow_id = ?
    ]], workflow_id)

    for _, row in ipairs(conn_results) do
        table.insert(connections, {
            from_node = row.from_node,
            from_port = row.from_port,
            to_node = row.to_node,
            to_port = row.to_port
        })
    end

    db_handle:close()

    execution.log("INFO", "Loaded workflow " .. workflow_id .. ": " .. #nodes .. " nodes, " .. #connections .. " connections, " .. #callback_nodes .. " callbacks")

    -- Execute on_start callbacks
    execute_callback_nodes(callback_nodes, "on_start", {
        execution_id = execution_id,
        workflow_id = workflow_id
    }, execution_id)

    -- Get execution order
    local execution_order = topological_sort(nodes, connections)
    if not execution_order then
        update_execution_status(execution_id, "error", "Workflow has a cycle or cannot be sorted")
        return false
    end

    -- Map nodes by ID for quick lookup
    local node_map = {}
    for _, node in ipairs(nodes) do
        node_map[node.id] = node
    end

    -- Store node outputs
    local node_outputs = {}

    -- Execute nodes in order
    for _, node_id in ipairs(execution_order) do
        -- Check for control commands
        if not check_control_command(execution_id) then
            update_execution_status(execution_id, "stopped")
            return false
        end

        -- Execute on_node_start callbacks
        execute_callback_nodes(callback_nodes, "on_node_start", {
            execution_id = execution_id,
            workflow_id = workflow_id,
            node_id = node_id
        }, execution_id)

        -- Gather inputs
        local inputs = gather_node_inputs(node_id, connections, node_outputs)

        -- Execute the node
        update_node_status(execution_id, node_id, "running")

        local node = node_map[node_id]
        local success, error_msg, outputs = execute_node(node, inputs, execution_id, workflow_id, node_outputs)

        if not success then
            -- Execute on_error callbacks
            execute_callback_nodes(callback_nodes, "on_error", {
                execution_id = execution_id,
                workflow_id = workflow_id,
                error_node_id = node_id,
                error_message = error_msg
            }, execution_id)

            update_node_status(execution_id, node_id, "error", nil, error_msg)
            update_execution_status(execution_id, "error", error_msg)
            return false
        end

        -- Update node status
        update_node_status(execution_id, node_id, "completed", outputs)

        -- Add trace entry
        add_trace_entry(execution_id, node_id)

        -- Execute on_node_complete callbacks
        execute_callback_nodes(callback_nodes, "on_node_complete", {
            execution_id = execution_id,
            workflow_id = workflow_id,
            node_id = node_id,
            outputs = outputs
        }, execution_id)

        execution.log("INFO", "Node " .. node_id .. " executed successfully", node_id)

        -- Small delay for visualization
        thread.sleep(0.1)
    end

    -- Execute on_complete callbacks
    execute_callback_nodes(callback_nodes, "on_complete", {
        execution_id = execution_id,
        workflow_id = workflow_id
    }, execution_id)

    -- Update execution status
    update_execution_status(execution_id, "completed")

    execution.log("INFO", "Execution " .. execution_id .. " completed successfully")
    return true
end

return M
