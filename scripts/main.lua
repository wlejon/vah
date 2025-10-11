-- Main Lua script for vah application
-- This script is loaded in a thread after the application initializes

function startup()
    print("Main Lua thread started")

    -- Load the streaming data demo UI
    ui.load_document("ui/streaming.rml")

    -- Spawn the data stream thread to continuously generate data
    command.spawn_thread("scripts/data_stream.lua")

    print("Streaming data demo initialized")
end

function update(dt)
    -- Called at 30hz
    -- Main coordination happens here if needed
end

function shutdown()
    print("Main Lua thread shutting down")
end
