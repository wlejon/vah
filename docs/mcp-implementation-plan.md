# MCP View System Implementation Plan

## Implementation Order

The system should be built in this order to allow incremental testing:

### 1. Markdown Template Renderer
**Files:** `scripts/markdown_template_renderer.lua`

Build the template engine:
- Variable substitution `{{var}}`
- Conditionals `{{#if}}...{{/if}}`
- Loops `{{#each}}...{{/each}}`
- Nested access `{{obj.field}}`
- Helper variables `@key`, `@value`, etc.

**Test:** Render sample templates with test data

### 2. Generic Templates
**Files:** `mcp_views/templates/*.md`

Create the six templates:
- list.md
- detail.md
- summary.md
- search.md
- diff.md
- status.md

**Test:** Render each template with sample data

### 3. Type Registry System
**Files:** `scripts/mcp_type_registry.lua`

Build the type registration system:
- Scan `mcp_views/types/` directory
- Load type definitions
- Validate structure
- Build lookup table
- Provide query interface

**Test:** Register mock type, query it

### 4. Session Manager
**Files:** `scripts/mcp_session_manager.lua`

Build session management:
- Create/destroy sessions
- Track current context
- Manage available tools
- Record recent actions
- Session timeout/cleanup

**Test:** Create session, update context, verify tool changes

### 5. Core Navigation Tools
**Files:** Update `scripts/mcp_server.lua`

Implement the six navigation tools:
- list(type, context, page, limit, etc.)
- detail(type, id, context)
- summary(type, context)
- search(query, type, context)
- diff(type, id, context)
- status()

Each tool:
1. Looks up type in registry
2. Calls appropriate query function
3. Renders with template
4. Updates session context
5. Returns view + updates tool list

**Test:** Call each tool with sample data

### 6. First Data Type Implementation
**Files:** `mcp_views/types/database.lua`

Implement complete database type:
- Query functions for all six views
- Action tools (create, delete, vacuum, etc.)
- Use actual SQLite queries

**Test:** Navigate database views, call tools, verify context switches

### 7. Additional Data Types
**Files:** `mcp_views/types/*.lua`

Implement remaining types in order of importance:
1. table.lua (database tables)
2. file.lua (file system files)
3. directory.lua (file system directories)
4. application.lua (running apps)
5. document.lua (RML documents)
6. datamodel.lua (bound data models)

**Test:** Each type independently

### 8. Integration with MCP Server
**Files:** `scripts/mcp_server.lua`

Full integration:
- Initialize type registry on startup
- Create session per connection
- Route all tool calls through session manager
- Dynamic tool list updates
- Proper error handling

**Test:** End-to-end with actual MCP client

### 9. Documentation & Examples
**Files:** In `docs/` and inline comments

- Type definition guide with examples
- Template customization guide
- Tool development guide
- Architecture overview

## Estimated Scope

Breaking this into roughly 2000-line chunks:

1. **Template Renderer + Templates** (~500 lines)
   - Renderer: 300 lines
   - Templates: 200 lines

2. **Registry + Session Manager** (~800 lines)
   - Registry: 400 lines
   - Session manager: 400 lines

3. **Navigation Tools + Server Integration** (~500 lines)
   - Tools: 300 lines
   - Server updates: 200 lines

4. **Database + Table Types** (~600 lines)
   - Database: 300 lines
   - Table: 300 lines

5. **File System Types** (~400 lines)
   - File: 200 lines
   - Directory: 200 lines

6. **Application Types** (~300 lines)
   - Application: 150 lines
   - Document: 100 lines
   - Datamodel: 50 lines

**Total: ~3100 lines** (fits within 2-3 implementation sessions)

## Dependencies

External (already available):
- fs (file system operations)
- sqlite (database queries)
- json (for MCP protocol)

Internal (need to build):
- Template renderer
- Type registry
- Session manager

## Testing Strategy

Each component should be testable independently:
- Template renderer: Unit tests with sample data
- Type registry: Mock type definitions
- Session manager: Isolated session tests
- Navigation tools: Mock registry/session
- Data types: Against test databases/files

## Extension Points

The system provides clear extension points:
1. New data types: Add file to `mcp_views/types/`
2. Custom templates: Override in type definition
3. Custom tools: Define in type's tools array
4. New view types: Add template + update type query interface

## Migration Path

Existing MCP server can coexist during implementation:
1. Build new system alongside current implementation
2. Test with new endpoints first
3. Migrate when proven stable
4. Remove old tool implementations

No disruption to current functionality during development.
