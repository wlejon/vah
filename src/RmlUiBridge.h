#pragma once

#include <RmlUi/Core.h>
#include <RmlUi/Lua.h>
#include <string>
#include "Seqlock.h"
#include "InputState.h"
#include "UIEventQueue.h"

class RmlUiBridge {
public:
    RmlUiBridge(Seqlock<InputState>* input_seqlock, UIEventQueue* ui_event_queue);
    ~RmlUiBridge() = default;

    // Setup lua bindings in RmlUI's lua state
    void SetupLuaBindings(lua_State* L, Rml::Context* context);

    // Add a UI event to the input state
    void TriggerEvent(const std::string& event_name, const PayloadMap& payload);

    // Get the RmlUi context
    Rml::Context* GetContext() const { return context_; }

private:
    Seqlock<InputState>* input_seqlock_;
    UIEventQueue* ui_event_queue_;
    InputState pending_state_;
    Rml::Context* context_;
};
