-- Main Lua script for vah application
-- This script is loaded in a thread after the application initializes

function startup()
    print("Main Lua thread started")

    -- Request main thread to load and show the UI document
    ui.load_document("ui/main.rml")
end

function update(dt)
    -- Called at 30hz
end

function shutdown()
    print("Main Lua thread shutting down")
end
