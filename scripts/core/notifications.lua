-- Notifications System
-- First native Lua plugin for vah
-- Provides a notification system with SQL backend and data binding frontend

-- Configuration constants
local REFRESH_INTERVAL = 0.5  -- Seconds between notification refresh (to remove expired ones)
local MAX_RECENT_ACTIONS = 10  -- Maximum number of recent actions to track
local DEFAULT_TTL = 5.0  -- Default time-to-live for notifications in seconds

local database = nil
local notifications = {}
local ui_state = {
    expanded = false  -- Track whether UI is expanded or collapsed
}
local time_since_refresh = 0.0  -- Track time since last notification refresh
local expanded_notifications = {}  -- Track which notifications are expanded by ID

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
            content_format TEXT DEFAULT 'text',
            ttl REAL DEFAULT 0,
            actions_json TEXT
        )
    ]])

    if not success then
        print("Error creating notifications table: " .. exec_error)
        return false
    end

    -- Create indexes for common queries
    -- Index for load query: WHERE dismissed = 0 AND (ttl = 0 OR (timestamp + ttl) > ?) ORDER BY timestamp DESC
    local idx_success, idx_error = database:execute([[
        CREATE INDEX IF NOT EXISTS idx_notifications_active
        ON notifications (dismissed, ttl, timestamp DESC)
    ]])

    if not idx_success then
        print("Warning: Failed to create index idx_notifications_active: " .. idx_error)
    end

    -- Index for cleanup query: WHERE dismissed = 1 OR (ttl > 0 AND (timestamp + ttl) <= ?)
    local idx2_success, idx2_error = database:execute([[
        CREATE INDEX IF NOT EXISTS idx_notifications_cleanup
        ON notifications (dismissed, ttl, timestamp)
    ]])

    if not idx2_success then
        print("Warning: Failed to create index idx_notifications_cleanup: " .. idx2_error)
    end

    return true
end

-- Load notifications from database
function load_notifications()
    if not database then
        return
    end

    -- Query active (non-dismissed, non-expired) notifications, most recent first
    -- ttl = 0 means persist until dismissed
    -- ttl > 0 means auto-expire after ttl seconds from timestamp
    local current_time = os.time()
    local sql = [[
        SELECT * FROM notifications
        WHERE dismissed = 0
          AND (ttl = 0 OR (timestamp + ttl) > ?)
        ORDER BY timestamp DESC
    ]]

    local results, error = database:query(sql, current_time)

    if error ~= "" then
        print("Error loading notifications: " .. error)
        return
    end

    notifications = results or {}

    -- Add expanded state to each notification
    for _, notif in ipairs(notifications) do
        notif.is_expanded = expanded_notifications[notif.id] and 1 or 0
    end

    -- Bind data to the model (triggers UI update)
    datamodel.bind_table("notifications", notifications)

    -- Update UI state with notification count
    update_ui_state()
end

-- Update UI state data model
function update_ui_state()
    -- Bind as a single object (not an array)
    datamodel.bind_object("notification_ui_state", {
        expanded = ui_state.expanded and 1 or 0,
        count = #notifications
    })
end

-- Helper to encode actions as JSON
local function encode_actions(actions)
    if not actions or type(actions) ~= "table" or #actions == 0 then
        return ""
    end

    local parts = {}
    for _, action in ipairs(actions) do
        local id = (action.id or ""):gsub('"', '\\"')  -- Escape quotes for JSON
        local label = (action.label or ""):gsub('"', '\\"')
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
    local content_format = notif.content_format or "text"  -- "text" or "markup"
    local ttl = notif.ttl or DEFAULT_TTL
    local actions_json = encode_actions(notif.actions)
    local timestamp = os.time()

    local sql = [[
        INSERT INTO notifications (timestamp, type, title, message, source, action_label, action_event,
                                   dismissible, expandable, expanded_content, content_format, ttl, actions_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]]

    local success, error = database:query(sql,
        timestamp, notif_type, title, message, source,
        action_label, action_event, dismissible, expandable,
        expanded_content, content_format, ttl, actions_json)
    if not success then
        print("Error adding notification: " .. error)
        return false
    end

    print(string.format("Added notification: '%s' (type=%s, ttl=%.1f, timestamp=%d, expires=%d)",
        title, notif_type, ttl, timestamp, timestamp + ttl))

    load_notifications()  -- Re-query and update UI
    return true
end

-- Mark a notification as read
function mark_read(notification_id)
    if not database then
        return false
    end

    local sql = [[
        UPDATE notifications
        SET read = 1
        WHERE id = ?
    ]]

    local success, error = database:query(sql, notification_id)
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

    local sql = [[
        UPDATE notifications
        SET dismissed = 1
        WHERE id = ?
    ]]

    local success, error = database:query(sql, notification_id)
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

    local sql = [[
        UPDATE notifications
        SET dismissed = 1
        WHERE dismissed = 0
    ]]

    local success, error = database:query(sql)

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

    -- Dispatch the action event globally
    event.trigger_global(action_event, {
        notification_id = notification_id
    })
end

-- Helper functions for common notification types
local function success(title, message)
    return add_notification({
        type = "success",
        title = title,
        message = message or "",
        dismissible = true,
        ttl = DEFAULT_TTL
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
        ttl = DEFAULT_TTL
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
        source = "system",
        ttl = 0  -- Persist until dismissed
    })

    add_notification({
        type = "success",
        title = "Task Complete",
        message = "File processing finished successfully",
        source = "file_processor",
        ttl = 0  -- Persist until dismissed
    })

    add_notification({
        type = "warning",
        title = "Low Memory",
        message = "Available memory is below 20%",
        source = "system_monitor",
        ttl = 0  -- Persist until dismissed
    })

    add_notification({
        type = "error",
        title = "Build Failed",
        message = "Compilation error in main.cpp line 42",
        source = "build_system",
        expandable = 1,
        content_format = "text",
        ttl = 0,  -- Persist until dismissed
        expanded_content = "Error details:\n  File: main.cpp\n  Line: 42\n  Error: undefined reference to 'calculateSum'\n\nStack trace:\n  1. main() at main.cpp:42\n  2. calculateTotal() at utils.cpp:15\n\nSuggested fix:\nEnsure calculateSum() is declared in the header file."
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

    event.register("toggle_notification_expand", function(payload)
        if payload.id then
            local notif_id = payload.id
            -- Toggle expanded state
            if expanded_notifications[notif_id] then
                expanded_notifications[notif_id] = nil
            else
                expanded_notifications[notif_id] = true
            end
            load_notifications()  -- Refresh to update UI
        end
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
    ui.load_document("ui/core/notifications/notifications_badge.rml", true, BADGE_DOC_ID)
    ui.load_document("ui/core/notifications/notifications_panel.rml", false, PANEL_DOC_ID)

    print("Notifications system ready")
end

-- Update loop
function update(dt)
    -- Refresh notifications periodically to remove expired ones
    time_since_refresh = time_since_refresh + dt
    if time_since_refresh >= REFRESH_INTERVAL then
        load_notifications()
        time_since_refresh = 0.0
    end
end

-- Cleanup old notifications from database
function cleanup_old_notifications()
    if not database then
        return
    end

    -- Delete notifications that are dismissed or expired
    local current_time = os.time()
    local sql = [[
        DELETE FROM notifications
        WHERE dismissed = 1
           OR (ttl > 0 AND (timestamp + ttl) <= ?)
    ]]

    local success, error = database:query(sql, current_time)

    if not success then
        print("Error cleaning up old notifications: " .. error)
    else
        print("Old notifications cleaned up")
    end
end

-- Shutdown
function shutdown()
    if database then
        cleanup_old_notifications()
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
