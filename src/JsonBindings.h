#pragma once

#include <sol/sol.hpp>
#include <nlohmann/json.hpp>

namespace JsonBindings {
    // Setup JSON bindings in lua state
    void SetupBindings(sol::state& lua);

    // Helper functions for converting between JSON and Lua
    nlohmann::json LuaToJson(const sol::object& obj);
    sol::object JsonToLua(sol::state_view lua, const nlohmann::json& j);

    // Lua-facing encode/decode functions
    std::tuple<sol::object, std::string> Encode(sol::this_state s, const sol::object& obj);
    std::tuple<sol::object, std::string> EncodePretty(sol::this_state s, const sol::object& obj, sol::optional<int> indent);
    std::tuple<sol::object, std::string> Decode(sol::this_state s, const std::string& json_str);
}
