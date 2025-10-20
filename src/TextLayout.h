#pragma once

#include "TextBuffer.h"
#include <RmlUi/Core.h>
#include <RmlUi/Core/FontEngineInterface.h>

/**
 * TextLayout - Handles font metrics and position conversion for monospace text.
 *
 * Converts between screen coordinates and text positions.
 * Generates glyph geometry for rendering.
 */
class TextLayout {
public:
    TextLayout();
    ~TextLayout();

    // Initialize with font
    void SetFont(const std::string& font_family, int font_size);

    // Get font metrics
    float GetCharWidth() const { return char_width_; }
    float GetLineHeight() const { return line_height_; }

    // Position conversion
    TextBuffer::Position ScreenToTextPosition(float screen_x, float screen_y) const;
    Rml::Vector2f TextToScreenPosition(const TextBuffer::Position& pos) const;

    // Get screen rect for a text range
    Rml::Vector2f GetRangeStart(const TextBuffer::Position& pos) const;
    Rml::Vector2f GetRangeEnd(const TextBuffer::Position& pos) const;

    // Calculate dimensions
    float CalculateLineWidth(const std::string& line) const;
    float CalculateTextHeight(int line_count) const;

private:
    void CalculateFontMetrics();

    std::string font_family_;
    int font_size_;
    float char_width_;
    float line_height_;
};
