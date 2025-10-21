#include "NotificationBindings.h"
#include "NotificationFeed.h"
#include "Commands.h"
#include "Logger.h"

namespace NotificationBindings {

void SetupBindings(sol::state& lua, moodycamel::ConcurrentQueue<Command>* command_queue) {
    if (!command_queue) {
        LOG_ERROR("NotificationBindings: command_queue is null");
        return;
    }

    auto notif_table = lua.create_table();

    // Add notification from Lua thread
    notif_table["add"] = [command_queue](sol::table notification_data, sol::this_state s) {
        sol::state_view lua(s);

        Commands::AddNotification cmd;
        cmd.type = notification_data.get_or("type", 0);
        cmd.title = notification_data.get_or<std::string>("title", "");
        cmd.message = notification_data.get_or<std::string>("message", "");
        cmd.thread_name = notification_data.get_or<std::string>("thread", "Agent");
        cmd.dismissible = notification_data.get_or("dismissible", true);
        cmd.expandable = notification_data.get_or("expandable", false);
        cmd.expanded_content = notification_data.get_or<std::string>("expanded_content", "");
        cmd.ttl_seconds = notification_data.get_or("ttl", 5.0);
        cmd.thread_id = lua["thread_id"].get_or(-1);

        // Extract actions if provided
        sol::optional<sol::table> actions_opt = notification_data.get<sol::optional<sol::table>>("actions");
        if (actions_opt) {
            sol::table actions_table = actions_opt.value();
            for (const auto& [key, value] : actions_table) {
                if (value.is<sol::table>()) {
                    sol::table action_table = value.as<sol::table>();
                    Commands::NotificationActionData action;
                    action.id = action_table.get_or<std::string>("id", "");
                    action.label = action_table.get_or<std::string>("label", "");
                    if (!action.id.empty() && !action.label.empty()) {
                        cmd.actions.push_back(std::move(action));
                    }
                }
            }
        }

        // Extract metadata if provided
        sol::optional<sol::table> metadata_opt = notification_data.get<sol::optional<sol::table>>("metadata");
        if (metadata_opt) {
            sol::table metadata_table = metadata_opt.value();
            for (const auto& [key, value] : metadata_table) {
                if (key.is<std::string>()) {
                    std::string key_str = key.as<std::string>();

                    if (value.is<bool>()) {
                        cmd.metadata[key_str] = value.as<bool>();
                    } else if (value.is<int>()) {
                        cmd.metadata[key_str] = static_cast<int64_t>(value.as<int>());
                    } else if (value.is<double>()) {
                        cmd.metadata[key_str] = value.as<double>();
                    } else if (value.is<std::string>()) {
                        cmd.metadata[key_str] = value.as<std::string>();
                    }
                }
            }
        }

        command_queue->enqueue(cmd);
    };

    // Show progress notification
    notif_table["progress"] = [command_queue](std::string title, int current, int total) {
        Commands::AddNotification cmd;
        cmd.type = static_cast<int>(NotificationType::Progress);
        cmd.title = title;
        cmd.message = std::to_string(current) + " / " + std::to_string(total);
        cmd.thread_name = "Worker";
        cmd.dismissible = false;
        cmd.expandable = false;
        cmd.ttl_seconds = 0.0;  // Progress notifications persist until dismissed

        command_queue->enqueue(cmd);
    };

    // Show success notification
    notif_table["success"] = [command_queue](std::string title, sol::optional<std::string> message) {
        Commands::AddNotification cmd;
        cmd.type = static_cast<int>(NotificationType::Success);
        cmd.title = title;
        cmd.message = message.value_or("");
        cmd.thread_name = "System";
        cmd.dismissible = true;
        cmd.expandable = false;
        cmd.ttl_seconds = 5.0;  // Default TTL

        command_queue->enqueue(cmd);
    };

    // Show error notification
    notif_table["error"] = [command_queue](std::string title, sol::optional<std::string> message) {
        Commands::AddNotification cmd;
        cmd.type = static_cast<int>(NotificationType::Error);
        cmd.title = title;
        cmd.message = message.value_or("");
        cmd.thread_name = "System";
        cmd.dismissible = true;
        cmd.expandable = false;
        cmd.ttl_seconds = 0.0;  // Errors persist until dismissed

        command_queue->enqueue(cmd);
    };

    // Show info notification
    notif_table["info"] = [command_queue](std::string title, sol::optional<std::string> message) {
        Commands::AddNotification cmd;
        cmd.type = static_cast<int>(NotificationType::Info);
        cmd.title = title;
        cmd.message = message.value_or("");
        cmd.thread_name = "System";
        cmd.dismissible = true;
        cmd.expandable = false;
        cmd.ttl_seconds = 5.0;  // Default TTL

        command_queue->enqueue(cmd);
    };

    // Clear all notifications
    notif_table["clear"] = [command_queue]() {
        Commands::ClearNotifications cmd;
        command_queue->enqueue(cmd);
    };

    // Dismiss specific notification
    notif_table["dismiss"] = [command_queue](std::string notification_id) {
        Commands::DismissNotification cmd;
        cmd.notification_id = notification_id;
        command_queue->enqueue(cmd);
    };

    lua["notifications"] = notif_table;

    LOG_INFO("Notification bindings initialized");
}

} // namespace NotificationBindings
