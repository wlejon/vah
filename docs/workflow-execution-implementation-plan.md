# Workflow Execution Implementation Plan

## Overview

This document provides a comprehensive implementation plan for the workflow execution system, outlining the order of implementation and how components integrate.

## System Architecture Summary

```
┌─────────────────────────────────────────────────────────────┐
│                      Workflow App UI                        │
│  (RmlUI + Lua - Main Thread)                                │
│                                                             │
│  - Workflow Editor (visual graph)                           │
│  - Config UI (library selection)                            │
│  - Execution Controls (play/pause/stop)                     │
│  - History View (past executions)                           │
└─────────────────┬───────────────────────────────────────────┘
                  │ Events
                  ↓
┌─────────────────────────────────────────────────────────────┐
│                 Workflow App Backend                         │
│  (Lua Thread)                                               │
│                                                             │
│  - Handles execution requests                               │
│  - Checks approvals                                         │
│  - Polls execution state from DB                            │
│  - Binds updates to UI                                      │
└─────────────────┬───────────────────────────────────────────┘
                  │ Commands
                  ↓
┌─────────────────────────────────────────────────────────────┐
│                 Command Queue (Lock-Free)                    │
└─────────────────┬───────────────────────────────────────────┘
                  │ Processed by Main Thread
                  ↓
┌─────────────────────────────────────────────────────────────┐
│                 C++ Workflow System                          │
│  (Main Thread → Spawns Workflow Threads)                    │
│                                                             │
│  - WorkflowLibraryRegistry (library management)             │
│  - create_workflow_thread() (thread spawning)               │
│  - WorkflowExecutor (C++ orchestration)                     │
└─────────────────┬───────────────────────────────────────────┘
                  │ Spawns
                  ↓
┌─────────────────────────────────────────────────────────────┐
│              Workflow Execution Thread                       │
│  (Isolated lua_State with requested libraries)              │
│                                                             │
│  - Executes nodes in topological order                      │
│  - Runs callback nodes                                      │
│  - Writes state to DB                                       │
│  - Node scripts execute here                                │
└─────────────────┬───────────────────────────────────────────┘
                  │ Reads/Writes
                  ↓
┌─────────────────────────────────────────────────────────────┐
│                    SQLite Database                           │
│                                                             │
│  - Workflow definitions (workflows, nodes, connections)     │
│  - Execution state (workflow_executions, execution_nodes)   │
│  - Per-execution tables (exec_{id}_state, exec_{id}_log)   │
│  - Library registry                                         │
│  - Approvals                                                │
└─────────────────────────────────────────────────────────────┘
```

## Implementation Phases

### Phase 1: Database Schema & Core Data Model

**Goal:** Establish data structures for execution system

**Tasks:**

1. Create schema migration script
   - Add columns to `workflows` and `workflow_nodes`
   - Create new tables: `library_registry`, `workflow_approvals`, `workflow_executions`, etc.
   - Add indexes for performance

2. Populate library registry
   - Insert C++ library definitions
   - Include descriptions and access levels

3. Update `workflow_db.lua`
   - Add functions to load/save workflow config
   - Add functions to load/save node config
   - Add functions for execution tracking
   - Add functions for per-execution table management

**Files Modified:**
- `scripts/workflow_db.lua` (add functions)
- `data/workflow.db` (schema changes)

**Validation:**
- Can store workflow config with requires list
- Can store node config with script
- Can create execution records
- Can create/query per-execution tables

---

### Phase 2: C++ Library System

**Goal:** Implement library registry and sandboxed thread creation

**Tasks:**

1. Create `WorkflowLibrary.h/cpp`
   - `LibraryDefinition` structure
   - `WorkflowLibraryRegistry` class
   - Registration functions for each library

2. Implement library registration functions
   - `register_workflow_db_bindings()` - DB access API
   - `register_fs_bindings()` - File system API
   - `register_http_bindings()` - HTTP API
   - `register_ui_bindings()` - UI API
   - Reuse existing bindings where possible

3. Create `WorkflowThread.h/cpp`
   - `WorkflowThreadConfig` structure
   - `create_workflow_thread()` function
   - Thread spawning with library setup

4. Add execution API bindings
   - `execution.set()`, `execution.get()`
   - `execution.log()`
   - `execution.id()`, `execution.workflow_id()`

**Files Created:**
- `src/WorkflowLibrary.h`
- `src/WorkflowLibrary.cpp`
- `src/WorkflowThread.h`
- `src/WorkflowThread.cpp`
- `src/WorkflowExecutionBindings.h`
- `src/WorkflowExecutionBindings.cpp`

**Files Modified:**
- `src/LuaThreading.cpp` (add `lua_create_workflow_thread` binding)
- `src/main.cpp` or init code (call `WorkflowLibraryRegistry::register_builtin_libraries()`)

**Validation:**
- Can create thread with specific libraries
- Libraries are available in thread's lua_State
- Execution API works (set/get from DB tables)
- Other libraries are NOT available

---

### Phase 3: C++ Workflow Executor

**Goal:** Implement core execution logic in C++

**Tasks:**

1. Create `WorkflowExecutor.h/cpp`
   - `WorkflowExecutor` class
   - `load_workflow()` - Load graph from DB
   - `topological_sort()` - Determine execution order
   - `execute()` - Main execution loop
   - `execute_node()` - Run individual node script
   - `execute_callback_nodes()` - Run callback nodes

2. Implement execution state management
   - Create per-execution tables
   - Update execution status in DB
   - Update node status in DB
   - Write execution trace

3. Implement control command handling
   - Check `execution_control` table
   - Handle pause/stop/step commands

4. Node script execution
   - Load script from node config
   - Create sandboxed environment
   - Provide inputs, config, context
   - Execute with pcall
   - Capture outputs
   - Handle errors

**Files Created:**
- `src/WorkflowExecutor.h`
- `src/WorkflowExecutor.cpp`

**Files Modified:**
- `src/WorkflowThread.cpp` (integrate executor)

**Validation:**
- Can load workflow from DB
- Can execute nodes in correct order
- Node scripts receive inputs/config/context
- Outputs are stored in DB
- Execution state updates in DB
- Errors are caught and logged

---

### Phase 4: Approval System

**Goal:** Implement user approval flow for library access

**Tasks:**

1. Backend approval checking
   - Check `workflow_approvals` table
   - Compute hash of requires list
   - Trigger approval dialog if needed

2. Approval dialog UI
   - Create RML for approval dialog
   - Show library list with descriptions
   - Bind library data from registry
   - Handle user response

3. Approval persistence
   - Store approval decisions
   - Handle "Always Allow"
   - Re-prompt on requires changes

4. Denial handling
   - Don't start execution thread
   - Show error notification

**Files Modified:**
- `scripts/workflow_app.lua` (approval logic)
- `ui/workflow_app.rml` (approval dialog)

**Files Created:**
- `ui/workflow_approval_dialog.rml`

**Validation:**
- First execution shows approval dialog
- "Always Allow" persists approval
- Approved workflows run silently
- Denied workflows don't run
- Changing requires triggers re-approval

---

### Phase 5: Workflow Configuration UI

**Goal:** Allow users to configure workflows

**Tasks:**

1. Create workflow config view
   - Add menu item "Configure Workflow"
   - Create RML for config view
   - Show workflow name, description
   - Show library checkboxes
   - Load library list from registry

2. Config save/load
   - Load current workflow config
   - Save updated config to DB
   - Update `workflows.config` JSON

3. Integrate into workflow app
   - Add view switching for config
   - Handle config events

**Files Modified:**
- `ui/workflow_app.rml` (add config view)
- `scripts/workflow_app.lua` (config handlers)

**Validation:**
- Can open config for active workflow
- Library checkboxes reflect current config
- Saving updates database
- Config persists across sessions

---

### Phase 6: Node Configuration UI

**Goal:** Allow users to edit node scripts and ports

**Tasks:**

1. Create node config dialog
   - Show on double-click or right-click → Edit
   - Text inputs for label, inputs, outputs
   - Large textarea for script
   - Save/Cancel buttons

2. Script editing
   - Load node config from DB
   - Save script to node config
   - Parse inputs/outputs from CSV

3. Script validation (optional)
   - Syntax check with luaL_loadstring
   - Show compilation errors

**Files Created:**
- `ui/node_config_dialog.rml`

**Files Modified:**
- `scripts/workflow_app.lua` (node config handlers)
- `ui/workflow_editor/input.lua` (add double-click detection)

**Validation:**
- Double-clicking node opens config
- Can edit script and ports
- Changes persist to database
- Script errors are shown

---

### Phase 7: Execution Controls

**Goal:** UI for starting/stopping workflow execution

**Tasks:**

1. Add execute button
   - Add to toolbar or menu
   - Trigger execution event

2. Backend execution handler
   - Handle "execute_workflow" event
   - Check approval
   - Create workflow thread
   - Store active execution ID

3. Execution controls panel
   - Show when execution active
   - Display progress
   - Pause/Stop/Step buttons

4. Control commands
   - Write to `execution_control` table
   - Executor checks table and responds

**Files Modified:**
- `ui/workflow_app.rml` (controls panel)
- `scripts/workflow_app.lua` (execution handlers)

**Validation:**
- Execute button starts workflow
- Controls panel appears during execution
- Pause/Stop buttons work
- Execution stops gracefully

---

### Phase 8: Visual Execution Feedback

**Goal:** Show execution state in workflow editor

**Tasks:**

1. Backend state polling
   - Poll `workflow_executions` table
   - Poll `execution_nodes` table
   - Bind execution state to UI

2. Node visual feedback
   - Read execution state in render
   - Color nodes by status (pending/running/completed/error)
   - Highlight current node

3. Connection value display (optional)
   - Read node outputs from execution state
   - Display values on connections

4. Progress indicator
   - Show progress bar
   - Display completed/total nodes

**Files Modified:**
- `scripts/workflow_app.lua` (state polling)
- `ui/workflow_editor/render.lua` (visual feedback)

**Validation:**
- Nodes change color during execution
- Current node is highlighted
- Progress updates in real-time
- Completed execution shows all green
- Failed execution shows red node

---

### Phase 9: Execution History

**Goal:** View past executions and their results

**Tasks:**

1. Execution history view
   - List past executions from DB
   - Show date, status, duration
   - Filter by workflow

2. Execution details view
   - Show node results
   - Show execution log
   - Display inputs/outputs per node

3. History management
   - Delete old executions
   - Export logs
   - Cleanup old execution tables

**Files Created:**
- `ui/workflow_execution_history.rml`
- `ui/workflow_execution_details.rml`

**Files Modified:**
- `scripts/workflow_app.lua` (history handlers)
- `ui/workflow_app.rml` (history view)

**Validation:**
- Can view list of past executions
- Can drill into execution details
- Logs are readable
- Can delete old executions

---

### Phase 10: Callback Nodes

**Goal:** Support workflow lifecycle callbacks as nodes

**Tasks:**

1. Add callback node types
   - Create node types in DB
   - "On Start", "On Complete", "On Node Start", etc.

2. Callback node identification
   - Store `callback_type` in node config
   - Store `target_node_id` for node-specific callbacks

3. Executor callback support
   - Detect callback nodes
   - Execute at appropriate times
   - Provide context to callback nodes

4. UI for creating callbacks
   - Add callback nodes to node menu
   - Config dialog for target selection

**Files Modified:**
- `scripts/workflow_db.lua` (add callback node types)
- `src/WorkflowExecutor.cpp` (callback execution)
- `scripts/workflow_app.lua` (callback node handling)

**Validation:**
- Can create callback nodes
- Callbacks execute at correct time
- Callbacks receive correct context
- On Error callbacks fire on failures

---

### Phase 11: Subworkflow Support

**Goal:** Allow workflows to execute other workflows

**Tasks:**

1. Subworkflow API
   - `workflow.execute(workflow_id, inputs)`
   - `workflow.get_status(execution_id)`
   - `workflow.get_results(execution_id)`

2. Nested approval
   - Check subworkflow approval
   - Show approval dialog for sub
   - Halt parent on denial

3. Thread coordination
   - Parent waits for child
   - Results passed back to parent

**Files Modified:**
- `src/WorkflowExecutionBindings.cpp` (subworkflow API)
- `src/WorkflowExecutor.cpp` (subworkflow execution)

**Validation:**
- Can call subworkflow from node
- Subworkflow approval prompts correctly
- Parent receives subworkflow results
- Denial halts entire chain

---

### Phase 12: Polish & Optimization

**Goal:** Improve user experience and performance

**Tasks:**

1. Error messages
   - Better error reporting in UI
   - Show which node failed
   - Display error details

2. Notifications
   - Execution started/completed/failed
   - Use notification system

3. Performance
   - Batch DB writes where possible
   - Optimize state polling frequency
   - Add execution speed control

4. Documentation
   - User guide for workflow execution
   - Example workflows
   - Tutorial workflow templates

**Files Modified:**
- Various (polish throughout)

---

## Dependencies

**External:**
- SQLite (already in use)
- Lua 5.4 (already in use)
- RmlUI (already in use)

**Internal:**
- Existing thread system
- Existing event system
- Existing data binding system
- Existing database bindings

## Migration Path

For existing workflows:

1. Run schema migration on `data/workflow.db`
2. Set default config for all workflows: `{requires: ["math", "string", "table"]}`
3. Set default node scripts based on node type
4. All workflows marked as not approved (will prompt on first run)

## Rollout Strategy

1. **Developer Testing** - Phases 1-8 (core functionality)
2. **Internal Alpha** - Phases 9-10 (history and callbacks)
3. **Beta Testing** - Phase 11 (subworkflows)
4. **Public Release** - Phase 12 (polish)

## Success Metrics

- Workflows execute successfully
- Users understand approval system
- Execution feedback is clear
- Performance is acceptable (<50ms per node)
- No cross-workflow data leaks
- System remains stable under concurrent executions

## Future Enhancements

Beyond initial release:

- Marketplace for workflow templates
- Lua library addon system
- Real-time collaboration
- Cloud execution
- Workflow scheduling (cron-like)
- Debugger with breakpoints
- Visual profiling
- Undo/redo for workflow edits
