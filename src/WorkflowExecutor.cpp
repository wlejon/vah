#include "WorkflowExecutor.h"
#include "Logger.h"
#include <sqlite3.h>
#include <algorithm>
#include <stack>
#include <set>
#include <thread>
#include <chrono>

using json = nlohmann::json;

// Helper to open database connection
static sqlite3* OpenDatabase() {
    sqlite3* db = nullptr;
    int rc = sqlite3_open("data/workflow.db", &db);
    if (rc != SQLITE_OK) {
        if (db) {
            LOG_ERROR("Failed to open database: {}", sqlite3_errmsg(db));
            sqlite3_close_v2(db);
        }
        return nullptr;
    }
    return db;
}

// Helper to execute SQL and bind parameters
static bool ExecuteSQL(sqlite3* db, const std::string& sql,
                      const std::vector<std::string>& params = {}) {
    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr);
    if (rc != SQLITE_OK) {
        LOG_ERROR("SQL prepare error: {}", sqlite3_errmsg(db));
        return false;
    }

    // Bind parameters
    for (size_t i = 0; i < params.size(); i++) {
        sqlite3_bind_text(stmt, i + 1, params[i].c_str(), -1, SQLITE_TRANSIENT);
    }

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE && rc != SQLITE_ROW) {
        LOG_ERROR("SQL execution error: {}", sqlite3_errmsg(db));
        return false;
    }

    return true;
}

WorkflowExecutor::WorkflowExecutor(lua_State* L, int execution_id)
    : m_lua_state(L)
    , m_execution_id(execution_id)
    , m_workflow_id(0)
    , m_stop_requested(false)
{
}

bool WorkflowExecutor::LoadWorkflow(int workflow_id) {
    m_workflow_id = workflow_id;

    sqlite3* db = OpenDatabase();
    if (!db) {
        m_last_error = "Failed to open database";
        return false;
    }

    // Load workflow nodes
    std::string sql = R"(
        SELECT node_id, node_type_id, x, y, config
        FROM workflow_nodes
        WHERE workflow_id = ?
        ORDER BY node_id
    )";

    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr);
    if (rc != SQLITE_OK) {
        m_last_error = "Failed to prepare node query: " + std::string(sqlite3_errmsg(db));
        sqlite3_close_v2(db);
        return false;
    }

    sqlite3_bind_int(stmt, 1, workflow_id);

    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        WorkflowNode node;
        node.id = sqlite3_column_int(stmt, 0);
        node.type_id = sqlite3_column_int(stmt, 1);
        node.x = sqlite3_column_double(stmt, 2);
        node.y = sqlite3_column_double(stmt, 3);

        // Parse config JSON
        const char* config_text = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 4));
        if (config_text) {
            try {
                node.config = json::parse(config_text);
            } catch (const json::exception& e) {
                LOG_WARN("Failed to parse node {} config: {}", node.id, e.what());
                node.config = json::object();
            }
        } else {
            node.config = json::object();
        }

        // Check if this is a callback node
        if (node.config.contains("callback_type") && node.config["callback_type"].is_string()) {
            m_callback_nodes.push_back(node);
        } else {
            m_nodes.push_back(node);
        }
    }

    sqlite3_finalize(stmt);

    // Load connections
    sql = R"(
        SELECT from_node, from_port, to_node, to_port
        FROM workflow_connections
        WHERE workflow_id = ?
    )";

    rc = sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr);
    if (rc != SQLITE_OK) {
        m_last_error = "Failed to prepare connection query: " + std::string(sqlite3_errmsg(db));
        sqlite3_close_v2(db);
        return false;
    }

    sqlite3_bind_int(stmt, 1, workflow_id);

    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        WorkflowConnection conn;
        conn.from_node = sqlite3_column_int(stmt, 0);
        conn.from_port = sqlite3_column_int(stmt, 1);
        conn.to_node = sqlite3_column_int(stmt, 2);
        conn.to_port = sqlite3_column_int(stmt, 3);
        m_connections.push_back(conn);
    }

    sqlite3_finalize(stmt);
    sqlite3_close_v2(db);

    LOG_INFO("Loaded workflow {}: {} nodes, {} connections, {} callbacks",
             workflow_id, m_nodes.size(), m_connections.size(), m_callback_nodes.size());

    return true;
}

std::vector<int> WorkflowExecutor::TopologicalSort() {
    if (m_nodes.empty()) {
        return {};
    }

    // Build adjacency list and in-degree map
    std::map<int, std::vector<int>> adj;
    std::map<int, int> in_degree;

    // Initialize all nodes with in-degree 0
    for (const auto& node : m_nodes) {
        in_degree[node.id] = 0;
        adj[node.id] = {};
    }

    // Build graph from connections
    for (const auto& conn : m_connections) {
        // Only consider connections between regular nodes (not callbacks)
        bool from_is_regular = false;
        bool to_is_regular = false;

        for (const auto& node : m_nodes) {
            if (node.id == conn.from_node) from_is_regular = true;
            if (node.id == conn.to_node) to_is_regular = true;
        }

        if (from_is_regular && to_is_regular) {
            adj[conn.from_node].push_back(conn.to_node);
            in_degree[conn.to_node]++;
        }
    }

    // Kahn's algorithm for topological sort
    std::vector<int> result;
    std::vector<int> queue;

    // Find all nodes with in-degree 0
    for (const auto& pair : in_degree) {
        if (pair.second == 0) {
            queue.push_back(pair.first);
        }
    }

    while (!queue.empty()) {
        int node_id = queue.back();
        queue.pop_back();
        result.push_back(node_id);

        // Reduce in-degree for all neighbors
        for (int neighbor : adj[node_id]) {
            in_degree[neighbor]--;
            if (in_degree[neighbor] == 0) {
                queue.push_back(neighbor);
            }
        }
    }

    // Check for cycles
    if (result.size() != m_nodes.size()) {
        LOG_ERROR("Workflow has a cycle - cannot execute");
        return {};
    }

    return result;
}

nlohmann::json WorkflowExecutor::GatherNodeInputs(int node_id) {
    json inputs = json::object();

    // Find all connections that feed into this node
    for (const auto& conn : m_connections) {
        if (conn.to_node == node_id) {
            // Look up the output from the source node
            auto it = m_node_outputs.find(conn.from_node);
            if (it != m_node_outputs.end()) {
                const json& outputs = it->second;

                // Map port index to port name (we need to look this up from node type)
                // For now, use simple port naming convention
                // TODO: Look up actual port names from node_type_ports table
                std::string port_name = "input_" + std::to_string(conn.to_port);

                // Try to find the output value by port index
                if (outputs.is_object()) {
                    // Assume outputs are stored with port names or indices
                    std::string output_key = "output_" + std::to_string(conn.from_port);
                    if (outputs.contains(output_key)) {
                        inputs[port_name] = outputs[output_key];
                    }
                }
            }
        }
    }

    return inputs;
}

void WorkflowExecutor::PushJsonToLua(const json& j) {
    if (j.is_null()) {
        lua_pushnil(m_lua_state);
    } else if (j.is_boolean()) {
        lua_pushboolean(m_lua_state, j.get<bool>());
    } else if (j.is_number_integer()) {
        lua_pushinteger(m_lua_state, j.get<int64_t>());
    } else if (j.is_number_float()) {
        lua_pushnumber(m_lua_state, j.get<double>());
    } else if (j.is_string()) {
        lua_pushstring(m_lua_state, j.get<std::string>().c_str());
    } else if (j.is_array()) {
        lua_newtable(m_lua_state);
        for (size_t i = 0; i < j.size(); i++) {
            lua_pushinteger(m_lua_state, i + 1);  // Lua arrays are 1-indexed
            PushJsonToLua(j[i]);
            lua_settable(m_lua_state, -3);
        }
    } else if (j.is_object()) {
        lua_newtable(m_lua_state);
        for (auto it = j.begin(); it != j.end(); ++it) {
            lua_pushstring(m_lua_state, it.key().c_str());
            PushJsonToLua(it.value());
            lua_settable(m_lua_state, -3);
        }
    }
}

nlohmann::json WorkflowExecutor::LuaToJson(int index) {
    int type = lua_type(m_lua_state, index);

    switch (type) {
        case LUA_TNIL:
            return nullptr;
        case LUA_TBOOLEAN:
            return lua_toboolean(m_lua_state, index) != 0;
        case LUA_TNUMBER:
            if (lua_isinteger(m_lua_state, index)) {
                return lua_tointeger(m_lua_state, index);
            } else {
                return lua_tonumber(m_lua_state, index);
            }
        case LUA_TSTRING:
            return std::string(lua_tostring(m_lua_state, index));
        case LUA_TTABLE: {
            // Check if it's an array or object
            lua_pushnil(m_lua_state);
            bool is_array = true;
            int max_index = 0;
            int count = 0;

            // First pass: check if all keys are sequential integers
            while (lua_next(m_lua_state, index < 0 ? index - 1 : index) != 0) {
                count++;
                if (!lua_isinteger(m_lua_state, -2)) {
                    is_array = false;
                    lua_pop(m_lua_state, 1);
                    break;
                }
                int key = lua_tointeger(m_lua_state, -2);
                if (key > max_index) max_index = key;
                lua_pop(m_lua_state, 1);
            }

            if (is_array && count == max_index && max_index > 0) {
                // It's an array
                json arr = json::array();
                for (int i = 1; i <= max_index; i++) {
                    lua_geti(m_lua_state, index, i);
                    arr.push_back(LuaToJson(-1));
                    lua_pop(m_lua_state, 1);
                }
                return arr;
            } else {
                // It's an object
                json obj = json::object();
                lua_pushnil(m_lua_state);
                while (lua_next(m_lua_state, index < 0 ? index - 1 : index) != 0) {
                    // Get key as string
                    std::string key;
                    if (lua_isstring(m_lua_state, -2)) {
                        key = lua_tostring(m_lua_state, -2);
                    } else if (lua_isnumber(m_lua_state, -2)) {
                        key = std::to_string(lua_tointeger(m_lua_state, -2));
                    }

                    if (!key.empty()) {
                        obj[key] = LuaToJson(-1);
                    }
                    lua_pop(m_lua_state, 1);
                }
                return obj;
            }
        }
        default:
            return nullptr;
    }
}

bool WorkflowExecutor::ExecuteNode(int node_id, const json& inputs) {
    // Find the node
    const WorkflowNode* node = nullptr;
    for (const auto& n : m_nodes) {
        if (n.id == node_id) {
            node = &n;
            break;
        }
    }

    if (!node) {
        m_last_error = "Node not found: " + std::to_string(node_id);
        return false;
    }

    // Get script from config
    if (!node->config.contains("script") || !node->config["script"].is_string()) {
        m_last_error = "Node " + std::to_string(node_id) + " has no script";
        return false;
    }

    std::string script = node->config["script"].get<std::string>();

    // Create environment table
    lua_newtable(m_lua_state);  // env
    int env_index = lua_gettop(m_lua_state);

    // Set inputs
    lua_pushstring(m_lua_state, "inputs");
    PushJsonToLua(inputs);
    lua_settable(m_lua_state, env_index);

    // Set config
    lua_pushstring(m_lua_state, "config");
    PushJsonToLua(node->config);
    lua_settable(m_lua_state, env_index);

    // Set context
    lua_pushstring(m_lua_state, "context");
    lua_newtable(m_lua_state);
    {
        lua_pushstring(m_lua_state, "execution_id");
        lua_pushinteger(m_lua_state, m_execution_id);
        lua_settable(m_lua_state, -3);

        lua_pushstring(m_lua_state, "workflow_id");
        lua_pushinteger(m_lua_state, m_workflow_id);
        lua_settable(m_lua_state, -3);

        lua_pushstring(m_lua_state, "node_id");
        lua_pushinteger(m_lua_state, node_id);
        lua_settable(m_lua_state, -3);
    }
    lua_settable(m_lua_state, env_index);

    // Copy global execution API into environment
    lua_getglobal(m_lua_state, "execution");
    if (!lua_isnil(m_lua_state, -1)) {
        lua_setfield(m_lua_state, env_index, "execution");
    } else {
        lua_pop(m_lua_state, 1);
    }

    // Set environment metatable to access globals
    lua_newtable(m_lua_state);  // metatable
    lua_pushstring(m_lua_state, "__index");
    lua_pushglobaltable(m_lua_state);
    lua_settable(m_lua_state, -3);
    lua_setmetatable(m_lua_state, env_index);

    // Load script
    if (luaL_loadstring(m_lua_state, script.c_str()) != LUA_OK) {
        m_last_error = "Script load error: " + std::string(lua_tostring(m_lua_state, -1));
        LOG_ERROR("Node {} script load error: {}", node_id, m_last_error);
        lua_pop(m_lua_state, 2);  // error, env
        UpdateNodeStatus(node_id, "error", json::object(), m_last_error);
        return false;
    }

    // Set environment for the loaded function
    lua_pushvalue(m_lua_state, env_index);  // Push env
    lua_setupvalue(m_lua_state, -2, 1);     // Set as first upvalue

    // Execute script
    if (lua_pcall(m_lua_state, 0, 1, 0) != LUA_OK) {
        m_last_error = "Script execution error: " + std::string(lua_tostring(m_lua_state, -1));
        LOG_ERROR("Node {} execution error: {}", node_id, m_last_error);
        lua_pop(m_lua_state, 2);  // error, env
        UpdateNodeStatus(node_id, "error", json::object(), m_last_error);
        return false;
    }

    // Get outputs (return value should be a table)
    json outputs = LuaToJson(-1);
    lua_pop(m_lua_state, 2);  // return value, env

    // Store outputs
    m_node_outputs[node_id] = outputs;

    // Update node status
    UpdateNodeStatus(node_id, "completed", outputs);

    // Add trace entry
    sqlite3* db = OpenDatabase();
    if (db) {
        std::string sql = R"(
            INSERT INTO execution_trace (execution_id, sequence, node_id)
            SELECT ?, COALESCE(MAX(sequence), 0) + 1, ?
            FROM execution_trace WHERE execution_id = ?
        )";

        sqlite3_stmt* stmt = nullptr;
        if (sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr) == SQLITE_OK) {
            sqlite3_bind_int(stmt, 1, m_execution_id);
            sqlite3_bind_int(stmt, 2, node_id);
            sqlite3_bind_int(stmt, 3, m_execution_id);
            sqlite3_step(stmt);
            sqlite3_finalize(stmt);
        }
        sqlite3_close_v2(db);
    }

    LOG_INFO("Node {} executed successfully", node_id);
    return true;
}

bool WorkflowExecutor::ExecuteCallbackNodes(const std::string& callback_type, const json& context) {
    for (const auto& node : m_callback_nodes) {
        if (node.config.contains("callback_type") &&
            node.config["callback_type"].get<std::string>() == callback_type) {

            LOG_INFO("Executing callback node {} ({})", node.id, callback_type);

            // Similar to ExecuteNode but with context as inputs
            if (!node.config.contains("script") || !node.config["script"].is_string()) {
                LOG_WARN("Callback node {} has no script", node.id);
                continue;
            }

            std::string script = node.config["script"].get<std::string>();

            // Create environment
            lua_newtable(m_lua_state);
            int env_index = lua_gettop(m_lua_state);

            // Set context as inputs for callback nodes
            lua_pushstring(m_lua_state, "inputs");
            PushJsonToLua(context);
            lua_settable(m_lua_state, env_index);

            lua_pushstring(m_lua_state, "config");
            PushJsonToLua(node.config);
            lua_settable(m_lua_state, env_index);

            lua_pushstring(m_lua_state, "context");
            PushJsonToLua(context);
            lua_settable(m_lua_state, env_index);

            // Copy execution API
            lua_getglobal(m_lua_state, "execution");
            if (!lua_isnil(m_lua_state, -1)) {
                lua_setfield(m_lua_state, env_index, "execution");
            } else {
                lua_pop(m_lua_state, 1);
            }

            // Set metatable for globals access
            lua_newtable(m_lua_state);
            lua_pushstring(m_lua_state, "__index");
            lua_pushglobaltable(m_lua_state);
            lua_settable(m_lua_state, -3);
            lua_setmetatable(m_lua_state, env_index);

            // Load and execute
            if (luaL_loadstring(m_lua_state, script.c_str()) != LUA_OK) {
                LOG_ERROR("Callback node {} load error: {}", node.id, lua_tostring(m_lua_state, -1));
                lua_pop(m_lua_state, 2);
                continue;
            }

            lua_pushvalue(m_lua_state, env_index);
            lua_setupvalue(m_lua_state, -2, 1);

            if (lua_pcall(m_lua_state, 0, 0, 0) != LUA_OK) {
                LOG_ERROR("Callback node {} execution error: {}", node.id, lua_tostring(m_lua_state, -1));
                lua_pop(m_lua_state, 2);
                continue;
            }

            lua_pop(m_lua_state, 1);  // env
        }
    }

    return true;
}

bool WorkflowExecutor::CheckControlCommand() {
    if (m_stop_requested) {
        return false;
    }

    sqlite3* db = OpenDatabase();
    if (!db) {
        return true;  // Continue if we can't check
    }

    std::string sql = "SELECT command FROM execution_control WHERE execution_id = ?";
    sqlite3_stmt* stmt = nullptr;

    if (sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr) != SQLITE_OK) {
        sqlite3_close_v2(db);
        return true;
    }

    sqlite3_bind_int(stmt, 1, m_execution_id);

    std::string command;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        const char* cmd = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 0));
        if (cmd) {
            command = cmd;
        }
    }

    sqlite3_finalize(stmt);
    sqlite3_close_v2(db);

    if (command == "stop") {
        LOG_INFO("Stop command received for execution {}", m_execution_id);
        return false;
    } else if (command == "pause") {
        LOG_INFO("Pause command received for execution {}", m_execution_id);
        // Wait until command changes
        while (command == "pause" && !m_stop_requested) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));

            // Check command again
            db = OpenDatabase();
            if (!db) break;

            if (sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr) == SQLITE_OK) {
                sqlite3_bind_int(stmt, 1, m_execution_id);
                if (sqlite3_step(stmt) == SQLITE_ROW) {
                    const char* cmd = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 0));
                    command = cmd ? cmd : "";
                }
                sqlite3_finalize(stmt);
            }
            sqlite3_close_v2(db);
        }

        if (command == "stop") {
            return false;
        }
    }

    return true;
}

void WorkflowExecutor::UpdateExecutionStatus(const std::string& status, const std::string& error) {
    sqlite3* db = OpenDatabase();
    if (!db) {
        LOG_ERROR("Failed to update execution status - cannot open database");
        return;
    }

    std::string sql;
    sqlite3_stmt* stmt = nullptr;

    if (error.empty()) {
        sql = R"(
            UPDATE workflow_executions
            SET status = ?, ended_at = CURRENT_TIMESTAMP
            WHERE id = ?
        )";
    } else {
        sql = R"(
            UPDATE workflow_executions
            SET status = ?, error_message = ?, ended_at = CURRENT_TIMESTAMP
            WHERE id = ?
        )";
    }

    if (sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, status.c_str(), -1, SQLITE_TRANSIENT);
        if (error.empty()) {
            sqlite3_bind_int(stmt, 2, m_execution_id);
        } else {
            sqlite3_bind_text(stmt, 2, error.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_int(stmt, 3, m_execution_id);
        }
        sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    }

    sqlite3_close_v2(db);
    LOG_INFO("Execution {} status updated to: {}", m_execution_id, status);
}

void WorkflowExecutor::UpdateNodeStatus(int node_id, const std::string& status,
                                       const json& outputs, const std::string& error) {
    sqlite3* db = OpenDatabase();
    if (!db) {
        LOG_ERROR("Failed to update node status - cannot open database");
        return;
    }

    // Check if node record exists
    std::string check_sql = "SELECT execution_order FROM execution_nodes WHERE execution_id = ? AND node_id = ?";
    sqlite3_stmt* stmt = nullptr;
    bool exists = false;

    if (sqlite3_prepare_v2(db, check_sql.c_str(), -1, &stmt, nullptr) == SQLITE_OK) {
        sqlite3_bind_int(stmt, 1, m_execution_id);
        sqlite3_bind_int(stmt, 2, node_id);
        exists = (sqlite3_step(stmt) == SQLITE_ROW);
        sqlite3_finalize(stmt);
    }

    std::string sql;
    std::string outputs_json = outputs.dump();
    std::string inputs_json = "{}";  // Could gather from GatherNodeInputs if needed

    if (exists) {
        // Update
        sql = R"(
            UPDATE execution_nodes
            SET status = ?, outputs = ?, error_message = ?,
                completed_at = CASE WHEN ? IN ('completed', 'error', 'skipped')
                                   THEN CURRENT_TIMESTAMP ELSE completed_at END
            WHERE execution_id = ? AND node_id = ?
        )";

        if (sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, status.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 2, outputs_json.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 3, error.empty() ? nullptr : error.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 4, status.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_int(stmt, 5, m_execution_id);
            sqlite3_bind_int(stmt, 6, node_id);
            sqlite3_step(stmt);
            sqlite3_finalize(stmt);
        }
    } else {
        // Insert
        sql = R"(
            INSERT INTO execution_nodes
            (execution_id, node_id, status, inputs, outputs, error_message, execution_order, started_at)
            SELECT ?, ?, ?, ?, ?, ?, COALESCE(MAX(execution_order), 0) + 1, CURRENT_TIMESTAMP
            FROM execution_nodes WHERE execution_id = ?
        )";

        if (sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr) == SQLITE_OK) {
            sqlite3_bind_int(stmt, 1, m_execution_id);
            sqlite3_bind_int(stmt, 2, node_id);
            sqlite3_bind_text(stmt, 3, status.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 4, inputs_json.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 5, outputs_json.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 6, error.empty() ? nullptr : error.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_int(stmt, 7, m_execution_id);
            sqlite3_step(stmt);
            sqlite3_finalize(stmt);
        }
    }

    sqlite3_close_v2(db);
}

bool WorkflowExecutor::Execute() {
    LOG_INFO("Starting execution {} for workflow {}", m_execution_id, m_workflow_id);

    // Create execution tables
    sqlite3* db = OpenDatabase();
    if (db) {
        std::string state_sql = "CREATE TABLE IF NOT EXISTS exec_" + std::to_string(m_execution_id) +
            "_state (key TEXT PRIMARY KEY, value TEXT, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)";

        std::string log_sql = "CREATE TABLE IF NOT EXISTS exec_" + std::to_string(m_execution_id) +
            "_log (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP, " +
            "level TEXT, node_id INTEGER, message TEXT)";

        ExecuteSQL(db, state_sql);
        ExecuteSQL(db, log_sql);
        sqlite3_close_v2(db);
    }

    // Execute on_start callbacks
    json start_context = {
        {"execution_id", m_execution_id},
        {"workflow_id", m_workflow_id}
    };
    ExecuteCallbackNodes("on_start", start_context);

    // Get execution order
    std::vector<int> execution_order = TopologicalSort();
    if (execution_order.empty() && !m_nodes.empty()) {
        m_last_error = "Workflow has a cycle or cannot be sorted";
        UpdateExecutionStatus("error", m_last_error);
        return false;
    }

    // Execute nodes in order
    for (int node_id : execution_order) {
        // Check for control commands
        if (!CheckControlCommand()) {
            UpdateExecutionStatus("stopped");
            return false;
        }

        // Execute on_node_start callbacks
        json node_start_context = {
            {"execution_id", m_execution_id},
            {"workflow_id", m_workflow_id},
            {"node_id", node_id}
        };
        ExecuteCallbackNodes("on_node_start", node_start_context);

        // Gather inputs
        json inputs = GatherNodeInputs(node_id);

        // Execute the node
        UpdateNodeStatus(node_id, "running");

        if (!ExecuteNode(node_id, inputs)) {
            // Execute on_error callbacks
            json error_context = {
                {"execution_id", m_execution_id},
                {"workflow_id", m_workflow_id},
                {"error_node_id", node_id},
                {"error_message", m_last_error}
            };
            ExecuteCallbackNodes("on_error", error_context);

            UpdateExecutionStatus("error", m_last_error);
            return false;
        }

        // Execute on_node_complete callbacks
        json node_complete_context = {
            {"execution_id", m_execution_id},
            {"workflow_id", m_workflow_id},
            {"node_id", node_id}
        };
        if (m_node_outputs.count(node_id)) {
            node_complete_context["outputs"] = m_node_outputs[node_id];
        }
        ExecuteCallbackNodes("on_node_complete", node_complete_context);

        // Small delay for visualization
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    // Execute on_complete callbacks
    json complete_context = {
        {"execution_id", m_execution_id},
        {"workflow_id", m_workflow_id}
    };
    ExecuteCallbackNodes("on_complete", complete_context);

    // Update execution status
    UpdateExecutionStatus("completed");

    LOG_INFO("Execution {} completed successfully", m_execution_id);
    return true;
}

void WorkflowExecutor::Stop() {
    m_stop_requested = true;
}
