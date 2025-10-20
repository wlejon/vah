#pragma once

#include <string>
#include <vector>
#include <unordered_map>
#include <RmlUi/Core.h>

extern "C" {
#include <lua.h>
}

/**
 * SyntaxHighlighter - Lua callback interface for syntax highlighting.
 *
 * Calls a Lua function to get color tokens for each line.
 * Caches results per line with invalidation support.
 */
class SyntaxHighlighter {
public:
    struct Token {
        int line;
        int start_col;
        int end_col;
        Rml::Colourb color;

        Token() : line(0), start_col(0), end_col(0), color(255, 255, 255, 255) {}
        Token(int l, int sc, int ec, Rml::Colourb c)
            : line(l), start_col(sc), end_col(ec), color(c) {}
    };

    SyntaxHighlighter();
    ~SyntaxHighlighter();

    // Set the Lua highlighting function name
    void SetHighlightFunction(const std::string& function_name);
    const std::string& GetHighlightFunction() const { return function_name_; }

    // Get tokens for text
    std::vector<Token> GetTokens(const std::string& text);

    // Invalidate cache
    void InvalidateCache();

private:
    std::string function_name_;
    std::unordered_map<int, std::vector<Token>> cache_;
    bool cache_valid_;
};
