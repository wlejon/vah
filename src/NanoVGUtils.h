#pragma once

#include <nanovg.h>

extern "C" {
#include <lua.h>
}

/**
 * NanoVGUtils - Utility functions for NanoVG Lua bindings
 *
 * Provides color utilities (HSL, lerp, transparency), scissoring,
 * composite operations, transform utilities, and antialiasing.
 * Also provides shared helper functions used by other binding modules.
 */
class NanoVGUtils {
public:
    // Setup utility bindings in the nvg table (assumes table is on stack at -1)
    static void SetupBindings(lua_State* L);

    // Shared helper function to convert Lua color table to NVGcolor
    static NVGcolor TableToColor(lua_State* L, int idx);
};
