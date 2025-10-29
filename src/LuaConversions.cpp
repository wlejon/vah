#include "LuaConversions.h"

namespace LuaConversions {

// Forward declaration for recursion
sol::object DynamicValueToLua(sol::state& lua, const DynamicValue& value);

// Helper to recursively convert DynamicValue to Lua object
sol::object DynamicValueToLua(sol::state& lua, const DynamicValue& value) {
    return std::visit([&](auto&& val) -> sol::object {
        using T = std::decay_t<decltype(val)>;

        if constexpr (std::is_same_v<T, std::monostate>) {
            return sol::make_object(lua, sol::nil);
        }
        else if constexpr (std::is_same_v<T, bool>) {
            return sol::make_object(lua, val);
        }
        else if constexpr (std::is_same_v<T, int64_t>) {
            return sol::make_object(lua, val);
        }
        else if constexpr (std::is_same_v<T, double>) {
            return sol::make_object(lua, val);
        }
        else if constexpr (std::is_same_v<T, std::string>) {
            return sol::make_object(lua, val);
        }
        else if constexpr (std::is_same_v<T, std::shared_ptr<DynamicMap>>) {
            // Nested object - recursively convert to Lua table
            if (!val) {
                return sol::make_object(lua, sol::nil);
            }
            auto nested_table = lua.create_table();

            if (val->is_array) {
                // Restore as Lua array with integer keys
                for (const auto& [key_str, nested_value] : val->fields) {
                    int index = std::stoi(key_str);
                    nested_table[index] = DynamicValueToLua(lua, nested_value);
                }
            } else {
                // Regular object with string keys
                for (const auto& [key, nested_value] : val->fields) {
                    nested_table[key] = DynamicValueToLua(lua, nested_value);
                }
            }
            return nested_table;
        }
        else {
            return sol::make_object(lua, sol::nil);
        }
    }, value);
}

// Helper to convert sol::object to DynamicValue
DynamicValue ObjectToDynamicValue(const sol::object& obj) {
    if (obj.is<bool>()) {
        return obj.as<bool>();
    } else if (obj.is<int>()) {
        return static_cast<int64_t>(obj.as<int>());
    } else if (obj.is<int64_t>()) {
        return obj.as<int64_t>();
    } else if (obj.is<double>()) {
        return obj.as<double>();
    } else if (obj.is<std::string>()) {
        return obj.as<std::string>();
    } else if (obj.is<sol::table>()) {
        // Nested table - convert to DynamicMap
        auto nested_map = std::make_shared<DynamicMap>();
        sol::table nested_table = obj.as<sol::table>();

        // Detect if this is an array (consecutive integer keys starting from 1)
        bool is_array = true;
        size_t expected_index = 1;
        size_t count = 0;

        for (const auto& [key, value] : nested_table) {
            count++;
            if (!key.is<int>() || key.as<int>() != static_cast<int>(expected_index)) {
                is_array = false;
            }
            expected_index++;
        }

        // Mark as array if detected
        nested_map->is_array = (count > 0 && is_array);

        // Convert all keys to strings for storage
        for (const auto& [key, value] : nested_table) {
            std::string key_str;
            if (key.is<std::string>()) {
                key_str = key.as<std::string>();
            } else if (key.is<int>()) {
                // Convert numeric index to string
                key_str = std::to_string(key.as<int>());
            } else {
                // Skip other key types
                continue;
            }
            nested_map->fields[key_str] = ObjectToDynamicValue(value);
        }
        return nested_map;
    } else {
        return std::monostate{};
    }
}

// Helper to convert Lua table (array of tables) to DynamicTable
DynamicTable TableToDynamicTable(const sol::table& table) {
    DynamicTable result;

    // Iterate through all pairs to see what we have
    for (const auto& [key, value] : table) {
        if (key.is<int>() || key.is<size_t>()) {
            if (value.is<sol::table>()) {
                sol::table row_table = value.as<sol::table>();
                DynamicRow row;

                // Convert each field in the row
                for (const auto& [row_key, row_value] : row_table) {
                    if (row_key.is<std::string>()) {
                        std::string key_str = row_key.as<std::string>();
                        row[key_str] = ObjectToDynamicValue(row_value);
                    }
                }

                result.push_back(std::move(row));
            }
        }
    }

    return result;
}

// Helper to convert Lua table (single object) to DynamicRow
DynamicRow TableToDynamicRow(const sol::table& table) {
    DynamicRow row;

    // Iterate through all key-value pairs
    for (const auto& [key, value] : table) {
        if (key.is<std::string>()) {
            std::string key_str = key.as<std::string>();
            row[key_str] = ObjectToDynamicValue(value);
        }
    }

    return row;
}

// Helper to convert Lua table to PayloadMap (for configs, params, etc.)
PayloadMap TableToPayloadMap(const sol::table& table) {
    PayloadMap result;
    for (const auto& [key, value] : table) {
        if (key.is<std::string>()) {
            std::string key_str = key.as<std::string>();
            result[key_str] = ObjectToDynamicValue(value);
        }
    }
    return result;
}

} // namespace LuaConversions
