-- Notifications System
-- First native Lua plugin for vah
-- Provides a notification system with SQL backend and data binding frontend

local database = nil
local notifications = {}
local ui_state = {
    expanded = false  -- Track whether UI is expanded or collapsed
}

-- Document IDs
local BADGE_DOC_ID = "notifications_badge"
local PANEL_DOC_ID = "notifications_panel"

-- Initialize the notifications database
function init_database()
    -- Open/create database
    local db_handle, error = db.open("data/notifications.db")
    if error ~= "" then
        print("Error opening notifications database: " .. error)
        return false
    end

    database = db_handle

    -- Create notifications table with expanded fields
    local success, exec_error = database:execute([[
        CREATE TABLE IF NOT EXISTS notifications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            type TEXT NOT NULL,
            title TEXT NOT NULL,
            message TEXT NOT NULL,
            dismissed INTEGER DEFAULT 0,
            read INTEGER DEFAULT 0,
            source TEXT,
            action_label TEXT,
            action_event TEXT,
            dismissible INTEGER DEFAULT 1,
            expandable INTEGER DEFAULT 0,
            expanded_content TEXT,
            ttl REAL DEFAULT 0,
            actions_json TEXT
        )
    ]])

    if not success then
        print("Error creating notifications table: " .. exec_error)
        return false
    end

    return true
end

-- Load notifications from database
function load_notifications()
    if not database then
        return
    end

    -- Query active (non-dismissed) notifications, most recent first
    local results, error = database:query([[
        SELECT * FROM notifications
        WHERE dismissed = 0
        ORDER BY timestamp DESC
    ]])

    if error ~= "" then
        print("Error loading notifications: " .. error)
        return
    end

    notifications = results or {}
    print("Loaded " .. #notifications .. " active notifications")

    -- Bind data to the model (triggers UI update)
    data.bind("notifications", notifications)

    -- Update UI state with notification count
    update_ui_state()
end

-- Update UI state data model
function update_ui_state()
    -- Bind as a single-element array so we can access fields directly
    data.bind("notification_ui_state", {{
        expanded = ui_state.expanded and 1 or 0,
        count = #notifications
    }})
end

-- Helper to escape SQL strings
local function escape_sql(str)
    if type(str) ~= "string" then
        return ""
    end
    return str:gsub("'", "''")
end

-- Helper to encode actions as JSON
local function encode_actions(actions)
    if not actions or type(actions) ~= "table" or #actions == 0 then
        return ""
    end

    local parts = {}
    for _, action in ipairs(actions) do
        local id = escape_sql(action.id or "")
        local label = escape_sql(action.label or "")
        table.insert(parts, string.format('{"id":"%s","label":"%s"}', id, label))
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

-- Add a new notification
function add_notification(notif)
    if not database then
        print("ERROR: Notifications database not initialized")
        return false
    end

    -- Map numeric type to string type (for backward compatibility)
    local type_map = {
        [0] = "info",
        [1] = "success",
        [2] = "warning",
        [3] = "error",
        [4] = "progress",
        [5] = "question"
    }

    -- Validate required fields
    local notif_type = notif.type
    if type(notif_type) == "number" then
        notif_type = type_map[notif_type] or "info"
    elseif type(notif_type) ~= "string" then
        notif_type = "info"
    end

    local title = notif.title or "Notification"
    local message = notif.message or ""
    local source = notif.source or notif.thread or ""
    local action_label = notif.action_label or ""
    local action_event = notif.action_event or ""
    local dismissible = (notif.dismissible == nil) and 1 or (notif.dismissible and 1 or 0)
    local expandable = notif.expandable and 1 or 0
    local expanded_content = notif.expanded_content or ""
    local ttl = notif.ttl or 5.0
    local actions_json = encode_actions(notif.actions)
    local timestamp = os.time()

    -- Escape single quotes for SQL
    local escaped_title = escape_sql(title)
    local escaped_message = escape_sql(message)
    local escaped_type = escape_sql(notif_type)
    local escaped_source = escape_sql(source)
    local escaped_action_label = escape_sql(action_label)
    local escaped_action_event = escape_sql(action_event)
    local escaped_expanded_content = escape_sql(expanded_content)
    local escaped_actions_json = escape_sql(actions_json)

    local sql = string.format([[
        INSERT INTO notifications (timestamp, type, title, message, source, action_label, action_event,
                                   dismissible, expandable, expanded_content, ttl, actions_json)
        VALUES (%d, '%s', '%s', '%s', '%s', '%s', '%s', %d, %d, '%s', %f, '%s')
    ]], timestamp, escaped_type, escaped_title, escaped_message, escaped_source,
       escaped_action_label, escaped_action_event, dismissible, expandable,
       escaped_expanded_content, ttl, escaped_actions_json)

    local success, error = database:execute(sql)
    if not success then
        print("Error adding notification: " .. error)
        return false
    end

    load_notifications()  -- Re-query and update UI
    return true
end

-- Mark a notification as read
function mark_read(notification_id)
    if not database then
        return false
    end

    local sql = string.format([[
        UPDATE notifications
        SET read = 1
        WHERE id = %d
    ]], notification_id)

    local success, error = database:execute(sql)
    if not success then
        print("Error marking notification as read: " .. error)
        return false
    end

    load_notifications()
    return true
end

-- Dismiss a notification
function dismiss_notification(notification_id)
    if not database then
        return false
    end

    local sql = string.format([[
        UPDATE notifications
        SET dismissed = 1
        WHERE id = %d
    ]], notification_id)

    local success, error = database:execute(sql)
    if not success then
        print("Error dismissing notification: " .. error)
        return false
    end

    load_notifications()
    return true
end

-- Dismiss all notifications
function dismiss_all()
    if not database then
        return false
    end

    local success, error = database:execute([[
        UPDATE notifications
        SET dismissed = 1
        WHERE dismissed = 0
    ]])

    if not success then
        print("Error dismissing all notifications: " .. error)
        return false
    end

    load_notifications()
    return true
end

-- Handle notification action (custom action button clicked)
function handle_action(notification_id, action_event)
    if not action_event or action_event == "" then
        return
    end

    print("Notification action triggered: " .. action_event .. " (notification: " .. notification_id .. ")")

    -- Mark as read when action is taken
    mark_read(notification_id)

    -- TODO: Dispatch the action event globally
    -- For now, just print it
    print("Would dispatch event: " .. action_event)
end

-- Helper functions for common notification types
local function success(title, message)
    return add_notification({
        type = "success",
        title = title,
        message = message or "",
        dismissible = true,
        ttl = 5.0
    })
end

local function error(title, message)
    return add_notification({
        type = "error",
        title = title,
        message = message or "",
        dismissible = true,
        ttl = 0  -- Errors persist until dismissed
    })
end

local function info(title, message)
    return add_notification({
        type = "info",
        title = title,
        message = message or "",
        dismissible = true,
        ttl = 5.0
    })
end

local function warning(title, message)
    return add_notification({
        type = "warning",
        title = title,
        message = message or "",
        dismissible = true,
        ttl = 0  -- Warnings persist until dismissed
    })
end

-- Add test notifications (for demonstration)
function add_test_notifications()
    add_notification({
        type = "info",
        title = "System Started",
        message = "Vah notification system is now running",
        source = "system"
    })

    add_notification({
        type = "success",
        title = "Task Complete",
        message = "File processing finished successfully",
        source = "file_processor"
    })

    add_notification({
        type = "warning",
        title = "Low Memory",
        message = "Available memory is below 20%",
        source = "system_monitor"
    })

    add_notification({
        type = "error",
        title = "Build Failed",
        message = "Compilation error in main.cpp line 42",
        source = "build_system",
        action_label = "View Details",
        action_event = "show_build_log"
    })
end

-- Startup
function startup()
    print("Notifications system started")

    -- Initialize database
    if not init_database() then
        print("ERROR: Failed to initialize notifications database")
        return
    end

    -- Register event handlers
    -- Global events - can be triggered by any thread
    event.register_global("add_notification", function(payload)
        add_notification(payload)
    end)

    event.register_global("notification_success", function(payload)
        success(payload.title or "Success", payload.message)
    end)

    event.register_global("notification_error", function(payload)
        error(payload.title or "Error", payload.message)
    end)

    event.register_global("notification_info", function(payload)
        info(payload.title or "Info", payload.message)
    end)

    event.register_global("notification_warning", function(payload)
        warning(payload.title or "Warning", payload.message)
    end)

    -- Local events - only triggered by notification UI (user actions)
    event.register("dismiss_notification", function(payload)
        if payload.id then
            dismiss_notification(payload.id)
        end
    end)

    event.register("dismiss_all_notifications", function(payload)
        dismiss_all()
    end)

    event.register("mark_notification_read", function(payload)
        if payload.id then
            mark_read(payload.id)
        end
    end)

    event.register("notification_action", function(payload)
        if payload.id and payload.action_event then
            handle_action(payload.id, payload.action_event)
        end
    end)

    event.register("add_test_notifications", function(payload)
        add_test_notifications()
    end)

    event.register("toggle_notifications", function(payload)
        ui_state.expanded = not ui_state.expanded

        if ui_state.expanded then
            -- Show panel, hide badge
            ui.hide_document(BADGE_DOC_ID)
            ui.show_document(PANEL_DOC_ID)
        else
            -- Show badge, hide panel
            ui.hide_document(PANEL_DOC_ID)
            ui.show_document(BADGE_DOC_ID)
        end

        update_ui_state()
    end)

    event.register("hide_notifications", function(payload)
        ui_state.expanded = false

        -- Show badge, hide panel
        ui.hide_document(PANEL_DOC_ID)
        ui.show_document(BADGE_DOC_ID)

        update_ui_state()
    end)

    event.register("show_notifications", function(payload)
        ui_state.expanded = true

        -- Show panel, hide badge
        ui.hide_document(BADGE_DOC_ID)
        ui.show_document(PANEL_DOC_ID)

        update_ui_state()
    end)

    -- Start with UI collapsed (badge visible)
    ui_state.expanded = false

    -- Load notifications and bind data BEFORE loading UI
    load_notifications()

    -- Load both UI documents
    -- Badge is shown by default, panel is hidden
    -- Data models are prioritized in command queue, so they'll be processed first
    ui.load_document("ui/internal/notifications_badge.rml", true, BADGE_DOC_ID)
    ui.load_document("ui/internal/notifications_panel.rml", false, PANEL_DOC_ID)

    print("Notifications system ready")
end

-- Update loop
function update(dt)
    -- Nothing needed - command queue handles proper ordering
end

-- Shutdown
function shutdown()
    if database then
        database:close()
    end
    print("Notifications system shutting down")
end

-- Export notification API for use by other threads via global events
-- Other threads can call: event.trigger_global("add_notification", {type = "info", title = "...", ...})
-- Or use helper shortcuts:
--   event.trigger_global("notification_success", {title = "Done", message = "Task completed"})
--   event.trigger_global("notification_error", {title = "Failed", message = "Error occurred"})
--   event.trigger_global("notification_info", {title = "Info", message = "FYI"})
--   event.trigger_global("notification_warning", {title = "Warning", message = "Be careful"})
return {
    add = add_notification,
    success = success,
    error = error,
    info = info,
    warning = warning
}
