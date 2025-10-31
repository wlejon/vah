-- Workflow Execution Control
-- Handles execution control and monitoring

local state = require("workflow.state")
local workflow_db = require("workflow.db")

local execution = {}

-- ============================================
-- Execution Helper Functions
-- ============================================

-- Simple hash function for requires list
local function compute_requires_hash(requires)
    if not requires or #requires == 0 then
        return "empty"
    end

    -- Sort and concatenate library IDs
    local sorted = {}
    for _, lib in ipairs(requires) do
        table.insert(sorted, lib)
    end
    table.sort(sorted)

    return table.concat(sorted, ",")
end

-- Load library information for approval dialog
local function load_library_info(library_ids)
    if not library_ids or #library_ids == 0 then
        return {}
    end

    local all_libs = workflow_db.get_library_definitions()
    local selected_libs = {}

    for _, lib_id in ipairs(library_ids) do
        for _, lib_def in ipairs(all_libs) do
            if lib_def.id == lib_id then
                table.insert(selected_libs, {
                    id = lib_def.id,
                    name = lib_def.name,
                    description = lib_def.description,
                    access_description = lib_def.access_description
                })
                break
            end
        end
    end

    return selected_libs
end

-- Poll execution state and bind to UI
function execution.poll_execution_state()
    if not state.active_execution_id then
        return
    end

    -- Query execution status
    local exec = workflow_db.get_execution(state.active_execution_id)
    if not exec then
        print("ERROR: Execution " .. state.active_execution_id .. " not found")
        state.active_execution_id = nil
        return
    end

    -- Query node states
    local node_states_sql = [[
        SELECT node_id, status, inputs, outputs, error_message
        FROM execution_nodes
        WHERE execution_id = ?
    ]]
    local node_results, node_error = workflow_db.db_handle:query(node_states_sql, state.active_execution_id)

    if node_error ~= "" then
        print("ERROR: Failed to query node states: " .. node_error)
        return
    end

    -- Build node states map
    local nodes_map = {}
    local completed_count = 0
    local total_count = 0

    if node_results then
        for _, node_state in ipairs(node_results) do
            nodes_map[node_state.node_id] = {
                status = node_state.status,
                inputs = node_state.inputs,
                outputs = node_state.outputs,
                error_message = node_state.error_message
            }

            total_count = total_count + 1
            if node_state.status == "completed" or node_state.status == "error" or node_state.status == "skipped" then
                completed_count = completed_count + 1
            end
        end
    end

    -- Calculate elapsed time
    local elapsed = 0
    if exec.started_at then
        local current_time = os.time()
        -- Parse timestamp (simplified - assumes ISO format)
        -- This is a rough approximation; proper timestamp parsing would be better
        elapsed = 0  -- Would need proper time parsing
    end

    -- Calculate progress percentage
    local progress_percent = total_count > 0 and math.floor((completed_count / total_count) * 100) or 0

    -- Bind execution state to UI
    datamodel.bind_table("execution_state", {{
        execution_id = state.active_execution_id,
        status = exec.status,
        workflow_id = exec.workflow_id,
        thread_id = exec.thread_id,
        total_nodes = total_count,
        completed_nodes = completed_count,
        progress_percent = progress_percent,
        elapsed_time = elapsed,
        elapsed_time_str = string.format("%.1fs", elapsed),
        error_message = exec.error_message,
        nodes = nodes_map
    }})

    -- Check if execution is complete
    if exec.status == "completed" or exec.status == "error" or exec.status == "stopped" then
        -- Clear active execution
        state.active_execution_id = nil

        -- Show notification
        if exec.status == "completed" then
            event.trigger_global("notification_success", {
                title = "Workflow Completed",
                message = "Workflow execution completed successfully"
            })
        elseif exec.status == "error" then
            event.trigger_global("notification_error", {
                title = "Workflow Failed",
                message = exec.error_message or "Workflow execution failed"
            })
        else
            event.trigger_global("notification_info", {
                title = "Workflow Stopped",
                message = "Workflow execution was stopped"
            })
        end

        -- Clear execution state binding
        datamodel.bind_table("execution_state", {})
    end
end

-- ============================================
-- Execution Control Event Handlers
-- ============================================

-- Execute workflow
function execution.handle_execute_workflow(payload)
    if not state.database_initialized or not state.active_workflow.id then
        print("ERROR: No active workflow")
        event.trigger_global("notification_error", {
            title = "Execution Failed",
            message = "No active workflow to execute"
        })
        return
    end

    -- Load workflow config to get requires list
    local config_json = workflow_db.load_workflow_config(state.active_workflow.id)
    local requires = {}

    if config_json and config_json ~= "" then
        local ok, config = pcall(json.decode, config_json)
        if ok and config then
            requires = config.requires or {}
        end
    end

    print("Workflow requires " .. #requires .. " libraries")

    -- Compute hash of requires list
    local requires_hash = compute_requires_hash(requires)

    -- Check approval (skip if no libraries required)
    local is_approved = (#requires == 0) or workflow_db.check_workflow_approval(state.active_workflow.id, requires_hash)

    if not is_approved then
        -- Load library info for approval dialog
        local libraries = load_library_info(requires)

        -- Show approval dialog (via event to avoid circular dependency)
        event.trigger_global("workflow_approval_needed", {
            workflow_id = state.active_workflow.id,
            workflow_name = state.active_workflow.name,
            requires = libraries,
            requires_hash = requires_hash
        })

        print("Workflow approval required")
        return
    end

    print("Workflow approved, starting execution...")

    -- Create execution record
    local execution_id = workflow_db.create_execution_record(state.active_workflow.id, nil)
    if not execution_id then
        print("ERROR: Failed to create execution record")
        event.trigger_global("notification_error", {
            title = "Execution Failed",
            message = "Failed to create execution record"
        })
        return
    end

    -- Initialize execution control
    workflow_db.set_execution_control(execution_id, "run")

    print("Starting workflow execution: " .. execution_id)

    -- Call thread.create_workflow_thread() to start execution
    local has_thread_func = thread and thread.create_workflow_thread
    if not has_thread_func then
        print("WARNING: thread.create_workflow_thread() not implemented yet")
        workflow_db.update_execution_status(execution_id, "error", "Thread creation not implemented")
        event.trigger_global("notification_error", {
            title = "Execution Failed",
            message = "Workflow thread creation not yet implemented in C++"
        })
        state.active_execution_id = nil
        return
    end

    -- Pass the requires array so the workflow has access to requested libraries
    local thread_id = thread.create_workflow_thread(state.active_workflow.id, execution_id, requires)

    if not thread_id then
        print("ERROR: Failed to create workflow thread")
        workflow_db.update_execution_status(execution_id, "error", "Failed to create workflow thread")
        event.trigger_global("notification_error", {
            title = "Execution Failed",
            message = "Failed to create workflow thread"
        })
        state.active_execution_id = nil
        return
    end

    -- Update execution record with thread ID
    local update_sql = "UPDATE workflow_executions SET thread_id = ? WHERE id = ?"
    workflow_db.db_handle:execute(update_sql, thread_id, execution_id)

    -- Store active execution ID
    state.active_execution_id = execution_id

    -- Show notification
    event.trigger_global("notification_info", {
        title = "Workflow Executing",
        message = "Started execution of workflow: " .. state.active_workflow.name
    })

    -- Start polling immediately
    state.time_since_poll = 0.1
    execution.poll_execution_state()
end

-- Pause execution
local function handle_pause_execution(payload)
    if not payload.execution_id then
        print("ERROR: No execution_id in pause_execution payload")
        return
    end

    workflow_db.set_execution_control(payload.execution_id, "pause")
    print("Pause command sent to execution: " .. payload.execution_id)
end

-- Stop execution
local function handle_stop_execution(payload)
    if not payload.execution_id then
        print("ERROR: No execution_id in stop_execution payload")
        return
    end

    workflow_db.set_execution_control(payload.execution_id, "stop")
    print("Stop command sent to execution: " .. payload.execution_id)
end

-- Step execution (future feature)
local function handle_step_execution(payload)
    if not payload.execution_id then
        print("ERROR: No execution_id in step_execution payload")
        return
    end

    workflow_db.set_execution_control(payload.execution_id, "step")
    print("Step command sent to execution: " .. payload.execution_id)
end

-- ============================================
-- Event Registration
-- ============================================

function execution.register_events()
    -- Register execution control event handlers
    event.register("execute_workflow", execution.handle_execute_workflow)
    event.register_global("execute_workflow", execution.handle_execute_workflow)  -- Also register as global for menu
    event.register("pause_execution", handle_pause_execution)
    event.register("stop_execution", handle_stop_execution)
    event.register("step_execution", handle_step_execution)
end

return execution
