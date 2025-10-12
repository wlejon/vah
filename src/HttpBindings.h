#pragma once

#include <sol/sol.hpp>

// Forward declaration
class LuaThread;

namespace HttpBindings {
    // Setup HTTP bindings in lua state
    // Pass the LuaThread pointer so servers can register themselves (lock-free)
    void SetupBindings(sol::state& lua, LuaThread* thread);
}
