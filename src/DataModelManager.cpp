#include "DataModelManager.h"
#include "Logger.h"
#include <RmlUi/Lua/Interpreter.h>
#include <lua.hpp>

DataModelManager::DataModelManager(Rml::Context* context, DataStore* data_store, moodycamel::ConcurrentQueue<UIEvent>* ui_event_queue)
    : context_(context)
    , data_store_(data_store)
    , ui_event_queue_(ui_event_queue)
{
}

DataModelManager::~DataModelManager() {
    ClearAllModels();
}

void DataModelManager::UpdateModel(const std::string& model_name, DynamicTable&& data) {
    LOG_DEBUG("Processing UpdateDataModel command: {} ({} rows)", model_name, data.size());

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
            constructor.BindEventCallback("trigger", [this](Rml::DataModelHandle, Rml::Event&, const Rml::VariantList& arguments) {
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

                // Build payload from remaining arguments
                PayloadMap payload;

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
                            payload[key] = arg.Get<int>();
                            break;
                        case Rml::Variant::INT64:
                            payload[key] = static_cast<int>(arg.Get<int64_t>());
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

                // Enqueue to UIEvent queue for Lua threads to consume
                UIEvent event{event_name, payload};
                ui_event_queue_->enqueue(std::move(event));

                LOG_DEBUG("DataModelManager: Triggered event '{}' with {} payload items", event_name, payload.size());
            });

            // Store the definition so it stays alive
            data_model_defs_[model_name] = std::move(table_def);

            // Get and store the model handle
            Rml::DataModelHandle model_handle = constructor.GetModelHandle();
            data_model_handles_[model_name] = model_handle;

            // Mark as dirty to trigger initial render
            model_handle.DirtyVariable(model_name);

            LOG_INFO("Created data model '{}' (marked dirty for initial render)", model_name);
        } else {
            LOG_WARN("Failed to create data model '{}'", model_name);
        }
    } else {
        // Model already exists - just mark it dirty to trigger re-render
        it->second.DirtyVariable(model_name);
        LOG_DEBUG("Marked data model '{}' as dirty", model_name);
    }
}

void DataModelManager::ClearAllModels() {
    // Clean up data model definitions before context is destroyed
    data_model_defs_.clear();
    data_model_handles_.clear();
}
