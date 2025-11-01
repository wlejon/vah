-- Main Lua script for vah application
-- This script is loaded in a thread after the application initializes

function startup()
    print("Main Lua thread started")

    -- Start core systems
    command.spawn_thread("scripts/core/notifications.lua")
    command.spawn_thread("scripts/core/menu.lua")
    command.spawn_thread("scripts/mcp/server.lua")

    -- Start file analyzers (background services)
    command.spawn_thread("scripts/analyzers/lua_analyzer.lua")

    -- Start the launcher (app selection menu)
    command.spawn_thread("scripts/core/launcher.lua")
end

function update(dt)
    -- Called at 30hz
    -- Main coordination happens here if needed
end

function shutdown()
    print("Main Lua thread shutting down")
end
