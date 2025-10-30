#pragma once

#include <string>
#include <vector>
#include "TextBuffer.h"

/**
 * UndoStack - Manages undo/redo history for text editor
 *
 * Stores snapshots of text buffer state for simple undo/redo.
 * Limits stack size to prevent unbounded memory growth.
 */
class UndoStack {
public:
    UndoStack(size_t max_size = 100);
    ~UndoStack();

    struct Snapshot {
        std::string text;
        TextBuffer::Position cursor_pos;
    };

    // Push current state onto undo stack
    void PushUndo(const std::string& text, const TextBuffer::Position& cursor_pos);

    // Undo to previous state
    // Takes current state, saves it to redo stack, and returns previous state
    // Returns true if undo was performed, false if stack is empty
    bool Undo(const std::string& current_text, const TextBuffer::Position& current_cursor_pos,
              std::string& out_text, TextBuffer::Position& out_cursor_pos);

    // Redo to next state
    // Takes current state, saves it to undo stack, and returns next state
    // Returns true if redo was performed, false if no redo available
    bool Redo(const std::string& current_text, const TextBuffer::Position& current_cursor_pos,
              std::string& out_text, TextBuffer::Position& out_cursor_pos);

    // Check if undo/redo is available
    bool CanUndo() const;
    bool CanRedo() const;

    // Clear all history
    void Clear();

private:
    std::vector<Snapshot> undo_stack_;
    std::vector<Snapshot> redo_stack_;
    size_t max_size_;
};
