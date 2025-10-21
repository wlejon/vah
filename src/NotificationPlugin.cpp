#include "NotificationPlugin.h"
#include "Logger.h"
#include <fstream>
#include <sstream>

// Singleton instance
NotificationPlugin* NotificationPlugin::instance_ = nullptr;

// ElementNotificationDocument implementation
ElementNotificationDocument::ElementNotificationDocument(const Rml::String& tag)
    : Rml::ElementDocument(tag)
{
    // Make focusable even when modal documents exist (like debugger)
    SetFocusableFromModal(true);
}

// NotificationPlugin implementation
NotificationPlugin::NotificationPlugin()
    : host_context_(nullptr)
    , notification_feed_(nullptr)
    , notif_model_handle_(nullptr)
    , notification_document_(nullptr)
    , visible_(false)
{
    instance_ = this;
}

NotificationPlugin::~NotificationPlugin() {
    if (instance_ == this) {
        instance_ = nullptr;
    }
}

bool NotificationPlugin::Initialise(Rml::Context* context, NotificationFeed* notification_feed,
                                    Rml::DataModelHandle* notif_model_handle) {
    if (!context || !notification_feed || !notif_model_handle) {
        LOG_ERROR("NotificationPlugin::Initialise: Invalid parameters");
        return false;
    }

    host_context_ = context;
    notification_feed_ = notification_feed;
    notif_model_handle_ = notif_model_handle;

    // Register custom element instancer for notification documents
    notification_instancer_ = Rml::MakeUnique<Rml::ElementInstancerGeneric<ElementNotificationDocument>>();
    Rml::Factory::RegisterElementInstancer("notification-document", notification_instancer_.get());

    // Create notification document
    notification_document_ = host_context_->CreateDocument("notification-document");
    if (!notification_document_) {
        LOG_ERROR("NotificationPlugin::Initialise: Failed to create notification document");
        return false;
    }

    // Mark with special ID so we can identify it
    notification_document_->SetId("vah-notification-overlay");

    // Set high z-index to stay on top
    notification_document_->SetProperty(Rml::PropertyId::ZIndex, Rml::Property(999999, Rml::Unit::NUMBER));

    // Initially hidden
    notification_document_->SetProperty(Rml::PropertyId::Visibility, Rml::Property(Rml::Style::Visibility::Hidden));

    // Load RML content from file
    std::ifstream rml_file("ui/internal/notification_overlay.rml");
    if (!rml_file.is_open()) {
        LOG_ERROR("NotificationPlugin::Initialise: Failed to open ui/internal/notification_overlay.rml");
        host_context_->UnloadDocument(notification_document_);
        notification_document_ = nullptr;
        return false;
    }

    std::stringstream buffer;
    buffer << rml_file.rdbuf();
    std::string rml_content = buffer.str();
    rml_file.close();

    notification_document_->SetInnerRML(rml_content);

    // Setup event handlers
    SetupEventHandlers();

    LOG_INFO("NotificationPlugin initialized successfully");
    return true;
}

void NotificationPlugin::Shutdown() {
    ReleaseElements();
    host_context_ = nullptr;
    notification_feed_ = nullptr;
}

void NotificationPlugin::SetVisible(bool visibility) {
    if (!notification_document_) return;

    visible_ = visibility;

    if (visibility) {
        notification_document_->SetProperty(Rml::PropertyId::Visibility, Rml::Property(Rml::Style::Visibility::Visible));
    } else {
        notification_document_->SetProperty(Rml::PropertyId::Visibility, Rml::Property(Rml::Style::Visibility::Hidden));
        // Also hide the stream when closing overlay
        Rml::Element* stream = notification_document_->GetElementById("notification-stream");
        if (stream) {
            stream->SetClass("active", false);
        }
    }
}

bool NotificationPlugin::IsVisible() const {
    return visible_;
}

void NotificationPlugin::MarkDirty() {
    if (!notif_model_handle_) {
        return;
    }

    // Immediately mark the data model as dirty
    // RmlUi will re-evaluate on next render
    notif_model_handle_->DirtyVariable("notifications");
    notif_model_handle_->DirtyVariable("count");
}

void NotificationPlugin::CleanupExpired() {
    if (!notification_feed_) {
        return;
    }

    // Mark expired notifications for removal
    notification_feed_->CleanupExpired();

    // Process all pending removals (deferred cleanup)
    notification_feed_->ProcessPendingRemovals();
}

void NotificationPlugin::OnContextDestroy(Rml::Context* context) {
    if (context == host_context_) {
        ReleaseElements();
        host_context_ = nullptr;
    }
}

void NotificationPlugin::OnElementDestroy(Rml::Element* element) {
    if (element == notification_document_) {
        LOG_ERROR("Notification overlay document was destroyed externally. This is not allowed.");
        notification_document_ = nullptr;
    }
}

void NotificationPlugin::ReleaseElements() {
    if (host_context_ && notification_document_) {
        host_context_->UnloadDocument(notification_document_);
        notification_document_ = nullptr;

        // Update to release documents before the plugin gets deleted.
        // Helps avoid cleanup crashes.
        host_context_->Update();
    }
}

void NotificationPlugin::SetupEventHandlers() {
    // Event handlers will be setup in Lua via RmlUi's Lua bindings
    // The onclick attributes in the RML will call Lua functions
}

// Public API implementation
namespace NotificationOverlay {

bool Initialise(Rml::Context* context, NotificationFeed* notification_feed,
                Rml::DataModelHandle* notif_model_handle) {
    if (NotificationPlugin::GetInstance() != nullptr) {
        LOG_WARN("NotificationOverlay already initialized");
        return false;
    }

    NotificationPlugin* plugin = new NotificationPlugin();
    if (!plugin->Initialise(context, notification_feed, notif_model_handle)) {
        delete plugin;
        return false;
    }

    // Register with RmlUi plugin system
    Rml::RegisterPlugin(plugin);

    // Note: Callback is setup in main.cpp to update cache and mark dirty
    return true;
}

void Shutdown() {
    NotificationPlugin* plugin = NotificationPlugin::GetInstance();
    if (plugin) {
        Rml::UnregisterPlugin(plugin);
        plugin->Shutdown();
        delete plugin;
    }
}

void SetVisible(bool visibility) {
    NotificationPlugin* plugin = NotificationPlugin::GetInstance();
    if (plugin) {
        plugin->SetVisible(visibility);
    }
}

bool IsVisible() {
    NotificationPlugin* plugin = NotificationPlugin::GetInstance();
    return plugin ? plugin->IsVisible() : false;
}

void MarkDirty() {
    NotificationPlugin* plugin = NotificationPlugin::GetInstance();
    if (plugin) {
        plugin->MarkDirty();
    }
}

void CleanupExpired() {
    NotificationPlugin* plugin = NotificationPlugin::GetInstance();
    if (plugin) {
        plugin->CleanupExpired();
    }
}

} // namespace NotificationOverlay
