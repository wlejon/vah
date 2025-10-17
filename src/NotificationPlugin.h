#pragma once

#include <RmlUi/Core.h>
#include "NotificationFeed.h"

// Custom notification document element type
class ElementNotificationDocument : public Rml::ElementDocument {
public:
    ElementNotificationDocument(const Rml::String& tag);
};

// Global notification overlay plugin
class NotificationPlugin : public Rml::Plugin {
public:
    NotificationPlugin();
    ~NotificationPlugin();

    // Initialize notification overlay on a context
    bool Initialise(Rml::Context* context, NotificationFeed* notification_feed,
                    std::vector<Notification>* notification_cache,
                    Rml::DataModelHandle* notif_model_handle,
                    int* notification_count);

    // Shutdown and cleanup
    void Shutdown();

    // Toggle notification visibility
    void SetVisible(bool visibility);
    bool IsVisible() const;

    // Update notification data (call when feed changes)
    // Returns true if update was performed, false if throttled
    bool Update();

    // Plugin lifecycle callbacks
    void OnContextDestroy(Rml::Context* context) override;
    void OnElementDestroy(Rml::Element* element) override;

    // Singleton access
    static NotificationPlugin* GetInstance() { return instance_; }

private:
    void ReleaseElements();
    void SetupEventHandlers();

    Rml::Context* host_context_;
    NotificationFeed* notification_feed_;
    std::vector<Notification>* notification_cache_;
    Rml::DataModelHandle* notif_model_handle_;
    int* notification_count_;

    Rml::ElementDocument* notification_document_;

    Rml::UniquePtr<Rml::ElementInstancer> notification_instancer_;

    bool visible_;

    // Throttling for updates
    double last_update_time_ = 0.0;
    double update_throttle_seconds_ = 0.1;  // Max 10 updates per second

    static NotificationPlugin* instance_;
};

namespace NotificationOverlay {
    // Public API
    bool Initialise(Rml::Context* context, NotificationFeed* notification_feed,
                    std::vector<Notification>* notification_cache,
                    Rml::DataModelHandle* notif_model_handle,
                    int* notification_count);
    void Shutdown();
    void SetVisible(bool visibility);
    bool IsVisible();
    bool Update();
}
