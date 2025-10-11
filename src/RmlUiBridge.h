#pragma once

#include <RmlUi/Core.h>
#include <RmlUi/Lua.h>
#include <string>
#include "Seqlock.h"
#include "InputState.h"

class RmlUiBridge {
public:
    RmlUiBridge(Seqlock<InputState>* input_seqlock);
    ~RmlUiBridge() = default;

    // Setup lua bindings in RmlUI's lua state
    void SetupLuaBindings(lua_State* L, Rml::Context* context);

    // Add a UI event to the input state
    void TriggerEvent(const std::string& event_name, const PayloadMap& payload);

private:
    Seqlock<InputState>* input_seqlock_;
    InputState pending_state_;
};
