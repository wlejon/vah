#pragma once

#include <string>
#include <vector>
#include <unordered_map>
#include <variant>
#include <memory>
#include <atomic>

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
// Uses atomic shared_ptr for lock-free single-writer, multiple-reader access
// This is safe for complex types unlike Seqlock
class DataStore {
public:
    DataStore() = default;
    ~DataStore() = default;

    // Set a model's data (called from worker threads)
    void SetModel(const std::string& name, const DynamicTable& data);

    // Get a model's data (called from main thread)
    // Returns a shared_ptr to avoid copying large tables
    std::shared_ptr<const DynamicTable> GetModel(const std::string& name) const;

    // Check if a model exists
    bool HasModel(const std::string& name) const;

    // Remove a model
    void RemoveModel(const std::string& name);

private:
    // Each model is stored as a shared_ptr for safe concurrent access
    // Writer creates new table, reader keeps reference to old table until done
    mutable std::unordered_map<std::string, std::shared_ptr<DynamicTable>> models_;
};
