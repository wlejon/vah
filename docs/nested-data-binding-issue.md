# Nested Data Binding Issue

## Problem Summary

The current data binding system doesn't properly handle immediate updates to nested arrays when using `trigger()` from the UI. This causes a brief flicker when saving changes to array fields (like input/output port names in the node type editor).

## Current Architecture

### Data Flow
1. **UI Thread (RmlUi Lua)**: User edits form → `trigger('save_node_type')` called
2. **Main Thread (DataModelManager.cpp)**:
   - Extracts tracked input values (e.g., `input_port_0`, `input_port_1`)
   - Updates DataStore row with flat fields
   - Sends event to server thread
3. **Server Thread (Lua)**:
   - Saves to database
   - Calls `data.bind()` to update models from database
   - This overwrites main thread's update

### The Issue

**DataModelManager.cpp line 184:**
```cpp
mutable_data[context_row][key] = value;
```

This only updates **flat fields**. When tracked inputs are named `input_port_0`, `input_port_1`, etc., they're stored as separate flat fields, NOT as elements in the nested `inputs` array.

**Data structure:**
```javascript
// What the UI binds to:
{
  name: "MyNode",
  inputs: ["Input1", "Input2"],  // Nested array
  outputs: ["Output1"]             // Nested array
}

// What DataModelManager updates:
{
  name: "MyNode",           // ✓ Updated immediately
  input_port_0: "Input1",   // ✓ Updated immediately (but wrong structure)
  input_port_1: "Input2",   // ✓ Updated immediately (but wrong structure)
  inputs: ["old", "old"],   // ✗ NOT updated (nested array not reconstructed)
}
```

The UI renders from `node.inputs` array, not from `input_port_0` fields, so it shows stale data until the server's `data.bind()` completes.

## Root Cause

`DataModelManager::UpdateModel()` (lines 174-200) applies tracked input values as flat key-value pairs. It doesn't understand the semantic relationship between `input_port_0` → `inputs[0]`.

## Solution Needed

### Option 1: Smart Field Reconstruction (Recommended)

Enhance `DataModelManager::UpdateModel()` to detect patterns like `input_port_N` and `output_port_N`, then reconstruct the nested arrays.

**Implementation location:** `src/DataModelManager.cpp` lines 174-200

**Logic needed:**
```cpp
// After updating flat fields, detect array patterns
std::map<std::string, std::map<int, DynamicValue>> array_fields;

for (const auto& [key, value] : payload) {
    // Parse "input_port_0" → base="input", type="port", index=0
    // Regex: "^(\\w+)_port_(\\d+)$"

    if (matches pattern) {
        array_fields[base + "s"][index] = value;  // "inputs"[0] = value
    }
}

// Reconstruct nested arrays
for (const auto& [array_name, indexed_values] : array_fields) {
    auto array = std::make_shared<DynamicMap>();
    for (const auto& [index, value] : indexed_values) {
        array->fields[std::to_string(index + 1)] = value;  // 1-based for Lua
    }
    mutable_data[context_row][array_name] = array;
}
```

### Option 2: Flatten Data Model

Change the data model to not use nested arrays - make each port a top-level field.

**Problems:**
- Dynamic number of ports becomes harder
- Less semantic structure
- Bigger refactor of Lua code

## Files Involved

- `src/DataModelManager.cpp` - Main thread update logic (lines 174-200)
- `src/DataStore.h` - Data structure definitions
- `src/RmlUiBridge.cpp` - `data.update_row()` function (could be enhanced instead)
- `scripts/workflow_app.lua` - Server-side handlers (lines 445-528)

## Current Workaround

The immediate update works for flat fields (name, colors) but nested arrays (inputs/outputs) flicker briefly until the server's `data.bind()` completes ~50-100ms later. The save persists correctly to the database.

## Priority

Medium - UX issue but not a blocker. Affects any form that edits nested array data via tracked inputs.
