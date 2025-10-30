#include "NanoVGImage.h"
#include "NanoVGUtils.h"
#include "Logger.h"
#include <nanovg.h>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

namespace {
    const char* IMAGE_METATABLE = "NVGimage";

    // Structure to hold image handle and context for cleanup
    struct NVGImageHandle {
        int handle;
        NVGcontext* ctx;
    };

    // Use shared GetContext from NanoVGUtils
    inline NVGcontext* GetContext(lua_State* L, int idx) {
        return NanoVGUtils::GetContext(L, idx);
    }

    // Helper to create image userdata with automatic cleanup
    void PushImageHandle(lua_State* L, NVGcontext* ctx, int handle) {
        NVGImageHandle* img = static_cast<NVGImageHandle*>(lua_newuserdata(L, sizeof(NVGImageHandle)));
        img->handle = handle;
        img->ctx = ctx;

        luaL_getmetatable(L, IMAGE_METATABLE);
        lua_setmetatable(L, -2);
    }

    // Helper to extract image handle from userdata
    int GetImageHandle(lua_State* L, int idx) {
        NVGImageHandle* img = static_cast<NVGImageHandle*>(luaL_checkudata(L, idx, IMAGE_METATABLE));
        return img->handle;
    }

    // ============================================================================
    // Image Management Functions
    // ============================================================================

    int lua_nvgCreateImage(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        const char* filename = luaL_checkstring(L, 2);
        int imageFlags = static_cast<int>(luaL_optinteger(L, 3, 0));
        int handle = nvgCreateImage(ctx, filename, imageFlags);

        // Return nil on failure instead of -1
        if (handle == -1) {
            lua_pushnil(L);
            return 1;
        }

        // Wrap in userdata for automatic cleanup
        PushImageHandle(L, ctx, handle);
        return 1;
    }

    int lua_nvgImageSize(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        int image = GetImageHandle(L, 2);
        int w, h;
        nvgImageSize(ctx, image, &w, &h);
        lua_pushinteger(L, w);
        lua_pushinteger(L, h);
        return 2;
    }

    int lua_nvgDeleteImage(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        int image = GetImageHandle(L, 2);

        // If it's a userdata, invalidate the handle to prevent double-free
        if (lua_isuserdata(L, 2)) {
            NVGImageHandle* img = static_cast<NVGImageHandle*>(luaL_checkudata(L, 2, IMAGE_METATABLE));
            if (img->handle != -1) {
                nvgDeleteImage(ctx, img->handle);
                img->handle = -1;  // Mark as deleted
            }
        } else {
            // Raw integer - just delete it
            nvgDeleteImage(ctx, image);
        }
        return 0;
    }

    // ============================================================================
    // Image Metatable Functions
    // ============================================================================

    int lua_nvgImageGC(lua_State* L) {
        NVGImageHandle* img = static_cast<NVGImageHandle*>(luaL_checkudata(L, 1, IMAGE_METATABLE));

        // Only delete if handle is still valid and context exists
        if (img->handle != -1 && img->ctx != nullptr) {
            nvgDeleteImage(img->ctx, img->handle);
            img->handle = -1;
            LOG_INFO("NanoVG image handle {} automatically cleaned up", img->handle);
        }
        return 0;
    }

    int lua_nvgImageToString(lua_State* L) {
        NVGImageHandle* img = static_cast<NVGImageHandle*>(luaL_checkudata(L, 1, IMAGE_METATABLE));
        if (img->handle == -1) {
            lua_pushfstring(L, "NVGimage: <deleted>");
        } else {
            lua_pushfstring(L, "NVGimage: %d", img->handle);
        }
        return 1;
    }

} // anonymous namespace

void NanoVGImage::SetupBindings(lua_State* L) {
    // Note: The nvg table is already on the stack at -1

    // Create image metatable for automatic cleanup
    luaL_newmetatable(L, IMAGE_METATABLE);

    lua_pushcfunction(L, lua_nvgImageGC);
    lua_setfield(L, -2, "__gc");

    lua_pushcfunction(L, lua_nvgImageToString);
    lua_setfield(L, -2, "__tostring");

    lua_pop(L, 1);  // Pop metatable

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
