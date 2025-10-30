#include "UndoStack.h"
#include "Logger.h"

UndoStack::UndoStack(size_t max_size)
    : max_size_(max_size)
{
}

UndoStack::~UndoStack() {
}

void UndoStack::PushUndo(const std::string& text, const TextBuffer::Position& cursor_pos) {
    // Clear redo stack when making a new change
    redo_stack_.clear();

    // Add new snapshot
    Snapshot snapshot;
    snapshot.text = text;
    snapshot.cursor_pos = cursor_pos;
    undo_stack_.push_back(snapshot);

    // Enforce max size
    if (undo_stack_.size() > max_size_) {
        undo_stack_.erase(undo_stack_.begin());
    }
}

bool UndoStack::Undo(const std::string& current_text, const TextBuffer::Position& current_cursor_pos,
                     std::string& out_text, TextBuffer::Position& out_cursor_pos) {
    if (undo_stack_.empty()) {
        return false;
    }

    // Save current state to redo stack
    Snapshot current;
    current.text = current_text;
    current.cursor_pos = current_cursor_pos;
    redo_stack_.push_back(current);

    // Pop previous state from undo stack
    Snapshot previous = undo_stack_.back();
    undo_stack_.pop_back();

    out_text = previous.text;
    out_cursor_pos = previous.cursor_pos;

    return true;
}

bool UndoStack::Redo(const std::string& current_text, const TextBuffer::Position& current_cursor_pos,
                     std::string& out_text, TextBuffer::Position& out_cursor_pos) {
    if (redo_stack_.empty()) {
        return false;
    }

    // Save current state to undo stack
    Snapshot current;
    current.text = current_text;
    current.cursor_pos = current_cursor_pos;
    undo_stack_.push_back(current);

    // Enforce max size on undo stack
    if (undo_stack_.size() > max_size_) {
        undo_stack_.erase(undo_stack_.begin());
    }

    // Pop next state from redo stack
    Snapshot next = redo_stack_.back();
    redo_stack_.pop_back();

    out_text = next.text;
    out_cursor_pos = next.cursor_pos;

    return true;
}

bool UndoStack::CanUndo() const {
    return !undo_stack_.empty();
}

bool UndoStack::CanRedo() const {
    return !redo_stack_.empty();
}

void UndoStack::Clear() {
    undo_stack_.clear();
    redo_stack_.clear();
}
