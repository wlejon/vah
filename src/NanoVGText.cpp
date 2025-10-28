#include "NanoVGText.h"
#include "NanoVGUtils.h"
#include "Logger.h"
#include <nanovg.h>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

namespace {
    // Use shared GetContext from NanoVGUtils
    inline NVGcontext* GetContext(lua_State* L, int idx) {
        return NanoVGUtils::GetContext(L, idx);
    }

    // ============================================================================
    // Font Management Functions
    // ============================================================================

    int lua_nvgCreateFont(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        const char* name = luaL_checkstring(L, 2);
        const char* filename = luaL_checkstring(L, 3);
        int handle = nvgCreateFont(ctx, name, filename);

        // Return nil on failure instead of -1
        if (handle == -1) {
            lua_pushnil(L);
            return 1;
        }

        lua_pushinteger(L, handle);
        return 1;
    }

    int lua_nvgFindFont(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        const char* name = luaL_checkstring(L, 2);
        int handle = nvgFindFont(ctx, name);

        // Return nil on failure instead of -1
        if (handle == -1) {
            lua_pushnil(L);
            return 1;
        }

        lua_pushinteger(L, handle);
        return 1;
    }

    int lua_nvgAddFallbackFontId(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        int baseFont = static_cast<int>(luaL_checkinteger(L, 2));
        int fallbackFont = static_cast<int>(luaL_checkinteger(L, 3));
        int result = nvgAddFallbackFontId(ctx, baseFont, fallbackFont);
        lua_pushinteger(L, result);
        return 1;
    }

    int lua_nvgAddFallbackFont(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        const char* baseFont = luaL_checkstring(L, 2);
        const char* fallbackFont = luaL_checkstring(L, 3);
        int result = nvgAddFallbackFont(ctx, baseFont, fallbackFont);
        lua_pushinteger(L, result);
        return 1;
    }

    // ============================================================================
    // Text Style Functions
    // ============================================================================

    int lua_nvgFontSize(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float size = static_cast<float>(luaL_checknumber(L, 2));
        nvgFontSize(ctx, size);
        return 0;
    }

    int lua_nvgFontFace(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        const char* font = luaL_checkstring(L, 2);
        nvgFontFace(ctx, font);
        return 0;
    }

    int lua_nvgFontFaceId(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        int font = static_cast<int>(luaL_checkinteger(L, 2));
        nvgFontFaceId(ctx, font);
        return 0;
    }

    int lua_nvgTextAlign(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        int align = static_cast<int>(luaL_checkinteger(L, 2));
        nvgTextAlign(ctx, align);
        return 0;
    }

    int lua_nvgFontBlur(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float blur = static_cast<float>(luaL_checknumber(L, 2));
        nvgFontBlur(ctx, blur);
        return 0;
    }

    int lua_nvgTextLetterSpacing(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float spacing = static_cast<float>(luaL_checknumber(L, 2));
        nvgTextLetterSpacing(ctx, spacing);
        return 0;
    }

    int lua_nvgTextLineHeight(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float lineHeight = static_cast<float>(luaL_checknumber(L, 2));
        nvgTextLineHeight(ctx, lineHeight);
        return 0;
    }

    // ============================================================================
    // Text Rendering Functions
    // ============================================================================

    int lua_nvgText(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float x = static_cast<float>(luaL_checknumber(L, 2));
        float y = static_cast<float>(luaL_checknumber(L, 3));
        const char* text = luaL_checkstring(L, 4);
        float advance = nvgText(ctx, x, y, text, nullptr);
        lua_pushnumber(L, advance);
        return 1;
    }

    int lua_nvgTextBox(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float x = static_cast<float>(luaL_checknumber(L, 2));
        float y = static_cast<float>(luaL_checknumber(L, 3));
        float breakRowWidth = static_cast<float>(luaL_checknumber(L, 4));
        const char* text = luaL_checkstring(L, 5);
        nvgTextBox(ctx, x, y, breakRowWidth, text, nullptr);
        return 0;
    }

    // ============================================================================
    // Text Measurement Functions
    // ============================================================================

    int lua_nvgTextBounds(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float x = static_cast<float>(luaL_checknumber(L, 2));
        float y = static_cast<float>(luaL_checknumber(L, 3));
        const char* text = luaL_checkstring(L, 4);

        float bounds[4];
        float advance = nvgTextBounds(ctx, x, y, text, nullptr, bounds);

        lua_pushnumber(L, advance);
        lua_createtable(L, 4, 0);
        lua_pushnumber(L, bounds[0]);
        lua_rawseti(L, -2, 1);
        lua_pushnumber(L, bounds[1]);
        lua_rawseti(L, -2, 2);
        lua_pushnumber(L, bounds[2]);
        lua_rawseti(L, -2, 3);
        lua_pushnumber(L, bounds[3]);
        lua_rawseti(L, -2, 4);

        return 2;
    }

} // anonymous namespace

void NanoVGText::SetupBindings(lua_State* L) {
    // Note: The nvg table is already on the stack at -1

    // Font management functions
    lua_pushcfunction(L, lua_nvgCreateFont);
    lua_setfield(L, -2, "createFont");

    lua_pushcfunction(L, lua_nvgFindFont);
    lua_setfield(L, -2, "findFont");

    lua_pushcfunction(L, lua_nvgAddFallbackFontId);
    lua_setfield(L, -2, "addFallbackFontId");

    lua_pushcfunction(L, lua_nvgAddFallbackFont);
    lua_setfield(L, -2, "addFallbackFont");

    // Text style functions
    lua_pushcfunction(L, lua_nvgFontSize);
    lua_setfield(L, -2, "fontSize");

    lua_pushcfunction(L, lua_nvgFontFace);
    lua_setfield(L, -2, "fontFace");

    lua_pushcfunction(L, lua_nvgFontFaceId);
    lua_setfield(L, -2, "fontFaceId");

    lua_pushcfunction(L, lua_nvgTextAlign);
    lua_setfield(L, -2, "textAlign");

    lua_pushcfunction(L, lua_nvgFontBlur);
    lua_setfield(L, -2, "fontBlur");

    lua_pushcfunction(L, lua_nvgTextLetterSpacing);
    lua_setfield(L, -2, "textLetterSpacing");

    lua_pushcfunction(L, lua_nvgTextLineHeight);
    lua_setfield(L, -2, "textLineHeight");

    // Text rendering functions
    lua_pushcfunction(L, lua_nvgText);
    lua_setfield(L, -2, "text");

    lua_pushcfunction(L, lua_nvgTextBox);
    lua_setfield(L, -2, "textBox");

    // Text measurement functions
    lua_pushcfunction(L, lua_nvgTextBounds);
    lua_setfield(L, -2, "textBounds");

    // Text alignment constants
    lua_pushinteger(L, NVG_ALIGN_LEFT);
    lua_setfield(L, -2, "ALIGN_LEFT");

    lua_pushinteger(L, NVG_ALIGN_CENTER);
    lua_setfield(L, -2, "ALIGN_CENTER");

    lua_pushinteger(L, NVG_ALIGN_RIGHT);
    lua_setfield(L, -2, "ALIGN_RIGHT");

    lua_pushinteger(L, NVG_ALIGN_TOP);
    lua_setfield(L, -2, "ALIGN_TOP");

    lua_pushinteger(L, NVG_ALIGN_MIDDLE);
    lua_setfield(L, -2, "ALIGN_MIDDLE");

    lua_pushinteger(L, NVG_ALIGN_BOTTOM);
    lua_setfield(L, -2, "ALIGN_BOTTOM");

    lua_pushinteger(L, NVG_ALIGN_BASELINE);
    lua_setfield(L, -2, "ALIGN_BASELINE");
}
