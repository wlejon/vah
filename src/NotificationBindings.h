#pragma once

#include <sol/sol.hpp>

// Forward declaration
class NotificationFeed;

namespace NotificationBindings {
    // Setup notification bindings in lua state
    void SetupBindings(sol::state& lua, NotificationFeed* feed);
}
