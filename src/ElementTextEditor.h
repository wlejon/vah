#pragma once

#include <RmlUi/Core/Element.h>
#include <RmlUi/Core/EventListener.h>
#include <RmlUi/Core/Input.h>
#include <RmlUi/Core/Geometry.h>
#include "TextBuffer.h"
#include "TextLayout.h"
#include "SelectionManager.h"
#include "SyntaxHighlighter.h"
#include <memory>
#include <vector>

/**
 * ElementTextEditor - A custom RmlUi element for viewing and editing text.
 *
 * Features:
 * - Character-level text selection
 * - Syntax highlighting via Lua callback
 * - Mouse drag selection
 * - Ctrl+C to copy
 *
 * Usage in RML:
 *   <texteditor id="my-editor" style="width: 800px; height: 600px;" />
 *
 * Lua interface:
 *   editor:SetText(text)
 *   editor:GetText() -> text
 *   editor:GetSelectedText() -> text
 *   editor:SetSyntaxHighlighter(function_name)
 */
class ElementTextEditor : public Rml::Element, public Rml::EventListener {
public:
    ElementTextEditor(const Rml::String& tag);
    virtual ~ElementTextEditor();

    // Called when element is added to the document tree
    void OnChildAdd(Rml::Element* element) override;

    // Called when element is removed from the document tree
    void OnChildRemove(Rml::Element* element) override;

    // Handle mouse and keyboard events
    void ProcessEvent(Rml::Event& event) override;

    // Lua interface
    void SetText(const std::string& text);
    std::string GetText() const;
    std::string GetSelectedText() const;
    void SetSyntaxHighlighter(SyntaxHighlighter::TokenCallback callback);
    void SetReferenceHighlighter(SyntaxHighlighter::ReferenceCallback callback, const std::string& file_path);

protected:
    // Called every frame to update state
    void OnUpdate() override;

    // Called during render pass
    void OnRender() override;

    // Return the intrinsic dimensions of the text content
    bool GetIntrinsicDimensions(Rml::Vector2f& dimensions, float& ratio) override;

private:
    void GenerateGeometry();
    void GenerateTextGeometry();
    void GenerateSelectionGeometry();

    // Convert mouse position to text position
    TextBuffer::Position ScreenToText(float screen_x, float screen_y);

    // Handle mouse events
    void OnMouseDown(float mouse_x, float mouse_y);
    void OnMouseMove(float mouse_x, float mouse_y);
    void OnMouseUp();

    // Handle keyboard events
    void OnKeyDown(Rml::Input::KeyIdentifier key, int modifiers);

    std::unique_ptr<TextBuffer> buffer_;
    std::unique_ptr<TextLayout> layout_;
    std::unique_ptr<SelectionManager> selection_;
    std::unique_ptr<SyntaxHighlighter> highlighter_;

    // Rendering
    struct TextGeometry {
        Rml::Geometry geometry;
        Rml::Texture texture;
    };
    std::vector<TextGeometry> text_geometries_;
    Rml::Geometry selection_geometry_;

    // Dirty flags
    bool selection_dirty_;
    bool font_ready_;

    // Mouse state
    bool mouse_dragging_;
    Rml::Vector2f last_mouse_pos_;
};
