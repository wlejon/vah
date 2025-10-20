#include "SyntaxHighlighter.h"
#include "Logger.h"

SyntaxHighlighter::SyntaxHighlighter()
    : cache_valid_(false)
{
}

SyntaxHighlighter::~SyntaxHighlighter() = default;

void SyntaxHighlighter::SetTokenHighlighter(TokenCallback callback) {
    token_callback_ = callback;
    reference_callback_ = nullptr;  // Clear reference callback
    InvalidateCache();
}

void SyntaxHighlighter::SetReferenceHighlighter(ReferenceCallback callback, const std::string& file_path) {
    reference_callback_ = callback;
    token_callback_ = nullptr;  // Clear token callback
    file_path_ = file_path;
    InvalidateCache();
}

std::vector<SyntaxHighlighter::Token> SyntaxHighlighter::GetTokens(const std::string& text) {
    if (cache_valid_) {
        return cached_tokens_;
    }

    cached_tokens_.clear();
    cached_decorations_.clear();

    if (reference_callback_) {
        // Call reference-based highlighter
        reference_callback_(text, file_path_, cached_tokens_, cached_decorations_);
    } else if (token_callback_) {
        // Call token-based highlighter
        cached_tokens_ = token_callback_(text);
    }

    cache_valid_ = true;
    return cached_tokens_;
}

std::vector<SyntaxHighlighter::ReferenceDecoration> SyntaxHighlighter::GetDecorations() {
    return cached_decorations_;
}

bool SyntaxHighlighter::HasHighlighter() const {
    return token_callback_ || reference_callback_;
}

void SyntaxHighlighter::InvalidateCache() {
    cached_tokens_.clear();
    cached_decorations_.clear();
    cache_valid_ = false;
}
