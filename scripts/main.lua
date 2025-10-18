-- Main Lua script for vah application
-- This script is loaded in a thread after the application initializes

function startup()
    print("Main Lua thread started")

    -- Spawn AI agent thread (auto-start, waits for user input via global queue)
    command.spawn_thread("scripts/agent/core.lua")

    -- Choose which demo to run (comment/uncomment):

    -- Unified Workflow Application (combines workflow editor and node type editor)
    command.spawn_thread("scripts/workflow_app.lua")

    -- Tetris Game
    -- ui.load_document("ui/tetris.rml")

    -- NanoVG Canvas Test (custom RmlUi element with NanoVG rendering)
    -- ui.load_document("ui/canvas_test.rml")

    -- File browser demo
    -- command.spawn_thread("scripts/file_browser.lua")

    -- JSON data viewer demo
    -- command.spawn_thread("scripts/json_demo.lua")

    -- SQLite database demo
    -- command.spawn_thread("scripts/sqlite_demo.lua")

    -- Streaming data demo
    -- command.spawn_thread("scripts/data_stream.lua")

    -- HTTP SSE demo (server and client)
    -- command.spawn_thread("scripts/http_server.lua")
    -- command.spawn_thread("scripts/http_client.lua")

    print("Application initialized (with AI agent)")
end

function update(dt)
    -- Called at 30hz
    -- Main coordination happens here if needed
end

function shutdown()
    print("Main Lua thread shutting down")
end
