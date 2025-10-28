#pragma once

#include <sol/sol.hpp>

/**
 * ClipboardBindings - Lua bindings for clipboard operations
 */
namespace ClipboardBindings {
    void SetupBindings(sol::state& lua);
}
