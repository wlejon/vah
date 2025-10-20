#include "TextBuffer.h"
#include <algorithm>
#include <sstream>

TextBuffer::TextBuffer() {
    lines_.push_back(""); // Always have at least one line
}

TextBuffer::~TextBuffer() = default;

void TextBuffer::SetText(const std::string& text) {
    lines_.clear();

    if (text.empty()) {
        lines_.push_back("");
        return;
    }

    std::istringstream stream(text);
    std::string line;
    while (std::getline(stream, line)) {
        // Strip trailing \r if present (Windows line endings)
        if (!line.empty() && line.back() == '\r') {
            line.pop_back();
        }
        lines_.push_back(line);
    }

    // If text ends with newline, add empty line
    if (!text.empty() && text.back() == '\n') {
        lines_.push_back("");
    }

    // Ensure at least one line
    if (lines_.empty()) {
        lines_.push_back("");
    }
}

std::string TextBuffer::GetText() const {
    if (lines_.empty()) {
        return "";
    }

    std::string result;
    for (size_t i = 0; i < lines_.size(); ++i) {
        result += lines_[i];
        if (i < lines_.size() - 1) {
            result += '\n';
        }
    }
    return result;
}

std::string TextBuffer::GetLine(int line) const {
    if (line < 0 || line >= static_cast<int>(lines_.size())) {
        return "";
    }
    return lines_[line];
}

int TextBuffer::GetLineCount() const {
    return static_cast<int>(lines_.size());
}

char TextBuffer::GetCharAt(const Position& pos) const {
    if (!IsValidPosition(pos)) {
        return '\0';
    }

    const std::string& line = lines_[pos.line];
    if (pos.column >= static_cast<int>(line.size())) {
        return '\0';
    }

    return line[pos.column];
}

std::string TextBuffer::GetTextRange(const Position& start, const Position& end) const {
    Position s = ClampPosition(start);
    Position e = ClampPosition(end);

    // Ensure start <= end
    if (e < s) {
        std::swap(s, e);
    }

    if (s.line == e.line) {
        // Same line
        const std::string& line = lines_[s.line];
        int length = e.column - s.column;
        if (length <= 0) return "";
        return line.substr(s.column, length);
    }

    // Multiple lines
    std::string result;

    // First line
    const std::string& first_line = lines_[s.line];
    if (s.column < static_cast<int>(first_line.size())) {
        result += first_line.substr(s.column);
    }
    result += '\n';

    // Middle lines
    for (int i = s.line + 1; i < e.line; ++i) {
        result += lines_[i];
        result += '\n';
    }

    // Last line
    const std::string& last_line = lines_[e.line];
    int end_col = std::min(e.column, static_cast<int>(last_line.size()));
    if (end_col > 0) {
        result += last_line.substr(0, end_col);
    }

    return result;
}

void TextBuffer::InsertChar(const Position& pos, char c) {
    Position clamped = ClampPosition(pos);

    if (c == '\n') {
        SplitLine(clamped);
        return;
    }

    std::string& line = lines_[clamped.line];
    line.insert(clamped.column, 1, c);
}

void TextBuffer::InsertText(const Position& pos, const std::string& text) {
    if (text.empty()) return;

    Position current = ClampPosition(pos);

    for (char c : text) {
        InsertChar(current, c);
        if (c == '\n') {
            current.line++;
            current.column = 0;
        } else {
            current.column++;
        }
    }
}

void TextBuffer::DeleteChar(const Position& pos) {
    if (!IsValidPosition(pos)) return;

    std::string& line = lines_[pos.line];

    if (pos.column >= static_cast<int>(line.size())) {
        // Delete at end of line - join with next line
        if (pos.line < GetLineCount() - 1) {
            JoinLines(pos.line);
        }
        return;
    }

    line.erase(pos.column, 1);
}

void TextBuffer::DeleteRange(const Position& start, const Position& end) {
    Position s = ClampPosition(start);
    Position e = ClampPosition(end);

    // Ensure start <= end
    if (e < s) {
        std::swap(s, e);
    }

    if (s == e) return;

    if (s.line == e.line) {
        // Same line deletion
        std::string& line = lines_[s.line];
        int length = e.column - s.column;
        if (length > 0 && s.column < static_cast<int>(line.size())) {
            line.erase(s.column, length);
        }
        return;
    }

    // Multi-line deletion
    std::string& first_line = lines_[s.line];
    const std::string& last_line = lines_[e.line];

    // Keep beginning of first line and end of last line
    std::string new_line = first_line.substr(0, s.column);
    if (e.column < static_cast<int>(last_line.size())) {
        new_line += last_line.substr(e.column);
    }

    first_line = new_line;

    // Delete intermediate lines
    lines_.erase(lines_.begin() + s.line + 1, lines_.begin() + e.line + 1);
}

void TextBuffer::InsertLine(int line) {
    if (line < 0 || line > static_cast<int>(lines_.size())) {
        return;
    }
    lines_.insert(lines_.begin() + line, "");
}

void TextBuffer::DeleteLine(int line) {
    if (line < 0 || line >= static_cast<int>(lines_.size())) {
        return;
    }

    lines_.erase(lines_.begin() + line);

    // Ensure at least one line
    if (lines_.empty()) {
        lines_.push_back("");
    }
}

void TextBuffer::SplitLine(const Position& pos) {
    Position clamped = ClampPosition(pos);

    std::string& line = lines_[clamped.line];
    std::string new_line;

    if (clamped.column < static_cast<int>(line.size())) {
        new_line = line.substr(clamped.column);
        line = line.substr(0, clamped.column);
    }

    lines_.insert(lines_.begin() + clamped.line + 1, new_line);
}

void TextBuffer::JoinLines(int line) {
    if (line < 0 || line >= static_cast<int>(lines_.size()) - 1) {
        return;
    }

    lines_[line] += lines_[line + 1];
    lines_.erase(lines_.begin() + line + 1);
}

TextBuffer::Position TextBuffer::ClampPosition(const Position& pos) const {
    Position result = pos;

    // Clamp line
    result.line = std::max(0, std::min(pos.line, GetLineCount() - 1));

    // Clamp column
    const std::string& line = lines_[result.line];
    result.column = std::max(0, std::min(pos.column, static_cast<int>(line.size())));

    return result;
}

bool TextBuffer::IsValidPosition(const Position& pos) const {
    if (pos.line < 0 || pos.line >= GetLineCount()) {
        return false;
    }

    if (pos.column < 0) {
        return false;
    }

    return true;
}
