#include "WorkflowLibrary.h"
#include "Logger.h"
#include "SqliteBindings.h"
#include "FileWatcherBindings.h"
#include "HttpBindings.h"
#include "JsonBindings.h"
#include <lua.hpp>
#include <sol/sol.hpp>

namespace WorkflowLibrary {

// Static member initialization
std::unordered_map<std::string, LibraryDefinition> WorkflowLibraryRegistry::s_libraries;

// Wrapper functions for standard Lua libraries
static void RegisterMathLibrary(sol::state& lua) {
    lua.open_libraries(sol::lib::math);
    LOG_DEBUG("Registered math library for workflow");
}

static void RegisterStringLibrary(sol::state& lua) {
    lua.open_libraries(sol::lib::string);
    LOG_DEBUG("Registered string library for workflow");
}

static void RegisterTableLibrary(sol::state& lua) {
    lua.open_libraries(sol::lib::table);
    LOG_DEBUG("Registered table library for workflow");
}

// Database bindings wrapper
static void RegisterDbLibrary(sol::state& lua) {
    SqliteBindings::SetupBindings(lua);
    LOG_DEBUG("Registered db library for workflow");
}

// File system bindings placeholder
static void RegisterFsLibrary(sol::state& lua) {
    LOG_WARN("File system library not yet implemented for workflows");
    lua["fs"] = lua.create_table();
    // TODO: Implement file system bindings for workflows
    // This should provide safe file system access with appropriate restrictions
}

// HTTP bindings wrapper
static void RegisterHttpLibrary(sol::state& lua) {
    // Note: HttpBindings normally requires LuaThread pointer for server registration
    // For workflows, we may need a different approach or restricted HTTP client only
    LOG_WARN("HTTP library for workflows needs special implementation - placeholder registered");
    lua["http"] = lua.create_table();
    // TODO: Implement HTTP bindings for workflows (likely client-only, no server)
}

// UI bindings placeholder
static void RegisterUiLibrary(sol::state& lua) {
    LOG_WARN("UI library not yet implemented for workflows");
    lua["ui"] = lua.create_table();
    // TODO: Implement UI bindings for workflows
    // This should allow workflows to create RmlUI windows and interact with UI
}

// Thread utilities
static void RegisterThreadLibrary(sol::state& lua) {
    auto thread_table = lua.create_table();

    // Sleep function (useful for workflows)
    thread_table["sleep"] = [](double seconds) {
        std::this_thread::sleep_for(std::chrono::milliseconds(static_cast<int>(seconds * 1000)));
    };

    lua["thread"] = thread_table;
    LOG_DEBUG("Registered thread library for workflow");
}

// JSON bindings wrapper
static void RegisterJsonLibrary(sol::state& lua) {
    JsonBindings::SetupBindings(lua);
    LOG_DEBUG("Registered json library for workflow");
}

// Event system bindings placeholder
static void RegisterEventLibrary(sol::state& lua) {
    LOG_WARN("Event system not yet implemented for workflows");
    lua["event"] = lua.create_table();
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

    RegisterLibrary({
        "json",
        "JSON Encoding/Decoding",
        "Encode and decode JSON data with support for Lua tables",
        "No data access - pure computation",
        RegisterJsonLibrary
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

int WorkflowLibraryRegistry::RegisterRequestedLibraries(sol::state& lua, const std::vector<std::string>& library_ids) {
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
            lib_def.register_func(lua);
            registered_count++;
            LOG_DEBUG("Registered library '{}' in workflow state", lib_id);
        }
        catch (const std::exception& e) {
            LOG_ERROR("Error registering library '{}': {}", lib_id, e.what());
        }
    }

    LOG_INFO("Registered {}/{} requested libraries in workflow state",
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
