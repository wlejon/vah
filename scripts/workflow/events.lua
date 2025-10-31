-- Workflow Event Registration
-- Coordinates event registration from all workflow modules

local views = require("workflow.views")
local workflows = require("workflow.workflows")
local node_types = require("workflow.node_types")
local execution = require("workflow.execution")
local approval = require("workflow.approval")
local config = require("workflow.config")
local history = require("workflow.history")

local events = {}

-- ============================================
-- Menu Registration
-- ============================================

local function register_workflow_menu()
    event.trigger_global("menu_register", {
        menu_id = "workflow",
        label = "Workflow",
        position = 100,
        items = {
            {
                item_id = "workflow_list",
                label = "Workflows",
                action = "workflow_switch_to_list_view"
            },
            {
                item_id = "new_workflow_menu",
                label = "New Workflow",
                action = "new_workflow"
            },
            {
                item_id = "node_types",
                label = "Configure Node Types",
                action = "workflow_switch_to_node_editor"
            },
            {
                item_id = "configure_workflow_menu",
                label = "Configure Workflow",
                action = "show_workflow_config"
            },
            {
                item_id = "execute_workflow_menu",
                label = "Execute Workflow",
                action = "execute_workflow"
            },
            {
                item_id = "execution_history_menu",
                label = "Execution History",
                action = "show_execution_history"
            }
        }
    })
end

-- ============================================
-- Texteditor Commands
-- ============================================

local function register_texteditor_commands()
    event.register("command_copy", function(payload)
        if payload.element_tag == "texteditor" then
            ui.texteditor_copy(payload.element_id)
        end
    end)

    event.register("command_paste", function(payload)
        if payload.element_tag == "texteditor" then
            ui.texteditor_paste(payload.element_id)
        end
    end)

    event.register("command_cut", function(payload)
        if payload.element_tag == "texteditor" then
            ui.texteditor_cut(payload.element_id)
        end
    end)

    event.register("command_select_all", function(payload)
        if payload.element_tag == "texteditor" then
            ui.texteditor_select_all(payload.element_id)
        end
    end)

    event.register("command_undo", function(payload)
        if payload.element_tag == "texteditor" then
            ui.texteditor_undo(payload.element_id)
        end
    end)

    event.register("command_redo", function(payload)
        if payload.element_tag == "texteditor" then
            ui.texteditor_redo(payload.element_id)
        end
    end)
end

-- ============================================
-- Master Event Registration
-- ============================================

function events.register_all()
    -- Register events from all modules
    views.register_events()
    workflows.register_events()
    node_types.register_events()
    execution.register_events()
    approval.register_events()
    config.register_events()
    history.register_events()

    -- Register texteditor commands
    register_texteditor_commands()

    -- Register workflow menu
    register_workflow_menu()
end

function events.unregister_all()
    -- Unregister workflow menu
    event.trigger_global("menu_unregister", {menu_id = "workflow"})
end

return events
