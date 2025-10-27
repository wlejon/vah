# MCP View System Architecture

## Overview

The MCP view system provides LLMs with a structured way to explore and interact with vah's data and functionality. Instead of exposing hundreds of specific tools, we use a small set of generic navigation tools combined with context-aware action tools.

## Core Principles

1. **Views are generic** - Six view types work for any data type
2. **Tools are contextual** - Action tools appear based on what data is being viewed
3. **Templates are reusable** - One markdown template renders many data types
4. **Types are self-contained** - Each data type defines its own queries and tools

## Navigation vs Action

**Navigation tools** (always available):
- `list(type, context, pagination...)` - View collections
- `detail(type, id, context...)` - View single entity
- `summary(type, context...)` - View aggregates
- `search(query, type, context...)` - Search within type
- `diff(type, id, context...)` - Compare versions
- `status()` - Application state

**Action tools** (contextual):
- Exposed only when viewing relevant data type
- Specific to the data (e.g., `create_contact`, `update_file`, `delete_table`)
- Defined by data type, not by core system

## How It Works

1. LLM calls navigation tool: `list(type="contacts")`
2. Server looks up "contacts" data type definition
3. Calls the type's query function to get data
4. Passes data to generic list template
5. Renders markdown view
6. Adds contact-specific action tools to available tools list
7. Returns rendered view to LLM

When LLM navigates elsewhere (e.g., `list(type="files")`), contact tools are removed and file tools are added.

## Benefits

- **Low initial complexity** - LLM starts with only 6-7 tools
- **Focused tool sets** - Only relevant actions available at any time
- **Extensible** - New data types add themselves without core changes
- **Token efficient** - Views are markdown, optimized for LLM consumption
- **Self-documenting** - Views show current state, tools show possible actions

## View Return Format

All navigation tools return:
- Markdown content (the view)
- Current context (what's being viewed)
- Recent action (if applicable)

The server uses this to track session state and manage tool availability.

## Data Type Structure

Each data type lives in `mcp_views/types/{typename}.lua` and exports:
- Query functions for each view type
- Tool definitions (schema + handler)
- Optional template overrides

See `mcp-data-types.md` for detailed specification.
