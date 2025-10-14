#pragma once

#include <RmlUi/Core/Element.h>
#include <RmlUi/Core/EventListener.h>
#include <nanovg.h>

/**
 * ElementCanvas - A custom RmlUi element that provides a NanoVG drawing surface.
 *
 * This element demonstrates how to integrate NanoVG with RmlUi for custom rendering.
 * It serves as the foundation for porting imgui-node-editor to RmlUi.
 *
 * Usage in RML:
 *   <canvas style="width: 800px; height: 600px;" />
 */
class ElementCanvas : public Rml::Element, public Rml::EventListener {
public:
    ElementCanvas(const Rml::String& tag);
    virtual ~ElementCanvas();

    // Called when element is added to the document tree
    void OnChildAdd(Rml::Element* element) override;

    // Called when element is removed from the document tree
    void OnChildRemove(Rml::Element* element) override;

    // Handle mouse events for interaction testing
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

    // Demo rendering function - draws test graphics to verify NanoVG works
    void RenderDemo(NVGcontext* vg, float x, float y, float w, float h, float t);

    NVGcontext* nvg_context_;
    float time_; // Animation time for demo

    // Mouse interaction state for testing
    Rml::Vector2f mouse_pos_;
    bool mouse_down_;
};

