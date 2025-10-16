-- Node Type Editor
-- UI for creating and editing workflow node types

-- Load workflow database module
local workflow_db = require("workflow_db")

-- Editor state
local editor = {
    node_types = {},
    selected_index = nil,
    selected_node = nil
}

-- Load all node types from database
local function load_node_types()
    -- Query node types with color components separated
    if not workflow_db then
        print("ERROR: workflow_db not available")
        return
    end

    local db_node_types = workflow_db.load_node_types()

    -- Convert to format suitable for the UI
    editor.node_types = {}
    for _, nt in ipairs(db_node_types) do
        -- Extract color components from nvg.rgba
        -- We need to query them separately from the database
        local node_type_data = {
            id = nt.id,
            name = nt.name,
            color_r = 0,
            color_g = 0,
            color_b = 0,
            color_a = 255,
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

    -- Now load color data separately
    load_node_type_colors()

    print("Loaded " .. #editor.node_types .. " node types for editing")
    data.bind("node_types", editor.node_types)
end

-- Load color data for all node types
local function load_node_type_colors()
    for _, nt in ipairs(editor.node_types) do
        local db_handle = workflow_db.db_handle or db.open("data/workflow.db")
        if db_handle then
            local result, error = db_handle:query(string.format(
                "SELECT color_r, color_g, color_b, color_a FROM node_types WHERE id = %d",
                nt.id
            ))

            if error == "" and result and #result > 0 then
                nt.color_r = result[1].color_r
                nt.color_g = result[1].color_g
                nt.color_b = result[1].color_b
                nt.color_a = result[1].color_a
            end
        end
    end
end

-- Select a node type for editing
function select_node_type(event)
    local index = tonumber(event.index)
    if not index or index < 1 or index > #editor.node_types then
        return
    end

    editor.selected_index = index
    editor.selected_node = editor.node_types[index]

    print("Selected node type: " .. editor.selected_node.name)

    -- Update data model
    data.bind("selected_index", editor.selected_index)
    data.bind("selected_node", editor.selected_node)
end

-- Add a new node type
function add_new_node_type()
    local node_id = workflow_db.create_node_type("New Node", 128, 128, 128, 255)

    if node_id then
        print("Created new node type with ID: " .. node_id)
        load_node_types()  -- Reload to show the new node type
    else
        print("ERROR: Failed to create new node type")
    end
end

-- Add input port to selected node
function add_input_port()
    if not editor.selected_node then
        return
    end

    table.insert(editor.selected_node.inputs, "New Input")
    data.bind("selected_node", editor.selected_node)
    print("Added input port")
end

-- Add output port to selected node
function add_output_port()
    if not editor.selected_node then
        return
    end

    table.insert(editor.selected_node.outputs, "New Output")
    data.bind("selected_node", editor.selected_node)
    print("Added output port")
end

-- Delete input port
function delete_input_port(event)
    if not editor.selected_node then
        return
    end

    local index = tonumber(event.index)
    if index and index >= 1 and index <= #editor.selected_node.inputs then
        table.remove(editor.selected_node.inputs, index)
        data.bind("selected_node", editor.selected_node)
        print("Deleted input port at index " .. index)
    end
end

-- Delete output port
function delete_output_port(event)
    if not editor.selected_node then
        return
    end

    local index = tonumber(event.index)
    if index and index >= 1 and index <= #editor.selected_node.outputs then
        table.remove(editor.selected_node.outputs, index)
        data.bind("selected_node", editor.selected_node)
        print("Deleted output port at index " .. index)
    end
end

-- Save changes to the selected node type
function save_node_type()
    if not editor.selected_node then
        print("ERROR: No node type selected")
        return
    end

    -- Get current input values
    local inputs = input.get_tracked_inputs()

    -- Update from tracked inputs
    local name = inputs.node_name or editor.selected_node.name
    local color_r = tonumber(inputs.color_r) or editor.selected_node.color_r
    local color_g = tonumber(inputs.color_g) or editor.selected_node.color_g
    local color_b = tonumber(inputs.color_b) or editor.selected_node.color_b
    local color_a = tonumber(inputs.color_a) or editor.selected_node.color_a

    -- Clamp color values
    color_r = math.max(0, math.min(255, color_r))
    color_g = math.max(0, math.min(255, color_g))
    color_b = math.max(0, math.min(255, color_b))
    color_a = math.max(0, math.min(255, color_a))

    -- Update port names from tracked inputs
    for i, _ in ipairs(editor.selected_node.inputs) do
        local input_name = inputs["input_port_" .. i]
        if input_name then
            editor.selected_node.inputs[i] = input_name
        end
    end

    for i, _ in ipairs(editor.selected_node.outputs) do
        local output_name = inputs["output_port_" .. i]
        if output_name then
            editor.selected_node.outputs[i] = output_name
        end
    end

    print("Saving node type: " .. name)
    print("  Color: " .. color_r .. ", " .. color_g .. ", " .. color_b .. ", " .. color_a)
    print("  Inputs: " .. #editor.selected_node.inputs)
    print("  Outputs: " .. #editor.selected_node.outputs)

    -- Update node type in database
    local success = workflow_db.update_node_type(
        editor.selected_node.id,
        name,
        color_r, color_g, color_b, color_a
    )

    if not success then
        print("ERROR: Failed to update node type")
        return
    end

    -- Delete all ports and re-add them
    workflow_db.delete_ports(editor.selected_node.id)

    -- Add input ports
    for i, port_name in ipairs(editor.selected_node.inputs) do
        workflow_db.add_port(editor.selected_node.id, port_name, "input", i)
    end

    -- Add output ports
    for i, port_name in ipairs(editor.selected_node.outputs) do
        workflow_db.add_port(editor.selected_node.id, port_name, "output", i)
    end

    print("Node type saved successfully")

    -- Reload node types to reflect changes
    load_node_types()

    -- Re-select the same node (it may have moved in the list due to sorting)
    for i, nt in ipairs(editor.node_types) do
        if nt.id == editor.selected_node.id then
            editor.selected_index = i
            editor.selected_node = editor.node_types[i]
            data.bind("selected_index", editor.selected_index)
            data.bind("selected_node", editor.selected_node)
            break
        end
    end
end

-- Delete the selected node type
function delete_node_type()
    if not editor.selected_node then
        print("ERROR: No node type selected")
        return
    end

    local node_type_name = editor.selected_node.name
    local node_type_id = editor.selected_node.id

    print("Deleting node type: " .. node_type_name)

    local success = workflow_db.delete_node_type(node_type_id)

    if not success then
        print("ERROR: Failed to delete node type")
        return
    end

    print("Node type deleted successfully")

    -- Clear selection
    editor.selected_index = nil
    editor.selected_node = nil
    data.bind("selected_index", nil)
    data.bind("selected_node", nil)

    -- Reload node types
    load_node_types()
end

-- Startup function
function startup()
    print("Node Type Editor started (thread_id: " .. thread_id .. ")")

    -- Initialize database
    if not workflow_db.init() then
        print("ERROR: Failed to initialize workflow database")
        return
    end

    -- Bind initial data
    data.bind("node_types", {})
    data.bind("selected_index", nil)
    data.bind("selected_node", nil)

    -- Load node types from database
    load_node_types()

    -- Load UI
    ui.load_document("ui/node_type_editor.rml")
end

function update(dt)
    -- Nothing to update continuously
end

function shutdown()
    workflow_db.close()
    print("Node Type Editor shutting down")
end
