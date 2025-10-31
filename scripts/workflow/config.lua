-- Workflow Configuration
-- Handles workflow and node configuration

local state = require("workflow.state")
local workflow_db = require("workflow.db")
local views = require("workflow.views")
local workflows = require("workflow.workflows")

local config = {}

-- ============================================
-- Workflow Configuration
-- ============================================

-- Show workflow configuration view
local function handle_show_workflow_config(payload)
    if not state.database_initialized or not state.active_workflow.id then
        print("ERROR: No active workflow to configure")
        event.trigger_global("notification_error", {
            title = "Configuration Error",
            message = "No active workflow to configure"
        })
        return
    end

    -- Load current workflow config from database
    local config_json = workflow_db.load_workflow_config(state.active_workflow.id)
    local workflow_config = {
        workflow_id = state.active_workflow.id,
        name = state.active_workflow.name or "Unnamed Workflow",
        description = "",
        requires = {}
    }

    -- Parse config JSON if it exists
    if config_json and config_json ~= "" then
        local ok, parsed = pcall(json.decode, config_json)
        if ok and parsed then
            workflow_config.description = parsed.description or ""
            workflow_config.requires = parsed.requires or {}
        end
    end

    -- Bind workflow config
    datamodel.bind_table("workflow_config", {{
        workflow_id = workflow_config.workflow_id,
        name = workflow_config.name,
        description = workflow_config.description
    }})

    -- Load all available libraries and mark which ones are required
    local all_libs = workflow_db.get_library_definitions()
    local library_list = {}

    for _, lib in ipairs(all_libs) do
        local is_enabled = false
        for _, req in ipairs(workflow_config.requires) do
            if req == lib.id then
                is_enabled = true
                break
            end
        end

        table.insert(library_list, {
            id = lib.id,
            name = lib.name,
            description = lib.description,
            access_description = lib.access_description,
            enabled = is_enabled
        })
    end

    -- Bind library list
    datamodel.bind_table("library_list", library_list)

    -- Switch to config view
    views.switch_to_view("workflow_config")
    print("Workflow config view loaded")
end

-- Save workflow configuration
local function handle_save_workflow_config(payload)
    if not state.active_workflow.id then
        print("ERROR: No active workflow")
        return
    end

    local workflow_id = state.active_workflow.id

    -- Update workflow name if provided
    if payload.name and payload.name ~= "" then
        local success = workflow_db.db_handle:execute(
            "UPDATE workflows SET name = ? WHERE id = ?",
            payload.name,
            workflow_id
        )
        if success then
            state.active_workflow.name = payload.name
            print("Workflow name updated to: " .. payload.name)
        end
    end

    -- Build config JSON with description and requires
    local workflow_config = {
        description = payload.description or "",
        requires = payload.requires or {}
    }

    -- Convert to JSON string
    local config_json = json.encode(workflow_config)
    print("Saving workflow config: " .. config_json)

    local success = workflow_db.save_workflow_config(workflow_id, config_json)
    if success then
        print("Workflow configuration saved")
        event.trigger_global("notification_success", {
            title = "Configuration Saved",
            message = "Workflow configuration has been saved"
        })

        -- Update workflows list to reflect name change
        workflows.load_workflows()

        -- Switch back to workflow view
        views.switch_to_view("workflow")
    else
        print("ERROR: Failed to save workflow configuration")
        event.trigger_global("notification_error", {
            title = "Save Failed",
            message = "Failed to save workflow configuration"
        })
    end
end

-- ============================================
-- Node Configuration
-- ============================================

-- Edit node (open config dialog)
local function handle_edit_node(payload)
    if not state.database_initialized or not state.active_workflow.id then
        print("ERROR: No active workflow")
        return
    end

    if not payload.node_id then
        print("ERROR: No node_id in edit_node payload")
        return
    end

    -- Load current node config from database
    local node_config = workflow_db.load_node_config(state.active_workflow.id, payload.node_id)
    print("Loaded config from DB: " .. tostring(node_config))

    -- Parse config or create default
    local node_config_data = {
        node_id = payload.node_id,
        workflow_id = state.active_workflow.id,
        label = "",
        inputs = "",
        outputs = "",
        script = ""
    }

    if node_config and node_config ~= "" then
        print("Config exists, parsing...")
        node_config_data.script = node_config.script or ""

        if node_config.inputs then
            node_config_data.inputs = table.concat(node_config.inputs, ", ")
        end

        if node_config.outputs then
            node_config_data.outputs = table.concat(node_config.outputs, ", ")
        end

        node_config_data.label = node_config.label or ""
    else
        -- Get node type to provide defaults
        local node_type = nil
        for _, nt in ipairs(state.node_types_data) do
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
    state.editing_node_config = node_config_data

    -- Switch to node config view
    views.switch_to_view("node_config")

    -- Set input field values via DOM manipulation
    ui.set_element_attribute("node_label_input", "value", node_config_data.label or "")
    ui.set_element_attribute("node_inputs_input", "value", node_config_data.inputs or "")
    ui.set_element_attribute("node_outputs_input", "value", node_config_data.outputs or "")

    -- Set texteditor content
    ui.set_texteditor_content("node_script_editor", state.editing_node_config.script or "")
    ui.set_texteditor_editable("node_script_editor", true)
end

-- Handle cancel button
local function handle_cancel_node_config(payload)
    state.editing_node_config = nil
    datamodel.bind_table("node_config", {})  -- Clear to empty array
    views.switch_to_view("workflow")
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

    if not state.editing_node_config then
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
    local node_config = {
        label = payload.label or "",
        script = state.editing_node_config.script or "",  -- Get from editing state
        inputs = split_csv(payload.inputs or ""),
        outputs = split_csv(payload.outputs or "")
    }

    local success = workflow_db.save_node_config(payload.workflow_id, payload.node_id, node_config)
    if success then
        print("Node configuration saved for node " .. payload.node_id)
        event.trigger_global("notification_success", {
            title = "Configuration Saved",
            message = "Node configuration has been saved"
        })

        -- Reload workflow from database and bind
        local nodes, connections = workflow_db.load_workflow(payload.workflow_id)
        if nodes then
            datamodel.bind_table("workflow_nodes", nodes)
            datamodel.bind_table("workflow_connections", connections)
        end

        -- Clear editing state
        state.editing_node_config = nil
        datamodel.bind_table("node_config", {})  -- Clear to empty array

        -- Switch back to workflow view
        views.switch_to_view("workflow")
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

    if not state.editing_node_config then
        print("ERROR: No node config being edited")
        return
    end

    print("editing_node_config.script length: " .. tostring(#(state.editing_node_config.script or "")))
    print("editing_node_config.workflow_id: " .. tostring(state.editing_node_config.workflow_id))
    print("editing_node_config.node_id: " .. tostring(state.editing_node_config.node_id))

    -- Use form values from payload (queried from DOM in RML)
    print("About to call handle_save_node_config")
    handle_save_node_config({
        workflow_id = state.editing_node_config.workflow_id,
        node_id = state.editing_node_config.node_id,
        label = payload.label or state.editing_node_config.label,
        inputs = payload.inputs or state.editing_node_config.inputs,
        outputs = payload.outputs or state.editing_node_config.outputs
    })
    print("handle_save_node_config returned")
end

-- Handle script modifications from texteditor
local function handle_node_script_modified(payload)
    if state.editing_node_config and payload.content then
        state.editing_node_config.script = payload.content
    end
end

-- ============================================
-- Event Registration
-- ============================================

function config.register_events()
    -- Register configuration event handlers
    event.register("show_workflow_config", handle_show_workflow_config)
    event.register_global("show_workflow_config", handle_show_workflow_config)  -- Also register as global for menu
    event.register("save_workflow_config", handle_save_workflow_config)
    event.register("edit_node", handle_edit_node)
    event.register("cancel_node_config", handle_cancel_node_config)
    event.register("save_node_config_from_dialog", handle_save_node_config_from_dialog)
    event.register("node_script_modified", handle_node_script_modified)
    event.register("save_node_config", handle_save_node_config)
end

return config
