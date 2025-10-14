#include "ElementCanvas.h"
#include "Logger.h"
#include <RmlUi/Core/Context.h>
#include <RmlUi/Core/SystemInterface.h>
#include <glad/glad.h>
#include <cmath>

#define NANOVG_GL3_IMPLEMENTATION
#include <nanovg_gl.h>

ElementCanvas::ElementCanvas(const Rml::String& tag)
    : Rml::Element(tag)
    , nvg_context_(nullptr)
    , time_(0.0f)
    , mouse_pos_(0.0f, 0.0f)
    , mouse_down_(false)
{
    LOG_INFO("ElementCanvas created");
}

ElementCanvas::~ElementCanvas()
{
    ShutdownNanoVG();
    LOG_INFO("ElementCanvas destroyed");
}

void ElementCanvas::InitializeNanoVG()
{
    if (nvg_context_) {
        return; // Already initialized
    }

    // Create NanoVG context with OpenGL3 backend
    // NVG_ANTIALIAS | NVG_STENCIL_STROKES for high quality rendering
    nvg_context_ = nvgCreateGL3(NVG_ANTIALIAS | NVG_STENCIL_STROKES);

    if (!nvg_context_) {
        LOG_ERROR("Failed to create NanoVG context");
        return;
    }

    LOG_INFO("NanoVG context created successfully");
}

void ElementCanvas::ShutdownNanoVG()
{
    if (nvg_context_) {
        nvgDeleteGL3(nvg_context_);
        nvg_context_ = nullptr;
        LOG_INFO("NanoVG context destroyed");
    }
}

void ElementCanvas::OnChildAdd(Rml::Element* element)
{
    Rml::Element::OnChildAdd(element);

    // Initialize NanoVG when we're added to the document
    if (element == this) {
        InitializeNanoVG();

        // Register for mouse events
        AddEventListener(Rml::EventId::Mousemove, this);
        AddEventListener(Rml::EventId::Mousedown, this);
        AddEventListener(Rml::EventId::Mouseup, this);

        LOG_INFO("ElementCanvas added to document tree");
    }
}

void ElementCanvas::OnChildRemove(Rml::Element* element)
{
    Rml::Element::OnChildRemove(element);

    if (element == this) {
        // Unregister event listeners
        RemoveEventListener(Rml::EventId::Mousemove, this);
        RemoveEventListener(Rml::EventId::Mousedown, this);
        RemoveEventListener(Rml::EventId::Mouseup, this);

        LOG_INFO("ElementCanvas removed from document tree");
    }
}

void ElementCanvas::ProcessEvent(Rml::Event& event)
{
    if (event == Rml::EventId::Mousemove) {
        mouse_pos_.x = event.GetParameter<float>("mouse_x", 0.0f);
        mouse_pos_.y = event.GetParameter<float>("mouse_y", 0.0f);
    }
    else if (event == Rml::EventId::Mousedown) {
        mouse_down_ = true;
        LOG_INFO("Canvas mouse down at ({}, {})", mouse_pos_.x, mouse_pos_.y);
    }
    else if (event == Rml::EventId::Mouseup) {
        mouse_down_ = false;
        LOG_INFO("Canvas mouse up at ({}, {})", mouse_pos_.x, mouse_pos_.y);
    }
}

void ElementCanvas::OnUpdate()
{
    // Update animation time
    if (auto* sys = Rml::GetSystemInterface()) {
        time_ = static_cast<float>(sys->GetElapsedTime());
    }
}

void ElementCanvas::OnRender()
{
    if (!nvg_context_) {
        return;
    }

    // Get the element's absolute position and size
    Rml::Vector2f absolute_offset = GetAbsoluteOffset(Rml::BoxArea::Content);
    const Rml::Box& box = GetBox();
    Rml::Vector2f size = box.GetSize(Rml::BoxArea::Content);

    float x = absolute_offset.x;
    float y = absolute_offset.y;
    float w = size.x;
    float h = size.y;

    // Save OpenGL state before NanoVG rendering
    GLint viewport[4];
    glGetIntegerv(GL_VIEWPORT, viewport);

    GLint scissor_box[4];
    glGetIntegerv(GL_SCISSOR_BOX, scissor_box);

    // Save more GL state that NanoVG modifies
    GLboolean blend_enabled = glIsEnabled(GL_BLEND);
    GLboolean cull_enabled = glIsEnabled(GL_CULL_FACE);
    GLboolean depth_enabled = glIsEnabled(GL_DEPTH_TEST);
    GLboolean stencil_enabled = glIsEnabled(GL_STENCIL_TEST);
    GLboolean scissor_enabled = glIsEnabled(GL_SCISSOR_TEST);

    GLint blend_src, blend_dst;
    glGetIntegerv(GL_BLEND_SRC_ALPHA, &blend_src);
    glGetIntegerv(GL_BLEND_DST_ALPHA, &blend_dst);

    GLint stencil_func, stencil_ref, stencil_mask;
    glGetIntegerv(GL_STENCIL_FUNC, &stencil_func);
    glGetIntegerv(GL_STENCIL_REF, &stencil_ref);
    glGetIntegerv(GL_STENCIL_VALUE_MASK, &stencil_mask);

    GLuint current_program;
    glGetIntegerv(GL_CURRENT_PROGRAM, reinterpret_cast<GLint*>(&current_program));

    // Disable scissor test for NanoVG - RmlUi's scissor might be clipping our content
    glDisable(GL_SCISSOR_TEST);

    // Clear stencil buffer before NanoVG rendering
    // NanoVG uses the stencil buffer for antialiasing and strokes
    glClearStencil(0);
    glClear(GL_STENCIL_BUFFER_BIT);

    // Ensure stencil test is enabled for NanoVG
    glEnable(GL_STENCIL_TEST);

    // Begin NanoVG frame
    nvgBeginFrame(nvg_context_, static_cast<float>(viewport[2]), static_cast<float>(viewport[3]), 1.0f);

    LOG_INFO("Canvas render at ({}, {}) size {}x{}, viewport: {}x{}",
             x, y, w, h, viewport[2], viewport[3]);

    // Render our demo content
    RenderDemo(nvg_context_, x, y, w, h, time_);

    // End NanoVG frame (this actually submits the draw calls)
    nvgEndFrame(nvg_context_);

    // Restore OpenGL state for RmlUi
    glViewport(viewport[0], viewport[1], viewport[2], viewport[3]);
    glScissor(scissor_box[0], scissor_box[1], scissor_box[2], scissor_box[3]);
    glUseProgram(current_program);

    if (blend_enabled) glEnable(GL_BLEND); else glDisable(GL_BLEND);
    if (cull_enabled) glEnable(GL_CULL_FACE); else glDisable(GL_CULL_FACE);
    if (depth_enabled) glEnable(GL_DEPTH_TEST); else glDisable(GL_DEPTH_TEST);
    if (stencil_enabled) glEnable(GL_STENCIL_TEST); else glDisable(GL_STENCIL_TEST);
    if (scissor_enabled) glEnable(GL_SCISSOR_TEST); else glDisable(GL_SCISSOR_TEST);

    glBlendFunc(blend_src, blend_dst);
    glStencilFunc(stencil_func, stencil_ref, stencil_mask);
}

void ElementCanvas::OnResize()
{
    const Rml::Box& box = GetBox();
    Rml::Vector2f size = box.GetSize(Rml::BoxArea::Content);
    LOG_INFO("Canvas resized to {}x{}", size.x, size.y);
}

void ElementCanvas::RenderDemo(NVGcontext* vg, float x, float y, float w, float h, float t)
{
    // Clear canvas background
    nvgBeginPath(vg);
    nvgRect(vg, x, y, w, h);
    nvgFillColor(vg, nvgRGBA(28, 30, 34, 255));
    nvgFill(vg);

    // Draw a grid (simulating a canvas/node editor background)
    float grid_size = 20.0f;
    for (float gx = x; gx < x + w; gx += grid_size) {
        nvgBeginPath(vg);
        nvgMoveTo(vg, gx, y);
        nvgLineTo(vg, gx, y + h);
        nvgStrokeColor(vg, nvgRGBA(60, 60, 60, 100));
        nvgStrokeWidth(vg, 1.0f);
        nvgStroke(vg);
    }
    for (float gy = y; gy < y + h; gy += grid_size) {
        nvgBeginPath(vg);
        nvgMoveTo(vg, x, gy);
        nvgLineTo(vg, x + w, gy);
        nvgStrokeColor(vg, nvgRGBA(60, 60, 60, 100));
        nvgStrokeWidth(vg, 1.0f);
        nvgStroke(vg);
    }

    // Draw an animated circle (simulating a node)
    float cx = x + w * 0.3f + std::sin(t) * 50.0f;
    float cy = y + h * 0.3f + std::cos(t * 0.7f) * 30.0f;
    float radius = 40.0f;

    // Node shadow
    NVGpaint shadowPaint = nvgRadialGradient(vg, cx, cy + 2, radius - 2, radius + 5,
        nvgRGBA(0, 0, 0, 128), nvgRGBA(0, 0, 0, 0));
    nvgBeginPath(vg);
    nvgCircle(vg, cx, cy + 2, radius + 5);
    nvgFillPaint(vg, shadowPaint);
    nvgFill(vg);

    // Node body
    nvgBeginPath(vg);
    nvgCircle(vg, cx, cy, radius);
    nvgPathWinding(vg, NVG_CCW);  // Counter-clockwise winding
    nvgFillColor(vg, nvgRGBA(80, 120, 255, 255));
    nvgFill(vg);

    // Node border
    nvgBeginPath(vg);
    nvgCircle(vg, cx, cy, radius);
    nvgStrokeWidth(vg, 2.0f);
    nvgStrokeColor(vg, nvgRGBA(100, 140, 255, 255));
    nvgStroke(vg);

    // Draw another static node
    float cx2 = x + w * 0.7f;
    float cy2 = y + h * 0.5f;

    nvgBeginPath(vg);
    nvgRoundedRect(vg, cx2 - 60, cy2 - 40, 120, 80, 8);
    nvgFillColor(vg, nvgRGBA(40, 40, 45, 255));
    nvgFill(vg);

    nvgBeginPath(vg);
    nvgRoundedRect(vg, cx2 - 60, cy2 - 40, 120, 80, 8);
    nvgStrokeWidth(vg, 2.0f);
    nvgStrokeColor(vg, nvgRGBA(255, 176, 50, 255));
    nvgStroke(vg);

    // Draw a bezier curve connecting the nodes (simulating a link)
    nvgBeginPath(vg);
    nvgMoveTo(vg, cx + radius, cy);
    nvgBezierTo(vg, cx + radius + 100, cy, cx2 - 60 - 100, cy2, cx2 - 60, cy2);
    nvgStrokeWidth(vg, 3.0f);
    nvgStrokeColor(vg, nvgRGBA(100, 200, 100, 255));
    nvgStroke(vg);

    // Draw mouse cursor position indicator (if mouse is over canvas)
    if (mouse_pos_.x > x && mouse_pos_.x < x + w &&
        mouse_pos_.y > y && mouse_pos_.y < y + h) {

        nvgBeginPath(vg);
        nvgCircle(vg, mouse_pos_.x, mouse_pos_.y, mouse_down_ ? 8.0f : 5.0f);
        nvgFillColor(vg, mouse_down_ ? nvgRGBA(255, 100, 100, 200) : nvgRGBA(255, 255, 255, 150));
        nvgFill(vg);
    }

    // Draw text label
    nvgFontSize(vg, 18.0f);
    nvgFontFace(vg, "sans");
    nvgTextAlign(vg, NVG_ALIGN_LEFT | NVG_ALIGN_TOP);
    nvgFillColor(vg, nvgRGBA(220, 220, 220, 255));
    nvgText(vg, x + 10, y + 10, "NanoVG Canvas Test", nullptr);

    nvgFontSize(vg, 14.0f);
    nvgFillColor(vg, nvgRGBA(180, 180, 180, 255));
    nvgText(vg, x + 10, y + 35, "Foundation for imgui-node-editor port", nullptr);
}
