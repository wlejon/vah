# Database Quick Start

Fast reference for common database operations in vah.

## Opening a Database

```lua
local db, error = db.open("data/myapp.db")
if error ~= "" then
    print("Error: " .. error)
    return
end
```

## Using Schema Manager

```lua
local schema_manager = require("schema_manager")

-- Define schema
local schema = {
    tables = {
        {
            name = "users",
            columns = {
                {name = "id", type = "id"},
                {name = "name", type = "text", not_null = true},
                {name = "email", type = "text", unique = true}
            }
        }
    }
}

-- Create schema
local success, error = schema_manager.create_schema(db, schema)
```

## Parameterized Queries (SAFE)

```lua
-- Insert
db:query("INSERT INTO users (name, email) VALUES (?, ?)", "Alice", "alice@example.com")

-- Select
local results, error = db:query("SELECT * FROM users WHERE name = ?", "Alice")

-- Update
db:query("UPDATE users SET email = ? WHERE id = ?", "newemail@example.com", 1)

-- Delete
db:query("DELETE FROM users WHERE id = ?", 1)
```

## Transactions

```lua
local schema_manager = require("schema_manager")

local success, error = schema_manager.transaction(db, function(db)
    db:query("INSERT INTO users (name) VALUES (?)", "Alice")
    db:query("INSERT INTO users (name) VALUES (?)", "Bob")
    return true  -- commit (false would rollback)
end)
```

## Batch Insert (Fast)

```lua
local users = {
    {name = "Alice", email = "alice@example.com"},
    {name = "Bob", email = "bob@example.com"}
    -- ... thousands more
}

local columns = {"name", "email"}
local count, error = schema_manager.batch_insert(db, "users", columns, users)
print("Inserted " .. count .. " rows")
```

## Data Validation

```lua
local db_tools = require("db_tools")

local valid, errors = db_tools.validate_data(schema, "users", rows)
if not valid then
    for _, err in ipairs(errors) do
        print("Error: " .. err)
    end
end
```

## Data Analysis

```lua
local db_tools = require("db_tools")

local analysis, error = db_tools.analyze_table(db, "users")
db_tools.print_analysis(analysis)
```

## Check Table Exists

```lua
if db:table_exists("users") then
    print("Table exists")
end
```

## Get Table List

```lua
local tables, error = db:get_tables()
for _, table_row in ipairs(tables or {}) do
    print("Table: " .. table_row.name)
end
```

## Close Database

```lua
function shutdown()
    if db then
        db:close()
    end
end
```

## Complete Example

```lua
local schema_manager = require("schema_manager")
local db_tools = require("db_tools")

function startup()
    -- Open database
    local db, error = db.open("data/app.db")
    if error ~= "" then return end

    -- Define schema
    local schema = {
        tables = {
            {
                name = "users",
                columns = {
                    {name = "id", type = "id"},
                    {name = "name", type = "text", not_null = true}
                }
            }
        }
    }

    -- Create schema
    schema_manager.create_schema(db, schema)

    -- Insert data in transaction
    schema_manager.transaction(db, function(db)
        db:query("INSERT INTO users (name) VALUES (?)", "Alice")
        db:query("INSERT INTO users (name) VALUES (?)", "Bob")
        return true
    end)

    -- Query data
    local results, error = db:query("SELECT * FROM users")
    for _, row in ipairs(results or {}) do
        print(row.name)
    end

    -- Close
    db:close()
end
```

## Common Patterns

### Insert and Get ID

```lua
db:query("INSERT INTO users (name) VALUES (?)", "Alice")
local id = db:last_insert_rowid()
```

### Count Rows

```lua
local result, error = db:query_single("SELECT COUNT(*) as count FROM users")
print("Total users: " .. result.count)
```

### Check if Record Exists

```lua
local result, error = db:query_single("SELECT 1 FROM users WHERE email = ?", email)
if result then
    print("Email already exists")
end
```

### Upsert Pattern

```lua
-- Insert or update if exists (SQLite 3.24+)
db:query([[
    INSERT INTO users (id, name, email) VALUES (?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET name = ?, email = ?
]], id, name, email, name, email)
```

## Performance Tips

1. **Use transactions** for multiple operations
2. **Use batch_insert** for bulk data (10-100x faster)
3. **Close databases** in shutdown function
4. **Create indexes** for frequently queried columns
5. **Use query_single** instead of query for single rows

## See Also

- Full guide: `docs/database-guide.md`
- Example: `scripts/db_example.lua`
- Demo app: `scripts/sqlite_demo.lua`
