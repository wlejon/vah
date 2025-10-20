#include "ElementTextEditor.h"
#include "Logger.h"
#include <RmlUi/Core/Context.h>
#include <RmlUi/Core/SystemInterface.h>
#include <RmlUi/Core/RenderManager.h>
#include <RmlUi/Core/FontEngineInterface.h>
#include <RmlUi/Core/Mesh.h>
#include <SDL2/SDL.h>
#include <map>

ElementTextEditor::ElementTextEditor(const Rml::String& tag)
    : Rml::Element(tag)
    , buffer_(std::make_unique<TextBuffer>())
    , layout_(std::make_unique<TextLayout>())
    , selection_(std::make_unique<SelectionManager>())
    , highlighter_(std::make_unique<SyntaxHighlighter>())
    , text_dirty_(true)
    , selection_dirty_(false)
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
}

void ElementTextEditor::SetText(const std::string& text) {
    buffer_->SetText(text);
    text_dirty_ = true;
    highlighter_->InvalidateCache();
    DirtyLayout();
}

std::string ElementTextEditor::GetText() const {
    return buffer_->GetText();
}

std::string ElementTextEditor::GetSelectedText() const {
    return selection_->ExtractText(*buffer_);
}

void ElementTextEditor::SetSyntaxHighlighter(const std::string& function_name) {
    highlighter_->SetHighlightFunction(function_name);
    text_dirty_ = true;
    DirtyLayout();
}

void ElementTextEditor::OnUpdate() {
    if (text_dirty_ || selection_dirty_) {
        GenerateGeometry();
    }
}

void ElementTextEditor::OnRender() {
    // Get absolute position
    Rml::Vector2f absolute_offset = GetAbsoluteOffset(Rml::BoxArea::Content);

    // Render selection geometry first (behind text)
    if (selection_geometry_) {
        selection_geometry_.Render(absolute_offset);
    }

    // Render text geometries
    for (auto& text_geom : text_geometries_) {
        if (text_geom.geometry) {
            text_geom.geometry.Render(absolute_offset, text_geom.texture);
        }
    }
}

void ElementTextEditor::GenerateGeometry() {
    if (text_dirty_) {
        GenerateTextGeometry();
        text_dirty_ = false;
    }

    if (selection_dirty_) {
        GenerateSelectionGeometry();
        selection_dirty_ = false;
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
        LOG_ERROR("ElementTextEditor: Failed to get font handle");
        return;
    }

    // Get syntax highlighting tokens
    std::string text = buffer_->GetText();
    std::vector<SyntaxHighlighter::Token> tokens = highlighter_->GetTokens(text);

    // Build token map for quick lookup: map[line] -> list of tokens on that line
    std::map<int, std::vector<SyntaxHighlighter::Token>> token_map;
    for (const auto& token : tokens) {
        token_map[token.line].push_back(token);
    }

    float line_height = layout_->GetLineHeight();
    int line_count = buffer_->GetLineCount();

    // Get font metrics to calculate baseline offset
    const Rml::FontMetrics& metrics = font_engine->GetFontMetrics(font_handle);
    float baseline_offset = metrics.ascent;

    // We'll generate text line by line using FontEngineInterface::GenerateString
    // This outputs TexturedMeshList which we need to convert to Geometry
    Rml::String language = "en";
    Rml::TextShapingContext shaping_context{language};

    float y = 0.0f;
    for (int line_num = 0; line_num < line_count; ++line_num) {
        std::string line = buffer_->GetLine(line_num);

        if (line.empty()) {
            y += line_height;
            continue;  // Skip empty lines
        }

        // Get tokens for this line
        auto tokens_it = token_map.find(line_num);

        if (tokens_it != token_map.end() && !tokens_it->second.empty()) {
            // Line has syntax highlighting tokens - render each token separately
            const auto& line_tokens = tokens_it->second;

            for (const auto& token : line_tokens) {
                // Extract substring for this token
                int start_col = token.start_col;
                int end_col = token.end_col;

                if (start_col < 0 || start_col >= static_cast<int>(line.size())) continue;
                if (end_col <= start_col) continue;

                int length = std::min(end_col - start_col, static_cast<int>(line.size()) - start_col);
                std::string token_text = line.substr(start_col, length);

                if (token_text.empty()) continue;

                // Calculate position for this token
                float char_width = layout_->GetCharWidth();
                float x = static_cast<float>(start_col) * char_width;

                Rml::ColourbPremultiplied premult_color = token.color.ToPremultiplied();
                Rml::TexturedMeshList mesh_list;
                // Position Y is the baseline, so add ascent to move from line top to baseline
                Rml::Vector2f position(x, y + baseline_offset);
                Rml::FontEffectsHandle effects_handle = 0;

                font_engine->GenerateString(
                    *render_manager,
                    font_handle,
                    effects_handle,
                    token_text,
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
        } else {
            // No syntax highlighting - render entire line in white
            Rml::Colourb color(255, 255, 255, 255);
            Rml::ColourbPremultiplied premult_color = color.ToPremultiplied();

            Rml::TexturedMeshList mesh_list;
            // Position Y is the baseline, so add ascent to move from line top to baseline
            Rml::Vector2f position(0.0f, y + baseline_offset);
            Rml::FontEffectsHandle effects_handle = 0;

            font_engine->GenerateString(
                *render_manager,
                font_handle,
                effects_handle,
                line,
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
    // Handle Ctrl+C for copy
    if (key == Rml::Input::KI_C && (modifiers & Rml::Input::KM_CTRL)) {
        std::string selected = GetSelectedText();
        if (!selected.empty()) {
            SDL_SetClipboardText(selected.c_str());
        }
    }
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
