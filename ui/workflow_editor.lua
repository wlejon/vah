-- Workflow Node Editor
-- This is now a thin wrapper around the modular workflow editor
-- All actual logic has been split into workflow_editor/ modules

local editor_module = require("workflow_editor.init")

-- Export all functions that RmlUI expects as global functions
render_workflow = editor_module.render_workflow
handle_workflow_click = editor_module.handle_workflow_click
handle_workflow_move = editor_module.handle_workflow_move
handle_workflow_scroll = editor_module.handle_workflow_scroll
handle_workflow_key = editor_module.handle_workflow_key

-- Also return the module for programmatic access
return editor_module
