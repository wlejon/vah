#include "JsonBindings.h"
#include "Logger.h"
#include <nlohmann/json.hpp>

using json = nlohmann::json;

namespace JsonBindings {

// Convert Lua table to JSON recursively
json LuaToJson(const sol::object& obj) {
    if (obj == sol::nil) {
        return nullptr;
    }
    else if (obj.is<bool>()) {
        return obj.as<bool>();
    }
    else if (obj.is<int>()) {
        return obj.as<int>();
    }
    else if (obj.is<double>()) {
        return obj.as<double>();
    }
    else if (obj.is<std::string>()) {
        return obj.as<std::string>();
    }
    else if (obj.is<sol::table>()) {
        sol::table tbl = obj.as<sol::table>();

        // Check if it's an array by verifying all keys are sequential integers starting from 1
        // We need to count the elements and verify keys 1..N exist (regardless of iteration order)
        size_t count = 0;
        bool has_non_integer_key = false;
        int max_key = 0;

        // First pass: count elements and check for non-integer keys
        for (const auto& pair : tbl) {
            count++;
            if (!pair.first.is<int>()) {
                has_non_integer_key = true;
                break;
            }
            int key = pair.first.as<int>();
            if (key > max_key) {
                max_key = key;
            }
        }

        // It's an array if:
        // 1. All keys are integers
        // 2. Keys form a sequence 1..N without gaps (count == max_key)
        // 3. There's at least one element
        bool is_array = !has_non_integer_key && count > 0 && count == static_cast<size_t>(max_key);

        // Verify no gaps if it looks like an array
        if (is_array) {
            for (size_t i = 1; i <= count; i++) {
                sol::optional<sol::object> val = tbl[i];
                if (!val) {
                    is_array = false;
                    break;
                }
            }
        }

        if (is_array) {
            json arr = json::array();
            // Access elements in order by index
            for (size_t i = 1; i <= count; i++) {
                arr.push_back(LuaToJson(tbl[i]));
            }
            return arr;
        }
        else {
            json obj = json::object();
            for (const auto& pair : tbl) {
                if (pair.first.is<std::string>()) {
                    obj[pair.first.as<std::string>()] = LuaToJson(pair.second);
                }
                else if (pair.first.is<int>()) {
                    obj[std::to_string(pair.first.as<int>())] = LuaToJson(pair.second);
                }
            }
            return obj;
        }
    }

    return nullptr;
}

// Convert JSON to Lua table recursively
sol::object JsonToLua(sol::state_view lua, const json& j) {
    if (j.is_null()) {
        return sol::nil;
    }
    else if (j.is_boolean()) {
        return sol::make_object(lua, j.get<bool>());
    }
    else if (j.is_number_integer()) {
        return sol::make_object(lua, j.get<int64_t>());
    }
    else if (j.is_number_float()) {
        return sol::make_object(lua, j.get<double>());
    }
    else if (j.is_string()) {
        return sol::make_object(lua, j.get<std::string>());
    }
    else if (j.is_array()) {
        auto tbl = lua.create_table();
        int index = 1;
        for (const auto& item : j) {
            tbl[index++] = JsonToLua(lua, item);
        }
        return tbl;
    }
    else if (j.is_object()) {
        auto tbl = lua.create_table();
        for (auto it = j.begin(); it != j.end(); ++it) {
            tbl[it.key()] = JsonToLua(lua, it.value());
        }
        return tbl;
    }

    return sol::nil;
}

// Encode Lua table to JSON string
std::tuple<sol::object, std::string> Encode(sol::this_state s, const sol::object& obj) {
    sol::state_view lua(s);

    try {
        json j = LuaToJson(obj);
        std::string result = j.dump();
        return {sol::make_object(lua, result), ""};
    }
    catch (const std::exception& e) {
        return {sol::nil, std::string("JSON encode error: ") + e.what()};
    }
}

// Encode Lua table to pretty JSON string
std::tuple<sol::object, std::string> EncodePretty(sol::this_state s, const sol::object& obj, sol::optional<int> indent) {
    sol::state_view lua(s);

    try {
        json j = LuaToJson(obj);
        std::string result = j.dump(indent.value_or(2));
        return {sol::make_object(lua, result), ""};
    }
    catch (const std::exception& e) {
        return {sol::nil, std::string("JSON encode error: ") + e.what()};
    }
}

// Decode JSON string to Lua table
std::tuple<sol::object, std::string> Decode(sol::this_state s, const std::string& json_str) {
    sol::state_view lua(s);

    try {
        json j = json::parse(json_str);
        sol::object result = JsonToLua(lua, j);
        return {result, ""};
    }
    catch (const std::exception& e) {
        return {sol::nil, std::string("JSON decode error: ") + e.what()};
    }
}

void SetupBindings(sol::state& lua) {
    auto json_table = lua.create_table();

    json_table["encode"] = Encode;
    json_table["encode_pretty"] = EncodePretty;
    json_table["decode"] = Decode;

    lua["json"] = json_table;
}

} // namespace JsonBindings
