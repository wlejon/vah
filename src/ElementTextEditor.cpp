#include "ElementTextEditor.h"
#include "Logger.h"
#include <RmlUi/Core/Context.h>
#include <RmlUi/Core/SystemInterface.h>
#include <chrono>

ElementTextEditor::ElementTextEditor(const Rml::String& tag)
    : Rml::Element(tag)
    , buffer_(std::make_unique<TextBuffer>())
    , layout_(std::make_unique<TextLayout>())
    , selection_(std::make_unique<SelectionManager>())
    , config_(std::make_unique<TextEditorConfig>())
    , editable_(false)
    , modified_(false)
    , cursor_blink_time_(0.0)
{
    // Create renderer and input handlers
    renderer_ = std::make_unique<TextEditorRenderer>(*buffer_, *layout_, *selection_, *config_);
    input_ = std::make_unique<TextEditorInput>(*buffer_, *layout_, *selection_, *config_);

    // Set up callbacks for input handler
    input_->SetDirtyCallback([this]() { OnDirty(); });
    input_->SetContentChangeCallback([this]() { OnContentChange(); });
    input_->SetSaveCallback([this]() { OnSave(); });
}

ElementTextEditor::~ElementTextEditor() {
}

void ElementTextEditor::OnChildAdd(Rml::Element* element) {
    Rml::Element::OnChildAdd(element);

    if (element == this) {
        // Initialize font (must be lowercase to match RmlUi font system)
        layout_->SetFont("jetbrains mono", 14);

        // Register for events
        AddEventListener(Rml::EventId::Mousedown, this);
        AddEventListener(Rml::EventId::Mousemove, this);
        AddEventListener(Rml::EventId::Mouseup, this);
        AddEventListener(Rml::EventId::Keydown, this);
        // Listen for drag events since we have drag: drag; set
        AddEventListener(Rml::EventId::Dragend, this);
        AddEventListener(Rml::EventId::Textinput, this);
    }
}

void ElementTextEditor::OnChildRemove(Rml::Element* element) {
    Rml::Element::OnChildRemove(element);

    if (element == this) {
        // Unregister event listeners
        RemoveEventListener(Rml::EventId::Mousedown, this);
        RemoveEventListener(Rml::EventId::Mousemove, this);
        RemoveEventListener(Rml::EventId::Mouseup, this);
        RemoveEventListener(Rml::EventId::Keydown, this);
        RemoveEventListener(Rml::EventId::Dragend, this);
        RemoveEventListener(Rml::EventId::Textinput, this);
    }
}

void ElementTextEditor::ProcessEvent(Rml::Event& event) {
    if (event == Rml::EventId::Mousedown) {
        // Give focus so we can receive keyboard events
        Focus();

        float mouse_x = event.GetParameter<float>("mouse_x", 0.0f);
        float mouse_y = event.GetParameter<float>("mouse_y", 0.0f);
        Rml::Vector2f element_offset = GetAbsoluteOffset(Rml::BoxArea::Content);

        input_->OnMouseDown(mouse_x, mouse_y, element_offset);

        // Update renderer with cursor position if editable
        if (editable_) {
            renderer_->SetCursorPosition(input_->GetCursorPosition());
        }
    }
    else if (event == Rml::EventId::Mousemove) {
        float mouse_x = event.GetParameter<float>("mouse_x", 0.0f);
        float mouse_y = event.GetParameter<float>("mouse_y", 0.0f);
        Rml::Vector2f element_offset = GetAbsoluteOffset(Rml::BoxArea::Content);

        input_->OnMouseMove(mouse_x, mouse_y, element_offset);
    }
    else if (event == Rml::EventId::Mouseup) {
        input_->OnMouseUp();
    }
    else if (event == Rml::EventId::Dragend) {
        // Dragend fires when drag is released (even outside element bounds)
        input_->OnMouseUp();
    }
    else if (event == Rml::EventId::Keydown) {
        Rml::Input::KeyIdentifier key = static_cast<Rml::Input::KeyIdentifier>(
            event.GetParameter<int>("key_identifier", 0));

        // RmlUi passes modifiers as separate boolean parameters, not a combined int
        int modifiers = 0;
        if (event.GetParameter<bool>("ctrl_key", false))
            modifiers |= Rml::Input::KM_CTRL;
        if (event.GetParameter<bool>("shift_key", false))
            modifiers |= Rml::Input::KM_SHIFT;
        if (event.GetParameter<bool>("alt_key", false))
            modifiers |= Rml::Input::KM_ALT;

        input_->OnKeyDown(key, modifiers, editable_);

        // Update renderer with cursor position if editable
        if (editable_) {
            renderer_->SetCursorPosition(input_->GetCursorPosition());
        }

        // Stop propagation for keys we handle when editable
        if (editable_ && (key == Rml::Input::KI_TAB ||
                          key == Rml::Input::KI_RETURN ||
                          key == Rml::Input::KI_NUMPADENTER ||
                          key == Rml::Input::KI_BACK ||
                          key == Rml::Input::KI_DELETE)) {
            event.StopPropagation();
        }
    }
    else if (event == Rml::EventId::Textinput) {
        if (editable_) {
            Rml::String text = event.GetParameter<Rml::String>("text", "");
            if (!text.empty()) {
                input_->OnTextInput(std::string(text), editable_);

                // Update renderer with cursor position
                renderer_->SetCursorPosition(input_->GetCursorPosition());
            }
        }
    }
}

void ElementTextEditor::SetText(const std::string& text) {
    buffer_->SetText(text);
    modified_ = false;  // Reset modified flag when setting new text
    DirtyLayout();
}

std::string ElementTextEditor::GetText() const {
    return buffer_->GetText();
}

std::string ElementTextEditor::GetSelectedText() const {
    return selection_->ExtractText(*buffer_);
}

void ElementTextEditor::SetTokens(const DynamicTable& tokens) {
    renderer_->SetTokens(tokens);
}

void ElementTextEditor::SetEditable(bool editable) {
    editable_ = editable;
    if (editable) {
        renderer_->SetCursorDirty(true);
    }
}

bool ElementTextEditor::IsModified() const {
    return modified_;
}

void ElementTextEditor::SetModified(bool modified) {
    if (modified_ != modified) {
        modified_ = modified;

        // Dispatch modified event with content for re-highlighting
        Rml::Dictionary parameters;
        parameters["element_id"] = GetId();
        parameters["modified"] = modified;
        if (modified) {
            // Include content when marking as modified (for re-highlighting)
            parameters["content"] = buffer_->GetText();
        }
        DispatchEvent("modified", parameters);
    }
}

void ElementTextEditor::OnUpdate() {
    // Check if value attribute has changed (for data binding support)
    auto value_variant = GetAttribute("value");
    if (value_variant) {
        Rml::String value_str;
        value_variant->GetInto(value_str);
        std::string new_value(value_str.c_str());

        // Only update if different from current content
        if (new_value != buffer_->GetText()) {
            SetText(new_value);
        }
    }

    // Update cursor blink animation
    if (editable_) {
        auto now = std::chrono::steady_clock::now();
        double time = std::chrono::duration<double>(now.time_since_epoch()).count();

        // Blink cursor using config period
        double blink_phase = fmod(time, config_->cursor_blink_period);
        bool cursor_visible = (blink_phase < config_->cursor_blink_period / 2.0);
        input_->SetCursorVisible(cursor_visible);
        renderer_->SetCursorDirty(true);
    }

    // Generate geometry
    auto* render_manager = GetRenderManager();
    if (render_manager) {
        renderer_->GenerateGeometry(render_manager, editable_, input_->IsCursorVisible());
    }
}

void ElementTextEditor::OnRender() {
    // Get absolute position
    Rml::Vector2f absolute_offset = GetAbsoluteOffset(Rml::BoxArea::Content);

    // Render everything
    renderer_->RenderAll(absolute_offset, editable_, input_->IsCursorVisible());
}

void ElementTextEditor::DispatchContentChangeEvent() {
    // Dispatch modified event with current content for re-highlighting
    Rml::Dictionary parameters;
    parameters["element_id"] = GetId();
    parameters["modified"] = true;
    parameters["content"] = buffer_->GetText();
    DispatchEvent("modified", parameters);
}

bool ElementTextEditor::GetIntrinsicDimensions(Rml::Vector2f& dimensions, float& ratio) {
    // Calculate the intrinsic size based on text content
    int line_count = buffer_->GetLineCount();
    float line_height = layout_->GetLineHeight();
    float char_width = layout_->GetCharWidth();

    // Find the longest line to determine width
    int max_line_length = 0;
    for (int i = 0; i < line_count; ++i) {
        int line_length = static_cast<int>(buffer_->GetLine(i).length());
        if (line_length > max_line_length) {
            max_line_length = line_length;
        }
    }

    // Set intrinsic dimensions
    dimensions.x = static_cast<float>(max_line_length) * char_width;
    dimensions.y = static_cast<float>(line_count) * line_height;

    // No aspect ratio constraint
    ratio = 0.0f;

    return true;
}

void ElementTextEditor::OnDirty() {
    renderer_->SetSelectionDirty(true);
    renderer_->SetCursorDirty(true);
    DirtyLayout();
}

void ElementTextEditor::OnContentChange() {
    renderer_->SetTokens(DynamicTable{});  // Clear tokens when text changes
    DispatchContentChangeEvent();
    modified_ = true;
}

void ElementTextEditor::OnSave() {
    // Dispatch a custom save event that Lua can listen to
    Rml::Dictionary parameters;
    parameters["element_id"] = GetId();
    parameters["content"] = buffer_->GetText();
    DispatchEvent("save", parameters);
}
