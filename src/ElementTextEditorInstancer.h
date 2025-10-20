#pragma once

#include <RmlUi/Core/ElementInstancer.h>
#include "ElementTextEditor.h"

/**
 * ElementTextEditorInstancer - Factory for creating ElementTextEditor instances.
 */
class ElementTextEditorInstancer : public Rml::ElementInstancer {
public:
    ElementTextEditorInstancer() = default;
    virtual ~ElementTextEditorInstancer() = default;

    // Create an instance of ElementTextEditor
    Rml::ElementPtr InstanceElement(
        Rml::Element* parent,
        const Rml::String& tag,
        const Rml::XMLAttributes& attributes) override
    {
        return Rml::ElementPtr(new ElementTextEditor(tag));
    }

    // Release an element instance
    void ReleaseElement(Rml::Element* element) override
    {
        delete element;
    }
};
