#pragma once

#include <sol/sol.hpp>

namespace FileIngestionBindings {
    // Setup file ingestion bindings in lua state
    void SetupBindings(sol::state& lua);
}
