#include "ElementCanvas.h"
#include "Logger.h"
#include <RmlUi/Core/Context.h>
#include <RmlUi/Core/SystemInterface.h>
#include <RmlUi/Lua/Interpreter.h>
#include <glad/glad.h>
#include <cmath>

#define NANOVG_GL3_IMPLEMENTATION
#include <nanovg_gl.h>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

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

    // Load default font (Roboto) for text rendering
    int font_handle = nvgCreateFont(nvg_context_, "roboto", "ui/fonts/roboto-static/Roboto-Regular.ttf");
    if (font_handle == -1) {
        LOG_WARN("Failed to load font 'roboto' from ui/fonts/roboto-static/Roboto-Regular.ttf");
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

        // Register for keyboard events
        AddEventListener(Rml::EventId::Keydown, this);
        AddEventListener(Rml::EventId::Keyup, this);

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
        RemoveEventListener(Rml::EventId::Keydown, this);
        RemoveEventListener(Rml::EventId::Keyup, this);

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
    else if (event == Rml::EventId::Keydown) {
        Rml::Input::KeyIdentifier key = static_cast<Rml::Input::KeyIdentifier>(
            event.GetParameter<int>("key_identifier", 0));

        // Map RmlUI key identifiers to string names for Lua
        Rml::String key_name;
        switch (key) {
            case Rml::Input::KI_LEFT:   key_name = "left"; break;
            case Rml::Input::KI_RIGHT:  key_name = "right"; break;
            case Rml::Input::KI_UP:     key_name = "up"; break;
            case Rml::Input::KI_DOWN:   key_name = "down"; break;
            case Rml::Input::KI_SPACE:  key_name = "space"; break;
            case Rml::Input::KI_RETURN: key_name = "return"; break;
            case Rml::Input::KI_ESCAPE: key_name = "escape"; break;
            case Rml::Input::KI_Z:      key_name = "z"; break;
            case Rml::Input::KI_X:      key_name = "x"; break;
            case Rml::Input::KI_C:      key_name = "c"; break;
            case Rml::Input::KI_P:      key_name = "p"; break;
            default: break;
        }

        if (!key_name.empty()) {
            CallLuaKeyHandler(key_name, true);
        }
    }
    else if (event == Rml::EventId::Keyup) {
        Rml::Input::KeyIdentifier key = static_cast<Rml::Input::KeyIdentifier>(
            event.GetParameter<int>("key_identifier", 0));

        Rml::String key_name;
        switch (key) {
            case Rml::Input::KI_LEFT:   key_name = "left"; break;
            case Rml::Input::KI_RIGHT:  key_name = "right"; break;
            case Rml::Input::KI_UP:     key_name = "up"; break;
            case Rml::Input::KI_DOWN:   key_name = "down"; break;
            case Rml::Input::KI_SPACE:  key_name = "space"; break;
            case Rml::Input::KI_RETURN: key_name = "return"; break;
            case Rml::Input::KI_ESCAPE: key_name = "escape"; break;
            case Rml::Input::KI_Z:      key_name = "z"; break;
            case Rml::Input::KI_X:      key_name = "x"; break;
            case Rml::Input::KI_C:      key_name = "c"; break;
            case Rml::Input::KI_P:      key_name = "p"; break;
            default: break;
        }

        if (!key_name.empty()) {
            CallLuaKeyHandler(key_name, false);
        }
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

    // Check if there's a Lua render function specified
    const Rml::Variant* render_attr = GetAttribute("renderfunction");

    if (render_attr) {
        Rml::String render_func = render_attr->Get<Rml::String>();
        if (!render_func.empty()) {
            // Call Lua render function
            CallLuaRenderFunction(x, y, w, h, time_);
        }
    } 

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

void ElementCanvas::CallLuaRenderFunction(float x, float y, float w, float h, float t)
{
    // Get the RmlUI Lua state
    lua_State* L = Rml::Lua::Interpreter::GetLuaState();
    if (!L) {
        LOG_ERROR("ElementCanvas: RmlUI Lua state not available");
        return;
    }

    // Get the renderfunction attribute
    const Rml::Variant* render_attr = GetAttribute("renderfunction");
    if (!render_attr) {
        return;
    }

    Rml::String render_func = render_attr->Get<Rml::String>();
    if (render_func.empty()) {
        return;
    }

    // Get the Lua function from global scope
    lua_getglobal(L, render_func.c_str());

    // Check if it's a function
    if (!lua_isfunction(L, -1)) {
        LOG_WARN("ElementCanvas: renderfunction attribute '{}' is not a valid Lua function", render_func);
        lua_pop(L, 1);
        return;
    }

    // Push arguments: nvg (light userdata), x, y, w, h, time
    lua_pushlightuserdata(L, nvg_context_);
    lua_pushnumber(L, x);
    lua_pushnumber(L, y);
    lua_pushnumber(L, w);
    lua_pushnumber(L, h);
    lua_pushnumber(L, t);

    // Call the function with 6 arguments, 0 return values
    if (lua_pcall(L, 6, 0, 0) != LUA_OK) {
        const char* error = lua_tostring(L, -1);
        LOG_ERROR("ElementCanvas: Error calling Lua render function '{}': {}", render_func, error);
        lua_pop(L, 1);
    }
}

void ElementCanvas::CallLuaKeyHandler(const Rml::String& key_name, bool key_down)
{
    // Get the RmlUI Lua state
    lua_State* L = Rml::Lua::Interpreter::GetLuaState();
    if (!L) {
        LOG_ERROR("ElementCanvas: RmlUI Lua state not available");
        return;
    }

    // Get the keyhandler attribute
    const Rml::Variant* handler_attr = GetAttribute("keyhandler");
    if (!handler_attr) {
        return;
    }

    Rml::String handler_func = handler_attr->Get<Rml::String>();
    if (handler_func.empty()) {
        return;
    }

    // Get the Lua function from global scope
    lua_getglobal(L, handler_func.c_str());

    // Check if it's a function
    if (!lua_isfunction(L, -1)) {
        LOG_WARN("ElementCanvas: keyhandler attribute '{}' is not a valid Lua function", handler_func);
        lua_pop(L, 1);
        return;
    }

    // Push arguments: key_name (string), key_down (boolean)
    lua_pushstring(L, key_name.c_str());
    lua_pushboolean(L, key_down);

    // Call the function with 2 arguments, 0 return values
    if (lua_pcall(L, 2, 0, 0) != LUA_OK) {
        const char* error = lua_tostring(L, -1);
        LOG_ERROR("ElementCanvas: Error calling Lua key handler '{}': {}", handler_func, error);
        lua_pop(L, 1);
    }
}
