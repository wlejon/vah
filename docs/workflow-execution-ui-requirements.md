# Workflow Execution UI Requirements

## Overview

This document specifies the UI components needed in the workflow app to support workflow execution.

## New Views and Dialogs

### 1. Workflow Configuration View

**Access:** Workflow menu → "Configure Workflow" or button in workflow editor

**Purpose:** Configure workflow-level settings including library requirements

**Layout:**
```
┌─────────────────────────────────────────┐
│ Workflow Configuration: [Workflow Name] │
├─────────────────────────────────────────┤
│                                         │
│ Name: [__________________________]      │
│                                         │
│ Description:                            │
│ [________________________________]      │
│ [________________________________]      │
│                                         │
│ Required Libraries:                     │
│                                         │
│ ☐ Database Access                       │
│   Query and modify SQLite databases     │
│                                         │
│ ☐ File System Access                    │
│   Read and write files on disk          │
│                                         │
│ ☐ Network Access                        │
│   Make HTTP/HTTPS requests              │
│                                         │
│ ☐ User Interface                        │
│   Create UI windows                     │
│                                         │
│ ☐ Event System                          │
│   Trigger and listen for events         │
│                                         │
│ [Save] [Cancel]                         │
└─────────────────────────────────────────┘
```

**Data Binding:**
```lua
-- Read current workflow config
local workflow_config = data.get("workflow_config")

-- On save, emit event
emit("save_workflow_config", {
    workflow_id = active_workflow.id,
    config = {
        requires = selected_libraries,
        description = description_text
    }
})
```

### 2. Workflow Approval Dialog

**Trigger:** When executing workflow without approval

**Purpose:** Show user what the workflow will access and get consent

**Layout:**
```
┌─────────────────────────────────────────────────┐
│ Workflow Approval Required                      │
├─────────────────────────────────────────────────┤
│                                                 │
│ Workflow "[Name]" wants to run with:            │
│                                                 │
│ ┌───────────────────────────────────────────┐  │
│ │ ⚠ Database Access                         │  │
│ │   Read/write to execution-specific tables │  │
│ │                                           │  │
│ │ ⚠ File System Access                      │  │
│ │   Full file system access                 │  │
│ │                                           │  │
│ │ ⚠ Network Access                          │  │
│ │   Can communicate with external services  │  │
│ └───────────────────────────────────────────┘  │
│                                                 │
│ Do you want to allow this workflow to run?      │
│                                                 │
│ [Deny]  [Allow Once]  [Always Allow]            │
└─────────────────────────────────────────────────┘
```

**Data Binding:**
```lua
-- Triggered by event
event.register("workflow_approval_needed", function(payload)
    data.bind("approval_request", {
        workflow_id = payload.workflow_id,
        workflow_name = payload.name,
        libraries = payload.requires  -- Array of library definitions
    })
    -- Show dialog
end)

-- User response
emit("workflow_approval_response", {
    workflow_id = workflow_id,
    approved = true/false,
    remember = true/false  -- For "Always Allow"
})
```

### 3. Execution Controls Panel

**Location:** Top of workflow editor when execution is active

**Purpose:** Control running workflow execution

**Layout:**
```
┌────────────────────────────────────────────────────────────┐
│ Executing: [████████████░░░░] 75% | Node 15/20             │
│ [⏸ Pause] [⏹ Stop] [⏭ Step] | Time: 2.3s | Status: Running │
└────────────────────────────────────────────────────────────┘
```

**Data Binding:**
```lua
-- Poll execution state
local exec_state = data.get("execution_state")
-- {
--   execution_id = 123,
--   status = "running",
--   current_node_id = 15,
--   total_nodes = 20,
--   completed_nodes = 14,
--   elapsed_time = 2.3
-- }
```

**Events:**
```lua
emit("pause_execution", {execution_id = exec_id})
emit("stop_execution", {execution_id = exec_id})
emit("step_execution", {execution_id = exec_id})
```

### 4. Node Configuration Dialog

**Trigger:** Double-click node or right-click → "Edit Node"

**Purpose:** Edit node-specific configuration and script

**Layout:**
```
┌─────────────────────────────────────────────────────────┐
│ Configure Node: [Node Label]                            │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ Label: [__________________________]                     │
│                                                         │
│ Inputs (comma-separated):                               │
│ [A, B, Threshold]                                       │
│                                                         │
│ Outputs (comma-separated):                              │
│ [Result, Count]                                         │
│                                                         │
│ Script:                                                 │
│ ┌───────────────────────────────────────────────────┐  │
│ │ local result = inputs.A + inputs.B                │  │
│ │                                                   │  │
│ │ if result > inputs.Threshold then                 │  │
│ │     execution.log("info", "Threshold exceeded")   │  │
│ │ end                                               │  │
│ │                                                   │  │
│ │ return {                                          │  │
│ │     Result = result,                              │  │
│ │     Count = 1                                     │  │
│ │ }                                                 │  │
│ │                                                   │  │
│ │                                                   │  │
│ │                                                   │  │
│ └───────────────────────────────────────────────────┘  │
│                                                         │
│ [Test Script] [Save] [Cancel]                           │
│                                                         │
│ Errors:                                                 │
│ [No errors]                                             │
└─────────────────────────────────────────────────────────┘
```

**Data Binding:**
```lua
-- Load node config
local node = get_selected_node()
data.bind("node_config_edit", {
    node_id = node.id,
    label = node.label or node.name,
    inputs = table.concat(node.config.inputs or {}, ", "),
    outputs = table.concat(node.config.outputs or {}, ", "),
    script = node.config.script or ""
})

-- Save
emit("save_node_config", {
    workflow_id = active_workflow.id,
    node_id = node.id,
    config = {
        label = label,
        inputs = split_csv(inputs_text),
        outputs = split_csv(outputs_text),
        script = script_text
    }
})
```

### 5. Execution History View

**Access:** Workflow menu → "Execution History" or tab in workflow app

**Purpose:** View past executions and their results

**Layout:**
```
┌─────────────────────────────────────────────────────────────┐
│ Execution History: [Workflow Name]                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ ┌───────────────────────────────────────────────────────┐  │
│ │ Date       │ Status    │ Duration │ Nodes │ Actions   │  │
│ ├───────────────────────────────────────────────────────┤  │
│ │ 2025-01-15 │ Completed │ 2.3s     │ 20/20 │ [View]    │  │
│ │ 2025-01-15 │ Error     │ 1.1s     │ 12/20 │ [View]    │  │
│ │ 2025-01-14 │ Completed │ 3.5s     │ 20/20 │ [View]    │  │
│ │ 2025-01-14 │ Stopped   │ 0.8s     │ 5/20  │ [View]    │  │
│ └───────────────────────────────────────────────────────┘  │
│                                                             │
│ [Load More] [Clear History]                                 │
└─────────────────────────────────────────────────────────────┘
```

**Data Binding:**
```lua
-- Load execution history
local history = data.get("execution_history")
-- Array of:
-- {
--   execution_id = 123,
--   started_at = "2025-01-15 10:30:00",
--   status = "completed",
--   duration = 2.3,
--   total_nodes = 20,
--   completed_nodes = 20
-- }

-- View execution details
emit("view_execution", {execution_id = exec_id})
```

### 6. Execution Details View

**Trigger:** Click "View" in execution history

**Purpose:** See detailed results and logs from past execution

**Layout:**
```
┌─────────────────────────────────────────────────────────────┐
│ Execution Details: [Workflow Name] - [Date/Time]           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ Status: Completed | Duration: 2.3s | Nodes: 20/20          │
│                                                             │
│ ┌─ Node Results ────────────────────────────────────────┐  │
│ │ Node          │ Status    │ Inputs    │ Outputs      │  │
│ ├──────────────────────────────────────────────────────┤  │
│ │ Number        │ Completed │ -         │ Value: 42    │  │
│ │ Math          │ Completed │ A:42 B:10 │ Result: 52   │  │
│ │ Compare       │ Completed │ A:52 B:50 │ Greater: 1   │  │
│ └──────────────────────────────────────────────────────┘  │
│                                                             │
│ ┌─ Execution Log ───────────────────────────────────────┐  │
│ │ 10:30:01 [INFO] Workflow started                      │  │
│ │ 10:30:01 [INFO] Processing batch 1 of 5               │  │
│ │ 10:30:02 [INFO] Processing batch 2 of 5               │  │
│ │ 10:30:02 [WARN] Using default value for field X       │  │
│ │ 10:30:03 [INFO] Workflow completed                    │  │
│ └──────────────────────────────────────────────────────┘  │
│                                                             │
│ [Export Log] [Replay] [Close]                               │
└─────────────────────────────────────────────────────────────┘
```

**Data Binding:**
```lua
-- Load execution details
local details = data.get("execution_details")
-- {
--   execution_id = 123,
--   status = "completed",
--   nodes = [...],  -- Array of node results
--   log = [...]     -- Array of log entries
-- }
```

## Visual Feedback in Workflow Editor

### Node Status Colors

During execution, nodes should be color-coded:

```lua
-- In render.lua
function render.draw_node(node, execution_state)
    local border_color = colors.node_border
    local border_width = 2

    if execution_state then
        local node_state = execution_state.nodes[node.id]
        if node_state then
            if node_state.status == "running" then
                border_color = colors.yellow
                border_width = 4
            elseif node_state.status == "completed" then
                border_color = colors.green
                border_width = 3
            elseif node_state.status == "error" then
                border_color = colors.red
                border_width = 4
            elseif node_state.status == "pending" then
                border_color = colors.gray
                border_width = 2
            end
        end
    end

    -- Draw with colored border
    nvg.strokeColor(nvg_ctx, border_color)
    nvg.strokeWidth(nvg_ctx, border_width)
    -- ... rest of drawing
end
```

### Connection Value Display

Show data flowing through connections:

```lua
function render.draw_connections(nvg_ctx, editor, execution_state)
    for _, conn in ipairs(editor.connections) do
        -- Draw connection line
        -- ...

        -- Show value if available
        if execution_state then
            local from_node_state = execution_state.nodes[conn.from_node]
            if from_node_state and from_node_state.outputs then
                local value = from_node_state.outputs[output_port_name]
                if value ~= nil then
                    -- Draw value label at connection midpoint
                    local label = tostring(value)
                    if type(value) == "table" then
                        label = "{...}"
                    end
                    nvg.text(nvg_ctx, mid_x, mid_y, label)
                end
            end
        end
    end
end
```

### Progress Indicator

Show overall progress:

```lua
-- In workflow editor overlay
if execution_state and execution_state.status == "running" then
    local progress = execution_state.completed_nodes / execution_state.total_nodes

    -- Draw progress bar
    nvg.beginPath(nvg_ctx)
    nvg.rect(nvg_ctx, x + 10, y + h - 30, (w - 20) * progress, 20)
    nvg.fillColor(nvg_ctx, colors.progress)
    nvg.fill(nvg_ctx)
end
```

## Menu Items

Add to workflow menu:

```lua
{
    item_id = "configure_workflow",
    label = "Configure Workflow",
    action = "show_workflow_config"
},
{
    item_id = "execute_workflow",
    label = "Execute Workflow",
    action = "execute_workflow"
},
{
    item_id = "execution_history",
    label = "Execution History",
    action = "show_execution_history"
}
```

## Toolbar Buttons

Add to workflow editor toolbar:

```
[▶ Execute] [⚙ Configure] [📊 History]
```

## Notifications

### Execution Started
```lua
event.trigger_global("notification_info", {
    title = "Workflow Executing",
    message = "Started execution of workflow: " .. workflow_name
})
```

### Execution Completed
```lua
event.trigger_global("notification_success", {
    title = "Workflow Completed",
    message = "Workflow completed successfully in " .. duration .. "s"
})
```

### Execution Failed
```lua
event.trigger_global("notification_error", {
    title = "Workflow Failed",
    message = "Workflow failed at node " .. node_name .. ": " .. error
})
```

### Approval Needed
Use interactive notification for approval dialog.

## Backend Event Handlers

New event handlers needed in `workflow_app.lua`:

```lua
-- Configuration
event.register("show_workflow_config", handle_show_config)
event.register("save_workflow_config", handle_save_config)

-- Execution control
event.register("execute_workflow", handle_execute_workflow)
event.register("pause_execution", handle_pause_execution)
event.register("stop_execution", handle_stop_execution)
event.register("step_execution", handle_step_execution)

-- History
event.register("show_execution_history", handle_show_history)
event.register("view_execution", handle_view_execution)
event.register("delete_execution", handle_delete_execution)

-- Node editing
event.register("edit_node", handle_edit_node)
event.register("save_node_config", handle_save_node_config)
event.register("test_node_script", handle_test_script)

-- Approval
event.register("workflow_approval_response", handle_approval_response)
```

## Backend Polling

Backend thread should poll execution tables for updates:

```lua
function update(dt)
    -- Poll for execution updates every 100ms
    time_since_poll = time_since_poll + dt
    if time_since_poll > 0.1 then
        update_execution_state()
        time_since_poll = 0
    end
end

function update_execution_state()
    if not active_execution_id then return end

    -- Query execution state from DB
    local state = db.query([[
        SELECT status, current_node_id
        FROM workflow_executions
        WHERE id = ?
    ]], active_execution_id)

    local node_states = db.query([[
        SELECT node_id, status, inputs, outputs
        FROM execution_nodes
        WHERE execution_id = ?
    ]], active_execution_id)

    -- Bind to UI
    data.bind("execution_state", {
        execution_id = active_execution_id,
        status = state[1].status,
        current_node_id = state[1].current_node_id,
        nodes = build_node_states(node_states)
    })
end
```

## Implementation Priority

1. **Phase 1: Basic Execution**
   - Execute button
   - Execution controls
   - Visual feedback (node colors)

2. **Phase 2: Configuration**
   - Workflow config view
   - Approval dialog
   - Node config dialog

3. **Phase 3: History & Details**
   - Execution history view
   - Execution details view
   - Log viewer

4. **Phase 4: Polish**
   - Connection value display
   - Progress indicators
   - Notifications
