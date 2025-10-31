-- Workflow Application State
-- Shared state variables used across all workflow modules

local state = {
    -- Database initialization flag
    database_initialized = false,

    -- Node types data (loaded from database)
    node_types_data = {},

    -- Editor state for node type editor
    editor = {
        node_types = {},
        selected_index = nil,
        selected_node = nil
    },

    -- Active workflow state
    active_workflow = {
        id = nil,
        name = nil
    },

    -- List of all workflows
    workflows_list = {},

    -- Current view state
    active_view = "workflow",

    -- Execution state
    active_execution_id = nil,
    time_since_poll = 0,

    -- Node config editing state
    editing_node_config = nil,

    -- Approval dialog state
    approval_dialog_doc = nil,
    pending_approval = nil,  -- Stores {workflow_id, requires_hash}

    -- User response tracking (for tutorial question)
    user_response = nil
}

return state
