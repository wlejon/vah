#include "NanoVGPaint.h"
#include "NanoVGUtils.h"
#include "Logger.h"
#include <nanovg.h>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

namespace {
    const char* PAINT_METATABLE = "NVGpaint";
    const char* IMAGE_METATABLE = "NVGimage";

    // Structure to hold image handle and context (must match NanoVGImage.cpp)
    struct NVGImageHandle {
        int handle;
        NVGcontext* ctx;
    };

    // Use shared GetContext from NanoVGUtils
    inline NVGcontext* GetContext(lua_State* L, int idx) {
        return NanoVGUtils::GetContext(L, idx);
    }

    // Helper to extract image handle from userdata
    int GetImageHandle(lua_State* L, int idx) {
        NVGImageHandle* img = static_cast<NVGImageHandle*>(luaL_checkudata(L, idx, IMAGE_METATABLE));
        return img->handle;
    }

    // Helper to create a paint userdata and set its metatable
    NVGpaint* CreatePaintUserdata(lua_State* L, const NVGpaint& paint) {
        NVGpaint* paintPtr = static_cast<NVGpaint*>(lua_newuserdata(L, sizeof(NVGpaint)));
        *paintPtr = paint;

        luaL_getmetatable(L, PAINT_METATABLE);
        lua_setmetatable(L, -2);

        return paintPtr;
    }

    // Helper to check and retrieve paint from userdata
    NVGpaint* CheckPaint(lua_State* L, int idx) {
        return static_cast<NVGpaint*>(luaL_checkudata(L, idx, PAINT_METATABLE));
    }

    // ============================================================================
    // Gradient Functions
    // ============================================================================

    int lua_nvgLinearGradient(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float sx = static_cast<float>(luaL_checknumber(L, 2));
        float sy = static_cast<float>(luaL_checknumber(L, 3));
        float ex = static_cast<float>(luaL_checknumber(L, 4));
        float ey = static_cast<float>(luaL_checknumber(L, 5));
        luaL_checktype(L, 6, LUA_TTABLE);
        NVGcolor icol = NanoVGUtils::TableToColor(L, 6);
        luaL_checktype(L, 7, LUA_TTABLE);
        NVGcolor ocol = NanoVGUtils::TableToColor(L, 7);

        NVGpaint paint = nvgLinearGradient(ctx, sx, sy, ex, ey, icol, ocol);
        CreatePaintUserdata(L, paint);

        return 1;
    }

    int lua_nvgRadialGradient(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float cx = static_cast<float>(luaL_checknumber(L, 2));
        float cy = static_cast<float>(luaL_checknumber(L, 3));
        float inr = static_cast<float>(luaL_checknumber(L, 4));
        float outr = static_cast<float>(luaL_checknumber(L, 5));
        luaL_checktype(L, 6, LUA_TTABLE);
        NVGcolor icol = NanoVGUtils::TableToColor(L, 6);
        luaL_checktype(L, 7, LUA_TTABLE);
        NVGcolor ocol = NanoVGUtils::TableToColor(L, 7);

        NVGpaint paint = nvgRadialGradient(ctx, cx, cy, inr, outr, icol, ocol);
        CreatePaintUserdata(L, paint);

        return 1;
    }

    int lua_nvgBoxGradient(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float x = static_cast<float>(luaL_checknumber(L, 2));
        float y = static_cast<float>(luaL_checknumber(L, 3));
        float w = static_cast<float>(luaL_checknumber(L, 4));
        float h = static_cast<float>(luaL_checknumber(L, 5));
        float r = static_cast<float>(luaL_checknumber(L, 6));
        float f = static_cast<float>(luaL_checknumber(L, 7));
        luaL_checktype(L, 8, LUA_TTABLE);
        NVGcolor icol = NanoVGUtils::TableToColor(L, 8);
        luaL_checktype(L, 9, LUA_TTABLE);
        NVGcolor ocol = NanoVGUtils::TableToColor(L, 9);

        NVGpaint paint = nvgBoxGradient(ctx, x, y, w, h, r, f, icol, ocol);
        CreatePaintUserdata(L, paint);

        return 1;
    }

    // ============================================================================
    // Image Pattern Function
    // ============================================================================

    int lua_nvgImagePattern(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float ox = static_cast<float>(luaL_checknumber(L, 2));
        float oy = static_cast<float>(luaL_checknumber(L, 3));
        float ex = static_cast<float>(luaL_checknumber(L, 4));
        float ey = static_cast<float>(luaL_checknumber(L, 5));
        float angle = static_cast<float>(luaL_checknumber(L, 6));
        int image = GetImageHandle(L, 7);  // Accept both userdata and integer
        float alpha = static_cast<float>(luaL_checknumber(L, 8));

        NVGpaint paint = nvgImagePattern(ctx, ox, oy, ex, ey, angle, image, alpha);
        CreatePaintUserdata(L, paint);

        return 1;
    }

    // ============================================================================
    // Paint Application Functions
    // ============================================================================

    int lua_nvgFillPaint(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        NVGpaint* paint = CheckPaint(L, 2);
        nvgFillPaint(ctx, *paint);
        return 0;
    }

    int lua_nvgStrokePaint(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        NVGpaint* paint = CheckPaint(L, 2);
        nvgStrokePaint(ctx, *paint);
        return 0;
    }

    // ============================================================================
    // Paint Metatable Functions
    // ============================================================================

    int lua_nvgPaintGC(lua_State* L) {
        // NVGpaint is a simple struct with no dynamic allocation
        // No cleanup needed, but we provide this for completeness
        return 0;
    }

    int lua_nvgPaintToString(lua_State* L) {
        NVGpaint* paint = CheckPaint(L, 1);
        lua_pushfstring(L, "NVGpaint: %p", paint);
        return 1;
    }

} // anonymous namespace

void NanoVGPaint::SetupBindings(lua_State* L) {
    // Note: The nvg table is already on the stack at -1

    // Create paint metatable
    luaL_newmetatable(L, PAINT_METATABLE);

    lua_pushcfunction(L, lua_nvgPaintGC);
    lua_setfield(L, -2, "__gc");

    lua_pushcfunction(L, lua_nvgPaintToString);
    lua_setfield(L, -2, "__tostring");

    lua_pop(L, 1); // Pop metatable

    // Register gradient functions into nvg table
    lua_pushcfunction(L, lua_nvgLinearGradient);
    lua_setfield(L, -2, "linearGradient");

    lua_pushcfunction(L, lua_nvgRadialGradient);
    lua_setfield(L, -2, "radialGradient");

    lua_pushcfunction(L, lua_nvgBoxGradient);
    lua_setfield(L, -2, "boxGradient");

    lua_pushcfunction(L, lua_nvgImagePattern);
    lua_setfield(L, -2, "imagePattern");

    lua_pushcfunction(L, lua_nvgFillPaint);
    lua_setfield(L, -2, "fillPaint");

    lua_pushcfunction(L, lua_nvgStrokePaint);
    lua_setfield(L, -2, "strokePaint");
}
