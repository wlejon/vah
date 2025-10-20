#pragma once

#include <RmlUi/Core/ElementInstancer.h>
#include "ElementTextEditor.h"
#include "DataStore.h"

/**
 * ElementTextEditorInstancer - Factory for creating ElementTextEditor instances.
 */
class ElementTextEditorInstancer : public Rml::ElementInstancer {
public:
    ElementTextEditorInstancer(DataStore* data_store) : data_store_(data_store) {}
    virtual ~ElementTextEditorInstancer() = default;

    // Create an instance of ElementTextEditor
    Rml::ElementPtr InstanceElement(
        Rml::Element* parent,
        const Rml::String& tag,
        const Rml::XMLAttributes& attributes) override
    {
        return Rml::ElementPtr(new ElementTextEditor(tag, data_store_));
    }

    // Release an element instance
    void ReleaseElement(Rml::Element* element) override
    {
        delete element;
    }

private:
    DataStore* data_store_;
};
