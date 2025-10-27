# MCP Data Type Specification

## Overview

Data types define how specific kinds of data (contacts, files, databases, etc.) are queried and manipulated through the MCP interface.

## Type Definition Structure

Each type is defined in `mcp_views/types/{typename}.lua`:

```lua
return {
    -- Display name for this type
    name = "Contact",
    plural = "Contacts",

    -- Query functions for each view type
    -- Each receives context table and returns data structure
    query = {
        list = function(context)
            -- Return array of objects with pagination info
            return {
                items = {...},
                total = 100,
                page = context.page or 1,
                limit = context.limit or 10
            }
        end,

        detail = function(context)
            -- Return single object with all fields
            return {
                id = context.id,
                field1 = "value1",
                field2 = "value2",
                -- ...
            }
        end,

        summary = function(context)
            -- Return aggregate data
            return {
                total_count = 100,
                recent_count = 5,
                stats = {...}
            }
        end,

        search = function(context)
            -- Return search results
            return {
                query = context.query,
                items = {...},
                total_matches = 42
            }
        end,

        diff = function(context)
            -- Return before/after comparison
            return {
                before = {...},
                after = {...},
                changes = {...}
            }
        end,

        status = function(context)
            -- Return current state/health
            return {
                status = "ready",
                details = {...}
            }
        end
    },

    -- Action tools specific to this type
    -- Exposed when LLM is viewing this type
    tools = {
        {
            name = "create_contact",
            description = "Create a new contact",
            inputSchema = {
                type = "object",
                properties = {
                    name = {type = "string"},
                    email = {type = "string"}
                },
                required = {"name"}
            },
            handler = function(params)
                -- Create contact
                -- Return updated detail view
                return {
                    success = true,
                    view = "detail",
                    context = {type = "contacts", id = new_id}
                }
            end
        },

        {
            name = "update_contact",
            description = "Update existing contact",
            inputSchema = {...},
            handler = function(params)
                -- Update contact
                -- Return updated detail view
            end
        },

        {
            name = "delete_contact",
            description = "Delete a contact",
            inputSchema = {...},
            handler = function(params)
                -- Delete contact
                -- Return updated list view
            end
        }
    },

    -- Optional: Template overrides
    -- If generic template doesn't work, provide custom
    templates = {
        -- list = "path/to/custom/list.md",
        -- detail = "path/to/custom/detail.md"
    }
}
```

## Query Function Contracts

### List Query
**Input:** `{page, limit, sort_by, filter, ...context}`
**Output:**
```lua
{
    items = array,      -- Array of objects to display
    total = number,     -- Total count (all pages)
    page = number,      -- Current page
    limit = number      -- Items per page
}
```

### Detail Query
**Input:** `{id, ...context}`
**Output:** Single object with all relevant fields

### Summary Query
**Input:** `{...context}`
**Output:** Object with aggregate statistics

### Search Query
**Input:** `{query, ...context}`
**Output:**
```lua
{
    query = string,     -- The search query
    items = array,      -- Matching results
    total_matches = number
}
```

### Diff Query
**Input:** `{id, version, ...context}`
**Output:**
```lua
{
    before = object,
    after = object,
    changes = array     -- List of what changed
}
```

### Status Query
**Input:** `{...context}`
**Output:**
```lua
{
    status = string,    -- "ready", "error", "busy", etc.
    message = string,
    details = object
}
```

## Tool Handler Contract

**Input:** Parameter object matching inputSchema
**Output:**
```lua
{
    success = boolean,
    view = string,          -- Which view to show: "detail", "list", etc.
    context = table,        -- Context for the view
    message = string        -- Optional user message
}
```

The system automatically renders the specified view with the returned context and sends it back to the LLM.

## Built-in Data Types

Initial types to implement:
- `database` - SQLite databases
- `table` - Database tables
- `row` - Table rows (for editing)
- `file` - File system files
- `directory` - File system directories
- `application` - Running applications/threads
- `document` - Loaded RML documents
- `datamodel` - Bound data models

## Adding New Types

1. Create `mcp_views/types/yourtype.lua`
2. Export definition following structure above
3. Type is automatically discovered and registered
4. Tools become available when viewing that type

No core code changes required.
