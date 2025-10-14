#include "DataStore.h"
#include "Logger.h"

void DataStore::SetModel(const std::string& name, const DynamicTable& data) {
    // Create a new shared_ptr with the data
    // This copies the data once, then readers share the immutable copy
    auto new_data = std::make_shared<DynamicTable>(data);

    // Store or replace the shared_ptr
    models_[name] = new_data;
}

std::shared_ptr<const DynamicTable> DataStore::GetModel(const std::string& name) const {
    auto it = models_.find(name);
    if (it != models_.end()) {
        // Return the shared_ptr - reader keeps the data alive even if writer updates
        return it->second;
    }
    LOG_WARN("DataStore: Model '{}' not found, returning empty table", name);
    // Return empty table wrapped in shared_ptr
    static auto empty = std::make_shared<DynamicTable>();
    return empty;
}

bool DataStore::HasModel(const std::string& name) const {
    return models_.find(name) != models_.end();
}

void DataStore::RemoveModel(const std::string& name) {
    auto it = models_.find(name);
    if (it != models_.end()) {
        models_.erase(it);
        LOG_DEBUG("DataStore: Removed model '{}'", name);
    }
}
