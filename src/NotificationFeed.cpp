#include "NotificationFeed.h"
#include "Logger.h"
#include <sstream>
#include <iomanip>

NotificationFeed::NotificationFeed() {
}

void NotificationFeed::AddNotification(Notification&& notification) {
    // Add to front (most recent first) - using vector insert
    notifications_.insert(notifications_.begin(), std::move(notification));

    // Trim if exceeds max
    if (notifications_.size() > max_notifications_) {
        notifications_.resize(max_notifications_);
    }

    // Trigger change callback
    TriggerChange();
}


void NotificationFeed::Dismiss(const std::string& notification_id) {
    for (auto it = notifications_.begin(); it != notifications_.end(); ++it) {
        if (it->id == notification_id) {
            notifications_.erase(it);
            TriggerChange();
            return;
        }
    }
}

void NotificationFeed::Clear() {
    if (notifications_.empty()) {
        return;  // No change
    }

    notifications_.clear();
    TriggerChange();
}

const Notification* NotificationFeed::Get(const std::string& notification_id) const {
    for (const auto& notif : notifications_) {
        if (notif.id == notification_id) {
            return &notif;
        }
    }
    return nullptr;
}

void NotificationFeed::CleanupExpired() {
    double current_time = GetCurrentTime();

    bool any_removed = false;

    // Remove notifications that have expired (TTL > 0 and time exceeded)
    auto it = notifications_.begin();
    while (it != notifications_.end()) {
        if (it->ttl_seconds > 0.0) {
            double elapsed = current_time - it->timestamp;
            if (elapsed >= it->ttl_seconds) {
                it = notifications_.erase(it);
                any_removed = true;
                continue;
            }
        }
        ++it;
    }

    // Only trigger change if we actually removed something
    if (any_removed) {
        TriggerChange();
    }
}

void NotificationFeed::TriggerChange() {
    if (on_change_callback_) {
        on_change_callback_();
    }
}

std::string NotificationFeed::GenerateId() {
    auto now = std::chrono::system_clock::now();
    auto now_ms = std::chrono::time_point_cast<std::chrono::milliseconds>(now);
    auto value = now_ms.time_since_epoch();
    long long millis = value.count();

    std::ostringstream oss;
    oss << "notif_" << millis;
    return oss.str();
}

double NotificationFeed::GetCurrentTime() {
    auto now = std::chrono::system_clock::now();
    auto duration = now.time_since_epoch();
    auto seconds = std::chrono::duration_cast<std::chrono::seconds>(duration);
    return static_cast<double>(seconds.count());
}
