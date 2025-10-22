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
    print("Notifications database opened successfully")

    -- Create notifications table
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
            action_event TEXT
        )
    ]])

    if not success then
        print("Error creating notifications table: " .. exec_error)
        return false
    end

    print("Notifications table ready")
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

-- Add a new notification
function add_notification(notif)
    if not database then
        print("ERROR: Notifications database not initialized")
        return false
    end

    -- Validate required fields
    local notif_type = notif.type or "info"
    local title = notif.title or "Notification"
    local message = notif.message or ""
    local source = notif.source or ""
    local action_label = notif.action_label or ""
    local action_event = notif.action_event or ""
    local timestamp = os.time()

    -- Escape single quotes for SQL
    local escaped_title = title:gsub("'", "''")
    local escaped_message = message:gsub("'", "''")
    local escaped_type = notif_type:gsub("'", "''")
    local escaped_source = source:gsub("'", "''")
    local escaped_action_label = action_label:gsub("'", "''")
    local escaped_action_event = action_event:gsub("'", "''")

    local sql = string.format([[
        INSERT INTO notifications (timestamp, type, title, message, source, action_label, action_event)
        VALUES (%d, '%s', '%s', '%s', '%s', '%s', '%s')
    ]], timestamp, escaped_type, escaped_title, escaped_message, escaped_source,
       escaped_action_label, escaped_action_event)

    local success, error = database:execute(sql)
    if not success then
        print("Error adding notification: " .. error)
        return false
    end

    print("Added notification: " .. title)
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

    print("Marked notification as read: " .. notification_id)
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

    print("Dismissed notification: " .. notification_id)
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

    print("Dismissed all notifications")
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
    event.register("add_notification", function(payload)
        add_notification(payload)
    end)

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
        print("Notifications UI " .. (ui_state.expanded and "expanded" or "collapsed"))

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
        print("Notifications UI collapsed")

        -- Show badge, hide panel
        ui.hide_document(PANEL_DOC_ID)
        ui.show_document(BADGE_DOC_ID)

        update_ui_state()
    end)

    event.register("show_notifications", function(payload)
        ui_state.expanded = true
        print("Notifications UI expanded")

        -- Show panel, hide badge
        ui.hide_document(BADGE_DOC_ID)
        ui.show_document(PANEL_DOC_ID)

        update_ui_state()
    end)

    -- Start with UI collapsed (badge visible)
    ui_state.expanded = false

    -- Load notifications and bind data BEFORE loading UI
    load_notifications()

    -- update_ui_state is called by load_notifications, but we need to ensure it's set
    -- This guarantees the data models exist before UI loads
    update_ui_state()

    -- Load both UI documents
    -- Badge is shown by default, panel is hidden
    -- Data models are prioritized in command queue, so they'll be processed first
    ui.load_document("ui/notifications_badge.rml", true, BADGE_DOC_ID)
    ui.load_document("ui/notifications_panel.rml", false, PANEL_DOC_ID)

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
