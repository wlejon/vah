#include "TextLayout.h"
#include "Logger.h"
#include <cmath>
#include <algorithm>
#include <cctype>

TextLayout::TextLayout()
    : font_family_("jetbrains mono")
    , font_style_(Rml::Style::FontStyle::Normal)
    , font_weight_(Rml::Style::FontWeight::Normal)
    , font_size_(14)
    , char_width_(8.0f)
    , line_height_(18.0f)
{
}

TextLayout::~TextLayout() = default;

void TextLayout::SetFont(const std::string& font_family, int font_size) {
    // Convert font family to lowercase as required by RmlUi
    font_family_ = font_family;
    std::transform(font_family_.begin(), font_family_.end(), font_family_.begin(),
                   [](unsigned char c) { return std::tolower(c); });
    font_size_ = font_size;
    CalculateFontMetrics();
}

void TextLayout::SetFontInfo(const std::string& font_family, Rml::Style::FontStyle font_style, Rml::Style::FontWeight font_weight, int font_size) {
    // Store font info without recalculating metrics
    // (metrics should be set separately via SetFontMetrics)
    font_family_ = font_family;
    std::transform(font_family_.begin(), font_family_.end(), font_family_.begin(),
                   [](unsigned char c) { return std::tolower(c); });
    font_style_ = font_style;
    font_weight_ = font_weight;
    font_size_ = font_size;
}

void TextLayout::SetFontMetrics(float line_height, float char_width) {
    // Directly set the font metrics
    line_height_ = line_height;
    char_width_ = char_width;
}

void TextLayout::CalculateFontMetrics() {
    // Get font from RmlUi
    auto font_engine = Rml::GetFontEngineInterface();
    if (!font_engine) {
        LOG_ERROR("TextLayout: Font engine not available");
        return;
    }

    // Get font handle
    Rml::FontFaceHandle font_handle = font_engine->GetFontFaceHandle(font_family_, Rml::Style::FontStyle::Normal, Rml::Style::FontWeight::Normal, font_size_);
    if (!font_handle) {
        LOG_ERROR("TextLayout: Failed to get font handle for '{}'", font_family_);
        return;
    }

    // Get metrics and validate
    const Rml::FontMetrics& metrics = font_engine->GetFontMetrics(font_handle);
    if (metrics.ascent <= 0.0f || metrics.descent <= 0.0f || metrics.line_spacing <= 0) {
        LOG_ERROR("TextLayout: Invalid font metrics for '{}' (ascent={}, descent={}, line_spacing={})",
                 font_family_, metrics.ascent, metrics.descent, metrics.line_spacing);
        return;
    }

    line_height_ = static_cast<float>(metrics.line_spacing);

    // Measure character width
    Rml::String test_string = "x";
    Rml::String language = "en";
    Rml::TextShapingContext context{language};
    int advance = font_engine->GetStringWidth(font_handle, test_string, context);
    if (advance <= 0) {
        LOG_ERROR("TextLayout: Invalid character width measurement for '{}': {}", font_family_, advance);
        return;
    }

    char_width_ = static_cast<float>(advance);
}

TextBuffer::Position TextLayout::ScreenToTextPosition(float screen_x, float screen_y) const {
    TextBuffer::Position pos;

    // Convert screen Y to line number
    pos.line = static_cast<int>(std::floor(screen_y / line_height_));

    // Convert screen X to column
    pos.column = static_cast<int>(std::floor(screen_x / char_width_));

    // Clamp to non-negative
    pos.line = std::max(0, pos.line);
    pos.column = std::max(0, pos.column);

    return pos;
}

Rml::Vector2f TextLayout::TextToScreenPosition(const TextBuffer::Position& pos) const {
    Rml::Vector2f screen_pos;
    screen_pos.x = static_cast<float>(pos.column) * char_width_;
    screen_pos.y = static_cast<float>(pos.line) * line_height_;
    return screen_pos;
}

Rml::Vector2f TextLayout::GetRangeStart(const TextBuffer::Position& pos) const {
    return TextToScreenPosition(pos);
}

Rml::Vector2f TextLayout::GetRangeEnd(const TextBuffer::Position& pos) const {
    return TextToScreenPosition(pos);
}

float TextLayout::CalculateLineWidth(const std::string& line) const {
    return static_cast<float>(line.size()) * char_width_;
}

float TextLayout::CalculateTextHeight(int line_count) const {
    return static_cast<float>(line_count) * line_height_;
}
