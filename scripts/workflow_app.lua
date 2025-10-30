-- Unified Workflow Application
-- Manages both the workflow editor and node type editor views

-- Load workflow database module
local workflow_db = require("workflow_db")

local database_initialized = false
local node_types_data = {}

-- Editor state for node type editor
local editor = {
    node_types = {},
    selected_index = nil,
    selected_node = nil
}

-- Active workflow state
local active_workflow = {
    id = nil,
    name = nil
}

local workflows_list = {}

-- Current view state
local active_view = "workflow"

-- Execution state
local active_execution_id = nil
local time_since_poll = 0

-- Node config editing state
local editing_node_config = nil

-- ============================================
-- View Switching Functions
-- ============================================

local function switch_to_view(view_name)
    active_view = view_name
    -- Bind as an array with a single element
    data.bind("active_view", {{view = view_name}})
end

local function handle_switch_to_list_view(payload)
    switch_to_view("list")
    -- Reload workflows when switching to list view
    load_workflows()
end

local function handle_switch_to_node_editor(payload)
    switch_to_view("node_editor")
end

local function handle_switch_to_workflow_view(payload)
    switch_to_view("workflow")
end

-- ============================================
-- Shared Functions
-- ============================================

-- Load node types from database
local function load_node_types()
    if not database_initialized then
        return
    end

    -- Load from database (already includes color components)
    node_types_data = workflow_db.load_node_types()

    -- Bind data to the UI for workflow editor
    data.bind("node_types", node_types_data)

    -- Also update the editor's copy for node type editor
    editor.node_types = {}
    for _, nt in ipairs(node_types_data) do
        local node_type_data = {
            id = nt.id,
            name = nt.name,
            color_r = nt.color_r,
            color_g = nt.color_g,
            color_b = nt.color_b,
            color_a = nt.color_a,
            inputs = {},
            outputs = {}
        }

        -- Copy inputs and outputs
        for _, input in ipairs(nt.inputs) do
            table.insert(node_type_data.inputs, input)
        end
        for _, output in ipairs(nt.outputs) do
            table.insert(node_type_data.outputs, output)
        end

        table.insert(editor.node_types, node_type_data)
    end
end

-- ============================================
-- Workflow Management Functions
-- ============================================

-- Load all workflows from database
local function load_workflows()
    if not database_initialized then
        return
    end

    workflows_list = workflow_db.get_workflows()

    -- Bind to UI
    data.bind("workflows", workflows_list)
end

-- Create a new workflow
local function create_new_workflow(payload)
    if not database_initialized then
        return
    end

    local workflow_id = workflow_db.create_workflow("New Workflow")
    if workflow_id then
        -- Reload workflows list
        load_workflows()

        -- Switch to the new workflow
        select_workflow({id = workflow_id})
    else
        print("ERROR: Failed to create new workflow")
    end
end

-- Select and load a workflow
function select_workflow(payload)
    if not database_initialized then
        return
    end

    local workflow_id = payload.id
    if not workflow_id then
        print("ERROR: No workflow_id in select_workflow payload")
        return
    end

    -- Load workflow from database
    local nodes, connections = workflow_db.load_workflow(workflow_id)
    if nodes == nil then
        print("ERROR: Failed to load workflow")
        return
    end

    -- Update active workflow
    active_workflow.id = workflow_id

    -- Find workflow name
    for _, wf in ipairs(workflows_list) do
        if wf.id == workflow_id then
            active_workflow.name = wf.name
            break
        end
    end

    -- Bind workflow data to make it available to workflow editor
    -- Include a timestamp to force client to reinitialize
    data.bind("workflow_nodes", nodes)
    data.bind("workflow_connections", connections)
    data.bind("active_workflow", {active_workflow})
    data.bind("workflow_reload_trigger", {timestamp = os.time()})

    -- Switch back to workflow view
    switch_to_view("workflow")
end


-- Rename the active workflow
local function rename_workflow(payload)
    if not database_initialized or not active_workflow.id then
        print("ERROR: No active workflow")
        return
    end

    local new_name = payload.name or "Unnamed Workflow"

    local success = workflow_db.update_workflow(active_workflow.id, new_name)
    if success then
        active_workflow.name = new_name
        data.bind("active_workflow", {active_workflow})
        load_workflows()
    else
        print("ERROR: Failed to rename workflow")
    end
end

-- Delete a workflow
local function delete_workflow(payload)
    if not database_initialized then
        return
    end

    local workflow_id = payload.id
    if not workflow_id then
        print("ERROR: No workflow_id in delete_workflow payload")
        return
    end

    local success = workflow_db.delete_workflow(workflow_id)
    if success then
        -- If this was the active workflow, clear it
        if active_workflow.id == workflow_id then
            active_workflow.id = nil
            active_workflow.name = nil
            data.bind("active_workflow", {})
            data.bind("workflow_nodes", {})
            data.bind("workflow_connections", {})
        end

        -- Reload workflows list
        load_workflows()
    else
        print("ERROR: Failed to delete workflow")
    end
end

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
local function poll_execution_state()
    if not active_execution_id then
        return
    end

    -- Query execution status
    local execution = workflow_db.get_execution(active_execution_id)
    if not execution then
        print("ERROR: Execution " .. active_execution_id .. " not found")
        active_execution_id = nil
        return
    end

    -- Query node states
    local node_states_sql = [[
        SELECT node_id, status, inputs, outputs, error_message
        FROM execution_nodes
        WHERE execution_id = ?
    ]]
    local node_results, node_error = workflow_db.db_handle:query(node_states_sql, active_execution_id)

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
    if execution.started_at then
        local current_time = os.time()
        -- Parse timestamp (simplified - assumes ISO format)
        -- This is a rough approximation; proper timestamp parsing would be better
        elapsed = 0  -- Would need proper time parsing
    end

    -- Bind execution state to UI
    data.bind("execution_state", {{
        execution_id = active_execution_id,
        status = execution.status,
        workflow_id = execution.workflow_id,
        thread_id = execution.thread_id,
        total_nodes = total_count,
        completed_nodes = completed_count,
        elapsed_time = elapsed,
        error_message = execution.error_message,
        nodes = nodes_map
    }})

    -- Check if execution is complete
    if execution.status == "completed" or execution.status == "error" or execution.status == "stopped" then
        -- Clear active execution
        active_execution_id = nil

        -- Show notification
        if execution.status == "completed" then
            event.trigger_global("notification_success", {
                title = "Workflow Completed",
                message = "Workflow execution completed successfully"
            })
        elseif execution.status == "error" then
            event.trigger_global("notification_error", {
                title = "Workflow Failed",
                message = execution.error_message or "Workflow execution failed"
            })
        else
            event.trigger_global("notification_info", {
                title = "Workflow Stopped",
                message = "Workflow execution was stopped"
            })
        end

        -- Clear execution state binding
        data.bind("execution_state", {})
    end
end

-- ============================================
-- Workflow Change Event Handlers
-- ============================================

-- Workflow change event handlers - update database and push to client
local function on_workflow_node_created(payload)
    if not database_initialized or not active_workflow.id then
        print("ERROR: No active workflow")
        return
    end

    -- Add node to database
    local success = workflow_db.add_node(
        active_workflow.id,
        payload.node_id,
        payload.type_index,
        payload.x,
        payload.y
    )

    if not success then
        print("ERROR: Failed to add node to database")
        return
    end

    -- Reload workflow from database and push to client
    local nodes, connections = workflow_db.load_workflow(active_workflow.id)
    if nodes then
        data.bind("workflow_nodes", nodes)
        data.bind("workflow_connections", connections)
    end
end

local function on_workflow_node_moved(payload)
    if not database_initialized or not active_workflow.id then
        print("ERROR: No active workflow")
        return
    end

    -- Update node position in database
    local success = workflow_db.update_node_position(
        active_workflow.id,
        payload.node_id,
        payload.x,
        payload.y
    )

    if not success then
        print("ERROR: Failed to update node position in database")
        return
    end

    -- Reload workflow from database and push to client
    local nodes, connections = workflow_db.load_workflow(active_workflow.id)
    if nodes then
        data.bind("workflow_nodes", nodes)
        data.bind("workflow_connections", connections)
    end
end

local function on_workflow_node_deleted(payload)
    if not database_initialized or not active_workflow.id then
        print("ERROR: No active workflow")
        return
    end

    -- Delete node from database (also deletes related connections)
    local success = workflow_db.delete_node(active_workflow.id, payload.node_id)

    if not success then
        print("ERROR: Failed to delete node from database")
        return
    end

    -- Reload workflow from database and push to client
    local nodes, connections = workflow_db.load_workflow(active_workflow.id)
    if nodes then
        data.bind("workflow_nodes", nodes)
        data.bind("workflow_connections", connections)
    end
end

local function on_workflow_connection_added(payload)
    if not database_initialized or not active_workflow.id then
        print("ERROR: No active workflow")
        return
    end

    -- Add connection to database
    local success = workflow_db.add_connection(
        active_workflow.id,
        payload.from_node,
        payload.from_port,
        payload.to_node,
        payload.to_port
    )

    if not success then
        print("ERROR: Failed to add connection to database")
        return
    end

    -- Reload workflow from database and push to client
    local nodes, connections = workflow_db.load_workflow(active_workflow.id)
    if nodes then
        data.bind("workflow_nodes", nodes)
        data.bind("workflow_connections", connections)
    end
end

-- ============================================
-- Execution Control Event Handlers
-- ============================================

-- Execute workflow
local function handle_execute_workflow(payload)
    if not database_initialized or not active_workflow.id then
        print("ERROR: No active workflow")
        event.trigger_global("notification_error", {
            title = "Execution Failed",
            message = "No active workflow to execute"
        })
        return
    end

    -- Load workflow config to get requires list
    local config_json = workflow_db.load_workflow_config(active_workflow.id)
    local config = {}
    local requires = {}

    if config_json then
        -- Parse JSON (assuming json library available or simple format)
        -- For now, we'll assume a simple format or use a simple parser
        -- In production, you'd use a proper JSON library
        config = {requires = {}}  -- Simplified
        requires = config.requires or {}
    end

    -- Compute hash of requires list
    local requires_hash = compute_requires_hash(requires)

    -- Check approval
    local is_approved = workflow_db.check_workflow_approval(active_workflow.id, requires_hash)

    if not is_approved then
        -- Load library info for approval dialog
        local libraries = load_library_info(requires)

        -- Trigger approval needed event
        event.trigger_global("workflow_approval_needed", {
            workflow_id = active_workflow.id,
            workflow_name = active_workflow.name,
            requires = libraries,
            requires_hash = requires_hash
        })

        print("Workflow approval required")
        return
    end

    -- Create execution record
    local execution_id = workflow_db.create_execution_record(active_workflow.id, nil)
    if not execution_id then
        print("ERROR: Failed to create execution record")
        event.trigger_global("notification_error", {
            title = "Execution Failed",
            message = "Failed to create execution record"
        })
        return
    end

    -- Create execution tables
    workflow_db.create_execution_tables(execution_id)

    -- Initialize execution control
    workflow_db.set_execution_control(execution_id, "run")

    print("Starting workflow execution: " .. execution_id)

    -- Call thread.create_workflow_thread() to start execution
    -- NOTE: This is a C++ function that needs to be implemented
    -- It should create a new thread and load the workflow executor script
    -- For now, this will fail gracefully if the function doesn't exist
    local has_thread_func = thread and thread.create_workflow_thread
    if not has_thread_func then
        print("WARNING: thread.create_workflow_thread() not implemented yet")
        workflow_db.update_execution_status(execution_id, "error", "Thread creation not implemented")
        event.trigger_global("notification_error", {
            title = "Execution Failed",
            message = "Workflow thread creation not yet implemented in C++"
        })
        active_execution_id = nil
        return
    end

    local thread_id = thread.create_workflow_thread(active_workflow.id, execution_id)

    if not thread_id then
        print("ERROR: Failed to create workflow thread")
        workflow_db.update_execution_status(execution_id, "error", "Failed to create workflow thread")
        event.trigger_global("notification_error", {
            title = "Execution Failed",
            message = "Failed to create workflow thread"
        })
        active_execution_id = nil
        return
    end

    -- Update execution record with thread ID
    local update_sql = "UPDATE workflow_executions SET thread_id = ? WHERE id = ?"
    workflow_db.db_handle:execute(update_sql, thread_id, execution_id)

    -- Store active execution ID
    active_execution_id = execution_id

    -- Show notification
    event.trigger_global("notification_info", {
        title = "Workflow Executing",
        message = "Started execution of workflow: " .. active_workflow.name
    })

    -- Start polling immediately
    time_since_poll = 0.1
    poll_execution_state()
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
-- Approval System Event Handlers
-- ============================================

-- Handle user's approval decision
local function handle_workflow_approval_response(payload)
    if not payload.workflow_id then
        print("ERROR: No workflow_id in approval response payload")
        return
    end

    local workflow_id = payload.workflow_id
    local approved = payload.approved or false
    local remember = payload.remember or false
    local requires_hash = payload.requires_hash or "empty"

    if not approved then
        -- User denied approval
        event.trigger_global("notification_error", {
            title = "Execution Denied",
            message = "Workflow execution was denied"
        })
        return
    end

    -- Save approval if "remember" is true
    if remember then
        workflow_db.save_workflow_approval(workflow_id, requires_hash, true)
        print("Workflow approval saved for workflow " .. workflow_id)
    end

    -- Proceed with execution
    handle_execute_workflow({workflow_id = workflow_id})
end

-- ============================================
-- Configuration Event Handlers
-- ============================================

-- Save workflow configuration
local function handle_save_workflow_config(payload)
    if not payload.workflow_id then
        print("ERROR: No workflow_id in save_workflow_config payload")
        return
    end

    if not payload.config then
        print("ERROR: No config in save_workflow_config payload")
        return
    end

    -- Convert config table to JSON string
    -- For now, we'll use a simple serialization
    -- In production, you'd use a proper JSON library
    local config_json = payload.config  -- Assuming already JSON string

    local success = workflow_db.save_workflow_config(payload.workflow_id, config_json)
    if success then
        print("Workflow configuration saved")
        event.trigger_global("notification_success", {
            title = "Configuration Saved",
            message = "Workflow configuration has been saved"
        })

        -- Update workflows list to reflect any changes
        load_workflows()
    else
        print("ERROR: Failed to save workflow configuration")
        event.trigger_global("notification_error", {
            title = "Save Failed",
            message = "Failed to save workflow configuration"
        })
    end
end

-- Edit node (open config dialog)
local function handle_edit_node(payload)
    if not database_initialized or not active_workflow.id then
        print("ERROR: No active workflow")
        return
    end

    if not payload.node_id then
        print("ERROR: No node_id in edit_node payload")
        return
    end

    -- Load current node config from database
    local config = workflow_db.load_node_config(active_workflow.id, payload.node_id)
    print("Loaded config from DB: " .. tostring(config))

    -- Parse config or create default
    local node_config_data = {
        node_id = payload.node_id,
        workflow_id = active_workflow.id,
        label = "",
        inputs = "",
        outputs = "",
        script = ""
    }

    if config and config ~= "" then
        print("Config exists, parsing...")
        node_config_data.script = config.script or ""

        if config.inputs then
            node_config_data.inputs = table.concat(config.inputs, ", ")
        end

        if config.outputs then
            node_config_data.outputs = table.concat(config.outputs, ", ")
        end

        node_config_data.label = config.label or ""
    else
        -- Get node type to provide defaults
        local node_type = nil
        for _, nt in ipairs(node_types_data) do
            if nt.id == payload.type_index then
                node_type = nt
                break
            end
        end

        if node_type then
            node_config_data.label = node_type.name
            if node_type.inputs then
                node_config_data.inputs = table.concat(node_type.inputs, ", ")
            end
            if node_type.outputs then
                node_config_data.outputs = table.concat(node_type.outputs, ", ")
            end
            -- Default script template
            node_config_data.script = "-- Node: " .. node_type.name .. "\n-- Inputs: " .. node_config_data.inputs .. "\n-- Outputs: " .. node_config_data.outputs .. "\n\nreturn {}\n"
        end
    end

    -- Store in editing state
    editing_node_config = node_config_data

    -- Switch to node config view
    switch_to_view("node_config")

    -- Set input field values via DOM manipulation
    ui.set_element_attribute("node_label_input", "value", node_config_data.label or "")
    ui.set_element_attribute("node_inputs_input", "value", node_config_data.inputs or "")
    ui.set_element_attribute("node_outputs_input", "value", node_config_data.outputs or "")

    -- Set texteditor content
    ui.set_texteditor_content("node_script_editor", editing_node_config.script or "")
    ui.set_texteditor_editable("node_script_editor", true)
end

-- Handle cancel button
local function handle_cancel_node_config(payload)
    editing_node_config = nil
    data.bind("node_config", {})  -- Clear to empty array
    switch_to_view("workflow")
end

-- Save node configuration
local function handle_save_node_config(payload)
    print("handle_save_node_config called")
    print("  workflow_id: " .. tostring(payload.workflow_id))
    print("  node_id: " .. tostring(payload.node_id))
    print("  label: " .. tostring(payload.label))
    print("  inputs: " .. tostring(payload.inputs))
    print("  outputs: " .. tostring(payload.outputs))

    if not payload.workflow_id or not payload.node_id then
        print("ERROR: Missing workflow_id or node_id in save_node_config payload")
        return
    end

    if not editing_node_config then
        print("ERROR: No node config being edited")
        return
    end

    -- Helper to split CSV into array
    local function split_csv(str)
        if not str or str == "" then
            return {}
        end
        local result = {}
        for item in string.gmatch(str, "([^,]+)") do
            local trimmed = item:match("^%s*(.-)%s*$")
            if trimmed ~= "" then
                table.insert(result, trimmed)
            end
        end
        return result
    end

    -- Build config object from form fields and editing state
    local config = {
        label = payload.label or "",
        script = editing_node_config.script or "",  -- Get from editing state
        inputs = split_csv(payload.inputs or ""),
        outputs = split_csv(payload.outputs or "")
    }

    local success = workflow_db.save_node_config(payload.workflow_id, payload.node_id, config)
    if success then
        print("Node configuration saved for node " .. payload.node_id)
        event.trigger_global("notification_success", {
            title = "Configuration Saved",
            message = "Node configuration has been saved"
        })

        -- Reload workflow from database and bind
        local nodes, connections = workflow_db.load_workflow(payload.workflow_id)
        if nodes then
            data.bind("workflow_nodes", nodes)
            data.bind("workflow_connections", connections)
        end

        -- Clear editing state
        editing_node_config = nil
        data.bind("node_config", {})  -- Clear to empty array

        -- Switch back to workflow view
        switch_to_view("workflow")
    else
        print("ERROR: Failed to save node configuration")
        event.trigger_global("notification_error", {
            title = "Save Failed",
            message = "Failed to save node configuration"
        })
    end
end

-- Handle save button from dialog
local function handle_save_node_config_from_dialog(payload)
    print("save_node_config_from_dialog called")
    print("Payload: label=" .. tostring(payload.label) .. ", inputs=" .. tostring(payload.inputs) .. ", outputs=" .. tostring(payload.outputs))

    if not editing_node_config then
        print("ERROR: No node config being edited")
        return
    end

    print("editing_node_config.script length: " .. tostring(#(editing_node_config.script or "")))
    print("editing_node_config.workflow_id: " .. tostring(editing_node_config.workflow_id))
    print("editing_node_config.node_id: " .. tostring(editing_node_config.node_id))

    -- Use form values from payload (queried from DOM in RML)
    print("About to call handle_save_node_config")
    handle_save_node_config({
        workflow_id = editing_node_config.workflow_id,
        node_id = editing_node_config.node_id,
        label = payload.label or editing_node_config.label,
        inputs = payload.inputs or editing_node_config.inputs,
        outputs = payload.outputs or editing_node_config.outputs
    })
    print("handle_save_node_config returned")
end

-- Handle script modifications from texteditor
local function handle_node_script_modified(payload)
    if editing_node_config and payload.content then
        editing_node_config.script = payload.content
    end
end

-- ============================================
-- History Event Handlers
-- ============================================

-- Show execution history
local function handle_show_execution_history(payload)
    if not active_workflow.id then
        print("ERROR: No active workflow")
        event.trigger_global("notification_error", {
            title = "History Error",
            message = "No active workflow to show history for"
        })
        return
    end

    -- Load execution history
    local executions = workflow_db.get_workflow_executions(active_workflow.id, 50)

    -- Calculate duration for each execution
    for _, exec in ipairs(executions) do
        if exec.started_at and exec.ended_at then
            -- Simple duration calculation (would need proper timestamp parsing)
            exec.duration = 0  -- Placeholder
        end
    end

    -- Bind to UI
    data.bind("execution_history", executions)

    print("Loaded " .. #executions .. " execution records")
end

-- View execution details
local function handle_view_execution(payload)
    if not payload.execution_id then
        print("ERROR: No execution_id in view_execution payload")
        return
    end

    local execution_id = payload.execution_id

    -- Load execution details
    local execution = workflow_db.get_execution(execution_id)
    if not execution then
        print("ERROR: Execution " .. execution_id .. " not found")
        event.trigger_global("notification_error", {
            title = "View Failed",
            message = "Execution not found"
        })
        return
    end

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

    -- Query execution logs
    local logs = workflow_db.get_execution_logs(execution_id)

    -- Bind detailed data to UI
    data.bind("execution_details", {{
        execution = execution,
        nodes = node_results or {},
        logs = logs
    }})

    print("Loaded execution details for execution " .. execution_id)
end

-- ============================================
-- Reload Functions (for view switching)
-- ============================================

local function reload_workflows_handler(payload)
    load_workflows()
end

-- ============================================
-- Node Type Editor Functions
-- ============================================

-- Select a node type for editing
local function select_node_type(payload)
    local node_id = payload.id
    if not node_id then
        print("ERROR: No id in select_node_type payload")
        return
    end

    -- Find the index of this node type
    for i, nt in ipairs(editor.node_types) do
        if nt.id == node_id then
            editor.selected_index = i
            editor.selected_node = editor.node_types[i]

            -- Update data model - wrap selected_node in an array for data binding
            data.bind("selected_node", {editor.selected_node})
            return
        end
    end

    print("ERROR: Could not find node type with id " .. node_id)
end

-- Add a new node type
local function add_new_node_type(payload)
    local node_id = workflow_db.create_node_type("New Node", 128, 128, 128, 255)

    if node_id then
        load_node_types()
    else
        print("ERROR: Failed to create new node type")
    end
end

-- Add input port to selected node
local function add_input_port(payload)
    if not editor.selected_node then
        return
    end

    table.insert(editor.selected_node.inputs, "New Input")
    data.bind("selected_node", {editor.selected_node})
end

-- Add output port to selected node
local function add_output_port(payload)
    if not editor.selected_node then
        return
    end

    table.insert(editor.selected_node.outputs, "New Output")
    data.bind("selected_node", {editor.selected_node})
end

-- Delete input port
local function delete_input_port(payload)
    if not editor.selected_node then
        return
    end

    local index = tonumber(payload.index)
    if index and index >= 1 and index <= #editor.selected_node.inputs then
        table.remove(editor.selected_node.inputs, index)
        data.bind("selected_node", {editor.selected_node})
    end
end

-- Delete output port
local function delete_output_port(payload)
    if not editor.selected_node then
        return
    end

    local index = tonumber(payload.index)
    if index and index >= 1 and index <= #editor.selected_node.outputs then
        table.remove(editor.selected_node.outputs, index)
        data.bind("selected_node", {editor.selected_node})
    end
end

-- Save changes to the selected node type
local function save_node_type(payload)
    if not payload.id then
        print("ERROR: No id in save_node_type payload")
        return
    end

    -- Payload already contains merged data:
    -- - Original row data from model (including id, inputs, outputs arrays)
    -- - Current input values from tracked inputs (override originals)
    -- So we can use payload directly!
    local node_id = payload.id
    local name = payload.name or "Unnamed"
    local color_r = tonumber(payload.color_r) or 128
    local color_g = tonumber(payload.color_g) or 128
    local color_b = tonumber(payload.color_b) or 128
    local color_a = tonumber(payload.color_a) or 255

    -- Clamp color values
    color_r = math.max(0, math.min(255, color_r))
    color_g = math.max(0, math.min(255, color_g))
    color_b = math.max(0, math.min(255, color_b))
    color_a = math.max(0, math.min(255, color_a))

    -- Extract port names from payload (tracked inputs override original values)
    local inputs = {}
    local outputs = {}

    -- The payload will have input_port_0, input_port_1, etc. for tracked inputs (0-based from RmlUi)
    -- and the original inputs/outputs arrays
    -- We need to check which ports exist and get their current values
    if editor.selected_node then
        -- Build inputs array from tracked values (RmlUi uses 0-based indexing)
        for i = 1, #editor.selected_node.inputs do
            local port_name = payload["input_port_" .. (i - 1)] or editor.selected_node.inputs[i]
            table.insert(inputs, port_name)
        end

        -- Build outputs array from tracked values (RmlUi uses 0-based indexing)
        for i = 1, #editor.selected_node.outputs do
            local port_name = payload["output_port_" .. (i - 1)] or editor.selected_node.outputs[i]
            table.insert(outputs, port_name)
        end
    end

    -- Update node type in database
    local success = workflow_db.update_node_type(
        node_id,
        name,
        color_r, color_g, color_b, color_a
    )

    if not success then
        print("ERROR: Failed to update node type")
        return
    end

    -- Delete all ports and re-add them
    workflow_db.delete_ports(node_id)

    -- Add input ports
    for i, port_name in ipairs(inputs) do
        workflow_db.add_port(node_id, port_name, "input", i)
    end

    -- Add output ports
    for i, port_name in ipairs(outputs) do
        workflow_db.add_port(node_id, port_name, "output", i)
    end

    -- Reload node types from database to get the updated values
    load_node_types()

    -- Re-select the same node and bind it
    -- This ensures both node_types and selected_node models are in sync
    for i, nt in ipairs(editor.node_types) do
        if nt.id == node_id then
            editor.selected_index = i
            editor.selected_node = editor.node_types[i]
            -- Update selected_node binding with fresh database values
            data.bind("selected_node", {editor.selected_node})
            break
        end
    end
end

-- Delete the selected node type
local function delete_node_type(payload)
    if not payload.id then
        print("ERROR: No id in delete_node_type payload")
        return
    end

    local node_type_id = payload.id
    local node_type_name = payload.name or "Unknown"

    local success = workflow_db.delete_node_type(node_type_id)

    if not success then
        print("ERROR: Failed to delete node type")
        return
    end

    -- Clear selection
    editor.selected_index = nil
    editor.selected_node = nil
    data.bind("selected_node", {})

    -- Reload node types
    load_node_types()
end

-- ============================================
-- Menu Registration
-- ============================================

local function register_workflow_menu()
    event.trigger_global("menu_register", {
        menu_id = "workflow",
        label = "Workflow",
        position = 100,
        items = {
            {
                item_id = "workflow_list",
                label = "Workflows",
                action = "workflow_switch_to_list_view"
            },
            {
                item_id = "new_workflow_menu",
                label = "New Workflow",
                action = "new_workflow"
            },
            {
                item_id = "node_types",
                label = "Configure Node Types",
                action = "workflow_switch_to_node_editor"
            },
            {
                item_id = "execute_workflow_menu",
                label = "Execute Workflow",
                action = "execute_workflow"
            },
            {
                item_id = "execution_history_menu",
                label = "Execution History",
                action = "show_execution_history"
            }
        }
    })
end

-- ============================================
-- Main Thread Functions
-- ============================================

function startup()
    print("Workflow Application started (thread_id: " .. thread_id .. ")")

    -- Send startup notification
    event.trigger_global("notification_success", {
        title = "Workflow App Started",
        message = "Initializing workflow application..."
    })

    -- Initialize workflow database
    if not workflow_db.init() then
        print("ERROR: Failed to initialize workflow database")
        event.trigger_global("notification_error", {
            title = "Database Error",
            message = "Failed to initialize workflow database"
        })
        return
    end

    database_initialized = true
    print("Workflow database initialized successfully")

    -- Test interactive notification (agent question)
    local user_response = nil
    event.register("notification_response", function(payload)
        print("Received notification response:", payload.action_id)
        user_response = payload.action_id
    end)

    event.trigger_global("add_notification", {
        type = "question",
        title = "Welcome to Workflow App",
        message = "Would you like a quick tutorial on creating workflows?",
        source = "Workflow App",
        dismissible = false,
        ttl = 0,  -- Persists until user responds
        actions = {
            { id = "yes", label = "Yes, show tutorial" },
            { id = "no", label = "No, skip tutorial" },
            { id = "later", label = "Remind me later" }
        }
    })

    -- Test expandable notification
    event.trigger_global("add_notification", {
        type = "info",
        title = "Workflow System Info",
        message = "Click to view system details",
        source = "Workflow App",
        dismissible = true,
        expandable = true,
        content_format = "markup",
        ttl = 0,
        expanded_content = [[
<p>The workflow system is now ready for use.</p>
<p><strong>Features:</strong></p>
<ul>
    <li>Visual node-based workflow editor</li>
    <li>Custom node type creation</li>
    <li>Persistent workflow storage</li>
    <li>Real-time database synchronization</li>
</ul>
<pre>System Status: Online
Database: SQLite (workflow.db)
Node Types Loaded: ]] .. #node_types_data .. [[

Version: 1.0.0</pre>
        ]]
    })

    -- Register global event handlers for view switching (from menu)
    event.register_global("workflow_switch_to_list_view", handle_switch_to_list_view)
    event.register_global("workflow_switch_to_node_editor", handle_switch_to_node_editor)
    event.register_global("workflow_switch_to_main_view", handle_switch_to_workflow_view)

    -- Register reload handler for workflow list view
    event.register("reload_workflows", reload_workflows_handler)

    -- Register event handlers for workflow management
    event.register("new_workflow", create_new_workflow)
    event.register_global("new_workflow", create_new_workflow)  -- Also register as global for menu
    event.register("select_workflow", select_workflow)
    event.register("rename_workflow", rename_workflow)
    event.register("delete_workflow", delete_workflow)

    -- Register workflow change event handlers (auto-persist to database)
    event.register("workflow_node_created", on_workflow_node_created)
    event.register("workflow_node_moved", on_workflow_node_moved)
    event.register("workflow_node_deleted", on_workflow_node_deleted)
    event.register("workflow_connection_added", on_workflow_connection_added)

    -- Register event handlers for node type editor
    event.register("select_node_type", select_node_type)
    event.register("add_new_node_type", add_new_node_type)
    event.register("add_input_port", add_input_port)
    event.register("add_output_port", add_output_port)
    event.register("delete_input_port", delete_input_port)
    event.register("delete_output_port", delete_output_port)
    event.register("save_node_type", save_node_type)
    event.register("delete_node_type", delete_node_type)

    -- Register execution control event handlers
    event.register("execute_workflow", handle_execute_workflow)
    event.register_global("execute_workflow", handle_execute_workflow)  -- Also register as global for menu
    event.register("pause_execution", handle_pause_execution)
    event.register("stop_execution", handle_stop_execution)
    event.register("step_execution", handle_step_execution)

    -- Register approval system event handlers
    event.register("workflow_approval_response", handle_workflow_approval_response)

    -- Register configuration event handlers
    event.register("save_workflow_config", handle_save_workflow_config)
    event.register("edit_node", handle_edit_node)
    event.register("cancel_node_config", handle_cancel_node_config)
    event.register("save_node_config_from_dialog", handle_save_node_config_from_dialog)
    event.register("node_script_modified", handle_node_script_modified)
    event.register("save_node_config", handle_save_node_config)

    -- Register texteditor command handlers for keybindings
    event.register("command_copy", function(payload)
        if payload.element_tag == "texteditor" then
            ui.texteditor_copy(payload.element_id)
        end
    end)

    event.register("command_paste", function(payload)
        if payload.element_tag == "texteditor" then
            ui.texteditor_paste(payload.element_id)
        end
    end)

    event.register("command_cut", function(payload)
        if payload.element_tag == "texteditor" then
            ui.texteditor_cut(payload.element_id)
        end
    end)

    event.register("command_select_all", function(payload)
        if payload.element_tag == "texteditor" then
            ui.texteditor_select_all(payload.element_id)
        end
    end)

    event.register("command_undo", function(payload)
        if payload.element_tag == "texteditor" then
            ui.texteditor_undo(payload.element_id)
        end
    end)

    event.register("command_redo", function(payload)
        if payload.element_tag == "texteditor" then
            ui.texteditor_redo(payload.element_id)
        end
    end)

    -- Register history event handlers
    event.register("show_execution_history", handle_show_execution_history)
    event.register_global("show_execution_history", handle_show_execution_history)  -- Also register as global for menu
    event.register("view_execution", handle_view_execution)

    -- Initialize data bindings
    data.bind("selected_node", {})
    data.bind("workflows", {})
    data.bind("active_workflow", {})
    data.bind("workflow_nodes", {})
    data.bind("workflow_connections", {})
    data.bind("active_view", {{view = "workflow"}})

    -- Initialize execution-related data models (prevents warnings)
    data.bind("execution_state", {})
    data.bind("workflow_config", {})
    data.bind("library_list", {})
    data.bind("node_config", {})  -- Empty array initially
    data.bind("approval_request", {})
    data.bind("execution_history", {})
    data.bind("execution_details", {})

    -- Load node types from database
    load_node_types()

    -- Load workflows from database
    load_workflows()

    -- Create a default workflow if none exists
    if #workflows_list == 0 then
        local workflow_id = workflow_db.create_workflow("My First Workflow")
        if workflow_id then
            load_workflows()
            select_workflow({id = workflow_id})
        end
    else
        -- Load the most recently updated workflow
        select_workflow({id = workflows_list[1].id})
    end

    -- Load the unified UI
    ui.load_document("ui/workflow_app.rml", true, "workflow_app")

    -- Register workflow menu
    register_workflow_menu()
end

function update(dt)
    -- Check if user responded to tutorial question
    if user_response then
        if user_response == "yes" then
            event.trigger_global("notification_info", {
                title = "Tutorial Mode",
                message = "Tutorial feature coming soon!"
            })
        elseif user_response == "no" then
            event.trigger_global("notification_info", {
                title = "Tutorial Skipped",
                message = "You can access help anytime from the menu."
            })
        elseif user_response == "later" then
            event.trigger_global("notification_info", {
                title = "Reminder Set",
                message = "We'll ask again next time."
            })
        end
        user_response = nil  -- Clear response
    end

    -- Poll execution state if there's an active execution
    if active_execution_id then
        time_since_poll = time_since_poll + dt
        if time_since_poll >= 0.1 then  -- Poll every 100ms
            poll_execution_state()
            time_since_poll = 0
        end
    end
end

function shutdown()
    -- Unregister workflow menu
    event.trigger_global("menu_unregister", {menu_id = "workflow"})

    if database_initialized then
        workflow_db.close()
    end
    print("Workflow Application shutting down")
end
