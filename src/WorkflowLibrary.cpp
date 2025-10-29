#include "WorkflowLibrary.h"
#include "Logger.h"
#include "SqliteBindings.h"
#include "FileWatcherBindings.h"
#include "HttpBindings.h"
#include <lua.hpp>
#include <sol/sol.hpp>

namespace WorkflowLibrary {

// Static member initialization
std::unordered_map<std::string, LibraryDefinition> WorkflowLibraryRegistry::s_libraries;

// Forward declarations for binding functions that may exist elsewhere
// Note: These will be implemented as we build out the workflow system

// Placeholder binding function for libraries not yet implemented
static void RegisterPlaceholder(lua_State* L, const std::string& lib_name) {
    LOG_WARN("Workflow library '{}' not yet implemented - placeholder registered", lib_name);
    // Create an empty table for the library so scripts don't error
    lua_newtable(L);
    lua_setglobal(L, lib_name.c_str());
}

// Wrapper functions for standard Lua libraries
static void RegisterMathLibrary(lua_State* L) {
    luaL_requiref(L, "math", luaopen_math, 1);
    lua_pop(L, 1);  // Pop the module table
    LOG_DEBUG("Registered math library for workflow");
}

static void RegisterStringLibrary(lua_State* L) {
    luaL_requiref(L, "string", luaopen_string, 1);
    lua_pop(L, 1);  // Pop the module table
    LOG_DEBUG("Registered string library for workflow");
}

static void RegisterTableLibrary(lua_State* L) {
    luaL_requiref(L, "table", luaopen_table, 1);
    lua_pop(L, 1);  // Pop the module table
    LOG_DEBUG("Registered table library for workflow");
}

// Database bindings wrapper
static void RegisterDbLibrary(lua_State* L) {
    // For now, use placeholder until we refactor bindings to work with lua_State*
    // The existing SqliteBindings::SetupBindings expects sol::state&
    // which requires ownership, but we only have a non-owning lua_State*
    LOG_WARN("Database library needs sol::state_view support - using placeholder");
    RegisterPlaceholder(L, "db");
    // TODO: Refactor SqliteBindings to accept sol::state_view or lua_State*
}

// File system bindings placeholder
static void RegisterFsLibrary(lua_State* L) {
    RegisterPlaceholder(L, "fs");
    // TODO: Implement file system bindings for workflows
    // This should provide safe file system access with appropriate restrictions
}

// HTTP bindings wrapper
static void RegisterHttpLibrary(lua_State* L) {
    // Note: HttpBindings normally requires LuaThread pointer for server registration
    // For workflows, we may need a different approach or restricted HTTP client only
    LOG_WARN("HTTP library for workflows needs special implementation - placeholder registered");
    RegisterPlaceholder(L, "http");
    // TODO: Implement HTTP bindings for workflows (likely client-only, no server)
}

// UI bindings placeholder
static void RegisterUiLibrary(lua_State* L) {
    RegisterPlaceholder(L, "ui");
    // TODO: Implement UI bindings for workflows
    // This should allow workflows to create RmlUI windows and interact with UI
}

// Thread utilities placeholder
static void RegisterThreadLibrary(lua_State* L) {
    // Provide basic thread utilities like sleep
    sol::state_view lua(L);
    auto thread_table = lua.create_table();

    // Sleep function (useful for workflows)
    thread_table["sleep"] = [](double seconds) {
        std::this_thread::sleep_for(std::chrono::milliseconds(static_cast<int>(seconds * 1000)));
    };

    lua["thread"] = thread_table;
    LOG_DEBUG("Registered thread library for workflow (limited functionality)");
}

// Event system bindings placeholder
static void RegisterEventLibrary(lua_State* L) {
    RegisterPlaceholder(L, "event");
    // TODO: Implement event bindings for workflows
    // This should allow workflows to trigger and listen for events
}

void WorkflowLibraryRegistry::RegisterBuiltinLibraries() {
    // Safe libraries (pure computation, no data access)
    RegisterLibrary({
        "math",
        "Math Operations",
        "Standard mathematical functions including trigonometry, logarithms, and random numbers",
        "No data access - pure computation",
        RegisterMathLibrary
    });

    RegisterLibrary({
        "string",
        "String Operations",
        "String manipulation and pattern matching functions",
        "No data access - pure computation",
        RegisterStringLibrary
    });

    RegisterLibrary({
        "table",
        "Table Operations",
        "Table manipulation utilities for sorting, concatenating, and managing Lua tables",
        "No data access - pure computation",
        RegisterTableLibrary
    });

    // System access libraries (require user approval)
    RegisterLibrary({
        "db",
        "Database Access",
        "Query and modify SQLite databases with full SQL support",
        "Read/write access to execution-specific database tables",
        RegisterDbLibrary
    });

    RegisterLibrary({
        "fs",
        "File System Access",
        "Read and write files on disk with path manipulation utilities",
        "Full file system read/write access",
        RegisterFsLibrary
    });

    RegisterLibrary({
        "http",
        "Network Access",
        "Make HTTP/HTTPS requests to external services",
        "Can communicate with any external web service",
        RegisterHttpLibrary
    });

    RegisterLibrary({
        "ui",
        "User Interface",
        "Create and manage UI windows using RmlUI",
        "Can display content and capture user input",
        RegisterUiLibrary
    });

    RegisterLibrary({
        "thread",
        "Threading Utilities",
        "Thread sleep and basic thread management utilities",
        "Limited thread control - sleep and queries only",
        RegisterThreadLibrary
    });

    RegisterLibrary({
        "event",
        "Event System",
        "Trigger and listen for application events",
        "Can communicate with other application components via events",
        RegisterEventLibrary
    });

    LOG_INFO("Registered {} built-in workflow libraries", s_libraries.size());
}

bool WorkflowLibraryRegistry::RegisterLibrary(const LibraryDefinition& def) {
    // Check if library with this ID already exists
    if (s_libraries.find(def.id) != s_libraries.end()) {
        LOG_WARN("Library '{}' already registered, skipping", def.id);
        return false;
    }

    s_libraries[def.id] = def;
    LOG_DEBUG("Registered workflow library: {} ({})", def.id, def.name);
    return true;
}

bool WorkflowLibraryRegistry::IsLibraryAvailable(const std::string& id) {
    return s_libraries.find(id) != s_libraries.end();
}

int WorkflowLibraryRegistry::RegisterRequestedLibraries(lua_State* L, const std::vector<std::string>& library_ids) {
    int registered_count = 0;

    for (const auto& lib_id : library_ids) {
        auto it = s_libraries.find(lib_id);
        if (it == s_libraries.end()) {
            LOG_WARN("Requested library '{}' not found in registry", lib_id);
            continue;
        }

        const LibraryDefinition& lib_def = it->second;

        try {
            // Call the registration function for this library
            lib_def.register_func(L);
            registered_count++;
            LOG_DEBUG("Registered library '{}' in workflow lua_State", lib_id);
        }
        catch (const std::exception& e) {
            LOG_ERROR("Error registering library '{}': {}", lib_id, e.what());
        }
    }

    LOG_INFO("Registered {}/{} requested libraries in workflow lua_State",
             registered_count, library_ids.size());

    return registered_count;
}

const LibraryDefinition* WorkflowLibraryRegistry::GetLibraryDefinition(const std::string& id) {
    auto it = s_libraries.find(id);
    if (it != s_libraries.end()) {
        return &it->second;
    }
    return nullptr;
}

std::vector<std::string> WorkflowLibraryRegistry::GetRegisteredLibraryIds() {
    std::vector<std::string> ids;
    ids.reserve(s_libraries.size());

    for (const auto& [id, def] : s_libraries) {
        ids.push_back(id);
    }

    return ids;
}

} // namespace WorkflowLibrary
