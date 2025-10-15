#pragma once

extern "C" {
#include <lua.h>
}

/**
 * NanoVGPaint - Paint management for NanoVG Lua bindings
 *
 * Provides proper lifetime management for NVGpaint objects, including
 * gradients (linear, radial, box) and image patterns.
 * Paint objects are managed as Lua userdata with proper garbage collection.
 */
class NanoVGPaint {
public:
    // Setup paint bindings in the nvg table (assumes table is on stack at -1)
    static void SetupBindings(lua_State* L);
};
