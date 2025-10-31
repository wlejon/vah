-- Workflow Approval System
-- Handles approval dialogs for library permissions

local state = require("workflow.state")
local workflow_db = require("workflow.db")

local approval = {}

-- ============================================
-- Approval System Functions
-- ============================================

-- Show approval dialog
local function show_approval_dialog(payload)
    -- Store pending approval info
    state.pending_approval = {
        workflow_id = payload.workflow_id,
        requires_hash = payload.requires_hash or "empty"
    }

    -- Bind approval request data
    datamodel.bind_table("approval_request", {{
        workflow_id = payload.workflow_id,
        workflow_name = payload.workflow_name or "Unknown"
    }})

    -- Bind libraries separately for nested data-for
    datamodel.bind_table("approval_libraries", payload.requires or {})

    -- Load and show approval dialog if not already loaded
    if not state.approval_dialog_doc then
        state.approval_dialog_doc = ui.load_document("ui/apps/workflow/workflow_approval_dialog.rml", false, "workflow_approval")
        print("Approval dialog loaded")
    else
        ui.show_document("workflow_approval")
    end
end

-- Hide approval dialog
local function hide_approval_dialog()
    if state.approval_dialog_doc then
        ui.close_document("workflow_approval")
        state.approval_dialog_doc = nil
    end
    state.pending_approval = nil
end

-- Handle user's approval decision
local function handle_workflow_approval_response(payload)
    if not payload.workflow_id then
        print("ERROR: No workflow_id in approval response payload")
        hide_approval_dialog()
        return
    end

    local workflow_id = payload.workflow_id
    local approved = payload.approved or false
    local remember = payload.remember or false

    -- Get requires_hash from pending_approval or payload
    local requires_hash = "empty"
    if state.pending_approval and state.pending_approval.workflow_id == workflow_id then
        requires_hash = state.pending_approval.requires_hash
    elseif payload.requires_hash then
        requires_hash = payload.requires_hash
    end

    -- Hide the dialog first
    hide_approval_dialog()

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

    -- Proceed with execution (call back via event to avoid circular dependency)
    event.trigger("execute_workflow", {workflow_id = workflow_id})
end

-- ============================================
-- Event Registration
-- ============================================

function approval.register_events()
    -- Register approval system event handlers
    event.register_global("workflow_approval_needed", show_approval_dialog)
    event.register("workflow_approval_response", handle_workflow_approval_response)
end

return approval
