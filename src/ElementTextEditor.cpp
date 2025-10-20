#include "ElementTextEditor.h"
#include "Logger.h"
#include <RmlUi/Core/Context.h>
#include <RmlUi/Core/SystemInterface.h>
#include <RmlUi/Core/RenderManager.h>
#include <RmlUi/Core/FontEngineInterface.h>
#include <RmlUi/Core/Mesh.h>
#include <SDL2/SDL.h>
#include <map>
#include <chrono>

ElementTextEditor::ElementTextEditor(const Rml::String& tag)
    : Rml::Element(tag)
    , buffer_(std::make_unique<TextBuffer>())
    , layout_(std::make_unique<TextLayout>())
    , selection_(std::make_unique<SelectionManager>())
    , selection_dirty_(false)
    , cursor_dirty_(false)
    , font_ready_(false)
    , editable_(false)
    , modified_(false)
    , cursor_pos_(0, 0)
    , cursor_blink_time_(0.0)
    , cursor_visible_(true)
    , mouse_dragging_(false)
    , last_mouse_pos_(0.0f, 0.0f)
{
    LOG_INFO("ElementTextEditor created");
}

ElementTextEditor::~ElementTextEditor() {
    LOG_INFO("ElementTextEditor destroyed");
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

        LOG_INFO("ElementTextEditor removed from document tree");
    }
}

void ElementTextEditor::ProcessEvent(Rml::Event& event) {
    if (event == Rml::EventId::Mousedown) {
        float mouse_x = event.GetParameter<float>("mouse_x", 0.0f);
        float mouse_y = event.GetParameter<float>("mouse_y", 0.0f);
        OnMouseDown(mouse_x, mouse_y);
    }
    else if (event == Rml::EventId::Mousemove) {
        float mouse_x = event.GetParameter<float>("mouse_x", 0.0f);
        float mouse_y = event.GetParameter<float>("mouse_y", 0.0f);
        OnMouseMove(mouse_x, mouse_y);
    }
    else if (event == Rml::EventId::Mouseup) {
        OnMouseUp();
    }
    else if (event == Rml::EventId::Dragend) {
        // Dragend fires when drag is released (even outside element bounds)
        OnMouseUp();
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

        OnKeyDown(key, modifiers);
    }
    else if (event == Rml::EventId::Textinput) {
        if (editable_) {
            Rml::String text = event.GetParameter<Rml::String>("text", "");
            if (!text.empty()) {
                OnTextInput(std::string(text));
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
    tokens_ = tokens;
    LOG_INFO("ElementTextEditor: Received {} syntax tokens", tokens.size());
}

void ElementTextEditor::SetEditable(bool editable) {
    editable_ = editable;
    if (editable) {
        cursor_dirty_ = true;
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
    // Retry font initialization if not ready
    if (!font_ready_) {
        layout_->SetFont("jetbrains mono", 14);
        // Check if it succeeded by seeing if we have valid metrics
        if (layout_->GetCharWidth() > 0.0f && layout_->GetLineHeight() > 0.0f) {
            font_ready_ = true;
            LOG_INFO("ElementTextEditor: Font ready");
        }
    }

    // Update cursor blink animation
    if (editable_) {
        auto now = std::chrono::steady_clock::now();
        double time = std::chrono::duration<double>(now.time_since_epoch()).count();

        // Blink cursor every 0.5 seconds
        double blink_phase = fmod(time, 1.0);
        cursor_visible_ = (blink_phase < 0.5);
        cursor_dirty_ = true;
    }

    // Always regenerate text geometry every frame to prevent garbled rendering
    // This is needed due to timing issues with the RmlUi font system
    GenerateGeometry();
}

void ElementTextEditor::OnRender() {
    // Get absolute position
    Rml::Vector2f absolute_offset = GetAbsoluteOffset(Rml::BoxArea::Content);

    // Render selection geometry first (behind text)
    if (selection_geometry_) {
        selection_geometry_.Render(absolute_offset);
    }

    // Render cursor (behind text but above selection)
    if (editable_ && cursor_visible_ && cursor_geometry_) {
        cursor_geometry_.Render(absolute_offset);
    }

    // Render text geometries
    for (auto& text_geom : text_geometries_) {
        if (text_geom.geometry) {
            text_geom.geometry.Render(absolute_offset, text_geom.texture);
        }
    }
}

void ElementTextEditor::GenerateGeometry() {
    // Always regenerate text geometry to prevent garbled rendering
    GenerateTextGeometry();

    if (selection_dirty_) {
        GenerateSelectionGeometry();
        selection_dirty_ = false;
    }

    if (cursor_dirty_ && editable_) {
        GenerateCursorGeometry();
        cursor_dirty_ = false;
    }
}

void ElementTextEditor::GenerateTextGeometry() {
    // Clear existing text geometries
    text_geometries_.clear();

    auto* render_manager = GetRenderManager();
    if (!render_manager) {
        LOG_ERROR("ElementTextEditor: No render manager available");
        return;
    }

    auto font_engine = Rml::GetFontEngineInterface();
    if (!font_engine) {
        LOG_ERROR("ElementTextEditor: Font engine not available");
        return;
    }

    // Get font handle (must be lowercase to match RmlUi font system)
    Rml::FontFaceHandle font_handle = font_engine->GetFontFaceHandle(
        "jetbrains mono",
        Rml::Style::FontStyle::Normal,
        Rml::Style::FontWeight::Normal,
        14
    );

    if (!font_handle) {
        return;
    }

    // Get font metrics and validate they're ready
    const Rml::FontMetrics& metrics = font_engine->GetFontMetrics(font_handle);
    if (metrics.ascent <= 0.0f || metrics.descent <= 0.0f || metrics.line_spacing <= 0.0f) {
        // Font metrics invalid - font not fully initialized yet
        LOG_WARN("ElementTextEditor: Font metrics not ready (ascent={}, descent={}, line_spacing={}), retrying next frame",
                 metrics.ascent, metrics.descent, metrics.line_spacing);
        return;
    }

    // Get syntax highlighting tokens (set via command from Lua thread)
    struct Token {
        int line;
        int start_col;
        int end_col;
        Rml::Colourb color;
    };
    std::vector<Token> tokens;

    // Convert tokens from DynamicTable to local format
    for (const auto& row : tokens_) {
        Token token;

        // Extract token fields from DynamicRow
        auto get_int = [&](const std::string& key, int default_val) -> int {
            auto it = row.find(key);
            if (it != row.end()) {
                if (std::holds_alternative<int64_t>(it->second)) {
                    return static_cast<int>(std::get<int64_t>(it->second));
                }
            }
            return default_val;
        };

        token.line = get_int("line", 0);
        token.start_col = get_int("start_col", 0);
        token.end_col = get_int("end_col", 0);

        int r = get_int("r", 255);
        int g = get_int("g", 255);
        int b = get_int("b", 255);
        int a = get_int("a", 255);
        token.color = Rml::Colourb(r, g, b, a);

        tokens.push_back(token);
    }

    // Build token map for quick lookup: map[line] -> list of tokens on that line
    std::map<int, std::vector<Token>> token_map;
    for (const auto& token : tokens) {
        token_map[token.line].push_back(token);
    }

    float line_height = layout_->GetLineHeight();
    int line_count = buffer_->GetLineCount();
    float baseline_offset = metrics.ascent;

    // We'll generate text line by line using FontEngineInterface::GenerateString
    // This outputs TexturedMeshList which we need to convert to Geometry
    Rml::String language = "en";
    Rml::TextShapingContext shaping_context{language};

    // Default text color for unhighlighted text
    Rml::Colourb default_color(200, 200, 200, 255);

    float y = 0.0f;
    for (int line_num = 0; line_num < line_count; ++line_num) {
        std::string line = buffer_->GetLine(line_num);

        if (line.empty()) {
            y += line_height;
            continue;  // Skip empty lines
        }

        // Get tokens for this line
        auto tokens_it = token_map.find(line_num);

        // Build colored segments for this line
        // Each segment is a contiguous range of characters with the same color
        struct ColoredSegment {
            int start_col;
            int end_col;
            Rml::Colourb color;
        };
        std::vector<ColoredSegment> segments;

        if (tokens_it != token_map.end() && !tokens_it->second.empty()) {
            // Sort tokens by start column
            auto line_tokens = tokens_it->second;
            std::sort(line_tokens.begin(), line_tokens.end(),
                [](const Token& a, const Token& b) {
                    return a.start_col < b.start_col;
                });

            // Fill in segments, adding default color for gaps
            int current_col = 0;
            for (const auto& token : line_tokens) {
                int start = std::max(0, token.start_col);
                int end = std::min(token.end_col, static_cast<int>(line.size()));

                // Add default color segment for gap before this token
                if (current_col < start) {
                    segments.push_back({current_col, start, default_color});
                }

                // Add highlighted token segment
                if (start < end && start < static_cast<int>(line.size())) {
                    segments.push_back({start, end, token.color});
                    current_col = end;
                }
            }

            // Fill remaining characters with default color
            if (current_col < static_cast<int>(line.size())) {
                segments.push_back({current_col, static_cast<int>(line.size()), default_color});
            }
        } else {
            // No tokens - entire line is default color
            segments.push_back({0, static_cast<int>(line.size()), default_color});
        }

        // Render each segment
        float char_width = layout_->GetCharWidth();
        for (const auto& segment : segments) {
            if (segment.start_col >= segment.end_col) continue;

            std::string segment_text = line.substr(segment.start_col, segment.end_col - segment.start_col);
            if (segment_text.empty()) continue;

            float x = static_cast<float>(segment.start_col) * char_width;
            Rml::ColourbPremultiplied premult_color = segment.color.ToPremultiplied();
            Rml::TexturedMeshList mesh_list;
            Rml::Vector2f position(x, y + baseline_offset);
            Rml::FontEffectsHandle effects_handle = 0;

            font_engine->GenerateString(
                *render_manager,
                font_handle,
                effects_handle,
                segment_text,
                position,
                premult_color,
                1.0f,
                shaping_context,
                mesh_list
            );

            // Convert to geometry
            for (auto& textured_mesh : mesh_list) {
                if (textured_mesh.mesh) {
                    TextGeometry text_geom;
                    text_geom.geometry = render_manager->MakeGeometry(std::move(textured_mesh.mesh));
                    text_geom.texture = textured_mesh.texture;
                    text_geometries_.push_back(std::move(text_geom));
                }
            }
        }

        y += line_height;
    }
}

void ElementTextEditor::GenerateSelectionGeometry() {
    // Release old selection geometry
    if (selection_geometry_) {
        selection_geometry_.Release();
    }

    if (!selection_->HasSelection()) {
        return;
    }

    auto* render_manager = GetRenderManager();
    if (!render_manager) {
        return;
    }

    // Get selection range
    TextBuffer::Position start, end;
    selection_->GetSelectionRange(start, end);

    // Clamp to buffer bounds
    start = buffer_->ClampPosition(start);
    end = buffer_->ClampPosition(end);

    // Build mesh for selection quads
    Rml::Mesh mesh;
    Rml::ColourbPremultiplied selection_color = Rml::Colourb(100, 150, 255, 100).ToPremultiplied();

    float line_height = layout_->GetLineHeight();
    float char_width = layout_->GetCharWidth();

    if (start.line == end.line) {
        // Single line selection
        float x1 = static_cast<float>(start.column) * char_width;
        float x2 = static_cast<float>(end.column) * char_width;
        float y1 = static_cast<float>(start.line) * line_height;
        float y2 = y1 + line_height;

        // Create quad (2 triangles = 6 indices, 4 vertices)
        int base = static_cast<int>(mesh.vertices.size());
        mesh.vertices.push_back({Rml::Vector2f(x1, y1), selection_color, Rml::Vector2f(0, 0)});
        mesh.vertices.push_back({Rml::Vector2f(x2, y1), selection_color, Rml::Vector2f(0, 0)});
        mesh.vertices.push_back({Rml::Vector2f(x2, y2), selection_color, Rml::Vector2f(0, 0)});
        mesh.vertices.push_back({Rml::Vector2f(x1, y2), selection_color, Rml::Vector2f(0, 0)});

        mesh.indices.push_back(base + 0);
        mesh.indices.push_back(base + 1);
        mesh.indices.push_back(base + 2);
        mesh.indices.push_back(base + 0);
        mesh.indices.push_back(base + 2);
        mesh.indices.push_back(base + 3);
    } else {
        // Multi-line selection

        // First line
        std::string first_line = buffer_->GetLine(start.line);
        float x1 = static_cast<float>(start.column) * char_width;
        // Include space for newline character (one position past the last character)
        float x2 = static_cast<float>(first_line.size() + 1) * char_width;
        float y1 = static_cast<float>(start.line) * line_height;
        float y2 = y1 + line_height;

        int base = static_cast<int>(mesh.vertices.size());
        mesh.vertices.push_back({Rml::Vector2f(x1, y1), selection_color, Rml::Vector2f(0, 0)});
        mesh.vertices.push_back({Rml::Vector2f(x2, y1), selection_color, Rml::Vector2f(0, 0)});
        mesh.vertices.push_back({Rml::Vector2f(x2, y2), selection_color, Rml::Vector2f(0, 0)});
        mesh.vertices.push_back({Rml::Vector2f(x1, y2), selection_color, Rml::Vector2f(0, 0)});

        mesh.indices.push_back(base + 0);
        mesh.indices.push_back(base + 1);
        mesh.indices.push_back(base + 2);
        mesh.indices.push_back(base + 0);
        mesh.indices.push_back(base + 2);
        mesh.indices.push_back(base + 3);

        // Middle lines
        for (int line_num = start.line + 1; line_num < end.line; ++line_num) {
            std::string line = buffer_->GetLine(line_num);
            float x1_mid = 0.0f;
            // Include space for newline character (one position past the last character)
            float x2_mid = static_cast<float>(line.size() + 1) * char_width;
            float y1_mid = static_cast<float>(line_num) * line_height;
            float y2_mid = y1_mid + line_height;

            base = static_cast<int>(mesh.vertices.size());
            mesh.vertices.push_back({Rml::Vector2f(x1_mid, y1_mid), selection_color, Rml::Vector2f(0, 0)});
            mesh.vertices.push_back({Rml::Vector2f(x2_mid, y1_mid), selection_color, Rml::Vector2f(0, 0)});
            mesh.vertices.push_back({Rml::Vector2f(x2_mid, y2_mid), selection_color, Rml::Vector2f(0, 0)});
            mesh.vertices.push_back({Rml::Vector2f(x1_mid, y2_mid), selection_color, Rml::Vector2f(0, 0)});

            mesh.indices.push_back(base + 0);
            mesh.indices.push_back(base + 1);
            mesh.indices.push_back(base + 2);
            mesh.indices.push_back(base + 0);
            mesh.indices.push_back(base + 2);
            mesh.indices.push_back(base + 3);
        }

        // Last line
        float x1_last = 0.0f;
        float x2_last = static_cast<float>(end.column) * char_width;
        float y1_last = static_cast<float>(end.line) * line_height;
        float y2_last = y1_last + line_height;

        base = static_cast<int>(mesh.vertices.size());
        mesh.vertices.push_back({Rml::Vector2f(x1_last, y1_last), selection_color, Rml::Vector2f(0, 0)});
        mesh.vertices.push_back({Rml::Vector2f(x2_last, y1_last), selection_color, Rml::Vector2f(0, 0)});
        mesh.vertices.push_back({Rml::Vector2f(x2_last, y2_last), selection_color, Rml::Vector2f(0, 0)});
        mesh.vertices.push_back({Rml::Vector2f(x1_last, y2_last), selection_color, Rml::Vector2f(0, 0)});

        mesh.indices.push_back(base + 0);
        mesh.indices.push_back(base + 1);
        mesh.indices.push_back(base + 2);
        mesh.indices.push_back(base + 0);
        mesh.indices.push_back(base + 2);
        mesh.indices.push_back(base + 3);
    }

    // Create geometry from mesh
    if (mesh) {
        selection_geometry_ = render_manager->MakeGeometry(std::move(mesh));
    }
}

void ElementTextEditor::GenerateCursorGeometry() {
    // Release old cursor geometry
    if (cursor_geometry_) {
        cursor_geometry_.Release();
    }

    if (!editable_) {
        return;
    }

    auto* render_manager = GetRenderManager();
    if (!render_manager) {
        return;
    }

    // Clamp cursor position to buffer bounds
    cursor_pos_ = buffer_->ClampPosition(cursor_pos_);

    // Build cursor quad (vertical line)
    Rml::Mesh mesh;
    Rml::ColourbPremultiplied cursor_color = Rml::Colourb(255, 255, 255, 140).ToPremultiplied();

    float line_height = layout_->GetLineHeight();
    float char_width = layout_->GetCharWidth();
    float cursor_width = 2.0f;  // 2 pixels wide

    float x = static_cast<float>(cursor_pos_.column) * char_width;
    float y = static_cast<float>(cursor_pos_.line) * line_height;

    // Create vertical line quad
    int base = static_cast<int>(mesh.vertices.size());
    mesh.vertices.push_back({Rml::Vector2f(x, y), cursor_color, Rml::Vector2f(0, 0)});
    mesh.vertices.push_back({Rml::Vector2f(x + cursor_width, y), cursor_color, Rml::Vector2f(0, 0)});
    mesh.vertices.push_back({Rml::Vector2f(x + cursor_width, y + line_height), cursor_color, Rml::Vector2f(0, 0)});
    mesh.vertices.push_back({Rml::Vector2f(x, y + line_height), cursor_color, Rml::Vector2f(0, 0)});

    mesh.indices.push_back(base + 0);
    mesh.indices.push_back(base + 1);
    mesh.indices.push_back(base + 2);
    mesh.indices.push_back(base + 0);
    mesh.indices.push_back(base + 2);
    mesh.indices.push_back(base + 3);

    // Create geometry from mesh
    if (mesh) {
        cursor_geometry_ = render_manager->MakeGeometry(std::move(mesh));
    }
}

TextBuffer::Position ElementTextEditor::ScreenToText(float screen_x, float screen_y) {
    // Get element offset - must match the box area used in OnRender()
    Rml::Vector2f absolute_offset = GetAbsoluteOffset(Rml::BoxArea::Content);

    // Convert to element-relative coordinates
    float local_x = screen_x - absolute_offset.x;
    float local_y = screen_y - absolute_offset.y;

    // Convert to text position
    TextBuffer::Position pos = layout_->ScreenToTextPosition(local_x, local_y);

    // Clamp to buffer bounds
    return buffer_->ClampPosition(pos);
}

void ElementTextEditor::OnMouseDown(float mouse_x, float mouse_y) {
    // Give focus to this element so it can receive keyboard events
    Focus();

    TextBuffer::Position pos = ScreenToText(mouse_x, mouse_y);

    selection_->SetAnchor(pos);
    selection_->SetCursor(pos);

    // Update cursor position if editable
    if (editable_) {
        cursor_pos_ = pos;
        cursor_dirty_ = true;
        cursor_visible_ = true;  // Reset blink when clicking
    }

    mouse_dragging_ = true;
    last_mouse_pos_ = Rml::Vector2f(mouse_x, mouse_y);

    selection_dirty_ = true;
    DirtyLayout();
}

void ElementTextEditor::OnMouseMove(float mouse_x, float mouse_y) {
    if (!mouse_dragging_) {
        return;
    }

    TextBuffer::Position pos = ScreenToText(mouse_x, mouse_y);
    selection_->SetCursor(pos);

    last_mouse_pos_ = Rml::Vector2f(mouse_x, mouse_y);

    selection_dirty_ = true;
    DirtyLayout();
}

void ElementTextEditor::OnMouseUp() {
    mouse_dragging_ = false;
}

void ElementTextEditor::OnKeyDown(Rml::Input::KeyIdentifier key, int modifiers) {
    // Handle Ctrl+C for copy (works in both editable and read-only mode)
    if (key == Rml::Input::KI_C && (modifiers & Rml::Input::KM_CTRL)) {
        std::string selected = GetSelectedText();
        if (!selected.empty()) {
            SDL_SetClipboardText(selected.c_str());
        }
        return;
    }

    // Only handle editing keys if editable
    if (!editable_) {
        return;
    }

    // Handle Ctrl+S for save
    if (key == Rml::Input::KI_S && (modifiers & Rml::Input::KM_CTRL)) {
        if (editable_) {
            // Dispatch a custom save event that Lua can listen to
            Rml::Dictionary parameters;
            parameters["element_id"] = GetId();
            parameters["content"] = buffer_->GetText();
            DispatchEvent("save", parameters);
        }
        return;
    }

    // Handle Ctrl+V for paste
    if (key == Rml::Input::KI_V && (modifiers & Rml::Input::KM_CTRL)) {
        if (SDL_HasClipboardText()) {
            char* clipboard_text = SDL_GetClipboardText();
            if (clipboard_text) {
                // Delete selection if any
                if (selection_->HasSelection()) {
                    TextBuffer::Position start, end;
                    selection_->GetSelectionRange(start, end);
                    buffer_->DeleteRange(start, end);
                    cursor_pos_ = start;
                    selection_->ClearSelection();
                }

                // Insert clipboard text
                buffer_->InsertText(cursor_pos_, clipboard_text);

                // Move cursor to end of inserted text
                for (const char* p = clipboard_text; *p; ++p) {
                    if (*p == '\n') {
                        cursor_pos_.line++;
                        cursor_pos_.column = 0;
                    } else {
                        cursor_pos_.column++;
                    }
                }

                SDL_free(clipboard_text);
                tokens_.clear();  // Clear tokens when text changes
                DispatchContentChangeEvent();
                modified_ = true;
                cursor_dirty_ = true;
                selection_dirty_ = true;
                DirtyLayout();
            }
        }
        return;
    }

    // Handle backspace
    if (key == Rml::Input::KI_BACK) {
        bool made_change = false;
        if (selection_->HasSelection()) {
            // Delete selection
            TextBuffer::Position start, end;
            selection_->GetSelectionRange(start, end);
            buffer_->DeleteRange(start, end);
            cursor_pos_ = start;
            selection_->ClearSelection();
            made_change = true;
        } else if (cursor_pos_.column > 0) {
            // Delete character before cursor
            cursor_pos_.column--;
            buffer_->DeleteChar(cursor_pos_);
            made_change = true;
        } else if (cursor_pos_.line > 0) {
            // Join with previous line
            int prev_line_len = static_cast<int>(buffer_->GetLine(cursor_pos_.line - 1).length());
            buffer_->JoinLines(cursor_pos_.line - 1);
            cursor_pos_.line--;
            cursor_pos_.column = prev_line_len;
            made_change = true;
        }
        if (made_change) {
            tokens_.clear();  // Clear tokens when text changes
            DispatchContentChangeEvent();
            modified_ = true;
        }
        cursor_dirty_ = true;
        selection_dirty_ = true;
        DirtyLayout();
        return;
    }

    // Handle delete
    if (key == Rml::Input::KI_DELETE) {
        if (selection_->HasSelection()) {
            // Delete selection
            TextBuffer::Position start, end;
            selection_->GetSelectionRange(start, end);
            buffer_->DeleteRange(start, end);
            cursor_pos_ = start;
            selection_->ClearSelection();
        } else {
            // Delete character at cursor
            buffer_->DeleteChar(cursor_pos_);
        }
        tokens_.clear();  // Clear tokens when text changes
        DispatchContentChangeEvent();
        modified_ = true;
        cursor_dirty_ = true;
        selection_dirty_ = true;
        DirtyLayout();
        return;
    }

    // Handle enter/return
    if (key == Rml::Input::KI_RETURN || key == Rml::Input::KI_NUMPADENTER) {
        // Delete selection if any
        if (selection_->HasSelection()) {
            TextBuffer::Position start, end;
            selection_->GetSelectionRange(start, end);
            buffer_->DeleteRange(start, end);
            cursor_pos_ = start;
            selection_->ClearSelection();
        }

        // Insert newline
        buffer_->InsertChar(cursor_pos_, '\n');
        cursor_pos_.line++;
        cursor_pos_.column = 0;
        tokens_.clear();  // Clear tokens when text changes
        DispatchContentChangeEvent();
        modified_ = true;
        cursor_dirty_ = true;
        selection_dirty_ = true;
        DirtyLayout();
        return;
    }

    // Handle arrow keys
    if (key == Rml::Input::KI_LEFT) {
        if (cursor_pos_.column > 0) {
            cursor_pos_.column--;
        } else if (cursor_pos_.line > 0) {
            cursor_pos_.line--;
            cursor_pos_.column = static_cast<int>(buffer_->GetLine(cursor_pos_.line).length());
        }
        cursor_dirty_ = true;
        selection_->ClearSelection();
        selection_dirty_ = true;
        return;
    }

    if (key == Rml::Input::KI_RIGHT) {
        int line_len = static_cast<int>(buffer_->GetLine(cursor_pos_.line).length());
        if (cursor_pos_.column < line_len) {
            cursor_pos_.column++;
        } else if (cursor_pos_.line < buffer_->GetLineCount() - 1) {
            cursor_pos_.line++;
            cursor_pos_.column = 0;
        }
        cursor_dirty_ = true;
        selection_->ClearSelection();
        selection_dirty_ = true;
        return;
    }

    if (key == Rml::Input::KI_UP) {
        if (cursor_pos_.line > 0) {
            cursor_pos_.line--;
            int line_len = static_cast<int>(buffer_->GetLine(cursor_pos_.line).length());
            cursor_pos_.column = std::min(cursor_pos_.column, line_len);
        }
        cursor_dirty_ = true;
        selection_->ClearSelection();
        selection_dirty_ = true;
        return;
    }

    if (key == Rml::Input::KI_DOWN) {
        if (cursor_pos_.line < buffer_->GetLineCount() - 1) {
            cursor_pos_.line++;
            int line_len = static_cast<int>(buffer_->GetLine(cursor_pos_.line).length());
            cursor_pos_.column = std::min(cursor_pos_.column, line_len);
        }
        cursor_dirty_ = true;
        selection_->ClearSelection();
        selection_dirty_ = true;
        return;
    }

    // Handle Home
    if (key == Rml::Input::KI_HOME) {
        cursor_pos_.column = 0;
        cursor_dirty_ = true;
        selection_->ClearSelection();
        selection_dirty_ = true;
        return;
    }

    // Handle End
    if (key == Rml::Input::KI_END) {
        cursor_pos_.column = static_cast<int>(buffer_->GetLine(cursor_pos_.line).length());
        cursor_dirty_ = true;
        selection_->ClearSelection();
        selection_dirty_ = true;
        return;
    }
}

void ElementTextEditor::OnTextInput(const std::string& text) {
    if (!editable_ || text.empty()) {
        return;
    }

    // Delete selection if any
    if (selection_->HasSelection()) {
        TextBuffer::Position start, end;
        selection_->GetSelectionRange(start, end);
        buffer_->DeleteRange(start, end);
        cursor_pos_ = start;
        selection_->ClearSelection();
    }

    // Insert text at cursor
    for (char c : text) {
        if (c >= 32 || c == '\t') {  // Printable characters and tab
            buffer_->InsertChar(cursor_pos_, c);
            cursor_pos_.column++;
        }
    }

    // Clear tokens when text changes - they'll be updated by Lua shortly
    tokens_.clear();

    // Dispatch content change event for re-highlighting
    DispatchContentChangeEvent();

    modified_ = true;
    cursor_dirty_ = true;
    selection_dirty_ = true;
    DirtyLayout();
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
