#pragma once

#include <RmlUi/Core.h>
#include <RmlUi/Lua.h>
#include <string>
#include <moodycamel/concurrentqueue.h>
#include "InputState.h"

class RmlUiBridge {
public:
    RmlUiBridge(moodycamel::ConcurrentQueue<UIEvent>* ui_event_queue);
    ~RmlUiBridge() = default;

    void SetupLuaBindings(lua_State* L, Rml::Context* context);
    void TriggerEvent(const std::string& event_name, const PayloadMap& payload);
    Rml::Context* GetContext() const { return context_; }

private:
    moodycamel::ConcurrentQueue<UIEvent>* ui_event_queue_;
    Rml::Context* context_;
};
