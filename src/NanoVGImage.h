#pragma once

extern "C" {
#include <lua.h>
}

/**
 * NanoVGImage - Image management for NanoVG Lua bindings
 *
 * Provides image loading, sizing, and deletion functionality.
 * Images can be used with image patterns for texture fills and strokes.
 */
class NanoVGImage {
public:
    // Setup image bindings in the nvg table (assumes table is on stack at -1)
    static void SetupBindings(lua_State* L);
};
