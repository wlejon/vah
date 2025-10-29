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
    bool is_array = false;  // True if this should be converted to Lua array
};

// A row is a map of column names to values
using DynamicRow = std::unordered_map<std::string, DynamicValue>;

// A table is a vector of rows
using DynamicTable = std::vector<DynamicRow>;

// Data store for dynamic models
class DataStore {
public:
    DataStore() = default;
    ~DataStore() = default;

    void SetModel(const std::string& name, DynamicTable&& data);

    // Returns a shared_ptr to avoid copying large tables
    std::shared_ptr<const DynamicTable> GetModel(const std::string& name) const;

    bool HasModel(const std::string& name) const;
    void RemoveModel(const std::string& name);

    // Object binding API (for single objects, not tables)
    void SetObject(const std::string& name, DynamicRow&& data);
    std::shared_ptr<const DynamicRow> GetObject(const std::string& name) const;
    bool HasObject(const std::string& name) const;
    void RemoveObject(const std::string& name);

private:
    // shared_ptr used to keep data alive during render cycle
    std::unordered_map<std::string, std::shared_ptr<DynamicTable>> models_;
    std::unordered_map<std::string, std::shared_ptr<DynamicRow>> objects_;
};
