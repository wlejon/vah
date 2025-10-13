#pragma once

#include <sol/sol.hpp>

namespace FileWatcherBindings {
    // Setup file watcher bindings in lua state
    // Each thread gets its own file watcher instance that it fully owns
    void SetupBindings(sol::state& lua);
}
