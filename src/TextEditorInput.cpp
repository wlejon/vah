#include "TextEditorInput.h"
#include "Logger.h"
#include <SDL2/SDL.h>
#include <algorithm>

TextEditorInput::TextEditorInput(
    TextBuffer& buffer,
    TextLayout& layout,
    SelectionManager& selection,
    TextEditorConfig& config
)
    : buffer_(buffer)
    , layout_(layout)
    , selection_(selection)
    , config_(config)
    , cursor_pos_(0, 0)
    , cursor_visible_(true)
    , mouse_dragging_(false)
    , last_mouse_pos_(0.0f, 0.0f)
{
}

TextEditorInput::~TextEditorInput() {
}

TextBuffer::Position TextEditorInput::ScreenToText(float screen_x, float screen_y, const Rml::Vector2f& element_offset) {
    // Convert to element-relative coordinates
    float local_x = screen_x - element_offset.x;
    float local_y = screen_y - element_offset.y;

    // Convert to text position
    TextBuffer::Position pos = layout_.ScreenToTextPosition(local_x, local_y);

    // Clamp to buffer bounds
    return buffer_.ClampPosition(pos);
}

void TextEditorInput::OnMouseDown(float mouse_x, float mouse_y, const Rml::Vector2f& element_offset) {
    TextBuffer::Position pos = ScreenToText(mouse_x, mouse_y, element_offset);

    selection_.SetAnchor(pos);
    selection_.SetCursor(pos);

    // Update cursor position
    cursor_pos_ = pos;
    cursor_visible_ = true;  // Reset blink when clicking

    mouse_dragging_ = true;
    last_mouse_pos_ = Rml::Vector2f(mouse_x, mouse_y);

    if (dirty_callback_) {
        dirty_callback_();
    }
}

void TextEditorInput::OnMouseMove(float mouse_x, float mouse_y, const Rml::Vector2f& element_offset) {
    if (!mouse_dragging_) {
        return;
    }

    TextBuffer::Position pos = ScreenToText(mouse_x, mouse_y, element_offset);
    selection_.SetCursor(pos);

    last_mouse_pos_ = Rml::Vector2f(mouse_x, mouse_y);

    if (dirty_callback_) {
        dirty_callback_();
    }
}

void TextEditorInput::OnMouseUp() {
    mouse_dragging_ = false;
}

void TextEditorInput::OnKeyDown(Rml::Input::KeyIdentifier key, int modifiers, bool editable) {
    // Handle Ctrl+C for copy (works in both editable and read-only mode)
    if (key == Rml::Input::KI_C && (modifiers & Rml::Input::KM_CTRL)) {
        std::string selected = selection_.ExtractText(buffer_);
        if (!selected.empty()) {
            SDL_SetClipboardText(selected.c_str());
        }
        return;
    }

    // Only handle editing keys if editable
    if (!editable) {
        return;
    }

    // Handle Ctrl+S for save
    if (key == Rml::Input::KI_S && (modifiers & Rml::Input::KM_CTRL)) {
        if (save_callback_) {
            save_callback_();
        }
        return;
    }

    // Handle Ctrl+V for paste
    if (key == Rml::Input::KI_V && (modifiers & Rml::Input::KM_CTRL)) {
        if (SDL_HasClipboardText()) {
            char* clipboard_text = SDL_GetClipboardText();
            if (clipboard_text) {
                // Delete selection if any
                if (selection_.HasSelection()) {
                    TextBuffer::Position start, end;
                    selection_.GetSelectionRange(start, end);
                    buffer_.DeleteRange(start, end);
                    cursor_pos_ = start;
                    selection_.ClearSelection();
                }

                // Insert clipboard text
                buffer_.InsertText(cursor_pos_, clipboard_text);

                // Move cursor to end of inserted text
                for (const char* p = clipboard_text; *p; ++p) {
                    if (*p == '\n') {
                        cursor_pos_.line++;
                        cursor_pos_.column = 0;
                    } else {
                        cursor_pos_.column++;
                    }
                }

                SDL_free(clipboard_text);

                if (content_change_callback_) {
                    content_change_callback_();
                }
                if (dirty_callback_) {
                    dirty_callback_();
                }
            }
        }
        return;
    }

    // Handle backspace
    if (key == Rml::Input::KI_BACK) {
        bool made_change = false;
        if (selection_.HasSelection()) {
            // Delete selection
            TextBuffer::Position start, end;
            selection_.GetSelectionRange(start, end);
            buffer_.DeleteRange(start, end);
            cursor_pos_ = start;
            selection_.ClearSelection();
            made_change = true;
        } else if (cursor_pos_.column > 0) {
            // Delete character before cursor
            cursor_pos_.column--;
            buffer_.DeleteChar(cursor_pos_);
            made_change = true;
        } else if (cursor_pos_.line > 0) {
            // Join with previous line
            int prev_line_len = static_cast<int>(buffer_.GetLine(cursor_pos_.line - 1).length());
            buffer_.JoinLines(cursor_pos_.line - 1);
            cursor_pos_.line--;
            cursor_pos_.column = prev_line_len;
            made_change = true;
        }
        if (made_change) {
            if (content_change_callback_) {
                content_change_callback_();
            }
        }
        if (dirty_callback_) {
            dirty_callback_();
        }
        return;
    }

    // Handle delete
    if (key == Rml::Input::KI_DELETE) {
        if (selection_.HasSelection()) {
            // Delete selection
            TextBuffer::Position start, end;
            selection_.GetSelectionRange(start, end);
            buffer_.DeleteRange(start, end);
            cursor_pos_ = start;
            selection_.ClearSelection();
        } else {
            // Delete character at cursor
            buffer_.DeleteChar(cursor_pos_);
        }
        if (content_change_callback_) {
            content_change_callback_();
        }
        if (dirty_callback_) {
            dirty_callback_();
        }
        return;
    }

    // Handle enter/return
    if (key == Rml::Input::KI_RETURN || key == Rml::Input::KI_NUMPADENTER) {
        // Delete selection if any
        if (selection_.HasSelection()) {
            TextBuffer::Position start, end;
            selection_.GetSelectionRange(start, end);
            buffer_.DeleteRange(start, end);
            cursor_pos_ = start;
            selection_.ClearSelection();
        }

        // Insert newline
        buffer_.InsertChar(cursor_pos_, '\n');
        cursor_pos_.line++;
        cursor_pos_.column = 0;

        if (content_change_callback_) {
            content_change_callback_();
        }
        if (dirty_callback_) {
            dirty_callback_();
        }
        return;
    }

    // Handle arrow keys
    if (key == Rml::Input::KI_LEFT) {
        if (cursor_pos_.column > 0) {
            cursor_pos_.column--;
        } else if (cursor_pos_.line > 0) {
            cursor_pos_.line--;
            cursor_pos_.column = static_cast<int>(buffer_.GetLine(cursor_pos_.line).length());
        }
        selection_.ClearSelection();
        if (dirty_callback_) {
            dirty_callback_();
        }
        return;
    }

    if (key == Rml::Input::KI_RIGHT) {
        int line_len = static_cast<int>(buffer_.GetLine(cursor_pos_.line).length());
        if (cursor_pos_.column < line_len) {
            cursor_pos_.column++;
        } else if (cursor_pos_.line < buffer_.GetLineCount() - 1) {
            cursor_pos_.line++;
            cursor_pos_.column = 0;
        }
        selection_.ClearSelection();
        if (dirty_callback_) {
            dirty_callback_();
        }
        return;
    }

    if (key == Rml::Input::KI_UP) {
        if (cursor_pos_.line > 0) {
            cursor_pos_.line--;
            int line_len = static_cast<int>(buffer_.GetLine(cursor_pos_.line).length());
            cursor_pos_.column = std::min(cursor_pos_.column, line_len);
        }
        selection_.ClearSelection();
        if (dirty_callback_) {
            dirty_callback_();
        }
        return;
    }

    if (key == Rml::Input::KI_DOWN) {
        if (cursor_pos_.line < buffer_.GetLineCount() - 1) {
            cursor_pos_.line++;
            int line_len = static_cast<int>(buffer_.GetLine(cursor_pos_.line).length());
            cursor_pos_.column = std::min(cursor_pos_.column, line_len);
        }
        selection_.ClearSelection();
        if (dirty_callback_) {
            dirty_callback_();
        }
        return;
    }

    // Handle Home
    if (key == Rml::Input::KI_HOME) {
        cursor_pos_.column = 0;
        selection_.ClearSelection();
        if (dirty_callback_) {
            dirty_callback_();
        }
        return;
    }

    // Handle End
    if (key == Rml::Input::KI_END) {
        cursor_pos_.column = static_cast<int>(buffer_.GetLine(cursor_pos_.line).length());
        selection_.ClearSelection();
        if (dirty_callback_) {
            dirty_callback_();
        }
        return;
    }

    // Handle Tab
    if (key == Rml::Input::KI_TAB) {
        // Delete selection if any
        if (selection_.HasSelection()) {
            TextBuffer::Position start, end;
            selection_.GetSelectionRange(start, end);
            buffer_.DeleteRange(start, end);
            cursor_pos_ = start;
            selection_.ClearSelection();
        }

        // Insert tab or spaces based on config
        if (config_.use_spaces_for_tab) {
            // Insert spaces
            for (int i = 0; i < config_.tab_width; ++i) {
                buffer_.InsertChar(cursor_pos_, ' ');
                cursor_pos_.column++;
            }
        } else {
            // Insert tab character
            buffer_.InsertChar(cursor_pos_, '\t');
            cursor_pos_.column++;
        }

        if (content_change_callback_) {
            content_change_callback_();
        }
        if (dirty_callback_) {
            dirty_callback_();
        }
        return;
    }
}

void TextEditorInput::OnTextInput(const std::string& text, bool editable) {
    if (!editable || text.empty()) {
        return;
    }

    // Delete selection if any
    if (selection_.HasSelection()) {
        TextBuffer::Position start, end;
        selection_.GetSelectionRange(start, end);
        buffer_.DeleteRange(start, end);
        cursor_pos_ = start;
        selection_.ClearSelection();
    }

    // Insert text at cursor
    for (char c : text) {
        if (c >= 32 && c != 127) {  // Printable characters only (not tab, not DEL)
            buffer_.InsertChar(cursor_pos_, c);
            cursor_pos_.column++;
        }
    }

    // Notify of content change
    if (content_change_callback_) {
        content_change_callback_();
    }
    if (dirty_callback_) {
        dirty_callback_();
    }
}
