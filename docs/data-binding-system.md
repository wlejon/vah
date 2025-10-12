# Data Binding System

## Overview

The data binding system enables **thread-safe, reactive data flow** from Lua worker threads to RmlUi views on the main thread. It allows UI to automatically update when data changes, without writing HTML strings in Lua code.

**Key Features:**
- Lock-free cross-thread data sharing using `shared_ptr`
- Zero-copy reads during render cycles (snapshot consistency)
- Supports dynamic schemas (no C++ struct per model)
- Works with RmlUi's `data-for`, `{{variables}}`, `data-if` syntax
- Automatic memory management via arena allocators

## Problem Statement

Manufold-client needs to display frequently-updating data (1-2Hz) from worker threads:

**Challenges:**
1. **Thread boundary**: Lua VMs can't share tables across threads
2. **Performance**: Serialization is too slow for high-frequency updates
3. **Type safety**: Complex C++ types (vector, map, string) can't use simple Seqlock
4. **RmlUi limitation**: Built-in Lua data binding only handles first-level data

**Solution:** Store data in generic C++ containers accessible to both threads via `shared_ptr`, with custom RmlUi VariableDefinition for reading.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Lua Worker Thread                        │
├─────────────────────────────────────────────────────────────────┤
│  data.bind("contacts", {                                        │
│    {id=1, name="Alice", email="alice@example.com"},            │
│    {id=2, name="Bob", email="bob@example.com"}                 │
│  })                                                             │
│                          ↓                                       │
│  TableToDynamicTable() - converts Lua → C++                    │
│                          ↓                                       │
│  DataStore::SetModel() - wraps in shared_ptr                   │
│                          ↓                                       │
│  Commands::BindDataModel (first time only)                     │
│  Commands::DirtyDataModel (on updates)                         │
└─────────────────────────────────────────────────────────────────┘
                            ↓
                    Command Queue (lock-free)
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                          Main Thread                             │
├─────────────────────────────────────────────────────────────────┤
│  Process Commands:                                              │
│    BindDataModel    → CreateDataModel + BindCustomDataVariable │
│    DirtyDataModel   → handle.DirtyVariable(name)               │
│                                                                  │
│  RmlUi Render Cycle:                                            │
│    Size(nullptr)    → RefreshCache(), clear arena              │
│    Child(...)       → Navigate data structure                   │
│    Get(...)         → Return variant value                      │
│                                                                  │
│  All methods read from cached_data_ (shared_ptr)               │
│  → Consistent snapshot for entire render cycle                 │
└─────────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. **DataStore** (`src/DataStore.h/cpp`)

Thread-safe storage for data models.

**Key Design Decision:** Uses `shared_ptr<DynamicTable>` instead of `Seqlock<DynamicTable>` because:
- Complex types (string, unordered_map) have non-trivial copy constructors
- Seqlock can't guarantee atomicity during multi-step copy operations
- `shared_ptr` provides automatic garbage collection + immutable snapshots

```cpp
class DataStore {
    std::unordered_map<std::string, std::shared_ptr<DynamicTable>> models_;

    void SetModel(const std::string& name, const DynamicTable& data);
    std::shared_ptr<const DynamicTable> GetModel(const std::string& name) const;
};
```

**How it works:**
- Writer: Creates new `shared_ptr`, replaces old one in map
- Reader: Grabs `shared_ptr` copy, keeps data alive until done
- No locks needed: `shared_ptr` ref-counting is atomic

### 2. **DynamicTableDef** (`src/DataBindings.h/cpp`)

Custom `Rml::VariableDefinition` that reads from DataStore.

**Responsibilities:**
- Implements RmlUi's Get/Size/Child interface
- Maintains consistent snapshot during render cycle
- Manages DataPath allocations via arena

**Key Methods:**

```cpp
// Called first by RmlUi - refreshes cache and clears arena
int Size(void* ptr) {
    if (ptr == nullptr) {
        RefreshCache();           // Get new shared_ptr
        path_arena_.clear();      // Free all DataPaths from last render
        return cached_data_->size();
    }
    // ... handle nested sizes
}

// Navigate data structure
DataVariable Child(void* ptr, const DataAddressEntry& address) {
    // Root access: contacts[0], contacts.size
    // Field access: contact.name, contact.email
    // Returns encoded DataPath pointer
}

// Get scalar value
bool Get(void* ptr, Variant& variant) {
    // Convert DynamicValue → Rml::Variant
}
```

**DataPath Encoding:**
- Simple paths (just row index): Encode as `row_index + 1` directly in pointer
- Nested paths (row + fields): Allocate in arena, return raw pointer
- Arena cleared at start of each render cycle (no memory leaks)

### 3. **Type System**

```cpp
// Supports primitives + nested objects
using DynamicValue = std::variant<
    std::monostate,  // nil
    bool,
    int64_t,
    double,
    std::string,
    std::shared_ptr<DynamicMap>  // For nested data
>;

// Rows are maps (dynamic schemas)
using DynamicRow = std::unordered_map<std::string, DynamicValue>;

// Tables are vectors of rows
using DynamicTable = std::vector<DynamicRow>;
```

This allows handling arbitrary data shapes without defining C++ structs.

### 4. **Lua API** (`src/LuaThread.cpp:496-532`)

Simple two-function API:

```lua
-- Bind data model (creates or updates)
data.bind("contacts", {
    {id=1, name="Alice", email="alice@example.com"},
    {id=2, name="Bob", email="bob@example.com"}
})

-- Mark model as dirty to trigger UI update
data.update("contacts")
```

**Implementation Details:**
- `data.bind()`: Converts Lua table → DynamicTable → DataStore
  - First call: Sends `BindDataModel` command to create RmlUi model
  - Subsequent calls: Just updates DataStore (model already exists)
- `data.update()`: Sends `DirtyDataModel` command to trigger re-render

## Data Flow Example

**Scenario:** User clicks "Delete" button for contact ID 42

```
[UI - RmlUi]
  Button clicked: data-event-click="trigger_delete(contact.id)"
                            ↓
[RmlUiBridge]
  trigger_delete(42) → Creates UIEvent
                            ↓
[InputState via Seqlock]
  UIEvent added to ui_events vector
                            ↓
[Lua Thread 2 - Event Loop]
  Processes UIEvent → Calls registered handler
                            ↓
[Lua - delete_contact(42)]
  1. database:execute("DELETE FROM contacts WHERE id = 42")
  2. results = database:query("SELECT * FROM contacts")
  3. data.bind("contacts", results)  ← Updates DataStore
  4. data.update("contacts")         ← Marks dirty
                            ↓
[Command Queue]
  DirtyDataModel{model_name: "contacts"}
                            ↓
[Main Thread - Next Frame]
  Processes DirtyDataModel command
  → data_model_handles_["contacts"].DirtyVariable("contacts")
  → RmlUi schedules re-render
                            ↓
[RmlUi Render Cycle]
  1. Size(nullptr) → RefreshCache() → Gets new snapshot with 72 rows
  2. Child(nullptr, index=0) → Returns contacts[0]
  3. Child(row_ptr, name="name") → Returns contact.name
  4. Get(field_ptr, variant) → "Alice"
  5. ... repeat for all visible rows ...
```

**Critical Insight:** The `cached_data_` snapshot is grabbed once at the start and used for the entire render cycle. Even if Lua updates the data mid-render, the main thread continues using the old snapshot (no corruption, no crashes).

## Usage Guide

### Adding a New Data Model

**1. In Lua:**
```lua
-- Prepare your data as array of tables
local items = {
    {id=1, title="Task 1", completed=false},
    {id=2, title="Task 2", completed=true}
}

-- Bind it (first time creates model)
data.bind("tasks", items)
```

**2. In RML:**
```xml
<div data-model="tasks">
    <!-- Show count -->
    <div>Total: {{tasks.size}} tasks</div>

    <!-- Conditional rendering -->
    <div data-if="tasks.size == 0">
        No tasks yet!
    </div>

    <!-- Loop through items -->
    <div data-for="task : tasks">
        <div class="task-row">
            <span>{{task.title}}</span>
            <span data-if="task.completed">✓</span>
        </div>
    </div>
</div>
```

**3. Update when data changes:**
```lua
function add_task(title)
    database:execute("INSERT INTO tasks (title) VALUES (?)", title)
    local results = database:query("SELECT * FROM tasks")
    data.bind("tasks", results)  -- Update data
    data.update("tasks")         -- Trigger UI refresh
end
```

### Nested Data Example

```lua
-- Nested objects are automatically converted
data.bind("users", {
    {
        id=1,
        name="Alice",
        address={
            city="Seattle",
            state="WA"
        }
    }
})
```

```xml
<div data-for="user : users">
    <div>{{user.name}} lives in {{user.address.city}}</div>
</div>
```

## Implementation Details

### Thread Safety Guarantees

**Safe Operations:**
- ✅ One Lua thread writing to a model
- ✅ Main thread reading same model simultaneously
- ✅ Multiple Lua threads writing to different models
- ✅ Rapid updates (1-2Hz or faster)

**Unsafe Operations:**
- ❌ Multiple Lua threads writing to same model concurrently
- ❌ Modifying DynamicTable after passing to `SetModel()` (always create new table)

### Memory Management

**No Manual Cleanup Required:**

1. **DataPath allocations**: Cleared automatically at start of render cycle via arena
2. **DynamicTable data**: Freed when last `shared_ptr` reference drops
3. **Old snapshots**: Kept alive while main thread renders, freed after

**Memory Usage:**
- Worst case: 2x data size (old snapshot + new snapshot during render)
- Typical case: 1x data size (single snapshot referenced)
- Arena overhead: ~256 pointers pre-allocated per model

### Performance Characteristics

**Write (Lua → DataStore):**
- Time: O(n) where n = total data elements
- One full copy of Lua table → DynamicTable
- One `shared_ptr` allocation and map update
- No locks, no blocking

**Read (Main Thread):**
- Time: O(1) per field access
- Zero copies during render cycle (snapshot held by `shared_ptr`)
- Direct pointer navigation through data structures

**Dirty Marking:**
- Time: O(1) command queue push
- Triggers RmlUi layout recalculation (depends on DOM size)

## Extending the System

### Adding New Data Types

To support a new primitive type:

**1. Update variant:**
```cpp
// DataStore.h
using DynamicValue = std::variant<
    std::monostate,
    bool,
    int64_t,
    double,
    std::string,
    std::shared_ptr<DynamicMap>,
    YourNewType  // ← Add here
>;
```

**2. Update Lua converter:**
```cpp
// LuaThread.cpp - ObjectToDynamicValue()
else if (obj.is<YourNewType>()) {
    return obj.as<YourNewType>();
}
```

**3. Update RmlUi converter:**
```cpp
// DataBindings.cpp - ConvertToVariant()
else if constexpr (std::is_same_v<T, YourNewType>) {
    variant = ConvertToRmlType(val);
    return true;
}
```

### Supporting Data Mutations

Currently the system is **replace-only** (entire table replaced on update). To support fine-grained updates:

**Option 1: Delta Commands**
```cpp
struct UpdateDataModelRow {
    std::string model_name;
    int row_index;
    DynamicRow new_data;
};
```

**Option 2: Immutable Updates with Structural Sharing**
Use persistent data structures to share unchanged portions between snapshots.

**Trade-off:** Complexity vs. memory savings. Current approach is simple and works well for tables up to ~10k rows at 2Hz.

### Adding Data Model Events

To notify Lua when data models are accessed:

```cpp
// DataStore.h
class DataStore {
    std::function<void(const std::string&)> on_model_read_;
public:
    void SetReadCallback(std::function<void(const std::string&)> cb) {
        on_model_read_ = cb;
    }
};

// Usage: Track which models are actually being rendered
```

## Troubleshooting

### "Row index N out of bounds" warnings

**Cause:** Data updated between `Size()` and `Child()` calls
**Solution:** None needed - system handles this gracefully by returning empty DataVariable
**Note:** Changed from WARN to DEBUG in `DataBindings.cpp:77-82` to reduce noise

### Crash in std::string copy/hash

**Cause:** Using `Seqlock<DynamicTable>` instead of `shared_ptr<DynamicTable>`
**Solution:** Ensure `DataStore` uses `shared_ptr` (fixed in commit)
**Why:** Seqlock can't guarantee atomicity for complex types with multi-step copy constructors

### Memory usage growing over time

**Cause:** Possible shared_ptr leak - old snapshots not released
**Diagnosis:** Check if `cached_data_` is being refreshed properly
**Solution:** Ensure `Size(nullptr)` is called at start of each render cycle

### UI not updating after data.update()

**Checklist:**
1. Is model bound? (`data.bind()` must be called first)
2. Is `DirtyDataModel` command being processed? (check logs)
3. Is model name correct? (case-sensitive)
4. Is `data-model="name"` attribute set on RML container?

## Key Takeaways

1. **Immutability is key**: `shared_ptr` works because snapshots are immutable
2. **Snapshot consistency**: Cache refreshed once per render cycle, not per access
3. **Arena allocation**: Prevents memory leaks from temporary DataPath objects
4. **Lock-free design**: No mutexes = no deadlocks, no priority inversion
5. **Dynamic schemas**: No need to define C++ structs, handles any Lua table shape

## References

**Implementation Files:**
- `src/DataStore.h/cpp` - Thread-safe storage
- `src/DataBindings.h/cpp` - RmlUi integration
- `src/LuaThread.cpp:34-86, 496-532` - Lua converters and API
- `src/CommandQueue.h:93-99, 119-120` - Commands
- `src/main.cpp:476-539` - Command handlers

**Related Documents:**
- [reactive-data-plan.md](reactive-data-plan.md) - Original design document
- [RmlUi Data Binding Docs](https://mikke89.github.io/RmlUiDoc/pages/cpp_manual/data_bindings.html)

**Example Usage:**
- `scripts/sqlite_demo.lua` - Full working example
- `ui/sqlite_demo.rml` - RML template with data-for loops
