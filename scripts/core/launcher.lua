-- Launcher
-- Main application launcher for vah

local active_app = {
    thread_id = nil,
    document_id = nil,
    script_path = nil
}

-- App registry with metadata
local apps = {
    manufold = {
        name = "Manufold",
        script = "scripts/manufold/agent.lua",
        document_id = "manufold"
    },
    file_editor = {
        name = "File Editor",
        script = "scripts/apps/file_editor.lua",
        document_id = "file_editor"
    },
    file_indexer = {
        name = "File Indexer",
        script = "scripts/apps/file_indexer.lua",
        document_id = "file_indexer"
    },
    chat = {
        name = "Chat",
        script = "scripts/apps/chat.lua",
        document_id = "chat"
    },
    workflow_app = {
        name = "Workflow Editor",
        script = "scripts/workflow/app.lua",
        document_id = "workflow_app"
    },
    mcp_client = {
        name = "MCP Client",
        script = "scripts/mcp/client.lua",
        document_id = "mcp_client"
    }
}

-- Update File menu when app is launched (add Home option)
local function update_file_menu_for_app()
    event.trigger_global("menu_register", {
        menu_id = "file",
        label = "File",
        position = 1,
        items = {
            {item_id = "home", label = "Home", action = "return_to_launcher"},
            {item_id = "close", label = "Close", action = "close_application"}
        }
    })
end

-- Update File menu when returning to launcher (remove Home option)
local function update_file_menu_for_launcher()
    event.trigger_global("menu_register", {
        menu_id = "file",
        label = "File",
        position = 1,
        items = {
            {item_id = "close", label = "Close", action = "close_application"}
        }
    })
end

-- Launch an app
local function launch_app(payload)
    local app_id = payload.app_id
    if not app_id then
        print("ERROR: No app_id in launch_app payload")
        return
    end

    local app = apps[app_id]
    if not app then
        print("ERROR: Unknown app: " .. app_id)
        return
    end

    print("Launching app: " .. app.name)

    -- Hide launcher
    ui.hide_document("launcher")

    -- Update File menu to include Home option
    update_file_menu_for_app()

    -- Launch the app
    if app.script then
        -- Spawn a thread for the app
        -- Store the script path first so we can match it in the thread_spawned event
        active_app.script_path = app.script
        active_app.document_id = app.document_id
        active_app.thread_id = nil  -- Will be set by thread_spawned event

        command.spawn_thread(app.script)
    elseif app.ui_path then
        -- Just load a UI document (no script)
        ui.load_document(app.ui_path, true, app.document_id)
        active_app.document_id = app.document_id
    end
end

-- Close the current app and return to launcher
local function close_current_app(payload)
    print("Closing current app")

    -- Update File menu to remove Home option
    update_file_menu_for_launcher()

    -- Hide the app's document if it exists
    if active_app.document_id then
        ui.hide_document(active_app.document_id)
    end

    -- Stop the app's thread if it exists
    if active_app.thread_id then
        print("Stopping thread: " .. active_app.thread_id)
        command.stop_thread(active_app.thread_id)
    end

    -- Clear active app state
    active_app.thread_id = nil
    active_app.document_id = nil
    active_app.script_path = nil

    -- Show launcher
    ui.show_document("launcher")
end

-- Handle thread spawned event to track the new thread ID
local function on_thread_spawned(payload)
    local spawned_thread_id = payload.thread_id
    local script_path = payload.script_path

    print("Thread spawned: " .. spawned_thread_id .. " for script: " .. script_path)

    -- Update active_app with the thread ID
    -- We should only update if we're expecting a thread (active_app.script_path is set)
    if active_app.script_path == script_path then
        active_app.thread_id = spawned_thread_id
        print("Tracking thread ID: " .. spawned_thread_id)
    end
end

function startup()
    print("Launcher started (thread_id: " .. thread_id .. ")")

    -- Register event handlers
    event.register("launch_app", launch_app)
    event.register("close_app", close_current_app)
    event.register("thread_spawned", on_thread_spawned)

    -- Register global event handlers (for menu system)
    event.register_global("return_to_launcher", close_current_app)
    event.register_global("close_application", function(payload)
        print("Closing application via menu")
        command.close_application()
    end)

    -- Load launcher UI
    ui.load_document("ui/core/launcher/launcher.rml", true, "launcher")

    print("Launcher ready")
end

function update(dt)
    -- Nothing needed
end

function shutdown()
    print("Launcher shutting down")
end

-- Called when menu system is ready
function menu_ready()
    -- Register File menu at startup (always visible)
    event.trigger_global("menu_register", {
        menu_id = "file",
        label = "File",
        position = 1,
        items = {
            {item_id = "close", label = "Close", action = "close_application"}
        }
    })
end
