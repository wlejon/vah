#include "SyntaxHighlighter.h"
#include "Logger.h"
#include <RmlUi/Lua/Interpreter.h>

extern "C" {
#include <lauxlib.h>
}

SyntaxHighlighter::SyntaxHighlighter()
    : cache_valid_(false)
{
}

SyntaxHighlighter::~SyntaxHighlighter() = default;

void SyntaxHighlighter::SetHighlightFunction(const std::string& function_name) {
    function_name_ = function_name;
    InvalidateCache();
}

std::vector<SyntaxHighlighter::Token> SyntaxHighlighter::GetTokens(const std::string& text) {
    std::vector<Token> tokens;

    if (function_name_.empty()) {
        return tokens;
    }

    // Get RmlUI Lua state
    lua_State* L = Rml::Lua::Interpreter::GetLuaState();
    if (!L) {
        LOG_ERROR("SyntaxHighlighter: RmlUI Lua state not available");
        return tokens;
    }

    // Get the Lua function
    lua_getglobal(L, function_name_.c_str());

    if (!lua_isfunction(L, -1)) {
        LOG_WARN("SyntaxHighlighter: '{}' is not a valid Lua function", function_name_);
        lua_pop(L, 1);
        return tokens;
    }

    // Push text argument
    lua_pushstring(L, text.c_str());

    // Call function: 1 argument (text), 1 return value (token array)
    if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
        const char* error = lua_tostring(L, -1);
        LOG_ERROR("SyntaxHighlighter: Error calling '{}': {}", function_name_, error);
        lua_pop(L, 1);
        return tokens;
    }

    // Parse returned token array
    if (!lua_istable(L, -1)) {
        LOG_WARN("SyntaxHighlighter: '{}' did not return a table", function_name_);
        lua_pop(L, 1);
        return tokens;
    }

    // Iterate over returned array
    size_t count = lua_rawlen(L, -1);
    for (size_t i = 1; i <= count; ++i) {
        lua_rawgeti(L, -1, i);

        if (lua_istable(L, -1)) {
            Token token;

            // Get line
            lua_getfield(L, -1, "line");
            if (lua_isnumber(L, -1)) {
                token.line = static_cast<int>(lua_tointeger(L, -1));
            }
            lua_pop(L, 1);

            // Get start_col
            lua_getfield(L, -1, "start_col");
            if (lua_isnumber(L, -1)) {
                token.start_col = static_cast<int>(lua_tointeger(L, -1));
            }
            lua_pop(L, 1);

            // Get end_col
            lua_getfield(L, -1, "end_col");
            if (lua_isnumber(L, -1)) {
                token.end_col = static_cast<int>(lua_tointeger(L, -1));
            }
            lua_pop(L, 1);

            // Get color (r, g, b, a)
            lua_getfield(L, -1, "r");
            int r = lua_isnumber(L, -1) ? static_cast<int>(lua_tointeger(L, -1)) : 255;
            lua_pop(L, 1);

            lua_getfield(L, -1, "g");
            int g = lua_isnumber(L, -1) ? static_cast<int>(lua_tointeger(L, -1)) : 255;
            lua_pop(L, 1);

            lua_getfield(L, -1, "b");
            int b = lua_isnumber(L, -1) ? static_cast<int>(lua_tointeger(L, -1)) : 255;
            lua_pop(L, 1);

            lua_getfield(L, -1, "a");
            int a = lua_isnumber(L, -1) ? static_cast<int>(lua_tointeger(L, -1)) : 255;
            lua_pop(L, 1);

            token.color = Rml::Colourb(r, g, b, a);
            tokens.push_back(token);
        }

        lua_pop(L, 1); // Pop token table
    }

    lua_pop(L, 1); // Pop token array

    return tokens;
}

void SyntaxHighlighter::InvalidateCache() {
    cache_.clear();
    cache_valid_ = false;
}
