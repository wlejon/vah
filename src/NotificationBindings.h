#pragma once

#include <sol/sol.hpp>
#include "Commands.h"
#include <moodycamel/concurrentqueue.h>

namespace NotificationBindings {
    // Setup notification bindings in lua state
    void SetupBindings(sol::state& lua, moodycamel::ConcurrentQueue<Command>* command_queue);
}
