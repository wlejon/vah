-- Main Lua script for vah application
-- This script is loaded in a thread after the application initializes

function startup()
    print("Main Lua thread started")

    -- Start the launcher (app selection menu)
    command.spawn_thread("scripts/launcher.lua")
end

function update(dt)
    -- Called at 30hz
    -- Main coordination happens here if needed
end

function shutdown()
    print("Main Lua thread shutting down")
end
