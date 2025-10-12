#pragma once

#include <RmlUi/Core.h>
#include <functional>
#include <string>

/**
 * InputEventListener - Automatic input tracking event hooks for RmlUi
 *
 * This class implements RmlUi's EventListener interface to detect focus, blur,
 * and change events on input elements. It only tracks elements that have ALL
 * THREE required data attributes: data-model, data-record-id, and data-field.
 *
 * When events fire on qualifying elements, it extracts the current value and
 * calls the appropriate callback function. This class does NOT store any state
 * or tracking information - all event data is passed to callbacks for external
 * handling.
 *
 * Usage:
 *   1. Create an instance: auto listener = std::make_unique<InputEventListener>();
 *   2. Set callbacks: listener->SetOnFocus([](model, id, field, value) { ... });
 *   3. Register with context: context->AddEventListener("focus", listener.get(), true);
 */
class InputEventListener : public Rml::EventListener {
public:
    InputEventListener() = default;
    ~InputEventListener() override = default;

    // Callback type: (model_name, record_id, field_name, value)
    using EventCallback = std::function<void(const std::string&, const std::string&,
                                              const std::string&, const std::string&)>;

    // Set callback functions for each event type
    void SetOnFocus(EventCallback callback) { on_focus_ = std::move(callback); }
    void SetOnChange(EventCallback callback) { on_change_ = std::move(callback); }
    void SetOnBlur(EventCallback callback) { on_blur_ = std::move(callback); }

    // RmlUi EventListener interface implementation
    void ProcessEvent(Rml::Event& event) override;

private:
    // Extract tracking attributes from element and call appropriate callback
    void HandleEvent(Rml::Event& event, EventCallback& callback);

    // Check if element has all required data attributes
    bool HasTrackingAttributes(Rml::Element* element) const;

    // Extract value from form control element
    std::string ExtractValue(Rml::Element* element) const;

    // Callbacks for each event type
    EventCallback on_focus_;
    EventCallback on_change_;
    EventCallback on_blur_;
};
