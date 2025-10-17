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
                    Rml::DataModelHandle* notif_model_handle);

    // Shutdown and cleanup
    void Shutdown();

    // Toggle notification visibility
    void SetVisible(bool visibility);
    bool IsVisible() const;

    // Mark data model as dirty (called by NotificationFeed change callback)
    void MarkDirty();

    // Cleanup expired notifications (call periodically, e.g., once per second)
    void CleanupExpired();

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
    Rml::DataModelHandle* notif_model_handle_;

    Rml::ElementDocument* notification_document_;

    Rml::UniquePtr<Rml::ElementInstancer> notification_instancer_;

    bool visible_;

    static NotificationPlugin* instance_;
};

namespace NotificationOverlay {
    // Public API
    bool Initialise(Rml::Context* context, NotificationFeed* notification_feed,
                    Rml::DataModelHandle* notif_model_handle);
    void Shutdown();
    void SetVisible(bool visibility);
    bool IsVisible();
    void MarkDirty();
    void CleanupExpired();
}
