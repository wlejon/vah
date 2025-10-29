# Workflow Execution Architecture

## Overview

Workflows execute in isolated threads with their own lua_State, using a library request system for controlled access to system capabilities. Communication between execution threads and the UI happens through database tables.

## Core Principles

1. **Thread Isolation** - Each workflow execution runs in a dedicated thread with its own lua_State
2. **Explicit Permissions** - Workflows declare required libraries; users approve access
3. **DB Communication** - Execution state persists to database tables; UI reads for progress
4. **C++ Orchestration** - Core execution logic in C++; user customization via Lua callbacks
5. **Visual Callbacks** - Workflow lifecycle hooks represented as special nodes in the graph

## Architecture Components

### Execution Thread Lifecycle

```
User clicks "Execute"
  ↓
Backend checks workflow.config.requires
  ↓
Check workflow_approvals table
  ↓
If not approved: Show approval dialog → User decides
  ↓
If denied: Halt (nothing persisted)
  ↓
If approved: Spawn workflow thread
  ↓
C++ creates lua_State with requested libraries
  ↓
C++ creates execution record in database
  ↓
C++ loads workflow graph and node scripts
  ↓
Execute callback nodes: "On Start"
  ↓
C++ executes nodes in topological order
  ↓  (for each node:)
  |  Execute callback nodes: "On Node Start"
  |  Execute node script
  |  Write outputs to execution tables
  |  Execute callback nodes: "On Node Complete"
  ↓
Execute callback nodes: "On Complete" or "On Error"
  ↓
Cleanup and destroy lua_State
```

### Subworkflow Execution

When a node executes a subworkflow:
1. Parent workflow pauses
2. System checks subworkflow's approval status
3. If not approved: Prompt user (entire chain halts on deny)
4. If approved: Spawn new thread for subworkflow
5. Subworkflow runs with its own requires and lua_State
6. Parent resumes after subworkflow completes

### Communication Model

**Workflow Thread → UI:**
- Workflow writes to `exec_{execution_id}_*` tables using provided API
- Backend thread polls these tables
- Backend binds updates to RmlUI via `data.bind()`

**UI → Workflow Thread:**
- User actions (pause/stop) update control table
- Workflow thread polls control table
- Or workflow thread exposes control via commands

## Library Request System

### Purpose
- Security by default (no access unless explicitly requested)
- User awareness (clear what workflow can do)
- Future marketplace support (missing libraries show download link)

### Library Types

**C++ Libraries** (hardcoded in application):
- `math` - Math operations (safe)
- `string` - String manipulation (safe)
- `table` - Table operations (safe)
- `db` - Database access (read/write to execution tables)
- `fs` - File system access (caution: full access)
- `http` - Network requests (caution: external access)
- `ui` - Spawn UI windows using RmlUI
- `thread` - Thread utilities (sleep, queries)
- `event` - Event system access

**Lua Libraries** (installed via addons):
- Stored in database with descriptions
- Registered dynamically when workflow requests them
- Must provide same quality documentation as C++ libs

### Approval Flow

**First Execution:**
1. Show dialog: "Workflow wants [libraries]"
2. Display library descriptions and access levels
3. Options: "Allow Once", "Always Allow", "Deny"
4. "Always Allow" persists approval with hash of requires list

**Subsequent Executions:**
- If approved: Run silently
- If requires list changes: Prompt again
- If denied previously: Prompt again (no persistent deny)

**Imported Workflows:**
- Import creates new workflow record
- Must go through approval again (untrusted by default)

## Node Types

### Regular Nodes
- Contain custom Lua scripts
- Define dynamic inputs and outputs
- Execute in topological order
- Store configuration in `workflow_nodes.config`

### Callback Nodes
- Special node types for workflow lifecycle hooks
- Execute outside main graph topology
- Receive data from execution context
- Types:
  - **On Start** - Before any nodes execute
  - **On Complete** - After all nodes complete successfully
  - **On Node Start** - Before specific node executes
  - **On Node Complete** - After specific node executes
  - **On Error** - If any node fails

## Data Persistence

### Execution Tables

Each workflow execution gets dedicated tables:
```
exec_{execution_id}_state     - Current execution state
exec_{execution_id}_nodes      - Per-node status and values
exec_{execution_id}_custom     - User-defined data from scripts
```

### API for Workflows

Workflows access execution data via provided API:
```lua
-- Write state
execution.set("key", value)

-- Read state
local value = execution.get("key")

-- Get execution context
local exec_id = execution.id()
local workflow_id = execution.workflow_id()
```

Backend reads same tables to update UI.

## Security Boundaries

1. **Isolated lua_State** - Each execution has separate Lua environment
2. **Explicit library access** - Only requested libraries available
3. **DB table scoping** - Workflows write to execution-specific tables
4. **No cross-workflow access** - Workflows cannot read other workflows' data
5. **User approval required** - Cannot run without user consent

## Scalability Considerations

- **State creation overhead** - Nominal, acceptable per-execution
- **Long-running workflows** - Persist state to DB, can survive crashes
- **Concurrent executions** - Each in own thread, no contention
- **Resource limits** - Future: add CPU/memory limits per thread

## Future Enhancements

- Marketplace for Lua libraries
- Workflow templates with pre-approved requires
- Execution history and replay
- Breakpoints and debugging
- Real-time collaboration (shared workflow editing)
