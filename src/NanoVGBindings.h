#pragma once

extern "C" {
#include <lua.h>
}

/**
 * NanoVGBindings - Exposes NanoVG 2D drawing API to Lua
 *
 * This module provides Lua bindings for the NanoVG vector graphics library,
 * allowing RML scripts to perform custom 2D rendering on canvas elements.
 *
 * The bindings expose a subset of NanoVG's C API through a 'nvg' table in Lua,
 * providing functions for path drawing, styling, transforms, and text rendering.
 */
class NanoVGBindings {
public:
    // Setup NanoVG bindings in the given Lua state
    // Creates a global 'nvg' table with drawing functions
    static void SetupBindings(lua_State* L);
};
