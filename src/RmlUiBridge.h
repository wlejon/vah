#pragma once

#include <RmlUi/Core.h>
#include <RmlUi/Lua.h>
#include <string>
#include "InputState.h"
#include "DomIntrospection.h"
#include "KeybindingRegistry.h"

class DataStore;  // Forward declaration
class EventDispatcher;  // Forward declaration

class RmlUiBridge {
public:
    RmlUiBridge(EventDispatcher* event_dispatcher);
    ~RmlUiBridge() = default;

    void SetupLuaBindings(lua_State* L, Rml::Context* context, DataStore* data_store);
    void TriggerEvent(const std::string& event_name, const PayloadMap& payload, const std::string& document_id);
    void SetCurrentDocument(const std::string& document_id) { current_document_id_ = document_id; }
    std::string GetCurrentDocument() const { return current_document_id_; }
    Rml::Context* GetContext() const { return context_; }
    EventDispatcher* GetEventDispatcher() const { return event_dispatcher_; }

    // Process keyboard event and check for command mappings
    // Returns true if a command was emitted, false otherwise
    bool ProcessKeyboardEvent(Rml::Input::KeyIdentifier key, int modifiers, Rml::Element* focused_element);

    // Get keybinding registry for configuration
    KeybindingRegistry& GetKeybindingRegistry() { return keybinding_registry_; }

private:
    EventDispatcher* event_dispatcher_;
    Rml::Context* context_;
    DataStore* data_store_;
    std::string current_document_id_;
    KeybindingRegistry keybinding_registry_;
};
