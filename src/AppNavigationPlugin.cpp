#include "AppNavigationPlugin.h"
#include "Logger.h"
#include <fstream>
#include <sstream>

// Singleton instance
AppNavigationPlugin* AppNavigationPlugin::instance_ = nullptr;

// ElementAppNavDocument implementation
ElementAppNavDocument::ElementAppNavDocument(const Rml::String& tag)
    : Rml::ElementDocument(tag)
{
    // Make focusable even when modal documents exist (like debugger)
    SetFocusableFromModal(true);
}

// AppNavigationPlugin implementation
AppNavigationPlugin::AppNavigationPlugin()
    : host_context_(nullptr)
    , nav_model_handle_(nullptr)
    , nav_document_(nullptr)
    , visible_(false)
{
    instance_ = this;
}

AppNavigationPlugin::~AppNavigationPlugin() {
    if (instance_ == this) {
        instance_ = nullptr;
    }
}

bool AppNavigationPlugin::Initialise(Rml::Context* context, Rml::DataModelHandle* nav_model_handle) {
    if (!context) {
        LOG_ERROR("AppNavigationPlugin::Initialise: Invalid parameters");
        return false;
    }

    host_context_ = context;
    nav_model_handle_ = nav_model_handle;  // Can be nullptr initially

    // Register custom element instancer for navigation documents
    nav_instancer_ = Rml::MakeUnique<Rml::ElementInstancerGeneric<ElementAppNavDocument>>();
    Rml::Factory::RegisterElementInstancer("app-nav-document", nav_instancer_.get());

    // Create navigation document
    nav_document_ = host_context_->CreateDocument("app-nav-document");
    if (!nav_document_) {
        LOG_ERROR("AppNavigationPlugin::Initialise: Failed to create navigation document");
        return false;
    }

    // Mark with special ID so we can identify it
    nav_document_->SetId("vah-app-navigation-overlay");

    // Set high z-index to stay on top (but below notifications)
    nav_document_->SetProperty(Rml::PropertyId::ZIndex, Rml::Property(999998, Rml::Unit::NUMBER));

    // Always visible (contains conditional rendering inside)
    nav_document_->SetProperty(Rml::PropertyId::Visibility, Rml::Property(Rml::Style::Visibility::Visible));

    // Load RML content from file
    std::ifstream rml_file("ui/internal/app_navigation.rml");
    if (!rml_file.is_open()) {
        LOG_ERROR("AppNavigationPlugin::Initialise: Failed to open ui/internal/app_navigation.rml");
        host_context_->UnloadDocument(nav_document_);
        nav_document_ = nullptr;
        return false;
    }

    std::stringstream buffer;
    buffer << rml_file.rdbuf();
    std::string rml_content = buffer.str();
    rml_file.close();

    nav_document_->SetInnerRML(rml_content);

    // Setup event handlers
    SetupEventHandlers();

    visible_ = true;

    LOG_INFO("AppNavigationPlugin initialized successfully");
    return true;
}

void AppNavigationPlugin::Shutdown() {
    ReleaseElements();
    host_context_ = nullptr;
    nav_model_handle_ = nullptr;
}

void AppNavigationPlugin::SetVisible(bool visibility) {
    if (!nav_document_) return;

    visible_ = visibility;

    if (visibility) {
        nav_document_->SetProperty(Rml::PropertyId::Visibility, Rml::Property(Rml::Style::Visibility::Visible));
    } else {
        nav_document_->SetProperty(Rml::PropertyId::Visibility, Rml::Property(Rml::Style::Visibility::Hidden));
    }
}

bool AppNavigationPlugin::IsVisible() const {
    return visible_;
}

void AppNavigationPlugin::MarkDirty() {
    if (!nav_model_handle_) {
        return;
    }

    // Mark the data model as dirty
    nav_model_handle_->DirtyVariable("app_nav");
}

void AppNavigationPlugin::OnContextDestroy(Rml::Context* context) {
    if (context == host_context_) {
        ReleaseElements();
        host_context_ = nullptr;
    }
}

void AppNavigationPlugin::OnElementDestroy(Rml::Element* element) {
    if (element == nav_document_) {
        LOG_ERROR("App navigation overlay document was destroyed externally. This is not allowed.");
        nav_document_ = nullptr;
    }
}

void AppNavigationPlugin::ReleaseElements() {
    if (host_context_ && nav_document_) {
        host_context_->UnloadDocument(nav_document_);
        nav_document_ = nullptr;

        // Update to release documents before the plugin gets deleted
        host_context_->Update();
    }
}

void AppNavigationPlugin::SetupEventHandlers() {
    // Event handlers will be setup in Lua via RmlUi's Lua bindings
    // The onclick attributes in the RML will call Lua functions
}

// Public API implementation
namespace AppNavigationOverlay {

bool Initialise(Rml::Context* context, Rml::DataModelHandle* nav_model_handle) {
    if (AppNavigationPlugin::GetInstance() != nullptr) {
        LOG_WARN("AppNavigationOverlay already initialized");
        return false;
    }

    AppNavigationPlugin* plugin = new AppNavigationPlugin();
    if (!plugin->Initialise(context, nav_model_handle)) {
        delete plugin;
        return false;
    }

    // Register with RmlUi plugin system
    Rml::RegisterPlugin(plugin);

    return true;
}

void Shutdown() {
    AppNavigationPlugin* plugin = AppNavigationPlugin::GetInstance();
    if (plugin) {
        Rml::UnregisterPlugin(plugin);
        plugin->Shutdown();
        delete plugin;
    }
}

void SetVisible(bool visibility) {
    AppNavigationPlugin* plugin = AppNavigationPlugin::GetInstance();
    if (plugin) {
        plugin->SetVisible(visibility);
    }
}

bool IsVisible() {
    AppNavigationPlugin* plugin = AppNavigationPlugin::GetInstance();
    return plugin ? plugin->IsVisible() : false;
}

void MarkDirty() {
    AppNavigationPlugin* plugin = AppNavigationPlugin::GetInstance();
    if (plugin) {
        plugin->MarkDirty();
    }
}

} // namespace AppNavigationOverlay
