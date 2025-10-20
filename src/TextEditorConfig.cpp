#include "TextEditorConfig.h"

TextEditorConfig::TextEditorConfig()
    : cursor_blink_period(0.6)  // Faster blink: 0.3s visible, 0.3s hidden
    , cursor_width(2.0f)
    , cursor_color(255, 255, 255, 140)
    , selection_color(100, 150, 255, 100)
    , default_text_color(200, 200, 200, 255)
    , use_spaces_for_tab(true)  // Default to spaces
    , tab_width(4)               // 4 spaces per tab
{
}

TextEditorConfig::~TextEditorConfig() {
}
