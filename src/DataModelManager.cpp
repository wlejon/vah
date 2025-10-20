#include "DataModelManager.h"
#include "Logger.h"
#include "EventDispatcher.h"
#include "RmlUiBridge.h"
#include <RmlUi/Lua/Interpreter.h>
#include <RmlUi/Core/Elements/ElementFormControl.h>
#include <lua.hpp>

// External reference to RmlUiBridge
extern RmlUiBridge* g_bridge;

DataModelManager::DataModelManager(Rml::Context* context, DataStore* data_store, EventDispatcher* event_dispatcher)
    : context_(context)
    , data_store_(data_store)
    , event_dispatcher_(event_dispatcher)
{
}

DataModelManager::~DataModelManager() {
    ClearAllModels();
}

void DataModelManager::UpdateModel(const std::string& model_name, DynamicTable&& data) {
    if (!context_ || !data_store_) {
        LOG_WARN("Cannot update model: context or data_store is null");
        return;
    }

    // Update the data in DataStore (main thread only - no races)
    data_store_->SetModel(model_name, data);

    // Check if we need to create the RmlUi model or just dirty it
    auto it = data_model_handles_.find(model_name);
    if (it == data_model_handles_.end()) {
        // First time - create the RmlUi data model
        Rml::DataModelConstructor constructor = context_->CreateDataModel(model_name);

        if (constructor) {
            // Create our custom variable definition
            auto table_def = std::make_unique<DynamicTableDef>(data_store_, model_name);

            // Bind the model (using nullptr as root pointer for the whole table)
            constructor.BindCustomDataVariable(model_name,
                                              Rml::DataVariable(table_def.get(), nullptr));

            // Register generic trigger event callback
            constructor.BindEventCallback("trigger", [this](Rml::DataModelHandle, Rml::Event& event, const Rml::VariantList& arguments) {
                if (arguments.size() < 1) {
                    LOG_WARN("trigger() requires at least event name argument");
                    return;
                }

                // First argument is the event name
                std::string event_name;
                if (arguments[0].GetType() == Rml::Variant::STRING) {
                    event_name = arguments[0].Get<Rml::String>();
                } else {
                    LOG_WARN("trigger() first argument must be event name (string)");
                    return;
                }

                // Build payload starting with context from data-for (if present)
                PayloadMap payload;

                // Try to extract data context from DOM
                Rml::Element* element = event.GetTargetElement();
                std::string context_model;
                int context_row = -1;

                // Walk up the DOM to find data-model and data-row-index attributes
                while (element) {
                    if (context_model.empty()) {
                        const Rml::Variant* model_attr = element->GetAttribute("data-model");
                        if (model_attr && model_attr->GetType() == Rml::Variant::STRING) {
                            context_model = std::string(model_attr->Get<Rml::String>());
                        }
                    }

                    if (context_row == -1) {
                        const Rml::Variant* row_attr = element->GetAttribute("data-row-index");
                        if (row_attr) {
                            if (row_attr->GetType() == Rml::Variant::INT) {
                                context_row = row_attr->Get<int>();
                            } else if (row_attr->GetType() == Rml::Variant::INT64) {
                                context_row = static_cast<int>(row_attr->Get<int64_t>());
                            } else if (row_attr->GetType() == Rml::Variant::STRING) {
                                // Parse string to int (from data-attr-data-row-index binding)
                                std::string row_str = std::string(row_attr->Get<Rml::String>());
                                try {
                                    context_row = std::stoi(row_str);
                                } catch (...) {
                                    LOG_WARN("trigger('{}') couldn't parse data-row-index: '{}'", event_name, row_str);
                                }
                            }
                        }
                    }

                    // If we found both, stop searching (innermost data-for wins)
                    if (!context_model.empty() && context_row != -1) {
                        break;
                    }

                    element = element->GetParentNode();
                }

                // If we found a data context, inject the full row into payload
                Rml::Element* row_element = nullptr;  // Track the row element for input extraction
                if (!context_model.empty() && context_row != -1) {
                    auto model_data = data_store_->GetModel(context_model);
                    if (model_data && context_row >= 0 && context_row < static_cast<int>(model_data->size())) {
                        const DynamicRow& row = (*model_data)[context_row];

                        // Copy all row fields to payload (this is the base object)
                        for (const auto& [key, value] : row) {
                            payload[key] = value;
                        }

                        // Store the row element for input extraction
                        // Walk back up from current element to find the element with data-row-index
                        Rml::Element* el = event.GetTargetElement();
                        while (el) {
                            const Rml::Variant* row_attr = el->GetAttribute("data-row-index");
                            if (row_attr) {
                                row_element = el;
                                break;
                            }
                            el = el->GetParentNode();
                        }
                    }
                }

                // Extract current values from tracked inputs in the row (overrides row data)
                if (row_element) {
                    PayloadMap tracked_values = ExtractTrackedInputValues(row_element);
                    for (const auto& [key, value] : tracked_values) {
                        payload[key] = value;  // Override with current input values
                    }
                }

                // Add explicit arguments on top (may override row fields and tracked values)
                // Use smart key assignment:
                // - Second argument (index 1) → "id"
                // - Third+ arguments → numbered keys "1", "2", etc.
                for (size_t i = 1; i < arguments.size(); ++i) {
                    std::string key = (i == 1) ? "id" : std::to_string(i);

                    const auto& arg = arguments[i];
                    switch (arg.GetType()) {
                        case Rml::Variant::BOOL:
                            payload[key] = arg.Get<bool>();
                            break;
                        case Rml::Variant::INT:
                            payload[key] = static_cast<int64_t>(arg.Get<int>());
                            break;
                        case Rml::Variant::INT64:
                            payload[key] = arg.Get<int64_t>();
                            break;
                        case Rml::Variant::FLOAT:
                            payload[key] = static_cast<double>(arg.Get<float>());
                            break;
                        case Rml::Variant::DOUBLE:
                            payload[key] = arg.Get<double>();
                            break;
                        case Rml::Variant::STRING:
                            payload[key] = std::string(arg.Get<Rml::String>());
                            break;
                        default:
                            // Skip unsupported types
                            break;
                    }
                }

                // UPDATE MAIN THREAD DATA IMMEDIATELY
                // If we have a data context, update the DataStore with the merged payload
                // This ensures the UI reflects user changes immediately, before server responds
                if (!context_model.empty() && context_row != -1) {
                    auto model_data = data_store_->GetModel(context_model);
                    if (model_data && context_row >= 0 && context_row < static_cast<int>(model_data->size())) {
                        // Create mutable copy
                        DynamicTable mutable_data = *model_data;

                        // Update the row with all payload fields
                        for (const auto& [key, value] : payload) {
                            mutable_data[context_row][key] = value;
                        }

                        // Write back to DataStore
                        data_store_->SetModel(context_model, mutable_data);

                        // Dirty the model to trigger re-render
                        auto it_handle = data_model_handles_.find(context_model);
                        if (it_handle != data_model_handles_.end()) {
                            it_handle->second.DirtyVariable(context_model);
                        }
                    }
                }

                // Get the document ID from the event
                std::string document_id;
                if (auto* doc = event.GetTargetElement()->GetOwnerDocument()) {
                    document_id = doc->GetId();

                    // Update current document in RmlUiBridge so nested triggers work
                    if (g_bridge) {
                        g_bridge->SetCurrentDocument(document_id);
                    }
                }

                // Dispatch event to the appropriate thread via EventDispatcher
                if (!document_id.empty()) {
                    event_dispatcher_->DispatchEvent(document_id, event_name, payload);
                } else {
                    LOG_WARN("DataModelManager: Event '{}' triggered but no document ID found", event_name);
                }
            });

            // Store the definition so it stays alive
            data_model_defs_[model_name] = std::move(table_def);

            // Get and store the model handle
            Rml::DataModelHandle model_handle = constructor.GetModelHandle();
            data_model_handles_[model_name] = model_handle;

            // Mark as dirty to trigger initial render
            model_handle.DirtyVariable(model_name);
        } else {
            LOG_WARN("Failed to create data model '{}'", model_name);
        }
    } else {
        // Model already exists - just mark it dirty to trigger re-render
        it->second.DirtyVariable(model_name);
    }
}

void DataModelManager::ClearAllModels() {
    // Clean up data model definitions before context is destroyed
    data_model_defs_.clear();
    data_model_handles_.clear();
}

PayloadMap DataModelManager::ExtractTrackedInputValues(Rml::Element* root) {
    PayloadMap result;

    if (!root) {
        return result;
    }

    // Recursively walk the DOM tree starting from root
    std::function<void(Rml::Element*)> walk = [&](Rml::Element* element) {
        if (!element) {
            return;
        }

        // Check if this element has the track attribute (not data-track, just track)
        // because data-attr-track creates an attribute called "track"
        const Rml::Variant* track_attr = element->GetAttribute("track");
        if (track_attr) {
            // This is a tracked input - try to extract its value
            Rml::ElementFormControl* form_control = dynamic_cast<Rml::ElementFormControl*>(element);
            if (form_control) {
                // Get current value from the form control
                Rml::String value_rml = form_control->GetValue();
                std::string value(value_rml.data(), value_rml.size());

                // Get the field name from the explicit field attribute
                Rml::String field_rml = element->GetAttribute("field", Rml::String());
                std::string field_name(field_rml.data(), field_rml.size());

                if (!field_name.empty()) {
                    result[field_name] = value;
                }
            }
        }

        // Recurse to children
        for (int i = 0; i < element->GetNumChildren(); ++i) {
            walk(element->GetChild(i));
        }
    };

    walk(root);

    return result;
}
