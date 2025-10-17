#pragma once

#include <string>
#include <vector>
#include <memory>
#include <chrono>
#include <functional>
#include "InputState.h"

enum class NotificationType {
    Info = 0,           // General information (blue)
    Progress = 1,       // Long-running operation (cyan)
    Success = 2,        // Completed operation (green)
    Warning = 3,        // Attention needed (yellow)
    Error = 4,          // Operation failed (red)
    AgentQuestion = 5,  // Agent asking user question (purple)
    AgentThinking = 6,  // Agent processing (gray, animated)
    FileOperation = 7   // File create/modify/delete (orange)
};

struct Notification {
    std::string id;                      // Unique ID (timestamp-based)
    int type;                            // NotificationType as int for data binding
    std::string title;                   // Brief description
    std::string message;                 // Detailed message (optional)
    std::string thread_name;             // Which thread/agent
    double timestamp;                    // When created (seconds since epoch)
    bool dismissible;                    // Can user dismiss?
    bool expandable;                     // Has detailed view?
    std::string expanded_content;        // RML content for expanded view
    PayloadMap metadata;                 // Command-specific data
    double ttl_seconds = 5.0;            // Time to live in seconds (0 = persist forever)
};

class NotificationFeed {
public:
    using OnChangeCallback = std::function<void()>;

    NotificationFeed();
    ~NotificationFeed() = default;

    // Add notification to feed (triggers onChange callback)
    void AddNotification(Notification&& notification);

    // Direct access to notifications vector for data binding
    std::vector<Notification>& GetNotifications() { return notifications_; }
    const std::vector<Notification>& GetNotifications() const { return notifications_; }

    // Get count for data binding
    int GetCount() const { return static_cast<int>(notifications_.size()); }

    // Dismiss a notification (triggers onChange callback)
    void Dismiss(const std::string& notification_id);

    // Clear all notifications (triggers onChange callback)
    void Clear();

    // Get notification by ID (for expansion)
    const Notification* Get(const std::string& notification_id) const;

    // Remove expired notifications based on TTL (triggers onChange callback if any removed)
    void CleanupExpired();

    // Set callback for when notifications change
    void SetOnChangeCallback(OnChangeCallback callback) { on_change_callback_ = callback; }

    // Generate unique notification ID
    static std::string GenerateId();

    // Get current timestamp
    static double GetCurrentTime();

private:
    void TriggerChange();  // Call after modifications to notify listeners

    std::vector<Notification> notifications_;  // Most recent first
    size_t max_notifications_ = 200;           // Keep last 200
    OnChangeCallback on_change_callback_;      // Called when notifications change
};
