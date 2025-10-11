#pragma once

#include <sol/sol.hpp>

namespace JsonBindings {
    // Setup JSON bindings in lua state
    void SetupBindings(sol::state& lua);
}
