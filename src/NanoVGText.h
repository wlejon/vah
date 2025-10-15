#pragma once

extern "C" {
#include <lua.h>
}

/**
 * NanoVGText - Text rendering for NanoVG Lua bindings
 *
 * Provides font management, text rendering, and text measurement functions.
 * Supports font loading, fallback fonts, text styling, and text layout.
 */
class NanoVGText {
public:
    // Setup text bindings in the nvg table (assumes table is on stack at -1)
    static void SetupBindings(lua_State* L);
};
