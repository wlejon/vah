# MCP Session Management

## Overview

The MCP server maintains session state to provide contextual tool exposure. As the LLM navigates through different data types, the available tools change dynamically.

## Session Structure

Each connected client has a session:

```lua
{
    session_id = "uuid",
    created_at = timestamp,
    last_activity = timestamp,

    -- Current navigation context
    current_context = {
        type = "contacts",      -- What type is being viewed
        view = "detail",        -- Which view (list, detail, etc.)
        id = 42,                -- Specific item (if detail view)
        -- Other context data
    },

    -- Available tools for this session
    -- Updated as navigation changes
    available_tools = {
        -- Core navigation tools (always present)
        "list", "detail", "summary", "search", "diff", "status",

        -- Context-specific tools (dynamic)
        "create_contact", "update_contact", "delete_contact"
    },

    -- Recent actions (for showing in views)
    recent_actions = {
        {action = "Created contact 'John'", timestamp = ...},
        {action = "Updated table schema", timestamp = ...}
    }
}
```

## Tool Exposure Flow

1. **Initial connection**: Only navigation tools available
2. **LLM calls `list(type="contacts")`**:
   - Server looks up "contacts" type definition
   - Queries contact data
   - Renders list view
   - Updates `current_context.type = "contacts"`
   - Adds contact tools to `available_tools`
   - Returns view + updated tool list
3. **LLM calls `create_contact(...)`**:
   - Tool is available because viewing contacts
   - Handler creates contact
   - Returns updated view (detail of new contact)
   - Adds recent action to history
4. **LLM calls `list(type="files")`**:
   - Server removes contact tools
   - Adds file tools
   - Updates context
   - Returns file list view

## Context Inheritance

When navigating from one view to another, context can be inherited:

```lua
-- Viewing database list
current_context = {type = "databases"}

-- Navigate to specific database
list(type="tables", context={database="data/contacts.db"})

-- Context becomes:
current_context = {
    type = "tables",
    database = "data/contacts.db"  -- Inherited
}
```

This allows drilling down: databases → tables → rows

## Tool List Updates

When context changes, the server:

1. Removes all previous context-specific tools
2. Looks up new type definition
3. Adds new type's tools to available list
4. Returns tools/list MCP response

The LLM doesn't know where tools came from - they just appear and disappear naturally.

## Recent Actions

Recent actions are tracked per session and shown in views:

- Limited to last N actions (10?)
- Each action has timestamp
- Shown at top of views when relevant
- Provides feedback similar to UI changes

Example:
```markdown
# Contacts (47)

**Recent:** Created contact 'Jane Smith' (5 seconds ago)

| Name | Email | Phone |
...
```

## Session Timeout

Sessions expire after inactivity:
- Default timeout: 30 minutes
- Extended on each request
- On expiry: clean up session state, remove tools

## Multiple Sessions

The server supports multiple concurrent sessions:
- Each has independent context
- Tools exposed based on that session's navigation
- No cross-session interference

## Implementation Considerations

1. **Thread safety**: Sessions accessed from HTTP handler thread
2. **Memory**: Limit session count, size of recent_actions
3. **Performance**: Fast tool lookup (hash table by session_id)
4. **Cleanup**: Periodic sweep for expired sessions

## Context-Specific Tool Filtering

Some tools may only be available in specific contexts:

```lua
-- In type definition
tools = {
    {
        name = "update_contact",
        -- Only available in detail view
        available_in = {"detail"},
        -- ...
    }
}
```

This prevents showing irrelevant tools (can't update without viewing detail first).

## Status View Special Case

The `status()` tool returns application-wide state and doesn't change context:

```lua
-- Before: viewing contacts
status()  -- Shows app state
-- After: still viewing contacts, contact tools still available
```

This allows checking overall state without losing current navigation context.
