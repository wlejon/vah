#include "NanoVGBindings.h"
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
    // Color Functions
    // ============================================================================

    int lua_nvgRGBA(lua_State* L) {
        unsigned char r = static_cast<unsigned char>(luaL_checkinteger(L, 1));
        unsigned char g = static_cast<unsigned char>(luaL_checkinteger(L, 2));
        unsigned char b = static_cast<unsigned char>(luaL_checkinteger(L, 3));
        unsigned char a = static_cast<unsigned char>(luaL_checkinteger(L, 4));

        NVGcolor color = nvgRGBA(r, g, b, a);

        // Return as a table {r, g, b, a}
        lua_createtable(L, 4, 0);
        lua_pushnumber(L, color.r);
        lua_rawseti(L, -2, 1);
        lua_pushnumber(L, color.g);
        lua_rawseti(L, -2, 2);
        lua_pushnumber(L, color.b);
        lua_rawseti(L, -2, 3);
        lua_pushnumber(L, color.a);
        lua_rawseti(L, -2, 4);

        return 1;
    }

    int lua_nvgRGBAf(lua_State* L) {
        float r = static_cast<float>(luaL_checknumber(L, 1));
        float g = static_cast<float>(luaL_checknumber(L, 2));
        float b = static_cast<float>(luaL_checknumber(L, 3));
        float a = static_cast<float>(luaL_checknumber(L, 4));

        NVGcolor color = nvgRGBAf(r, g, b, a);

        // Return as a table {r, g, b, a}
        lua_createtable(L, 4, 0);
        lua_pushnumber(L, color.r);
        lua_rawseti(L, -2, 1);
        lua_pushnumber(L, color.g);
        lua_rawseti(L, -2, 2);
        lua_pushnumber(L, color.b);
        lua_rawseti(L, -2, 3);
        lua_pushnumber(L, color.a);
        lua_rawseti(L, -2, 4);

        return 1;
    }

    int lua_nvgRGB(lua_State* L) {
        unsigned char r = static_cast<unsigned char>(luaL_checkinteger(L, 1));
        unsigned char g = static_cast<unsigned char>(luaL_checkinteger(L, 2));
        unsigned char b = static_cast<unsigned char>(luaL_checkinteger(L, 3));

        NVGcolor color = nvgRGB(r, g, b);

        // Return as a table {r, g, b, a}
        lua_createtable(L, 4, 0);
        lua_pushnumber(L, color.r);
        lua_rawseti(L, -2, 1);
        lua_pushnumber(L, color.g);
        lua_rawseti(L, -2, 2);
        lua_pushnumber(L, color.b);
        lua_rawseti(L, -2, 3);
        lua_pushnumber(L, color.a);
        lua_rawseti(L, -2, 4);

        return 1;
    }

    // Helper to convert Lua color table to NVGcolor
    NVGcolor TableToColor(lua_State* L, int idx) {
        NVGcolor color;

        lua_rawgeti(L, idx, 1);
        color.r = static_cast<float>(lua_tonumber(L, -1));
        lua_pop(L, 1);

        lua_rawgeti(L, idx, 2);
        color.g = static_cast<float>(lua_tonumber(L, -1));
        lua_pop(L, 1);

        lua_rawgeti(L, idx, 3);
        color.b = static_cast<float>(lua_tonumber(L, -1));
        lua_pop(L, 1);

        lua_rawgeti(L, idx, 4);
        color.a = static_cast<float>(lua_tonumber(L, -1));
        lua_pop(L, 1);

        return color;
    }

    // ============================================================================
    // Path Drawing Functions
    // ============================================================================

    int lua_nvgBeginPath(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        nvgBeginPath(ctx);
        return 0;
    }

    int lua_nvgMoveTo(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float x = static_cast<float>(luaL_checknumber(L, 2));
        float y = static_cast<float>(luaL_checknumber(L, 3));
        nvgMoveTo(ctx, x, y);
        return 0;
    }

    int lua_nvgLineTo(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float x = static_cast<float>(luaL_checknumber(L, 2));
        float y = static_cast<float>(luaL_checknumber(L, 3));
        nvgLineTo(ctx, x, y);
        return 0;
    }

    int lua_nvgBezierTo(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float c1x = static_cast<float>(luaL_checknumber(L, 2));
        float c1y = static_cast<float>(luaL_checknumber(L, 3));
        float c2x = static_cast<float>(luaL_checknumber(L, 4));
        float c2y = static_cast<float>(luaL_checknumber(L, 5));
        float x = static_cast<float>(luaL_checknumber(L, 6));
        float y = static_cast<float>(luaL_checknumber(L, 7));
        nvgBezierTo(ctx, c1x, c1y, c2x, c2y, x, y);
        return 0;
    }

    int lua_nvgQuadTo(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float cx = static_cast<float>(luaL_checknumber(L, 2));
        float cy = static_cast<float>(luaL_checknumber(L, 3));
        float x = static_cast<float>(luaL_checknumber(L, 4));
        float y = static_cast<float>(luaL_checknumber(L, 5));
        nvgQuadTo(ctx, cx, cy, x, y);
        return 0;
    }

    int lua_nvgArcTo(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float x1 = static_cast<float>(luaL_checknumber(L, 2));
        float y1 = static_cast<float>(luaL_checknumber(L, 3));
        float x2 = static_cast<float>(luaL_checknumber(L, 4));
        float y2 = static_cast<float>(luaL_checknumber(L, 5));
        float radius = static_cast<float>(luaL_checknumber(L, 6));
        nvgArcTo(ctx, x1, y1, x2, y2, radius);
        return 0;
    }

    int lua_nvgClosePath(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        nvgClosePath(ctx);
        return 0;
    }

    int lua_nvgPathWinding(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        int dir = static_cast<int>(luaL_checkinteger(L, 2));
        nvgPathWinding(ctx, dir);
        return 0;
    }

    int lua_nvgArc(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float cx = static_cast<float>(luaL_checknumber(L, 2));
        float cy = static_cast<float>(luaL_checknumber(L, 3));
        float r = static_cast<float>(luaL_checknumber(L, 4));
        float a0 = static_cast<float>(luaL_checknumber(L, 5));
        float a1 = static_cast<float>(luaL_checknumber(L, 6));
        int dir = static_cast<int>(luaL_checkinteger(L, 7));
        nvgArc(ctx, cx, cy, r, a0, a1, dir);
        return 0;
    }

    int lua_nvgRect(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float x = static_cast<float>(luaL_checknumber(L, 2));
        float y = static_cast<float>(luaL_checknumber(L, 3));
        float w = static_cast<float>(luaL_checknumber(L, 4));
        float h = static_cast<float>(luaL_checknumber(L, 5));
        nvgRect(ctx, x, y, w, h);
        return 0;
    }

    int lua_nvgRoundedRect(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float x = static_cast<float>(luaL_checknumber(L, 2));
        float y = static_cast<float>(luaL_checknumber(L, 3));
        float w = static_cast<float>(luaL_checknumber(L, 4));
        float h = static_cast<float>(luaL_checknumber(L, 5));
        float r = static_cast<float>(luaL_checknumber(L, 6));
        nvgRoundedRect(ctx, x, y, w, h, r);
        return 0;
    }

    int lua_nvgEllipse(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float cx = static_cast<float>(luaL_checknumber(L, 2));
        float cy = static_cast<float>(luaL_checknumber(L, 3));
        float rx = static_cast<float>(luaL_checknumber(L, 4));
        float ry = static_cast<float>(luaL_checknumber(L, 5));
        nvgEllipse(ctx, cx, cy, rx, ry);
        return 0;
    }

    int lua_nvgCircle(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float cx = static_cast<float>(luaL_checknumber(L, 2));
        float cy = static_cast<float>(luaL_checknumber(L, 3));
        float r = static_cast<float>(luaL_checknumber(L, 4));
        nvgCircle(ctx, cx, cy, r);
        return 0;
    }

    // ============================================================================
    // Fill and Stroke Functions
    // ============================================================================

    int lua_nvgFill(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        nvgFill(ctx);
        return 0;
    }

    int lua_nvgStroke(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        nvgStroke(ctx);
        return 0;
    }

    int lua_nvgFillColor(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        luaL_checktype(L, 2, LUA_TTABLE);
        NVGcolor color = TableToColor(L, 2);
        nvgFillColor(ctx, color);
        return 0;
    }

    int lua_nvgStrokeColor(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        luaL_checktype(L, 2, LUA_TTABLE);
        NVGcolor color = TableToColor(L, 2);
        nvgStrokeColor(ctx, color);
        return 0;
    }

    int lua_nvgStrokeWidth(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float width = static_cast<float>(luaL_checknumber(L, 2));
        nvgStrokeWidth(ctx, width);
        return 0;
    }

    // ============================================================================
    // State Functions
    // ============================================================================

    int lua_nvgSave(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        nvgSave(ctx);
        return 0;
    }

    int lua_nvgRestore(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        nvgRestore(ctx);
        return 0;
    }

    int lua_nvgReset(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        nvgReset(ctx);
        return 0;
    }

    // ============================================================================
    // Transform Functions
    // ============================================================================

    int lua_nvgResetTransform(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        nvgResetTransform(ctx);
        return 0;
    }

    int lua_nvgTransform(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float a = static_cast<float>(luaL_checknumber(L, 2));
        float b = static_cast<float>(luaL_checknumber(L, 3));
        float c = static_cast<float>(luaL_checknumber(L, 4));
        float d = static_cast<float>(luaL_checknumber(L, 5));
        float e = static_cast<float>(luaL_checknumber(L, 6));
        float f = static_cast<float>(luaL_checknumber(L, 7));
        nvgTransform(ctx, a, b, c, d, e, f);
        return 0;
    }

    int lua_nvgTranslate(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float x = static_cast<float>(luaL_checknumber(L, 2));
        float y = static_cast<float>(luaL_checknumber(L, 3));
        nvgTranslate(ctx, x, y);
        return 0;
    }

    int lua_nvgRotate(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float angle = static_cast<float>(luaL_checknumber(L, 2));
        nvgRotate(ctx, angle);
        return 0;
    }

    int lua_nvgSkewX(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float angle = static_cast<float>(luaL_checknumber(L, 2));
        nvgSkewX(ctx, angle);
        return 0;
    }

    int lua_nvgSkewY(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float angle = static_cast<float>(luaL_checknumber(L, 2));
        nvgSkewY(ctx, angle);
        return 0;
    }

    int lua_nvgScale(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float x = static_cast<float>(luaL_checknumber(L, 2));
        float y = static_cast<float>(luaL_checknumber(L, 3));
        nvgScale(ctx, x, y);
        return 0;
    }

    // ============================================================================
    // Text Functions
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

    int lua_nvgTextAlign(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        int align = static_cast<int>(luaL_checkinteger(L, 2));
        nvgTextAlign(ctx, align);
        return 0;
    }

    int lua_nvgText(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float x = static_cast<float>(luaL_checknumber(L, 2));
        float y = static_cast<float>(luaL_checknumber(L, 3));
        const char* text = luaL_checkstring(L, 4);
        nvgText(ctx, x, y, text, nullptr);
        return 0;
    }

    // ============================================================================
    // Additional Style Functions
    // ============================================================================

    int lua_nvgGlobalAlpha(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float alpha = static_cast<float>(luaL_checknumber(L, 2));
        nvgGlobalAlpha(ctx, alpha);
        return 0;
    }

    int lua_nvgLineCap(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        int cap = static_cast<int>(luaL_checkinteger(L, 2));
        nvgLineCap(ctx, cap);
        return 0;
    }

    int lua_nvgLineJoin(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        int join = static_cast<int>(luaL_checkinteger(L, 2));
        nvgLineJoin(ctx, join);
        return 0;
    }

    int lua_nvgMiterLimit(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float limit = static_cast<float>(luaL_checknumber(L, 2));
        nvgMiterLimit(ctx, limit);
        return 0;
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
        NVGcolor icol = TableToColor(L, 6);
        luaL_checktype(L, 7, LUA_TTABLE);
        NVGcolor ocol = TableToColor(L, 7);

        NVGpaint paint = nvgLinearGradient(ctx, sx, sy, ex, ey, icol, ocol);

        // Return paint as light userdata (Note: this is a simplified approach)
        // For production, you'd want to properly manage paint lifetime
        lua_pushlightuserdata(L, &paint);
        return 1;
    }

    int lua_nvgRadialGradient(lua_State* L) {
        NVGcontext* ctx = GetContext(L, 1);
        float cx = static_cast<float>(luaL_checknumber(L, 2));
        float cy = static_cast<float>(luaL_checknumber(L, 3));
        float inr = static_cast<float>(luaL_checknumber(L, 4));
        float outr = static_cast<float>(luaL_checknumber(L, 5));
        luaL_checktype(L, 6, LUA_TTABLE);
        NVGcolor icol = TableToColor(L, 6);
        luaL_checktype(L, 7, LUA_TTABLE);
        NVGcolor ocol = TableToColor(L, 7);

        NVGpaint paint = nvgRadialGradient(ctx, cx, cy, inr, outr, icol, ocol);

        lua_pushlightuserdata(L, &paint);
        return 1;
    }

} // anonymous namespace

void NanoVGBindings::SetupBindings(lua_State* L) {
    // Create nvg table
    lua_newtable(L);

    // Color functions
    lua_pushcfunction(L, lua_nvgRGBA);
    lua_setfield(L, -2, "rgba");

    lua_pushcfunction(L, lua_nvgRGBAf);
    lua_setfield(L, -2, "rgbaf");

    lua_pushcfunction(L, lua_nvgRGB);
    lua_setfield(L, -2, "rgb");

    // Path drawing functions
    lua_pushcfunction(L, lua_nvgBeginPath);
    lua_setfield(L, -2, "beginPath");

    lua_pushcfunction(L, lua_nvgMoveTo);
    lua_setfield(L, -2, "moveTo");

    lua_pushcfunction(L, lua_nvgLineTo);
    lua_setfield(L, -2, "lineTo");

    lua_pushcfunction(L, lua_nvgBezierTo);
    lua_setfield(L, -2, "bezierTo");

    lua_pushcfunction(L, lua_nvgQuadTo);
    lua_setfield(L, -2, "quadTo");

    lua_pushcfunction(L, lua_nvgArcTo);
    lua_setfield(L, -2, "arcTo");

    lua_pushcfunction(L, lua_nvgClosePath);
    lua_setfield(L, -2, "closePath");

    lua_pushcfunction(L, lua_nvgPathWinding);
    lua_setfield(L, -2, "pathWinding");

    lua_pushcfunction(L, lua_nvgArc);
    lua_setfield(L, -2, "arc");

    lua_pushcfunction(L, lua_nvgRect);
    lua_setfield(L, -2, "rect");

    lua_pushcfunction(L, lua_nvgRoundedRect);
    lua_setfield(L, -2, "roundedRect");

    lua_pushcfunction(L, lua_nvgEllipse);
    lua_setfield(L, -2, "ellipse");

    lua_pushcfunction(L, lua_nvgCircle);
    lua_setfield(L, -2, "circle");

    // Fill and stroke functions
    lua_pushcfunction(L, lua_nvgFill);
    lua_setfield(L, -2, "fill");

    lua_pushcfunction(L, lua_nvgStroke);
    lua_setfield(L, -2, "stroke");

    lua_pushcfunction(L, lua_nvgFillColor);
    lua_setfield(L, -2, "fillColor");

    lua_pushcfunction(L, lua_nvgStrokeColor);
    lua_setfield(L, -2, "strokeColor");

    lua_pushcfunction(L, lua_nvgStrokeWidth);
    lua_setfield(L, -2, "strokeWidth");

    // State functions
    lua_pushcfunction(L, lua_nvgSave);
    lua_setfield(L, -2, "save");

    lua_pushcfunction(L, lua_nvgRestore);
    lua_setfield(L, -2, "restore");

    lua_pushcfunction(L, lua_nvgReset);
    lua_setfield(L, -2, "reset");

    // Transform functions
    lua_pushcfunction(L, lua_nvgResetTransform);
    lua_setfield(L, -2, "resetTransform");

    lua_pushcfunction(L, lua_nvgTransform);
    lua_setfield(L, -2, "transform");

    lua_pushcfunction(L, lua_nvgTranslate);
    lua_setfield(L, -2, "translate");

    lua_pushcfunction(L, lua_nvgRotate);
    lua_setfield(L, -2, "rotate");

    lua_pushcfunction(L, lua_nvgSkewX);
    lua_setfield(L, -2, "skewX");

    lua_pushcfunction(L, lua_nvgSkewY);
    lua_setfield(L, -2, "skewY");

    lua_pushcfunction(L, lua_nvgScale);
    lua_setfield(L, -2, "scale");

    // Text functions
    lua_pushcfunction(L, lua_nvgFontSize);
    lua_setfield(L, -2, "fontSize");

    lua_pushcfunction(L, lua_nvgFontFace);
    lua_setfield(L, -2, "fontFace");

    lua_pushcfunction(L, lua_nvgTextAlign);
    lua_setfield(L, -2, "textAlign");

    lua_pushcfunction(L, lua_nvgText);
    lua_setfield(L, -2, "text");

    // Additional style functions
    lua_pushcfunction(L, lua_nvgGlobalAlpha);
    lua_setfield(L, -2, "globalAlpha");

    lua_pushcfunction(L, lua_nvgLineCap);
    lua_setfield(L, -2, "lineCap");

    lua_pushcfunction(L, lua_nvgLineJoin);
    lua_setfield(L, -2, "lineJoin");

    lua_pushcfunction(L, lua_nvgMiterLimit);
    lua_setfield(L, -2, "miterLimit");

    // Gradient functions
    lua_pushcfunction(L, lua_nvgLinearGradient);
    lua_setfield(L, -2, "linearGradient");

    lua_pushcfunction(L, lua_nvgRadialGradient);
    lua_setfield(L, -2, "radialGradient");

    // Constants
    lua_pushinteger(L, NVG_CCW);
    lua_setfield(L, -2, "CCW");

    lua_pushinteger(L, NVG_CW);
    lua_setfield(L, -2, "CW");

    lua_pushinteger(L, NVG_BUTT);
    lua_setfield(L, -2, "BUTT");

    lua_pushinteger(L, NVG_ROUND);
    lua_setfield(L, -2, "ROUND");

    lua_pushinteger(L, NVG_SQUARE);
    lua_setfield(L, -2, "SQUARE");

    lua_pushinteger(L, NVG_BEVEL);
    lua_setfield(L, -2, "BEVEL");

    lua_pushinteger(L, NVG_MITER);
    lua_setfield(L, -2, "MITER");

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

    // Set as global 'nvg' table
    lua_setglobal(L, "nvg");

    LOG_INFO("NanoVG bindings registered in Lua state");
}
