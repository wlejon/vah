#pragma once

#include <string>
#include <unordered_map>
#include <variant>

using PayloadValue = std::variant<std::monostate, bool, int, double, std::string>;
using PayloadMap = std::unordered_map<std::string, PayloadValue>;

struct UIEvent {
    std::string name;
    PayloadMap payload;
};
