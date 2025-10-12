#pragma once

#include <sol/sol.hpp>
#include <nlohmann/json.hpp>

namespace JsonBindings {
    // Setup JSON bindings in lua state
    void SetupBindings(sol::state& lua);

    // Helper functions for converting between JSON and Lua
    nlohmann::json LuaToJson(const sol::object& obj);
    sol::object JsonToLua(sol::state_view lua, const nlohmann::json& j);
}
