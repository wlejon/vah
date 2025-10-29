# Workflow Execution C++ Interface

## Overview

This document specifies the C++ components needed to support workflow execution with isolated threads and library management.

## Core Components

### 1. Workflow Thread Creation

**New Function:** `create_workflow_thread`

```cpp
// In LuaThreading.cpp or new WorkflowThread.cpp

struct WorkflowThreadConfig {
    int workflow_id;
    int execution_id;
    std::vector<std::string> required_libraries;
};

int create_workflow_thread(const WorkflowThreadConfig& config);
```

**Implementation Steps:**
1. Create new `lua_State`
2. Register requested libraries based on `required_libraries`
3. Create execution record in database
4. Spawn thread with standard thread infrastructure
5. Load workflow executor into the state
6. Return thread ID

### 2. Library Registration System

**Registry Structure:**

```cpp
// In WorkflowLibrary.h

struct LibraryDefinition {
    const char* id;                    // "db", "fs", "http"
    const char* name;                  // "Database Access"
    const char* description;           // Full description
    const char* access_description;    // What it can access
    void (*register_func)(lua_State*); // Registration function
};

class WorkflowLibraryRegistry {
public:
    static void register_builtin_libraries();
    static bool register_library(const LibraryDefinition& def);
    static bool is_library_available(const std::string& id);
    static void register_requested_libraries(lua_State* L, const std::vector<std::string>& libs);

private:
    static std::unordered_map<std::string, LibraryDefinition> s_libraries;
};
```

**Builtin Libraries:**

```cpp
void WorkflowLibraryRegistry::register_builtin_libraries() {
    // Safe libraries (always available baseline)
    register_library({
        "math", "Math Operations",
        "Standard mathematical functions",
        "No data access - pure computation",
        luaopen_math
    });

    register_library({
        "string", "String Operations",
        "String manipulation and pattern matching",
        "No data access - pure computation",
        luaopen_string
    });

    register_library({
        "table", "Table Operations",
        "Table manipulation utilities",
        "No data access - pure computation",
        luaopen_table
    });

    // System access libraries
    register_library({
        "db", "Database Access",
        "Query and modify SQLite databases",
        "Read/write to execution-specific tables",
        register_workflow_db_bindings
    });

    register_library({
        "fs", "File System Access",
        "Read and write files on disk",
        "Full file system access",
        register_fs_bindings
    });

    register_library({
        "http", "Network Access",
        "Make HTTP/HTTPS requests",
        "Can communicate with external services",
        register_http_bindings
    });

    register_library({
        "ui", "User Interface",
        "Create UI windows using RmlUI",
        "Can display content and capture input",
        register_ui_bindings
    });

    register_library({
        "thread", "Threading Utilities",
        "Thread queries and utilities",
        "Limited thread management access",
        register_thread_queries
    });

    register_library({
        "event", "Event System",
        "Trigger and listen for events",
        "Can communicate with other components",
        register_event_bindings
    });
}
```

### 3. Workflow Executor (C++ Core)

**Executor Class:**

```cpp
// In WorkflowExecutor.h

class WorkflowExecutor {
public:
    WorkflowExecutor(lua_State* L, int execution_id);

    bool load_workflow(int workflow_id);
    bool execute();
    void stop();

private:
    lua_State* m_lua_state;
    int m_execution_id;
    int m_workflow_id;

    std::vector<WorkflowNode> m_nodes;
    std::vector<WorkflowConnection> m_connections;
    std::vector<WorkflowNode> m_callback_nodes;

    bool execute_topological();
    bool execute_node(const WorkflowNode& node, const NodeInputs& inputs);
    bool execute_callback_nodes(const std::string& callback_type, const nlohmann::json& context);

    void update_execution_state(const std::string& status);
    void update_node_state(int node_id, const std::string& status,
                          const nlohmann::json& outputs = {});

    bool check_control_command();
    std::vector<int> topological_sort();
};
```

**Key Methods:**

```cpp
bool WorkflowExecutor::execute() {
    // Create execution tables
    create_execution_tables(m_execution_id);

    // Execute "On Start" callbacks
    execute_callback_nodes("on_start", {{"execution_id", m_execution_id}});

    // Get execution order
    auto order = topological_sort();
    if (order.empty()) {
        update_execution_state("error");
        return false;
    }

    // Execute nodes in order
    for (int node_id : order) {
        // Check control commands (pause/stop)
        if (!check_control_command()) {
            update_execution_state("stopped");
            return false;
        }

        // Execute on_node_start callbacks
        execute_callback_nodes("on_node_start", {
            {"node_id", node_id},
            {"execution_id", m_execution_id}
        });

        // Gather inputs from connected nodes
        NodeInputs inputs = gather_node_inputs(node_id);

        // Execute node
        if (!execute_node(m_nodes[node_id], inputs)) {
            // Execute on_error callbacks
            execute_callback_nodes("on_error", {
                {"node_id", node_id},
                {"error", get_last_error()}
            });
            update_execution_state("error");
            return false;
        }

        // Execute on_node_complete callbacks
        execute_callback_nodes("on_node_complete", {
            {"node_id", node_id},
            {"outputs", get_node_outputs(node_id)}
        });

        // Small delay for visualization
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    // Execute on_complete callbacks
    execute_callback_nodes("on_complete", {
        {"execution_id", m_execution_id}
    });

    update_execution_state("completed");
    return true;
}

bool WorkflowExecutor::execute_node(const WorkflowNode& node, const NodeInputs& inputs) {
    // Get node script from config
    std::string script = node.config["script"];

    // Create environment table
    lua_newtable(m_lua_state);

    // Set inputs
    push_json_to_lua(m_lua_state, inputs);
    lua_setfield(m_lua_state, -2, "inputs");

    // Set config
    push_json_to_lua(m_lua_state, node.config);
    lua_setfield(m_lua_state, -2, "config");

    // Set context
    lua_newtable(m_lua_state);
    lua_pushinteger(m_lua_state, m_execution_id);
    lua_setfield(m_lua_state, -2, "execution_id");
    lua_setfield(m_lua_state, -2, "context");

    // Load and compile script
    if (luaL_loadstring(m_lua_state, script.c_str()) != LUA_OK) {
        const char* error = lua_tostring(m_lua_state, -1);
        log_error(node.id, error);
        return false;
    }

    // Set environment
    lua_pushvalue(m_lua_state, -2);  // Copy env table
    lua_setupvalue(m_lua_state, -2, 1);  // Set as function's env

    // Execute
    if (lua_pcall(m_lua_state, 0, 1, 0) != LUA_OK) {
        const char* error = lua_tostring(m_lua_state, -1);
        log_error(node.id, error);
        return false;
    }

    // Get outputs
    nlohmann::json outputs = lua_to_json(m_lua_state, -1);

    // Store outputs in database
    update_node_state(node.id, "completed", outputs);

    return true;
}
```

### 4. Execution API Bindings

**Lua API for Workflows:**

```cpp
// In WorkflowExecutionBindings.cpp

void register_execution_api(lua_State* L, int execution_id) {
    lua_newtable(L);

    // Store execution_id in closure
    lua_pushinteger(L, execution_id);

    // execution.set(key, value)
    lua_pushcclosure(L, lua_execution_set, 1);
    lua_setfield(L, -2, "set");

    // execution.get(key)
    lua_pushinteger(L, execution_id);
    lua_pushcclosure(L, lua_execution_get, 1);
    lua_setfield(L, -2, "get");

    // execution.log(level, message, node_id?)
    lua_pushinteger(L, execution_id);
    lua_pushcclosure(L, lua_execution_log, 1);
    lua_setfield(L, -2, "log");

    // execution.id()
    lua_pushinteger(L, execution_id);
    lua_pushcclosure(L, lua_execution_id, 1);
    lua_setfield(L, -2, "id");

    lua_setglobal(L, "execution");
}

int lua_execution_set(lua_State* L) {
    int execution_id = lua_tointeger(L, lua_upvalueindex(1));
    const char* key = luaL_checkstring(L, 1);

    // Convert Lua value to JSON
    std::string json_value = lua_to_json_string(L, 2);

    // Write to database
    std::string sql = "INSERT OR REPLACE INTO exec_" +
                     std::to_string(execution_id) +
                     "_state (key, value, updated_at) VALUES (?, ?, CURRENT_TIMESTAMP)";

    // Execute SQL...

    return 0;
}

int lua_execution_get(lua_State* L) {
    int execution_id = lua_tointeger(L, lua_upvalueindex(1));
    const char* key = luaL_checkstring(L, 1);

    // Read from database
    std::string sql = "SELECT value FROM exec_" +
                     std::to_string(execution_id) +
                     "_state WHERE key = ?";

    // Execute SQL and convert JSON to Lua value...

    return 1;
}
```

### 5. Thread Management

**Lua Binding:**

```cpp
// In LuaThreading.cpp

int lua_create_workflow_thread(lua_State* L) {
    int workflow_id = luaL_checkinteger(L, 1);

    // Load workflow config from database to get requires
    auto config = load_workflow_config(workflow_id);

    // Check if approved
    if (!is_workflow_approved(workflow_id, config.requires)) {
        lua_pushnil(L);
        lua_pushstring(L, "Workflow not approved");
        return 2;
    }

    // Create execution record
    int execution_id = create_execution_record(workflow_id);

    // Create thread config
    WorkflowThreadConfig thread_config{
        workflow_id,
        execution_id,
        config.requires
    };

    // Create thread
    int thread_id = create_workflow_thread(thread_config);

    lua_pushinteger(L, thread_id);
    lua_pushinteger(L, execution_id);
    return 2;
}
```

## Integration Points

### Command Queue Integration

Add new command type for workflow execution:

```cpp
struct ExecuteWorkflowCommand {
    int workflow_id;
    int requesting_thread_id;  // For approval dialog response
};

// In CommandProcessor.cpp
void process_execute_workflow_command(const ExecuteWorkflowCommand& cmd) {
    // Check approval
    // Create thread
    // Notify requesting thread
}
```

### Approval Dialog

The approval dialog is triggered via event system:

```cpp
// When approval needed
event_system.trigger("workflow_approval_needed", {
    {"workflow_id", workflow_id},
    {"requires", required_libraries},
    {"callback_event", "workflow_approval_response"}
});

// UI responds with
event_system.trigger("workflow_approval_response", {
    {"workflow_id", workflow_id},
    {"approved", true/false},
    {"remember", true/false}
});
```

## Error Handling

- All execution errors logged to `exec_{execution_id}_log`
- Node errors stored in `execution_nodes.error_message`
- Workflow-level errors in `workflow_executions.error_message`
- Lua script errors caught with pcall
- Missing library errors prevent thread creation

## Performance Considerations

- lua_State creation: ~1-5ms per workflow
- Library registration: Cached, minimal overhead
- Database writes: Batched where possible
- Topological sort: O(n + e) for n nodes, e edges
- Thread cleanup: Automatic via RAII

## Testing Requirements

1. Library registration/isolation
2. Workflow approval flow
3. Node script execution
4. Callback node triggering
5. Error handling and recovery
6. Concurrent workflow executions
7. Database table creation/cleanup
8. Thread termination and cleanup
