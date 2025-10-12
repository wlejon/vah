#include "RmlUiBridge.h"
#include "Logger.h"
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

    // Lua callback for trigger_save function
    int lua_trigger_save(lua_State* L) {
        if (!g_bridge) {
            return luaL_error(L, "RmlUiBridge not initialized");
        }

        // Single argument: contact ID (required)
        if (!lua_isnumber(L, 1)) {
            return luaL_error(L, "trigger_save() requires contact ID as first argument");
        }

        int contact_id = static_cast<int>(lua_tointeger(L, 1));

        // Get the context
        Rml::Context* context = g_bridge->GetContext();
        if (!context) {
            return luaL_error(L, "RmlUi context not available");
        }

        // Get the active document
        Rml::ElementDocument* document = context->GetDocument(0);
        if (!document) {
            return luaL_error(L, "No active document");
        }

        // Build element IDs based on contact_id
        std::string name_id = "name_" + std::to_string(contact_id);
        std::string email_id = "email_" + std::to_string(contact_id);
        std::string phone_id = "phone_" + std::to_string(contact_id);
        std::string company_id = "company_" + std::to_string(contact_id);

        // Query input elements and extract values
        PayloadMap payload;
        payload["id"] = contact_id;

        auto name_elem = document->GetElementById(name_id);
        if (name_elem) {
            auto value = name_elem->GetAttribute<Rml::String>("value", "");
            payload["name"] = std::string(value.data(), value.size());
        }

        auto email_elem = document->GetElementById(email_id);
        if (email_elem) {
            auto value = email_elem->GetAttribute<Rml::String>("value", "");
            payload["email"] = std::string(value.data(), value.size());
        }

        auto phone_elem = document->GetElementById(phone_id);
        if (phone_elem) {
            auto value = phone_elem->GetAttribute<Rml::String>("value", "");
            payload["phone"] = std::string(value.data(), value.size());
        }

        auto company_elem = document->GetElementById(company_id);
        if (company_elem) {
            auto value = company_elem->GetAttribute<Rml::String>("value", "");
            payload["company"] = std::string(value.data(), value.size());
        }

        // Trigger the save_contact event
        g_bridge->TriggerEvent("save_contact", payload);

        return 0;  // No return values
    }
}

RmlUiBridge::RmlUiBridge(Seqlock<InputState>* input_seqlock)
    : input_seqlock_(input_seqlock)
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

    // Expose the context as a global for RML inline scripts to use
    // Use RmlUI's Lua type system to push it properly
    Rml::Lua::LuaType<Rml::Context>::push(L, context, false);
    lua_setglobal(L, "rmlui_context");

    LOG_INFO("RmlUiBridge: Registered trigger(), trigger_delete(), and trigger_save() functions in RmlUI lua state");
}

void RmlUiBridge::TriggerEvent(const std::string& event_name, const PayloadMap& payload) {
    // Read current state
    auto current_state = input_seqlock_->Read();

    // Clear old ui_events to prevent accumulation
    // (Main thread will read these events and process them next frame)
    current_state.ui_events.clear();

    // Add new event
    UIEvent event;
    event.name = event_name;
    event.payload = payload;
    current_state.ui_events.push_back(event);

    // Write back to seqlock
    input_seqlock_->Write(current_state);

    LOG_DEBUG("RmlUiBridge: Triggered event '{}' with {} payload items", event_name, payload.size());
}
