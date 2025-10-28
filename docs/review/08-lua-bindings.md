# Code Review: Lua Bindings (Database & HTTP)

## Component Overview

This review covers the Lua bindings layer that exposes C++ functionality to the Lua scripting environment. The bindings provide access to:

- **SQLite Database** - Full database operations including queries, transactions, and batch inserts
- **HTTP Client/Server** - HTTP requests with SSE (Server-Sent Events) streaming support and HTTP server capabilities
- **JSON** - Bidirectional JSON encoding/decoding between Lua tables and JSON strings
- **File Watcher** - File system monitoring with event callbacks
- **File Ingestion** - Bulk file/directory metadata extraction and analysis
- **Clipboard** - System clipboard text operations

The bindings use the **sol2** library for Lua/C++ integration and follow a consistent pattern of returning tuples with `(result, error_message)` for error handling.

## Files Reviewed

| File | Lines | Purpose |
|------|-------|---------|
| `SqliteBindings.cpp` | 588 | SQLite database operations |
| `SqliteBindings.h` | 8 | SQLite header |
| `HttpBindings.cpp` | 586 | HTTP client/server with SSE streaming |
| `HttpBindings.h` | 12 | HTTP header |
| `JsonBindings.cpp` | 155 | JSON encoding/decoding |
| `JsonBindings.h` | 13 | JSON header |
| `FileWatcherBindings.cpp` | 136 | File system change monitoring |
| `FileWatcherBindings.h` | 9 | File watcher header |
| `FileIngestionBindings.cpp` | 129 | File/directory metadata extraction |
| `FileIngestionBindings.h` | 8 | File ingestion header |
| `ClipboardBindings.cpp` | 49 | Clipboard text operations |
| `ClipboardBindings.h` | 10 | Clipboard header |
| **Total** | **1,703** | |

## Architecture & Design

### Binding Pattern

All bindings follow a consistent architecture:

1. **RAII Wrapper Classes** - C++ classes that manage underlying resources (Database, HttpServer, FileWatcherWrapper)
2. **Free Functions** - Direct function bindings for stateless operations (http.get, json.encode, clipboard.get_text)
3. **Error Handling** - Tuple returns: `(result, error_message)` where error_message is empty string on success
4. **Resource Ownership** - Lua owns all wrapper objects via shared_ptr or direct ownership
5. **Thread Safety** - Each LuaThread gets its own Lua state with bindings; uses lock-free atomics for cross-thread communication

### Integration Points

- **LuaThread** - Each thread gets bindings initialized via `SetupBindings()`
- **sol2** - Modern C++/Lua binding library providing type safety
- **httplib** - HTTP client/server library (cpp-httplib)
- **efsw** - Cross-platform file watcher library
- **SQLite3** - Embedded database
- **nlohmann/json** - JSON parsing library
- **SDL2** - Clipboard operations

### Key Design Decisions

1. **Lock-Free Communication** - HttpBindings stores LuaThread pointer in Lua registry for abort signaling during SSE streams
2. **Per-Thread Resources** - FileWatcher instances are owned by each thread, avoiding cross-thread issues
3. **Streaming Support** - HTTP client/server both support SSE with callback-based event handling
4. **SQLITE_TRANSIENT** - Used for string binding to ensure SQLite copies strings (prevents use-after-free)
5. **JSON Array Detection** - Lua tables are analyzed to determine if they're arrays (sequential 1-based integer keys) or objects

## Code Quality Assessment

### Strengths

1. **Consistent Error Handling**
   - All functions use tuple returns with `(result, error)` pattern
   - Lua code can easily check: `local result, err = db:query(sql)`
   - Exceptions are caught and converted to error messages

2. **Proper Resource Management**
   - RAII classes with destructors (Database, HttpServer, FileWatcherWrapper)
   - sqlite3_finalize() called on all prepared statements
   - SDL_free() used for SDL-allocated memory
   - Unique/shared pointers used appropriately

3. **Type Safety with sol2**
   - Template-based type checking at compile time
   - sol::optional for optional parameters
   - sol::variadic_args for variadic parameters
   - Type conversions handled automatically

4. **Good Logging**
   - Debug logging for operations (file watch add/remove, HTTP server routes)
   - Error logging for failures (handler errors, stream errors)

5. **Streaming Architecture**
   - SSE parsing implemented correctly for both GET and POST
   - Thread cancellation support (checks `thread->ShouldStop()`)
   - Callback-based event delivery
   - JSON auto-parsing in SSE events (falls back to string if not JSON)

6. **SQL Injection Protection**
   - Uses prepared statements with parameter binding
   - Never constructs SQL with string concatenation (except GetTableInfo which uses PRAGMA)

### Issues & Concerns

#### Critical Issues

**C1. SQL Injection in GetTableInfo** (SqliteBindings.cpp:424)
```cpp
std::string sql = "PRAGMA table_info(" + table_name + ")";
```
- **Issue**: Direct string concatenation allows SQL injection
- **Attack Vector**: `table_name = "); DROP TABLE users; --"`
- **Fix**: While PRAGMA is somewhat protected, should still validate table_name against allowed characters or use `TableExists()` first
- **Severity**: High - Can lead to arbitrary SQL execution

**C2. SQL Injection in BatchInsert** (SqliteBindings.cpp:346-356)
```cpp
std::string sql = "INSERT INTO " + table + " (";
for (size_t i = 0; i < col_names.size(); i++) {
    if (i > 0) sql += ", ";
    sql += col_names[i];
}
```
- **Issue**: Both `table` and column names are concatenated without validation
- **Attack Vector**: `table = "users; DROP TABLE passwords--"` or column names with SQL
- **Fix**: Validate table/column names against SQLite identifier rules
- **Severity**: Critical - Allows arbitrary SQL execution

**C3. No HTTPS Support Detection** (HttpBindings.cpp:19-36)
```cpp
parts.scheme = matches[1].str();
// ...
httplib::Client client(url_parts.host, url_parts.port);
```
- **Issue**: URL regex accepts "https://" but httplib::Client doesn't support HTTPS without SSL configuration
- **Impact**: HTTPS requests will silently fail or connect insecurely
- **Fix**: Check scheme and use httplib::SSLClient for HTTPS, or return error if HTTPS not supported
- **Severity**: High - Security implications (downgrade attacks)

**C4. Unbounded Memory Growth in SSE Streaming** (HttpBindings.cpp:64, 302)
```cpp
buffer.append(data, len);
```
- **Issue**: If server never sends newlines, buffer grows unbounded
- **Impact**: Memory exhaustion, DoS
- **Fix**: Implement max buffer size (e.g., 10MB) and abort if exceeded
- **Severity**: High - DoS vulnerability

#### Major Issues

**M1. BLOB Data Loss** (SqliteBindings.cpp:141-144, 241-243)
```cpp
case SQLITE_BLOB:
    // For now, skip blobs or convert to hex string
    row[col_names[i]] = sol::nil;
    break;
```
- **Issue**: BLOB data is silently dropped
- **Impact**: Data loss when querying tables with BLOB columns
- **Fix**: Convert to base64 string or return as Lua string
- **Severity**: Medium - Data loss

**M2. Duplicate SSE Parsing Logic** (HttpBindings.cpp:40-137, 295-358)
- **Issue**: Identical SSE parsing code duplicated in GET and POST
- **Impact**: Maintenance burden, bug fixes need to be applied twice
- **Fix**: Extract to shared function `ParseSSEResponse()`
- **Severity**: Medium - Code quality

**M3. Missing Error Check on sqlite3_close** (SqliteBindings.cpp:37)
```cpp
void Close() {
    if (db_) {
        sqlite3_close(db_);
        db_ = nullptr;
    }
}
```
- **Issue**: sqlite3_close() can fail if statements are still active
- **Impact**: Resource leaks, database file locks
- **Fix**: Use sqlite3_close_v2() which waits for statements to finalize
- **Severity**: Medium - Resource leak

**M4. No Timeout on File Watcher Operations** (FileWatcherBindings.cpp:75-88)
- **Issue**: File watcher callbacks execute on watcher thread without timeout
- **Impact**: If Lua callback blocks, file watcher thread hangs
- **Fix**: Add timeout mechanism or warning in documentation
- **Severity**: Medium - Can cause thread hangs

**M5. Race Condition in HttpServer::Stop** (HttpBindings.cpp:546-550)
```cpp
void Stop() {
    if (server_) {
        server_->stop();
    }
}
```
- **Issue**: If called from different thread while Listen() is running, potential race
- **Impact**: Crash or undefined behavior
- **Fix**: Already using atomic for active_http_server_, but Stop() doesn't check it
- **Severity**: Medium - Thread safety issue

**M6. Missing Content-Type Handling in HTTP POST** (HttpBindings.cpp:381)
```cpp
auto res = client.Post(url_parts.path, headers, body, content_type);
```
- **Issue**: `content_type` defaults to "application/json" but is never read from config
- **Impact**: Always sends JSON content-type even if body is form data
- **Fix**: Allow content_type to be specified in config, or detect from body
- **Severity**: Medium - API usability

**M7. JSON Array Detection Algorithm Fragility** (JsonBindings.cpp:29-41)
```cpp
bool is_array = true;
size_t expected_key = 1;
size_t count = 0;

for (const auto& pair : tbl) {
    count++;
    if (!pair.first.is<int>() || pair.first.as<int>() != static_cast<int>(expected_key)) {
        is_array = false;
        break;
    }
    expected_key++;
}
```
- **Issue**: Lua table iteration order is not guaranteed; this may fail to detect arrays correctly
- **Impact**: Arrays might be serialized as objects
- **Fix**: Check if table has keys 1..N without gaps, regardless of iteration order
- **Severity**: Medium - Correctness issue

**M8. No Connection Pooling** (SqliteBindings.cpp:19-33)
- **Issue**: Each Database instance opens its own connection
- **Impact**: Resource waste, potential locking issues with multiple connections
- **Fix**: Consider connection pool or document single-connection pattern
- **Severity**: Low-Medium - Performance/resource management

#### Minor Issues

**m1. Inconsistent Header Parsing** (HttpBindings.cpp:158-169, 253-264)
- Identical header parsing duplicated in GET and POST
- Should be extracted to helper function

**m2. Magic Numbers** (HttpBindings.cpp:50-51, 288-289)
```cpp
client.set_connection_timeout(30);
client.set_read_timeout(300);  // 5 minutes for long streams
```
- Hardcoded timeouts should be constants or configurable

**m3. Poor Error Messages** (SqliteBindings.cpp:104)
```cpp
return {sol::nil, "Unsupported parameter type at index " + std::to_string(param_index)};
```
- Should include the actual type name for debugging

**m4. Missing Path Validation** (FileIngestionBindings.cpp:36-48)
- No validation that paths exist before attempting ingestion
- Lua code must handle errors, but validation would improve UX

**m5. No Size Limits on Clipboard** (ClipboardBindings.cpp:7-24)
- Clipboard could contain very large text (e.g., entire file)
- Could cause memory issues if Lua stores multiple clipboard snapshots

**m6. Inefficient String Handling** (HttpBindings.cpp:74, 313)
```cpp
if (!line.empty() && line.back() == '\r') {
    line.pop_back();
}
```
- Creates unnecessary string copies during SSE parsing
- Minor performance impact, but could use string_view

**m7. No HTTP Method Validation** (HttpBindings.cpp:509-513)
```cpp
if (method == "GET") {
    server_->Get(pattern, cpp_handler);
} else if (method == "POST") {
    server_->Post(pattern, cpp_handler);
}
```
- Silently ignores unsupported methods (PUT, DELETE, etc.)
- Should return error or support more methods

**m8. Missing Documentation**
- No doc comments on binding functions
- Lua users need to read C++ code to understand APIs

### Security Analysis

#### SQL Injection Vulnerabilities

**Severity: Critical**

1. **GetTableInfo** (line 424) - Direct concatenation of table name
2. **BatchInsert** (lines 346-356) - Direct concatenation of table and column names

**Recommended Fixes:**
```cpp
// Option 1: Validate identifiers
bool IsValidSQLiteIdentifier(const std::string& name) {
    if (name.empty() || name.size() > 128) return false;
    if (name[0] >= '0' && name[0] <= '9') return false;
    for (char c : name) {
        if (!std::isalnum(c) && c != '_') return false;
    }
    return true;
}

// Option 2: Quote identifiers
std::string QuoteIdentifier(const std::string& name) {
    std::string quoted = "\"";
    for (char c : name) {
        if (c == '"') quoted += "\"\"";  // Escape quotes
        else quoted += c;
    }
    quoted += "\"";
    return quoted;
}
```

#### Path Traversal

**Severity: Medium**

- **FileIngestion** - No path validation, could access arbitrary files
- **FileWatcher** - Can watch any directory user has permissions for
- **SQLite Database::Open** - Can open any .db file

**Mitigation**: Document that these bindings trust Lua code. If untrusted Lua scripts are executed, implement path whitelisting.

#### HTTPS/TLS Issues

**Severity: High**

- HTTPS URLs accepted but not supported properly
- No certificate validation
- No way to configure TLS settings

**Recommended Fix:**
```cpp
// Check scheme and fail fast
if (url_parts.scheme == "https") {
    #ifdef CPPHTTPLIB_OPENSSL_SUPPORT
        httplib::SSLClient client(url_parts.host, url_parts.port);
        // ... configure cert verification
    #else
        return {sol::nil, "HTTPS not supported in this build"};
    #endif
}
```

#### Denial of Service

**Severity: Medium-High**

1. **Unbounded Buffer Growth** - SSE streaming can cause memory exhaustion
2. **No Query Timeouts** - Long-running SQL queries can't be canceled
3. **No File Count Limits** - FileIngestion has default of 10,000 but can be overridden to unlimited

**Recommended Fixes:**
- Add max buffer size to SSE parsing (10MB limit)
- Add SQLite busy timeout and progress handler
- Enforce maximum file count limit

#### XSS in HTTP Server

**Severity: Low**

- HTTP server doesn't sanitize response bodies
- If Lua code echoes user input without escaping, XSS possible
- This is Lua code's responsibility, but could provide helper functions

### Resource Management

#### Connection Lifecycle

**SQLite:**
- Database objects are RAII-managed
- Close on destruction or explicit close()
- Should use sqlite3_close_v2() instead of sqlite3_close()
- No connection pooling - each Database instance = one connection

**HTTP:**
- httplib::Client is created per-request (no keep-alive between requests)
- httplib::Server runs blocking on LuaThread
- Server properly stops via atomic pointer on thread shutdown

**File Watcher:**
- Each LuaThread gets its own FileWatcher instance
- Listeners stored in unordered_map to keep them alive
- Watcher stopped on destruction

#### Memory Management

**String Handling:**
- SQLITE_TRANSIENT used correctly for string binding (SQLite copies)
- SDL_free() used for SDL-allocated clipboard text
- std::string used throughout (RAII)

**Lua Object Lifetime:**
- sol::function callbacks stored in vectors to prevent GC
- Lua tables created via lua.create_table() are owned by Lua GC
- No manual lua_ref/lua_unref - sol2 handles this

**Potential Leaks:**
- sqlite3_finalize() called on all prepared statements
- No obvious memory leaks detected
- SSE buffer growth is the main memory concern

#### File Handles

**FileWatcher:**
- efsw::FileWatcher manages file handles internally
- Platform-specific (inotify on Linux, ReadDirectoryChangesW on Windows)
- No explicit handle limits

**File Ingestion:**
- Files opened briefly for metadata/binary detection
- No long-lived handles
- Potential issue: Ingesting 10,000+ files opens each one briefly

### API Usability

#### Lua API Design

**Strengths:**
```lua
-- Consistent error handling
local db, err = db.open("data.db")
if err ~= "" then error(err) end

local result, err = db:query("SELECT * FROM users WHERE id = ?", user_id)
if err ~= "" then error(err) end

-- Clean streaming API
http.get(url, {
    on_event = function(event_type, data)
        print(event_type, data)
    end,
    on_error = function(err)
        print("Error:", err)
    end
})
```

**Weaknesses:**

1. **No Chaining** - Can't chain operations: `db:query():map():filter()`
2. **Empty String vs nil** - Error checking requires `err ~= ""`, could use nil
3. **No Iterator Support** - Query results are full tables, not iterators
4. **Table/Column Names Unsafe** - No validation or escaping helpers
5. **No HTTP Response Type** - Response is table, not userdata with methods

#### Error Handling Patterns

**Current Pattern:**
```lua
local result, err = operation()
if err ~= "" then
    -- handle error
end
```

**Alternative (more Lua-idiomatic):**
```lua
local ok, result = pcall(function()
    return operation()  -- throws on error
end)
```

Both patterns are valid. Current pattern avoids exceptions, which is good for performance and stack traces.

#### Missing Features

1. **SQLite:**
   - No BLOB support (returns nil)
   - No custom functions/aggregates
   - No full-text search (FTS) helpers
   - No incremental BLOB I/O
   - No backup API

2. **HTTP:**
   - No PUT/DELETE/PATCH methods
   - No multipart form data
   - No cookie management
   - No redirect following control
   - No progress callbacks for uploads
   - No connection pooling/keep-alive

3. **JSON:**
   - No streaming JSON parser for large files
   - No JSON Schema validation
   - No JSON Pointer/Path queries

4. **File Watcher:**
   - No filtering (watch specific extensions)
   - No debouncing (multiple rapid changes)
   - No recursive depth control

## Recommendations

### Priority 1: Security Fixes (Immediate)

1. **Fix SQL Injection in GetTableInfo and BatchInsert**
   - Add identifier validation function
   - Quote identifiers before concatenation
   - Estimated effort: 2-3 hours

2. **Fix HTTPS Support**
   - Detect HTTPS and fail with clear error if not supported
   - If SSL available, use SSLClient
   - Estimated effort: 3-4 hours

3. **Add SSE Buffer Limits**
   - Implement 10MB max buffer size
   - Abort stream with error if exceeded
   - Estimated effort: 1-2 hours

### Priority 2: Correctness Issues (Short-term)

4. **Fix BLOB Handling**
   - Implement base64 encoding for BLOBs
   - Add helper to decode base64 to BLOB for inserts
   - Estimated effort: 3-4 hours

5. **Use sqlite3_close_v2()**
   - Replace sqlite3_close() with sqlite3_close_v2()
   - Test with pending statements
   - Estimated effort: 30 minutes

6. **Refactor SSE Parsing**
   - Extract to shared function
   - Reduce code duplication
   - Estimated effort: 2-3 hours

7. **Fix JSON Array Detection**
   - Check for keys 1..N instead of relying on iteration order
   - Add test cases
   - Estimated effort: 1-2 hours

### Priority 3: API Improvements (Medium-term)

8. **Add SQL Identifier Escaping Helpers**
   ```lua
   db:query("INSERT INTO " .. db.quote_identifier(table_name) .. " VALUES (?)", value)
   ```
   - Estimated effort: 2 hours

9. **Add More HTTP Methods**
   - Support PUT, DELETE, PATCH, HEAD
   - Estimated effort: 2-3 hours

10. **Improve Error Messages**
    - Include type names in errors
    - Add context (file names, line numbers where applicable)
    - Estimated effort: 2-3 hours

11. **Add Content-Type Configuration**
    - Allow POST to specify content type
    - Auto-detect from body when possible
    - Estimated effort: 1-2 hours

### Priority 4: Performance & Robustness (Long-term)

12. **Add SQLite Query Timeout**
    - Use sqlite3_progress_handler()
    - Allow cancellation from Lua
    - Estimated effort: 4-5 hours

13. **Implement Connection Pooling**
    - For SQLite, share connections when safe
    - Document thread safety
    - Estimated effort: 8-10 hours

14. **Add Streaming JSON Parser**
    - For large JSON files
    - Iterator-based API
    - Estimated effort: 6-8 hours

15. **Add File Watcher Filtering**
    - Watch specific extensions
    - Debounce rapid changes
    - Estimated effort: 4-5 hours

### Priority 5: Documentation & Testing

16. **Add API Documentation**
    - Write Lua API docs
    - Include examples
    - Document error conditions
    - Estimated effort: 8-10 hours

17. **Add Unit Tests**
    - Test SQL injection protection
    - Test SSE parsing edge cases
    - Test JSON array detection
    - Estimated effort: 10-15 hours

## Dependencies & Integration

### External Libraries

| Library | Purpose | Version Notes |
|---------|---------|---------------|
| **sol2** | Lua/C++ binding | Header-only, modern C++ |
| **SQLite3** | Database | Stable API, widely used |
| **httplib** (cpp-httplib) | HTTP client/server | Single-header, check SSL support |
| **nlohmann/json** | JSON parsing | Header-only, v3.x |
| **efsw** | File watching | Cross-platform, platform-specific backends |
| **SDL2** | Clipboard | Only used for clipboard, large dependency |

### Thread Safety Model

**Key Principles:**
1. Each LuaThread has its own Lua state (no shared state)
2. Bindings initialized per-thread via SetupBindings()
3. Cross-thread communication uses lock-free queues and atomics
4. LuaThread pointer stored in Lua registry for abort signaling
5. FileWatcher, Database, HttpServer instances owned by single thread

**Thread-Safe Components:**
- Lock-free response queues (moodycamel::ConcurrentQueue)
- Atomic flags (should_stop, active_http_server)
- Lua registry access (lock-free)

**NOT Thread-Safe:**
- Lua state (by design - one per thread)
- Database instances (SQLite connections not shared)
- HttpServer instances (block on single thread)
- FileWatcher instances (callbacks execute on watcher thread, but safe because same thread as Lua)

### Integration with LuaThread

**Initialization Order:**
```cpp
// From LuaThread::SetupLuaBindings()
FileSystemBindings::SetupBindings(*lua_);      // First - no deps
JsonBindings::SetupBindings(*lua_);            // No deps
SqliteBindings::SetupBindings(*lua_);          // No deps
HttpBindings::SetupBindings(*lua_, this);      // Needs LuaThread*
FileWatcherBindings::SetupBindings(*lua_);     // No deps
FileIngestionBindings::SetupBindings(*lua_);   // No deps
ClipboardBindings::SetupBindings(*lua_);       // No deps
```

**Shutdown Sequence:**
1. LuaThread::Stop() sets should_stop atomic
2. Active HTTP servers check should_stop and abort
3. SSE streams check thread->ShouldStop() and abort
4. FileWatcher destroyed (stops watching)
5. Database closed (finalizes statements)
6. Lua state destroyed (triggers RAII destructors)

### Potential Integration Issues

1. **HTTP Server Blocking** - Server.listen() blocks the LuaThread
   - This is intentional design
   - Lua script can't do other work while server is running
   - Could be improved with non-blocking API

2. **File Watcher Callback Thread** - Callbacks execute on efsw's internal thread
   - Comment says "same thread" but this may not be accurate
   - Could cause issues if Lua state is not thread-safe
   - **NEEDS VERIFICATION**

3. **SQLite Busy Handling** - No sqlite3_busy_timeout() set
   - Multiple threads accessing same DB file will get SQLITE_BUSY
   - Should set busy timeout or document single-writer pattern

4. **SDL Dependency for Clipboard** - Heavy dependency for simple feature
   - Consider platform-specific clipboard APIs
   - Or document as optional feature

## Conclusion

The Lua bindings are generally well-designed and follow good practices for C++/Lua integration. The code demonstrates:

- Strong RAII discipline
- Consistent error handling
- Good use of modern C++ features
- Clean separation of concerns

However, there are **critical security issues** that must be addressed immediately:

1. SQL injection in GetTableInfo and BatchInsert
2. HTTPS support issues
3. Unbounded memory growth in SSE streaming

The API is usable but could be improved with better documentation, more features, and performance optimizations. The thread safety model is sound but relies on careful usage - each thread must have its own instances.

**Overall Grade: B-**
- Security: C (critical SQL injection issues)
- Correctness: B+ (minor bugs, BLOB data loss)
- Performance: B (no major issues, room for optimization)
- Usability: B (functional but lacks documentation)
- Maintainability: B+ (clean code, but some duplication)

**Recommendation: Address Priority 1 security fixes before production use.**
