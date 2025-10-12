#pragma once

#include <RmlUi/Core.h>
#include <RmlUi/Lua.h>
#include <string>
#include "InputState.h"
#include "UIEventQueue.h"

class RmlUiBridge {
public:
    RmlUiBridge(UIEventQueue* ui_event_queue);
    ~RmlUiBridge() = default;

    void SetupLuaBindings(lua_State* L, Rml::Context* context);
    void TriggerEvent(const std::string& event_name, const PayloadMap& payload);
    Rml::Context* GetContext() const { return context_; }

private:
    UIEventQueue* ui_event_queue_;
    Rml::Context* context_;
};
