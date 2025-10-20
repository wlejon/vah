#pragma once

#include "TextBuffer.h"

/**
 * SelectionManager - Manages text selection state.
 *
 * Tracks anchor (start) and cursor (end) positions.
 * Provides normalized selection range.
 */
class SelectionManager {
public:
    SelectionManager();
    ~SelectionManager();

    // Selection state
    void SetAnchor(const TextBuffer::Position& pos);
    void SetCursor(const TextBuffer::Position& pos);
    void ClearSelection();

    // Get current positions
    TextBuffer::Position GetAnchor() const { return anchor_; }
    TextBuffer::Position GetCursor() const { return cursor_; }

    // Check if there's a selection
    bool HasSelection() const;

    // Get normalized selection range (start <= end)
    void GetSelectionRange(TextBuffer::Position& start, TextBuffer::Position& end) const;

    // Extract text from buffer
    std::string ExtractText(const TextBuffer& buffer) const;

private:
    TextBuffer::Position anchor_;
    TextBuffer::Position cursor_;
};
