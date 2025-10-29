# Workflow Execution System Design

## Overview

This document outlines the design for adding execution capabilities to the workflow app. The design leverages the existing lock-free, command-queue architecture and maintains the principle of keeping application logic in Lua.

## Architecture Fit

### Thread Model

**Execution Thread (New Lua Thread):**
- Dedicated thread for workflow execution
- Evaluates nodes in topological order
- Computes data flow through the graph
- Emits execution state updates via `data.bind()`
- Runs independently from UI/rendering

**Main Thread (Existing):**
- Renders execution visualization
- Receives execution state via `data.get()`
- Displays node states, values, and trace
- Handles execution control events (play/pause/step)

**Backend Thread (Existing):**
- Routes execution control events
- Manages workflow/execution lifecycle
- Persists execution results if needed

### Communication Flow

```
User clicks "Execute"
  → UI emits event
  → Backend receives event
  → Backend starts execution thread
  → Execution thread loads graph
  → Execution thread evaluates nodes
  → Execution thread binds state updates
  → UI receives updates via data.get()
  → UI re-renders with execution visualization
```

**No locks, no mutexes, no busy-waits** - just lock-free queues and data binding.

---

## Node Behavior System

### Behavior Registry

Each node type has an associated behavior function. Store behaviors in a Lua module that maps node type names to functions:

```lua
-- scripts/workflow_behaviors.lua
local behaviors = {}

behaviors["Number"] = function(inputs, node)
    -- Nodes store their configuration (e.g., the number value)
    return { Value = node.config.number or 0 }
end

behaviors["Math"] = function(inputs, node)
    local a = inputs.A or 0
    local b = inputs.B or 0
    local op = node.config.operation or "add"

    local result
    if op == "add" then result = a + b
    elseif op == "subtract" then result = a - b
    elseif op == "multiply" then result = a * b
    elseif op == "divide" then result = b ~= 0 and (a / b) or 0
    end

    return { Result = result }
end

behaviors["Compare"] = function(inputs, node)
    local a = inputs.A or 0
    local b = inputs.B or 0
    return {
        Greater = a > b and 1 or 0,
        Equal = a == b and 1 or 0,
        Less = a < b and 1 or 0
    }
end

behaviors["Branch"] = function(inputs, node)
    local condition = inputs.Condition or 0
    if condition ~= 0 then
        return { Result = inputs.True }
    else
        return { Result = inputs.False }
    end
end

behaviors["Print"] = function(inputs, node)
    local value = inputs.Value
    -- Send to log or store for display
    print("Node " .. node.id .. " Print: " .. tostring(value))
    return {} -- No outputs
end

behaviors["Time"] = function(inputs, node)
    -- Access execution context for timing
    return {
        Seconds = node.context.elapsed_time,
        Delta = node.context.delta_time
    }
end

behaviors["Event"] = function(inputs, node)
    -- Trigger on input presence
    if inputs.Trigger ~= nil then
        return { ["On Event"] = inputs.Trigger }
    end
    return {}
end

return behaviors
```

### Node Configuration

Add a `config` field to nodes for behavior parameters:

```lua
{
    id = 1,
    type_index = 1,
    name = "Number",
    config = { number = 42 }  -- Node-specific configuration
}
```

Store configuration in database as JSON:
```sql
ALTER TABLE workflow_nodes ADD COLUMN config TEXT; -- JSON blob
```

---

## Execution State Model

### State Structure

```lua
execution_state = {
    workflow_id = 123,
    status = "idle",  -- idle|running|paused|completed|error
    current_node_id = nil,

    -- Per-node execution state
    nodes = {
        [node_id] = {
            status = "pending",  -- pending|ready|running|completed|error|skipped
            input_values = { [port_name] = value },
            output_values = { [port_name] = value },
            error_message = nil,
            execution_order = nil  -- Number indicating when it ran
        }
    },

    -- Execution trace (ordered list of node IDs)
    trace = {1, 3, 5, 2, ...},

    -- Timing
    start_time = os.time(),
    end_time = nil,
    elapsed_time = 0
}
```

### State Updates

Bind execution state to data store:
```lua
data.bind("execution_state", execution_state)
```

UI subscribes via:
```lua
local state = data.get("execution_state")
```

---

## Execution Engine

### Executor Module

Create `scripts/workflow_executor.lua`:

```lua
local executor = {}
local behaviors = require("workflow_behaviors")

-- Topological sort for execution order
function executor.topological_sort(nodes, connections)
    -- Build adjacency list
    local graph = {}
    local in_degree = {}

    for _, node in ipairs(nodes) do
        graph[node.id] = {}
        in_degree[node.id] = 0
    end

    for _, conn in ipairs(connections) do
        table.insert(graph[conn.from_node], conn.to_node)
        in_degree[conn.to_node] = in_degree[conn.to_node] + 1
    end

    -- Kahn's algorithm
    local queue = {}
    for node_id, degree in pairs(in_degree) do
        if degree == 0 then
            table.insert(queue, node_id)
        end
    end

    local sorted = {}
    while #queue > 0 do
        local node_id = table.remove(queue, 1)
        table.insert(sorted, node_id)

        for _, neighbor in ipairs(graph[node_id]) do
            in_degree[neighbor] = in_degree[neighbor] - 1
            if in_degree[neighbor] == 0 then
                table.insert(queue, neighbor)
            end
        end
    end

    -- Check for cycles
    if #sorted ~= #nodes then
        return nil, "Graph contains cycles"
    end

    return sorted
end

-- Execute workflow
function executor.execute(workflow_id, nodes, connections, node_types)
    local state = {
        workflow_id = workflow_id,
        status = "running",
        current_node_id = nil,
        nodes = {},
        trace = {},
        start_time = os.time(),
        elapsed_time = 0
    }

    -- Initialize node states
    for _, node in ipairs(nodes) do
        state.nodes[node.id] = {
            status = "pending",
            input_values = {},
            output_values = {},
            error_message = nil,
            execution_order = nil
        }
    end

    -- Bind initial state
    data.bind("execution_state", state)

    -- Get execution order
    local order, err = executor.topological_sort(nodes, connections)
    if not order then
        state.status = "error"
        state.error_message = err
        data.bind("execution_state", state)
        return false, err
    end

    -- Build lookup maps
    local node_map = {}
    for _, node in ipairs(nodes) do
        node_map[node.id] = node
    end

    -- Build connection map: [to_node][to_port] = {from_node, from_port}
    local input_map = {}
    for _, conn in ipairs(connections) do
        if not input_map[conn.to_node] then
            input_map[conn.to_node] = {}
        end
        input_map[conn.to_node][conn.to_port] = {
            from_node = conn.from_node,
            from_port = conn.from_port
        }
    end

    -- Execute nodes in order
    for i, node_id in ipairs(order) do
        local node = node_map[node_id]
        local node_state = state.nodes[node_id]

        node_state.status = "running"
        node_state.execution_order = i
        state.current_node_id = node_id
        table.insert(state.trace, node_id)
        data.bind("execution_state", state)

        -- Small delay for visualization
        thread.sleep(0.1)

        -- Gather inputs from connected nodes
        local inputs = {}
        if input_map[node_id] then
            for port_idx, source in pairs(input_map[node_id]) do
                local source_node_state = state.nodes[source.from_node]
                local source_node = node_map[source.from_node]
                local port_name = source_node.outputs[source.from_port]
                local value = source_node_state.output_values[port_name]

                -- Map to input port name
                local input_port_name = node.inputs[port_idx]
                inputs[input_port_name] = value
            end
        end

        node_state.input_values = inputs

        -- Get behavior function
        local behavior = behaviors[node.name]
        if not behavior then
            node_state.status = "error"
            node_state.error_message = "No behavior defined for node type: " .. node.name
            state.status = "error"
            data.bind("execution_state", state)
            return false, node_state.error_message
        end

        -- Execute behavior
        local success, result = pcall(behavior, inputs, node)
        if not success then
            node_state.status = "error"
            node_state.error_message = result
            state.status = "error"
            data.bind("execution_state", state)
            return false, result
        end

        -- Store outputs
        node_state.output_values = result or {}
        node_state.status = "completed"
        data.bind("execution_state", state)
    end

    -- Execution complete
    state.status = "completed"
    state.current_node_id = nil
    state.end_time = os.time()
    state.elapsed_time = state.end_time - state.start_time
    data.bind("execution_state", state)

    return true
end

return executor
```

### Execution Thread

Add to `scripts/workflow_app.lua`:

```lua
local executor = require("workflow_executor")

-- Event handler: start execution
events.on("execute_workflow", function(workflow_id)
    -- Load workflow
    local workflow_data = db:load_workflow(workflow_id)
    if not workflow_data then
        print("Failed to load workflow: " .. workflow_id)
        return
    end

    local nodes = workflow_data.nodes
    local connections = workflow_data.connections
    local node_types = db:get_node_types()

    -- Create execution thread
    local exec_thread = thread.create(function()
        local success, err = executor.execute(workflow_id, nodes, connections, node_types)
        if not success then
            print("Execution failed: " .. err)
        end
    end)
end)

-- Event handlers for execution control
events.on("pause_execution", function()
    -- Set flag to pause (implementation depends on execution loop)
end)

events.on("stop_execution", function()
    -- Kill execution thread
end)

events.on("step_execution", function()
    -- Execute one node then pause
end)
```

---

## UI Visualization

### Execution Controls

Add to `workflow_app.rml`:

```html
<div id="execution-controls">
    <button onclick="emit('execute_workflow', active_workflow.id)">Execute</button>
    <button onclick="emit('pause_execution')">Pause</button>
    <button onclick="emit('stop_execution')">Stop</button>
    <button onclick="emit('step_execution')">Step</button>
    <button onclick="emit('reset_execution')">Reset</button>
</div>

<div id="execution-status">
    <span>Status: {{execution_state.status}}</span>
    <span>Node: {{execution_state.current_node_id}}</span>
</div>
```

### Visual Feedback

Enhance `workflow_editor/render.lua` to show execution state:

```lua
function render.draw_node(node, state, execution_state)
    local node_exec_state = execution_state and execution_state.nodes[node.id]

    -- Change node appearance based on execution status
    local border_color
    if node_exec_state then
        if node_exec_state.status == "running" then
            border_color = colors.yellow -- Highlight current
        elseif node_exec_state.status == "completed" then
            border_color = colors.green -- Completed
        elseif node_exec_state.status == "error" then
            border_color = colors.red -- Error
        end
    end

    -- Draw border if executing
    if border_color then
        nvg.stroke_color(border_color)
        nvg.stroke_width(3)
        nvg.begin_path()
        nvg.rounded_rect(node.x, node.y, node_width, node_height, node_rounding)
        nvg.stroke()
    end

    -- ... rest of node rendering
end

function render.draw_connection_values(conn, execution_state)
    if not execution_state then return end

    local from_state = execution_state.nodes[conn.from_node]
    if not from_state then return end

    local from_node = find_node(conn.from_node)
    local port_name = from_node.outputs[conn.from_port]
    local value = from_state.output_values[port_name]

    if value ~= nil then
        -- Draw value label on connection midpoint
        local mid_x, mid_y = calculate_connection_midpoint(conn)
        nvg.font_size(12)
        nvg.fill_color(colors.white)
        nvg.text(mid_x, mid_y, tostring(value))
    end
end
```

---

## Database Schema Changes

### Node Configuration Storage

```sql
-- Add config column to workflow_nodes
ALTER TABLE workflow_nodes ADD COLUMN config TEXT; -- JSON blob

-- Example data
INSERT INTO workflow_nodes (workflow_id, node_id, node_type_id, x, y, label, config)
VALUES (1, 1, 1, 100, 100, 'My Number', '{"number": 42}');
```

### Execution History (Optional)

If you want to persist execution results:

```sql
CREATE TABLE IF NOT EXISTS workflow_executions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    workflow_id INTEGER NOT NULL,
    start_time INTEGER,
    end_time INTEGER,
    status TEXT,
    trace TEXT, -- JSON array of node IDs
    FOREIGN KEY (workflow_id) REFERENCES workflows(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS execution_node_results (
    execution_id INTEGER NOT NULL,
    node_id INTEGER NOT NULL,
    input_values TEXT, -- JSON
    output_values TEXT, -- JSON
    error_message TEXT,
    FOREIGN KEY (execution_id) REFERENCES workflow_executions(id) ON DELETE CASCADE
);
```

---

## Implementation Steps

1. **Add node behaviors module** (`scripts/workflow_behaviors.lua`)
2. **Add execution engine** (`scripts/workflow_executor.lua`)
3. **Extend database schema** (add `config` column)
4. **Add execution event handlers** (in `scripts/workflow_app.lua`)
5. **Add execution controls to UI** (in `workflow_app.rml`)
6. **Enhance rendering** (show execution state in `render.lua`)
7. **Add node configuration UI** (edit dialog for node-specific settings)

---

## Scalability Considerations

### Large Graphs
- Current design evaluates nodes sequentially
- For graphs with 1000+ nodes, consider:
  - Chunked execution (batch of N nodes, then yield)
  - Incremental state updates (don't bind on every node)
  - Background thread pool for parallel execution of independent branches

### Long-Running Workflows
- Add pause/resume capability
- Save execution checkpoints to database
- Allow resuming from last checkpoint

### Real-Time Execution
- For workflows that need to run continuously (e.g., 30hz update loop):
  - Use different execution mode
  - Skip visualization updates
  - Only bind final results

---

## Future Enhancements

1. **Breakpoints** - Pause execution at specific nodes
2. **Watch values** - Monitor specific node outputs
3. **Execution history** - Replay past executions
4. **Conditional execution** - Only execute branches based on conditions
5. **Subgraphs** - Nest workflows as nodes
6. **External triggers** - Start execution from external events
7. **Async nodes** - Nodes that yield and resume (e.g., HTTP requests)

---

## Conclusion

This design fits naturally into the existing vah architecture:

- **Lock-free**: Uses data binding for state updates, no mutexes
- **Multi-threaded**: Execution in dedicated Lua thread
- **Lua-based**: All logic in Lua (behaviors, executor)
- **Event-driven**: Uses existing event system for control
- **Visualizable**: Execution state flows to UI for rendering

The execution system is modular, testable, and extensible while maintaining the architectural principles of the vah platform.
