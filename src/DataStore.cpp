#include "DataStore.h"
#include "Logger.h"

void DataStore::SetModel(const std::string& name, const DynamicTable& data) {
    // Access or create the seqlock for this model
    models_[name].Write(data);
    LOG_DEBUG("DataStore: Set model '{}' with {} rows", name, data.size());
}

DynamicTable DataStore::GetModel(const std::string& name) const {
    auto it = models_.find(name);
    if (it != models_.end()) {
        return it->second.Read();
    }
    LOG_WARN("DataStore: Model '{}' not found, returning empty table", name);
    return DynamicTable{};
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
