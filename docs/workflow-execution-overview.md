# Workflow Execution System - Overview

## What Is This?

A visual workflow execution system where users create node-based graphs, write custom Lua scripts for each node, and execute workflows in isolated threads with explicit library permissions.

## Key Design Decisions

### 1. Every Node Has Its Own Script

Unlike traditional node-based systems with hardcoded behaviors, **each node instance** contains a custom Lua script. Node types are templates, not behaviors.

```lua
-- Node instance config
{
    script = [[
        local result = inputs.A + inputs.B
        return { Result = result }
    ]],
    inputs = {"A", "B"},
    outputs = {"Result"}
}
```

### 2. Execution in Isolated Threads

Each workflow execution spawns a dedicated thread with its own `lua_State`. This provides:
- Memory isolation
- API isolation (only requested libraries available)
- Crash isolation
- Clean termination

### 3. Explicit Library Permissions

Workflows declare required libraries. Users must approve before execution.

```json
{
  "requires": ["db", "fs", "http"]
}
```

First run → approval dialog → user decides → remembered for future runs.

### 4. Database for Communication

Workflows write to execution-specific DB tables. Backend polls tables and updates UI via data binding.

```
Workflow Thread → exec_{id}_state table → Backend polls → UI updates
```

No complex thread synchronization needed.

### 5. C++ Orchestration + Lua Scripts

- C++ handles thread creation, topological sort, node execution order
- Lua provides customization via node scripts and callbacks
- Balance between control and flexibility

### 6. Callbacks as Visual Nodes

Workflow lifecycle hooks (on_start, on_complete, on_error) are represented as special nodes in the graph. Makes everything visual and composable.

## Architecture at a Glance

```
User clicks Execute
    ↓
Check approval → Prompt if needed → User approves
    ↓
Spawn isolated thread with lua_State + requested libraries
    ↓
C++ loads workflow graph from DB
    ↓
C++ executes nodes in topological order
    ↓  (for each node)
    |  Load node script from config
    |  Create sandboxed environment
    |  Execute script with inputs
    |  Store outputs to DB
    ↓
Workflow writes state to exec_{id}_* tables
    ↓
Backend polls tables → Binds to UI
    ↓
UI shows execution progress visually
    ↓
Execution completes → Thread destroyed
```

## What Gets Built

### Database Schema
- Workflow config (libraries, description)
- Node config (script, inputs, outputs)
- Library registry (C++ and Lua libraries)
- Execution tracking (status, results, logs)
- Approval persistence

### C++ Components
- Library registry system
- Sandboxed thread creation
- Workflow executor (topological execution)
- Node script execution engine
- Execution API bindings

### Lua Components
- Workflow config UI
- Node config dialog
- Approval dialog
- Execution controls
- History viewer
- Visual feedback in editor

### APIs
- `execution.set/get(key, value)` - Persistent state
- `execution.log(level, message)` - Logging
- `execution.id()` - Context info
- Library APIs: db, fs, http, ui, thread, event

## User Workflows

### Creating a Workflow

1. Open workflow app
2. Add nodes to canvas
3. Double-click node → edit script and ports
4. Connect nodes
5. Workflow → Configure → Select required libraries
6. Save

### Executing a Workflow

1. Click Execute button
2. If first time → Approval dialog appears
3. Review libraries → Click "Always Allow"
4. Execution starts → Nodes light up in sequence
5. View progress in real-time
6. Execution completes → See results

### Sharing a Workflow

1. Export workflow (future: export to file)
2. Share file with others
3. They import → Creates new workflow in their DB
4. On first execute → Approval dialog shows what it needs
5. They review → Approve → Runs

## Security Model

**Not sandboxing malicious code**, but:
- Explicit consent (user knows what workflow can do)
- Isolation (can't affect other workflows)
- Transparency (clear library descriptions)
- Audit trail (logs all actions)

Users share workflows in trusted contexts. System prevents accidental conflicts and makes capabilities explicit.

## Example Node Scripts

### Number Source
```lua
return { Value = config.number or 0 }
```

### Math Operation
```lua
local op = config.operation or "add"
local result
if op == "add" then result = inputs.A + inputs.B
elseif op == "multiply" then result = inputs.A * inputs.B
end
return { Result = result }
```

### Database Query
```lua
local results = db.query(
    "SELECT * FROM exec_" .. execution.id() .. "_custom WHERE key = ?",
    inputs.Key
)
return { Results = results }
```

### HTTP Request
```lua
local response = http.get(config.url)
if response.status ~= 200 then
    error("Request failed: " .. response.status)
end
return { Data = response.body }
```

### Callback: On Error
```lua
-- Config: callback_type = "on_error"
execution.log("error", "Workflow failed at node " .. context.error_node_id)

event.trigger_global("notification_error", {
    title = "Workflow Failed",
    message = context.error_message
})

return {}
```

## Implementation Phases

1. **Database** - Schema changes, migrations
2. **C++ Library System** - Registry, thread creation
3. **C++ Executor** - Topological execution
4. **Approval System** - User consent flow
5. **Config UI** - Workflow configuration
6. **Node Editor** - Script editing
7. **Execution Controls** - Play/pause/stop
8. **Visual Feedback** - Node colors, progress
9. **History** - Past executions
10. **Callbacks** - Lifecycle hooks
11. **Subworkflows** - Nested execution
12. **Polish** - UX improvements

## Documents

Detailed specifications in:

- **workflow-execution-architecture.md** - High-level architecture and principles
- **workflow-execution-schema.md** - Complete database schema
- **workflow-execution-cpp-interface.md** - C++ implementation details
- **workflow-execution-lua-api.md** - Lua API for workflows
- **workflow-execution-ui-requirements.md** - UI components needed
- **workflow-execution-implementation-plan.md** - Step-by-step implementation

## Questions & Answers

**Q: Why not use hardcoded node behaviors?**
A: Every user's needs are different. Custom scripts provide maximum flexibility without requiring C++ changes.

**Q: Why isolated threads instead of shared state?**
A: Simplicity. No mutex complexity, no deadlocks, no cross-workflow conflicts. Each execution is independent.

**Q: Why database for communication?**
A: It's persistent, queryable, and fits the architecture. Backend polls tables → binds to UI. Clean and simple.

**Q: Why explicit library requests?**
A: Transparency and future-proofing. Users know what workflows do. Marketplace can show library requirements. No surprises.

**Q: Can workflows run in parallel?**
A: Yes! Each execution is a separate thread. They write to separate DB tables. No conflicts.

**Q: What about performance?**
A: Creating lua_State is ~1-5ms. Node execution is microseconds. DB writes are fast. Totally acceptable for most workflows.

**Q: What if a workflow crashes?**
A: Thread-isolated. Other workflows unaffected. Execution state in DB shows what happened. Can resume manually if needed.

**Q: How do I debug a workflow?**
A: Execution logs show everything. Execution history shows all node inputs/outputs. Visual feedback shows progress. Future: breakpoints and stepping.

## Next Steps

1. Review all design documents
2. Discuss any concerns or changes
3. Begin Phase 1 implementation (database schema)
4. Iterate through phases
5. Test thoroughly
6. Ship!

## Success Criteria

- ✅ Workflows execute successfully
- ✅ Approval system is clear and non-intrusive
- ✅ Visual feedback makes execution obvious
- ✅ Node scripting is powerful and flexible
- ✅ System is stable and performant
- ✅ Users can share workflows easily
- ✅ Error handling is robust
- ✅ Architecture is maintainable

---

**This is the foundation for Vah's workflow system.** Once implemented, users can create powerful automation, data processing pipelines, and visual scripts entirely within the application.
