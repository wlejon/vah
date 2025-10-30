#include "ElementTextEditor.h"
#include "Logger.h"
#include <RmlUi/Core/Context.h>
#include <RmlUi/Core/SystemInterface.h>
#include <RmlUi/Core/ID.h>
#include <SDL2/SDL.h>
#include <chrono>

ElementTextEditor::ElementTextEditor(const Rml::String& tag)
    : Rml::Element(tag)
    , buffer_(std::make_unique<TextBuffer>())
    , layout_(std::make_unique<TextLayout>())
    , selection_(std::make_unique<SelectionManager>())
    , config_(std::make_unique<TextEditorConfig>())
    , undo_stack_(std::make_unique<UndoStack>())
    , editable_(false)
    , modified_(false)
    , cursor_blink_time_(0.0)
    , applying_undo_redo_(false)
{
    // Create renderer and input handlers
    renderer_ = std::make_unique<TextEditorRenderer>(*buffer_, *layout_, *selection_, *config_);
    input_ = std::make_unique<TextEditorInput>(*buffer_, *layout_, *selection_, *config_);

    // Set up callbacks for input handler
    input_->SetDirtyCallback([this]() { OnDirty(); });
    input_->SetContentChangeCallback([this]() { OnContentChange(); });
    input_->SetSaveCallback([this]() { OnSave(); });
    input_->SetBeforeContentChangeCallback([this]() { PushUndoSnapshot(); });
}

ElementTextEditor::~ElementTextEditor() {
}

void ElementTextEditor::OnChildAdd(Rml::Element* element) {
    Rml::Element::OnChildAdd(element);

    if (element == this) {
        // Register for events FIRST - must happen even if font initialization fails
        AddEventListener(Rml::EventId::Mousedown, this);
        AddEventListener(Rml::EventId::Mousemove, this);
        AddEventListener(Rml::EventId::Mouseup, this);
        AddEventListener(Rml::EventId::Keydown, this);
        AddEventListener(Rml::EventId::Dragend, this);
        AddEventListener(Rml::EventId::Textinput, this);

        // Try to initialize font from computed styles
        // NOTE: This may fail for elements in data-bound templates that haven't been
        // fully processed yet. That's OK - we'll lazily initialize on first render.
        InitializeFontMetrics();
    }
}

bool ElementTextEditor::InitializeFontMetrics() {
    // Skip if already initialized
    if (layout_->HasFontMetrics()) {
        return true;
    }

    // Try to get font handle from computed styles
    const auto& computed = GetComputedValues();
    Rml::FontFaceHandle font_handle = computed.font_face_handle();
    auto font_engine = Rml::GetFontEngineInterface();

    if (!font_handle || !font_engine) {
        // Not ready yet - will try again on next render
        return false;
    }

    const Rml::FontMetrics& metrics = font_engine->GetFontMetrics(font_handle);

    // Measure a single character width
    Rml::String test_string = "x";
    Rml::String language = "en";
    Rml::TextShapingContext context{language};
    int char_advance = font_engine->GetStringWidth(font_handle, test_string, context);

    if (char_advance <= 0) {
        LOG_WARN("ElementTextEditor: Invalid character width measurement: {}", char_advance);
        return false;
    }

    // Store the measurements in layout
    layout_->SetFontMetrics(metrics.line_spacing, static_cast<float>(char_advance));

    // Get font parameters for reference (used by renderer)
    std::string font_family = "jetbrains mono";
    if (auto p = GetProperty(Rml::PropertyId::FontFamily)) {
        Rml::String rml_family = p->Get<Rml::String>();
        if (!rml_family.empty()) {
            font_family = std::string(rml_family);
        }
    }

    // Get style and weight from computed values
    Rml::Style::FontStyle font_style = computed.font_style();
    Rml::Style::FontWeight font_weight = computed.font_weight();
    int font_size = static_cast<int>(computed.font_size());

    // Store font info in layout for renderer to use
    layout_->SetFontInfo(font_family, font_style, font_weight, font_size);

    return true;
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

        // Stop propagation for all editing and navigation keys when editable
        if (editable_ && (key == Rml::Input::KI_TAB ||
                          key == Rml::Input::KI_RETURN ||
                          key == Rml::Input::KI_NUMPADENTER ||
                          key == Rml::Input::KI_BACK ||
                          key == Rml::Input::KI_DELETE ||
                          key == Rml::Input::KI_LEFT ||
                          key == Rml::Input::KI_RIGHT ||
                          key == Rml::Input::KI_UP ||
                          key == Rml::Input::KI_DOWN ||
                          key == Rml::Input::KI_HOME ||
                          key == Rml::Input::KI_END)) {
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

void ElementTextEditor::CopyToClipboard() {
    if (!selection_) return;

    std::string selected = selection_->ExtractText(*buffer_);
    if (!selected.empty()) {
        SDL_SetClipboardText(selected.c_str());
    }
}

void ElementTextEditor::PasteFromClipboard() {
    if (!editable_ || !buffer_ || !selection_ || !input_) return;

    if (SDL_HasClipboardText()) {
        char* clipboard_text = SDL_GetClipboardText();
        if (clipboard_text) {
            // Push state to undo stack BEFORE making changes
            PushUndoSnapshot();

            // Delete selection if any and clear it
            TextBuffer::Position cursor;
            if (selection_->HasSelection()) {
                TextBuffer::Position start, end;
                selection_->GetSelectionRange(start, end);
                buffer_->DeleteRange(start, end);
                selection_->ClearSelection();
                cursor = start;
            } else {
                cursor = input_->GetCursorPosition();
            }

            // Insert clipboard text character by character and update cursor position
            for (const char* p = clipboard_text; *p; ++p) {
                buffer_->InsertChar(cursor, *p);
                if (*p == '\n') {
                    cursor.line++;
                    cursor.column = 0;
                } else {
                    cursor.column++;
                }
            }

            SDL_free(clipboard_text);

            // Set cursor to end of pasted text and update
            input_->SetCursorPosition(cursor);

            // Mark as modified and trigger events
            SetModified(true);
            OnDirty();
            OnContentChange();
        }
    }
}

void ElementTextEditor::CutToClipboard() {
    if (!editable_ || !selection_ || !buffer_ || !input_) return;

    if (selection_->HasSelection()) {
        // Push state to undo stack BEFORE making changes
        PushUndoSnapshot();

        // Copy to clipboard first
        std::string selected = selection_->ExtractText(*buffer_);
        if (!selected.empty()) {
            SDL_SetClipboardText(selected.c_str());
        }

        // Delete the selection and clear it
        TextBuffer::Position start, end;
        selection_->GetSelectionRange(start, end);
        buffer_->DeleteRange(start, end);
        selection_->ClearSelection();

        // Set cursor to where the selection started (the void/gap)
        input_->SetCursorPosition(start);

        // Mark as modified and trigger events
        SetModified(true);
        OnDirty();
        OnContentChange();
    }
}

void ElementTextEditor::SelectAll() {
    if (!buffer_ || !selection_ || !input_) return;

    // Select from start to end of document
    TextBuffer::Position start(0, 0);
    int last_line = buffer_->GetLineCount() - 1;
    int last_column = static_cast<int>(buffer_->GetLine(last_line).length());
    TextBuffer::Position end(last_line, last_column);

    selection_->SetAnchor(start);
    selection_->SetCursor(end);
    input_->SetCursorPosition(end);

    OnDirty();
}

void ElementTextEditor::Undo() {
    if (!undo_stack_ || !buffer_ || !input_) return;

    // Get current state
    std::string current_text = buffer_->GetText();
    TextBuffer::Position current_cursor_pos = input_->GetCursorPosition();

    // Undo to previous state
    std::string text;
    TextBuffer::Position cursor_pos;

    if (undo_stack_->Undo(current_text, current_cursor_pos, text, cursor_pos)) {
        // Set flag to prevent pushing to undo stack
        applying_undo_redo_ = true;

        // Restore state
        buffer_->SetText(text);
        input_->SetCursorPosition(cursor_pos);
        selection_->ClearSelection();

        // Update display
        SetModified(true);
        OnDirty();

        // Dispatch content change event (won't push to undo due to flag)
        renderer_->SetTokens(DynamicTable{});
        DispatchContentChangeEvent();

        // Clear flag
        applying_undo_redo_ = false;
    }
}

void ElementTextEditor::Redo() {
    if (!undo_stack_ || !buffer_ || !input_) return;

    // Get current state
    std::string current_text = buffer_->GetText();
    TextBuffer::Position current_cursor_pos = input_->GetCursorPosition();

    // Redo to next state
    std::string text;
    TextBuffer::Position cursor_pos;

    if (undo_stack_->Redo(current_text, current_cursor_pos, text, cursor_pos)) {
        // Set flag to prevent pushing to undo stack
        applying_undo_redo_ = true;

        // Restore state
        buffer_->SetText(text);
        input_->SetCursorPosition(cursor_pos);
        selection_->ClearSelection();

        // Update display
        SetModified(true);
        OnDirty();

        // Dispatch content change event (won't push to undo due to flag)
        renderer_->SetTokens(DynamicTable{});
        DispatchContentChangeEvent();

        // Clear flag
        applying_undo_redo_ = false;
    }
}

bool ElementTextEditor::CanUndo() const {
    return undo_stack_ && undo_stack_->CanUndo();
}

bool ElementTextEditor::CanRedo() const {
    return undo_stack_ && undo_stack_->CanRedo();
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
    // Lazily initialize font metrics if not done yet
    // (needed for elements in data-bound templates)
    if (!InitializeFontMetrics()) {
        // Font not ready yet, skip rendering
        return;
    }

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

    // NOTE: Undo stack is pushed BEFORE changes in PushUndoSnapshot()
    // We don't push here because this is called AFTER the change
}

void ElementTextEditor::PushUndoSnapshot() {
    // Push current state to undo stack BEFORE making changes
    if (!applying_undo_redo_ && undo_stack_ && buffer_ && input_) {
        undo_stack_->PushUndo(buffer_->GetText(), input_->GetCursorPosition());
    }
}

void ElementTextEditor::OnSave() {
    // Dispatch a custom save event that Lua can listen to
    Rml::Dictionary parameters;
    parameters["element_id"] = GetId();
    parameters["content"] = buffer_->GetText();
    DispatchEvent("save", parameters);
}
