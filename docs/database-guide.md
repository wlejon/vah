# Database Guide

Comprehensive guide to using SQLite in vah with schema management, validation, and best practices.

## Overview

The vah database system provides:

- **SQLite integration** with full CRUD operations
- **Transaction support** for atomic operations
- **Batch operations** for high-performance inserts
- **Schema management** for creating and validating database structures
- **Data validation** and quality checks
- **Introspection tools** for analyzing databases

## Core Components

### 1. SqliteBindings (C++)

Low-level SQLite bindings exposed to Lua.

**Location:** `src/SqliteBindings.cpp`

### 2. Schema Manager (Lua)

High-level schema creation and management.

**Location:** `scripts/schema_manager.lua`

### 3. Database Tools (Lua)

Validation, analysis, and utilities.

**Location:** `scripts/db_tools.lua`

---

## Quick Start

### Opening a Database

```lua
local db, error = db.open("data/myapp.db")
if error ~= "" then
    print("Error: " .. error)
    return
end
```

### Basic Operations

```lua
-- Execute DDL (create table, etc.)
local success, error = db:execute([[
    CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT UNIQUE
    )
]])

-- Query data
local results, error = db:query("SELECT * FROM users WHERE name = ?", "Alice")

-- Query single row
local user, error = db:query_single("SELECT * FROM users WHERE id = ?", 1)

-- Close database
db:close()
```

---

## Schema Management

### Defining Schemas

Use the schema manager to define database structures programmatically:

```lua
local schema_manager = require("schema_manager")

local schema = {
    tables = {
        {
            name = "users",
            columns = {
                {name = "id", type = "INTEGER PRIMARY KEY AUTOINCREMENT"},
                {name = "name", type = "TEXT", not_null = true},
                {name = "email", type = "TEXT", unique = true},
                {name = "age", type = "INTEGER", check = "age >= 0"},
                {name = "active", type = "INTEGER", default = 1}
            },
            indexes = {
                {columns = {"email"}},
                {columns = {"active", "name"}}
            }
        }
    }
}
```

### Column Definition Options

| Property | Type | Description |
|----------|------|-------------|
| `name` | string | Column name (required) |
| `type` | string | SQLite type (INTEGER, TEXT, REAL, BLOB) |
| `not_null` | boolean | NOT NULL constraint |
| `unique` | boolean | UNIQUE constraint |
| `default` | any | DEFAULT value |
| `check` | string | CHECK constraint expression |

### Type Mapping

The schema manager automatically maps common types to SQLite types:

| Input Type | SQLite Type |
|------------|-------------|
| `int`, `integer` | INTEGER |
| `string`, `text`, `varchar` | TEXT |
| `float`, `double`, `real` | REAL |
| `boolean`, `bool` | INTEGER |
| `date`, `datetime` | TEXT |
| `id` | INTEGER PRIMARY KEY AUTOINCREMENT |

### Creating Schemas

```lua
local success, error = schema_manager.create_schema(db, schema)
if not success then
    print("Schema creation failed: " .. error)
end
```

### Foreign Keys

```lua
{
    name = "orders",
    columns = {
        {name = "id", type = "id"},
        {name = "user_id", type = "INTEGER", not_null = true},
        {name = "total", type = "REAL"}
    },
    foreign_keys = {
        {
            column = "user_id",
            references_table = "users",
            references_column = "id",
            on_delete = "CASCADE",
            on_update = "RESTRICT"
        }
    }
}
```

### Composite Primary Keys

```lua
{
    name = "user_roles",
    columns = {
        {name = "user_id", type = "INTEGER"},
        {name = "role_id", type = "INTEGER"}
    },
    primary_key = {"user_id", "role_id"}
}
```

---

## Transactions

### Manual Transactions

```lua
local success, error = db:begin_transaction()
if not success then
    print("Failed to start transaction: " .. error)
    return
end

-- Perform operations
db:query("INSERT INTO users (name) VALUES (?)", "Alice")
db:query("INSERT INTO users (name) VALUES (?)", "Bob")

-- Commit or rollback
if some_condition then
    db:commit()
else
    db:rollback()
end
```

### Transaction Helper

The schema manager provides a safe transaction wrapper:

```lua
local success, result = schema_manager.transaction(db, function(db)
    -- All operations here are in a transaction
    db:query("INSERT INTO users (name) VALUES (?)", "Alice")
    db:query("INSERT INTO users (name) VALUES (?)", "Bob")

    -- Return true to commit, false to rollback
    return true
end)
```

**Benefits:**
- Automatic rollback on errors
- Exception safety (pcall wrapper)
- Cleaner code

---

## Batch Operations

### Batch Insert

For inserting large datasets efficiently:

```lua
-- Prepare data
local users = {
    {name = "Alice", email = "alice@example.com"},
    {name = "Bob", email = "bob@example.com"},
    {name = "Carol", email = "carol@example.com"}
    -- ... thousands more
}

-- Define columns
local columns = {"name", "email"}

-- Insert in batches
local count, error = schema_manager.batch_insert(
    db,
    "users",           -- table name
    columns,           -- column names
    users,             -- data rows
    1000              -- batch size (optional, default 1000)
)

print(string.format("Inserted %d rows", count))
```

**Performance Notes:**
- Batching uses prepared statements (faster)
- Automatic transaction management
- Recommended batch size: 500-2000 rows

### Low-Level Batch Insert

```lua
-- Direct C++ batch insert (no transaction wrapper)
local count, error = db:batch_insert("users", columns, users)
```

---

## Data Validation

### Validate Before Import

```lua
local db_tools = require("db_tools")

-- Sample data to validate
local rows = {
    {name = "Alice", email = "alice@example.com"},
    {name = nil, email = "bob@example.com"}  -- Missing required field
}

-- Validate against schema
local valid, errors = db_tools.validate_data(schema, "users", rows)

if not valid then
    print("Validation errors:")
    for _, err in ipairs(errors) do
        print("  - " .. err)
    end
end
```

**Checks:**
- Required fields (NOT NULL columns)
- Type compatibility
- Missing columns

---

## Data Analysis

### Analyze Table Quality

```lua
local analysis, error = db_tools.analyze_table(db, "users")

if analysis then
    db_tools.print_analysis(analysis)
end
```

**Returns:**
- Row count
- Null counts per column
- Unique value counts
- Sample values
- Completeness percentage

**Example Output:**
```
Table: users
Rows: 1000

Columns:
  id (INTEGER)
    Null count: 0 (100.0% complete)
    Unique values: 1000
    Sample: 1, 2, 3, 4, 5

  email (TEXT)
    Null count: 15 (98.5% complete)
    Unique values: 985
    Sample: alice@example.com, bob@example.com, ...
```

### Find Duplicates

```lua
local duplicates, error = db_tools.find_duplicates(
    db,
    "users",
    {"email"}  -- columns to check
)

if duplicates and #duplicates > 0 then
    for _, dup in ipairs(duplicates) do
        print(string.format("%s appears %d times", dup.email, dup.count))
    end
end
```

### Check Referential Integrity

```lua
local valid, error = db_tools.check_referential_integrity(
    db,
    "orders",          -- child table
    "user_id",         -- foreign key column
    "users",           -- parent table
    "id"               -- parent key column
)

if not valid then
    print("Integrity violation: " .. error)
end
```

---

## Introspection

### Get Current Schema

```lua
local current_schema, error = schema_manager.get_schema(db)

if current_schema then
    schema_manager.print_schema(current_schema)
end
```

### List Tables

```lua
local tables, error = db:get_tables()

for _, table_row in ipairs(tables or {}) do
    print("Table: " .. table_row.name)
end
```

### Get Table Info

```lua
local info, error = db:get_table_info("users")

for _, col in ipairs(info or {}) do
    print(string.format("%s (%s)", col.name, col.type))
end
```

### Check Table Exists

```lua
if db:table_exists("users") then
    print("Users table exists")
end
```

### Get Table Statistics

```lua
local stats, error = db_tools.get_table_stats(db)

for _, stat in ipairs(stats or {}) do
    print(string.format("%s: %d rows", stat.name, stat.row_count))
end
```

---

## Query Testing

Test queries for syntax and execution:

```lua
local success, result = db_tools.test_query(
    db,
    "SELECT * FROM users WHERE age > ?",
    {18}  -- parameters
)

if success then
    print(string.format("Query returned %d rows", result.row_count))
else
    print("Query failed: " .. result)
end
```

---

## Schema Inference

Generate schema from sample data:

```lua
-- Sample data
local sample_rows = {
    {id = 1, name = "Alice", age = 30, active = true},
    {id = 2, name = "Bob", age = 25, active = false}
}

-- Infer schema
local inferred_schema, error = schema_manager.infer_schema(
    "users",
    sample_rows,
    {add_id = true, id_column = "id"}
)

if inferred_schema then
    schema_manager.print_schema(inferred_schema)
end
```

**Type Inference Rules:**
- Numbers → INTEGER (if whole) or REAL
- Strings → TEXT
- Booleans → INTEGER
- Default → TEXT

---

## Best Practices

### ✓ Always Use Parameterized Queries

**Bad:**
```lua
local name = user_input
db:query("SELECT * FROM users WHERE name = '" .. name .. "'")  -- SQL INJECTION!
```

**Good:**
```lua
db:query("SELECT * FROM users WHERE name = ?", name)
```

### ✓ Use Transactions for Multiple Operations

```lua
schema_manager.transaction(db, function(db)
    db:query("DELETE FROM orders WHERE user_id = ?", user_id)
    db:query("DELETE FROM users WHERE id = ?", user_id)
    return true
end)
```

### ✓ Batch Large Inserts

Don't insert rows one-by-one. Use batch operations:

```lua
-- Bad: 1000 separate inserts
for i = 1, 1000 do
    db:query("INSERT INTO users VALUES (?)", data[i])
end

-- Good: Single batch operation
schema_manager.batch_insert(db, "users", columns, data)
```

### ✓ Define Schemas Programmatically

Avoid raw SQL for schema creation. Use the schema manager:

```lua
local schema = {
    tables = {
        {name = "users", columns = {...}}
    }
}

schema_manager.create_schema(db, schema)
```

**Benefits:**
- Validation
- Consistency
- Easier to modify
- Self-documenting

### ✓ Validate Data Before Import

```lua
local valid, errors = db_tools.validate_data(schema, table_name, rows)
if not valid then
    -- Handle errors
end
```

### ✓ Close Databases Properly

```lua
function shutdown()
    if database then
        database:close()
    end
end
```

---

## Performance Tips

1. **Use indexes** for frequently queried columns
2. **Batch operations** for bulk inserts (10-100x faster)
3. **Transactions** reduce disk I/O
4. **VACUUM** periodically to reclaim space
5. **Prepared statements** (automatic with parameterized queries)
6. **Limit result sets** when possible

---

## Error Handling

All database operations return `(result, error)` tuples:

```lua
local result, error = db:query("SELECT * FROM users")

if error ~= "" then
    print("Error: " .. error)
    return
end

-- Process result
for _, row in ipairs(result or {}) do
    print(row.name)
end
```

---

## Examples

See these files for complete examples:

- `scripts/sqlite_demo.lua` - Basic CRUD operations
- `scripts/db_example.lua` - Comprehensive best practices
- `scripts/code_flow_viewer.lua` - Real-world usage

---

## API Reference

### Database Object

```lua
db:open(path) → (success, error)
db:close()
db:execute(sql) → (success, error)
db:query(sql, ...params) → (results, error)
db:query_single(sql, ...params) → (row, error)
db:begin_transaction() → (success, error)
db:commit() → (success, error)
db:rollback() → (success, error)
db:batch_insert(table, columns, rows) → (count, error)
db:get_table_info(table_name) → (info, error)
db:get_tables() → (tables, error)
db:table_exists(table_name) → boolean
db:last_insert_rowid() → integer
db:changes_count() → integer
db:is_open() → boolean
```

### Schema Manager

```lua
schema_manager.create_schema(db, schema) → (success, error)
schema_manager.get_schema(db) → (schema, error)
schema_manager.validate_schema(db, schema) → (valid, error)
schema_manager.transaction(db, fn) → (success, result)
schema_manager.batch_insert(db, table, columns, rows, batch_size) → (count, error)
schema_manager.infer_schema(table_name, sample_rows, options) → (schema, error)
schema_manager.print_schema(schema)
```

### Database Tools

```lua
db_tools.validate_data(schema, table_name, rows) → (valid, errors)
db_tools.analyze_table(db, table_name) → (analysis, error)
db_tools.test_query(db, sql, params) → (success, result)
db_tools.find_duplicates(db, table_name, columns) → (duplicates, error)
db_tools.check_referential_integrity(db, ...) → (valid, error)
db_tools.get_table_stats(db) → (stats, error)
db_tools.compare_schemas(schema1, schema2) → (has_changes, differences)
db_tools.export_table(db, table_name, limit) → (rows, error)
db_tools.vacuum(db) → (success, error)
db_tools.print_analysis(analysis)
```

---

## Troubleshooting

### "Database is locked"

- Another thread is using the database
- Use transactions appropriately
- Close database connections when done

### "No such table"

- Check table name spelling
- Ensure schema was created successfully
- Use `db:get_tables()` to list existing tables

### Slow Inserts

- Use batch operations
- Wrap in transactions
- Add indexes AFTER bulk inserts, not before

### "Constraint failed"

- Check UNIQUE constraints
- Verify NOT NULL fields have values
- Validate foreign key references

---

## Advanced Topics

### Custom Types

Define application-specific type mappings in `schema_manager.lua`:

```lua
TYPE_MAP["uuid"] = "TEXT"
TYPE_MAP["json"] = "TEXT"
```

### Migration Pattern

```lua
-- Get current schema
local current, _ = schema_manager.get_schema(db)

-- Define new schema
local new_schema = {...}

-- Compare
local has_changes, diff = db_tools.compare_schemas(current, new_schema)

if has_changes then
    -- Apply migrations manually
end
```

### Read-Only Databases

```lua
-- Open in read-only mode (requires URI)
local db, error = db.open("file:data/readonly.db?mode=ro")
```

---

## Summary

The vah database system provides production-quality tools for:

✓ Schema-driven development
✓ Safe parameterized queries
✓ High-performance batch operations
✓ Transaction management
✓ Data validation and quality checks
✓ Comprehensive introspection

All designed to work seamlessly with vah's multi-threaded, lock-free architecture.
