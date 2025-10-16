#pragma once

#include <RmlUi/Core/Element.h>
#include <RmlUi/Core/EventListener.h>
#include <RmlUi/Core/Input.h>
#include <nanovg.h>

extern "C" {
#include <lua.h>
}

/**
 * ElementCanvas - A custom RmlUi element that provides a NanoVG drawing surface.
 *
 * This element exposes NanoVG 2D drawing primitives to Lua scripts in RML files.
 * When a 'renderfunction' attribute is specified, the element will call that Lua function
 * each frame to perform custom rendering.
 *
 * Usage in RML:
 *   <canvas id="my-canvas" renderfunction="myRenderFunction" style="width: 800px; height: 600px;" />
 *
 * The Lua render function receives:
 *   function myRenderFunction(nvg, x, y, w, h, time)
 *     -- nvg: NanoVG context (light userdata)
 *     -- x, y: absolute position of canvas
 *     -- w, h: size of canvas
 *     -- time: elapsed time in seconds
 *   end
 */
class ElementCanvas : public Rml::Element, public Rml::EventListener {
public:
    ElementCanvas(const Rml::String& tag);
    virtual ~ElementCanvas();

    // Called when element is added to the document tree
    void OnChildAdd(Rml::Element* element) override;

    // Called when element is removed from the document tree
    void OnChildRemove(Rml::Element* element) override;

    // Handle mouse and keyboard events for interaction
    void ProcessEvent(Rml::Event& event) override;

protected:
    // Called every frame to update state
    void OnUpdate() override;

    // Called during render pass - this is where we draw with NanoVG
    void OnRender() override;

    // Called when element is resized
    void OnResize() override;

private:
    void InitializeNanoVG();
    void ShutdownNanoVG();

    // Call Lua render function if renderfunction attribute is set
    void CallLuaRenderFunction(float x, float y, float w, float h, float t);

    // Map RmlUI key identifier to Lua string name
    Rml::String MapKeyToString(Rml::Input::KeyIdentifier key);

    // Call Lua keyboard handler if keyhandler attribute is set
    void CallLuaKeyHandler(const Rml::String& key_name, bool key_down);

    // Call Lua mouse click handler - called on button down/up events only
    void CallLuaMouseClickHandler(int button, bool button_down);

    // Call Lua mouse move handler - called on move events
    void CallLuaMouseMoveHandler();

    // Call Lua mouse scroll handler - called on mouse wheel events
    void CallLuaMouseScrollHandler(float wheel_x, float wheel_y);

    NVGcontext* nvg_context_;
    float time_; // Animation time

    // Mouse interaction state
    Rml::Vector2f mouse_pos_;
    bool mouse_buttons_[3]; // Track left (0), right (1), middle (2) mouse buttons
};

