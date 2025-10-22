#include "DataBindings.h"
#include "Logger.h"
#include <RmlUi/Core/Types.h>

// Cache Strategy:
// ----------------
// DynamicTableDef maintains a cached snapshot of the data for consistency.
// The cache is refreshed lazily (on-demand) when accessed and found to be null.
//
// Why caching?
// 1. Consistency: RmlUi may call Size/Child/Get multiple times during a render.
//    Without caching, if Lua updates data mid-render, we could read inconsistent state.
// 2. Safety: shared_ptr keeps old data alive during render even if Lua replaces it.
// 3. Performance: Avoids repeated DataStore lookups during a single render.
//
// Cache invalidation:
// - Cache starts null (no data loaded yet)
// - First access during render calls RefreshCache() -> gets latest shared_ptr
// - Subsequent accesses use cached data (consistent snapshot)
// - When Lua calls data.bind(), DataStore creates new shared_ptr
// - Next render: first access gets new pointer, old data released
//
// No manual cache clearing needed - shared_ptr handles everything!

DynamicTableDef::DynamicTableDef(DataStore* store, const std::string& model_name)
    : Rml::VariableDefinition(Rml::DataVariableType::Array)
    , store_(store)
    , model_name_(model_name)
{
    // Pre-allocate arena space to reduce allocations
    path_arena_.reserve(256);
}

DynamicTableDef::~DynamicTableDef()
{
    // Arena allocations are automatically cleaned up via unique_ptr
}

bool DynamicTableDef::Get(void* ptr, Rml::Variant& variant)
{
    // Refresh cache if not already loaded
    if (!cached_data_) {
        RefreshCache();
    }

    // ptr encodes the row index and field path
    const DataPath* path = GetPath(ptr);
    const DynamicValue* value = GetValueAtPath(path);

    if (!value) {
        return false;
    }

    return ConvertToVariant(*value, variant);
}

int DynamicTableDef::Size(void* ptr)
{
    // If ptr is nullptr, we're asking for the root table size
    if (ptr == nullptr) {
        // Refresh cache if not already loaded
        if (!cached_data_) {
            RefreshCache();
        }
        return cached_data_ ? static_cast<int>(cached_data_->size()) : 0;
    }

    // Otherwise we're asking for the size of a nested structure
    const DataPath* path = GetPath(ptr);
    const DynamicValue* value = GetValueAtPath(path);

    if (!value) {
        return 0;
    }

    // Check if it's a nested object (map)
    if (auto nested = std::get_if<std::shared_ptr<DynamicMap>>(value)) {
        if (*nested) {
            return static_cast<int>((*nested)->fields.size());
        }
    }

    return 0;
}

Rml::DataVariable DynamicTableDef::Child(void* ptr, const Rml::DataAddressEntry& address)
{
    // Root table access: table[index] -> get a row, or table.size -> get size
    if (ptr == nullptr) {
        // Refresh cache on root access (same as Size() does)
        if (!cached_data_) {
            RefreshCache();
        }

        if (!cached_data_) {
            return Rml::DataVariable();
        }

        // Handle named field access (e.g., contacts.size)
        if (!address.name.empty() && address.index == -1) {
            if (address.name == "size") {
                return Rml::MakeLiteralIntVariable(static_cast<int>(cached_data_->size()));
            }
            LOG_WARN("DataBindings: Unknown field '{}' on model '{}'", address.name, model_name_);
            return Rml::DataVariable();
        }

        // Handle indexed access (e.g., contacts[0])
        int index = address.index;
        if (index < 0 || index >= static_cast<int>(cached_data_->size())) {
            // Out of bounds - this can happen during data updates, not an error
            LOG_DEBUG("DataBindings: Row index {} out of bounds for model '{}' (size: {})",
                      index, model_name_, cached_data_->size());
            return Rml::DataVariable();
        }

        // Return a pointer to this row (encoded as index+1 to avoid nullptr)
        DataPath row_path(index);
        return Rml::DataVariable(this, AllocatePath(row_path));
    }

    // Row or nested object access: obj.field or obj[index]
    const DataPath* parent_path = GetPath(ptr);

    if (!cached_data_) {
        return Rml::DataVariable();
    }

    // Get the row this belongs to
    if (parent_path->row_index < 0 || parent_path->row_index >= static_cast<int>(cached_data_->size())) {
        return Rml::DataVariable();
    }

    const DynamicRow& row = (*cached_data_)[parent_path->row_index];

    // Build new path
    DataPath child_path = *parent_path;

    // If address has a name, it's field access (obj.name)
    if (!address.name.empty() && address.index == -1) {
        child_path.path.push_back(std::string(address.name.data(), address.name.size()));
    }
    // If address has an index, it's array access (array[index])
    // Lua arrays use 1-based indexing, but RmlUi uses 0-based indexing
    // Convert to string key matching Lua's 1-based index
    else if (address.index >= 0) {
        child_path.path.push_back(std::to_string(address.index + 1));
    }

    // Verify the child path exists and return it
    const DynamicValue* child_value = GetValueAtPath(&child_path);
    if (!child_value) {
        return Rml::DataVariable();
    }

    return Rml::DataVariable(this, AllocatePath(child_path));
}

const DynamicValue* DynamicTableDef::GetValueAtPath(const DataPath* path)
{
    if (!path || !cached_data_) {
        return nullptr;
    }

    // Root table has no specific value
    if (path->row_index < 0) {
        return nullptr;
    }

    if (path->row_index >= static_cast<int>(cached_data_->size())) {
        return nullptr;
    }

    const DynamicRow& row = (*cached_data_)[path->row_index];

    // If no path, return the whole row (but we can't return a row as a value)
    // This case shouldn't happen in practice
    if (path->path.empty()) {
        // We need to handle this case - when accessing a row itself
        // For now, return nullptr as we expect field access
        return nullptr;
    }

    // Navigate through the path
    const DynamicValue* current = nullptr;
    const DynamicRow* current_row = &row;

    for (size_t i = 0; i < path->path.size(); ++i) {
        const std::string& field = path->path[i];

        auto it = current_row->find(field);
        if (it == current_row->end()) {
            return nullptr;
        }

        current = &it->second;

        // If there are more path components, we need to navigate deeper
        if (i < path->path.size() - 1) {
            // Check if current value is a nested object
            if (auto nested = std::get_if<std::shared_ptr<DynamicMap>>(current)) {
                if (!*nested) {
                    return nullptr;
                }
                current_row = &(*nested)->fields;
            } else {
                // Path continues but current value is not an object
                return nullptr;
            }
        }
    }

    return current;
}

bool DynamicTableDef::ConvertToVariant(const DynamicValue& value, Rml::Variant& variant)
{
    return std::visit([&](auto&& val) -> bool {
        using T = std::decay_t<decltype(val)>;

        if constexpr (std::is_same_v<T, std::monostate>) {
            variant = Rml::Variant();
            return true;
        }
        else if constexpr (std::is_same_v<T, bool>) {
            variant = val;
            return true;
        }
        else if constexpr (std::is_same_v<T, int64_t>) {
            variant = static_cast<int>(val);
            return true;
        }
        else if constexpr (std::is_same_v<T, double>) {
            variant = static_cast<float>(val);
            return true;
        }
        else if constexpr (std::is_same_v<T, std::string>) {
            variant = Rml::String(val.c_str());
            return true;
        }
        else if constexpr (std::is_same_v<T, std::shared_ptr<DynamicMap>>) {
            // Nested objects can't be directly converted to variants
            // They should be accessed via Child()
            return false;
        }
        else {
            return false;
        }
    }, value);
}

void* DynamicTableDef::AllocatePath(const DataPath& path)
{
    // Simple encoding for common cases:
    // - If path is empty (just row index), encode row_index + 1 directly
    // - Otherwise, allocate a DataPath in our arena
    if (path.path.empty()) {
        return reinterpret_cast<void*>(static_cast<intptr_t>(path.row_index + 1));
    }

    // For nested paths, allocate in arena (cleaned up at start of next render cycle)
    auto heap_path = std::make_unique<DataPath>(path);
    void* ptr = heap_path.get();
    path_arena_.push_back(std::move(heap_path));
    return ptr;
}

void DynamicTableDef::RefreshCache()
{
    // Get the latest data snapshot from DataStore
    // - If Lua updated the model, this gets the new shared_ptr
    // - The old cached_data_ is released (if we were the last holder)
    // - DataStore returns shared_ptr, so data stays alive during this render
    cached_data_ = store_->GetModel(model_name_);
}

const DataPath* DynamicTableDef::GetPath(void* ptr)
{
    if (ptr == nullptr) {
        static DataPath root_path;
        root_path.row_index = -1;
        root_path.path.clear();
        return &root_path;
    }

    intptr_t ptr_value = reinterpret_cast<intptr_t>(ptr);

    // Check if it's a simple row index (small positive integer)
    // We encoded row indices as row_index + 1, so valid range is 1 to ~1000000
    if (ptr_value > 0 && ptr_value < 1000000) {
        static thread_local DataPath simple_path;
        simple_path.row_index = static_cast<int>(ptr_value - 1);
        simple_path.path.clear();
        return &simple_path;
    }

    // Otherwise it's a heap-allocated path
    return reinterpret_cast<DataPath*>(ptr);
}
