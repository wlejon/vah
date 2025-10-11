#pragma once

#include <sol/sol.hpp>
#include <string>

namespace FileSystemBindings {
    // Setup file system bindings in lua state
    void SetupBindings(sol::state& lua);
}
