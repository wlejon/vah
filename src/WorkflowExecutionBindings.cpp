#include "WorkflowExecutionBindings.h"
#include "Logger.h"
#include <lua.hpp>
#include <sqlite3.h>
#include <nlohmann/json.hpp>
#include <string>
#include <sstream>

using json = nlohmann::json;

namespace WorkflowExecutionBindings {

// Forward declarations for internal helper functions
static json LuaValueToJson(lua_State* L, int idx);
static void JsonToLuaValue(lua_State* L, const json& j);
static std::string LuaValueToJsonString(lua_State* L, int idx);

// Helper: Convert Lua value at stack index to JSON
static json LuaValueToJson(lua_State* L, int idx) {
    int type = lua_type(L, idx);

    switch (type) {
        case LUA_TNIL:
            return nullptr;

        case LUA_TBOOLEAN:
            return lua_toboolean(L, idx) != 0;

        case LUA_TNUMBER:
            if (lua_isinteger(L, idx)) {
                return lua_tointeger(L, idx);
            } else {
                return lua_tonumber(L, idx);
            }

        case LUA_TSTRING:
            return std::string(lua_tostring(L, idx));

        case LUA_TTABLE: {
            // Check if it's an array or object
            lua_pushnil(L);
            bool is_array = true;
            int max_idx = 0;
            int count = 0;

            // First pass: check if all keys are integers
            while (lua_next(L, idx < 0 ? idx - 1 : idx) != 0) {
                count++;
                if (lua_type(L, -2) == LUA_TNUMBER && lua_isinteger(L, -2)) {
                    int key = lua_tointeger(L, -2);
                    if (key > max_idx) max_idx = key;
                } else {
                    is_array = false;
                }
                lua_pop(L, 1);
            }

            // Array if all keys are sequential integers starting from 1
            is_array = is_array && count > 0 && count == max_idx;

            if (is_array) {
                json arr = json::array();
                for (int i = 1; i <= max_idx; i++) {
                    lua_geti(L, idx, i);
                    arr.push_back(LuaValueToJson(L, -1));
                    lua_pop(L, 1);
                }
                return arr;
            } else {
                json obj = json::object();
                lua_pushnil(L);
                while (lua_next(L, idx < 0 ? idx - 1 : idx) != 0) {
                    // Key at -2, value at -1
                    std::string key;
                    if (lua_type(L, -2) == LUA_TSTRING) {
                        key = lua_tostring(L, -2);
                    } else if (lua_type(L, -2) == LUA_TNUMBER) {
                        key = std::to_string(lua_tointeger(L, -2));
                    }

                    if (!key.empty()) {
                        obj[key] = LuaValueToJson(L, -1);
                    }
                    lua_pop(L, 1);
                }
                return obj;
            }
        }

        default:
            return nullptr;
    }
}

// Helper: Push JSON value to Lua stack
static void JsonToLuaValue(lua_State* L, const json& j) {
    if (j.is_null()) {
        lua_pushnil(L);
    } else if (j.is_boolean()) {
        lua_pushboolean(L, j.get<bool>());
    } else if (j.is_number_integer()) {
        lua_pushinteger(L, j.get<int64_t>());
    } else if (j.is_number_float()) {
        lua_pushnumber(L, j.get<double>());
    } else if (j.is_string()) {
        lua_pushstring(L, j.get<std::string>().c_str());
    } else if (j.is_array()) {
        lua_newtable(L);
        int idx = 1;
        for (const auto& item : j) {
            JsonToLuaValue(L, item);
            lua_seti(L, -2, idx++);
        }
    } else if (j.is_object()) {
        lua_newtable(L);
        for (auto it = j.begin(); it != j.end(); ++it) {
            lua_pushstring(L, it.key().c_str());
            JsonToLuaValue(L, it.value());
            lua_settable(L, -3);
        }
    } else {
        lua_pushnil(L);
    }
}

// Helper: Convert Lua value to JSON string
static std::string LuaValueToJsonString(lua_State* L, int idx) {
    json j = LuaValueToJson(L, idx);
    return j.dump();
}

// Lua C function: execution.set(key, value)
static int lua_execution_set(lua_State* L) {
    // Get execution_id from upvalue
    int execution_id = lua_tointeger(L, lua_upvalueindex(1));

    // Get arguments
    const char* key = luaL_checkstring(L, 1);
    if (!key || strlen(key) == 0) {
        lua_pushnil(L);
        lua_pushstring(L, "Key cannot be empty");
        return 2;
    }

    // Convert value to JSON string
    std::string json_value;
    try {
        json_value = LuaValueToJsonString(L, 2);
    } catch (const std::exception& e) {
        lua_pushnil(L);
        lua_pushstring(L, ("Failed to serialize value: " + std::string(e.what())).c_str());
        return 2;
    }

    // Open database
    sqlite3* db = nullptr;
    int rc = sqlite3_open("vah.db", &db);
    if (rc != SQLITE_OK) {
        std::string error = sqlite3_errmsg(db);
        sqlite3_close(db);
        lua_pushnil(L);
        lua_pushstring(L, ("Failed to open database: " + error).c_str());
        return 2;
    }

    // Build table name
    std::string table_name = "exec_" + std::to_string(execution_id) + "_state";

    // Prepare SQL
    std::string sql = "INSERT OR REPLACE INTO " + table_name + " (key, value, updated_at) VALUES (?, ?, CURRENT_TIMESTAMP)";

    sqlite3_stmt* stmt = nullptr;
    rc = sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr);
    if (rc != SQLITE_OK) {
        std::string error = sqlite3_errmsg(db);
        sqlite3_close(db);
        lua_pushnil(L);
        lua_pushstring(L, ("Failed to prepare statement: " + error).c_str());
        return 2;
    }

    // Bind parameters
    sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, json_value.c_str(), -1, SQLITE_TRANSIENT);

    // Execute
    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    sqlite3_close(db);

    if (rc != SQLITE_DONE) {
        lua_pushnil(L);
        lua_pushstring(L, "Failed to execute statement");
        return 2;
    }

    return 0;
}

// Lua C function: execution.get(key)
static int lua_execution_get(lua_State* L) {
    // Get execution_id from upvalue
    int execution_id = lua_tointeger(L, lua_upvalueindex(1));

    // Get key argument
    const char* key = luaL_checkstring(L, 1);
    if (!key || strlen(key) == 0) {
        lua_pushnil(L);
        return 1;
    }

    // Open database
    sqlite3* db = nullptr;
    int rc = sqlite3_open("vah.db", &db);
    if (rc != SQLITE_OK) {
        sqlite3_close(db);
        lua_pushnil(L);
        return 1;
    }

    // Build table name
    std::string table_name = "exec_" + std::to_string(execution_id) + "_state";

    // Prepare SQL
    std::string sql = "SELECT value FROM " + table_name + " WHERE key = ?";

    sqlite3_stmt* stmt = nullptr;
    rc = sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr);
    if (rc != SQLITE_OK) {
        sqlite3_close(db);
        lua_pushnil(L);
        return 1;
    }

    // Bind key
    sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT);

    // Execute and get result
    rc = sqlite3_step(stmt);
    if (rc == SQLITE_ROW) {
        // Get JSON value
        const char* json_str = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 0));

        if (json_str) {
            try {
                json j = json::parse(json_str);
                JsonToLuaValue(L, j);
            } catch (const std::exception& e) {
                LOG_ERROR("Failed to parse JSON value for key '{}': {}", key, e.what());
                lua_pushnil(L);
            }
        } else {
            lua_pushnil(L);
        }
    } else {
        lua_pushnil(L);
    }

    sqlite3_finalize(stmt);
    sqlite3_close(db);

    return 1;
}

// Lua C function: execution.log(level, message, node_id?)
static int lua_execution_log(lua_State* L) {
    // Get execution_id from upvalue
    int execution_id = lua_tointeger(L, lua_upvalueindex(1));

    // Get arguments
    const char* level = luaL_checkstring(L, 1);
    const char* message = luaL_checkstring(L, 2);

    // Optional node_id
    int node_id = 0;
    if (lua_gettop(L) >= 3 && lua_isnumber(L, 3)) {
        node_id = lua_tointeger(L, 3);
    }

    // Open database
    sqlite3* db = nullptr;
    int rc = sqlite3_open("vah.db", &db);
    if (rc != SQLITE_OK) {
        std::string error = sqlite3_errmsg(db);
        sqlite3_close(db);
        lua_pushnil(L);
        lua_pushstring(L, ("Failed to open database: " + error).c_str());
        return 2;
    }

    // Build table name
    std::string table_name = "exec_" + std::to_string(execution_id) + "_log";

    // Prepare SQL
    std::string sql = "INSERT INTO " + table_name + " (timestamp, level, message, node_id) VALUES (CURRENT_TIMESTAMP, ?, ?, ?)";

    sqlite3_stmt* stmt = nullptr;
    rc = sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr);
    if (rc != SQLITE_OK) {
        std::string error = sqlite3_errmsg(db);
        sqlite3_close(db);
        lua_pushnil(L);
        lua_pushstring(L, ("Failed to prepare statement: " + error).c_str());
        return 2;
    }

    // Bind parameters
    sqlite3_bind_text(stmt, 1, level, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, message, -1, SQLITE_TRANSIENT);
    if (node_id > 0) {
        sqlite3_bind_int(stmt, 3, node_id);
    } else {
        sqlite3_bind_null(stmt, 3);
    }

    // Execute
    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    sqlite3_close(db);

    if (rc != SQLITE_DONE) {
        lua_pushnil(L);
        lua_pushstring(L, "Failed to execute statement");
        return 2;
    }

    return 0;
}

// Lua C function: execution.id()
static int lua_execution_id(lua_State* L) {
    // Get execution_id from upvalue
    int execution_id = lua_tointeger(L, lua_upvalueindex(1));
    lua_pushinteger(L, execution_id);
    return 1;
}

// Lua C function: execution.workflow_id()
static int lua_execution_workflow_id(lua_State* L) {
    // Get execution_id from upvalue
    int execution_id = lua_tointeger(L, lua_upvalueindex(1));

    // Open database
    sqlite3* db = nullptr;
    int rc = sqlite3_open("vah.db", &db);
    if (rc != SQLITE_OK) {
        sqlite3_close(db);
        lua_pushnil(L);
        return 1;
    }

    // Query workflow_id from workflow_executions table
    std::string sql = "SELECT workflow_id FROM workflow_executions WHERE id = ?";

    sqlite3_stmt* stmt = nullptr;
    rc = sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr);
    if (rc != SQLITE_OK) {
        sqlite3_close(db);
        lua_pushnil(L);
        return 1;
    }

    // Bind execution_id
    sqlite3_bind_int(stmt, 1, execution_id);

    // Execute and get result
    rc = sqlite3_step(stmt);
    if (rc == SQLITE_ROW) {
        int workflow_id = sqlite3_column_int(stmt, 0);
        lua_pushinteger(L, workflow_id);
    } else {
        lua_pushnil(L);
    }

    sqlite3_finalize(stmt);
    sqlite3_close(db);

    return 1;
}

// Register execution API in lua_State
void RegisterExecutionAPI(lua_State* L, int execution_id) {
    // Create execution table
    lua_newtable(L);
    int exec_table = lua_gettop(L);

    // Register execution.set(key, value)
    lua_pushinteger(L, execution_id);
    lua_pushcclosure(L, lua_execution_set, 1);
    lua_setfield(L, exec_table, "set");

    // Register execution.get(key)
    lua_pushinteger(L, execution_id);
    lua_pushcclosure(L, lua_execution_get, 1);
    lua_setfield(L, exec_table, "get");

    // Register execution.log(level, message, node_id?)
    lua_pushinteger(L, execution_id);
    lua_pushcclosure(L, lua_execution_log, 1);
    lua_setfield(L, exec_table, "log");

    // Register execution.id()
    lua_pushinteger(L, execution_id);
    lua_pushcclosure(L, lua_execution_id, 1);
    lua_setfield(L, exec_table, "id");

    // Register execution.workflow_id()
    lua_pushinteger(L, execution_id);
    lua_pushcclosure(L, lua_execution_workflow_id, 1);
    lua_setfield(L, exec_table, "workflow_id");

    // Set as global "execution"
    lua_setglobal(L, "execution");
}

} // namespace WorkflowExecutionBindings
