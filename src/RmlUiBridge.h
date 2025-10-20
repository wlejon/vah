#pragma once

#include <RmlUi/Core.h>
#include <RmlUi/Lua.h>
#include <string>
#include "InputState.h"
#include "DomIntrospection.h"

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

private:
    EventDispatcher* event_dispatcher_;
    Rml::Context* context_;
    DataStore* data_store_;
    std::string current_document_id_;
};
