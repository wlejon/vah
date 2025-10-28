#pragma once

#include <string>
#include <vector>

/**
 * TextBuffer - Line-based text storage with undo/redo support.
 *
 * Stores text as a vector of strings (one per line).
 * Provides character and line-level operations.
 */
class TextBuffer {
public:
    struct Position {
        int line;
        int column;

        Position() : line(0), column(0) {}
        Position(int l, int c) : line(l), column(c) {}

        bool operator==(const Position& other) const {
            return line == other.line && column == other.column;
        }

        bool operator!=(const Position& other) const {
            return !(*this == other);
        }

        bool operator<(const Position& other) const {
            if (line != other.line) return line < other.line;
            return column < other.column;
        }

        bool operator<=(const Position& other) const {
            return *this < other || *this == other;
        }
    };

    TextBuffer();
    ~TextBuffer();

    // Text operations
    void SetText(const std::string& text);
    std::string GetText() const;
    std::string GetLine(int line) const;
    int GetLineCount() const;
    char GetCharAt(const Position& pos) const;

    // Range operations
    std::string GetTextRange(const Position& start, const Position& end) const;

    // Insert/delete operations
    void InsertChar(const Position& pos, char c);
    void InsertText(const Position& pos, const std::string& text);
    void DeleteChar(const Position& pos);
    void DeleteRange(const Position& start, const Position& end);

    // Line operations
    void InsertLine(int line);
    void DeleteLine(int line);
    void SplitLine(const Position& pos);
    void JoinLines(int line);

    // Position validation
    // ClampPosition: Clamps position to valid buffer bounds (line and column ranges)
    // Use this when you need to ensure a position is safe to use for operations
    Position ClampPosition(const Position& pos) const;

    // IsValidPosition: Checks if position has valid lower bounds only (line >= 0, column >= 0)
    // Does NOT check upper bounds - use ClampPosition for safe position handling
    bool IsValidPosition(const Position& pos) const;

private:
    std::vector<std::string> lines_;
};
