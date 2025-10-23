#pragma once

#include <RmlUi/Core.h>
#include <string>
#include <unordered_map>
#include <memory>
#include "DataStore.h"
#include "DataBindings.h"
#include "Commands.h"

class EventDispatcher;  // Forward declaration

class DataModelManager {
public:
    DataModelManager(Rml::Context* context, DataStore* data_store, EventDispatcher* event_dispatcher);
    ~DataModelManager();

    // Update or create a data model (table)
    void UpdateModel(const std::string& model_name, DynamicTable&& data);

    // Update or create a data object (single object, not array)
    void UpdateObject(const std::string& object_name, DynamicRow&& data);

    // Check if a model has been registered in RmlUi
    bool IsModelRegistered(const std::string& model_name) const;

    // Check if an object has been registered in RmlUi
    bool IsObjectRegistered(const std::string& object_name) const;

    // Clear all models (called during shutdown)
    void ClearAllModels();

private:
    Rml::Context* context_;
    DataStore* data_store_;
    EventDispatcher* event_dispatcher_;

    // Track data models (tables) and their definitions
    std::unordered_map<std::string, std::unique_ptr<DynamicTableDef>> data_model_defs_;
    std::unordered_map<std::string, Rml::DataModelHandle> data_model_handles_;

    // Track data objects (single objects) and their definitions
    std::unordered_map<std::string, std::unique_ptr<DynamicObjectDef>> data_object_defs_;
    std::unordered_map<std::string, Rml::DataModelHandle> data_object_handles_;
};
