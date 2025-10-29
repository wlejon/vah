-- Menu System
-- Core system for application navigation
-- Provides a dynamic menu bar where apps can register their menus

-- Menu registry (key = menu_id, value = menu definition)
local menu_registry = {}

-- Menu data for RML binding (sorted array)
local menu_data = {}

-- Document ID
local MENU_DOC_ID = "app_menu"

-- Generate menu data array for RML binding
function generate_menu_data()
    -- Convert registry to sorted array
    local menus = {}
    for menu_id, menu_def in pairs(menu_registry) do
        local menu_copy = {
            menu_id = menu_def.menu_id,
            label = menu_def.label,
            position = menu_def.position or 999,
            open = menu_def.open or 0,
            status_indicator = menu_def.status_indicator and 1 or 0,
            status = menu_def.status or "",
            status_text = menu_def.status_text or "",
            items = {}
        }

        -- Copy items and filter based on show_when_status
        for _, item in ipairs(menu_def.items or {}) do
            local visible = 1

            -- Check if item should be visible based on status
            if item.show_when_status and menu_def.status ~= "" then
                visible = (item.show_when_status == menu_def.status) and 1 or 0
            end

            table.insert(menu_copy.items, {
                item_id = item.item_id,
                label = item.label,
                action = item.action,
                visible = visible
            })
        end

        table.insert(menus, menu_copy)
    end

    -- Sort by position
    table.sort(menus, function(a, b) return a.position < b.position end)

    menu_data = menus
end

-- Update menu data model
function update_menu_data()
    generate_menu_data()
    data.bind("menus", menu_data)
end

-- Register a menu
function handle_menu_register(payload)
    local menu_id = payload.menu_id
    if not menu_id then
        print("ERROR: menu_register requires menu_id")
        return
    end

    -- Store in registry
    menu_registry[menu_id] = {
        menu_id = menu_id,
        label = payload.label or menu_id,
        position = payload.position or 999,
        open = 0,
        items = payload.items or {},
        status_indicator = payload.status_indicator or false,
        status = payload.status or "",
        status_text = payload.status_text or ""
    }

    update_menu_data()
end

-- Unregister a menu
function handle_menu_unregister(payload)
    local menu_id = payload.menu_id
    if not menu_id then
        print("ERROR: menu_unregister requires menu_id")
        return
    end

    menu_registry[menu_id] = nil
    update_menu_data()
end

-- Update menu status (for status indicators like MCP)
function handle_menu_update_status(payload)
    local menu_id = payload.menu_id
    if not menu_id or not menu_registry[menu_id] then
        print("ERROR: menu_update_status for unknown menu: " .. tostring(menu_id))
        return
    end

    local menu = menu_registry[menu_id]
    menu.status = payload.status or menu.status
    menu.status_text = payload.status_text or menu.status_text

    update_menu_data()
end

-- Toggle menu open state
function handle_toggle_menu(payload)
    local menu_id = payload.menu_id
    if not menu_id or not menu_registry[menu_id] then
        return
    end

    local menu = menu_registry[menu_id]

    -- Close all other menus first
    for id, m in pairs(menu_registry) do
        m.open = 0
    end

    -- Toggle this menu
    menu.open = (menu.open == 0) and 1 or 0

    update_menu_data()
end

-- Close a specific menu
function handle_close_menu(payload)
    local menu_id = payload.menu_id
    if not menu_id or not menu_registry[menu_id] then
        return
    end

    menu_registry[menu_id].open = 0
    update_menu_data()
end

-- Close all menus
function handle_close_all_menus(payload)
    for id, menu in pairs(menu_registry) do
        menu.open = 0
    end
    update_menu_data()
end

-- Handle menu item click
function handle_menu_item_click(payload)
    local menu_id = payload.menu_id
    local item_id = payload.item_id

    if not menu_id or not item_id then
        return
    end

    local menu = menu_registry[menu_id]
    if not menu then
        return
    end

    -- Close the menu
    menu.open = 0
    update_menu_data()

    -- Find the item and trigger its action
    for _, item in ipairs(menu.items) do
        if item.item_id == item_id and item.action then
            event.trigger_global(item.action, {})
            break
        end
    end
end

-- Register local event handlers (UI interactions)
function register_local_events()
    event.register("toggle_menu", handle_toggle_menu)
    event.register("close_menu", handle_close_menu)
    event.register("menu_item_click", handle_menu_item_click)
end

-- Register global event handlers (cross-thread communication)
function register_global_events()
    event.register_global("menu_register", handle_menu_register)
    event.register_global("menu_unregister", handle_menu_unregister)
    event.register_global("menu_update_status", handle_menu_update_status)
    event.register_global("close_all_menus", handle_close_all_menus)
end

function startup()
    print("Menu system starting...")

    -- Initialize empty data model FIRST
    update_menu_data()

    -- Register event handlers
    register_local_events()
    register_global_events()

    -- Load menu UI
    ui.load_document("ui/internal/menu.rml", true, MENU_DOC_ID)

    print("Menu system started")

    -- Announce readiness (broadcasts to all threads)
    system.mark_ready("menu")
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
