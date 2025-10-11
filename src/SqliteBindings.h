#pragma once

#include <sol/sol.hpp>

namespace SqliteBindings {
    // Setup SQLite bindings in lua state
    void SetupBindings(sol::state& lua);
}
