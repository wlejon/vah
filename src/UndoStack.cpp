#include "UndoStack.h"
#include "Logger.h"

UndoStack::UndoStack(size_t max_size)
    : max_size_(max_size)
    , current_index_(0)
{
}

UndoStack::~UndoStack() {
}

void UndoStack::PushUndo(const std::string& text, const TextBuffer::Position& cursor_pos) {
    // If we're in the middle of the stack (after undo), discard redo history
    if (current_index_ < undo_stack_.size()) {
        undo_stack_.erase(undo_stack_.begin() + current_index_, undo_stack_.end());
    }

    // Add new snapshot
    Snapshot snapshot;
    snapshot.text = text;
    snapshot.cursor_pos = cursor_pos;
    undo_stack_.push_back(snapshot);

    // Enforce max size
    if (undo_stack_.size() > max_size_) {
        undo_stack_.erase(undo_stack_.begin());
    } else {
        current_index_++;
    }
}

bool UndoStack::Undo(std::string& out_text, TextBuffer::Position& out_cursor_pos) {
    // Need at least 2 states: current and previous
    if (current_index_ == 0 || undo_stack_.empty()) {
        return false;
    }

    // Move back one step
    current_index_--;

    // Return the state we're undoing to
    const Snapshot& snapshot = undo_stack_[current_index_];
    out_text = snapshot.text;
    out_cursor_pos = snapshot.cursor_pos;

    return true;
}

bool UndoStack::Redo(std::string& out_text, TextBuffer::Position& out_cursor_pos) {
    // Check if we can redo
    if (current_index_ >= undo_stack_.size() - 1) {
        return false;
    }

    // Move forward one step
    current_index_++;

    // Return the state we're redoing to
    const Snapshot& snapshot = undo_stack_[current_index_];
    out_text = snapshot.text;
    out_cursor_pos = snapshot.cursor_pos;

    return true;
}

bool UndoStack::CanUndo() const {
    return current_index_ > 0 && !undo_stack_.empty();
}

bool UndoStack::CanRedo() const {
    return current_index_ < undo_stack_.size() - 1;
}

void UndoStack::Clear() {
    undo_stack_.clear();
    current_index_ = 0;
}
