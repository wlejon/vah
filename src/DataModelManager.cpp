#include "DataModelManager.h"
#include "Logger.h"
#include <RmlUi/Lua/Interpreter.h>
#include <lua.hpp>

DataModelManager::DataModelManager(Rml::Context* context, DataStore* data_store)
    : context_(context)
    , data_store_(data_store)
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

            // Register event callbacks that use RmlUI's Lua state
            constructor.BindEventCallback("trigger_delete", [](Rml::DataModelHandle, Rml::Event&, const Rml::VariantList& arguments) {
                if (arguments.size() >= 1) {
                    lua_State* L = Rml::Lua::Interpreter::GetLuaState();
                    lua_getglobal(L, "trigger_delete");
                    if (lua_isfunction(L, -1)) {
                        if (arguments[0].GetType() == Rml::Variant::INT) {
                            lua_pushinteger(L, arguments[0].Get<int>());
                        } else if (arguments[0].GetType() == Rml::Variant::INT64) {
                            lua_pushinteger(L, arguments[0].Get<int64_t>());
                        } else if (arguments[0].GetType() == Rml::Variant::FLOAT) {
                            lua_pushinteger(L, static_cast<int>(arguments[0].Get<float>()));
                        } else {
                            lua_pushinteger(L, 0);
                        }
                        lua_pcall(L, 1, 0, 0);
                    } else {
                        lua_pop(L, 1);
                    }
                }
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
