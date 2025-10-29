#pragma once

#include <sol/sol.hpp>
#include "DataStore.h"
#include "InputState.h"

namespace LuaConversions {
    // Convert DynamicValue to Lua object (recursive for nested objects)
    sol::object DynamicValueToLua(sol::state& lua, const DynamicValue& value);

    // Convert Lua object to DynamicValue
    DynamicValue ObjectToDynamicValue(const sol::object& obj);

    // Convert Lua table (array of tables) to DynamicTable
    DynamicTable TableToDynamicTable(const sol::table& table);

    // Convert Lua table (single object) to DynamicRow
    DynamicRow TableToDynamicRow(const sol::table& table);

    // Convert Lua table to PayloadMap (for configs, params, etc.)
    PayloadMap TableToPayloadMap(const sol::table& table);
}
