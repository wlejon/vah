#include "TextEditorRenderer.h"
#include "Logger.h"
#include <RmlUi/Core/FontEngineInterface.h>
#include <RmlUi/Core/Mesh.h>
#include <map>
#include <algorithm>

TextEditorRenderer::TextEditorRenderer(
    TextBuffer& buffer,
    TextLayout& layout,
    SelectionManager& selection,
    TextEditorConfig& config
)
    : buffer_(buffer)
    , layout_(layout)
    , selection_(selection)
    , config_(config)
    , selection_dirty_(false)
    , cursor_dirty_(false)
    , font_ready_(false)
    , cursor_pos_(0, 0)
{
}

TextEditorRenderer::~TextEditorRenderer() {
}

void TextEditorRenderer::SetTokens(const DynamicTable& tokens) {
    tokens_ = tokens;
    LOG_INFO("TextEditorRenderer: Received {} syntax tokens", tokens.size());
}

void TextEditorRenderer::GenerateGeometry(Rml::RenderManager* render_manager, bool editable, bool cursor_visible) {
    if (!render_manager) {
        return;
    }

    // Retry font initialization if not ready
    if (!font_ready_) {
        layout_.SetFont("jetbrains mono", 14);
        // Check if it succeeded by seeing if we have valid metrics
        if (layout_.GetCharWidth() > 0.0f && layout_.GetLineHeight() > 0.0f) {
            font_ready_ = true;
            LOG_INFO("TextEditorRenderer: Font ready");
        }
    }

    // Always regenerate text geometry to prevent garbled rendering
    GenerateTextGeometry(render_manager);

    if (selection_dirty_) {
        GenerateSelectionGeometry(render_manager);
        selection_dirty_ = false;
    }

    if (cursor_dirty_ && editable) {
        GenerateCursorGeometry(render_manager);
        cursor_dirty_ = false;
    }
}

void TextEditorRenderer::RenderAll(const Rml::Vector2f& absolute_offset, bool editable, bool cursor_visible) {
    // Render selection geometry first (behind text)
    if (selection_geometry_) {
        selection_geometry_.Render(absolute_offset);
    }

    // Render cursor (behind text but above selection)
    if (editable && cursor_visible && cursor_geometry_) {
        cursor_geometry_.Render(absolute_offset);
    }

    // Render text geometries
    for (auto& text_geom : text_geometries_) {
        if (text_geom.geometry) {
            text_geom.geometry.Render(absolute_offset, text_geom.texture);
        }
    }
}

void TextEditorRenderer::GenerateTextGeometry(Rml::RenderManager* render_manager) {
    // Clear existing text geometries
    text_geometries_.clear();

    auto font_engine = Rml::GetFontEngineInterface();
    if (!font_engine) {
        LOG_ERROR("TextEditorRenderer: Font engine not available");
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
        LOG_WARN("TextEditorRenderer: Font metrics not ready (ascent={}, descent={}, line_spacing={}), retrying next frame",
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

    float line_height = layout_.GetLineHeight();
    int line_count = buffer_.GetLineCount();
    float baseline_offset = metrics.ascent;

    // We'll generate text line by line using FontEngineInterface::GenerateString
    // This outputs TexturedMeshList which we need to convert to Geometry
    Rml::String language = "en";
    Rml::TextShapingContext shaping_context{language};

    // Default text color from config
    Rml::Colourb default_color = config_.default_text_color;

    float y = 0.0f;
    for (int line_num = 0; line_num < line_count; ++line_num) {
        std::string line = buffer_.GetLine(line_num);

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
        float char_width = layout_.GetCharWidth();
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

void TextEditorRenderer::GenerateSelectionGeometry(Rml::RenderManager* render_manager) {
    // Release old selection geometry
    if (selection_geometry_) {
        selection_geometry_.Release();
    }

    if (!selection_.HasSelection()) {
        return;
    }

    // Get selection range
    TextBuffer::Position start, end;
    selection_.GetSelectionRange(start, end);

    // Clamp to buffer bounds
    start = buffer_.ClampPosition(start);
    end = buffer_.ClampPosition(end);

    // Build mesh for selection quads
    Rml::Mesh mesh;
    Rml::ColourbPremultiplied selection_color = config_.selection_color.ToPremultiplied();

    float line_height = layout_.GetLineHeight();
    float char_width = layout_.GetCharWidth();

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
        std::string first_line = buffer_.GetLine(start.line);
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
            std::string line = buffer_.GetLine(line_num);
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

void TextEditorRenderer::GenerateCursorGeometry(Rml::RenderManager* render_manager) {
    // Release old cursor geometry
    if (cursor_geometry_) {
        cursor_geometry_.Release();
    }

    // Clamp cursor position to buffer bounds
    cursor_pos_ = buffer_.ClampPosition(cursor_pos_);

    // Build cursor quad (vertical line)
    Rml::Mesh mesh;
    Rml::ColourbPremultiplied cursor_color = config_.cursor_color.ToPremultiplied();

    float line_height = layout_.GetLineHeight();
    float char_width = layout_.GetCharWidth();
    float cursor_width = config_.cursor_width;

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
