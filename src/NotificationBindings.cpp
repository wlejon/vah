#include "NotificationBindings.h"
#include "NotificationFeed.h"
#include "Logger.h"

namespace NotificationBindings {

void SetupBindings(sol::state& lua, NotificationFeed* feed) {
    if (!feed) {
        LOG_ERROR("NotificationBindings: feed is null");
        return;
    }

    auto notif_table = lua.create_table();

    // Add notification from Lua thread
    notif_table["add"] = [feed](sol::table notification_data) {
        Notification notif;
        notif.id = NotificationFeed::GenerateId();
        notif.type = notification_data.get_or("type", 0);
        notif.title = notification_data.get_or<std::string>("title", "");
        notif.message = notification_data.get_or<std::string>("message", "");
        notif.thread_name = notification_data.get_or<std::string>("thread", "Agent");
        notif.timestamp = NotificationFeed::GetCurrentTime();
        notif.dismissible = notification_data.get_or("dismissible", true);
        notif.expandable = notification_data.get_or("expandable", false);
        notif.expanded_content = notification_data.get_or<std::string>("expanded_content", "");

        // Extract metadata if provided
        sol::optional<sol::table> metadata_opt = notification_data.get<sol::optional<sol::table>>("metadata");
        if (metadata_opt) {
            sol::table metadata_table = metadata_opt.value();
            for (const auto& [key, value] : metadata_table) {
                if (key.is<std::string>()) {
                    std::string key_str = key.as<std::string>();

                    if (value.is<bool>()) {
                        notif.metadata[key_str] = value.as<bool>();
                    } else if (value.is<int>()) {
                        notif.metadata[key_str] = value.as<int>();
                    } else if (value.is<double>()) {
                        notif.metadata[key_str] = value.as<double>();
                    } else if (value.is<std::string>()) {
                        notif.metadata[key_str] = value.as<std::string>();
                    }
                }
            }
        }

        feed->AddNotification(std::move(notif));
    };

    // Show progress notification
    notif_table["progress"] = [feed](std::string title, int current, int total) {
        Notification notif;
        notif.id = NotificationFeed::GenerateId();
        notif.type = static_cast<int>(NotificationType::Progress);
        notif.title = title;
        notif.message = std::to_string(current) + " / " + std::to_string(total);
        notif.thread_name = "Worker";
        notif.timestamp = NotificationFeed::GetCurrentTime();
        notif.dismissible = false;
        notif.expandable = false;

        feed->AddNotification(std::move(notif));
    };

    // Show success notification
    notif_table["success"] = [feed](std::string title, sol::optional<std::string> message) {
        Notification notif;
        notif.id = NotificationFeed::GenerateId();
        notif.type = static_cast<int>(NotificationType::Success);
        notif.title = title;
        notif.message = message.value_or("");
        notif.thread_name = "System";
        notif.timestamp = NotificationFeed::GetCurrentTime();
        notif.dismissible = true;
        notif.expandable = false;

        feed->AddNotification(std::move(notif));
    };

    // Show error notification
    notif_table["error"] = [feed](std::string title, sol::optional<std::string> message) {
        Notification notif;
        notif.id = NotificationFeed::GenerateId();
        notif.type = static_cast<int>(NotificationType::Error);
        notif.title = title;
        notif.message = message.value_or("");
        notif.thread_name = "System";
        notif.timestamp = NotificationFeed::GetCurrentTime();
        notif.dismissible = true;
        notif.expandable = false;

        feed->AddNotification(std::move(notif));
    };

    // Show info notification
    notif_table["info"] = [feed](std::string title, sol::optional<std::string> message) {
        Notification notif;
        notif.id = NotificationFeed::GenerateId();
        notif.type = static_cast<int>(NotificationType::Info);
        notif.title = title;
        notif.message = message.value_or("");
        notif.thread_name = "System";
        notif.timestamp = NotificationFeed::GetCurrentTime();
        notif.dismissible = true;
        notif.expandable = false;

        feed->AddNotification(std::move(notif));
    };

    // Clear all notifications
    notif_table["clear"] = [feed]() {
        feed->Clear();
    };

    // Dismiss specific notification
    notif_table["dismiss"] = [feed](std::string notification_id) {
        feed->Dismiss(notification_id);
    };

    lua["notifications"] = notif_table;

    LOG_INFO("Notification bindings initialized");
}

} // namespace NotificationBindings
