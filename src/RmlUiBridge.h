#pragma once

#include <RmlUi/Core.h>
#include <RmlUi/Lua.h>
#include <string>
#include <map>
#include <tuple>
#include "Seqlock.h"
#include "InputState.h"
#include "UIEventQueue.h"

// Compound key for tracking edits: (model_name, record_id, field_name)
struct EditKey {
    std::string model_name;
    int record_id;
    std::string field_name;

    bool operator<(const EditKey& other) const {
        return std::tie(model_name, record_id, field_name) <
               std::tie(other.model_name, other.record_id, other.field_name);
    }
};

class RmlUiBridge {
public:
    RmlUiBridge(Seqlock<InputState>* input_seqlock, UIEventQueue* ui_event_queue);
    ~RmlUiBridge() = default;

    // Setup lua bindings in RmlUI's lua state
    void SetupLuaBindings(lua_State* L, Rml::Context* context);

    // Add a UI event to the input state
    void TriggerEvent(const std::string& event_name, const PayloadMap& payload);

    // Edit tracking
    void StartEdit(const std::string& model_name, int record_id, const std::string& field_name, const std::string& initial_value);
    void EndEdit(const std::string& model_name, int record_id, const std::string& field_name, const std::string& final_value);
    PayloadMap GetPendingEdits(const std::string& model_name, int record_id) const;

    // Get the RmlUi context
    Rml::Context* GetContext() const { return context_; }

private:
    Seqlock<InputState>* input_seqlock_;
    UIEventQueue* ui_event_queue_;
    InputState pending_state_;
    Rml::Context* context_;

    // Track pending edits for all models
    std::map<EditKey, std::string> pending_edits_;
};
