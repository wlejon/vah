-- Workflow Editor Thread Script
-- Handles database initialization and data management for workflow editor

-- Load workflow database module
local workflow_db = require("workflow_db")

local database_initialized = false
local node_types_data = {}

-- Load node types from database and bind to UI
local function load_node_types()
    if not database_initialized then
        return
    end

    -- Load from database (already includes color components)
    node_types_data = workflow_db.load_node_types()

    print("Loaded " .. #node_types_data .. " node types for workflow editor")

    -- Bind data to the UI
    data.bind("node_types", node_types_data)
end

function startup()
    print("Workflow Editor thread started (thread_id: " .. thread_id .. ")")

    -- Initialize workflow database
    if not workflow_db.init() then
        print("ERROR: Failed to initialize workflow database")
        return
    end

    database_initialized = true
    print("Workflow database initialized successfully")

    -- Register event handler for navigation
    event.register("open_node_editor", function(payload)
        print("Opening node type editor view")
        ui.hide_document("workflow_editor")
        ui.show_document("node_type_editor")
    end)

    -- Bind data BEFORE loading UI (so data model exists when document loads)
    load_node_types()

    -- Load UI AFTER data is bound
    ui.load_document("ui/workflow_editor.rml", true, "workflow_editor")
end

function update(dt)
    -- Nothing to update continuously
end

function shutdown()
    if database_initialized then
        workflow_db.close()
    end
    print("Workflow Editor thread shutting down")
end
