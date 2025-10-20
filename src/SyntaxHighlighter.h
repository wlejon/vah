#pragma once

#include <string>
#include <vector>
#include <functional>
#include <RmlUi/Core.h>

/**
 * SyntaxHighlighter - Callback-based interface for syntax highlighting.
 *
 * Supports both token-based (simple pattern matching) and reference-based
 * (semantic/contextual) highlighting through callbacks.
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

    struct ReferenceDecoration {
        int line;
        int start_col;
        int end_col;
        enum Type {
            Underline,
            DottedUnderline,
            WavyUnderline,
            Background
        } type;
        Rml::Colourb color;
        std::string hover_text;  // For tooltips
    };

    // Callback function type: takes text, returns tokens
    using TokenCallback = std::function<std::vector<Token>(const std::string&)>;

    // Reference-based callback: takes text + file_path, returns tokens + decorations
    using ReferenceCallback = std::function<void(
        const std::string& text,
        const std::string& file_path,
        std::vector<Token>& tokens,
        std::vector<ReferenceDecoration>& decorations
    )>;

    SyntaxHighlighter();
    ~SyntaxHighlighter();

    // Set token-based highlighter (simple pattern matching)
    void SetTokenHighlighter(TokenCallback callback);

    // Set reference-based highlighter (semantic/contextual)
    void SetReferenceHighlighter(ReferenceCallback callback, const std::string& file_path);

    // Get tokens for text (calls whichever highlighter is set)
    std::vector<Token> GetTokens(const std::string& text);

    // Get decorations (only available with reference highlighter)
    std::vector<ReferenceDecoration> GetDecorations();

    // Check if any highlighter is set
    bool HasHighlighter() const;

    // Invalidate cache
    void InvalidateCache();

private:
    TokenCallback token_callback_;
    ReferenceCallback reference_callback_;
    std::string file_path_;

    // Cached results
    std::vector<Token> cached_tokens_;
    std::vector<ReferenceDecoration> cached_decorations_;
    bool cache_valid_;
};
