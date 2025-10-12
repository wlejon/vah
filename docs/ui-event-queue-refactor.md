# UI Event Queue Refactor - Design Document

## Problem Statement

### Current Issue: Infinite Event Loop

**Symptom**: When a user clicks a button (Save, Delete), the event is processed repeatedly (30+ times) instead of once, causing log spam and redundant database operations.

**Root Cause**: Events added to `InputState.ui_events` are **never cleared**, creating an infinite loop:

```
Frame N:
1. ProcessInput() creates fresh InputState (ui_events empty)
2. User clicks button during SDL processing
3. RmlUi invokes trigger_save(id) from RML onclick handler
4. RmlUiBridge::TriggerEvent():
   - Reads seqlock (gets InputState)
   - CLEARS ui_events (current fix attempt)
   - Adds new save_contact event
   - Writes back to seqlock
5. ProcessInput() line 316: Reads seqlock AGAIN after SDL loop
   - Gets the state RmlUiBridge just wrote (with the event!)
6. ProcessInput() line 320: Copies ui_events to current_state
7. ProcessInput() line 325: Writes current_state → event back in seqlock

Frame N+1:
1. ProcessInput() creates fresh InputState
2. No user interaction
3. Line 316: Reads seqlock → STILL contains old event from Frame N
4. Line 320: Copies old event to current_state
5. Line 325: Writes current_state → event persists
6. Worker thread reads seqlock, sees new frame_number, processes event AGAIN
... loop continues forever
```

### Why This Happens

**Architectural Flaw**: Using `Seqlock<InputState>` as both:
1. **Input state holder** (mouse, keyboard positions)
2. **Event queue** (UI button clicks)

These have different semantics:
- **State**: Latest value matters, old values discarded (mouse position)
- **Events**: All values matter, each must be processed exactly once (button clicks)

**The Perpetuation Mechanism** (`src/main.cpp:314-325`):
```cpp
// Check if any UI events were triggered during SDL processing
auto state_after_triggers = input_seqlock_->Read();

// Copy any UI events that were added by trigger() during this frame
if (!state_after_triggers.ui_events.empty()) {
    current_state.ui_events = state_after_triggers.ui_events;  // ← PERPETUATION
}

// Write updated input state to seqlock
input_seqlock_->Write(current_state);  // ← Event written back
```

Once an event enters `ui_events`, it is copied frame-to-frame indefinitely.

### Secondary Issue: Missing Input Values

`trigger_save()` extracts input field values using `GetAttribute("value", "")`, but RmlUi input elements store their current value as a **property**, not an attribute. The attribute is only the initial value from RML.

**Result**: `trigger_save` payload contains only ID, missing name/email/phone/company fields.

## Current Architecture

### Key Files and Locations

**InputState Structure** (`src/InputState.h:20-60`):
```cpp
struct InputState {
    // ... mouse, keyboard state ...
    std::vector<UIEvent> ui_events;  // ← Events mixed with state
    uint64_t frame_number;

    void ClearEvents() {
        ui_events.clear();
        // ... other event vectors
    }
};
```

**RmlUiBridge Event Creation** (`src/RmlUiBridge.cpp:172-190`):
```cpp
void RmlUiBridge::TriggerEvent(const std::string& event_name, const PayloadMap& payload) {
    auto current_state = input_seqlock_->Read();
    current_state.ui_events.clear();  // Recent fix attempt

    UIEvent event;
    event.name = event_name;
    event.payload = payload;
    current_state.ui_events.push_back(event);

    input_seqlock_->Write(current_state);  // ← Writes to shared state
}
```

**Main Thread Processing** (`src/main.cpp:201-326`):
```cpp
void ProcessInput() {
    InputState current_state;
    current_state.frame_number = old_state.frame_number + 1;

    // ... SDL event loop (may trigger RmlUi events) ...

    // PROBLEM: Read events that were just written
    auto state_after_triggers = input_seqlock_->Read();
    if (!state_after_triggers.ui_events.empty()) {
        current_state.ui_events = state_after_triggers.ui_events;
    }

    input_seqlock_->Write(current_state);  // Perpetuates events
}
```

**Worker Thread Consumption** (`src/LuaThread.cpp:318-351`):
```cpp
void LuaThread::ThreadMain() {
    while (!should_stop_) {
        auto input_state = input_seqlock_->Read();

        // Only process events if this is a new frame
        if (input_state.frame_number != last_processed_frame_) {
            last_processed_frame_ = input_state.frame_number;

            for (const auto& ui_event : input_state.ui_events) {
                auto it = event_handlers_.find(ui_event.name);
                if (it != event_handlers_.end()) {
                    it->second(payload_table);  // ← Processes SAME events every frame
                }
            }
        }
    }
}
```

**The Frame Number Guard Doesn't Help**: Worker only processes events when `frame_number` changes, which happens every frame (60 Hz). Since events persist across frames, they get processed 60 times/second.

## Solution: Separate Lock-Free Event Queue

### Architecture Overview

**Separate concerns**:
1. **InputState** (Seqlock): Mouse/keyboard positions, button states (pure state)
2. **UIEventQueue** (new lock-free queue): Button click events (transient events)

```
┌─────────────────────────────────────────────────────────────┐
│                     Main Thread (RmlUi)                      │
│                                                              │
│  User clicks "Save" button                                  │
│    ↓                                                         │
│  RmlUi event handler: trigger_save(226)                     │
│    ↓                                                         │
│  RmlUiBridge::TriggerEvent("save_contact", {id: 226, ...})  │
│    ↓                                                         │
│  ui_event_queue_->Push(UIEvent{...})  ← Lock-free enqueue  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                            ↓
           ┌────────────────────────────────┐
           │   UIEventQueue (lock-free)     │
           │   Multi-producer (RmlUi)       │
           │   Single-consumer (worker)     │
           └────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                  Worker Thread (Lua Thread 2)                │
│                                                              │
│  30Hz update loop:                                          │
│    events = ui_event_queue_->PopAll()  ← Drains queue      │
│    for event in events:                                     │
│       if event.name == "save_contact":                      │
│          save_contact(event.payload.id, ...)                │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Key Properties**:
- Events consumed exactly once (PopAll drains the queue)
- No frame_number tracking needed (queue naturally transient)
- No mixing of state and events
- Follows existing CommandQueue pattern (already proven in codebase)

### Reference Implementation

**Use CommandQueue as template** (`src/CommandQueue.h` and `CommandQueue.cpp`):
- Already implements multi-producer, single-consumer lock-free queue
- Uses `moodycamel::ConcurrentQueue` under the hood
- Pattern: `Push()` from any thread, `ProcessAll()` from main thread
- Proven stable in production

**Pattern to follow**:
```cpp
// Push (from any thread)
command_queue_->Push(Commands::Something{...});

// Consume (from main thread only)
command_queue_->ProcessAll([](const Command& cmd) {
    // Process each command exactly once
});
```

### Implementation Plan

#### 1. Create UIEventQueue Class

**File**: `src/UIEventQueue.h` (new)

```cpp
#pragma once
#include "InputState.h"  // For UIEvent, PayloadMap
#include <moodycamel/concurrentqueue.h>
#include <vector>

class UIEventQueue {
public:
    UIEventQueue();
    ~UIEventQueue() = default;

    // Thread-safe push (called from RmlUi thread via RmlUiBridge)
    void Push(UIEvent&& event);

    // Drain all pending events (called from worker threads only)
    std::vector<UIEvent> PopAll();

private:
    moodycamel::ConcurrentQueue<UIEvent> queue_;
};
```

**File**: `src/UIEventQueue.cpp` (new)

```cpp
#include "UIEventQueue.h"

UIEventQueue::UIEventQueue()
    : queue_(256)  // Initial capacity
{
}

void UIEventQueue::Push(UIEvent&& event) {
    queue_.enqueue(std::move(event));
}

std::vector<UIEvent> UIEventQueue::PopAll() {
    std::vector<UIEvent> events;
    events.reserve(32);  // Common case: few events per frame

    UIEvent event;
    while (queue_.try_dequeue(event)) {
        events.push_back(std::move(event));
    }

    return events;
}
```

#### 2. Remove ui_events from InputState

**File**: `src/InputState.h:20-60`

**Remove**:
```cpp
std::vector<UIEvent> ui_events;  // ← DELETE THIS
```

**Update ClearEvents()**:
```cpp
void ClearEvents() {
    // ui_events.clear();  ← REMOVE THIS LINE
    mouse_button_events.clear();
    mouse_move_events.clear();
    key_events.clear();
}
```

**Keep** mouse/keyboard event vectors - those are still used for per-frame input processing.

#### 3. Update RmlUiBridge

**File**: `src/RmlUiBridge.h:9-27`

**Add member**:
```cpp
class RmlUiBridge {
public:
    RmlUiBridge(Seqlock<InputState>* input_seqlock, UIEventQueue* ui_event_queue);
    // ...
private:
    Seqlock<InputState>* input_seqlock_;
    UIEventQueue* ui_event_queue_;  // ← ADD THIS
    Rml::Context* context_;
};
```

**File**: `src/RmlUiBridge.cpp:141-190`

**Update constructor**:
```cpp
RmlUiBridge::RmlUiBridge(Seqlock<InputState>* input_seqlock, UIEventQueue* ui_event_queue)
    : input_seqlock_(input_seqlock)
    , ui_event_queue_(ui_event_queue)  // ← ADD THIS
    , context_(nullptr)
{
    g_bridge = this;
}
```

**Update TriggerEvent()**:
```cpp
void RmlUiBridge::TriggerEvent(const std::string& event_name, const PayloadMap& payload) {
    UIEvent event;
    event.name = event_name;
    event.payload = payload;

    // Simple enqueue - no seqlock manipulation
    ui_event_queue_->Push(std::move(event));

    LOG_DEBUG("RmlUiBridge: Triggered event '{}' with {} payload items", event_name, payload.size());
}
```

**Remove** all seqlock read/write logic from TriggerEvent.

#### 4. Update Main Thread

**File**: `src/main.cpp:126-131`

**Add UIEventQueue**:
```cpp
// In VahEngine::Initialize()
command_queue_ = std::make_unique<CommandQueue>();
input_seqlock_ = std::make_unique<Seqlock<InputState>>();
ui_event_queue_ = std::make_unique<UIEventQueue>();  // ← ADD THIS
data_store_ = std::make_unique<DataStore>();
thread_manager_ = std::make_unique<ThreadManager>(
    command_queue_.get(),
    input_seqlock_.get(),
    ui_event_queue_.get(),  // ← ADD PARAMETER
    data_store_.get()
);
rmlui_bridge_ = std::make_unique<RmlUiBridge>(
    input_seqlock_.get(),
    ui_event_queue_.get()  // ← ADD PARAMETER
);
```

**Add member variable** (`src/main.cpp:603-607`):
```cpp
std::unique_ptr<CommandQueue> command_queue_;
std::unique_ptr<Seqlock<InputState>> input_seqlock_;
std::unique_ptr<UIEventQueue> ui_event_queue_;  // ← ADD THIS
std::unique_ptr<DataStore> data_store_;
std::unique_ptr<ThreadManager> thread_manager_;
```

**File**: `src/main.cpp:201-326`

**Simplify ProcessInput()**:

REMOVE lines 314-321 entirely:
```cpp
// Check if any UI events were triggered during SDL processing
auto state_after_triggers = input_seqlock_->Read();

// Copy any UI events that were added by trigger() during this frame
if (!state_after_triggers.ui_events.empty()) {
    current_state.ui_events = state_after_triggers.ui_events;
}
```

ProcessInput() now ONLY manages input state (mouse/keyboard), not events. UI events go through the queue.

#### 5. Update ThreadManager

**File**: `src/ThreadManager.h:10-30`

**Update constructor**:
```cpp
class ThreadManager {
public:
    ThreadManager(CommandQueue* command_queue,
                  Seqlock<InputState>* input_seqlock,
                  UIEventQueue* ui_event_queue,  // ← ADD THIS
                  DataStore* data_store);
    // ...
private:
    UIEventQueue* ui_event_queue_;  // ← ADD THIS
};
```

**Update SpawnThread()** to pass ui_event_queue to LuaThread constructor.

**File**: `src/ThreadManager.cpp`

Update all places where `LuaThread` is constructed to include `ui_event_queue_`.

#### 6. Update LuaThread

**File**: `src/LuaThread.h:23-50`

**Update constructor**:
```cpp
class LuaThread {
public:
    LuaThread(int id,
              const std::string& script_path,
              CommandQueue* command_queue,
              Seqlock<InputState>* input_seqlock,
              UIEventQueue* ui_event_queue,  // ← ADD THIS
              DataStore* data_store);
    // ...
private:
    UIEventQueue* ui_event_queue_;  // ← ADD THIS
};
```

**File**: `src/LuaThread.cpp:89-100, 261-389`

**Update constructor**:
```cpp
LuaThread::LuaThread(int id, const std::string& script_path,
                     CommandQueue* command_queue,
                     Seqlock<InputState>* input_seqlock,
                     UIEventQueue* ui_event_queue,  // ← ADD THIS
                     DataStore* data_store)
    : id_(id)
    , script_path_(script_path)
    , command_queue_(command_queue)
    , input_seqlock_(input_seqlock)
    , ui_event_queue_(ui_event_queue)  // ← ADD THIS
    , data_store_(data_store)
    // ...
{
}
```

**Update ThreadMain() event dispatch** (`src/LuaThread.cpp:318-351`):

REPLACE:
```cpp
// Dispatch UI events to registered event handlers
if (input_seqlock_) {
    auto input_state = input_seqlock_->Read();

    if (input_state.frame_number != last_processed_frame_) {
        last_processed_frame_ = input_state.frame_number;

        for (const auto& ui_event : input_state.ui_events) {
            // ... process events ...
        }
    }
}
```

WITH:
```cpp
// Dispatch UI events to registered event handlers
if (ui_event_queue_) {
    auto ui_events = ui_event_queue_->PopAll();  // ← Drain queue

    for (const auto& ui_event : ui_events) {
        auto it = event_handlers_.find(ui_event.name);
        if (it != event_handlers_.end()) {
            // Convert payload to lua table
            auto payload_table = lua_->create_table();
            for (const auto& [key, value] : ui_event.payload) {
                std::visit([&](auto&& val) {
                    using T = std::decay_t<decltype(val)>;
                    if constexpr (std::is_same_v<T, std::monostate>) {
                        payload_table[key] = sol::nil;
                    } else {
                        payload_table[key] = val;
                    }
                }, value);
            }

            // Call registered handler
            try {
                it->second(payload_table);
            } catch (const sol::error& e) {
                LOG_ERROR("Lua thread {} error in event handler for '{}': {}",
                         id_, ui_event.name, e.what());
            }
        }
    }
}
```

**Remove**:
- `last_processed_frame_` member variable (no longer needed)
- Frame number tracking logic

#### 7. Fix Input Value Extraction

**File**: `src/RmlUiBridge.cpp:100-138` (trigger_save function)

REPLACE:
```cpp
auto value = name_elem->GetAttribute<Rml::String>("value", "");
```

WITH:
```cpp
// Get the "value" property, not attribute (attributes are initial values only)
const Rml::Property* prop = name_elem->GetProperty("value");
Rml::String value;
if (prop) {
    value = prop->Get<Rml::String>();
} else {
    value = "";
}
```

This extracts the **current input value** (what the user typed), not the initial value from RML.

Apply this fix to all four input element queries (name, email, phone, company).

### Expected Result

After implementation:

1. **Event processing**: Each button click processed EXACTLY once
   - Click "Save" → 1 database UPDATE
   - Click "Delete" → 1 database DELETE
   - No log spam

2. **Input values**: `trigger_save` payload contains all fields
   - `payload.id` = contact ID (from function parameter)
   - `payload.name` = current text in name input
   - `payload.email` = current text in email input
   - `payload.phone` = current text in phone input
   - `payload.company` = current text in company input

3. **No frame number tracking**: Queue naturally handles event lifecycle
   - Push → process → gone
   - No perpetuation, no frame guards

4. **Clean separation**:
   - `InputState` = pure state (mouse position, keyboard state)
   - `UIEventQueue` = transient events (button clicks)

### Verification Steps

1. **Single event processing**:
   - Add logging to `ui_event_queue_->Push()` and `PopAll()`
   - Click "Save" once
   - Verify logs show: 1 Push, 1 PopAll with 1 event, 1 handler execution

2. **Input extraction**:
   - Edit a contact's name to "Test User"
   - Click "Save"
   - Check Lua logs for payload contents
   - Verify database: `SELECT name FROM contacts WHERE id = X`

3. **Rapid clicks**:
   - Click "Save" 5 times quickly
   - Verify 5 separate events processed (5 database UPDATEs)
   - No accumulation or dropped events

4. **Thread safety**:
   - Run for 5 minutes, clicking rapidly
   - No crashes, no deadlocks
   - All events processed correctly

### Potential Pitfalls

1. **Constructor parameter order**: ThreadManager, LuaThread constructors get new parameter. Update ALL call sites.

2. **Include moodycamel header**: `#include <moodycamel/concurrentqueue.h>` in UIEventQueue.h

3. **CMakeLists.txt**: Add `src/UIEventQueue.cpp` to source list

4. **Property vs Attribute**: RmlUi input elements:
   - `GetAttribute("value")` = initial value from RML (wrong)
   - `GetProperty("value")` = current user input (correct)

5. **Move semantics**: UIEvent must be moveable. Check that `PayloadMap` (std::variant) is move-constructible.

6. **Queue capacity**: ConcurrentQueue(256) initial size. If >256 events enqueued between polls, queue automatically grows (no issue, just allocation).

## References

### Files to Modify

1. **src/UIEventQueue.h** (NEW)
2. **src/UIEventQueue.cpp** (NEW)
3. **src/InputState.h** - Remove ui_events vector
4. **src/RmlUiBridge.h** - Add UIEventQueue parameter
5. **src/RmlUiBridge.cpp** - Replace TriggerEvent impl, fix input extraction
6. **src/ThreadManager.h** - Add UIEventQueue parameter
7. **src/ThreadManager.cpp** - Pass to LuaThread
8. **src/LuaThread.h** - Add UIEventQueue parameter
9. **src/LuaThread.cpp** - Replace event dispatch with PopAll()
10. **src/main.cpp** - Create UIEventQueue, simplify ProcessInput()
11. **CMakeLists.txt** - Add UIEventQueue.cpp to sources

### Key Line Numbers (current state)

- InputState ui_events: `src/InputState.h:46`
- RmlUiBridge::TriggerEvent: `src/RmlUiBridge.cpp:172-190`
- ProcessInput event copy: `src/main.cpp:314-321`
- LuaThread event dispatch: `src/LuaThread.cpp:318-351`
- trigger_save input extraction: `src/RmlUiBridge.cpp:110-132`

### Existing Patterns

- **CommandQueue**: `src/CommandQueue.h/cpp` - Lock-free queue pattern to follow
- **Seqlock usage**: `src/InputState.h` + `src/main.cpp` - How to properly use seqlock for state
- **ThreadManager spawning**: `src/ThreadManager.cpp:32-50` - Constructor parameter passing

### RmlUi Documentation

For input element value extraction:
- `D:/projects/RmlUi/Include/RmlUi/Core/Element.h` - GetProperty() method
- `D:/projects/RmlUiDoc/pages/cpp_manual/element_packages/form.md` - Form control documentation

## Summary

**Problem**: Events in Seqlock perpetuate forever due to read-copy-write loop.

**Solution**: Separate UIEventQueue (lock-free, transient) from InputState (seqlock, persistent state).

**Pattern**: Follow CommandQueue architecture - multi-producer Push(), single-consumer PopAll().

**Key Insight**: State and events have different lifecycles. Don't mix them.

**Outcome**: Each button click → exactly one event → exactly one handler execution → clean.
