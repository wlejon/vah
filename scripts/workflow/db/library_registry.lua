-- Library Registry Module
-- Manages available libraries and their access controls

local helpers = require("scripts.workflow.db.helpers")

local M = {}

-- Reference to database handle (set by init.lua)
M.db_handle = nil

-- Populate library registry with default C++ libraries
function M.populate_library_registry()
    if not M.db_handle then
        print("library_registry.populate_library_registry: Database not initialized")
        return false
    end

    local libraries = {
        {id = "math", name = "Math Operations",
         description = "Standard mathematical functions and constants",
         access_description = "No data access - pure computation"},
        {id = "string", name = "String Operations",
         description = "String manipulation and pattern matching",
         access_description = "No data access - pure computation"},
        {id = "table", name = "Table Operations",
         description = "Table manipulation utilities",
         access_description = "No data access - pure computation"},
        {id = "db", name = "Database Access",
         description = "Query and modify SQLite databases",
         access_description = "Read/write access to execution-specific tables"},
        {id = "fs", name = "File System Access",
         description = "Read and write files on disk",
         access_description = "Full file system access (current user permissions)"},
        {id = "http", name = "Network Access",
         description = "Make HTTP/HTTPS requests",
         access_description = "Can send data to external services"},
        {id = "ui", name = "User Interface",
         description = "Create UI windows using RmlUI",
         access_description = "Can display content and capture user input"},
        {id = "thread", name = "Threading Utilities",
         description = "Thread management and querying",
         access_description = "Limited to thread queries and sleep"},
        {id = "event", name = "Event System",
         description = "Trigger and listen for events",
         access_description = "Can communicate with other application components"}
    }

    local sql = [[
        INSERT INTO library_registry (id, name, description, access_description, is_builtin)
        VALUES (?, ?, ?, ?, 1)
    ]]

    for _, lib in ipairs(libraries) do
        local success, error = M.db_handle:execute(sql, lib.id, lib.name, lib.description, lib.access_description)
        if not success then
            print("library_registry.populate_library_registry: Error adding library '" .. lib.id .. "': " .. error)
        end
    end

    print("Library registry populated with default libraries")
    return true
end

-- Get all library definitions
-- Returns array of library records
function M.get_library_definitions()
    if not M.db_handle then
        print("library_registry.get_library_definitions: Database not initialized")
        return {}
    end

    local results, error = M.db_handle:query([[
        SELECT id, name, description, access_description, is_builtin, enabled, lua_module_path
        FROM library_registry
        ORDER BY is_builtin DESC, name
    ]])

    if error ~= "" then
        print("library_registry.get_library_definitions: Error loading libraries: " .. error)
        return {}
    end

    return results or {}
end

-- Get enabled libraries
-- Returns array of enabled library records
function M.get_enabled_libraries()
    if not M.db_handle then
        print("library_registry.get_enabled_libraries: Database not initialized")
        return {}
    end

    local results, error = M.db_handle:query([[
        SELECT id, name, description, access_description, is_builtin, lua_module_path
        FROM library_registry
        WHERE enabled = 1
        ORDER BY is_builtin DESC, name
    ]])

    if error ~= "" then
        print("library_registry.get_enabled_libraries: Error loading enabled libraries: " .. error)
        return {}
    end

    return results or {}
end

-- Enable/disable a library
-- Returns (success, error)
function M.set_library_enabled(library_id, enabled)
    if not M.db_handle then
        return false, "Database not initialized"
    end

    local sql = [[
        UPDATE library_registry
        SET enabled = ?
        WHERE id = ?
    ]]

    local success, error = M.db_handle:execute(sql, enabled and 1 or 0, library_id)
    if not success then
        return false, helpers.error_msg("set_library_enabled", "Error updating library: " .. error)
    end

    return true, nil
end

-- Register a custom library
-- Returns (success, error)
function M.register_library(id, name, description, access_description, lua_module_path)
    if not M.db_handle then
        return false, "Database not initialized"
    end

    local sql = [[
        INSERT INTO library_registry (id, name, description, access_description, is_builtin, lua_module_path)
        VALUES (?, ?, ?, ?, 0, ?)
    ]]

    local success, error = M.db_handle:execute(sql, id, name, description, access_description, lua_module_path)
    if not success then
        return false, helpers.error_msg("register_library", "Error registering library: " .. error)
    end

    return true, nil
end

-- Unregister a custom library
-- Returns (success, error)
function M.unregister_library(library_id)
    if not M.db_handle then
        return false, "Database not initialized"
    end

    -- Only allow unregistering custom libraries (not built-in)
    local sql = "DELETE FROM library_registry WHERE id = ? AND is_builtin = 0"
    local success, error = M.db_handle:execute(sql, library_id)

    if not success then
        return false, helpers.error_msg("unregister_library", "Error unregistering library: " .. error)
    end

    return true, nil
end

return M
