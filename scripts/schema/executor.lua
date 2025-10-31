-- Schema Executor
-- Executes database schemas, validates them, and provides rich views of results

local SchemaExecutor = {}

-- Type mapping from generic types to SQLite types
local TYPE_MAP = {
    string = "TEXT",
    text = "TEXT",
    integer = "INTEGER",
    int = "INTEGER",
    number = "REAL",
    real = "REAL",
    float = "REAL",
    double = "REAL",
    boolean = "INTEGER",
    bool = "INTEGER",
    date = "TEXT",
    datetime = "TEXT",
    timestamp = "TEXT",
    blob = "BLOB"
}

-- Normalize a type to SQLite type
local function normalize_type(type_str)
    local lower = string.lower(type_str or "text")
    return TYPE_MAP[lower] or "TEXT"
end

-- Validate schema structure
local function validate_schema(schema)
    local warnings = {}
    local suggestions = {}

    if not schema.tables or #schema.tables == 0 then
        return false, {"Schema has no tables"}, {}
    end

    -- Track all table names for foreign key validation
    local table_names = {}
    for _, table in ipairs(schema.tables) do
        table_names[table.name] = true
    end

    for _, table in ipairs(schema.tables) do
        -- Validate table name
        if not table.name or table.name == "" then
            table.insert(warnings, "Table with empty name")
        end

        -- Check for columns
        if not table.columns or #table.columns == 0 then
            table.insert(warnings, string.format("Table '%s' has no columns", table.name))
        end

        -- Check for primary key
        local has_primary = false
        local primary_count = 0

        for _, col in ipairs(table.columns or {}) do
            if col.primary then
                has_primary = true
                primary_count = primary_count + 1
            end

            -- Validate foreign keys
            if col.foreign_key then
                local ref_table, ref_col = col.foreign_key:match("^([^.]+)%.(.+)$")
                if not ref_table or not ref_col then
                    table.insert(warnings, string.format(
                        "Invalid foreign key format in %s.%s: '%s' (expected 'table.column')",
                        table.name, col.name, col.foreign_key
                    ))
                elseif not table_names[ref_table] then
                    table.insert(warnings, string.format(
                        "Foreign key %s.%s references non-existent table '%s'",
                        table.name, col.name, ref_table
                    ))
                end
            end
        end

        if not has_primary then
            table.insert(suggestions, string.format(
                "Consider adding a primary key to table '%s' (e.g., an 'id' column)",
                table.name
            ))
        end

        if primary_count > 1 then
            table.insert(warnings, string.format(
                "Table '%s' has %d primary keys (composite key) - ensure this is intentional",
                table.name, primary_count
            ))
        end
    end

    return true, warnings, suggestions
end

-- Generate CREATE TABLE statement
local function generate_create_table_sql(table_def)
    local parts = {}
    table.insert(parts, "CREATE TABLE IF NOT EXISTS " .. table_def.name .. " (")

    local column_defs = {}
    local primary_keys = {}

    for _, col in ipairs(table_def.columns) do
        local def = col.name .. " " .. normalize_type(col.type)

        if col.primary then
            table.insert(primary_keys, col.name)
        end

        if col.nullable == false then
            def = def .. " NOT NULL"
        end

        if col.default ~= nil then
            if type(col.default) == "string" then
                def = def .. " DEFAULT '" .. col.default .. "'"
            else
                def = def .. " DEFAULT " .. tostring(col.default)
            end
        end

        table.insert(column_defs, def)
    end

    table.insert(parts, "    " .. table.concat(column_defs, ",\n    "))

    -- Add primary key constraint if needed
    if #primary_keys > 0 then
        table.insert(parts, ",\n    PRIMARY KEY (" .. table.concat(primary_keys, ", ") .. ")")
    end

    -- Add foreign key constraints
    for _, col in ipairs(table_def.columns) do
        if col.foreign_key then
            local ref_table, ref_col = col.foreign_key:match("^([^.]+)%.(.+)$")
            if ref_table and ref_col then
                table.insert(parts, string.format(",\n    FOREIGN KEY (%s) REFERENCES %s(%s)",
                    col.name, ref_table, ref_col))
            end
        end
    end

    table.insert(parts, "\n)")

    return table.concat(parts, "")
end

-- Generate CREATE INDEX statement
local function generate_create_index_sql(index_def)
    local unique_str = index_def.unique and "UNIQUE " or ""
    local index_name = string.format("idx_%s_%s", index_def.table, table.concat(index_def.columns, "_"))

    return string.format("CREATE %sINDEX IF NOT EXISTS %s ON %s (%s)",
        unique_str, index_name, index_def.table, table.concat(index_def.columns, ", "))
end

-- Execute schema on database
function SchemaExecutor.execute_schema(schema, db_path)
    -- Validate schema first
    local is_valid, warnings, suggestions = validate_schema(schema)
    if not is_valid then
        return {
            execution_status = "failed",
            validation = {
                is_valid = false,
                warnings = warnings,
                suggestions = suggestions
            },
            ready_for_import = false,
            next_steps = {"Fix schema validation errors and try again"}
        }
    end

    -- Create directory if needed
    local db_dir = fs.dirname(db_path)
    if db_dir and db_dir ~= "" then
        fs.create_dir(db_dir)
    end

    -- Open database
    local db = sqlite.open(db_path)
    if not db then
        return {
            execution_status = "failed",
            error = "Failed to open database at: " .. db_path,
            ready_for_import = false,
            next_steps = {"Check file path and permissions"}
        }
    end

    -- Enable foreign keys
    db:execute("PRAGMA foreign_keys = ON")

    local created_objects = {}
    local failed_count = 0

    -- Create tables
    for _, table_def in ipairs(schema.tables) do
        local sql = generate_create_table_sql(table_def)
        local success, error = db:execute(sql)

        local status = "created"
        local error_msg = nil

        if not success then
            status = "failed"
            error_msg = error
            failed_count = failed_count + 1
        end

        table.insert(created_objects, {
            type = "table",
            name = table_def.name,
            sql = sql,
            status = status,
            error = error_msg
        })
    end

    -- Create indexes
    if schema.indexes then
        for _, index_def in ipairs(schema.indexes) do
            local sql = generate_create_index_sql(index_def)
            local success, error = db:execute(sql)

            local status = "created"
            local error_msg = nil

            if not success then
                status = "failed"
                error_msg = error
                failed_count = failed_count + 1
            end

            table.insert(created_objects, {
                type = "index",
                name = string.format("idx_%s_%s", index_def.table, table.concat(index_def.columns, "_")),
                sql = sql,
                status = status,
                error = error_msg
            })
        end
    end

    -- Get database info
    local db_stat, _ = fs.stat(db_path)
    local db_size = db_stat and db_stat.size or 0

    -- Count created objects
    local created_tables = 0
    local created_indexes = 0
    for _, obj in ipairs(created_objects) do
        if obj.status == "created" then
            if obj.type == "table" then
                created_tables = created_tables + 1
            elseif obj.type == "index" then
                created_indexes = created_indexes + 1
            end
        end
    end

    -- Verify schema by querying sqlite_master
    local verification_query = "SELECT name, type FROM sqlite_master WHERE type IN ('table', 'index')"
    local actual_objects, _ = db:query(verification_query)

    local verified = true
    local mismatches = {}

    -- Check that all expected tables exist
    for _, table_def in ipairs(schema.tables) do
        local found = false
        for _, obj in ipairs(actual_objects or {}) do
            if obj.name == table_def.name and obj.type == "table" then
                found = true
                break
            end
        end
        if not found then
            verified = false
            table.insert(mismatches, string.format("Table '%s' not found in database", table_def.name))
        end
    end

    db:close()

    -- Determine execution status
    local execution_status = "success"
    if failed_count > 0 then
        if failed_count == #created_objects then
            execution_status = "failed"
        else
            execution_status = "partial"
        end
    end

    -- Prepare next steps
    local next_steps = {}
    if execution_status == "success" then
        table.insert(next_steps, "Schema successfully created")
        table.insert(next_steps, "Ready to generate and execute parser scripts")
        table.insert(next_steps, "Use introspect_database to verify schema")
    elseif execution_status == "partial" then
        table.insert(next_steps, "Some objects failed to create - review errors")
        table.insert(next_steps, "Fix issues and retry failed objects")
    else
        table.insert(next_steps, "Schema creation failed - review errors")
        table.insert(next_steps, "Check SQL syntax and database permissions")
    end

    return {
        execution_status = execution_status,
        database_info = {
            path = db_path,
            size_bytes = db_size,
            created_tables = created_tables,
            created_indexes = created_indexes
        },
        created_objects = created_objects,
        schema_verification = {
            verified = verified,
            mismatches = mismatches
        },
        validation = {
            is_valid = is_valid,
            warnings = warnings,
            suggestions = suggestions
        },
        ready_for_import = execution_status == "success",
        next_steps = next_steps
    }
end

-- Summarize a proposed schema (without executing)
function SchemaExecutor.summarize_schema(schema)
    local is_valid, warnings, suggestions = validate_schema(schema)

    local table_summaries = {}
    local total_columns = 0

    for _, table_def in ipairs(schema.tables or {}) do
        local foreign_keys = {}
        local has_primary = false

        for _, col in ipairs(table_def.columns or {}) do
            total_columns = total_columns + 1
            if col.primary then
                has_primary = true
            end
            if col.foreign_key then
                table.insert(foreign_keys, {
                    from = col.name,
                    to = col.foreign_key
                })
            end
        end

        table.insert(table_summaries, {
            name = table_def.name,
            column_count = #(table_def.columns or {}),
            has_primary_key = has_primary,
            foreign_keys = foreign_keys
        })
    end

    -- Determine complexity
    local complexity = "simple"
    if #(schema.tables or {}) > 5 or total_columns > 30 then
        complexity = "moderate"
    end
    if #(schema.tables or {}) > 10 or total_columns > 60 then
        complexity = "complex"
    end

    return {
        status = "proposed",
        schema_summary = {
            table_count = #(schema.tables or {}),
            total_columns = total_columns,
            tables = table_summaries
        },
        validation = {
            is_valid = is_valid,
            warnings = warnings,
            suggestions = suggestions
        },
        estimated_complexity = complexity
    }
end

return SchemaExecutor
