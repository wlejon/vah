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

    print("Loaded " .. #node_types_data .. " node types")

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
-- View Switching Functions
-- ============================================

local function switch_to_workflow(payload)
    print("Switching to workflow editor view")

    -- Reload node types from database (in case they were modified)
    load_node_types()

    -- Hide node editor view
    ui.remove_element_class("node-editor-view", "active")
    -- Show workflow view
    ui.add_element_class("workflow-view", "active")
end

local function switch_to_node_editor(payload)
    print("Switching to node type editor view")

    -- Hide workflow view
    ui.remove_element_class("workflow-view", "active")
    -- Show node editor view
    ui.add_element_class("node-editor-view", "active")
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
            print("Selected node type: " .. editor.selected_node.name)

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
        print("Created new node type with ID: " .. node_id)
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
    print("Added input port")
end

-- Add output port to selected node
local function add_output_port(payload)
    if not editor.selected_node then
        return
    end

    table.insert(editor.selected_node.outputs, "New Output")
    data.bind("selected_node", {editor.selected_node})
    print("Added output port")
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
        print("Deleted input port at index " .. index)
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
        print("Deleted output port at index " .. index)
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

    -- The payload will have input_port_1, input_port_2, etc. for tracked inputs
    -- and the original inputs/outputs arrays
    -- We need to check which ports exist and get their current values
    if editor.selected_node then
        -- Build inputs array from tracked values
        for i = 1, #editor.selected_node.inputs do
            local port_name = payload["input_port_" .. i] or editor.selected_node.inputs[i]
            table.insert(inputs, port_name)
        end

        -- Build outputs array from tracked values
        for i = 1, #editor.selected_node.outputs do
            local port_name = payload["output_port_" .. i] or editor.selected_node.outputs[i]
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

    -- Reload node types to reflect changes
    load_node_types()

    -- Re-select the same node
    for i, nt in ipairs(editor.node_types) do
        if nt.id == node_id then
            editor.selected_index = i
            editor.selected_node = editor.node_types[i]
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

    -- Initialize workflow database
    if not workflow_db.init() then
        print("ERROR: Failed to initialize workflow database")
        return
    end

    database_initialized = true
    print("Workflow database initialized successfully")

    -- Register event handlers for view switching
    event.register("switch_to_workflow", switch_to_workflow)
    event.register("switch_to_node_editor", switch_to_node_editor)

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

    -- Load node types from database
    load_node_types()

    -- Load the unified UI
    ui.load_document("ui/workflow_app.rml", true, "workflow_app")
end

function update(dt)
    -- Nothing to update continuously
end

function shutdown()
    if database_initialized then
        workflow_db.close()
    end
    print("Workflow Application shutting down")
end
