#pragma once

#include <RmlUi/Core/Geometry.h>
#include <RmlUi/Core/RenderManager.h>
#include "TextBuffer.h"
#include "TextLayout.h"
#include "SelectionManager.h"
#include "TextEditorConfig.h"
#include "DataStore.h"  // For DynamicTable type
#include <vector>
#include <memory>

/**
 * TextEditorRenderer - Handles all geometry generation and rendering for text editor.
 *
 * Responsible for:
 * - Text rendering with syntax highlighting
 * - Selection highlight rendering
 * - Cursor rendering
 */
class TextEditorRenderer {
public:
    TextEditorRenderer(
        TextBuffer& buffer,
        TextLayout& layout,
        SelectionManager& selection,
        TextEditorConfig& config
    );
    ~TextEditorRenderer();

    // Rendering
    struct TextGeometry {
        Rml::Geometry geometry;
        Rml::Texture texture;
    };

    void GenerateGeometry(Rml::RenderManager* render_manager, bool editable, bool cursor_visible);
    void RenderAll(const Rml::Vector2f& absolute_offset, bool editable, bool cursor_visible);

    // Syntax highlighting
    void SetTokens(const DynamicTable& tokens);

    // Dirty flags
    void SetSelectionDirty(bool dirty) { selection_dirty_ = dirty; }
    void SetCursorDirty(bool dirty) { cursor_dirty_ = dirty; }
    bool IsSelectionDirty() const { return selection_dirty_; }
    bool IsCursorDirty() const { return cursor_dirty_; }

    // Cursor position (for rendering)
    void SetCursorPosition(const TextBuffer::Position& pos) { cursor_pos_ = pos; }

private:
    void GenerateTextGeometry(Rml::RenderManager* render_manager);
    void GenerateSelectionGeometry(Rml::RenderManager* render_manager);
    void GenerateCursorGeometry(Rml::RenderManager* render_manager);

    TextBuffer& buffer_;
    TextLayout& layout_;
    SelectionManager& selection_;
    TextEditorConfig& config_;

    // Syntax highlighting tokens (set via command from Lua thread)
    DynamicTable tokens_;

    // Rendering
    std::vector<TextGeometry> text_geometries_;
    Rml::Geometry selection_geometry_;
    Rml::Geometry cursor_geometry_;

    // Dirty flags
    bool selection_dirty_;
    bool cursor_dirty_;
    bool font_ready_;

    // Cursor position for rendering
    TextBuffer::Position cursor_pos_;
};
