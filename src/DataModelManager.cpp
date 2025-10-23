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
    // Data is moved into DataStore, avoiding unnecessary deep copy
    data_store_->SetModel(model_name, std::move(data));

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

            // Store the definition so it stays alive
            data_model_defs_[model_name] = std::move(table_def);

            // Get and store the model handle
            Rml::DataModelHandle model_handle = constructor.GetModelHandle();
            data_model_handles_[model_name] = model_handle;

            // Mark as dirty to trigger initial render (always dirty on first creation)
            model_handle.DirtyVariable(model_name);
        } else {
            LOG_WARN("Failed to create data model '{}'", model_name);
        }
    } else {
        // Model already exists - invalidate cache and mark dirty to trigger re-render
        // Invalidate cache first so the next render picks up the new data
        auto def_it = data_model_defs_.find(model_name);
        if (def_it != data_model_defs_.end()) {
            def_it->second->InvalidateCache();
        }

        // Mark it dirty to trigger re-render
        it->second.DirtyVariable(model_name);
    }
}

void DataModelManager::UpdateObject(const std::string& object_name, DynamicRow&& data) {
    if (!context_ || !data_store_) {
        LOG_WARN("Cannot update object: context or data_store is null");
        return;
    }

    // Update the data in DataStore (main thread only - no races)
    data_store_->SetObject(object_name, std::move(data));

    // Check if we need to create the RmlUi model or just dirty it
    auto it = data_object_handles_.find(object_name);
    if (it == data_object_handles_.end()) {
        // First time - create the RmlUi data model for this object
        Rml::DataModelConstructor constructor = context_->CreateDataModel(object_name);

        if (constructor) {
            // Create our custom variable definition for objects
            auto object_def = std::make_unique<DynamicObjectDef>(data_store_, object_name);

            // Bind the object (using nullptr as root pointer for the whole object)
            constructor.BindCustomDataVariable(object_name,
                                              Rml::DataVariable(object_def.get(), nullptr));

            // Store the definition so it stays alive
            data_object_defs_[object_name] = std::move(object_def);

            // Get and store the model handle
            Rml::DataModelHandle object_handle = constructor.GetModelHandle();
            data_object_handles_[object_name] = object_handle;

            // Mark as dirty to trigger initial render
            object_handle.DirtyVariable(object_name);
        } else {
            LOG_WARN("Failed to create data object '{}'", object_name);
        }
    } else {
        // Object already exists - invalidate cache and mark dirty to trigger re-render
        auto def_it = data_object_defs_.find(object_name);
        if (def_it != data_object_defs_.end()) {
            def_it->second->InvalidateCache();
        }

        // Mark it dirty to trigger re-render
        it->second.DirtyVariable(object_name);
    }
}

bool DataModelManager::IsModelRegistered(const std::string& model_name) const {
    return data_model_handles_.find(model_name) != data_model_handles_.end();
}

bool DataModelManager::IsObjectRegistered(const std::string& object_name) const {
    return data_object_handles_.find(object_name) != data_object_handles_.end();
}

void DataModelManager::ClearAllModels() {
    // Clean up data model definitions before context is destroyed
    data_model_defs_.clear();
    data_model_handles_.clear();
    data_object_defs_.clear();
    data_object_handles_.clear();
}
