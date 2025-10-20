#pragma once

#include <RmlUi/Core/Element.h>
#include <RmlUi/Core/EventListener.h>
#include <RmlUi/Core/Input.h>
#include "TextBuffer.h"
#include "TextLayout.h"
#include "SelectionManager.h"
#include "TextEditorConfig.h"
#include "TextEditorRenderer.h"
#include "TextEditorInput.h"
#include "DataStore.h"  // For DynamicTable type
#include <memory>

/**
 * ElementTextEditor - A custom RmlUi element for viewing and editing text.
 *
 * Features:
 * - Character-level text selection
 * - Syntax highlighting via data binding
 * - Mouse drag selection
 * - Ctrl+C to copy
 *
 * Usage in RML:
 *   <texteditor id="my-editor" style="width: 800px; height: 600px;" />
 *
 * Lua interface:
 *   ui.set_texteditor_content("my-editor", text)
 *
 * Syntax highlighting (from Lua thread):
 *   data.bind("editor_tokens_my-editor", token_array)
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

    // Interface for commands
    void SetText(const std::string& text);
    std::string GetText() const;
    std::string GetSelectedText() const;
    void SetTokens(const DynamicTable& tokens);
    void SetEditable(bool editable);
    bool IsModified() const;
    void SetModified(bool modified);

    // Access to config for Lua binding
    TextEditorConfig& GetConfig() { return *config_; }

protected:
    // Called every frame to update state
    void OnUpdate() override;

    // Called during render pass
    void OnRender() override;

    // Return the intrinsic dimensions of the text content
    bool GetIntrinsicDimensions(Rml::Vector2f& dimensions, float& ratio) override;

private:
    void DispatchContentChangeEvent();
    void OnDirty();
    void OnContentChange();
    void OnSave();

    std::unique_ptr<TextBuffer> buffer_;
    std::unique_ptr<TextLayout> layout_;
    std::unique_ptr<SelectionManager> selection_;
    std::unique_ptr<TextEditorConfig> config_;
    std::unique_ptr<TextEditorRenderer> renderer_;
    std::unique_ptr<TextEditorInput> input_;

    // Editor state
    bool editable_;
    bool modified_;
    double cursor_blink_time_;
};
