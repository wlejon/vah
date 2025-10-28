# Code Review: Core Lua Scripts (Framework & System)

**Review Date:** 2025-10-28
**Reviewer:** Code Review Agent
**Component:** Core Lua application scripts (startup, MCP, UI, HTTP)
**Total Lines Reviewed:** 2,162 lines

---

## Component Overview

The Core Lua Scripts comprise the application-level business logic of the Vah application. These scripts implement a threaded Lua architecture with Model Context Protocol (MCP) server capabilities, notification system, application launcher, menu system, and HTTP client/server functionality.

**Key Architectural Features:**
- Thread-based modular design (each script runs in its own Lua thread)
- MCP 2025-06-18 protocol implementation with JSON-RPC 2.0 over HTTP
- Event-driven communication (local and global event buses)
- Data binding for reactive UI updates
- Type registry system for extensible data source integration
- Template-based view rendering for MCP responses
- RmlUi integration for UI rendering

---

## Files Reviewed

| File | Lines | Purpose |
|------|-------|---------|
| `D:\projects\vah\scripts\main.lua` | 23 | Application entry point and core system orchestration |
| `D:\projects\vah\scripts\mcp_server.lua` | 645 | MCP protocol server implementation |
| `D:\projects\vah\scripts\mcp_client.lua` | 427 | MCP protocol client for testing/debugging |
| `D:\projects\vah\scripts\mcp_config.lua` | 44 | MCP server configuration |
| `D:\projects\vah\scripts\launcher.lua` | 177 | Application launcher and lifecycle management |
| `D:\projects\vah\scripts\menu.lua` | 141 | Global menu bar system |
| `D:\projects\vah\scripts\notifications.lua` | 520 | Notification system with SQLite persistence |
| `D:\projects\vah\scripts\http_server.lua` | 110 | HTTP/SSE server example |
| `D:\projects\vah\scripts\http_client.lua` | 75 | HTTP/SSE client example |
| **Supporting files:** | | |
| `D:\projects\vah\scripts\mcp_type_registry.lua` | 144 | Type system for MCP data sources |
| `D:\projects\vah\scripts\mcp_tools\navigation.lua` | 514 | Core MCP navigation tools |

**Total:** ~2,162 lines reviewed

---

## Architecture & Design

### Thread-Based Architecture

**Design Pattern:**
- Each major system runs in its own Lua thread (`LuaThread` class from C++)
- Threads communicate via event system (local events within thread, global events across threads)
- Main thread spawns: notifications, menu, MCP server, and launcher threads

**Thread Lifecycle:**
```lua
function startup()  -- Called when thread starts
function update(dt) -- Called at 30Hz
function shutdown() -- Called when thread stops
```

**Strengths:**
- Clear separation of concerns
- Independent lifecycle management
- Parallel execution of systems

**Concerns:**
- No explicit synchronization primitives visible (relies on C++ thread safety)
- No documented thread safety guarantees for shared resources

### MCP Protocol Implementation

**Architecture:**
- JSON-RPC 2.0 over HTTP (POST for requests, DELETE for session termination)
- Session-based state management with `Mcp-Session-Id` header
- Context-aware tool availability (tools change based on current navigation context)
- Type registry system for extensible data sources
- Template-based view rendering (Markdown templates with variable substitution)

**Key Design Decisions:**

1. **Contextual Tools** (`mcp_server.lua:112-138`):
   - Session tracks current context (type, view, id, params)
   - Available tools rebuild dynamically based on context
   - Core navigation tools always available
   - Type-specific tools added when context has active type

2. **Type Registry System** (`mcp_type_registry.lua`):
   - Pluggable data source architecture
   - Each type defines: name, plural, query functions, optional tools/templates
   - Required query functions: list, detail, summary, search, diff, status
   - Templates can be type-specific or use generic templates

3. **Navigation Tools** (`mcp_tools/navigation.lua`):
   - Six core tools: list, detail, summary, search, diff, status
   - All tools render via template system
   - Session context updated after successful navigation
   - Recent actions tracked for context

**MCP Protocol Compliance:**
- ✅ Protocol version negotiation (2025-06-18)
- ✅ Capabilities negotiation
- ✅ Session management
- ✅ JSON-RPC 2.0 error codes
- ✅ Tools list/call methods
- ⚠️ SSE streaming declared but not implemented (`mcp_server.lua:508-512`)
- ❌ Resources and prompts capabilities not implemented

### HTTP Server/Client

**HTTP Server Design:**
- Blocking server with streaming support (SSE)
- Route registration via closures
- Stream function for SSE events
- Server runs on Lua thread, blocks in `listen()`

**Issues:**
- Server blocks the Lua thread's update loop (`http_server.lua:83-84`)
- UI updates during streaming may be problematic
- No request queue or async handling visible

### UI System Integration

**Data Binding Pattern:**
```lua
data.bind("model_name", array_data)        -- For arrays
data.bind_object("model_name", object_data) -- For objects
```

**UI Event Pattern:**
```lua
event.register("event_name", handler)        -- Local thread events
event.register_global("event_name", handler) -- Cross-thread events
event.trigger_global("event_name", payload)  -- Send global event
```

**Strengths:**
- Reactive data binding
- Clear separation of local vs global events
- Document show/hide for view management

**Issues:**
- No validation that data models exist before UI loads
- Race conditions possible if UI loads before data binding

---

## Code Quality Assessment

### Strengths

1. **Well-Structured Modularity**
   - Clear separation of concerns (each script has single responsibility)
   - Consistent file organization
   - Clean module exports with API tables

2. **Good Error Handling Patterns**
   - `pcall()` used extensively for error catching
   - JSON-RPC error responses follow specification
   - Database errors checked and logged

3. **Comprehensive MCP Implementation**
   - Full JSON-RPC 2.0 compliance
   - Session management
   - Dynamic tool registration
   - Context-aware capabilities

4. **Documentation**
   - File headers explain purpose
   - Complex functions have comments
   - Protocol version clearly stated

5. **Type Registry Architecture**
   - Excellent extensibility design
   - Validation of type definitions
   - Graceful handling of missing types

6. **Event System Design**
   - Clear distinction between local and global events
   - Consistent naming conventions
   - Well-organized event handlers

### Issues & Concerns

#### Critical Issues

**C1. Missing Input Validation (MCP Server)**

File: `mcp_server.lua:254-289`

```lua
function handle_tools_call(message, session)
    local params = message.params or {}
    local tool_name = params.name
    local arguments = params.arguments or {}

    -- Missing validation:
    -- - arguments schema validation against tool.inputSchema
    -- - No sanitization of arguments before passing to handlers
    -- - Tool handlers receive raw user input
```

**Risk:** Tool handlers may crash or behave unexpectedly with malformed input. JSON Schema validation is defined but never enforced.

**Recommendation:** Add JSON Schema validation before tool execution:
```lua
-- Validate arguments against schema
if tool.inputSchema then
    local valid, errors = validate_json_schema(arguments, tool.inputSchema)
    if not valid then
        return json_rpc_error(message.id, -32602, "Invalid parameters", errors)
    end
end
```

---

**C2. Session Management Security Issues**

File: `mcp_server.lua:68-73, 345-346`

```lua
function generate_session_id()
    local id = "session-" .. next_session_id
    next_session_id = next_session_id + 1
    return id
end

-- Later:
local session_id = headers["mcp-session-id"] or headers["Mcp-Session-Id"]
```

**Issues:**
- Predictable session IDs (sequential numbers)
- No session expiration
- No maximum session limit
- Session ID transmitted in headers without additional security
- Case-insensitive header lookup may cause issues

**Risk:** Session hijacking, resource exhaustion, memory leaks.

**Recommendation:**
- Use cryptographically random session IDs
- Implement session timeout (e.g., 1 hour inactivity)
- Add maximum session limit (e.g., 100 concurrent sessions)
- Add session cleanup in update loop

---

**C3. Unimplemented HTTP DELETE**

File: `mcp_client.lua:209-216`

```lua
function disconnect_from_server()
    print("Disconnecting from MCP server...")

    if session_id then
        -- Send DELETE request to terminate session
        local headers = {
            ["Mcp-Session-Id"] = session_id
        }

        -- Note: http.delete is not implemented, so we'll just clear local state
        -- In a full implementation, we'd send a DELETE request here
    end
```

**Issue:** Comment admits `http.delete` doesn't exist. Sessions accumulate on server without proper cleanup.

**Impact:** Memory leak on MCP server if clients don't properly disconnect.

**Recommendation:** Implement `http.delete` in C++ bindings or use `http.request` with custom method.

---

**C4. Race Condition in Data Binding**

File: `notifications.lua:453-460`

```lua
-- Load notifications and bind data BEFORE loading UI
load_notifications()

-- Load both UI documents
-- Badge is shown by default, panel is hidden
-- Data models are prioritized in command queue, so they'll be processed first
ui.load_document("ui/internal/notifications_badge.rml", true, BADGE_DOC_ID)
ui.load_document("ui/internal/notifications_panel.rml", false, PANEL_DOC_ID)
```

**Issue:** Comment acknowledges race condition concern. Command queue ordering is not guaranteed by API contract.

Files affected: `notifications.lua:453-460`, `mcp_client.lua:396-412`, `menu.lua:118-127`

**Risk:** UI may render before data model exists, causing RmlUi errors or blank displays.

**Recommendation:**
- Make data binding synchronous before UI load
- Or add explicit callback when data binding completes
- Or document guarantee in C++ API

---

#### Major Issues

**M1. No JSON Schema Validation**

The MCP server defines inputSchema for all tools but never validates arguments against schemas. This is a protocol violation and security risk.

Files: `mcp_server.lua` (all tool definitions), `mcp_tools/navigation.lua:375-508`

**Recommendation:** Implement JSON Schema validation or use a Lua library.

---

**M2. Incomplete Error Context**

File: `mcp_server.lua:288`

```lua
if not success then
    return json_rpc_error(message.id, -32603, "Tool execution error: " .. tostring(result))
end
```

**Issue:** Stack traces and detailed error information are lost. Only string representation returned.

**Impact:** Difficult to debug tool failures.

**Recommendation:** Include error details in JSON-RPC error `data` field:
```lua
return json_rpc_error(message.id, -32603, "Tool execution error", {
    message = tostring(result),
    tool = tool_name,
    arguments = arguments
})
```

---

**M3. Missing Request ID Validation**

File: `mcp_server.lua:301-312`

```lua
function handle_request(message, session)
    local method = message.method
    -- No validation that message.id exists or is valid type
```

**Issue:** JSON-RPC requires request ID to be string, number, or null. No type checking.

**Risk:** Invalid responses if client sends wrong ID type.

**Recommendation:** Validate request ID before processing.

---

**M4. HTTP Server Blocks Update Loop**

File: `http_server.lua:83-84`

```lua
-- Start server (this blocks until server is stopped)
print("Calling server:listen() - this will block...")
local success, err = server:listen("127.0.0.1", 8080)
```

**Issue:** The update(dt) function never runs while server is listening.

**Impact:**
- UI updates don't occur (line 65: `update_model()` during streaming)
- Thread appears hung
- Data binding updates delayed until request completes

**Recommendation:**
- Run HTTP server on separate OS thread (C++ level)
- Or make listen() non-blocking with poll mechanism
- Or document that HTTP server threads shouldn't use update loop

---

**M5. Notification System Race Conditions**

File: `notifications.lua:466-472`

```lua
function update(dt)
    -- Refresh notifications every 0.5 seconds to remove expired ones
    time_since_refresh = time_since_refresh + dt
    if time_since_refresh >= 0.5 then
        load_notifications()
        time_since_refresh = 0.0
    end
end
```

**Issue:** Database queries every 0.5 seconds from update loop while other threads may be adding notifications via global events.

**Risks:**
- SQLite concurrent access issues (depends on C++ db.open flags)
- Performance impact if query is slow
- UI flicker from constant rebinding

**Recommendation:**
- Document SQLite thread-safety mode
- Only reload on add/dismiss events instead of polling
- Use event-driven updates

---

**M6. Missing Thread Lifecycle Management**

File: `launcher.lua:120-124`

```lua
-- Stop the app's thread if it exists
if active_app.thread_id then
    print("Stopping thread: " .. active_app.thread_id)
    command.stop_thread(active_app.thread_id)
end
```

**Issue:** No confirmation that thread stopped. No timeout. No handling if stop fails.

**Risk:** Zombie threads, resource leaks.

**Recommendation:** Add thread stop confirmation or timeout.

---

**M7. Hardcoded Server Configuration**

File: `mcp_client.lua:5`, `http_client.lua:32`

```lua
local SERVER_URL = "http://127.0.0.1:8765/mcp"
-- ...
http.get("http://127.0.0.1:8080/events", {
```

**Issue:** URLs hardcoded in multiple files. Server configuration in `mcp_config.lua` not used by client.

**Impact:** Difficult to change server address, port conflicts.

**Recommendation:** Client should read from config or discover server via menu.

---

#### Minor Issues

**m1. Inconsistent Error Handling**

Mixed patterns for error handling:
- Some functions return `(result, error_string)` (e.g., `db.open`)
- Some functions use pcall with success boolean
- Some functions throw errors

**Recommendation:** Document and standardize error handling patterns.

---

**m2. Magic Numbers**

Files throughout:
- `notifications.lua:468`: 0.5 seconds (refresh interval)
- `notifications.lua:152`: 10 actions (history limit)
- `mcp_tools/navigation.lua:50`: 10 items (default page limit)
- `mcp_client.lua:85`: 30 seconds (HTTP timeout)

**Recommendation:** Move to configuration constants at file top.

---

**m3. Inconsistent Code Style**

- Mixed use of `and`/`or` vs `if` statements for defaults
- Inconsistent string concatenation (.. vs string.format)
- Mixed quote styles (' vs ")

**Example:**
```lua
local title = notif.title or "Notification"  -- Using 'or'
if not notif_type then notif_type = "info" end  -- Using 'if'
```

**Recommendation:** Establish Lua style guide (e.g., Lua Style Guide or LuaRocks conventions).

---

**m4. Commented Out Code**

File: `mcp_server.lua:615-616`

```lua
-- Register built-in test tools (temporary, for backward compatibility)
register_builtin_tools()
```

Comment says "temporary" but tools are still registered. `echo` and `get_time` tools should either be removed or properly documented.

**Recommendation:** Remove test tools or move to separate testing module.

---

**m5. Missing Type Annotations**

Lua is dynamically typed but would benefit from LuaLS/EmmyLua annotations for IDE support.

**Example:**
```lua
---@param message table JSON-RPC message
---@param session table Session state
---@return table JSON-RPC response
function handle_tools_call(message, session)
```

**Recommendation:** Add type annotations for major functions.

---

**m6. Potential Memory Leak in Session History**

File: `mcp_server.lua:140-155`

```lua
function add_recent_action(session, action_text)
    if not session.recent_actions then
        session.recent_actions = {}
    end

    table.insert(session.recent_actions, {
        action = action_text,
        timestamp = os.time()
    })

    -- Keep only last 10 actions
    if #session.recent_actions > 10 then
        table.remove(session.recent_actions, 1)
    end
end
```

**Issue:** Recent actions added but never called. Sessions never expire. Memory grows unbounded.

**Impact:** Memory leak if server runs long-term with many sessions.

**Recommendation:**
- Implement session expiration
- Or call add_recent_action in navigation tools
- Or remove if unused

---

**m7. Incomplete Notification Features**

File: `notifications.lua:258-260`

```lua
-- TODO: Dispatch the action event globally
-- For now, just print it
print("Would dispatch event: " .. action_event)
```

Notification actions don't work. UI shows action buttons but clicking does nothing.

**Recommendation:** Complete implementation or remove action button UI.

---

**m8. Missing HTTP Client Features**

Client-side HTTP issues:
- No request cancellation API
- No progress callbacks for long requests
- No retry logic
- No connection pooling
- Timeout only option

**Recommendation:** Add to C++ HTTP client bindings.

---

### MCP Protocol Implementation Analysis

#### Protocol Adherence

**Implemented Correctly:**
- ✅ Initialize/initialized handshake
- ✅ Protocol version negotiation
- ✅ Capabilities reporting
- ✅ Session management via headers
- ✅ Tools list/call methods
- ✅ JSON-RPC 2.0 error codes
- ✅ Request/notification distinction

**Issues:**

1. **SSE Streaming Not Implemented** (`mcp_server.lua:502-512`)
   - GET /mcp with session returns 501 Not Implemented
   - Protocol requires SSE for server-initiated messages
   - Server can't send progress updates or notifications to client

2. **Resources Not Implemented**
   - MCP protocol supports resources (files, URIs)
   - Server declares no resources capability
   - Could expose file system, databases as MCP resources

3. **Prompts Not Implemented**
   - MCP protocol supports prompt templates
   - Could provide query templates for LLM clients

4. **Sampling Not Implemented**
   - MCP protocol supports LLM sampling requests
   - Not applicable for this use case (server, not client)

#### Context-Aware Tool Design

**Excellent Design Decision:** The session context system (`mcp_server.lua:112-138`) is clever:

```lua
function update_session_context(session, type_name, view, id, params)
    session.current_context = {
        type = type_name,
        view = view,
        id = id,
        params = params or {}
    }

    -- Rebuild available tools list
    session.available_tools = {}

    -- Add core navigation tools
    for _, tool_name in ipairs(config.core_tools) do
        table.insert(session.available_tools, tool_name)
    end

    -- Add type-specific tools if we have a type
    if type_name and type_registry then
        local type_def = type_registry.get(type_name)
        if type_def and type_def.tools then
            for _, tool in ipairs(type_def.tools) do
                table.insert(session.available_tools, tool.name)
            end
        end
    end
end
```

This allows:
- AI agents to see only relevant tools for current context
- Type-specific actions (e.g., SQL query tools only when viewing database)
- Reduced token usage (fewer tools to describe)
- Natural conversation flow (tools match current focus)

**Potential Issue:** If LLM client caches tools list, context changes may confuse it. MCP spec says `listChanged` capability notifies client to refetch tools, but server doesn't send notifications yet (no SSE).

---

### Error Handling Patterns

**Positive Patterns:**

1. **Database Error Handling** (`notifications.lua:18-30`):
```lua
local db_handle, error = db.open("data/notifications.db")
if error ~= "" then
    print("Error opening notifications database: " .. error)
    return false
end
```
Clear, explicit error checking.

2. **JSON Parsing** (`mcp_server.lua:329-342`):
```lua
local message
local parse_success, parse_error = pcall(function()
    message = json.decode(body)
end)

if not parse_success or not message then
    local err_response = json_rpc_error(nil, -32700, "Parse error")
    return {
        status = 400,
        content_type = "application/json",
        body = json.encode(err_response),
        session_id = nil
    }
end
```
Proper JSON-RPC error code for parse errors.

3. **Tool Execution** (`mcp_server.lua:285-289`):
```lua
local success, result = pcall(tool.handler, arguments, session)

if not success then
    return json_rpc_error(message.id, -32603, "Tool execution error: " .. tostring(result))
end
```
Protected calls prevent crashes.

**Issues:**

1. **Lost Error Context**: `tostring(result)` loses stack traces
2. **No Error Logging**: Errors printed but not logged to file
3. **No Error Metrics**: Can't track error rates or patterns
4. **Silent Failures**: Some functions return false with no error message

---

### Security Considerations

#### Authentication & Authorization

**Current State:** None implemented.

**Risks:**
- MCP server listens on localhost (127.0.0.1) only - mitigates remote attacks
- No authentication required - any local process can connect
- No authorization - all clients have same permissions
- Session IDs predictable - session hijacking possible (though localhost only)

**Recommendations:**
1. **Short Term:** Add API key authentication via header
2. **Medium Term:** Implement OAuth2 or JWT tokens
3. **Long Term:** Per-session permissions/capabilities

#### Input Validation

**Issues Identified:**

1. **No JSON Schema Validation** (Critical)
   - Tool arguments not validated
   - Could cause crashes or unexpected behavior

2. **SQL Injection Risk** (`notifications.lua:68-75`):
```lua
local sql = [[
    SELECT * FROM notifications
    WHERE dismissed = 0
      AND (ttl = 0 OR (timestamp + ttl) > ?)
    ORDER BY timestamp DESC
]]

local results, error = database:query(sql, current_time)
```

**Status:** Uses parameterized queries (?) - SAFE. However, other queries should be audited.

3. **Path Traversal Risk** (`mcp_type_registry.lua:132-141`):
```lua
function M.get_template_path(type_name, view_name)
    local type_def = types[type_name]

    if type_def and type_def.templates and type_def.templates[view_name] then
        return type_def.templates[view_name]  -- User-controlled path
    end

    return config.templates_directory .. "/" .. view_name .. ".md"
end
```

**Risk:** If type_def.templates comes from external config, could contain "../../../etc/passwd"

**Recommendation:** Validate paths before file access.

4. **Command Injection Risk**:
   - No shell commands visible in reviewed code
   - HTTP URLs hardcoded, not user-controlled
   - Low risk

#### Data Sanitization

**Issues:**

1. **RmlUi Injection** (`mcp_client.lua:298`):
```lua
ui.set_texteditor_content("result_editor", text_content)
```

If `text_content` contains RmlUi markup, could break UI or inject content.

**Risk Level:** Low (depends on RmlUi escaping)

2. **Notification Message Injection** (`notifications.lua:306-339`):
```lua
add_notification({
    type = "info",
    title = "System Started",
    message = "Vah notification system is now running",
```

Notification title/message not sanitized before DB storage or UI display.

**Risk Level:** Low (internal use only, but should sanitize)

---

### Performance Considerations

#### Database Performance

**Issue 1: Polling Query** (`notifications.lua:466-472`)

```lua
function update(dt)
    -- Refresh notifications every 0.5 seconds to remove expired ones
    time_since_refresh = time_since_refresh + dt
    if time_since_refresh >= 0.5 then
        load_notifications()  -- Full table scan
        time_since_refresh = 0.0
    end
end
```

**Impact:** 2 queries/second * 3600 seconds = 7200 queries/hour even with no activity.

**Recommendation:** Event-driven updates only.

---

**Issue 2: Missing Indexes** (`notifications.lua:29-49`)

```sql
CREATE TABLE IF NOT EXISTS notifications (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp INTEGER NOT NULL,
    type TEXT NOT NULL,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    dismissed INTEGER DEFAULT 0,
    -- ... more fields
)
```

**Missing Indexes:**
- `(dismissed, ttl, timestamp)` for load query (line 68-75)
- `(timestamp)` for cleanup query (line 483-487)

**Impact:** Full table scans as notification count grows.

**Recommendation:** Add indexes for common queries.

---

#### Memory Usage

**Issue 1: Session Accumulation**

Sessions stored in memory, never expire. With 100 sessions * 1KB each = 100KB (acceptable), but grows unbounded.

**Recommendation:** Implement session expiration.

---

**Issue 2: Tools List Rebuilding** (`mcp_server.lua:122-138`)

Every context change rebuilds entire tools list. With 50 types * 10 tools/type = 500 tools, this is O(n) on every navigation.

**Optimization:** Cache type tools, only rebuild if type changes.

---

**Issue 3: Template Loading** (`mcp_tools/navigation.lua:16-32`)

```lua
local function render_view(template_path, data)
    -- Load template
    local template_content, err = fs.read_file(template_path)
```

Template loaded from disk on every request. No caching.

**Impact:** Disk I/O on every tool call.

**Recommendation:** Cache compiled templates in memory.

---

#### Network Performance

**Issue 1: Synchronous HTTP** (`mcp_client.lua:82-86`)

```lua
local response, err = http.post(SERVER_URL, {
    headers = headers,
    body = body,
    timeout = 30
})
```

Blocking HTTP calls. UI freezes during request.

**Recommendation:** Async HTTP with callbacks (may require C++ changes).

---

**Issue 2: No HTTP Compression**

HTTP responses not compressed. MCP tool responses can be large (multi-KB markdown).

**Recommendation:** Enable gzip compression in HTTP server.

---

---

## Recommendations

### Priority 1 (Critical - Security & Stability)

1. **Implement JSON Schema Validation** (`mcp_server.lua`)
   - Validate tool arguments against inputSchema
   - Prevent crashes from malformed input
   - Estimated effort: 50 lines

2. **Fix Session ID Generation** (`mcp_server.lua:68-73`)
   - Use crypto-random IDs (e.g., UUID)
   - Implement session expiration (1 hour timeout)
   - Add session cleanup in update loop
   - Estimated effort: 100 lines

3. **Implement HTTP DELETE** (`mcp_client.lua:209-216`)
   - Complete session termination protocol
   - Prevent server-side memory leaks
   - Estimated effort: C++ binding + 20 lines Lua

4. **Fix Data Binding Race Conditions** (multiple files)
   - Make data binding synchronous or add callback
   - Document ordering guarantees
   - Estimated effort: C++ changes or 50 lines Lua

### Priority 2 (Major - Functionality & Performance)

5. **Add Error Context to Tool Failures** (`mcp_server.lua:288`)
   - Include stack traces in error data
   - Add error logging to file
   - Estimated effort: 50 lines

6. **Fix HTTP Server Blocking** (`http_server.lua:83-84`)
   - Move HTTP server to OS thread or make non-blocking
   - Enable UI updates during requests
   - Estimated effort: C++ changes

7. **Event-Driven Notification Updates** (`notifications.lua:466-472`)
   - Remove polling, use events only
   - Add database indexes
   - Estimated effort: 100 lines

8. **Complete Notification Actions** (`notifications.lua:258-260`)
   - Dispatch action events globally
   - Connect to action handlers
   - Estimated effort: 50 lines

9. **Implement SSE Streaming** (`mcp_server.lua:502-512`)
   - Complete GET /mcp with session support
   - Enable server-initiated messages
   - Support tools/list changes notification
   - Estimated effort: 200 lines

### Priority 3 (Minor - Code Quality)

10. **Standardize Error Handling**
    - Document error return patterns
    - Consistent error types
    - Estimated effort: documentation + 100 lines refactor

11. **Add Configuration Constants**
    - Remove magic numbers
    - Centralize timeouts, limits
    - Estimated effort: 50 lines

12. **Code Style Consistency**
    - Establish Lua style guide
    - Run formatter
    - Estimated effort: documentation

13. **Add Type Annotations**
    - LuaLS/EmmyLua comments
    - IDE autocomplete support
    - Estimated effort: 200 lines comments

14. **Remove Test Tools**
    - Remove or document echo/get_time tools
    - Move to separate test module
    - Estimated effort: 50 lines

### Priority 4 (Enhancement)

15. **Template Caching** (`mcp_tools/navigation.lua`)
    - Cache compiled templates
    - Reduce disk I/O
    - Estimated effort: 100 lines

16. **Async HTTP** (`mcp_client.lua`)
    - Non-blocking requests with callbacks
    - Prevent UI freezing
    - Estimated effort: C++ changes + 150 lines

17. **HTTP Compression**
    - Enable gzip for large responses
    - Reduce bandwidth
    - Estimated effort: C++ changes

18. **Advanced MCP Features**
    - Implement resources capability
    - Implement prompts capability
    - Estimated effort: 500 lines

---

## Dependencies & Integration

### C++ Bindings Required

The Lua scripts depend on these C++ bindings (assumed from usage):

**Core:**
- `thread_id` (global) - Current thread ID
- `print()` - Console logging
- `sleep(seconds)` - Thread sleep

**Command System:**
- `command.spawn_thread(script_path)`
- `command.stop_thread(thread_id)`
- `command.close_application()`
- `command.http_response(request_id, status, content_type, body, headers)`

**Event System:**
- `event.register(name, handler)`
- `event.register_global(name, handler)`
- `event.trigger_global(name, payload)`

**UI System:**
- `ui.load_document(path, visible, id)`
- `ui.show_document(id)`
- `ui.hide_document(id)`
- `ui.set_texteditor_content(id, text)`
- `ui.set_texteditor_editable(id, bool)`

**Data Binding:**
- `data.bind(name, array_table)`
- `data.bind_object(name, object_table)`

**HTTP:**
- `http.post(url, options)` - Returns `{body, headers}` or `(nil, error)`
- `http.get(url, options)` - SSE support with `on_event` callback
- `HttpServer.new()` - Returns server object
- `server:route(method, path, handler)`
- `server:listen(host, port)` - Blocking
- `server:stop()`

**Database:**
- `db.open(path)` - Returns `(handle, error_string)`
- `handle:execute(sql, ...params)` - Returns `(success, error_string)`
- `handle:query(sql, ...params)` - Returns `(results_array, error_string)`
- `handle:close()`

**Filesystem:**
- `fs.read_file(path)` - Returns `(content, error_string)`
- `fs.list_dir(path)` - Returns `(entries_array, error_string)` where entry = `{name, is_dir}`

**JSON:**
- `json.encode(table)` - Returns JSON string
- `json.decode(string)` - Returns table (throws on error)

**OS:**
- `os.time()` - Unix timestamp
- `os.date(format)` - Formatted date string

### RmlUi Integration

- UI documents loaded from `ui/*.rml` files
- Data binding connects Lua tables to RmlUi data models
- Events from RmlUi (onclick, etc.) trigger Lua event handlers
- Multiple documents can be loaded, show/hide for view switching

### Missing Integrations

1. **Template Renderer** (`require("template_renderer")`)
   - Used by navigation tools
   - Assumed to exist in `scripts/template_renderer.lua`
   - Not reviewed in this document

2. **Type Definitions** (`mcp_views/types/*.lua`)
   - Data source implementations
   - Loaded dynamically by type registry
   - Not reviewed in this document

3. **MCP Client Tools** (External)
   - LLM clients (Claude, GPT, etc.)
   - MCP protocol clients
   - Testing tools

---

## Summary

### Overall Assessment

**Grade: B+ (Good, with room for improvement)**

The Core Lua Scripts demonstrate a well-architected, modular system with strong separation of concerns and thoughtful design patterns. The MCP protocol implementation is comprehensive and the type registry system shows excellent extensibility design.

**Key Strengths:**
- Clean modular architecture
- Comprehensive MCP protocol implementation
- Excellent type registry design
- Good error handling patterns
- Clear code organization

**Key Weaknesses:**
- Security vulnerabilities (session management, input validation)
- Missing JSON Schema validation (protocol violation)
- Race conditions in data binding
- Performance issues (polling, lack of caching)
- Incomplete features (SSE, notification actions, HTTP DELETE)

### Recommendations Summary

**Must Fix (Before Production):**
1. JSON Schema validation
2. Secure session ID generation
3. Session expiration
4. Data binding race conditions
5. HTTP DELETE implementation

**Should Fix (For Stability):**
6. Error context preservation
7. HTTP server threading
8. Event-driven notifications
9. SSE streaming
10. Complete notification actions

**Nice to Have (Code Quality):**
11. Standardized error handling
12. Configuration constants
13. Code style guide
14. Type annotations
15. Template caching

### Test Coverage Recommendations

No unit tests found in reviewed code. Recommend adding:

1. **MCP Protocol Tests:**
   - Initialize/initialized handshake
   - Session management (create, use, expire, terminate)
   - Tools list/call methods
   - JSON-RPC error cases
   - Malformed requests

2. **Integration Tests:**
   - Full tool execution flow
   - Type registry loading
   - Template rendering
   - Navigation context changes

3. **Performance Tests:**
   - Session scaling (100+ concurrent sessions)
   - Notification system load (1000+ notifications)
   - Template rendering performance
   - HTTP server throughput

4. **Security Tests:**
   - Session hijacking attempts
   - Path traversal attacks
   - SQL injection tests
   - Input fuzzing

---

**End of Code Review**
