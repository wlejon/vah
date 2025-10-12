#pragma once

#include <string>
#include <vector>
#include <unordered_map>
#include <variant>
#include <memory>
#include "Seqlock.h"

// Forward declaration for recursive type
struct DynamicMap;

// Dynamic value types that can cross thread boundaries
using DynamicValue = std::variant<
    std::monostate,  // nil/null
    bool,
    int64_t,
    double,
    std::string,
    std::shared_ptr<DynamicMap>  // For nested objects
>;

// Define the nested map structure
struct DynamicMap {
    std::unordered_map<std::string, DynamicValue> fields;
};

// A row is a map of column names to values
using DynamicRow = std::unordered_map<std::string, DynamicValue>;

// A table is a vector of rows
using DynamicTable = std::vector<DynamicRow>;

// Thread-safe data store for dynamic models
// Uses Seqlock for lock-free single-writer, multiple-reader access
class DataStore {
public:
    DataStore() = default;
    ~DataStore() = default;

    // Set a model's data (called from worker threads)
    void SetModel(const std::string& name, const DynamicTable& data);

    // Get a model's data (called from main thread)
    DynamicTable GetModel(const std::string& name) const;

    // Check if a model exists
    bool HasModel(const std::string& name) const;

    // Remove a model
    void RemoveModel(const std::string& name);

private:
    // Each model has its own seqlock for independent updates
    mutable std::unordered_map<std::string, Seqlock<DynamicTable>> models_;
};
