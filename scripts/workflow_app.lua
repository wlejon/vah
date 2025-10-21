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
-- Main Thread Functions
-- ============================================

function startup()
    print("Workflow Application started (thread_id: " .. thread_id .. ")")

    -- Send startup notification
    notifications.success("Workflow App Started", "Initializing workflow application...")

    -- Initialize workflow database
    if not workflow_db.init() then
        print("ERROR: Failed to initialize workflow database")
        notifications.error("Database Error", "Failed to initialize workflow database")
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

    notifications.add({
        type = 5,  -- AgentQuestion
        title = "Welcome to Workflow App",
        message = "Would you like a quick tutorial on creating workflows?",
        thread = "Workflow App",
        dismissible = false,
        ttl = 0,  -- Persists until user responds
        actions = {
            { id = "yes", label = "Yes, show tutorial" },
            { id = "no", label = "No, skip tutorial" },
            { id = "later", label = "Remind me later" }
        }
    })

    -- Test expandable notification
    notifications.add({
        type = 0,  -- Info
        title = "Workflow System Info",
        message = "Click to view system details",
        thread = "Workflow App",
        dismissible = true,
        expandable = true,
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

    -- Register reload handler for workflow list view
    event.register("reload_workflows", reload_workflows_handler)

    -- Register event handlers for workflow management
    event.register("new_workflow", create_new_workflow)
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

    -- Initialize data bindings
    data.bind("selected_node", {})
    data.bind("workflows", {})
    data.bind("active_workflow", {})
    data.bind("workflow_nodes", {})
    data.bind("workflow_connections", {})

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
end

function update(dt)
    -- Check if user responded to tutorial question
    if user_response then
        if user_response == "yes" then
            notifications.info("Tutorial Mode", "Tutorial feature coming soon!")
        elseif user_response == "no" then
            notifications.info("Tutorial Skipped", "You can access help anytime from the menu.")
        elseif user_response == "later" then
            notifications.info("Reminder Set", "We'll ask again next time.")
        end
        user_response = nil  -- Clear response
    end
end

function shutdown()
    if database_initialized then
        workflow_db.close()
    end
    print("Workflow Application shutting down")
end
