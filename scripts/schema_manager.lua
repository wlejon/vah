-- Schema Manager
-- Comprehensive database schema management for SQLite
-- Provides schema creation, validation, introspection, and migration

local schema_manager = {}

-- Type mapping from common type names to SQLite types
local TYPE_MAP = {
    -- Standard SQL types
    integer = "INTEGER",
    int = "INTEGER",
    smallint = "INTEGER",
    bigint = "INTEGER",

    real = "REAL",
    float = "REAL",
    double = "REAL",

    text = "TEXT",
    string = "TEXT",
    varchar = "TEXT",
    char = "TEXT",

    blob = "BLOB",
    binary = "BLOB",

    boolean = "INTEGER",
    bool = "INTEGER",

    date = "TEXT",
    datetime = "TEXT",
    timestamp = "TEXT",
    time = "TEXT",

    -- Auto-increment
    id = "INTEGER PRIMARY KEY AUTOINCREMENT"
}

-- Normalize a type string to SQLite type
local function normalize_type(type_str)
    if not type_str then
        return "TEXT"  -- Default type
    end

    local lower_type = string.lower(type_str)
    return TYPE_MAP[lower_type] or string.upper(type_str)
end

-- Build column definition SQL
local function build_column_definition(column)
    local parts = {}

    -- Column name and type
    local col_type = normalize_type(column.type)
    table.insert(parts, column.name .. " " .. col_type)

    -- Skip other constraints if this is a PRIMARY KEY AUTOINCREMENT
    if col_type:match("PRIMARY KEY AUTOINCREMENT") then
        return table.concat(parts, " ")
    end

    -- NOT NULL constraint
    if column.not_null or column.required then
        table.insert(parts, "NOT NULL")
    end

    -- UNIQUE constraint
    if column.unique then
        table.insert(parts, "UNIQUE")
    end

    -- DEFAULT value
    if column.default ~= nil then
        if type(column.default) == "string" then
            -- Quote string defaults
            table.insert(parts, "DEFAULT '" .. column.default:gsub("'", "''") .. "'")
        elseif type(column.default) == "boolean" then
            table.insert(parts, "DEFAULT " .. (column.default and "1" or "0"))
        else
            table.insert(parts, "DEFAULT " .. tostring(column.default))
        end
    end

    -- CHECK constraint
    if column.check then
        table.insert(parts, "CHECK (" .. column.check .. ")")
    end

    return table.concat(parts, " ")
end

-- Build CREATE TABLE SQL from table definition
local function build_create_table_sql(table_def)
    local parts = {}
    table.insert(parts, "CREATE TABLE IF NOT EXISTS " .. table_def.name .. " (")

    -- Build column definitions
    local column_defs = {}
    for _, column in ipairs(table_def.columns) do
        table.insert(column_defs, "  " .. build_column_definition(column))
    end

    -- Add table-level constraints
    if table_def.primary_key and type(table_def.primary_key) == "table" then
        -- Composite primary key
        local pk_cols = table.concat(table_def.primary_key, ", ")
        table.insert(column_defs, "  PRIMARY KEY (" .. pk_cols .. ")")
    end

    -- Foreign keys
    if table_def.foreign_keys then
        for _, fk in ipairs(table_def.foreign_keys) do
            local fk_def = string.format("  FOREIGN KEY (%s) REFERENCES %s(%s)",
                fk.column,
                fk.references_table,
                fk.references_column)

            if fk.on_delete then
                fk_def = fk_def .. " ON DELETE " .. fk.on_delete
            end

            if fk.on_update then
                fk_def = fk_def .. " ON UPDATE " .. fk.on_update
            end

            table.insert(column_defs, fk_def)
        end
    end

    -- Unique constraints
    if table_def.unique_constraints then
        for _, unique_cols in ipairs(table_def.unique_constraints) do
            local cols = type(unique_cols) == "table" and table.concat(unique_cols, ", ") or unique_cols
            table.insert(column_defs, "  UNIQUE (" .. cols .. ")")
        end
    end

    table.insert(parts, table.concat(column_defs, ",\n"))
    table.insert(parts, ")")

    -- Table options
    if table_def.without_rowid then
        table.insert(parts, " WITHOUT ROWID")
    end

    return table.concat(parts, "\n")
end

-- Create schema from schema definition
-- Schema format: {tables = {table_def1, table_def2, ...}}
-- Table format: {name, columns = {col_def1, col_def2, ...}, indexes, foreign_keys, ...}
-- Column format: {name, type, not_null, unique, default, check, ...}
function schema_manager.create_schema(db, schema)
    if not db or not db:is_open() then
        return false, "Database not open"
    end

    if not schema or not schema.tables then
        return false, "Invalid schema: missing tables"
    end

    -- Begin transaction for atomic schema creation
    local success, error = db:begin_transaction()
    if not success then
        return false, "Failed to begin transaction: " .. error
    end

    -- Create tables
    for _, table_def in ipairs(schema.tables) do
        if not table_def.name then
            db:rollback()
            return false, "Table definition missing name"
        end

        -- Build and execute CREATE TABLE
        local create_sql = build_create_table_sql(table_def)

        local exec_success, exec_error = db:execute(create_sql)
        if not exec_success then
            db:rollback()
            return false, "Failed to create table '" .. table_def.name .. "': " .. exec_error
        end

        -- Create indexes
        if table_def.indexes then
            for _, index_def in ipairs(table_def.indexes) do
                local index_name = index_def.name or (table_def.name .. "_" .. table.concat(index_def.columns, "_") .. "_idx")
                local unique_clause = index_def.unique and "UNIQUE " or ""
                local cols = table.concat(index_def.columns, ", ")

                local index_sql = string.format("CREATE %sINDEX IF NOT EXISTS %s ON %s (%s)",
                    unique_clause, index_name, table_def.name, cols)

                local idx_success, idx_error = db:execute(index_sql)
                if not idx_success then
                    db:rollback()
                    return false, "Failed to create index '" .. index_name .. "': " .. idx_error
                end
            end
        end
    end

    -- Commit transaction
    success, error = db:commit()
    if not success then
        db:rollback()
        return false, "Failed to commit schema: " .. error
    end

    return true, ""
end

-- Get current database schema
function schema_manager.get_schema(db)
    if not db or not db:is_open() then
        return nil, "Database not open"
    end

    local schema = {tables = {}}

    -- Get table list
    local tables, error = db:get_tables()
    if error ~= "" then
        return nil, "Failed to get tables: " .. error
    end

    if not tables then
        return schema, ""
    end

    -- Get info for each table
    for _, table_row in ipairs(tables) do
        local table_name = table_row.name

        -- Skip system tables
        if not table_name:match("^sqlite_") then
            local table_info, info_error = db:get_table_info(table_name)

            if info_error == "" and table_info then
                local table_def = {
                    name = table_name,
                    columns = {}
                }

                for _, col_info in ipairs(table_info) do
                    table.insert(table_def.columns, {
                        name = col_info.name,
                        type = col_info.type,
                        not_null = col_info.notnull == 1,
                        default = col_info.dflt_value,
                        primary_key = col_info.pk == 1
                    })
                end

                table.insert(schema.tables, table_def)
            end
        end
    end

    return schema, ""
end

-- Validate that a schema matches the database
function schema_manager.validate_schema(db, schema)
    if not db or not db:is_open() then
        return false, "Database not open"
    end

    if not schema or not schema.tables then
        return false, "Invalid schema: missing tables"
    end

    local errors = {}

    for _, table_def in ipairs(schema.tables) do
        -- Check if table exists
        if not db:table_exists(table_def.name) then
            table.insert(errors, "Table '" .. table_def.name .. "' does not exist")
        else
            -- Validate columns
            local table_info, error = db:get_table_info(table_def.name)

            if error ~= "" then
                table.insert(errors, "Failed to get info for table '" .. table_def.name .. "': " .. error)
            elseif table_info then
                -- Build column map
                local existing_cols = {}
                for _, col_info in ipairs(table_info) do
                    existing_cols[col_info.name] = col_info
                end

                -- Check that all required columns exist
                for _, column in ipairs(table_def.columns) do
                    if not existing_cols[column.name] then
                        table.insert(errors, "Table '" .. table_def.name .. "' missing column '" .. column.name .. "'")
                    end
                end
            end
        end
    end

    if #errors > 0 then
        return false, table.concat(errors, "; ")
    end

    return true, ""
end

-- Safe transaction wrapper
-- Executes a function within a transaction, auto-rollback on error
function schema_manager.transaction(db, fn)
    if not db or not db:is_open() then
        return false, "Database not open"
    end

    local success, error = db:begin_transaction()
    if not success then
        return false, "Failed to begin transaction: " .. error
    end

    -- Execute function
    local fn_success, fn_result = pcall(fn, db)

    if not fn_success then
        -- Function threw error - rollback
        db:rollback()
        return false, "Transaction failed: " .. tostring(fn_result)
    end

    -- Check if function returned error
    if fn_result == false then
        db:rollback()
        return false, "Transaction rolled back"
    end

    -- Commit
    success, error = db:commit()
    if not success then
        db:rollback()
        return false, "Failed to commit: " .. error
    end

    return true, fn_result
end

-- Batch insert with automatic transaction
function schema_manager.batch_insert(db, table_name, columns, rows, batch_size)
    if not db or not db:is_open() then
        return 0, "Database not open"
    end

    batch_size = batch_size or 1000
    local total_inserted = 0

    -- Process in batches
    local i = 1
    while i <= #rows do
        -- Get batch
        local batch_end = math.min(i + batch_size - 1, #rows)
        local batch = {}
        for j = i, batch_end do
            table.insert(batch, rows[j])
        end

        -- Insert batch in transaction
        local success, error = schema_manager.transaction(db, function(db)
            local count, err = db:batch_insert(table_name, columns, batch)
            if err ~= "" then
                return false
            end
            return true
        end)

        if not success then
            return total_inserted, "Batch insert failed at row " .. i .. ": " .. (error or "unknown error")
        end

        total_inserted = total_inserted + #batch
        i = batch_end + 1
    end

    return total_inserted, ""
end

-- Generate schema from sample data
-- Infers types and structure from Lua tables
function schema_manager.infer_schema(table_name, sample_rows, options)
    options = options or {}

    if not sample_rows or #sample_rows == 0 then
        return nil, "No sample data provided"
    end

    -- Collect all keys and infer types
    local columns = {}
    local column_map = {}

    for _, row in ipairs(sample_rows) do
        for key, value in pairs(row) do
            if not column_map[key] then
                -- New column - infer type from first occurrence
                local col_type = "TEXT"

                if type(value) == "number" then
                    -- Check if it's an integer
                    if math.floor(value) == value then
                        col_type = "INTEGER"
                    else
                        col_type = "REAL"
                    end
                elseif type(value) == "boolean" then
                    col_type = "INTEGER"
                end

                local column_def = {
                    name = key,
                    type = col_type
                }

                table.insert(columns, column_def)
                column_map[key] = column_def
            end
        end
    end

    -- Add ID column if requested
    if options.add_id then
        table.insert(columns, 1, {
            name = options.id_column or "id",
            type = "INTEGER PRIMARY KEY AUTOINCREMENT"
        })
    end

    local table_def = {
        name = table_name,
        columns = columns
    }

    return {tables = {table_def}}, ""
end

-- Pretty print schema (for debugging)
function schema_manager.print_schema(schema)
    if not schema or not schema.tables then
        print("Empty schema")
        return
    end

    print("Schema:")
    for _, table_def in ipairs(schema.tables) do
        print("  Table: " .. table_def.name)
        for _, col in ipairs(table_def.columns) do
            local col_str = "    " .. col.name .. " " .. (col.type or "TEXT")
            if col.not_null then col_str = col_str .. " NOT NULL" end
            if col.unique then col_str = col_str .. " UNIQUE" end
            if col.default then col_str = col_str .. " DEFAULT " .. tostring(col.default) end
            print(col_str)
        end
    end
end

return schema_manager
