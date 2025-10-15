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
 * The bindings are organized into multiple focused modules:
 * - NanoVGBindings: Core path drawing, shapes, transforms, and state management
 * - NanoVGPaint: Paint management (gradients and patterns)
 * - NanoVGText: Font loading, text rendering, and measurement
 * - NanoVGImage: Image loading and management
 * - NanoVGUtils: Color utilities, scissoring, and composite operations
 *
 * All functions are exposed through a global 'nvg' table in Lua.
 */
class NanoVGBindings {
public:
    // Setup NanoVG bindings in the given Lua state
    // Creates a global 'nvg' table with all drawing functions
    static void SetupBindings(lua_State* L);
};
