#include "SelectionManager.h"

SelectionManager::SelectionManager()
    : anchor_(0, 0)
    , cursor_(0, 0)
{
}

SelectionManager::~SelectionManager() = default;

void SelectionManager::SetAnchor(const TextBuffer::Position& pos) {
    anchor_ = pos;
}

void SelectionManager::SetCursor(const TextBuffer::Position& pos) {
    cursor_ = pos;
}

void SelectionManager::ClearSelection() {
    anchor_ = cursor_;
}

bool SelectionManager::HasSelection() const {
    return anchor_ != cursor_;
}

void SelectionManager::GetSelectionRange(TextBuffer::Position& start, TextBuffer::Position& end) const {
    if (cursor_ < anchor_) {
        start = cursor_;
        end = anchor_;
    } else {
        start = anchor_;
        end = cursor_;
    }
}

std::string SelectionManager::ExtractText(const TextBuffer& buffer) const {
    if (!HasSelection()) {
        return "";
    }

    TextBuffer::Position start, end;
    GetSelectionRange(start, end);

    return buffer.GetTextRange(start, end);
}
