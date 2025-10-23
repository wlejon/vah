-- Menu System
-- Core system for application navigation
-- Provides a menu bar with File menu (Home, Close)

local menu_state = {
    file_menu_open = false  -- Track whether File menu is expanded
}

-- Document ID
local MENU_DOC_ID = "app_menu"

-- Update menu state data model
function update_menu_state()
    -- Bind as a single-element array so we can access fields directly
    data.bind("menu_state", {{
        file_menu_open = menu_state.file_menu_open and 1 or 0
    }})
end

-- Register local event handlers (UI interactions)
function register_local_events()
    -- Toggle File menu dropdown
    event.register("toggle_file_menu", function(payload)
        menu_state.file_menu_open = not menu_state.file_menu_open
        update_menu_state()
    end)

    -- Close File menu
    event.register("close_file_menu", function(payload)
        menu_state.file_menu_open = false
        update_menu_state()
    end)

    -- File -> Home action
    event.register("menu_file_home", function(payload)
        menu_state.file_menu_open = false
        update_menu_state()

        -- Trigger global event to return to launcher
        event.trigger_global("return_to_launcher", {})
    end)

    -- File -> Close action
    event.register("menu_file_close", function(payload)
        menu_state.file_menu_open = false
        update_menu_state()

        -- Trigger global event to close application
        event.trigger_global("close_application", {})
    end)
end

-- Register global event handlers (cross-thread communication)
function register_global_events()
    -- Allow other threads to programmatically open/close menus if needed
    event.register_global("open_file_menu", function(payload)
        menu_state.file_menu_open = true
        update_menu_state()
    end)

    event.register_global("close_all_menus", function(payload)
        menu_state.file_menu_open = false
        update_menu_state()
    end)
end

function startup()
    print("Menu system starting...")

    -- Register event handlers
    register_local_events()
    register_global_events()

    -- Load menu UI
    ui.load_document("ui/internal/menu.rml", true, MENU_DOC_ID)

    -- Initialize menu state
    update_menu_state()

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
