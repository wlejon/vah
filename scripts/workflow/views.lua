-- Workflow View Management
-- Handles switching between different views in the workflow application

local state = require("workflow.state")

local views = {}

-- Switch to a specific view
function views.switch_to_view(view_name)
    state.active_view = view_name
    -- Bind as an array with a single element
    datamodel.bind_table("active_view", {{view = view_name}})
end

-- ============================================
-- View Switch Handlers
-- ============================================

function views.handle_switch_to_list_view(payload)
    views.switch_to_view("list")
    -- Reload workflows when switching to list view
    -- This will be called from workflows module
    event.trigger("reload_workflows", {})
end

function views.handle_switch_to_node_editor(payload)
    views.switch_to_view("node_editor")
end

function views.handle_switch_to_workflow_view(payload)
    views.switch_to_view("workflow")
end

-- ============================================
-- Event Registration
-- ============================================

function views.register_events()
    -- Register global event handlers for view switching (from menu)
    event.register_global("workflow_switch_to_list_view", views.handle_switch_to_list_view)
    event.register_global("workflow_switch_to_node_editor", views.handle_switch_to_node_editor)
    event.register_global("workflow_switch_to_main_view", views.handle_switch_to_workflow_view)
end

return views
