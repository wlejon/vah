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
        CallLuaMouseHandler(true);
    }
    else if (event == Rml::EventId::Mouseup) {
        mouse_down_ = false;
        LOG_INFO("Canvas mouse up at ({}, {})", mouse_pos_.x, mouse_pos_.y);
        CallLuaMouseHandler(false);
    }
    else if (event == Rml::EventId::Keydown) {
        Rml::Input::KeyIdentifier key = static_cast<Rml::Input::KeyIdentifier>(
            event.GetParameter<int>("key_identifier", 0));

        Rml::String key_name = MapKeyToString(key);
        if (!key_name.empty()) {
            CallLuaKeyHandler(key_name, true);
        }
    }
    else if (event == Rml::EventId::Keyup) {
        Rml::Input::KeyIdentifier key = static_cast<Rml::Input::KeyIdentifier>(
            event.GetParameter<int>("key_identifier", 0));

        Rml::String key_name = MapKeyToString(key);
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

Rml::String ElementCanvas::MapKeyToString(Rml::Input::KeyIdentifier key)
{
    // Map RmlUI key identifiers to string names for Lua
    switch (key) {
        // Arrow keys
        case Rml::Input::KI_LEFT:   return "left";
        case Rml::Input::KI_RIGHT:  return "right";
        case Rml::Input::KI_UP:     return "up";
        case Rml::Input::KI_DOWN:   return "down";

        // Special keys
        case Rml::Input::KI_SPACE:  return "space";
        case Rml::Input::KI_RETURN: return "return";
        case Rml::Input::KI_ESCAPE: return "escape";
        case Rml::Input::KI_BACK:   return "backspace";
        case Rml::Input::KI_TAB:    return "tab";
        case Rml::Input::KI_DELETE: return "delete";
        case Rml::Input::KI_INSERT: return "insert";
        case Rml::Input::KI_HOME:   return "home";
        case Rml::Input::KI_END:    return "end";
        case Rml::Input::KI_PRIOR:  return "pageup";
        case Rml::Input::KI_NEXT:   return "pagedown";

        // Letters A-Z
        case Rml::Input::KI_A: return "a";
        case Rml::Input::KI_B: return "b";
        case Rml::Input::KI_C: return "c";
        case Rml::Input::KI_D: return "d";
        case Rml::Input::KI_E: return "e";
        case Rml::Input::KI_F: return "f";
        case Rml::Input::KI_G: return "g";
        case Rml::Input::KI_H: return "h";
        case Rml::Input::KI_I: return "i";
        case Rml::Input::KI_J: return "j";
        case Rml::Input::KI_K: return "k";
        case Rml::Input::KI_L: return "l";
        case Rml::Input::KI_M: return "m";
        case Rml::Input::KI_N: return "n";
        case Rml::Input::KI_O: return "o";
        case Rml::Input::KI_P: return "p";
        case Rml::Input::KI_Q: return "q";
        case Rml::Input::KI_R: return "r";
        case Rml::Input::KI_S: return "s";
        case Rml::Input::KI_T: return "t";
        case Rml::Input::KI_U: return "u";
        case Rml::Input::KI_V: return "v";
        case Rml::Input::KI_W: return "w";
        case Rml::Input::KI_X: return "x";
        case Rml::Input::KI_Y: return "y";
        case Rml::Input::KI_Z: return "z";

        // Numbers 0-9
        case Rml::Input::KI_0: return "0";
        case Rml::Input::KI_1: return "1";
        case Rml::Input::KI_2: return "2";
        case Rml::Input::KI_3: return "3";
        case Rml::Input::KI_4: return "4";
        case Rml::Input::KI_5: return "5";
        case Rml::Input::KI_6: return "6";
        case Rml::Input::KI_7: return "7";
        case Rml::Input::KI_8: return "8";
        case Rml::Input::KI_9: return "9";

        // Numpad
        case Rml::Input::KI_NUMPAD0: return "numpad0";
        case Rml::Input::KI_NUMPAD1: return "numpad1";
        case Rml::Input::KI_NUMPAD2: return "numpad2";
        case Rml::Input::KI_NUMPAD3: return "numpad3";
        case Rml::Input::KI_NUMPAD4: return "numpad4";
        case Rml::Input::KI_NUMPAD5: return "numpad5";
        case Rml::Input::KI_NUMPAD6: return "numpad6";
        case Rml::Input::KI_NUMPAD7: return "numpad7";
        case Rml::Input::KI_NUMPAD8: return "numpad8";
        case Rml::Input::KI_NUMPAD9: return "numpad9";
        case Rml::Input::KI_NUMPADENTER: return "numpadenter";
        case Rml::Input::KI_MULTIPLY: return "multiply";
        case Rml::Input::KI_ADD: return "add";
        case Rml::Input::KI_SUBTRACT: return "subtract";
        case Rml::Input::KI_DECIMAL: return "decimal";
        case Rml::Input::KI_DIVIDE: return "divide";

        // Function keys
        case Rml::Input::KI_F1:  return "f1";
        case Rml::Input::KI_F2:  return "f2";
        case Rml::Input::KI_F3:  return "f3";
        case Rml::Input::KI_F4:  return "f4";
        case Rml::Input::KI_F5:  return "f5";
        case Rml::Input::KI_F6:  return "f6";
        case Rml::Input::KI_F7:  return "f7";
        case Rml::Input::KI_F8:  return "f8";
        case Rml::Input::KI_F9:  return "f9";
        case Rml::Input::KI_F10: return "f10";
        case Rml::Input::KI_F11: return "f11";
        case Rml::Input::KI_F12: return "f12";

        // Punctuation
        case Rml::Input::KI_OEM_1:      return "semicolon";
        case Rml::Input::KI_OEM_PLUS:   return "equals";
        case Rml::Input::KI_OEM_COMMA:  return "comma";
        case Rml::Input::KI_OEM_MINUS:  return "minus";
        case Rml::Input::KI_OEM_PERIOD: return "period";
        case Rml::Input::KI_OEM_2:      return "slash";
        case Rml::Input::KI_OEM_3:      return "backquote";
        case Rml::Input::KI_OEM_4:      return "leftbracket";
        case Rml::Input::KI_OEM_5:      return "backslash";
        case Rml::Input::KI_OEM_6:      return "rightbracket";
        case Rml::Input::KI_OEM_7:      return "quote";

        default: return "";
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

void ElementCanvas::CallLuaMouseHandler(bool mouse_down)
{
    // Get the RmlUI Lua state
    lua_State* L = Rml::Lua::Interpreter::GetLuaState();
    if (!L) {
        LOG_ERROR("ElementCanvas: RmlUI Lua state not available");
        return;
    }

    // Get the mousehandler attribute
    const Rml::Variant* handler_attr = GetAttribute("mousehandler");
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
        LOG_WARN("ElementCanvas: mousehandler attribute '{}' is not a valid Lua function", handler_func);
        lua_pop(L, 1);
        return;
    }

    // Push arguments: mouse_down (boolean)
    lua_pushboolean(L, mouse_down);

    // Call the function with 1 argument, 0 return values
    if (lua_pcall(L, 1, 0, 0) != LUA_OK) {
        const char* error = lua_tostring(L, -1);
        LOG_ERROR("ElementCanvas: Error calling Lua mouse handler '{}': {}", handler_func, error);
        lua_pop(L, 1);
    }
}
