#include "InputEventListener.h"
#include "Logger.h"
#include <RmlUi/Core/Elements/ElementFormControl.h>

void InputEventListener::ProcessEvent(Rml::Event& event) {
    // Route to appropriate callback based on event type
    if (event == "focus" || event == Rml::EventId::Focus) {
        HandleEvent(event, on_focus_);
    }
    else if (event == "blur" || event == Rml::EventId::Blur) {
        HandleEvent(event, on_blur_);
    }
    else if (event == "change" || event == Rml::EventId::Change) {
        HandleEvent(event, on_change_);
    }
}

void InputEventListener::HandleEvent(Rml::Event& event, EventCallback& callback) {
    // Skip if no callback registered
    if (!callback) {
        return;
    }

    // Get the target element (the element that triggered the event)
    Rml::Element* target = event.GetTargetElement();
    if (!target) {
        return;
    }

    // Only process elements with all three required tracking attributes
    if (!HasTrackingAttributes(target)) {
        return;
    }

    // Extract tracking attributes
    Rml::String model_attr = target->GetAttribute("data-model", Rml::String());
    Rml::String record_id_attr = target->GetAttribute("data-record-id", Rml::String());
    Rml::String field_attr = target->GetAttribute("data-field", Rml::String());

    // Convert to std::string
    std::string model_name(model_attr.data(), model_attr.size());
    std::string record_id(record_id_attr.data(), record_id_attr.size());
    std::string field_name(field_attr.data(), field_attr.size());

    // Extract current value from form control
    std::string value = ExtractValue(target);

    // Log for debugging
    LOG_DEBUG("InputEventListener: {} event on {}.{}.{} = '{}'",
              event.GetType(), model_name, record_id, field_name, value);

    // Call the callback
    callback(model_name, record_id, field_name, value);
}

bool InputEventListener::HasTrackingAttributes(Rml::Element* element) const {
    if (!element) {
        return false;
    }

    // Element must have all three data attributes
    return element->HasAttribute("data-model") &&
           element->HasAttribute("data-record-id") &&
           element->HasAttribute("data-field");
}

std::string InputEventListener::ExtractValue(Rml::Element* element) const {
    if (!element) {
        return "";
    }

    // Try to cast to ElementFormControl to get the value
    auto* form_control = dynamic_cast<Rml::ElementFormControl*>(element);
    if (form_control) {
        Rml::String value = form_control->GetValue();
        return std::string(value.data(), value.size());
    }

    // Fallback: try to get value attribute
    Rml::String value_attr = element->GetAttribute("value", Rml::String());
    return std::string(value_attr.data(), value_attr.size());
}
