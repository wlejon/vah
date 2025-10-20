#pragma once

#include <RmlUi/Core/Types.h>

/**
 * TextEditorConfig - Configuration for text editor behavior and appearance.
 *
 * All settings are configurable from Lua via the global ui.texteditor_config table.
 * Default values are set in the constructor.
 */
class TextEditorConfig {
public:
    TextEditorConfig();
    ~TextEditorConfig();

    // Cursor settings
    double cursor_blink_period;  // Seconds for full blink cycle (visible + hidden)
    float cursor_width;          // Cursor width in pixels
    Rml::Colourb cursor_color;   // Cursor color

    // Selection settings
    Rml::Colourb selection_color;  // Selection highlight color

    // Text settings
    Rml::Colourb default_text_color;  // Default text color (when no syntax highlighting)

    // Tab settings
    bool use_spaces_for_tab;  // true = insert spaces, false = insert tab character
    int tab_width;            // Number of spaces per tab (when use_spaces_for_tab is true)
};
