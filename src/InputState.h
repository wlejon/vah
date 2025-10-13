#pragma once

#include <string>
#include <unordered_map>
#include "DataStore.h"

// Reuse DynamicValue for payload - supports nested objects
using PayloadMap = std::unordered_map<std::string, DynamicValue>;

struct UIEvent {
    std::string name;
    PayloadMap payload;
};
