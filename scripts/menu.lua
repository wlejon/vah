-- Menu System
-- Core system for application navigation
-- Provides a menu bar with File menu (Home, Close)

-- Combined menu state (includes MCP status owned by menu)
local menu_data = {
    file_menu_open = 0,
    mcp_menu_open = 0,
    -- MCP status fields
    mcp_status = "stopped",
    mcp_status_text = "Stopped",
    mcp_status_color = "red",
    mcp_is_stopped = 1,
    mcp_is_running = 0
}

-- Document ID
local MENU_DOC_ID = "app_menu"

-- Update menu data model
function update_menu_data()
    data.bind_object("menu_data", menu_data)
end

-- Register local event handlers (UI interactions)
function register_local_events()
    -- Toggle File menu dropdown
    event.register("toggle_file_menu", function(payload)
        menu_data.file_menu_open = (menu_data.file_menu_open == 0) and 1 or 0
        update_menu_data()
    end)

    -- Close File menu
    event.register("close_file_menu", function(payload)
        menu_data.file_menu_open = 0
        update_menu_data()
    end)

    -- File -> Home action
    event.register("menu_file_home", function(payload)
        menu_data.file_menu_open = 0
        update_menu_data()

        -- Trigger global event to return to launcher
        event.trigger_global("return_to_launcher", {})
    end)

    -- File -> Close action
    event.register("menu_file_close", function(payload)
        menu_data.file_menu_open = 0
        update_menu_data()

        -- Trigger global event to close application
        event.trigger_global("close_application", {})
    end)

    -- Toggle MCP menu dropdown
    event.register("toggle_mcp_menu", function(payload)
        menu_data.mcp_menu_open = (menu_data.mcp_menu_open == 0) and 1 or 0
        update_menu_data()
    end)

    -- Close MCP menu
    event.register("close_mcp_menu", function(payload)
        menu_data.mcp_menu_open = 0
        update_menu_data()
    end)

    -- MCP -> Start action
    event.register("menu_mcp_start", function(payload)
        menu_data.mcp_menu_open = 0
        update_menu_data()

        -- Trigger global event to start MCP server
        event.trigger_global("mcp_start_server", {})
    end)

    -- MCP -> Stop action
    event.register("menu_mcp_stop", function(payload)
        menu_data.mcp_menu_open = 0
        update_menu_data()

        -- Trigger global event to stop MCP server
        event.trigger_global("mcp_stop_server", {})
    end)
end

-- Register global event handlers (cross-thread communication)
function register_global_events()
    -- Allow other threads to programmatically open/close menus if needed
    event.register_global("open_file_menu", function(payload)
        menu_data.file_menu_open = 1
        update_menu_data()
    end)

    event.register_global("close_all_menus", function(payload)
        menu_data.file_menu_open = 0
        menu_data.mcp_menu_open = 0
        update_menu_data()
    end)

    -- MCP server status updates
    event.register_global("mcp_status_update", function(payload)
        if payload.status then
            menu_data.mcp_status = payload.status
            menu_data.mcp_status_text = payload.status_text or ""
            menu_data.mcp_status_color = payload.status_color or "red"
            menu_data.mcp_is_stopped = payload.is_stopped or 0
            menu_data.mcp_is_running = payload.is_running or 0
            update_menu_data()
        end
    end)
end

function startup()
    print("Menu system starting...")

    -- Initialize data model FIRST, before any events
    update_menu_data()

    -- Register event handlers
    register_local_events()
    register_global_events()

    -- Load menu UI
    ui.load_document("ui/internal/menu.rml", true, MENU_DOC_ID)

    print("Menu system started")
end

function update(dt)
    -- Called at 30hz
    -- Menu system is event-driven, no periodic updates needed
end

function shutdown()
    print("Menu system shutting down")

    -- Hide menu document
    ui.hide_document(MENU_DOC_ID)
end
