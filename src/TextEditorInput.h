#pragma once

#include <RmlUi/Core/Input.h>
#include <RmlUi/Core/Types.h>
#include <functional>
#include "TextBuffer.h"
#include "TextLayout.h"
#include "SelectionManager.h"
#include "TextEditorConfig.h"

/**
 * TextEditorInput - Handles all input processing for text editor.
 *
 * Responsible for:
 * - Mouse input (click, drag, selection)
 * - Keyboard input (navigation, shortcuts)
 * - Text input (typing, paste)
 */
class TextEditorInput {
public:
    TextEditorInput(
        TextBuffer& buffer,
        TextLayout& layout,
        SelectionManager& selection,
        TextEditorConfig& config
    );
    ~TextEditorInput();

    // Callbacks for state changes
    using DirtyCallback = std::function<void()>;
    using ContentChangeCallback = std::function<void()>;
    using SaveCallback = std::function<void()>;
    using BeforeContentChangeCallback = std::function<void()>;

    void SetDirtyCallback(DirtyCallback callback) { dirty_callback_ = callback; }
    void SetContentChangeCallback(ContentChangeCallback callback) { content_change_callback_ = callback; }
    void SetSaveCallback(SaveCallback callback) { save_callback_ = callback; }
    void SetBeforeContentChangeCallback(BeforeContentChangeCallback callback) { before_content_change_callback_ = callback; }

    // Mouse input
    void OnMouseDown(float mouse_x, float mouse_y, const Rml::Vector2f& element_offset);
    void OnMouseMove(float mouse_x, float mouse_y, const Rml::Vector2f& element_offset);
    void OnMouseUp();

    // Keyboard input
    void OnKeyDown(Rml::Input::KeyIdentifier key, int modifiers, bool editable);

    // Text input
    void OnTextInput(const std::string& text, bool editable);

    // Cursor state
    TextBuffer::Position GetCursorPosition() const { return cursor_pos_; }
    void SetCursorPosition(const TextBuffer::Position& pos) { cursor_pos_ = pos; }
    bool IsCursorVisible() const { return cursor_visible_; }
    void SetCursorVisible(bool visible) { cursor_visible_ = visible; }

private:
    // Convert mouse position to text position
    TextBuffer::Position ScreenToText(float screen_x, float screen_y, const Rml::Vector2f& element_offset);

    TextBuffer& buffer_;
    TextLayout& layout_;
    SelectionManager& selection_;
    TextEditorConfig& config_;

    // Cursor state
    TextBuffer::Position cursor_pos_;
    bool cursor_visible_;

    // Mouse state
    bool mouse_dragging_;
    Rml::Vector2f last_mouse_pos_;

    // Callbacks
    DirtyCallback dirty_callback_;
    ContentChangeCallback content_change_callback_;
    SaveCallback save_callback_;
    BeforeContentChangeCallback before_content_change_callback_;
};
