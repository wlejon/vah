-- Main Lua script for vah application
-- This script is loaded in a thread after the application initializes

function startup()
    print("Main Lua thread started")

    -- Choose which demo to run (comment/uncomment):

    -- File browser demo
    -- command.spawn_thread("scripts/file_browser.lua")

    -- JSON data viewer demo
    -- command.spawn_thread("scripts/json_demo.lua")

    -- SQLite database demo
    command.spawn_thread("scripts/sqlite_demo.lua")

    -- Streaming data demo
    -- ui.load_document("ui/streaming.rml")
    -- command.spawn_thread("scripts/data_stream.lua")

    print("Demo initialized")
end

function update(dt)
    -- Called at 30hz
    -- Main coordination happens here if needed
end

function shutdown()
    print("Main Lua thread shutting down")
end
