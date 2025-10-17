#include "RmlUiBridge.h"
#include "Logger.h"
#include "DataStore.h"
#include "NotificationFeed.h"
#include "NotificationPlugin.h"
#include <RmlUi/Core/Elements/ElementFormControl.h>
#include <RmlUi/Lua/Utilities.h>
#include <RmlUi/Lua/Interpreter.h>

// Global references for lua callbacks (accessible from main.cpp)
NotificationFeed* g_notification_feed = nullptr;

namespace {
    // Global reference to the bridge for lua callback
    RmlUiBridge* g_bridge = nullptr;
    DataStore* g_data_store = nullptr;

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

    // Lua callback for data.update_row() function
    // Updates an entire row in the DataStore immediately (main thread only)
    int lua_data_update_row(lua_State* L) {
        if (!g_data_store) {
            return luaL_error(L, "data.update_row() called but data store not available");
        }

        // Arguments: model_name, row_index, updates_table
        if (!lua_isstring(L, 1)) {
            return luaL_error(L, "data.update_row() arg 1: model name (string) required");
        }
        if (!lua_isnumber(L, 2)) {
            return luaL_error(L, "data.update_row() arg 2: row index (number) required");
        }
        if (!lua_istable(L, 3)) {
            return luaL_error(L, "data.update_row() arg 3: updates table required");
        }

        std::string model_name = lua_tostring(L, 1);
        int row_index = static_cast<int>(lua_tonumber(L, 2)) - 1;  // Lua is 1-indexed

        // Get the current model data
        auto model_data = g_data_store->GetModel(model_name);
        if (!model_data) {
            return luaL_error(L, "data.update_row(): model '%s' not found", model_name.c_str());
        }

        // Create a mutable copy
        DynamicTable mutable_data = *model_data;

        if (row_index < 0 || row_index >= static_cast<int>(mutable_data.size())) {
            return luaL_error(L, "data.update_row(): row index %d out of bounds (size: %d)",
                            row_index + 1, static_cast<int>(mutable_data.size()));
        }

        // Iterate through the updates table and apply to the row
        lua_pushnil(L);  // First key
        while (lua_next(L, 3) != 0) {
            // Key at -2, value at -1
            if (lua_isstring(L, -2)) {
                std::string field_name = lua_tostring(L, -2);

                // Convert Lua value to DynamicValue
                DynamicValue new_value;
                if (lua_isnil(L, -1)) {
                    new_value = std::monostate{};
                } else if (lua_isboolean(L, -1)) {
                    new_value = static_cast<bool>(lua_toboolean(L, -1));
                } else if (lua_isinteger(L, -1)) {
                    new_value = static_cast<int64_t>(lua_tointeger(L, -1));
                } else if (lua_isnumber(L, -1)) {
                    new_value = lua_tonumber(L, -1);
                } else if (lua_isstring(L, -1)) {
                    new_value = std::string(lua_tostring(L, -1));
                }

                // Update the field
                mutable_data[row_index][field_name] = new_value;
            }
            lua_pop(L, 1);  // Remove value, keep key for next iteration
        }

        // Write back to DataStore
        g_data_store->SetModel(model_name, mutable_data);

        // Dirty the model in RmlUi to trigger re-render
        if (g_bridge && g_bridge->GetContext()) {
            auto model_constructor = g_bridge->GetContext()->GetDataModel(model_name);
            if (model_constructor) {
                auto model_handle = model_constructor.GetModelHandle();
                if (model_handle) {
                    model_handle.DirtyVariable(model_name);
                }
            }
        }

        return 0;  // No return values
    }

    // Lua callback for data.get() function
    int lua_data_get(lua_State* L) {
        if (!g_data_store) {
            lua_pushnil(L);
            return 1;
        }

        // First argument: model name (required)
        if (!lua_isstring(L, 1)) {
            return luaL_error(L, "data.get() requires model name as first argument");
        }
        std::string model_name = lua_tostring(L, 1);

        // Get the model from the data store
        auto model_data = g_data_store->GetModel(model_name);
        if (!model_data) {
            lua_pushnil(L);
            return 1;
        }

        // Helper function to recursively convert DynamicValue to Lua
        std::function<void(const DynamicValue&)> push_value;
        push_value = [L, &push_value](const DynamicValue& val) {
            std::visit([L, &push_value](auto&& v) {
                using T = std::decay_t<decltype(v)>;
                if constexpr (std::is_same_v<T, std::monostate>) {
                    lua_pushnil(L);
                } else if constexpr (std::is_same_v<T, bool>) {
                    lua_pushboolean(L, v);
                } else if constexpr (std::is_same_v<T, int64_t>) {
                    lua_pushinteger(L, v);
                } else if constexpr (std::is_same_v<T, double>) {
                    lua_pushnumber(L, v);
                } else if constexpr (std::is_same_v<T, std::string>) {
                    lua_pushstring(L, v.c_str());
                } else if constexpr (std::is_same_v<T, std::shared_ptr<DynamicMap>>) {
                    // Handle nested objects/maps
                    if (v) {
                        lua_newtable(L);
                        for (const auto& [key, nested_val] : v->fields) {
                            // Check if key is a number (array index)
                            char* end;
                            long idx = strtol(key.c_str(), &end, 10);
                            if (*end == '\0' && idx > 0) {
                                // It's an array index (Lua uses 1-based)
                                push_value(nested_val);
                                lua_rawseti(L, -2, idx);
                            } else {
                                // It's a string key
                                lua_pushstring(L, key.c_str());
                                push_value(nested_val);
                                lua_settable(L, -3);
                            }
                        }
                    } else {
                        lua_pushnil(L);
                    }
                } else {
                    lua_pushnil(L);
                }
            }, val);
        };

        // Convert DynamicTable to Lua table
        lua_newtable(L);  // Create array table
        int row_index = 1;
        for (const auto& row : *model_data) {
            lua_newtable(L);  // Create row table
            for (const auto& [field_name, field_value] : row) {
                lua_pushstring(L, field_name.c_str());
                push_value(field_value);
                lua_settable(L, -3);  // Set field in row table
            }
            lua_rawseti(L, -2, row_index++);  // Add row to array
        }

        return 1;  // Return the table
    }

    // Lua callback for toggle_notification_feed
    int lua_toggle_notification_feed(lua_State* L) {
        // The notification overlay is global, so we find it by ID in the context
        // First argument is the calling document (we don't actually need it)

        // We need to find the vah-notification-overlay document in the context
        // For now, just toggle the stream class directly via the global context
        if (g_bridge && g_bridge->GetContext()) {
            Rml::ElementDocument* overlay_doc = g_bridge->GetContext()->GetDocument("vah-notification-overlay");
            if (overlay_doc) {
                Rml::Element* stream = overlay_doc->GetElementById("notification-stream");
                if (stream) {
                    bool is_active = stream->IsClassSet("active");
                    stream->SetClass("active", !is_active);

                    // If opening, update the notifications to ensure latest data
                    if (!is_active) {
                        NotificationOverlay::Update();
                    }
                }
            }
        }
        return 0;
    }

    // Lua callback for clear_notifications
    int lua_clear_notifications(lua_State* L) {
        if (g_notification_feed) {
            g_notification_feed->Clear();
            // Update the UI
            NotificationOverlay::Update();
        }
        return 0;
    }

    // Lua callback for dismiss_notification
    int lua_dismiss_notification(lua_State* L) {
        // Arguments: event, notif_id
        if (!lua_isstring(L, 2)) {
            return luaL_error(L, "dismiss_notification requires notification ID");
        }

        std::string notif_id = lua_tostring(L, 2);
        if (g_notification_feed) {
            g_notification_feed->Dismiss(notif_id);
            // Update the UI
            NotificationOverlay::Update();
        }
        return 0;
    }

}

RmlUiBridge::RmlUiBridge(moodycamel::ConcurrentQueue<UIEvent>* ui_event_queue)
    : ui_event_queue_(ui_event_queue)
    , context_(nullptr)
    , data_store_(nullptr)
{
    g_bridge = this;
}

void RmlUiBridge::SetupLuaBindings(lua_State* L, Rml::Context* context, DataStore* data_store) {
    // Store the context and data store
    context_ = context;
    data_store_ = data_store;
    g_data_store = data_store;

    // Register the trigger function globally in RmlUI's lua state
    lua_pushcfunction(L, lua_trigger);
    lua_setglobal(L, "trigger");

    // Create data table with get() and update_row() functions
    lua_newtable(L);
    lua_pushcfunction(L, lua_data_get);
    lua_setfield(L, -2, "get");
    lua_pushcfunction(L, lua_data_update_row);
    lua_setfield(L, -2, "update_row");
    lua_setglobal(L, "data");

    // Register notification event handlers
    lua_pushcfunction(L, lua_toggle_notification_feed);
    lua_setglobal(L, "toggle_notification_feed");

    lua_pushcfunction(L, lua_clear_notifications);
    lua_setglobal(L, "clear_notifications");

    lua_pushcfunction(L, lua_dismiss_notification);
    lua_setglobal(L, "dismiss_notification");

    // Expose the context as a global for RML inline scripts to use
    // Use RmlUI's Lua type system to push it properly
    Rml::Lua::LuaType<Rml::Context>::push(L, context, false);
    lua_setglobal(L, "rmlui_context");

    LOG_INFO("RmlUiBridge: Registered trigger(), data, and notification functions in RmlUI lua state");
}

void RmlUiBridge::TriggerEvent(const std::string& event_name, const PayloadMap& payload) {
    UIEvent event;
    event.name = event_name;
    event.payload = payload;

    // Simple enqueue
    ui_event_queue_->enqueue(std::move(event));

    LOG_DEBUG("RmlUiBridge: Triggered event '{}' with {} payload items", event_name, payload.size());
}
