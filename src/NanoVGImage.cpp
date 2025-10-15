#include "NanoVGImage.h"
#include "Logger.h"
#include <nanovg.h>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

namespace {
    // Helper to get NVGcontext* from light userdata at stack position
    NVGcontext* GetContext(lua_State* L, int idx) {
        if (!lua_islightuserdata(L, idx)) {
            luaL_error(L, "Expected NVGcontext (light userdata)");
            return nullptr;
        }
        return static_cast<NVGcontext*>(lua_touserdata(L, idx));
    }

    // ============================================================================
    // Image Management Functions
    // ============================================================================

    int lua_nvgCreateImage(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        const char* filename = luaL_checkstring(L, 2);
        int imageFlags = static_cast<int>(luaL_optinteger(L, 3, 0));
        int handle = nvgCreateImage(ctx, filename, imageFlags);
        lua_pushinteger(L, handle);
        return 1;
    }

    int lua_nvgImageSize(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        int image = static_cast<int>(luaL_checkinteger(L, 2));
        int w, h;
        nvgImageSize(ctx, image, &w, &h);
        lua_pushinteger(L, w);
        lua_pushinteger(L, h);
        return 2;
    }

    int lua_nvgDeleteImage(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        int image = static_cast<int>(luaL_checkinteger(L, 2));
        nvgDeleteImage(ctx, image);
        return 0;
    }

} // anonymous namespace

void NanoVGImage::SetupBindings(lua_State* L) {
    // Note: The nvg table is already on the stack at -1

    // Image management functions
    lua_pushcfunction(L, lua_nvgCreateImage);
    lua_setfield(L, -2, "createImage");

    lua_pushcfunction(L, lua_nvgImageSize);
    lua_setfield(L, -2, "imageSize");

    lua_pushcfunction(L, lua_nvgDeleteImage);
    lua_setfield(L, -2, "deleteImage");

    // Image flags constants
    lua_pushinteger(L, NVG_IMAGE_GENERATE_MIPMAPS);
    lua_setfield(L, -2, "IMAGE_GENERATE_MIPMAPS");

    lua_pushinteger(L, NVG_IMAGE_REPEATX);
    lua_setfield(L, -2, "IMAGE_REPEATX");

    lua_pushinteger(L, NVG_IMAGE_REPEATY);
    lua_setfield(L, -2, "IMAGE_REPEATY");

    lua_pushinteger(L, NVG_IMAGE_FLIPY);
    lua_setfield(L, -2, "IMAGE_FLIPY");

    lua_pushinteger(L, NVG_IMAGE_PREMULTIPLIED);
    lua_setfield(L, -2, "IMAGE_PREMULTIPLIED");

    lua_pushinteger(L, NVG_IMAGE_NEAREST);
    lua_setfield(L, -2, "IMAGE_NEAREST");
}
