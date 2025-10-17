#include "NotificationFeed.h"
#include "Logger.h"
#include <sstream>
#include <iomanip>

NotificationFeed::NotificationFeed() {
}

void NotificationFeed::AddNotification(Notification&& notification) {
    // Add to front (most recent first)
    notifications_.push_front(std::move(notification));

    // Trim if exceeds max
    while (notifications_.size() > max_notifications_) {
        notifications_.pop_back();
    }
}

std::vector<Notification> NotificationFeed::GetRecent(size_t count) {
    std::vector<Notification> result;
    size_t limit = std::min(count, notifications_.size());
    result.reserve(limit);

    for (size_t i = 0; i < limit; i++) {
        result.push_back(notifications_[i]);
    }

    return result;
}

void NotificationFeed::Dismiss(const std::string& notification_id) {
    for (auto it = notifications_.begin(); it != notifications_.end(); ++it) {
        if (it->id == notification_id) {
            notifications_.erase(it);
            LOG_INFO("Dismissed notification: {}", notification_id);
            return;
        }
    }
}

void NotificationFeed::Clear() {
    notifications_.clear();
    LOG_INFO("Cleared all notifications");
}

const Notification* NotificationFeed::Get(const std::string& notification_id) const {
    for (const auto& notif : notifications_) {
        if (notif.id == notification_id) {
            return &notif;
        }
    }
    return nullptr;
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
