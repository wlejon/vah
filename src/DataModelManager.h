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

    // Update or create a data model
    void UpdateModel(const std::string& model_name, DynamicTable&& data);

    // Clear all models (called during shutdown)
    void ClearAllModels();

private:
    Rml::Context* context_;
    DataStore* data_store_;
    EventDispatcher* event_dispatcher_;

    // Track data models and their definitions
    std::unordered_map<std::string, std::unique_ptr<DynamicTableDef>> data_model_defs_;
    std::unordered_map<std::string, Rml::DataModelHandle> data_model_handles_;

    // Helper function for extracting tracked input values from DOM
    PayloadMap ExtractTrackedInputValues(Rml::Element* root);
};
