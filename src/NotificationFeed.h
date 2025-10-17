#pragma once

#include <string>
#include <vector>
#include <deque>
#include <memory>
#include <chrono>
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
    NotificationFeed();
    ~NotificationFeed() = default;

    // Add notification to feed
    void AddNotification(Notification&& notification);

    // Get recent notifications (for data binding)
    std::vector<Notification> GetRecent(size_t count = 50);

    // Get all notifications
    const std::deque<Notification>& GetAll() const { return notifications_; }

    // Dismiss a notification
    void Dismiss(const std::string& notification_id);

    // Clear all notifications
    void Clear();

    // Get notification by ID (for expansion)
    const Notification* Get(const std::string& notification_id) const;

    // Remove expired notifications based on TTL
    void CleanupExpired();

    // Generate unique notification ID
    static std::string GenerateId();

    // Get current timestamp
    static double GetCurrentTime();

private:
    std::deque<Notification> notifications_;  // FIFO queue
    size_t max_notifications_ = 200;          // Keep last 200
};
