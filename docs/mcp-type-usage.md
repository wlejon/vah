# MCP Data Type Usage Guide

## Overview

The MCP View System provides 7 data types for exploring vah's data. Each type supports the same 6 navigation tools: `list`, `detail`, `summary`, `search`, `diff`, and `status`.

## Data Types and Context Requirements

### Standalone Types (No Context Required)

These types work without additional context parameters:

#### 1. **database**
Lists SQLite databases in the `data/` directory.

```json
// List all databases
{"type": "database"}

// View specific database
{"type": "database", "id": "data/myapp.db"}
```

#### 2. **file**
Lists files in a directory.

```json
// List files in current directory
{"type": "file"}

// List files in specific directory
{"type": "file", "context": {"directory": "scripts"}}

// View specific file
{"type": "file", "id": "scripts/main.lua"}
```

#### 3. **directory**
Lists subdirectories within a directory.

```json
// List directories in current directory
{"type": "directory"}

// List subdirectories of a specific directory
{"type": "directory", "context": {"directory": "scripts"}}

// View specific directory
{"type": "directory", "id": "scripts/mcp_tools"}
```

#### 4. **application**
Lists running application threads.

```json
// List all applications
{"type": "application"}

// View specific application
{"type": "application", "id": "3"}
```

**Note:** Currently uses placeholder data until `thread.list()` API is implemented in C++.

#### 5. **document**
Lists loaded RML documents.

```json
// List all documents
{"type": "document"}

// View specific document
{"type": "document", "id": "menu"}
```

**Note:** Currently uses placeholder data until `ui.list_documents()` API is implemented in C++.

### Context-Dependent Types

These types **require** context parameters to work:

#### 6. **table**
Lists tables within a database. **Requires:** `database` context parameter.

```json
// List tables in a database
{
  "type": "table",
  "context": {"database": "data/contacts.db"}
}

// View specific table
{
  "type": "table",
  "id": "users",
  "context": {"database": "data/contacts.db"}
}

// Search tables
{
  "type": "table",
  "query": "user",
  "context": {"database": "data/contacts.db"}
}
```

#### 7. **row**
Lists rows within a database table. **Requires:** `database` and `table` context parameters.

```json
// List rows in a table
{
  "type": "row",
  "context": {
    "database": "data/contacts.db",
    "table": "users"
  }
}

// View specific row (using primary key or rowid)
{
  "type": "row",
  "id": "123",
  "context": {
    "database": "data/contacts.db",
    "table": "users",
    "primary_key": "id"  // optional, defaults to "rowid"
  }
}

// Search within rows
{
  "type": "row",
  "query": "john",
  "context": {
    "database": "data/contacts.db",
    "table": "users"
  }
}
```

## Navigation Tools

All types support these 6 tools:

### 1. `list` - View collections
```json
{
  "name": "list",
  "arguments": {
    "type": "database",
    "page": 1,        // optional, default: 1
    "limit": 10,      // optional, default: 10
    "context": {}     // optional, type-specific
  }
}
```

### 2. `detail` - View single item
```json
{
  "name": "detail",
  "arguments": {
    "type": "database",
    "id": "data/myapp.db",
    "context": {}     // optional, type-specific
  }
}
```

### 3. `summary` - View statistics
```json
{
  "name": "summary",
  "arguments": {
    "type": "database",
    "context": {}     // optional, type-specific
  }
}
```

### 4. `search` - Search within type
```json
{
  "name": "search",
  "arguments": {
    "type": "database",
    "query": "contacts",
    "context": {}     // optional, type-specific
  }
}
```

### 5. `diff` - Compare versions
```json
{
  "name": "diff",
  "arguments": {
    "type": "database",
    "id": "data/myapp.db",
    "context": {}     // optional, type-specific
  }
}
```

**Note:** Currently returns "not supported" for all types. Placeholder for future implementation.

### 6. `status` - Get system status
```json
{
  "name": "status",
  "arguments": {}
}
```

Returns application-wide status. Does not change navigation context.

## Typical Navigation Flows

### Exploring Databases
```
1. list databases → shows all .db files
2. detail on specific database → shows table count, size, etc.
3. list tables (with database context) → shows tables in that database
4. detail on specific table → shows schema, row count, indexes
5. list rows (with database + table context) → shows actual data
6. detail on specific row → shows all column values
```

### Browsing Files
```
1. list directories → shows subdirectories
2. detail on specific directory → shows contents count, size
3. list files (with directory context) → shows files
4. detail on specific file → shows metadata, content preview
```

### Monitoring System
```
1. status → overall system health
2. list applications → running threads
3. detail on application → thread details, memory usage
4. list documents → loaded RML documents
5. detail on document → element count, visibility
```

## Error Handling

### Missing Context
If you try to list rows without providing database and table context:
```
Error: Missing required context parameter: database
```

Solution: Always provide required context:
```json
{
  "type": "row",
  "context": {
    "database": "data/mydb.db",
    "table": "mytable"
  }
}
```

### Invalid IDs
If you request a detail view with an invalid ID:
```
Error: Database not found: data/invalid.db
```

Solution: Use `list` or `search` first to find valid IDs.

## Current Limitations

### Read-Only
All types are currently read-only. No action tools are implemented yet for:
- Creating/deleting databases
- Creating/modifying tables
- Inserting/updating/deleting rows
- Creating/deleting files or directories
- Starting/stopping threads
- Showing/hiding documents

### Placeholder Data
- `application` type uses placeholder data until `thread.list()` C++ API is available
- `document` type uses placeholder data until `ui.list_documents()` C++ API is available

### Diff Not Implemented
The `diff` tool currently returns "not supported" for all types. This is a placeholder for future version comparison functionality.

## Tips for LLMs

1. **Start with `list`** - Always start by listing items before trying to view details
2. **Use `summary`** - Get overview statistics before diving into details
3. **Provide context** - Remember to include context for table and row types
4. **Search first** - Use `search` to find items when you know partial information
5. **Check status** - Use `status` to see overall system health
6. **Navigate hierarchically** - Follow the natural flow: databases → tables → rows

## Examples

### Find all databases and explore one
```
1. list(type="database")
2. detail(type="database", id="data/contacts.db")
3. list(type="table", context={database="data/contacts.db"})
```

### Search for a file
```
1. search(type="file", query="mcp", context={directory="scripts"})
2. detail(type="file", id="scripts/mcp_server.lua")
```

### Monitor running applications
```
1. summary(type="application")
2. list(type="application")
3. detail(type="application", id="3")
```
