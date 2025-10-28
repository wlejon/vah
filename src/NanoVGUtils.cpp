#include "NanoVGUtils.h"
#include "Logger.h"
#include <nanovg.h>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

namespace {
    // Internal helper - use NanoVGUtils::GetContext() instead
    inline NVGcontext* GetContextInternal(lua_State* L, int idx) {
        return NanoVGUtils::GetContext(L, idx);
    }

    // Helper to push a color table to the Lua stack
    void PushColorTable(lua_State* L, const NVGcolor& color) {
        lua_createtable(L, 4, 0);
        lua_pushnumber(L, color.r);
        lua_rawseti(L, -2, 1);
        lua_pushnumber(L, color.g);
        lua_rawseti(L, -2, 2);
        lua_pushnumber(L, color.b);
        lua_rawseti(L, -2, 3);
        lua_pushnumber(L, color.a);
        lua_rawseti(L, -2, 4);
    }

    // ============================================================================
    // Color Utility Functions
    // ============================================================================

    int lua_nvgRGBf(lua_State* L) {
        float r = static_cast<float>(luaL_checknumber(L, 1));
        float g = static_cast<float>(luaL_checknumber(L, 2));
        float b = static_cast<float>(luaL_checknumber(L, 3));

        NVGcolor color = nvgRGBf(r, g, b);
        PushColorTable(L, color);

        return 1;
    }

    int lua_nvgHSL(lua_State* L) {
        float h = static_cast<float>(luaL_checknumber(L, 1));
        float s = static_cast<float>(luaL_checknumber(L, 2));
        float l = static_cast<float>(luaL_checknumber(L, 3));

        NVGcolor color = nvgHSL(h, s, l);
        PushColorTable(L, color);

        return 1;
    }

    int lua_nvgHSLA(lua_State* L) {
        float h = static_cast<float>(luaL_checknumber(L, 1));
        float s = static_cast<float>(luaL_checknumber(L, 2));
        float l = static_cast<float>(luaL_checknumber(L, 3));
        unsigned char a = static_cast<unsigned char>(luaL_checkinteger(L, 4));

        NVGcolor color = nvgHSLA(h, s, l, a);
        PushColorTable(L, color);

        return 1;
    }

    int lua_nvgLerpRGBA(lua_State* L) {
        luaL_checktype(L, 1, LUA_TTABLE);
        NVGcolor c0 = NanoVGUtils::TableToColor(L, 1);
        luaL_checktype(L, 2, LUA_TTABLE);
        NVGcolor c1 = NanoVGUtils::TableToColor(L, 2);
        float u = static_cast<float>(luaL_checknumber(L, 3));

        NVGcolor result = nvgLerpRGBA(c0, c1, u);
        PushColorTable(L, result);

        return 1;
    }

    int lua_nvgTransRGBA(lua_State* L) {
        luaL_checktype(L, 1, LUA_TTABLE);
        NVGcolor c0 = NanoVGUtils::TableToColor(L, 1);
        unsigned char a = static_cast<unsigned char>(luaL_checkinteger(L, 2));

        NVGcolor result = nvgTransRGBA(c0, a);
        PushColorTable(L, result);

        return 1;
    }

    int lua_nvgTransRGBAf(lua_State* L) {
        luaL_checktype(L, 1, LUA_TTABLE);
        NVGcolor c0 = NanoVGUtils::TableToColor(L, 1);
        float a = static_cast<float>(luaL_checknumber(L, 2));

        NVGcolor result = nvgTransRGBAf(c0, a);
        PushColorTable(L, result);

        return 1;
    }

    // ============================================================================
    // Scissoring Functions
    // ============================================================================

    int lua_nvgScissor(lua_State* L) {
        NVGcontext* ctx = GetContextInternal(L, 1);
        float x = static_cast<float>(luaL_checknumber(L, 2));
        float y = static_cast<float>(luaL_checknumber(L, 3));
        float w = static_cast<float>(luaL_checknumber(L, 4));
        float h = static_cast<float>(luaL_checknumber(L, 5));
        nvgScissor(ctx, x, y, w, h);
        return 0;
    }

    int lua_nvgIntersectScissor(lua_State* L) {
        NVGcontext* ctx = GetContextInternal(L, 1);
        float x = static_cast<float>(luaL_checknumber(L, 2));
        float y = static_cast<float>(luaL_checknumber(L, 3));
        float w = static_cast<float>(luaL_checknumber(L, 4));
        float h = static_cast<float>(luaL_checknumber(L, 5));
        nvgIntersectScissor(ctx, x, y, w, h);
        return 0;
    }

    int lua_nvgResetScissor(lua_State* L) {
        NVGcontext* ctx = GetContextInternal(L, 1);
        nvgResetScissor(ctx);
        return 0;
    }

    // ============================================================================
    // Composite Operation Functions
    // ============================================================================

    int lua_nvgGlobalCompositeOperation(lua_State* L) {
        NVGcontext* ctx = GetContextInternal(L, 1);
        int op = static_cast<int>(luaL_checkinteger(L, 2));
        nvgGlobalCompositeOperation(ctx, op);
        return 0;
    }

    int lua_nvgGlobalCompositeBlendFunc(lua_State* L) {
        NVGcontext* ctx = GetContextInternal(L, 1);
        int sfactor = static_cast<int>(luaL_checkinteger(L, 2));
        int dfactor = static_cast<int>(luaL_checkinteger(L, 3));
        nvgGlobalCompositeBlendFunc(ctx, sfactor, dfactor);
        return 0;
    }

    int lua_nvgGlobalCompositeBlendFuncSeparate(lua_State* L) {
        NVGcontext* ctx = GetContextInternal(L, 1);
        int srcRGB = static_cast<int>(luaL_checkinteger(L, 2));
        int dstRGB = static_cast<int>(luaL_checkinteger(L, 3));
        int srcAlpha = static_cast<int>(luaL_checkinteger(L, 4));
        int dstAlpha = static_cast<int>(luaL_checkinteger(L, 5));
        nvgGlobalCompositeBlendFuncSeparate(ctx, srcRGB, dstRGB, srcAlpha, dstAlpha);
        return 0;
    }

    // ============================================================================
    // Transform Utility Functions
    // ============================================================================

    int lua_nvgDegToRad(lua_State* L) {
        float deg = static_cast<float>(luaL_checknumber(L, 1));
        float rad = nvgDegToRad(deg);
        lua_pushnumber(L, rad);
        return 1;
    }

    int lua_nvgRadToDeg(lua_State* L) {
        float rad = static_cast<float>(luaL_checknumber(L, 1));
        float deg = nvgRadToDeg(rad);
        lua_pushnumber(L, deg);
        return 1;
    }

    // ============================================================================
    // Other Utility Functions
    // ============================================================================

    int lua_nvgShapeAntiAlias(lua_State* L) {
        NVGcontext* ctx = GetContextInternal(L, 1);
        int enabled = lua_toboolean(L, 2);
        nvgShapeAntiAlias(ctx, enabled);
        return 0;
    }

} // anonymous namespace

// Public helper function implementations

NVGcontext* NanoVGUtils::GetContext(lua_State* L, int idx) {
    if (!lua_islightuserdata(L, idx)) {
        luaL_error(L, "Expected NVGcontext (light userdata)");
        return nullptr;
    }
    return static_cast<NVGcontext*>(lua_touserdata(L, idx));
}

NVGcolor NanoVGUtils::TableToColor(lua_State* L, int idx) {
    // Validate that we have a table
    if (!lua_istable(L, idx)) {
        luaL_error(L, "Expected color table, got %s", lua_typename(L, lua_type(L, idx)));
        return nvgRGBA(0, 0, 0, 0);
    }

    NVGcolor color;

    // Extract and validate red component
    lua_rawgeti(L, idx, 1);
    if (!lua_isnumber(L, -1)) {
        luaL_error(L, "Color table element 1 (red) must be a number");
        lua_pop(L, 1);
        return nvgRGBA(0, 0, 0, 0);
    }
    color.r = static_cast<float>(lua_tonumber(L, -1));
    lua_pop(L, 1);

    // Extract and validate green component
    lua_rawgeti(L, idx, 2);
    if (!lua_isnumber(L, -1)) {
        luaL_error(L, "Color table element 2 (green) must be a number");
        lua_pop(L, 1);
        return nvgRGBA(0, 0, 0, 0);
    }
    color.g = static_cast<float>(lua_tonumber(L, -1));
    lua_pop(L, 1);

    // Extract and validate blue component
    lua_rawgeti(L, idx, 3);
    if (!lua_isnumber(L, -1)) {
        luaL_error(L, "Color table element 3 (blue) must be a number");
        lua_pop(L, 1);
        return nvgRGBA(0, 0, 0, 0);
    }
    color.b = static_cast<float>(lua_tonumber(L, -1));
    lua_pop(L, 1);

    // Extract and validate alpha component
    lua_rawgeti(L, idx, 4);
    if (!lua_isnumber(L, -1)) {
        luaL_error(L, "Color table element 4 (alpha) must be a number");
        lua_pop(L, 1);
        return nvgRGBA(0, 0, 0, 0);
    }
    color.a = static_cast<float>(lua_tonumber(L, -1));
    lua_pop(L, 1);

    return color;
}

void NanoVGUtils::SetupBindings(lua_State* L) {
    // Note: The nvg table is already on the stack at -1

    // Color utility functions
    lua_pushcfunction(L, lua_nvgRGBf);
    lua_setfield(L, -2, "rgbf");

    lua_pushcfunction(L, lua_nvgHSL);
    lua_setfield(L, -2, "hsl");

    lua_pushcfunction(L, lua_nvgHSLA);
    lua_setfield(L, -2, "hsla");

    lua_pushcfunction(L, lua_nvgLerpRGBA);
    lua_setfield(L, -2, "lerpRGBA");

    lua_pushcfunction(L, lua_nvgTransRGBA);
    lua_setfield(L, -2, "transRGBA");

    lua_pushcfunction(L, lua_nvgTransRGBAf);
    lua_setfield(L, -2, "transRGBAf");

    // Scissoring functions
    lua_pushcfunction(L, lua_nvgScissor);
    lua_setfield(L, -2, "scissor");

    lua_pushcfunction(L, lua_nvgIntersectScissor);
    lua_setfield(L, -2, "intersectScissor");

    lua_pushcfunction(L, lua_nvgResetScissor);
    lua_setfield(L, -2, "resetScissor");

    // Composite operation functions
    lua_pushcfunction(L, lua_nvgGlobalCompositeOperation);
    lua_setfield(L, -2, "globalCompositeOperation");

    lua_pushcfunction(L, lua_nvgGlobalCompositeBlendFunc);
    lua_setfield(L, -2, "globalCompositeBlendFunc");

    lua_pushcfunction(L, lua_nvgGlobalCompositeBlendFuncSeparate);
    lua_setfield(L, -2, "globalCompositeBlendFuncSeparate");

    // Transform utility functions
    lua_pushcfunction(L, lua_nvgDegToRad);
    lua_setfield(L, -2, "degToRad");

    lua_pushcfunction(L, lua_nvgRadToDeg);
    lua_setfield(L, -2, "radToDeg");

    // Other utility functions
    lua_pushcfunction(L, lua_nvgShapeAntiAlias);
    lua_setfield(L, -2, "shapeAntiAlias");

    // Composite operation constants
    lua_pushinteger(L, NVG_SOURCE_OVER);
    lua_setfield(L, -2, "SOURCE_OVER");

    lua_pushinteger(L, NVG_SOURCE_IN);
    lua_setfield(L, -2, "SOURCE_IN");

    lua_pushinteger(L, NVG_SOURCE_OUT);
    lua_setfield(L, -2, "SOURCE_OUT");

    lua_pushinteger(L, NVG_ATOP);
    lua_setfield(L, -2, "ATOP");

    lua_pushinteger(L, NVG_DESTINATION_OVER);
    lua_setfield(L, -2, "DESTINATION_OVER");

    lua_pushinteger(L, NVG_DESTINATION_IN);
    lua_setfield(L, -2, "DESTINATION_IN");

    lua_pushinteger(L, NVG_DESTINATION_OUT);
    lua_setfield(L, -2, "DESTINATION_OUT");

    lua_pushinteger(L, NVG_DESTINATION_ATOP);
    lua_setfield(L, -2, "DESTINATION_ATOP");

    lua_pushinteger(L, NVG_LIGHTER);
    lua_setfield(L, -2, "LIGHTER");

    lua_pushinteger(L, NVG_COPY);
    lua_setfield(L, -2, "COPY");

    lua_pushinteger(L, NVG_XOR);
    lua_setfield(L, -2, "XOR");

    // Blend factor constants
    lua_pushinteger(L, NVG_ZERO);
    lua_setfield(L, -2, "ZERO");

    lua_pushinteger(L, NVG_ONE);
    lua_setfield(L, -2, "ONE");

    lua_pushinteger(L, NVG_SRC_COLOR);
    lua_setfield(L, -2, "SRC_COLOR");

    lua_pushinteger(L, NVG_ONE_MINUS_SRC_COLOR);
    lua_setfield(L, -2, "ONE_MINUS_SRC_COLOR");

    lua_pushinteger(L, NVG_DST_COLOR);
    lua_setfield(L, -2, "DST_COLOR");

    lua_pushinteger(L, NVG_ONE_MINUS_DST_COLOR);
    lua_setfield(L, -2, "ONE_MINUS_DST_COLOR");

    lua_pushinteger(L, NVG_SRC_ALPHA);
    lua_setfield(L, -2, "SRC_ALPHA");

    lua_pushinteger(L, NVG_ONE_MINUS_SRC_ALPHA);
    lua_setfield(L, -2, "ONE_MINUS_SRC_ALPHA");

    lua_pushinteger(L, NVG_DST_ALPHA);
    lua_setfield(L, -2, "DST_ALPHA");

    lua_pushinteger(L, NVG_ONE_MINUS_DST_ALPHA);
    lua_setfield(L, -2, "ONE_MINUS_DST_ALPHA");

    lua_pushinteger(L, NVG_SRC_ALPHA_SATURATE);
    lua_setfield(L, -2, "SRC_ALPHA_SATURATE");
}
