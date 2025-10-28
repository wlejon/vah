# Code Review: Tools, Adapters & UI Workflows (Lua)

## Component Overview

This component encompasses external tool integration, data transformation adapters, and complex interactive UI workflows. It includes the Manufold agent system for data ingestion and transformation, an LLM client with model adapters, and sophisticated canvas-based UIs including a visual node workflow editor and a Tetris game implementation.

**Review Date:** 2025-10-28
**Reviewer:** Claude Code (Automated Review)
**Total Lines Reviewed:** 5,012 lines

## Files Reviewed

### Tool Integration & Adapters (3,197 lines)
- `D:\projects\vah\scripts\manufold_tools.lua` (425 lines) - Tool definitions for Manufold agent
- `D:\projects\vah\scripts\manufold_agent.lua` (711 lines) - Main agent workflow orchestration
- `D:\projects\vah\scripts\harmony_adapter.lua` (701 lines) - Harmony format model adapter
- `D:\projects\vah\scripts\model_adapter.lua` (48 lines) - Base adapter interface
- `D:\projects\vah\scripts\lm_studio_client.lua` (301 lines) - HTTP client for LM Studio
- `D:\projects\vah\scripts\parser_executor.lua` (546 lines) - Sandboxed parser execution
- `D:\projects\vah\scripts\file_inspector.lua` (465 lines) - Intelligent file analysis

### Workflow Editor UI (1,207 lines)
- `D:\projects\vah\ui\workflow_editor\init.lua` (216 lines) - Main initialization and coordination
- `D:\projects\vah\ui\workflow_editor\input.lua` (327 lines) - Mouse and keyboard input handling
- `D:\projects\vah\ui\workflow_editor\render.lua` (358 lines) - NanoVG rendering functions
- `D:\projects\vah\ui\workflow_editor\node.lua` (167 lines) - Node operations and utilities
- `D:\projects\vah\ui\workflow_editor\state.lua` (57 lines) - Editor state management
- `D:\projects\vah\ui\workflow_editor\connection.lua` (35 lines) - Connection management
- `D:\projects\vah\ui\workflow_editor\transform.lua` (20 lines) - Coordinate transformations
- `D:\projects\vah\ui\workflow_editor\colors.lua` (27 lines) - Color scheme definitions

### Interactive Game (608 lines)
- `D:\projects\vah\ui\tetris.lua` (608 lines) - Complete Tetris implementation

## Architecture & Design

### Tool Integration Architecture

**Manufold Agent System:**
The Manufold system implements an agent-assisted workflow for transforming unstructured data into structured knowledge environments. The architecture follows a view-oriented design where tools return rich, structured information rather than simple success/error responses.

**Key Components:**
1. **Tool Definitions** (`manufold_tools.lua`): 12 tool definitions covering file system exploration, database operations, data transformation, and view generation
2. **Agent Orchestrator** (`manufold_agent.lua`): State machine managing workflow from ingestion through view generation
3. **Tool Executor**: Dispatches tool calls to appropriate handlers with comprehensive error handling

**Workflow States:**
```
WELCOME → INGESTION → EXPLORATION → VALIDATION →
MODEL_DESIGN → TRANSFORMATION → VIEW_GENERATION → COMPLETE
```

### Model Adapter Pattern

**Design:** Abstract adapter interface with concrete implementations for different LLM formats

**Components:**
1. **Base Interface** (`model_adapter.lua`): 48-line contract defining required methods
2. **Harmony Adapter** (`harmony_adapter.lua`): 701-line implementation with custom tokenizer and parser

**Adapter Responsibilities:**
- System prompt generation from tool definitions
- Response tokenization (character-level lexer with 15+ token types)
- Tool call parsing from token stream
- Tool result formatting for model consumption

**Tokenization Strategy:** The Harmony adapter implements a complete character-level lexer supporting:
- Harmony control tokens (`<|channel|>`, `<|message|>`)
- JSON structural tokens (braces, brackets, colons, commas)
- JSON value tokens (strings, numbers, booleans, null)
- Escape sequence handling in strings
- Number parsing (integers, decimals, exponents)

### LM Studio HTTP Client

**Architecture:** Comprehensive OpenAI-compatible API client with both streaming and non-streaming support

**Features:**
- Chat completions with full parameter support (temperature, max_tokens, top_p, penalties)
- Streaming chat with Server-Sent Events (SSE) handling
- Model listing and introspection
- Health check utilities
- Configurable timeouts (default 5 minutes for long responses)

**Error Handling:** Returns tuple of (response, error) with nil on failure

### Data Transformation Pipeline

**Parser Executor** (`parser_executor.lua`):
- Sandboxed Lua environment for safe parser script execution
- Registry of generated parsers by ID
- Batch file processing with per-file result tracking
- Transaction-based database insertion
- Comprehensive validation and data quality metrics

**File Inspector** (`file_inspector.lua`):
- Intelligent file type detection (JSON, CSV, XML, plain text, binary)
- Automatic sampling for large files
- Header detection for CSV files
- Structure hints and parsing suggestions
- Collection-level relationship analysis

**Sandboxing Strategy:**
- Whitelist of safe Lua functions and libraries
- Read-only filesystem access
- Database access limited to insertion
- Results accumulator for metrics tracking
- Error and warning reporting hooks

### Workflow Editor Architecture

**Design Philosophy:** Canvas-based node editor with infinite pan/zoom, real-time interaction, and server-synchronized state

**Module Organization:**
1. **init.lua**: Main coordination, server sync, event registration
2. **state.lua**: Pure data structure (no logic)
3. **render.lua**: All NanoVG drawing operations
4. **input.lua**: Mouse and keyboard event handlers
5. **node.lua**: Node creation and manipulation utilities
6. **connection.lua**: Connection management
7. **transform.lua**: Coordinate space conversions
8. **colors.lua**: Centralized color definitions

**Coordinate System:**
- **Screen Space**: Canvas-relative pixel coordinates
- **World Space**: Zoom/pan-independent logical coordinates
- Transformation: `world = (screen - pan) / zoom`

**Rendering Pipeline:**
1. Draw background and grid in canvas space
2. Apply transform (translate + scale)
3. Draw connections and nodes in world space
4. Restore transform
5. Draw UI overlays in screen space

**State Synchronization:**
- Server is source of truth (data.get/data.bind)
- Client reads server state periodically
- Local drag state prevents sync during interaction
- Events trigger server updates on completion

**Event Model:**
- `workflow_node_created`: Emitted on node spawn
- `workflow_node_moved`: Emitted on drag completion
- `workflow_node_deleted`: Emitted on node deletion
- `workflow_connection_added`: Emitted on connection completion

### Tetris Implementation

**Design:** Complete Tetris game using NanoVG for rendering on ElementCanvas

**Features:**
- Standard 10x20 board with 7 tetromino types
- Rotation, hard drop, ghost piece preview
- Score, lines, level progression
- Collision detection and line clearing
- Pause and restart functionality

**Rendering Approach:**
- Block-based drawing with depth effects (outlines, highlights)
- Grid lines for visual clarity
- Ghost piece showing drop location
- Next piece preview
- Game over and pause overlays

## Code Quality Assessment

### Strengths

#### 1. Excellent Architectural Separation
- Clear separation between data (state.lua), logic (node.lua, connection.lua), rendering (render.lua), and input (input.lua)
- Modular design allows independent testing and modification
- Single Responsibility Principle consistently applied

#### 2. Comprehensive Tool System
- Rich, view-oriented tool responses provide structured data for agent consumption
- Tool definitions include clear parameter specifications and return value documentation
- Execution results include sample data, statistics, validation info, and recommendations

#### 3. Robust Error Handling
- Parser executor uses pcall for safe script execution
- Comprehensive error context in Harmony adapter (shows surrounding tokens)
- File inspector gracefully handles binary files and read errors
- HTTP client returns error tuples consistently

#### 4. Professional Documentation
```lua
-- Tool definitions include detailed parameter documentation:
{
    name = "inspect_file",
    parameters = {
        {name = "path", type = "string", required = true, description = "Full path..."},
        {name = "max_bytes", type = "number", required = false, description = "Maximum..."}
    },
    returns = [[VIEW: {...}]]  -- Structured documentation
}
```

#### 5. Smart Default Behaviors
- File inspector automatically adjusts sampling based on file type (32KB for text, 1KB for binary)
- Parser executor handles transaction management automatically
- Workflow editor prevents sync during drag operations
- Zoom constraints prevent unusable zoom levels (0.3x to 3.0x)

#### 6. Excellent Coordinate Transformation Design
- Clean separation of screen and world coordinates
- Transform module provides clear, testable conversion functions
- Consistent application across input and rendering

#### 7. Rich Metadata and Analytics
- File inspector provides extensive statistics (extension counts, size stats, naming patterns)
- Parser executor returns per-file results with error details
- Workflow state includes comprehensive UI constants

### Issues & Concerns

#### Critical Issues

**C1: Missing Error Recovery in Tool Execution** (manufold_agent.lua:330-440)
```lua
if #tool_calls > 0 then
    for _, call in ipairs(tool_calls) do
        local result = execute_tool(call.name, call.arguments)
        -- If one tool fails, all subsequent tools still execute
        -- No short-circuit on critical failures
    end
end
```
**Impact:** A critical tool failure (e.g., database connection loss) doesn't stop subsequent tools, potentially causing cascading failures or inconsistent state.

**C2: SQL Injection Vulnerability** (parser_executor.lua:256-272)
```lua
if type(val) == "string" then
    table.insert(values_str, "'" .. val:gsub("'", "''") .. "'")
```
**Impact:** Manual SQL escaping is error-prone. While single quotes are escaped, complex inputs or encoding issues could bypass this. Should use prepared statements.

**C3: Unrestricted Parser Script Execution** (parser_executor.lua:76-141)
```lua
local sandbox = {
    -- Provides string, table, math libraries
    string = string,
    table = table,
    math = math,
}
```
**Impact:** Even in sandbox, malicious scripts could exploit string/table functions for denial of service (infinite loops, memory exhaustion). No CPU time limits or memory constraints.

**C4: Race Condition in Workflow Sync** (workflow_editor/init.lua:24-33)
```lua
if editor.dragging_node then
    return  -- Don't refresh during drag
end
-- But multiple events could fire between checks
```
**Impact:** If user drags rapidly while server updates arrive, could result in position jumps or lost updates.

#### Major Issues

**M1: Hardcoded Database Paths** (manufold_agent.lua:596)
```lua
agent_state.db_path = "data/" .. agent_state.session_id .. ".db"
```
**Impact:** No configuration for database location. Path may not exist, causing failures. No path validation.

**M2: Missing Connection Validation** (workflow_editor/connection.lua:7-23)
```lua
function M.add(editor, from_node_id, from_port, to_node_id, to_port)
    -- Only checks for duplicate connections
    -- Doesn't validate:
    -- - Nodes exist
    -- - Ports are in range
    -- - Type compatibility
end
```
**Impact:** Invalid connections can be created, causing rendering errors or crashes when dereferencing nil nodes.

**M3: Unbounded Memory Growth** (manufold_agent.lua:44)
```lua
conversation_history = {},  -- {role, content}
-- Never cleared or truncated
```
**Impact:** Long agent sessions will accumulate unbounded conversation history, potentially causing memory issues or hitting LLM context limits.

**M4: No Timeout for Parser Execution** (parser_executor.lua:187-202)
```lua
local parser_func, compile_err = load(parser.script_content, ...)
local success, result = pcall(parser_func)
-- No timeout - could hang indefinitely
```
**Impact:** Malicious or buggy parser scripts could hang the application. No way to detect or kill runaway parsers.

**M5: Missing File Extension Normalization** (file_inspector.lua:7-34)
```lua
if extension == ".json" then
    -- Case sensitive comparison
```
**Impact:** `.JSON`, `.Json` won't be recognized. Should normalize to lowercase.

**M6: Inefficient Grid Rendering** (workflow_editor/render.lua:31-77)
```lua
while gx <= world_x2 do
    -- Draws grid lines even when zoomed way out
    -- Could draw thousands of lines per frame
end
```
**Impact:** At low zoom levels, grid rendering becomes expensive. Should skip grid or increase spacing based on zoom level.

**M7: Node Menu Position Not Constrained** (workflow_editor/render.lua:277-356)
```lua
local menu_x = editor.canvas_x + editor.node_menu_x
local menu_y = editor.canvas_y + editor.node_menu_y
-- No check if menu extends beyond canvas bounds
```
**Impact:** Right-clicking near canvas edge shows partially off-screen menu, making items unclickable.

**M8: Missing Drag Threshold** (workflow_editor/input.lua:74-83)
```lua
if node_module.is_point_inside(editor, node, world_x, world_y) then
    editor.dragging_node = node
    -- Drag starts immediately on mouse down
end
```
**Impact:** Accidental tiny mouse movements during click cause unwanted node repositioning. Should require minimum movement before starting drag.

#### Minor Issues

**m1: Inconsistent Error Return Format** (parser_executor.lua:150-156)
```lua
return {
    execution_summary = {
        status = "failed",
        error = "Parser not found: " .. parser_id
    }
}
-- vs file_inspector.lua:116-118:
return {
    error = "File not found: " .. path
}
```
**Impact:** Callers must check multiple locations for errors. Should standardize on one format.

**m2: Magic Numbers in Rendering** (workflow_editor/render.lua)
```lua
nvg.strokeWidth(nvg_ctx, 1.5 / editor.zoom)  -- Line 55
nvg.strokeWidth(nvg_ctx, 3.0)  -- Line 108
nvg.circle(nvg_ctx, x, y, editor.node_port_radius - 2)  -- Line 148
```
**Impact:** Reduces maintainability. Should define named constants for stroke widths and padding values.

**m3: Incomplete Input Validation** (manufold_agent.lua:95-97)
```lua
if not arguments or not arguments.path then
    return {success = false, error = "Missing path parameter"}
end
-- Doesn't validate path is non-empty string, or path exists
```
**Impact:** Could pass empty strings or non-existent paths to filesystem operations, causing unclear errors downstream.

**m4: Loose Equality Comparisons** (harmony_adapter.lua:335-343)
```lua
elseif text:sub(i, i + 3) == "true" then
    -- Should check word boundaries
    -- "truetype" would partially match
```
**Impact:** Keywords could be matched within identifiers if not followed by whitespace or delimiters.

**m5: Missing Type Guards** (workflow_editor/node.lua:117-129)
```lua
local node_type = node_types[node.type_index]
-- Assumes node_types is array and index is valid
-- Should check: if not node_type then return end
```
**Impact:** If node_types is reloaded and indices change, could access nil, causing crashes.

**m6: Hardcoded Font Names** (workflow_editor/render.lua:164)
```lua
nvg.fontFace(nvg_ctx, "roboto")
-- Repeated in multiple places
```
**Impact:** No fallback if font isn't loaded. Should centralize font names as constants with fallbacks.

**m7: No Version Checking** (lm_studio_client.lua:12-18)
```lua
function LMStudioClient.new(base_url, model)
    self.base_url = base_url or "http://127.0.0.1:1234"
    -- No check that server is compatible version
end
```
**Impact:** API changes in LM Studio could cause silent failures. Should check API version in health_check.

**m8: Redundant Color Conversions** (workflow_editor/init.lua:50-54)
```lua
color = nvg.rgba(
    node_type.color_r or 128,
    node_type.color_g or 128,
    node_type.color_b or 128,
    node_type.color_a or 255
)
-- Duplicated in node.lua:14-19 and render.lua:329-334
```
**Impact:** Color conversion logic scattered across 3 files. Should centralize in node module.

**m9: Missing Null Checks in Tetris** (tetris.lua:271-276)
```lua
local function get_ghost_position()
    local ghost_y = game.current_y
    while is_valid_position(game.current_piece, ...) do
        -- Assumes game.current_piece is not nil
```
**Impact:** If called during initialization or game over, could access nil. Should add guard.

**m10: Inefficient Table Iteration** (file_inspector.lua:278-284)
```lua
for _, file in ipairs(files) do
    local dir = fs.dirname(file.path)
    if not dir_tree[dir] then
        dir_tree[dir] = {}
    end
    table.insert(dir_tree[dir], file.name)
end
-- Could use table.insert which is O(1) amortized
```
**Impact:** Minor performance issue with large file collections. Current approach is fine, but comment suggests understanding could be improved.

### Workflow Editor Analysis

**Canvas Rendering Performance:**
- **Pros:** Clean separation of rendering and logic; efficient use of NanoVG state management (save/restore)
- **Cons:** Grid rendering not optimized for extreme zoom levels; all nodes redrawn every frame even when static

**Node System Design:**
- **Pros:** Immutable node type definitions; dynamic port counts; labels support multi-line text
- **Cons:** No node validation on creation; missing undo/redo support; no grouping or subgraphs

**Interaction Quality:**
- **Pros:** Smooth panning with middle mouse; keyboard shortcuts for common operations; visual feedback for hover states
- **Cons:** No drag threshold for accidental movements; no snap-to-grid option; menu can go off-screen

**Server Synchronization:**
- **Pros:** Clear ownership model (server is source of truth); efficient updates (only on drag completion)
- **Cons:** Potential race conditions during rapid interactions; no conflict resolution; no offline support

**Code Organization:**
- **Excellent:** 8 focused modules with clear responsibilities; consistent naming conventions; no circular dependencies
- The modular structure makes testing and modification straightforward

### Tool Integration Quality

**Manufold Agent Design:**
- **Pros:** Well-structured state machine; view-oriented responses provide rich context; comprehensive tool set covers full workflow
- **Cons:** No error recovery strategy; unbounded conversation history; hardcoded paths

**Harmony Adapter Implementation:**
- **Pros:** Complete character-level tokenizer; robust JSON parser from tokens; excellent error context
- **Cons:** Keyword matching could be improved; no optimization for large responses; tokenizer not reusable outside this context

**Parser Executor Safety:**
- **Pros:** Sandboxed environment; comprehensive result tracking; transaction-based insertion
- **Cons:** No CPU/memory limits; SQL injection vulnerability; no timeout mechanism

**File Inspector Intelligence:**
- **Pros:** Smart format detection; automatic sampling; structure hints; relationship analysis
- **Cons:** Case-sensitive extension matching; binary detection could be improved (checks only first 512 bytes)

### Performance Considerations

**Canvas Rendering:**
- Grid rendering: O(gridLines) where gridLines increases with zoom out
- Node rendering: O(nodes) - all nodes redrawn each frame
- Connection rendering: O(connections) with bezier curve calculations
- **Optimization opportunity:** Only redraw when state changes; cull off-screen nodes

**Tool Execution:**
- File inspection: O(fileSize) for content sampling, but capped at max_bytes
- Parser execution: O(files × rowsPerFile) for batch processing
- Database operations: Transaction batching provides good performance
- **Optimization opportunity:** Stream large files instead of full read

**Memory Usage:**
- Conversation history: Unbounded growth - **Critical issue**
- Ingested files: Full file metadata kept in memory - reasonable for typical use
- Workflow nodes: Small fixed size per node - excellent
- Token arrays: Created per response, GC'd after parsing - good

**HTTP Client:**
- Streaming support prevents memory buildup for large responses
- 5-minute timeout is generous but prevents hangs
- No connection pooling (probably fine for single-server use)

## Recommendations

### Priority 1: Critical Security and Stability

1. **Add Parser Execution Limits** (parser_executor.lua)
   ```lua
   -- Wrap parser execution with timeout and resource limits
   local timeout = 30  -- seconds
   local max_memory = 100 * 1024 * 1024  -- 100MB

   local co = coroutine.create(parser_func)
   local start_time = os.clock()

   while coroutine.status(co) ~= "dead" do
       if os.clock() - start_time > timeout then
           return {error = "Parser timeout"}
       end
       local success, result = coroutine.resume(co)
       if not success then
           return {error = result}
       end
   end
   ```

2. **Use Prepared Statements** (parser_executor.lua:240-285)
   - Replace string concatenation with SQLite prepared statements
   - Or use a proper SQL builder library if available

3. **Add Tool Execution Error Recovery** (manufold_agent.lua:399-430)
   ```lua
   local critical_tools = {"execute_schema", "execute_parser"}
   for _, call in ipairs(tool_calls) do
       local result = execute_tool(call.name, call.arguments)
       if not result.success and table_contains(critical_tools, call.name) then
           -- Stop execution and report critical failure
           return send_error_to_agent(result.error)
       end
   end
   ```

4. **Implement Conversation History Trimming** (manufold_agent.lua:344-359)
   ```lua
   -- Keep only recent messages to prevent memory growth
   local max_messages = 50
   if #agent_state.conversation_history > max_messages then
       -- Keep system message and most recent messages
       local recent = {}
       for i = #agent_state.conversation_history - max_messages + 1,
               #agent_state.conversation_history do
           table.insert(recent, agent_state.conversation_history[i])
       end
       agent_state.conversation_history = recent
   end
   ```

### Priority 2: Major Functionality Improvements

5. **Add Connection Validation** (workflow_editor/connection.lua)
   ```lua
   function M.add(editor, from_node_id, from_port, to_node_id, to_port)
       -- Validate nodes exist
       local from_node = node_module.find_by_id(editor, from_node_id)
       local to_node = node_module.find_by_id(editor, to_node_id)
       if not from_node or not to_node then
           return false, "Node not found"
       end

       -- Validate port indices
       if from_port < 1 or from_port > #from_node.outputs then
           return false, "Invalid output port"
       end
       if to_port < 1 or to_port > #to_node.inputs then
           return false, "Invalid input port"
       end

       -- Existing duplicate check...
   end
   ```

6. **Optimize Grid Rendering** (workflow_editor/render.lua:10-80)
   ```lua
   -- Skip grid or increase spacing at low zoom
   if editor.zoom < 0.5 then
       grid_spacing = editor.grid_size * 5  -- Show only accent grid
   end

   -- Calculate visible grid lines count
   local num_lines = (world_x2 - world_x1) / grid_spacing
   if num_lines > 200 then
       -- Skip grid rendering entirely at extreme zoom out
       nvg.restore(nvg_ctx)
       return
   end
   ```

7. **Add Drag Threshold** (workflow_editor/input.lua:74-83)
   ```lua
   local DRAG_THRESHOLD = 3  -- pixels

   -- On mouse down, store potential drag node
   editor.potential_drag = node
   editor.drag_start_x = mouse_x
   editor.drag_start_y = mouse_y

   -- On mouse move, check threshold
   local dx = mouse_x - editor.drag_start_x
   local dy = mouse_y - editor.drag_start_y
   if math.sqrt(dx*dx + dy*dy) > DRAG_THRESHOLD then
       editor.dragging_node = editor.potential_drag
   end
   ```

8. **Constrain Menu Position** (workflow_editor/render.lua:286-289)
   ```lua
   local menu_x = editor.canvas_x + editor.node_menu_x
   local menu_y = editor.canvas_y + editor.node_menu_y

   -- Keep menu on screen
   if menu_x + menu_width > canvas_x + canvas_w then
       menu_x = canvas_x + canvas_w - menu_width - 5
   end
   if menu_y + menu_height > canvas_y + canvas_h then
       menu_y = canvas_y + canvas_h - menu_height - 5
   end
   ```

### Priority 3: Code Quality and Maintainability

9. **Standardize Error Response Format**
   - Create error response builder utility
   - Use consistently across all tool executors
   - Document error format in model_adapter.lua

10. **Extract Magic Numbers to Constants**
    ```lua
    -- At top of render.lua
    local STROKE_WIDTH = {
        GRID = 1.0,
        GRID_ACCENT = 1.5,
        CONNECTION = 3.0,
        NODE_BORDER = 2.0,
        NODE_BORDER_SELECTED = 3.0,
        PORT_OUTLINE = 1.5
    }
    ```

11. **Centralize Color Conversion** (workflow_editor/node.lua)
    ```lua
    function M.create_color(node_type)
        return nvg.rgba(
            node_type.color_r or 128,
            node_type.color_g or 128,
            node_type.color_b or 128,
            node_type.color_a or 255
        )
    end
    ```

12. **Add Input Validation Layer**
    - Create validation utilities for common patterns (path, number range, string length)
    - Apply consistently across all tool handlers
    - Return clear validation error messages

13. **Improve File Extension Handling** (file_inspector.lua)
    ```lua
    local extension = fs.extension(path)
    if extension then
        extension = extension:lower()  -- Normalize to lowercase
    end
    ```

14. **Add Type Guards in Critical Paths**
    ```lua
    function M.update_from_types(editor, node_types)
        if not node_types or type(node_types) ~= "table" then
            print("[Workflow] Invalid node_types provided")
            return
        end

        for _, node in ipairs(editor.nodes) do
            if not node.type_index then
                print("[Workflow] Node missing type_index: " .. node.id)
                continue
            end
            -- ... rest of function
        end
    end
    ```

### Priority 4: Feature Enhancements

15. **Add Workflow Editor Features**
    - Undo/redo system using command pattern
    - Snap-to-grid option (toggle with 'G' key)
    - Multi-node selection with Shift+click
    - Node search/filter in creation menu
    - Connection type validation based on port data types

16. **Enhance Parser Sandbox**
    - Add memory usage tracking
    - Provide CSV parsing utilities
    - Add XML parsing utilities
    - Include data validation helpers (email, date, etc.)

17. **Improve Agent Feedback**
    - Show tool execution progress in UI
    - Display parsed data samples in validation phase
    - Add ability to edit generated parsers before execution
    - Provide data quality visualizations

18. **Add Tetris Features** (optional, low priority)
    - High score persistence
    - Hold piece mechanic
    - T-spin detection
    - Sound effects and visual polish

## Dependencies & Integration

### External Dependencies

**NanoVG:**
- Used extensively in workflow editor and Tetris
- All rendering functions use nvg.* API
- Assumed to be globally available
- No fallback if unavailable

**SQLite:**
- Used by parser executor and database tools
- Accessed via global `sqlite` object
- No connection pooling
- No migration system

**HTTP:**
- Used by LM Studio client
- Accessed via global `http` object
- Supports streaming (SSE)
- No retry logic or circuit breaker

**JSON:**
- Used throughout for serialization
- Accessed via global `json` object
- No schema validation
- Error handling via pcall

**Filesystem:**
- Used by file inspector and parser executor
- Accessed via global `fs` object
- Read-only operations in sandbox
- No quota enforcement

### Integration Points

**Data Binding System:**
- Workflow editor reads from `data.get("workflow_nodes")`
- Workflow editor reads from `data.get("workflow_connections")`
- Workflow editor reads from `data.get("node_types")`
- Agent binds to `manufold` namespace
- Updates via `data.update_row()` for immediate UI sync

**Event System:**
- Workflow emits: `workflow_node_created`, `workflow_node_moved`, `workflow_node_deleted`, `workflow_connection_added`
- Agent registers: `file_drop`, `start_exploration`, `send_message`, `submit_feedback`, `approve_understanding`, `approve_schema`, `start_import`, `reset_session`
- Global events via `event.register_global()`
- Thread-local events via `event.register()`

**UI Integration:**
- Workflow editor renders on ElementCanvas via `render_workflow()`
- Input handlers called by ElementCanvas event system
- Tetris renders on ElementCanvas via `render_tetris()`
- Agent loads RML document via `ui.load_document()`

**Thread Model:**
- Agent runs in worker thread (has `thread_id`)
- Workflow editor runs in UI thread
- No explicit thread synchronization
- Relies on data binding system for cross-thread communication

### API Surface

**Public Functions:**

Workflow Editor (init.lua):
```lua
render_workflow(nvg_ctx, canvas_x, canvas_y, canvas_w, canvas_h, time)
handle_workflow_click(button, button_down, mouse_x, mouse_y, canvas_x, canvas_y)
handle_workflow_move(mouse_x, mouse_y, canvas_x, canvas_y, button_left, button_middle, button_right)
handle_workflow_scroll(wheel_x, wheel_y)
handle_workflow_key(key, key_down)
```

Tetris (tetris.lua):
```lua
render_tetris(nvg_ctx, x, y, w, h, time)
handle_tetris_mouse(button, button_down, mouse_x, mouse_y, canvas_x, canvas_y)
handle_tetris_key(key, key_down)
```

Manufold Agent (manufold_agent.lua):
```lua
startup()  -- Called by thread system
update(dt)  -- Called every frame
shutdown()  -- Called on thread exit
```

LM Studio Client (lm_studio_client.lua):
```lua
LMStudioClient.new(base_url, model) -> client
client:chat(messages, options) -> response, error
client:chat_stream(messages, callbacks, options) -> error
client:list_models() -> models, error
client:get_model(model_id) -> model_info, error
client:complete(prompt, options) -> response, error
client:complete_stream(prompt, callbacks, options) -> error
client:health_check() -> is_healthy, error
```

## Summary

This component demonstrates **strong architectural design** with excellent separation of concerns and modular organization. The workflow editor is particularly well-structured with 8 focused modules. The tool integration system uses a sophisticated view-oriented design that provides rich context to agents.

**Key Strengths:**
- Professional modular architecture
- Comprehensive tool system with rich responses
- Robust tokenizer and parser for Harmony format
- Clean coordinate transformation system
- Excellent error context in parser failures

**Critical Concerns:**
- SQL injection vulnerability in parser executor
- Missing execution limits for parser scripts
- Unbounded memory growth in conversation history
- Race conditions in workflow state synchronization

**Recommended Actions:**
1. Immediately address SQL injection (use prepared statements)
2. Add CPU/memory limits to parser sandbox
3. Implement conversation history trimming
4. Add connection validation to workflow editor
5. Optimize grid rendering for extreme zoom levels

The codebase is production-ready after addressing the critical security issues. The architecture is sound and maintainable. The sophisticated tool system and workflow editor provide strong foundations for the Manufold data transformation platform.
