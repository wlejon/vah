#pragma once

#include <RmlUi/Core.h>

// Custom ElementDocument that can be focused even when modal documents exist
class ElementAppNavDocument : public Rml::ElementDocument {
public:
    ElementAppNavDocument(const Rml::String& tag);
};

// Plugin for managing the app navigation overlay
class AppNavigationPlugin : public Rml::Plugin {
public:
    AppNavigationPlugin();
    ~AppNavigationPlugin();

    bool Initialise(Rml::Context* context, Rml::DataModelHandle* nav_model_handle);
    void Shutdown();

    void SetVisible(bool visibility);
    bool IsVisible() const;

    void MarkDirty();

    // Plugin interface
    void OnContextDestroy(Rml::Context* context) override;
    void OnElementDestroy(Rml::Element* element) override;

    static AppNavigationPlugin* GetInstance() { return instance_; }

private:
    void ReleaseElements();
    void SetupEventHandlers();

    Rml::Context* host_context_;
    Rml::DataModelHandle* nav_model_handle_;
    Rml::ElementDocument* nav_document_;
    Rml::UniquePtr<Rml::ElementInstancer> nav_instancer_;
    bool visible_;

    static AppNavigationPlugin* instance_;
};

// Public API for app navigation overlay
namespace AppNavigationOverlay {
    bool Initialise(Rml::Context* context, Rml::DataModelHandle* nav_model_handle);
    void Shutdown();
    void SetVisible(bool visibility);
    bool IsVisible();
    void MarkDirty();
} // namespace AppNavigationOverlay
