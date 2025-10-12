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
}

RmlUiBridge::RmlUiBridge(UIEventQueue* ui_event_queue)
    : ui_event_queue_(ui_event_queue)
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

    // Expose the context as a global for RML inline scripts to use
    // Use RmlUI's Lua type system to push it properly
    Rml::Lua::LuaType<Rml::Context>::push(L, context, false);
    lua_setglobal(L, "rmlui_context");

    LOG_INFO("RmlUiBridge: Registered trigger() and convenience functions in RmlUI lua state");
}

void RmlUiBridge::TriggerEvent(const std::string& event_name, const PayloadMap& payload) {
    UIEvent event;
    event.name = event_name;
    event.payload = payload;

    // Simple enqueue - no seqlock manipulation
    ui_event_queue_->Push(std::move(event));

    LOG_DEBUG("RmlUiBridge: Triggered event '{}' with {} payload items", event_name, payload.size());
}
