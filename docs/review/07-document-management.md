# Code Review: Document & Event Management

## Component Overview

The Document & Event Management subsystem provides the bridge between RmlUI documents and the Lua application layer. It consists of three key modules:

1. **DocumentManager** - Manages RmlUI document lifecycle, element manipulation, and hot reload
2. **EventDispatcher** - Routes events between main thread (RmlUI) and Lua worker threads
3. **FileSystem** - Provides file I/O utilities exposed to Lua for data access

The architecture enables multi-threaded Lua applications to control UI documents while maintaining thread safety through lock-free queues and main-thread-only operations for RmlUI.

## Files Reviewed

| File | Lines | Purpose |
|------|-------|---------|
| DocumentManager.cpp | 627 | Document lifecycle and element manipulation implementation |
| DocumentManager.h | 80 | Document manager interface |
| EventDispatcher.cpp | 132 | Event routing implementation |
| EventDispatcher.h | 49 | Event dispatcher interface |
| FileSystem.cpp | 329 | File operations for Lua bindings |
| FileSystem.h | 9 | File system bindings interface |
| **Total** | **1,226** | |

## Architecture & Design

### Document Lifecycle

Documents follow this lifecycle:
1. **Load** - Lua thread issues `LoadUIDocument` command → main thread loads via RmlUI context
2. **Track** - Document stored in `loaded_documents_` map with string ID
3. **Show/Hide** - Visibility toggled while document remains loaded
4. **Reload** - Document closed and reloaded (for hot reload or manual refresh)
5. **Unload** - Document removed from tracking and closed

Thread ownership is tracked via EventDispatcher, allowing document-local events to route to the correct Lua thread.

### Event Flow Architecture

**RmlUI → Lua (UI Events)**
```
RmlUI Event Handler (RmlUiBridge)
    → EventDispatcher::DispatchEvent(doc_id, event_name, payload)
    → Lookup document's owning thread
    → Enqueue to thread's ConcurrentQueue<UIEvent>
    → Lua thread polls queue via vah.check_events()
```

**Lua → RmlUI (Commands)**
```
Lua calls vah.load_document(path, id)
    → Command enqueued to main thread's command queue
    → CommandProcessor::ProcessCommands() on main thread
    → DocumentManager::LoadDocument()
    → RmlUI context loads document
```

**Global Events**
- Named events (e.g., "file_changed") registered to specific thread
- Only one thread can own a global event (enforced by assertion)
- Used for application-wide notifications

### File System Operations

Simple wrapper around `std::filesystem` providing:
- File read/write (binary safe)
- Directory operations (list, walk, create)
- Path manipulation (join, dirname, basename, etc.)
- File metadata (size, timestamps)

Returns `(result, error_string)` tuples to Lua for error handling.

### Hot Reload Mechanism

File watchers trigger commands that call:
- **HandleRmlFileChanged** - Reloads specific .rml document
- **HandleRcssFileChanged** - Clears stylesheet cache, reloads all documents
- **HandleLuaFileChanged** - Clears Lua module cache, reloads all documents

All reload operations preserve document visibility state and dispatch "document_reloaded" events to owning threads.

## Code Quality Assessment

### Strengths

1. **Clean Thread Safety Model**
   - All DocumentManager/EventDispatcher methods run on main thread only (explicit comment)
   - Lock-free concurrent queues handle cross-thread communication
   - No mutex contention or race conditions

2. **Good Hot Reload Support**
   - Preserves document visibility across reloads (DocumentManager.cpp:390, 442, 518)
   - Clears caches appropriately (stylesheet cache, Lua package.loaded)
   - Updates tracked document references to prevent dangling pointers

3. **Comprehensive ElementTextEditor Integration**
   - Full API for custom text editor element (content, tokens, config, clipboard, undo/redo)
   - Proper type checking with dynamic_cast (lines 165-169, 183-186, etc.)
   - Clear warning messages when element not found or wrong type

4. **Path Manipulation Safety**
   - Uses std::filesystem for robust path operations
   - Exception handling on all file operations
   - Returns error tuples rather than throwing to Lua

5. **Document Ownership Tracking**
   - Thread ID associated with each document
   - Events routed to correct thread automatically
   - Cleanup on thread unregister (EventDispatcher.cpp:26-32)

### Issues & Concerns

#### Critical

**1. Memory Safety: Raw Pointer Storage Without Lifetime Management**
- **Location**: DocumentManager.h:73 - `std::unordered_map<std::string, Rml::ElementDocument*> loaded_documents_`
- **Issue**: Stores raw RmlUI document pointers that can be invalidated by RmlUI context without notification
- **Risk**: Use-after-free if RmlUI closes a document (e.g., via debugger or internal cleanup)
- **Impact**: Crashes or undefined behavior when accessing stale document pointers
- **Evidence**: ReloadDocument (DocumentManager.cpp:105) erases from map, but if RmlUI closes doc externally, pointer becomes dangling

**2. Element Lookup Performance: O(n) Search Across All Documents**
- **Location**: DocumentManager.cpp:566-580 - `FindElementById()`
- **Issue**: Iterates through all documents to find element by ID
- **Complexity**: O(n * m) where n = documents, m = elements per document
- **Impact**: Performance degradation with many documents, called frequently by element manipulation functions
- **Frequency**: Called by all SetElement* functions (text, attribute, style, class, text editor operations)

**3. Document Reload Path Matching: Fragile String Comparison**
- **Location**: DocumentManager.cpp:385-387
- **Code**: `if (src == normalized_path || normalized_path.ends_with(src) || src.ends_with(normalized_path))`
- **Issue**: Unreliable path matching (absolute vs relative, forward/back slashes, case sensitivity)
- **Risk**: Hot reload may fail to match documents or reload wrong documents
- **Example**: "ui/test.rml" vs "D:/projects/vah/ui/test.rml" vs "ui\test.rml"

**4. Hot Reload Iterator Invalidation Risk**
- **Location**: DocumentManager.cpp:397-406, 449-458, 525-534
- **Issue**: Modifies `loaded_documents_` map while potentially iterating in nested code
- **Code Pattern**:
  ```cpp
  for (auto& [doc_id, tracked_doc] : loaded_documents_) {
      if (tracked_doc == doc) {
          loaded_documents_[doc_id] = new_doc;  // Modifying map during iteration
  ```
- **Risk**: Iterator invalidation if any called code iterates the map
- **Note**: Currently safe because breaks after modification, but brittle design

#### Major

**5. Missing Error Handling: Document Load Failure Not Propagated**
- **Location**: DocumentManager.cpp:34-66 - `LoadDocument()`
- **Issue**: Document load failure logged but not reported to calling Lua thread
- **Impact**: Lua thread unaware of load failure, may assume document exists
- **Expected**: Should dispatch an error event or command response to requesting thread

**6. Context Update Without Null Check After Reload**
- **Location**: DocumentManager.cpp:413, 471, 547
- **Code**: `context_->Update();` after document reload
- **Issue**: If context becomes null during reload, dereferencing null pointer
- **Note**: Unlikely but defensive null check consistent with other code

**7. EventDispatcher Registration Conflict: Assert in Production Code**
- **Location**: EventDispatcher.cpp:57-60
- **Code**: `assert(false && "Global event already registered by another thread");`
- **Issue**: Assert disabled in release builds, allows silent registration conflict
- **Impact**: Second registration succeeds, first thread's handler is orphaned
- **Recommendation**: Should return error or throw exception visible in release builds

**8. Element Modification Without Document Ownership Check**
- **Location**: All SetElement* methods (DocumentManager.cpp:122-155)
- **Issue**: Any thread can modify elements in any document via command queue
- **Risk**: Thread A modifies document owned by Thread B without coordination
- **Impact**: Potential data races in Lua-side state tracking, confusing event flow

**9. FileSystem: Unsafe Timestamp Conversion**
- **Location**: FileSystem.cpp:113-122
- **Code**: Complex `file_time_type` to `system_clock` conversion
- **Issue**: Uses clock offset arithmetic that may be incorrect across platforms
- **Risk**: Incorrect file modification times reported to Lua
- **Alternative**: Use C++20 `file_clock::to_sys()` or platform-specific functions

#### Minor

**10. Duplicate Code: Reload Logic Repeated Three Times**
- **Location**: DocumentManager.cpp:372-423, 425-472, 474-548
- **Issue**: HandleRmlFileChanged, HandleRcssFileChanged, HandleLuaFileChanged share ~95% identical code
- **Impact**: Maintenance burden, bug fixes need to be applied three times
- **Recommendation**: Extract common reload logic into private helper function

**11. Mixed Naming Conventions: document_id vs element_id**
- **Location**: Throughout DocumentManager interface
- **Issue**: Inconsistent naming (document_id uses snake_case, but document itself is camelCase)
- **Minor**: Doesn't affect functionality but reduces code consistency

**12. GetTextEditorContent/Modified Return Default Values on Error**
- **Location**: DocumentManager.cpp:338-370
- **Issue**: Returns empty string or false on error, indistinguishable from valid empty/unmodified state
- **Impact**: Lua cannot detect errors (unlike FileSystem which returns nil + error)
- **Recommendation**: Match FileSystem pattern with `(result, error)` tuple or throw

**13. document_changed_this_frame_ Flag Never Set to True**
- **Location**: DocumentManager.h:76, DocumentManager.cpp:22-25
- **Issue**: Flag defined but never set to true anywhere in the codebase
- **Status**: Dead code or incomplete feature
- **Action**: Remove flag or implement the feature it was intended for

**14. UpdateTrackedDocument Function Unused**
- **Location**: DocumentManager.cpp:557-564
- **Issue**: Public method defined but grep shows no callers
- **Status**: Dead code or API prepared for future use
- **Recommendation**: Remove if truly unused, or document intended use case

**15. FileSystem: Exception Swallowing in Catch-All Blocks**
- **Location**: FileSystem.cpp - lines 71, 105, 120, 136, 174, 214, 229
- **Code**: `catch (...) { return 0/empty/false; }`
- **Issue**: Silently swallows all exceptions without logging
- **Impact**: Debugging difficulty, errors invisible to developer
- **Recommendation**: At minimum log exceptions before returning defaults

**16. FileSystem Walk: Callback Return Value Ambiguity**
- **Location**: FileSystem.cpp:220-227
- **Issue**: Checks if callback returns boolean false to stop, but continues on non-boolean return
- **Behavior**: Callback returning nil/number/string won't stop iteration
- **Recommendation**: Document behavior or treat non-boolean as "continue"

**17. Lua Module Name Extraction Fragile**
- **Location**: DocumentManager.cpp:484-495
- **Issue**: Simple string manipulation to extract module name from path
- **Risk**: Fails on paths with multiple dots (e.g., "ui/canvas.test.lua")
- **Result**: Would clear wrong module from package.loaded
- **Example**: "ui/canvas.test.lua" → "canvas.test" (wrong) vs "canvas" (should try multiple)

### Event Flow Analysis

**Event Types**

1. **Document-Local Events** (DispatchEvent)
   - Routed to document's owning thread
   - Examples: button clicks, text editor changes, custom element events
   - Thread lookup via `document_to_thread_` map

2. **Global Events** (DispatchGlobalEvent)
   - Routed to single registered handler thread
   - Examples: file_changed, application-wide notifications
   - Thread lookup via `global_events_` map

3. **Direct Thread Events** (DispatchToThread)
   - Explicitly routed to thread ID
   - Used for inter-thread communication, responses

**Event Flow Integrity**

- **Good**: Lock-free queues prevent message loss
- **Good**: Events continue queuing even if Lua thread is busy
- **Risk**: Unbounded queue growth if Lua thread stops polling
- **Missing**: No queue size limits or overflow detection
- **Missing**: No event priority or ordering guarantees beyond FIFO

**Document Ownership Lifecycle**

```
LoadUIDocument command
  → DocumentManager::LoadDocument
  → EventDispatcher::RegisterDocument(doc_id, thread_id)
  → Document now owned by thread

Thread stops
  → EventDispatcher::UnregisterThread(thread_id)
  → All documents owned by thread removed from document_to_thread_
  → Documents still loaded in RmlUI but events will be dropped
```

**Issue**: Documents remain loaded when owning thread dies, creating "orphan documents" that accept no events.

### File System Operations

**Safety Properties**

- All operations catch exceptions and return error strings
- Binary-safe file I/O (ios::binary flag)
- Path operations use std::filesystem (portable)

**Error Handling Patterns**

1. **Tuple Return**: `(result, error_string)` - Lua pattern for error handling
2. **Empty Defaults**: Simple operations return "" or false on error (less safe)
3. **Exception Swallowing**: Catch-all blocks hide errors (problematic)

**Path Utilities Coverage**

- **Complete**: join, dirname, basename, extension, stem, absolute_path
- **Missing**: normalize (resolve .., .), relative_path, canonical path
- **Missing**: Path validation/sanitization

**Security Considerations**

- No path traversal protection (Lua can read/write any accessible file)
- No whitelist/blacklist for file access
- Appropriate for trusted Lua scripts, dangerous if loading untrusted scripts

## Recommendations

### Priority 1 (Critical - Address Immediately)

1. **Fix Document Pointer Lifetime Management**
   - Replace raw pointers with weak_ptr or reference counting
   - Add validation before dereferencing (check IsValid() or similar)
   - OR: Register observer with RmlUI to update map on document close

2. **Optimize Element Lookup**
   - Cache last-accessed document for repeated operations
   - Maintain document_id → document map for O(1) lookup
   - Pass document_id hint to FindElementById to skip search

3. **Improve Path Matching for Hot Reload**
   - Normalize all paths to absolute canonical form before comparison
   - Use std::filesystem::equivalent() for reliable comparison
   - Handle both forward and back slashes on Windows

4. **Add Error Propagation for Document Load**
   - Dispatch "document_load_failed" event to requesting thread
   - Include error message in event payload
   - Allow Lua to handle failure (retry, show error UI, etc.)

### Priority 2 (Major - Address Soon)

5. **Replace Assert with Runtime Error Check**
   - In EventDispatcher::RegisterGlobalEvent, return false or throw on conflict
   - Log error and return gracefully instead of asserting

6. **Add Document Ownership Enforcement**
   - Store document_id in Command structs for element operations
   - Validate thread owns document before allowing modifications
   - OR: Document design decision if cross-thread modification is intentional

7. **Fix Timestamp Conversion**
   - Use C++20 `std::chrono::file_clock::to_sys()` if available
   - Else: Use platform-specific conversions (Windows: FILETIME, Linux: timespec)
   - Add unit test to verify timestamp accuracy

8. **Add Event Queue Overflow Protection**
   - Set maximum queue size (e.g., 1000 events)
   - Log warning when queue > 80% full
   - Option: Drop oldest events or newest events when full

### Priority 3 (Minor - Address When Convenient)

9. **Refactor Reload Logic**
   - Extract common code into `ReloadDocumentsForFileChange()`
   - Pass predicates or flags to customize behavior (clear CSS cache, clear Lua cache)

10. **Improve Error Handling Consistency**
    - Unify GetTextEditorContent/Modified to return (result, error) tuples
    - OR: Expose error log mechanism to Lua for async error checking

11. **Add FileSystem Exception Logging**
    - Log exception messages before returning defaults
    - Helps debugging without changing API contract

12. **Handle Orphaned Documents**
    - Add CloseDocument command so Lua can explicitly close on shutdown
    - OR: Auto-close all documents owned by thread when thread dies
    - Document the current behavior (documents remain loaded)

13. **Remove Dead Code**
    - Delete `document_changed_this_frame_` flag and GetAndClearDocumentChangedFlag
    - Delete UpdateTrackedDocument if truly unused
    - OR: Document intended future use

14. **Improve Lua Module Name Extraction**
    - Try multiple module name candidates (full path, partial paths)
    - Clear package.loaded for all possible matches
    - Log which modules were cleared for debugging

### Priority 4 (Nice to Have)

15. **Add FileSystem Path Validation**
    - Optional security mode restricting access to workspace directory
    - Path sanitization utility (remove .., ., etc.)
    - Useful if loading untrusted Lua scripts in future

16. **Add Document Query Batching**
    - Allow getting info for multiple documents in one command
    - Reduces command queue round-trips for tooling/debugging

17. **Event Metrics and Debugging**
    - Track event queue depth per thread
    - Log slow event processing (time between enqueue and dequeue)
    - Expose metrics to MCP API for monitoring

## Dependencies & Integration

### Internal Dependencies

- **RmlUiBridge**: Receives RmlUI events, calls EventDispatcher, provides current document ID
- **ElementTextEditor**: Custom element type with specialized API for code editing
- **DataStore**: Provides DynamicTable/DynamicValue types for structured data
- **CommandProcessor**: Processes commands from Lua threads, calls DocumentManager methods
- **Logger**: Centralized logging (LOG_INFO, LOG_WARN, LOG_ERROR macros)

### External Dependencies

- **RmlUi**: Document/element lifecycle, rendering, event system
- **SDL2**: Mouse state for hover recalculation (DocumentManager.cpp:60-61)
- **Lua/Sol2**: Lua bindings for FileSystem, RmlUI Lua interpreter for hot reload
- **std::filesystem**: Modern C++ path and file operations
- **moodycamel::ConcurrentQueue**: Lock-free queues for thread communication

### Integration Points

**CommandProcessor → DocumentManager**
- Commands: LoadUIDocument, ShowUIDocument, HideUIDocument, ReloadUIDocument
- Commands: SetElement*, TextEditor* operations
- Commands: FileChanged (triggers hot reload handlers)

**RmlUiBridge → EventDispatcher**
- RmlUI events (click, change, etc.) dispatched to owning Lua thread
- Custom events from Lua <script> tags

**DocumentManager → EventDispatcher**
- Dispatches "document_reloaded" after hot reload
- Uses document ownership info for event routing

**Lua → FileSystem**
- Direct calls to fs.* functions (read, write, stat, walk, etc.)
- No event queue, synchronous operations
- Returns to Lua immediately (blocking I/O on calling thread)

### Thread Safety Model

**Main Thread Only** (no synchronization needed):
- All DocumentManager methods
- All EventDispatcher registration/dispatch methods
- RmlUI context access

**Lock-Free Cross-Thread**:
- Command enqueue (Lua thread → main thread)
- Event enqueue (main thread → Lua thread)
- Uses moodycamel::ConcurrentQueue

**Thread-Local**:
- FileSystem operations (each Lua thread calls independently)
- No shared state between threads

### Coupling Analysis

- **DocumentManager ↔ EventDispatcher**: Loose coupling via interface, good
- **DocumentManager ↔ RmlUiBridge**: Tight coupling for current document tracking
- **EventDispatcher ↔ CommandProcessor**: Implicit coupling via command processing pattern
- **FileSystem → (Independent)**: Zero coupling, pure utility module

## Summary

The Document & Event Management subsystem provides a solid foundation for multi-threaded UI programming with clear separation between main thread (RmlUI) and worker threads (Lua). The event routing architecture is well-designed with lock-free queues preventing race conditions.

**Key Strengths**: Clean threading model, comprehensive hot reload, good ElementTextEditor integration, robust file system utilities.

**Critical Issues**: Document pointer lifetime management, O(n) element lookup, fragile path matching for hot reload, missing error propagation.

**Recommended Focus**: Address the pointer lifetime safety issue first (most likely to cause production crashes), then optimize element lookup (performance), then improve hot reload reliability (developer experience).

The codebase shows good understanding of multi-threaded programming patterns and maintains thread safety effectively. Most issues are refinement opportunities rather than fundamental design flaws. With the recommended fixes, this component should be production-ready.
