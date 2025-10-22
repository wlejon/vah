#pragma once

#include <RmlUi/Core/DataVariable.h>
#include <RmlUi/Core/Variant.h>
#include <string>
#include <vector>
#include <memory>
#include "DataStore.h"

// Pointer encoding for DynamicTableDef:
// The void* ptr encodes the path to a specific value in the data structure
struct DataPath {
    int row_index;  // -1 for the root table itself
    std::vector<std::string> path;  // Path within a nested object (empty for row root)

    DataPath() : row_index(-1) {}
    DataPath(int row) : row_index(row) {}
    DataPath(int row, const std::vector<std::string>& p) : row_index(row), path(p) {}
};

// Custom VariableDefinition that reads from DataStore
// This allows RmlUi to read our C++ data structures directly
class DynamicTableDef : public Rml::VariableDefinition {
public:
    DynamicTableDef(DataStore* store, const std::string& model_name);
    ~DynamicTableDef() override;

    // Get the value at ptr as a Variant
    bool Get(void* ptr, Rml::Variant& variant) override;

    // Get the size of the array (number of rows)
    int Size(void* ptr) override;

    // Get a child element (for array indexing or struct member access)
    Rml::DataVariable Child(void* ptr, const Rml::DataAddressEntry& address) override;

    // Invalidate cache (force refresh on next access)
    // This should be called before DirtyVariable() to ensure UI picks up new data
    void InvalidateCache();

private:
    DataStore* store_;
    std::string model_name_;

    // Cached data snapshot for consistency during rendering
    // - Refreshed lazily on first access (when null)
    // - shared_ptr keeps data alive even if Lua threads update mid-render
    // - Old snapshot released when new one is fetched from DataStore
    std::shared_ptr<const DynamicTable> cached_data_;

    // Arena allocator for DataPaths
    // - Allocates path objects during rendering
    // - Cleared automatically on destruction (no manual clearing needed)
    std::vector<std::unique_ptr<DataPath>> path_arena_;

    // Helper: Get the value at a specific path
    const DynamicValue* GetValueAtPath(const DataPath* path);

    // Helper: Convert DynamicValue to Rml::Variant
    bool ConvertToVariant(const DynamicValue& value, Rml::Variant& variant);

    // Helper: Allocate a DataPath (managed by arena)
    void* AllocatePath(const DataPath& path);

    // Helper: Extract DataPath from ptr
    const DataPath* GetPath(void* ptr);

    // Helper: Refresh cache from DataStore
    void RefreshCache();
};
