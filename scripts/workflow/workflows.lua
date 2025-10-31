-- Workflow Management
-- Handles workflow CRUD operations and change events

local state = require("workflow.state")
local workflow_db = require("workflow.db")
local views = require("workflow.views")

local workflows = {}

-- ============================================
-- Workflow Management Functions
-- ============================================

-- Load all workflows from database
function workflows.load_workflows()
    if not state.database_initialized then
        return
    end

    state.workflows_list = workflow_db.get_workflows()

    -- Bind to UI
    datamodel.bind_table("workflows", state.workflows_list)
end

-- Create a new workflow
local function create_new_workflow(payload)
    if not state.database_initialized then
        return
    end

    local workflow_id = workflow_db.create_workflow("New Workflow")
    if workflow_id then
        -- Reload workflows list
        workflows.load_workflows()

        -- Switch to the new workflow
        workflows.select_workflow({id = workflow_id})
    else
        print("ERROR: Failed to create new workflow")
    end
end

-- Select and load a workflow
function workflows.select_workflow(payload)
    if not state.database_initialized then
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
    state.active_workflow.id = workflow_id

    -- Find workflow name
    for _, wf in ipairs(state.workflows_list) do
        if wf.id == workflow_id then
            state.active_workflow.name = wf.name
            break
        end
    end

    -- Bind workflow data to make it available to workflow editor
    -- Include a timestamp to force client to reinitialize
    datamodel.bind_table("workflow_nodes", nodes)
    datamodel.bind_table("workflow_connections", connections)
    datamodel.bind_table("active_workflow", {state.active_workflow})
    datamodel.bind_table("workflow_reload_trigger", {timestamp = os.time()})

    -- Switch back to workflow view
    views.switch_to_view("workflow")
end

-- Rename the active workflow
local function rename_workflow(payload)
    if not state.database_initialized or not state.active_workflow.id then
        print("ERROR: No active workflow")
        return
    end

    local new_name = payload.name or "Unnamed Workflow"

    local success = workflow_db.update_workflow(state.active_workflow.id, new_name)
    if success then
        state.active_workflow.name = new_name
        datamodel.bind_table("active_workflow", {state.active_workflow})
        workflows.load_workflows()
    else
        print("ERROR: Failed to rename workflow")
    end
end

-- Delete a workflow
local function delete_workflow(payload)
    if not state.database_initialized then
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
        if state.active_workflow.id == workflow_id then
            state.active_workflow.id = nil
            state.active_workflow.name = nil
            datamodel.bind_table("active_workflow", {})
            datamodel.bind_table("workflow_nodes", {})
            datamodel.bind_table("workflow_connections", {})
        end

        -- Reload workflows list
        workflows.load_workflows()
    else
        print("ERROR: Failed to delete workflow")
    end
end

-- ============================================
-- Workflow Change Event Handlers
-- ============================================

-- Workflow change event handlers - update database and push to client
local function on_workflow_node_created(payload)
    if not state.database_initialized or not state.active_workflow.id then
        print("ERROR: No active workflow")
        return
    end

    -- Add node to database
    local success = workflow_db.add_node(
        state.active_workflow.id,
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
    local nodes, connections = workflow_db.load_workflow(state.active_workflow.id)
    if nodes then
        datamodel.bind_table("workflow_nodes", nodes)
        datamodel.bind_table("workflow_connections", connections)
    end
end

local function on_workflow_node_moved(payload)
    if not state.database_initialized or not state.active_workflow.id then
        print("ERROR: No active workflow")
        return
    end

    -- Update node position in database
    local success = workflow_db.update_node_position(
        state.active_workflow.id,
        payload.node_id,
        payload.x,
        payload.y
    )

    if not success then
        print("ERROR: Failed to update node position in database")
        return
    end

    -- Reload workflow from database and push to client
    local nodes, connections = workflow_db.load_workflow(state.active_workflow.id)
    if nodes then
        datamodel.bind_table("workflow_nodes", nodes)
        datamodel.bind_table("workflow_connections", connections)
    end
end

local function on_workflow_node_deleted(payload)
    if not state.database_initialized or not state.active_workflow.id then
        print("ERROR: No active workflow")
        return
    end

    -- Delete node from database (also deletes related connections)
    local success = workflow_db.delete_node(state.active_workflow.id, payload.node_id)

    if not success then
        print("ERROR: Failed to delete node from database")
        return
    end

    -- Reload workflow from database and push to client
    local nodes, connections = workflow_db.load_workflow(state.active_workflow.id)
    if nodes then
        datamodel.bind_table("workflow_nodes", nodes)
        datamodel.bind_table("workflow_connections", connections)
    end
end

local function on_workflow_connection_added(payload)
    if not state.database_initialized or not state.active_workflow.id then
        print("ERROR: No active workflow")
        return
    end

    -- Add connection to database
    local success = workflow_db.add_connection(
        state.active_workflow.id,
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
    local nodes, connections = workflow_db.load_workflow(state.active_workflow.id)
    if nodes then
        datamodel.bind_table("workflow_nodes", nodes)
        datamodel.bind_table("workflow_connections", connections)
    end
end

-- Handler for reload_workflows event
local function reload_workflows_handler(payload)
    workflows.load_workflows()
end

-- ============================================
-- Event Registration
-- ============================================

function workflows.register_events()
    -- Register reload handler for workflow list view
    event.register("reload_workflows", reload_workflows_handler)

    -- Register event handlers for workflow management
    event.register("new_workflow", create_new_workflow)
    event.register_global("new_workflow", create_new_workflow)  -- Also register as global for menu
    event.register("select_workflow", workflows.select_workflow)
    event.register("rename_workflow", rename_workflow)
    event.register("delete_workflow", delete_workflow)

    -- Register workflow change event handlers (auto-persist to database)
    event.register("workflow_node_created", on_workflow_node_created)
    event.register("workflow_node_moved", on_workflow_node_moved)
    event.register("workflow_node_deleted", on_workflow_node_deleted)
    event.register("workflow_connection_added", on_workflow_connection_added)
end

return workflows
