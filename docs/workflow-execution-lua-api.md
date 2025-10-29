# Workflow Execution Lua API

## Overview

This document specifies the Lua APIs available to workflow scripts, including node scripts and callback nodes.

## Execution Context API

### execution.set(key, value)

Store data in the execution's state table.

```lua
execution.set("current_step", 5)
execution.set("results", {total = 100, processed = 42})
```

**Parameters:**
- `key` (string): Key to store value under
- `value` (any): Value to store (will be JSON-encoded)

**Notes:**
- Stored in `exec_{execution_id}_state` table
- Persists across script executions
- Can be read by UI or other nodes

### execution.get(key)

Retrieve data from the execution's state table.

```lua
local step = execution.get("current_step")
local results = execution.get("results")
```

**Parameters:**
- `key` (string): Key to retrieve

**Returns:**
- Value associated with key, or `nil` if not found

### execution.log(level, message, node_id?)

Write to execution log.

```lua
execution.log("info", "Processing started")
execution.log("warning", "Missing optional field", 42)
execution.log("error", "Failed to connect to database")
```

**Parameters:**
- `level` (string): "debug", "info", "warning", "error"
- `message` (string): Log message
- `node_id` (number, optional): Associate log with specific node

**Notes:**
- Stored in `exec_{execution_id}_log` table
- Visible in execution details UI

### execution.id()

Get current execution ID.

```lua
local exec_id = execution.id()
print("Running execution:", exec_id)
```

**Returns:**
- (number): Current execution ID

### execution.workflow_id()

Get the workflow ID being executed.

```lua
local wf_id = execution.workflow_id()
```

**Returns:**
- (number): Workflow ID

## Node Script Environment

Each node script runs with the following environment:

### inputs

Table containing input values from connected nodes.

```lua
-- For a Math node with inputs A and B
local sum = inputs.A + inputs.B
local product = inputs.A * inputs.B
```

**Structure:**
```lua
inputs = {
    ["Port Name"] = value,
    ...
}
```

### config

Table containing node's configuration.

```lua
-- Access node-specific settings
local operation = config.operation or "add"
local precision = config.precision or 2
```

**Structure:**
```lua
config = {
    script = "...",
    inputs = {...},
    outputs = {...},
    -- User-defined config fields
    operation = "add",
    ...
}
```

### context

Table containing execution context information.

```lua
local exec_id = context.execution_id
local workflow_id = context.workflow_id
local node_id = context.node_id
```

**Structure:**
```lua
context = {
    execution_id = number,
    workflow_id = number,
    node_id = number
}
```

### Return Value

Node scripts must return a table of outputs:

```lua
-- Single output
return { Result = 42 }

-- Multiple outputs
return {
    Sum = a + b,
    Product = a * b,
    Average = (a + b) / 2
}

-- No outputs
return {}
```

**Requirements:**
- Must return a table
- Keys match output port names
- Values can be any JSON-serializable type

## Callback Node Environment

Callback nodes receive additional context based on their type:

### On Start Callback

```lua
-- Available in environment
context = {
    execution_id = number,
    workflow_id = number
}

-- Example usage
execution.log("info", "Workflow started")
execution.set("start_time", os.time())

return {}
```

### On Complete Callback

```lua
-- Available in environment
context = {
    execution_id = number,
    workflow_id = number
}

inputs = {
    -- Final results from workflow
}

-- Example usage
local start_time = execution.get("start_time")
local duration = os.time() - start_time
execution.log("info", "Workflow completed in " .. duration .. " seconds")

return {}
```

### On Node Start Callback

```lua
-- Available in environment
context = {
    execution_id = number,
    workflow_id = number,
    node_id = number  -- The node about to execute
}

-- Example usage
execution.log("debug", "Starting node " .. context.node_id)

return {}
```

### On Node Complete Callback

```lua
-- Available in environment
context = {
    execution_id = number,
    workflow_id = number,
    node_id = number  -- The node that completed
}

inputs = {
    -- Outputs from the completed node
    Result = value,
    ...
}

-- Example usage
execution.log("debug", "Node " .. context.node_id .. " produced: " .. inputs.Result)

return {}
```

### On Error Callback

```lua
-- Available in environment
context = {
    execution_id = number,
    workflow_id = number,
    error_node_id = number,
    error_message = string
}

-- Example usage
execution.log("error", "Node " .. context.error_node_id .. " failed: " .. context.error_message)

-- Optionally cleanup or notify
if config.send_notification then
    event.trigger_global("notification_error", {
        title = "Workflow Failed",
        message = context.error_message
    })
end

return {}
```

## Standard Library Access

Based on workflow's `requires` configuration:

### math (always available)

```lua
local result = math.sqrt(16)
local angle = math.sin(math.pi / 2)
```

Standard Lua math library.

### string (always available)

```lua
local upper = string.upper("hello")
local parts = string.split("a,b,c", ",")
```

Standard Lua string library.

### table (always available)

```lua
table.insert(list, value)
local sorted = table.sort(list)
```

Standard Lua table library.

### db (requires: "db")

```lua
-- Query execution tables
local results = db.query("SELECT * FROM exec_" .. execution.id() .. "_custom WHERE key = ?", "mykey")

-- Write to custom table
db.execute("INSERT INTO exec_" .. execution.id() .. "_custom (key, value) VALUES (?, ?)",
    "mykey", "myvalue")
```

**Restrictions:**
- Can only access `exec_{execution_id}_*` tables
- Read-only access to workflow definition tables
- No access to other workflows' execution tables

### fs (requires: "fs")

```lua
-- Read file
local content = fs.read_file("data/input.txt")

-- Write file
fs.write_file("data/output.txt", "result data")

-- List directory
local files = fs.list_dir("data/")

-- Check existence
if fs.exists("data/config.json") then
    -- ...
end
```

**Caution:** Full file system access with current user permissions.

### http (requires: "http")

```lua
-- GET request
local response = http.get("https://api.example.com/data")

-- POST request
local response = http.post("https://api.example.com/submit", {
    body = '{"key": "value"}',
    headers = {
        ["Content-Type"] = "application/json"
    }
})

-- Response structure
response = {
    status = 200,
    body = "...",
    headers = {...}
}
```

**Caution:** Can send data to external services.

### ui (requires: "ui")

```lua
-- Load UI document
local doc_id = ui.load_document("ui/workflow_result.rml", false, "workflow_result_" .. execution.id())

-- Bind data to UI
data.bind("workflow_result", {
    execution_id = execution.id(),
    results = get_results()
})
```

UI runs in separate thread, uses standard data binding system.

### thread (requires: "thread")

```lua
-- Sleep (always safe)
thread.sleep(1.0)  -- seconds

-- Query thread info
local threads = thread.list()
local info = thread.get_info(thread_id)
```

Limited to queries, no thread spawning from workflow scripts.

### event (requires: "event")

```lua
-- Trigger events
event.trigger_global("custom_event", {
    execution_id = execution.id(),
    data = "value"
})

-- Register listeners (within this execution only)
event.register("response_event", function(payload)
    execution.set("response", payload)
end)
```

Can communicate with other application components.

## Subworkflow Execution

If a node needs to execute another workflow:

```lua
-- Request subworkflow execution
local sub_exec_id = workflow.execute(subworkflow_id, {
    input_data = inputs.Data
})

-- Wait for completion
while true do
    local status = workflow.get_status(sub_exec_id)
    if status == "completed" then
        break
    elseif status == "error" then
        error("Subworkflow failed")
    end
    thread.sleep(0.1)
end

-- Get results
local results = workflow.get_results(sub_exec_id)

return { Result = results.FinalValue }
```

**Notes:**
- Subworkflow approval happens automatically
- Denied subworkflow halts parent workflow
- Each subworkflow runs in own thread

## Error Handling

### Recommended Pattern

```lua
-- Node script
local success, result = pcall(function()
    -- Potentially failing operation
    return risky_operation(inputs.Data)
end)

if not success then
    execution.log("error", "Operation failed: " .. tostring(result))
    return { Error = result }
end

return { Result = result }
```

### Automatic Error Handling

If a node script throws an error:
1. Error is caught by executor
2. Stored in `execution_nodes.error_message`
3. On Error callback nodes are triggered
4. Execution stops

## Best Practices

### 1. Validate Inputs

```lua
if not inputs.Required then
    error("Missing required input: Required")
end

local value = inputs.Optional or default_value
```

### 2. Use Execution State for Progress

```lua
execution.set("progress", {
    current = i,
    total = total,
    percent = (i / total) * 100
})
```

### 3. Log Important Events

```lua
execution.log("info", "Processing batch " .. i .. " of " .. total)
execution.log("warning", "Using default value for missing field")
execution.log("error", "Failed to process item: " .. error_msg)
```

### 4. Clean Return Values

```lua
-- Good: clear output names
return {
    ProcessedCount = count,
    FailedItems = failed,
    Summary = summary
}

-- Avoid: unclear names
return {
    result = something,
    data = other_thing
}
```

### 5. Handle Long Operations

```lua
for i = 1, large_count do
    -- Do work

    -- Periodically update progress
    if i % 100 == 0 then
        execution.set("progress", i / large_count)
    end
end
```

## Security Notes

- Scripts run in isolated lua_State
- Only requested libraries available
- No access to global application state
- Database access limited to execution tables
- File system access unrestricted (user permission required)
- Network access unrestricted (user permission required)

## Example Scripts

### Simple Math Node

```lua
local result = inputs.A + inputs.B
return { Sum = result }
```

### Data Processing Node

```lua
local data = inputs.Data
local results = {}

for _, item in ipairs(data) do
    if item.value > config.threshold then
        table.insert(results, item)
    end
end

execution.log("info", "Filtered " .. #results .. " items from " .. #data)

return { Filtered = results }
```

### Database Query Node

```lua
local query = config.query or "SELECT * FROM data"
local results = db.query("SELECT * FROM exec_" .. execution.id() .. "_custom WHERE " .. inputs.Filter)

return { Results = results }
```

### HTTP Request Node

```lua
local url = config.url or inputs.URL
local response = http.get(url)

if response.status ~= 200 then
    execution.log("error", "HTTP request failed: " .. response.status)
    return { Error = "Request failed" }
end

return {
    Data = response.body,
    Status = response.status
}
```
