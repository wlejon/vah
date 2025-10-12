#include "RmlUiBridge.h"
#include "Logger.h"
#include <RmlUi/Core/Elements/ElementFormControl.h>
#include <RmlUi/Lua/Utilities.h>
#include <RmlUi/Lua/Interpreter.h>

namespace {
    // Global reference to the bridge for lua callback
    RmlUiBridge* g_bridge = nullptr;

    // Lua callback for trigger function
    int lua_trigger(lua_State* L) {
        if (!g_bridge) {
            return luaL_error(L, "RmlUiBridge not initialized");
        }

        // First argument: event name (required)
        if (!lua_isstring(L, 1)) {
            return luaL_error(L, "trigger() requires event name as first argument");
        }
        std::string event_name = lua_tostring(L, 1);

        // Second argument: payload table (optional)
        PayloadMap payload;
        if (lua_istable(L, 2)) {
            // Convert lua table to PayloadMap
            lua_pushnil(L);  // First key
            while (lua_next(L, 2) != 0) {
                // Key at -2, value at -1
                if (lua_isstring(L, -2)) {
                    std::string key = lua_tostring(L, -2);

                    if (lua_isboolean(L, -1)) {
                        payload[key] = static_cast<bool>(lua_toboolean(L, -1));
                    } else if (lua_isinteger(L, -1)) {
                        payload[key] = static_cast<int>(lua_tointeger(L, -1));
                    } else if (lua_isnumber(L, -1)) {
                        payload[key] = lua_tonumber(L, -1);
                    } else if (lua_isstring(L, -1)) {
                        payload[key] = std::string(lua_tostring(L, -1));
                    }
                }
                lua_pop(L, 1);  // Remove value, keep key for next iteration
            }
        }

        // Trigger the event
        g_bridge->TriggerEvent(event_name, payload);

        return 0;  // No return values
    }

    // Lua callback for trigger_delete function (convenience wrapper)
    int lua_trigger_delete(lua_State* L) {
        if (!g_bridge) {
            return luaL_error(L, "RmlUiBridge not initialized");
        }

        // Single argument: contact ID (required)
        if (!lua_isnumber(L, 1)) {
            return luaL_error(L, "trigger_delete() requires contact ID as first argument");
        }

        int contact_id = static_cast<int>(lua_tointeger(L, 1));

        // Create payload with id
        PayloadMap payload;
        payload["id"] = contact_id;

        // Trigger the delete_contact event
        g_bridge->TriggerEvent("delete_contact", payload);

        return 0;  // No return values
    }

    // Lua callback for start_edit - user focused on an input
    int lua_start_edit(lua_State* L) {
        if (!g_bridge) {
            return luaL_error(L, "RmlUiBridge not initialized");
        }

        // Arguments: model_name, record_id, field_name, initial_value
        if (!lua_isstring(L, 1) || !lua_isnumber(L, 2) || !lua_isstring(L, 3) || !lua_isstring(L, 4)) {
            return luaL_error(L, "start_edit(model_name, record_id, field_name, initial_value) requires string, number, string, string");
        }

        std::string model_name = lua_tostring(L, 1);
        int record_id = static_cast<int>(lua_tointeger(L, 2));
        std::string field_name = lua_tostring(L, 3);
        std::string initial_value = lua_tostring(L, 4);

        g_bridge->StartEdit(model_name, record_id, field_name, initial_value);
        return 0;
    }

    // Lua callback for end_edit - user blurred from an input
    int lua_end_edit(lua_State* L) {
        if (!g_bridge) {
            return luaL_error(L, "RmlUiBridge not initialized");
        }

        // Arguments: model_name, record_id, field_name, final_value
        if (!lua_isstring(L, 1) || !lua_isnumber(L, 2) || !lua_isstring(L, 3) || !lua_isstring(L, 4)) {
            return luaL_error(L, "end_edit(model_name, record_id, field_name, final_value) requires string, number, string, string");
        }

        std::string model_name = lua_tostring(L, 1);
        int record_id = static_cast<int>(lua_tointeger(L, 2));
        std::string field_name = lua_tostring(L, 3);
        std::string final_value = lua_tostring(L, 4);

        g_bridge->EndEdit(model_name, record_id, field_name, final_value);
        return 0;
    }

    // Lua callback for trigger_save function
    int lua_trigger_save(lua_State* L) {
        if (!g_bridge) {
            return luaL_error(L, "RmlUiBridge not initialized");
        }

        // Arguments: model_name, record_id
        if (!lua_isstring(L, 1) || !lua_isnumber(L, 2)) {
            return luaL_error(L, "trigger_save(model_name, record_id) requires string, number");
        }

        std::string model_name = lua_tostring(L, 1);
        int record_id = static_cast<int>(lua_tointeger(L, 2));

        // Get pending edits for this record
        PayloadMap payload = g_bridge->GetPendingEdits(model_name, record_id);
        payload["id"] = record_id;

        LOG_DEBUG("RmlUiBridge: trigger_save called for {} ID {} with {} edits",
                  model_name, record_id, payload.size() - 1);

        // Trigger save event with model-specific name (e.g., "save_contact")
        std::string event_name = "save_" + model_name.substr(0, model_name.size() - 1); // Remove trailing 's'
        if (model_name.back() == 's') {
            event_name = "save_" + model_name.substr(0, model_name.size() - 1);
        } else {
            event_name = "save_" + model_name;
        }

        g_bridge->TriggerEvent(event_name, payload);
        return 0;
    }
}

RmlUiBridge::RmlUiBridge(Seqlock<InputState>* input_seqlock, UIEventQueue* ui_event_queue)
    : input_seqlock_(input_seqlock)
    , ui_event_queue_(ui_event_queue)
    , context_(nullptr)
{
    g_bridge = this;
}

void RmlUiBridge::SetupLuaBindings(lua_State* L, Rml::Context* context) {
    // Store the context
    context_ = context;

    // Register the trigger function globally in RmlUI's lua state
    lua_pushcfunction(L, lua_trigger);
    lua_setglobal(L, "trigger");

    // Register the trigger_delete convenience function
    lua_pushcfunction(L, lua_trigger_delete);
    lua_setglobal(L, "trigger_delete");

    // Register the trigger_save convenience function
    lua_pushcfunction(L, lua_trigger_save);
    lua_setglobal(L, "trigger_save");

    // Register edit tracking functions
    lua_pushcfunction(L, lua_start_edit);
    lua_setglobal(L, "start_edit");

    lua_pushcfunction(L, lua_end_edit);
    lua_setglobal(L, "end_edit");

    // Expose the context as a global for RML inline scripts to use
    // Use RmlUI's Lua type system to push it properly
    Rml::Lua::LuaType<Rml::Context>::push(L, context, false);
    lua_setglobal(L, "rmlui_context");

    LOG_INFO("RmlUiBridge: Registered trigger(), edit tracking, and convenience functions in RmlUI lua state");
}

void RmlUiBridge::TriggerEvent(const std::string& event_name, const PayloadMap& payload) {
    UIEvent event;
    event.name = event_name;
    event.payload = payload;

    // Simple enqueue - no seqlock manipulation
    ui_event_queue_->Push(std::move(event));

    LOG_DEBUG("RmlUiBridge: Triggered event '{}' with {} payload items", event_name, payload.size());
}

void RmlUiBridge::StartEdit(const std::string& model_name, int record_id, const std::string& field_name, const std::string& initial_value) {
    EditKey key{model_name, record_id, field_name};
    pending_edits_[key] = initial_value;
    LOG_DEBUG("RmlUiBridge: Started edit for {}.{}.{} = '{}'", model_name, record_id, field_name, initial_value);
}

void RmlUiBridge::EndEdit(const std::string& model_name, int record_id, const std::string& field_name, const std::string& final_value) {
    EditKey key{model_name, record_id, field_name};
    pending_edits_[key] = final_value;
    LOG_DEBUG("RmlUiBridge: Ended edit for {}.{}.{} = '{}'", model_name, record_id, field_name, final_value);
}

PayloadMap RmlUiBridge::GetPendingEdits(const std::string& model_name, int record_id) const {
    PayloadMap edits;

    // Find all edits for this record
    for (const auto& [key, value] : pending_edits_) {
        if (key.model_name == model_name && key.record_id == record_id) {
            edits[key.field_name] = value;
        }
    }

    LOG_DEBUG("RmlUiBridge: Retrieved {} pending edits for {}.{}", edits.size(), model_name, record_id);
    return edits;
}
