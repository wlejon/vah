-- Unified Workflow Application
-- Manages both the workflow editor and node type editor views

-- Load all workflow modules
local state = require("workflow.state")
local workflow_db = require("workflow.db")
local views = require("workflow.views")
local workflows = require("workflow.workflows")
local node_types = require("workflow.node_types")
local execution = require("workflow.execution")
local events = require("workflow.events")

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

    state.database_initialized = true
    print("Workflow database initialized successfully")

    -- Register all event handlers from modules
    events.register_all()

    -- Initialize data bindings
    datamodel.bind_table("selected_node", {})
    datamodel.bind_table("workflows", {})
    datamodel.bind_table("active_workflow", {})
    datamodel.bind_table("workflow_nodes", {})
    datamodel.bind_table("workflow_connections", {})
    datamodel.bind_table("active_view", {{view = "workflow"}})

    -- Initialize execution-related data models (prevents warnings)
    datamodel.bind_table("execution_state", {})
    datamodel.bind_table("workflow_config", {})
    datamodel.bind_table("library_list", {})
    datamodel.bind_table("node_config", {})  -- Empty array initially
    datamodel.bind_table("approval_request", {})
    datamodel.bind_table("execution_history", {})
    datamodel.bind_table("execution_details", {})

    -- Load node types from database
    node_types.load_node_types()

    -- Load workflows from database
    workflows.load_workflows()

    -- Create a default workflow if none exists
    if #state.workflows_list == 0 then
        local workflow_id = workflow_db.create_workflow("My First Workflow")
        if workflow_id then
            workflows.load_workflows()
            workflows.select_workflow({id = workflow_id})
        end
    else
        -- Load the most recently updated workflow
        workflows.select_workflow({id = state.workflows_list[1].id})
    end

    -- Load the unified UI
    ui.load_document("ui/apps/workflow/workflow_app.rml", true, "workflow_app")
end

function shutdown()
    -- Unregister all events
    events.unregister_all()

    if state.database_initialized then
        workflow_db.close()
    end
    print("Workflow Application shutting down")
end
